# Documentation Figure Style And Accessibility

Use this reference when creating or revising figures for an R package README,
article, vignette, or pkgdown site. Standardize semantic and review decisions,
not a universal theme. Keep plot-specific scientific choices local and do not
add a shared plotting dependency merely to conform to this guidance.

## Match Visual Semantics To Data

Choose the palette family from the variable's structure, not merely its storage
type:

| Data structure | Default palette role | Required check |
| --- | --- | --- |
| Unordered classes | Categorical | Stable named mapping and a non-color cue when identity matters |
| Ordered magnitude | Sequential | Perceptually ordered lightness without an artificial midpoint |
| Meaningful midpoint or signed departure | Diverging | The visual center matches the scientific reference |
| Angle, phase, season, or another closed domain | Cyclic | First and last values meet without a perceptual seam |

Keep mapping direction and category identity stable across related panels. For
periodic mappings, inspect endpoint distance numerically and in the rendered
figure; use a tolerance appropriate to the palette resolution and verify that
seam continuity has not erased useful local contrast. A bounded base-R check is:

```r
rgb <- grDevices::col2rgb(c(colours[1], colours[length(colours)]))
endpoint_distance <- sqrt(sum((rgb[, 1] - rgb[, 2])^2))
```

Use named mappings rather than relying on factor order. The same mapping can
serve base graphics and ggplot2 without imposing a package-wide theme:

```r
category_colours <- c(control = "#0072B2", treatment = "#D55E00")
point_colours <- unname(category_colours[as.character(group)])

ggplot2::scale_colour_manual(
  values = category_colours,
  breaks = names(category_colours)
)
```

When identity or status is decision-relevant, add a redundant cue such as
shape, line type, direct label, or reference marker. For dense points, balance
size and alpha against overlap, then make legend keys large and opaque enough
to decode the marks. Preserve honest aspect ratios and comparison limits when
geometry or cross-panel magnitude is part of the claim; disclose clipping or
different scales rather than allowing them to imply equality.

## Preserve Reader Value During Revision

Admission of a new plot and preservation of an existing plot are separate
decisions. Before simplifying or removing an existing figure:

1. Inventory every reader question and evidence layer it serves, including
   domain context, comparisons, residuals, uncertainty, and interaction.
2. Retain valid high-information layers whose reader value is not duplicated.
3. If one mechanism is arbitrary or unsupported, replace that mechanism with
   an explicit one while preserving the diagnostic task.
4. Remove a layer only when its reader value is duplicated, unsupported, or
   obsolete.

Visual consistency is a legibility baseline, not authority to flatten useful
domain-specific evidence. After replacement, inspect whether the revised plot
still answers the original reader questions rather than merely matching nearby
styling.

## Captions, Alternative Text, And Display Size

Give the visible caption the interpretive job: what the figure shows and why it
matters in context. Give alternative text the visual-information job: the plot
type, variables, material pattern, and distinctions needed by a reader who
cannot see the image. Do not copy a filename, title, or caption into alternative
text when it omits the visual evidence.

Treat device dimensions and displayed dimensions separately. Generate at a
resolution suitable for the output, then inspect the rendered page at its
actual article width for text, marks, legends, clipping, and panel order. An
enlarged or native-resolution image cannot substitute for that check.

For base graphics, restore state after a bounded plotting function so one
figure does not silently alter the next:

```r
old_par <- graphics::par(no.readonly = TRUE)
on.exit(graphics::par(old_par), add = TRUE)
```

## Optional Figure Enlargement

Keep enlargement only when it materially helps readers inspect dense evidence.
Treat it as an accessible modal dialog rather than a body-wide image click
handler:

- scope triggers to intentional article figures and expose pointer and keyboard
  activation;
- give the trigger, dialog, and explicit close control accessible names;
- move focus into the dialog, keep keyboard focus within it, support Escape and
  other visible close paths, and return focus to the triggering figure;
- lock body scrolling only while open and restore the prior page state on
  closure;
- exercise trigger scope, Enter and Space activation, every close path, focus
  return, scroll restoration, console output, and horizontal overflow in a real
  browser.

Do not infer interaction correctness from a static screenshot or successful
site build. Inspect the resting, open, focused, and closed states separately.
