#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "optparse"
require "tmpdir"
require "yaml"
require "date"

repo_dir = File.expand_path("..", __dir__)
archive_dir = File.join(repo_dir, "retrospectives")
self_test = false

OptionParser.new do |opts|
  opts.banner = "Usage: validate-retrospectives.rb [--archive DIR] [--self-test]"
  opts.on("--archive DIR", "Validate a retrospective archive directory") do |value|
    archive_dir = File.expand_path(value)
  end
  opts.on("--self-test", "Run validator fixture checks") do
    self_test = true
  end
end.parse!

ID_PATTERN = /\ASCR-\d{8}-[a-z0-9]+(?:-[a-z0-9]+)*\z/.freeze
DISPOSITIONS = %w[accepted implemented no-change superseded reverted].freeze
VERIFICATIONS = %w[unverified supported contradicted].freeze
VERIFICATION_BASES = %w[none later-session deterministic-test].freeze
REQUIRED_FIELDS = %w[
  id
  accepted_date
  source_report_summary
  expected_behavior
  observed_behavior
  decisive_evidence
  materially_distinct_attempts
  trigger
  non_trigger
  destination
  verification_opportunity
  redaction_review
  disposition
  verification
  verification_basis
  implementation_commit
].freeze
FORBIDDEN_PATTERNS = [
  [%r{(?:^|/)\.codex/(?:sessions|history|logs|attachments)(?:/|\b)}, "raw Codex runtime history path"],
  [%r{(?:^|/)auth\.json\z}, "Codex auth file"],
  [%r{(?:^|/)sessions/[^[:space:]]+\.jsonl\b}, "raw session transcript path"],
  [/BEGIN (?:OPENSSH|RSA|DSA|EC|PGP) PRIVATE KEY/, "private key material"]
].freeze

def read_utf8(path)
  File.read(path, encoding: "UTF-8", invalid: :replace, undef: :replace)
end

def frontmatter(path)
  text = read_utf8(path)
  yaml = text.split(/^---\s*$/, 3)[1]
  raise "#{path}: missing YAML frontmatter" unless yaml

  data = YAML.safe_load(yaml, permitted_classes: [Date])
  raise "#{path}: YAML frontmatter must be a mapping" unless data.is_a?(Hash)

  [data, text]
end

def blank_value?(value)
  case value
  when nil
    true
  when String
    value.empty?
  when Array
    value.empty? || value.any? { |item| !item.is_a?(String) || item.empty? }
  else
    false
  end
end

def validate_archive(archive_dir)
  accepted_dir = File.join(archive_dir, "accepted")
  template_path = File.join(archive_dir, "templates", "accepted-candidate.md")
  errors = []
  ids = {}

  errors << "#{archive_dir}: missing archive README.md" unless File.file?(File.join(archive_dir, "README.md"))
  errors << "#{template_path}: missing accepted candidate template" unless File.file?(template_path)
  errors << "#{accepted_dir}: missing accepted records directory" unless Dir.exist?(accepted_dir)
  return errors unless Dir.exist?(accepted_dir)

  Dir.glob(File.join(accepted_dir, "*.md")).sort.each do |path|
    data, text = frontmatter(path)

    REQUIRED_FIELDS.each do |field|
      if field == "implementation_commit"
        errors << "#{path}: missing #{field}" unless data.key?(field)
      elsif blank_value?(data[field])
        errors << "#{path}: missing or empty #{field}"
      end
    end

    id = data["id"]
    if id && !id.match?(ID_PATTERN)
      errors << "#{path}: id must match SCR-YYYYMMDD-short-slug"
    end
    if id
      if ids.key?(id)
        errors << "#{path}: duplicate id #{id} also used by #{ids.fetch(id)}"
      else
        ids[id] = path
      end
    end

    disposition = data["disposition"]
    verification = data["verification"]
    verification_basis = data["verification_basis"]
    unless DISPOSITIONS.include?(disposition)
      errors << "#{path}: disposition must be one of #{DISPOSITIONS.join(', ')}"
    end
    unless VERIFICATIONS.include?(verification)
      errors << "#{path}: verification must be one of #{VERIFICATIONS.join(', ')}"
    end
    unless VERIFICATION_BASES.include?(verification_basis)
      errors << "#{path}: verification_basis must be one of #{VERIFICATION_BASES.join(', ')}"
    end
    if verification == "unverified" && verification_basis != "none"
      errors << "#{path}: unverified records must use verification_basis: none"
    end
    if %w[supported contradicted].include?(verification) && verification_basis == "none"
      errors << "#{path}: #{verification} records need later-session or deterministic-test basis"
    end

    if data["implementation_commit"] && !data["implementation_commit"].empty? &&
       !data["implementation_commit"].match?(/\A[0-9a-f]{7,40}\z/)
      errors << "#{path}: implementation_commit must be empty or a Git commit hash"
    end

    FORBIDDEN_PATTERNS.each do |pattern, label|
      errors << "#{path}: contains forbidden #{label}" if text.match?(pattern)
    end
  rescue StandardError => e
    errors << e.message
  end

  errors
end

def write_record(path, id:, disposition: "accepted", verification: "unverified",
                 verification_basis: "none", extra: "")
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, <<~MD)
    ---
    id: #{id}
    accepted_date: "2026-01-02"
    source_report_summary: "Accepted report summary."
    expected_behavior: "Expected behavior."
    observed_behavior: "Observed behavior."
    decisive_evidence:
      - "Evidence."
    materially_distinct_attempts:
      - "Attempt."
    trigger: "Trigger."
    non_trigger: "Non-trigger."
    destination: "skills/example/SKILL.md"
    verification_opportunity: "Future observation."
    redaction_review: "No raw transcript, secret, or private path included."
    disposition: #{disposition}
    verification: #{verification}
    verification_basis: #{verification_basis}
    implementation_commit: ""
    #{extra}
    ---

    # #{id}
  MD
end

def build_archive(root)
  FileUtils.mkdir_p(File.join(root, "accepted"))
  FileUtils.mkdir_p(File.join(root, "templates"))
  File.write(File.join(root, "README.md"), "# Test Archive\n")
  File.write(File.join(root, "templates", "accepted-candidate.md"), "---\n# template\n---\n")
end

def expect_valid(label)
  errors = yield
  return if errors.empty?

  raise "#{label}: expected valid archive, got: #{errors.join('; ')}"
end

def expect_invalid(label, expected_fragment)
  errors = yield
  if errors.any? { |error| error.include?(expected_fragment) }
    return
  end

  raise "#{label}: expected error containing #{expected_fragment.inspect}, got: #{errors.join('; ')}"
end

def run_self_test
  Dir.mktmpdir("retro-validator.") do |tmp|
    root = File.join(tmp, "archive")
    build_archive(root)
    write_record(File.join(root, "accepted", "valid.md"), id: "SCR-20260102-valid-record")
    expect_valid("valid fixture") { validate_archive(root) }

    write_record(File.join(root, "accepted", "bad-id.md"), id: "bad")
    expect_invalid("bad id", "id must match") { validate_archive(root) }
    FileUtils.rm_f(File.join(root, "accepted", "bad-id.md"))

    write_record(
      File.join(root, "accepted", "bad-state.md"),
      id: "SCR-20260102-bad-state",
      verification: "supported",
      verification_basis: "none"
    )
    expect_invalid("bad state", "need later-session or deterministic-test") { validate_archive(root) }
    FileUtils.rm_f(File.join(root, "accepted", "bad-state.md"))

    write_record(File.join(root, "accepted", "duplicate.md"), id: "SCR-20260102-valid-record")
    expect_invalid("duplicate id", "duplicate id") { validate_archive(root) }
    FileUtils.rm_f(File.join(root, "accepted", "duplicate.md"))

    write_record(
      File.join(root, "accepted", "forbidden.md"),
      id: "SCR-20260102-forbidden-path",
      extra: "note: \"/home/user/.codex/sessions/raw.jsonl\""
    )
    expect_invalid("forbidden path", "forbidden raw Codex runtime history path") { validate_archive(root) }
  end
end

begin
  run_self_test if self_test
  errors = validate_archive(archive_dir)
  if errors.empty?
    puts "Retrospective archive validation passed."
    exit 0
  end

  errors.each { |error| warn error }
  exit 1
rescue StandardError => e
  warn e.message
  exit 1
end
