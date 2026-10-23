#!/usr/bin/env -S RBENV_VERSION=3.3.12 ruby
# frozen_string_literal: true

required_ruby_engine = "ruby"
required_ruby_version = "3.3.12"
unless required_ruby_engine == RUBY_ENGINE && required_ruby_version == RUBY_VERSION
  warn "check-verification-context.rb: CRuby 3.3.12 is required; detected #{RUBY_DESCRIPTION} via #{RbConfig.ruby}"
  exit 1
end

require "json"
require "optparse"

module VerificationContextCheck
  class InputError < StandardError; end

  STOP_WORDS = Set.new(%w[
    a after all also an and are as at be before both but by can could did do does during
    every for from had has have if in including into is it its of on or our same still
    the their them these they this those through to using was were when where which while with
  ]).freeze
  POOLS = {"observed_behavior_refs" => "observations", "observation_ref" => "observations",
           "summary_ref" => "observations", "decisive_evidence_refs" => "evidence"}.freeze
  CONTEXT_FIELDS = {"expected_behavior" => "requirement", "verification_opportunity" => "opportunity",
                    "opportunity_match" => "opportunity_match", "rationale" => "rationale",
                    "source_scope" => "provenance", "source_report_summary" => "historical_problem"}.freeze

  def self.escape(value)
    value.to_s.gsub("~", "~0").gsub("/", "~1")
  end

  def self.walk(value, path = "#", &block)
    yield path, value
    case value
    when Hash then value.each { |key, child| walk(child, "#{path}/#{escape(key)}", &block) }
    when Array then value.each_with_index { |child, index| walk(child, "#{path}/#{index}", &block) }
    end
  end

  def self.normalized(text)
    text.downcase.gsub(/\s+/, " ").strip
  end

  def self.passages(text)
    text.split(/(?<=[.!?])\s+|\n\s*\n/).map { |part| normalized(part) }
      .select { |part| part.scan(/[[:alnum:]]+/).length >= 4 }.to_set
  end

  def self.terms(text)
    text.downcase.scan(/[a-z]+/).reject { |word| word.length < 3 || STOP_WORDS.include?(word) }
      .map { |word| (word.length > 5) ? "#{word[0, 5]}*" : word }.to_set
  end

  def self.qualifiers(text)
    {"numbers" => text.scan(/(?<![[:alnum:]])[+-]?\d+(?:\.\d+)?(?:e[+-]?\d+)?\b/i).uniq,
     "negation" => text.downcase.scan(/\b(?:no|not|never|without|unverified|untested|unexamined)\b/).uniq}
  end

  def self.run(document)
    unless document.is_a?(Hash) && document["mode"] == "detail" && document["records"].is_a?(Array)
      raise InputError, "expected expanded verification-context JSON with mode detail and records array"
    end
    nodes = {}
    walk(document) { |path, value| nodes[path] = value }
    references = []
    errors = []
    nodes.each do |path, value|
      next unless value.is_a?(Hash)

      if value.key?("$ref")
        references << {"path" => path, "target" => value["$ref"], "kind" => "json_pointer"}
        errors << {"path" => path, "reason" => "reference object has extra fields"} unless value.keys == ["$ref"]
        pool = if path.match?(%r{/evidence_refs/\d+\z})
          "evidence"
        elsif path.match?(%r{/claim_limits_refs/\d+\z})
          "claim_limits"
        end
        if pool && !(value["$ref"].is_a?(String) && value["$ref"].start_with?("#{path[%r{\A#/records/\d+}]}/#{pool}/"))
          errors << {"path" => path, "reason" => "reference must target its record's #{pool} dictionary"}
        end
      end
      POOLS.each do |field, pool|
        next unless value.key?(field)

        source = "#{path}/#{field}"
        entries = value[field].is_a?(Array) ? value[field] : [value[field]]
        entries.each_with_index do |id, index|
          origin = value[field].is_a?(Array) ? "#{source}/#{index}" : source
          base = path[%r{\A#/records/\d+}]
          target = (id.is_a?(String) && base) ? "#{base}/#{pool}/#{escape(id)}" : nil
          references << {"path" => origin, "target" => target, "kind" => "pool_link"}
        end
      end
    end
    document.fetch("records").each_with_index do |record, index|
      next unless record.is_a?(Hash)

      proposals = record.fetch("verification_proposals", [])
      %w[selected applied pending].each do |role|
        field = "#{role}_verification_proposal_ids"
        next unless record[field].is_a?(Array)

        record[field].each_with_index do |id, position|
          target = proposals.is_a?(Array) && proposals.index { |proposal| proposal.is_a?(Hash) && proposal["id"] == id }
          references << {"path" => "#/records/#{index}/#{field}/#{position}",
                         "target" => target ? "#/records/#{index}/verification_proposals/#{target}" : nil,
                         "kind" => "proposal_role_link"}
        end
      end
    end
    references.each do |ref|
      source_record = ref["path"][%r{\A#/records/\d+}]
      target_record = ref["target"].is_a?(String) && ref["target"][%r{\A#/records/\d+}]
      reason = if !nodes.key?(ref["target"])
        "missing or invalid target"
      elsif source_record != target_record
        "reference leaves its record"
      end
      errors << ref.merge("reason" => reason) if reason
    end
    active = Set.new
    visited = Set.new
    edges = references.to_h { |ref| [ref.fetch("path"), ref.fetch("target")] }
    visit = lambda do |path, parent|
      if active.include?(path)
        errors << {"path" => parent, "target" => path, "reason" => "reference cycle"}
        next
      end
      next if visited.include?(path)

      active << path
      value = nodes.fetch(path)
      children = if edges.key?(path)
        nodes.key?(edges[path]) ? [edges[path]] : []
      elsif value.is_a?(Hash)
        if value.keys == ["$ref"]
          nodes.key?(value["$ref"]) ? [value["$ref"]] : []
        else
          value.keys.map { |key| "#{path}/#{escape(key)}" }
        end
      elsif value.is_a?(Array)
        value.each_index.map { |index| "#{path}/#{index}" }
      else
        []
      end
      children.each { |child| visit.call(child, path) }
      active.delete(path)
      visited << path
    end
    visit.call("#", nil)

    findings = []
    role_overlaps = []
    contexts = []
    intentional = []
    units = []
    document.fetch("records").each_with_index do |record, index|
      unless record.is_a?(Hash) && %w[observations evidence claim_limits].all? { |pool| record[pool].is_a?(Hash) }
        raise InputError, "#/records/#{index}: expected observations, evidence, and claim_limits dictionaries"
      end
      base = "#/records/#{index}"
      record_units = []
      %w[observations evidence claim_limits].each do |pool|
        walk(record.fetch(pool), "#{base}/#{pool}") do |path, value|
          next unless value.is_a?(String) && !path.end_with?("/$ref")
          next if path.match?(%r{/(claim_limits_refs|evidence_refs)/})

          record_units << {"path" => path, "role" => (pool == "claim_limits") ? "limit" : "fact", "text" => value}
        end
      end
      walk(record, base) do |path, value|
        next unless value.is_a?(Hash)

        if value.key?("body")
          body = value.fetch("body")
          text = if body.is_a?(String)
            body
          else
            body.is_a?(Hash) ? body["text"] : nil
          end
          if text.is_a?(String)
            body_path = "#{path}/body#{"/text" if body.is_a?(Hash)}"
            record_units << {"path" => body_path, "role" => "fact", "text" => text}
          end
        end
        CONTEXT_FIELDS.each do |field, role|
          text = value[field]
          suffix = text.is_a?(Hash) ? "/text" : ""
          text = text["text"] if text.is_a?(Hash)
          contexts << {"path" => "#{path}/#{field}#{suffix}", "role" => role, "text" => text} if text.is_a?(String)
        end
      end
      record_units.combination(2) do |left, right|
        left_text = normalized(left.fetch("text"))
        right_text = normalized(right.fetch("text"))
        exact = !left_text.empty? && left_text == right_text
        shared_passages = passages(left.fetch("text")) & passages(right.fetch("text"))
        left_terms = terms(left.fetch("text"))
        right_terms = terms(right.fetch("text"))
        shared = left_terms & right_terms
        shorter = [left_terms.size, right_terms.size].min
        score = shorter.zero? ? 0.0 : shared.size.fdiv(shorter)
        qualifies = exact || !shared_passages.empty? || (shared.size >= 3 && (score >= 0.2 || shared.size >= 5))
        next unless qualifies

        match = {"paths" => [left.fetch("path"), right.fetch("path")],
                 "kind" => if exact
                             "exact_text"
                           else
                             shared_passages.empty? ? "lexical_overlap" : "exact_passage"
                           end,
                 "shared_passages" => shared_passages.to_a, "shared_terms" => shared.to_a.sort,
                 "shorter_text_coverage" => score.round(3),
                 "excerpts" => [left.fetch("text"), right.fetch("text")],
                 "qualifiers" => [qualifiers(left.fetch("text")), qualifiers(right.fetch("text"))]}
        if match["kind"] == "lexical_overlap" && (left.fetch("role") != "fact" || right.fetch("role") != "fact")
          role_overlaps << match.merge("reason" => "scope and evidence have different assertion roles; no equivalence inferred")
        else
          findings << match
        end
      end
      %w[verification verification_basis].each do |field|
        matches = nodes.select do |path, value|
          names = (field == "verification") ? %w[verification proposed_verification] : [field]
          path.start_with?("#{base}/") && names.include?(path.split("/").last) && value.is_a?(String)
        end
        matches.to_a.group_by(&:last).each_value do |rows|
          if rows.length > 1
            intentional << {"paths" => rows.map(&:first), "value" => rows.first.last,
                            "reason" => "independent accepted-outcome and proposal categories"}
          end
        end
      end
      units.concat(record_units)
    end
    invalid_paths = errors.map { |error| error["path"] }.to_set
    grouped_refs = references.reject { |ref| invalid_paths.include?(ref["path"]) }
      .group_by { |ref| [ref["kind"], ref["target"]] }.map do |(kind, target), refs|
      {"kind" => kind, "target" => target, "paths" => refs.map { |ref| ref.fetch("path") }}
    end
    {"summary" => {"records" => document.fetch("records").length, "text_fields" => units.length,
                   "exact_duplicates" => findings.count { |finding| finding["kind"].start_with?("exact_") },
                   "review_candidates" => findings.count { |finding| finding["kind"] == "lexical_overlap" },
                   "reference_errors" => errors.length, "references" => references.length},
     "method" => "Compare stored text within each record. Exact text/passages ignore case and whitespace only. Lexical candidates share >=5 terms, or >=3 terms covering >=20% of the shorter term set. Words longer than five letters use five-letter prefixes (*). Lexical candidates are review leads, not semantic equivalence or deletion instructions. Context fields have separate requirement, decision, and provenance roles and are listed outside factual comparisons.",
     "findings" => findings, "reference_errors" => errors,
     "intentional_references" => grouped_refs, "intentional_categories" => intentional,
     "role_overlaps" => role_overlaps, "context_fields" => contexts}
  end

  def self.self_test
    fixture = {"mode" => "detail", "records" => [{
      "accepted" => {"frontmatter" => {"verification_basis" => "deterministic-test",
                                       "observed_behavior_refs" => ["observation/~"]}},
      "verification_proposals" => [{"frontmatter" => {"verification_basis" => "deterministic-test",
                                                      "rationale" => "Keep the independently observed reason."}}],
      "observations" => {"observation/~" => {"text" => "The smoke preceded the larger acquisition.",
                                             "evidence_refs" => [{"$ref" => "#/records/0/evidence/source~1recovery~0"}]}},
      "evidence" => {"source/recovery~" => "The native samples recovered source locations using matching debug information.",
                     "hashes" => "Capture and binary hashes stayed identical."},
      "claim_limits" => {"untested" => "Caller recovery was not tested."}
    }]}
    baseline = JSON.generate(fixture)
    report = run(fixture)
    raise "references were treated as duplicate text" unless report.dig("summary", "exact_duplicates").zero? && report["reference_errors"].empty?
    raise "escaped pooled references were lost" unless report["intentional_references"].any? { |ref| ref["target"] == "#/records/0/observations/observation~1~0" }
    raise "independent categories were lost" unless report["intentional_categories"].length == 1
    raise "checker changed its input" unless baseline == JSON.generate(fixture)
    copy = JSON.parse(baseline)
    copy["records"][0]["observations"]["observation/~"]["text"] = copy["records"][0]["evidence"]["source/recovery~"]
    duplicate = run(copy)["findings"].find { |finding| finding["kind"] == "exact_text" }
    raise "linked repeated prose was hidden" unless duplicate && duplicate["paths"].include?("#/records/0/observations/observation~1~0/text")
    copy["records"][0]["observations"]["observation/~"]["text"] = "Recovered native sample sources using the matching debugger."
    raise "paraphrase review lead was missed" unless run(copy).dig("summary", "review_candidates").positive?
    copy["records"][0]["observations"]["observation/~"]["evidence_refs"][0]["$ref"] = "#/records/0/evidence/missing"
    raise "broken reference was missed" if run(copy)["reference_errors"].empty?
    copy["records"][0]["observations"]["observation/~"]["evidence_refs"][0]["$ref"] = "#/records/0/observations/observation~1~0"
    raise "reference cycle was missed" unless run(copy)["reference_errors"].any? { |error| error["reason"] == "reference cycle" }
    copy = JSON.parse(baseline)
    second = JSON.parse(JSON.generate(copy["records"].first))
    second["observations"]["observation/~"]["evidence_refs"][0]["$ref"] = "#/records/1/evidence/source~1recovery~0"
    copy["records"] << second
    raise "cross-record content was treated as duplicate" unless run(copy).dig("summary", "exact_duplicates").zero?
    second["observations"]["observation/~"]["evidence_refs"][0]["$ref"] = "#/records/0/evidence/source~1recovery~0"
    raise "cross-record evidence reference was missed" unless run(copy)["reference_errors"].any? { |error| error["reason"] == "reference leaves its record" }
    copy = JSON.parse(baseline)
    copy["records"][0]["evidence"]["one"] = "A unique first condition. The captured output stayed identical after recovery."
    copy["records"][0]["evidence"]["two"] = "The captured output stayed identical after recovery. A unique second condition."
    raise "embedded literal passage was missed" unless run(copy)["findings"].any? { |finding| finding["kind"] == "exact_passage" }
    copy = JSON.parse(baseline)
    copy["records"][0]["accepted"]["frontmatter"]["expected_behavior"] = copy["records"][0]["evidence"]["hashes"]
    report = run(copy)
    raise "requirement was treated as observed evidence" unless report.dig("summary", "exact_duplicates").zero? &&
      report["context_fields"].any? { |field| field["role"] == "requirement" }
    copy["records"][0]["accepted"]["body"] = "Extra context. Caller recovery was not tested."
    raise "body duplicated limit was missed" unless run(copy)["findings"].any? do |finding|
      finding["kind"] == "exact_passage" && finding["paths"].include?("#/records/0/accepted/body")
    end
    copy = JSON.parse(baseline)
    copy["records"][0]["evidence"]["one"] = "Measured native recovery took -1.2 seconds."
    copy["records"][0]["evidence"]["two"] = "Measured native recovery took 1.2 seconds."
    candidate = run(copy)["findings"].find { |finding| finding["paths"].all? { |path| path.match?(%r{/evidence/(one|two)\z}) } }
    raise "numeric distinctions were discarded" unless candidate && candidate["kind"] == "lexical_overlap" &&
      candidate["qualifiers"].map { |value| value["numbers"] } == [["-1.2"], ["1.2"]]

    require "open3"
    require "tmpdir"
    command = [RbConfig.ruby, File.expand_path(__FILE__)]
    duplicate_input = JSON.parse(baseline)
    duplicate_input["records"][0]["evidence"]["copy"] = duplicate_input["records"][0]["evidence"]["hashes"]
    [[[], "[", 2],
      [[], '{"mode":"discovery","records":[]}', 2],
      [["--unknown"], "", 2], [["extra"], "", 2],
      [[], JSON.generate(duplicate_input), 1],
      [[], JSON.generate(fixture), 0]].each do |args, input, expected|
      stdout, stderr, status = Open3.capture3(*command, *args, stdin_data: input)
      streams_valid = if expected == 2
        stdout.empty? && stderr.start_with?("check-verification-context.rb:")
      else
        stderr.empty? && JSON.parse(stdout).key?("summary")
      end
      raise "CLI stream/status contract changed" unless status.exitstatus == expected && streams_valid
    end
    Dir.mktmpdir("context-checker-test.") do |directory|
      File.write(File.join(directory, ".ruby-version"), "0.0.0\n")
      stdout, stderr, status = Open3.capture3(File.expand_path(__FILE__), stdin_data: baseline, chdir: directory)
      raise "shebang did not bind the repository runtime" unless status.success? && stderr.empty? && JSON.parse(stdout).key?("summary")
      stdout, stderr, status = Open3.capture3(*command, "--file", directory)
      raise "directory input exposed a traceback" unless status.exitstatus == 2 && stdout.empty? && stderr.start_with?("check-verification-context.rb:")
    end
    if File.executable?("/usr/bin/ruby")
      version, = Open3.capture3("/usr/bin/ruby", "-e", 'print RUBY_ENGINE + ":" + RUBY_VERSION')
      if version != "ruby:3.3.12"
        stdout, stderr, status = Open3.capture3("/usr/bin/ruby", File.expand_path(__FILE__), stdin_data: baseline)
        raise "wrong interpreter passed its guard" unless status.exitstatus == 1 && stdout.empty? && stderr.include?("CRuby 3.3.12 is required")
      end
    end
    puts "Verification context checker tests passed."
  end
end

if $PROGRAM_NAME == __FILE__
  options = {file: "-", self_test: false}
  parser = OptionParser.new do |opts|
    opts.banner = "Usage: check-verification-context.rb [--file JSON|-] [--self-test]"
    opts.separator "Read expanded verification-context JSON; write a JSON audit without modifying input or state."
    opts.separator "Evidence, observations, document bodies, and claim limits are compared within each record."
    opts.separator "Opportunity, rationale, requirement, and provenance fields keep separate roles."
    opts.separator "References are checked and listed without expanding them into repeated prose."
    opts.separator "Exit 0: audit complete; 1: exact duplicates or reference errors; 2: invalid input/usage."
    opts.separator "Lexical overlaps require review and do not fail the check. No semantic completeness is claimed."
    opts.on("--file PATH", "JSON input path, or - for standard input (default)") { |value| options[:file] = value }
    opts.on("--self-test", "Run disposable checker fixtures") { options[:self_test] = true }
    opts.on("-h", "--help", "Show help") {
      puts opts
      exit 0
    }
  end
  begin
    parser.parse!
    raise OptionParser::InvalidArgument, "unexpected argument: #{ARGV.first}" unless ARGV.empty?
    if options[:self_test]
      VerificationContextCheck.self_test
    else
      source = (options[:file] == "-") ? $stdin.read : File.read(options[:file], encoding: "UTF-8")
      report = VerificationContextCheck.run(JSON.parse(source))
      puts JSON.pretty_generate(report)
      exit 1 if report.dig("summary", "exact_duplicates").positive? || report.dig("summary", "reference_errors").positive?
    end
  rescue OptionParser::ParseError, VerificationContextCheck::InputError, JSON::ParserError,
    Errno::ENOENT, Errno::ENOTDIR, Errno::EISDIR, Errno::EACCES => e
    warn "check-verification-context.rb: #{e.message}"
    exit 2
  end
end
