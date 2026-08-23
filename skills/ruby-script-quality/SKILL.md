---
name: ruby-script-quality
description: Write, review, test, and harden standalone Ruby scripts and CLIs. Use for .rb files, OptionParser, structured-data or filesystem automation, executable helpers, output behavior, and Ruby script validation.
---

# Ruby Script Quality

Use repository tooling as the source of truth for formatting and lint rules.
Do not reproduce a formatter's rulebook in prose.

## Establish The Contract

Before editing, identify:

- the supported Ruby version and how CI selects it;
- the working directory, arguments, environment variables, and standard-input
  contract;
- which output belongs on standard output versus standard error;
- success, usage-error, and operational-failure exit statuses;
- files or directories the script may create, replace, move, or delete;
- the formatter, linter, and behavior tests the repository already uses.

Keep executable scripts on `#!/usr/bin/env ruby`, preserve executable mode, and
add `# frozen_string_literal: true` when it matches the repository convention.
When a directly executable helper requires a Ruby newer than a plausible
platform default, check `RUBY_VERSION` before argument parsing or command
dispatch. Report the required and detected versions, then exit before mutation.

## CLI Behavior

Prefer `OptionParser` for nontrivial interfaces. Provide concise `--help` text
that names commands, required inputs, defaults, and meaningful environment
variables. Catch `OptionParser::ParseError`; print a stable one-line diagnostic
and usage to standard error, then use a distinct usage-error status such as 2.

Write machine-readable results to standard output. Write diagnostics and
enabled progress to standard error. Keep routine success silent or limited to
one stable summary. Offer `--verbose` when progress is useful and `--quiet` when
callers may need to suppress otherwise useful normal output. Keep error prefixes
and terminology consistent across related commands. Reject unknown commands,
missing required arguments, unexpected trailing arguments, and invalid
combinations before mutating state.

When wrapping noisy subprocesses, prefer their quiet and no-progress flags when
failure diagnostics remain complete. Otherwise capture output, emit a compact
success summary, and replay actionable output on failure. Do not make failures
silent merely to reduce output volume.

## Structured Data And Filesystems

- Use safe parsers for untrusted YAML and disable aliases unless the format
  explicitly needs them.
- Validate parsed types and required fields before use; do not assume a valid
  document shape merely because parsing succeeded.
- Decode text with an explicit encoding when portability matters.
- Use `Dir.mktmpdir` or `Tempfile` for temporary state and clean it up.
- Prefer atomic create-or-replace operations for durable state. Handle expected
  filesystem errors narrowly and preserve the original destination on failure.
- Scope deletes and moves to resolved, validated paths. Refuse dangerous roots
  and surprising repository boundaries when the script manages external state.

Use arrays with `Open3` or `Process.spawn` for subprocess arguments. Avoid shell
interpolation for data-derived commands.

## Errors And Structure

Raise domain-specific exceptions for expected failures and rescue them at the
CLI boundary. Do not catch `StandardError` broadly unless the boundary adds
useful context and preserves unexpected failures. Keep library logic separate
from argument parsing once a script is large enough to test through methods or
classes; avoid unrelated refactors solely to reach a preferred file size.

Use intention-revealing snake_case names, predicate suffixes such as `?`, and
constants for fixed vocabularies. Prefer small methods around validation,
rendering, and state transitions over dense command branches.

## Validation

Run the repository's pinned commands. Common checks are:

```sh
ruby -c path/to/script.rb
bundle exec standardrb path/to/script.rb
path/to/script.rb --help
```

If StandardRB or RuboCop fails before reporting source diagnostics because its
cache is not writable, treat that as restricted-environment evidence. Use the
[writable cache mechanics](references/standardrb.md) before classifying
formatter findings.

Exercise representative success and failure behavior in temporary directories.
Assert exit status, standard output, standard error, and the absence of partial
writes. Cover malformed structured data, missing inputs, invalid options,
unexpected arguments, permission failures when practical, and idempotence for
state-changing commands.

When output modes exist, assert default, quiet, verbose, and failure behavior;
quiet success must preserve actionable failure diagnostics.

When an older interpreter is available, exercise the minimum-version guard and
assert its status, diagnostic, and absence of partial writes.

For a substantial change, run focused tests first and then the repository's
complete validation. Never claim formatter, CI, or cross-version success from
syntax checking alone.

## Review Priorities

Prioritize findings that can corrupt or disclose data, report false success,
emit machine output on the wrong stream, expose exception traces for expected
input errors, accept unsafe paths, or behave differently across supported Ruby
versions. Treat cosmetic preferences already settled by the formatter as
non-findings.
