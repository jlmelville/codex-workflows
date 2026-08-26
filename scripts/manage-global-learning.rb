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
require "fileutils"
require "optparse"
require "securerandom"

module GlobalLearning
  START_MARKER = "<!-- codex-workflows:ambient-learning:start -->"
  END_MARKER = "<!-- codex-workflows:ambient-learning:end -->"
  MODES = %w[install check dry-run].freeze
  LEGACY_ASSET_DIGESTS = %w[
    f9fa43121bb2052ed077cff041f5c9e42ae4d39ed5eb274b997b7e9b5b91c6c3
  ].freeze

  class Error < StandardError; end

  # Keyword-only construction is intentional even though Ruby 3.3 also accepts
  # keywords under Struct's default nil mode.
  # standard:disable Style/RedundantStructKeywordInit
  Analysis = Struct.new(:path, :status, :content, :suffix, :mode, keyword_init: true)
  # standard:enable Style/RedundantStructKeywordInit

  module_function

  def canonical_material(asset_path)
    reject_symlink!(asset_path, "canonical asset")
    unless File.file?(asset_path)
      raise Error, "canonical asset is not a regular file: #{asset_path}"
    end

    asset = File.binread(asset_path)
    raise Error, "canonical asset is empty: #{asset_path}" if asset.empty?
    unless asset.end_with?("\n")
      raise Error, "canonical asset must end with a newline: #{asset_path}"
    end
    if asset.include?(START_MARKER) || asset.include?(END_MARKER)
      raise Error, "canonical asset must not contain managed markers: #{asset_path}"
    end

    [asset, "#{START_MARKER}\n#{asset}#{END_MARKER}\n".b]
  end

  def analyze(target_path, asset, canonical)
    reject_symlink!(target_path, "instruction file")
    return Analysis.new(path: target_path, status: :missing, content: "".b, suffix: "".b) unless File.exist?(target_path)
    unless File.file?(target_path)
      raise Error, "instruction path is not a regular file: #{target_path}"
    end

    content = File.binread(target_path)
    start_count = content.scan(START_MARKER).length
    end_count = content.scan(END_MARKER).length
    if start_count.zero? && end_count.zero?
      if content.start_with?(asset)
        return Analysis.new(
          path: target_path,
          status: :legacy,
          content: content,
          suffix: content.byteslice(asset.bytesize..-1) || "".b,
          mode: file_mode(target_path)
        )
      end
      if LEGACY_ASSET_DIGESTS.include?(Digest::SHA256.hexdigest(content))
        return Analysis.new(
          path: target_path,
          status: :legacy,
          content: content,
          suffix: "".b,
          mode: file_mode(target_path)
        )
      end
      return Analysis.new(
        path: target_path,
        status: :absent,
        content: content,
        suffix: content,
        mode: file_mode(target_path)
      )
    end
    unless start_count == 1 && end_count == 1
      raise Error, "malformed or duplicate managed markers in #{target_path}"
    end

    start_index = content.index(START_MARKER)
    end_index = content.index(END_MARKER)
    if start_index != 0
      raise Error, "managed block is not at the top of #{target_path}"
    end
    if end_index.nil? || end_index < START_MARKER.bytesize
      raise Error, "managed markers are out of order in #{target_path}"
    end

    managed_end = end_index + END_MARKER.bytesize
    if content.byteslice(managed_end, 2) == "\r\n"
      managed_end += 2
    elsif content.byteslice(managed_end, 1) == "\n"
      managed_end += 1
    end
    managed = content.byteslice(0, managed_end)
    suffix = content.byteslice(managed_end..-1) || "".b
    status = (managed == canonical) ? :current : :stale
    Analysis.new(
      path: target_path,
      status: status,
      content: content,
      suffix: suffix,
      mode: file_mode(target_path)
    )
  end

  def execute(mode, asset_path:, codex_home:)
    asset, canonical = canonical_material(asset_path)
    base_path = File.join(codex_home, "AGENTS.md")
    override_path = File.join(codex_home, "AGENTS.override.md")
    override_exists = File.exist?(override_path) || File.symlink?(override_path)
    active_path = override_exists ? override_path : base_path
    inactive_path = override_exists ? base_path : nil
    active = analyze(active_path, asset, canonical)
    inactive = inactive_path ? analyze(inactive_path, asset, canonical) : nil

    case mode
    when "check"
      check(active, inactive)
    when "dry-run"
      report_plan(active, inactive)
    when "install"
      install(active, inactive, canonical, codex_home)
    else
      raise Error, "unsupported mode: #{mode}"
    end
  end

  def check(active, inactive)
    unless active.status == :current
      raise Error, "global learning instructions are #{active.status} in active file #{active.path}"
    end
    if inactive && owned_status?(inactive.status)
      raise Error, "inactive instruction file retains a managed block: #{inactive.path}"
    end

    puts "Global learning instructions match the canonical asset in #{active.path}"
  end

  def report_plan(active, inactive)
    case active.status
    when :missing
      puts "Would create global learning instructions in #{active.path}"
    when :absent
      puts "Would prepend global learning instructions to #{active.path}"
    when :legacy
      puts "Would adopt legacy canonical learning instructions in #{active.path}"
    when :stale
      puts "Would update global learning instructions in #{active.path}"
    when :current
      puts "Global learning instructions are current in #{active.path}"
    end

    return unless inactive && owned_status?(inactive.status)

    puts "Would remove the managed block from inactive instruction file #{inactive.path}"
  end

  def install(active, inactive, canonical, codex_home)
    ensure_codex_home(codex_home) if active.status == :missing
    unless active.status == :current
      replacement = canonical + active.suffix
      atomic_replace(active.path, replacement, active.mode || 0o600)
    end
    remove_inactive_block(inactive) if inactive && owned_status?(inactive.status)

    puts "Installed global learning instructions in #{active.path}"
  end

  def remove_inactive_block(inactive)
    if inactive.suffix.empty?
      File.unlink(inactive.path)
      fsync_directory(File.dirname(inactive.path))
    else
      atomic_replace(inactive.path, inactive.suffix, inactive.mode)
    end
  end

  def owned_status?(status)
    %i[current stale legacy].include?(status)
  end

  def ensure_codex_home(codex_home)
    return if Dir.exist?(codex_home)
    raise Error, "Codex home exists but is not a directory: #{codex_home}" if File.exist?(codex_home)

    FileUtils.mkdir_p(codex_home, mode: 0o700)
    File.chmod(0o700, codex_home)
  end

  def atomic_replace(target_path, content, mode)
    target_dir = File.dirname(target_path)
    temporary = File.join(
      target_dir,
      ".#{File.basename(target_path)}.codex-workflows-#{Process.pid}-#{SecureRandom.hex(3)}"
    )
    File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, mode) do |file|
      file.binmode
      file.write(content)
      file.flush
      file.fsync
    end
    File.chmod(mode, temporary)
    File.rename(temporary, target_path)
    fsync_directory(target_dir)
  ensure
    File.unlink(temporary) if temporary && File.exist?(temporary)
  end

  def fsync_directory(directory)
    File.open(directory, File::RDONLY) { |handle| handle.fsync }
  rescue Errno::EINVAL, Errno::EISDIR
    nil
  end

  def reject_symlink!(target_path, label)
    return unless File.symlink?(target_path)

    raise Error, "#{label} must not be a symlink: #{target_path}"
  end

  def file_mode(target_path)
    File.stat(target_path).mode & 0o777
  end
end

def usage
  <<~TEXT
    Usage: manage-global-learning.rb MODE --asset FILE --codex-home DIR

    Manage the canonical codex-workflows learning block in the active global
    Codex instruction file. MODE is install, check, or dry-run.
  TEXT
end

if ARGV.empty? || %w[-h --help].include?(ARGV.first)
  puts usage
  exit 0
end

mode = ARGV.shift
asset_path = nil
codex_home = nil
parser = OptionParser.new do |opts|
  opts.on("--asset FILE") { |value| asset_path = File.expand_path(value) }
  opts.on("--codex-home DIR") { |value| codex_home = File.expand_path(value) }
  opts.on("--help") do
    puts usage
    exit 0
  end
end

begin
  parser.parse!(ARGV)
  raise OptionParser::InvalidArgument, "unexpected argument: #{ARGV.first}" unless ARGV.empty?
  raise OptionParser::InvalidArgument, "MODE must be one of #{GlobalLearning::MODES.join(", ")}" unless GlobalLearning::MODES.include?(mode)
  raise OptionParser::MissingArgument, "--asset FILE" unless asset_path
  raise OptionParser::MissingArgument, "--codex-home DIR" unless codex_home

  GlobalLearning.execute(mode, asset_path: asset_path, codex_home: codex_home)
rescue OptionParser::ParseError => e
  warn "manage-global-learning.rb: #{e.message}"
  warn usage
  exit 2
rescue GlobalLearning::Error, SystemCallError => e
  warn "manage-global-learning.rb: #{e.message}"
  exit 1
end
