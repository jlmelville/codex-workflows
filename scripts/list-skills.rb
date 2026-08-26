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

require "optparse"
require "yaml"

repo_dir = File.expand_path("..", __dir__)
format = :tsv

class MetadataError < StandardError; end

parser = OptionParser.new do |opts|
  opts.banner = "Usage: list-skills.rb [--tsv|--markdown|--catalog]"
  opts.on("--tsv", "Output tab-separated rows (default)") { format = :tsv }
  opts.on("--markdown", "Output a Markdown table") { format = :markdown }
  opts.on("--catalog", "Output a human-facing capability catalog") { format = :catalog }
end

begin
  parser.parse!
rescue OptionParser::ParseError => e
  warn "list-skills.rb: #{e.message}"
  warn parser
  exit 2
end

unless ARGV.empty?
  warn "list-skills.rb: unexpected argument: #{ARGV.first}"
  warn parser
  exit 2
end

def frontmatter(path)
  text = File.read(path, encoding: "UTF-8")
  yaml = text.split(/^---\s*$/, 3)[1]
  return {} unless yaml

  data = YAML.safe_load(yaml)
  raise MetadataError, "#{path}: frontmatter must be a YAML mapping" unless data.is_a?(Hash)

  data
rescue Psych::SyntaxError => e
  raise MetadataError, "#{path}: invalid YAML frontmatter: #{e.message.lines.first.strip}"
end

def load_yaml(path)
  return {} unless File.file?(path)

  data = YAML.safe_load(File.read(path, encoding: "UTF-8"))
  raise MetadataError, "#{path}: YAML must be a mapping" unless data.is_a?(Hash)

  data
rescue Psych::SyntaxError => e
  raise MetadataError, "#{path}: invalid YAML: #{e.message.lines.first.strip}"
end

def count_files(path)
  return 0 unless Dir.exist?(path)

  Dir.glob(File.join(path, "**", "*")).count { |candidate| File.file?(candidate) }
end

def compact_text(value)
  value.to_s.gsub(/\s+/, " ").strip
end

def count_label(count, singular)
  label = (count == 1) ? singular : "#{singular}s"
  "#{count} #{label}"
end

begin
  rows = Dir.glob(File.join(repo_dir, "skills", "*")).select { |path|
    File.directory?(path)
  }.sort.map do |skill_dir|
    skill_name = File.basename(skill_dir)
    skill = frontmatter(File.join(skill_dir, "SKILL.md"))
    agents_path = File.join(skill_dir, "agents", "openai.yaml")
    agents = load_yaml(agents_path)
    interface = agents.fetch("interface", {})
    unless interface.is_a?(Hash)
      raise MetadataError, "#{agents_path}: interface must be a YAML mapping"
    end
    default_prompt = interface.fetch("default_prompt", "")

    {
      "name" => skill_name,
      "description" => compact_text(skill.fetch("description", "")),
      "description_length" => skill.fetch("description", "").length,
      "has_agents_yaml" => File.file?(agents_path),
      "display_name" => compact_text(interface.fetch("display_name", "")),
      "short_description" => compact_text(interface.fetch("short_description", "")),
      "default_prompt" => compact_text(default_prompt),
      "default_prompt_mentions_skill" => default_prompt.include?("$#{skill_name}"),
      "reference_count" => count_files(File.join(skill_dir, "references")),
      "script_count" => count_files(File.join(skill_dir, "scripts")),
      "asset_count" => count_files(File.join(skill_dir, "assets"))
    }
  end
rescue MetadataError, Errno::ENOENT, Errno::EACCES => e
  warn "list-skills.rb: #{e.message}"
  exit 1
end

headers = %w[
  name
  description_length
  has_agents_yaml
  display_name
  short_description
  default_prompt_mentions_skill
  reference_count
  script_count
  asset_count
]

case format
when :markdown
  puts "| #{headers.join(" | ")} |"
  puts "| #{headers.map { "---" }.join(" | ")} |"
  rows.each do |row|
    puts "| #{headers.map { |header| row.fetch(header).to_s.gsub("|", '\\|') }.join(" | ")} |"
  end
when :catalog
  rows.each_with_index do |row, index|
    puts if index.positive?
    puts "#{row.fetch("display_name")} ($#{row.fetch("name")})"
    puts "  Does: #{row.fetch("short_description")}"
    puts "  Use when: #{row.fetch("description")}"
    puts "  Try: #{row.fetch("default_prompt")}"
    includes = [
      count_label(row.fetch("script_count"), "script"),
      count_label(row.fetch("reference_count"), "reference"),
      count_label(row.fetch("asset_count"), "asset")
    ]
    puts "  Includes: #{includes.join(", ")}"
  end
else
  puts headers.join("\t")
  rows.each do |row|
    puts headers.map { |header| row.fetch(header) }.join("\t")
  end
end
