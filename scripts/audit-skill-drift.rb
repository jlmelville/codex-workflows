#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "set"
require "yaml"

repo_dir = File.expand_path("..", __dir__)
options = {
  max_description: 420,
  max_total_description: 6_000,
  overlap_threshold: 0.20,
  strict: false,
  strict_hard: false,
  hard_only: false,
  show_triaged: false,
  triage_path: File.join(repo_dir, "scripts", "audit-skill-drift-triage.tsv")
}

OptionParser.new do |opts|
  opts.banner = "Usage: audit-skill-drift.rb [options]"
  opts.on("--max-description N", Integer, "Flag descriptions longer than N characters") do |value|
    options[:max_description] = value
  end
  opts.on("--max-total-description N", Integer, "Flag total description budget above N characters") do |value|
    options[:max_total_description] = value
  end
  opts.on("--overlap-threshold N", Float, "Flag description token overlap above N") do |value|
    options[:overlap_threshold] = value
  end
  opts.on("--strict", "Exit nonzero when any untriaged findings are present") do
    options[:strict] = true
  end
  opts.on("--strict-hard", "Exit nonzero when hard untriaged findings are present") do
    options[:strict_hard] = true
  end
  opts.on("--hard-only", "Show only hard findings") do
    options[:hard_only] = true
  end
  opts.on("--triage PATH", "Use a TSV triage manifest") do |value|
    options[:triage_path] = value
  end
  opts.on("--show-triaged", "Show findings accepted by the triage manifest") do
    options[:show_triaged] = true
  end
end.parse!

STOP_WORDS = Set.new(%w[
  about across after against already also and any are ask asks automated
  before between both but can choosing codex code commit commits common
  debug debugging decisions edit edits especially etc every file files for
  from general github guidance harden help including into issue issues its
  local maintain maintenance merge needs other package packages path pull
  repository requests review run scripts should skill skills source specific
  test tests that the their them this through tool tools update use used uses
  user when whenever where with workflow workflows work working
])

COMMAND_PATTERNS = {
  "actionlint" => /\bactionlint\b/,
  "zizmor or uvx zizmor" => /\b(?:uvx\s+)?zizmor\b/,
  "lintr::lint_package" => /lintr::lint_package/,
  "Rcpp::compileAttributes" => /Rcpp::compileAttributes/,
  "roxygen2::roxygenise" => /roxygen2::roxygenise/,
  "Rscript -e" => /Rscript(?:\s+--vanilla)?\s+-e/,
  "devtools::check" => /devtools::check/,
  "persist-credentials" => /persist-credentials:\s*false/
}.freeze

FUNCTION_PATTERNS = [
  [/\.sh\z/, /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{/],
  [/\.R\z/, /^\s*([A-Za-z.][A-Za-z0-9_.]*)\s*<-\s*function\s*\(/],
  [/\.rb\z/, /^\s*def\s+([A-Za-z_][A-Za-z0-9_?!]*)\b/],
  [/\.py\z/, /^\s*def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/]
].freeze

IGNORED_DUPLICATE_HELPERS = Set.new(%w[
  main
  parse_args
  usage
])

SKILL_SCRIPT_PATH_PATTERN = %r{(?:[.]/)?skills/[A-Za-z0-9._-]+/scripts/[A-Za-z0-9._/-]+}.freeze
SOURCE_REPO_CONTEXT_PATTERN = /\b(?:source repo|source repository|source tree|repository root|from this repo)\b/i

def read_text(path)
  File.read(path, encoding: "UTF-8", invalid: :replace, undef: :replace)
end

def relative_path(repo_dir, path)
  path.delete_prefix("#{repo_dir}/")
end

def frontmatter(path)
  yaml = read_text(path).split(/^---\s*$/, 3)[1]
  yaml ? YAML.safe_load(yaml) : {}
end

def line_hits(repo_dir, files, pattern)
  hits = []
  files.each do |path|
    read_text(path).each_line.with_index(1) do |line, line_no|
      next unless line.match?(pattern)

      hits << [relative_path(repo_dir, path), line_no, line.strip]
    end
  end
  hits
end

def load_triage_entries(path)
  return [] unless File.file?(path)

  entries = []
  read_text(path).each_line.with_index(1) do |line, line_no|
    row = line.chomp
    next if row.empty? || row.start_with?("#")

    section, pattern, rationale = row.split("\t", 3)
    if [section, pattern, rationale].any? { |field| field.nil? || field.empty? }
      raise ArgumentError, "#{path}:#{line_no}: expected section<TAB>pattern<TAB>rationale"
    end

    entries << {
      section: section,
      pattern: pattern,
      rationale: rationale
    }
  end
  entries
end

def triage_entry(entries, section, row)
  entries.find { |entry|
    (entry[:section] == "*" || entry[:section] == section) &&
      row.include?(entry[:pattern])
  }
end

def record_findings(findings, triaged_findings, triage_entries, severity, section, rows)
  rows.each do |row|
    entry = triage_entry(triage_entries, section, row)
    if entry
      triaged_findings << "#{section}: #{row} [#{entry[:rationale]}]"
    else
      findings.fetch(severity)[section] << row
    end
  end
end

def executable_skill_script_command?(line)
  stripped = line.strip.sub(/\A[$>]\s*/, "")
  return false if stripped.include?("${CODEX_HOME")
  return false unless stripped.match?(SKILL_SCRIPT_PATH_PATTERN)
  return true if stripped.start_with?("./skills/", "skills/")

  stripped.match?(
    %r{\A(?:env\s+)?(?:bash|sh|ruby|python3?|Rscript(?:\s+--vanilla)?)\s+(?:[.]/)?skills/}
  )
end

def source_repo_context?(lines, index)
  start_index = [index - 4, 0].max
  lines[start_index...index].join(" ").match?(SOURCE_REPO_CONTEXT_PATTERN)
end

def installed_breaking_command_rows(repo_dir, files)
  rows = []
  files.each do |path|
    lines = read_text(path).lines
    lines.each_with_index do |line, index|
      next unless executable_skill_script_command?(line)
      next if source_repo_context?(lines, index)

      rows << "#{relative_path(repo_dir, path)}:#{index + 1}: #{line.strip}"
    end
  end
  rows
end

def description_tokens(text)
  text.downcase.scan(/[a-z][a-z0-9]+/).reject { |word|
    word.length < 4 || STOP_WORDS.include?(word)
  }.to_set
end

def script_function_definitions(repo_dir, script_files)
  definitions = Hash.new { |hash, key| hash[key] = [] }
  script_files.each do |path|
    matcher = FUNCTION_PATTERNS.find { |extension, _pattern| path.match?(extension) }
    next unless matcher

    _extension, pattern = matcher
    read_text(path).each_line.with_index(1) do |line, line_no|
      match = line.match(pattern)
      next unless match

      name = match[1]
      next if IGNORED_DUPLICATE_HELPERS.include?(name)

      definitions[name] << [relative_path(repo_dir, path), line_no]
    end
  end
  definitions.select { |_name, hits| hits.map(&:first).uniq.length > 1 }
end

def print_findings(title, sections)
  count = sections.values.sum(&:length)
  return 0 if count.zero?

  puts
  puts "#{title}:"
  sections.each do |section, rows|
    next if rows.empty?

    puts "  #{section}:"
    rows.each { |row| puts "    #{row}" }
  end
  count
end

skill_dirs = Dir.glob(File.join(repo_dir, "skills", "*")).select { |path|
  File.directory?(path)
}.sort

skills = skill_dirs.map do |skill_dir|
  skill_name = File.basename(skill_dir)
  skill_file = File.join(skill_dir, "SKILL.md")
  frontmatter_data = frontmatter(skill_file)
  skill_body = read_text(skill_file)

  {
    name: skill_name,
    description: frontmatter_data.fetch("description", ""),
    skill_lines: skill_body.lines.length,
    token_set: description_tokens(frontmatter_data.fetch("description", ""))
  }
end

markdown_files = Dir.glob([
  File.join(repo_dir, "README.md"),
  File.join(repo_dir, "AGENTS.md"),
  File.join(repo_dir, "prompts", "**", "*.md"),
  File.join(repo_dir, "skills", "**", "*.md")
]).select { |path| File.file?(path) }.sort

script_files = Dir.glob([
  File.join(repo_dir, "scripts", "*"),
  File.join(repo_dir, "install.sh"),
  File.join(repo_dir, "skills", "**", "scripts", "*")
]).select { |path| File.file?(path) }.sort

all_review_files = (markdown_files + script_files).uniq
skill_markdown_files = markdown_files.select { |path|
  path.start_with?(File.join(repo_dir, "skills", ""))
}
triage_entries = load_triage_entries(options[:triage_path])
findings = {
  hard: Hash.new { |hash, key| hash[key] = [] },
  review: Hash.new { |hash, key| hash[key] = [] },
  info: Hash.new { |hash, key| hash[key] = [] }
}
triaged_findings = []

total_description_chars = skills.sum { |skill| skill[:description].length }
puts "Skill Drift Audit"
puts "Skills: #{skills.length}"
puts "Always-loaded description budget: #{total_description_chars} characters (~#{(total_description_chars / 4.0).round} tokens)"

if total_description_chars > options[:max_total_description]
  record_findings(
    findings,
    triaged_findings,
    triage_entries,
    :info,
    "Description Budget",
    ["total description text exceeds #{options[:max_total_description]} characters"]
  )
end

long_description_rows = skills.select { |skill|
  skill[:description].length > options[:max_description]
}.map { |skill|
  "#{skill[:name]}: #{skill[:description].length} chars"
}
record_findings(findings, triaged_findings, triage_entries, :info, "Long Descriptions", long_description_rows)

long_skill_rows = skills.select { |skill| skill[:skill_lines] > 200 }.map { |skill|
  "#{skill[:name]}: #{skill[:skill_lines]} SKILL.md lines"
}
record_findings(findings, triaged_findings, triage_entries, :info, "Large Always-Read Skill Files", long_skill_rows)

overlap_rows = []
skills.combination(2) do |left, right|
  union = left[:token_set] | right[:token_set]
  next if union.empty?

  overlap = ((left[:token_set] & right[:token_set]).length.to_f / union.length)
  next if overlap < options[:overlap_threshold]

  overlap_rows << format(
    "%s <-> %s: %.2f token overlap",
    left[:name],
    right[:name],
    overlap
  )
end
record_findings(findings, triaged_findings, triage_entries, :review, "Description Overlap", overlap_rows.sort)

duplicate_helper_rows = script_function_definitions(repo_dir, script_files).sort.map do |name, hits|
  locations = hits.map { |path, line_no| "#{path}:#{line_no}" }.join(", ")
  "#{name}: #{locations}"
end
record_findings(findings, triaged_findings, triage_entries, :review, "Repeated Helper Names", duplicate_helper_rows)

repeated_command_rows = COMMAND_PATTERNS.filter_map do |label, pattern|
  hits = line_hits(repo_dir, markdown_files, pattern)
  next if hits.map(&:first).uniq.length < 3

  "#{label}: #{hits.length} hits in #{hits.map(&:first).uniq.length} files"
end
record_findings(findings, triaged_findings, triage_entries, :review, "Repeated Command Guidance", repeated_command_rows)

machine_path_rows = line_hits(repo_dir, all_review_files, %r{/(?:home|Users)/james|/mnt/[A-Za-z]/}).map { |path, line_no, line|
  "#{path}:#{line_no}: #{line}"
}
record_findings(findings, triaged_findings, triage_entries, :review, "Machine-Specific Paths", machine_path_rows)

installed_command_rows = installed_breaking_command_rows(repo_dir, skill_markdown_files)
record_findings(
  findings,
  triaged_findings,
  triage_entries,
  :hard,
  "Installed-Breaking Skill Script Commands",
  installed_command_rows
)

repo_relative_helper_rows = line_hits(
  repo_dir,
  markdown_files,
  %r{\bskills/[A-Za-z0-9._-]+/scripts/[A-Za-z0-9._/-]+}
).reject { |_path, _line_no, line|
  line.include?("${CODEX_HOME")
}.map { |path, line_no, line|
  "#{path}:#{line_no}: #{line}"
}
record_findings(
  findings,
  triaged_findings,
  triage_entries,
  :review,
  "Repo-Relative Skill Script References",
  repo_relative_helper_rows
)

hard_count = findings.fetch(:hard).values.sum(&:length)
review_count = findings.fetch(:review).values.sum(&:length)
info_count = findings.fetch(:info).values.sum(&:length)
active_count = hard_count + review_count + info_count

if options[:hard_only]
  print_findings("Hard Findings", findings.fetch(:hard))
elsif active_count.positive?
  print_findings("Hard Findings", findings.fetch(:hard))
  print_findings("Review Findings", findings.fetch(:review))
  print_findings("Informational Findings", findings.fetch(:info))
end

if options[:show_triaged] && triaged_findings.any?
  puts
  puts "Triaged Findings:"
  triaged_findings.each { |row| puts "  #{row}" }
elsif triaged_findings.any? && !options[:hard_only]
  puts
  puts "Triaged findings: #{triaged_findings.length} accepted by #{relative_path(repo_dir, options[:triage_path])}"
end

if options[:hard_only] && hard_count.zero?
  puts
  puts "No hard drift findings."
elsif active_count.zero?
  puts
  puts "No untriaged drift findings."
else
  puts
  puts "Hard findings: #{hard_count}"
  puts "Review findings: #{review_count}"
  puts "Informational findings: #{info_count}"
  puts "Default mode is advisory. Re-run with --strict-hard to fail on hard findings."
  puts "Use --strict when a cleanup branch should fail on any untriaged finding."
end

exit(1) if options[:strict_hard] && hard_count.positive?
exit(1) if options[:strict] && active_count.positive?

exit(0)
