# Editing R Markdown Articles

Use this for formatting, prose reflow, or mathematical-notation changes in R Markdown articles.
Follow the document's configured width and repository conventions; embedded documentation follows
its host source rules.

## R Code Formatting

Run the helper on explicitly selected changed Rmd files or vignette directories:

```sh
python3 "${HOME}/.agents/skills/r-docs-pkgdown/scripts/format-rmd.py" --write vignettes
python3 "${HOME}/.agents/skills/r-docs-pkgdown/scripts/format-rmd.py" --check vignettes
```

It formats executable R chunks and plain fenced `r`/`R` examples with Air, including consistently
quoted fences. A synthetic `.R` path beside each article lets Air use its project configuration.
The helper does not execute code. It validates R parse-tree identity before writing and preserves
surrounding prose, front matter, fences and options, and non-R blocks. Invalid input or failed
validation stops the batch before writing. Python 3, Air, and Rscript must be available on `PATH`.

`--check` exits 1 when formatting is needed; invalid or unsafe input and tool failures exit 2.
Both modes report residual long code and literal output lines; `--report-width` sets the advisory
character threshold (default 80). Width reports do not change the exit status. Review the residuals:
formatting source does not fix captured literal output or guarantee browser fit. Render changed
articles and inspect actual overflow at desktop and mobile widths as described in
[Checks](../SKILL.md#checks).

## Mechanical Reflow

Keep formatting-only changes distinguishable from wording, notation and executable changes.

1. Trial an existing formatter on temporary copies of explicitly selected files. Inspect how its
   active plugins handle knitr headers, YAML, tables, code and math before applying output.
   A supported input flavor alone does not establish preservation.
2. Preserve YAML front matter, tables, code spans, executable chunk headers and bodies, and math
   spans unless their changes are intended. If needed, use a bounded adapter around the formatter
   to retain protected blocks. Exercise the syntax encountered; a few regular expressions do not
   establish a general Markdown parser.
3. Compare the protected content exactly during mechanical reflow. Exclude code spans from any math
   inventory: R's dollar operator is not a math delimiter. Treat an intentional editor-width setting
   change separately from accidental YAML normalization.
4. When parsed document comparison adds useful evidence, normalize soft line breaks to spaces and
   compare structure. Confirm that the parser recognizes the actual input dialect. If necessary,
   represent knitr headers as ordinary fenced R only in validation copies; preserve real headers.
5. Inspect the remaining diff and check prose width with explicit exclusions for protected content.
   Keep subsequent wording and mathematical edits separate so their changed meaning can be reviewed.

A formatter that preserves the encountered code and math can still rewrite YAML or table layout.
Keep or reject those changes deliberately. Do not prescribe one formatter or plugin combination as
universally safe from a trial on a few documents.

## Mathematical Edits

Choose notation by mathematical role and the article's teaching task. Keep definitions and later
uses consistent across related passages. Preserve useful worked steps and align multi-line
derivations so readers can follow them.

When changing a buffer definition, displacement, sign, index or scaling convention, re-derive the
affected relationship rather than treating it as typography. Use small numerical checks where
they can distinguish competing formulas. Check necessary division conditions and any advertised
special case against the original update. These checks support the exercised identities, not a
universal notation style.

## Completion Evidence

Render each affected article and follow the
[browser inspection checks](../SKILL.md#checks). A successful render, parsed-tree comparison or
MathML inspection does not establish visual readability. If captures are blank or unavailable,
report visual review as unverified rather than inferring that the published page is blank.
