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
  VERDICTS = %w[accept defer reject split merge no-change local-fix external-owner].freeze
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
  FOLLOW_UP_FIELDS = %w[owner review_trigger next_action close_condition].freeze
  DEFERRAL_FIELDS = ["unresolved_decision", *FOLLOW_UP_FIELDS].freeze
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
    unless %w[candidate observation].include?(data["record_type"])
      raise Error, "#{label}: record_type must be observation or legacy candidate"
    end

    require_fields(data, %w[title source_scope observation redaction_review], label)
    require_string_array(data, "decisive_evidence", label)
    if data["record_type"] == "candidate"
      require_fields(data, %w[
        reusable_lesson existing_coverage missing_delta proposed_destination smallest_change
        test_status confidence recommendation
      ], label)
      lineage_present = data.key?("evidence_lineage") || data.key?("evidence_lineage_note")
      if !routed || lineage_present
        require_fields(data, %w[evidence_lineage evidence_lineage_note], label)
        validate_enum(data, "evidence_lineage", EVIDENCE_LINEAGES, label)
      end
      validate_enum(data, "confidence", CONFIDENCES, label)
      validate_enum(data, "recommendation", RECOMMENDATIONS, label)
    end

    validate_supersession(data, label)

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
      if data["record_type"] == "observation" && %w[accept split].include?(triage["verdict"])
        require_fields(triage, %w[evidence_lineage evidence_lineage_note], label)
        validate_enum(triage, "evidence_lineage", EVIDENCE_LINEAGES, label)
      end
      if data["supersedes_accepted_id"] && triage["supersedes_accepted_id"] &&
          data["supersedes_accepted_id"] != triage["supersedes_accepted_id"]
        raise Error, "#{label}: review cannot replace original supersession evidence"
      end
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

  def validate_supersession(data, label)
    supersedes_id = data["supersedes_accepted_id"]
    now_false = data["now_false"]
    if supersedes_id || now_false
      require_fields(data, %w[supersedes_accepted_id now_false], label)
      unless supersedes_id.match?(/\ASCR-\d{8}-[a-f0-9]{6}\z/)
        raise Error, "#{label}: invalid supersedes_accepted_id"
      end
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
    if data.key?("source_observation_ids")
      require_string_array(data, "source_observation_ids", label)
      unless data["source_observation_ids"].all? { |id| id.match?(/\A(?:RC|PC)-\d{8}T\d{6}Z-[a-f0-9]{6}\z/) }
        raise Error, "#{label}: invalid source_observation_ids"
      end
    end
    if data.key?("review")
      review = data["review"]
      raise Error, "#{label}: review must be a mapping" unless review.is_a?(Hash)
      unless (review.keys - %w[verification_proposal_id verdict rationale reviewed_at close_observation_ids]).empty?
        raise Error, "#{label}: unexpected reviewed-submission field"
      end
      validate_verification_decision(review.merge("schema_version" => SCHEMA_VERSION,
        "record_type" => "verification-decision"), "", label: label,
        expected_id: data["verification_proposal_id"])
      raise Error, "#{label}: reviewed submissions must apply" unless review["verdict"] == "apply"
      require_string_array(review, "close_observation_ids", label, allow_empty: true)
      ids = review.fetch("close_observation_ids")
      unless ids.uniq == ids && ids.all? { |id| id.match?(/\ARC-\d{8}T\d{6}Z-[a-f0-9]{6}\z/) } &&
          (ids - data.fetch("source_observation_ids", [])).empty?
        raise Error, "#{label}: close_observation_ids must select distinct RC source observations"
      end
    end
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
      if data.key?("review")
        if triage["verdict"] == "reject"
          unless triage.keys.sort == data["review"].keys.sort && triage["close_observation_ids"] == []
            raise Error, "#{label}: rejected reviewed submission cannot close observations"
          end
        elsif without_keys(triage, "acknowledged_closures") != data["review"]
          raise Error, "#{label}: archived decision differs from the reviewed submission"
        end
        if triage.key?("acknowledged_closures")
          acknowledgments = triage["acknowledged_closures"]
          unless acknowledgments.is_a?(Hash) && acknowledgments.any? &&
              (acknowledgments.keys - data["review"]["close_observation_ids"]).empty?
            raise Error, "#{label}: acknowledgments must select planned observation closures"
          end
          acknowledgments.each_value do |ack|
            raise Error, "#{label}: acknowledgment must be a mapping" unless ack.is_a?(Hash)
            require_fields(ack, %w[rationale reviewed_at record_digest], label)
            unless ack.keys.sort == %w[rationale record_digest reviewed_at] &&
                ack["reviewed_at"].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/) &&
                ack["record_digest"].match?(/\A[a-f0-9]{64}\z/)
              raise Error, "#{label}: invalid closure acknowledgment"
            end
          end
        end
      end
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
      unless data["intake_digest"] == expected_digest
        raise Error, "#{label}: papercut intake fields changed after recording"
      end
      validate_papercut_schema_repairs(data, body, label)
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
    unless routed
      PAPERCUT_CLASSIFICATIONS.each do |field, allowed|
        validate_enum(data, field, allowed, label)
      end
    end
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

  def validate_follow_up(data, label, legacy_allowed:)
    fields = FOLLOW_UP_FIELDS
    fields -= %w[owner] if legacy_allowed && !data.key?("owner")
    require_fields(data, fields, label)
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

    validate_supersession(triage, "#{label} triage")
    related = triage.fetch("related_candidate_ids", [])
    unless related.is_a?(Array) && related.all? { |item| item.is_a?(String) && !item.empty? }
      raise Error, "#{label}: related_candidate_ids must be an array of strings"
    end

    return unless triage["verdict"] == "defer"

    require_fields(triage, %w[unresolved_decision], "#{label} deferred triage") if
      triage.key?("owner") || triage.key?("review_trigger_contract_version")
    validate_follow_up(triage, "#{label} deferred triage", legacy_allowed: true)
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
    validate_supersession(data, label)
    require_string_array(data, "related_candidate_ids", label, allow_empty: true)
    if data["verdict"] == "defer"
      require_fields(data, %w[unresolved_decision], label)
      validate_follow_up(data, label, legacy_allowed: false)
    else
      trigger_fields = data.keys.select do |field|
        DEFERRAL_FIELDS.include?(field) || field.start_with?("review_trigger_")
      end
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
      validate_follow_up(data, label, legacy_allowed: assigned)
    elsif data.key?("review_trigger_contract_version")
      validate_follow_up(data, label, legacy_allowed: assigned)
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
      validate_follow_up(data, label, legacy_allowed: assigned)
    elsif data.key?("review_trigger_contract_version")
      validate_follow_up(data, label, legacy_allowed: assigned)
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
      if data.key?("candidate_archive_count") &&
          (!data["candidate_archive_count"].is_a?(Integer) || data["candidate_archive_count"].negative?)
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

  def observation_template
    <<~MARKDOWN
      ---
      schema_version: 1
      record_type: observation
      title: "Short observation title"
      source_scope: "Sanitized task category; omit private names."
      observation: "What happened and why it may be worth improving."
      decisive_evidence:
        - "Bounded observed behavior, error, artifact or user feedback."
      redaction_review: "Confirmed no transcript, secret, private source or unredacted local path."
      ---

      Optional context: guidance in use, impact, workaround, outcome, or a clearly labeled hypothesis.
      Preserve useful facts already known; no remedy, owner or skill classification is required.
    MARKDOWN
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
      # When based on captured observations, link original RC-* or legacy PC-* IDs:
      # source_observation_ids: []
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
      owner: "skill-retro-triage"
      unresolved_decision: "" # Decision that current evidence cannot justify.
      review_trigger: "" # Concrete review condition and how the owner checks it.
      next_action: "" # Executable action when the review condition is met.
      close_condition: "" # Condition that resolves the action.
      # Complete the blanks for defer; remove all deferral fields for other verdicts.
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

  def ledger_template
    <<~MARKDOWN
      ---
      schema_version: 1
      record_type: ledger-entry
      title: "Threshold-based maintenance observation"
      owner: "skill-retro-triage"
      status: open
      last_reviewed: "never"
      review_trigger: "Name the concrete review condition and the check the owner performs."
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
      executable consequence with an owner, review condition, next action,
      and close condition as a deferral or ledger before recording the audit,
      then list its ID above.
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
      validate_state_layout!
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
        data, body = read_state_document(path)
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
        raise Error, "resume reviewed submission with record-verification --id #{id}" if data.key?("review")
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
      if data["record_type"] == "observation" && %w[accept split].include?(verdict)
        decision["evidence_lineage"] = ""
        decision["evidence_lineage_note"] = ""
      end
      if id_field == "candidate_id" && verdict != "defer"
        DEFERRAL_FIELDS.each { |field| decision.delete(field) }
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
      now = Time.now.utc
      draft["review"] = {"verification_proposal_id" => unique_verification_id("VP-#{now.strftime("%Y%m%dT%H%M%SZ")}"),
                         "verdict" => "apply", "rationale" => "", "reviewed_at" => now.strftime("%Y-%m-%dT%H:%M:%SZ"),
                         "close_observation_ids" => []}
      prior = accepted.slice(
        "accepted_id", "destination", "expected_behavior", "verification_opportunity",
        "verification", "verification_basis", "applied_verification_proposal_ids"
      ).merge("pending_verification_proposals" => pending.map do |proposal|
        proposal.slice("verification_proposal_id", "proposed_verification", "claim")
      end)
      notes = <<~TEXT
        Complete every blank field, curate evidence, and review redaction before record-verification.
        Read applied and pending evidence through verification-context before judging supplementation.
        Preparation writes no state, supplies no evidence claim, and does not establish eligibility
        at submission time. These comments are discarded automatically on submission.

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
      source_records = records.to_h { |record| [record.fetch("id"), record] }
      resolve_candidate = lambda do |id|
        next unless id.match?(/\ARC-\d{8}T\d{6}Z-[a-f0-9]{6}\z/) && File.file?(candidate_path("archive", id))

        source_records[id] = show([id]).fetch("records").first
        ancestry[id] = validate_archived_candidate_record(source_records.fetch(id))
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
        ).merge("context" => source_records.fetch(candidate.fetch("candidate_id")).fetch("body"))
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
            state_lock_path]
        when "close-papercut"
          [papercut_path("inbox", id), papercut_path("archive", id)]
        when "reconsider"
          [candidate_path("archive", id), state_lock_path]
        when "record-accepted"
          [accepted_path(id)]
        when "update-accepted"
          [accepted_path(id), state_lock_path]
        when "process-verification"
          archive = verification_path("archive", id)
          record = show([id]).fetch("records").first
          unless File.join(root, record.fetch("path")) == archive
            raise Error, "process-verification allowance requires a completed archived proposal: #{id}"
          end
          proposal = validate_verification_record(record).fetch("frontmatter")
          footprint = [verification_path("inbox", id), archive, state_lock_path]
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
      pending_candidates.map { |path, data| [data.fetch("candidate_id"), data.fetch("title"), path] }
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

    def papercuts(archive: false)
      ensure_initialized
      area = archive ? "archive" : "inbox"
      Dir.glob(File.join(root, "papercuts", area, "*.md")).sort.map do |path|
        data, body = read_state_document(path)
        RetroState.validate_papercut(data, body, label: path, routed: true, archived: archive)
        observation = data.fetch("observation").gsub(/\s+/, " ").strip
        [data.fetch("papercut_id"), data.fetch("kind"), data.fetch("impact"), observation, path]
      end
    end

    def close_papercut(papercut_id, outcome:, rationale:, related_papercut_id: nil, related_candidate_id: nil)
      ensure_initialized
      source = papercut_path("inbox", papercut_id)
      raise Error, "papercut not found in inbox: #{papercut_id}" unless File.file?(source)

      data, body = read_state_document(source)
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

        candidate, body = read_state_document(source)
        RetroState.validate_candidate(candidate, body, label: source, routed: true)
        decision, decision_body = RetroState.read_document(decision_path)
        RetroState.validate_decision(decision, decision_body, label: decision_path, expected_id: candidate_id)

        triage = RetroState.without_keys(decision, "schema_version", "record_type")
        triage["notes"] = decision_body.rstrip unless decision_body.strip.empty?
        candidate["triage"] = triage
        validate_candidate_supersession!(candidate)
        RetroState.validate_candidate(candidate, body, label: source, routed: true, archived: true)
        archive_candidate(candidate, body)
      end
    end

    def process_verification(proposal_id, decision_path)
      ensure_initialized
      with_state_lock do
        source = verification_path("inbox", proposal_id)
        raise Error, "verification proposal not found in inbox: #{proposal_id}" unless File.file?(source)

        proposal, body = read_state_document(source)
        RetroState.validate_verification_proposal(proposal, body, label: source, routed: true)
        raise Error, "verification identity does not match #{proposal_id}" unless proposal["verification_proposal_id"] == proposal_id
        if proposal.key?("review")
          raise Error, "resume reviewed submission with record-verification --id #{proposal_id}"
        end
        decision, decision_body = RetroState.read_document(decision_path)
        RetroState.validate_verification_decision(decision, decision_body, label: decision_path, expected_id: proposal_id)
        validate_verification_sources!(proposal)
        target = read_verification_target(proposal)
        destination = complete_verification(proposal, body, decision, target, decision_body)
        File.unlink(source)
        destination
      end
    end

    def record_verification(input_path = nil, proposal_id: nil, reject: false, acknowledge_closures: [], rationale: nil)
      resolving = reject || acknowledge_closures.any?
      if resolving
        raise Error, "resolution requires --id without --file" if input_path || !proposal_id
        raise Error, "choose rejection or closure acknowledgment" if reject && acknowledge_closures.any?
        RetroState.require_fields({"rationale" => rationale}, ["rationale"], "verification resolution")
      elsif rationale
        raise Error, "rationale requires an explicit verification resolution"
      end
      input = RetroState.read_document(input_path) if input_path
      if input
        RetroState.validate_verification_proposal(*input, label: input_path, routed: false)
        raise Error, "record-verification requires a prepared review" unless input.first.key?("review")
        proposal_id = input.first.fetch("review").fetch("verification_proposal_id")
      end
      ensure_initialized
      with_state_lock do
        inbox = verification_path("inbox", proposal_id)
        archive = verification_path("archive", proposal_id)
        validate_state_path!(inbox)
        validate_state_path!(archive)
        source = File.file?(archive) ? archive : inbox
        if File.file?(source)
          proposal, body = read_state_document(source)
          RetroState.validate_verification_proposal(proposal, body, label: source, routed: true, archived: source == archive)
          raise Error, "reviewed verification identity does not match #{proposal_id}" unless proposal["verification_proposal_id"] == proposal_id
          if source == archive && File.file?(inbox)
            pending, pending_body = read_state_document(inbox)
            RetroState.validate_verification_proposal(pending, pending_body, label: inbox, routed: true)
            unless pending == RetroState.without_keys(proposal, "triage") && pending_body == body
              raise Error, "verification archive differs from stored intake: #{proposal_id}"
            end
          end
          if input && RetroState.render_document(*input) != RetroState.render_document(
            RetroState.without_keys(proposal, "verification_proposal_id", "created_at", "intake_digest", "triage"), body
          )
            raise Error, "reviewed submission differs from stored verification: #{proposal_id}"
          end
        else
          raise Error, "reviewed verification not found: #{proposal_id}" unless input
          proposal, body = input
        end
        raise Error, "record-verification requires a reviewed submission" unless proposal.key?("review")
        target = read_verification_target(proposal)
        applied = target.fetch(1).fetch("applied_verification_proposal_ids", []).include?(proposal_id)
        decision = RetroState.stringify_keys(proposal.fetch("triage", proposal.fetch("review")))
        if File.file?(archive) && (decision["verdict"] == "apply") != applied
          raise Error, "archived reviewed verification conflicts with accepted metadata: #{proposal_id}"
        end
        if reject
          raise Error, "applied verification cannot be rejected" if applied
          if decision["verdict"] == "reject"
            raise Error, "rejection differs from stored resolution" unless decision["rationale"] == rationale
          else
            decision.merge!("verdict" => "reject", "rationale" => rationale,
              "reviewed_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"), "close_observation_ids" => [])
          end
        end
        if acknowledge_closures.any?
          raise Error, "closure acknowledgment requires applied verification" unless applied
          unless acknowledge_closures.uniq == acknowledge_closures &&
              (acknowledge_closures - proposal.fetch("review").fetch("close_observation_ids")).empty?
            raise Error, "acknowledgment must select distinct planned observation closures"
          end
          verify_applied_proposal!(target.fetch(1), proposal)
        end
        reviewed = proposal.merge("triage" => decision)
        closures = validate_verification_sources!(reviewed, acknowledge_closures: acknowledge_closures, rationale: rationale)
        RetroState.validate_verification_proposal(reviewed, body, label: source, routed: true, archived: true) if resolving
        unless File.file?(source)
          validate_verification_target_state!(target.fetch(1), proposal)
          validate_pending_support!(proposal)
          proposal = proposal.merge("verification_proposal_id" => proposal_id,
            "created_at" => proposal.fetch("review").fetch("reviewed_at"))
          proposal["intake_digest"] = Digest::SHA256.hexdigest(RetroState.render_document(proposal, body))
          ensure_verification_dirs
          exclusive_write(inbox, RetroState.render_document(proposal, body))
          operation_checkpoint(:verification_submission_written)
        end
        if File.file?(archive) && proposal["triage"] != decision
          replace_write(archive, RetroState.render_document(reviewed, body))
          operation_checkpoint(:verification_resolution_written)
        end
        destination = complete_verification(proposal, body, decision, target)
        closures.each_value do |candidate, candidate_body|
          archive_candidate(candidate, candidate_body)
          operation_checkpoint(:verification_observation_closed)
        end
        File.unlink(inbox) if File.file?(inbox)
        destination
      end
    end

    def reconsider(candidate_id, decision_path)
      ensure_initialized
      with_state_lock do
        path = candidate_path("archive", candidate_id)
        raise Error, "candidate not found in archive: #{candidate_id}" unless File.file?(path)

        candidate, body = read_state_document(path)
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
        validate_candidate_supersession!(candidate)
        RetroState.validate_candidate(candidate, body, label: path, routed: true, archived: true)
        replace_write(path, RetroState.render_document(candidate, body))
        path
      end
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
        candidate, candidate_body = read_state_document(archive_path)
        RetroState.validate_candidate(
          candidate,
          candidate_body,
          label: archive_path,
          routed: true,
          archived: true
        )
        candidate.dig("triage", "supersedes_accepted_id") || candidate["supersedes_accepted_id"]
      end.compact.uniq.sort
      supplied_supersedes_ids = data.fetch("supersedes_accepted_ids", []).sort
      if data.key?("supersedes_accepted_ids") && supplied_supersedes_ids != supersedes_ids
        raise Error, "accepted record supersedes_accepted_ids do not match originating candidates"
      end
      unless supersedes_ids.empty?
        data["supersedes_accepted_ids"] = supersedes_ids
        RetroState.validate_accepted(
          data,
          body,
          label: input_path,
          assigned: false,
          strict_contradiction: true
        )
      end
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

        current, current_body = read_state_document(path)
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
          applied = applied_ids.map { |proposal_id| proposal.call(proposal_id) }
          pending_proposals = pending.fetch(id, [])
          {
            "accepted" => record,
            "verification_proposals" => (selected_proposals + applied + pending_proposals)
              .uniq { |item| item.fetch("id") },
            "selected_verification_proposal_ids" => selected_proposals.map { |item| item.fetch("id") },
            "applied_verification_proposal_ids" => applied_ids,
            "pending_verification_proposal_ids" => pending_proposals.map { |item| item.fetch("id") }
          }.merge(verification_claim_summary(data, &proposal))
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
          next data.slice("destination", "expected_behavior", "verification", "verification_basis")
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

    def record_ledger(input_path)
      ensure_initialized
      data, body = RetroState.read_document(input_path)
      RetroState.validate_ledger_entry(data, body, label: input_path, assigned: false)
      now = Time.now.utc
      id = unique_auxiliary_id("LE", "ledgers")
      data["ledger_id"] = id
      data["created_at"] = now.strftime("%Y-%m-%dT%H:%M:%SZ")
      RetroState.validate_ledger_entry(data, body, label: input_path, assigned: true)
      destination = ledger_path(id)
      exclusive_write(destination, RetroState.render_document(data, body))
      destination
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

        data, body = read_state_document(path)
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

      pending_candidates.each do |path, data|
        kind = data.fetch("record_type")
        title = data.fetch("title").gsub(/\s+/, " ").strip
        rows << [kind, data.fetch("candidate_id"), "Review #{kind}: #{title}", path]
      end
      papercuts.each do |papercut_id, _kind, _impact, observation, path|
        rows << ["papercut", papercut_id, "Review papercut: #{observation}", path]
      end
      pending_verification_records.each do |path, proposal|
        trigger = if proposal.key?("review")
          "Resume reviewed verification and selected observation closures with record-verification."
        else
          "Adjudicate proposed #{proposal.fetch("proposed_verification")} evidence for #{proposal.fetch("target_accepted_id")}."
        end
        rows << ["verification-proposal", proposal.fetch("verification_proposal_id"), trigger, path]
      end

      accepted = accepted_records
      published_candidate_ids = accepted.flat_map do |_path, data|
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

      open_ledgers = Dir.glob(File.join(root, "ledgers", "*.md")).sort.filter_map do |path|
        data, body = read_state_document(path)
        RetroState.validate_ledger_entry(data, body, label: path, assigned: true)
        [path, data] if data["status"] == "open"
      end

      accepted.each do |path, data|
        next unless data["verification"] == "contradicted"
        next if RetroState.contradiction_resolved?(data)
        residual_id = data.dig("contradiction", "residual_ledger_id")
        next if residual_id && open_ledgers.any? { |ledger_pathname, _ledger| ledger_pathname == ledger_path(residual_id) }

        trigger = "Review the contradiction: retain with rationale, correct or remove guidance, or assign a residual ledger."
        rows << ["contradiction", data.fetch("accepted_id"), trigger, path]
      end

      Dir.glob(File.join(root, "drafts", "*.md")).sort.each do |path|
        data, body = read_state_document(path)
        RetroState.validate_draft(data, body, label: path, assigned: true)
        next unless %w[open revised].include?(data["status"])

        rows << ["draft", data.fetch("draft_id"), data.fetch("review_trigger"), path]
      end

      open_ledgers.each do |path, data|
        rows << ["ledger", data.fetch("ledger_id"), data.fetch("review_trigger"), path]
      end

      cadence = artifact_audit_status(candidate_rows: candidates)
      if cadence.fetch(:due)
        trigger = "#{cadence.fetch(:archives_since)} retained observations first reviewed since the last completed artifact audit"
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
        data.fetch("unresolved_action_ids").each do |action_id|
          next if action_reference_open?(action_id)

          raise Error, "audit unresolved action is missing or not open: #{action_id}"
        end

        now = Time.now.utc
        id = unique_auxiliary_id("LA", "audits/learning-process")
        data["audit_id"] = id
        data["completed_at"] = now.strftime("%Y-%m-%dT%H:%M:%SZ")
        RetroState.validate_learning_audit(data, body, label: input_path, assigned: true)
        destination = learning_audit_path(id)
        exclusive_write(destination, RetroState.render_document(data, body))
        operation_checkpoint(:audit_record_written)
        destination
      end
    end

    def audits
      ensure_initialized
      learning_audits.map do |path, data|
        [data.fetch("audit_id"), data.fetch("audit_kind"), data.fetch("completed_at"), path]
      end
    end

    def artifact_audit_status(archive_threshold: ARTIFACT_AUDIT_ARCHIVE_THRESHOLD, candidate_rows: nil)
      ensure_initialized
      unless archive_threshold.is_a?(Integer) && archive_threshold.positive?
        raise Error, "artifact audit archive threshold must be a positive integer"
      end

      latest_path, latest = learning_audits
        .select { |_path, data| data["audit_kind"] == "skill-repository" }
        .max_by { |_path, data| data.fetch("completed_at") }
      cutoff = latest&.fetch("completed_at")
      # This reminder uses retained first-review dates, not durable processing totals.
      archives_since = (candidate_rows || archived_candidates).count do |_path, data|
        first_triage = data.fetch("triage_history", []).first || data.fetch("triage")
        !cutoff || first_triage.fetch("reviewed_at") > cutoff
      end
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
          data, body = read_state_document(path)
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
            data, body = read_state_document(path)
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
          data, body = read_state_document(path)
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
        data, body = read_state_document(path)
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
        validate_candidate_supersession!(data)
      rescue Error => e
        errors << "#{path}: #{e.message}"
      end
      accepted_rows.each do |path, data|
        data.fetch("supersedes_accepted_ids", []).each do |superseded_id|
          errors << "#{path}: superseded accepted record does not exist: #{superseded_id}" unless accepted_ids.key?(superseded_id)
        end
      end
      verification_rows.each do |path, data, archived|
        begin
          validate_verification_sources!(data)
          if archived && data.key?("review") && data.dig("triage", "verdict") == "apply" &&
              !File.file?(verification_path("inbox", data.fetch("verification_proposal_id"))) &&
              data.fetch("review").fetch("close_observation_ids").any? { |id| File.file?(candidate_path("inbox", id)) }
            raise Error, "completed reviewed verification has an unfinished observation closure"
          end
        rescue Error => e
          errors << "#{path}: #{e.message}"
        end
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
            next
          end
          verify_applied_proposal!(data, proposal)
        rescue Error => e
          errors << "#{path}: #{e.message}"
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
        ledger, ledger_body = read_state_document(residual_path)
        RetroState.validate_ledger_entry(ledger, ledger_body, label: residual_path, assigned: true)
        if !RetroState.contradiction_resolved?(data) && ledger["status"] != "open"
          errors << "#{path}: unresolved contradiction requires an open residual ledger: #{residual_id}"
        end
      rescue Error => e
        errors << e.message
      end

      audit_rows = []
      Dir.glob(File.join(root, "audits", "learning-process", "*.md")).sort.each do |path|
        data, body = read_state_document(path)
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

      raise Error, errors.join("\n") unless errors.empty?

      true
    end

    private

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
      [candidate, *candidate.fetch("triage_history", []), candidate.fetch("triage", {})].each do |review|
        supersedes_id = review["supersedes_accepted_id"]
        next unless supersedes_id
        next if File.file?(accepted_path(supersedes_id))

        raise Error, "candidate supersedes missing accepted record: #{supersedes_id}"
      end
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
        verify_applied_proposal!(accepted, proposal)
      end

      residual_id = accepted.dig("contradiction", "residual_ledger_id")
      return unless residual_id

      residual_path = ledger_path(residual_id)
      unless File.file?(residual_path)
        raise Error, "contradiction residual ledger does not exist: #{residual_id}"
      end
      ledger, ledger_body = read_state_document(residual_path)
      RetroState.validate_ledger_entry(ledger, ledger_body, label: residual_path, assigned: true)
      return if RetroState.contradiction_resolved?(accepted)
      return if ledger["status"] == "open"

      raise Error, "unresolved contradiction requires an open residual ledger: #{residual_id}"
    end

    def read_state_document(path)
      validate_state_path!(path)
      RetroState.read_document(path)
    end

    def validate_state_layout!
      paths = (STATE_DIRS + VERIFICATION_DIRS).map { |relative| File.join(root, relative) }
      (paths + [File.join(root, "state-version"), state_lock_path]).each { |path| validate_state_path!(path) }
    end

    def validate_state_path!(path)
      unless canonical_root(path).start_with?(root + File::SEPARATOR)
        raise Error, "record resolves outside the state root: #{File.basename(path, ".md")}"
      end
      if path == state_lock_path && File.symlink?(path)
        raise Error, "state writer lock must not be a symlink"
      end
    end

    def archive_candidate(candidate, body)
      id = candidate.fetch("candidate_id")
      destination = candidate_path("archive", id)
      created = write_or_verify_archive(destination, RetroState.render_document(candidate, body), record_type: "candidate")
      operation_checkpoint(:candidate_archive_written) if created
      source = candidate_path("inbox", id)
      File.unlink(source) if File.file?(source)
      destination
    end

    def reviewed_observation_closures(proposal, acknowledge_closures: [], rationale: nil)
      review = proposal["review"]
      return {} unless review && proposal.dig("triage", "verdict") != "reject"

      review.fetch("close_observation_ids").to_h do |id|
        inbox = candidate_path("inbox", id)
        archive = candidate_path("archive", id)
        source = File.file?(inbox) ? inbox : archive
        validate_state_path!(archive)
        candidate, body = read_state_document(source)
        RetroState.validate_candidate(candidate, body, label: source, routed: true, archived: source == archive)
        unless candidate["record_type"] == "observation" && candidate["candidate_id"] == id
          raise Error, "closure requires an original observation: #{id}"
        end
        triage = {"candidate_id" => id, "verdict" => "no-change", "reviewed_at" => review.fetch("reviewed_at"),
                  "rationale" => "Review completed with #{review.fetch("verification_proposal_id")}: #{review.fetch("rationale")}",
                  "related_candidate_ids" => []}
        acknowledgment = proposal.dig("triage", "acknowledged_closures", id)
        if acknowledgment || acknowledge_closures.include?(id)
          unless source == archive && !File.file?(inbox) && candidate.dig("triage", "verdict") != "defer" && candidate["triage"] != triage
            raise Error, "acknowledgment requires an observation already completed by another review: #{id}"
          end
          digest = Digest::SHA256.hexdigest(RetroState.render_document(candidate, body))
          if acknowledgment
            raise Error, "acknowledged observation changed: #{id}" unless acknowledgment["record_digest"] == digest
            if acknowledge_closures.include?(id) && acknowledgment["rationale"] != rationale
              raise Error, "acknowledgment differs from stored resolution: #{id}"
            end
          else
            proposal.fetch("triage")["acknowledged_closures"] ||= {}
            proposal["triage"]["acknowledged_closures"][id] = {"rationale" => rationale,
              "reviewed_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"), "record_digest" => digest}
          end
          next [id, nil]
        end
        if candidate.key?("triage") && candidate["triage"] != triage
          raise Error, "observation already has a different review: #{id}"
        end
        candidate["triage"] = triage
        RetroState.validate_candidate(candidate, body, label: source, routed: true, archived: true)
        if File.file?(archive) && File.binread(archive) != RetroState.render_document(candidate, body)
          raise Error, "existing observation archive differs: #{id}"
        end
        [id, [candidate, body]]
      end
    end

    # Callers hold the writer lock and have validated fresh sources and target.
    def complete_verification(proposal, body, decision, target, decision_body = "")
      proposal_id = proposal.fetch("verification_proposal_id")
      triage = RetroState.stringify_keys(RetroState.without_keys(decision, "schema_version", "record_type"))
      triage["notes"] = decision_body.rstrip unless decision_body.strip.empty?
      proposal["triage"] = triage
      output = RetroState.render_document(proposal, body)
      destination = verification_path("archive", proposal_id)
      validate_state_path!(destination)
      write_or_verify_archive(destination, output, record_type: "verification") if File.file?(destination)
      if decision.fetch("verdict") == "apply"
        apply_verification_proposal!(proposal, decision, target)
        operation_checkpoint(:verification_accepted_written)
      else
        _path, accepted, _body = target
        if accepted.fetch("applied_verification_proposal_ids", []).include?(proposal_id)
          raise Error, "verification proposal is already applied; resume with the original apply decision"
        end
      end
      write_or_verify_archive(destination, output, record_type: "verification")
      operation_checkpoint(:verification_archive_written)
      destination
    end

    def apply_verification_proposal!(proposal, decision, target)
      proposal_id = proposal.fetch("verification_proposal_id")
      accepted_pathname, current, body = target
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
      if expected_state == "supported"
        return if %w[supported contradicted].include?(accepted["verification"])

        raise Error, "applied supported proposal no longer matches accepted state"
      end
      unless accepted["verification"] == "contradicted"
        raise Error, "applied contradicted proposal no longer matches accepted state"
      end

      unless accepted.dig("contradiction", "what_is_false") == proposal["what_is_false"]
        raise Error, "applied contradiction no longer matches accepted state"
      end
    end

    def validate_verification_sources!(proposal, acknowledge_closures: [], rationale: nil)
      closures = reviewed_observation_closures(proposal, acknowledge_closures: acknowledge_closures, rationale: rationale)
      proposal.fetch("source_observation_ids", []).each do |id|
        # Selected closures validate exact matching archive/inbox recovery copies above.
        next if closures.key?(id)
        record = show([id]).fetch("records").first
        data, body = record.values_at("frontmatter", "body")
        archived = record.fetch("path").split("/").include?("archive")
        if id.start_with?("PC-")
          RetroState.validate_papercut(data, body, label: id, routed: true, archived: archived)
          identity = data["papercut_id"]
        else
          RetroState.validate_candidate(data, body, label: id, routed: true, archived: archived)
          identity = data["candidate_id"]
        end
        raise Error, "source observation identity does not match #{id}" unless identity == id
      end
      closures.compact
    end

    def read_verification_target(proposal)
      record = validate_accepted_record(show([proposal.fetch("target_accepted_id")]).fetch("records").first)
      [File.join(root, record.fetch("path")), record.fetch("frontmatter"), record.fetch("body")]
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
        data, body = read_state_document(path)
        RetroState.validate_verification_proposal(data, body, label: path, routed: true)
        [path, data]
      end
    end

    def validate_pending_support!(proposal)
      return unless proposal["proposed_verification"] == "supported" && !proposal.key?("supplemental_reason")
      pending = pending_support.fetch(proposal.fetch("target_accepted_id"), [])
      return if pending.empty?
      ids = pending.map { |item| item.fetch("verification_proposal_id") }
      raise Error, "support already pending: #{ids.join(", ")}; read it and add supplemental_reason only for materially useful evidence"
    end

    def pending_support
      pending_verification_records.map(&:last)
        .select { |proposal| proposal["proposed_verification"] == "supported" }
        .group_by { |proposal| proposal.fetch("target_accepted_id") }
    end

    def write_or_verify_archive(destination, output, record_type:)
      validate_state_path!(destination)
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
      archived, archived_body = read_state_document(destination)
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

    def pending_candidates
      ensure_initialized
      Dir.glob(File.join(root, "retrospectives", "inbox", "*.md")).sort.map do |path|
        data, body = read_state_document(path)
        RetroState.validate_candidate(data, body, label: path, routed: true)
        [path, data]
      end
    end

    def archived_candidates
      Dir.glob(File.join(root, "retrospectives", "archive", "*.md")).sort.map do |path|
        data, body = read_state_document(path)
        RetroState.validate_candidate(data, body, label: path, routed: true, archived: true)
        [path, data]
      end
    end

    def accepted_records(include_body: false)
      Dir.glob(File.join(root, "retrospectives", "accepted", "*.md")).sort.map do |path|
        data, body = read_state_document(path)
        RetroState.validate_accepted(data, body, label: path, assigned: true)
        include_body ? [path, data, body] : [path, data]
      end
    end

    def learning_audits
      Dir.glob(File.join(root, "audits", "learning-process", "*.md")).sort.map do |path|
        data, body = read_state_document(path)
        RetroState.validate_learning_audit(data, body, label: path, assigned: true)
        [path, data]
      end
    end

    # Retain the original pathname so installed helper versions share one writer lock.
    def with_state_lock
      validate_state_path!(state_lock_path)
      File.open(state_lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
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

        data, body = read_state_document(path)
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

      data, body = read_state_document(path)
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

    def validate_auxiliary_dir(errors, directory, id_field)
      ids = {}
      Dir.glob(File.join(root, directory, "*.md")).sort.each do |path|
        data, body = read_state_document(path)
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
      validate_state_layout!
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
      validate_state_layout!
      VERIFICATION_DIRS.each do |relative|
        path = File.join(root, relative)
        FileUtils.mkdir_p(path, mode: 0o700)
        File.chmod(0o700, path)
      end
    end

    def validate_version
      path = File.join(root, "state-version")
      raise Error, "state-version is missing: #{path}" unless File.file?(path)
      validate_state_path!(path)
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

    def state_lock_path
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
      validate_state_path!(path)
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

  def self_test_papercut(store, data, body, label:)
    RetroState.validate_papercut(data, body, label: label, routed: false)
    store.init

    now = Time.now.utc
    id = store.send(:unique_papercut_id, "PC-#{now.strftime("%Y%m%dT%H%M%SZ")}")
    record = data.dup
    record["papercut_id"] = id
    record["created_at"] = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    intake = RetroState.without_keys(record, "intake_digest")
    record["intake_digest"] = Digest::SHA256.hexdigest(RetroState.render_document(intake, body))
    destination = store.send(:papercut_path, "inbox", id)
    store.send(:exclusive_write, destination, RetroState.render_document(record, body))
    destination
  end

  def self_test_legacy_verification(store, input_path)
    data, body = read_document(input_path)
    data = without_keys(data, "review")
    now = Time.now.utc
    id = store.send(:unique_verification_id, "VP-#{now.strftime("%Y%m%dT%H%M%SZ")}")
    data["verification_proposal_id"] = id
    data["created_at"] = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    data["intake_digest"] = Digest::SHA256.hexdigest(render_document(data, body))
    validate_verification_proposal(data, body, label: input_path, routed: true)
    store.send(:ensure_verification_dirs)
    path = store.send(:verification_path, "inbox", id)
    File.write(path, render_document(data, body))
    path
  end

  def reviewed_verification_self_test
    Dir.mktmpdir("retro-reviewed-self-test.") do |tmp|
      store = Store.new(File.join(tmp, "state"))
      input = File.join(tmp, "input.md")
      write = lambda do |data, body = ""|
        File.write(input, render_document(data, body))
        input
      end
      capture = lambda do
        File.write(input, observation_template)
        path = store.route(input)
        [File.basename(path, ".md"), path]
      end
      origin, = capture.call
      decision, = parse_document(store.prepare_decision(origin, "accept", rationale: "Executable fixture."))
      decision["evidence_lineage"] = "not-applicable"
      decision["evidence_lineage_note"] = "Protocol fixture."
      store.process(origin, write.call(decision))
      accepted, body = parse_document(accepted_template)
      accepted["originating_candidate_ids"] = [origin]
      target = store.record_accepted(write.call(accepted, body))
      target_id = File.basename(target, ".md")
      original_target = File.binread(target)
      source_id, source = capture.call
      open_id, open_source = capture.call
      original_source = read_document(source)
      open_bytes = File.binread(open_source)
      before = store.snapshot
      prepared, = parse_document(store.prepare_verification(target_id, "supported"))
      unless store.snapshot == before && prepared.dig("review", "rationale") == ""
        raise "reviewed preparation wrote state or invented its rationale"
      end
      proposal, body = parse_document(verification_proposal_template)
      proposal["target_accepted_id"] = target_id
      proposal["review"] = prepared.fetch("review")
      proposal["review"]["rationale"] = "Reviewed exact fixture opportunity."
      proposal["source_observation_ids"] = [source_id, open_id]
      proposal["review"]["close_observation_ids"] = [source_id]
      id = proposal.fetch("review").fetch("verification_proposal_id")
      run = self_test_cli(store.root)
      run.call(1, "route-verification", "--file", "-", stdin: render_document(proposal, body), error: "retired")
      out, err, status = Open3.capture3({STATE_ENV => nil}, RbConfig.ruby, File.expand_path(__FILE__), "route-verification")
      raise "retired routing tried to use unset state" unless status.exitstatus == 1 && out.empty? && err.include?("retired")
      raise "retired routing wrote state" unless store.snapshot == before
      malformed = Marshal.load(Marshal.dump(proposal))
      malformed["review"]["close_observation_ids"] = [origin]
      self_test_error("select distinct RC source") { store.record_verification(write.call(malformed, body)) }
      outside = File.join(tmp, "outside.md")
      File.rename(source, outside)
      File.symlink(outside, source)
      self_test_error("outside the state root") { store.record_verification(write.call(proposal, body)) }
      File.unlink(source)
      File.rename(outside, source)
      File.write(source, File.read(source).sub("Short observation title", "Tampered title"))
      self_test_error("intake fields changed") { store.record_verification(write.call(proposal, body)) }
      File.write(source, render_document(*original_source))
      run.call(2, "record-verification", error: "choose --file")
      run.call(2, "record-verification", "--id", id, "--file", input, error: "choose --file")
      [["--reject"], ["--rationale", "Reason only"],
        ["--reject", "--acknowledge-closure", source_id, "--rationale", "Both"]].each do |options|
        run.call(2, "record-verification", "--id", id, *options, error: "resolution requires")
      end
      legacy_id = File.basename(self_test_legacy_verification(store, write.call(proposal, body)), ".md")
      apply, = parse_document(store.prepare_decision(legacy_id, "apply", rationale: "Reviewed legacy evidence."))
      %w[identity symlink].each do |defect|
        if defect == "identity"
          data, target_body = read_document(target)
          data["accepted_id"] = "SCR-20000101-000000"
          File.write(target, render_document(data, target_body))
          message = "record identity does not match"
        else
          File.rename(target, outside)
          File.symlink(outside, target)
          message = "outside the state root"
        end
        before = store.snapshot
        supplemental = proposal.merge("supplemental_reason" => "A distinct reviewed boundary.")
        run.call(1, "record-verification", "--file", "-", stdin: render_document(supplemental, body), error: message)
        run.call(1, "process-verification", "--id", legacy_id, "--decision", write.call(apply), error: message)
        raise "invalid verification target refusal wrote state" unless store.snapshot == before
        if defect == "symlink"
          raise "verification changed an external target" unless File.binread(outside) == original_target
          File.unlink(target)
          File.rename(outside, target)
        else
          File.binwrite(target, original_target)
        end
      end
      legacy_path = File.join(store.root, "verifications/inbox", "#{legacy_id}.md")
      renamed_id = "VP-20000101T000000Z-000000"
      renamed_path = File.join(File.dirname(legacy_path), "#{renamed_id}.md")
      File.rename(legacy_path, renamed_path)
      before = store.snapshot
      %w[apply reject].each do |verdict|
        decision = apply.merge("verification_proposal_id" => renamed_id, "verdict" => verdict)
        run.call(1, "process-verification", "--id", renamed_id, "--decision", write.call(decision), error: "verification identity does not match")
      end
      raise "mismatched legacy intake refusal wrote state" unless store.snapshot == before
      File.rename(renamed_path, legacy_path)
      legacy_bytes = File.binread(legacy_path)
      File.rename(legacy_path, outside)
      File.symlink(outside, legacy_path)
      before = store.snapshot
      %w[apply reject].each do |verdict|
        run.call(1, "process-verification", "--id", legacy_id, "--decision", write.call(apply.merge("verdict" => verdict)), error: "outside the state root")
      end
      unless store.snapshot == before && File.binread(outside) == legacy_bytes
        raise "external legacy intake refusal changed state or external evidence"
      end
      File.unlink(legacy_path)
      File.rename(outside, legacy_path)
      before = store.snapshot
      self_test_error("support already pending: #{legacy_id}") { store.record_verification(write.call(proposal, body)) }
      raise "pending support refusal wrote state" unless store.snapshot == before
      reject, = parse_document(store.prepare_decision(legacy_id, "reject", rationale: "Insufficient legacy evidence."))
      store.process_verification(legacy_id, write.call(reject))
      raise "legacy rejection changed accepted evidence" unless File.binread(target) == original_target
      submitted = render_document(proposal, body)
      archive = run.call(0, "record-verification", "--file", "-", stdin: submitted).strip
      stored, = read_document(archive)
      unless stored["verification_proposal_id"] == id && stored["triage"] == proposal["review"] &&
          read_document(target).first.fetch("applied_verification_proposal_ids") == [id] &&
          File.binread(open_source) == open_bytes && !File.exist?(source)
        raise "reviewed application lost its identity or closed an unselected observation"
      end
      closed = read_document(File.join(store.root, "retrospectives/archive", "#{source_id}.md"))
      unless without_keys(closed.first, "triage") == original_source.first && closed.last == original_source.last
        raise "reviewed closure changed original evidence"
      end
      false_id = "VP-20000101T000000Z-000000"
      false_path = File.join(store.root, "verifications/archive", "#{false_id}.md")
      FileUtils.cp(archive, false_path)
      self_test_error("identity does not match") { store.record_verification(nil, proposal_id: false_id) }
      File.unlink(false_path)
      target_bytes = File.binread(target)
      File.binwrite(target, original_target)
      self_test_error("conflicts with accepted metadata") { store.record_verification(nil, proposal_id: id) }
      File.binwrite(target, target_bytes)
      curated, target_body = parse_document(store.prepare_accepted_update(target_id))
      curated["decisive_evidence"] = ["Curated summary; original evidence remains in the applied proposal."]
      store.update_accepted(target_id, write.call(curated, target_body))
      archive_bytes = File.binread(archive)
      altered, archive_body = read_document(archive)
      altered["decisive_evidence"] = ["Altered original evidence."]
      File.write(archive, render_document(altered, archive_body))
      before = store.snapshot
      run.call(1, "record-verification", "--id", id, error: "intake fields changed")
      raise "tampered verification retry wrote state" unless store.snapshot == before
      File.binwrite(archive, archive_bytes)
      before = store.snapshot
      run.call(0, "record-verification", "--id", id)
      run.call(0, "record-verification", "--file", "-", stdin: submitted)
      raise "completed verification retry wrote state" unless store.snapshot == before
      proposal["review"]["rationale"] = "Conflicting review."
      self_test_error("differs from stored") { store.record_verification(write.call(proposal, body)) }
      raise "conflicting retry wrote state" unless store.snapshot == before
      store.validate
      # A competing observation review must be detected before publishing or applying anything.
      fresh, = parse_document(store.prepare_verification(target_id, "supported"))
      repeat = proposal.merge("review" => fresh.fetch("review").merge("rationale" => "Stale reviewed support."))
      before = store.snapshot
      self_test_error("already supported; add supplemental_reason") { store.record_verification(write.call(repeat, body)) }
      raise "stale support refusal wrote state" unless store.snapshot == before
      proposal["review"] = fresh.fetch("review").merge("rationale" => "Second reviewed boundary.",
        "close_observation_ids" => [open_id])
      proposal["supplemental_reason"] = "A new executable boundary."
      other, = parse_document(store.prepare_decision(open_id, "no-change", rationale: "Another completed review."))
      store.process(open_id, write.call(other))
      before = store.snapshot
      self_test_error("different review") { store.record_verification(write.call(proposal, body)) }
      raise "closure conflict partially applied verification" unless store.snapshot == before
      remaining_id, remaining_path = capture.call
      prepared, = parse_document(store.prepare_verification(target_id, "contradicted"))
      contradiction, body = parse_document(verification_proposal_template)
      contradiction.merge!("target_accepted_id" => target_id, "proposed_verification" => "contradicted",
        "what_is_false" => "The intended outcome failed.", "source_observation_ids" => [remaining_id],
        "review" => prepared.fetch("review").merge("rationale" => "Reviewed observed failure."))
      store.record_verification(write.call(contradiction, body))
      state, = read_document(target)
      unless state["verification"] == "contradicted" && state.fetch("applied_verification_proposal_ids").first == id &&
          File.file?(remaining_path) && !state.fetch("contradiction").key?("resolution")
        raise "reviewed contradiction lost history or implicitly resolved observation work"
      end
      before = store.snapshot
      self_test_error("state contradicted cannot receive proposed supported") { store.record_verification(write.call(repeat, body)) }
      raise "refused support changed contradictory evidence" unless store.snapshot == before
      store.validate
    end
  end

  def queue_archive_race_self_test
    Dir.mktmpdir("retro-queue-archive-self-test.") do |tmp|
      store = Store.new(File.join(tmp, "state"))
      input = File.join(tmp, "input.md")
      decision = File.join(tmp, "decision.md")
      %w[observation candidate].each do |kind|
        File.write(input, public_send("#{kind}_template"))
        path = store.route(input)
        data, = read_document(path)
        id = data.fetch("candidate_id")
        title = data.fetch("title")
        raise "pending output changed" unless store.pending == [[id, title, path]]
        File.write(decision, store.prepare_decision(id, "no-change", rationale: "Concurrent review fixture."))
        reader = method(:read_document)
        archived = false
        # Interleave another writer after the inbox read, before the queue consumes its metadata.
        define_singleton_method(:read_document) do |source|
          document = reader.call(source)
          if source == path && !archived
            archived = true
            store.process(id, decision)
          end
          document
        end
        begin
          rows = store.review_queue
        ensure
          define_singleton_method(:read_document, reader)
        end
        unless archived && rows == [[kind, id, "Review #{kind}: #{title}", path]]
          raise "review queue lost its validated intake row during archival"
        end
        raise "next queue read retained archived intake" unless store.review_queue.empty?
        store.validate
      end
    end
  end

  def observation_self_test
    Dir.mktmpdir("retro-observation-self-test.") do |tmp|
      store = Store.new(File.join(tmp, "state"))
      store.init
      store.send(:with_state_lock) {}
      run = self_test_cli(store.root)
      input = File.join(tmp, "input.md")
      write = lambda do |data, body = ""|
        File.write(input, render_document(data, body))
        input
      end
      capture = lambda do
        data, _ = parse_document(observation_template)
        data["observation"] = "A confusing instruction caused a retry; the remedy is unknown."
        body = "Guidance was active. Impact: one retry. The suspected cause is not established.\n"
        path = run.call(0, "record-observation", "--file", write.call(data, body)).strip
        [File.basename(path, ".md"), path]
      end
      decision = lambda do |id, verdict|
        data, body = parse_document(store.prepare_decision(id, verdict, rationale: "Reviewed fixture decision."))
        if %w[accept split].include?(verdict)
          data["evidence_lineage"] = "descendant"
          data["evidence_lineage_note"] = "Active guidance shaped the observation; independence is not established."
        end
        [data, body]
      end

      # Existing records remain byte-for-byte intact while the unified producer writes new intake.
      legacy, legacy_body = parse_document(papercut_template)
      legacy_path = self_test_papercut(store, legacy, legacy_body, label: "legacy fixture")
      legacy_bytes = File.binread(legacy_path)
      id, path = capture.call
      original, original_body = read_document(path)
      unless original["record_type"] == "observation" && original["candidate_id"] == id &&
          !original.key?("proposed_destination") && !original.key?("kind") &&
          store.review_queue.any? { |row| row[0] == "observation" && row[1] == id } &&
          File.binread(legacy_path) == legacy_bytes
        raise "observation capture classified the remedy, hid intake or altered legacy evidence"
      end
      before = store.snapshot
      empty, = parse_document(store.prepare_decision(id, "accept"))
      empty["rationale"] = "Accepted fixture gap."
      self_test_error("evidence_lineage must be a non-empty string") { store.process(id, write.call(empty)) }
      raise "incomplete review changed state" unless store.snapshot == before
      data, body = decision.call(id, "accept")
      archive = store.process(id, write.call(data, body))
      archived, archived_body = read_document(archive)
      unless without_keys(archived, "triage") == original && archived_body == original_body &&
          !Dir.glob(File.join(store.root, "retrospectives", "accepted", "*.md")).any?
        raise "review changed observation evidence or implicitly created an accepted outcome"
      end
      prepared = store.prepare_accepted([id], ["abcdef0"])
      unless prepared.include?(original_body.lines.first.strip) && prepared.include?("Active guidance shaped")
        raise "accepted preparation lost observation context or reviewed lineage"
      end
      accepted, accepted_body = parse_document(accepted_template)
      accepted["originating_candidate_ids"] = [id]
      accepted_path = store.record_accepted(write.call(accepted, accepted_body))
      accepted_id = File.basename(accepted_path, ".md")

      # A later review cannot hide a dangling correction link in retained deferral history.
      historical_id, = capture.call
      deferred, body = decision.call(historical_id, "defer")
      deferred.merge!(self_test_deferral_fields)
      deferred["reviewed_at"] = "2000-01-01T00:00:00Z"
      deferred["supersedes_accepted_id"] = accepted_id
      deferred["now_false"] = "Possible correction pending the named evidence."
      store.process(historical_id, write.call(deferred, body))
      later, body = decision.call(historical_id, "no-change")
      store.reconsider(historical_id, write.call(later, body))
      accepted_bytes = File.binread(accepted_path)
      File.unlink(accepted_path)
      self_test_error("supersedes missing accepted record") { store.validate }
      File.binwrite(accepted_path, accepted_bytes)
      store.validate

      %w[local-fix external-owner no-change].each do |verdict|
        local_id, local_path = capture.call
        evidence = read_document(local_path)
        local_decision, body = decision.call(local_id, verdict)
        stored, stored_body = read_document(store.process(local_id, write.call(local_decision, body)))
        unless without_keys(stored, "triage") == evidence[0] && stored_body == evidence[1] &&
            store.review_queue.none? { |row| row[1] == local_id }
          raise "#{verdict} changed evidence or created a publication obligation"
        end
      end

      # Correction classification belongs to review, and its referenced identity must exist.
      correction_id, = capture.call
      correction, body = decision.call(correction_id, "accept")
      correction["supersedes_accepted_id"] = "SCR-20000101-000000"
      correction["now_false"] = "The earlier decision fails the newly observed boundary."
      before = store.snapshot
      self_test_error("supersedes missing accepted record") { store.process(correction_id, write.call(correction, body)) }
      raise "invalid reviewed correction changed state" unless store.snapshot == before
      correction["supersedes_accepted_id"] = accepted_id
      store.process(correction_id, write.call(correction, body))
      accepted["originating_candidate_ids"] = [correction_id]
      corrected, = read_document(store.record_accepted(write.call(accepted, accepted_body)))
      unless corrected["supersedes_accepted_ids"] == [accepted_id]
        raise "reviewed correction lost supersession lineage"
      end

      # Verification is separately adjudicated; a linked observation alone proves no claim.
      source_id, source_path = capture.call
      source_bytes = File.binread(source_path)
      proposal, proposal_body = parse_document(verification_proposal_template)
      proposal["target_accepted_id"] = accepted_id
      proposal["source_observation_ids"] = [source_id, File.basename(legacy_path, ".md")]
      proposal_path = self_test_legacy_verification(store, write.call(proposal, proposal_body))
      proposal_id = File.basename(proposal_path, ".md")
      apply, body = parse_document(store.prepare_decision(proposal_id, "apply", rationale: "Exact opportunity exercised."))
      apply_path = File.join(tmp, "apply.md")
      File.write(apply_path, render_document(apply, body))
      File.write(source_path, source_bytes.sub("A confusing instruction", "Tampered evidence"))
      before = store.snapshot
      self_test_error("intake fields changed") { store.process_verification(proposal_id, apply_path) }
      raise "verification with corrupted source changed state" unless store.snapshot == before
      File.binwrite(source_path, source_bytes)
      store.process_verification(proposal_id, apply_path)
      reviewed, body = decision.call(source_id, "no-change")
      reviewed_archive = store.process(source_id, write.call(reviewed, body))
      store.validate
      kept_bytes = File.binread(reviewed_archive)
      File.unlink(reviewed_archive)
      self_test_error("record not found") { store.validate }
      File.binwrite(reviewed_archive, kept_bytes)
      store.validate
      unless read_document(accepted_path).first["verification"] == "supported" &&
          File.binread(legacy_path) == legacy_bytes
        raise "verification failed or altered unrelated legacy evidence"
      end
      run.call(2, "record-papercut", error: "unknown command")
    end
  end

  def self_test_error(message)
    yield
  rescue Error => e
    raise unless e.message.include?(message)
  else
    raise "expected RetroState::Error containing #{message.inspect}"
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
        raise "#{arguments.inspect}: invalid error output" unless out.empty? && err.include?(error) && !err.match?(/^\s+from .+:\d+/)
      else
        raise "#{arguments.inspect}: unexpected stderr: #{err}" unless err.empty?
      end
      out
    end
  end

  def state_confinement_self_test
    Dir.mktmpdir("retro-confinement-self-test.") do |tmp|
      store = Store.new(File.join(tmp, "state"))
      input = File.join(tmp, "input.md")
      File.write(input, observation_template)
      record = store.route(input)
      store.send(:with_state_lock) {}
      outside = File.join(tmp, "state-other.md")
      [File.join(store.root, "state-version"), store.send(:state_lock_path), record].each do |path|
        bytes = File.binread(path)
        File.rename(path, outside)
        File.symlink(outside, path)
        before = store.snapshot
        self_test_error("outside the state root") { store.validate }
        if path == record
          self_test_error("outside the state root") { store.pending }
        else
          self_test_error("outside the state root") { store.init }
        end
        self_test_error("outside the state root") { store.send(:replace_write, path, "replacement") }
        unless store.snapshot == before && File.binread(outside) == bytes
          raise "state-file confinement refusal changed state or external evidence"
        end
        File.unlink(path)
        File.rename(outside, path)
      end
      root_alias = File.join(tmp, "alias")
      File.symlink(store.root, root_alias)
      raise "root alias lost canonical identity" unless Store.new(root_alias).root == store.root
      lock = store.send(:state_lock_path)
      File.unlink(lock)
      File.symlink(record, lock)
      before = store.snapshot
      self_test_error("writer lock must not be a symlink") { store.validate }
      self_test_error("writer lock must not be a symlink") { store.init }
      self_test_error("writer lock must not be a symlink") do
        Store.new(root_alias).send(:with_state_lock) { raise "entered a replaceable record's lock" }
      end
      raise "lock symlink refusal changed state or linked evidence" unless store.snapshot == before
      File.unlink(lock)
      Store.new(root_alias).send(:with_state_lock) {}
      kept = File.join(store.root, "kept.md")
      File.rename(record, kept)
      File.symlink(kept, record)
      Store.new(root_alias).validate
      store.show([File.basename(record, ".md")])
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
      papercut = self_test_papercut(store, papercut_data, papercut_body, label: "inspection fixture")
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
            "audits/learning-process/artifact-cadence.lock"
          ].sort
            raise "process comparison did not detect the shared writer lock"
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
        File.basename(self_test_papercut(store, data, body, label: "comparison fixture"), ".md")
      end
      deferred_id = File.basename(store.route(input), ".md")
      decision, body = parse_document(store.prepare_decision(deferred_id, "defer", rationale: "An independent observation is missing."))
      decision.merge!(self_test_deferral_fields)
      decision["reviewed_at"] = "2000-01-01T00:00:00Z"
      run.call(0, "process", "--id", deferred_id, "--decision", "-", stdin: render_document(decision, body))
      File.unlink(File.join(root, "audits/learning-process/artifact-cadence.lock"))
      File.write(snapshot_file, JSON.generate(store.snapshot))
      papercut_ids.each do |id|
        run.call(0, "close-papercut", "--id", id, "--outcome", "no-action", "--rationale", "Reviewed comparison fixture.")
      end
      decision = store.prepare_decision(deferred_id, "no-change", rationale: "A reviewed terminal outcome.")
      run.call(0, "reconsider", "--id", deferred_id, "--decision", "-", stdin: decision)
      paths = papercut_ids.flat_map { |id| ["papercuts/inbox/#{id}.md", "papercuts/archive/#{id}.md"] }
      strict = JSON.parse(run.call(1, "compare", "--file", snapshot_file))
      unless strict.fetch("unexpected") == (paths + [
        "retrospectives/archive/#{deferred_id}.md", "audits/learning-process/artifact-cadence.lock"
      ]).sort
        raise "closure and reconsideration changed unexpected bookkeeping"
      end
      actions = papercut_ids.flat_map { |id| ["--allow-action", "close-papercut:#{id}"] }
      actions += ["--allow-action", "reconsider:#{deferred_id}"]
      run.call(0, "compare", "--file", snapshot_file, *actions)
      partial = JSON.parse(run.call(1, "compare", "--file", snapshot_file, "--allow-action", "reconsider:#{deferred_id}"))
      raise "reconsideration allowance hid papercut changes" unless partial.fetch("unexpected") == paths.sort
      cadence = File.join(root, "audits/learning-process/artifact-cadence.yml")
      File.write(cadence, "legacy cadence fixture\n")
      File.write(snapshot_file, JSON.generate(store.snapshot))
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
      File.write(File.join(root, "audits/learning-process/artifact-cadence.yml"), "legacy cadence fixture\n")
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
        File.basename(self_test_legacy_verification(store, write.call(render_document(data, body))), ".md")
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
      papercut_path = self_test_papercut(store, papercut, body, label: "context fixture")
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

      # Historical display metadata stays opaque, including stale evidence references.
      legacy_context = {
        "claim_limits" => {"scope" => "Historical acquisition context."},
        "prose" => [{"source" => "Stale original wording.", "text" => "Replacement display.",
                     "evidence" => ["No longer present evidence."], "limits" => ["scope"]}]
      }
      create_accepted = lambda do |destination, disposition = "implemented", verification = "unverified", unverified_claims = nil|
        File.write(input, candidate_template)
        candidate_id = File.basename(store.route(input), ".md")
        store.process(candidate_id, decide.call(candidate_id, "accept"))
        data, body = parse_document(accepted_template)
        data["originating_candidate_ids"] = [candidate_id]
        data["destination"] = destination
        data["verification_context"] = legacy_context
        data["expected_behavior"] = "Exact [#{destination}] outcome."
        data["source_report_summary"] = "Summary [#{destination}]."
        data["verification_opportunity"] = "Check #{destination} in a later task."
        data["implementation_commits"] = [Digest::SHA256.hexdigest(destination)[0, 40]]
        data["disposition"] = disposition
        data["verification"] = verification
        data["verification_basis"] = (verification == "unverified") ? "none" : "later-session"
        data["unverified_claims"] = unverified_claims unless unverified_claims.nil?
        body = body.sub("# Accepted candidate", "# Accepted fixture [#{destination}]")
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
        data["decisive_evidence"] << data.fetch("observation")
        data["source_note"] = data.fetch("observation")
        data["decisive_evidence"] << "Shared context evidence!" if supplemental
        data["opportunity_match"] = "Only this #{claim} fixture scope is exercised; comparative improvement is unverified."
        data["contradiction"] = "Unrelated proposal metadata must remain unchanged."
        body += "\nBody-only limit: caller recovery is untested.\n"
        data["what_is_false"] = "Fixture assertion failed." if state == "contradicted"
        data["supplemental_reason"] = "A distinct fixture boundary." if supplemental
        File.basename(self_test_legacy_verification(store, write.call(data, body)), ".md")
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
        "EXACT [SHARED DOMAIN FIRST] OUTCOME." => unverified_id,
        "SUMMARY [SHARED DOMAIN FIRST]." => unverified_id,
        "ACCEPTED FIXTURE [SHARED DOMAIN FIRST]" => unverified_id,
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
      run.call(1, "accepted-records", "--active-supported", error: "requires --destination TEXT or --text TEXT")
      run.call(2, "snapshot", "--active-supported", error: "--active-supported is not valid")
      unless run.call(0, "accepted-records", "--help").include?("--active-supported")
        raise "accepted-record lookup help omitted its supplemental filter"
      end
      {"Shared domain first" => [unverified_id, "implemented", "unverified"],
       "Contested claim" => [contradicted_id, "implemented", "contradicted"]}.each do |destination, expected|
        unless lookup.call("--destination", destination, "--active-supported").empty?
          raise "supplemental lookup included unverified or contradicted evidence"
        end
        unless run.call(0, "accepted-records", "--destination", destination).split("\t").first(3) == expected
          raise "broad lookup hid an outcome or changed its verification state"
        end
      end
      lookup_path = File.join(root, "retrospectives/accepted/#{supported_id}.md")
      lookup_bytes = File.binread(lookup_path)
      lookup_data, lookup_body = parse_document(lookup_bytes)
      begin
        {"accepted" => [supported_id], "implemented" => [supported_id],
         "no-change" => [], "superseded" => [], "reverted" => []}.each do |disposition, expected_ids|
          File.write(lookup_path, render_document(lookup_data.merge("disposition" => disposition), lookup_body))
          before_query = store.snapshot
          if lookup.call("--active-supported", "--destination", "OTHER DOMAIN", "--text", "BODY-ONLY") != expected_ids
            raise "supplemental lookup selected the wrong outcomes for #{disposition}"
          end
          unless run.call(0, "accepted-records", "--text", supported_id).split("\t").first(3) ==
              [supported_id, disposition, "supported"]
            raise "broad lookup hid an outcome for #{disposition}"
          end
          raise "accepted-record lookup changed state" unless store.snapshot == before_query
        end
        File.binwrite(lookup_path, lookup_bytes + "\nauth.json\n")
        run.call(1, "accepted-records", "--text", supported_id, error: "forbidden Codex auth file")
      ensure
        File.binwrite(lookup_path, lookup_bytes)
      end
      unless lookup.call("--active-supported", "--destination", "unrelated").empty? &&
          lookup.call("--active-supported", "--destination", "Other domain", "--text", "unrelated").empty?
        raise "supplemental lookup ignored a destination or text filter"
      end
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
      compact_fields = %w[id destination expected_behavior verification verification_basis supported_claims contradicted_claims unverified_claims]
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
      unless records.first.fetch("supported_claims") == supported_claims &&
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
      [detail, {"records" => mixed}, historical,
        JSON.parse(run.call(0, "verification-context", "--id", contradicted_id))].each do |output|
        output.fetch("records").each do |context|
          proposals = context.fetch("verification_proposals")
          ids = proposals.map { |record| record.fetch("id") }
          roles = %w[selected applied pending].map { |role| context.fetch("#{role}_verification_proposal_ids") }
          unless ids == roles.flatten.uniq && ids.uniq == ids
            raise "joined verification context repeated a proposal or lost its role"
          end
          %w[supported_claims contradicted_claims].each do |field|
            context.fetch(field)&.each do |claim|
              id = claim.fetch("verification_proposal_id")
              proposal = proposals.find { |record| record.fetch("id") == id }
              unless context.fetch("applied_verification_proposal_ids").include?(id) &&
                  proposal.dig("frontmatter", "proposed_verification") == field.delete_suffix("_claims") &&
                  claim == proposal.fetch("frontmatter").slice(*compact_claim_fields, "observation")
                raise "claim summary selected pending, rejected, or differently scoped evidence"
              end
            end
          end
          [context.fetch("accepted"), *proposals].each do |record|
            unless record == store.show([record.fetch("id")]).fetch("records").first
              raise "joined context changed source evidence, opportunity match, triage rationale, body limits, or provenance"
            end
          end
        end
      end
      replacement, replacement_body = parse_document(store.prepare_accepted_update(supported_id))
      unless replacement.fetch("verification_context") == legacy_context &&
          replacement_body == records.first.fetch("accepted").fetch("body")
        raise "accepted preparation discarded historical metadata or body-only evidence"
      end
      draft, = parse_document(run.call(0, "prepare-verification", "--id", supported_id, "--verification", "supported"))
      unless draft.fetch("target_accepted_id") == supported_id && draft.fetch("supplemental_reason") == ""
        raise "stale display metadata blocked proposal preparation or removed supplementation"
      end
      lookup_context = lambda do
        [store.verification_context(record_ids: [supported_id]),
          store.verification_context(destinations: ["Other domain second"], compact: true)]
      end
      fresh_detail, fresh_discovery = JSON.parse(JSON.generate(lookup_context.call))
      context = fresh_detail.fetch("records").first
      fresh_accepted = context.fetch("accepted")
      fresh_proposal = context.fetch("verification_proposals").find { |record| record.fetch("id") == applied_id }
      fresh_accepted.fetch("frontmatter")["expected_behavior"] = "Updated fixture expectation."
      fresh_proposal.fetch("frontmatter").fetch("triage")["notes"] = "Updated fixture review notes."
      fresh_discovery.fetch("records").first["expected_behavior"] = "Updated fixture expectation."
      originals = [fresh_accepted, fresh_proposal].to_h do |record|
        path = File.join(root, record.fetch("path"))
        [path, File.binread(path)]
      end
      begin
        [fresh_accepted, fresh_proposal].each do |record|
          File.write(File.join(root, record.fetch("path")), render_document(record.fetch("frontmatter"), record.fetch("body")))
        end
        unless lookup_context.call == [fresh_detail, fresh_discovery]
          raise "verification context retained stale accepted metadata or proposal evidence between calls"
        end
      ensure
        originals.each { |path, bytes| File.binwrite(path, bytes) }
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

      # Validation and every context view must agree with applied proposal evidence.
      %w[unverified supported missing-contradiction changed-claim].each do |defect|
        id = (defect == "unverified") ? supported_id : contradicted_id
        path = File.join(root, "retrospectives/accepted", "#{id}.md")
        original = File.binread(path)
        data, body = read_document(path)
        case defect
        when "unverified"
          data["verification"] = "unverified"
          data["verification_basis"] = "none"
          message = "applied supported proposal no longer matches accepted state"
        when "supported"
          data["verification"] = "supported"
          data.delete("contradiction")
          message = "applied contradicted proposal no longer matches accepted state"
        else
          if defect == "missing-contradiction"
            data.delete("contradiction")
          else
            data["contradiction"]["what_is_false"] = "A different assertion."
          end
          message = "applied contradiction no longer matches accepted state"
        end
        File.write(path, render_document(data, body))
        inconsistent = store.snapshot
        run.call(1, "validate", error: message)
        run.call(1, "verification-context", "--id", id, error: message)
        [[], ["--compact"]].each do |mode|
          run.call(1, "verification-context", "--destination", data.fetch("destination"), *mode, error: message)
        end
        raise "verification consistency refusal wrote state" unless store.snapshot == inconsistent
        File.binwrite(path, original)
      end
      # Legacy contradiction without applied proposal provenance remains valid as stored.
      legacy_path = File.join(root, "retrospectives/accepted", "#{legacy_id}.md")
      legacy_bytes = File.binread(legacy_path)
      legacy, legacy_body = read_document(legacy_path)
      legacy["verification"] = "contradicted"
      File.write(legacy_path, render_document(legacy, legacy_body))
      legacy_snapshot = store.snapshot
      run.call(0, "validate")
      run.call(0, "verification-context", "--id", legacy_id)
      raise "legacy consistency check wrote state" unless store.snapshot == legacy_snapshot
      File.binwrite(legacy_path, legacy_bytes)

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
        data["decisive_evidence"] << data.fetch("verification_opportunity")
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

      flagged, = parse_document(prepare.call(0, "--id", targets.first, "--verification", "supported", "--reviewed"))
      raise "compatibility flag lost reviewed preparation" unless flagged.dig("review", "rationale") == ""
      drafts = %w[supported contradicted].to_h do |state|
        text = prepare.call(0, "--id", targets.first, "--verification", state)
        data, body = parse_document(text)
        blank_fields = %w[title source_scope verification_basis opportunity_match claim observation redaction_review]
        unless data.values_at("target_accepted_id", "proposed_verification", "decisive_evidence") == [targets.first, state, []] &&
            blank_fields.all? { |field| data.fetch(field) == "" } && body.empty? &&
            %w[verification_proposal_id created_at intake_digest triage supplemental_reason].none? { |field| data.key?(field) } &&
            ((state == "contradicted") ? data.fetch("what_is_false") == "" : !data.key?("what_is_false")) &&
            text.include?("Exercise preparation target 0.") && !text.include?("Exercise preparation target 1.") &&
            !text.include?("$ref")
          raise "verification preparation invented judgment or lost target context"
        end
        before = store.snapshot
        run.call(1, "record-verification", "--file", "-", stdin: text, error: "title must be a non-empty string")
        raise "incomplete verification submission wrote state" unless store.snapshot == before
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
        data["review"]["rationale"] = "Reviewed fixture evidence."
        data["what_is_false"] = "The fixture expectation failed." if data.key?("what_is_false")
        data["supplemental_reason"] = "A distinct fixture boundary." if data.key?("supplemental_reason")
        comments = text.lines.drop(1).take_while { |line| line.start_with?("#") || line.strip.empty? }.join
        render_document(data, "").sub(/\A---\n/) { "---\n#{comments}" }
      end
      completed = complete.call(drafts.fetch("supported"))
      legacy_id = File.basename(self_test_legacy_verification(store, write.call(completed)), ".md")
      pending = prepare.call(0, "--id", targets.first, "--verification", "supported")
      unless parse_document(pending).first.fetch("supplemental_reason") == "" && pending.include?(legacy_id)
        raise "pending support preparation lost the supplementation requirement or context"
      end
      before = store.snapshot
      run.call(1, "record-verification", "--file", "-", stdin: completed, error: "support already pending")
      raise "stale verification submission wrote state" unless store.snapshot == before
      store.process_verification(legacy_id, write.call(store.prepare_decision(legacy_id, "reject", rationale: "Legacy fixture.")))
      archived_path = run.call(0, "record-verification", "--file", "-", stdin: completed).strip
      proposal_id = File.basename(archived_path, ".md")
      stored, stored_body = read_document(archived_path)
      expected, = parse_document(completed)
      unless without_keys(stored, "verification_proposal_id", "created_at", "intake_digest", "triage") == expected &&
          stored_body.empty? && !File.read(archived_path).include?("# Target context:")
        raise "submission persisted preparation comments or changed curated evidence"
      end
      prepare.call(1, "--id", proposal_id, "--verification", "supported", error: "invalid accepted_id")
      supported = prepare.call(0, "--id", targets.first, "--verification", "supported")
      unless parse_document(supported).first.fetch("supplemental_reason") == "" && supported.include?(proposal_id)
        raise "supported target preparation lost applied provenance or supplementation"
      end

      contradiction, = parse_document(complete.call(drafts.fetch("contradicted")))
      contradiction["target_accepted_id"] = targets.last
      id = File.basename(self_test_legacy_verification(store, write.call(render_document(contradiction, ""))), ".md")
      only_contradiction, = parse_document(prepare.call(0, "--id", targets.last, "--verification", "supported"))
      raise "pending contradiction required supplemental support" if only_contradiction.key?("supplemental_reason")
      decision = store.prepare_decision(id, "reject", rationale: "Reviewed fixture rejection.")
      store.process_verification(id, write.call(decision))
      run.call(0, "record-verification", "--file", "-", stdin: complete.call(drafts.fetch("contradicted")))
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
          body.empty? && DEFERRAL_FIELDS.none? { |field| decision.key?(field) }
        raise "incorrect terminal decision draft"
      end
      self_test_error("rationale must be a non-empty string") do
        validate_decision(decision, body, label: "unreviewed draft", expected_id: id)
      end
      deferred, = parse_document(run.call(0, "prepare-decision", "--id", id, "--verdict", "defer"))
      unless self_test_deferral_fields.keys.all? { |field| deferred.fetch(field).empty? } &&
          deferred.fetch("owner") == "skill-retro-triage"
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
        DEFERRAL_FIELDS.each { |field| raw.delete(field) }
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
        template_id = File.basename(self_test_legacy_verification(store, input), ".md")
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
      proposal_path = self_test_legacy_verification(store, input)
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

  def self_test_legacy_draft
    <<~MARKDOWN
      ---
      schema_version: 1
      record_type: draft
      draft_id: SD-20260715-abcdef
      created_at: "2026-07-15T12:00:00Z"
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
      owner: "learning-process-review"
      review_trigger: "The named evidence is supplied in the review input; check it against missing_evidence."
      next_action: "Executable next review action."
      close_condition: "Condition for activation or deprecation."
      status: open
      redaction_review: "Confirmed no raw transcript, secret, private source, or unredacted local path is included."
      ---

      # Provisional skill kernel

      Keep only the coherent reusable kernel. Do not copy a full speculative skill.
    MARKDOWN
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
        unless id.start_with?("VP-")
          data["evidence_lineage"] = "not-applicable"
          data["evidence_lineage_note"] = "Executable protocol fixture, not behavioral evidence."
        end
        data["reviewed_at"] = "2026-10-15T12:00:00Z"
        DEFERRAL_FIELDS.each { |field| data.delete(field) } unless id.start_with?("VP-")
        write.call("#{id}-#{verdict}.md", data, body)
      end
      route_candidate = lambda do |store|
        data, body = parse_document(observation_template)
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
        path = self_test_legacy_verification(store, write.call("proposal.md", data, body))
        File.basename(path, ".md")
      end
      reviewed = lambda do |store, accepted, state = "supported", supplemental = false|
        target = File.basename(accepted, ".md")
        prepared, = parse_document(store.prepare_verification(target, state))
        data, body = parse_document(verification_proposal_template)
        data.merge!("target_accepted_id" => target, "proposed_verification" => state,
          "review" => prepared.fetch("review"), "observation" => "Reviewed #{SecureRandom.hex(3)}",
          "decisive_evidence" => ["Reviewed evidence #{SecureRandom.hex(3)}"])
        data["what_is_false"] = "The claimed boundary failed." if state == "contradicted"
        data["supplemental_reason"] = "A distinct reviewed boundary." if supplemental
        sources = 3.times.map { route_candidate.call(store).first }
        data["source_observation_ids"] = sources
        data["review"].merge!("rationale" => "Reviewed fixture evidence.", "close_observation_ids" => sources.first(2))
        id = data.fetch("review").fetch("verification_proposal_id")
        [id, write.call("#{id}.md", data, body), sources]
      end
      event = lambda do |worker, expected|
        ready = IO.select([worker.fetch(1)], nil, nil, 5)
        actual = ready && worker.fetch(1).gets&.strip
        raise "child expected #{expected.inspect}, got #{actual.inspect}" unless actual == expected
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
        event.call(worker, "started")
        worker
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
      crash_at = lambda do |point, &action|
        worker = start.call(point, &action)
        event.call(worker, "paused")
        kill.call(worker)
      end
      blocked = lambda do |worker|
        if IO.select([worker.fetch(1)], nil, nil, 0.1)
          raise "shared mutation completed while another writer held the state lock: #{worker.fetch(1).gets}"
        end
      end

      # Reconsideration must read the preceding writer's decision under the shared lock.
      store = Store.new(File.join(tmp, "parallel-reconsider"))
      store.init
      id, = route_candidate.call(store)
      triages = []
      decisions = 3.times.map do |index|
        data, = parse_document(decision_template)
        data.merge!(self_test_deferral_fields)
        data["candidate_id"] = id
        data["reviewed_at"] = "2000-01-0#{index + 1}T00:00:00Z"
        data["rationale"] = "Concurrent reconsideration fixture #{index}."
        notes = "Review notes #{index}."
        triages << without_keys(data, "schema_version", "record_type").merge("notes" => notes)
        write.call("reconsider-#{index}.md", data, notes)
      end
      archive = store.process(id, decisions.fetch(0))
      original, original_body = read_document(archive)
      first = start.call(:state_file_prepared) do |fault|
        Store.new(store.root, fault_injector: fault).reconsider(id, decisions.fetch(1))
      end
      event.call(first, "paused")
      second = start.call(nil) do |fault|
        Store.new(store.root, fault_injector: fault).reconsider(id, decisions.fetch(2))
      end
      blocked.call(second)
      first.fetch(2).puts("continue")
      finish.call(first)
      finish.call(second)
      data, body = read_document(archive)
      unless data["triage_history"] == triages.first(2) && data["triage"] == triages.last
        raise "parallel reconsideration lost a decision or its notes"
      end
      unless without_keys(data, "triage", "triage_history") == without_keys(original, "triage") && body == original_body
        raise "parallel reconsideration changed the original candidate evidence"
      end
      store.validate

      # Killing the resource-owning process before publication must leave a retryable inbox.
      store, = fixture.call("atomic-create")
      id, inbox = route_candidate.call(store)
      decision = decide.call(id, "reject")
      crash_at.call(:state_file_prepared) do |fault|
        Store.new(store.root, fault_injector: fault).process(id, decision)
      end
      archive = File.join(store.root, "retrospectives/archive", "#{id}.md")
      raise "unpublished archive became visible" if File.exist?(archive)
      raise "interrupted archival lost inbox" unless File.file?(inbox)
      run = self_test_cli(store.root)
      run.call(0, "process", "--id", id, "--decision", decision)
      run.call(0, "validate")
      raise "archive recovery lost its decision" unless read_document(archive).first.dig("triage", "verdict") == "reject"
      original = File.binread(archive)
      self_test_error("refusing to overwrite") do
        store.send(:exclusive_write, archive, "replacement")
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
        event.call(first, "paused")
        second = start.call(nil) do |fault|
          Store.new(store.root, fault_injector: fault).process_verification(second_id, second_decision)
        end
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

      # Both writers must refuse escaped archive destinations before applying any evidence.
      %w[reviewed legacy].each do |mode|
        store, accepted = fixture.call("confined-#{mode}")
        if mode == "reviewed"
          id, input, = reviewed.call(store, accepted)
        else
          id = propose.call(store, accepted, "supported")
          input = decide.call(id, "apply")
        end
        invoke = lambda do |writer|
          (mode == "reviewed") ? writer.record_verification(input) : writer.process_verification(id, input)
        end
        directory = File.join(store.root, "verifications/archive")
        outside = File.join(tmp, "#{mode}-outside")
        File.rename(directory, outside)
        File.chmod(0o755, outside)
        File.symlink(outside, directory)
        before = store.snapshot
        self_test_error("outside the state root") { invoke.call(store) }
        self_test_error("outside the state root") { store.validate }
        self_test_error("outside the state root") { store.init }
        unless store.snapshot == before && Dir.empty?(outside) && (File.stat(outside).mode & 0o777) == 0o755
          raise "escaped archive directory refusal wrote state or changed external permissions"
        end
        File.unlink(directory)
        File.rename(outside, directory)
        archive = File.join(directory, "#{id}.md")
        File.symlink(outside, archive)
        before = store.snapshot
        self_test_error("dangling symlink") { invoke.call(store) }
        self_test_error("dangling symlink") { store.validate }
        raise "dangling archive refusal wrote state" unless store.snapshot == before && !File.exist?(outside)
        File.unlink(archive)
        crash_at.call(:verification_archive_written) do |fault|
          invoke.call(Store.new(store.root, fault_injector: fault))
        end
        bytes = File.binread(archive)
        File.rename(archive, outside)
        File.symlink(outside, archive)
        before = store.snapshot
        self_test_error("outside the state root") { invoke.call(store) }
        self_test_error("outside the state root") { store.validate }
        unless store.snapshot == before && File.binread(outside) == bytes
          raise "external matching archive refusal changed state or evidence"
        end
        File.unlink(archive)
        File.rename(outside, archive)
        invoke.call(store)
        store.validate
      end

      # Reviewed submission survives a killed writer at every durable publication boundary.
      %i[state_file_prepared verification_submission_written verification_accepted_written
        verification_archive_written candidate_archive_written verification_observation_closed].each do |point|
        store, accepted = fixture.call("reviewed-#{point}")
        id, input, sources = reviewed.call(store, accepted)
        originals = sources.to_h { |source_id| [source_id, read_document(File.join(store.root, "retrospectives/inbox", "#{source_id}.md"))] }
        crash_at.call(point) { |fault| Store.new(store.root, fault_injector: fault).record_verification(input) }
        unless point == :state_file_prepared
          raise "interrupted reviewed submission vanished from queue" unless store.review_queue.any? { |row| row[1] == id }
          self_test_error("record-verification") { store.process_verification(id, decide.call(id, "reject")) }
        end
        store.record_verification(input)
        store.validate
        before = store.snapshot
        store.record_verification(nil, proposal_id: id)
        raise "reviewed recovery retry changed state" unless store.snapshot == before
        unless read_document(accepted).first.fetch("applied_verification_proposal_ids") == [id]
          raise "reviewed recovery duplicated or lost verification"
        end
        sources.each_with_index do |source_id, index|
          area = (index < 2) ? "archive" : "inbox"
          data, body = read_document(File.join(store.root, "retrospectives", area, "#{source_id}.md"))
          unless without_keys(data, "triage") == originals.fetch(source_id).first && body == originals.fetch(source_id).last
            raise "reviewed recovery changed source evidence"
          end
        end
      end
      # A later contradiction can make persisted, unapplied support impossible to finish.
      store, accepted = fixture.call("reviewed-reject-stale")
      id, input, sources = reviewed.call(store, accepted)
      crash_at.call(:verification_submission_written) { |fault| Store.new(store.root, fault_injector: fault).record_verification(input) }
      original = read_document(File.join(store.root, "verifications/inbox", "#{id}.md"))
      _other_id, other_input, = reviewed.call(store, accepted, "contradicted")
      store.record_verification(other_input)
      self_test_error("state contradicted") { store.record_verification(nil, proposal_id: id) }
      store.process(sources.first, decide.call(sources.first, "no-change"))
      source_bytes = store.show(sources).fetch("records").to_h do |record|
        path = File.join(store.root, record.fetch("path"))
        [path, File.binread(path)]
      end
      target_bytes = File.binread(accepted)
      reason = "A later contradiction made the unapplied support ineligible."
      crash_at.call(:verification_archive_written) do |fault|
        Store.new(store.root, fault_injector: fault).record_verification(nil, proposal_id: id, reject: true, rationale: reason)
      end
      store.record_verification(nil, proposal_id: id)
      rejected, rejected_body = read_document(File.join(store.root, "verifications/archive", "#{id}.md"))
      unless [without_keys(rejected, "triage"), rejected_body] == original && rejected.dig("triage", "verdict") == "reject" &&
          rejected.dig("triage", "rationale") == reason && File.binread(accepted) == target_bytes &&
          source_bytes.all? { |path, bytes| File.binread(path) == bytes } && store.review_queue.none? { |row| row[1] == id }
        raise "recovery rejection lost original intent, changed evidence or left queued work"
      end
      run = self_test_cli(store.root)
      before = store.snapshot
      run.call(0, "record-verification", "--id", id, "--reject", "--rationale", reason)
      store.record_verification(input)
      run.call(1, "record-verification", "--id", id, "--reject", "--rationale", "Different reason", error: "differs from stored")
      raise "rejection retries changed the stored outcome" unless store.snapshot == before
      store.validate

      # Another reviewer may close a selected observation after verification was applied.
      %i[verification_accepted_written verification_archive_written].each do |point|
        store, accepted = fixture.call("reviewed-ack-#{point}")
        id, input, sources = reviewed.call(store, accepted)
        crash_at.call(point) { |fault| Store.new(store.root, fault_injector: fault).record_verification(input) }
        original = read_document(File.join(store.root, "verifications/inbox", "#{id}.md"))
        target_bytes = File.binread(accepted)
        deferred, body = parse_document(store.prepare_decision(sources.first, "defer", rationale: "Review remains open."))
        deferred.merge!(self_test_deferral_fields)
        deferred["reviewed_at"] = "2026-01-01T00:00:00Z"
        store.process(sources.first, write.call("defer.md", deferred, body))
        reason = "Another review completed this selected observation; retain its decision."
        before = store.snapshot
        self_test_error("already completed by another review") do
          store.record_verification(nil, proposal_id: id, acknowledge_closures: [sources.first], rationale: reason)
        end
        raise "acknowledgment closed a deferred observation" unless store.snapshot == before
        store.reconsider(sources.first, decide.call(sources.first, "no-change"))
        closed_path = File.join(store.root, "retrospectives/archive", "#{sources.first}.md")
        closed_bytes = File.binread(closed_path)
        before = store.snapshot
        self_test_error("different review") { store.record_verification(nil, proposal_id: id) }
        self_test_error("cannot be rejected") { store.record_verification(nil, proposal_id: id, reject: true, rationale: reason) }
        self_test_error("distinct planned") do
          store.record_verification(nil, proposal_id: id, acknowledge_closures: [sources.last], rationale: reason)
        end
        self_test_error("already completed by another review") do
          store.record_verification(nil, proposal_id: id, acknowledge_closures: sources.first(2), rationale: reason)
        end
        self_test_error("forbidden Codex auth file") do
          store.record_verification(nil, proposal_id: id, acknowledge_closures: [sources.first], rationale: "/tmp/auth.json")
        end
        raise "refused resolutions wrote state" unless store.snapshot == before
        checkpoint = (point == :verification_archive_written) ? :verification_resolution_written : :verification_archive_written
        crash_at.call(checkpoint) do |fault|
          Store.new(store.root, fault_injector: fault).record_verification(nil, proposal_id: id,
            acknowledge_closures: [sources.first], rationale: reason)
        end
        archive = store.record_verification(nil, proposal_id: id)
        resolved, resolved_body = read_document(archive)
        unless [without_keys(resolved, "triage"), resolved_body] == original &&
            without_keys(resolved.fetch("triage"), "acknowledged_closures") == original.first.fetch("review") &&
            resolved.dig("triage", "acknowledged_closures", sources.first, "rationale") == reason &&
            File.binread(accepted) == target_bytes && File.binread(closed_path) == closed_bytes &&
            File.file?(File.join(store.root, "retrospectives/archive", "#{sources[1]}.md")) &&
            File.file?(File.join(store.root, "retrospectives/inbox", "#{sources.last}.md")) &&
            store.review_queue.none? { |row| row[1] == id }
          raise "acknowledgment changed original evidence or lost remaining closures"
        end
        run = self_test_cli(store.root)
        before = store.snapshot
        run.call(0, "record-verification", "--id", id, "--acknowledge-closure", sources.first, "--rationale", reason)
        store.record_verification(input)
        run.call(1, "record-verification", "--id", id, "--acknowledge-closure", sources.first,
          "--rationale", "Changed judgment", error: "differs from stored")
        raise "acknowledgment retries wrote state" unless store.snapshot == before
        changed, body = read_document(closed_path)
        changed["triage"]["rationale"] = "Changed after acknowledgment."
        File.write(closed_path, render_document(changed, body))
        self_test_error("acknowledged observation changed") { store.record_verification(nil, proposal_id: id) }
        self_test_error("acknowledged observation changed") { store.validate }
        File.binwrite(closed_path, closed_bytes)
        store.validate
      end

      # Rejection must observe an application that finishes while it waits for the lock.
      store, accepted = fixture.call("reviewed-reject-race")
      id, input, = reviewed.call(store, accepted)
      first = start.call(:verification_submission_written) { |fault| Store.new(store.root, fault_injector: fault).record_verification(input) }
      event.call(first, "paused")
      second = start.call(nil) do |fault|
        self_test_error("cannot be rejected") do
          Store.new(store.root, fault_injector: fault).record_verification(nil, proposal_id: id, reject: true, rationale: "Concurrent rejection.")
        end
      end
      blocked.call(second)
      first.fetch(2).puts("continue")
      finish.call(first)
      finish.call(second)
      raise "concurrent rejection lost applied verification" unless read_document(accepted).first.fetch("applied_verification_proposal_ids") == [id]
      store.validate

      # Concurrent retries of one reviewed input apply its stable identity only once.
      %i[verification_submission_written verification_accepted_written].each do |point|
        store, accepted = fixture.call("reviewed-duplicate-#{point}")
        root_alias = "#{store.root}-alias"
        File.symlink(store.root, root_alias)
        id, input, = reviewed.call(store, accepted)
        first = start.call(point) { |fault| Store.new(store.root, fault_injector: fault).record_verification(input) }
        event.call(first, "paused")
        second = start.call(nil) { |fault| Store.new(root_alias, fault_injector: fault).record_verification(input) }
        blocked.call(second)
        first.fetch(2).puts("continue")
        finish.call(first)
        finish.call(second)
        unless read_document(accepted).first.fetch("applied_verification_proposal_ids") == [id]
          raise "concurrent reviewed retries duplicated application"
        end
        store.validate
      end

      # New and legacy writers use the same lock and preserve each other's evidence.
      %w[supported contradicted].each do |state|
        store, accepted = fixture.call("reviewed-parallel-#{state}")
        first_id, input, = reviewed.call(store, accepted, "supported", true)
        second_id = propose.call(store, accepted, state, state == "supported")
        second_decision = decide.call(second_id, "apply")
        first = start.call(:verification_submission_written) do |fault|
          Store.new(store.root, fault_injector: fault).record_verification(input)
        end
        event.call(first, "paused")
        second = start.call(nil) { |fault| Store.new(store.root, fault_injector: fault).process_verification(second_id, second_decision) }
        blocked.call(second)
        first.fetch(2).puts("continue")
        finish.call(first)
        finish.call(second)
        data, = read_document(accepted)
        unless data["verification"] == state && data.fetch("applied_verification_proposal_ids") == [first_id, second_id]
          raise "mixed verification writers lost a transition"
        end
        store.validate
      end

      # A queued submission must see a competing closure after acquiring the lock.
      store, accepted = fixture.call("reviewed-closure-freshness")
      id, input, sources = reviewed.call(store, accepted)
      target_bytes = File.binread(accepted)
      decision = decide.call(sources.first, "no-change")
      first = start.call(:state_file_prepared) { |fault| Store.new(store.root, fault_injector: fault).process(sources.first, decision) }
      event.call(first, "paused")
      second = start.call(nil) do |fault|
        self_test_error("different review") { Store.new(store.root, fault_injector: fault).record_verification(input) }
      end
      blocked.call(second)
      first.fetch(2).puts("continue")
      finish.call(first)
      finish.call(second)
      unless File.binread(accepted) == target_bytes && store.review_queue.none? { |row| row[1] == id }
        raise "competing closure partially applied the queued submission"
      end
      store.validate

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
      event.call(first, "paused")
      second = start.call(nil) do |fault|
        Store.new(store.root, fault_injector: fault).update_accepted(accepted_id, stale)
        raise "stale generic replacement erased verification"
      rescue Error => e
        raise unless e.message.include?("applied_verification_proposal_ids must be preserved")
      end
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
      crash_at.call(:verification_accepted_written) do |fault|
        Store.new(store.root, fault_injector: fault).process_verification(id, apply)
      end
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
      crash_at.call(:verification_archive_written) do |fault|
        Store.new(store.root, fault_injector: fault).process_verification(id, reject)
      end
      before = store.snapshot
      run = self_test_cli(store.root)
      run.call(1, "process-verification", "--id", id, "--decision", decide.call(id, "apply"), error: "existing verification archive differs")
      raise "archive conflict applied evidence" unless store.snapshot == before
      run.call(0, "process-verification", "--id", id, "--decision", reject)
      run.call(0, "validate")

      # Audit publication and candidate processing must still serialize through the shared lock.
      store, = fixture.call("audit-concurrency")
      data, body = parse_document(learning_audit_template)
      data["audit_kind"] = "skill-repository"
      audit_input = write.call("audit.md", data, body)
      id, = route_candidate.call(store)
      decision = decide.call(id, "reject")
      audit = start.call(:state_file_prepared) do |fault|
        Store.new(store.root, fault_injector: fault).record_audit(audit_input)
      end
      event.call(audit, "paused")
      candidate = start.call(nil) do |fault|
        Store.new(store.root, fault_injector: fault).process(id, decision)
      end
      blocked.call(candidate)
      audit.fetch(2).puts("continue")
      finish.call(audit)
      finish.call(candidate)
      unless store.send(:archived_candidates).length == 2 && store.audits.length == 1 && store.pending.empty?
        raise "concurrent audit and candidate processing lost a record"
      end
      store.validate

      # Atomic audit publication is the only commit point; there is no second cache write.
      store, = fixture.call("audit-publication")
      data, body = parse_document(learning_audit_template)
      data["audit_kind"] = "skill-repository"
      input = write.call("audit-publication.md", data, body)
      before = store.snapshot
      failed = Store.new(store.root, fault_injector: lambda do |point|
        raise Error, "before publication" if point == :state_file_prepared
      end)
      begin
        failed.record_audit(input)
        raise "audit publication failure was not injected"
      rescue Error => e
        raise unless e.message == "before publication"
      end
      raise "unpublished audit changed state" unless store.snapshot == before
      raise "unpublished audit reset cadence" unless store.artifact_audit_status(archive_threshold: 1).fetch(:due)
      crash_at.call(:audit_record_written) do |fault|
        Store.new(store.root, fault_injector: fault).record_audit(input)
      end
      audit_path = store.audits.fetch(0).fetch(3)
      audit_id = File.basename(audit_path, ".md")
      before = store.snapshot
      run = self_test_cli(store.root)
      run.call(0, "show", "--id", audit_id)
      run.call(0, "validate")
      run.call(2, "record-audit", error: "missing argument: --file")
      run.call(2, "record-audit", "--id", audit_id, error: "--id is not valid")
      raise "published audit failed to reset the reminder" if store.artifact_audit_status(archive_threshold: 1).fetch(:due)
      raise "audit inspection wrote state" unless store.snapshot == before
      fresh = store.record_audit(input)
      raise "fresh audit overwrote an earlier publication" unless fresh != audit_path && store.audits.length == 2
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

  def approximate_cadence_self_test
    Dir.mktmpdir("retro-approximate-cadence.") do |tmp|
      store = Store.new(File.join(tmp, "state"))
      store.init
      input = File.join(tmp, "input.md")
      decision_file = File.join(tmp, "decision.md")
      File.write(input, candidate_template)
      ids = %w[01 03 04].map.with_index do |day, index|
        id = File.basename(store.route(input), ".md")
        decision, body = parse_document(store.prepare_decision(id, index.zero? ? "defer" : "reject", rationale: "Cadence fixture."))
        decision.merge!(self_test_deferral_fields) if index.zero?
        decision["reviewed_at"] = "2026-01-#{day}T12:00:00Z"
        File.write(decision_file, render_document(decision, body))
        store.process(id, decision_file)
        id
      end
      cache = File.join(store.root, "audits/learning-process/artifact-cadence.yml")
      raise "candidate processing created a cadence cache" if File.exist?(cache)
      assert_count = lambda do |count, last_id = nil|
        before = store.snapshot
        status = store.artifact_audit_status(archive_threshold: 2)
        unless status.fetch(:archives_since) == count && status.fetch(:due) == (count >= 2) &&
            status[:last_audit_id] == last_id
          raise "wrong approximate cadence: #{status.inspect}"
        end
        raise "status query wrote state" unless store.snapshot == before
      end
      assert_count.call(3)
      # Retired bookkeeping is retained without influencing reads or later writes.
      File.write(cache, "schema_version: 1\nrecord_type: artifact-audit-cadence\ncandidate_archives_total: 999\n")
      original_cache = File.binread(cache)
      record_audit = lambda do |day, kind, legacy|
        data, body = parse_document(learning_audit_template)
        data["audit_kind"] = kind
        File.write(input, render_document(data, body))
        path = store.record_audit(input)
        assigned, body = read_document(path)
        if assigned.key?("candidate_archive_count") || assigned.key?("candidate_archives_total")
          raise "new audit persisted obsolete candidate counts"
        end
        assigned["completed_at"] = "2026-01-#{day}T12:00:00Z"
        if legacy
          assigned["candidate_archive_count"] = 99
          assigned["candidate_archives_total"] = 999
        end
        File.write(path, render_document(assigned, body))
        assigned.fetch("audit_id")
      end
      first = record_audit.call("02", "skill-repository", true)
      assert_count.call(2, first)
      decision, body = parse_document(store.prepare_decision(ids.first, "reject", rationale: "Resolved fixture."))
      decision["reviewed_at"] = "2026-01-05T12:00:00Z"
      File.write(decision_file, render_document(decision, body))
      store.reconsider(ids.first, decision_file)
      assert_count.call(2, first)
      record_audit.call("06", "learning-process", false)
      assert_count.call(2, first)
      second = record_audit.call("03", "skill-repository", false)
      assert_count.call(1, second)
      File.unlink(File.join(store.root, "retrospectives/archive", "#{ids.last}.md"))
      assert_count.call(0, second)
      store.validate
      raise "retired cadence file was changed" unless File.binread(cache) == original_cache
      self_test_error("threshold must be a positive integer") do
        store.artifact_audit_status(archive_threshold: 0)
      end
    end
  end

  def legacy_draft_self_test
    require "open3"
    Dir.mktmpdir("retro-legacy-drafts.") do |tmp|
      store = Store.new(File.join(tmp, "state"))
      store.init
      data, body = parse_document(self_test_legacy_draft)
      id = data.fetch("draft_id")
      path = File.join(store.root, "drafts", "#{id}.md")
      data.delete("owner")
      data["review_trigger_contract_version"] = 1
      data["review_trigger_observer"] = "learning-process-review"
      audit_input = File.join(tmp, "audit.md")
      audit, audit_body = parse_document(learning_audit_template)
      audit["unresolved_action_ids"] = [id]
      File.write(audit_input, render_document(audit, audit_body))
      audit_path = nil
      DRAFT_STATUSES.each do |status|
        data["status"] = status
        File.write(path, render_document(data, body))
        before = store.snapshot
        store.validate
        shown = store.show([id]).fetch("records").first
        unless shown.fetch("frontmatter") == data && shown.fetch("body") == body
          raise "legacy draft contents changed on read"
        end
        queued = store.review_queue.any? { |type, row_id, _trigger, _path| type == "draft" && row_id == id }
        raise "legacy draft status lost queue behavior" unless queued == %w[open revised].include?(status)
        raise "legacy draft reads changed state" unless store.snapshot == before
        if queued
          audit_path ||= store.record_audit(audit_input)
        else
          self_test_error("unresolved action is missing or not open") do
            store.record_audit(audit_input)
          end
        end
      end
      store.validate
      before = store.snapshot
      [[1, %w[template draft], "unknown template type: draft"],
        [2, ["record-draft", "--file", path], "unknown command: record-draft"]].each do |expected, arguments, message|
        out, err, status = Open3.capture3({STATE_ENV => store.root}, RbConfig.ruby, File.expand_path(__FILE__), *arguments)
        unless status.exitstatus == expected && out.empty? && err.include?(message)
          raise "retired draft command was accepted: #{arguments.inspect}"
        end
      end
      raise "retired draft commands changed state" unless store.snapshot == before
      File.unlink(path)
      self_test_error("unresolved action does not exist") do
        store.validate
      end
    end
  end

  def self_test
    reviewed_verification_self_test
    queue_archive_race_self_test
    observation_self_test
    approximate_cadence_self_test
    legacy_draft_self_test
    transition_recovery_self_test
    state_confinement_self_test
    inspection_self_test
    metadata_comparison_self_test
    verification_context_self_test
    verification_preparation_self_test
    accepted_preparation_self_test
    preparation_self_test
    Dir.mktmpdir("retro-state-self-test.") do |tmp|
      root = File.join(tmp, "state")
      input = File.join(tmp, "candidate.md")
      decision = File.join(tmp, "decision.md")
      accepted = File.join(tmp, "accepted.md")
      ledger = File.join(tmp, "ledger.md")
      audit = File.join(tmp, "audit.md")
      papercut = File.join(tmp, "papercut.md")
      verification_proposal = File.join(tmp, "verification.md")
      verification_decision = File.join(tmp, "verification-decision.md")
      without_deferral_fields = lambda do |text|
        data, body = parse_document(text)
        DEFERRAL_FIELDS.each { |field| data.delete(field) }
        render_document(data, body)
      end
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
      self_test_error("evidence_lineage must be a non-empty string") do
        validate_candidate(
          missing_lineage,
          missing_lineage_body,
          label: "new candidate without evidence lineage",
          routed: false
        )
      end
      PAPERCUT_CLASSIFICATIONS.each do |field, values|
        line = papercut_template.lines.find { |candidate| candidate.start_with?("#{field}:") }
        unless line && values.all? { |value| line.include?(value) }
          raise "papercut template #{field} vocabulary is incomplete"
        end
      end
      File.write(input, candidate_template.gsub("Short candidate title", "Atomic routing"))

      store = Store.new(root)
      store.init

      base_decision, decision_body = parse_document(decision_template)
      base_decision.merge!(self_test_deferral_fields)
      base_decision["candidate_id"] = "RC-20260715T120000Z-000000"
      base_decision["reviewed_at"] = "2026-07-15T11:59:00Z"
      validate_decision(base_decision, decision_body, label: "simple deferral")
      DEFERRAL_FIELDS.each do |field|
        incomplete = base_decision.reject { |key, _| key == field }
        self_test_error("#{field} must be a non-empty string") do
          validate_decision(incomplete, decision_body, label: "incomplete deferral")
        end
      end

      legacy_decision = base_decision.except("owner", "unresolved_decision")
      validate_triage(legacy_decision, legacy_decision.fetch("candidate_id"), "legacy deferral")
      legacy_decision.merge!(
        "unresolved_decision" => base_decision.fetch("unresolved_decision"),
        "review_trigger_contract_version" => 1,
        "review_trigger_type" => "explicit-input",
        "review_trigger_observer" => "skill-retro-triage",
        "review_trigger_route" => "review-queue",
        "review_trigger_probe" => "Inspect the current request.",
        "review_trigger_input" => "An independent observation."
      )
      legacy_before = render_document(legacy_decision, "")
      validate_triage(legacy_decision, legacy_decision.fetch("candidate_id"), "typed legacy deferral")
      raise "legacy trigger metadata changed" unless render_document(legacy_decision, "") == legacy_before

      invalid, body = parse_document(ledger_template)
      invalid.delete("review_trigger")
      File.write(ledger, render_document(invalid, body))
      self_test_error("review_trigger must be a non-empty string") do
        store.record_ledger(ledger)
      end

      path = store.route(input)
      id = File.basename(path, ".md")
      raise "pending candidate missing" unless store.pending.map(&:first) == [id]
      store.validate

      File.write(papercut, papercut_template)
      papercut_data, papercut_body = read_document(papercut)
      papercut_path = self_test_papercut(store, papercut_data, papercut_body, label: papercut)
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
      duplicate_path = self_test_papercut(store, duplicate_data, duplicate_body, label: papercut)
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
      recovery_source = self_test_papercut(papercut_recovery_store,
        recovery_data,
        recovery_body,
        label: papercut)
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
      conflicting_source = self_test_papercut(papercut_recovery_store,
        conflicting_data,
        conflicting_body,
        label: papercut)
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
      self_test_error("existing papercut archive differs") do
        papercut_recovery_store.close_papercut(
          conflicting_id,
          outcome: "no-action",
          rationale: "Original closure rationale."
        )
      end
      unless File.binread(conflicting_archive) == conflicting_archive_bytes && File.file?(conflicting_source)
        raise "conflicting papercut archive was overwritten or its inbox record was removed"
      end

      missing_reference_data, missing_reference_body = read_document(papercut)
      missing_reference_path = self_test_papercut(store,
        missing_reference_data,
        missing_reference_body,
        label: papercut)
      missing_reference_id = File.basename(missing_reference_path, ".md")
      self_test_error("related papercut does not exist") do
        store.close_papercut(
          missing_reference_id,
          outcome: "duplicate",
          rationale: "Invalid missing-reference test.",
          related_papercut_id: "PC-20260715T120000Z-000000"
        )
      end
      store.close_papercut(
        missing_reference_id,
        outcome: "no-action",
        rationale: "Closed after the missing-reference test."
      )

      malformed_papercut = File.join(tmp, "malformed-papercut.md")
      File.write(malformed_papercut, papercut_template.sub("impact: retry", "impact: surprise"))
      malformed_data, malformed_body = read_document(malformed_papercut)
      self_test_error("impact must be one of") do
        self_test_papercut(store, malformed_data, malformed_body, label: malformed_papercut)
      end

      # Historical labels stay readable without reclassifying or rewriting intake.
      historical, historical_body = read_document(closed_papercut)
      historical.delete("closure")
      PAPERCUT_CLASSIFICATIONS.each_key { |field| historical[field] = "historical-#{field}" }
      intake = without_keys(historical, "intake_digest")
      historical["intake_digest"] = Digest::SHA256.hexdigest(render_document(intake, historical_body))
      historical_root = File.join(tmp, "historical-papercut-state")
      historical_store = Store.new(historical_root)
      historical_store.init
      historical_path = File.join(historical_root, "papercuts", "inbox", "#{papercut_id}.md")
      original_intake = render_document(historical, historical_body)
      File.write(historical_path, original_intake)
      historical_store.validate
      historical_store.papercuts
      historical_store.review_queue
      raise "historical papercut was rewritten" unless File.read(historical_path) == original_intake
      PAPERCUT_CLASSIFICATIONS.each_key do |field|
        tampered = historical.merge(field => "other-label")
        self_test_error("papercut intake fields changed after recording") do
          validate_papercut(tampered, historical_body, label: "altered classification", routed: true)
        end
        malformed = historical.merge(field => [])
        self_test_error("#{field} must be a non-empty string") do
          validate_papercut(malformed, historical_body, label: "malformed classification", routed: true)
        end
      end
      historical_archive = historical_store.close_papercut(
        papercut_id, outcome: "no-action", rationale: "No reusable action is needed."
      )
      historical_closed, closed_body = read_document(historical_archive)
      unless without_keys(historical_closed, "closure") == historical && closed_body == historical_body
        raise "closing historical papercut changed its intake"
      end
      historical_store.validate

      # Keep validating existing repair receipts, even when their enclosing digest matches.
      %w[matched classification-only current-evidence-authorized].each do |mode|
        repaired, repaired_body = read_document(closed_papercut)
        prior = without_keys(repaired, "intake_digest", "closure")
        replaced = prior.merge("kind" => "historical-kind")
        replaced_digest = Digest::SHA256.hexdigest(render_document(replaced, repaired_body))
        receipt = {
          "repaired_at" => "2026-08-28T12:00:00Z",
          "rationale" => "Historical compatibility repair.",
          "redaction_review" => "Sanitized fixture.",
          "prior_intake_digest" => case mode
                                   when "matched" then replaced_digest
                                   when "classification-only" then repaired.fetch("intake_digest")
                                   else "0" * 64
                                   end,
          "replaced_intake_digest" => replaced_digest,
          "digest_recovery" => mode,
          "changes" => {"kind" => {"from" => "historical-kind", "to" => repaired.fetch("kind")}}
        }
        if mode == "classification-only"
          receipt["authenticated_classifications"] = repaired.slice(*PAPERCUT_CLASSIFICATIONS.keys)
        end
        repaired["schema_repairs"] = [receipt]
        repaired["intake_digest"] = Digest::SHA256.hexdigest(
          render_document(without_keys(repaired, "intake_digest", "closure"), repaired_body)
        )
        validate_papercut(repaired, repaired_body, label: "historical #{mode} repair", routed: true, archived: true)
        receipt["replaced_intake_digest"] = "f" * 64
        repaired["intake_digest"] = Digest::SHA256.hexdigest(
          render_document(without_keys(repaired, "intake_digest", "closure"), repaired_body)
        )
        self_test_error("replaced_intake_digest does not match repair history") do
          validate_papercut(repaired, repaired_body, label: "tampered repair history", routed: true, archived: true)
        end
      end

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

      decision_text = without_deferral_fields.call(
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

      recovery_root = File.join(tmp, "candidate-recovery")
      recovery_store = Store.new(recovery_root)
      recovery_store.init
      recovery_input = File.join(tmp, "candidate-recovery.md")
      recovery_decision = File.join(tmp, "candidate-recovery-decision.md")
      File.write(
        recovery_input,
        candidate_template.gsub("Short candidate title", "Recoverable candidate archival")
      )
      recovery_source = recovery_store.route(recovery_input)
      recovery_id = File.basename(recovery_source, ".md")
      recovery_decision_text = without_deferral_fields.call(
        decision_template
        .sub("RC-YYYYMMDDTHHMMSSZ-abcdef", recovery_id)
        .sub("YYYY-MM-DDTHH:MM:SSZ", "2026-07-15T12:00:00Z")
        .sub("verdict: defer", "verdict: reject")
      )
      File.write(recovery_decision, recovery_decision_text)
      interrupted_store = Store.new(
        recovery_root,
        fault_injector: lambda do |point|
          raise Error, "simulated candidate archival interruption" if point == :candidate_archive_written
        end
      )
      begin
        interrupted_store.process(recovery_id, recovery_decision)
        raise "candidate interruption was not injected"
      rescue Error => e
        raise unless e.message == "simulated candidate archival interruption"
      end

      recovery_archive = File.join(
        recovery_root,
        "retrospectives",
        "archive",
        "#{recovery_id}.md"
      )
      unless File.file?(recovery_source) && File.file?(recovery_archive)
        raise "candidate interruption did not retain both recovery inputs"
      end
      archived_before_retry = File.binread(recovery_archive)

      recovery_store.process(recovery_id, recovery_decision)
      raise "recovered candidate remained in inbox" if File.exist?(recovery_source)
      unless File.binread(recovery_archive) == archived_before_retry
        raise "candidate retry changed the existing archive"
      end
      unless Dir.glob(File.join(recovery_root, "retrospectives", "archive", "*.md")).length == 1
        raise "candidate retry did not retain exactly one archive"
      end
      recovery_store.validate

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
      conflict_decision_text = without_deferral_fields.call(
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
      self_test_error("existing candidate archive differs") do
        conflict_store.process(conflict_id, conflict_decision)
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
      {"route" => File.read(input), "record-observation" => observation_template}.each do |command, text|
        cli_input = File.join(tmp, "#{command}-cli.md")
        File.write(cli_input, text)
        expected_data, expected_body = parse_document(text)
        [cli_input, "-"].each do |path|
          before_cli = cli_snapshot.call
          out, err, result = run_cli.call(command, path, text, cli_root)
          routed_path = out.strip
          unless result.success? && err.empty? && File.file?(routed_path) &&
              File.dirname(routed_path) == File.join(cli_root, "retrospectives/inbox")
            raise "#{command} #{path}: CLI routing failed: #{err}"
          end
          routed_data, routed_body = read_document(routed_path)
          unless without_keys(routed_data, "candidate_id", "created_at", "intake_digest") == expected_data &&
              routed_body.rstrip == expected_body.rstrip
            raise "#{command}: CLI routing changed submission content"
          end
          File.unlink(routed_path)
          raise "#{command}: CLI routing changed existing state" unless cli_snapshot.call == before_cli

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
        before_failure = cli_snapshot.call
        failing_store = Store.new(cli_root)
        failing_store.define_singleton_method(:exclusive_write) { |_destination, _content| raise Errno::ENOSPC }
        fallback_data, fallback_body = parse_document(text)
        begin
          failing_store.route(cli_input, document: [fallback_data, fallback_body])
          raise "#{command}: write failure was not injected"
        rescue Errno::ENOSPC
          unless [fallback_data, fallback_body] == [expected_data, expected_body] && cli_snapshot.call == before_failure
            raise "#{command}: late write failure changed fallback input or existing state"
          end
        end
      end
      Store.new(cli_root).validate
      unless store.verification_opportunities(destination: "public source").first.fetch(4).empty?
        raise "fresh verification opportunity reported pending support"
      end
      File.write(verification_proposal, supported_proposal_text)
      supported_proposal_path = self_test_legacy_verification(store, verification_proposal)
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
      pending_contradiction_text = supported_proposal_text
        .sub("proposed_verification: supported", "proposed_verification: contradicted")
        .sub("# what_is_false:", "what_is_false:")
      File.write(verification_proposal, pending_contradiction_text)
      pending_contradiction_path = self_test_legacy_verification(store, verification_proposal)
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
      supported_proposal_path = self_test_legacy_verification(store, verification_proposal)
      supported_proposal_id = File.basename(supported_proposal_path, ".md")

      supplemental_data, supplemental_body = parse_document(supported_proposal_text)
      supplemental_data["supplemental_reason"] = "Exercises a distinct failure boundary absent from pending support."
      supplemental_data["observation"] = "The previously untested failure boundary holds."
      supplemental_data["decisive_evidence"] = ["A distinct failure-boundary check passed."]
      supplemental_text = render_document(supplemental_data, supplemental_body)
      File.write(verification_proposal, supplemental_text)
      supplemental_path = self_test_legacy_verification(store, verification_proposal)
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
      self_test_error("supplemental_reason is only for supported proposals") do
        invalid_supplement = supplemental_data.merge(
          "proposed_verification" => "contradicted", "what_is_false" => "A boundary fails."
        )
        validate_verification_proposal(
          invalid_supplement, supplemental_body, label: "contradiction with supplement", routed: false
        )
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
      supported_accepted, = read_document(accepted_path)
      raise "verification proposal was not applied" unless supported_accepted["verification"] == "supported"
      unless supported_accepted["verification_basis"] == "deterministic-test"
        raise "verification proposal basis was not applied"
      end
      unless supported_accepted.fetch("applied_verification_proposal_ids") == [supported_proposal_id]
        raise "accepted record did not retain applied verification proposal identity"
      end
      if store.verification_opportunities(destination: "public source").map(&:first).include?(accepted_id)
        raise "supported accepted record remained in the unverified opportunity query"
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
      contradicted_proposal_path = self_test_legacy_verification(store, verification_proposal)
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
      self_test_error("originating_candidate_ids must not change") do
        store.update_accepted(accepted_id, accepted)
      end
      self_test_error("accepted record not found") do
        store.update_accepted("SCR-20260715-000000", accepted)
      end
      store.validate

      draft_id = "SD-20260715-abcdef"
      draft_path = File.join(root, "drafts", "#{draft_id}.md")
      File.write(draft_path, self_test_legacy_draft)
      File.write(ledger, ledger_template)
      ledger_path = store.record_ledger(ledger)
      raise "ledger record missing" unless File.file?(ledger_path)
      ledger_id = File.basename(ledger_path, ".md")
      [draft_path, ledger_path].each do |legacy_path|
        legacy_data, legacy_body = read_document(legacy_path)
        legacy_data.delete("owner") if legacy_path == draft_path
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
      supported_contradiction_path = self_test_legacy_verification(store, verification_proposal)
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
      contradicted_data = without_keys(assigned_contradiction, "accepted_id", "accepted_at")
      unless store.review_queue.map(&:first).include?("contradiction")
        raise "contradicted accepted record missing from review queue"
      end
      self_test_error("contradiction decisive_evidence must be preserved") do
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
      self_test_error("unresolved contradicted record") do
        store.close_ledger(ledger_id, rationale: "Invalid early closure.")
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
      self_test_error("unresolved contradiction requires an open residual ledger") do
        store.update_accepted(accepted_id, accepted)
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
      correction_decision = without_deferral_fields.call(
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
      applied_contradiction_path = self_test_legacy_verification(store, verification_proposal)
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
      self_test_error("candidate supersedes missing accepted record") do
        store.route(input)
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
      %w[owner unresolved_decision].each do |field|
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
      merged_decision = without_deferral_fields.call(
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
      nested_merged_decision = without_deferral_fields.call(
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
      self_test_error("replacement decision must be newer") do
        store.reconsider(deferred_id, decision)
      end

      accepted_decision = without_deferral_fields.call(
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
      self_test_error("candidate is not currently deferred") do
        store.reconsider(deferred_id, decision)
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
      self_test_error("ledger is already closed") do
        store.close_ledger(ledger_id, rationale: "Invalid repeated closure.")
      end
      self_test_error("ledger not found") do
        store.close_ledger("LE-20260715-000000", rationale: "Invalid missing-ledger test.")
      end
      store.validate

      forbidden = File.join(tmp, "forbidden.md")
      File.write(forbidden, candidate_template.sub("Optional concise context.", "Raw /home/person/private path."))
      self_test_error("unredacted user-home path") do
        store.route(forbidden)
      end

      forbidden_papercut = File.join(tmp, "forbidden-papercut.md")
      File.write(
        forbidden_papercut,
        papercut_template.sub("Optional bounded evidence or context.", "Raw /home/person/private path.")
      )
      forbidden_data, forbidden_body = read_document(forbidden_papercut)
      self_test_error("unredacted user-home path") do
        self_test_papercut(store, forbidden_data, forbidden_body, label: forbidden_papercut)
      end

      legacy_root = File.join(tmp, "legacy-state")
      legacy_store = Store.new(legacy_root)
      legacy_store.init
      FileUtils.rm_r(File.join(legacy_root, "verifications"))
      legacy_store.validate
      raise "legacy state reported verification proposals" unless legacy_store.pending_verifications.empty?
      FileUtils.mkdir_p(File.join(legacy_root, "verifications", "inbox"))
      self_test_error("verification state directory is missing") do
        legacy_store.validate
      end

      git_root = File.join(tmp, "repo")
      FileUtils.mkdir_p(File.join(git_root, ".git"))
      File.write(File.join(git_root, ".git", "HEAD"), "ref: refs/heads/main\n")
      self_test_error("must not be inside a Git worktree") do
        Store.new(File.join(git_root, "state")).init
      end

      linked_target = File.join(git_root, "linked-state")
      linked_root = File.join(tmp, "state-link")
      FileUtils.mkdir_p(linked_target)
      File.symlink(linked_target, linked_root)
      self_test_error("must not be inside a Git worktree") do
        Store.new(linked_root).init
      end

      self_test_error("state root is too broad") do
        Store.new(File::SEPARATOR)
      end
    end
    true
  end
end

def usage(command = nil)
  details = case command
  when "record-observation"
    <<~TEXT
      Usage: retro-state.rb record-observation --file PATH [--root DIR]

      Capture one observation using template observation; --file - reads standard input.
      Requires title, source_scope, observation, decisive_evidence and redaction_review.
      Preserve useful context in the body; no remedy, owner, confidence or skill classification
      is required. The helper creates an immutable, digested RC-* record in retrospectives/inbox.
      Existing identity and directory names remain for compatibility, without a promotion step.
      Review later uses prepare-decision and process; capture never accepts or verifies an outcome.
      Unset or blocked state returns validated paste-ready input with status 2.
    TEXT
  when "route-verification"
    "New legacy proposal creation is retired; use prepare-verification and record-verification.\n"
  when "record-verification"
    <<~TEXT
      Usage: retro-state.rb record-verification --file PATH | --id VP-ID [--root DIR]
             retro-state.rb record-verification --id VP-ID --reject --rationale TEXT
             retro-state.rb record-verification --id VP-ID --acknowledge-closure RC-ID
                            [--acknowledge-closure RC-ID ...] --rationale TEXT

      Apply a completed prepare-verification submission; --file - reads stdin.
      Requires processing authority, not capture authority. The review mapping binds one
      stable VP ID, apply verdict, rationale, UTC reviewed_at, and close_observation_ids.
      Source links preserve provenance; closure IDs explicitly select source RC observations
      whose entire review is complete. Empty closure IDs leave every source open. Legacy
      candidates and papercuts retain their existing closure commands.
      Rechecks target eligibility and original evidence under the shared writer lock. Saves
      reviewed intent in the existing inbox, applies and archives verification, then closes
      only selected observations. Original evidence and prior verification remain intact.
      Retry the unchanged input after any interruption, including a lost response. Once the
      inbox was published, --id resumes its stored review without the original input file.
      Keep the prepared ID; generating another submission is not a retry. Conflicting input
      or observation reviews fail. The queue retains interrupted submissions until closure
      completes. A completed retry is a no-op. No separate apply/reject file is required.

      Resolve interrupted work explicitly, with processing authority and a rationale.
      --reject archives unapplied intent without applying verification or closing sources.
      It cannot reject applied verification. --acknowledge-closure is only for applied
      verification and selected observations already completed by another review; open or
      deferred observations fail. It binds that exact record and preserves the other decision,
      then finishes remaining planned closures. Original intake, review and applied evidence
      remain intact. Resolutions require --id, cannot use --file, and are mutually exclusive.
      A normal retry resumes the stored resolution; changing its rationale is refused.
    TEXT

  when "prepare-decision"
    <<~TEXT
      Usage: retro-state.rb prepare-decision --id ID --verdict VERDICT
                                            [--rationale TEXT] [--root DIR]

      Print an editable Markdown/YAML decision for an observation or legacy candidate (RC-*) in inbox or
      deferred archive, or an existing legacy verification proposal (VP-*) in inbox.
      Review verdicts: #{RetroState::VERDICTS.join(", ")}.
      Verification verdicts: #{RetroState::VERIFICATION_PROPOSAL_VERDICTS.join(", ")}.
      Sets the ID and current UTC reviewed_at; reconsiderations must be newer.
      Optionally supply an already-reviewed, nonblank rationale; otherwise fill the blank.
      Deferrals keep safe structural defaults but leave the unresolved decision and
      substantive trigger/action fields blank. Complete them even when supplying a
      rationale; the draft cannot be processed until they are filled.
      Accepted or split observations require reviewed evidence_lineage and evidence_lineage_note.
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
      Prepares a stable VP identity and review time, a blank rationale,
      and an empty close_observation_ids list. Complete this single document and submit with
      record-verification --file PATH. Add source_observation_ids when using captured evidence;
      select only fully reviewed source observations for closure. Preserve the ID for retries.
      --reviewed is accepted for compatibility; preparation is always reviewed.
      Preparation writes no state, supplies no evidence claim and grants no processing authority.
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
        process:RC-ID               Candidate inbox/archive plus shared writer lock.
        close-papercut:PC-ID         Papercut inbox/archive.
        reconsider:RC-ID            Candidate archive plus writer lock.
        record-accepted:SCR-ID       New accepted record only; no writer lock.
        update-accepted:SCR-ID       Accepted record plus writer lock.
        process-verification:VP-ID   Proposal inbox/archive plus writer lock; target for apply.
      The shared writer lock is audits/learning-process/artifact-cadence.lock.
      No action allowance permits changes to legacy cadence files.
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
      --compact includes id, destination, expected_behavior, verification, verification_basis,
      and these three claim lists per record, with the same pagination and filtering.
      It omits verification_opportunity and claim observations. Use noncompact discovery
      or --id for the exact opportunity and evidence scope.
      The overall verification field does not certify every claim. Expand selected IDs
      before judging evidence.

      IDs may be accepted records (SCR-*) or inbox/archived verification proposals (VP-*).
      Proposal IDs resolve to their target; mixed IDs deduplicate targets in selected order.
      Print JSON {root, mode, records}. Each result contains accepted and verification_proposals
      with the original {id, path, frontmatter, body} records, as returned by show.
      Each proposal appears once; selected_verification_proposal_ids,
      applied_verification_proposal_ids, and pending_verification_proposal_ids preserve
      roles and ordering. Explicitly selected rejected proposals remain included.
      supported_claims and contradicted_claims contain the same summaries as noncompact
      discovery, including each observation. unverified_claims retains the accepted list
      or null when unassessed. Read proposal evidence, opportunity matches, and triage
      reasons before interpreting these summaries as support for a broader claim.
      Source text and metadata remain unchanged, including repeated evidence and body-only
      limits. No JSON pointers, shared text pools, or prose replacement maps are generated.
      Historical verification_context metadata is preserved as opaque source data; it no
      longer controls rendering or validation and cannot block retrieval or preparation.
      Historical dispositions remain inspectable; legacy support without proposal
      provenance has no applied IDs. Reads do not migrate or rewrite any stored evidence.
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
    return details + "\n--root defaults to #{RetroState::STATE_ENV}.\n"
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
                                        Prepare one reviewed verification submission
      prepare-accepted --id RC-ID ... --commit SHA ...
                                        Prepare a new accepted-record draft from archived candidates
      prepare-accepted-update --id ID  Print an editable accepted-record replacement
      init                              Initialize the configured state root
      template TYPE                    Print an observation, decision,
                                        verification, verification-decision, accepted,
                                        ledger, or audit template
      record-observation --file PATH  Capture an observation from PATH, or - for standard input
      papercuts [--archive]            List open papercuts, or archived papercuts explicitly
      close-papercut --id ID --outcome OUTCOME --rationale TEXT
                                        Archive a papercut with a reviewed outcome
      route --file PATH                Compatibility route for observations and legacy candidate input
      pending                           List observations and legacy candidates
      process --id ID --decision PATH  Attach a reviewed decision and archive the original intake
      record-verification --file PATH | --id VP-ID
                                        Apply or resume one reviewed submission and optional closures
      pending-verifications            List validated verification proposals
      process-verification --id ID --decision PATH
                                        Apply or reject an existing legacy proposal
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
      record-ledger --file PATH         Store a maintenance ledger entry
      close-ledger --id ID --rationale TEXT
                                        Close a maintenance ledger entry
      record-audit --file PATH          Store a fresh completed sanitized system audit
      audits                            List completed system audits
      artifact-audit-status [--archive-threshold N]
                                        Report approximate cadence from retained first-review dates
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
    "prepare-verification" => %w[--root --id --verification --reviewed],
    "prepare-accepted" => %w[--root --id --commit],
    "prepare-accepted-update" => %w[--root --id --commit --destination],
    "init" => %w[--root],
    "template" => [],
    "record-observation" => %w[--root --file],
    "papercuts" => %w[--root --archive],
    "close-papercut" => %w[
      --root --id --outcome --rationale --related-papercut-id
      --related-candidate-id
    ],
    "route" => %w[--root --file],
    "pending" => %w[--root],
    "process" => %w[--root --id --decision],
    "route-verification" => %w[--root --file],
    "record-verification" => %w[--root --file --id --reject --acknowledge-closure --rationale],
    "pending-verifications" => %w[--root],
    "process-verification" => %w[--root --id --decision],
    "reconsider" => %w[--root --id --decision],
    "record-accepted" => %w[--root --file],
    "update-accepted" => %w[--root --id --file],
    "accepted-records" => %w[--root --destination --text --active-supported],
    "verification-opportunities" => %w[--root --destination],
    "verification-context" => %w[--root --destination --id --text --compact --limit --offset],
    "record-ledger" => %w[--root --file],
    "close-ledger" => %w[--root --id --rationale],
    "record-audit" => %w[--root --file],
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
  init template record-observation papercuts
  close-papercut route pending process
  route-verification record-verification pending-verifications process-verification
  reconsider record-accepted update-accepted record-ledger close-ledger
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
reject_verification = false
acknowledge_closures = []
outcome = nil
rationale = nil
verdict = nil
proposed_verification = nil
reviewed = false
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
  opts.on("--reviewed") { reviewed = true }
  opts.on("--reject") { reject_verification = true }
  opts.on("--acknowledge-closure RC-ID") { |value| acknowledge_closures << value }
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
      "--reviewed" => reviewed,
      "--reject" => reject_verification,
      "--acknowledge-closure" => acknowledge_closures.any?,
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
  if command == "record-verification" && ((!input_path.nil? == !record_id.nil?) || record_ids.length > 1)
    raise OptionParser::InvalidArgument, "choose --file PATH or one --id VP-ID"
  end
  if command == "record-verification" && (reject_verification || acknowledge_closures.any? || rationale)
    unless record_id && !input_path && !rationale.nil? && reject_verification != acknowledge_closures.any?
      raise OptionParser::InvalidArgument, "resolution requires --id and --rationale with either --reject or --acknowledge-closure"
    end
  end
  if command == "record-audit" && !input_path
    raise OptionParser::MissingArgument, "--file PATH"
  end

  case command
  when "template"
    template = case type
    when "observation" then RetroState.observation_template
    when "decision" then RetroState.decision_template
    when "verification" then RetroState.verification_proposal_template
    when "verification-decision" then RetroState.verification_decision_template
    when "accepted" then RetroState.accepted_template
    when "ledger" then RetroState.ledger_template
    when "audit" then RetroState.learning_audit_template
    else raise RetroState::Error, "unknown template type: #{type}"
    end
    print template
  when "route-verification"
    raise RetroState::Error, "new legacy proposal creation is retired; use prepare-verification and record-verification with processing authority"
  when "self-test"
    RetroState.self_test
    puts "Retro state self-test passed."
  else
    root = root_override || ENV[RetroState::STATE_ENV]
    if %w[route record-observation].include?(command) && RetroState.blank?(root)
      command_label = command
      raise RetroState::Error, "#{command_label} requires --file PATH" unless input_path

      data, body = RetroState.read_document(input_path)
      RetroState.validate_candidate(data, body, label: input_path, routed: false)
      if command == "record-observation" && data["record_type"] != "observation"
        raise RetroState::Error, "record-observation requires an observation; use template observation"
      end
      warn "#{RetroState::STATE_ENV} is not set; no state was written. Paste-ready observation follows."
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
    when "route", "record-observation"
      raise RetroState::Error, "#{command} requires --file PATH" unless input_path

      data, body = RetroState.read_document(input_path)
      RetroState.validate_candidate(data, body, label: input_path, routed: false)
      if command == "record-observation" && data["record_type"] != "observation"
        raise RetroState::Error, "record-observation requires an observation; use template observation"
      end
      begin
        puts store.route(input_path, document: [data, body])
      rescue RetroState::Error, Errno::EACCES, Errno::EROFS, Errno::ENOSPC => e
        warn "Could not route to external state (#{e.message}); no state was written. Paste-ready observation follows."
        print RetroState.render_document(data, body)
        exit 2
      end
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
    when "record-verification"
      puts store.record_verification(input_path, proposal_id: record_id, reject: reject_verification,
        acknowledge_closures: acknowledge_closures, rationale: rationale)
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
    when "record-ledger"
      raise RetroState::Error, "record-ledger requires --file PATH" unless input_path

      puts store.record_ledger(input_path)
    when "close-ledger"
      raise RetroState::Error, "close-ledger requires --id ID" unless record_id
      raise RetroState::Error, "close-ledger requires --rationale TEXT" unless rationale

      puts store.close_ledger(record_id, rationale: rationale)
    when "record-audit"
      puts store.record_audit(input_path)
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
rescue RetroState::Error, Errno::ENOENT, Errno::EACCES, Errno::EISDIR, Errno::ENOTDIR, Errno::ELOOP, Errno::EROFS, Errno::ENOSPC => e
  warn "retro-state.rb: #{e.message}"
  exit 1
end
