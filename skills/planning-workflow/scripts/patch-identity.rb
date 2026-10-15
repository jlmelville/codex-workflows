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

  def normalize_path(raw, root, label: "untracked")
    path = Pathname.new(raw)
    raise Error, "#{label} path must be repository-relative: #{raw.inspect}" if path.absolute?

    clean = path.cleanpath.to_s
    resolved = File.expand_path(clean, root)
    prefix = root.end_with?(File::SEPARATOR) ? root : "#{root}#{File::SEPARATOR}"
    unless resolved.start_with?(prefix) && clean != "."
      raise Error, "#{label} path escapes the repository: #{raw.inspect}"
    end
    Pathname.new(resolved).relative_path_from(Pathname.new(root)).to_s
  end

  def classify_paths(values, label, root, available, available_label: "an untracked file")
    normalized = values.map { |path| normalize_path(path, root) }
    counts = Hash.new(0)
    normalized.each { |path| counts[path] += 1 }
    duplicate = counts.find { |_path, count| count > 1 }&.first
    raise Error, "duplicate #{label} path: #{duplicate.inspect}" if duplicate

    unknown = normalized.reject { |path| available.include?(path) }
    unless unknown.empty?
      raise Error, "#{label} path is not #{available_label}: #{unknown.first.inspect}"
    end
    normalized
  end

  def render_path(path)
    path.encode("UTF-8", invalid: :replace, undef: :replace).inspect
  end

  def scoped_untracked(root, scopes, pathspecs, include_ignored_paths, exclude_ignored_paths)
    untracked = capture("git", "ls-files", "--others", "--exclude-standard", "-z", "--", *pathspecs)
      .split("\0").sort
    ignored = capture("git", "ls-files", "--others", "--ignored", "--exclude-standard", "-z", "--", *pathspecs)
      .split("\0").sort
    tracked = capture("git", "ls-files", "--cached", "-z", "--", *pathspecs).split("\0")
    available = tracked + untracked + ignored
    scopes.each do |scope|
      unless available.any? { |path| path == scope || path.start_with?("#{scope}/") }
        raise Error, "scope matches no files: #{scope.inspect}"
      end
    end

    included = classify_paths(include_ignored_paths, "included ignored", root, ignored,
      available_label: "an ignored file inside scope")
    excluded = classify_paths(exclude_ignored_paths, "excluded ignored", root, ignored,
      available_label: "an ignored file inside scope")
    conflict = included & excluded
    unless conflict.empty?
      raise Error, "ignored path is both included and excluded: #{conflict.first.inspect}"
    end
    unclassified = ignored - included - excluded
    unless unclassified.empty?
      raise Error, "unclassified ignored path inside scope: #{unclassified.first.inspect}; use --include-ignored or --exclude-ignored"
    end
    [untracked + included, included, excluded]
  end

  def run(include_paths:, exclude_paths:, scope_paths: [], include_ignored_paths: [], exclude_ignored_paths: [])
    root = capture("git", "rev-parse", "--show-toplevel").strip
    baseline = capture("git", "rev-parse", "HEAD").strip
    scopes = scope_paths.map { |path| normalize_path(path, root, label: "scope") }.uniq.sort
    pathspecs = scopes.map { |scope| ":(top,literal)#{scope}" }

    Dir.chdir(root) do
      _stdout, stderr, status = Open3.capture3("git", "diff", "--cached", "--quiet", "--exit-code")
      if status.exitstatus == 1
        raise Error, "the index is not clean; unstaged identity requires HEAD as its exact baseline"
      end
      raise Error, "git diff --cached failed: #{stderr.strip}" unless status.success?

      included_ignored = []
      excluded_ignored = []
      excluded = []
      if scopes.empty?
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
      else
        included, included_ignored, excluded_ignored = scoped_untracked(
          root, scopes, pathspecs, include_ignored_paths, exclude_ignored_paths
        )
      end

      tracked_paths = capture("git", "diff", "--name-only", "--no-ext-diff", "-z", "--", *pathspecs).split("\0")
      tracked_patch = capture(
        "git", "diff", "--binary", "--no-ext-diff", "--full-index", "--no-color",
        "--src-prefix=a/", "--dst-prefix=b/", "--", *pathspecs
      )
      digest = Digest::SHA256.new
      unless scopes.empty?
        digest.update("scoped-patch-identity-v1\0")
        {
          "baseline" => [baseline], "scopes" => scopes,
          "include_ignored" => included_ignored.sort, "exclude_ignored" => excluded_ignored.sort
        }.each do |field, paths|
          digest.update("#{field}\0#{paths.length}\0")
          paths.each { |path| digest.update(path.b + "\0") }
        end
      end
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
      scopes.each { |scope| warn "scope: #{render_path(scope)}" }
      warn "tracked paths: #{tracked_paths.length}"
      included.sort.each do |path|
        label = included_ignored.include?(path) ? "included ignored" : "included untracked"
        warn "#{label}: #{render_path(path)}"
      end
      excluded.sort.each { |path| warn "excluded untracked: #{render_path(path)}" }
      excluded_ignored.sort.each { |path| warn "excluded ignored: #{render_path(path)}" }
      puts digest.hexdigest
    end
  end
end

options = {include_paths: [], exclude_paths: [], scope_paths: [], include_ignored_paths: [], exclude_ignored_paths: []}
parser = OptionParser.new do |opts|
  opts.banner = "Usage: patch-identity.rb [options]"
  opts.separator "Default: classify every nonignored untracked file; hash the complete tracked patch."
  opts.separator "Scoped: hash only literal files/directories; automatically include new nonignored files."
  opts.separator "Both modes require a clean index. Scoped identity binds HEAD, scope, and ignored-file decisions."
  opts.on("--scope PATH", "Review a repository-relative file or directory; repeat as needed") do |path|
    options[:scope_paths] << path
  end
  opts.on("--include-untracked PATH", "Include an untracked file; repeat as needed") do |path|
    options[:include_paths] << path
  end
  opts.on("--exclude-untracked PATH", "Classify an out-of-scope untracked file") do |path|
    options[:exclude_paths] << path
  end
  opts.on("--include-ignored PATH", "Scoped only: hash an ignored file inside the declared scope") do |path|
    options[:include_ignored_paths] << path
  end
  opts.on("--exclude-ignored PATH", "Scoped only: explicitly omit an ignored file inside the scope") do |path|
    options[:exclude_ignored_paths] << path
  end
  opts.on("-h", "--help", "Show this help") do
    puts opts
    exit 0
  end
end

begin
  parser.parse!
  raise OptionParser::InvalidArgument, "unexpected argument: #{ARGV.first}" unless ARGV.empty?
  if options[:scope_paths].empty?
    unless options[:include_ignored_paths].empty? && options[:exclude_ignored_paths].empty?
      raise OptionParser::InvalidArgument, "ignored-file flags require --scope"
    end
  elsif !options[:include_paths].empty? || !options[:exclude_paths].empty?
    raise OptionParser::InvalidArgument, "--scope cannot mix with --include-untracked or --exclude-untracked"
  end

  PatchIdentity.run(**options)
rescue OptionParser::ParseError => e
  warn "patch-identity.rb: #{e.message}"
  warn parser
  exit 2
rescue PatchIdentity::Error => e
  warn "patch-identity.rb: #{e.message}"
  exit 1
end
