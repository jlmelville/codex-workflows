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

require "cgi"
require "uri"

def usage(io)
  io.puts("Usage: validate-markdown-references.rb [REPOSITORY]")
end

if ARGV == ["-h"] || ARGV == ["--help"]
  usage($stdout)
  exit 0
end

if ARGV.length > 1
  warn "validate-markdown-references.rb: expected at most one repository path"
  usage($stderr)
  exit 2
end

if ARGV.first&.start_with?("-")
  warn "validate-markdown-references.rb: unknown option: #{ARGV.first}"
  usage($stderr)
  exit 2
end

repo_dir = File.expand_path(ARGV.fetch(0, File.expand_path("..", __dir__)))
unless Dir.exist?(repo_dir)
  warn "validate-markdown-references.rb: repository not found: #{repo_dir}"
  usage($stderr)
  exit 2
end

skills_dir = File.join(repo_dir, "skills")
skill_names = if Dir.exist?(skills_dir)
  Dir.children(skills_dir).select do |name|
    File.directory?(File.join(skills_dir, name))
  end
else
  []
end

markdown_files = Dir.glob([
  File.join(repo_dir, "README.md"),
  File.join(repo_dir, "AGENTS.md"),
  File.join(repo_dir, "docs", "**", "*.md"),
  File.join(repo_dir, "prompts", "**", "*.md"),
  File.join(repo_dir, "skills", "**", "*.md")
]).sort.uniq

def github_heading_slug(heading)
  text = heading
    .gsub(/!\[([^\]]*)\]\([^)]+\)/, "\\1")
    .gsub(/\[([^\]]+)\]\([^)]+\)/, "\\1")
    .gsub(/<[^>]+>/, "")
    .delete("`")
  text = CGI.unescapeHTML(text).strip.downcase
  text
    .gsub(/[\u2000-\u206f\u2e00-\u2e7f\\'!"#\$%&()*+,.\/:;<=>?@\[\]^`{|}~]/, "")
    .gsub(/[[:space:]]+/, "-")
end

def markdown_anchors(path)
  text = File.read(path, encoding: "UTF-8")
  anchors = text.scan(/<(?:a\s+[^>]*(?:id|name)|[A-Za-z][^>]*\sid)=["']([^"']+)["'][^>]*>/i)
    .flatten
    .to_set
  slug_counts = Hash.new(0)

  text.each_line do |line|
    match = line.chomp.match(/\A {0,3}(#+)[ \t]+(.+?)[ \t]*#*[ \t]*\z/)
    next unless match && match[1].length <= 6

    slug = github_heading_slug(match[2])
    next if slug.empty?

    count = slug_counts[slug]
    anchors << (count.zero? ? slug : "#{slug}-#{count}")
    slug_counts[slug] += 1
  end

  anchors
end

anchor_cache = {}
status = 0

markdown_files.each do |path|
  text = File.read(path, encoding: "UTF-8")
  rel_path = path.delete_prefix("#{repo_dir}/")

  text.scan(/\[[^\]\n]+\]\(([^)\s]+)(?:\s+[^)]*)?\)/).each do |match|
    target = match.fetch(0)
    next if target.match?(/\A[A-Za-z][A-Za-z0-9+.-]*:/)

    target_path, fragment = target.split("#", 2)
    decoded_path = URI::DEFAULT_PARSER.unescape(target_path)
    resolved = if decoded_path.empty?
      path
    else
      File.expand_path(decoded_path, File.dirname(path))
    end

    unless File.exist?(resolved)
      warn "#{rel_path}: markdown link target not found: #{target}"
      status = 1
      next
    end

    next if fragment.nil? || fragment.empty? || File.extname(resolved).downcase != ".md"

    decoded_fragment = URI::DEFAULT_PARSER.unescape(fragment)
    anchors = anchor_cache.fetch(resolved) do
      anchor_cache[resolved] = markdown_anchors(resolved)
    end
    unless anchors.include?(decoded_fragment)
      warn "#{rel_path}: markdown link fragment not found: #{target}"
      status = 1
    end
  end

  text.scan(/\$([a-z][a-z0-9]*(?:-[a-z0-9]+)*)/).each do |match|
    skill_ref = match.fetch(0)
    next if skill_ref == "skill-name"
    next if !skill_ref.include?("-") && !skill_names.include?(skill_ref)

    unless skill_names.include?(skill_ref)
      warn "#{rel_path}: unknown skill reference $#{skill_ref}"
      status = 1
    end
  end

  text.scan(/\bskills\/[A-Za-z0-9._-]+(?:\/[A-Za-z0-9._-]+)*[A-Za-z0-9_-]/).each do |target|
    resolved = File.join(repo_dir, target)
    unless File.exist?(resolved)
      warn "#{rel_path}: repo path not found: #{target}"
      status = 1
    end
  end
end

exit(status)
