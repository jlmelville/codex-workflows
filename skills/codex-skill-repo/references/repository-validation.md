# Repository Validation

Use this reference when a skill-repository change needs more than the core
validator and installed-copy check.

## Skill And Script Validation

For new or substantially changed skills, run the system quick validator when
available:

```sh
python /path/to/quick_validate.py skills/<skill-name>
```

If the validator needs Python packages such as PyYAML, run it through `uv` and
follow `$uv-sandbox-workflow` so caches live under `/tmp`.

For bundled scripts, prefer validation that does not write artifacts into
`skills/`, such as in-memory parsing or caches under `/tmp`. Run representative
behavior checks and remove generated test artifacts such as `__pycache__`
before staging.

Markdown templates and documentation are subject to repository-path
validation. Use real existing repository paths in examples, or avoid
placeholder text shaped like a repository-relative path when no such file
exists.

## Maintainer Tool Ownership

Inventory tools in three columns before changing bootstrap or parity policy:
repository-maintainer checks, downstream installed-skill dependencies, and
optional enhancements. Do not install or version-check a downstream-only tool
merely because its command appears in skill prose.

Prefer the host platform's package manager for a long-lived maintainer CLI when
the repository expects one shared executable. Use exact temporary isolation for
CI reproduction or an intentionally pinned validator. Parity diagnostics must
print the resolved executable and version; do not silently prepend an ignored
persistent environment to `PATH`. Remove pins and parity checks for tools the
workflow does not execute.

For language runtimes, distinguish the maintainer toolchain from the execution
contract of installed helpers. A version-manager file in the source repository
can select the maintainer interpreter without controlling a helper invoked from
another working directory. If installed helpers own an exact runtime contract,
bind selection in their shebang, launcher, or owning caller and retain an early
in-process guard. Validate the actual executable shebang from a directory with
a conflicting version-manager file; a shell command that explicitly invokes a
known interpreter does not test shebang selection.

Do not infer a downstream Bundler dependency merely because maintainers use a
locked gem tool. Keep installed helpers on the standard library when that is
their contract, and document Bundler as development-only unless runtime code
actually invokes it.

Use `bundle install --quiet` for routine dependency setup. Bundler's `exec`
subcommand has no native quiet switch; do not invent one. For pass/fail checks
run through `bundle exec`, capture both streams and discard them only on
success, replaying the complete captured output when the command fails.

Treat a locked Ruby gem and its generated executable wrapper as separate
availability surfaces. When `bundle check` succeeds but host packaging omits
the wrapper from `PATH`, invoke the locked entry point through RubyGems under
the selected Bundler instead of adding a persistent gem directory to `PATH`:

```sh
bundle exec ruby -rrubygems \
  -e 'load Gem.activate_bin_path("standard", "standardrb")' -- \
  --format quiet path/to/script.rb
```

Use the repository's versioned Bundler command when required. Reserve this
mechanic for repository-owned locked tools with a known gem and executable;
ordinary host CLIs should continue to use normal executable discovery.

## Workflow Validation

Use `${HOME}/.agents/skills/...` command paths inside installed
skill workflows unless the text explicitly says it is source-repository only.

If the repository's generic workflow audit is unavailable, run `actionlint`,
`zizmor`, and ShellCheck as applicable.

When adding or changing a manual validation lane, push it, trigger it once with
`gh workflow run`, watch it to completion, and fix setup failures.

## Shared Policy And Mirrors

When changing shared tool policy, common command examples, or duplicated
bundled scripts, search the whole skill tree for stale parallel guidance before
committing. If two scripts are intentionally mirrored across skills, update
both or record why they differ.

## Drift Audit

Run the advisory drift and bloat audit before or after consolidation work:

```sh
./scripts/audit-skill-drift.rb
```

Use `--strict-hard --hard-only` for hard installed-runtime failures. Use
`--strict` only when the branch should remove every untriaged finding. Review
findings cover instructional-payload growth, long descriptions, trigger
overlap, repeated helpers or commands, machine paths, and repo-relative script
paths.

Accepted advisory findings live in `scripts/audit-skill-drift-triage.tsv`;
each row records the audit section, a row substring to match, and the rationale
for accepting that finding. Keep repeated-command triage patterns stable at the
command-label level. Their reviewed per-file hit counts live separately in
`scripts/audit-skill-drift-command-baseline.tsv` as
`command<TAB>path<TAB>hit-count` rows.

The audit continues to print current absolute totals, then compares every
tracked command with that per-file baseline. A new path or an increased count
on an existing path produces an untriaged `Repeated Command Growth` finding;
unchanged and reduced repetition do not. Review the named delta before updating
the baseline. Never regenerate or advance it automatically merely to make the
audit green.

`scripts/audit-skill-drift-payload-baseline.tsv` caps the physical lines and
whitespace-normalized characters in each `SKILL.md`, each skill's instructional
Markdown, and repository instructional Markdown. The character ceiling prevents
line reflow from concealing payload growth; neither measure is a semantic score.
Growth is reported for explicit review, and lowering a cap is allowed. The
audit also compares a changed baseline with `HEAD` or `HEAD^`, so an increase or
new skill entry remains visible during ordinary maintenance. A separately
accepted policy or portfolio decision must own that change. Never rewrite
unrelated skills to manufacture room beneath an aggregate ceiling; review the
affected addition and any proposed local reduction independently.

## Pre-Commit Review

Before committing, stage only intended files and inspect:

```sh
git diff --cached --stat
git diff --cached --name-only
```

After publication is authorized under the main skill's `Authority` section,
commit the inspected paths and push using the target repository's convention.
