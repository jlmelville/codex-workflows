# Learning Process Retrospective Prompt

Review the disposable retrospective state beneath
`CODEX_WORKFLOWS_STATE_DIR` as a learning process. Do not audit public skill
artifacts except where external evidence identifies a specific producer or
triage problem. Do not edit public source or external state unless explicitly
asked; report findings in chat first.

If the state variable is unset or unavailable, stop and report that this audit
cannot run. Do not invent a fallback location.

Inspect only the external records needed to evaluate:

- distributions of accept, defer, reject, split, merge, and no-change verdicts;
- repeated report-construction or routing mistakes;
- reusable kernels lost inside repository-specific wrappers;
- deferrals, drafts, or ledger actions whose review triggers fired;
- deferrals repeatedly refreshed without a concrete drain;
- implemented guidance that remains unverified or became contradicted;
- whether earlier producer feedback changed later candidate quality;
- active work domains that appear absent from intake, without assuming unequal
  report volume is automatically a defect.

Treat synchronized state as potentially exposed. Do not reproduce secrets,
private source, raw transcripts, unredacted local paths, or unnecessary private
repository names in the report.

Report:

```md
## Learning Process Retrospective

### Intake Quality
### Verdict And Deferral Patterns
### Draft And Ledger Drains
### Verification Health
### Producer Feedback Candidates
### Cleanup Candidates
### No-Action Findings
### Proposed Next Review Trigger
```

Recommend a `$skill-retro` or template change only when the same producer error
recurs across batches or one occurrence is especially decisive. Recommend
deleting external history that no longer improves future judgment. Keep public
source changes behind the ordinary `$skill-retro-triage` implementation gate.
