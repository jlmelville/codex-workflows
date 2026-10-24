# frozen_string_literal: true

require "digest"
require "json"
require "time"
require_relative "verification-context-artifacts"

module VerificationContextCheck
  class ReviewManifest
    BINDING_VERSION = 1
    VERDICTS = %w[distinct_evidence distinct_context unresolved_provenance duplicate].freeze
    PROVENANCE_FIELDS = %w[
      originating_candidate_ids source_report_summary source_scope intake_digest
      target_accepted_id verification_basis claim proposed_verification
      expected_behavior verification_opportunity opportunity_match triage
    ].freeze

    def initialize(document, report, manifest = {"schema_version" => 1, "reviews" => []}, artifact_roots: {})
      @report = report
      @records = {}
      document.fetch("records").each_with_index do |record, index|
        accepted = record["accepted"]
        id = accepted.is_a?(Hash) ? accepted["id"] : nil
        unless id.is_a?(String) && id.match?(/\ASCR-\d{8}-[a-f0-9]{6}\z/) && !@records.key?(id)
          raise InputError, "review modes require distinct accepted record IDs"
        end
        nodes = {}
        VerificationContextCheck.walk(record, "") { |path, value| nodes[path] = value }
        base = "#/records/#{index}"
        refs = report.fetch("intentional_references").flat_map do |group|
          group.fetch("paths").filter_map do |path|
            next unless path.start_with?(base + "/")

            {"path" => path.delete_prefix(base), "target" => group.fetch("target").delete_prefix(base)}
          end
        end
        @records[id] = {"base" => base, "nodes" => nodes, "references" => refs}
      end
      validate(manifest, artifact_roots)
      @reviews = manifest.fetch("reviews").to_h { |review| [key(review.fetch("accepted_id"), review.fetch("paths")), review] }
    end

    def validate(manifest, artifact_roots)
      version = manifest.is_a?(Hash) ? manifest["schema_version"] : nil
      expected_keys = {1 => %w[reviews schema_version], 2 => %w[artifacts reviews schema_version]}[version]
      unless expected_keys && manifest.keys.sort == expected_keys && manifest["reviews"].is_a?(Array)
        raise InputError, "expected review manifest schema_version 1 or 2, reviews array, and artifacts registry for version 2"
      end
      @manifest = manifest
      external = manifest["schema_version"] == 2
      @artifacts = ExternalArtifacts.new(external ? manifest["artifacts"] : {}, artifact_roots)
      seen = Set.new
      manifest.fetch("reviews").each do |review|
        required = %w[accepted_id binding context_paths paths rationale reviewed_at verdict]
        allowed = required + (external ? ["artifact_refs"] : [])
        unless review.is_a?(Hash) && (required - review.keys).empty? && (review.keys - allowed).empty? &&
            review["accepted_id"].is_a?(String) && review["accepted_id"].match?(/\ASCR-\d{8}-[a-f0-9]{6}\z/) &&
            path_list?(review["paths"], size: 2) && path_list?(review["context_paths"])
          raise InputError, "review requires accepted_id, two distinct relative paths, context_paths, verdict, rationale, UTC reviewed_at, and binding"
        end
        unless blank_judgment?(review)
          unless VERDICTS.include?(review["verdict"]) && review["rationale"].is_a?(String) && !review["rationale"].strip.empty? &&
              review["reviewed_at"].is_a?(String) && review["reviewed_at"].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
            raise InputError, "review judgment must be complete or prepared blanks (verdict: null, rationale: empty string, reviewed_at: null)"
          end
          begin
            Time.iso8601(review.fetch("reviewed_at"))
          rescue ArgumentError
            raise InputError, "invalid review timestamp"
          end
        end
        binding = review.fetch("binding")
        unless binding.is_a?(Hash) && (%w[dependencies version] - binding.keys).empty? &&
            (binding.keys - (%w[dependencies version] + (external ? ["artifacts"] : []))).empty? &&
            binding["version"].is_a?(Integer) && binding["version"].positive? &&
            binding["dependencies"].is_a?(Hash) && !binding["dependencies"].empty? &&
            binding["dependencies"].all? { |path, digest| pointer?(path) && digest.is_a?(String) && digest.match?(/\Asha256:[a-f0-9]{64}\z/) }
          raise InputError, "review binding requires a positive version and dependency path/SHA-256 map"
        end
        @artifacts.validate_review(review)
        identity = key(review.fetch("accepted_id"), review.fetch("paths"))
        raise InputError, "conflicting or duplicate reviews for #{identity.inspect}" unless seen.add?(identity)
      end
    end

    def blank_judgment?(review)
      review.values_at("verdict", "rationale", "reviewed_at") == [nil, "", nil]
    end

    def pointer?(path)
      path.is_a?(String) && path.start_with?("/") && !path.match?(/~(?![01])/)
    end

    def path_list?(paths, size: nil)
      paths.is_a?(Array) && (!size || paths.length == size) && paths.uniq == paths && paths.all? { |path| pointer?(path) }
    end

    def key(id, paths)
      [id, paths.sort]
    end

    def canonical(value, base)
      case value
      when Hash
        value.keys.sort.to_h do |name|
          child = value.fetch(name)
          child = child.delete_prefix(base) if name == "$ref" && child.is_a?(String) && child.start_with?(base + "/")
          [name, canonical(child, base)]
        end
      when Array then value.map { |child| canonical(child, base) }
      else value
      end
    end

    def entry_path(path)
      if path.match?(%r{\A/(?:evidence|observations|claim_limits)/})
        path.split("/").first(3).join("/")
      elsif path.start_with?("/accepted/body")
        "/accepted/body"
      elsif (match = path.match(%r{\A/verification_proposals/\d+/body(?:/|\z)}))
        match[0].delete_suffix("/")
      else
        path
      end
    end

    def dependencies(id, paths, context_paths)
      record = @records.fetch(id)
      nodes = record.fetch("nodes")
      refs = record.fetch("references")
      dependencies = {}
      followed = Set.new
      add = lambda do |path, follow = true|
        unless dependencies.key?(path)
          value = nodes.key?(path) ? {"present" => true, "value" => nodes.fetch(path)} : {"present" => false}
          dependencies[path] = "sha256:#{Digest::SHA256.hexdigest(JSON.generate(canonical(value, record.fetch("base"))))}"
        end
        next unless follow && followed.add?(path)

        refs.each do |ref|
          add.call(ref.fetch("target")) if ref.fetch("path") == path || ref.fetch("path").start_with?(path + "/")
        end
      end
      documents = Set.new(["/accepted"])
      paths.each do |path|
        add.call(entry_path(path))
        owner = path[%r{\A/(?:accepted|verification_proposals/\d+)(?=/|\z)}]
        documents << owner if owner
        refs.each do |ref|
          target = ref.fetch("target")
          next unless path == target || path.start_with?(target + "/")

          origin = ref.fetch("path")
          # Incoming citations identify owners without importing their other claims.
          add.call(origin, false)
          document = origin[%r{\A/(?:accepted|verification_proposals/\d+)(?=/|\z)}]
          documents << document if document
        end
      end
      documents.each do |path|
        %w[id path].each { |field| add.call("#{path}/#{field}") }
        PROVENANCE_FIELDS.each { |field| add.call("#{path}/frontmatter/#{field}") }
      end
      add.call("/claim_limits")
      context_paths.each { |path| add.call(path) }
      dependencies.sort.to_h
    end

    def finding_identity(finding)
      path = finding.fetch("paths").first
      id, record = @records.find { |_, item| path.start_with?(item.fetch("base") + "/") }
      [id, finding.fetch("paths").map { |item| item.delete_prefix(record.fetch("base")) }]
    end

    def freshness(review)
      id = review.fetch("accepted_id")
      binding = review.fetch("binding")
      current = dependencies(id, review.fetch("paths"), review.fetch("context_paths"))
      previous = binding.fetch("dependencies")
      changed = (current.keys | previous.keys).select { |path| current[path] != previous[path] }
      reasons = []
      reasons << "binding_version_changed" if binding.fetch("version") != BINDING_VERSION
      reasons << "dependencies_changed" unless changed.empty?
      reasons << "endpoint_missing" unless review.fetch("paths").all? { |path| @records.fetch(id).fetch("nodes").key?(path) }
      reasons << "context_missing" unless review.fetch("context_paths").all? { |path| @records.fetch(id).fetch("nodes").key?(path) }
      artifact_status = @artifacts.assess(review)
      reasons << "external_artifacts_changed" if artifact_status.key?("changed_artifact_refs")
      if blank_judgment?(review)
        result = {"freshness" => "unreviewed", "reasons" => ["blank_judgment", *reasons]}
        result["changed_paths"] = changed.map { |path| @records.fetch(id).fetch("base") + path } unless changed.empty?
        return result.merge(artifact_status)
      end
      judgment = review.slice("verdict", "rationale", "reviewed_at")
      return judgment.merge("freshness" => "current").merge(artifact_status) if reasons.empty?

      {"freshness" => "stale", "previous_review" => judgment, "reasons" => reasons,
       "changed_paths" => changed.map { |path| @records.fetch(id).fetch("base") + path }}.merge(artifact_status)
    end

    def annotate
      counts = VERDICTS.to_h { |verdict| [verdict, 0] }
      unreviewed = 0
      stale = 0
      used = Set.new
      @report.fetch("findings").each do |finding|
        id, paths = finding_identity(finding)
        identity = key(id, paths)
        review = @reviews[identity]
        used << identity
        result = review ? freshness(review) : {"freshness" => "unreviewed", "artifact_coverage" => "json_only"}
        finding["review"] = result
        case result.fetch("freshness")
        when "current" then counts[result.fetch("verdict")] += 1
        when "stale" then stale += 1
        else unreviewed += 1
        end
      end
      inactive = @reviews.filter_map do |identity, review|
        id = review.fetch("accepted_id")
        next if used.include?(identity) || !@records.key?(id)

        result = freshness(review)
        inactive_review = if blank_judgment?(review)
          result.merge("reasons" => result.fetch("reasons") + ["no_longer_candidate"])
        else
          {"freshness" => "stale", "previous_review" => review.slice("verdict", "rationale", "reviewed_at"),
           "reasons" => (result.fetch("reasons", []) + ["no_longer_candidate"]),
           "changed_paths" => result.fetch("changed_paths", [])}.merge(result.slice("artifact_coverage", "artifact_refs", "changed_artifact_refs"))
        end
        {"accepted_id" => id, "paths" => review.fetch("paths").map { |path| @records.fetch(id).fetch("base") + path },
         "review" => inactive_review}
      end
      @report.merge("review_summary" => {"candidates" => @report.fetch("findings").length, "current" => counts,
                                         "unreviewed" => unreviewed + inactive.count { |item| item.dig("review", "freshness") == "unreviewed" },
                                         "stale" => stale + inactive.count { |item| item.dig("review", "freshness") == "stale" }, "inactive" => inactive.length},
        "inactive_reviews" => inactive, "external_artifacts" => @artifacts.report)
    end

    def prepare
      raise InputError, "repair reference errors before preparing reviews" unless @report.fetch("reference_errors").empty?

      prepared = @report.fetch("findings").map do |finding|
        id, paths = finding_identity(finding)
        previous = @reviews[key(id, paths)]
        next previous if previous && freshness(previous).fetch("freshness") == "current"

        context = previous ? previous.fetch("context_paths") : []
        unless context.all? { |path| @records.fetch(id).fetch("nodes").key?(path) }
          raise InputError, "repair missing review context paths before preparation"
        end
        entry = {"accepted_id" => id, "paths" => paths.sort, "context_paths" => context,
                 "verdict" => nil, "rationale" => "", "reviewed_at" => nil,
                 "binding" => {"version" => BINDING_VERSION, "dependencies" => dependencies(id, paths, context)}}
        if previous && (previous.key?("artifact_refs") || previous.fetch("binding").key?("artifacts"))
          entry["artifact_refs"] = previous.fetch("artifact_refs", [])
          entry["binding"]["artifacts"] = @artifacts.prepare(previous)
        end
        entry
      end
      identities = prepared.map { |review| key(review.fetch("accepted_id"), review.fetch("paths")) }.to_set
      retained = @reviews.except(*identities).values
      @manifest.merge("reviews" => prepared + retained)
    end

    def self.failed?(report, require_reviewed: false)
      summary = report.fetch("summary")
      reviews = report["review_summary"]
      summary.fetch("exact_duplicates").positive? || summary.fetch("reference_errors").positive? ||
        (reviews && (reviews.fetch("current").fetch("duplicate").positive? ||
          (require_reviewed && (reviews.fetch("unreviewed").positive? || reviews.fetch("stale").positive?))))
    end

    def self.gate_diagnostics(report)
      (report.fetch("findings") + report.fetch("inactive_reviews")).filter_map do |finding|
        review = finding.fetch("review")
        status = review.fetch("freshness")
        next unless %w[unreviewed stale].include?(status)

        detail = review.fetch("reasons", []).include?("blank_judgment") ? " (blank judgment)" : ""
        artifacts = review.fetch("changed_artifact_refs", []).map do |ref|
          id = ref.fetch("$ref").delete_prefix("#/external_artifacts/")
          observed = report.fetch("external_artifacts").fetch(id)
          locator = observed["locator"]&.values_at("root", "path")&.join(":")
          "#{id} at #{observed["resolved_path"] || locator || "undeclared locator"}: #{observed.fetch("changes").join(", ")}"
        end
        suffix = artifacts.empty? ? "" : "; external artifacts: #{artifacts.join("; ")}"
        "#{status} overlap#{detail}: #{finding.fetch("paths").join(" <-> ")}#{suffix}"
      end
    end
  end
end
