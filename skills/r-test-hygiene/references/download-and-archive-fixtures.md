# Download And Archive Fixtures

For public download or parser wrappers accepting `base_url`, `url`, or `tmpdir`, prefer tiny local fixtures:
`file://` gzip for byte parsers and local tar or folders for archive readers. When repository metadata supplies a
relative URL path, exercise the constructed URL with literal, percent-encoded, mixed, double-encoded, and malformed
hazards plus a benign encoded-unreserved control. Validate escape syntax, reject encoded separators and unsafe
reserved bytes, and normalize encoded dots before checking dot segments.

Keep payloads minimal, but use non-contiguous labels or ids and boundary-like values such as `0` and a high label
when parsers map codes to descriptions; this catches indexing such as `description_levels[as.numeric(label)]`.

For untrusted tar archives, inspect type flags before extraction and reject symbolic links, hard links, and
unsupported special entries; entry-name and normalized-path checks are insufficient. Add link, traversal, and
duplicate-path fixtures, keeping tar and ZIP expectations separate. Construct links with a minimal tar header or
an archive API that sets type and target directly, because CI may not support intermediate `file.symlink()`.

For a specification-driven downloader, make one minimal happy path use the production specification through
terminal construction. At raw decoder boundaries ignore representation attributes the format does not own; at
the package boundary assert names, dimensions, and semantic metadata. Exercise every output mode after shared
construction, and keep incomplete controls separate from terminal-format evidence.

When validation depends on an external filename, suffix, media type, schema id, or similar hint, use the same
immutable planned hint before and after staged publication. Include valid bytes with conflicting embedded metadata
and require pre-publication failure, unchanged durable state, and empty staging.
