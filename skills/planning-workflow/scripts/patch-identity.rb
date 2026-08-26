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

require "digest"
require "open3"
require "optparse"
require "pathname"

module PatchIdentity
  class Error < StandardError; end

  module_function

  def capture(*command, accepted: [0])
    stdout, stderr, status = Open3.capture3(*command)
    unless accepted.include?(status.exitstatus)
      detail = stderr.strip
      detail = "command exited #{status.exitstatus}" if detail.empty?
      raise Error, "#{command.first}: #{detail}"
    end
    stdout.b
  end

  def normalize_path(raw, root)
    path = Pathname.new(raw)
    raise Error, "untracked path must be repository-relative: #{raw.inspect}" if path.absolute?

    clean = path.cleanpath.to_s
    resolved = File.expand_path(clean, root)
    prefix = root.end_with?(File::SEPARATOR) ? root : "#{root}#{File::SEPARATOR}"
    unless resolved.start_with?(prefix) && clean != "."
      raise Error, "untracked path escapes the repository: #{raw.inspect}"
    end
    Pathname.new(resolved).relative_path_from(Pathname.new(root)).to_s
  end

  def classify_paths(values, label, root, available)
    normalized = values.map { |path| normalize_path(path, root) }
    counts = Hash.new(0)
    normalized.each { |path| counts[path] += 1 }
    duplicate = counts.find { |_path, count| count > 1 }&.first
    raise Error, "duplicate #{label} path: #{duplicate.inspect}" if duplicate

    unknown = normalized.reject { |path| available.include?(path) }
    unless unknown.empty?
      raise Error, "#{label} path is not an untracked file: #{unknown.first.inspect}"
    end
    normalized
  end

  def render_path(path)
    path.encode("UTF-8", invalid: :replace, undef: :replace).inspect
  end

  def run(include_paths:, exclude_paths:)
    root = capture("git", "rev-parse", "--show-toplevel").strip
    baseline = capture("git", "rev-parse", "HEAD").strip

    Dir.chdir(root) do
      _stdout, stderr, status = Open3.capture3("git", "diff", "--cached", "--quiet", "--exit-code")
      if status.exitstatus == 1
        raise Error, "the index is not clean; unstaged identity requires HEAD as its exact baseline"
      end
      raise Error, "git diff --cached failed: #{stderr.strip}" unless status.success?

      untracked = capture("git", "ls-files", "--others", "--exclude-standard", "-z")
        .split("\0")
        .sort
      included = classify_paths(include_paths, "included", root, untracked)
      excluded = classify_paths(exclude_paths, "excluded", root, untracked)
      conflict = included & excluded
      raise Error, "untracked path is both included and excluded: #{conflict.first.inspect}" unless conflict.empty?

      uncategorized = untracked - included - excluded
      unless uncategorized.empty?
        raise Error, "uncategorized untracked path: #{uncategorized.first.inspect}"
      end

      tracked_paths = capture("git", "diff", "--name-only", "--no-ext-diff", "-z").split("\0")
      tracked_patch = capture(
        "git", "diff", "--binary", "--no-ext-diff", "--full-index", "--no-color",
        "--src-prefix=a/", "--dst-prefix=b/"
      )
      digest = Digest::SHA256.new
      digest.update(tracked_patch)

      included.sort.each do |path|
        patch = capture(
          "git", "diff", "--no-index", "--binary", "--no-ext-diff", "--full-index", "--no-color",
          "--src-prefix=a/", "--dst-prefix=b/", "--", File::NULL, path,
          accepted: [0, 1]
        )
        raise Error, "untracked path produced no patch: #{path.inspect}" if patch.empty?
        digest.update(patch)
      end

      raise Error, "working patch is empty" if tracked_patch.empty? && included.empty?

      warn "baseline: #{baseline}"
      warn "tracked paths: #{tracked_paths.length}"
      included.sort.each { |path| warn "included untracked: #{render_path(path)}" }
      excluded.sort.each { |path| warn "excluded untracked: #{render_path(path)}" }
      puts digest.hexdigest
    end
  end
end

options = {include_paths: [], exclude_paths: []}
parser = OptionParser.new do |opts|
  opts.banner = "Usage: patch-identity.rb [options]"
  opts.on("--include-untracked PATH", "Include an untracked file; repeat as needed") do |path|
    options[:include_paths] << path
  end
  opts.on("--exclude-untracked PATH", "Classify an out-of-scope untracked file") do |path|
    options[:exclude_paths] << path
  end
  opts.on("-h", "--help", "Show this help") do
    puts opts
    exit 0
  end
end

begin
  parser.parse!
  raise OptionParser::InvalidArgument, "unexpected argument: #{ARGV.first}" unless ARGV.empty?

  PatchIdentity.run(**options)
rescue OptionParser::ParseError => e
  warn "patch-identity.rb: #{e.message}"
  warn parser
  exit 2
rescue PatchIdentity::Error => e
  warn "patch-identity.rb: #{e.message}"
  exit 1
end
