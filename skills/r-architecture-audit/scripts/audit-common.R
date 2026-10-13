# codex-workflows: internal-skill-script: Shared helpers loaded by the three R audit CLI entry points.
# CLI entry points provide abort() for error reporting.

assignment_parts <- function(expr) {
  if (!is.call(expr) || !is.symbol(expr[[1L]])) {
    return(NULL)
  }
  head <- as.character(expr[[1L]])
  if (head %in% c("<-", "=", "<<-")) {
    lhs <- expr[[2L]]
    rhs <- expr[[3L]]
  } else if (head %in% c("->", "->>")) {
    lhs <- expr[[3L]]
    rhs <- expr[[2L]]
  } else {
    return(NULL)
  }
  if (!is.symbol(lhs)) {
    return(NULL)
  }
  list(name = as.character(lhs), rhs = rhs)
}

package_relative_path <- function(path, root) {
  prefix <- paste0(root, "/")
  if (startsWith(path, prefix)) {
    return(substring(path, nchar(prefix) + 1L))
  }
  path
}

markdown_escape <- function(value) {
  gsub("[|]", "\\\\|", as.character(value))
}

write_atomic <- function(path, writer) {
  temporary <- tempfile(
    pattern = paste0(".", basename(path), "."),
    tmpdir = dirname(path)
  )
  on.exit(unlink(temporary), add = TRUE)
  writer(temporary)
  if (!file.rename(temporary, path)) {
    abort("could not move completed output into place: ", path)
  }
}

write_tsv <- function(data, path) {
  write_atomic(path, function(temporary) {
    write.table(
      data,
      file = temporary,
      sep = "\t",
      row.names = FALSE,
      col.names = TRUE,
      quote = TRUE,
      na = ""
    )
  })
}
