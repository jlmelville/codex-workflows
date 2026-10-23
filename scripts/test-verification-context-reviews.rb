# frozen_string_literal: true

require "open3"
require "tmpdir"

module VerificationContextReviewTests
  ID = "SCR-20000101-000001"
  PATHS = ["/evidence/capture/text", "/evidence/checks"].freeze
  CHECKER = File.expand_path("check-verification-context.rb", __dir__)

  def self.copy(value)
    JSON.parse(JSON.generate(value))
  end

  def self.fixture
    {"mode" => "detail", "records" => [{
      "accepted" => {"id" => ID, "path" => "accepted.md", "body" => "The fixture had 40 rows and 3 repetitions.",
                     "frontmatter" => {"originating_candidate_ids" => ["RC-20000101T000000Z-000001"],
                                       "decisive_evidence_refs" => %w[capture checks], "observed_behavior_refs" => ["order"]}},
      "verification_proposals" => [{"id" => "VP-20000101T000000Z-000001", "path" => "proposal.md",
                                    "frontmatter" => {"decisive_evidence_refs" => %w[capture checks], "observation_ref" => "order",
                                                      "source_scope" => {"text" => "Prompted fixture", "claim_limits_refs" => [{"$ref" => "#/records/0/claim_limits/scope"}]},
                                                      "intake_digest" => "1" * 64}}],
      "observations" => {"order" => {"text" => "The smoke preceded follow-up.",
                                     "evidence_refs" => [{"$ref" => "#/records/0/evidence/capture"}]}},
      "evidence" => {"capture" => {"text" => "The capture acquired 20 native samples and recovered source locations.",
                                   "claim_limits_refs" => [{"$ref" => "#/records/0/claim_limits/attribution"}]},
                     "checks" => "Assertions checked native source locations after recovery for captured samples."},
      "claim_limits" => {"scope" => "The tested fixture only.", "attribution" => "Exclusive sampled instruction-pointer attribution.",
                         "unverified_claims" => ["Later-use effectiveness.", "Comparative improvement."]}
    }]}
  end

  def self.manager(document, manifest = {"schema_version" => 1, "reviews" => []})
    VerificationContextCheck::ReviewManifest.new(document, VerificationContextCheck.run(document), manifest)
  end

  def self.manifest(document, verdict: "distinct_evidence", context: [])
    checker = manager(document)
    prepared = checker.prepare
    raise "review fixture must have exactly one factual candidate" unless prepared.fetch("reviews").length == 1

    review = prepared.fetch("reviews").first
    raise "unexpected fixture endpoints" unless review.fetch("paths").sort == PATHS.sort

    review["context_paths"] = context
    review["binding"]["dependencies"] = checker.dependencies(ID, PATHS, context)
    review.merge!("verdict" => verdict, "rationale" => "Measurement and assertion serve distinct evidentiary roles.", "reviewed_at" => "2000-01-01T00:00:00Z")
    prepared
  end

  def self.review(report)
    finding = report.fetch("findings").find { |item| item.fetch("paths").map { |path| path.delete_prefix("#/records/0") }.sort == PATHS.sort }
    raise "reviewed pair disappeared unexpectedly" unless finding

    finding.fetch("review")
  end

  def self.stale(document, saved, changed_path)
    result = review(manager(document, saved).annotate)
    unless result["freshness"] == "stale" && !result.key?("verdict") && result.dig("previous_review", "verdict") == "distinct_evidence" &&
        result.fetch("changed_paths").include?("#/records/0#{changed_path}")
      raise "changed dependency remained accepted: #{changed_path}"
    end
  end

  def self.run
    document = fixture
    saved = manifest(document)
    before = JSON.generate([document, saved])
    report = manager(document, saved).annotate
    raise "current review lost" unless review(report)["freshness"] == "current" && report.dig("review_summary", "current", "distinct_evidence") == 1
    raise "read-only review mutated its inputs" unless before == JSON.generate([document, saved])
    raise "current preparation renewed a judgment" unless manager(document, saved).prepare == saved

    VerificationContextCheck::ReviewManifest::VERDICTS.each do |verdict|
      result = manager(document, manifest(document, verdict: verdict)).annotate
      failure = VerificationContextCheck::ReviewManifest.failed?(result, require_reviewed: true)
      raise "review verdict lost its separate meaning: #{verdict}" unless result.dig("review_summary", "current", verdict) == 1 && !!failure == (verdict == "duplicate")
    end
    pending = manager(document).annotate
    raise "missing review bypassed the gate" unless pending.dig("review_summary", "unreviewed") == 1 && VerificationContextCheck::ReviewManifest.failed?(pending, require_reviewed: true)
    prepared = manager(document).prepare
    blank = manager(document, prepared).annotate
    unless review(blank) == {"freshness" => "unreviewed", "reasons" => ["blank_judgment"]} &&
        blank.dig("review_summary", "unreviewed") == 1 && blank.dig("review_summary", "current").values.sum.zero? &&
        !VerificationContextCheck::ReviewManifest.failed?(blank) && VerificationContextCheck::ReviewManifest.failed?(blank, require_reviewed: true)
      raise "prepared blank judgment was rejected, approved, or bypassed the review gate"
    end
    raise "preparation failed to round-trip its own blank output" unless manager(document, prepared).prepare == prepared
    changed_blank = copy(document)
    changed_blank["records"][0]["evidence"]["capture"]["text"] += " Changed."
    result = review(manager(changed_blank, prepared).annotate)
    unless result["freshness"] == "unreviewed" && result["reasons"] == %w[blank_judgment dependencies_changed] && !result.key?("previous_review")
      raise "changed blank binding was treated as a previous judgment"
    end
    inactive_blank = copy(document)
    inactive_blank["records"][0]["evidence"]["checks"] = "Purple hexagons moved sideways."
    result = manager(inactive_blank, prepared).annotate
    raise "inactive blank was treated as a reviewed judgment" unless result.dig("review_summary", "unreviewed") == 1 && result.dig("review_summary", "stale").zero? && result.dig("review_summary", "inactive") == 1
    reversed = copy(saved)
    reversed["reviews"][0]["paths"].reverse!
    raise "pair ordering changed identity" unless review(manager(document, reversed).annotate)["freshness"] == "current"
    sorted = lambda do |value|
      case value
      when Hash then value.keys.reverse.to_h { |name| [name, sorted.call(value.fetch(name))] }
      when Array then value.map { |child| sorted.call(child) }
      else value
      end
    end
    raise "object key order invalidated a review" unless review(manager(sorted.call(document), saved).annotate)["freshness"] == "current"

    ["The capture acquired 21 native samples and recovered source locations.",
      "The capture acquired 20 native samples and did not recover source locations.",
      "THE capture acquired 20 native samples and recovered source locations."].each do |text|
      changed = copy(document)
      changed["records"][0]["evidence"]["capture"]["text"] = text
      stale(changed, saved, "/evidence/capture")
    end
    mutations = {
      "/claim_limits/attribution" => ->(record) { record["claim_limits"]["attribution"] += " Changed." },
      "/claim_limits" => ->(record) { record["claim_limits"]["unverified_claims"] << "A further claim." },
      "/evidence/capture" => ->(record) { record["evidence"]["capture"]["claim_limits_refs"][0]["$ref"] = "#/records/0/claim_limits/scope" },
      "/accepted/frontmatter/originating_candidate_ids" => ->(record) { record["accepted"]["frontmatter"]["originating_candidate_ids"] << "RC-20000101T000000Z-000002" },
      "/verification_proposals/0/frontmatter/source_scope" => ->(record) { record["verification_proposals"][0]["frontmatter"]["source_scope"]["text"] += " Changed." },
      "/verification_proposals/0/frontmatter/intake_digest" => ->(record) { record["verification_proposals"][0]["frontmatter"]["intake_digest"] = "2" * 64 },
      "/accepted/frontmatter/source_scope" => ->(record) { record["accepted"]["frontmatter"]["source_scope"] = "Newly supplied provenance." },
      "/accepted/frontmatter/decisive_evidence_refs/1" => ->(record) { record["accepted"]["frontmatter"]["decisive_evidence_refs"].pop }
    }
    mutations.each do |path, mutate|
      changed = copy(document)
      mutate.call(changed["records"][0])
      stale(changed, saved, path)
    end
    changed = copy(document)
    changed["records"][0]["verification_proposals"] << {"id" => "VP-20000101T000000Z-000002", "frontmatter" => {"decisive_evidence_refs" => ["capture"]}}
    stale(changed, saved, "/verification_proposals/1/frontmatter/decisive_evidence_refs/0")

    linked = copy(document)
    linked["records"][0]["evidence"]["capture"]["evidence_refs"] = [{"$ref" => "#/records/0/evidence/auxiliary"}]
    linked["records"][0]["evidence"]["auxiliary"] = "Purple hexagons remained stationary."
    linked_saved = manifest(linked)
    linked["records"][0]["evidence"]["auxiliary"] = "Purple hexagons moved sideways."
    stale(linked, linked_saved, "/evidence/auxiliary")
    extra = manifest(document, context: ["/accepted/body"])
    changed = copy(document)
    changed["records"][0]["accepted"]["body"] += " Six repetitions."
    stale(changed, extra, "/accepted/body")
    changed["records"][0]["evidence"]["unrelated"] = "Purple hexagons moved sideways."
    raise "unrelated data invalidated a review" unless review(manager(changed, saved).annotate)["freshness"] == "current"
    proposal_context = copy(document)
    proposal_context["records"][0]["verification_proposals"][0]["body"] = {"text" => "This proposal introduces no new source change or accepted identity."}
    proposal_context["records"][0]["evidence"]["checks"] += " Retained artifact identity was rechecked before this proposal."
    body_paths = ["/evidence/checks", "/verification_proposals/0/body/text"]
    body_review = manager(proposal_context).prepare["reviews"].find { |item| item["paths"].sort == body_paths.sort }
    raise "proposal body fixture lost its candidate" unless body_review

    body_review.merge!(saved["reviews"].first.slice("verdict", "rationale", "reviewed_at"))
    body_manifest = {"schema_version" => 1, "reviews" => [body_review]}
    proposal_context["records"][0]["evidence"]["capture"]["text"] = "The capture acquired 21 native samples and recovered source locations."
    body_finding = manager(proposal_context, body_manifest).annotate["findings"].find do |item|
      item["paths"].sort == body_paths.map { |path| "#/records/0" + path }.sort
    end
    raise "incoming proposal citation pulled unrelated evidence into the binding" unless body_finding.dig("review", "freshness") == "current"
    missing_context = manifest(document, context: ["/missing"])
    raise "missing review context was treated as current" unless review(manager(document, missing_context).annotate)["reasons"].include?("context_missing")
    begin
      manager(document, missing_context).prepare
      raise "preparation accepted missing context"
    rescue VerificationContextCheck::InputError
      # Missing old context can be audited as stale, but cannot bind a new approval.
    end

    reordered = copy(document)
    rewrite = lambda do |value|
      case value
      when Hash then value.each { |name, child| (name == "$ref") ? value[name] = child.sub("#/records/0/", "#/records/1/") : rewrite.call(child) }
      when Array then value.each { |child| rewrite.call(child) }
      end
    end
    rewrite.call(reordered)
    reordered["records"].unshift({"accepted" => {"id" => "SCR-20000101-000002"}, "observations" => {}, "evidence" => {}, "claim_limits" => {}})
    moved = manager(reordered, saved).annotate
    raise "record batch order invalidated a review" unless moved.dig("review_summary", "current", "distinct_evidence") == 1

    bumped = copy(saved)
    bumped["reviews"][0]["binding"]["version"] += 1
    result = review(manager(document, bumped).annotate)
    raise "binding version silently reused a judgment" unless result["freshness"] == "stale" && result["reasons"] == ["binding_version_changed"]
    prepared = manager(document, bumped).prepare["reviews"].first
    raise "stale preparation retained approval" unless prepared.values_at("verdict", "rationale", "reviewed_at") == [nil, "", nil] && prepared.dig("binding", "version") == 1

    disappeared = copy(document)
    disappeared["records"][0]["evidence"]["checks"] = "Purple hexagons moved sideways."
    inactive = manager(disappeared, saved).annotate
    raise "disappearing candidate silently lost its review" unless inactive.dig("review_summary", "inactive") == 1 && inactive.dig("review_summary", "stale") == 1 && VerificationContextCheck::ReviewManifest.failed?(inactive, require_reviewed: true)
    raise "preparation discarded an inactive review" unless manager(disappeared, saved).prepare["reviews"].include?(saved["reviews"].first)
    removed = copy(document)
    removed["records"][0]["evidence"].delete("checks")
    result = manager(removed, saved).annotate["inactive_reviews"].first["review"]
    raise "removed endpoint was not reported" unless result["reasons"].include?("endpoint_missing")

    renumbered = copy(document)
    record = renumbered["records"][0]
    record["evidence"]["capture-new"] = record["evidence"].delete("capture")
    record["accepted"]["frontmatter"]["decisive_evidence_refs"][0] = "capture-new"
    record["verification_proposals"][0]["frontmatter"]["decisive_evidence_refs"][0] = "capture-new"
    record["observations"]["order"]["evidence_refs"][0]["$ref"] = "#/records/0/evidence/capture-new"
    result = manager(renumbered, saved).annotate
    raise "renumbered evidence inherited approval" unless result.dig("review_summary", "unreviewed") == 1 && result.dig("review_summary", "inactive") == 1
    exact = copy(document)
    exact["records"][0]["evidence"]["checks"] = exact["records"][0]["evidence"]["capture"]["text"]
    exact_saved = manifest(exact)
    raise "review suppressed an exact duplicate" unless VerificationContextCheck::ReviewManifest.failed?(manager(exact, exact_saved).annotate)
    broken = copy(document)
    broken["records"][0]["evidence"]["capture"]["claim_limits_refs"][0]["$ref"] = "#/records/0/claim_limits/missing"
    raise "review suppressed a broken reference" unless VerificationContextCheck::ReviewManifest.failed?(manager(broken, saved).annotate)

    invalid = [[], {"schema_version" => 2, "reviews" => []}]
    [->(entry) { entry["verdict"] = "supported" }, ->(entry) { entry["rationale"] = " " },
      ->(entry) { entry["reviewed_at"] = "yesterday" }, ->(entry) { entry["context_paths"] = ["#/records/0/evidence/capture"] },
      ->(entry) { entry["binding"]["dependencies"] = {"/evidence/capture" => "wrong-hash"} }].each do |mutate|
      bad = copy(saved)
      mutate.call(bad["reviews"].first)
      invalid << bad
    end
    conflict = copy(saved)
    conflict["reviews"] << copy(conflict["reviews"].first).merge("paths" => PATHS.reverse)
    invalid << conflict
    invalid.each do |value|
      begin
        manager(document, value)
      rescue VerificationContextCheck::InputError
        next
      end
      raise "invalid review manifest accepted"
    end
    partial = copy(saved)
    partial["reviews"] << copy(partial["reviews"].first).merge("accepted_id" => "SCR-20000101-000003")
    raise "partial input discarded another record's review" unless manager(document, partial).prepare == partial
    cli_tests(document, saved, bumped)
    prepared_review_tests
  end

  def self.prepared_review_tests
    document = {"mode" => "detail", "records" => Array.new(9) do |index|
      record = fixture.fetch("records").first
      record["accepted"]["id"] = "SCR-20000101-%06x" % (index + 1)
      rewrite = lambda do |value|
        case value
        when Hash then value.each { |name, child| (name == "$ref") ? value[name] = child.sub("#/records/0/", "#/records/#{index}/") : rewrite.call(child) }
        when Array then value.each { |child| rewrite.call(child) }
        end
      end
      rewrite.call(record)
      record
    end}
    prepared = manager(document).prepare
    verdicts = %w[unresolved_provenance unresolved_provenance distinct_evidence distinct_context]
    prepared.fetch("reviews").drop(5).each_with_index do |entry, index|
      entry.merge!("verdict" => verdicts.fetch(index), "rationale" => "Retain the scoped reviewed judgment.", "reviewed_at" => "2000-01-01T00:00:00Z")
    end
    before = JSON.generate([document, prepared])
    report = manager(document, prepared).annotate
    expected = Array.new(5) do |index|
      "check-verification-context.rb: unreviewed overlap (blank judgment): #/records/#{index}/evidence/capture/text <-> #/records/#{index}/evidence/checks"
    end.join("\n") + "\n"
    raise "prepared judgments were renewed or current reviews changed" unless manager(document, prepared).prepare == prepared && JSON.generate([document, prepared]) == before
    raise "five prepared blanks were not classified separately from four current reviews" unless report.fetch("review_summary") == {
      "candidates" => 9, "current" => {"distinct_evidence" => 1, "distinct_context" => 1, "unresolved_provenance" => 2, "duplicate" => 0},
      "unreviewed" => 5, "stale" => 0, "inactive" => 0
    }
    Dir.mktmpdir("prepared-reviews.") do |directory|
      source = File.join(directory, "context.json")
      reviews = File.join(directory, "prepared.json")
      File.write(source, JSON.generate(document))
      File.write(reviews, JSON.generate(prepared))
      original = Dir.children(directory).sort.to_h { |name| [name, File.binread(File.join(directory, name))] }
      stdout, stderr, status = Open3.capture3(CHECKER, "--file", source, "--reviews", reviews, "--require-reviewed")
      raise "prepared review gate did not exit 1 with all five exact path diagnostics" unless status.exitstatus == 1 && stderr == expected && JSON.parse(stdout) == report
      raise "prepared review gate changed source or manifest" unless original == Dir.children(directory).sort.to_h { |name| [name, File.binread(File.join(directory, name))] }

      values = ["distinct_evidence", "Reviewed rationale.", "2000-01-01T00:00:00Z"]
      (1..6).each do |mask|
        partial = copy(prepared)
        %w[verdict rationale reviewed_at].each_with_index do |name, index|
          partial["reviews"][0][name] = values[index] if mask[index] == 1
        end
        File.write(reviews, JSON.generate(partial))
        stdout, stderr, status = Open3.capture3(CHECKER, "--file", source, "--reviews", reviews, "--require-reviewed")
        raise "partially completed judgment was accepted as a prepared blank" unless status.exitstatus == 2 && stdout.empty? && stderr.include?("review judgment must be complete or prepared blanks")
      end
      malformed = copy(prepared)
      malformed["reviews"][0]["binding"]["dependencies"] = {"/evidence/capture" => "invalid-digest"}
      File.write(reviews, JSON.generate(malformed))
      stdout, stderr, status = Open3.capture3(CHECKER, "--file", source, "--reviews", reviews, "--require-reviewed")
      raise "blank judgment bypassed malformed binding validation" unless status.exitstatus == 2 && stdout.empty? && stderr.include?("review binding requires")
    end
  end

  def self.cli_tests(document, saved, stale)
    Dir.mktmpdir("verification-reviews.") do |directory|
      source = File.join(directory, "context.json")
      reviews = File.join(directory, "reviews.json")
      File.write(source, JSON.generate(document))
      File.write(reviews, JSON.generate(saved))
      baseline = Dir.children(directory).sort.to_h { |name| [name, File.binread(File.join(directory, name))] }
      run = lambda do |args, status|
        stdout, stderr, actual = Open3.capture3(CHECKER, "--file", source, *args)
        payload = (status == 2) ? nil : JSON.parse(stdout)
        gate_failure = payload && args.include?("--require-reviewed") &&
          (payload.dig("review_summary", "unreviewed").positive? || payload.dig("review_summary", "stale").positive?)
        valid_streams = if status == 2
          stdout.empty? && stderr.start_with?("check-verification-context.rb:")
        elsif gate_failure
          !stderr.empty? && stderr.lines.all? { |line| line.start_with?("check-verification-context.rb:") }
        else
          stderr.empty?
        end
        raise "review CLI stream/status contract changed: #{args.inspect}: #{stderr}" unless actual.exitstatus == status && valid_streams

        payload
      end
      run.call(["--require-reviewed"], 1)
      run.call(["--reviews", reviews, "--require-reviewed"], 0)
      raise "CLI preparation renewed reviews" unless run.call(["--reviews", reviews, "--prepare-reviews"], 0) == saved
      raise "CLI preparation inferred judgments" unless run.call(["--prepare-reviews"], 0)["reviews"].all? { |entry| entry["verdict"].nil? }
      run.call(["--reviews", reviews, "--prepare-reviews", "--require-reviewed"], 2)
      run.call(["--reviews", directory], 2)
      run.call(["--reviews", "-"], 2)
      run.call(["--reviews", File.join(directory, "missing")], 2)
      raise "checking wrote source, manifest, or other files" unless baseline == Dir.children(directory).sort.to_h { |name| [name, File.binread(File.join(directory, name))] }
      File.write(reviews, JSON.generate(stale))
      stale_bytes = File.binread(reviews)
      run.call(["--reviews", reviews, "--require-reviewed"], 1)
      run.call(["--reviews", reviews], 0)
      run.call(["--reviews", reviews, "--prepare-reviews"], 0)
      raise "stale audit or preparation rewrote the saved review" unless File.binread(reviews) == stale_bytes
      File.write(reviews, "[")
      run.call(["--reviews", reviews], 2)
      File.write(reviews, JSON.generate(manifest(document, verdict: "duplicate")))
      run.call(["--reviews", reviews], 1)
    end
  end
end
