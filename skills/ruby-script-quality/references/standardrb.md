# StandardRB In Restricted Filesystems

StandardRB uses RuboCop cache state. In a managed or restricted workspace, a
cache permission failure can stop the command before it evaluates the requested
Ruby files. Route the cache to writable temporary state for that invocation:

```sh
XDG_CACHE_HOME="${TMPDIR:-/tmp}/standardrb-cache" \
  bundle exec standardrb path/to/script.rb
```

Use the repository's pinned Bundler command when it differs. Report the first
failure as environmental; interpret formatting output only after a rerun with
the writable cache reaches the formatter normally.
