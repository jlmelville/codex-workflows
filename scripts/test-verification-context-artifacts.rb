# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

module VerificationContextArtifactTests
  BASE = VerificationContextReviewTests

  def self.manager(document, saved, roots)
    VerificationContextCheck::ReviewManifest.new(document, VerificationContextCheck.run(document), saved, artifact_roots: roots)
  end

  def self.review(report, index = 0)
    report.fetch("findings").find { |finding| finding.fetch("paths").first.start_with?("#/records/#{index}/") }.fetch("review")
  end

  def self.assert_summary(report, current:, stale: 0, unreviewed: 0)
    summary = report.fetch("review_summary")
    unless summary.dig("current", "distinct_evidence") == current && summary["stale"] == stale && summary["unreviewed"] == unreviewed
      raise "unexpected artifact freshness summary: #{summary.inspect}"
    end
  end

  def self.fixture(directory)
    %w[shared smoke followup].each { |name| File.binwrite(File.join(directory, name), "#{name} capture bytes\x00") }
    document = {"mode" => "detail", "records" => Array.new(3) do |index|
      record = JSON.parse(JSON.generate(BASE.fixture).gsub("#/records/0/", "#/records/#{index}/")).fetch("records").first
      record["accepted"]["id"] = "SCR-20000101-%06x" % (index + 1)
      record
    end}
    saved = BASE.manager(document).prepare.merge("schema_version" => 2, "artifacts" => %w[shared smoke followup].to_h do |id|
      [id, {"root" => "fixture", "path" => id}]
    end)
    saved.fetch("reviews").each { |entry| entry.merge!("verdict" => "distinct_evidence", "rationale" => "Reviewed fixture artifacts.", "reviewed_at" => "2000-01-01T00:00:00Z") }
    saved["reviews"][0]["artifact_refs"] = %w[shared smoke]
    saved["reviews"][1]["artifact_refs"] = %w[shared followup]
    roots = {"fixture" => directory}
    pending = manager(document, saved, roots).annotate
    assert_summary(pending, current: 1, stale: 2)
    prepared = manager(document, saved, roots).prepare
    raise "adding external dependencies silently retained approval" unless prepared.fetch("reviews").take(2).all? { |entry| entry.values_at("verdict", "rationale", "reviewed_at") == [nil, "", nil] }
    raise "adding dependencies renewed unrelated review" unless prepared["reviews"][2] == saved["reviews"][2]
    prepared.fetch("reviews").take(2).each { |entry| entry.merge!(saved["reviews"].first.slice("verdict", "rationale", "reviewed_at")) }
    [document, prepared, roots]
  end

  def self.assert_changed(document, saved, roots, id, current: 2, stale: 1)
    report = manager(document, saved, roots).annotate
    assert_summary(report, current: current, stale: stale)
    ref = {"$ref" => "#/external_artifacts/#{id}"}
    unless review(report).fetch("freshness") == "stale" && review(report).fetch("changed_artifact_refs").include?(ref) &&
        !review(report).key?("verdict") && review(report).dig("previous_review", "verdict") == "distinct_evidence" &&
        VerificationContextCheck::ReviewManifest.failed?(report, require_reviewed: true)
      raise "external artifact change retained current approval"
    end
    report
  end

  def self.run
    Dir.mktmpdir("external-review-artifacts.") do |directory|
      document, saved, roots = fixture(directory)
      before = JSON.generate([document, saved])
      report = manager(document, saved, roots).annotate
      assert_summary(report, current: 3)
      unless report.fetch("external_artifacts").keys.sort == %w[followup shared smoke] &&
          review(report)["artifact_coverage"] == "declared" && review(report, 2)["artifact_coverage"] == "json_only"
        raise "artifact observations were duplicated or JSON-only coverage hidden"
      end
      raise "current preparation renewed artifact judgment" unless manager(document, saved, roots).prepare == saved
      raise "artifact checking mutated inputs" unless JSON.generate([document, saved]) == before
      changed_json = BASE.copy(document)
      changed_json["records"][0]["claim_limits"]["attribution"] += " Changed."
      json_report = manager(changed_json, saved, roots).annotate
      assert_summary(json_report, current: 2, stale: 1)
      raise "external binding suppressed JSON freshness" unless review(json_report)["reasons"] == ["dependencies_changed"] && !review(json_report).key?("changed_artifact_refs")
      changes(document, saved, roots, directory)
      unavailable(document, saved, roots, directory)
      invalid(document, saved, roots)
      cli(document, saved, roots, directory)
    end
  end

  def self.changes(document, saved, roots, directory)
    smoke = File.join(directory, "smoke")
    original = File.binread(smoke)
    metadata = File.stat(smoke)
    File.binwrite(smoke, original.sub("smoke", "SMOKE"))
    File.utime(metadata.atime, metadata.mtime, smoke)
    report = assert_changed(document, saved, roots, "smoke")
    observed = report.fetch("external_artifacts").fetch("smoke")
    raise "artifact change diagnostics lost hashes or reason" unless observed["changes"] == ["fingerprint_changed"] && observed["expected_fingerprints"].length == 1 && !observed["expected_fingerprints"].include?(observed["fingerprint"])
    prepared = manager(document, saved, roots).prepare
    raise "changed artifact preparation renewed judgment" unless prepared["reviews"][0].values_at("verdict", "rationale", "reviewed_at") == [nil, "", nil]
    raise "artifact preparation changed other judgments" unless prepared["reviews"].drop(1) == saved["reviews"].drop(1)
    assert_summary(manager(document, prepared, roots).annotate, current: 2, unreviewed: 1)
    raise "blank preparation cannot round-trip" unless manager(document, prepared, roots).prepare == prepared
    File.binwrite(smoke, original)
    File.utime(metadata.atime, metadata.mtime + 60, smoke)
    assert_summary(manager(document, saved, roots).annotate, current: 3)

    renamed = BASE.copy(saved)
    FileUtils.cp(smoke, File.join(directory, "renamed"))
    renamed["artifacts"]["smoke"]["path"] = "renamed"
    assert_changed(document, renamed, roots, "smoke")
    shared = File.join(directory, "shared")
    original_shared = File.binread(shared)
    File.binwrite(shared, original_shared + "changed")
    assert_changed(document, saved, roots, "shared", current: 1, stale: 2)
    File.binwrite(shared, original_shared)

    removed = BASE.copy(saved)
    removed["reviews"][0]["artifact_refs"].delete("smoke")
    assert_changed(document, removed, roots, "smoke")
    removed["artifacts"].delete("smoke")
    result = assert_changed(document, removed, roots, "smoke")
    raise "removed registry entry was silently forgotten" unless result.dig("external_artifacts", "smoke", "status") == "no_longer_declared"
    removed = BASE.copy(saved)
    removed["reviews"][0].delete("artifact_refs")
    assert_changed(document, removed, roots, "smoke")
    added = BASE.copy(saved)
    added["reviews"][0]["artifact_refs"] << "followup"
    assert_changed(document, added, roots, "followup")

    Dir.mktmpdir("relocated-review-artifacts.") do |other|
      %w[shared smoke followup].each { |name| FileUtils.cp(File.join(directory, name), other) }
      assert_summary(manager(document, saved, {"fixture" => other}).annotate, current: 3)
    end
    partial = BASE.copy(document)
    partial["records"] = partial["records"].take(1)
    raise "partial preparation discarded other artifact reviews" unless manager(partial, saved, roots).prepare == saved
  end

  def self.unavailable(document, saved, roots, directory)
    report = manager(document, saved, {}).annotate
    assert_summary(report, current: 1, stale: 2)
    raise "missing roots were treated as checked" unless report.fetch("external_artifacts").values.all? { |item| item["status"] == "root_unavailable" }
    smoke = File.join(directory, "smoke")
    original = File.binread(smoke)
    File.unlink(smoke)
    report = assert_changed(document, saved, roots, "smoke")
    raise "missing artifact status hidden" unless report.dig("external_artifacts", "smoke", "status") == "missing"
    begin
      manager(document, saved, roots).prepare
      raise "preparation rebound unavailable artifact"
    rescue VerificationContextCheck::InputError => e
      raise unless e.message.include?("cannot prepare external artifact smoke: missing")
    end
    Dir.mkdir(smoke)
    report = assert_changed(document, saved, roots, "smoke")
    raise "directory was hashed as file" unless report.dig("external_artifacts", "smoke", "status") == "not_regular_file"
    Dir.rmdir(smoke)
    File.binwrite(smoke, original)
    unless Process.uid.zero?
      begin
        File.chmod(0, smoke)
        report = assert_changed(document, saved, roots, "smoke")
        raise "unreadable artifact was silently accepted" unless report.dig("external_artifacts", "smoke", "status") == "unreadable"
      ensure
        File.chmod(0o600, smoke)
      end
    end
    Dir.mktmpdir("outside-artifact-root.") do |outside|
      File.binwrite(File.join(outside, "capture"), original)
      File.unlink(smoke)
      File.symlink(File.join(outside, "capture"), smoke)
      report = assert_changed(document, saved, roots, "smoke")
      raise "artifact escaped its named root" unless report.dig("external_artifacts", "smoke", "status") == "outside_root"
      File.unlink(smoke)
      File.binwrite(smoke, original)
    end
  end

  def self.invalid(document, saved, roots)
    mutations = [
      ->(value) { value["artifacts"] = [] },
      ->(value) { value["artifacts"]["smoke"]["path"] = "../smoke" },
      ->(value) { value["artifacts"]["smoke"]["path"] = "/smoke" },
      ->(value) { value["artifacts"]["smoke"]["path"] = "./smoke" },
      ->(value) { value["artifacts"]["smoke"]["path"] = "smoke\0" },
      ->(value) { value["artifacts"]["smoke"]["root"] = "../root" },
      ->(value) { value["reviews"][0]["artifact_refs"] << "missing" },
      ->(value) { value["reviews"][0]["artifact_refs"] << "smoke" },
      ->(value) { value["reviews"][0]["binding"]["artifacts"]["smoke"] = "bad" }
    ]
    mutations.each do |mutate|
      value = BASE.copy(saved)
      mutate.call(value)
      begin
        manager(document, value, roots)
      rescue VerificationContextCheck::InputError
        next
      end
      raise "invalid external artifact manifest accepted"
    end
  end

  def self.cli(document, saved, roots, directory)
    source = File.join(directory, "context.json")
    manifest = File.join(directory, "reviews.json")
    File.write(source, JSON.generate(document))
    File.write(manifest, JSON.generate(saved))
    arguments = [BASE::CHECKER, "--file", source, "--reviews", manifest]
    root_args = ["--artifact-root", "fixture=#{directory}"]
    original = Dir.children(directory).sort.to_h { |name| [name, File.binread(File.join(directory, name))] }
    stdout, stderr, status = Open3.capture3(*arguments, *root_args, "--require-reviewed")
    raise "artifact CLI current gate failed" unless status.success? && stderr.empty? && JSON.parse(stdout) == manager(document, saved, roots).annotate
    stdout, stderr, status = Open3.capture3(*arguments, *root_args, "--prepare-reviews")
    raise "artifact CLI preparation renewed current reviews" unless status.success? && stderr.empty? && JSON.parse(stdout) == saved
    raise "artifact CLI wrote input or other files" unless original == Dir.children(directory).sort.to_h { |name| [name, File.binread(File.join(directory, name))] }

    smoke = File.join(directory, "smoke")
    File.binwrite(smoke, "new contents")
    stdout, stderr, status = Open3.capture3(*arguments, *root_args, "--require-reviewed")
    expected = "check-verification-context.rb: stale overlap: #/records/0/evidence/capture/text <-> #/records/0/evidence/checks; external artifacts: smoke at #{smoke}: fingerprint_changed\n"
    raise "artifact CLI lost exact pair/file diagnostic" unless status.exitstatus == 1 && stderr == expected
    assert_summary(JSON.parse(stdout), current: 2, stale: 1)
    stdout, stderr, status = Open3.capture3(*arguments, *root_args, "--prepare-reviews")
    prepared = JSON.parse(stdout)
    raise "artifact CLI did not blank changed judgment" unless status.success? && stderr.empty? && prepared["reviews"][0]["verdict"].nil? && prepared["reviews"].drop(1) == saved["reviews"].drop(1)
    File.write(manifest, JSON.generate(prepared))
    stdout, stderr, status = Open3.capture3(*arguments, *root_args, "--require-reviewed")
    raise "prepared artifact review bypassed gate" unless status.exitstatus == 1 && stderr.include?("unreviewed overlap (blank judgment)")
    assert_summary(JSON.parse(stdout), current: 2, unreviewed: 1)
    File.unlink(smoke)
    stdout, stderr, status = Open3.capture3(*arguments, *root_args, "--prepare-reviews")
    raise "unavailable artifact preparation did not fail cleanly" unless status.exitstatus == 2 && stdout.empty? && stderr.include?("cannot prepare external artifact smoke: missing")
    [[], ["--artifact-root", "fixture=other"], ["--artifact-root", "broken"], ["--artifact-root", ""]].each do |extra|
      flags = extra.empty? ? [] : root_args + extra
      stdout, stderr, status = Open3.capture3(*arguments, *flags, "--require-reviewed")
      if extra.empty?
        raise "missing root did not fail reviewed gate" unless status.exitstatus == 1 && stderr.include?("root_unavailable") && JSON.parse(stdout)
      else
        raise "malformed/repeated root was not usage error" unless status.exitstatus == 2 && stdout.empty? && stderr.include?("--artifact-root requires a unique NAME=DIR")
      end
    end
  end
end
