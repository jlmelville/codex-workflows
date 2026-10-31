# R formatting and lint maintenance

Run this task now. Keep the local Air and lintr installations and their R package CI gates on
validated, explicit versions. Include both tools in ordinary package development and CI by default,
while preserving explicit repository or user opt-outs.

## Settings and authority

Load `${XDG_CONFIG_HOME:-$HOME/.config}/codex-workflows/weekly-r-tooling-updates.yaml` when present.
Apply invocation overrides for this run only unless the user asks to save them. Settings are private
configuration outside Git; never store credentials or operational logs in them.

Require `github_host`, `github_account`, a nonempty `repositories` list of exact `owner/name`
identities, and `mode` (`review` or `upgrade`). Default to `review`. On first use, suggest settings
from the invoking message and available account metadata; ask only about unresolved scope or
authority. Save approved settings for later runs. Account access alone does not authorize a
repository or upgrade mode. See the
[configuration example](../README.md#r-tooling-maintenance-example).

Optional settings:

- `excluded_repositories`: exact identities that take precedence over the allowlist. Apply these
  exclusions before repository API calls, checkout inspection, cloning, or edits.
- `checkouts`: a map from allowed repository identities to existing local checkout paths. Expand
  home-directory notation. Use disposable clones for unmapped repositories; do not scan unrelated
  checkouts to populate this map.
- `local_environment`: the intended installation environment, such as WSL Ubuntu or this machine.
  Verify that the actual host matches before installing. `rscript` selects its Rscript executable
  when PATH does not select the intended R installation.
- `publication`: `pull_request` (default) or `direct`. Respect each repository's delivery policy.
  Direct publication cannot bypass required reviews or branch protection.
- `tool_opt_outs`: a map from allowed identities to lists containing `air`, `lintr`, or both.
  Preserve other explicit opt-outs found in repository instructions; report them separately from
  missing gates. Do not reinterpret an old version pin as an opt-out.

Review mode may download and exercise temporary tool installations and disposable source copies.
It does not change the active local tools, existing checkouts, saved settings, or GitHub state.
First-use settings are saved only with the user's approval.

Upgrade mode authorizes validated local tool installation, dependency installation needed for
validation, explicit CI version pins, missing formatting/lint gates, Air-owned R formatting, and
small lint fixes that preserve behavior. It also authorizes committing and publishing those changes,
merging this run's upgrade PRs after required checks and reviews, and justified CI reruns. Keep PR
merges bound to the validated head. Do not infer this authority from Dependabot merge settings.

Do not force-push, bypass reviews, alter unrelated branches, upgrade R or the OS, regenerate
documentation or bindings, or weaken lint rules and exclusions merely to obtain a pass. Behavioral
repairs and changes to repository opt-outs need separate authority. Continue independent work when
one tool or repository is blocked.

## Establish the baseline

Apply `$r-package-workflow`, `$github-actions-hardening`, and `$r-ci-hardening`; use
`$uv-sandbox-workflow` when invoking uv. Follow their current validation procedures. Read repository
instructions from mapped checkouts and the fresh remote default-branch tree.

Reuse the companion CI prompt's
[GitHub access checks](weekly-r-ci-updates.md#verify-github-cli-access)
and [checkout preservation procedure](weekly-r-ci-updates.md#preserve-local-work), including its
protected Git inspection wrapper, snapshots, comparisons, and disposable standalone clones. Limit
these operations to this prompt's resolved allowlist after exclusions. Refresh and edit only the
clones; preserve existing checkout files, index, branches, stashes, and commits. No local checkout
is required to maintain an explicitly allowed remote repository.

Record the resolved Air executable and installation method, its actual version, OS and architecture,
the selected Rscript and R version, `.libPaths()`, and the resolved lintr version and library. Reuse
the active installation method and intended user library; do not silently select another R or leave
a temporary candidate ahead of the normal executable on PATH.

For every allowed repository, confirm R package identity from root `DESCRIPTION`. Inspect the
current default branch's Air configuration, lint configuration and entry points, CI tool versions,
event/path filters, and actual recent formatting/lint step results. Distinguish an absent gate,
version drift, local-only files, explicit opt-outs, and a real failing hosted check. Both tool
versions matter even when commands and configuration match. Snapshot comparisons close every run,
including runs with no upgrades.

## Select and trial releases

Check official [Air releases](https://github.com/posit-dev/air/releases) and
[lintr's CRAN metadata](https://cran.r-project.org/package=lintr), requirements, and release notes.
Select the newest stable version of each tool that works with the intended local OS, architecture,
and installed R. Exclude prereleases and development builds. Do not downgrade an intentionally newer
installation without authority.

Trial candidates outside the active installation. Prefer the supported existing package manager;
if its distribution lags upstream, try a supported official alternative before declaring a platform
limit. Verify checksums for downloaded Air release executables. For lintr, use an isolated R library
prepended to the existing libraries so other installed package dependencies remain available.
Validate executable resolution and versions, then run real formatting/lint checks on disposable
package copies; `--version` and successful installation alone do not prove usability. Attribute
network restrictions separately and use the available network-approval path before concluding that
a release is incompatible. Record concrete compatibility limits and any older version selected.

Use one selected version per tool across participating repositories and the local installation.
Resolve baseline failures and repository-specific holds before promoting that tool globally. When a
repository blocks a common version, retain the active version for that tool and report the hold;
continue the other tool and independent maintenance. An opted-out repository does not need to adopt
the selected tool, and excluded repositories are not inspected or claimed as validated.

## Prepare and validate repository changes

Trial Air formatting on tracked R source in clean copies. Preserve configured widths, exclusions,
generated-file ownership, and shape-sensitive skips. Leave untracked plans and other local material
alone. Do not reflow Markdown, articles, LaTeX, roxygen, or Rdoc. Inspect the diff and run relevant
behavior checks: Air can add braces to single-expression branches, so raw parse-tree identity alone
cannot determine whether the formatting is safe.

Run the repository's actual lint entry point with the selected lintr version. Load its current
development namespace and test helpers when needed by object-usage checks. Reuse an existing entry
point and update its version guard, CI installer, and local instructions when they encode an old
version. Distinguish new lint diagnostics from baseline findings. Make clear fixes that preserve
behavior within this grant; retain meaningful diagnostics and report fixes needing wider authority.

For each tool, make local and CI invocations agree and pin the selected numeric version in CI,
including version guards or other existing sources of truth. Keep the setup-air action's SHA
and its Air `version` input distinct. Use an exact lintr package version rather than a floating
dependency. Default gates must run on relevant push and pull-request changes and fail on findings:
`air format . --check` for Air and a lint entry point that exits nonzero for nonempty lint results.
Respect explicit opt-outs instead of enabling their gates.

Keep full-SHA action pins with matching version comments, read-only permissions, checkout
`persist-credentials: false`, and safe push/PR behavior. Run the canonical Actions audit and the
package workflow's applicable tests, package checks, formatting, and lint gates without incidental
documentation generation. Confirm each intended test or check actually executes. Repeat only checks
invalidated by later changes, and attribute baseline or environmental diagnostics with evidence.

## Install, publish, and finish

In upgrade mode, promote a tool only after its participating repository candidates pass validation.
Preserve a supported way to restore the prior installation, install through the resolved method, and
verify normal executable/library resolution and the actual version from a fresh process. If
installation fails, restore the prior working tool before publishing that tool's CI changes. A
successful temporary trial is not an upgrade of the active environment.

Refresh each repository's remote default branch before publication. If it moved, rebuild the
candidate against the new base and repeat affected validation. Publish only intended files through
the configured route and repository policy. Use expected-head protection for PR merges and ordinary
fast-forward pushes for direct publication; retry from a fresh base rather than force-pushing.

Observe the actual hosted formatting and lint steps for each exact final default-branch commit;
workflow existence, static audits, and local passes do not establish hosted success. Confirm the
installed CI versions from setup output or explicit version checks. Fix in-scope failures and report
any blocked publication or local/CI mismatch explicitly. If publication fails after installation,
retain the candidate and recovery information and finish through the continuation procedure; do not
claim all repositories are aligned while a pin or hosted check remains pending.

For CI waits, reuse the
[bounded continuation procedure](weekly-r-ci-updates.md#continue-across-ci-waits).
Record selected and prior local versions, installation/recovery state, repository opt-outs, bases,
candidate commits/PRs, expected run and step IDs, validation, blockers, and next actions in a
continuation record. When invoked together, this phase and Dependabot share one record and temporary
heartbeat. Retain each phase's scope and authority and serialize writes to a
repository; refresh its base after the preceding phase. Include any unstarted phase in continuation
work so a CI wait cannot drop it. Keep the recurring weekly schedule separate from CI polls.

Report official latest, selected, and active local versions, compatibility limits, and a compact
per-repository table of pins, diff scope, local validation, publication identity, actual hosted
format/lint results, opt-outs, and concrete remaining action. Distinguish no update available from
an incomplete release lookup or failed trial. Report checkout preservation and retire this batch's
temporary heartbeat and disposable resources when complete, following the shared continuation rules.
