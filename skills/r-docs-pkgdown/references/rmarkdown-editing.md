# Editing R Markdown Articles

Use this for prose reflow or mathematical-notation changes in R Markdown articles. Follow the
document's configured width and repository conventions; embedded documentation follows its host
source rules.

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
