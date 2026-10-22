#!/usr/bin/env -S RBENV_VERSION=3.3.12 ruby
# frozen_string_literal: true

required_ruby_engine = "ruby"
required_ruby_version = "3.3.12"
unless required_ruby_engine == RUBY_ENGINE && required_ruby_version == RUBY_VERSION
  warn "#{File.basename($PROGRAM_NAME)}: CRuby #{required_ruby_version} is required; detected #{RUBY_DESCRIPTION}"
  warn "#{File.basename($PROGRAM_NAME)}: resolved interpreter: #{RbConfig.ruby}"
  warn "#{File.basename($PROGRAM_NAME)}: select the required Ruby (rbenv is the supported user setup) and retry"
  exit 1
end

require "date"
require "digest"
require "fileutils"
require "json"
require "optparse"
require "securerandom"
require "tmpdir"
require "yaml"

module RetroState
  SCHEMA_VERSION = 1
  STATE_ENV = "CODEX_WORKFLOWS_STATE_DIR"
  VERDICTS = %w[accept defer reject split merge no-change].freeze
  DISPOSITIONS = %w[accepted implemented no-change superseded reverted].freeze
  VERIFICATIONS = %w[unverified supported contradicted].freeze
  VERIFICATION_BASES = %w[none later-session deterministic-test].freeze
  COMMIT_HASH_PATTERN = /\A[0-9a-f]{7,40}\z/
  VERIFICATION_PROPOSAL_STATES = %w[supported contradicted].freeze
  VERIFICATION_PROPOSAL_VERDICTS = %w[apply reject].freeze
  VERIFICATION_CLAIMS = %w[
    executable-correctness guidance-conformance intended-outcome comparative-improvement
  ].freeze
  TERMINAL_CONTRADICTION_DISPOSITIONS = %w[superseded reverted].freeze
  AUDIT_KINDS = %w[learning-process skill-repository].freeze
  ARTIFACT_AUDIT_ARCHIVE_THRESHOLD = 10
  ARTIFACT_CADENCE_RECORD_TYPE = "artifact-audit-cadence"
  COUNTED_CANDIDATE_IDS_FIELD = "counted_candidate_ids"
  CONFIDENCES = %w[high medium low].freeze
  EVIDENCE_LINEAGES = %w[independent descendant mixed unknown not-applicable].freeze
  RECOMMENDATIONS = %w[
    update-existing no-change new-skill new-script new-prompt uncertain
  ].freeze
  PAPERCUT_KINDS = %w[
    command tool-call documentation-or-link environment repository-convention
    validation-order tooling-version other
  ].freeze
  PAPERCUT_IMPACTS = %w[retry dead-end blocked noise ambiguity].freeze
  PAPERCUT_RESOLUTIONS = %w[worked-around resolved unresolved].freeze
  PAPERCUT_OWNERS = %w[
    unknown repo-local skill-system environment external-tool external-docs
  ].freeze
  PAPERCUT_CLASSIFICATIONS = {
    "kind" => PAPERCUT_KINDS,
    "impact" => PAPERCUT_IMPACTS,
    "resolution" => PAPERCUT_RESOLUTIONS,
    "owner_hint" => PAPERCUT_OWNERS
  }.freeze
  PAPERCUT_OUTCOMES = %w[
    no-action local-fix candidate external-owner duplicate
  ].freeze
  DRAFT_STATUSES = %w[open revised activated deprecated].freeze
  LEDGER_STATUSES = %w[open closed].freeze
  REVIEW_TRIGGER_CONTRACT_VERSION = 1
  REVIEW_TRIGGER_TYPES = %w[
    date state-threshold external-artifact explicit-input destination-use
  ].freeze
  REVIEW_TRIGGER_OBSERVERS = %w[
    learning-process-review skill-retro-triage
  ].freeze
  REVIEW_TRIGGER_ROUTE = "review-queue"
  REVIEW_TRIGGER_COMMON_FIELDS = %w[
    review_trigger_type review_trigger_observer review_trigger_route
    review_trigger_probe review_trigger next_action close_condition
  ].freeze
  REVIEW_TRIGGER_TYPE_FIELDS = {
    "date" => %w[review_trigger_at],
    "state-threshold" => %w[review_trigger_counter review_trigger_threshold],
    "external-artifact" => %w[review_trigger_locator],
    "explicit-input" => %w[review_trigger_input],
    "destination-use" => %w[review_trigger_destination]
  }.freeze
  STATE_DIRS = %w[
    retrospectives/inbox
    retrospectives/archive
    retrospectives/accepted
    papercuts/inbox
    papercuts/archive
    drafts
    ledgers
    audits/learning-process
  ].freeze
  VERIFICATION_DIRS = %w[
    verifications/inbox
    verifications/archive
  ].freeze
  FORBIDDEN_PATTERNS = [
    [%r{(?:^|/)\.codex/(?:sessions|history|logs|attachments)(?:/|\b)}, "raw Codex runtime history path"],
    [%r{(?:^|/)auth\.json\b}, "Codex auth file"],
    [%r{(?:^|/)sessions/[^[:space:]]+\.jsonl\b}, "raw session transcript path"],
    [%r{/(?:home|Users)/[^/[:space:]]+/}, "unredacted user-home path"],
    [%r{[A-Za-z]:\\Users\\[^\\[:space:]]+\\}, "unredacted Windows user-home path"],
    [/BEGIN (?:OPENSSH|RSA|DSA|EC|PGP) PRIVATE KEY/, "private key material"],
    [/(?:ghp|github_pat)_[A-Za-z0-9_]{20,}/, "GitHub token-shaped value"],
    [/\bsk-[A-Za-z0-9_-]{20,}\b/, "API key-shaped value"]
  ].freeze

  class Error < StandardError; end
  class MissingStateRoot < Error; end

  module_function

  def read_document(path)
    text = (path == "-") ? $stdin.read : File.read(path, encoding: "UTF-8")
    parse_document(text, label: (path == "-") ? "standard input" : path)
  end

  def parse_document(text, label: "document")
    parts = text.split(/^---\s*$/, 3)
    raise Error, "#{label}: missing YAML frontmatter" unless parts.length == 3

    data = YAML.safe_load(parts.fetch(1), permitted_classes: [Date], aliases: false)
    raise Error, "#{label}: YAML frontmatter must be a mapping" unless data.is_a?(Hash)

    [stringify_keys(data), parts.fetch(2).sub(/\A\r?\n/, "")]
  rescue Psych::Exception => e
    raise Error, "#{label}: invalid YAML frontmatter: #{e.message}"
  end

  def stringify_keys(value)
    case value
    when Hash
      value.to_h { |key, item| [key.to_s, stringify_keys(item)] }
    when Array
      value.map { |item| stringify_keys(item) }
    else
      value
    end
  end

  def render_document(data, body)
    yaml = YAML.dump(data).sub(/\A---\s*\n/, "")
    "---\n#{yaml}---\n\n#{body.rstrip}\n"
  end

  def blank?(value)
    value.nil? || (value.respond_to?(:empty?) && value.empty?)
  end

  def without_keys(data, *keys)
    data.dup.tap do |copy|
      keys.each { |key| copy.delete(key) }
    end
  end

  def require_fields(data, fields, label)
    fields.each do |field|
      value = data[field]
      unless value.is_a?(String) && !value.empty?
        raise Error, "#{label}: #{field} must be a non-empty string"
      end
    end
  end

  def require_string_array(data, field, label, allow_empty: false)
    value = data[field]
    valid = value.is_a?(Array) && (allow_empty || !value.empty?) &&
      value.all? { |item| item.is_a?(String) && !item.empty? }
    return if valid

    qualifier = allow_empty ? "an array of strings" : "a non-empty array of strings"
    raise Error, "#{label}: #{field} must be #{qualifier}"
  end

  def validate_common(data, text, label)
    unless data["schema_version"] == SCHEMA_VERSION
      raise Error, "#{label}: schema_version must be #{SCHEMA_VERSION}"
    end

    FORBIDDEN_PATTERNS.each do |pattern, description|
      raise Error, "#{label}: contains forbidden #{description}" if text.match?(pattern)
    end
  end

  def validate_candidate(data, body, label:, routed:, archived: false)
    text = render_document(data, body)
    validate_common(data, text, label)
    unless data["record_type"] == "candidate"
      raise Error, "#{label}: record_type must be candidate"
    end

    require_fields(
      data,
      %w[
        title source_scope observation reusable_lesson existing_coverage
        missing_delta proposed_destination smallest_change test_status
        confidence recommendation redaction_review
      ],
      label
    )
    require_string_array(data, "decisive_evidence", label)

    lineage_present = data.key?("evidence_lineage") || data.key?("evidence_lineage_note")
    if !routed || lineage_present
      require_fields(data, %w[evidence_lineage evidence_lineage_note], label)
      unless EVIDENCE_LINEAGES.include?(data["evidence_lineage"])
        raise Error,
          "#{label}: evidence_lineage must be one of #{EVIDENCE_LINEAGES.join(", ")}"
      end
    end

    unless CONFIDENCES.include?(data["confidence"])
      raise Error, "#{label}: confidence must be one of #{CONFIDENCES.join(", ")}"
    end
    unless RECOMMENDATIONS.include?(data["recommendation"])
      raise Error, "#{label}: recommendation must be one of #{RECOMMENDATIONS.join(", ")}"
    end

    supersedes_id = data["supersedes_accepted_id"]
    now_false = data["now_false"]
    if supersedes_id || now_false
      require_fields(data, %w[supersedes_accepted_id now_false], label)
      unless supersedes_id.match?(/\ASCR-\d{8}-[a-f0-9]{6}\z/)
        raise Error, "#{label}: invalid supersedes_accepted_id"
      end
    end

    if routed
      require_fields(data, %w[candidate_id created_at intake_digest], label)
      unless data["candidate_id"].match?(/\ARC-\d{8}T\d{6}Z-[a-f0-9]{6}\z/)
        raise Error, "#{label}: invalid candidate_id"
      end
      unless data["created_at"].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
        raise Error, "#{label}: created_at must be a UTC timestamp"
      end
      unless data["intake_digest"].match?(/\A[a-f0-9]{64}\z/)
        raise Error, "#{label}: intake_digest must be a SHA-256 digest"
      end
      intake = without_keys(data, "intake_digest", "triage", "triage_history")
      expected_digest = Digest::SHA256.hexdigest(render_document(intake, body))
      unless data["intake_digest"] == expected_digest
        raise Error, "#{label}: intake fields changed after routing"
      end
    elsif data.key?("candidate_id") || data.key?("created_at") || data.key?("intake_digest")
      raise Error, "#{label}: unrouted input must not assign identity fields"
    end

    triage = data["triage"]
    triage_history = data.fetch("triage_history", [])
    if archived
      validate_triage(triage, data["candidate_id"], label)
      unless triage_history.is_a?(Array)
        raise Error, "#{label}: triage_history must be an array"
      end
      triage_history.each_with_index do |prior_triage, index|
        history_label = "#{label} triage_history[#{index}]"
        validate_triage(prior_triage, data["candidate_id"], history_label)
        unless prior_triage["verdict"] == "defer"
          raise Error, "#{history_label}: prior verdict must be defer"
        end
      end
      reviewed_at = triage_history.map { |item| item.fetch("reviewed_at") }
      reviewed_at << triage.fetch("reviewed_at")
      unless reviewed_at.each_cons(2).all? { |earlier, later| earlier < later }
        raise Error, "#{label}: triage decisions must have increasing reviewed_at timestamps"
      end
    elsif triage || data.key?("triage_history")
      raise Error, "#{label}: inbox candidate must not contain triage data"
    end
  end

  def validate_verification_proposal(data, body, label:, routed:, archived: false)
    text = render_document(data, body)
    validate_common(data, text, label)
    unless data["record_type"] == "verification-proposal"
      raise Error, "#{label}: record_type must be verification-proposal"
    end

    require_fields(
      data,
      %w[
        title source_scope target_accepted_id proposed_verification
        verification_basis opportunity_match claim observation redaction_review
      ],
      label
    )
    require_string_array(data, "decisive_evidence", label)
    unless data["target_accepted_id"].match?(/\ASCR-\d{8}-[a-f0-9]{6}\z/)
      raise Error, "#{label}: invalid target_accepted_id"
    end
    validate_enum(data, "proposed_verification", VERIFICATION_PROPOSAL_STATES, label)
    unless %w[later-session deterministic-test].include?(data["verification_basis"])
      raise Error, "#{label}: verification_basis must be later-session or deterministic-test"
    end
    validate_enum(data, "claim", VERIFICATION_CLAIMS, label)
    if data["proposed_verification"] == "contradicted"
      require_fields(data, %w[what_is_false], label)
    elsif data.key?("what_is_false")
      raise Error, "#{label}: supported proposals must not contain what_is_false"
    end
    if data.key?("supplemental_reason")
      require_fields(data, %w[supplemental_reason], label)
      unless data["proposed_verification"] == "supported"
        raise Error, "#{label}: supplemental_reason is only for supported proposals"
      end
    end

    if routed
      require_fields(data, %w[verification_proposal_id created_at intake_digest], label)
      unless data["verification_proposal_id"].match?(/\AVP-\d{8}T\d{6}Z-[a-f0-9]{6}\z/)
        raise Error, "#{label}: invalid verification_proposal_id"
      end
      unless data["created_at"].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
        raise Error, "#{label}: created_at must be a UTC timestamp"
      end
      unless data["intake_digest"].match?(/\A[a-f0-9]{64}\z/)
        raise Error, "#{label}: intake_digest must be a SHA-256 digest"
      end
      intake = without_keys(data, "intake_digest", "triage")
      expected_digest = Digest::SHA256.hexdigest(render_document(intake, body))
      unless data["intake_digest"] == expected_digest
        raise Error, "#{label}: verification proposal intake fields changed after routing"
      end
    elsif %w[verification_proposal_id created_at intake_digest].any? { |field| data.key?(field) }
      raise Error, "#{label}: unrouted verification proposal must not assign identity fields"
    end

    triage = data["triage"]
    if archived
      validate_verification_triage(triage, data["verification_proposal_id"], label)
    elsif triage
      raise Error, "#{label}: inbox verification proposal must not contain triage data"
    end
  end

  def validate_verification_triage(triage, proposal_id, label)
    raise Error, "#{label}: missing triage mapping" unless triage.is_a?(Hash)

    require_fields(
      triage,
      %w[verification_proposal_id verdict rationale reviewed_at],
      "#{label} triage"
    )
    unless triage["verification_proposal_id"] == proposal_id
      raise Error, "#{label}: triage verification_proposal_id does not match intake"
    end
    validate_enum(triage, "verdict", VERIFICATION_PROPOSAL_VERDICTS, "#{label} triage")
    unless triage["reviewed_at"].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
      raise Error, "#{label}: triage reviewed_at must be a UTC timestamp"
    end
  end

  def validate_verification_decision(data, body, label:, expected_id: nil)
    text = render_document(data, body)
    validate_common(data, text, label)
    unless data["record_type"] == "verification-decision"
      raise Error, "#{label}: record_type must be verification-decision"
    end

    require_fields(
      data,
      %w[verification_proposal_id verdict rationale reviewed_at],
      label
    )
    proposal_id = data["verification_proposal_id"]
    unless proposal_id.match?(/\AVP-\d{8}T\d{6}Z-[a-f0-9]{6}\z/)
      raise Error, "#{label}: invalid verification_proposal_id"
    end
    if expected_id && proposal_id != expected_id
      raise Error, "#{label}: verification_proposal_id does not match #{expected_id}"
    end
    validate_enum(data, "verdict", VERIFICATION_PROPOSAL_VERDICTS, label)
    unless data["reviewed_at"].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
      raise Error, "#{label}: reviewed_at must be a UTC timestamp"
    end
  end

  def validate_papercut(data, body, label:, routed:, archived: false)
    validate_papercut_integrity(data, body, label: label, routed: routed, archived: archived)
    PAPERCUT_CLASSIFICATIONS.each do |field, allowed|
      validate_enum(data, field, allowed, label)
    end
  end

  def validate_papercut_integrity(
    data,
    body,
    label:,
    routed:,
    archived: false,
    recover_classification_digest: false,
    allow_unverified_digest: false
  )
    text = render_document(data, body)
    validate_common(data, text, label)
    unless data["record_type"] == "papercut"
      raise Error, "#{label}: record_type must be papercut"
    end

    require_fields(
      data,
      %w[
        source_scope kind observation impact resolution owner_hint
        redaction_review
      ],
      label
    )
    if data.key?("workaround") && (!data["workaround"].is_a?(String) || data["workaround"].empty?)
      raise Error, "#{label}: workaround must be a non-empty string when present"
    end

    if routed
      require_fields(data, %w[papercut_id created_at intake_digest], label)
      unless data["papercut_id"].match?(/\APC-\d{8}T\d{6}Z-[a-f0-9]{6}\z/)
        raise Error, "#{label}: invalid papercut_id"
      end
      unless data["created_at"].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
        raise Error, "#{label}: created_at must be a UTC timestamp"
      end
      unless data["intake_digest"].match?(/\A[a-f0-9]{64}\z/)
        raise Error, "#{label}: intake_digest must be a SHA-256 digest"
      end
      intake = without_keys(data, "intake_digest", "closure")
      expected_digest = Digest::SHA256.hexdigest(render_document(intake, body))
      authenticated_classifications = nil
      unless data["intake_digest"] == expected_digest
        unless recover_classification_digest
          raise Error, "#{label}: papercut intake fields changed after recording"
        end
        authenticated_classifications = recover_papercut_classifications(data, body, label)
        if !authenticated_classifications && !allow_unverified_digest
          raise Error, "#{label}: intake digest mismatch is not recoverable as classification-only change"
        end
      end
      if authenticated_classifications || data["intake_digest"] == expected_digest
        history_data = authenticated_classifications ? data.merge(authenticated_classifications) : data
        validate_papercut_schema_repairs(history_data, body, label)
      elsif data.key?("schema_repairs")
        raise Error, "#{label}: existing schema repair history cannot be authenticated"
      end
    elsif data.key?("papercut_id") || data.key?("created_at") || data.key?("intake_digest")
      raise Error, "#{label}: unrecorded papercut must not assign identity fields"
    elsif data.key?("schema_repairs")
      raise Error, "#{label}: unrecorded papercut must not contain schema repair history"
    end

    closure = data["closure"]
    if archived
      validate_papercut_closure(closure, data["papercut_id"], label)
    elsif closure
      raise Error, "#{label}: open papercut must not contain closure data"
    end
    authenticated_classifications
  end

  def recover_papercut_classifications(data, body, label)
    expected_digest = data.fetch("intake_digest")
    intake = without_keys(data, "intake_digest", "closure")
    fields = PAPERCUT_CLASSIFICATIONS.keys
    matches = PAPERCUT_CLASSIFICATIONS.values.reduce([[]]) do |combinations, values|
      combinations.product(values).map { |prefix, value| prefix + [value] }
    end.filter_map do |values|
      candidate = intake.merge(fields.zip(values).to_h)
      fields.zip(values).to_h if Digest::SHA256.hexdigest(render_document(candidate, body)) == expected_digest
    end
    if matches.length > 1
      raise Error, "#{label}: intake digest matches multiple historical classification tuples"
    end

    matches.first
  end

  def validate_papercut_repair(data, body, label:, expected_id: nil)
    text = render_document(data, body)
    validate_common(data, text, label)
    unless data["record_type"] == "papercut-repair"
      raise Error, "#{label}: record_type must be papercut-repair"
    end

    fields = %w[
      schema_version record_type papercut_id kind impact resolution owner_hint
      observed_intake_digest accept_current_evidence rationale redaction_review
    ]
    unexpected = data.keys - fields
    unless unexpected.empty?
      raise Error, "#{label}: unexpected papercut repair field: #{unexpected.first}"
    end
    require_fields(
      data,
      %w[
        papercut_id kind impact resolution owner_hint observed_intake_digest
        rationale redaction_review
      ],
      label
    )
    papercut_id = data["papercut_id"]
    unless papercut_id.match?(/\APC-\d{8}T\d{6}Z-[a-f0-9]{6}\z/)
      raise Error, "#{label}: invalid papercut_id"
    end
    if expected_id && papercut_id != expected_id
      raise Error, "#{label}: papercut_id does not match #{expected_id}"
    end
    PAPERCUT_CLASSIFICATIONS.each do |field, allowed|
      validate_enum(data, field, allowed, label)
    end
    unless data["observed_intake_digest"].match?(/\A[a-f0-9]{64}\z/)
      raise Error, "#{label}: observed_intake_digest must be a SHA-256 digest"
    end
    unless [true, false].include?(data["accept_current_evidence"])
      raise Error, "#{label}: accept_current_evidence must be true or false"
    end
    raise Error, "#{label}: papercut repair body must be empty" unless body.strip.empty?
  end

  def validate_papercut_schema_repairs(data, body, label)
    repairs = data["schema_repairs"]
    return unless repairs
    unless repairs.is_a?(Array) && !repairs.empty? && repairs.all? { |repair| repair.is_a?(Hash) }
      raise Error, "#{label}: schema_repairs must be a non-empty array of mappings"
    end

    working = without_keys(data, "intake_digest", "closure")
    repairs.length.downto(1) do |length|
      repair = repairs.fetch(length - 1)
      repair_label = "#{label} schema repair #{length}"
      allowed_fields = %w[
        repaired_at rationale redaction_review prior_intake_digest
        replaced_intake_digest digest_recovery authenticated_classifications changes
      ]
      unexpected = repair.keys - allowed_fields
      unless unexpected.empty?
        raise Error, "#{repair_label}: unexpected field: #{unexpected.first}"
      end
      require_fields(
        repair,
        %w[
          repaired_at rationale redaction_review prior_intake_digest
          replaced_intake_digest digest_recovery
        ],
        repair_label
      )
      unless repair["repaired_at"].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
        raise Error, "#{repair_label}: repaired_at must be a UTC timestamp"
      end
      unless repair["prior_intake_digest"].match?(/\A[a-f0-9]{64}\z/)
        raise Error, "#{repair_label}: prior_intake_digest must be a SHA-256 digest"
      end
      unless repair["replaced_intake_digest"].match?(/\A[a-f0-9]{64}\z/)
        raise Error, "#{repair_label}: replaced_intake_digest must be a SHA-256 digest"
      end
      digest_recovery = repair["digest_recovery"]
      unless %w[matched classification-only current-evidence-authorized].include?(digest_recovery)
        raise Error, "#{repair_label}: invalid digest_recovery"
      end

      authenticated = repair["authenticated_classifications"]
      if authenticated
        unless authenticated.is_a?(Hash) && authenticated.keys.sort == PAPERCUT_CLASSIFICATIONS.keys.sort
          raise Error, "#{repair_label}: authenticated_classifications must contain the complete tuple"
        end
        authenticated.each do |field, value|
          unless PAPERCUT_CLASSIFICATIONS.fetch(field).include?(value)
            raise Error, "#{repair_label}: authenticated #{field} is not valid"
          end
        end
      end

      changes = repair["changes"]
      unless changes.is_a?(Hash) && !changes.empty?
        raise Error, "#{repair_label}: changes must be a non-empty mapping"
      end
      unexpected_changes = changes.keys - PAPERCUT_CLASSIFICATIONS.keys
      unless unexpected_changes.empty?
        raise Error, "#{repair_label}: unsupported repaired field: #{unexpected_changes.first}"
      end
      changes.each do |field, change|
        unless change.is_a?(Hash) && change.keys.sort == %w[from to]
          raise Error, "#{repair_label}: #{field} change must contain only from and to"
        end
        require_fields(change, %w[from to], "#{repair_label} #{field}")
        if change["from"] == change["to"]
          raise Error, "#{repair_label}: #{field} change must alter the value"
        end
        if PAPERCUT_CLASSIFICATIONS.fetch(field).include?(change["from"])
          unless authenticated && change["to"] == authenticated[field]
            raise Error, "#{repair_label}: #{field} repair changed an already-valid value"
          end
        end
        unless PAPERCUT_CLASSIFICATIONS.fetch(field).include?(change["to"])
          raise Error, "#{repair_label}: #{field} repair target is not valid"
        end
        unless working[field] == change["to"]
          raise Error, "#{repair_label}: #{field} repair does not match current state"
        end
      end

      prior_repairs = repairs.first(length - 1)
      if prior_repairs.empty?
        working.delete("schema_repairs")
      else
        working["schema_repairs"] = prior_repairs
      end
      changes.each { |field, change| working[field] = change.fetch("from") }
      replaced_digest = Digest::SHA256.hexdigest(render_document(working, body))
      unless repair["replaced_intake_digest"] == replaced_digest
        raise Error, "#{repair_label}: replaced_intake_digest does not match repair history"
      end
      prior_state = authenticated ? working.merge(authenticated) : working
      prior_digest = Digest::SHA256.hexdigest(render_document(prior_state, body))
      case digest_recovery
      when "matched"
        if authenticated || repair["prior_intake_digest"] != prior_digest || prior_digest != replaced_digest
          raise Error, "#{repair_label}: matched digest recovery is inconsistent"
        end
      when "classification-only"
        raise Error, "#{repair_label}: classification-only digest recovery is inconsistent" unless authenticated
        unless repair["prior_intake_digest"] == prior_digest
          raise Error, "#{repair_label}: prior_intake_digest does not match repair history"
        end
      when "current-evidence-authorized"
        if authenticated || repair["prior_intake_digest"] == replaced_digest
          raise Error, "#{repair_label}: current-evidence digest recovery is inconsistent"
        end
      end
      unless digest_recovery == "current-evidence-authorized" || repair["prior_intake_digest"] == prior_digest
        raise Error, "#{repair_label}: prior_intake_digest does not match repair history"
      end
      working = prior_state
    end
  end

  def validate_papercut_closure(closure, papercut_id, label)
    raise Error, "#{label}: missing closure mapping" unless closure.is_a?(Hash)

    require_fields(closure, %w[outcome rationale closed_at], "#{label} closure")
    validate_enum(closure, "outcome", PAPERCUT_OUTCOMES, "#{label} closure")
    unless closure["closed_at"].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
      raise Error, "#{label}: closure closed_at must be a UTC timestamp"
    end

    related_papercut_id = closure["related_papercut_id"]
    related_candidate_id = closure["related_candidate_id"]
    case closure["outcome"]
    when "duplicate"
      require_fields(closure, %w[related_papercut_id], "#{label} duplicate closure")
      unless related_papercut_id.match?(/\APC-\d{8}T\d{6}Z-[a-f0-9]{6}\z/)
        raise Error, "#{label}: invalid related_papercut_id"
      end
      if related_papercut_id == papercut_id
        raise Error, "#{label}: duplicate papercut cannot reference itself"
      end
      if related_candidate_id
        raise Error, "#{label}: duplicate closure must not contain related_candidate_id"
      end
    when "candidate"
      require_fields(closure, %w[related_candidate_id], "#{label} candidate closure")
      unless related_candidate_id.match?(/\ARC-\d{8}T\d{6}Z-[a-f0-9]{6}\z/)
        raise Error, "#{label}: invalid related_candidate_id"
      end
      if related_papercut_id
        raise Error, "#{label}: candidate closure must not contain related_papercut_id"
      end
    else
      if related_papercut_id || related_candidate_id
        raise Error, "#{label}: #{closure["outcome"]} closure must not contain a related ID"
      end
    end
  end

  def validate_enum(data, field, allowed, label)
    return if allowed.include?(data[field])

    raise Error, "#{label}: #{field} must be one of #{allowed.join(", ")}"
  end

  def review_trigger_contract_fields
    [
      "review_trigger_contract_version",
      "unresolved_decision",
      *REVIEW_TRIGGER_COMMON_FIELDS,
      *REVIEW_TRIGGER_TYPE_FIELDS.values.flatten
    ].uniq
  end

  def validate_review_trigger_contract(data, label, legacy_allowed:)
    unless data.key?("review_trigger_contract_version")
      if legacy_allowed
        require_fields(data, %w[review_trigger next_action close_condition], label)
        return
      end

      raise Error,
        "#{label}: review_trigger_contract_version must be #{REVIEW_TRIGGER_CONTRACT_VERSION}"
    end

    unless data["review_trigger_contract_version"] == REVIEW_TRIGGER_CONTRACT_VERSION
      raise Error,
        "#{label}: review_trigger_contract_version must be #{REVIEW_TRIGGER_CONTRACT_VERSION}"
    end

    require_fields(data, REVIEW_TRIGGER_COMMON_FIELDS, label)
    validate_enum(data, "review_trigger_type", REVIEW_TRIGGER_TYPES, label)
    validate_enum(data, "review_trigger_observer", REVIEW_TRIGGER_OBSERVERS, label)
    unless data["review_trigger_route"] == REVIEW_TRIGGER_ROUTE
      raise Error, "#{label}: review_trigger_route must be #{REVIEW_TRIGGER_ROUTE}"
    end

    trigger_type = data.fetch("review_trigger_type")
    if trigger_type == "destination-use"
      raise Error, "#{label}: destination-use triggers require a supported destination matcher"
    end

    expected_type_fields = REVIEW_TRIGGER_TYPE_FIELDS.fetch(trigger_type)
    string_type_fields = expected_type_fields - %w[review_trigger_threshold]
    require_fields(data, string_type_fields, label)

    unexpected_type_fields = (
      REVIEW_TRIGGER_TYPE_FIELDS.values.flatten - expected_type_fields
    ).select { |field| data.key?(field) }
    unless unexpected_type_fields.empty?
      raise Error,
        "#{label}: #{unexpected_type_fields.first} is not valid for #{trigger_type} triggers"
    end

    case trigger_type
    when "date"
      validate_review_trigger_date(data.fetch("review_trigger_at"), label)
    when "state-threshold"
      threshold = data["review_trigger_threshold"]
      unless threshold.is_a?(Integer) && threshold.positive?
        raise Error, "#{label}: review_trigger_threshold must be a positive integer"
      end
    end
  end

  def validate_review_trigger_date(value, label)
    unless value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      raise Error, "#{label}: review_trigger_at must be an ISO date"
    end

    parsed = Date.iso8601(value)
    return if parsed.iso8601 == value

    raise Error, "#{label}: review_trigger_at must be an ISO date"
  rescue ArgumentError
    raise Error, "#{label}: review_trigger_at must be an ISO date"
  end

  def validate_triage(triage, candidate_id, label)
    raise Error, "#{label}: missing triage mapping" unless triage.is_a?(Hash)

    require_fields(triage, %w[candidate_id verdict rationale reviewed_at], "#{label} triage")
    unless triage["candidate_id"] == candidate_id
      raise Error, "#{label}: triage candidate_id does not match intake"
    end
    unless VERDICTS.include?(triage["verdict"])
      raise Error, "#{label}: verdict must be one of #{VERDICTS.join(", ")}"
    end

    related = triage.fetch("related_candidate_ids", [])
    unless related.is_a?(Array) && related.all? { |item| item.is_a?(String) && !item.empty? }
      raise Error, "#{label}: related_candidate_ids must be an array of strings"
    end

    return unless triage["verdict"] == "defer"

    require_fields(triage, %w[unresolved_decision], "#{label} deferred triage") if
      triage.key?("review_trigger_contract_version")
    validate_review_trigger_contract(triage, "#{label} deferred triage", legacy_allowed: true)
  end

  def validate_decision(data, body, label:, expected_id: nil)
    text = render_document(data, body)
    validate_common(data, text, label)
    raise Error, "#{label}: record_type must be decision" unless data["record_type"] == "decision"

    require_fields(data, %w[candidate_id verdict rationale reviewed_at], label)
    unless data["reviewed_at"].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
      raise Error, "#{label}: reviewed_at must be a UTC timestamp"
    end
    if expected_id && data["candidate_id"] != expected_id
      raise Error, "#{label}: candidate_id does not match #{expected_id}"
    end
    unless VERDICTS.include?(data["verdict"])
      raise Error, "#{label}: verdict must be one of #{VERDICTS.join(", ")}"
    end
    require_string_array(data, "related_candidate_ids", label, allow_empty: true)
    if data["verdict"] == "defer"
      require_fields(data, %w[unresolved_decision], label)
      validate_review_trigger_contract(data, label, legacy_allowed: false)
    else
      trigger_fields = review_trigger_contract_fields.select { |field| data.key?(field) }
      unless trigger_fields.empty?
        raise Error, "#{label}: #{trigger_fields.first} is only valid for defer"
      end
    end
  end

  def validate_accepted(data, body, label:, assigned:, strict_contradiction: false)
    text = render_document(data, body)
    validate_common(data, text, label)
    raise Error, "#{label}: record_type must be accepted" unless data["record_type"] == "accepted"

    require_fields(
      data,
      %w[
        source_report_summary expected_behavior observed_behavior trigger
        non_trigger destination verification_opportunity redaction_review
        disposition verification verification_basis
      ],
      label
    )
    require_string_array(data, "originating_candidate_ids", label)
    require_string_array(data, "decisive_evidence", label)
    require_string_array(data, "implementation_commits", label, allow_empty: true)
    if data.key?("unverified_claims")
      require_string_array(data, "unverified_claims", label, allow_empty: true)
      claims = data.fetch("unverified_claims")
      if claims.any? { |claim| claim.strip.empty? } || claims.uniq.length != claims.length
        raise Error, "#{label}: unverified_claims must contain distinct, nonblank strings"
      end
    end
    if data.key?("applied_verification_proposal_ids")
      require_string_array(data, "applied_verification_proposal_ids", label)
      proposal_ids = data["applied_verification_proposal_ids"]
      unless proposal_ids.uniq.length == proposal_ids.length
        raise Error, "#{label}: applied_verification_proposal_ids must not contain duplicates"
      end
      proposal_ids.each do |proposal_id|
        unless proposal_id.match?(/\AVP-\d{8}T\d{6}Z-[a-f0-9]{6}\z/)
          raise Error, "#{label}: invalid applied_verification_proposal_ids entry"
        end
      end
    end
    if data.key?("supersedes_accepted_ids")
      require_string_array(data, "supersedes_accepted_ids", label)
      data["supersedes_accepted_ids"].each do |accepted_id|
        unless accepted_id.match?(/\ASCR-\d{8}-[a-f0-9]{6}\z/)
          raise Error, "#{label}: invalid supersedes_accepted_ids entry"
        end
      end
    end

    if assigned
      require_fields(data, %w[accepted_id accepted_at], label)
      unless data["accepted_id"].match?(/\ASCR-\d{8}-[a-f0-9]{6}\z/)
        raise Error, "#{label}: invalid accepted_id"
      end
      unless data["accepted_at"].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
        raise Error, "#{label}: accepted_at must be a UTC timestamp"
      end
    elsif data.key?("accepted_id") || data.key?("accepted_at")
      raise Error, "#{label}: unrecorded accepted input must not assign identity fields"
    end

    unless DISPOSITIONS.include?(data["disposition"])
      raise Error, "#{label}: invalid disposition"
    end
    unless VERIFICATIONS.include?(data["verification"])
      raise Error, "#{label}: invalid verification"
    end
    unless VERIFICATION_BASES.include?(data["verification_basis"])
      raise Error, "#{label}: invalid verification_basis"
    end
    if data["verification"] == "unverified" && data["verification_basis"] != "none"
      raise Error, "#{label}: unverified records must use verification_basis: none"
    end
    if %w[supported contradicted].include?(data["verification"]) && data["verification_basis"] == "none"
      raise Error, "#{label}: supported or contradicted records need an evidence basis"
    end
    contradiction = data["contradiction"]
    if contradiction
      unless data["verification"] == "contradicted"
        raise Error, "#{label}: contradiction details require verification: contradicted"
      end
      validate_contradiction(contradiction, label)
    elsif data["verification"] == "contradicted" && strict_contradiction
      raise Error, "#{label}: newly contradicted records need contradiction details"
    end
    unless data["implementation_commits"].all? { |item| item.match?(COMMIT_HASH_PATTERN) }
      raise Error, "#{label}: implementation_commits must contain Git commit hashes"
    end
  end

  def validate_contradiction(contradiction, label)
    unless contradiction.is_a?(Hash)
      raise Error, "#{label}: contradiction must be a mapping"
    end

    require_fields(
      contradiction,
      %w[summary what_is_false recorded_at],
      "#{label} contradiction"
    )
    require_string_array(contradiction, "decisive_evidence", "#{label} contradiction")
    unless contradiction["recorded_at"].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
      raise Error, "#{label}: contradiction recorded_at must be a UTC timestamp"
    end
    if contradiction.key?("resolution")
      resolution = contradiction["resolution"]
      unless resolution.is_a?(Hash)
        raise Error, "#{label}: contradiction resolution must be a mapping"
      end
      require_fields(resolution, %w[outcome rationale resolved_at], "#{label} contradiction resolution")
      unless resolution["outcome"] == "retained"
        raise Error, "#{label}: contradiction resolution outcome must be retained"
      end
      unless resolution["resolved_at"].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
        raise Error, "#{label}: contradiction resolution resolved_at must be a UTC timestamp"
      end
      if resolution["resolved_at"] < contradiction["recorded_at"]
        raise Error, "#{label}: contradiction resolution must not predate the contradiction"
      end
    end
    residual_id = contradiction["residual_ledger_id"]
    return unless residual_id
    return if residual_id.match?(/\ALE-\d{8}-[a-f0-9]{6}\z/)

    raise Error, "#{label}: invalid contradiction residual_ledger_id"
  end

  def contradiction_resolved?(accepted)
    TERMINAL_CONTRADICTION_DISPOSITIONS.include?(accepted["disposition"]) ||
      accepted.dig("contradiction", "resolution", "outcome") == "retained"
  end

  def validate_accepted_transition(current, replacement, label)
    unless replacement["originating_candidate_ids"] == current["originating_candidate_ids"]
      raise Error, "accepted record originating_candidate_ids must not change: #{label}"
    end
    unless replacement.fetch("supersedes_accepted_ids", []) == current.fetch("supersedes_accepted_ids", [])
      raise Error, "accepted record supersedes_accepted_ids must not change: #{label}"
    end
    missing_proposal_ids = current.fetch("applied_verification_proposal_ids", []) -
      replacement.fetch("applied_verification_proposal_ids", [])
    unless missing_proposal_ids.empty?
      raise Error, "accepted record applied_verification_proposal_ids must be preserved: #{label}"
    end
    return unless current["verification"] == "contradicted"

    unless replacement["verification"] == "contradicted"
      raise Error, "contradicted verification must be preserved: #{label}"
    end
    current_contradiction = current["contradiction"]
    return unless current_contradiction

    replacement_contradiction = replacement.fetch("contradiction")
    %w[summary what_is_false recorded_at].each do |field|
      next if replacement_contradiction[field] == current_contradiction[field]

      raise Error, "contradiction #{field} must be preserved: #{label}"
    end
    missing_evidence = current_contradiction.fetch("decisive_evidence") -
      replacement_contradiction.fetch("decisive_evidence")
    return if missing_evidence.empty?

    raise Error, "contradiction decisive_evidence must be preserved: #{label}"
  end

  def validate_draft(data, body, label:, assigned:)
    text = render_document(data, body)
    validate_common(data, text, label)
    raise Error, "#{label}: record_type must be draft" unless data["record_type"] == "draft"

    require_fields(data, %w[title purpose trigger_boundary status redaction_review], label)
    %w[evidence seeded_conventions missing_evidence activation_criteria].each do |field|
      require_string_array(data, field, label)
    end
    unless DRAFT_STATUSES.include?(data["status"])
      raise Error, "#{label}: status must be one of #{DRAFT_STATUSES.join(", ")}"
    end
    if %w[open revised].include?(data["status"])
      validate_review_trigger_contract(data, label, legacy_allowed: assigned)
    elsif data.key?("review_trigger_contract_version")
      validate_review_trigger_contract(data, label, legacy_allowed: false)
    end

    validate_assigned_id(data, label, assigned, "draft_id", /\ASD-\d{8}-[a-f0-9]{6}\z/)
  end

  def validate_ledger_entry(data, body, label:, assigned:)
    text = render_document(data, body)
    validate_common(data, text, label)
    unless data["record_type"] == "ledger-entry"
      raise Error, "#{label}: record_type must be ledger-entry"
    end

    require_fields(data, %w[title owner status last_reviewed redaction_review], label)
    require_string_array(data, "evidence", label)
    unless LEDGER_STATUSES.include?(data["status"])
      raise Error, "#{label}: status must be one of #{LEDGER_STATUSES.join(", ")}"
    end
    if data["status"] == "open"
      validate_review_trigger_contract(data, label, legacy_allowed: assigned)
    elsif data.key?("review_trigger_contract_version")
      validate_review_trigger_contract(data, label, legacy_allowed: false)
    end

    closure = data["closure"]
    if data["status"] == "open" && closure
      raise Error, "#{label}: open ledger must not contain closure data"
    elsif closure
      validate_ledger_closure(closure, label)
    end

    validate_assigned_id(data, label, assigned, "ledger_id", /\ALE-\d{8}-[a-f0-9]{6}\z/)
  end

  def validate_ledger_closure(closure, label)
    raise Error, "#{label}: ledger closure must be a mapping" unless closure.is_a?(Hash)

    require_fields(closure, %w[rationale closed_at], "#{label} closure")
    unless closure["closed_at"].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
      raise Error, "#{label}: closure closed_at must be a UTC timestamp"
    end
  end

  def validate_learning_audit(data, body, label:, assigned:)
    text = render_document(data, body)
    validate_common(data, text, label)
    unless data["record_type"] == "learning-audit"
      raise Error, "#{label}: record_type must be learning-audit"
    end

    require_fields(data, %w[audit_kind summary redaction_review], label)
    require_string_array(data, "findings", label)
    require_string_array(data, "unresolved_action_ids", label, allow_empty: true)
    raise Error, "#{label}: audit diagnosis body must not be empty" if body.strip.empty?
    validate_enum(data, "audit_kind", AUDIT_KINDS, label)
    data["unresolved_action_ids"].each do |action_id|
      next if action_id.match?(/\A(?:RC-\d{8}T\d{6}Z|SD-\d{8}|LE-\d{8})-[a-f0-9]{6}\z/)

      raise Error, "#{label}: invalid unresolved_action_ids entry"
    end

    if assigned
      require_fields(data, %w[audit_id completed_at], label)
      unless data["candidate_archive_count"].is_a?(Integer) && data["candidate_archive_count"] >= 0
        raise Error, "#{label}: candidate_archive_count must be a non-negative integer"
      end
      if data.key?("candidate_archives_total") &&
          (!data["candidate_archives_total"].is_a?(Integer) || data["candidate_archives_total"].negative?)
        raise Error, "#{label}: candidate_archives_total must be a non-negative integer"
      end
      unless data["audit_id"].match?(/\ALA-\d{8}-[a-f0-9]{6}\z/)
        raise Error, "#{label}: invalid audit_id"
      end
      unless data["completed_at"].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
        raise Error, "#{label}: completed_at must be a UTC timestamp"
      end
    elsif %w[audit_id completed_at candidate_archive_count candidate_archives_total].any? { |field| data.key?(field) }
      raise Error, "#{label}: unrecorded audit input must not assign identity fields"
    end
  end

  def validate_artifact_cadence(data, label:)
    unless data.is_a?(Hash) && data["schema_version"] == SCHEMA_VERSION &&
        data["record_type"] == ARTIFACT_CADENCE_RECORD_TYPE
      raise Error, "#{label}: invalid artifact-audit cadence record"
    end

    total = data["candidate_archives_total"]
    baseline = data["last_completed_artifact_audit_total"]
    unless total.is_a?(Integer) && total >= 0
      raise Error, "#{label}: candidate_archives_total must be a non-negative integer"
    end
    unless baseline.is_a?(Integer) && baseline >= 0 && baseline <= total
      raise Error, "#{label}: invalid last_completed_artifact_audit_total"
    end

    counted_ids = data.fetch(COUNTED_CANDIDATE_IDS_FIELD, [])
    valid_ids = counted_ids.is_a?(Array) && counted_ids.all? do |candidate_id|
      candidate_id.is_a?(String) && candidate_id.match?(/\ARC-\d{8}T\d{6}Z-[a-f0-9]{6}\z/)
    end
    unless valid_ids && counted_ids.uniq.length == counted_ids.length
      raise Error, "#{label}: #{COUNTED_CANDIDATE_IDS_FIELD} must contain unique candidate IDs"
    end
    if counted_ids.length > total
      raise Error, "#{label}: #{COUNTED_CANDIDATE_IDS_FIELD} cannot exceed candidate_archives_total"
    end
  end

  def validate_assigned_id(data, label, assigned, field, pattern)
    timestamp_field = "created_at"
    if assigned
      require_fields(data, [field, timestamp_field], label)
      raise Error, "#{label}: invalid #{field}" unless data[field].match?(pattern)
      unless data[timestamp_field].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
        raise Error, "#{label}: #{timestamp_field} must be a UTC timestamp"
      end
    elsif data.key?(field) || data.key?(timestamp_field)
      raise Error, "#{label}: unrecorded input must not assign identity fields"
    end
  end

  def candidate_template
    <<~MARKDOWN
      ---
      schema_version: 1
      record_type: candidate
      title: "Short candidate title"
      source_scope: "Sanitized repository or task category; omit private names."
      evidence_lineage: unknown # #{EVIDENCE_LINEAGES.join(", ")}
      evidence_lineage_note: "Whether affected destination guidance was active and how it may have shaped what was attempted, noticed, or reported."
      observation: "What happened and why it matters."
      decisive_evidence:
        - "Bounded, sanitized failure signal or observed behavior."
      reusable_lesson: "What a fresh agent should reuse."
      existing_coverage: "Existing skill/reference coverage, or none."
      missing_delta: "The exact gap not already covered."
      proposed_destination: "Smallest natural skill, reference, script, prompt, or no change."
      smallest_change: "Minimum useful change; explain what a helper can enforce, what judgment remains, and why prose is needed when chosen. Both may apply."
      test_status: "What was exercised, or explicitly untested."
      confidence: medium
      recommendation: uncertain # #{RECOMMENDATIONS.join(", ")}
      redaction_review: "Confirmed no raw transcript, secret, private source, or unredacted local path is included."
      # For a decision-changing correction, also add:
      # supersedes_accepted_id: SCR-YYYYMMDD-abcdef
      # now_false: "What the earlier accepted outcome asserted that is now false."
      ---

      # Short candidate title

      Optional concise context. Keep this document self-contained and sanitized.
    MARKDOWN
  end

  def verification_proposal_template
    <<~MARKDOWN
      ---
      schema_version: 1
      record_type: verification-proposal
      title: "Short verification proposal title"
      source_scope: "Sanitized repository or task category; omit private names."
      target_accepted_id: SCR-YYYYMMDD-abcdef
      proposed_verification: supported # #{VERIFICATION_PROPOSAL_STATES.join(", ")}
      verification_basis: later-session # later-session, deterministic-test
      opportunity_match: "How this evidence exercises the target's exact recorded verification opportunity."
      claim: guidance-conformance # #{VERIFICATION_CLAIMS.join(", ")}
      observation: "What the later session or deterministic check established."
      decisive_evidence:
        - "Bounded, sanitized evidence supporting the proposed state."
      redaction_review: "Confirmed no raw transcript, secret, private source, or unredacted local path is included."
      # A contradicted proposal must also add:
      # what_is_false: "What the accepted outcome asserted that is now false."
      # Further support when support is pending or the target is supported must add:
      # supplemental_reason: "What this evidence materially adds to adjudication beyond existing support."
      ---

      # Short verification proposal title

      Keep this proposal self-contained and limited to the named verification opportunity.
    MARKDOWN
  end

  def verification_decision_template
    <<~MARKDOWN
      ---
      schema_version: 1
      record_type: verification-decision
      verification_proposal_id: VP-YYYYMMDDTHHMMSSZ-abcdef
      verdict: reject # #{VERIFICATION_PROPOSAL_VERDICTS.join(", ")}
      rationale: "Why the evidence does or does not support the target's exact opportunity."
      reviewed_at: "YYYY-MM-DDTHH:MM:SSZ"
      # Optional adjudication notes may follow the closing frontmatter; omit when unused.
      ---
    MARKDOWN
  end

  def papercut_template
    <<~MARKDOWN
      ---
      schema_version: 1
      record_type: papercut
      source_scope: "Sanitized repository or task category; omit private names."
      kind: command # #{PAPERCUT_KINDS.join(", ")}
      observation: "Unexpected, avoidable friction and why it interrupted the task."
      impact: retry # #{PAPERCUT_IMPACTS.join(", ")}
      resolution: worked-around # #{PAPERCUT_RESOLUTIONS.join(", ")}
      workaround: "Optional concise workaround; remove this field when unresolved."
      owner_hint: unknown # #{PAPERCUT_OWNERS.join(", ")}
      redaction_review: "Confirmed no raw transcript, secret, private source, or unredacted local path is included."
      ---

      # Papercut observation

      Optional bounded evidence or context. Do not synthesize a skill candidate here.
    MARKDOWN
  end

  def papercut_repair_template
    <<~MARKDOWN
      ---
      schema_version: 1
      record_type: papercut-repair
      papercut_id: PC-YYYYMMDDTHHMMSSZ-abcdef
      observed_intake_digest: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      accept_current_evidence: false
      kind: other # #{PAPERCUT_KINDS.join(", ")}
      impact: blocked # #{PAPERCUT_IMPACTS.join(", ")}
      resolution: resolved # #{PAPERCUT_RESOLUTIONS.join(", ")}
      owner_hint: unknown # #{PAPERCUT_OWNERS.join(", ")}
      rationale: "Why each unsupported classification maps to the selected valid value."
      redaction_review: "Confirmed no raw transcript, secret, private source, or unredacted local path is included."
      ---
    MARKDOWN
  end

  def decision_template
    <<~MARKDOWN
      ---
      schema_version: 1
      record_type: decision
      candidate_id: RC-YYYYMMDDTHHMMSSZ-abcdef
      verdict: defer
      rationale: "Why this verdict is the smallest justified outcome."
      reviewed_at: "YYYY-MM-DDTHH:MM:SSZ"
      related_candidate_ids: []
      review_trigger_contract_version: 1
      unresolved_decision: "" # Decision that current evidence cannot justify.
      review_trigger_type: explicit-input # #{REVIEW_TRIGGER_TYPES.join(", ")}
      review_trigger_observer: skill-retro-triage # #{REVIEW_TRIGGER_OBSERVERS.join(", ")}
      review_trigger_route: review-queue
      review_trigger_probe: "" # Exact check the observer performs.
      review_trigger_input: "" # Specific input that must be supplied.
      review_trigger: "" # Durable predicate that fires the action.
      next_action: "" # Executable action after the predicate is observed.
      close_condition: "" # Condition that resolves the action.
      # Complete the blanks for defer; remove all deferral contract fields for other verdicts.
      # Optional implementation-batch notes may follow the closing frontmatter; omit when unused.
      ---
    MARKDOWN
  end

  def accepted_template
    <<~MARKDOWN
      ---
      schema_version: 1
      record_type: accepted
      originating_candidate_ids:
        - RC-YYYYMMDDTHHMMSSZ-abcdef
      source_report_summary: "Sanitized summary of the accepted evidence."
      expected_behavior: "What the resulting workflow should do."
      observed_behavior: "What made the candidate useful."
      decisive_evidence:
        - "Sanitized decisive evidence."
      trigger: "When the guidance applies."
      non_trigger: "When it does not apply."
      destination: "Public source destination or no change."
      verification_opportunity: "Deterministic check or ordinary later-session observation."
      redaction_review: "Confirmed no raw transcript, secret, private source, or unredacted local path is included."
      disposition: accepted
      verification: unverified
      verification_basis: none
      implementation_commits: []
      # Optional unverified_claims lists remaining claim scopes. Omit when unassessed;
      # use [] only when assessed and no declared claims remain unverified.
      # Correction outcomes may add supersedes_accepted_ids. Contradicted
      # records must add a contradiction mapping; see state-protocol.md.
      ---

      # Accepted candidate

      Keep curated evidence concise. Update implementation commits only after
      the public source commit exists.
    MARKDOWN
  end

  def draft_template
    <<~MARKDOWN
      ---
      schema_version: 1
      record_type: draft
      title: "Provisional skill kernel"
      purpose: "Reusable capability this draft may eventually provide."
      trigger_boundary: "When it should and should not activate."
      evidence:
        - "Sanitized evidence already present."
      seeded_conventions:
        - "Convention supported by current evidence."
      missing_evidence:
        - "Behavioral evidence or boundary question still missing."
      activation_criteria:
        - "Concrete condition required before installing a complete skill."
      review_trigger_contract_version: 1
      review_trigger_type: explicit-input # #{REVIEW_TRIGGER_TYPES.join(", ")}
      review_trigger_observer: learning-process-review # #{REVIEW_TRIGGER_OBSERVERS.join(", ")}
      review_trigger_route: review-queue
      review_trigger_probe: "Confirm the named evidence is present in the current review input."
      review_trigger_input: "Specific missing evidence that must be supplied."
      review_trigger: "The named evidence is supplied to a learning-process review."
      next_action: "Executable next review action."
      close_condition: "Condition for activation or deprecation."
      status: open
      redaction_review: "Confirmed no raw transcript, secret, private source, or unredacted local path is included."
      ---

      # Provisional skill kernel

      Keep only the coherent reusable kernel. Do not copy a full speculative skill.
    MARKDOWN
  end

  def ledger_template
    <<~MARKDOWN
      ---
      schema_version: 1
      record_type: ledger-entry
      title: "Threshold-based maintenance observation"
      owner: "skill-retro-triage"
      status: open
      last_reviewed: "never"
      review_trigger_contract_version: 1
      review_trigger_type: state-threshold # #{REVIEW_TRIGGER_TYPES.join(", ")}
      review_trigger_observer: learning-process-review # #{REVIEW_TRIGGER_OBSERVERS.join(", ")}
      review_trigger_route: review-queue
      review_trigger_probe: "Run the named helper query and read its durable counter."
      review_trigger_counter: "Named helper-owned counter or state query."
      review_trigger_threshold: 3
      review_trigger: "The named durable counter reaches the threshold."
      evidence:
        - "Sanitized observation supporting continued monitoring."
      next_action: "Executable action when the review trigger fires."
      close_condition: "Condition that closes or promotes this entry."
      redaction_review: "Confirmed no raw transcript, secret, private source, or unredacted local path is included."
      ---

      # Threshold-based maintenance observation

      Keep this short and delete it when it no longer improves future judgment.
    MARKDOWN
  end

  def learning_audit_template
    <<~MARKDOWN
      ---
      schema_version: 1
      record_type: learning-audit
      audit_kind: learning-process # #{AUDIT_KINDS.join(", ")}
      summary: "Complete sanitized diagnosis in one sentence."
      findings:
        - "Sanitized finding and its disposition."
      unresolved_action_ids: []
      redaction_review: "Confirmed no raw transcript, secret, private source, or unredacted local path is included."
      ---

      # Completed system audit

      Keep the complete sanitized diagnosis here. Create every unresolved
      executable consequence with the structured trigger contract as a
      deferral, draft, or ledger action before recording the audit, then list
      its ID above.
    MARKDOWN
  end

  class Store
    attr_reader :root

    def initialize(root, fault_injector: nil)
      raise MissingStateRoot, "#{STATE_ENV} is not set" if RetroState.blank?(root)

      @root = canonical_root(root)
      @fault_injector = fault_injector
      dangerous_roots = [File::SEPARATOR, File.expand_path("~")]
      raise Error, "state root is too broad: #{@root}" if dangerous_roots.include?(@root)
    end

    def init
      refuse_git_worktree!
      FileUtils.mkdir_p(root, mode: 0o700)
      File.chmod(0o700, root)
      (STATE_DIRS + VERIFICATION_DIRS).each do |relative|
        path = File.join(root, relative)
        FileUtils.mkdir_p(path, mode: 0o700)
        File.chmod(0o700, path)
      end
      version_path = File.join(root, "state-version")
      exclusive_write(version_path, "#{SCHEMA_VERSION}\n") unless File.exist?(version_path)
      validate_version
      root
    end

    def show(record_ids)
      ensure_initialized
      records = record_ids.uniq.map do |id|
        unless id.match?(/\A(?:(?:RC|PC|VP)-\d{8}T\d{6}Z|(?:SCR|SD|LE|LA)-\d{8})-[a-f0-9]{6}\z/)
          raise Error, "invalid record ID: #{id}"
        end
        paths = (STATE_DIRS + VERIFICATION_DIRS).map { |dir| File.join(root, dir, "#{id}.md") }
          .select { |path| File.file?(path) }
        raise Error, "record not found: #{id}" if paths.empty?
        raise Error, "record ID is ambiguous: #{id}" unless paths.one?

        path = paths.first
        unless File.realpath(path).start_with?(root + File::SEPARATOR)
          raise Error, "record resolves outside the state root: #{id}"
        end
        data, body = RetroState.read_document(path)
        {"id" => id, "path" => path.delete_prefix(root + File::SEPARATOR),
         "frontmatter" => data, "body" => body}
      end
      {"root" => root, "records" => records}
    end

    def prepare_decision(id, verdict, rationale: nil)
      if !rationale.nil? && (!rationale.is_a?(String) || rationale.strip.empty?)
        raise Error, "reviewed rationale must be a non-empty string"
      end
      record = show([id]).fetch("records").first
      data = record.fetch("frontmatter")
      body = record.fetch("body")
      path = File.join(root, record.fetch("path"))
      reviewed_at = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
      case id
      when /\ARC-/
        archived = path == candidate_path("archive", id)
        unless archived || path == candidate_path("inbox", id)
          raise Error, "candidate must be in inbox or archive: #{id}"
        end
        RetroState.validate_candidate(data, body, label: path, routed: true, archived: archived)
        if archived
          unless data.fetch("triage").fetch("verdict") == "defer"
            raise Error, "candidate is not currently deferred: #{id}"
          end
          unless reviewed_at > data.fetch("triage").fetch("reviewed_at")
            raise Error, "replacement decision timestamp must be newer than the current triage"
          end
        end
        id_field = "candidate_id"
        verdicts = VERDICTS
        template = RetroState.decision_template
      when /\AVP-/
        unless path == verification_path("inbox", id)
          raise Error, "verification proposal must be in inbox: #{id}"
        end
        RetroState.validate_verification_proposal(data, body, label: path, routed: true)
        id_field = "verification_proposal_id"
        verdicts = VERIFICATION_PROPOSAL_VERDICTS
        template = RetroState.verification_decision_template
      else
        raise Error, "prepare-decision requires a candidate or verification proposal ID"
      end
      raise Error, "record identity does not match #{id}" unless data[id_field] == id
      raise Error, "verdict must be one of #{verdicts.join(", ")}" unless verdicts.include?(verdict)

      decision, = RetroState.parse_document(template)
      decision[id_field] = id
      decision["verdict"] = verdict
      decision["reviewed_at"] = reviewed_at
      decision["rationale"] = rationale || ""
      if id_field == "candidate_id" && verdict != "defer"
        RetroState.review_trigger_contract_fields.each { |field| decision.delete(field) }
      end
      RetroState.render_document(decision, "")
    end

    def prepare_verification(id, verification)
      unless VERIFICATION_PROPOSAL_STATES.include?(verification)
        raise Error, "proposed verification must be one of #{VERIFICATION_PROPOSAL_STATES.join(", ")}"
      end
      # Context retrieval also accepts proposal IDs; preparation must bind an accepted ID directly.
      accepted_path(id)
      context = verification_context(record_ids: [id]).fetch("records").first
      accepted = context.fetch("accepted").fetch("frontmatter")
      pending_ids = context.fetch("pending_verification_proposal_ids")
      pending = context.fetch("verification_proposals")
        .select { |record| pending_ids.include?(record.fetch("id")) }.map { |record| record.fetch("frontmatter") }
      draft, = RetroState.parse_document(RetroState.verification_proposal_template)
      draft["target_accepted_id"] = id
      draft["proposed_verification"] = verification
      %w[title source_scope verification_basis opportunity_match claim observation redaction_review].each do |field|
        draft[field] = ""
      end
      draft["decisive_evidence"] = []
      draft["what_is_false"] = "" if verification == "contradicted"
      if verification == "supported" && (accepted.fetch("verification") == "supported" ||
          pending.any? { |proposal| proposal.fetch("proposed_verification") == "supported" })
        draft["supplemental_reason"] = ""
      end
      validate_verification_target_state!(accepted, draft)
      prior = accepted.slice(
        "accepted_id", "destination", "expected_behavior", "verification_opportunity",
        "verification", "verification_basis", "applied_verification_proposal_ids"
      ).merge("pending_verification_proposals" => pending.map do |proposal|
        proposal.slice("verification_proposal_id", "proposed_verification", "claim")
      end)
      notes = <<~TEXT
        Complete every blank field, curate evidence, and review redaction before route-verification.
        Read applied and pending evidence through verification-context before judging supplementation.
        Preparation writes no state, supplies no evidence claim, and does not establish eligibility
        at routing time. These comments are discarded automatically when the proposal is routed.

        Target context:
        #{YAML.dump(prior).rstrip}
      TEXT
      comments = notes.lines.map { |line| "# #{line}" }.join
      RetroState.render_document(draft, "").sub(/\A---\n/) { "---\n#{comments}\n" }
    end

    def prepare_accepted(record_ids, commits)
      raise Error, "prepare-accepted requires candidate IDs and public commit SHAs" if record_ids.empty? || commits.empty?
      commits = commits.map(&:downcase).uniq
      unless commits.all? { |commit| commit.match?(COMMIT_HASH_PATTERN) }
        raise Error, "prepare-accepted requires hexadecimal commit SHAs of 7 to 40 characters"
      end

      records = show(record_ids).fetch("records")
      candidates = records.map { |record| validate_archived_candidate_record(record) }
      ancestry = candidates.to_h { |candidate| [candidate.fetch("candidate_id"), candidate] }
      resolve_candidate = lambda do |id|
        next unless id.match?(/\ARC-\d{8}T\d{6}Z-[a-f0-9]{6}\z/) && File.file?(candidate_path("archive", id))

        ancestry[id] = validate_archived_candidate_record(show([id]).fetch("records").first)
      end
      candidates.each do |candidate|
        unless accepted_publication_expected?(candidate.fetch("triage"), ancestry, uncertain: false, &resolve_candidate)
          raise Error, "candidate has no accepted publication outcome: #{candidate.fetch("candidate_id")}"
        end
      end

      draft, = RetroState.parse_document(RetroState.accepted_template)
      draft["originating_candidate_ids"] = records.map { |record| record.fetch("id") }
      draft["implementation_commits"] = commits
      %w[
        source_report_summary expected_behavior observed_behavior trigger non_trigger
        destination verification_opportunity redaction_review
      ].each { |field| draft[field] = "" }
      draft["decisive_evidence"] = []
      context = ancestry.values.map do |candidate|
        candidate.slice(
          "candidate_id", "title", "evidence_lineage", "evidence_lineage_note",
          "observation", "decisive_evidence", "proposed_destination", "triage"
        )
      end
      notes = <<~TEXT
        Complete the blank outcome fields, curate decisive evidence, and review redaction before
        submitting with record-accepted. Verify the supplied public commits and final destination.
        Defaults remain accepted and unverified; source publication alone establishes no benefit.
        These preparation comments are discarded automatically when the record is stored.

        Prior candidate context:
        This context preserves intake evidence and reviewed triage. Proposed destinations may have
        been narrowed during review. It does not establish the implemented outcome or verification.

        #{YAML.dump(context).rstrip}
      TEXT
      comments = notes.lines.map { |line| "# #{line}" }.join
      RetroState.render_document(draft, "# Accepted candidate\n").sub(/\A---\n/) { "---\n#{comments}\n" }
    end

    def prepare_accepted_update(id, commits: [], destination: nil)
      if !destination.nil? && (!destination.is_a?(String) || destination.strip.empty?)
        raise Error, "destination must be a non-empty string"
      end
      record = validate_accepted_record(show([id]).fetch("records").first)
      data = record.fetch("frontmatter")
      body = record.fetch("body")
      unless commits.empty?
        data["implementation_commits"] = (data.fetch("implementation_commits") + commits.map(&:downcase)).uniq
      end
      data["destination"] = destination unless destination.nil?
      RetroState.validate_accepted(data, body, label: id, assigned: true) unless commits.empty? && destination.nil?

      RetroState.render_document(RetroState.without_keys(data, "accepted_id", "accepted_at"), body)
    end

    def snapshot
      raise Error, "state root does not exist: #{root}" unless Dir.exist?(root)
      refuse_git_worktree!
      entries = {}
      visit = lambda do |directory|
        Dir.children(directory).sort.each do |name|
          path = File.join(directory, name)
          relative = path.delete_prefix(root + File::SEPARATOR)
          stat = File.lstat(path)
          entries[relative] = if stat.symlink?
            {"kind" => "symlink", "target" => File.readlink(path)}
          elsif stat.directory?
            {"kind" => "directory"}
          elsif stat.file?
            {"kind" => "file", "sha256" => Digest::SHA256.file(path).hexdigest}
          else
            raise Error, "unsupported filesystem entry: #{relative}"
          end
          visit.call(path) if stat.directory?
        end
      end
      visit.call(root)
      {"snapshot_version" => 1, "root" => root, "entries" => entries.sort.to_h}
    end

    def compare(input_path, allowed_paths: [], allowed_actions: [])
      text = (input_path == "-") ? $stdin.read : File.read(input_path, encoding: "UTF-8")
      before = JSON.parse(text)
      unless before.is_a?(Hash) && before["snapshot_version"] == 1 &&
          before["root"] == root && before["entries"].is_a?(Hash)
        raise Error, "snapshot must have version 1, this state root, and an entries mapping"
      end
      before.fetch("entries").each do |path, entry|
        validate_relative_path!(path)
        valid = case entry.is_a?(Hash) && entry["kind"]
        when "directory" then entry.keys == ["kind"]
        when "file" then entry.keys.sort == %w[kind sha256] && entry["sha256"].is_a?(String) && entry["sha256"].match?(/\A[a-f0-9]{64}\z/)
        when "symlink" then entry.keys.sort == %w[kind target] && entry["target"].is_a?(String)
        end
        raise Error, "invalid snapshot entry: #{path}" unless valid
      end
      allowed_paths.each { |path| validate_relative_path!(path) }
      allowed_paths += allowed_actions.flat_map do |action|
        operation, id = action.split(":", 2)
        raise Error, "expected --allow-action ACTION:ID" unless id

        paths = case operation
        when "process"
          [candidate_path("inbox", id), candidate_path("archive", id),
            artifact_cadence_path, artifact_cadence_lock_path]
        when "close-papercut"
          [papercut_path("inbox", id), papercut_path("archive", id)]
        when "reconsider"
          [candidate_path("archive", id)]
        when "record-accepted"
          [accepted_path(id)]
        when "update-accepted"
          [accepted_path(id), artifact_cadence_lock_path]
        when "process-verification"
          archive = verification_path("archive", id)
          record = show([id]).fetch("records").first
          unless File.join(root, record.fetch("path")) == archive
            raise Error, "process-verification allowance requires a completed archived proposal: #{id}"
          end
          proposal = validate_verification_record(record).fetch("frontmatter")
          footprint = [verification_path("inbox", id), archive, artifact_cadence_lock_path]
          if proposal.fetch("triage").fetch("verdict") == "apply"
            target = validate_accepted_record(show([proposal.fetch("target_accepted_id")]).fetch("records").first)
            footprint << File.join(root, target.fetch("path"))
          end
          footprint
        else
          raise Error, "unsupported comparison action: #{operation}; see compare --help"
        end
        paths.map do |path|
          path.delete_prefix(root + File::SEPARATOR)
        end
      end
      previous = before.fetch("entries")
      current = snapshot.fetch("entries")
      added = (current.keys - previous.keys).sort
      removed = (previous.keys - current.keys).sort
      modified = (previous.keys & current.keys).select { |path| previous[path] != current[path] }.sort
      changed = (added + removed + modified).sort
      unexpected = changed - allowed_paths
      {"root" => root, "unchanged" => changed.empty?, "matches" => unexpected.empty?,
       "added" => added, "removed" => removed, "modified" => modified, "unexpected" => unexpected}
    rescue JSON::ParserError => e
      raise Error, "invalid snapshot JSON: #{e.message}"
    end

    def validate_relative_path!(path)
      unless path.is_a?(String) && !path.include?("\0") &&
          path.split("/", -1).none? { |part| ["", ".", ".."].include?(part) }
        raise Error, "expected an exact state-root-relative path: #{path.inspect}"
      end
    end

    def route(input_path, document: nil)
      init
      data, body = document || RetroState.read_document(input_path)
      data = data.dup
      RetroState.validate_candidate(data, body, label: input_path, routed: false)
      validate_candidate_supersession!(data)

      now = Time.now.utc
      id = unique_id("RC-#{now.strftime("%Y%m%dT%H%M%SZ")}")
      data["candidate_id"] = id
      data["created_at"] = now.strftime("%Y-%m-%dT%H:%M:%SZ")
      intake = RetroState.without_keys(data, "intake_digest")
      data["intake_digest"] = Digest::SHA256.hexdigest(RetroState.render_document(intake, body))
      output = RetroState.render_document(data, body)
      destination = File.join(root, "retrospectives", "inbox", "#{id}.md")
      exclusive_write(destination, output)
      destination
    end

    def pending
      ensure_initialized
      Dir.glob(File.join(root, "retrospectives", "inbox", "*.md")).sort.map do |path|
        data, body = RetroState.read_document(path)
        RetroState.validate_candidate(data, body, label: path, routed: true)
        [data.fetch("candidate_id"), data.fetch("title"), path]
      end
    end

    def route_verification(input_path, document: nil)
      data, body = document || RetroState.read_document(input_path)
      data = data.dup
      RetroState.validate_verification_proposal(data, body, label: input_path, routed: false)
      ensure_initialized
      validate_verification_target!(data)
      if data["proposed_verification"] == "supported" && !data.key?("supplemental_reason")
        pending = pending_support.fetch(data.fetch("target_accepted_id"), [])
        unless pending.empty?
          ids = pending.map { |proposal| proposal.fetch("verification_proposal_id") }
          raise Error, "support already pending: #{ids.join(", ")}; read it and add supplemental_reason only for materially useful evidence"
        end
      end
      ensure_verification_dirs

      now = Time.now.utc
      id = unique_verification_id("VP-#{now.strftime("%Y%m%dT%H%M%SZ")}")
      data["verification_proposal_id"] = id
      data["created_at"] = now.strftime("%Y-%m-%dT%H:%M:%SZ")
      intake = RetroState.without_keys(data, "intake_digest")
      data["intake_digest"] = Digest::SHA256.hexdigest(RetroState.render_document(intake, body))
      output = RetroState.render_document(data, body)
      destination = verification_path("inbox", id)
      exclusive_write(destination, output)
      destination
    end

    def pending_verifications
      ensure_initialized
      pending_verification_records.map do |path, data|
        [
          data.fetch("verification_proposal_id"),
          data.fetch("target_accepted_id"),
          data.fetch("proposed_verification"),
          data.fetch("title"),
          path
        ]
      end
    end

    def record_papercut(data, body, label:)
      RetroState.validate_papercut(data, body, label: label, routed: false)
      init

      now = Time.now.utc
      id = unique_papercut_id("PC-#{now.strftime("%Y%m%dT%H%M%SZ")}")
      record = data.dup
      record["papercut_id"] = id
      record["created_at"] = now.strftime("%Y-%m-%dT%H:%M:%SZ")
      intake = RetroState.without_keys(record, "intake_digest")
      record["intake_digest"] = Digest::SHA256.hexdigest(RetroState.render_document(intake, body))
      destination = papercut_path("inbox", id)
      exclusive_write(destination, RetroState.render_document(record, body))
      destination
    end

    def repair_papercut(papercut_id, repair_path)
      ensure_initialized
      repair, repair_body = RetroState.read_document(repair_path)
      RetroState.validate_papercut_repair(
        repair,
        repair_body,
        label: repair_path,
        expected_id: papercut_id
      )

      locations = %w[inbox archive].filter_map do |area|
        path = papercut_path(area, papercut_id)
        [area, path] if File.file?(path)
      end
      raise Error, "papercut not found: #{papercut_id}" if locations.empty?
      if locations.length > 1
        raise Error, "papercut exists in both inbox and archive: #{papercut_id}"
      end

      area, path = locations.fetch(0)
      data, body = RetroState.read_document(path)
      authenticated_classifications = RetroState.validate_papercut_integrity(
        data,
        body,
        label: path,
        routed: true,
        archived: area == "archive",
        recover_classification_digest: true,
        allow_unverified_digest: true
      )
      unless data["papercut_id"] == papercut_id
        raise Error, "#{path}: papercut_id does not match filename"
      end

      invalid_fields = PAPERCUT_CLASSIFICATIONS.filter_map do |field, allowed|
        field unless allowed.include?(data.fetch(field))
      end
      if invalid_fields.empty?
        raise Error, "#{path}: papercut classifications are already valid"
      end

      changes = {}
      replaced_intake = RetroState.without_keys(data, "intake_digest", "closure")
      replaced_digest = Digest::SHA256.hexdigest(RetroState.render_document(replaced_intake, body))
      unless repair["observed_intake_digest"] == replaced_digest
        raise Error, "#{repair_path}: observed_intake_digest does not match current papercut"
      end
      prior_digest = data.fetch("intake_digest")
      digest_recovery = if prior_digest == replaced_digest
        "matched"
      elsif authenticated_classifications
        "classification-only"
      else
        unless repair["accept_current_evidence"]
          raise Error, "#{repair_path}: unrecoverable intake digest requires accept_current_evidence: true"
        end
        "current-evidence-authorized"
      end
      if digest_recovery != "current-evidence-authorized" && repair["accept_current_evidence"]
        raise Error, "#{repair_path}: accept_current_evidence must be false when the prior digest is authenticated"
      end

      PAPERCUT_CLASSIFICATIONS.each do |field, allowed|
        current = data.fetch(field)
        replacement = repair.fetch(field)
        if allowed.include?(current)
          valid_replacements = [current]
          valid_replacements << authenticated_classifications[field] if authenticated_classifications
          unless valid_replacements.include?(replacement)
            raise Error, "#{path}: repair must not change already-valid #{field}"
          end
        end
        changes[field] = {"from" => current, "to" => replacement} unless current == replacement
      end

      changes.each { |field, change| data[field] = change.fetch("to") }
      schema_repair = {
        "repaired_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "rationale" => repair.fetch("rationale"),
        "redaction_review" => repair.fetch("redaction_review"),
        "prior_intake_digest" => prior_digest,
        "replaced_intake_digest" => replaced_digest,
        "digest_recovery" => digest_recovery,
        "changes" => changes
      }
      if authenticated_classifications
        schema_repair["authenticated_classifications"] = authenticated_classifications
      end
      data["schema_repairs"] = data.fetch("schema_repairs", []) + [schema_repair]
      intake = RetroState.without_keys(data, "intake_digest", "closure")
      data["intake_digest"] = Digest::SHA256.hexdigest(RetroState.render_document(intake, body))
      RetroState.validate_papercut(
        data,
        body,
        label: path,
        routed: true,
        archived: area == "archive"
      )
      replace_write(path, RetroState.render_document(data, body))
      path
    end

    def prepare_papercut_repair(papercut_id)
      ensure_initialized
      locations = %w[inbox archive].filter_map do |area|
        path = papercut_path(area, papercut_id)
        [area, path] if File.file?(path)
      end
      raise Error, "papercut not found: #{papercut_id}" if locations.empty?
      if locations.length > 1
        raise Error, "papercut exists in both inbox and archive: #{papercut_id}"
      end

      area, path = locations.fetch(0)
      data, body = RetroState.read_document(path)
      RetroState.validate_papercut_integrity(
        data,
        body,
        label: path,
        routed: true,
        archived: area == "archive",
        recover_classification_digest: true,
        allow_unverified_digest: true
      )
      if PAPERCUT_CLASSIFICATIONS.all? { |field, allowed| allowed.include?(data.fetch(field)) }
        raise Error, "#{path}: papercut classifications are already valid"
      end

      decision, decision_body = RetroState.parse_document(RetroState.papercut_repair_template)
      decision["papercut_id"] = papercut_id
      current_intake = RetroState.without_keys(data, "intake_digest", "closure")
      decision["observed_intake_digest"] = Digest::SHA256.hexdigest(
        RetroState.render_document(current_intake, body)
      )
      PAPERCUT_CLASSIFICATIONS.each_key { |field| decision[field] = data.fetch(field) }
      RetroState.render_document(decision, decision_body)
    end

    def papercuts(archive: false)
      ensure_initialized
      area = archive ? "archive" : "inbox"
      Dir.glob(File.join(root, "papercuts", area, "*.md")).sort.map do |path|
        data, body = RetroState.read_document(path)
        RetroState.validate_papercut(data, body, label: path, routed: true, archived: archive)
        observation = data.fetch("observation").gsub(/\s+/, " ").strip
        [data.fetch("papercut_id"), data.fetch("kind"), data.fetch("impact"), observation, path]
      end
    end

    def close_papercut(papercut_id, outcome:, rationale:, related_papercut_id: nil, related_candidate_id: nil)
      ensure_initialized
      source = papercut_path("inbox", papercut_id)
      raise Error, "papercut not found in inbox: #{papercut_id}" unless File.file?(source)

      data, body = RetroState.read_document(source)
      RetroState.validate_papercut(data, body, label: source, routed: true)
      closure = {
        "outcome" => outcome,
        "rationale" => rationale,
        "closed_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
      }
      closure["related_papercut_id"] = related_papercut_id if related_papercut_id
      closure["related_candidate_id"] = related_candidate_id if related_candidate_id
      RetroState.validate_papercut_closure(closure, papercut_id, source)
      validate_papercut_reference!(closure)

      destination = papercut_path("archive", papercut_id)
      if File.file?(destination)
        verify_matching_papercut_archive(destination, data, body, closure)
      else
        data["closure"] = closure
        exclusive_write(destination, RetroState.render_document(data, body))
        operation_checkpoint(:papercut_archive_written)
      end
      File.unlink(source)
      destination
    end

    def process(candidate_id, decision_path)
      ensure_initialized
      with_state_lock do
        source = candidate_path("inbox", candidate_id)
        raise Error, "candidate not found in inbox: #{candidate_id}" unless File.file?(source)

        candidate, body = RetroState.read_document(source)
        RetroState.validate_candidate(candidate, body, label: source, routed: true)
        decision, decision_body = RetroState.read_document(decision_path)
        RetroState.validate_decision(decision, decision_body, label: decision_path, expected_id: candidate_id)

        triage = RetroState.without_keys(decision, "schema_version", "record_type")
        triage["notes"] = decision_body.rstrip unless decision_body.strip.empty?
        candidate["triage"] = triage
        output = RetroState.render_document(candidate, body)
        destination = candidate_path("archive", candidate_id)
        cadence = artifact_cadence_state
        archive_exists = File.file?(destination)
        tracking_is_durable = File.file?(artifact_cadence_path) &&
          cadence.key?(COUNTED_CANDIDATE_IDS_FIELD)
        if archive_exists && !tracking_is_durable
          raise Error,
            "cannot safely resume candidate archive without durable identity tracking: #{destination}"
        end
        unless tracking_is_durable
          cadence[COUNTED_CANDIDATE_IDS_FIELD] = []
          write_artifact_cadence(cadence)
        end

        created = write_or_verify_archive(destination, output, record_type: "candidate")
        operation_checkpoint(:candidate_archive_written) if created

        counted_ids = cadence.fetch(COUNTED_CANDIDATE_IDS_FIELD)
        unless counted_ids.include?(candidate_id)
          cadence["candidate_archives_total"] += 1
          counted_ids << candidate_id
          write_artifact_cadence(cadence)
        end
        operation_checkpoint(:candidate_cadence_written)

        File.unlink(source)
        destination
      end
    end

    def process_verification(proposal_id, decision_path)
      ensure_initialized
      with_state_lock do
        source = verification_path("inbox", proposal_id)
        raise Error, "verification proposal not found in inbox: #{proposal_id}" unless File.file?(source)

        proposal, body = RetroState.read_document(source)
        RetroState.validate_verification_proposal(proposal, body, label: source, routed: true)
        decision, decision_body = RetroState.read_document(decision_path)
        RetroState.validate_verification_decision(
          decision,
          decision_body,
          label: decision_path,
          expected_id: proposal_id
        )

        triage = RetroState.without_keys(decision, "schema_version", "record_type")
        triage["notes"] = decision_body.rstrip unless decision_body.strip.empty?
        proposal["triage"] = triage
        output = RetroState.render_document(proposal, body)
        destination = verification_path("archive", proposal_id)
        write_or_verify_archive(destination, output, record_type: "verification") if File.file?(destination)
        if decision.fetch("verdict") == "apply"
          apply_verification_proposal!(proposal, decision)
          operation_checkpoint(:verification_accepted_written)
        else
          _path, accepted, _body = read_verification_target(proposal)
          if accepted.fetch("applied_verification_proposal_ids", []).include?(proposal_id)
            raise Error, "verification proposal is already applied; resume with the original apply decision"
          end
        end
        write_or_verify_archive(destination, output, record_type: "verification")
        operation_checkpoint(:verification_archive_written)
        File.unlink(source)
        destination
      end
    end

    def reconsider(candidate_id, decision_path)
      ensure_initialized
      path = candidate_path("archive", candidate_id)
      raise Error, "candidate not found in archive: #{candidate_id}" unless File.file?(path)

      candidate, body = RetroState.read_document(path)
      RetroState.validate_candidate(candidate, body, label: path, routed: true, archived: true)
      current_triage = candidate.fetch("triage")
      unless current_triage.fetch("verdict") == "defer"
        raise Error, "candidate is not currently deferred: #{candidate_id}"
      end

      decision, decision_body = RetroState.read_document(decision_path)
      RetroState.validate_decision(decision, decision_body, label: decision_path, expected_id: candidate_id)
      unless decision.fetch("reviewed_at") > current_triage.fetch("reviewed_at")
        raise Error, "replacement decision must be newer than the current triage"
      end

      replacement = RetroState.without_keys(decision, "schema_version", "record_type")
      replacement["notes"] = decision_body.rstrip unless decision_body.strip.empty?
      candidate["triage_history"] = candidate.fetch("triage_history", []) + [current_triage]
      candidate["triage"] = replacement
      RetroState.validate_candidate(candidate, body, label: path, routed: true, archived: true)
      replace_write(path, RetroState.render_document(candidate, body))
      path
    end

    def record_accepted(input_path)
      ensure_initialized
      data, body = RetroState.read_document(input_path)
      RetroState.validate_accepted(
        data,
        body,
        label: input_path,
        assigned: false,
        strict_contradiction: true
      )
      missing = data.fetch("originating_candidate_ids").reject do |id|
        File.file?(candidate_path("archive", id))
      end
      raise Error, "accepted record references candidates not in archive: #{missing.join(", ")}" unless missing.empty?

      supersedes_ids = data.fetch("originating_candidate_ids").map do |candidate_id|
        archive_path = candidate_path("archive", candidate_id)
        candidate, candidate_body = RetroState.read_document(archive_path)
        RetroState.validate_candidate(
          candidate,
          candidate_body,
          label: archive_path,
          routed: true,
          archived: true
        )
        candidate["supersedes_accepted_id"]
      end.compact.uniq.sort
      supplied_supersedes_ids = data.fetch("supersedes_accepted_ids", []).sort
      if data.key?("supersedes_accepted_ids") && supplied_supersedes_ids != supersedes_ids
        raise Error, "accepted record supersedes_accepted_ids do not match originating candidates"
      end
      data["supersedes_accepted_ids"] = supersedes_ids unless supersedes_ids.empty?
      RetroState.validate_accepted(
        data,
        body,
        label: input_path,
        assigned: false,
        strict_contradiction: true
      )
      validate_accepted_external_references!(data)

      now = Time.now.utc
      id = unique_id("SCR-#{now.strftime("%Y%m%d")}")
      data["accepted_id"] = id
      data["accepted_at"] = now.strftime("%Y-%m-%dT%H:%M:%SZ")
      output = RetroState.render_document(data, body)
      destination = accepted_path(id)
      exclusive_write(destination, output)
      destination
    end

    def update_accepted(accepted_id, input_path)
      ensure_initialized
      with_state_lock do
        path = accepted_path(accepted_id)
        raise Error, "accepted record not found: #{accepted_id}" unless File.file?(path)

        current, current_body = RetroState.read_document(path)
        RetroState.validate_accepted(current, current_body, label: path, assigned: true)
        replacement, body = RetroState.read_document(input_path)
        RetroState.validate_accepted(
          replacement,
          body,
          label: input_path,
          assigned: false,
          strict_contradiction: true
        )
        RetroState.validate_accepted_transition(current, replacement, accepted_id)
        %w[verification verification_basis].each do |field|
          unless replacement[field] == current[field]
            raise Error, "accepted record #{field} changes require process-verification"
          end
        end
        validate_accepted_external_references!(replacement, accepted_id: accepted_id)

        replacement["accepted_id"] = current.fetch("accepted_id")
        replacement["accepted_at"] = current.fetch("accepted_at")
        replacement["implementation_commits"] =
          (current.fetch("implementation_commits") + replacement.fetch("implementation_commits")).uniq
        RetroState.validate_accepted(replacement, body, label: input_path, assigned: true)
        replace_write(path, RetroState.render_document(replacement, body))
        path
      end
    end

    def accepted_records_query(destinations: [], texts: [], active_supported: false)
      ensure_initialized
      if destinations.empty? && texts.empty?
        raise Error, "accepted-records requires --destination TEXT or --text TEXT"
      end
      if (destinations + texts).any? { |query| query.strip.empty? }
        raise Error, "accepted-records filters must not be blank"
      end

      destination_queries = destinations.map(&:downcase).uniq
      text_queries = texts.map(&:downcase).uniq
      accepted_records(include_body: true).each_with_object([]) do |(path, data, body), rows|
        if active_supported
          next unless %w[accepted implemented].include?(data["disposition"])
          next unless data["verification"] == "supported"
        end
        recorded_destination = data.fetch("destination")
        next unless destination_queries.empty? || destination_queries.any? { |query| recorded_destination.downcase.include?(query) }

        searchable = [
          data.fetch("accepted_id"),
          *data.fetch("originating_candidate_ids"),
          *data.fetch("implementation_commits"),
          data.fetch("source_report_summary"),
          data.fetch("expected_behavior"),
          data.fetch("observed_behavior"),
          *data.fetch("decisive_evidence"),
          data.fetch("trigger"),
          data.fetch("non_trigger"),
          recorded_destination,
          data.fetch("verification_opportunity"),
          body
        ].join("\n").downcase
        next unless text_queries.empty? || text_queries.any? { |query| searchable.include?(query) }

        rows << [
          data.fetch("accepted_id"),
          data.fetch("disposition"),
          data.fetch("verification"),
          recorded_destination.gsub(/\s+/, " ").strip,
          data.fetch("expected_behavior").gsub(/\s+/, " ").strip,
          path
        ]
      end
    end

    def verification_context(destinations: [], record_ids: [], texts: [], compact: false, limit: 20, offset: 0)
      ensure_initialized
      if destinations.empty? == record_ids.empty?
        raise Error, "verification-context requires destinations or record IDs, separately"
      end
      documents = {}
      read = ->(id) { documents[id] ||= show([id]).fetch("records").first }
      validated_proposals = {}
      proposal = ->(id) { validated_proposals[id] ||= validate_verification_record(read.call(id)) }
      unless record_ids.empty?
        unless texts.empty? && !compact
          raise Error, "text filters and compact output apply only to destination discovery"
        end
        selected = show(record_ids).fetch("records")
        documents.merge!(selected.to_h { |record| [record.fetch("id"), record] })
        proposals = selected.select { |record| record.fetch("id").start_with?("VP-") }
        proposals.each { |record| proposal.call(record.fetch("id")) }
        target_ids = selected.map do |record|
          record.fetch("id").start_with?("VP-") ? record.fetch("frontmatter").fetch("target_accepted_id") : record.fetch("id")
        end
        records = target_ids.uniq.map { |id| read.call(id) }
        proposals_by_target = proposals.group_by { |record| record.fetch("frontmatter").fetch("target_accepted_id") }
        pending = Dir.glob(File.join(root, "verifications", "inbox", "*.md")).sort
          .map { |path| proposal.call(File.basename(path, ".md")) }
          .group_by { |record| record.fetch("frontmatter").fetch("target_accepted_id") }
        details = records.map do |record|
          id = record.fetch("id")
          data = record.fetch("frontmatter")
          unless File.join(root, record.fetch("path")) == accepted_path(id) && data["accepted_id"] == id
            raise Error, "verification-context requires accepted record IDs: #{id}"
          end
          RetroState.validate_accepted(data, record.fetch("body"), label: id, assigned: true)
          validate_accepted_external_references!(data, accepted_id: id, &proposal)
          applied_ids = data.fetch("applied_verification_proposal_ids", [])
          selected_proposals = proposals_by_target.fetch(id, [])
          selected_proposals.each do |proposal|
            if proposal.dig("frontmatter", "triage", "verdict") == "apply" && !applied_ids.include?(proposal.fetch("id"))
              raise Error, "verification target does not reference applied proposal: #{proposal.fetch("id")}"
            end
          end
          verification_detail(
            record,
            selected: selected_proposals,
            applied: applied_ids.map { |proposal_id| proposal.call(proposal_id) },
            pending: pending.fetch(id, [])
          ).merge(verification_claim_summary(data, compact: true, &proposal))
        end
        return {"root" => root, "mode" => "detail", "records" => details}
      end

      if destinations.any? { |destination| destination.strip.empty? }
        raise Error, "verification-context destinations must not be blank"
      end
      if texts.any? { |text| text.strip.empty? }
        raise Error, "verification-context text filters must not be blank"
      end
      unless limit.is_a?(Integer) && limit.positive? && offset.is_a?(Integer) && offset >= 0
        raise Error, "verification-context requires a positive limit and nonnegative offset"
      end
      queries = destinations.map(&:downcase).uniq
      text_queries = texts.map(&:downcase).uniq
      matches = accepted_records.select do |_path, data|
        %w[accepted implemented].include?(data["disposition"]) &&
          queries.any? { |query| data.fetch("destination").downcase.include?(query) } &&
          (text_queries.empty? || text_queries.any? do |query|
            %w[expected_behavior verification_opportunity].any? { |field| data.fetch(field).downcase.include?(query) }
          end)
      end
      pending = compact ? {} : pending_verification_records.group_by { |_path, data| data.fetch("target_accepted_id") }
      records = matches.drop(offset).first(limit).map do |path, data|
        id = data.fetch("accepted_id")
        validate_accepted_external_references!(data, accepted_id: id, &proposal)
        claims = verification_claim_summary(data, compact: compact, &proposal)
        if compact
          next data.slice("verification", "verification_basis")
            .merge("id" => id).merge(claims)
        end
        summary = data.slice(
          "disposition", "verification", "verification_basis", "destination",
          "expected_behavior", "verification_opportunity"
        )
        summary.merge(claims).merge(
          "id" => id,
          "path" => path.delete_prefix(root + File::SEPARATOR),
          "applied_verification_proposal_ids" => data.fetch("applied_verification_proposal_ids", []),
          "pending_verification_proposals" => pending.fetch(id, []).map do |_proposal_path, proposal|
            proposal.slice("verification_proposal_id", "proposed_verification", "claim")
          end
        )
      end
      next_offset = offset + records.length
      {
        "root" => root, "mode" => "discovery", "destinations" => destinations.uniq, "texts" => texts.uniq,
        "total" => matches.length, "limit" => limit, "offset" => offset,
        "next_offset" => (next_offset < matches.length) ? next_offset : nil,
        "records" => records
      }
    end

    def record_draft(input_path)
      record_auxiliary(input_path, "draft", "drafts", "draft_id", "SD") do |data, body, label, assigned|
        RetroState.validate_draft(data, body, label: label, assigned: assigned)
      end
    end

    def record_ledger(input_path)
      record_auxiliary(input_path, "ledger-entry", "ledgers", "ledger_id", "LE") do |data, body, label, assigned|
        RetroState.validate_ledger_entry(data, body, label: label, assigned: assigned)
      end
    end

    def close_ledger(ledger_id, rationale:)
      ensure_initialized
      with_state_lock do
        path = ledger_path(ledger_id)
        raise Error, "ledger not found: #{ledger_id}" unless File.file?(path)

        blocking_accepted_id = accepted_records.find do |_accepted_path, accepted|
          accepted.dig("contradiction", "residual_ledger_id") == ledger_id &&
            !RetroState.contradiction_resolved?(accepted)
        end&.last&.fetch("accepted_id")
        if blocking_accepted_id
          raise Error,
            "ledger remains responsible for unresolved contradicted record: #{blocking_accepted_id}"
        end

        data, body = RetroState.read_document(path)
        RetroState.validate_ledger_entry(data, body, label: path, assigned: true)
        raise Error, "ledger is already closed: #{ledger_id}" unless data["status"] == "open"

        closed_at = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
        data["status"] = "closed"
        data["last_reviewed"] = closed_at
        data["closure"] = {
          "rationale" => rationale,
          "closed_at" => closed_at
        }
        RetroState.validate_ledger_entry(data, body, label: path, assigned: true)
        replace_write(path, RetroState.render_document(data, body))
        path
      end
    end

    def review_queue
      ensure_initialized
      rows = []

      pending.each do |candidate_id, title, path|
        rows << ["candidate", candidate_id, "Review candidate: #{title.gsub(/\s+/, " ").strip}", path]
      end
      papercuts.each do |papercut_id, _kind, _impact, observation, path|
        rows << ["papercut", papercut_id, "Review papercut: #{observation}", path]
      end
      pending_verifications.each do |proposal_id, accepted_id, proposed_state, _title, path|
        trigger = "Adjudicate proposed #{proposed_state} evidence for #{accepted_id}."
        rows << ["verification-proposal", proposal_id, trigger, path]
      end

      published_candidate_ids = accepted_records.flat_map do |_path, data|
        data.fetch("originating_candidate_ids")
      end
      candidates = archived_candidates
      candidates_by_id = candidates.to_h do |_path, data|
        [data.fetch("candidate_id"), data]
      end

      candidates.each do |path, data|
        triage = data.fetch("triage")
        candidate_id = data.fetch("candidate_id")
        if triage["verdict"] == "defer"
          rows << ["deferred", candidate_id, triage.fetch("review_trigger"), path]
        elsif accepted_publication_expected?(triage, candidates_by_id) &&
            !published_candidate_ids.include?(candidate_id)
          trigger = "Publish the accepted outcome and record accepted metadata for this candidate origin."
          rows << ["accepted-publication", candidate_id, trigger, path]
        end
      end

      accepted_records.each do |path, data|
        next unless data["verification"] == "contradicted"
        next if RetroState.contradiction_resolved?(data)
        residual_id = data.dig("contradiction", "residual_ledger_id")
        next if residual_id && action_reference_open?(residual_id)

        trigger = "Review the contradiction: retain with rationale, correct or remove guidance, or assign a residual ledger."
        rows << ["contradiction", data.fetch("accepted_id"), trigger, path]
      end

      Dir.glob(File.join(root, "drafts", "*.md")).sort.each do |path|
        data, body = RetroState.read_document(path)
        RetroState.validate_draft(data, body, label: path, assigned: true)
        next unless %w[open revised].include?(data["status"])

        rows << ["draft", data.fetch("draft_id"), data.fetch("review_trigger"), path]
      end

      Dir.glob(File.join(root, "ledgers", "*.md")).sort.each do |path|
        data, body = RetroState.read_document(path)
        RetroState.validate_ledger_entry(data, body, label: path, assigned: true)
        next unless data["status"] == "open"

        rows << ["ledger", data.fetch("ledger_id"), data.fetch("review_trigger"), path]
      end

      cadence = artifact_audit_status
      if cadence.fetch(:due)
        trigger = "#{cadence.fetch(:archives_since)} candidate archives since the last completed artifact audit"
        rows << ["artifact-audit", "repository", trigger, cadence.fetch(:last_audit_path, "-")]
      end

      rows
    end

    def accepted_publication_expected?(triage, candidates_by_id, visited_ids = [], uncertain: true, &resolve_candidate)
      verdict = triage.fetch("verdict")
      return true if %w[accept split].include?(verdict)
      return false unless verdict == "merge"

      related_ids = triage.fetch("related_candidate_ids", [])
      return uncertain if related_ids.empty?

      related_ids.any? do |id|
        next false if visited_ids.include?(id)

        related = candidates_by_id[id] || resolve_candidate&.call(id)
        related ? accepted_publication_expected?(
          related.fetch("triage"),
          candidates_by_id,
          visited_ids + [id],
          uncertain: uncertain,
          &resolve_candidate
        ) : uncertain
      end
    end

    def verification_opportunities(destination: nil)
      ensure_initialized
      support = pending_support
      accepted_records.each_with_object([]) do |(path, data), rows|
        next unless %w[accepted implemented].include?(data["disposition"])
        next unless data["verification"] == "unverified"
        if destination && !data.fetch("destination").downcase.include?(destination.downcase)
          next
        end

        rows << [
          data.fetch("accepted_id"),
          data.fetch("destination"),
          data.fetch("verification_opportunity"),
          path,
          support.fetch(data.fetch("accepted_id"), []).map { |proposal|
            "#{proposal.fetch("verification_proposal_id")}:#{proposal.fetch("claim")}"
          }.join(",")
        ]
      end
    end

    def record_audit(input_path)
      ensure_initialized
      with_state_lock do
        data, body = RetroState.read_document(input_path)
        RetroState.validate_learning_audit(data, body, label: input_path, assigned: false)
        cadence = artifact_cadence_state

        data.fetch("unresolved_action_ids").each do |action_id|
          next if action_reference_open?(action_id)

          raise Error, "audit unresolved action is missing or not open: #{action_id}"
        end

        now = Time.now.utc
        id = unique_auxiliary_id("LA", "audits/learning-process")
        data["audit_id"] = id
        data["completed_at"] = now.strftime("%Y-%m-%dT%H:%M:%SZ")
        data["candidate_archive_count"] = archived_candidates.length
        data["candidate_archives_total"] = cadence.fetch("candidate_archives_total")
        RetroState.validate_learning_audit(data, body, label: input_path, assigned: true)
        destination = learning_audit_path(id)
        exclusive_write(destination, RetroState.render_document(data, body))
        operation_checkpoint(:audit_record_written)
        if data["audit_kind"] == "skill-repository"
          cadence["last_completed_artifact_audit_total"] = cadence.fetch("candidate_archives_total")
          write_artifact_cadence(cadence)
        end
        destination
      end
    end

    def recover_audit(audit_id)
      ensure_initialized
      with_state_lock do
        path = learning_audit_path(audit_id)
        raise Error, "audit not found: #{audit_id}" unless File.file?(path)

        data, body = RetroState.read_document(path)
        RetroState.validate_learning_audit(data, body, label: path, assigned: true)
        raise Error, "audit identity does not match #{audit_id}" unless data["audit_id"] == audit_id
        unless data["audit_kind"] == "skill-repository" && data.key?("candidate_archives_total")
          raise Error, "audit recovery requires a skill-repository audit with a monotonic cadence total"
        end

        cadence = artifact_cadence_state
        write_artifact_cadence(cadence) unless read_artifact_cadence == cadence
        path
      end
    end

    def audits
      ensure_initialized
      learning_audits.map do |path, data|
        [data.fetch("audit_id"), data.fetch("audit_kind"), data.fetch("completed_at"), path]
      end
    end

    def artifact_audit_status(archive_threshold: ARTIFACT_AUDIT_ARCHIVE_THRESHOLD)
      ensure_initialized
      unless archive_threshold.is_a?(Integer) && archive_threshold.positive?
        raise Error, "artifact audit archive threshold must be a positive integer"
      end

      latest_path, latest = learning_audits
        .select { |_path, data| data["audit_kind"] == "skill-repository" }
        .max_by { |_path, data| data.fetch("completed_at") }
      cadence = artifact_cadence_state
      archives_since = cadence.fetch("candidate_archives_total") -
        cadence.fetch("last_completed_artifact_audit_total")
      status = {
        due: archives_since >= archive_threshold,
        archives_since: archives_since,
        archive_threshold: archive_threshold
      }
      if latest
        status[:last_audit_id] = latest.fetch("audit_id")
        status[:last_audit_path] = latest_path
      end
      status
    end

    def validate
      ensure_initialized
      errors = []
      ids = {}
      candidate_rows = []
      verification_rows = []
      verification_ids = {}

      {
        "inbox" => false,
        "archive" => true
      }.each do |area, archived|
        Dir.glob(File.join(root, "retrospectives", area, "*.md")).sort.each do |path|
          data, body = RetroState.read_document(path)
          RetroState.validate_candidate(data, body, label: path, routed: true, archived: archived)
          id = data.fetch("candidate_id")
          errors << "#{path}: filename must be #{id}.md" unless File.basename(path) == "#{id}.md"
          if ids.key?(id)
            errors << "#{path}: duplicate candidate_id also used by #{ids.fetch(id)}"
          else
            ids[id] = path
          end
          candidate_rows << [path, data]
        rescue Error => e
          errors << e.message
        end
      end

      if verification_dirs_present?
        {
          "inbox" => false,
          "archive" => true
        }.each do |area, archived|
          Dir.glob(File.join(root, "verifications", area, "*.md")).sort.each do |path|
            data, body = RetroState.read_document(path)
            RetroState.validate_verification_proposal(
              data,
              body,
              label: path,
              routed: true,
              archived: archived
            )
            id = data.fetch("verification_proposal_id")
            errors << "#{path}: filename must be #{id}.md" unless File.basename(path) == "#{id}.md"
            if verification_ids.key?(id)
              errors << "#{path}: duplicate verification_proposal_id also used by #{verification_ids.fetch(id)}"
            else
              verification_ids[id] = path
            end
            verification_rows << [path, data, archived]
          rescue Error => e
            errors << e.message
          end
        end
      end

      papercut_ids = {}
      archived_papercuts = []
      {
        "inbox" => false,
        "archive" => true
      }.each do |area, archived|
        Dir.glob(File.join(root, "papercuts", area, "*.md")).sort.each do |path|
          data, body = RetroState.read_document(path)
          RetroState.validate_papercut(data, body, label: path, routed: true, archived: archived)
          id = data.fetch("papercut_id")
          errors << "#{path}: filename must be #{id}.md" unless File.basename(path) == "#{id}.md"
          if papercut_ids.key?(id)
            errors << "#{path}: duplicate papercut_id also used by #{papercut_ids.fetch(id)}"
          else
            papercut_ids[id] = path
          end
          archived_papercuts << [path, data] if archived
        rescue Error => e
          errors << e.message
        end
      end

      archived_papercuts.each do |path, data|
        closure = data.fetch("closure")
        if closure["outcome"] == "duplicate" && !papercut_ids.key?(closure["related_papercut_id"])
          errors << "#{path}: related papercut does not exist: #{closure["related_papercut_id"]}"
        end
        if closure["outcome"] == "candidate" && !ids.key?(closure["related_candidate_id"])
          errors << "#{path}: related candidate does not exist: #{closure["related_candidate_id"]}"
        end
      end

      accepted_ids = {}
      accepted_rows = []
      Dir.glob(File.join(root, "retrospectives", "accepted", "*.md")).sort.each do |path|
        data, body = RetroState.read_document(path)
        RetroState.validate_accepted(data, body, label: path, assigned: true)
        id = data.fetch("accepted_id")
        errors << "#{path}: filename must be #{id}.md" unless File.basename(path) == "#{id}.md"
        if accepted_ids.key?(id)
          errors << "#{path}: duplicate accepted_id also used by #{accepted_ids.fetch(id)}"
        else
          accepted_ids[id] = path
        end
        data.fetch("originating_candidate_ids").each do |candidate_id|
          archive_path = candidate_path("archive", candidate_id)
          errors << "#{path}: originating candidate is not archived: #{candidate_id}" unless File.file?(archive_path)
        end
        accepted_rows << [path, data]
      rescue Error => e
        errors << e.message
      end

      candidate_rows.each do |path, data|
        supersedes_id = data["supersedes_accepted_id"]
        next unless supersedes_id

        errors << "#{path}: superseded accepted record does not exist: #{supersedes_id}" unless accepted_ids.key?(supersedes_id)
      end
      accepted_rows.each do |path, data|
        data.fetch("supersedes_accepted_ids", []).each do |superseded_id|
          errors << "#{path}: superseded accepted record does not exist: #{superseded_id}" unless accepted_ids.key?(superseded_id)
        end
      end
      verification_rows.each do |path, data, archived|
        target_id = data.fetch("target_accepted_id")
        unless accepted_ids.key?(target_id)
          errors << "#{path}: target accepted record does not exist: #{target_id}"
          next
        end
        next unless archived && data.dig("triage", "verdict") == "apply"

        target = accepted_rows.find { |_accepted_path, accepted| accepted["accepted_id"] == target_id }&.last
        unless target&.fetch("applied_verification_proposal_ids", [])&.include?(data["verification_proposal_id"])
          errors << "#{path}: applied proposal is missing from target accepted metadata"
        end
      end
      accepted_rows.each do |path, data|
        data.fetch("applied_verification_proposal_ids", []).each do |proposal_id|
          proposal_row = verification_rows.find do |_proposal_path, proposal, archived|
            archived && proposal["verification_proposal_id"] == proposal_id
          end
          unless proposal_row
            errors << "#{path}: applied verification proposal is not archived: #{proposal_id}"
            next
          end
          proposal = proposal_row.fetch(1)
          unless proposal.dig("triage", "verdict") == "apply" && proposal["target_accepted_id"] == data["accepted_id"]
            errors << "#{path}: applied verification proposal does not match target: #{proposal_id}"
          end
        end
      end

      validate_auxiliary_dir(errors, "drafts", "draft_id") do |data, body, path|
        RetroState.validate_draft(data, body, label: path, assigned: true)
      end
      validate_auxiliary_dir(errors, "ledgers", "ledger_id") do |data, body, path|
        RetroState.validate_ledger_entry(data, body, label: path, assigned: true)
      end

      accepted_rows.each do |path, data|
        residual_id = data.dig("contradiction", "residual_ledger_id")
        next unless residual_id

        residual_path = ledger_path(residual_id)
        unless File.file?(residual_path)
          errors << "#{path}: contradiction residual ledger does not exist: #{residual_id}"
          next
        end
        ledger, ledger_body = RetroState.read_document(residual_path)
        RetroState.validate_ledger_entry(ledger, ledger_body, label: residual_path, assigned: true)
        if !RetroState.contradiction_resolved?(data) && ledger["status"] != "open"
          errors << "#{path}: unresolved contradiction requires an open residual ledger: #{residual_id}"
        end
      rescue Error => e
        errors << e.message
      end

      audit_rows = []
      Dir.glob(File.join(root, "audits", "learning-process", "*.md")).sort.each do |path|
        data, body = RetroState.read_document(path)
        RetroState.validate_learning_audit(data, body, label: path, assigned: true)
        id = data.fetch("audit_id")
        errors << "#{path}: filename must be #{id}.md" unless File.basename(path) == "#{id}.md"
        audit_rows << [path, data]
      rescue Error => e
        errors << e.message
      end
      audit_rows.each do |path, data|
        data.fetch("unresolved_action_ids").each do |action_id|
          errors << "#{path}: unresolved action does not exist: #{action_id}" unless action_reference_exists?(action_id)
        end
      end

      begin
        cadence = artifact_cadence_state
        latest_total = audit_rows.map do |_path, data|
          data["candidate_archives_total"] if data["audit_kind"] == "skill-repository"
        end.compact.max
        if latest_total && cadence["last_completed_artifact_audit_total"] < latest_total
          errors << "#{artifact_cadence_path}: baseline predates the latest completed artifact audit"
        end
      rescue Error => e
        errors << e.message
      end

      raise Error, errors.join("\n") unless errors.empty?

      true
    end

    private

    def verification_detail(accepted, selected:, applied:, pending:)
      texts = {"observations" => {}, "evidence" => {}}
      references = {"observations" => {}, "evidence" => {}}
      intern = lambda do |pool, text|
        references.fetch(pool)[text] ||= begin
          reference = "#{pool}-#{texts.fetch(pool).length + 1}"
          texts.fetch(pool)[reference] = text
          reference
        end
      end
      project_fields = lambda do |fields, observation_field, observation_texts = nil|
        fields.dup.tap do |copy|
          observation = copy.delete(observation_field)
          if observation_texts
            copy["#{observation_field}_refs"] = observation_texts.map { |text| intern.call("observations", text) }
          else
            copy["#{observation_field}_ref"] = intern.call("observations", observation)
          end
          copy["decisive_evidence_refs"] = copy.delete("decisive_evidence").map { |text| intern.call("evidence", text) }
        end
      end
      applied_observations = applied.map { |record| record.fetch("frontmatter").fetch("observation") }.uniq
      project = lambda do |record|
        fields = record.fetch("frontmatter")
        observation_field = (fields["record_type"] == "accepted") ? "observed_behavior" : "observation"
        observation_texts = if observation_field == "observed_behavior"
          observation = fields.fetch(observation_field)
          (observation == applied_observations.join("\n\n")) ? applied_observations : [observation]
        end
        projected = project_fields.call(fields, observation_field, observation_texts)
        if observation_field == "observed_behavior" && fields["contradiction"]
          projected["contradiction"] = project_fields.call(fields.fetch("contradiction"), "summary")
        end
        record.merge("frontmatter" => projected)
      end
      proposals = (selected + applied + pending).uniq { |record| record.fetch("id") }
      {
        "accepted" => project.call(accepted),
        "verification_proposals" => proposals.map { |record| project.call(record) },
        "selected_verification_proposal_ids" => selected.map { |record| record.fetch("id") },
        "applied_verification_proposal_ids" => applied.map { |record| record.fetch("id") },
        "pending_verification_proposal_ids" => pending.map { |record| record.fetch("id") }
      }.merge(texts)
    end

    def verification_claim_summary(accepted, compact: false)
      applied = accepted.fetch("applied_verification_proposal_ids", []).map do |id|
        yield(id).fetch("frontmatter")
      end
      fields = %w[verification_proposal_id claim verification_basis]
      fields << "observation" unless compact
      claims_for = lambda do |state|
        claims = applied.select { |proposal| proposal["proposed_verification"] == state }.map do |proposal|
          proposal.slice(*fields)
        end
        (claims.empty? && accepted["verification"] == state) ? nil : claims
      end
      {
        "supported_claims" => claims_for.call("supported"),
        "contradicted_claims" => claims_for.call("contradicted"),
        "unverified_claims" => accepted["unverified_claims"]
      }
    end

    def validate_accepted_record(record)
      id = record.fetch("id")
      path = File.join(root, record.fetch("path"))
      raise Error, "accepted record must be in retrospectives/accepted: #{id}" unless path == accepted_path(id)

      data = record.fetch("frontmatter")
      RetroState.validate_accepted(data, record.fetch("body"), label: path, assigned: true)
      raise Error, "record identity does not match #{id}" unless data.fetch("accepted_id") == id

      record
    end

    def validate_archived_candidate_record(record)
      id = record.fetch("id")
      path = File.join(root, record.fetch("path"))
      unless path == candidate_path("archive", id)
        raise Error, "prepare-accepted requires archived candidates: #{id}"
      end
      data = record.fetch("frontmatter")
      RetroState.validate_candidate(data, record.fetch("body"), label: path, routed: true, archived: true)
      raise Error, "record identity does not match #{id}" unless data.fetch("candidate_id") == id

      data
    end

    def validate_verification_record(record)
      id = record.fetch("id")
      path = File.join(root, record.fetch("path"))
      archived = path == verification_path("archive", id)
      unless archived || path == verification_path("inbox", id)
        raise Error, "verification proposal must be in verifications/inbox or archive: #{id}"
      end
      RetroState.validate_verification_proposal(
        record.fetch("frontmatter"), record.fetch("body"), label: id, routed: true, archived: archived
      )
      unless record.dig("frontmatter", "verification_proposal_id") == id
        raise Error, "record identity does not match #{id}"
      end

      record
    end

    def validate_candidate_supersession!(candidate)
      supersedes_id = candidate["supersedes_accepted_id"]
      return unless supersedes_id
      return if File.file?(accepted_path(supersedes_id))

      raise Error, "candidate supersedes missing accepted record: #{supersedes_id}"
    end

    # Context retrieval supplies a reader to share its already validated proposal documents.
    def validate_accepted_external_references!(accepted, accepted_id: nil)
      accepted.fetch("supersedes_accepted_ids", []).each do |superseded_id|
        next if File.file?(accepted_path(superseded_id))

        raise Error, "accepted record supersedes missing accepted record: #{superseded_id}"
      end

      accepted.fetch("applied_verification_proposal_ids", []).each do |proposal_id|
        unless accepted_id
          raise Error, "new accepted records must not claim applied verification proposals"
        end
        proposal_path = verification_path("archive", proposal_id)
        unless File.file?(proposal_path)
          raise Error, "accepted record references unarchived verification proposal: #{proposal_id}"
        end
        record = block_given? ? yield(proposal_id) : validate_verification_record(show([proposal_id]).fetch("records").first)
        unless File.join(root, record.fetch("path")) == proposal_path
          raise Error, "accepted record references unarchived verification proposal: #{proposal_id}"
        end
        proposal = record.fetch("frontmatter")
        unless proposal.dig("triage", "verdict") == "apply" &&
            proposal["target_accepted_id"] == accepted_id
          raise Error, "accepted record references mismatched verification proposal: #{proposal_id}"
        end
      end

      residual_id = accepted.dig("contradiction", "residual_ledger_id")
      return unless residual_id

      residual_path = ledger_path(residual_id)
      unless File.file?(residual_path)
        raise Error, "contradiction residual ledger does not exist: #{residual_id}"
      end
      ledger, ledger_body = RetroState.read_document(residual_path)
      RetroState.validate_ledger_entry(ledger, ledger_body, label: residual_path, assigned: true)
      return if RetroState.contradiction_resolved?(accepted)
      return if ledger["status"] == "open"

      raise Error, "unresolved contradiction requires an open residual ledger: #{residual_id}"
    end

    def apply_verification_proposal!(proposal, decision)
      proposal_id = proposal.fetch("verification_proposal_id")
      accepted_pathname, current, body = read_verification_target(proposal)
      if current.fetch("applied_verification_proposal_ids", []).include?(proposal_id)
        verify_applied_proposal!(current, proposal)
        return
      end

      validate_verification_target_state!(current, proposal)
      replacement = current.dup
      replacement["observed_behavior"] = if current["verification"] == "supported" &&
          proposal["proposed_verification"] == "supported"
        [current.fetch("observed_behavior"), proposal.fetch("observation")].uniq.join("\n\n")
      else
        proposal.fetch("observation")
      end
      replacement["decisive_evidence"] = (
        current.fetch("decisive_evidence") + proposal.fetch("decisive_evidence")
      ).uniq
      replacement["verification"] = proposal.fetch("proposed_verification")
      replacement["verification_basis"] = proposal.fetch("verification_basis")
      replacement["applied_verification_proposal_ids"] = (
        current.fetch("applied_verification_proposal_ids", []) + [proposal_id]
      )
      if proposal["proposed_verification"] == "contradicted"
        replacement["contradiction"] = {
          "summary" => proposal.fetch("observation"),
          "what_is_false" => proposal.fetch("what_is_false"),
          "recorded_at" => decision.fetch("reviewed_at"),
          "decisive_evidence" => proposal.fetch("decisive_evidence")
        }
      end
      RetroState.validate_accepted(
        replacement,
        body,
        label: accepted_pathname,
        assigned: true,
        strict_contradiction: true
      )
      RetroState.validate_accepted_transition(current, replacement, proposal_id)
      replace_write(accepted_pathname, RetroState.render_document(replacement, body))
    end

    def verify_applied_proposal!(accepted, proposal)
      expected_state = proposal.fetch("proposed_verification")
      missing_evidence = proposal.fetch("decisive_evidence") - accepted.fetch("decisive_evidence")
      unless missing_evidence.empty?
        raise Error, "applied verification proposal evidence is missing from accepted state"
      end
      if expected_state == "supported"
        return if %w[supported contradicted].include?(accepted["verification"])

        raise Error, "applied supported proposal no longer matches accepted state"
      end
      unless accepted["verification"] == "contradicted"
        raise Error, "applied contradicted proposal no longer matches accepted state"
      end

      contradiction = accepted.fetch("contradiction")
      unless contradiction["what_is_false"] == proposal["what_is_false"]
        raise Error, "applied contradiction no longer matches accepted state"
      end
    end

    def validate_verification_target!(proposal)
      target = read_verification_target(proposal)
      validate_verification_target_state!(target.fetch(1), proposal)
      target
    end

    def read_verification_target(proposal)
      target_id = proposal.fetch("target_accepted_id")
      target_path = accepted_path(target_id)
      raise Error, "verification target accepted record not found: #{target_id}" unless File.file?(target_path)

      accepted, body = RetroState.read_document(target_path)
      RetroState.validate_accepted(accepted, body, label: target_path, assigned: true)
      [target_path, accepted, body]
    end

    def validate_verification_target_state!(accepted, proposal)
      unless %w[accepted implemented].include?(accepted["disposition"])
        raise Error, "verification target disposition is not accepted or implemented"
      end

      proposed_state = proposal.fetch("proposed_verification")
      current_state = accepted.fetch("verification")
      valid = if proposed_state == "supported"
        current_state == "unverified" ||
          (current_state == "supported" && proposal.key?("supplemental_reason"))
      else
        %w[unverified supported].include?(current_state)
      end
      return if valid

      if proposed_state == "supported" && current_state == "supported"
        raise Error, "verification target is already supported; add supplemental_reason only for materially useful evidence"
      end
      raise Error, "verification target state #{current_state} cannot receive proposed #{proposed_state} evidence"
    end

    def pending_verification_records
      return [] unless verification_dirs_present?

      Dir.glob(File.join(root, "verifications", "inbox", "*.md")).sort.map do |path|
        data, body = RetroState.read_document(path)
        RetroState.validate_verification_proposal(data, body, label: path, routed: true)
        [path, data]
      end
    end

    def pending_support
      pending_verification_records.map(&:last)
        .select { |proposal| proposal["proposed_verification"] == "supported" }
        .group_by { |proposal| proposal.fetch("target_accepted_id") }
    end

    def write_or_verify_archive(destination, output, record_type:)
      if File.file?(destination)
        unless File.binread(destination) == output
          raise Error, "existing #{record_type} archive differs: #{destination}"
        end
        false
      else
        exclusive_write(destination, output)
        true
      end
    end

    def verify_matching_papercut_archive(destination, intake, body, requested_closure)
      archived, archived_body = RetroState.read_document(destination)
      RetroState.validate_papercut(
        archived,
        archived_body,
        label: destination,
        routed: true,
        archived: true
      )
      archived_intake = RetroState.without_keys(archived, "closure")
      same_intake = archived_body == body && archived_intake == intake
      archived_closure = RetroState.without_keys(archived.fetch("closure"), "closed_at")
      requested = RetroState.without_keys(requested_closure, "closed_at")
      return if same_intake && archived_closure == requested

      raise Error, "existing papercut archive differs: #{destination}"
    end

    def archived_candidates
      Dir.glob(File.join(root, "retrospectives", "archive", "*.md")).sort.map do |path|
        data, body = RetroState.read_document(path)
        RetroState.validate_candidate(data, body, label: path, routed: true, archived: true)
        [path, data]
      end
    end

    def accepted_records(include_body: false)
      Dir.glob(File.join(root, "retrospectives", "accepted", "*.md")).sort.map do |path|
        data, body = RetroState.read_document(path)
        RetroState.validate_accepted(data, body, label: path, assigned: true)
        include_body ? [path, data, body] : [path, data]
      end
    end

    def learning_audits
      Dir.glob(File.join(root, "audits", "learning-process", "*.md")).sort.map do |path|
        data, body = RetroState.read_document(path)
        RetroState.validate_learning_audit(data, body, label: path, assigned: true)
        [path, data]
      end
    end

    def artifact_cadence_state
      path = artifact_cadence_path
      audits = learning_audits.select { |_audit_path, data| data["audit_kind"] == "skill-repository" }
      completed_total = audits.filter_map { |_audit_path, data| data["candidate_archives_total"] }.max
      data = read_artifact_cadence
      if data
        data["last_completed_artifact_audit_total"] = [
          data.fetch("last_completed_artifact_audit_total"), completed_total || 0
        ].max
        RetroState.validate_artifact_cadence(data, label: path)
        return data
      end

      archived = archived_candidates
      total = archived.length
      latest = audits.max_by { |_audit_path, audit| audit.fetch("completed_at") }&.last
      baseline = completed_total || latest&.fetch("candidate_archive_count", 0) || 0
      total = [total, baseline].max
      {
        "schema_version" => SCHEMA_VERSION,
        "record_type" => ARTIFACT_CADENCE_RECORD_TYPE,
        "candidate_archives_total" => total,
        "last_completed_artifact_audit_total" => baseline,
        COUNTED_CANDIDATE_IDS_FIELD => archived.map { |_path, data| data.fetch("candidate_id") }
      }
    end

    def read_artifact_cadence
      path = artifact_cadence_path
      return unless File.file?(path)

      data = YAML.safe_load(File.read(path, encoding: "UTF-8"), aliases: false)
      data = RetroState.stringify_keys(data) if data.is_a?(Hash)
      RetroState.validate_artifact_cadence(data, label: path)
      data
    rescue Psych::Exception => e
      raise Error, "#{path}: invalid YAML: #{e.message}"
    end

    def write_artifact_cadence(data)
      RetroState.validate_artifact_cadence(data, label: artifact_cadence_path)
      replace_write(artifact_cadence_path, YAML.dump(data))
    end

    # Keep the existing lock pathname so mixed helper versions still coordinate cadence writes.
    def with_state_lock
      File.open(artifact_cadence_lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        yield
      end
    end

    def operation_checkpoint(point)
      @fault_injector&.call(point)
    end

    def action_reference_open?(action_id)
      case action_id
      when /\ARC-/
        path = candidate_path("archive", action_id)
        return false unless File.file?(path)

        data, body = RetroState.read_document(path)
        RetroState.validate_candidate(data, body, label: path, routed: true, archived: true)
        data.fetch("triage").fetch("verdict") == "defer"
      when /\ASD-/
        auxiliary_status_open?(File.join(root, "drafts", "#{action_id}.md"), :draft)
      when /\ALE-/
        auxiliary_status_open?(ledger_path(action_id), :ledger)
      else
        false
      end
    end

    def action_reference_exists?(action_id)
      case action_id
      when /\ARC-/
        File.file?(candidate_path("archive", action_id))
      when /\ASD-/
        File.file?(File.join(root, "drafts", "#{action_id}.md"))
      when /\ALE-/
        File.file?(ledger_path(action_id))
      else
        false
      end
    end

    def auxiliary_status_open?(path, type)
      return false unless File.file?(path)

      data, body = RetroState.read_document(path)
      case type
      when :draft
        RetroState.validate_draft(data, body, label: path, assigned: true)
        %w[open revised].include?(data["status"])
      when :ledger
        RetroState.validate_ledger_entry(data, body, label: path, assigned: true)
        data["status"] == "open"
      end
    end

    def canonical_root(path)
      cursor = File.expand_path(path)
      suffix = []
      until File.exist?(cursor)
        raise Error, "state root contains a dangling symlink: #{path}" if File.symlink?(cursor)

        parent = File.dirname(cursor)
        break if parent == cursor

        suffix << File.basename(cursor)
        cursor = parent
      end
      File.join(File.realpath(cursor), *suffix.reverse)
    rescue Errno::ENOENT, Errno::EACCES => e
      raise Error, "could not resolve state root #{path}: #{e.message}"
    end

    def validate_papercut_reference!(closure)
      case closure["outcome"]
      when "duplicate"
        related_id = closure.fetch("related_papercut_id")
        exists = %w[inbox archive].any? { |area| File.file?(papercut_path(area, related_id)) }
        raise Error, "related papercut does not exist: #{related_id}" unless exists
      when "candidate"
        related_id = closure.fetch("related_candidate_id")
        exists = %w[inbox archive].any? { |area| File.file?(candidate_path(area, related_id)) }
        raise Error, "related candidate does not exist: #{related_id}" unless exists
      end
    end

    def record_auxiliary(input_path, record_type, directory, id_field, prefix)
      ensure_initialized
      data, body = RetroState.read_document(input_path)
      yield(data, body, input_path, false)
      unless data["record_type"] == record_type
        raise Error, "#{input_path}: record_type must be #{record_type}"
      end

      now = Time.now.utc
      id = unique_auxiliary_id(prefix, directory)
      data[id_field] = id
      data["created_at"] = now.strftime("%Y-%m-%dT%H:%M:%SZ")
      yield(data, body, input_path, true)
      destination = File.join(root, directory, "#{id}.md")
      exclusive_write(destination, RetroState.render_document(data, body))
      destination
    end

    def validate_auxiliary_dir(errors, directory, id_field)
      ids = {}
      Dir.glob(File.join(root, directory, "*.md")).sort.each do |path|
        data, body = RetroState.read_document(path)
        yield(data, body, path)
        id = data.fetch(id_field)
        errors << "#{path}: filename must be #{id}.md" unless File.basename(path) == "#{id}.md"
        if ids.key?(id)
          errors << "#{path}: duplicate #{id_field} also used by #{ids.fetch(id)}"
        else
          ids[id] = path
        end
      rescue Error => e
        errors << e.message
      end
    end

    def ensure_initialized
      raise Error, "state root is not initialized: #{root}" unless Dir.exist?(root)

      refuse_git_worktree!
      validate_version
      STATE_DIRS.each do |relative|
        path = File.join(root, relative)
        raise Error, "state directory is missing: #{path}" unless Dir.exist?(path)
      end
    end

    def verification_dirs_present?
      paths = VERIFICATION_DIRS.map { |relative| File.join(root, relative) }
      present = paths.map { |path| Dir.exist?(path) }
      return false if present.none?
      return true if present.all?

      missing = paths.zip(present).reject { |_path, exists| exists }.map(&:first)
      raise Error, "verification state directory is missing: #{missing.join(", ")}"
    end

    def ensure_verification_dirs
      VERIFICATION_DIRS.each do |relative|
        path = File.join(root, relative)
        FileUtils.mkdir_p(path, mode: 0o700)
        File.chmod(0o700, path)
      end
    end

    def validate_version
      path = File.join(root, "state-version")
      raise Error, "state-version is missing: #{path}" unless File.file?(path)
      return if File.read(path).strip == SCHEMA_VERSION.to_s

      raise Error, "unsupported state version in #{path}"
    end

    def refuse_git_worktree!
      cursor = root
      cursor = File.dirname(cursor) until File.exist?(cursor) || cursor == File.dirname(cursor)
      loop do
        marker = File.join(cursor, ".git")
        if File.file?(marker) || (File.directory?(marker) && File.file?(File.join(marker, "HEAD")))
          raise Error, "state root must not be inside a Git worktree: #{root}"
        end
        parent = File.dirname(cursor)
        break if parent == cursor

        cursor = parent
      end
    end

    def candidate_path(area, candidate_id)
      unless candidate_id.match?(/\ARC-\d{8}T\d{6}Z-[a-f0-9]{6}\z/)
        raise Error, "invalid candidate_id: #{candidate_id}"
      end

      File.join(root, "retrospectives", area, "#{candidate_id}.md")
    end

    def accepted_path(accepted_id)
      unless accepted_id.match?(/\ASCR-\d{8}-[a-f0-9]{6}\z/)
        raise Error, "invalid accepted_id: #{accepted_id}"
      end

      File.join(root, "retrospectives", "accepted", "#{accepted_id}.md")
    end

    def learning_audit_path(audit_id)
      unless audit_id.match?(/\ALA-\d{8}-[a-f0-9]{6}\z/)
        raise Error, "invalid audit_id: #{audit_id}"
      end

      File.join(root, "audits", "learning-process", "#{audit_id}.md")
    end

    def artifact_cadence_path
      File.join(root, "audits", "learning-process", "artifact-cadence.yml")
    end

    def artifact_cadence_lock_path
      File.join(root, "audits", "learning-process", "artifact-cadence.lock")
    end

    def papercut_path(area, papercut_id)
      unless papercut_id.match?(/\APC-\d{8}T\d{6}Z-[a-f0-9]{6}\z/)
        raise Error, "invalid papercut_id: #{papercut_id}"
      end

      File.join(root, "papercuts", area, "#{papercut_id}.md")
    end

    def verification_path(area, proposal_id)
      unless proposal_id.match?(/\AVP-\d{8}T\d{6}Z-[a-f0-9]{6}\z/)
        raise Error, "invalid verification_proposal_id: #{proposal_id}"
      end

      File.join(root, "verifications", area, "#{proposal_id}.md")
    end

    def ledger_path(ledger_id)
      unless ledger_id.match?(/\ALE-\d{8}-[a-f0-9]{6}\z/)
        raise Error, "invalid ledger_id: #{ledger_id}"
      end

      File.join(root, "ledgers", "#{ledger_id}.md")
    end

    def unique_papercut_id(prefix)
      100.times do
        id = "#{prefix}-#{SecureRandom.hex(3)}"
        paths = Dir.glob(File.join(root, "papercuts", "**", "#{id}.md"))
        return id if paths.empty?
      end
      raise Error, "could not allocate a unique papercut ID"
    end

    def unique_verification_id(prefix)
      100.times do
        id = "#{prefix}-#{SecureRandom.hex(3)}"
        paths = Dir.glob(File.join(root, "verifications", "**", "#{id}.md"))
        return id if paths.empty?
      end
      raise Error, "could not allocate a unique verification proposal ID"
    end

    def unique_id(prefix)
      100.times do
        id = "#{prefix}-#{SecureRandom.hex(3)}"
        paths = Dir.glob(File.join(root, "retrospectives", "**", "#{id}.md"))
        return id if paths.empty?
      end
      raise Error, "could not allocate a unique record ID"
    end

    def unique_auxiliary_id(prefix, directory)
      100.times do
        id = "#{prefix}-#{Time.now.utc.strftime("%Y%m%d")}-#{SecureRandom.hex(3)}"
        return id unless File.exist?(File.join(root, directory, "#{id}.md"))
      end
      raise Error, "could not allocate a unique #{prefix} ID"
    end

    def exclusive_write(path, content)
      with_prepared_file(path, content) { |temporary| File.link(temporary, path) }
    rescue Errno::EEXIST
      raise Error, "refusing to overwrite existing state file: #{path}"
    end

    def replace_write(path, content)
      with_prepared_file(path, content) { |temporary| File.rename(temporary, path) }
    end

    def with_prepared_file(path, content)
      temporary = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(3)}"
      created = false
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        created = true
        file.write(content)
        file.flush
        file.fsync
      end
      operation_checkpoint(:state_file_prepared)
      yield temporary
    ensure
      File.unlink(temporary) if created && File.exist?(temporary)
    end
  end

  def self_test_cli(root)
    require "open3"
    lambda do |status, *arguments, stdin: "", error: nil|
      out, err, result = Open3.capture3(
        RbConfig.ruby, File.expand_path(__FILE__), *arguments, "--root", root,
        stdin_data: stdin
      )
      raise "#{arguments.inspect}: expected exit #{status}, got #{result.exitstatus}: #{err}" unless result.exitstatus == status
      if error
        raise "#{arguments.inspect}: invalid error output" unless out.empty? && err.include?(error) && !err.include?("from ")
      else
        raise "#{arguments.inspect}: unexpected stderr: #{err}" unless err.empty?
      end
      out
    end
  end

  def inspection_self_test
    Dir.mktmpdir("retro-inspection-self-test.") do |tmp|
      root = File.join(File.realpath(tmp), "state")
      store = Store.new(root)
      store.init
      run = self_test_cli(root)
      input = File.join(tmp, "candidate.md")
      File.write(input, candidate_template)
      candidate = store.route(input)
      candidate_id = File.basename(candidate, ".md")
      papercut_data, papercut_body = parse_document(papercut_template)
      papercut = store.record_papercut(papercut_data, papercut_body, label: "inspection fixture")
      papercut_id = File.basename(papercut, ".md")
      store.close_papercut(papercut_id, outcome: "no-action", rationale: "Inspection fixture.")
      File.binwrite(File.join(root, ".kept"), "\x00a")
      File.write(File.join(root, "removed"), "old")
      outside = File.join(tmp, "outside")
      FileUtils.mkdir_p(outside)
      File.write(File.join(outside, "private"), "before")
      File.symlink(outside, File.join(root, "outside-link"))
      File.symlink(File.join(tmp, "missing"), File.join(root, "dangling"))
      before = run.call(0, "snapshot")
      snapshot_file = File.join(tmp, "before.json")
      File.write(snapshot_file, before)
      entries = JSON.parse(before).fetch("entries")
      raise "snapshot followed a directory symlink" unless entries["outside-link"] == {"kind" => "symlink", "target" => outside} && !entries.key?("outside-link/private")
      raise "snapshot missed a dangling symlink" unless entries.dig("dangling", "kind") == "symlink"
      shown = JSON.parse(run.call(0, "show", "--id", candidate_id, "--id", papercut_id)).fetch("records")
      data, body = read_document(candidate)
      raise "show lost record content" unless shown.first == {"id" => candidate_id, "path" => "retrospectives/inbox/#{candidate_id}.md", "frontmatter" => data, "body" => body}
      raise "show missed an archived record" unless shown.last.dig("frontmatter", "closure", "outcome") == "no-action"
      %w[show snapshot compare].each do |command|
        raise "missing focused help" unless run.call(0, command, "--help").include?("Usage: retro-state.rb #{command}")
      end
      run.call(2, "show", error: "missing argument: --id ID")
      run.call(2, "compare", error: "missing argument: --file PATH")
      run.call(2, "snapshot", "--file", snapshot_file, error: "--file is not valid for snapshot")
      run.call(1, "show", "--id", "../escape", error: "invalid record ID")
      run.call(1, "show", "--id", "SCR-20000101-000000", error: "record not found")
      run.call(1, "show", "--id", candidate_id, "--id", "SCR-20000101-000000", error: "record not found")
      duplicate = File.join(root, "retrospectives", "archive", "#{candidate_id}.md")
      FileUtils.cp(candidate, duplicate)
      run.call(1, "show", "--id", candidate_id, error: "record ID is ambiguous")
      File.unlink(duplicate)
      run.call(1, "compare", "--file", "-", stdin: "{", error: "invalid snapshot JSON")
      run.call(1, "compare", "--file", tmp, error: "Is a directory")
      bad = JSON.parse(before).merge("root" => tmp)
      run.call(1, "compare", "--file", "-", stdin: JSON.generate(bad), error: "this state root")
      bad = JSON.parse(before)
      bad["entries"]["../escape"] = {"kind" => "directory"}
      run.call(1, "compare", "--file", "-", stdin: JSON.generate(bad), error: "state-root-relative path")
      bad = JSON.parse(before)
      bad["entries"][".kept"]["sha256"] = "invalid"
      run.call(1, "compare", "--file", "-", stdin: JSON.generate(bad), error: "invalid snapshot entry")
      run.call(1, "compare", "--file", snapshot_file, "--allow-path", "../escape", error: "state-root-relative path")
      File.write(File.join(outside, "private"), "after")
      unchanged = JSON.parse(run.call(0, "compare", "--file", snapshot_file))
      raise "inspection wrote state or followed symlink contents" unless unchanged.fetch("unchanged") && unchanged.fetch("matches")

      File.binwrite(File.join(root, ".kept"), "\x00b")
      File.unlink(File.join(root, "removed"))
      added = ".added\nfile"
      File.write(File.join(root, added), "new")
      FileUtils.mkdir_p(File.join(root, "empty"))
      File.unlink(File.join(root, "outside-link"))
      File.symlink(File.join(tmp, "other"), File.join(root, "outside-link"))
      changed = JSON.parse(run.call(1, "compare", "--file", snapshot_file))
      raise "incorrect comparison" unless changed.fetch("added") == [added, "empty"] && changed.fetch("removed") == ["removed"] && changed.fetch("modified") == [".kept", "outside-link"] && !changed.fetch("matches") && !changed.fetch("unchanged")
      permitted = [".kept", "outside-link", "removed", added, "empty"]
      partial = JSON.parse(run.call(1, "compare", "--file", snapshot_file, "--allow-path", ".kept"))
      raise "allow-path hid unrelated changes" if partial.fetch("unexpected").include?(".kept") || partial.fetch("unexpected").empty?
      allowed = permitted.flat_map { |path| ["--allow-path", path] }
      result = JSON.parse(run.call(0, "compare", "--file", "-", *allowed, stdin: before))
      raise "allowed comparison failed" unless result.fetch("matches") && result.fetch("unexpected").empty? && !result.fetch("unchanged")

      second_id = File.basename(store.route(input), ".md")
      File.write(snapshot_file, JSON.generate(store.snapshot))
      run.call(2, "snapshot", "--allow-action", "process:#{candidate_id}", error: "--allow-action is not valid")
      {
        "process" => "expected --allow-action ACTION:ID",
        "unknown:#{papercut_id}" => "unsupported comparison action",
        "process-verification:#{papercut_id}" => "invalid verification_proposal_id",
        "process-verification:../escape" => "invalid verification_proposal_id",
        "record-accepted:#{candidate_id}" => "invalid accepted_id",
        "record-accepted:../escape" => "invalid accepted_id",
        "update-accepted:#{candidate_id}" => "invalid accepted_id",
        "update-accepted:../escape" => "invalid accepted_id",
        "process:#{papercut_id}" => "invalid candidate_id",
        "process:../escape" => "invalid candidate_id",
        "process:#{candidate_id}:extra" => "invalid candidate_id",
        "close-papercut:#{candidate_id}" => "invalid papercut_id",
        "close-papercut:../escape" => "invalid papercut_id",
        "reconsider:#{papercut_id}" => "invalid candidate_id",
        "reconsider:" => "invalid candidate_id"
      }.each do |action, error|
        run.call(1, "compare", "--file", snapshot_file, "--allow-action", action, error: error)
      end
      baseline = File.read(snapshot_file)
      run.call(0, "compare", "--file", snapshot_file, "--allow-action", "process:#{candidate_id}")
      [candidate_id, second_id].each do |id|
        decision = run.call(0, "prepare-decision", "--id", id, "--verdict", "no-change", "--rationale", "Reviewed fixture.")
        run.call(0, "process", "--id", id, "--decision", "-", stdin: decision)
        if id == candidate_id
          strict = JSON.parse(run.call(1, "compare", "--file", snapshot_file))
          unless strict.fetch("unexpected").sort == [
            "retrospectives/inbox/#{id}.md", "retrospectives/archive/#{id}.md",
            "audits/learning-process/artifact-cadence.yml", "audits/learning-process/artifact-cadence.lock"
          ].sort
            raise "process comparison did not detect fresh cadence bookkeeping"
          end
          permitted = JSON.parse(run.call(0, "compare", "--file", snapshot_file, "--allow-action", "process:#{id}"))
          raise "action allowance changed comparison semantics" unless permitted.fetch("matches") && !permitted.fetch("unchanged")
        end
      end
      actions = ["--allow-action", "process:#{candidate_id}", "--allow-action", "process:#{second_id}"]
      partial = JSON.parse(run.call(1, "compare", "--file", snapshot_file, *actions.first(2)))
      unless partial.fetch("unexpected") == ["retrospectives/archive/#{second_id}.md", "retrospectives/inbox/#{second_id}.md"]
        raise "process allowance hid another candidate's changes"
      end
      run.call(0, "compare", "--file", "-", *actions, stdin: baseline)
      File.write(File.join(root, ".kept"), "unrelated")
      unexpected = JSON.parse(run.call(1, "compare", "--file", snapshot_file, *actions))
      raise "process allowance hid unrelated state" unless unexpected.fetch("unexpected") == [".kept"]
      run.call(0, "compare", "--file", snapshot_file, *actions, "--allow-path", ".kept")
      unchanged = store.snapshot
      run.call(1, "compare", "--file", snapshot_file, *actions, "--allow-action", "invalid", error: "expected --allow-action ACTION:ID")
      raise "action comparison wrote state" unless store.snapshot == unchanged

      papercut_ids = 2.times.map do |index|
        data, body = parse_document(papercut_template)
        data["observation"] = "Comparison closure fixture #{index}."
        File.basename(store.record_papercut(data, body, label: "comparison fixture"), ".md")
      end
      deferred_id = File.basename(store.route(input), ".md")
      decision, body = parse_document(store.prepare_decision(deferred_id, "defer", rationale: "An independent observation is missing."))
      decision.merge!(self_test_deferral_fields)
      decision["reviewed_at"] = "2000-01-01T00:00:00Z"
      run.call(0, "process", "--id", deferred_id, "--decision", "-", stdin: render_document(decision, body))
      File.write(snapshot_file, JSON.generate(store.snapshot))
      papercut_ids.each do |id|
        run.call(0, "close-papercut", "--id", id, "--outcome", "no-action", "--rationale", "Reviewed comparison fixture.")
      end
      decision = store.prepare_decision(deferred_id, "no-change", rationale: "A reviewed terminal outcome.")
      run.call(0, "reconsider", "--id", deferred_id, "--decision", "-", stdin: decision)
      paths = papercut_ids.flat_map { |id| ["papercuts/inbox/#{id}.md", "papercuts/archive/#{id}.md"] }
      strict = JSON.parse(run.call(1, "compare", "--file", snapshot_file))
      unless strict.fetch("unexpected") == (paths + ["retrospectives/archive/#{deferred_id}.md"]).sort
        raise "closure and reconsideration changed unexpected bookkeeping"
      end
      actions = papercut_ids.flat_map { |id| ["--allow-action", "close-papercut:#{id}"] }
      actions += ["--allow-action", "reconsider:#{deferred_id}"]
      run.call(0, "compare", "--file", snapshot_file, *actions)
      partial = JSON.parse(run.call(1, "compare", "--file", snapshot_file, "--allow-action", "reconsider:#{deferred_id}"))
      raise "reconsideration allowance hid papercut changes" unless partial.fetch("unexpected") == paths.sort
      cadence = File.join(root, "audits/learning-process/artifact-cadence.yml")
      original = File.binread(cadence)
      File.binwrite(cadence, original + "\n")
      unexpected = JSON.parse(run.call(1, "compare", "--file", snapshot_file, *actions))
      unless unexpected.fetch("unexpected") == ["audits/learning-process/artifact-cadence.yml"]
        raise "closure or reconsideration allowance hid unrelated cadence changes"
      end
      File.binwrite(cadence, original)
      before_compare = store.snapshot
      run.call(0, "compare", "--file", snapshot_file, *actions)
      raise "closure or reconsideration comparison wrote state" unless store.snapshot == before_compare
    end
  end

  def metadata_comparison_self_test
    Dir.mktmpdir("retro-metadata-comparison-self-test.") do |tmp|
      root = File.join(File.realpath(tmp), "state")
      store = Store.new(root)
      store.init
      run = self_test_cli(root)
      input = File.join(tmp, "input.md")
      write = lambda do |text|
        File.write(input, text)
        input
      end
      snapshot_file = File.join(tmp, "before.json")
      compare = lambda do |status, *arguments, error: nil, baseline: snapshot_file|
        before = store.snapshot
        result = run.call(status, "compare", "--file", baseline, *arguments, error: error)
        raise "metadata comparison wrote state" unless store.snapshot == before
        result
      end
      origin = File.basename(store.route(write.call(candidate_template)), ".md")
      processing_snapshot = File.join(tmp, "before-processing.json")
      File.write(processing_snapshot, JSON.generate(store.snapshot))
      store.process(origin, write.call(store.prepare_decision(origin, "accept", rationale: "Comparison fixture.")))
      creation_snapshot = File.join(tmp, "before-creation.json")
      File.write(creation_snapshot, JSON.generate(store.snapshot))
      targets = 2.times.map do |index|
        data, body = parse_document(accepted_template)
        data["originating_candidate_ids"] = [origin]
        data["destination"] = "Comparison target #{index}."
        data["implementation_commits"] = ["abcdef0"]
        File.basename(store.record_accepted(write.call(render_document(data, body))), ".md")
      end
      creation_actions = targets.flat_map { |id| ["--allow-action", "record-accepted:#{id}"] }
      compare.call(0, *creation_actions, *creation_actions, baseline: creation_snapshot)
      unless JSON.parse(compare.call(1, *creation_actions.first(2), baseline: creation_snapshot)).fetch("unexpected") ==
          ["retrospectives/accepted/#{targets.last}.md"]
        raise "accepted creation allowance hid another record"
      end
      compare.call(0, *creation_actions, "--allow-action", "process:#{origin}", baseline: processing_snapshot)
      %w[artifact-cadence.lock artifact-cadence.yml].each do |name|
        relative = "audits/learning-process/#{name}"
        path = File.join(root, relative)
        original = File.binread(path)
        File.binwrite(path, original + "\n")
        unless JSON.parse(compare.call(1, *creation_actions, baseline: creation_snapshot)).fetch("unexpected") == [relative]
          raise "accepted creation allowance hid unrelated writer bookkeeping"
        end
        File.binwrite(path, original)
      end
      proposals = targets.map do |target|
        data, body = parse_document(verification_proposal_template)
        data["target_accepted_id"] = target
        File.basename(store.route_verification(write.call(render_document(data, body))), ".md")
      end
      File.write(snapshot_file, JSON.generate(store.snapshot))
      lock_relative = "audits/learning-process/artifact-cadence.lock"
      lock_path = File.join(root, lock_relative)
      operation_snapshot = File.join(tmp, "operation-before.json")
      actions = proposals.flat_map { |id| ["--allow-action", "process-verification:#{id}"] }
      compare.call(1, *actions.first(2), error: "requires a completed archived proposal")
      compare.call(1, "--allow-action", "process-verification:VP-20000101T000000Z-000000", error: "record not found")
      proposals.zip(%w[apply reject]).each do |id, verdict|
        File.unlink(lock_path)
        File.write(operation_snapshot, JSON.generate(store.snapshot))
        decision = store.prepare_decision(id, verdict, rationale: "Reviewed comparison fixture.")
        run.call(0, "process-verification", "--id", id, "--decision", "-", stdin: decision)
        result = JSON.parse(compare.call(0, "--allow-action", "process-verification:#{id}", baseline: operation_snapshot))
        unless result.fetch("added").include?(lock_relative)
          raise "verification #{verdict} comparison did not cover writer lock creation"
        end
      end
      proposal_paths = proposals.map { |id| ["verifications/inbox/#{id}.md", "verifications/archive/#{id}.md"] }
      applied_target_path = "retrospectives/accepted/#{targets.first}.md"
      rejected_target_path = "retrospectives/accepted/#{targets.last}.md"
      strict = JSON.parse(compare.call(1))
      unless strict.fetch("unexpected") == (proposal_paths.flatten + [applied_target_path]).sort
        raise "verification processing changed unexpected paths"
      end
      compare.call(0, *actions)
      unless JSON.parse(compare.call(1, *actions.first(2))).fetch("unexpected") == proposal_paths.last.sort &&
          JSON.parse(compare.call(1, *actions.last(2))).fetch("unexpected") == (proposal_paths.first + [applied_target_path]).sort
        raise "verification allowance hid another proposal or target"
      end
      prepared = run.call(0, "prepare-accepted-update", "--id", targets.last,
        "--commit", "BCDEF12", "--destination", "Reviewed comparison destination.")
      File.unlink(lock_path)
      File.write(operation_snapshot, JSON.generate(store.snapshot))
      run.call(0, "update-accepted", "--id", targets.last, "--file", "-", stdin: prepared)
      update_action = ["--allow-action", "update-accepted:#{targets.last}"]
      unless JSON.parse(compare.call(0, *update_action, baseline: operation_snapshot)).fetch("added").include?(lock_relative)
        raise "accepted update comparison did not cover writer lock creation"
      end
      unless JSON.parse(compare.call(1, *actions)).fetch("unexpected") == [rejected_target_path]
        raise "rejected verification allowance hid accepted-record changes"
      end
      compare.call(0, *actions, *update_action)
      unless JSON.parse(compare.call(1, *update_action)).fetch("unexpected") == strict.fetch("unexpected")
        raise "accepted update allowance hid unrelated record changes"
      end
      cadence = File.join(root, "audits/learning-process/artifact-cadence.yml")
      original_cadence = File.binread(cadence)
      File.binwrite(cadence, original_cadence + "\n")
      unless JSON.parse(compare.call(1, *actions, *update_action)).fetch("unexpected") == ["audits/learning-process/artifact-cadence.yml"]
        raise "metadata allowance hid unrelated cadence changes"
      end
      compare.call(0, *actions, *update_action, "--allow-path", "audits/learning-process/artifact-cadence.yml")
      File.binwrite(cadence, original_cadence)

      archive = File.join(root, proposal_paths.first.last)
      original = File.binread(archive)
      File.binwrite(archive, "---\ninvalid: [\n---\n")
      compare.call(1, *actions, error: "invalid YAML frontmatter")
      data, body = parse_document(original)
      File.write(archive, render_document(without_keys(data, "triage"), body))
      compare.call(1, *actions, error: "missing triage mapping")
      data["target_accepted_id"] = targets.last
      File.write(archive, render_document(data, body))
      compare.call(1, *actions, error: "intake fields changed after routing")
      File.binwrite(archive, original)
      duplicate = File.join(root, proposal_paths.first.first)
      FileUtils.cp(archive, duplicate)
      compare.call(1, *actions, error: "record ID is ambiguous")
      File.unlink(duplicate)

      target = File.join(root, applied_target_path)
      original_target = File.binread(target)
      File.rename(target, "#{target}.hidden")
      compare.call(1, *actions, error: "record not found")
      File.rename("#{target}.hidden", target)
      duplicate = File.join(root, "retrospectives/inbox/#{targets.first}.md")
      FileUtils.cp(target, duplicate)
      compare.call(1, *actions, error: "record ID is ambiguous")
      File.unlink(duplicate)
      data, body = parse_document(original_target)
      data["accepted_id"] = targets.last
      File.write(target, render_document(data, body))
      compare.call(1, *actions, error: "record identity does not match")
      File.binwrite(target, original_target)
      compare.call(0, *actions, *update_action)
      store.validate
    end
  end

  def verification_context_self_test
    Dir.mktmpdir("retro-verification-context-self-test.") do |tmp|
      root = File.join(File.realpath(tmp), "state")
      store = Store.new(root)
      store.init
      run = self_test_cli(root)
      input = File.join(tmp, "input.md")
      write = lambda do |data, body|
        File.write(input, render_document(data, body))
        input
      end
      decide = lambda do |id, verdict|
        data, body = parse_document(store.prepare_decision(id, verdict))
        data["rationale"] = "Disposable context fixture."
        write.call(data, body)
      end

      candidate, body = parse_document(candidate_template)
      candidate["title"] = "Queue\ncandidate\tfixture"
      candidate_path = store.route(write.call(candidate, body))
      candidate_id = File.basename(candidate_path, ".md")
      papercut, body = parse_document(papercut_template)
      papercut_path = store.record_papercut(papercut, body, label: "context fixture")
      papercut_id = File.basename(papercut_path, ".md")
      before = store.snapshot
      rows = run.call(0, "review-queue").lines.map { |line| line.chomp.split("\t") }
      unless rows.map { |row| row.first(2) } == [["candidate", candidate_id], ["papercut", papercut_id]] &&
          rows.all? { |row| row.length == 4 }
        raise "review queue did not expose complete, stable intake rows"
      end
      raise "review queue wrote state" unless store.snapshot == before
      store.process(candidate_id, decide.call(candidate_id, "no-change"))
      store.close_papercut(papercut_id, outcome: "no-action", rationale: "Fixture closed.")
      raise "review queue retained closed intake" unless run.call(0, "review-queue").empty?

      create_accepted = lambda do |destination, disposition = "implemented", verification = "unverified", unverified_claims = nil|
        File.write(input, candidate_template)
        candidate_id = File.basename(store.route(input), ".md")
        store.process(candidate_id, decide.call(candidate_id, "accept"))
        data, body = parse_document(accepted_template)
        data["originating_candidate_ids"] = [candidate_id]
        data["destination"] = destination
        data["expected_behavior"] = "Exact [#{destination}] outcome."
        data["verification_opportunity"] = "Check #{destination} in a later task."
        data["implementation_commits"] = [Digest::SHA256.hexdigest(destination)[0, 40]]
        data["disposition"] = disposition
        data["verification"] = verification
        data["verification_basis"] = (verification == "unverified") ? "none" : "later-session"
        data["unverified_claims"] = unverified_claims unless unverified_claims.nil?
        body += "\nBody-only fixture [#{destination}].\n"
        File.basename(store.record_accepted(write.call(data, body)), ".md")
      end
      unverified_id = create_accepted.call("Shared domain first")
      remaining_claims = ["Ordinary later-use effectiveness.", "Comparative improvement."]
      supported_id = create_accepted.call("Other domain second", "implemented", "unverified", remaining_claims)
      retired_id = create_accepted.call("Shared domain retired", "reverted")
      legacy_id = create_accepted.call("Shared domain legacy", "accepted", "supported")
      propose = lambda do |id, state = "supported", supplemental = false, claim = "intended-outcome", basis = "later-session"|
        data, body = parse_document(verification_proposal_template)
        data["target_accepted_id"] = id
        data["proposed_verification"] = state
        data["claim"] = claim
        data["verification_basis"] = basis
        data["observation"] = "#{claim} #{state} fixture scope for #{id}."
        data["decisive_evidence"] = ["Shared context evidence.", "Distinct #{id} #{state} evidence."]
        data["decisive_evidence"] << "Shared context evidence!" if supplemental
        data["opportunity_match"] = "Only this #{claim} fixture scope is exercised; comparative improvement is unverified."
        data["contradiction"] = "Unrelated proposal metadata must remain unchanged."
        body += "\nBody-only limit: caller recovery is untested.\n"
        data["what_is_false"] = "Fixture assertion failed." if state == "contradicted"
        data["supplemental_reason"] = "A distinct fixture boundary." if supplemental
        File.basename(store.route_verification(write.call(data, body)), ".md")
      end
      applied_id = propose.call(supported_id)
      store.process_verification(applied_id, decide.call(applied_id, "apply"))
      supplemental_id = propose.call(supported_id, "supported", true, "executable-correctness", "deterministic-test")
      store.process_verification(supplemental_id, decide.call(supplemental_id, "apply"))
      pending_ids = [propose.call(supported_id, "supported", true), propose.call(supported_id, "contradicted")]
      rejected_id = propose.call(supported_id, "supported", true)
      store.process_verification(rejected_id, decide.call(rejected_id, "reject"))
      propose.call(unverified_id)
      contradicted_id = create_accepted.call("Contested claim fixture", "implemented", "unverified", [])
      positive_id = propose.call(contradicted_id)
      store.process_verification(positive_id, decide.call(positive_id, "apply"))
      negative_id = propose.call(contradicted_id, "contradicted")
      store.process_verification(negative_id, decide.call(negative_id, "apply"))
      before = store.snapshot
      accepted = store.show([unverified_id, supported_id]).fetch("records")
      origin = accepted.first.fetch("frontmatter").fetch("originating_candidate_ids").first
      commit = accepted.last.fetch("frontmatter").fetch("implementation_commits").first
      lookup = lambda do |*arguments|
        run.call(0, "accepted-records", *arguments).lines.map { |line| line.split("\t").first }
      end
      {
        origin.upcase => unverified_id,
        commit.upcase => supported_id,
        retired_id => retired_id,
        "BODY-ONLY fixture [Shared domain retired]" => retired_id
      }.each do |text, id|
        raise "accepted identity, provenance, or body lookup missed #{id}" unless lookup.call("--text", text) == [id]
      end
      lookup_destinations = ["--destination", "SHARED", "--destination", "other", "--destination", "shared"]
      unless lookup.call(*lookup_destinations) == [unverified_id, supported_id, retired_id, legacy_id].sort
        raise "multi-destination identity lookup lost states, dispositions, order, or deduplication"
      end
      lookup_texts = ["--text", origin, "--text", commit, "--text", "Body-only fixture [Shared domain retired]", "--text", origin.upcase]
      unless lookup.call(*lookup_texts) == [unverified_id, supported_id, retired_id].sort &&
          lookup.call(*lookup_texts, "--destination", "other") == [supported_id] &&
          lookup.call(*lookup_texts, *lookup_destinations, "--active-supported") == [supported_id]
        raise "multi-text identity lookup failed OR matching, group intersection, deduplication, or supported filtering"
      end
      unless lookup.call("--destination", "shared", "--text", "Other domain second").empty? &&
          lookup.call("--text", ".*").empty?
        raise "accepted identity lookup ignored destination scope or literal matching"
      end
      run.call(1, "accepted-records", "--text", "", error: "filters must not be blank")
      run.call(1, "accepted-records", "--destination", " ", error: "filters must not be blank")
      run.call(1, "accepted-records", *lookup_texts, "--destination", "", error: "filters must not be blank")
      run.call(1, "accepted-records", *lookup_destinations, "--text", " ", error: "filters must not be blank")
      query = ["verification-context", "--destination", "SHARED", "--destination", "other", "--destination", "shared"]
      first = JSON.parse(run.call(0, *query, "--limit", "1"))
      ids = first.fetch("records").map { |record| record.fetch("id") }
      offset = first.fetch("next_offset")
      while offset
        page = JSON.parse(run.call(0, *query, "--limit", "1", "--offset", offset.to_s))
        ids.concat(page.fetch("records").map { |record| record.fetch("id") })
        offset = page.fetch("next_offset")
      end
      unless first.fetch("total") == 3 && ids == [unverified_id, supported_id, legacy_id].sort
        raise "verification discovery lost, duplicated, or reordered active outcomes"
      end
      all = JSON.parse(run.call(0, *query))
      summary = all.fetch("records").find { |record| record["id"] == supported_id }
      legacy_summary = all.fetch("records").find { |record| record["id"] == legacy_id }
      unless all.fetch("limit") == 20 && all.fetch("next_offset").nil? &&
          summary.fetch("verification") == "supported" &&
          summary.fetch("expected_behavior") == "Exact [Other domain second] outcome." &&
          summary.fetch("verification_opportunity") == "Check Other domain second in a later task." &&
          summary.fetch("applied_verification_proposal_ids") == [applied_id, supplemental_id] &&
          legacy_summary.fetch("applied_verification_proposal_ids").empty? &&
          summary.fetch("pending_verification_proposals").map { |proposal| proposal.fetch("verification_proposal_id") }.sort == pending_ids.sort
        raise "verification discovery omitted evidence context or pagination limits"
      end
      supported_claims = summary.fetch("supported_claims")
      unless supported_claims.map { |claim| claim.fetch("verification_proposal_id") } == [applied_id, supplemental_id] &&
          supported_claims.map { |claim| claim.fetch("claim") } == %w[intended-outcome executable-correctness] &&
          supported_claims.map { |claim| claim.fetch("verification_basis") } == %w[later-session deterministic-test] &&
          supported_claims.all? { |claim| claim.fetch("observation").include?("fixture scope") } &&
          summary.fetch("unverified_claims") == remaining_claims && summary.fetch("contradicted_claims").empty?
        raise "verification discovery conflated partial support, pending evidence, or remaining claim scopes"
      end
      unverified_summary = all.fetch("records").find { |record| record["id"] == unverified_id }
      unless legacy_summary.fetch("supported_claims").nil? && legacy_summary.fetch("unverified_claims").nil? &&
          unverified_summary.fetch("supported_claims").empty? && unverified_summary.fetch("unverified_claims").nil?
        raise "verification discovery invented legacy support or inferred remaining claims"
      end
      filtered_query = query + ["--text", "[SHARED domain FIRST]", "--text", "check OTHER domain second", "--text", "[SHARED domain FIRST]"]
      filtered = JSON.parse(run.call(0, *filtered_query, "--limit", "1", "--compact"))
      filtered_last = JSON.parse(run.call(0, *filtered_query, "--limit", "1", "--offset", "1", "--compact"))
      filtered_ids = [filtered, filtered_last].flat_map { |page| page.fetch("records").map { |record| record.fetch("id") } }
      unless filtered.fetch("total") == 2 && filtered.fetch("next_offset") == 1 &&
          filtered_last.fetch("next_offset").nil? && filtered_ids == [unverified_id, supported_id].sort &&
          filtered.fetch("texts").length == 2
        raise "text filtering failed OR matching, deduplication, case folding, or filtering before pagination"
      end
      compact = JSON.parse(run.call(0, *query, "--compact"))
      compact_fields = %w[id verification verification_basis supported_claims contradicted_claims unverified_claims]
      compact_claim_fields = %w[verification_proposal_id claim verification_basis]
      expected_compact = all.fetch("records").map do |record|
        record.slice(*compact_fields).tap do |summary|
          %w[supported_claims contradicted_claims].each do |field|
            summary[field] = summary[field]&.map { |claim| claim.slice(*compact_claim_fields) }
          end
        end
      end
      unless without_keys(compact, "records") == without_keys(all, "records") &&
          compact.fetch("records") == expected_compact &&
          compact.fetch("records").all? { |record| record.keys.sort == compact_fields.sort }
        raise "compact discovery changed coverage or omitted its decision fields"
      end
      compact_support = compact.fetch("records").find { |record| record["id"] == supported_id }.fetch("supported_claims")
      unless compact_support.all? { |claim| claim.keys.sort == compact_claim_fields.sort }
        raise "compact discovery retained prose or lost claim identity, type, or basis"
      end
      [[], ["--compact"]].each do |mode|
        contested = JSON.parse(run.call(0, "verification-context", "--destination", "Contested claim", *mode))
          .fetch("records").fetch(0)
        unless contested.fetch("verification") == "contradicted" &&
            contested.fetch("supported_claims").map { |claim| claim.fetch("verification_proposal_id") } == [positive_id] &&
            contested.fetch("contradicted_claims").map { |claim| claim.fetch("verification_proposal_id") } == [negative_id] &&
            contested.fetch("unverified_claims") == []
          raise "verification discovery hid contradictory evidence or conflated absent and empty remaining claims"
        end
        unless %w[supported_claims contradicted_claims].all? do |field|
          contested.fetch(field).all? { |claim| claim.key?("observation") == mode.empty? }
        end
          raise "verification claim prose did not follow the compact versus expanded boundary"
        end
      end
      [
        ["--destination", "shared", "--text", "Other domain second"],
        ["--destination", "shared", "--text", ".*"],
        ["--destination", "shared", "--text", "[Shared domain retired]"]
      ].each do |filters|
        result = JSON.parse(run.call(0, "verification-context", *filters))
        unless result.fetch("total").zero? && result.fetch("records").empty? && result.fetch("next_offset").nil?
          raise "text filtering ignored the destination, literal matching, or active disposition boundary"
        end
      end
      empty = JSON.parse(run.call(0, "verification-context", "--destination", "unrelated"))
      past_end = JSON.parse(run.call(0, *query, "--offset", "99"))
      unless empty.fetch("total").zero? && empty.fetch("records").empty? &&
          past_end.fetch("records").empty? && past_end.fetch("next_offset").nil?
        raise "empty verification discovery reported misleading coverage"
      end
      detail = JSON.parse(run.call(0, "verification-context", "--id", supported_id, "--id", unverified_id, "--id", supported_id))
      records = detail.fetch("records")
      applied = records.first.fetch("verification_proposals")
        .select { |proposal| records.first.fetch("applied_verification_proposal_ids").include?(proposal.fetch("id")) }
      unless records.map { |record| record.dig("accepted", "id") } == [supported_id, unverified_id] &&
          applied.first.fetch("id") == applied_id && applied.first.dig("frontmatter", "claim") == "intended-outcome" &&
          !applied.first.fetch("body").empty? &&
          records.first.fetch("pending_verification_proposal_ids").sort == pending_ids.sort
        raise "verification details lost selected order, claim, original evidence, or pending proposals"
      end
      unless records.first.fetch("supported_claims") == supported_claims.map { |claim| claim.slice(*compact_claim_fields) } &&
          records.first.fetch("unverified_claims") == remaining_claims
        raise "verification detail and discovery disagree about claim scope"
      end
      historical = JSON.parse(run.call(0, "verification-context", "--id", retired_id, "--id", legacy_id))
      unless historical.fetch("records").first.dig("accepted", "frontmatter", "disposition") == "reverted" &&
          historical.fetch("records").last.fetch("applied_verification_proposal_ids").empty?
        raise "verification detail hid historical or legacy evidence limits"
      end
      queue_id = run.call(0, "review-queue").lines.map { |line| line.split("\t") }
        .find { |row| row.first == "verification-proposal" && pending_ids.include?(row[1]) }.fetch(1)
      queued = JSON.parse(run.call(0, "verification-context", "--id", queue_id)).fetch("records")
      unless queued.one? && queued.first.dig("accepted", "id") == supported_id &&
          queued.first.fetch("pending_verification_proposal_ids").include?(queue_id)
        raise "verification context could not consume a queue proposal ID directly"
      end
      mixed = JSON.parse(run.call(0, "verification-context", "--id", queue_id, "--id", unverified_id,
        "--id", supported_id, "--id", applied_id, "--id", rejected_id, "--id", queue_id)).fetch("records")
      unless mixed.map { |record| record.dig("accepted", "id") } == [supported_id, unverified_id] &&
          mixed.first.fetch("selected_verification_proposal_ids") == [queue_id, applied_id, rejected_id] &&
          mixed.first.fetch("verification_proposals").find { |record| record.fetch("id") == rejected_id }.dig("frontmatter", "triage", "verdict") == "reject"
        raise "mixed verification IDs lost order, deduplication, or selected archived evidence"
      end
      restore_fields = lambda do |context, fields, observation_field|
        fields.dup.tap do |copy|
          references = copy.delete("#{observation_field}_refs")
          copy[observation_field] = if references
            references.map { |reference| context.fetch("observations").fetch(reference) }.join("\n\n")
          else
            context.fetch("observations").fetch(copy.delete("#{observation_field}_ref"))
          end
          copy["decisive_evidence"] = copy.delete("decisive_evidence_refs")
            .map { |reference| context.fetch("evidence").fetch(reference) }
        end
      end
      [*records, *mixed, *historical.fetch("records"),
        *JSON.parse(run.call(0, "verification-context", "--id", contradicted_id)).fetch("records")].each do |context|
        proposals = context.fetch("verification_proposals")
        ids = proposals.map { |record| record.fetch("id") }
        roles = %w[selected applied pending].map { |role| context.fetch("#{role}_verification_proposal_ids") }
        unless ids == roles.flatten.uniq && ids.uniq == ids
          raise "expanded verification context repeated a proposal or lost its role"
        end
        %w[observations evidence].each do |pool|
          texts = context.fetch(pool).values
          raise "expanded verification context repeated exact text" unless texts.uniq == texts
        end
        [context.fetch("accepted"), *proposals].each do |record|
          fields = record.fetch("frontmatter")
          field = (fields["record_type"] == "accepted") ? "observed_behavior" : "observation"
          restored = restore_fields.call(context, fields, field)
          if field == "observed_behavior" && fields["contradiction"]
            restored["contradiction"] = restore_fields.call(context, fields.fetch("contradiction"), "summary")
          end
          original = store.show([record.fetch("id")]).fetch("records").first
          unless record.merge("frontmatter" => restored) == original
            raise "expanded context lost source evidence, opportunity match, triage rationale, body limits, or provenance"
          end
        end
      end
      normalized = records.first
      unless normalized.fetch("evidence").values.count("Shared context evidence.") == 1 &&
          normalized.fetch("evidence").value?("Shared context evidence!") &&
          normalized.fetch("accepted").fetch("frontmatter").fetch("observed_behavior_refs").length == 2 &&
          normalized.fetch("observations").length == 3
        raise "expanded deduplication merged distinct evidence or repeated the accepted observation rollup"
      end
      read_counts = Hash.new(0)
      original_reader = method(:read_document)
      define_singleton_method(:read_document) do |path|
        read_counts[path] += 1
        original_reader.call(path)
      end
      begin
        2.times do |index|
          store.verification_context(record_ids: [queue_id, supported_id, applied_id, rejected_id])
          unless !read_counts.empty? && read_counts.values.all? { |count| count == index + 1 }
            raise "verification context reread documents within a call or retained documents between calls"
          end
        end
        read_counts.clear
        store.verification_context(destinations: ["Other domain second"], compact: true)
        unless !read_counts.empty? && read_counts.values.all? { |count| count == 1 }
          raise "compact discovery reread accepted or applied proposal documents"
        end
      ensure
        define_singleton_method(:read_document, original_reader)
      end
      %w[review-queue verification-context].each do |command|
        raise "missing context help" unless run.call(0, command, "--help").include?("Usage: retro-state.rb #{command}")
      end
      run.call(2, "verification-context", error: "choose --destination TEXT or --id ID")
      run.call(2, *query, "--id", supported_id, error: "choose --destination TEXT or --id ID")
      run.call(2, "verification-context", "--destination", " ", error: "--destination must not be blank")
      run.call(2, *query, "--text", " ", error: "--text must not be blank")
      run.call(2, *query, "--limit", "0", error: "--limit must be positive")
      run.call(2, *query, "--offset", "-1", error: "--offset must be nonnegative")
      run.call(2, *query, "--limit", "bad", error: "invalid argument")
      run.call(2, "verification-context", "--id", supported_id, "--limit", "1", error: "apply only to destination discovery")
      run.call(2, "verification-context", "--id", supported_id, "--text", "outcome", error: "apply only to destination discovery")
      run.call(2, "verification-context", "--id", supported_id, "--compact", error: "apply only to destination discovery")
      run.call(2, "accepted-records", "--destination", "shared", "--compact", error: "--compact is not valid")
      run.call(2, "review-queue", "--limit", "1", error: "--limit is not valid")
      run.call(1, "verification-context", "--id", "../escape", error: "invalid record ID")
      run.call(1, "verification-context", "--id", candidate_id, error: "invalid accepted_id")
      run.call(1, "verification-context", "--id", supported_id, "--id", "SCR-20000101-000000", error: "record not found")
      raise "context retrieval wrote state" unless store.snapshot == before

      ["not-an-array", [nil], [""], [" "], ["duplicate", "duplicate"]].each do |claims|
        data, body = parse_document(store.prepare_accepted_update(supported_id))
        data["unverified_claims"] = claims
        run.call(1, "update-accepted", "--id", supported_id, "--file", write.call(data, body), error: "unverified_claims")
      end
      raise "invalid remaining-claim metadata wrote state" unless store.snapshot == before

      path = File.join(root, "retrospectives", "accepted", "#{supported_id}.md")
      original = File.read(path)
      File.write(path, "---\ninvalid: [\n---\n")
      run.call(1, "verification-context", "--id", supported_id, error: "invalid YAML frontmatter")
      File.write(path, original)
      data, body = read_document(path)
      data["applied_verification_proposal_ids"] = ["VP-20000101T000000Z-000000"]
      File.write(path, render_document(data, body))
      run.call(1, "verification-context", "--id", supported_id, error: "unarchived verification proposal")
      run.call(1, "verification-context", "--destination", "Other domain second", "--compact", error: "unarchived verification proposal")
      File.write(path, original)
      proposal_path = File.join(root, "verifications", "archive", "#{applied_id}.md")
      proposal_original = File.read(proposal_path)
      proposal, body = read_document(proposal_path)
      proposal["target_accepted_id"] = unverified_id
      proposal["intake_digest"] = Digest::SHA256.hexdigest(render_document(without_keys(proposal, "intake_digest", "triage"), body))
      File.write(proposal_path, render_document(proposal, body))
      run.call(1, "verification-context", "--id", supported_id, error: "mismatched verification proposal")
      run.call(1, "verification-context", "--destination", "Other domain second", error: "mismatched verification proposal")
      run.call(1, "verification-context", "--id", supported_id, "--id", applied_id, error: "mismatched verification proposal")
      run.call(1, "verification-context", "--id", applied_id, error: "does not reference applied proposal")
      File.write(proposal_path, proposal_original)
      File.write(proposal_path, proposal_original.sub("Distinct", "Tampered"))
      run.call(1, "verification-context", "--destination", "Other domain second", "--compact", error: "intake fields changed after routing")
      File.write(proposal_path, proposal_original)
      false_id = "VP-20000101T000000Z-000000"
      false_path = File.join(root, "verifications", "archive", "#{false_id}.md")
      File.rename(proposal_path, false_path)
      data, body = parse_document(original)
      data["applied_verification_proposal_ids"] = [false_id]
      File.write(path, render_document(data, body))
      mismatched = store.snapshot
      run.call(1, "verification-context", "--id", supported_id, error: "record identity does not match")
      File.write(input, run.call(0, "prepare-accepted-update", "--id", supported_id))
      run.call(1, "update-accepted", "--id", supported_id, "--file", input, error: "record identity does not match")
      raise "mismatched proposal refusal wrote state" unless store.snapshot == mismatched
      File.rename(false_path, proposal_path)
      File.write(path, original)
      pending_path = File.join(root, "verifications", "inbox", "#{queue_id}.md")
      pending_original = File.read(pending_path)
      false_pending_path = File.join(root, "verifications", "inbox", "#{false_id}.md")
      File.rename(pending_path, false_pending_path)
      run.call(1, "verification-context", "--id", supported_id, error: "record identity does not match")
      File.rename(false_pending_path, pending_path)
      File.write(pending_path, pending_original.sub("Distinct", "Tampered"))
      run.call(1, "verification-context", "--id", supported_id, "--id", queue_id, error: "intake fields changed after routing")
      File.write(pending_path, pending_original)
      File.rename(path, "#{path}.hidden")
      run.call(1, "verification-context", "--id", queue_id, error: "record not found")
      File.rename("#{path}.hidden", path)
      raise "failed context retrieval wrote state" unless store.snapshot == before
      store.validate
    end
  end

  def verification_evidence_curation_self_test
    Dir.mktmpdir("retro-evidence-curation-self-test.") do |tmp|
      root = File.join(File.realpath(tmp), "state")
      store = Store.new(root)
      store.init
      run = self_test_cli(root)
      input = File.join(tmp, "input.md")
      write = lambda do |data, body|
        File.write(input, render_document(data, body))
        input
      end
      File.write(input, candidate_template)
      candidate_id = File.basename(store.route(input), ".md")
      File.write(input, store.prepare_decision(candidate_id, "accept", rationale: "Disposable curation fixture."))
      store.process(candidate_id, input)

      implementation_evidence = "The profiling implementation passed its static checks."
      overlapping_summaries = [
        "The smoke recovered every native sample using retained debug information.",
        "Recovery preserved the measured inputs and did not acquire another profile."
      ]
      remaining_claims = ["Ordinary later-use effectiveness.", "Comparative improvement."]
      data, body = parse_document(accepted_template)
      data["originating_candidate_ids"] = [candidate_id]
      data["disposition"] = "implemented"
      data["implementation_commits"] = ["a" * 40]
      data["decisive_evidence"] = [implementation_evidence, *overlapping_summaries]
      data["unverified_claims"] = remaining_claims
      accepted_id = File.basename(store.record_accepted(write.call(data, body)), ".md")

      data, body = parse_document(verification_proposal_template)
      data["target_accepted_id"] = accepted_id
      data["claim"] = "executable-correctness"
      data["verification_basis"] = "deterministic-test"
      data["observation"] = "The prompted smoke recovered native source locations; caller recovery was untested."
      data["opportunity_match"] = "Only the capture and recovery mechanics witness was exercised."
      proposal_evidence = [
        "The smoke captured 19 samples; all 7 native samples resolved using matching debug information.",
        "Capture and binary hashes stayed identical before and after source recovery.",
        "No profiling reacquisition was used; later use and comparative benefit remain unverified."
      ]
      data["decisive_evidence"] = proposal_evidence
      body += "\nCaller stacks, inclusive costs, and allocation behavior were not tested.\n"
      proposal_id = File.basename(store.route_verification(write.call(data, body)), ".md")
      File.write(input, store.prepare_decision(proposal_id, "apply", rationale: "Support only the tested mechanics."))
      store.process_verification(proposal_id, input)

      original = store.show([accepted_id]).fetch("records").first
      original_proposal = store.show([proposal_id]).fetch("records").first
      context = JSON.parse(run.call(0, "verification-context", "--id", accepted_id)).fetch("records").first
      unless (overlapping_summaries - context.fetch("evidence").values).empty?
        raise "verification context silently inferred semantic evidence equivalence"
      end
      snapshot = File.join(tmp, "before.json")
      File.write(snapshot, JSON.generate(store.snapshot))
      File.write(input, run.call(0, "prepare-accepted-update", "--id", accepted_id))
      replacement, body = read_document(input)
      replacement["decisive_evidence"] -= overlapping_summaries
      run.call(0, "update-accepted", "--id", accepted_id, "--file", write.call(replacement, body))

      curated = store.show([accepted_id]).fetch("records").first
      unless curated == original.merge("frontmatter" => original.fetch("frontmatter").merge(
          "decisive_evidence" => [implementation_evidence, *proposal_evidence]
        )) && store.show([proposal_id]).fetch("records").first == original_proposal
        raise "evidence curation changed identity, claim limits, opportunity, proposal provenance, or triage"
      end
      comparison = JSON.parse(run.call(0, "compare", "--file", snapshot, "--allow-action", "update-accepted:#{accepted_id}"))
      raise "evidence curation changed unrelated state" unless comparison.fetch("matches")

      before = store.snapshot
      detail = JSON.parse(run.call(0, "verification-context", "--id", accepted_id)).fetch("records").first
      proposal = detail.fetch("verification_proposals").fetch(0)
      accepted_refs = detail.fetch("accepted").fetch("frontmatter").fetch("decisive_evidence_refs")
      proposal_refs = proposal.fetch("frontmatter").fetch("decisive_evidence_refs")
      unless detail.fetch("evidence").values == [implementation_evidence, *proposal_evidence] &&
          accepted_refs.drop(1) == proposal_refs &&
          detail.fetch("applied_verification_proposal_ids") == [proposal_id] &&
          detail.fetch("unverified_claims") == remaining_claims &&
          detail.fetch("supported_claims") == context.fetch("supported_claims") &&
          detail.fetch("observations") == context.fetch("observations") &&
          proposal == context.fetch("verification_proposals").first.merge("frontmatter" =>
            context.fetch("verification_proposals").first.fetch("frontmatter").merge("decisive_evidence_refs" => proposal_refs))
        raise "curated expanded evidence repeated summaries or lost shared references, provenance, or claim limits"
      end
      raise "curated context retrieval wrote state" unless store.snapshot == before
      store.validate
    end
  end

  def verification_preparation_self_test
    Dir.mktmpdir("retro-verification-preparation-self-test.") do |tmp|
      root = File.join(File.realpath(tmp), "state")
      store = Store.new(root)
      store.init
      run = self_test_cli(root)
      input = File.join(tmp, "input.md")
      write = ->(text) {
        File.write(input, text)
        input
      }
      origin = File.basename(store.route(write.call(candidate_template)), ".md")
      store.process(origin, write.call(store.prepare_decision(origin, "accept", rationale: "Preparation fixture.")))
      targets = 2.times.map do |index|
        data, body = parse_document(accepted_template)
        data["originating_candidate_ids"] = [origin]
        data["verification_opportunity"] = "Exercise preparation target #{index}."
        File.basename(store.record_accepted(write.call(render_document(data, body))), ".md")
      end
      prepare = lambda do |status, *arguments, error: nil|
        before = store.snapshot
        result = run.call(status, "prepare-verification", *arguments, error: error)
        raise "verification preparation wrote state" unless store.snapshot == before
        result
      end
      prepare.call(2, "--verification", "supported", error: "missing argument: --id")
      prepare.call(2, "--id", targets.first, error: "missing argument: --verification")
      prepare.call(2, "--id", targets.first, "--id", targets.first, "--verification", "supported", error: "exactly one --id")
      prepare.call(2, "--id", targets.first, "--verification", "supported", "--verification", "contradicted",
        error: "supply --verification at most once")
      prepare.call(2, "--id", targets.first, "--verification", "supported", "--commit", "abcdef0", error: "--commit is not valid")
      prepare.call(1, "--id", targets.first, "--verification", "unverified", error: "proposed verification must be one of")
      prepare.call(1, "--id", origin, "--verification", "supported", error: "invalid accepted_id")
      prepare.call(1, "--id", "../escape", "--verification", "supported", error: "invalid accepted_id")
      prepare.call(1, "--id", "SCR-20000101-000000", "--verification", "supported", error: "record not found")
      raise "missing verification preparation help" unless prepare.call(0, "--help").include?("Usage: retro-state.rb prepare-verification")
      run.call(2, "show", "--id", targets.first, "--verification", "supported", error: "--verification is not valid")

      drafts = %w[supported contradicted].to_h do |state|
        text = prepare.call(0, "--id", targets.first, "--verification", state)
        data, body = parse_document(text)
        blank_fields = %w[title source_scope verification_basis opportunity_match claim observation redaction_review]
        unless data.values_at("target_accepted_id", "proposed_verification", "decisive_evidence") == [targets.first, state, []] &&
            blank_fields.all? { |field| data.fetch(field) == "" } && body.empty? &&
            %w[verification_proposal_id created_at intake_digest triage supplemental_reason].none? { |field| data.key?(field) } &&
            ((state == "contradicted") ? data.fetch("what_is_false") == "" : !data.key?("what_is_false")) &&
            text.include?("Exercise preparation target 0.") && !text.include?("Exercise preparation target 1.")
          raise "verification preparation invented judgment or lost target context"
        end
        before = store.snapshot
        run.call(1, "route-verification", "--file", "-", stdin: text, error: "title must be a non-empty string")
        raise "incomplete verification routing wrote state" unless store.snapshot == before
        [state, text]
      end
      complete = lambda do |text|
        data, = parse_document(text)
        data.merge!(
          "title" => "Reviewed: \"literal\" proposal.", "source_scope" => "Temporary preparation fixture.",
          "verification_basis" => "deterministic-test", "claim" => "executable-correctness",
          "opportunity_match" => "Exercises the selected fixture opportunity.",
          "observation" => "A reviewed observation.\nA bounded second line with \\literal text.",
          "decisive_evidence" => ["A bounded fixture check."], "redaction_review" => "Reviewed sanitized fixture."
        )
        data["what_is_false"] = "The fixture expectation failed." if data.key?("what_is_false")
        data["supplemental_reason"] = "A distinct fixture boundary." if data.key?("supplemental_reason")
        comments = text.lines.drop(1).take_while { |line| line.start_with?("#") || line.strip.empty? }.join
        render_document(data, "").sub(/\A---\n/) { "---\n#{comments}" }
      end
      completed = complete.call(drafts.fetch("supported"))
      proposal_id = File.basename(run.call(0, "route-verification", "--file", "-", stdin: completed).strip, ".md")
      routed_path = File.join(root, "verifications/inbox/#{proposal_id}.md")
      routed, routed_body = read_document(routed_path)
      expected, = parse_document(completed)
      unless without_keys(routed, "verification_proposal_id", "created_at", "intake_digest") == expected &&
          routed_body.empty? && !File.read(routed_path).include?("# Target context:")
        raise "routing persisted preparation comments or changed curated evidence"
      end
      prepare.call(1, "--id", proposal_id, "--verification", "supported", error: "invalid accepted_id")
      pending = prepare.call(0, "--id", targets.first, "--verification", "supported")
      unless parse_document(pending).first.fetch("supplemental_reason") == "" && pending.include?(proposal_id)
        raise "pending support preparation lost the supplementation requirement or context"
      end
      before = store.snapshot
      out, err, result = Open3.capture3(RbConfig.ruby, File.expand_path(__FILE__),
        "route-verification", "--root", root, "--file", "-", stdin_data: completed)
      unless result.exitstatus == 2 && err.include?("support already pending") && parse_document(out).first == expected
        raise "stale verification routing lost its refusal or paste-ready fallback"
      end
      raise "stale verification routing wrote state" unless store.snapshot == before
      decision = store.prepare_decision(proposal_id, "apply", rationale: "Reviewed fixture evidence.")
      run.call(0, "process-verification", "--id", proposal_id, "--decision", "-", stdin: decision)
      supported = prepare.call(0, "--id", targets.first, "--verification", "supported")
      unless parse_document(supported).first.fetch("supplemental_reason") == "" && supported.include?(proposal_id)
        raise "supported target preparation lost applied provenance or supplementation"
      end

      contradiction, = parse_document(complete.call(drafts.fetch("contradicted")))
      contradiction["target_accepted_id"] = targets.last
      id = File.basename(store.route_verification(write.call(render_document(contradiction, ""))), ".md")
      only_contradiction, = parse_document(prepare.call(0, "--id", targets.last, "--verification", "supported"))
      raise "pending contradiction required supplemental support" if only_contradiction.key?("supplemental_reason")
      decision = store.prepare_decision(id, "reject", rationale: "Reviewed fixture rejection.")
      store.process_verification(id, write.call(decision))
      id = File.basename(run.call(0, "route-verification", "--file", "-",
        stdin: complete.call(drafts.fetch("contradicted"))).strip, ".md")
      decision = store.prepare_decision(id, "apply", rationale: "Reviewed fixture contradiction.")
      store.process_verification(id, write.call(decision))
      %w[supported contradicted].each do |state|
        prepare.call(1, "--id", targets.first, "--verification", state, error: "verification target state contradicted cannot receive")
      end
      terminal, body = parse_document(store.prepare_accepted_update(targets.last))
      terminal["disposition"] = "reverted"
      store.update_accepted(targets.last, write.call(render_document(terminal, body)))
      prepare.call(1, "--id", targets.last, "--verification", "contradicted", error: "verification target disposition is not accepted or implemented")
      store.validate
    end
  end

  def accepted_preparation_self_test
    Dir.mktmpdir("retro-accepted-preparation-self-test.") do |tmp|
      root = File.join(File.realpath(tmp), "state")
      store = Store.new(root)
      store.init
      run = self_test_cli(root)
      input = File.join(tmp, "input.md")
      write = lambda do |data, body|
        File.write(input, render_document(data, body))
        input
      end
      archive = lambda do |verdict, related_ids = [], rationale = "Reviewed narrow outcome; the original proposal is not authoritative."|
        candidate, body = parse_document(candidate_template)
        candidate["observation"] = "Known prior observation."
        candidate["decisive_evidence"] = ["Literal \\& and \\1 evidence."]
        candidate["proposed_destination"] = "Original broad proposal, subject to review."
        path = store.route(write.call(candidate, body))
        id = File.basename(path, ".md")
        decision, body = parse_document(store.prepare_decision(id, verdict))
        decision["rationale"] = rationale
        decision["related_candidate_ids"] = related_ids
        decision.merge!(self_test_deferral_fields) if verdict == "defer"
        store.process(id, write.call(decision, body))
        id
      end
      accepted_rationale = "Accepted scope is restricted to the reviewed narrow boundary."
      accepted_origin = archive.call("accept", [], accepted_rationale)
      split_origin = archive.call("split")
      merged_origin = archive.call("merge", [accepted_origin])
      merged_chain = archive.call("merge", [merged_origin])
      rejected_origin = archive.call("reject")
      nonpublication_merge = archive.call("merge", [rejected_origin])
      empty_merge = archive.call("merge")
      missing_merge = archive.call("merge", ["RC-20000101T000000Z-000000"])
      uncertain_chain = archive.call("merge", [missing_merge])
      cycle_first = archive.call("merge")
      cycle_second = archive.call("merge", [cycle_first])
      cycle_path = File.join(root, "retrospectives", "archive", "#{cycle_first}.md")
      cycle, cycle_body = read_document(cycle_path)
      cycle["triage"]["related_candidate_ids"] = [cycle_second]
      File.write(cycle_path, render_document(cycle, cycle_body))
      deferred_origin = archive.call("defer")
      before = store.snapshot
      command = ["prepare-accepted", "--id", accepted_origin, "--id", split_origin, "--id", accepted_origin, "--id", merged_chain,
        "--commit", "ABCDEF0", "--commit", "1234567", "--commit", "abcdef0", "--commit", "A" * 40]
      output = run.call(0, *command)
      draft, body = parse_document(output)
      blank_fields = %w[
        source_report_summary expected_behavior observed_behavior trigger non_trigger
        destination verification_opportunity redaction_review
      ]
      unless draft.fetch("originating_candidate_ids") == [accepted_origin, split_origin, merged_chain] &&
          draft.fetch("implementation_commits") == ["abcdef0", "1234567", "a" * 40] &&
          draft.values_at("disposition", "verification", "verification_basis") == %w[accepted unverified none] &&
          blank_fields.all? { |field| draft.fetch(field) == "" } && draft.fetch("decisive_evidence").empty? &&
          !draft.key?("accepted_id") && !draft.key?("accepted_at")
        raise "new accepted preparation inferred outcome judgments or lost explicit linkage"
      end
      unless output.include?("#   observation: Known prior observation.") && output.include?("Reviewed narrow outcome") &&
          output.include?("Original broad proposal") && output.include?("decisive_evidence") &&
          output.include?("Literal \\& and \\1 evidence.") &&
          !body.include?("Prior candidate context") && !draft.key?("triage")
        raise "new accepted preparation lost prior evidence or reviewed scope"
      end
      [merged_origin, merged_chain].each do |id|
        prepared = run.call(0, "prepare-accepted", "--id", id, "--id", merged_origin, "--commit", "abcdef0")
        merged, = parse_document(prepared)
        unless merged.fetch("originating_candidate_ids") == [id, merged_origin].uniq &&
            prepared.scan(accepted_rationale).length == 1
          raise "publication-bound merge lost or duplicated the resolving acceptance context"
        end
      end
      unrelated_path = File.join(root, "retrospectives", "archive", "#{deferred_origin}.md")
      unrelated_original = File.read(unrelated_path)
      File.write(unrelated_path, "---\ninvalid: [\n---\n")
      isolated = store.snapshot
      unrelated_probe = run.call(0, "prepare-accepted", "--id", merged_chain, "--commit", "abcdef0")
      unless unrelated_probe.include?(accepted_rationale) && store.snapshot == isolated
        raise "merged preparation depended on unrelated archive state or wrote state"
      end
      File.write(unrelated_path, unrelated_original)
      queue_ids = run.call(0, "review-queue").lines.map { |line| line.split("\t") }
        .select { |row| row.first == "accepted-publication" }.map { |row| row[1] }
      unless [empty_merge, missing_merge, uncertain_chain].all? { |id| queue_ids.include?(id) } &&
          !queue_ids.include?(nonpublication_merge)
        raise "preparation eligibility changed conservative publication discovery"
      end
      File.write(input, output)
      run.call(1, "record-accepted", "--file", input, error: "source_report_summary must be a non-empty string")
      run.call(2, "prepare-accepted", "--commit", "abcdef0", error: "missing argument: --id RC-ID")
      run.call(2, "prepare-accepted", "--id", accepted_origin, error: "missing argument: --commit SHA")
      run.call(1, "prepare-accepted-update", "--id", accepted_origin, "--commit", "abcdef0", error: "invalid accepted_id")
      ["HEAD", "abcdef", "g" * 40, "a" * 41, "a" * 64, ""].each do |invalid|
        run.call(1, "prepare-accepted", "--id", accepted_origin, "--commit", invalid, error: "hexadecimal commit SHAs")
      end
      [rejected_origin, nonpublication_merge, deferred_origin, empty_merge, missing_merge,
        uncertain_chain, cycle_first, cycle_second].each do |id|
        run.call(1, "prepare-accepted", "--id", id, "--commit", "abcdef0", error: "no accepted publication outcome")
      end
      run.call(1, "prepare-accepted", "--id", "../escape", "--commit", "abcdef0", error: "invalid record ID")
      run.call(1, "prepare-accepted", "--id", accepted_origin, "--id", "RC-20000101T000000Z-000000",
        "--commit", "abcdef0", error: "record not found")
      raise "new accepted preparation wrote state" unless store.snapshot == before

      path = File.join(root, "retrospectives", "archive", "#{accepted_origin}.md")
      original = File.read(path)
      File.write(path, original.sub("Known prior observation.", "Tampered prior observation."))
      run.call(1, *command, error: "intake fields changed after routing")
      run.call(1, "prepare-accepted", "--id", merged_chain, "--commit", "abcdef0", error: "intake fields changed after routing")
      File.write(path, "---\ninvalid: [\n---\n")
      run.call(1, *command, error: "invalid YAML frontmatter")
      File.write(path, original)
      raise "failed accepted preparation wrote state" unless store.snapshot == before

      template, = parse_document(accepted_template)
      blank_fields.each { |field| draft[field] = template.fetch(field) }
      draft["decisive_evidence"] = ["Reviewed fixture implementation evidence."]
      comments = output.lines.drop(1).take_while { |line| line.start_with?("#") }.join
      completed = render_document(draft, "# Curated accepted outcome\n").sub(/\A---\n/) { "---\n#{comments}" }
      unless completed.include?("Known prior observation.") && completed.include?("Complete the blank outcome fields")
        raise "round-trip fixture removed preparation comments before recording"
      end
      File.write(input, completed)
      accepted_path = run.call(0, "record-accepted", "--file", input).strip
      accepted_id = File.basename(accepted_path, ".md")
      recorded, recorded_body = read_document(accepted_path)
      unless recorded.fetch("originating_candidate_ids") == [accepted_origin, split_origin, merged_chain] &&
          recorded.fetch("implementation_commits") == ["abcdef0", "1234567", "a" * 40] &&
          recorded.fetch("decisive_evidence") == ["Reviewed fixture implementation evidence."] &&
          recorded_body.include?("# Curated accepted outcome") &&
          ["Known prior observation.", accepted_rationale, "Complete the blank outcome fields", "Prior candidate context"].none? { |text| File.read(accepted_path).include?(text) }
        raise "completed accepted draft lost curated content or retained preparation comments"
      end
      before = store.snapshot
      another, = parse_document(run.call(0, "prepare-accepted", "--id", split_origin, "--commit", "abcdef1"))
      unless another.fetch("originating_candidate_ids") == [split_origin]
        raise "new accepted preparation consumed a split origin"
      end
      run.call(1, "prepare-accepted", "--id", accepted_id, "--commit", "abcdef0", error: "invalid candidate_id")
      File.write(input, candidate_template)
      pending_id = File.basename(store.route(input), ".md")
      before_pending = store.snapshot
      run.call(1, "prepare-accepted", "--id", pending_id, "--commit", "abcdef0", error: "requires archived candidates")
      raise "pending-origin refusal wrote state" unless store.snapshot == before_pending
      File.unlink(File.join(root, "retrospectives", "inbox", "#{pending_id}.md"))
      unless run.call(0, "prepare-accepted", "--help").include?("Usage: retro-state.rb prepare-accepted") &&
          store.snapshot == before
        raise "accepted preparation changed state or omitted focused help"
      end
      store.validate
    end
  end

  def self_test_deferral_fields
    {
      "unresolved_decision" => "Whether the proposed guidance covers a second independent task.",
      "review_trigger_probe" => "Inspect the current triage request for an independent task observation.",
      "review_trigger_input" => "A second independent task observation supplied to triage.",
      "review_trigger" => "A second independent task observation is available in the triage request.",
      "next_action" => "Compare the new observation with the proposed guidance and choose a terminal verdict.",
      "close_condition" => "A terminal verdict replaces this deferral."
    }
  end

  def preparation_self_test
    Dir.mktmpdir("retro-preparation-self-test.") do |tmp|
      root = File.join(File.realpath(tmp), "state")
      store = Store.new(root)
      store.init
      run = self_test_cli(root)
      input = File.join(tmp, "input.md")
      decision_file = File.join(tmp, "decision.md")
      {"decision" => decision_template, "verification-decision" => verification_decision_template}.each do |type, text|
        _data, body = parse_document(text)
        raise "#{type} template emitted placeholder notes" unless body.empty?
      end
      File.write(input, candidate_template)
      candidate = store.route(input)
      id = File.basename(candidate, ".md")
      before = store.snapshot
      decision, body = parse_document(run.call(0, "prepare-decision", "--id", id, "--verdict", "accept"))
      unless decision.values_at("candidate_id", "verdict", "rationale") == [id, "accept", ""] &&
          body.empty? && review_trigger_contract_fields.none? { |field| decision.key?(field) }
        raise "incorrect terminal decision draft"
      end
      begin
        validate_decision(decision, body, label: "unreviewed draft", expected_id: id)
        raise "blank rationale was accepted"
      rescue Error => e
        raise unless e.message.include?("rationale must be a non-empty string")
      end
      deferred, = parse_document(run.call(0, "prepare-decision", "--id", id, "--verdict", "defer"))
      unless self_test_deferral_fields.keys.all? { |field| deferred.fetch(field).empty? } &&
          deferred.values_at("review_trigger_contract_version", "review_trigger_type", "review_trigger_observer", "review_trigger_route") ==
              [1, "explicit-input", "skill-retro-triage", "review-queue"]
        raise "deferral preparation supplied judgment or lost safe structural defaults"
      end
      run.call(2, "prepare-decision", "--id", id, error: "missing argument: --verdict")
      run.call(2, "prepare-decision", "--id", id, "--id", id, "--verdict", "accept", error: "exactly one --id")
      run.call(1, "prepare-decision", "--id", id, "--verdict", "accept", "--rationale", " ", error: "reviewed rationale must be a non-empty string")
      run.call(2, "prepare-accepted-update", error: "missing argument: --id")
      run.call(2, "prepare-accepted-update", "--id", id, "--verdict", "accept", error: "--verdict is not valid")
      run.call(1, "prepare-decision", "--id", id, "--verdict", "apply", error: "verdict must be one of")
      run.call(1, "prepare-decision", "--id", "../escape", "--verdict", "accept", error: "invalid record ID")
      run.call(1, "prepare-accepted-update", "--id", "SCR-20000101-000000", error: "record not found")
      intake = File.read(candidate)
      File.write(candidate, intake.sub("Short candidate title", "Tampered candidate title"))
      run.call(1, "prepare-decision", "--id", id, "--verdict", "accept", error: "intake fields changed after routing")
      File.write(candidate, intake)
      rationale = "Reviewed: retain \"literal\" evidence, \\paths, and [brackets].\nSecond line: # not a comment."
      prepared = run.call(0, "prepare-decision", "--id", id, "--verdict", "accept", "--rationale", rationale)
      reviewed, reviewed_body = parse_document(prepared)
      validate_decision(reviewed, reviewed_body, label: "reviewed draft", expected_id: id)
      unless reviewed.fetch("rationale") == rationale && reviewed_body.empty?
        raise "reviewed rationale did not round-trip or optional notes were emitted"
      end
      raise "decision preparation wrote state" unless store.snapshot == before
      run.call(0, "process", "--id", id, "--decision", "-", stdin: prepared)
      archived, = read_document(File.join(root, "retrospectives", "archive", "#{id}.md"))
      unless archived.dig("triage", "rationale") == rationale && !archived.fetch("triage").key?("notes")
        raise "processing lost the supplied rationale or persisted placeholder notes"
      end
      run.call(1, "prepare-decision", "--id", id, "--verdict", "reject", error: "not currently deferred")

      ["", "# Reviewed implementation notes\n\nPreserve this deliberately supplied context."].each do |notes|
        File.write(input, candidate_template)
        template_id = File.basename(store.route(input), ".md")
        raw, = parse_document(decision_template)
        raw.merge!("candidate_id" => template_id, "verdict" => "no-change", "rationale" => rationale,
          "reviewed_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"))
        review_trigger_contract_fields.each { |field| raw.delete(field) }
        path = run.call(0, "process", "--id", template_id, "--decision", "-", stdin: render_document(raw, notes)).strip
        archived, = read_document(path)
        if notes.empty? ? archived.fetch("triage").key?("notes") : archived.dig("triage", "notes") != notes
          raise "raw candidate decision lost intentional notes or persisted placeholder notes"
        end
      end

      accepted, accepted_body = parse_document(accepted_template)
      accepted["originating_candidate_ids"] = [id]
      accepted["implementation_commits"] = ["abcdef0"]
      accepted["extra_context"] = {"preserve" => ["custom metadata"]}
      File.write(input, render_document(accepted, accepted_body))
      accepted_path = store.record_accepted(input)
      accepted_id = File.basename(accepted_path, ".md")
      ["", "# Reviewed adjudication notes\n\nPreserve this deliberately supplied evidence boundary."].each do |notes|
        proposal, proposal_body = parse_document(verification_proposal_template)
        proposal["target_accepted_id"] = accepted_id
        proposal["observation"] = "Raw decision notes boundary: #{notes.empty? ? "omitted" : "supplied"}."
        File.write(input, render_document(proposal, proposal_body))
        template_id = File.basename(store.route_verification(input), ".md")
        raw, = parse_document(verification_decision_template)
        raw.merge!("verification_proposal_id" => template_id, "verdict" => "reject", "rationale" => rationale,
          "reviewed_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"))
        path = run.call(0, "process-verification", "--id", template_id, "--decision", "-", stdin: render_document(raw, notes)).strip
        archived, = read_document(path)
        if notes.empty? ? archived.fetch("triage").key?("notes") : archived.dig("triage", "notes") != notes
          raise "raw verification decision lost intentional notes or persisted placeholder notes"
        end
      end
      proposal, proposal_body = parse_document(verification_proposal_template)
      proposal["target_accepted_id"] = accepted_id
      proposal["proposed_verification"] = "contradicted"
      proposal["what_is_false"] = "The recorded fixture expectation failed."
      File.write(input, render_document(proposal, proposal_body))
      proposal_path = store.route_verification(input)
      proposal_id = File.basename(proposal_path, ".md")
      before = store.snapshot
      verification, verification_body = parse_document(run.call(0, "prepare-decision", "--id", proposal_id, "--verdict", "apply"))
      unless verification.values_at("record_type", "verification_proposal_id", "verdict", "rationale") ==
          ["verification-decision", proposal_id, "apply", ""] && verification_body.empty?
        raise "incorrect verification decision draft"
      end
      run.call(1, "prepare-decision", "--id", proposal_id, "--verdict", "accept", error: "verdict must be one of")
      prepared = run.call(0, "prepare-decision", "--id", proposal_id, "--verdict", "apply", "--rationale", rationale)
      raise "verification preparation wrote state" unless store.snapshot == before
      run.call(0, "process-verification", "--id", proposal_id, "--decision", "-", stdin: prepared)
      archived, = read_document(File.join(root, "verifications", "archive", "#{proposal_id}.md"))
      unless archived.dig("triage", "rationale") == rationale && !archived.fetch("triage").key?("notes")
        raise "verification processing lost the supplied rationale or persisted placeholder notes"
      end
      run.call(1, "prepare-decision", "--id", proposal_id, "--verdict", "reject", error: "must be in inbox")

      original, original_body = read_document(accepted_path)
      before = store.snapshot
      replacement = run.call(0, "prepare-accepted-update", "--id", accepted_id)
      updated, updated_body = parse_document(replacement)
      unless updated == without_keys(original, "accepted_id", "accepted_at") && updated_body == original_body
        raise "accepted preparation lost metadata or body"
      end
      new_commit = "b" * 40
      destination = "Curated: \"destination\", with \\literal text.\nSecond destination line."
      [
        [["--commit", "ABCDEF0", "--commit", new_commit.upcase, "--commit", new_commit],
          {"implementation_commits" => ["abcdef0", new_commit]}],
        [["--destination", destination], {"destination" => destination}],
        [["--commit", new_commit, "--destination", destination],
          {"implementation_commits" => ["abcdef0", new_commit], "destination" => destination}]
      ].each do |arguments, changes|
        prepared, body = parse_document(run.call(0, "prepare-accepted-update", "--id", accepted_id, *arguments))
        unless prepared == updated.merge(changes) && body == original_body
          raise "metadata preparation changed unrelated fields or failed to preserve supplied values"
        end
      end
      ["HEAD", "abcdef", "g" * 40, "a" * 41, "", " "].each do |invalid|
        run.call(1, "prepare-accepted-update", "--id", accepted_id, "--commit", invalid, error: "implementation_commits")
      end
      ["", " "].each do |invalid|
        run.call(1, "prepare-accepted-update", "--id", accepted_id, "--destination", invalid, error: "destination must be a non-empty string")
      end
      run.call(2, "prepare-accepted-update", "--id", accepted_id, "--destination", "first", "--destination", "second",
        error: "supply --destination at most once")
      run.call(1, "prepare-accepted-update", "--id", accepted_id, "--destination", "/tmp/auth.json", error: "forbidden Codex auth file")
      %w[prepare-decision prepare-accepted-update].each do |command|
        raise "missing preparation help" unless run.call(0, command, "--help").include?("Usage: retro-state.rb #{command}")
      end
      run.call(1, "prepare-decision", "--id", accepted_id, "--verdict", "accept", error: "requires a candidate or verification")
      raise "accepted preparation wrote state" unless store.snapshot == before
      File.write(input, replacement)
      store.update_accepted(accepted_id, input)
      raise "accepted update did not round-trip" unless read_document(accepted_path) == [original, original_body]

      retained, retained_body = parse_document(replacement)
      resolution = {
        "outcome" => "retained",
        "rationale" => "The failure limits the evidence claim; the existing guidance remains appropriate.",
        "resolved_at" => retained.fetch("contradiction").fetch("recorded_at")
      }
      invalid_resolutions = [
        ["retained", "resolution must be a mapping"],
        [resolution.merge("outcome" => "ignored"), "outcome must be retained"],
        [resolution.merge("rationale" => ""), "rationale must be a non-empty string"],
        [resolution.merge("resolved_at" => "tomorrow"), "resolved_at must be a UTC timestamp"],
        [resolution.merge("resolved_at" => "2000-01-01T00:00:00Z"), "must not predate"]
      ]
      before = store.snapshot
      invalid_resolutions.each do |invalid, message|
        retained["contradiction"]["resolution"] = invalid
        File.write(input, render_document(retained, retained_body))
        run.call(1, "update-accepted", "--id", accepted_id, "--file", input, error: message)
        raise "invalid retention resolution wrote state" unless store.snapshot == before
      end
      retained["contradiction"]["resolution"] = resolution
      File.write(input, render_document(retained, retained_body))
      run.call(0, "update-accepted", "--id", accepted_id, "--file", input)
      resolved, resolved_body = read_document(accepted_path)
      unless resolved.dig("contradiction", "resolution") == resolution
        raise "retention resolution was not recorded"
      end
      resolved["contradiction"].delete("resolution")
      unless [resolved, resolved_body] == [original, original_body]
        raise "retention resolution changed prior evidence or provenance"
      end
      if store.review_queue.any? { |type, row_id, _trigger, _path| type == "contradiction" && row_id == accepted_id }
        raise "retained contradiction remained in review queue"
      end
      resolved_snapshot = store.snapshot
      run.call(0, "update-accepted", "--id", accepted_id, "--file", input)
      raise "retention resolution retry changed state" unless store.snapshot == resolved_snapshot
      File.write(input, replacement)
      run.call(0, "update-accepted", "--id", accepted_id, "--file", input)
      unless store.review_queue.any? { |type, row_id, _trigger, _path| type == "contradiction" && row_id == accepted_id }
        raise "removing the resolution did not reopen contradiction review"
      end
      legacy = without_keys(original, "contradiction")
      File.write(accepted_path, render_document(legacy, original_body))
      legacy_input, = parse_document(run.call(0, "prepare-accepted-update", "--id", accepted_id))
      raise "preparation invented legacy contradiction evidence" if legacy_input.key?("contradiction")
      legacy_input, = parse_document(run.call(0, "prepare-accepted-update", "--id", accepted_id, "--commit", new_commit))
      unless legacy_input == without_keys(legacy, "accepted_id", "accepted_at").merge("implementation_commits" => ["abcdef0", new_commit])
        raise "metadata overrides invented legacy evidence or changed unrelated fields"
      end
      File.write(accepted_path, render_document(original, original_body))

      File.write(input, candidate_template)
      candidate = store.route(input)
      id = File.basename(candidate, ".md")
      before = store.snapshot
      prepared = run.call(0, "prepare-decision", "--id", id, "--verdict", "defer", "--rationale", "Independent evidence is still missing.")
      run.call(1, "process", "--id", id, "--decision", "-", stdin: prepared, error: "unresolved_decision must be a non-empty string")
      deferred, deferred_body = parse_document(prepared)
      deferred.merge!(self_test_deferral_fields)
      deferred["reviewed_at"] = "2000-01-01T00:00:00Z"
      self_test_deferral_fields.each_key do |field|
        incomplete = render_document(deferred.merge(field => ""), deferred_body)
        run.call(1, "process", "--id", id, "--decision", "-", stdin: incomplete, error: "#{field} must be a non-empty string")
        raise "incomplete deferral processing wrote state" unless store.snapshot == before
      end
      File.write(decision_file, render_document(deferred, deferred_body))
      archived = run.call(0, "process", "--id", id, "--decision", "-", stdin: File.read(decision_file)).strip
      before = store.snapshot
      incomplete = run.call(0, "prepare-decision", "--id", id, "--verdict", "defer", "--rationale", "A revised deferral still needs a concrete trigger.")
      run.call(1, "reconsider", "--id", id, "--decision", "-", stdin: incomplete, error: "unresolved_decision must be a non-empty string")
      raise "incomplete deferral reconsideration wrote state" unless store.snapshot == before
      replacement, replacement_body = parse_document(run.call(0, "prepare-decision", "--id", id, "--verdict", "no-change"))
      raise "reconsideration timestamp is not newer" unless replacement.fetch("reviewed_at") > deferred.fetch("reviewed_at")
      raise "reconsideration preparation wrote state" unless store.snapshot == before
      data, body = read_document(archived)
      prior_triage = data.fetch("triage").dup
      data["triage"]["reviewed_at"] = "9999-01-01T00:00:00Z"
      File.write(archived, render_document(data, body))
      before = store.snapshot
      run.call(1, "prepare-decision", "--id", id, "--verdict", "no-change", error: "timestamp must be newer")
      raise "failed preparation wrote state" unless store.snapshot == before
      data["triage"] = prior_triage
      File.write(archived, render_document(data, body))
      replacement["rationale"] = "Fixture terminal reconsideration."
      File.write(decision_file, render_document(replacement, replacement_body))
      store.reconsider(id, decision_file)
      reconsidered, = read_document(archived)
      raise "prepared reconsideration lost history" unless reconsidered.fetch("triage_history").last == prior_triage
    end
  end

  def transition_recovery_self_test
    Dir.mktmpdir("retro-transition-self-test.") do |tmp|
      workers = []
      write = lambda do |name, data, body|
        path = File.join(tmp, name)
        File.write(path, render_document(data, body))
        path
      end
      decide = lambda do |id, verdict|
        template = id.start_with?("VP-") ? verification_decision_template : decision_template
        data, body = parse_document(template)
        data[id.start_with?("VP-") ? "verification_proposal_id" : "candidate_id"] = id
        data["verdict"] = verdict
        data["reviewed_at"] = "2026-10-15T12:00:00Z"
        review_trigger_contract_fields.each { |field| data.delete(field) } unless id.start_with?("VP-")
        write.call("#{id}-#{verdict}.md", data, body)
      end
      route_candidate = lambda do |store|
        data, body = parse_document(candidate_template)
        path = store.route(write.call("candidate.md", data, body))
        [File.basename(path, ".md"), path]
      end
      fixture = lambda do |name|
        store = Store.new(File.join(tmp, name))
        store.init
        id, = route_candidate.call(store)
        store.process(id, decide.call(id, "accept"))
        data, body = parse_document(accepted_template)
        data["originating_candidate_ids"] = [id]
        path = store.record_accepted(write.call("accepted.md", data, body))
        [store, path]
      end
      propose = lambda do |store, accepted, state, supplemental = false|
        data, body = parse_document(verification_proposal_template)
        data["target_accepted_id"] = File.basename(accepted, ".md")
        data["proposed_verification"] = state
        data["observation"] = "Observation #{SecureRandom.hex(3)}"
        data["decisive_evidence"] = ["Evidence #{SecureRandom.hex(3)}"]
        data["what_is_false"] = "The accepted outcome fails this boundary." if state == "contradicted"
        data["supplemental_reason"] = "A distinct boundary is exercised." if supplemental
        path = store.route_verification(write.call("proposal.md", data, body))
        File.basename(path, ".md")
      end
      start = lambda do |pause_at, &action|
        events, output = IO.pipe
        input, release = IO.pipe
        pid = fork do
          events.close
          release.close
          output.sync = true
          output.puts("started")
          paused = false
          fault = lambda do |point|
            if point == pause_at && !paused
              paused = true
              output.puts("paused")
              input.gets
            end
          end
          begin
            action.call(fault)
            output.puts("completed")
            exit! 0
          rescue => e
            output.puts("failed: #{e.class}: #{e.message}")
            exit! 1
          end
        end
        output.close
        input.close
        worker = [pid, events, release]
        workers << worker
        worker
      end
      event = lambda do |worker, expected|
        ready = IO.select([worker.fetch(1)], nil, nil, 5)
        actual = ready && worker.fetch(1).gets&.strip
        raise "child expected #{expected.inspect}, got #{actual.inspect}" unless actual == expected
      end
      finish = lambda do |worker|
        event.call(worker, "completed")
        _pid, status = Process.wait2(worker.fetch(0))
        raise "child operation failed" unless status.success?
      end
      kill = lambda do |worker|
        Process.kill("KILL", worker.fetch(0))
        _pid, status = Process.wait2(worker.fetch(0))
        raise "child was not killed" unless status.signaled?
      end
      blocked = lambda do |worker|
        if IO.select([worker.fetch(1)], nil, nil, 0.1)
          raise "shared mutation completed while another writer held the state lock: #{worker.fetch(1).gets}"
        end
      end

      # Killing the resource-owning process before publication must leave a retryable inbox.
      store, = fixture.call("atomic-create")
      id, inbox = route_candidate.call(store)
      decision = decide.call(id, "reject")
      child = start.call(:state_file_prepared) do |fault|
        Store.new(store.root, fault_injector: fault).process(id, decision)
      end
      event.call(child, "started")
      event.call(child, "paused")
      kill.call(child)
      archive = File.join(store.root, "retrospectives/archive", "#{id}.md")
      raise "unpublished archive became visible" if File.exist?(archive)
      raise "interrupted archival lost inbox" unless File.file?(inbox)
      run = self_test_cli(store.root)
      run.call(0, "process", "--id", id, "--decision", decision)
      run.call(0, "validate")
      raise "archive recovery lost its decision" unless read_document(archive).first.dig("triage", "verdict") == "reject"
      original = File.binread(archive)
      begin
        store.send(:exclusive_write, archive, "replacement")
        raise "atomic creation overwrote an existing archive"
      rescue Error => e
        raise unless e.message.include?("refusing to overwrite")
      end
      raise "refused create changed the archive" unless File.binread(archive) == original

      # Both supplemental support and contradiction must preserve the preceding writer's evidence.
      %w[supported contradicted].each do |second_state|
        store, accepted = fixture.call("parallel-#{second_state}")
        first_id = propose.call(store, accepted, "supported")
        second_id = propose.call(store, accepted, second_state, second_state == "supported")
        first_decision = decide.call(first_id, "apply")
        second_decision = decide.call(second_id, "apply")
        first = start.call(:state_file_prepared) do |fault|
          Store.new(store.root, fault_injector: fault).process_verification(first_id, first_decision)
        end
        event.call(first, "started")
        event.call(first, "paused")
        second = start.call(nil) do |fault|
          Store.new(store.root, fault_injector: fault).process_verification(second_id, second_decision)
        end
        event.call(second, "started")
        blocked.call(second)
        first.fetch(2).puts("continue")
        finish.call(first)
        finish.call(second)
        data, = read_document(accepted)
        unless data["verification"] == second_state &&
            data.fetch("applied_verification_proposal_ids") == [first_id, second_id]
          raise "parallel verification lost a transition or its provenance"
        end
        [first_id, second_id].each do |proposal_id|
          proposal, = read_document(File.join(store.root, "verifications/archive", "#{proposal_id}.md"))
          unless (proposal.fetch("decisive_evidence") - data.fetch("decisive_evidence")).empty?
            raise "parallel verification lost evidence"
          end
        end
        if second_state == "contradicted" && !data.key?("contradiction")
          raise "parallel verification erased the contradiction"
        end
        store.validate
      end

      # Generic replacement must share the verification lock and retain verification fields.
      store, accepted = fixture.call("generic-update")
      accepted_id = File.basename(accepted, ".md")
      id = propose.call(store, accepted, "supported")
      apply = decide.call(id, "apply")
      data, body = read_document(accepted)
      update = without_keys(data, "accepted_id", "accepted_at")
      update["destination"] = "Relocated destination."
      stale = write.call("stale-update.md", update, body)
      first = start.call(:state_file_prepared) do |fault|
        Store.new(store.root, fault_injector: fault).process_verification(id, apply)
      end
      event.call(first, "started")
      event.call(first, "paused")
      second = start.call(nil) do |fault|
        Store.new(store.root, fault_injector: fault).update_accepted(accepted_id, stale)
        raise "stale generic replacement erased verification"
      rescue Error => e
        raise unless e.message.include?("applied_verification_proposal_ids must be preserved")
      end
      event.call(second, "started")
      blocked.call(second)
      first.fetch(2).puts("continue")
      finish.call(first)
      finish.call(second)
      data, body = read_document(accepted)
      update = without_keys(data, "accepted_id", "accepted_at")
      run = self_test_cli(store.root)
      [{"verification" => "unverified", "verification_basis" => "none"},
        {"verification_basis" => "deterministic-test"}].each do |changes|
        input = write.call("invalid-update.md", update.merge(changes), body)
        before = store.snapshot
        run.call(1, "update-accepted", "--id", accepted_id, "--file", input, error: "changes require process-verification")
        raise "refused generic update changed state" unless store.snapshot == before
      end
      update["destination"] = "Relocated destination."
      store.update_accepted(accepted_id, write.call("valid-update.md", update, body))
      store.validate
      unverified_store, unverified_path = fixture.call("generic-upgrade")
      data, body = read_document(unverified_path)
      data = without_keys(data, "accepted_id", "accepted_at")
      data["verification"] = "supported"
      data["verification_basis"] = "later-session"
      before = unverified_store.snapshot
      self_test_cli(unverified_store.root).call(
        1, "update-accepted", "--id", File.basename(unverified_path, ".md"),
        "--file", write.call("invalid-upgrade.md", data, body), error: "changes require process-verification"
      )
      raise "generic upgrade changed state" unless unverified_store.snapshot == before

      # An interrupted application can resume, but cannot be relabeled as rejection.
      store, accepted = fixture.call("verification-recovery")
      id = propose.call(store, accepted, "supported")
      apply = decide.call(id, "apply")
      child = start.call(:verification_accepted_written) do |fault|
        Store.new(store.root, fault_injector: fault).process_verification(id, apply)
      end
      event.call(child, "started")
      event.call(child, "paused")
      kill.call(child)
      before = store.snapshot
      run = self_test_cli(store.root)
      run.call(1, "process-verification", "--id", id, "--decision", decide.call(id, "reject"), error: "already applied")
      raise "conflicting recovery changed state" unless store.snapshot == before
      run.call(0, "process-verification", "--id", id, "--decision", apply)
      run.call(0, "validate")
      unless read_document(accepted).first.fetch("applied_verification_proposal_ids") == [id]
        raise "verification retry duplicated application"
      end

      # A stored rejection is checked before a conflicting retry can apply any evidence.
      store, accepted = fixture.call("verification-archive-conflict")
      id = propose.call(store, accepted, "supported")
      reject = decide.call(id, "reject")
      child = start.call(:verification_archive_written) do |fault|
        Store.new(store.root, fault_injector: fault).process_verification(id, reject)
      end
      event.call(child, "started")
      event.call(child, "paused")
      kill.call(child)
      before = store.snapshot
      run = self_test_cli(store.root)
      run.call(1, "process-verification", "--id", id, "--decision", decide.call(id, "apply"), error: "existing verification archive differs")
      raise "archive conflict applied evidence" unless store.snapshot == before
      run.call(0, "process-verification", "--id", id, "--decision", reject)
      run.call(0, "validate")

      # Audit publication and candidate processing share the same cadence snapshot boundary.
      store, = fixture.call("audit-concurrency")
      data, body = parse_document(learning_audit_template)
      data["audit_kind"] = "skill-repository"
      audit_input = write.call("audit.md", data, body)
      id, = route_candidate.call(store)
      decision = decide.call(id, "reject")
      audit = start.call(:state_file_prepared) do |fault|
        Store.new(store.root, fault_injector: fault).record_audit(audit_input)
      end
      event.call(audit, "started")
      event.call(audit, "paused")
      candidate = start.call(nil) do |fault|
        Store.new(store.root, fault_injector: fault).process(id, decision)
      end
      event.call(candidate, "started")
      blocked.call(candidate)
      audit.fetch(2).puts("continue")
      finish.call(audit)
      finish.call(candidate)
      cadence = store.send(:artifact_cadence_state)
      unless cadence.fetch("candidate_archives_total") == 2 &&
          cadence.fetch("counted_candidate_ids").include?(id) &&
          store.artifact_audit_status(archive_threshold: 1).fetch(:due)
        raise "audit recording rewound candidate cadence"
      end
      store.validate

      # Legacy counts describe retained files, so only the latest count bootstraps migration.
      legacy = Store.new(File.join(tmp, "legacy-audit-counts"))
      legacy.init
      [["LA-20260701-aaaaaa", "2026-07-01T12:00:00Z", 20],
        ["LA-20260801-bbbbbb", "2026-08-01T12:00:00Z", 1]].each do |audit_id, completed_at, count|
        data, body = parse_document(learning_audit_template)
        data.merge!("audit_kind" => "skill-repository", "audit_id" => audit_id,
          "completed_at" => completed_at, "candidate_archive_count" => count)
        path = File.join(legacy.root, "audits/learning-process", "#{audit_id}.md")
        File.write(path, render_document(data, body))
      end
      expected_cadence = {
        "schema_version" => 1, "record_type" => ARTIFACT_CADENCE_RECORD_TYPE,
        "candidate_archives_total" => 1, "last_completed_artifact_audit_total" => 1,
        COUNTED_CANDIDATE_IDS_FIELD => []
      }
      unless legacy.send(:artifact_cadence_state) == expected_cadence
        raise "legacy migration used an older retained-file count"
      end
      legacy.validate
      legacy.send(:write_artifact_cadence, expected_cadence)
      before = legacy.snapshot
      unless legacy.send(:artifact_cadence_state) == expected_cadence
        raise "legacy history overrode durable monotonic cadence"
      end
      legacy.validate
      raise "legacy reconciliation wrote state" unless legacy.snapshot == before

      # Publication is the audit commit point; readers and retries reconcile a lost cache update.
      store, = fixture.call("audit-recovery")
      data, body = parse_document(ledger_template)
      ledger = store.record_ledger(write.call("ledger.md", data, body))
      ledger_id = File.basename(ledger, ".md")
      data, body = parse_document(learning_audit_template)
      data["audit_kind"] = "skill-repository"
      data["unresolved_action_ids"] = [ledger_id]
      audit_input = write.call("recovery-audit.md", data, body)
      before = store.snapshot
      failed = Store.new(store.root, fault_injector: lambda do |point|
        raise Error, "before publication" if point == :state_file_prepared
      end)
      begin
        failed.record_audit(audit_input)
        raise "audit publication failure was not injected"
      rescue Error => e
        raise unless e.message == "before publication"
      end
      raise "unpublished audit changed state" unless store.snapshot == before
      raise "unpublished audit reset cadence" unless store.artifact_audit_status(archive_threshold: 1).fetch(:due)
      child = start.call(:audit_record_written) do |fault|
        Store.new(store.root, fault_injector: fault).record_audit(audit_input)
      end
      event.call(child, "started")
      event.call(child, "paused")
      kill.call(child)
      original_audit = store.audits.fetch(0).fetch(3)
      original_bytes = File.binread(original_audit)
      run = self_test_cli(store.root)
      run.call(0, "validate")
      raise "published audit failed to reset effective cadence" if store.artifact_audit_status(archive_threshold: 1).fetch(:due)
      store.close_ledger(ledger_id, rationale: "The action completed after audit publication.")
      audit_id = File.basename(original_audit, ".md")
      retried = run.call(0, "record-audit", "--id", audit_id).strip
      unless retried == original_audit && store.audits.length == 1 && File.binread(original_audit) == original_bytes
        raise "audit recovery created another identity or changed its committed record"
      end

      10.times do
        candidate_id, = route_candidate.call(store)
        store.process(candidate_id, decide.call(candidate_id, "reject"))
      end
      raise "later candidate processing failed to make an audit due" unless store.artifact_audit_status.fetch(:due)
      before = store.snapshot
      2.times do
        retried = run.call(0, "record-audit", "--id", audit_id).strip
        unless retried == original_audit && store.audits.length == 1 &&
            store.artifact_audit_status.fetch(:archives_since) == 10 && store.snapshot == before
          raise "audit recovery after another writer changed identity, cutoff, or state"
        end
      end
      run.call(1, "record-audit", "--id", "LA-20000101-000000", error: "audit not found")
      run.call(1, "record-audit", "--id", "invalid", error: "invalid audit_id")
      [[], ["--id", audit_id, "--file", audit_input], ["--id", audit_id, "--id", audit_id]].each do |arguments|
        out, err, status = Open3.capture3(
          RbConfig.ruby, File.expand_path(__FILE__), "record-audit", *arguments, "--root", store.root
        )
        unless status.exitstatus == 2 && out.empty? && err.include?("retro-state.rb:")
          raise "audit recording accepted an ambiguous or incomplete invocation"
        end
      end
      raise "refused audit recovery changed state" unless store.snapshot == before
      File.unlink(original_audit)
      raise "deleting cached audit rewound cadence" unless store.artifact_audit_status.fetch(:archives_since) == 10
      store.validate

      # A fresh audit remains distinct even when its payload matches an interrupted publication.
      store, = fixture.call("fresh-audit-identity")
      data, body = parse_document(learning_audit_template)
      data["audit_kind"] = "skill-repository"
      input = write.call("fresh-audit.md", data, body)
      child = start.call(:audit_record_written) do |fault|
        Store.new(store.root, fault_injector: fault).record_audit(input)
      end
      event.call(child, "started")
      event.call(child, "paused")
      kill.call(child)
      old_audit = store.audits.fetch(0).fetch(3)
      10.times do
        candidate_id, = route_candidate.call(store)
        store.process(candidate_id, decide.call(candidate_id, "reject"))
      end
      before = store.snapshot
      recovered = self_test_cli(store.root).call(0, "record-audit", "--id", File.basename(old_audit, ".md")).strip
      unless recovered == old_audit && store.audits.length == 1 &&
          store.artifact_audit_status.fetch(:archives_since) == 10 && store.snapshot == before
        raise "first recovery after a cadence writer changed the original audit cutoff"
      end
      fresh = store.record_audit(input)
      raise "fresh audit was mistaken for recovery" unless fresh != old_audit && store.audits.length == 2
      before = store.snapshot
      store.recover_audit(File.basename(old_audit, ".md"))
      unless store.snapshot == before && store.artifact_audit_status.fetch(:archives_since).zero?
        raise "recovering an older audit rewound a newer completed audit"
      end
      data["audit_kind"] = "learning-process"
      other = store.record_audit(write.call("process-audit.md", data, body))
      before = store.snapshot
      self_test_cli(store.root).call(1, "record-audit", "--id", File.basename(other, ".md"),
        error: "audit recovery requires a skill-repository audit")
      raise "wrong-kind audit recovery changed state" unless store.snapshot == before
      store.validate

      # Fresh recording must not infer a retry from matching content and an unfinished cache write.
      store, = fixture.call("fresh-audit-pending-cache")
      failed = Store.new(store.root, fault_injector: lambda do |point|
        raise Error, "after publication" if point == :audit_record_written
      end)
      begin
        failed.record_audit(input)
        raise "audit cache interruption was not injected"
      rescue Error => e
        raise unless e.message == "after publication"
      end
      old_audit = store.audits.fetch(0).fetch(3)
      fresh = self_test_cli(store.root).call(0, "record-audit", "--file", input).strip
      raise "matching content merged a fresh audit into recovery" unless fresh != old_audit && store.audits.length == 2
      store.validate
    ensure
      workers.each do |pid, events, release|
        begin
          unless Process.waitpid(pid, Process::WNOHANG)
            Process.kill("KILL", pid)
            Process.waitpid(pid)
          end
        rescue Errno::ECHILD, Errno::ESRCH
          # Already reaped by the successful or killed-process assertion.
        end
        events.close
        release.close
      end
    end
  end

  def self_test
    transition_recovery_self_test
    inspection_self_test
    metadata_comparison_self_test
    verification_context_self_test
    verification_evidence_curation_self_test
    verification_preparation_self_test
    accepted_preparation_self_test
    preparation_self_test
    Dir.mktmpdir("retro-state-self-test.") do |tmp|
      root = File.join(tmp, "state")
      input = File.join(tmp, "candidate.md")
      decision = File.join(tmp, "decision.md")
      accepted = File.join(tmp, "accepted.md")
      draft = File.join(tmp, "draft.md")
      ledger = File.join(tmp, "ledger.md")
      audit = File.join(tmp, "audit.md")
      papercut = File.join(tmp, "papercut.md")
      papercut_repair = File.join(tmp, "papercut-repair.md")
      verification_proposal = File.join(tmp, "verification.md")
      verification_decision = File.join(tmp, "verification-decision.md")
      without_review_trigger_contract = lambda do |text|
        data, body = parse_document(text)
        review_trigger_contract_fields.each { |field| data.delete(field) }
        render_document(data, body)
      end
      legacy_review_trigger_fields = review_trigger_contract_fields -
        %w[review_trigger next_action close_condition]
      recommendation_line = candidate_template.lines.find { |line| line.include?("recommendation: uncertain") }
      unless recommendation_line && RECOMMENDATIONS.all? { |value| recommendation_line.include?(value) }
        raise "candidate template recommendation vocabulary is incomplete"
      end
      lineage_line = candidate_template.lines.find { |line| line.start_with?("evidence_lineage:") }
      unless lineage_line && EVIDENCE_LINEAGES.all? { |value| lineage_line.include?(value) }
        raise "candidate template evidence lineage vocabulary is incomplete"
      end
      missing_lineage, missing_lineage_body = parse_document(candidate_template)
      missing_lineage.delete("evidence_lineage")
      missing_lineage.delete("evidence_lineage_note")
      begin
        validate_candidate(
          missing_lineage,
          missing_lineage_body,
          label: "new candidate without evidence lineage",
          routed: false
        )
        raise "new candidate without evidence lineage was accepted"
      rescue Error => e
        raise unless e.message.include?("evidence_lineage must be a non-empty string")
      end
      trigger_type_line = decision_template.lines.find { |line| line.start_with?("review_trigger_type:") }
      unless trigger_type_line && REVIEW_TRIGGER_TYPES.all? { |value| trigger_type_line.include?(value) }
        raise "decision template trigger type vocabulary is incomplete"
      end
      trigger_observer_line = decision_template.lines.find do |line|
        line.start_with?("review_trigger_observer:")
      end
      unless trigger_observer_line &&
          REVIEW_TRIGGER_OBSERVERS.all? { |value| trigger_observer_line.include?(value) }
        raise "decision template trigger observer vocabulary is incomplete"
      end
      PAPERCUT_CLASSIFICATIONS.each do |field, values|
        line = papercut_template.lines.find { |candidate| candidate.start_with?("#{field}:") }
        unless line && values.all? { |value| line.include?(value) }
          raise "papercut template #{field} vocabulary is incomplete"
        end
        repair_line = papercut_repair_template.lines.find do |candidate|
          candidate.start_with?("#{field}:")
        end
        unless repair_line && values.all? { |value| repair_line.include?(value) }
          raise "papercut repair template #{field} vocabulary is incomplete"
        end
      end
      File.write(input, candidate_template.gsub("Short candidate title", "Atomic routing"))

      store = Store.new(root)
      store.init

      base_decision, decision_body = parse_document(decision_template)
      base_decision.merge!(self_test_deferral_fields)
      base_decision["candidate_id"] = "RC-20260715T120000Z-000000"
      base_decision["reviewed_at"] = "2026-07-15T11:59:00Z"
      base_contract = base_decision.slice(*review_trigger_contract_fields)
      trigger_variant = lambda do |trigger_type|
        variant = base_contract.dup
        REVIEW_TRIGGER_TYPE_FIELDS.values.flatten.each { |field| variant.delete(field) }
        variant["review_trigger_type"] = trigger_type
        variant["review_trigger_observer"] = "learning-process-review"
        case trigger_type
        when "date"
          variant["review_trigger_at"] = "2026-08-27"
          variant["review_trigger_probe"] = "Compare the current UTC date with review_trigger_at."
        when "state-threshold"
          variant["review_trigger_counter"] = "candidate_archives_total from artifact-audit-status"
          variant["review_trigger_threshold"] = 10
          variant["review_trigger_probe"] = "Run retro-state.rb artifact-audit-status."
        when "external-artifact"
          variant["review_trigger_locator"] = "upstream-release-x"
          variant["review_trigger_probe"] = "Inspect the named upstream release artifact."
        when "explicit-input"
          variant["review_trigger_input"] = "A bounded user decision supplied to triage."
          variant["review_trigger_probe"] = "Confirm the named input is present in the triage request."
        when "destination-use"
          variant["review_trigger_destination"] = "skills/example/SKILL.md"
        end
        variant
      end

      %w[date state-threshold external-artifact explicit-input].each do |trigger_type|
        validate_review_trigger_contract(
          trigger_variant.call(trigger_type),
          "#{trigger_type} trigger",
          legacy_allowed: false
        )
      end

      missing_contract = base_decision.dup
      missing_contract.delete("review_trigger_contract_version")
      begin
        validate_decision(missing_contract, decision_body, label: "missing trigger contract")
        raise "deferred decision without a trigger contract was accepted"
      rescue Error => e
        raise unless e.message.include?("review_trigger_contract_version must be")
      end

      missing_unresolved_decision = base_decision.dup
      missing_unresolved_decision.delete("unresolved_decision")
      begin
        validate_decision(
          missing_unresolved_decision,
          decision_body,
          label: "missing unresolved decision"
        )
        raise "deferred decision without an unresolved decision was accepted"
      rescue Error => e
        raise unless e.message.include?("unresolved_decision must be a non-empty string")
      end

      begin
        validate_review_trigger_contract(
          trigger_variant.call("destination-use"),
          "destination-use trigger",
          legacy_allowed: false
        )
        raise "destination-use trigger without a matcher was accepted"
      rescue Error => e
        raise unless e.message.include?("destination-use triggers require a supported destination matcher")
      end

      invalid_date = trigger_variant.call("date").merge("review_trigger_at" => "2026-02-30")
      begin
        validate_review_trigger_contract(invalid_date, "invalid date trigger", legacy_allowed: false)
        raise "invalid date trigger was accepted"
      rescue Error => e
        raise unless e.message.include?("review_trigger_at must be an ISO date")
      end

      invalid_threshold = trigger_variant.call("state-threshold").merge(
        "review_trigger_threshold" => 0
      )
      begin
        validate_review_trigger_contract(
          invalid_threshold,
          "invalid threshold trigger",
          legacy_allowed: false
        )
        raise "nonpositive state threshold was accepted"
      rescue Error => e
        raise unless e.message.include?("review_trigger_threshold must be a positive integer")
      end

      missing_counter = trigger_variant.call("state-threshold")
      missing_counter.delete("review_trigger_counter")
      begin
        validate_review_trigger_contract(
          missing_counter,
          "state threshold trigger",
          legacy_allowed: false
        )
        raise "state threshold trigger without a counter was accepted"
      rescue Error => e
        raise unless e.message.include?("review_trigger_counter must be a non-empty string")
      end

      missing_locator = trigger_variant.call("external-artifact")
      missing_locator.delete("review_trigger_locator")
      begin
        validate_review_trigger_contract(
          missing_locator,
          "external artifact trigger",
          legacy_allowed: false
        )
        raise "external artifact trigger without a locator was accepted"
      rescue Error => e
        raise unless e.message.include?("review_trigger_locator must be a non-empty string")
      end

      missing_input = trigger_variant.call("explicit-input")
      missing_input.delete("review_trigger_input")
      begin
        validate_review_trigger_contract(missing_input, "explicit input trigger", legacy_allowed: false)
        raise "explicit input trigger without named input was accepted"
      rescue Error => e
        raise unless e.message.include?("review_trigger_input must be a non-empty string")
      end

      invalid_observer = trigger_variant.call("explicit-input").merge(
        "review_trigger_observer" => "review-queue"
      )
      begin
        validate_review_trigger_contract(
          invalid_observer,
          "invalid trigger observer",
          legacy_allowed: false
        )
        raise "routing surface was accepted as a trigger observer"
      rescue Error => e
        raise unless e.message.include?("review_trigger_observer must be one of")
      end

      invalid_route = trigger_variant.call("explicit-input").merge(
        "review_trigger_route" => "skill-retro-triage"
      )
      begin
        validate_review_trigger_contract(invalid_route, "invalid trigger route", legacy_allowed: false)
        raise "observer was accepted as a trigger route"
      rescue Error => e
        raise unless e.message.include?("review_trigger_route must be review-queue")
      end

      missing_probe = trigger_variant.call("explicit-input")
      missing_probe.delete("review_trigger_probe")
      begin
        validate_review_trigger_contract(missing_probe, "missing trigger probe", legacy_allowed: false)
        raise "trigger without a probe was accepted"
      rescue Error => e
        raise unless e.message.include?("review_trigger_probe must be a non-empty string")
      end

      invalid_draft, invalid_draft_body = parse_document(draft_template)
      invalid_draft.delete("review_trigger_contract_version")
      File.write(draft, render_document(invalid_draft, invalid_draft_body))
      begin
        store.record_draft(draft)
        raise "open draft without a trigger contract was accepted"
      rescue Error => e
        raise unless e.message.include?("review_trigger_contract_version must be")
      end

      invalid_ledger, invalid_ledger_body = parse_document(ledger_template)
      invalid_ledger.delete("review_trigger_contract_version")
      File.write(ledger, render_document(invalid_ledger, invalid_ledger_body))
      begin
        store.record_ledger(ledger)
        raise "open ledger without a trigger contract was accepted"
      rescue Error => e
        raise unless e.message.include?("review_trigger_contract_version must be")
      end

      path = store.route(input)
      id = File.basename(path, ".md")
      raise "pending candidate missing" unless store.pending.map(&:first) == [id]
      store.validate

      File.write(papercut, papercut_template)
      papercut_data, papercut_body = read_document(papercut)
      papercut_path = store.record_papercut(papercut_data, papercut_body, label: papercut)
      papercut_id = File.basename(papercut_path, ".md")
      raise "open papercut missing" unless store.papercuts.map(&:first) == [papercut_id]
      closed_papercut = store.close_papercut(
        papercut_id,
        outcome: "candidate",
        rationale: "The observation was synthesized into a candidate.",
        related_candidate_id: id
      )
      raise "papercut was not archived" unless File.file?(closed_papercut)
      raise "closed papercut remained open" unless store.papercuts.empty?
      raise "archived papercut missing" unless store.papercuts(archive: true).map(&:first) == [papercut_id]

      duplicate_data, duplicate_body = read_document(papercut)
      duplicate_path = store.record_papercut(duplicate_data, duplicate_body, label: papercut)
      duplicate_id = File.basename(duplicate_path, ".md")
      raise "papercut IDs were not unique" if duplicate_id == papercut_id
      store.close_papercut(
        duplicate_id,
        outcome: "duplicate",
        rationale: "The same observation was already recorded.",
        related_papercut_id: papercut_id
      )
      store.validate

      papercut_recovery_root = File.join(tmp, "papercut-recovery-state")
      papercut_recovery_store = Store.new(papercut_recovery_root)
      papercut_recovery_store.init
      recovery_data, recovery_body = read_document(papercut)
      recovery_source = papercut_recovery_store.record_papercut(
        recovery_data,
        recovery_body,
        label: papercut
      )
      recovery_id = File.basename(recovery_source, ".md")
      interrupted_papercut_store = Store.new(
        papercut_recovery_root,
        fault_injector: lambda do |point|
          raise Error, "simulated papercut interruption" if point == :papercut_archive_written
        end
      )
      begin
        interrupted_papercut_store.close_papercut(
          recovery_id,
          outcome: "no-action",
          rationale: "No reusable action was identified."
        )
        raise "papercut interruption was not injected"
      rescue Error => e
        raise unless e.message == "simulated papercut interruption"
      end
      recovery_archive = File.join(
        papercut_recovery_root,
        "papercuts",
        "archive",
        "#{recovery_id}.md"
      )
      unless File.file?(recovery_source) && File.file?(recovery_archive)
        raise "papercut interruption did not retain both recovery inputs"
      end
      archived_before_retry = File.binread(recovery_archive)
      papercut_recovery_store.close_papercut(
        recovery_id,
        outcome: "no-action",
        rationale: "No reusable action was identified."
      )
      raise "recovered papercut remained in inbox" if File.exist?(recovery_source)
      unless File.binread(recovery_archive) == archived_before_retry
        raise "papercut retry changed the existing archive or closure timestamp"
      end
      papercut_recovery_store.validate

      conflicting_data, conflicting_body = read_document(papercut)
      conflicting_source = papercut_recovery_store.record_papercut(
        conflicting_data,
        conflicting_body,
        label: papercut
      )
      conflicting_id = File.basename(conflicting_source, ".md")
      conflicting_store = Store.new(
        papercut_recovery_root,
        fault_injector: lambda do |point|
          raise Error, "simulated papercut conflict" if point == :papercut_archive_written
        end
      )
      begin
        conflicting_store.close_papercut(
          conflicting_id,
          outcome: "no-action",
          rationale: "Original closure rationale."
        )
        raise "papercut conflict interruption was not injected"
      rescue Error => e
        raise unless e.message == "simulated papercut conflict"
      end
      conflicting_archive = File.join(
        papercut_recovery_root,
        "papercuts",
        "archive",
        "#{conflicting_id}.md"
      )
      conflicting_archive_data, conflicting_archive_body = read_document(conflicting_archive)
      conflicting_archive_data.fetch("closure")["rationale"] = "Conflicting closure rationale."
      File.write(
        conflicting_archive,
        render_document(conflicting_archive_data, conflicting_archive_body)
      )
      conflicting_archive_bytes = File.binread(conflicting_archive)
      begin
        papercut_recovery_store.close_papercut(
          conflicting_id,
          outcome: "no-action",
          rationale: "Original closure rationale."
        )
        raise "conflicting papercut archive was accepted"
      rescue Error => e
        raise unless e.message.include?("existing papercut archive differs")
      end
      unless File.binread(conflicting_archive) == conflicting_archive_bytes && File.file?(conflicting_source)
        raise "conflicting papercut archive was overwritten or its inbox record was removed"
      end

      missing_reference_data, missing_reference_body = read_document(papercut)
      missing_reference_path = store.record_papercut(
        missing_reference_data,
        missing_reference_body,
        label: papercut
      )
      missing_reference_id = File.basename(missing_reference_path, ".md")
      begin
        store.close_papercut(
          missing_reference_id,
          outcome: "duplicate",
          rationale: "Invalid missing-reference test.",
          related_papercut_id: "PC-20260715T120000Z-000000"
        )
        raise "missing related papercut was accepted"
      rescue Error => e
        raise unless e.message.include?("related papercut does not exist")
      end
      store.close_papercut(
        missing_reference_id,
        outcome: "no-action",
        rationale: "Closed after the missing-reference test."
      )

      malformed_papercut = File.join(tmp, "malformed-papercut.md")
      File.write(malformed_papercut, papercut_template.sub("impact: retry", "impact: surprise"))
      malformed_data, malformed_body = read_document(malformed_papercut)
      begin
        store.record_papercut(malformed_data, malformed_body, label: malformed_papercut)
        raise "malformed papercut was accepted"
      rescue Error => e
        raise unless e.message.include?("impact must be one of")
      end

      seed_invalid_papercut = lambda do |overrides, recompute_digest: true|
        source_data, source_body = read_document(papercut)
        source_path = store.record_papercut(source_data, source_body, label: papercut)
        assigned, assigned_body = read_document(source_path)
        overrides.each { |field, value| assigned[field] = value }
        if recompute_digest
          intake = without_keys(assigned, "intake_digest", "closure")
          assigned["intake_digest"] = Digest::SHA256.hexdigest(render_document(intake, assigned_body))
        end
        File.write(source_path, render_document(assigned, assigned_body))
        [source_path, assigned, assigned_body]
      end
      build_repair = lambda do |papercut_id, values, accept_current_evidence: false|
        repair, repair_body = parse_document(store.prepare_papercut_repair(papercut_id))
        values.each { |field, value| repair[field] = value }
        repair["accept_current_evidence"] = accept_current_evidence
        File.write(papercut_repair, render_document(repair, repair_body))
      end

      repair_target, invalid_record, invalid_body = seed_invalid_papercut.call(
        {
          "kind" => "orchestration",
          "impact" => "delay",
          "resolution" => "resolved",
          "owner_hint" => "skill"
        },
        recompute_digest: false
      )
      repair_target_id = invalid_record.fetch("papercut_id")
      build_repair.call(
        repair_target_id,
        {
          "kind" => "other",
          "impact" => "blocked",
          "resolution" => invalid_record.fetch("resolution"),
          "owner_hint" => "skill-system"
        }
      )
      repaired_path = store.repair_papercut(repair_target_id, papercut_repair)
      raise "papercut repair changed the target path" unless repaired_path == repair_target
      repaired, repaired_body = read_document(repaired_path)
      raise "papercut repair changed identity" unless repaired["papercut_id"] == repair_target_id
      raise "papercut repair changed evidence body" unless repaired_body == invalid_body
      %w[source_scope observation workaround redaction_review created_at].each do |field|
        raise "papercut repair changed #{field}" unless repaired[field] == invalid_record[field]
      end
      repair_history = repaired.fetch("schema_repairs")
      raise "papercut repair history was not recorded" unless repair_history.length == 1
      repair_entry = repair_history.fetch(0)
      unless repair_entry["prior_intake_digest"] == invalid_record["intake_digest"]
        raise "papercut repair did not preserve the prior digest"
      end
      authenticated = repair_entry.fetch("authenticated_classifications")
      unless authenticated == {
        "kind" => "command",
        "impact" => "retry",
        "resolution" => "worked-around",
        "owner_hint" => "unknown"
      }
        raise "papercut repair did not preserve the authenticated classification tuple"
      end
      unless repair_entry.fetch("changes").keys.sort == %w[impact kind owner_hint]
        raise "papercut repair did not record the exact invalid fields"
      end
      store.validate

      begin
        store.repair_papercut(repair_target_id, papercut_repair)
        raise "already-valid papercut was repaired again"
      rescue Error => e
        raise unless e.message.include?("papercut classifications are already valid")
      end

      history_original = File.read(repaired_path)
      history_tampered = repaired.dup
      history_tampered["schema_repairs"] = repair_history.map(&:dup)
      history_tampered["schema_repairs"][0] = repair_entry.merge("prior_intake_digest" => "0" * 64)
      history_intake = without_keys(history_tampered, "intake_digest", "closure")
      history_tampered["intake_digest"] = Digest::SHA256.hexdigest(
        render_document(history_intake, repaired_body)
      )
      File.write(repaired_path, render_document(history_tampered, repaired_body))
      begin
        store.validate
        raise "tampered papercut repair history was accepted"
      rescue Error => e
        raise unless e.message.include?("prior_intake_digest does not match repair history")
      ensure
        File.write(repaired_path, history_original)
      end

      reclassification_target, reclassification_record, = seed_invalid_papercut.call(
        {"kind" => "orchestration"}
      )
      reclassification_id = reclassification_record.fetch("papercut_id")
      build_repair.call(
        reclassification_id,
        {
          "kind" => "other",
          "impact" => "blocked",
          "resolution" => reclassification_record.fetch("resolution"),
          "owner_hint" => reclassification_record.fetch("owner_hint")
        }
      )
      reclassification_original = File.read(reclassification_target)
      begin
        store.repair_papercut(reclassification_id, papercut_repair)
        raise "papercut repair changed an already-valid classification"
      rescue Error => e
        raise unless e.message.include?("repair must not change already-valid impact")
        raise "failed repair changed its target" unless File.read(reclassification_target) == reclassification_original
      ensure
        File.unlink(reclassification_target)
      end

      authorized_target, authorized_record, = seed_invalid_papercut.call(
        {"kind" => "orchestration"},
        recompute_digest: false
      )
      authorized_id = authorized_record.fetch("papercut_id")
      authorized_data, authorized_body = read_document(authorized_target)
      authorized_data["observation"] = "Sanitized current evidence accepted for compatibility repair."
      File.write(authorized_target, render_document(authorized_data, authorized_body))
      authorized_values = {
        "kind" => "other",
        "impact" => authorized_data.fetch("impact"),
        "resolution" => authorized_data.fetch("resolution"),
        "owner_hint" => authorized_data.fetch("owner_hint")
      }
      build_repair.call(authorized_id, authorized_values)
      begin
        store.repair_papercut(authorized_id, papercut_repair)
        raise "unrecoverable digest was accepted without explicit current-evidence authority"
      rescue Error => e
        raise unless e.message.include?("unrecoverable intake digest requires accept_current_evidence: true")
      end
      build_repair.call(authorized_id, authorized_values, accept_current_evidence: true)
      store.repair_papercut(authorized_id, papercut_repair)
      authorized_repaired, = read_document(authorized_target)
      unless authorized_repaired.dig("schema_repairs", 0, "digest_recovery") == "current-evidence-authorized"
        raise "explicit current-evidence digest recovery was not recorded"
      end
      store.validate

      digest_target, digest_record, = seed_invalid_papercut.call(
        {"kind" => "orchestration"},
        recompute_digest: false
      )
      digest_id = digest_record.fetch("papercut_id")
      build_repair.call(
        digest_id,
        {
          "kind" => "other",
          "impact" => digest_record.fetch("impact"),
          "resolution" => digest_record.fetch("resolution"),
          "owner_hint" => digest_record.fetch("owner_hint")
        }
      )
      File.write(digest_target, File.read(digest_target).sub("Unexpected, avoidable friction", "Altered friction"))
      begin
        store.repair_papercut(digest_id, papercut_repair)
        raise "papercut with a bad original digest was repaired"
      rescue Error => e
        raise unless e.message.include?("observed_intake_digest does not match current papercut")
      ensure
        File.unlink(digest_target)
      end
      store.validate

      archived_original = File.read(closed_papercut)
      File.write(closed_papercut, archived_original.sub("Unexpected, avoidable friction", "Altered friction"))
      begin
        store.validate
        raise "tampered papercut intake was accepted"
      rescue Error => e
        raise unless e.message.include?("papercut intake fields changed after recording")
      ensure
        File.write(closed_papercut, archived_original)
      end

      original = File.read(path)
      File.write(path, original.sub("Atomic routing", "Tampered routing"))
      begin
        store.validate
        raise "tampered intake was accepted"
      rescue Error => e
        raise unless e.message.include?("intake fields changed after routing")
      ensure
        File.write(path, original)
      end

      decision_text = without_review_trigger_contract.call(
        decision_template
        .sub("RC-YYYYMMDDTHHMMSSZ-abcdef", id)
        .sub("YYYY-MM-DDTHH:MM:SSZ", "2026-07-15T12:00:00Z")
        .sub("verdict: defer", "verdict: accept")
      )
      File.write(decision, decision_text)
      archive_path = store.process(id, decision)
      raise "candidate was not archived" unless File.file?(archive_path)
      raise "candidate remained in inbox" if File.exist?(path)
      publication_row = store.review_queue.find do |type, candidate_id, _trigger, _path|
        type == "accepted-publication" && candidate_id == id
      end
      raise "unpublished accepted candidate missing from review queue" unless publication_row

      %i[candidate_archive_written candidate_cadence_written].each do |fault_point|
        recovery_root = File.join(tmp, "candidate-recovery-#{fault_point}")
        recovery_store = Store.new(recovery_root)
        recovery_store.init
        recovery_input = File.join(tmp, "candidate-recovery-#{fault_point}.md")
        recovery_decision = File.join(tmp, "candidate-recovery-#{fault_point}-decision.md")
        File.write(
          recovery_input,
          candidate_template.gsub("Short candidate title", "Recoverable candidate archival")
        )
        recovery_source = recovery_store.route(recovery_input)
        recovery_id = File.basename(recovery_source, ".md")
        recovery_decision_text = without_review_trigger_contract.call(
          decision_template
          .sub("RC-YYYYMMDDTHHMMSSZ-abcdef", recovery_id)
          .sub("YYYY-MM-DDTHH:MM:SSZ", "2026-07-15T12:00:00Z")
          .sub("verdict: defer", "verdict: reject")
        )
        File.write(recovery_decision, recovery_decision_text)
        interrupted_store = Store.new(
          recovery_root,
          fault_injector: lambda do |point|
            raise Error, "simulated #{fault_point}" if point == fault_point
          end
        )
        begin
          interrupted_store.process(recovery_id, recovery_decision)
          raise "candidate interruption was not injected at #{fault_point}"
        rescue Error => e
          raise unless e.message == "simulated #{fault_point}"
        end

        recovery_archive = File.join(
          recovery_root,
          "retrospectives",
          "archive",
          "#{recovery_id}.md"
        )
        unless File.file?(recovery_source) && File.file?(recovery_archive)
          raise "candidate interruption did not retain both recovery inputs at #{fault_point}"
        end
        archived_before_retry = File.binread(recovery_archive)
        cadence_path = File.join(
          recovery_root,
          "audits",
          "learning-process",
          "artifact-cadence.yml"
        )
        interrupted_cadence = stringify_keys(
          YAML.safe_load(File.read(cadence_path, encoding: "UTF-8"), aliases: false)
        )
        expected_interrupted_total = (fault_point == :candidate_archive_written) ? 0 : 1
        unless interrupted_cadence.fetch("candidate_archives_total") == expected_interrupted_total
          raise "candidate interruption recorded the wrong cadence total at #{fault_point}"
        end

        recovery_store.process(recovery_id, recovery_decision)
        raise "recovered candidate remained in inbox at #{fault_point}" if File.exist?(recovery_source)
        unless File.binread(recovery_archive) == archived_before_retry
          raise "candidate retry changed the existing archive at #{fault_point}"
        end
        final_cadence = stringify_keys(
          YAML.safe_load(File.read(cadence_path, encoding: "UTF-8"), aliases: false)
        )
        unless final_cadence.fetch("candidate_archives_total") == 1 &&
            final_cadence.fetch(COUNTED_CANDIDATE_IDS_FIELD) == [recovery_id]
          raise "candidate retry did not count the archive exactly once at #{fault_point}"
        end
        unless Dir.glob(File.join(recovery_root, "retrospectives", "archive", "*.md")).length == 1
          raise "candidate retry did not retain exactly one archive at #{fault_point}"
        end
        recovery_store.validate
      end

      conflict_root = File.join(tmp, "candidate-recovery-conflict")
      conflict_store = Store.new(conflict_root)
      conflict_store.init
      conflict_input = File.join(tmp, "candidate-recovery-conflict.md")
      conflict_decision = File.join(tmp, "candidate-recovery-conflict-decision.md")
      File.write(
        conflict_input,
        candidate_template.gsub("Short candidate title", "Conflicting candidate archival")
      )
      conflict_source = conflict_store.route(conflict_input)
      conflict_id = File.basename(conflict_source, ".md")
      conflict_decision_text = without_review_trigger_contract.call(
        decision_template
        .sub("RC-YYYYMMDDTHHMMSSZ-abcdef", conflict_id)
        .sub("YYYY-MM-DDTHH:MM:SSZ", "2026-07-15T12:00:00Z")
        .sub("verdict: defer", "verdict: reject")
      )
      File.write(conflict_decision, conflict_decision_text)
      interrupted_conflict_store = Store.new(
        conflict_root,
        fault_injector: lambda do |point|
          raise Error, "simulated candidate conflict" if point == :candidate_archive_written
        end
      )
      begin
        interrupted_conflict_store.process(conflict_id, conflict_decision)
        raise "candidate conflict interruption was not injected"
      rescue Error => e
        raise unless e.message == "simulated candidate conflict"
      end
      conflict_archive = File.join(
        conflict_root,
        "retrospectives",
        "archive",
        "#{conflict_id}.md"
      )
      conflict_archive_data, conflict_archive_body = read_document(conflict_archive)
      conflict_archive_data.fetch("triage")["rationale"] = "Conflicting decision rationale."
      File.write(conflict_archive, render_document(conflict_archive_data, conflict_archive_body))
      conflict_archive_bytes = File.binread(conflict_archive)
      begin
        conflict_store.process(conflict_id, conflict_decision)
        raise "conflicting candidate archive was accepted"
      rescue Error => e
        raise unless e.message.include?("existing candidate archive differs")
      end
      unless File.binread(conflict_archive) == conflict_archive_bytes && File.file?(conflict_source)
        raise "conflicting candidate archive was overwritten or its inbox record was removed"
      end

      accepted_text = accepted_template
        .sub("RC-YYYYMMDDTHHMMSSZ-abcdef", id)
        .sub("# Accepted candidate", "# Make plan-item admission counterfactual and contract-relative")
      File.write(accepted, accepted_text)
      accepted_path = store.record_accepted(accepted)
      raise "accepted record missing" unless File.file?(accepted_path)
      if store.review_queue.any? { |type, candidate_id, _trigger, _path|
           type == "accepted-publication" && candidate_id == id
         }
        raise "published accepted candidate remained in review queue"
      end
      accepted_id = File.basename(accepted_path, ".md")
      accepted_data, = read_document(accepted_path)
      original_accepted_at = accepted_data.fetch("accepted_at")
      destination_rows = store.accepted_records_query(destinations: ["PUBLIC SOURCE"])
      unless destination_rows.map(&:first) == [accepted_id] &&
          destination_rows.first.fetch(2) == "unverified"
        raise "unverified accepted record was not discoverable by destination"
      end
      unless store.accepted_records_query(destinations: ["public source"], active_supported: true).empty?
        raise "supplemental lookup included an unverified outcome"
      end
      text_rows = store.accepted_records_query(texts: ["SANITIZED SUMMARY"])
      unless text_rows.map(&:first) == [accepted_id]
        raise "accepted record was not discoverable by metadata text"
      end
      lookup_snapshot = store.snapshot
      ["PLAN-ITEM ADMISSION", "counterfactual", "CURATED EVIDENCE"].each do |query|
        unless store.accepted_records_query(texts: [query]) == destination_rows
          raise "accepted record heading or body was not discoverable: #{query}"
        end
      end
      unless store.accepted_records_query(destinations: ["unrelated destination"], texts: ["counterfactual"]).empty?
        raise "body lookup ignored the destination filter"
      end
      unless store.accepted_records_query(texts: ["unrelated heading phrase"]).empty?
        raise "body lookup returned an unrelated accepted record"
      end
      raise "accepted-record lookup changed state" unless store.snapshot == lookup_snapshot

      accepted_bytes = File.binread(accepted_path)
      File.write(accepted_path, accepted_bytes + "\nauth.json\n")
      begin
        store.accepted_records_query(texts: ["counterfactual"])
        raise "body lookup bypassed accepted-record privacy validation"
      rescue Error => e
        raise unless e.message.include?("forbidden Codex auth file")
      ensure
        File.binwrite(accepted_path, accepted_bytes)
      end
      begin
        store.accepted_records_query
        raise "unfiltered accepted-record lookup was allowed"
      rescue Error => e
        raise unless e.message.include?("requires --destination TEXT or --text TEXT")
      end

      supported_proposal_text = verification_proposal_template
        .sub("SCR-YYYYMMDD-abcdef", accepted_id)
        .sub("verification_basis: later-session", "verification_basis: deterministic-test")
        .sub("claim: guidance-conformance", "claim: executable-correctness")
      require "open3"
      cli_root = File.join(tmp, "routing-cli")
      FileUtils.cp_r(root, cli_root)
      cli_root = File.realpath(cli_root)
      blocked_parent = File.join(tmp, "routing-git")
      FileUtils.mkdir_p(File.join(blocked_parent, ".git"))
      File.write(File.join(blocked_parent, ".git", "HEAD"), "ref: refs/heads/main\n")
      blocked_root = File.join(blocked_parent, "state")
      cli_snapshot = lambda do
        Dir.glob(File.join(cli_root, "**", "*"), File::FNM_DOTMATCH)
          .select { |path| File.file?(path) }.to_h { |path| [path, File.binread(path)] }
      end
      run_cli = lambda do |command, path, text, selected_root|
        arguments = [RbConfig.ruby, File.expand_path(__FILE__), command, "--file", path]
        arguments += ["--root", selected_root] if selected_root
        Open3.capture3({STATE_ENV => nil}, *arguments, stdin_data: text)
      end
      {"route" => File.read(input), "route-verification" => supported_proposal_text}.each do |command, text|
        cli_input = File.join(tmp, "#{command}-cli.md")
        File.write(cli_input, text)
        expected_data, expected_body = parse_document(text)
        [cli_input, "-"].each do |path|
          before_cli = cli_snapshot.call
          out, err, result = run_cli.call(command, path, text, cli_root)
          routed_path = out.strip
          unless result.success? && err.empty? && File.file?(routed_path) &&
              File.dirname(routed_path) == File.join(cli_root, (command == "route") ? "retrospectives/inbox" : "verifications/inbox")
            raise "#{command} #{path}: CLI routing failed: #{err}"
          end
          routed_data, routed_body = read_document(routed_path)
          identity_field = (command == "route") ? "candidate_id" : "verification_proposal_id"
          unless without_keys(routed_data, identity_field, "created_at", "intake_digest") == expected_data &&
              routed_body.rstrip == expected_body.rstrip
            raise "#{command}: CLI routing changed submission content"
          end
          File.unlink(routed_path)
          raise "#{command}: CLI routing changed existing state" unless cli_snapshot.call == before_cli

          failing_store = Store.new(cli_root)
          failing_store.define_singleton_method(:exclusive_write) { |_destination, _content| raise Errno::ENOSPC }
          fallback_data, fallback_body = parse_document(text)
          begin
            method = (command == "route") ? :route : :route_verification
            failing_store.public_send(method, path, document: [fallback_data, fallback_body])
            raise "#{command}: write failure was not injected"
          rescue Errno::ENOSPC
            unless [fallback_data, fallback_body] == [expected_data, expected_body] && cli_snapshot.call == before_cli
              raise "#{command}: late write failure changed fallback input or existing state"
            end
          end

          [nil, blocked_root].each do |fallback_root|
            out, err, result = run_cli.call(command, path, text, fallback_root)
            unless result.exitstatus == 2 && err.include?("Paste-ready") &&
                parse_document(out) == [expected_data, expected_body] &&
                cli_snapshot.call == before_cli && !File.exist?(blocked_root)
              raise "#{command}: CLI fallback lost input or changed state"
            end
          end

          invalid = text.sub("schema_version: 1", "schema_version: 0")
          File.write(cli_input, invalid) unless path == "-"
          out, err, result = run_cli.call(command, path, invalid, cli_root)
          unless result.exitstatus == 1 && out.empty? && err.include?("schema_version must be 1") &&
              cli_snapshot.call == before_cli
            raise "#{command}: invalid CLI input was not rejected without mutation"
          end
          File.write(cli_input, text)
        end
      end
      Store.new(cli_root).validate
      unless store.verification_opportunities(destination: "public source").first.fetch(4).empty?
        raise "fresh verification opportunity reported pending support"
      end
      File.write(verification_proposal, supported_proposal_text)
      supported_proposal_path = store.route_verification(verification_proposal)
      supported_proposal_id = File.basename(supported_proposal_path, ".md")
      unless store.pending_verifications.map(&:first) == [supported_proposal_id]
        raise "pending verification proposal missing"
      end
      unless store.review_queue.any? { |type, row_id, _trigger, _path|
               type == "verification-proposal" && row_id == supported_proposal_id
             }
        raise "verification proposal missing from review queue"
      end
      unless store.verification_opportunities(destination: "public source").first.fetch(4) ==
          "#{supported_proposal_id}:executable-correctness"
        raise "opportunity query did not expose pending support and claim"
      end
      original_support_bytes = File.binread(supported_proposal_path)
      [supported_proposal_text,
        supported_proposal_text.sub("claim: executable-correctness", "claim: intended-outcome")].each do |repeat|
        File.write(verification_proposal, repeat)
        begin
          store.route_verification(verification_proposal)
          raise "unexplained repeat support was routed"
        rescue Error => e
          raise unless e.message.include?("support already pending: #{supported_proposal_id}")
        end
      end
      unless store.pending_verifications.map(&:first) == [supported_proposal_id] &&
          File.binread(supported_proposal_path) == original_support_bytes
        raise "refused repeat support changed the inbox"
      end

      pending_contradiction_text = supported_proposal_text
        .sub("proposed_verification: supported", "proposed_verification: contradicted")
        .sub("# what_is_false:", "what_is_false:")
      File.write(verification_proposal, pending_contradiction_text)
      pending_contradiction_path = store.route_verification(verification_proposal)
      pending_contradiction_id = File.basename(pending_contradiction_path, ".md")
      pending_reject = verification_decision_template
        .sub("VP-YYYYMMDDTHHMMSSZ-abcdef", pending_contradiction_id)
        .sub("YYYY-MM-DDTHH:MM:SSZ", "2026-07-15T12:00:01Z")
      File.write(verification_decision, pending_reject)
      store.process_verification(pending_contradiction_id, verification_decision)
      support_reject = pending_reject.sub(pending_contradiction_id, supported_proposal_id)
      File.write(verification_decision, support_reject)
      store.process_verification(supported_proposal_id, verification_decision)
      unless store.verification_opportunities(destination: "public source").first.fetch(4).empty?
        raise "rejected support still covered the opportunity"
      end
      File.write(verification_proposal, supported_proposal_text)
      supported_proposal_path = store.route_verification(verification_proposal)
      supported_proposal_id = File.basename(supported_proposal_path, ".md")

      supplemental_data, supplemental_body = parse_document(supported_proposal_text)
      supplemental_data["supplemental_reason"] = "Exercises a distinct failure boundary absent from pending support."
      supplemental_data["observation"] = "The previously untested failure boundary holds."
      supplemental_data["decisive_evidence"] = ["A distinct failure-boundary check passed."]
      supplemental_text = render_document(supplemental_data, supplemental_body)
      File.write(verification_proposal, supplemental_text)
      supplemental_path = store.route_verification(verification_proposal)
      supplemental_id = File.basename(supplemental_path, ".md")
      ["", false].each do |invalid_reason|
        validate_verification_proposal(
          supplemental_data.merge("supplemental_reason" => invalid_reason),
          supplemental_body, label: "invalid supplemental reason", routed: false
        )
        raise "invalid supplemental rationale was accepted"
      rescue Error => e
        raise unless e.message.include?("supplemental_reason must be a non-empty string")
      end
      begin
        invalid_supplement = supplemental_data.merge(
          "proposed_verification" => "contradicted", "what_is_false" => "A boundary fails."
        )
        validate_verification_proposal(
          invalid_supplement, supplemental_body, label: "contradiction with supplement", routed: false
        )
        raise "contradiction accepted a supplemental support rationale"
      rescue Error => e
        raise unless e.message.include?("supplemental_reason is only for supported proposals")
      end
      cadence_before_verification = store.artifact_audit_status
      supported_decision_text = verification_decision_template
        .sub("VP-YYYYMMDDTHHMMSSZ-abcdef", supported_proposal_id)
        .sub("verdict: reject", "verdict: apply")
        .sub("YYYY-MM-DDTHH:MM:SSZ", "2026-07-15T12:01:00Z")
      File.write(verification_decision, supported_decision_text)
      supported_archive_path = store.process_verification(supported_proposal_id, verification_decision)
      raise "verification proposal was not archived" unless File.file?(supported_archive_path)
      unless store.pending_verifications.map(&:first) == [supplemental_id]
        raise "primary application removed supplemental support"
      end
      unless store.artifact_audit_status == cadence_before_verification
        raise "verification proposal changed candidate artifact-audit cadence"
      end
      supported_accepted, supported_accepted_body = read_document(accepted_path)
      raise "verification proposal was not applied" unless supported_accepted["verification"] == "supported"
      unless supported_accepted["verification_basis"] == "deterministic-test"
        raise "verification proposal basis was not applied"
      end
      unless supported_accepted.fetch("applied_verification_proposal_ids") == [supported_proposal_id]
        raise "accepted record did not retain applied verification proposal identity"
      end
      supported_rows = store.accepted_records_query(texts: ["sanitized summary"])
      unless supported_rows.map(&:first) == [accepted_id] &&
          supported_rows.first.fetch(2) == "supported"
        raise "supported accepted record was not discoverable by metadata text"
      end
      supported_destination_rows = store.accepted_records_query(destinations: ["public source"])
      unless supported_destination_rows.map(&:first) == [accepted_id] &&
          supported_destination_rows.first.fetch(2) == "supported"
        raise "supported accepted record was not discoverable by destination"
      end
      unless store.accepted_records_query(destinations: ["unrelated destination"]).empty?
        raise "unrelated destination supplied a false accepted-record match"
      end
      if store.verification_opportunities(destination: "public source").map(&:first).include?(accepted_id)
        raise "supported accepted record remained in the unverified opportunity query"
      end

      lookup_cli = self_test_cli(root)
      lookup_cli.call(1, "accepted-records", "--active-supported", error: "requires --destination TEXT or --text TEXT")
      lookup_cli.call(2, "snapshot", "--active-supported", error: "--active-supported is not valid")
      unless lookup_cli.call(0, "accepted-records", "--help").include?("--active-supported")
        raise "accepted-record lookup help omitted its supplemental filter"
      end
      lookup_snapshot = store.snapshot
      lookup_bytes = File.binread(accepted_path)
      begin
        {
          "accepted" => [accepted_id], "implemented" => [accepted_id],
          "no-change" => [], "superseded" => [], "reverted" => []
        }.each do |disposition, expected_ids|
          File.write(
            accepted_path,
            render_document(supported_accepted.merge("disposition" => disposition), supported_accepted_body)
          )
          before_query = store.snapshot
          filtered = lookup_cli.call(
            0, "accepted-records", "--active-supported",
            "--destination", "PUBLIC SOURCE", "--text", "COUNTERFACTUAL"
          )
          unless filtered.lines.map { |line| line.split("\t").first } == expected_ids
            raise "supplemental CLI lookup selected the wrong outcomes for #{disposition}"
          end
          broad = lookup_cli.call(0, "accepted-records", "--text", "COUNTERFACTUAL")
          unless broad.split("\t").first(3) == [accepted_id, disposition, "supported"]
            raise "default CLI lookup hid an outcome for #{disposition}"
          end
          raise "accepted-record lookup changed state" unless store.snapshot == before_query
        end
      ensure
        File.binwrite(accepted_path, lookup_bytes)
      end
      unless lookup_cli.call(0, "accepted-records", "--active-supported", "--destination", "unrelated").empty? &&
          lookup_cli.call(0, "accepted-records", "--active-supported", "--destination", "public source", "--text", "unrelated").empty?
        raise "supplemental CLI lookup ignored a destination or text filter"
      end
      raise "supplemental lookup changed state" unless store.snapshot == lookup_snapshot

      File.write(verification_proposal, supported_proposal_text)
      begin
        store.route_verification(verification_proposal)
        raise "supported target accepted unexplained repeat support"
      rescue Error => e
        raise unless e.message.include?("already supported; add supplemental_reason")
      end
      supplemental_decision = supported_decision_text.sub(supported_proposal_id, supplemental_id)
      File.write(verification_decision, supplemental_decision)
      store.process_verification(supplemental_id, verification_decision)
      supplemented, = read_document(accepted_path)
      unless supplemented["verification"] == "supported" &&
          supplemented["observed_behavior"].include?(supported_accepted.fetch("observed_behavior")) &&
          supplemented["observed_behavior"].include?(supplemental_data.fetch("observation")) &&
          supplemented["decisive_evidence"] ==
              (supported_accepted.fetch("decisive_evidence") + supplemental_data.fetch("decisive_evidence")).uniq &&
          supplemented["applied_verification_proposal_ids"] == [supported_proposal_id, supplemental_id]
        raise "supplemental support lost accepted state, observations, evidence, or provenance"
      end
      if store.pending_verifications.any?
        raise "applied supplemental support remained pending"
      end

      contradicted_proposal_text = verification_proposal_template
        .sub("SCR-YYYYMMDD-abcdef", accepted_id)
        .sub("proposed_verification: supported", "proposed_verification: contradicted")
        .sub(
          '# what_is_false: "What the accepted outcome asserted that is now false."',
          'what_is_false: "The accepted outcome remains correct; this proposal is rejected."'
        )
      File.write(verification_proposal, contradicted_proposal_text)
      contradicted_proposal_path = store.route_verification(verification_proposal)
      contradicted_proposal_id = File.basename(contradicted_proposal_path, ".md")
      rejected_decision_text = verification_decision_template
        .sub("VP-YYYYMMDDTHHMMSSZ-abcdef", contradicted_proposal_id)
        .sub("YYYY-MM-DDTHH:MM:SSZ", "2026-07-15T12:02:00Z")
      File.write(verification_decision, rejected_decision_text)
      rejected_archive_path = store.process_verification(contradicted_proposal_id, verification_decision)
      raise "rejected verification proposal was not archived" unless File.file?(rejected_archive_path)
      rejected_accepted, rejected_accepted_body = read_document(accepted_path)
      unless rejected_accepted["verification"] == "supported" &&
          rejected_accepted.fetch("applied_verification_proposal_ids") == [supported_proposal_id, supplemental_id]
        raise "rejected verification proposal changed accepted state"
      end
      unless store.artifact_audit_status == cadence_before_verification
        raise "rejected verification proposal changed candidate artifact-audit cadence"
      end
      store.validate

      updated_accepted = without_keys(rejected_accepted, "accepted_id", "accepted_at")
      updated_accepted["disposition"] = "implemented"
      updated_accepted["implementation_commits"] = ["abc1234"]
      updated_accepted_text = render_document(updated_accepted, rejected_accepted_body)
      File.write(accepted, updated_accepted_text)
      updated_accepted_path = store.update_accepted(accepted_id, accepted)
      raise "accepted update changed path" unless updated_accepted_path == accepted_path
      stored_updated_accepted, = read_document(updated_accepted_path)
      raise "accepted update changed identity" unless stored_updated_accepted["accepted_id"] == accepted_id
      unless stored_updated_accepted["accepted_at"] == original_accepted_at
        raise "accepted update changed acceptance timestamp"
      end
      raise "accepted update missed disposition" unless stored_updated_accepted["disposition"] == "implemented"
      raise "accepted update missed verification" unless stored_updated_accepted["verification"] == "supported"

      relocated_accepted = without_keys(stored_updated_accepted, "accepted_id", "accepted_at")
      relocated_accepted["destination"] = "Relocated public source destination."
      relocated_accepted["implementation_commits"] = ["def5678"]
      File.write(accepted, render_document(relocated_accepted, rejected_accepted_body))
      store.update_accepted(accepted_id, accepted)
      stored_relocated_accepted, = read_document(accepted_path)
      unless stored_relocated_accepted["destination"] == relocated_accepted["destination"] &&
          stored_relocated_accepted["implementation_commits"] == ["abc1234", "def5678"]
        raise "accepted relocation lost its original implementation commit or new destination"
      end
      %w[accepted_id accepted_at verification verification_basis applied_verification_proposal_ids].each do |field|
        unless stored_relocated_accepted[field] == stored_updated_accepted[field]
          raise "accepted relocation changed #{field}"
        end
      end
      relocated_bytes = File.binread(accepted_path)
      store.update_accepted(accepted_id, accepted)
      unless File.binread(accepted_path) == relocated_bytes
        raise "accepted relocation retry changed provenance"
      end

      changed_lineage = updated_accepted_text.sub(id, "RC-20260715T120000Z-000000")
      File.write(accepted, changed_lineage)
      begin
        store.update_accepted(accepted_id, accepted)
        raise "changed accepted lineage was accepted"
      rescue Error => e
        raise unless e.message.include?("originating_candidate_ids must not change")
      end
      begin
        store.update_accepted("SCR-20260715-000000", accepted)
        raise "missing accepted record was updated"
      rescue Error => e
        raise unless e.message.include?("accepted record not found")
      end
      store.validate

      File.write(draft, draft_template)
      draft_path = store.record_draft(draft)
      raise "draft record missing" unless File.file?(draft_path)
      draft_id = File.basename(draft_path, ".md")
      File.write(ledger, ledger_template)
      ledger_path = store.record_ledger(ledger)
      raise "ledger record missing" unless File.file?(ledger_path)
      ledger_id = File.basename(ledger_path, ".md")
      [draft_path, ledger_path].each do |legacy_path|
        legacy_data, legacy_body = read_document(legacy_path)
        legacy_review_trigger_fields.each { |field| legacy_data.delete(field) }
        File.write(legacy_path, render_document(legacy_data, legacy_body))
      end
      store.validate

      supported_contradiction_text = verification_proposal_template
        .sub("SCR-YYYYMMDD-abcdef", accepted_id)
        .sub("proposed_verification: supported", "proposed_verification: contradicted")
        .sub(
          '# what_is_false: "What the accepted outcome asserted that is now false."',
          'what_is_false: "The earlier action is not safe under the observed condition."'
        )
      File.write(verification_proposal, supported_contradiction_text)
      supported_contradiction_path = store.route_verification(verification_proposal)
      supported_contradiction_id = File.basename(supported_contradiction_path, ".md")
      supported_contradiction_decision = verification_decision_template
        .sub("VP-YYYYMMDDTHHMMSSZ-abcdef", supported_contradiction_id)
        .sub("verdict: reject", "verdict: apply")
        .sub("YYYY-MM-DDTHH:MM:SSZ", "2026-07-15T12:03:00Z")
      File.write(verification_decision, supported_contradiction_decision)
      store.process_verification(supported_contradiction_id, verification_decision)
      assigned_contradiction, rejected_accepted_body = read_document(accepted_path)
      prior_evidence_preserved = stored_updated_accepted.fetch("decisive_evidence").all? do |evidence|
        assigned_contradiction.fetch("decisive_evidence").include?(evidence)
      end
      unless assigned_contradiction["verification"] == "contradicted" &&
          assigned_contradiction["accepted_id"] == accepted_id &&
          assigned_contradiction["accepted_at"] == original_accepted_at &&
          assigned_contradiction.fetch("applied_verification_proposal_ids") ==
              [supported_proposal_id, supplemental_id, supported_contradiction_id] &&
          prior_evidence_preserved
        raise "supported contradiction did not preserve accepted identity and evidence"
      end
      unless store.accepted_records_query(destinations: ["public source"], active_supported: true).empty? &&
          store.accepted_records_query(destinations: ["public source"]).first.fetch(2) == "contradicted"
        raise "accepted-record lookup lost the supplemental or broad contradiction boundary"
      end
      contradiction_bytes = File.binread(accepted_path)
      File.write(verification_proposal, supplemental_text)
      begin
        store.route_verification(verification_proposal)
        raise "supplemental support revived a contradicted target"
      rescue Error => e
        raise unless e.message.include?("state contradicted cannot receive proposed supported")
      end
      unless File.binread(accepted_path) == contradiction_bytes
        raise "refused supplemental support changed contradictory evidence"
      end
      contradicted_data = without_keys(assigned_contradiction, "accepted_id", "accepted_at")
      unless store.review_queue.map(&:first).include?("contradiction")
        raise "contradicted accepted record missing from review queue"
      end
      begin
        altered_contradiction = contradicted_data.fetch("contradiction").merge(
          "decisive_evidence" => ["Replacement evidence that erases the original witness."]
        )
        File.write(
          accepted,
          render_document(
            contradicted_data.merge("contradiction" => altered_contradiction),
            rejected_accepted_body
          )
        )
        store.update_accepted(accepted_id, accepted)
        raise "contradiction evidence was allowed to disappear"
      rescue Error => e
        raise unless e.message.include?("contradiction decisive_evidence must be preserved")
      end
      ledger_contradicted_data = contradicted_data.merge(
        "contradiction" => contradicted_data.fetch("contradiction").merge(
          "residual_ledger_id" => ledger_id
        )
      )
      ledger_contradicted_text = render_document(ledger_contradicted_data, rejected_accepted_body)
      File.write(accepted, ledger_contradicted_text)
      store.update_accepted(accepted_id, accepted)
      if store.review_queue.map(&:first).include?("contradiction")
        raise "contradiction remained in the review queue after assignment to a residual ledger"
      end
      begin
        store.close_ledger(ledger_id, rationale: "Invalid early closure.")
        raise "residual contradiction ledger was closed early"
      rescue Error => e
        raise unless e.message.include?("unresolved contradicted record")
      end

      File.write(ledger, ledger_template)
      retained_ledger_path = store.record_ledger(ledger)
      retained_ledger_id = File.basename(retained_ledger_path, ".md")
      retained_ledger_data = contradicted_data.merge(
        "contradiction" => contradicted_data.fetch("contradiction").merge(
          "residual_ledger_id" => retained_ledger_id,
          "resolution" => {
            "outcome" => "retained",
            "rationale" => "Review found that the existing guidance remains appropriate despite the failure.",
            "resolved_at" => "2026-07-15T12:04:00Z"
          }
        )
      )
      File.write(accepted, render_document(retained_ledger_data, rejected_accepted_body))
      store.update_accepted(accepted_id, accepted)
      store.close_ledger(retained_ledger_id, rationale: "Guidance retained with the contradiction preserved.")
      store.validate
      unless read_document(retained_ledger_path).first.fetch("status") == "closed" &&
          read_document(accepted_path).first.fetch("verification") == "contradicted"
        raise "retained resolution did not close the residual action while preserving contradiction"
      end
      closed_residual_snapshot = store.snapshot
      File.write(
        accepted,
        render_document(
          retained_ledger_data.merge(
            "contradiction" => without_keys(retained_ledger_data.fetch("contradiction"), "resolution")
          ),
          rejected_accepted_body
        )
      )
      begin
        store.update_accepted(accepted_id, accepted)
        raise "reopened contradiction accepted a closed residual ledger"
      rescue Error => e
        raise unless e.message.include?("unresolved contradiction requires an open residual ledger")
      end
      raise "invalid residual reopening changed state" unless store.snapshot == closed_residual_snapshot
      superseded_text = render_document(
        ledger_contradicted_data.merge("disposition" => "superseded"),
        rejected_accepted_body
      )
      File.write(accepted, superseded_text)
      store.update_accepted(accepted_id, accepted)

      correction_text = candidate_template
        .gsub("Short candidate title", "Correct an accepted outcome")
        .sub(
          "# supersedes_accepted_id: SCR-YYYYMMDD-abcdef",
          "supersedes_accepted_id: #{accepted_id}"
        )
        .sub(
          '# now_false: "What the earlier accepted outcome asserted that is now false."',
          'now_false: "The earlier action is unsafe under the distinguishing condition."'
        )
      File.write(input, correction_text)
      correction_path = store.route(input)
      correction_id = File.basename(correction_path, ".md")
      correction_decision = without_review_trigger_contract.call(
        decision_template
        .sub("RC-YYYYMMDDTHHMMSSZ-abcdef", correction_id)
        .sub("YYYY-MM-DDTHH:MM:SSZ", "2026-07-15T12:04:00Z")
        .sub("verdict: defer", "verdict: accept")
      )
      File.write(decision, correction_decision)
      store.process(correction_id, decision)
      correction_accepted_text = accepted_template.sub("RC-YYYYMMDDTHHMMSSZ-abcdef", correction_id)
      File.write(accepted, correction_accepted_text)
      correction_accepted_path = store.record_accepted(accepted)
      correction_accepted, = read_document(correction_accepted_path)
      unless correction_accepted["supersedes_accepted_ids"] == [accepted_id]
        raise "accepted correction did not preserve the superseded outcome link"
      end
      unless store.verification_opportunities(destination: "Public source").map(&:first)
          .include?(correction_accepted.fetch("accepted_id"))
        raise "relevant verification opportunity missing"
      end

      applied_contradiction_text = verification_proposal_template
        .sub("SCR-YYYYMMDD-abcdef", correction_accepted.fetch("accepted_id"))
        .sub("proposed_verification: supported", "proposed_verification: contradicted")
        .sub(
          '# what_is_false: "What the accepted outcome asserted that is now false."',
          'what_is_false: "The corrected outcome does not hold under the observed condition."'
        )
      File.write(verification_proposal, applied_contradiction_text)
      applied_contradiction_path = store.route_verification(verification_proposal)
      applied_contradiction_id = File.basename(applied_contradiction_path, ".md")
      applied_contradiction_decision = verification_decision_template
        .sub("VP-YYYYMMDDTHHMMSSZ-abcdef", applied_contradiction_id)
        .sub("verdict: reject", "verdict: apply")
        .sub("YYYY-MM-DDTHH:MM:SSZ", "2026-07-15T12:04:30Z")
      File.write(verification_decision, applied_contradiction_decision)
      store.process_verification(applied_contradiction_id, verification_decision)
      contradicted_correction, = read_document(correction_accepted_path)
      applied_state = [
        contradicted_correction["verification"],
        contradicted_correction.dig("contradiction", "what_is_false")
      ]
      unless applied_state == [
        "contradicted",
        "The corrected outcome does not hold under the observed condition."
      ]
        raise "contradicted verification proposal was not applied"
      end
      unless store.review_queue.any? { |type, row_id, _trigger, _path|
               type == "contradiction" && row_id == correction_accepted.fetch("accepted_id")
             }
        raise "applied contradiction proposal did not create a review obligation"
      end
      store.validate

      missing_supersession = correction_text.sub(accepted_id, "SCR-20260715-000000")
      File.write(input, missing_supersession)
      begin
        store.route(input)
        raise "candidate superseding a missing accepted outcome was routed"
      rescue Error => e
        raise unless e.message.include?("candidate supersedes missing accepted record")
      end

      File.write(input, candidate_template.gsub("Short candidate title", "Atomic routing"))
      deferred_path = store.route(input)
      deferred_id = File.basename(deferred_path, ".md")
      deferred_data, deferred_body = parse_document(decision_template)
      deferred_data.merge!(self_test_deferral_fields)
      deferred_data["candidate_id"] = deferred_id
      deferred_data["reviewed_at"] = "2026-07-15T12:05:00Z"
      deferred_decision = render_document(deferred_data, deferred_body)
      File.write(decision, deferred_decision)
      deferred_archive_path = store.process(deferred_id, decision)
      legacy_deferred, legacy_deferred_body = read_document(deferred_archive_path)
      legacy_review_trigger_fields.each do |field|
        legacy_deferred.fetch("triage").delete(field)
      end
      File.write(
        deferred_archive_path,
        render_document(legacy_deferred, legacy_deferred_body)
      )
      store.validate
      review_types = store.review_queue.map(&:first)
      raise "deferral missing from review queue" unless review_types.include?("deferred")
      raise "draft missing from review queue" unless review_types.include?("draft")
      raise "ledger missing from review queue" unless review_types.include?("ledger")

      File.write(input, candidate_template.gsub("Short candidate title", "Merge into deferral"))
      merged_path = store.route(input)
      merged_id = File.basename(merged_path, ".md")
      merged_decision = without_review_trigger_contract.call(
        decision_template
        .sub("RC-YYYYMMDDTHHMMSSZ-abcdef", merged_id)
        .sub("YYYY-MM-DDTHH:MM:SSZ", "2026-07-15T12:05:30Z")
        .sub("verdict: defer", "verdict: merge")
        .sub("related_candidate_ids: []", "related_candidate_ids:\n  - #{deferred_id}")
      )
      File.write(decision, merged_decision)
      store.process(merged_id, decision)
      if store.review_queue.any? { |type, row_id, _trigger, _path|
           type == "accepted-publication" && row_id == merged_id
         }
        raise "merge into deferred candidate created a publication obligation"
      end

      File.write(input, candidate_template.gsub("Short candidate title", "Merge into deferred merge"))
      nested_merged_path = store.route(input)
      nested_merged_id = File.basename(nested_merged_path, ".md")
      nested_merged_decision = without_review_trigger_contract.call(
        decision_template
        .sub("RC-YYYYMMDDTHHMMSSZ-abcdef", nested_merged_id)
        .sub("YYYY-MM-DDTHH:MM:SSZ", "2026-07-15T12:05:45Z")
        .sub("verdict: defer", "verdict: merge")
        .sub("related_candidate_ids: []", "related_candidate_ids:\n  - #{merged_id}")
      )
      File.write(decision, nested_merged_decision)
      store.process(nested_merged_id, decision)
      if store.review_queue.any? { |type, row_id, _trigger, _path|
           type == "accepted-publication" && row_id == nested_merged_id
         }
        raise "nested merge into deferred candidate created a publication obligation"
      end

      cycle_a_id = "RC-20260715T120546Z-000001"
      cycle_b_id = "RC-20260715T120547Z-000002"
      cycle_candidates = {
        cycle_a_id => {
          "triage" => {"verdict" => "merge", "related_candidate_ids" => [cycle_b_id]}
        },
        cycle_b_id => {
          "triage" => {"verdict" => "merge", "related_candidate_ids" => [cycle_a_id]}
        }
      }
      if store.accepted_publication_expected?(cycle_candidates.fetch(cycle_a_id).fetch("triage"), cycle_candidates)
        raise "merge cycle created a publication obligation"
      end

      unless store.artifact_audit_status(archive_threshold: 1).fetch(:due)
        raise "artifact audit did not become due after candidate archives"
      end
      audit_text = learning_audit_template
        .sub("audit_kind: learning-process", "audit_kind: skill-repository")
        .sub(
          "unresolved_action_ids: []",
          "unresolved_action_ids:\n  - #{deferred_id}\n  - #{draft_id}\n  - #{ledger_id}"
        )
      File.write(audit, audit_text)
      audit_path = store.record_audit(audit)
      raise "system audit missing" unless File.file?(audit_path)
      raise "system audit missing from history" unless store.audits.map(&:first).include?(File.basename(audit_path, ".md"))
      if store.artifact_audit_status(archive_threshold: 1).fetch(:due)
        raise "completed artifact audit did not reset cadence"
      end

      refreshed_data = deferred_data.merge(
        "reviewed_at" => "2026-07-15T12:06:00Z",
        "review_trigger" => "A second independent observation is recorded."
      )
      refreshed_decision = render_document(refreshed_data, deferred_body)
      File.write(decision, refreshed_decision)
      store.reconsider(deferred_id, decision)
      refreshed_candidate, refreshed_body = read_document(deferred_archive_path)
      validate_candidate(
        refreshed_candidate,
        refreshed_body,
        label: deferred_archive_path,
        routed: true,
        archived: true
      )
      unless refreshed_candidate.fetch("triage_history").map { |item| item.fetch("verdict") } == ["defer"]
        raise "refreshed deferral did not preserve prior triage"
      end
      refreshed_row = store.review_queue.find { |type, id, _trigger, _path| type == "deferred" && id == deferred_id }
      unless refreshed_row && refreshed_row.fetch(2) == "A second independent observation is recorded."
        raise "refreshed deferral did not update the review queue trigger"
      end

      stale_decision = refreshed_decision.sub("2026-07-15T12:06:00Z", "2026-07-15T12:05:30Z")
      File.write(decision, stale_decision)
      begin
        store.reconsider(deferred_id, decision)
        raise "stale replacement decision was accepted"
      rescue Error => e
        raise unless e.message.include?("replacement decision must be newer")
      end

      accepted_decision = without_review_trigger_contract.call(
        decision_template
        .sub("RC-YYYYMMDDTHHMMSSZ-abcdef", deferred_id)
        .sub("YYYY-MM-DDTHH:MM:SSZ", "2026-07-15T12:07:00Z")
        .sub("verdict: defer", "verdict: accept")
      )
      File.write(decision, accepted_decision)
      store.reconsider(deferred_id, decision)
      accepted_candidate, accepted_body = read_document(deferred_archive_path)
      validate_candidate(
        accepted_candidate,
        accepted_body,
        label: deferred_archive_path,
        routed: true,
        archived: true
      )
      unless accepted_candidate.fetch("triage_history").map { |item| item.fetch("verdict") } == %w[defer defer]
        raise "accepted reconsideration did not preserve complete triage history"
      end
      raise "replacement verdict was not stored" unless accepted_candidate.dig("triage", "verdict") == "accept"
      unless store.review_queue.any? { |type, row_id, _trigger, _path|
               type == "accepted-publication" && row_id == merged_id
             }
        raise "merge into accepted candidate missing publication obligation"
      end
      unless store.review_queue.any? { |type, row_id, _trigger, _path|
               type == "accepted-publication" && row_id == nested_merged_id
             }
        raise "nested merge into accepted candidate missing publication obligation"
      end
      if store.review_queue.any? { |type, id, _trigger, _path| type == "deferred" && id == deferred_id }
        raise "resolved deferral remained in the review queue"
      end
      begin
        store.reconsider(deferred_id, decision)
        raise "non-deferred candidate was reconsidered"
      rescue Error => e
        raise unless e.message.include?("candidate is not currently deferred")
      end

      closed_ledger = store.close_ledger(ledger_id, rationale: "The maintenance action was completed.")
      closed_data, closed_body = read_document(closed_ledger)
      raise "ledger was not closed" unless closed_data["status"] == "closed"
      raise "ledger review timestamp was not updated" unless closed_data["last_reviewed"].end_with?("Z")
      unless closed_data.dig("closure", "rationale") == "The maintenance action was completed."
        raise "ledger closure rationale missing"
      end
      legacy_closed_data = without_keys(closed_data, "closure")
      File.write(closed_ledger, render_document(legacy_closed_data, closed_body))
      store.validate
      if store.review_queue.map(&:first).count("ledger").positive?
        raise "closed ledger remained in review queue"
      end
      begin
        store.close_ledger(ledger_id, rationale: "Invalid repeated closure.")
        raise "already closed ledger was accepted"
      rescue Error => e
        raise unless e.message.include?("ledger is already closed")
      end
      begin
        store.close_ledger("LE-20260715-000000", rationale: "Invalid missing-ledger test.")
        raise "missing ledger was accepted"
      rescue Error => e
        raise unless e.message.include?("ledger not found")
      end
      store.validate

      post_audit_path = store.route(input)
      post_audit_id = File.basename(post_audit_path, ".md")
      post_audit_decision = without_review_trigger_contract.call(
        decision_template
        .sub("RC-YYYYMMDDTHHMMSSZ-abcdef", post_audit_id)
        .sub("YYYY-MM-DDTHH:MM:SSZ", "2026-07-15T12:06:00Z")
        .sub("verdict: defer", "verdict: reject")
      )
      File.write(decision, post_audit_decision)
      store.process(post_audit_id, decision)
      unless store.artifact_audit_status(archive_threshold: 1).fetch(:due)
        raise "artifact audit cadence did not advance after productive triage"
      end
      archived_post_audit_path = File.join(
        store.root,
        "retrospectives",
        "archive",
        "#{post_audit_id}.md"
      )
      File.unlink(archived_post_audit_path)
      unless store.artifact_audit_status(archive_threshold: 1).fetch(:due)
        raise "deleting cold archive history rewound artifact audit cadence"
      end

      forbidden = File.join(tmp, "forbidden.md")
      File.write(forbidden, candidate_template.sub("Optional concise context.", "Raw /home/person/private path."))
      begin
        store.route(forbidden)
        raise "forbidden path was accepted"
      rescue Error => e
        raise unless e.message.include?("unredacted user-home path")
      end

      forbidden_papercut = File.join(tmp, "forbidden-papercut.md")
      File.write(
        forbidden_papercut,
        papercut_template.sub("Optional bounded evidence or context.", "Raw /home/person/private path.")
      )
      forbidden_data, forbidden_body = read_document(forbidden_papercut)
      begin
        store.record_papercut(forbidden_data, forbidden_body, label: forbidden_papercut)
        raise "forbidden papercut was accepted"
      rescue Error => e
        raise unless e.message.include?("unredacted user-home path")
      end

      legacy_root = File.join(tmp, "legacy-state")
      legacy_store = Store.new(legacy_root)
      legacy_store.init
      FileUtils.rm_r(File.join(legacy_root, "verifications"))
      legacy_store.validate
      raise "legacy state reported verification proposals" unless legacy_store.pending_verifications.empty?
      FileUtils.mkdir_p(File.join(legacy_root, "verifications", "inbox"))
      begin
        legacy_store.validate
        raise "partially initialized verification state was accepted"
      rescue Error => e
        raise unless e.message.include?("verification state directory is missing")
      end

      git_root = File.join(tmp, "repo")
      FileUtils.mkdir_p(File.join(git_root, ".git"))
      File.write(File.join(git_root, ".git", "HEAD"), "ref: refs/heads/main\n")
      begin
        Store.new(File.join(git_root, "state")).init
        raise "Git-contained state root was accepted"
      rescue Error => e
        raise unless e.message.include?("must not be inside a Git worktree")
      end

      linked_target = File.join(git_root, "linked-state")
      linked_root = File.join(tmp, "state-link")
      FileUtils.mkdir_p(linked_target)
      File.symlink(linked_target, linked_root)
      begin
        Store.new(linked_root).init
        raise "symlinked Git-contained state root was accepted"
      rescue Error => e
        raise unless e.message.include?("must not be inside a Git worktree")
      end

      begin
        Store.new(File::SEPARATOR)
        raise "filesystem root was accepted as a state root"
      rescue Error => e
        raise unless e.message.include?("state root is too broad")
      end
    end
    true
  end
end

def usage(command = nil)
  details = case command
  when "prepare-decision"
    <<~TEXT
      Usage: retro-state.rb prepare-decision --id ID --verdict VERDICT
                                            [--rationale TEXT] [--root DIR]

      Print an editable Markdown/YAML decision for a candidate (RC-*) in inbox or
      deferred archive, or a verification proposal (VP-*) in inbox.
      Candidate verdicts: #{RetroState::VERDICTS.join(", ")}.
      Verification verdicts: #{RetroState::VERIFICATION_PROPOSAL_VERDICTS.join(", ")}.
      Sets the ID and current UTC reviewed_at; reconsiderations must be newer.
      Optionally supply an already-reviewed, nonblank rationale; otherwise fill the blank.
      Deferrals keep safe structural defaults but leave the unresolved decision and
      substantive trigger/action fields blank. Complete them even when supplying a
      rationale; the draft cannot be processed until they are filled.
      Decision templates have empty bodies; add optional notes and related IDs as needed.
      Preparation does not judge the verdict. Review and submit separately through
      process, reconsider, or process-verification; --decision - reads standard input.
    TEXT
  when "prepare-verification"
    <<~TEXT
      Usage: retro-state.rb prepare-verification --id SCR-ID --verification STATE [--root DIR]

      Print an editable Markdown/YAML proposal for the chosen accepted target and proposed
      supported or contradicted state. The target must currently be accepted or implemented,
      with an eligible verification transition. Context comments include its exact opportunity
      and applied/pending proposal IDs; use verification-context to review their evidence.
      Basis, claim, opportunity match, observation, evidence, title, scope, and redaction review
      remain blank. Contradiction adds blank what_is_false; support adds blank supplemental_reason
      when the target is supported or support is pending. Judge these fields deliberately.
      The draft cannot be routed until completed. Review it, then submit separately through
      route-verification --file PATH. Routing rechecks current eligibility and supplementation;
      preparation comments are discarded. Preparation supplies no evidence or routing authority.
    TEXT
  when "prepare-accepted"
    <<~TEXT
      Usage: retro-state.rb prepare-accepted --id RC-ID [--id RC-ID ...]
                                            --commit SHA [--commit SHA ...] [--root DIR]

      Print an incomplete Markdown/YAML draft for a new accepted record. Select archived
      candidates with accept/split verdicts or merge ancestry reaching a known accept/split.
      Missing or empty ancestry stays visible in review-queue but cannot establish acceptance.
      Read only selected origins and merge ancestors needed to resolve acceptance. Comments
      retain their evidence and reviewed triage, including the resolving acceptance rationale;
      originating_candidate_ids still contains only the explicitly selected origins.
      Multiple origins and split outcomes remain supported; existing accepted records do
      not consume an origin.

      Deduplicate selected IDs and commits. Commit SHAs must be 7-40 hexadecimal digits;
      this checks their shape, not existence, publication, or relationship to the outcome.
      No Git command or network access runs, and no accepted identity is allocated.
      Defaults: disposition accepted, verification unverified, basis none. Outcome fields,
      decisive evidence, and redaction review remain incomplete and cannot be recorded as-is.
      Frontmatter comments include prior evidence, reviewed triage, and preparation notes;
      record-accepted discards these comments automatically. Proposed destinations are not
      treated as final. Complete the outcome fields and evidence after verifying
      the public commits, then submit separately with record-accepted --file PATH.
      Use prepare-accepted-update for an existing accepted identity.
    TEXT
  when "prepare-accepted-update"
    <<~TEXT
      Usage: retro-state.rb prepare-accepted-update --id SCR-ID
                                                   [--commit SHA ...] [--destination TEXT]
                                                   [--root DIR]

      Print the accepted record as editable Markdown/YAML, removing only accepted_id
      and accepted_at by default. Repeat --commit to append 7-40 hexadecimal commit SHAs,
      normalized to lowercase and deduplicated while preserving prior commits.
      Supply --destination once to replace it with a nonblank curated destination string.
      Other metadata and the body, including evidence, verification, opportunity, and
      lineage, are preserved; legacy gaps remain visible. No Git or network check runs;
      verify publication and the final destination yourself. Preparation writes no state.
      Review edits, then submit separately through update-accepted --id ID --file PATH.
    TEXT
  when "show"
    <<~TEXT
      Usage: retro-state.rb show --id ID [--id ID ...] [--root DIR]

      Print JSON {root, records}: each record has id, relative path, frontmatter, body.
      Finds inbox and archived records; missing or ambiguous IDs fail without output.
      Parses selected records only; use validate for full state validation.
    TEXT
  when "snapshot"
    <<~TEXT
      Usage: retro-state.rb snapshot [--root DIR] > /tmp/retro-before.json

      Print JSON {snapshot_version, root, entries}, including hidden files and empty
      directories. Files use SHA-256; symlinks record targets and are never followed.
      Save outside the state root. Excludes permissions and timestamps; not atomic.
    TEXT
  when "compare"
    <<~TEXT
      Usage: retro-state.rb compare --file PATH [--allow-path PATH ...]
                                   [--allow-action ACTION:ID ...] [--root DIR]

      Compare this state root with snapshot JSON; --file - reads standard input.
      Print JSON {root, unchanged, matches, added, removed, modified, unexpected}.
      --allow-path permits an exact root-relative path to change; no globs or subtree
      matching. Supported --allow-action forms and exact permitted paths:
        process:RC-ID               Candidate inbox/archive plus cadence cache and lock.
        close-papercut:PC-ID         Papercut inbox/archive.
        reconsider:RC-ID            Candidate archive only.
        record-accepted:SCR-ID       New accepted record only; no writer lock or cadence cache.
        update-accepted:SCR-ID       Accepted record plus writer lock.
        process-verification:VP-ID   Proposal inbox/archive plus writer lock; target for apply.
      The shared writer lock is audits/learning-process/artifact-cadence.lock.
      Accepted updates and verification processing permit no cadence cache changes.
      Verification allowances require a validated, completed archived proposal; missing
      or ambiguous records fail. Rejections permit no accepted-record changes. Use exact
      --allow-path allowances for interrupted verification recovery.
      Both allowance flags combine and repeat. IDs must match the operation's type.
      Allowed paths need not change; allowances do not prove the operation occurred or
      validate its result. Default: no changes permitted. Unrelated changes still fail.
      Exit 0 for matches, 1 for unexpected changes or operational errors, 2 for usage.
      Errors go to stderr without JSON; unexpected changes produce JSON without stderr.
    TEXT
  when "accepted-records"
    <<~TEXT
      Usage: retro-state.rb accepted-records [--destination TEXT ...] [--text TEXT ...]
                                           [--active-supported] [--root DIR]

      Match case-insensitive literal substrings in destinations and metadata/body text,
      including accepted IDs, originating candidate IDs, and implementation commits.
      Repeat either flag to match any term within its group; both groups must match
      when combined. Results are deduplicated in stable ID order.
      Requires --destination or --text; terms must not be blank.
      Default: include all dispositions and verification states.
      --active-supported: include only supported records whose disposition is
      accepted or implemented. Omit it for broader investigations.

      Print TSV: identity, disposition, verification, destination, expected behavior, path.
    TEXT
  when "verification-context"
    <<~TEXT
      Usage: retro-state.rb verification-context --destination TEXT [--destination TEXT ...]
                                                [--text TEXT ...] [--compact]
                                                [--limit N] [--offset N] [--root DIR]
             retro-state.rb verification-context --id ID [--id ID ...] [--root DIR]

      Discovery matches any case-insensitive destination substring, once per accepted
      identity. Includes accepted/implemented outcomes in every verification state.
      Optional --text matches any case-insensitive literal substring in expected_behavior
      or verification_opportunity. Text and destination filters must both match. Filtering
      happens before pagination; total and next_offset describe the filtered result.
      Print JSON {root, mode, destinations, texts, total, limit, offset, next_offset, records}.
      Default limit: 20; positive --limit and nonnegative --offset page stable ID order.
      Summaries include the exact opportunity, verification basis, applied proposal IDs,
      and pending proposal IDs/states/claims. Follow next_offset when more relevant
      records remain; do not treat the first page as complete coverage.
      Both discovery formats include supported_claims and contradicted_claims from
      validated applied proposals, each with verification_proposal_id, claim, and
      verification_basis. Noncompact discovery also includes each observation.
      These describe scoped evidence, not category-wide
      support; pending and rejected proposals never establish support. Positive evidence
      remains visible alongside contradictions. A legacy supported/contradicted status
      without matching typed provenance has null for that claim list, not invented claims.
      unverified_claims copies the accepted record's optional list of remaining scopes;
      null means unassessed, [] means assessed with no declared unverified scopes.
      Prose is not parsed to infer claims, and proposal application does not clear that list.
      --compact includes only id, verification, verification_basis, and these three claim
      lists per record, with the same pagination and filtering. It omits expected_behavior,
      verification_opportunity, and claim observations. Use noncompact discovery or --id
      for that prose and the evidence scope.
      The overall verification field does not certify every claim. Expand selected IDs
      before judging evidence.

      IDs may be accepted records (SCR-*) or inbox/archived verification proposals (VP-*).
      Proposal IDs resolve to their target; mixed IDs deduplicate targets in selected order.
      Print JSON {root, mode, records}. Each result contains an accepted projection and
      verification_proposals with one {id, path, frontmatter, body} projection per proposal.
      selected_verification_proposal_ids, applied_verification_proposal_ids, and
      pending_verification_proposal_ids preserve roles and ordering without repeating
      documents. Explicitly selected rejected proposals remain included.
      observations and evidence dictionaries hold exact text once per result. Projected
      observed_behavior_refs, observation_ref, summary_ref, and decisive_evidence_refs
      point into those dictionaries. Accepted observed_behavior_refs reconstruct the
      original text by joining the referenced observations with two newlines; an exact
      applied-observation rollup reuses its component references. Distinct wording stays
      distinct. Consolidate redundant paraphrases through prepare-accepted-update and
      update-accepted, reusing precise applied-proposal evidence while retaining unique
      facts and claim limits. Proposal archives preserve their original evidence and triage.
      These references are local to the result, not persistent record IDs.
      Opportunity matches, triage rationales, source notes, and claim limits remain intact.
      Detail claim summaries carry IDs, claim types, and bases; their observations live
      in the referenced proposals. Source digests describe the original documents, which
      remain available verbatim through show --id ID. Historical dispositions remain
      inspectable; legacy support without proposal provenance has no applied IDs.
      Expanded proposals must match their record IDs and locations. Accepted and proposal
      documents are read once per invocation and reused; later calls read anew.
      Choose destinations or IDs; text filters, compact output, and pagination apply only
      to discovery. Literal filtering may omit relevant outcomes; adjust or omit terms
      when broader coverage is needed. Does not judge
      relevance, opportunity match, supplementation, or effectiveness. Use validate
      separately for full state validation; reads are not an atomic snapshot.
    TEXT
  when "review-queue"
    <<~TEXT
      Usage: retro-state.rb review-queue [--root DIR]

      Print TSV: type, identity, review trigger or intake summary, path.
      Includes pending candidates, open papercuts, verification proposals, deferrals,
      contradictions, drafts, ledgers, publication gaps, and a due artifact audit.
      Detailed intake commands remain available as filtered views. Queue presence
      neither authorizes processing nor requires draining unrelated intake. Use
      validate separately for full state validation.
    TEXT
  end
  if details
    return details + "\n--root defaults to #{RetroState::STATE_ENV}. These commands do not write state.\n"
  end

  <<~TEXT
    Usage: retro-state.rb COMMAND [options]

    Manage disposable Markdown state beneath #{RetroState::STATE_ENV}.

    Commands:
      show --id ID [--id ID ...]       Inspect selected records as JSON
      snapshot                         Print a JSON state inventory
      compare --file PATH              Compare inventory; exact path or action allowances
      prepare-decision --id ID --verdict VERDICT
                                        Print an editable candidate or verification decision
      prepare-verification --id SCR-ID --verification STATE
                                        Prepare a new verification proposal for the chosen target
      prepare-accepted --id RC-ID ... --commit SHA ...
                                        Prepare a new accepted-record draft from archived candidates
      prepare-accepted-update --id ID  Print an editable accepted-record replacement
      init                              Initialize the configured state root
      template TYPE                    Print a papercut, papercut-repair, candidate, decision,
                                        verification, verification-decision, accepted, draft,
                                        ledger, or audit template
      record-papercut --file PATH      Record a papercut from PATH, or - for standard input
      prepare-papercut-repair --id ID  Print a repair decision bound to current intake
      repair-papercut --id ID --file PATH
                                        Repair invalid papercut classifications with a typed decision
      papercuts [--archive]            List open papercuts, or archived papercuts explicitly
      close-papercut --id ID --outcome OUTCOME --rationale TEXT
                                        Archive a papercut with a reviewed outcome
      route --file PATH                Route a candidate into the inbox
      pending                           List validated inbox candidates
      process --id ID --decision PATH  Archive a candidate with a verdict
      route-verification --file PATH   Route verification evidence into its external inbox
      pending-verifications            List validated verification proposals
      process-verification --id ID --decision PATH
                                        Apply or reject a verification proposal
      reconsider --id ID --decision PATH
                                        Replace a deferred verdict and preserve its history
      record-accepted --file PATH       Store a curated accepted record
      update-accepted --id ID --file PATH
                                        Replace a curated record; preserve identity, acceptance
                                        date, and prior implementation commits
      accepted-records [--destination TEXT ...] [--text TEXT ...] [--active-supported]
                                        Match case-insensitive substrings in destinations or metadata/body
      verification-opportunities [--destination TEXT]
                                        List unverified outcomes; final column is pending support IDs:claims
      verification-context --destination TEXT ... | --id ID ...
                                        Page active outcomes or retrieve selected verification evidence
      record-draft --file PATH          Store an uninstalled draft
      record-ledger --file PATH         Store a maintenance ledger entry
      close-ledger --id ID --rationale TEXT
                                        Close a maintenance ledger entry
      record-audit --file PATH          Store a fresh completed sanitized system audit
      record-audit --id LA-ID           Recover a committed artifact audit's cadence cache
      audits                            List completed system audits
      artifact-audit-status [--archive-threshold N]
                                        Report machine-owned artifact-audit cadence
      review-queue                      List all intake and unresolved executable learning work
      validate                          Validate the configured live state
      self-test                         Exercise the protocol in a temporary directory

    Common option:
      --root DIR  Override #{RetroState::STATE_ENV} for this invocation
      COMMAND --help  Show command help (inspection and preparation have focused help)
  TEXT
end

def parse_options!(parser, arguments)
  parser.parse!(arguments)
  return if arguments.empty?

  raise OptionParser::InvalidArgument, "unexpected argument: #{arguments.first}"
end

def reject_inapplicable_options!(command, provided)
  allowed = {
    "show" => %w[--root --id],
    "snapshot" => %w[--root],
    "compare" => %w[--root --file --allow-path --allow-action],
    "prepare-decision" => %w[--root --id --verdict --rationale],
    "prepare-verification" => %w[--root --id --verification],
    "prepare-accepted" => %w[--root --id --commit],
    "prepare-accepted-update" => %w[--root --id --commit --destination],
    "init" => %w[--root],
    "template" => [],
    "record-papercut" => %w[--root --file],
    "prepare-papercut-repair" => %w[--root --id],
    "repair-papercut" => %w[--root --id --file],
    "papercuts" => %w[--root --archive],
    "close-papercut" => %w[
      --root --id --outcome --rationale --related-papercut-id
      --related-candidate-id
    ],
    "route" => %w[--root --file],
    "pending" => %w[--root],
    "process" => %w[--root --id --decision],
    "route-verification" => %w[--root --file],
    "pending-verifications" => %w[--root],
    "process-verification" => %w[--root --id --decision],
    "reconsider" => %w[--root --id --decision],
    "record-accepted" => %w[--root --file],
    "update-accepted" => %w[--root --id --file],
    "accepted-records" => %w[--root --destination --text --active-supported],
    "verification-opportunities" => %w[--root --destination],
    "verification-context" => %w[--root --destination --id --text --compact --limit --offset],
    "record-draft" => %w[--root --file],
    "record-ledger" => %w[--root --file],
    "close-ledger" => %w[--root --id --rationale],
    "record-audit" => %w[--root --file --id],
    "audits" => %w[--root],
    "artifact-audit-status" => %w[--root --archive-threshold],
    "review-queue" => %w[--root],
    "validate" => %w[--root],
    "self-test" => []
  }.fetch(command)
  unexpected = provided.select { |_option, present| present }.keys - allowed
  return if unexpected.empty?

  raise OptionParser::InvalidOption, "#{unexpected.first} is not valid for #{command}"
end

if ARGV.empty? || %w[-h --help].include?(ARGV.first)
  puts usage
  exit 0
end

command = ARGV.shift
commands = %w[
  show snapshot compare
  prepare-decision prepare-verification prepare-accepted prepare-accepted-update
  init template record-papercut prepare-papercut-repair repair-papercut papercuts
  close-papercut route pending process
  route-verification pending-verifications process-verification
  reconsider record-accepted update-accepted record-draft record-ledger close-ledger
  accepted-records verification-opportunities verification-context record-audit audits artifact-audit-status
  review-queue validate self-test
]
unless commands.include?(command)
  warn "retro-state.rb: unknown command: #{command}"
  warn usage
  exit 2
end

root_override = nil
input_path = nil
record_id = nil
record_ids = []
implementation_commits = []
allowed_paths = []
allowed_actions = []
decision_path = nil
archive = false
outcome = nil
rationale = nil
verdict = nil
proposed_verification = nil
related_papercut_id = nil
related_candidate_id = nil
destination_filter = nil
destination_filters = []
text_filters = []
context_compact = false
active_supported = false
context_limit = 20
context_offset = 0
context_limit_explicit = false
context_offset_explicit = false
archive_threshold = RetroState::ARTIFACT_AUDIT_ARCHIVE_THRESHOLD
archive_threshold_explicit = false
parser = OptionParser.new do |opts|
  opts.on("--root DIR") { |value| root_override = value }
  opts.on("--file PATH") { |value| input_path = value }
  opts.on("--id ID") do |value|
    record_id = value
    record_ids << value
  end
  opts.on("--commit SHA") { |value| implementation_commits << value }
  opts.on("--allow-path PATH") { |value| allowed_paths << value }
  opts.on("--allow-action ACTION:ID") { |value| allowed_actions << value }
  opts.on("--decision PATH") { |value| decision_path = value }
  opts.on("--archive") { archive = true }
  opts.on("--outcome OUTCOME") { |value| outcome = value }
  opts.on("--rationale TEXT") { |value| rationale = value }
  opts.on("--verdict VERDICT") { |value| verdict = value }
  opts.on("--verification STATE") do |value|
    raise OptionParser::InvalidArgument, "supply --verification at most once" if proposed_verification

    proposed_verification = value
  end
  opts.on("--related-papercut-id ID") { |value| related_papercut_id = value }
  opts.on("--related-candidate-id ID") { |value| related_candidate_id = value }
  opts.on("--destination TEXT") do |value|
    destination_filter = value
    destination_filters << value
  end
  opts.on("--text TEXT") { |value| text_filters << value }
  opts.on("--compact") { context_compact = true }
  opts.on("--active-supported") { active_supported = true }
  opts.on("--limit N", Integer) do |value|
    context_limit = value
    context_limit_explicit = true
  end
  opts.on("--offset N", Integer) do |value|
    context_offset = value
    context_offset_explicit = true
  end
  opts.on("--archive-threshold N", Integer) do |value|
    archive_threshold = value
    archive_threshold_explicit = true
  end
  opts.on("--help") do
    puts usage(command)
    exit 0
  end
end

begin
  type = ARGV.shift if command == "template"
  parse_options!(parser, ARGV)
  reject_inapplicable_options!(
    command,
    {
      "--root" => !root_override.nil?,
      "--file" => !input_path.nil?,
      "--id" => !record_id.nil?,
      "--commit" => !implementation_commits.empty?,
      "--allow-path" => !allowed_paths.empty?,
      "--allow-action" => !allowed_actions.empty?,
      "--decision" => !decision_path.nil?,
      "--archive" => archive,
      "--outcome" => !outcome.nil?,
      "--rationale" => !rationale.nil?,
      "--verdict" => !verdict.nil?,
      "--verification" => !proposed_verification.nil?,
      "--related-papercut-id" => !related_papercut_id.nil?,
      "--related-candidate-id" => !related_candidate_id.nil?,
      "--destination" => !destination_filter.nil?,
      "--text" => !text_filters.empty?,
      "--compact" => context_compact,
      "--active-supported" => active_supported,
      "--limit" => context_limit_explicit,
      "--offset" => context_offset_explicit,
      "--archive-threshold" => archive_threshold_explicit
    }
  )
  if command == "show" && record_ids.empty?
    raise OptionParser::MissingArgument, "--id ID"
  end
  if command == "compare" && !input_path
    raise OptionParser::MissingArgument, "--file PATH"
  end
  if %w[prepare-decision prepare-verification prepare-accepted-update].include?(command)
    raise OptionParser::MissingArgument, "--id ID" unless record_id
    raise OptionParser::InvalidArgument, "exactly one --id is required" unless record_ids.one?
  end
  if command == "prepare-decision" && !verdict
    raise OptionParser::MissingArgument, "--verdict VERDICT"
  end
  if command == "prepare-verification" && !proposed_verification
    raise OptionParser::MissingArgument, "--verification STATE"
  end
  if command == "prepare-accepted-update" && destination_filters.length > 1
    raise OptionParser::InvalidArgument, "supply --destination at most once"
  end
  if command == "prepare-accepted"
    raise OptionParser::MissingArgument, "--id RC-ID" if record_ids.empty?
    raise OptionParser::MissingArgument, "--commit SHA" if implementation_commits.empty?
  end
  if command == "verification-context"
    if destination_filters.empty? == record_ids.empty?
      raise OptionParser::InvalidArgument, "choose --destination TEXT or --id ID"
    end
    if destination_filters.any? { |destination| destination.strip.empty? }
      raise OptionParser::InvalidArgument, "--destination must not be blank"
    end
    if text_filters.any? { |text| text.strip.empty? }
      raise OptionParser::InvalidArgument, "--text must not be blank"
    end
    unless context_limit.positive? && context_offset >= 0
      raise OptionParser::InvalidArgument, "--limit must be positive and --offset must be nonnegative"
    end
    if !record_ids.empty? && (context_limit_explicit || context_offset_explicit || !text_filters.empty? || context_compact)
      raise OptionParser::InvalidArgument, "--text, --compact, --limit and --offset apply only to destination discovery"
    end
  end
  if command == "record-audit"
    raise OptionParser::MissingArgument, "--file PATH or --id LA-ID" unless input_path || record_id
    if input_path && record_id
      raise OptionParser::InvalidArgument, "choose --file for a fresh audit or --id for recovery"
    end
    if record_id && !record_ids.one?
      raise OptionParser::InvalidArgument, "exactly one --id is required for audit recovery"
    end
  end

  case command
  when "template"
    template = case type
    when "papercut" then RetroState.papercut_template
    when "papercut-repair" then RetroState.papercut_repair_template
    when "candidate" then RetroState.candidate_template
    when "decision" then RetroState.decision_template
    when "verification" then RetroState.verification_proposal_template
    when "verification-decision" then RetroState.verification_decision_template
    when "accepted" then RetroState.accepted_template
    when "draft" then RetroState.draft_template
    when "ledger" then RetroState.ledger_template
    when "audit" then RetroState.learning_audit_template
    else raise RetroState::Error, "unknown template type: #{type}"
    end
    print template
  when "self-test"
    RetroState.self_test
    puts "Retro state self-test passed."
  else
    root = root_override || ENV[RetroState::STATE_ENV]
    if %w[route route-verification record-papercut].include?(command) && RetroState.blank?(root)
      command_label = command
      raise RetroState::Error, "#{command_label} requires --file PATH" unless input_path

      data, body = RetroState.read_document(input_path)
      if command == "route"
        RetroState.validate_candidate(data, body, label: input_path, routed: false)
      elsif command == "route-verification"
        RetroState.validate_verification_proposal(data, body, label: input_path, routed: false)
      else
        RetroState.validate_papercut(data, body, label: input_path, routed: false)
      end
      record_name = case command
      when "route" then "candidate"
      when "route-verification" then "verification proposal"
      else "papercut"
      end
      warn "#{RetroState::STATE_ENV} is not set; no state was written. Paste-ready #{record_name} follows."
      print RetroState.render_document(data, body)
      exit 2
    end

    store = RetroState::Store.new(root)
    case command
    when "prepare-decision"
      print store.prepare_decision(record_id, verdict, rationale: rationale)
    when "prepare-verification"
      print store.prepare_verification(record_id, proposed_verification)
    when "prepare-accepted"
      print store.prepare_accepted(record_ids, implementation_commits)
    when "prepare-accepted-update"
      print store.prepare_accepted_update(record_id, commits: implementation_commits, destination: destination_filter)
    when "show"
      puts JSON.pretty_generate(store.show(record_ids))
    when "snapshot"
      puts JSON.pretty_generate(store.snapshot)
    when "compare"
      result = store.compare(input_path, allowed_paths: allowed_paths, allowed_actions: allowed_actions)
      puts JSON.pretty_generate(result)
      exit(result.fetch("matches") ? 0 : 1)
    when "init"
      puts store.init
    when "route"
      raise RetroState::Error, "route requires --file PATH" unless input_path

      data, body = RetroState.read_document(input_path)
      RetroState.validate_candidate(data, body, label: input_path, routed: false)
      begin
        puts store.route(input_path, document: [data, body])
      rescue RetroState::Error, Errno::EACCES, Errno::EROFS, Errno::ENOSPC => e
        warn "Could not route to external state (#{e.message}); no state was written. Paste-ready candidate follows."
        print RetroState.render_document(data, body)
        exit 2
      end
    when "route-verification"
      raise RetroState::Error, "route-verification requires --file PATH" unless input_path

      data, body = RetroState.read_document(input_path)
      RetroState.validate_verification_proposal(data, body, label: input_path, routed: false)
      begin
        puts store.route_verification(input_path, document: [data, body])
      rescue RetroState::Error, Errno::EACCES, Errno::EROFS, Errno::ENOSPC => e
        warn "Could not route to external state (#{e.message}); no state was written. " \
          "Paste-ready verification proposal follows."
        print RetroState.render_document(data, body)
        exit 2
      end
    when "record-papercut"
      raise RetroState::Error, "record-papercut requires --file PATH" unless input_path

      data, body = RetroState.read_document(input_path)
      RetroState.validate_papercut(data, body, label: input_path, routed: false)
      begin
        puts store.record_papercut(data, body, label: input_path)
      rescue RetroState::Error, Errno::EACCES, Errno::EROFS, Errno::ENOSPC => e
        warn "Could not record to external state (#{e.message}); no state was written. Paste-ready papercut follows."
        print RetroState.render_document(data, body)
        exit 2
      end
    when "repair-papercut"
      raise RetroState::Error, "repair-papercut requires --id ID" unless record_id
      raise RetroState::Error, "repair-papercut requires --file PATH" unless input_path

      puts store.repair_papercut(record_id, input_path)
    when "prepare-papercut-repair"
      raise RetroState::Error, "prepare-papercut-repair requires --id ID" unless record_id

      print store.prepare_papercut_repair(record_id)
    when "papercuts"
      store.papercuts(archive: archive).each { |row| puts row.join("\t") }
    when "close-papercut"
      raise RetroState::Error, "close-papercut requires --id ID" unless record_id
      raise RetroState::Error, "close-papercut requires --outcome OUTCOME" unless outcome
      raise RetroState::Error, "close-papercut requires --rationale TEXT" unless rationale

      puts store.close_papercut(
        record_id,
        outcome: outcome,
        rationale: rationale,
        related_papercut_id: related_papercut_id,
        related_candidate_id: related_candidate_id
      )
    when "pending"
      store.pending.each { |id, title, path| puts [id, title, path].join("\t") }
    when "process"
      raise RetroState::Error, "process requires --id ID" unless record_id
      raise RetroState::Error, "process requires --decision PATH" unless decision_path

      puts store.process(record_id, decision_path)
    when "pending-verifications"
      store.pending_verifications.each { |row| puts row.join("\t") }
    when "process-verification"
      raise RetroState::Error, "process-verification requires --id ID" unless record_id
      raise RetroState::Error, "process-verification requires --decision PATH" unless decision_path

      puts store.process_verification(record_id, decision_path)
    when "reconsider"
      raise RetroState::Error, "reconsider requires --id ID" unless record_id
      raise RetroState::Error, "reconsider requires --decision PATH" unless decision_path

      puts store.reconsider(record_id, decision_path)
    when "record-accepted"
      raise RetroState::Error, "record-accepted requires --file PATH" unless input_path

      puts store.record_accepted(input_path)
    when "update-accepted"
      raise RetroState::Error, "update-accepted requires --id ID" unless record_id
      raise RetroState::Error, "update-accepted requires --file PATH" unless input_path

      puts store.update_accepted(record_id, input_path)
    when "accepted-records"
      store.accepted_records_query(
        destinations: destination_filters, texts: text_filters, active_supported: active_supported
      ).each do |row|
        puts row.join("\t")
      end
    when "verification-opportunities"
      store.verification_opportunities(destination: destination_filter).each do |row|
        puts row.join("\t")
      end
    when "verification-context"
      puts JSON.pretty_generate(store.verification_context(
        destinations: destination_filters, record_ids: record_ids,
        texts: text_filters, compact: context_compact, limit: context_limit, offset: context_offset
      ))
    when "record-draft"
      raise RetroState::Error, "record-draft requires --file PATH" unless input_path

      puts store.record_draft(input_path)
    when "record-ledger"
      raise RetroState::Error, "record-ledger requires --file PATH" unless input_path

      puts store.record_ledger(input_path)
    when "close-ledger"
      raise RetroState::Error, "close-ledger requires --id ID" unless record_id
      raise RetroState::Error, "close-ledger requires --rationale TEXT" unless rationale

      puts store.close_ledger(record_id, rationale: rationale)
    when "record-audit"
      puts(record_id ? store.recover_audit(record_id) : store.record_audit(input_path))
    when "audits"
      store.audits.each { |row| puts row.join("\t") }
    when "artifact-audit-status"
      status = store.artifact_audit_status(archive_threshold: archive_threshold)
      puts [
        status.fetch(:due) ? "due" : "not-due",
        status.fetch(:archives_since),
        status.fetch(:archive_threshold),
        status.fetch(:last_audit_id, "none"),
        status.fetch(:last_audit_path, "-")
      ].join("\t")
    when "review-queue"
      store.review_queue.each { |type, id, trigger, path| puts [type, id, trigger, path].join("\t") }
    when "validate"
      store.validate
      puts "Retro state validation passed."
    end
  end
rescue OptionParser::ParseError => e
  warn "retro-state.rb: #{e.message}"
  warn usage(command)
  exit 2
rescue RetroState::Error, Errno::ENOENT, Errno::EACCES, Errno::EISDIR, Errno::ENOTDIR, Errno::ELOOP => e
  warn "retro-state.rb: #{e.message}"
  exit 1
end
