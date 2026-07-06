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
  strict: false
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
  opts.on("--strict", "Exit nonzero when review findings are present") do
    options[:strict] = true
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

def print_section(title, rows)
  return 0 if rows.empty?

  puts
  puts "#{title}:"
  rows.each { |row| puts "  #{row}" }
  rows.length
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
finding_count = 0

total_description_chars = skills.sum { |skill| skill[:description].length }
puts "Skill Drift Audit"
puts "Skills: #{skills.length}"
puts "Always-loaded description budget: #{total_description_chars} characters (~#{(total_description_chars / 4.0).round} tokens)"

if total_description_chars > options[:max_total_description]
  finding_count += print_section(
    "Description Budget",
    ["total description text exceeds #{options[:max_total_description]} characters"]
  )
end

long_description_rows = skills.select { |skill|
  skill[:description].length > options[:max_description]
}.map { |skill|
  "#{skill[:name]}: #{skill[:description].length} chars"
}
finding_count += print_section("Long Descriptions", long_description_rows)

long_skill_rows = skills.select { |skill| skill[:skill_lines] > 200 }.map { |skill|
  "#{skill[:name]}: #{skill[:skill_lines]} SKILL.md lines"
}
finding_count += print_section("Large Always-Read Skill Files", long_skill_rows)

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
finding_count += print_section("Description Overlap", overlap_rows.sort)

duplicate_helper_rows = script_function_definitions(repo_dir, script_files).sort.map do |name, hits|
  locations = hits.map { |path, line_no| "#{path}:#{line_no}" }.join(", ")
  "#{name}: #{locations}"
end
finding_count += print_section("Repeated Helper Names", duplicate_helper_rows)

repeated_command_rows = COMMAND_PATTERNS.filter_map do |label, pattern|
  hits = line_hits(repo_dir, markdown_files, pattern)
  next if hits.map(&:first).uniq.length < 3

  "#{label}: #{hits.length} hits in #{hits.map(&:first).uniq.length} files"
end
finding_count += print_section("Repeated Command Guidance", repeated_command_rows)

machine_path_rows = line_hits(repo_dir, all_review_files, %r{/(?:home|Users)/james|/mnt/[A-Za-z]/}).map { |path, line_no, line|
  "#{path}:#{line_no}: #{line}"
}
finding_count += print_section("Machine-Specific Paths", machine_path_rows)

repo_relative_helper_rows = line_hits(
  repo_dir,
  markdown_files,
  %r{\bskills/[A-Za-z0-9._-]+/scripts/[A-Za-z0-9._/-]+}
).reject { |_path, _line_no, line|
  line.include?("${CODEX_HOME")
}.map { |path, line_no, line|
  "#{path}:#{line_no}: #{line}"
}
finding_count += print_section("Repo-Relative Skill Script References", repo_relative_helper_rows)

if finding_count.zero?
  puts
  puts "No drift review findings."
else
  puts
  puts "Review findings: #{finding_count}"
  puts "Default mode is advisory. Re-run with --strict to make findings exit nonzero."
end

exit(options[:strict] && finding_count.positive? ? 1 : 0)
