#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "set"
require "yaml"

repo_dir = File.expand_path("..", __dir__)
options = {
  max_description: 420,
  max_total_description: 6_000,
  max_skill_lines: 160,
  overlap_threshold: 0.20,
  strict: false,
  strict_hard: false,
  hard_only: false,
  show_triaged: false,
  triage_explicit: false,
  triage_path: File.join(repo_dir, "scripts", "audit-skill-drift-triage.tsv"),
  command_baseline_path: File.join(repo_dir, "scripts", "audit-skill-drift-command-baseline.tsv")
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: audit-skill-drift.rb [options]"
  opts.on("--max-description N", Integer, "Flag descriptions longer than N characters") do |value|
    options[:max_description] = value
  end
  opts.on("--max-total-description N", Integer, "Flag total description budget above N characters") do |value|
    options[:max_total_description] = value
  end
  opts.on("--max-skill-lines N", Integer, "Flag SKILL.md files longer than N lines") do |value|
    options[:max_skill_lines] = value
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
    options[:triage_explicit] = true
    options[:triage_path] = value
  end
  opts.on("--command-baseline PATH", "Use a repeated-command baseline TSV") do |value|
    options[:command_baseline_path] = value
  end
  opts.on("--show-triaged", "Show findings accepted by the triage manifest") do
    options[:show_triaged] = true
  end
end

begin
  parser.parse!
rescue OptionParser::ParseError => e
  warn "audit-skill-drift.rb: #{e.message}"
  warn parser
  exit 2
end

unless ARGV.empty?
  warn "audit-skill-drift.rb: unexpected argument: #{ARGV.first}"
  warn parser
  exit 2
end

if options[:triage_explicit] && !File.file?(options[:triage_path])
  warn "audit-skill-drift.rb: triage manifest not found: #{options[:triage_path]}"
  exit 1
end

unless File.file?(options[:command_baseline_path])
  warn "audit-skill-drift.rb: command baseline not found: #{options[:command_baseline_path]}"
  exit 1
end

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

MAX_COMMAND_GROWTH_PATHS = 5

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

SKILL_SCRIPT_PATH_PATTERN = %r{(?:[.]/)?skills/[A-Za-z0-9._-]+/scripts/[A-Za-z0-9._/-]+}
SKILL_DIR_PLACEHOLDER_PATTERN = %r{<skill-dir>/scripts/[A-Za-z0-9._/-]+}
BARE_SCRIPT_PATH_PATTERN = %r{\bscripts/([A-Za-z0-9._/-]*[A-Za-z0-9_/-])}
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
      rationale: rationale,
      line_no: line_no,
      used: false
    }
  end
  entries
end

def load_command_baselines(path, known_labels)
  baselines = Hash.new { |hash, key| hash[key] = {} }
  read_text(path).each_line.with_index(1) do |line, line_no|
    row = line.chomp
    next if row.empty? || row.start_with?("#")

    label, relative_path, count_text = row.split("\t", -1)
    if [label, relative_path, count_text].any? { |field| field.nil? || field.empty? }
      raise ArgumentError, "#{path}:#{line_no}: expected command<TAB>path<TAB>hit-count"
    end
    unless known_labels.include?(label)
      raise ArgumentError, "#{path}:#{line_no}: unknown command label: #{label}"
    end
    unless relative_path.match?(%r{\A[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*\z})
      raise ArgumentError, "#{path}:#{line_no}: expected a normalized repository-relative path"
    end

    begin
      count = Integer(count_text, 10)
    rescue ArgumentError
      raise ArgumentError, "#{path}:#{line_no}: hit-count must be a positive integer"
    end
    if count <= 0
      raise ArgumentError, "#{path}:#{line_no}: hit-count must be a positive integer"
    end
    if baselines[label].key?(relative_path)
      raise ArgumentError, "#{path}:#{line_no}: duplicate command and path"
    end

    baselines[label][relative_path] = count
  end
  baselines
end

def validate_command_baseline_triage(triage_entries, command_baselines, known_labels)
  triaged_labels = triage_entries.filter_map do |entry|
    next unless entry[:section] == "Repeated Command Guidance"

    known_labels.find { |label| entry[:pattern] == "#{label}:" }
  end.to_set
  baseline_labels = command_baselines.keys.to_set
  missing_baselines = (triaged_labels - baseline_labels).sort
  untriaged_baselines = (baseline_labels - triaged_labels).sort
  return if missing_baselines.empty? && untriaged_baselines.empty?

  details = []
  details << "missing baselines: #{missing_baselines.join(", ")}" if missing_baselines.any?
  details << "untriaged baselines: #{untriaged_baselines.join(", ")}" if untriaged_baselines.any?
  raise ArgumentError, "repeated-command baseline and triage labels differ; #{details.join("; ")}"
end

def repeated_command_growth_rows(command_hits, command_baselines)
  command_baselines.sort.filter_map do |label, baseline_counts|
    current_counts = Hash.new(0)
    command_hits.fetch(label, []).each do |path, _line_no, _line|
      current_counts[path] += 1
    end

    growth = current_counts.filter_map do |path, count|
      baseline_count = baseline_counts.fetch(path, 0)
      next unless count > baseline_count

      [path, count - baseline_count, baseline_count.zero?]
    end
    next if growth.empty?

    growth.sort_by! { |path, delta, _new_path| [-delta, path] }
    shown = growth.first(MAX_COMMAND_GROWTH_PATHS).map do |path, delta, new_path|
      new_path ? "#{path} new (+#{delta})" : "#{path} +#{delta}"
    end
    omitted = growth.length - shown.length
    shown << "+#{omitted} more paths" if omitted.positive?
    added_hits = growth.sum { |_path, delta, _new_path| delta }

    "#{label}: +#{added_hits} baseline-relative hits across #{growth.length} paths; #{shown.join("; ")}"
  end
end

def triage_entry(entries, section, row)
  entry = entries.find { |candidate|
    (candidate[:section] == "*" || candidate[:section] == section) &&
      row.include?(candidate[:pattern])
  }
  entry[:used] = true if entry
  entry
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
  return false if stripped.include?("${CODEX_HOME") || stripped.include?("${HOME}/.agents/skills")
  return false unless stripped.match?(SKILL_SCRIPT_PATH_PATTERN)
  return true if stripped.start_with?("./skills/", "skills/")

  stripped.match?(
    %r{\A(?:env\s+)?(?:bash|sh|ruby|python3?|Rscript(?:\s+--vanilla)?)\s+(?:[.]/)?skills/}
  )
end

def source_repo_context?(lines, index)
  start_index = [index - 4, 0].max
  context = lines[start_index...index].join(" ").gsub(/\s+/, " ")
  context.match?(SOURCE_REPO_CONTEXT_PATTERN)
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

def ambiguous_bundled_script_rows(repo_dir, files)
  rows = []
  files.each do |path|
    relative = relative_path(repo_dir, path)
    skill_match = relative.match(%r{\Askills/([^/]+)/})
    next unless skill_match

    skill_dir = File.join(repo_dir, "skills", skill_match[1])
    lines = read_text(path).lines
    lines.each_with_index do |line, index|
      if line.match?(SKILL_DIR_PLACEHOLDER_PATTERN)
        rows << "#{relative}:#{index + 1}: #{line.strip}"
        next
      end

      next if line.include?("${CODEX_HOME") || line.include?("${HOME}/.agents/skills")
      next if source_repo_context?(lines, index)

      bundled_reference = line.scan(BARE_SCRIPT_PATH_PATTERN).flatten.find { |script_path|
        File.file?(File.join(skill_dir, "scripts", script_path))
      }
      next unless bundled_reference

      rows << "#{relative}:#{index + 1}: #{line.strip}"
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
reference_files = skill_markdown_files.select { |path| path.include?("/references/") }
begin
  triage_entries = load_triage_entries(options[:triage_path])
  command_baselines = load_command_baselines(options[:command_baseline_path], COMMAND_PATTERNS.keys)
  validate_command_baseline_triage(triage_entries, command_baselines, COMMAND_PATTERNS.keys)
rescue ArgumentError, Errno::EACCES => e
  warn "audit-skill-drift.rb: #{e.message}"
  exit 1
end
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
reference_lines = reference_files.sum { |path| read_text(path).lines.length }
reference_words = reference_files.sum { |path| read_text(path).scan(/\S+/).length }
puts "Routed references: #{reference_files.length} files, #{reference_lines} lines, ~#{reference_words} words"

command_hits = COMMAND_PATTERNS.transform_values do |pattern|
  line_hits(repo_dir, markdown_files, pattern)
end
command_growth_rows = repeated_command_growth_rows(command_hits, command_baselines)
stable_command_baselines = command_baselines.length - command_growth_rows.length
puts "Repeated command baselines: #{stable_command_baselines} stable, #{command_growth_rows.length} expanded"

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

long_skill_rows = skills.select { |skill| skill[:skill_lines] > options[:max_skill_lines] }.map { |skill|
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

repeated_command_rows = command_hits.filter_map do |label, hits|
  next if hits.map(&:first).uniq.length < 3

  "#{label}: #{hits.length} hits in #{hits.map(&:first).uniq.length} files"
end
record_findings(findings, triaged_findings, triage_entries, :review, "Repeated Command Guidance", repeated_command_rows)
record_findings(
  findings,
  triaged_findings,
  triage_entries,
  :review,
  "Repeated Command Growth",
  command_growth_rows
)

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

ambiguous_script_rows = ambiguous_bundled_script_rows(repo_dir, skill_markdown_files)
record_findings(
  findings,
  triaged_findings,
  triage_entries,
  :hard,
  "Ambiguous Bundled Skill Script References",
  ambiguous_script_rows
)

repo_relative_helper_rows = line_hits(
  repo_dir,
  markdown_files,
  %r{\bskills/[A-Za-z0-9._-]+/scripts/[A-Za-z0-9._/-]+}
).reject { |_path, _line_no, line|
  line.include?("${CODEX_HOME") || line.include?("${HOME}/.agents/skills")
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

unused_triage_rows = triage_entries.reject { |entry| entry[:used] }.map { |entry|
  "#{relative_path(repo_dir, options[:triage_path])}:#{entry[:line_no]}: #{entry[:section]} / #{entry[:pattern]}"
}
findings.fetch(:hard)["Unused Triage Entries"].concat(unused_triage_rows)

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

puts
if options[:hard_only] && hard_count.zero?
  puts "No hard drift findings."
elsif active_count.zero?
  puts "No untriaged drift findings."
else
  puts "Hard findings: #{hard_count}"
  puts "Review findings: #{review_count}"
  puts "Informational findings: #{info_count}"
  puts "Default mode is advisory. Re-run with --strict-hard to fail on hard findings."
  puts "Use --strict when a cleanup branch should fail on any untriaged finding."
end

exit(1) if options[:strict_hard] && hard_count.positive?
exit(1) if options[:strict] && active_count.positive?

exit(0)
