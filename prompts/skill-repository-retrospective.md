# Skill Repository Retrospective Prompt

Audit this `codex-workflows` repository as a public skill system, not as an
ordinary codebase and not as a review of personal retrospective state.

Use this periodically after several skill-driven updates. Do not edit files,
create commits, sync installed skills, or open PRs unless explicitly asked.
Produce a report in chat.

Inspect:

- `skills/*/SKILL.md` trigger descriptions and core workflow guidance;
- `skills/*/agents/openai.yaml` display metadata and default prompts;
- `skills/*/references/` for duplicated or drifting detailed guidance;
- bundled scripts under `skills/*/scripts/`;
- root scripts and the installer ownership contract in `install.sh`;
- repository instructions in `AGENTS.md`;
- `.github/workflows/` and `.github/dependabot.yml`, including pinned tool
  acquisition and update ownership;
- prompts and recent source commits;
- managed runtime parity, when the installed runtime is available.

Do not require or inspect `CODEX_WORKFLOWS_STATE_DIR` for this artifact audit.
Inbox reports, verdict history, accepted evidence, drafts, ledgers, learning
audits, and cadence are disposable external state owned by the separate
learning-process retrospective.

Focus on:

- duplicated guidance across skills;
- trigger overlap or unclear skill boundaries;
- top-level sequences that lack a non-obvious constraint, ordering hazard, or
  observed failure that earns their always-read context cost;
- conflicting action authority across trigger descriptions, default prompts,
  skill bodies, references, and repository instructions;
- vague brevity or style directives that do not say which evidence, caveats,
  decisions, or next actions must survive shortening;
- skill bloat, including one-off bullets without concrete failure signals;
- local conventions leaking into general-purpose skills;
- guidance that should move from `SKILL.md` into references;
- deterministic behavior that should become a script or validator;
- bundled scripts that are stale, too narrow, duplicated, or under-validated;
- CI or installer drift that can change validation without a repository diff;
- missing cross-links between related skills;
- no-action findings where existing guidance is already enough.

Run a semantic-compression pass in addition to those checks:

1. Inventory operative rules and clauses across `SKILL.md` and routed
   references in temporary working material. Cluster them by the action,
   authority boundary, required observation, or success condition they
   produce; report only the useful clusters and findings.
2. Flag several cases leading to the same action, headings that have become
   incident lists, references that reduced default loading without reducing
   decision duplication, exact mechanics repeated across cases, and casebooks
   that repeat one witness shape under different narratives.
3. Classify each flagged unit as default judgment, routed mechanics, optional
   case, or external verification only. Treat a reference as a loading
   mechanism rather than a semantic category.
4. Recommend a rewrite only when the crosswalk can remove duplicated operative
   clauses or incident-shaped branches without merging distinguishable actions,
   constraints, witnesses, or completion claims. Do not use a numerical
   semantic score or threshold.

Keep two admission questions separate:

- Evidence admission asks whether the lesson has a concrete failure signal or
  other decisive grounding.
- Semantic curation asks whether it adds a decision to the public corpus.

The first occurrence can be well grounded without earning a new clause, and a
recurrence can strengthen verification without adding public guidance. Keep
the existing concrete-failure-signal checks.

Classify every recommendation as one of:

- `implement-now`: the decision and implementation are justified, with no
  distinct later behavioral claim to test;
- `implement-now-verify-later`: the decision and implementation are justified,
  while ordinary downstream behavior remains unverified;
- `candidate-defer`: a named decision cannot yet be justified because specific
  evidence is missing;
- `draft`: a coherent new-skill kernel is not ready for activation;
- `ledger`: an accepted implementation blocker, maintenance threshold, or
  cross-report hypothesis needs an executable drain; or
- `no-action`: no public or live operational change is warranted.

Before using `candidate-defer`, state exactly what decision cannot be made now
and what evidence is missing. Behavioral uncertainty after a justified,
reversible implementation is `implement-now-verify-later`, not a deferral.

Every proposed candidate deferral, draft, or ledger must include a liveness
argument: the durable trigger predicate, the existing process that observes
it, the route by which that observer discovers the record, the probe it runs,
the next action, and the close condition. `review-queue` is a routing surface,
not an observer. "Next use" is invalid unless an existing emitted record or
destination-matched query makes that use observable. Do not propose a new
destination-use matcher merely to preserve a recommendation that is already
safe to implement and verify later.

For casebooks, confirm that each capsule is sanitized, optional, skill-local,
organized by reasoning problem or witness shape, and admitted for a distinct
plausible wrong implementation or observation boundary rather than provenance.
Flag uncurated collections of report narratives.

Reference word and line totals are not proof of semantic bloat. Treat checked
payload budgets as circuit breakers against unbounded growth, then use semantic
review to decide what to consolidate, demote, or remove; never advance a budget
merely to clear a finding.

Report using this shape:

```md
## Skill Repository Retrospective

### High-Value Consolidations
### Bloat Or Drift Risks
### Semantic Compression Findings
### Trigger Boundary Issues
### Script Opportunities
### Reference/Structure Improvements
### No-Action Findings
### Recommended Edits
```

For each recommended edit, include file and line evidence, current location,
proposed destination, reason, risk if omitted, and its classification from the
preceding list. Prefer pruning, consolidating, or clarifying existing skills
over creating new skills.

End with a complete sanitized diagnosis suitable for a cold external audit
record and a list of unresolved executable consequences. Do not write external
state from this report-only audit; `$learning-process-review` owns action
creation and audit recording after its applicable mutation gate.

Report `Structural status: healthy` or `findings present` from this public
evidence. Do not claim behavioral effectiveness from corpus organization,
validation, or source history. Use: `Behavioral effectiveness: unknown —
Insufficient downstream evidence to assess behavioral effectiveness.`
