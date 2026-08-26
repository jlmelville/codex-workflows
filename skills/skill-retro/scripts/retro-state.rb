#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "fileutils"
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
  VERIFICATION_PROPOSAL_STATES = %w[supported contradicted].freeze
  VERIFICATION_PROPOSAL_VERDICTS = %w[apply reject].freeze
  VERIFICATION_CLAIMS = %w[
    executable-correctness guidance-conformance intended-outcome comparative-improvement
  ].freeze
  TERMINAL_CONTRADICTION_DISPOSITIONS = %w[superseded reverted].freeze
  AUDIT_KINDS = %w[learning-process skill-repository].freeze
  ARTIFACT_AUDIT_ARCHIVE_THRESHOLD = 10
  ARTIFACT_CADENCE_RECORD_TYPE = "artifact-audit-cadence"
  CONFIDENCES = %w[high medium low].freeze
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
    validate_enum(data, "kind", PAPERCUT_KINDS, label)
    validate_enum(data, "impact", PAPERCUT_IMPACTS, label)
    validate_enum(data, "resolution", PAPERCUT_RESOLUTIONS, label)
    validate_enum(data, "owner_hint", PAPERCUT_OWNERS, label)
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
    elsif data.key?("papercut_id") || data.key?("created_at") || data.key?("intake_digest")
      raise Error, "#{label}: unrecorded papercut must not assign identity fields"
    end

    closure = data["closure"]
    if archived
      validate_papercut_closure(closure, data["papercut_id"], label)
    elsif closure
      raise Error, "#{label}: open papercut must not contain closure data"
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
  rescue Date::Error
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
    unless data["implementation_commits"].all? { |item| item.match?(/\A[0-9a-f]{7,40}\z/) }
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
    residual_id = contradiction["residual_ledger_id"]
    return unless residual_id
    return if residual_id.match?(/\ALE-\d{8}-[a-f0-9]{6}\z/)

    raise Error, "#{label}: invalid contradiction residual_ledger_id"
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
      observation: "What happened and why it matters."
      decisive_evidence:
        - "Bounded, sanitized failure signal or observed behavior."
      reusable_lesson: "What a fresh agent should reuse."
      existing_coverage: "Existing skill/reference coverage, or none."
      missing_delta: "The exact gap not already covered."
      proposed_destination: "Smallest natural skill, reference, script, prompt, or no change."
      smallest_change: "The minimum useful content or mechanism change."
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
      ---

      # Verification decision

      Optional concise adjudication notes.
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
      review_trigger_contract_version: 1
      unresolved_decision: "Decision that current evidence cannot justify."
      review_trigger_type: explicit-input # #{REVIEW_TRIGGER_TYPES.join(", ")}
      review_trigger_observer: skill-retro-triage # #{REVIEW_TRIGGER_OBSERVERS.join(", ")}
      review_trigger_route: review-queue
      review_trigger_probe: "Confirm the named input is present in the current triage request."
      review_trigger_input: "Specific evidence or decision the user must supply."
      review_trigger: "Required for defer; remove for other verdicts."
      next_action: "Required for defer; remove for other verdicts."
      close_condition: "Required for defer; remove for other verdicts."
      ---

      # Triage decision

      Optional concise implementation-batch notes.
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

    def initialize(root)
      raise MissingStateRoot, "#{STATE_ENV} is not set" if RetroState.blank?(root)

      @root = canonical_root(root)
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

    def route(input_path)
      init
      data, body = RetroState.read_document(input_path)
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

    def route_verification(input_path)
      data, body = RetroState.read_document(input_path)
      RetroState.validate_verification_proposal(data, body, label: input_path, routed: false)
      ensure_initialized
      validate_verification_target!(data)
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
      return [] unless verification_dirs_present?

      Dir.glob(File.join(root, "verifications", "inbox", "*.md")).sort.map do |path|
        data, body = RetroState.read_document(path)
        RetroState.validate_verification_proposal(data, body, label: path, routed: true)
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

      data["closure"] = closure
      destination = papercut_path("archive", papercut_id)
      exclusive_write(destination, RetroState.render_document(data, body))
      File.unlink(source)
      destination
    end

    def process(candidate_id, decision_path)
      ensure_initialized
      source = candidate_path("inbox", candidate_id)
      raise Error, "candidate not found in inbox: #{candidate_id}" unless File.file?(source)

      candidate, body = RetroState.read_document(source)
      RetroState.validate_candidate(candidate, body, label: source, routed: true)
      decision, decision_body = RetroState.read_document(decision_path)
      RetroState.validate_decision(decision, decision_body, label: decision_path, expected_id: candidate_id)
      cadence = artifact_cadence_state

      triage = RetroState.without_keys(decision, "schema_version", "record_type")
      triage["notes"] = decision_body.rstrip unless decision_body.strip.empty?
      candidate["triage"] = triage
      output = RetroState.render_document(candidate, body)
      destination = candidate_path("archive", candidate_id)
      exclusive_write(destination, output)
      cadence["candidate_archives_total"] += 1
      write_artifact_cadence(cadence)
      File.unlink(source)
      destination
    end

    def process_verification(proposal_id, decision_path)
      ensure_initialized
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

      apply_verification_proposal!(proposal, decision) if decision.fetch("verdict") == "apply"
      triage = RetroState.without_keys(decision, "schema_version", "record_type")
      triage["notes"] = decision_body.rstrip unless decision_body.strip.empty?
      proposal["triage"] = triage
      output = RetroState.render_document(proposal, body)
      destination = verification_path("archive", proposal_id)
      write_or_verify_archive(destination, output)
      File.unlink(source)
      destination
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
      validate_accepted_external_references!(replacement, accepted_id: accepted_id)

      replacement["accepted_id"] = current.fetch("accepted_id")
      replacement["accepted_at"] = current.fetch("accepted_at")
      RetroState.validate_accepted(replacement, body, label: input_path, assigned: true)
      replace_write(path, RetroState.render_document(replacement, body))
      path
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
      path = ledger_path(ledger_id)
      raise Error, "ledger not found: #{ledger_id}" unless File.file?(path)

      blocking_accepted_id = accepted_records.find do |_accepted_path, accepted|
        accepted.dig("contradiction", "residual_ledger_id") == ledger_id &&
          !TERMINAL_CONTRADICTION_DISPOSITIONS.include?(accepted["disposition"])
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

    def review_queue
      ensure_initialized
      rows = []

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
        next if TERMINAL_CONTRADICTION_DISPOSITIONS.include?(data["disposition"])
        residual_id = data.dig("contradiction", "residual_ledger_id")
        next if residual_id && action_reference_open?(residual_id)

        trigger = "Correct or remove contradicted guidance, or assign an executable residual ledger action."
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

    def accepted_publication_expected?(triage, candidates_by_id, visited_ids = [])
      verdict = triage.fetch("verdict")
      return true if %w[accept split].include?(verdict)
      return false unless verdict == "merge"

      related_ids = triage.fetch("related_candidate_ids", [])
      return true if related_ids.empty?

      related_ids.any? do |id|
        next false if visited_ids.include?(id)

        related = candidates_by_id[id]
        related.nil? || accepted_publication_expected?(
          related.fetch("triage"),
          candidates_by_id,
          visited_ids + [id]
        )
      end
    end

    def verification_opportunities(destination: nil)
      ensure_initialized
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
          path
        ]
      end
    end

    def record_audit(input_path)
      ensure_initialized
      data, body = RetroState.read_document(input_path)
      RetroState.validate_learning_audit(data, body, label: input_path, assigned: false)
      data.fetch("unresolved_action_ids").each do |action_id|
        next if action_reference_open?(action_id)

        raise Error, "audit unresolved action is missing or not open: #{action_id}"
      end

      now = Time.now.utc
      id = unique_auxiliary_id("LA", "audits/learning-process")
      cadence = artifact_cadence_state
      data["audit_id"] = id
      data["completed_at"] = now.strftime("%Y-%m-%dT%H:%M:%SZ")
      data["candidate_archive_count"] = archived_candidates.length
      data["candidate_archives_total"] = cadence.fetch("candidate_archives_total")
      RetroState.validate_learning_audit(data, body, label: input_path, assigned: true)
      destination = learning_audit_path(id)
      exclusive_write(destination, RetroState.render_document(data, body))
      if data["audit_kind"] == "skill-repository"
        cadence["last_completed_artifact_audit_total"] = cadence.fetch("candidate_archives_total")
        write_artifact_cadence(cadence)
      end
      destination
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
        if !TERMINAL_CONTRADICTION_DISPOSITIONS.include?(data["disposition"]) && ledger["status"] != "open"
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

    def validate_candidate_supersession!(candidate)
      supersedes_id = candidate["supersedes_accepted_id"]
      return unless supersedes_id
      return if File.file?(accepted_path(supersedes_id))

      raise Error, "candidate supersedes missing accepted record: #{supersedes_id}"
    end

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
        proposal, proposal_body = RetroState.read_document(proposal_path)
        RetroState.validate_verification_proposal(
          proposal,
          proposal_body,
          label: proposal_path,
          routed: true,
          archived: true
        )
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
      return if TERMINAL_CONTRADICTION_DISPOSITIONS.include?(accepted["disposition"])
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
      replacement["observed_behavior"] = proposal.fetch("observation")
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
        current_state == "unverified"
      else
        %w[unverified supported].include?(current_state)
      end
      return if valid

      raise Error, "verification target state #{current_state} cannot receive proposed #{proposed_state} evidence"
    end

    def write_or_verify_archive(destination, output)
      if File.file?(destination)
        unless File.binread(destination) == output
          raise Error, "existing verification archive differs: #{destination}"
        end
      else
        exclusive_write(destination, output)
      end
    end

    def archived_candidates
      Dir.glob(File.join(root, "retrospectives", "archive", "*.md")).sort.map do |path|
        data, body = RetroState.read_document(path)
        RetroState.validate_candidate(data, body, label: path, routed: true, archived: true)
        [path, data]
      end
    end

    def accepted_records
      Dir.glob(File.join(root, "retrospectives", "accepted", "*.md")).sort.map do |path|
        data, body = RetroState.read_document(path)
        RetroState.validate_accepted(data, body, label: path, assigned: true)
        [path, data]
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
      if File.file?(path)
        data = YAML.safe_load(File.read(path, encoding: "UTF-8"), aliases: false)
        data = RetroState.stringify_keys(data) if data.is_a?(Hash)
        RetroState.validate_artifact_cadence(data, label: path)
        return data
      end

      latest = learning_audits
        .select { |_audit_path, data| data["audit_kind"] == "skill-repository" }
        .max_by { |_audit_path, data| data.fetch("completed_at") }
        &.last
      total = archived_candidates.length
      baseline = if latest
        latest.fetch("candidate_archives_total", latest.fetch("candidate_archive_count", 0))
      else
        0
      end
      total = [total, baseline].max
      {
        "schema_version" => SCHEMA_VERSION,
        "record_type" => ARTIFACT_CADENCE_RECORD_TYPE,
        "candidate_archives_total" => total,
        "last_completed_artifact_audit_total" => baseline
      }
    rescue Psych::Exception => e
      raise Error, "#{path}: invalid YAML: #{e.message}"
    end

    def write_artifact_cadence(data)
      RetroState.validate_artifact_cadence(data, label: artifact_cadence_path)
      replace_write(artifact_cadence_path, YAML.dump(data))
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
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(content)
        file.flush
        file.fsync
      end
    rescue Errno::EEXIST
      raise Error, "refusing to overwrite existing state file: #{path}"
    end

    def replace_write(path, content)
      temporary = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(3)}"
      exclusive_write(temporary, content)
      File.rename(temporary, path)
    ensure
      File.unlink(temporary) if temporary && File.exist?(temporary)
    end
  end

  def self_test
    Dir.mktmpdir("retro-state-self-test.") do |tmp|
      root = File.join(tmp, "state")
      input = File.join(tmp, "candidate.md")
      decision = File.join(tmp, "decision.md")
      accepted = File.join(tmp, "accepted.md")
      draft = File.join(tmp, "draft.md")
      ledger = File.join(tmp, "ledger.md")
      audit = File.join(tmp, "audit.md")
      papercut = File.join(tmp, "papercut.md")
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
      {
        "kind" => PAPERCUT_KINDS,
        "impact" => PAPERCUT_IMPACTS,
        "resolution" => PAPERCUT_RESOLUTIONS,
        "owner_hint" => PAPERCUT_OWNERS
      }.each do |field, values|
        line = papercut_template.lines.find { |candidate| candidate.start_with?("#{field}:") }
        unless line && values.all? { |value| line.include?(value) }
          raise "papercut template #{field} vocabulary is incomplete"
        end
      end
      File.write(input, candidate_template.gsub("Short candidate title", "Atomic routing"))

      store = Store.new(root)
      store.init

      base_decision, decision_body = parse_document(decision_template)
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

      accepted_text = accepted_template.sub("RC-YYYYMMDDTHHMMSSZ-abcdef", id)
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
      cadence_before_verification = store.artifact_audit_status
      supported_decision_text = verification_decision_template
        .sub("VP-YYYYMMDDTHHMMSSZ-abcdef", supported_proposal_id)
        .sub("verdict: reject", "verdict: apply")
        .sub("YYYY-MM-DDTHH:MM:SSZ", "2026-07-15T12:01:00Z")
      File.write(verification_decision, supported_decision_text)
      supported_archive_path = store.process_verification(supported_proposal_id, verification_decision)
      raise "verification proposal was not archived" unless File.file?(supported_archive_path)
      raise "verification proposal remained pending" unless store.pending_verifications.empty?
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
          rejected_accepted.fetch("applied_verification_proposal_ids") == [supported_proposal_id]
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

      contradicted_data = updated_accepted.merge(
        "verification" => "contradicted",
        "verification_basis" => "later-session",
        "contradiction" => {
          "summary" => "Later evidence contradicts the implemented outcome.",
          "what_is_false" => "The earlier action is not safe under the observed condition.",
          "recorded_at" => "2026-07-15T12:03:00Z",
          "decisive_evidence" => ["Later-session evidence reproduced the unsafe action."]
        }
      )
      contradicted_text = render_document(contradicted_data, rejected_accepted_body)
      File.write(accepted, contradicted_text)
      store.update_accepted(accepted_id, accepted)
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
      deferred_decision = decision_template
        .sub("RC-YYYYMMDDTHHMMSSZ-abcdef", deferred_id)
        .sub("YYYY-MM-DDTHH:MM:SSZ", "2026-07-15T12:05:00Z")
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

      refreshed_decision = decision_template
        .sub("RC-YYYYMMDDTHHMMSSZ-abcdef", deferred_id)
        .sub("YYYY-MM-DDTHH:MM:SSZ", "2026-07-15T12:06:00Z")
        .sub(
          'review_trigger: "Required for defer; remove for other verdicts."',
          'review_trigger: "A second independent observation is recorded."'
        )
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

def usage
  <<~TEXT
    Usage: retro-state.rb COMMAND [options]

    Manage disposable Markdown state beneath #{RetroState::STATE_ENV}.

    Commands:
      init                              Initialize the configured state root
      template TYPE                    Print a papercut, candidate, decision, verification,
                                        verification-decision, accepted, draft, ledger, or audit template
      record-papercut --file PATH      Record a papercut from PATH, or - for standard input
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
                                        Replace a curated record while preserving identity
      verification-opportunities [--destination TEXT]
                                        List relevant unverified accepted outcomes
      record-draft --file PATH          Store an uninstalled draft
      record-ledger --file PATH         Store a maintenance ledger entry
      close-ledger --id ID --rationale TEXT
                                        Close a maintenance ledger entry
      record-audit --file PATH          Store a completed sanitized system audit
      audits                            List completed system audits
      artifact-audit-status [--archive-threshold N]
                                        Report machine-owned artifact-audit cadence
      review-queue                      List unresolved executable learning work
      validate                          Validate the configured live state
      self-test                         Exercise the protocol in a temporary directory

    Common option:
      --root DIR  Override #{RetroState::STATE_ENV} for this invocation
  TEXT
end

def parse_options!(parser, arguments)
  parser.parse!(arguments)
  return if arguments.empty?

  raise OptionParser::InvalidArgument, "unexpected argument: #{arguments.first}"
end

def reject_inapplicable_options!(command, provided)
  allowed = {
    "init" => %w[--root],
    "template" => [],
    "record-papercut" => %w[--root --file],
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
    "verification-opportunities" => %w[--root --destination],
    "record-draft" => %w[--root --file],
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
  init template record-papercut papercuts close-papercut route pending process
  route-verification pending-verifications process-verification
  reconsider record-accepted update-accepted record-draft record-ledger close-ledger
  verification-opportunities record-audit audits artifact-audit-status
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
decision_path = nil
archive = false
outcome = nil
rationale = nil
related_papercut_id = nil
related_candidate_id = nil
destination_filter = nil
archive_threshold = RetroState::ARTIFACT_AUDIT_ARCHIVE_THRESHOLD
archive_threshold_explicit = false
parser = OptionParser.new do |opts|
  opts.on("--root DIR") { |value| root_override = value }
  opts.on("--file PATH") { |value| input_path = value }
  opts.on("--id ID") { |value| record_id = value }
  opts.on("--decision PATH") { |value| decision_path = value }
  opts.on("--archive") { archive = true }
  opts.on("--outcome OUTCOME") { |value| outcome = value }
  opts.on("--rationale TEXT") { |value| rationale = value }
  opts.on("--related-papercut-id ID") { |value| related_papercut_id = value }
  opts.on("--related-candidate-id ID") { |value| related_candidate_id = value }
  opts.on("--destination TEXT") { |value| destination_filter = value }
  opts.on("--archive-threshold N", Integer) do |value|
    archive_threshold = value
    archive_threshold_explicit = true
  end
  opts.on("--help") do
    puts usage
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
      "--decision" => !decision_path.nil?,
      "--archive" => archive,
      "--outcome" => !outcome.nil?,
      "--rationale" => !rationale.nil?,
      "--related-papercut-id" => !related_papercut_id.nil?,
      "--related-candidate-id" => !related_candidate_id.nil?,
      "--destination" => !destination_filter.nil?,
      "--archive-threshold" => archive_threshold_explicit
    }
  )

  case command
  when "template"
    template = case type
    when "papercut" then RetroState.papercut_template
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
    when "init"
      puts store.init
    when "route"
      raise RetroState::Error, "route requires --file PATH" unless input_path

      data, body = RetroState.read_document(input_path)
      RetroState.validate_candidate(data, body, label: input_path, routed: false)
      begin
        puts store.route(input_path)
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
        puts store.route_verification(input_path)
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
    when "verification-opportunities"
      store.verification_opportunities(destination: destination_filter).each do |row|
        puts row.join("\t")
      end
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
      raise RetroState::Error, "record-audit requires --file PATH" unless input_path

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
  warn usage
  exit 2
rescue RetroState::Error, Errno::ENOENT, Errno::EACCES => e
  warn "retro-state.rb: #{e.message}"
  exit 1
end
