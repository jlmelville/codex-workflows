#!/usr/bin/env Rscript

usage <- function() {
  cat(
    "Usage: r-value-family-trace.R --package DIR --family NAME \\\n",
    "       --pattern NAME=REGEX [--pattern NAME=REGEX ...] [--out FILE]\n",
    "       r-value-family-trace.R --self-test\n",
    "\n",
    "Build a deterministic lexical reading set across conventional R package\n",
    "source, test, and documentation files. Without --out, TSV is written to\n",
    "standard output.\n",
    sep = ""
  )
}

abort <- function(...) {
  stop(..., call. = FALSE)
}

nonempty_scalar <- function(value) {
  length(value) == 1L && !is.na(value) && nzchar(value)
}

parse_pattern <- function(value) {
  separator <- regexpr("=", value, fixed = TRUE)[[1L]]
  if (separator <= 1L || separator == nchar(value)) {
    abort("--pattern must use NAME=REGEX with non-empty values")
  }
  name <- substr(value, 1L, separator - 1L)
  regex <- substr(value, separator + 1L, nchar(value))
  if (grepl("[,\t\r\n]", name)) {
    abort("--pattern name must not contain commas, tabs, or newlines")
  }
  tryCatch(
    grepl(regex, "", perl = TRUE),
    error = function(error) {
      abort(
        "invalid regular expression for pattern ",
        name,
        ": ",
        conditionMessage(error)
      )
    }
  )
  list(name = name, regex = regex)
}

parse_args <- function(args) {
  opts <- list(
    package = NULL,
    family = NULL,
    patterns = list(),
    out = NULL,
    self_test = FALSE
  )
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (key %in% c("-h", "--help")) {
      usage()
      quit(status = 0L)
    }
    if (key == "--self-test") {
      opts$self_test <- TRUE
      i <- i + 1L
      next
    }
    if (!key %in% c("--package", "--family", "--pattern", "--out")) {
      abort("unknown argument: ", key)
    }
    if (i == length(args)) {
      abort("missing value for ", key)
    }
    value <- args[[i + 1L]]
    if (key == "--package") {
      opts$package <- value
    } else if (key == "--family") {
      opts$family <- value
    } else if (key == "--pattern") {
      opts$patterns[[length(opts$patterns) + 1L]] <- parse_pattern(value)
    } else {
      opts$out <- value
    }
    i <- i + 2L
  }

  if (opts$self_test) {
    if (length(args) != 1L) {
      abort("--self-test cannot be combined with other arguments")
    }
    return(opts)
  }
  if (!nonempty_scalar(opts$package)) {
    abort("--package requires a non-empty directory")
  }
  if (!nonempty_scalar(opts$family)) {
    abort("--family requires a non-empty value")
  }
  if (grepl("[\t\r\n]", opts$family)) {
    abort("--family must not contain tabs or newlines")
  }
  if (length(opts$patterns) == 0L) {
    abort("at least one --pattern NAME=REGEX is required")
  }
  pattern_names <- vapply(opts$patterns, `[[`, character(1L), "name")
  if (anyDuplicated(pattern_names)) {
    abort("--pattern names must be unique")
  }
  if (!is.null(opts$out) && !nonempty_scalar(opts$out)) {
    abort("--out requires a non-empty file path")
  }
  opts
}

package_relative_path <- function(path, root) {
  prefix <- paste0(root, "/")
  if (startsWith(path, prefix)) {
    return(substring(path, nchar(prefix) + 1L))
  }
  path
}

trace_files <- function(package_root) {
  roots <- c("R", "tests", "vignettes", "man")
  extensions <- "[.](R|r|Rmd|rmd|qmd|md|Rd)$"
  files <- unlist(
    lapply(roots, function(root) {
      directory <- file.path(package_root, root)
      if (!dir.exists(directory)) {
        return(character())
      }
      list.files(
        directory,
        pattern = extensions,
        recursive = TRUE,
        full.names = TRUE
      )
    }),
    use.names = FALSE
  )
  top_level_docs <- list.files(
    package_root,
    pattern = "^(README|NEWS)([.][^.]+)?$",
    full.names = TRUE
  )
  files <- c(files, top_level_docs[file.info(top_level_docs)$isdir %in% FALSE])
  files <- normalizePath(files, winslash = "/", mustWork = TRUE)
  files[order(vapply(
    files,
    package_relative_path,
    character(1L),
    package_root
  ))]
}

source_extent <- function(ref) {
  if (is.null(ref)) {
    return(c(line = NA_integer_, end_line = NA_integer_))
  }
  values <- as.integer(ref)
  c(line = values[[1L]], end_line = values[[3L]])
}

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

function_extents <- function(file, relative) {
  if (!grepl("[.][Rr]$", file)) {
    return(data.frame(
      name = character(),
      line = integer(),
      end_line = integer(),
      stringsAsFactors = FALSE
    ))
  }
  expressions <- tryCatch(
    parse(file = file, keep.source = TRUE, encoding = "UTF-8"),
    error = function(error) abort(relative, ": ", conditionMessage(error))
  )
  source_refs <- attr(expressions, "srcref")
  rows <- list()
  for (i in seq_along(expressions)) {
    parts <- assignment_parts(expressions[[i]])
    if (
      is.null(parts) ||
        !is.call(parts$rhs) ||
        !identical(parts$rhs[[1L]], as.name("function"))
    ) {
      next
    }
    source_ref <- if (length(source_refs) >= i) {
      source_refs[[i]]
    } else {
      attr(expressions[[i]], "srcref")
    }
    extent <- source_extent(source_ref)
    if (anyNA(extent)) {
      next
    }
    rows[[length(rows) + 1L]] <- data.frame(
      name = parts$name,
      line = unname(extent[["line"]]),
      end_line = unname(extent[["end_line"]]),
      stringsAsFactors = FALSE
    )
  }
  if (length(rows) == 0L) {
    return(data.frame(
      name = character(),
      line = integer(),
      end_line = integer(),
      stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, rows)
}

enclosing_function <- function(line, extents) {
  matches <- extents[
    extents$line <= line & extents$end_line >= line,
    ,
    drop = FALSE
  ]
  if (nrow(matches) == 0L) {
    return(NA_character_)
  }
  matches <- matches[
    order(matches$end_line - matches$line, matches$line),
    ,
    drop = FALSE
  ]
  matches$name[[1L]]
}

empty_trace <- function() {
  data.frame(
    family = character(),
    patterns = character(),
    file = character(),
    line = integer(),
    enclosing_function = character(),
    source_text = character(),
    stringsAsFactors = FALSE
  )
}

trace_family <- function(package, family, patterns) {
  package_root <- normalizePath(package, winslash = "/", mustWork = TRUE)
  if (!file.exists(file.path(package_root, "DESCRIPTION"))) {
    abort("package DESCRIPTION not found: ", package_root)
  }
  files <- trace_files(package_root)
  rows <- list()
  for (file in files) {
    relative <- package_relative_path(file, package_root)
    lines <- readLines(file, warn = FALSE, encoding = "UTF-8")
    extents <- function_extents(file, relative)
    for (line_number in seq_along(lines)) {
      matched <- vapply(
        patterns,
        function(pattern) {
          grepl(pattern$regex, lines[[line_number]], perl = TRUE)
        },
        logical(1L)
      )
      if (!any(matched)) {
        next
      }
      rows[[length(rows) + 1L]] <- data.frame(
        family = family,
        patterns = paste(
          vapply(patterns[matched], `[[`, character(1L), "name"),
          collapse = ","
        ),
        file = relative,
        line = line_number,
        enclosing_function = enclosing_function(line_number, extents),
        source_text = lines[[line_number]],
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(rows) == 0L) {
    return(empty_trace())
  }
  result <- do.call(rbind, rows)
  keys <- paste(result$file, result$line, sep = "\034")
  if (anyDuplicated(keys)) {
    abort("internal error: duplicate file and line rows")
  }
  result
}

write_tsv_connection <- function(data, connection) {
  write.table(
    data,
    connection,
    sep = "\t",
    row.names = FALSE,
    col.names = TRUE,
    quote = TRUE,
    na = ""
  )
}

render_tsv <- function(data) {
  connection <- textConnection("output", "w", local = TRUE)
  on.exit(close(connection), add = TRUE)
  write_tsv_connection(data, connection)
  paste0(paste(output, collapse = "\n"), "\n")
}

write_atomic_tsv <- function(data, out) {
  if (file.exists(out)) {
    abort("refusing to overwrite existing output path: ", out)
  }
  parent <- dirname(out)
  if (
    !dir.exists(parent) &&
      !dir.create(parent, recursive = TRUE, showWarnings = FALSE)
  ) {
    abort("could not create output parent: ", parent)
  }
  parent <- normalizePath(parent, winslash = "/", mustWork = TRUE)
  destination <- file.path(parent, basename(out))
  temporary <- tempfile(
    pattern = paste0(".", basename(out), "."),
    tmpdir = parent
  )
  on.exit(unlink(temporary), add = TRUE)
  connection <- file(temporary, open = "w", encoding = "UTF-8")
  write_tsv_connection(data, connection)
  close(connection)
  if (!file.rename(temporary, destination)) {
    abort("could not move completed output into place: ", destination)
  }
  normalizePath(destination, winslash = "/", mustWork = TRUE)
}

run_self_test <- function() {
  root <- tempfile("r-value-family-trace-test.")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  dir.create(file.path(root, "R"))
  dir.create(file.path(root, "tests", "testthat"), recursive = TRUE)
  dir.create(file.path(root, "vignettes"))
  writeLines(
    c("Package: tracefixture", "Version: 0.0.1"),
    file.path(root, "DESCRIPTION")
  )
  writeLines(
    c(
      "make_result <- function(x) {",
      "  list(diagnostic_mode = 'trace', value = x)",
      "}",
      "consume_result <- function(x) x$diagnostic_mode"
    ),
    file.path(root, "R", "core.R")
  )
  writeLines(
    "testthat::expect_equal(make_result(1)$diagnostic_mode, 'trace')",
    file.path(root, "tests", "testthat", "test-mode.R")
  )
  writeLines(
    "The `diagnostic_mode` field reports trace behavior.",
    file.path(root, "vignettes", "mode.md")
  )
  patterns <- list(
    list(name = "field", regex = "diagnostic_mode"),
    list(name = "mode", regex = "trace")
  )
  first <- trace_family(root, "diagnostics", patterns)
  second <- trace_family(root, "diagnostics", patterns)
  stopifnot(identical(render_tsv(first), render_tsv(second)))
  stopifnot(identical(names(first), names(empty_trace())))
  stopifnot(!anyDuplicated(paste(first$file, first$line)))
  construction <- first[
    first$file == "R/core.R" & grepl("list", first$source_text, fixed = TRUE),
    ,
    drop = FALSE
  ]
  stopifnot(nrow(construction) == 1L)
  stopifnot(construction$patterns[[1L]] == "field,mode")
  stopifnot(construction$enclosing_function[[1L]] == "make_result")
  stopifnot(any(first$file == "tests/testthat/test-mode.R"))
  stopifnot(any(first$file == "vignettes/mode.md"))
  out <- file.path(root, "trace.tsv")
  write_atomic_tsv(first, out)
  stopifnot(file.exists(out))
  invisible(TRUE)
}

main <- function(args) {
  opts <- parse_args(args)
  if (opts$self_test) {
    run_self_test()
    cat("R value-family trace self-test passed.\n")
    return(invisible(NULL))
  }
  result <- trace_family(opts$package, opts$family, opts$patterns)
  if (is.null(opts$out)) {
    write_tsv_connection(result, stdout())
  } else {
    destination <- write_atomic_tsv(result, opts$out)
    cat(destination, "\n", sep = "")
  }
  invisible(NULL)
}

tryCatch(
  main(commandArgs(trailingOnly = TRUE)),
  error = function(error) {
    message("r-value-family-trace.R: ", conditionMessage(error))
    quit(status = 1L)
  }
)
