# Download And Archive Fixtures

When a public download, dataset, or parser wrapper accepts `base_url`, `url`,
or `tmpdir`, prefer tiny local fixtures over remote integration tests for
wrapper plumbing. Use `file://` gzip fixtures for byte parsers and local tar or
folder fixtures for archive/directory readers.

Keep payloads minimal, but include non-contiguous labels or ids when the parser
maps codes to descriptions or factors. Include boundary-like values such as
`0` and a high label so tests catch factor-code indexing mistakes, including
patterns like `description_levels[as.numeric(label)]`.

For untrusted tar archives, entry-name and normalized-path checks are not
enough: inspect tar type flags before extraction and reject symbolic links,
hard links, and unsupported special entries. Add a local link-containing tar
fixture alongside traversal and duplicate-path regressions; keep tar and ZIP
expectations separate because their metadata APIs and extractors differ.
Construct link fixtures by writing a minimal tar header or using an archive API
that sets the entry type and link target directly; do not require
`file.symlink()` as an intermediate step because CI runners may lack that
filesystem capability.

For a specification-driven downloader, keep fixtures small but make at least
one happy path complete enough to use the production specification and reach
terminal result construction. At raw decoder boundaries, compare values without
names or other representation attributes when the external format does not own
them; at the canonical package boundary, assert exact names, dimensions, and
other semantic metadata. Exercise every supported output mode when branching
occurs after shared construction, and keep incomplete-archive controls separate
so an early exit cannot stand in for the terminal formatter.
