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
  CONFIDENCES = %w[high medium low].freeze
  RECOMMENDATIONS = %w[
    update-existing no-change new-skill new-script new-prompt uncertain
  ].freeze
  DRAFT_STATUSES = %w[open revised activated deprecated].freeze
  LEDGER_STATUSES = %w[open closed].freeze
  STATE_DIRS = %w[
    retrospectives/inbox
    retrospectives/archive
    retrospectives/accepted
    drafts
    ledgers
    audits/learning-process
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
    parse_document(File.read(path, encoding: "UTF-8"), label: path)
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
    unless value.is_a?(Array) && (allow_empty || !value.empty?) &&
           value.all? { |item| item.is_a?(String) && !item.empty? }
      qualifier = allow_empty ? "an array of strings" : "a non-empty array of strings"
      raise Error, "#{label}: #{field} must be #{qualifier}"
    end
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
      raise Error, "#{label}: confidence must be one of #{CONFIDENCES.join(', ')}"
    end
    unless RECOMMENDATIONS.include?(data["recommendation"])
      raise Error, "#{label}: recommendation must be one of #{RECOMMENDATIONS.join(', ')}"
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
      intake = data.reject { |key, _| %w[intake_digest triage].include?(key) }
      expected_digest = Digest::SHA256.hexdigest(render_document(intake, body))
      unless data["intake_digest"] == expected_digest
        raise Error, "#{label}: intake fields changed after routing"
      end
    elsif data.key?("candidate_id") || data.key?("created_at") || data.key?("intake_digest")
      raise Error, "#{label}: unrouted input must not assign identity fields"
    end

    triage = data["triage"]
    if archived
      validate_triage(triage, data["candidate_id"], label)
    elsif triage
      raise Error, "#{label}: inbox candidate must not contain triage data"
    end
  end

  def validate_triage(triage, candidate_id, label)
    raise Error, "#{label}: missing triage mapping" unless triage.is_a?(Hash)

    require_fields(triage, %w[candidate_id verdict rationale reviewed_at], "#{label} triage")
    unless triage["candidate_id"] == candidate_id
      raise Error, "#{label}: triage candidate_id does not match intake"
    end
    unless VERDICTS.include?(triage["verdict"])
      raise Error, "#{label}: verdict must be one of #{VERDICTS.join(', ')}"
    end

    related = triage.fetch("related_candidate_ids", [])
    unless related.is_a?(Array) && related.all? { |item| item.is_a?(String) && !item.empty? }
      raise Error, "#{label}: related_candidate_ids must be an array of strings"
    end

    return unless triage["verdict"] == "defer"

    require_fields(triage, %w[review_trigger next_action close_condition], "#{label} deferred triage")
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
      raise Error, "#{label}: verdict must be one of #{VERDICTS.join(', ')}"
    end
    require_string_array(data, "related_candidate_ids", label, allow_empty: true)
    if data["verdict"] == "defer"
      require_fields(data, %w[review_trigger next_action close_condition], label)
    end
  end

  def validate_accepted(data, body, label:, assigned:)
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
    unless data["implementation_commits"].all? { |item| item.match?(/\A[0-9a-f]{7,40}\z/) }
      raise Error, "#{label}: implementation_commits must contain Git commit hashes"
    end
  end

  def validate_draft(data, body, label:, assigned:)
    text = render_document(data, body)
    validate_common(data, text, label)
    raise Error, "#{label}: record_type must be draft" unless data["record_type"] == "draft"

    require_fields(
      data,
      %w[
        title purpose trigger_boundary review_trigger next_action close_condition
        status redaction_review
      ],
      label
    )
    %w[evidence seeded_conventions missing_evidence activation_criteria].each do |field|
      require_string_array(data, field, label)
    end
    unless DRAFT_STATUSES.include?(data["status"])
      raise Error, "#{label}: status must be one of #{DRAFT_STATUSES.join(', ')}"
    end

    validate_assigned_id(data, label, assigned, "draft_id", /\ASD-\d{8}-[a-f0-9]{6}\z/)
  end

  def validate_ledger_entry(data, body, label:, assigned:)
    text = render_document(data, body)
    validate_common(data, text, label)
    unless data["record_type"] == "ledger-entry"
      raise Error, "#{label}: record_type must be ledger-entry"
    end

    require_fields(
      data,
      %w[
        title owner status last_reviewed review_trigger next_action
        close_condition redaction_review
      ],
      label
    )
    require_string_array(data, "evidence", label)
    unless LEDGER_STATUSES.include?(data["status"])
      raise Error, "#{label}: status must be one of #{LEDGER_STATUSES.join(', ')}"
    end

    validate_assigned_id(data, label, assigned, "ledger_id", /\ALE-\d{8}-[a-f0-9]{6}\z/)
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
      recommendation: uncertain
      redaction_review: "Confirmed no raw transcript, secret, private source, or unredacted local path is included."
      ---

      # Short candidate title

      Optional concise context. Keep this document self-contained and sanitized.
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
      review_trigger: "Date or event that requires activate, revise, or deprecate judgment."
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
      review_trigger: "Date, recurrence threshold, or concrete event."
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

  class Store
    attr_reader :root

    def initialize(root)
      raise MissingStateRoot, "#{STATE_ENV} is not set" if RetroState.blank?(root)

      @root = File.expand_path(root)
    end

    def init
      refuse_git_worktree!
      FileUtils.mkdir_p(root, mode: 0o700)
      File.chmod(0o700, root)
      STATE_DIRS.each do |relative|
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

      now = Time.now.utc
      id = unique_id("RC-#{now.strftime('%Y%m%dT%H%M%SZ')}")
      data["candidate_id"] = id
      data["created_at"] = now.strftime("%Y-%m-%dT%H:%M:%SZ")
      data["intake_digest"] = Digest::SHA256.hexdigest(RetroState.render_document(data.reject { |key, _| key == "intake_digest" }, body))
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

    def process(candidate_id, decision_path)
      ensure_initialized
      source = candidate_path("inbox", candidate_id)
      raise Error, "candidate not found in inbox: #{candidate_id}" unless File.file?(source)

      candidate, body = RetroState.read_document(source)
      RetroState.validate_candidate(candidate, body, label: source, routed: true)
      decision, decision_body = RetroState.read_document(decision_path)
      RetroState.validate_decision(decision, decision_body, label: decision_path, expected_id: candidate_id)

      triage = decision.reject { |key, _| %w[schema_version record_type].include?(key) }
      triage["notes"] = decision_body.rstrip unless decision_body.strip.empty?
      candidate["triage"] = triage
      output = RetroState.render_document(candidate, body)
      destination = candidate_path("archive", candidate_id)
      exclusive_write(destination, output)
      File.unlink(source)
      destination
    end

    def record_accepted(input_path)
      ensure_initialized
      data, body = RetroState.read_document(input_path)
      RetroState.validate_accepted(data, body, label: input_path, assigned: false)
      missing = data.fetch("originating_candidate_ids").reject do |id|
        File.file?(candidate_path("archive", id))
      end
      raise Error, "accepted record references candidates not in archive: #{missing.join(', ')}" unless missing.empty?

      now = Time.now.utc
      id = unique_id("SCR-#{now.strftime('%Y%m%d')}")
      data["accepted_id"] = id
      data["accepted_at"] = now.strftime("%Y-%m-%dT%H:%M:%SZ")
      output = RetroState.render_document(data, body)
      destination = File.join(root, "retrospectives", "accepted", "#{id}.md")
      exclusive_write(destination, output)
      destination
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

    def review_queue
      ensure_initialized
      rows = []

      Dir.glob(File.join(root, "retrospectives", "archive", "*.md")).sort.each do |path|
        data, body = RetroState.read_document(path)
        RetroState.validate_candidate(data, body, label: path, routed: true, archived: true)
        triage = data.fetch("triage")
        next unless triage["verdict"] == "defer"

        rows << ["deferred", data.fetch("candidate_id"), triage.fetch("review_trigger"), path]
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

      rows
    end

    def validate
      ensure_initialized
      errors = []
      ids = {}

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
        rescue Error => e
          errors << e.message
        end
      end

      accepted_ids = {}
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
      rescue Error => e
        errors << e.message
      end

      validate_auxiliary_dir(errors, "drafts", "draft_id") do |data, body, path|
        RetroState.validate_draft(data, body, label: path, assigned: true)
      end
      validate_auxiliary_dir(errors, "ledgers", "ledger_id") do |data, body, path|
        RetroState.validate_ledger_entry(data, body, label: path, assigned: true)
      end

      raise Error, errors.join("\n") unless errors.empty?

      true
    end

    private

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
        id = "#{prefix}-#{Time.now.utc.strftime('%Y%m%d')}-#{SecureRandom.hex(3)}"
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
  end

  def self_test
    Dir.mktmpdir("retro-state-self-test.") do |tmp|
      root = File.join(tmp, "state")
      input = File.join(tmp, "candidate.md")
      decision = File.join(tmp, "decision.md")
      accepted = File.join(tmp, "accepted.md")
      draft = File.join(tmp, "draft.md")
      ledger = File.join(tmp, "ledger.md")
      File.write(input, candidate_template.gsub("Short candidate title", "Atomic routing"))

      store = Store.new(root)
      store.init
      path = store.route(input)
      id = File.basename(path, ".md")
      raise "pending candidate missing" unless store.pending.map(&:first) == [id]
      store.validate

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

      decision_text = decision_template
                      .sub("RC-YYYYMMDDTHHMMSSZ-abcdef", id)
                      .sub("YYYY-MM-DDTHH:MM:SSZ", "2026-07-15T12:00:00Z")
                      .sub("verdict: defer", "verdict: accept")
                      .sub(/^review_trigger:.*\n/, "")
                      .sub(/^next_action:.*\n/, "")
                      .sub(/^close_condition:.*\n/, "")
      File.write(decision, decision_text)
      archive_path = store.process(id, decision)
      raise "candidate was not archived" unless File.file?(archive_path)
      raise "candidate remained in inbox" if File.exist?(path)

      accepted_text = accepted_template.sub("RC-YYYYMMDDTHHMMSSZ-abcdef", id)
      File.write(accepted, accepted_text)
      accepted_path = store.record_accepted(accepted)
      raise "accepted record missing" unless File.file?(accepted_path)

      File.write(draft, draft_template)
      raise "draft record missing" unless File.file?(store.record_draft(draft))
      File.write(ledger, ledger_template)
      raise "ledger record missing" unless File.file?(store.record_ledger(ledger))

      deferred_path = store.route(input)
      deferred_id = File.basename(deferred_path, ".md")
      deferred_decision = decision_template
                          .sub("RC-YYYYMMDDTHHMMSSZ-abcdef", deferred_id)
                          .sub("YYYY-MM-DDTHH:MM:SSZ", "2026-07-15T12:05:00Z")
      File.write(decision, deferred_decision)
      store.process(deferred_id, decision)
      review_types = store.review_queue.map(&:first)
      raise "deferral missing from review queue" unless review_types.include?("deferred")
      raise "draft missing from review queue" unless review_types.include?("draft")
      raise "ledger missing from review queue" unless review_types.include?("ledger")
      store.validate

      forbidden = File.join(tmp, "forbidden.md")
      File.write(forbidden, candidate_template.sub("Optional concise context.", "Raw /home/person/private path."))
      begin
        store.route(forbidden)
        raise "forbidden path was accepted"
      rescue Error => e
        raise unless e.message.include?("unredacted user-home path")
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
      template TYPE                    Print candidate, decision, accepted, draft, or ledger template
      route --file PATH                Route a candidate into the inbox
      pending                           List validated inbox candidates
      process --id ID --decision PATH  Archive a candidate with a verdict
      record-accepted --file PATH       Store a curated accepted record
      record-draft --file PATH          Store an uninstalled draft
      record-ledger --file PATH         Store a maintenance ledger entry
      review-queue                      List open deferrals, drafts, and ledger entries
      validate                          Validate the configured live state
      self-test                         Exercise the protocol in a temporary directory

    Common option:
      --root DIR  Override #{RetroState::STATE_ENV} for this invocation
  TEXT
end

if ARGV.empty? || %w[-h --help].include?(ARGV.first)
  puts usage
  exit 0
end

command = ARGV.shift

root_override = nil
input_path = nil
candidate_id = nil
decision_path = nil
parser = OptionParser.new do |opts|
  opts.on("--root DIR") { |value| root_override = value }
  opts.on("--file PATH") { |value| input_path = value }
  opts.on("--id ID") { |value| candidate_id = value }
  opts.on("--decision PATH") { |value| decision_path = value }
  opts.on("--help") do
    puts usage
    exit 0
  end
end

begin
  case command
  when "template"
    type = ARGV.shift
    parser.parse!(ARGV)
    template = case type
               when "candidate" then RetroState.candidate_template
               when "decision" then RetroState.decision_template
               when "accepted" then RetroState.accepted_template
               when "draft" then RetroState.draft_template
               when "ledger" then RetroState.ledger_template
               else raise RetroState::Error, "unknown template type: #{type}"
               end
    print template
  when "self-test"
    parser.parse!(ARGV)
    RetroState.self_test
    puts "Retro state self-test passed."
  else
    parser.parse!(ARGV)
    root = root_override || ENV[RetroState::STATE_ENV]
    if command == "route" && RetroState.blank?(root)
      raise RetroState::Error, "route requires --file PATH" unless input_path

      data, body = RetroState.read_document(input_path)
      RetroState.validate_candidate(data, body, label: input_path, routed: false)
      warn "#{RetroState::STATE_ENV} is not set; no state was written. Paste-ready candidate follows."
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
    when "pending"
      store.pending.each { |id, title, path| puts [id, title, path].join("\t") }
    when "process"
      raise RetroState::Error, "process requires --id ID" unless candidate_id
      raise RetroState::Error, "process requires --decision PATH" unless decision_path

      puts store.process(candidate_id, decision_path)
    when "record-accepted"
      raise RetroState::Error, "record-accepted requires --file PATH" unless input_path

      puts store.record_accepted(input_path)
    when "record-draft"
      raise RetroState::Error, "record-draft requires --file PATH" unless input_path

      puts store.record_draft(input_path)
    when "record-ledger"
      raise RetroState::Error, "record-ledger requires --file PATH" unless input_path

      puts store.record_ledger(input_path)
    when "review-queue"
      store.review_queue.each { |type, id, trigger, path| puts [type, id, trigger, path].join("\t") }
    when "validate"
      store.validate
      puts "Retro state validation passed."
    else
      raise RetroState::Error, "unknown command: #{command}"
    end
  end
rescue RetroState::Error, Errno::ENOENT, Errno::EACCES => e
  warn "retro-state.rb: #{e.message}"
  exit 1
end
