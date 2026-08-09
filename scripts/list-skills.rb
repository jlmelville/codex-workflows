#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "yaml"

repo_dir = File.expand_path("..", __dir__)
format = :tsv

class MetadataError < StandardError; end

parser = OptionParser.new do |opts|
  opts.banner = "Usage: list-skills.rb [--tsv|--markdown]"
  opts.on("--tsv", "Output tab-separated rows (default)") { format = :tsv }
  opts.on("--markdown", "Output a Markdown table") { format = :markdown }
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
      "description_length" => skill.fetch("description", "").length,
      "has_agents_yaml" => File.file?(agents_path),
      "display_name" => interface.fetch("display_name", ""),
      "short_description" => interface.fetch("short_description", ""),
      "default_prompt_mentions_skill" => default_prompt.include?("$#{skill_name}"),
      "reference_count" => count_files(File.join(skill_dir, "references")),
      "script_count" => count_files(File.join(skill_dir, "scripts"))
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
]

case format
when :markdown
  puts "| #{headers.join(" | ")} |"
  puts "| #{headers.map { "---" }.join(" | ")} |"
  rows.each do |row|
    puts "| #{headers.map { |header| row.fetch(header).to_s.gsub("|", '\\|') }.join(" | ")} |"
  end
else
  puts headers.join("\t")
  rows.each do |row|
    puts headers.map { |header| row.fetch(header) }.join("\t")
  end
end
