---
name: codex-approval-rules-audit
description: Audit Codex command-approval rules, layers, and scoping.
---

# Codex Approval Rules Audit

Audit effective command authority without changing policy unless the user
explicitly requests that separate mutation.

## Current Product Semantics

Apply the system `openai-docs` skill first and fetch the current official Codex
Rules and Config Basics pages. Rules are product configuration and may change.
Use the official pages to establish active layers, trust requirements, precedence, rule syntax,
shell-wrapper handling, and the supported policy checker; do not preserve those
details as copied local doctrine.

## Audit

1. Inventory the user, trusted project, and managed rule layers that are
   actually active. Distinguish project trust from command authorization and
   do not infer activation from file presence alone.
2. Record each rule's layer, prefix pattern, decision, justification, and
   inline match tests. Group exact duplicates, narrower rules shadowed by a
   broader prefix, and open-ended command families.
3. Classify the operation behind each prefix: read-only inspection,
   recoverable local mutation, local-history mutation, remote mutation, or
   execution of repository-controlled code. Treat relative executables and
   unrestricted trailing arguments as additional risk.
4. Use `codex execpolicy check` with the complete active rule set to test the
   effective decision. Include ordinary expected commands and bounded
   adversarial variants that add destructive flags, HTTP methods, extra paths,
   or shell composition when those forms are plausible.
5. Recommend the smallest authority surface. Keep a conservative global
   baseline, prefer trusted repository-local rules for repository-specific
   maintainer mutations, and retain prompts or prohibitions when a prefix
   cannot encode the required safety predicates.

Recurrence demonstrates usefulness, not safety. A frequently repeated local
rule is only a promotion candidate; risk and effective-decision review remain
independent gates.

## Mutation Boundary

Default to a report or proposed diff. Moving, deleting, or promoting rules
requires explicit user authority, a review of the exact before/after effective
decisions, and a recoverable backup. Never auto-promote by frequency and never
replace a guarded command with a broader primitive merely to avoid prompts.

## Output

Report active layers, redundancies, risky effective decisions and their probes,
recommended global versus project scope, proposed removals or retained prompts,
and any product-semantics uncertainty or untested policy path.
