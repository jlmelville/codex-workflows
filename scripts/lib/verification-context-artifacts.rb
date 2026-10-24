# frozen_string_literal: true

require "digest"
require "json"
require "pathname"

module VerificationContextCheck
  class ExternalArtifacts
    NAME = /\A[a-z][a-z0-9_-]*\z/
    DIGEST = /\Asha256:[a-f0-9]{64}\z/

    def initialize(definitions, roots)
      unless definitions.is_a?(Hash) && definitions.all? { |id, locator| name?(id) && locator?(locator) }
        raise InputError, "artifacts require named IDs with root and relative file path locators"
      end
      unless roots.is_a?(Hash) && roots.all? { |name, path| name?(name) && path.is_a?(String) && !path.empty? && !path.include?("\0") }
        raise InputError, "artifact roots require NAME=DIR mappings"
      end
      @definitions = definitions
      @roots = roots.transform_values { |path| File.expand_path(path) }
      @observations = {}
      @expected = Hash.new { |hash, id| hash[id] = Set.new }
      @changes = Hash.new { |hash, id| hash[id] = Set.new }
    end

    def name?(value)
      value.is_a?(String) && value.match?(NAME)
    end

    def relative_path?(value)
      value.is_a?(String) && !value.empty? && !value.include?("\0") && !value.include?("\\") &&
        !Pathname.new(value).absolute? && value.split("/", -1).none? { |part| ["", ".", ".."].include?(part) }
    end

    def locator?(value)
      value.is_a?(Hash) && value.keys.sort == %w[path root] && name?(value["root"]) && relative_path?(value["path"])
    end

    def validate_review(review)
      refs = review.fetch("artifact_refs", [])
      receipts = review.fetch("binding").fetch("artifacts", {})
      unless refs.is_a?(Array) && refs.uniq == refs && refs.all? { |id| name?(id) && @definitions.key?(id) } &&
          receipts.is_a?(Hash) && receipts.all? { |id, digest| name?(id) && digest.is_a?(String) && digest.match?(DIGEST) }
        raise InputError, "review artifact_refs must name declared artifacts; binding.artifacts must map IDs to SHA-256 fingerprints"
      end
    end

    def reference(id)
      {"$ref" => "#/external_artifacts/#{id}"}
    end

    def observe(id)
      @observations[id] ||= begin
        locator = @definitions[id]
        result = {"manifest_path" => "#/artifacts/#{id}", "locator" => locator}
        if !locator
          result.merge("status" => "no_longer_declared")
        elsif !@roots.key?(locator.fetch("root"))
          result.merge("status" => "root_unavailable")
        else
          path = File.join(@roots.fetch(locator.fetch("root")), locator.fetch("path"))
          status = File.directory?(@roots.fetch(locator.fetch("root"))) ? read_file(path, @roots.fetch(locator.fetch("root")), locator) : {"status" => "root_unavailable"}
          result.merge("resolved_path" => path).merge(status)
        end
      end
    end

    def read_file(path, root, locator)
      resolved_root = File.realpath(root)
      resolved = File.realpath(path)
      unless resolved.start_with?(resolved_root.delete_suffix("/") + "/")
        return {"status" => "outside_root"}
      end
      return {"status" => "not_regular_file"} unless File.file?(resolved)

      File.open(resolved, File::RDONLY | File::NONBLOCK) do |stream|
        before = stream.stat
        return {"status" => "not_regular_file"} unless before.file?

        digest = Digest::SHA256.new
        while (chunk = stream.read(1024 * 1024))
          digest.update(chunk)
        end
        after = stream.stat
        signature = ->(info) { [info.dev, info.ino, info.size, info.mtime, info.ctime] }
        unless signature.call(before) == signature.call(after) && signature.call(after) == signature.call(File.stat(path))
          return {"status" => "changed_during_read"}
        end
        content = "sha256:#{digest.hexdigest}"
        fingerprint = Digest::SHA256.hexdigest(JSON.generate(["external-artifact-v1", locator.fetch("root"), locator.fetch("path"), content]))
        {"status" => "available", "content_sha256" => content, "fingerprint" => "sha256:#{fingerprint}"}
      end
    rescue Errno::ENOENT, Errno::ENOTDIR
      {"status" => "missing"}
    rescue SystemCallError, IOError => e
      {"status" => "unreadable", "error" => e.class.name}
    end

    def assess(review)
      refs = review.fetch("artifact_refs", [])
      previous = review.fetch("binding").fetch("artifacts", {})
      changed = (refs | previous.keys).select do |id|
        @expected[id] << previous[id] if previous.key?(id)
        observed = observe(id)
        reason = if !refs.include?(id)
          "reference_removed"
        elsif !previous.key?(id)
          "reference_added"
        elsif observed["status"] != "available"
          observed.fetch("status")
        elsif observed["fingerprint"] != previous[id]
          "fingerprint_changed"
        end
        @changes[id] << reason if reason
        reason
      end
      result = {"artifact_coverage" => refs.empty? ? "json_only" : "declared"}
      result["artifact_refs"] = refs.map { |id| reference(id) } unless refs.empty?
      result["changed_artifact_refs"] = changed.map { |id| reference(id) } unless changed.empty?
      result
    end

    def prepare(review)
      review.fetch("artifact_refs", []).sort.to_h do |id|
        observed = observe(id)
        unless observed["status"] == "available"
          raise InputError, "cannot prepare external artifact #{id}: #{observed.fetch("status")} at #{observed["resolved_path"] || observed.fetch("locator").fetch("root")}"
        end
        [id, observed.fetch("fingerprint")]
      end
    end

    def report
      @observations.sort.to_h do |id, observed|
        [id, observed.merge("expected_fingerprints" => @expected[id].to_a.sort, "changes" => @changes[id].to_a.sort)]
      end
    end
  end
end
