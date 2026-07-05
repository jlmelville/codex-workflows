#!/usr/bin/env Rscript

default_manifest <- "/mnt/e/dev/R/datasets/R-datasets-manifest.tsv"
required_columns <- c(
  "file", "path", "basename", "X_nrow", "X_ncol", "Y_nrow", "Y_ncol",
  "Y_length", "Y_class", "Y_colnames", "color_by", "nn_idx_dim",
  "nn_dist_dim", "nn_k", "notes"
)

usage <- function(status = 0L) {
  cat(
    "Usage: Rscript --vanilla validate_manifest.R [--manifest PATH] [--draft PATH] [--replace] [--max-rows N]\n",
    "\n",
    "Defaults:\n",
    "  --manifest ", default_manifest, "\n",
    "  --draft    file.path(tempdir(), 'R-datasets-manifest.tsv')\n",
    sep = ""
  )
  quit(status = status)
}

parse_args <- function(args) {
  opts <- list(
    manifest = default_manifest,
    draft = file.path(tempdir(), "R-datasets-manifest.tsv"),
    replace = FALSE,
    max_rows = NA_integer_
  )

  i <- 1L
  while (i <= length(args)) {
    arg <- args[[i]]
    if (arg == "--help" || arg == "-h") {
      usage(0L)
    } else if (arg == "--replace") {
      opts$replace <- TRUE
      i <- i + 1L
    } else if (arg %in% c("--manifest", "--draft", "--max-rows")) {
      if (i == length(args)) {
        stop(arg, " requires a value", call. = FALSE)
      }
      value <- args[[i + 1L]]
      if (arg == "--manifest") {
        opts$manifest <- value
      } else if (arg == "--draft") {
        opts$draft <- value
      } else {
        opts$max_rows <- as.integer(value)
        if (is.na(opts$max_rows) || opts$max_rows < 1L) {
          stop("--max-rows must be a positive integer", call. = FALSE)
        }
      }
      i <- i + 2L
    } else {
      stop("Unknown argument: ", arg, call. = FALSE)
    }
  }

  opts
}

empty_string <- function(x) {
  if (length(x) == 0L || is.null(x)) {
    ""
  } else if (all(is.na(x))) {
    ""
  } else {
    paste(x, collapse = ",")
  }
}

dim_string <- function(x) {
  d <- dim(x)
  if (is.null(d) || length(d) < 2L) {
    ""
  } else {
    paste0(d[[1L]], "x", d[[2L]])
  }
}

scalar <- function(x) {
  if (length(x) == 0L || is.null(x) || is.na(x)) {
    ""
  } else {
    as.character(x)
  }
}

field <- function(row, name) {
  if (!name %in% names(row)) {
    ""
  } else {
    scalar(row[[name]])
  }
}

read_manifest <- function(path) {
  if (!file.exists(path)) {
    stop("manifest not found: ", path, call. = FALSE)
  }
  manifest <- read.delim(
    path,
    check.names = FALSE,
    stringsAsFactors = FALSE,
    na.strings = character()
  )
  missing <- setdiff(required_columns, names(manifest))
  if (length(missing) > 0L) {
    stop("manifest missing columns: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  manifest
}

load_bundle <- function(path) {
  env <- new.env(parent = emptyenv())
  object_names <- load(path, envir = env)
  if (length(object_names) != 1L) {
    stop("expected one object, found: ", paste(object_names, collapse = ", "), call. = FALSE)
  }
  env[[object_names]]
}

inspect_row <- function(row, data_root) {
  errors <- character()
  name <- field(row, "file")
  path <- field(row, "path")
  manifest_basename <- field(row, "basename")
  expected_basename <- paste0(name, "l.Rda")

  if (!identical(manifest_basename, expected_basename)) {
    errors <- c(errors, paste0("basename ", manifest_basename, " != ", expected_basename))
  }
  if (!identical(basename(path), expected_basename)) {
    errors <- c(errors, paste0("path basename ", basename(path), " != ", expected_basename))
  }
  if (!startsWith(normalizePath(path, mustWork = FALSE), normalizePath(data_root, mustWork = FALSE))) {
    errors <- c(errors, paste0("path is outside data root: ", path))
  }
  if (!file.exists(path)) {
    errors <- c(errors, paste0("expected file is missing: ", path))
    return(list(errors = errors, row = NULL, nn_rows_match = NA, nn_k = NA_integer_))
  }

  obj <- tryCatch(
    load_bundle(path),
    error = function(e) {
      errors <<- c(errors, conditionMessage(e))
      NULL
    }
  )
  if (is.null(obj)) {
    return(list(errors = errors, row = NULL, nn_rows_match = NA, nn_k = NA_integer_))
  }

  if (!is.list(obj)) {
    errors <- c(errors, paste0("object is not a list: ", paste(class(obj), collapse = "/")))
  }
  for (required_name in c("X", "Y", "nn")) {
    if (!required_name %in% names(obj)) {
      errors <- c(errors, paste0("missing list element: ", required_name))
    }
  }
  if (length(errors) > 0L) {
    return(list(errors = errors, row = NULL, nn_rows_match = NA, nn_k = NA_integer_))
  }

  x <- obj$X
  y <- obj$Y
  nn <- obj$nn

  if (!is.matrix(x)) {
    errors <- c(errors, paste0("X is not a matrix: ", paste(class(x), collapse = "/")))
  }
  if (!is.list(nn)) {
    errors <- c(errors, paste0("nn is not a list: ", paste(class(nn), collapse = "/")))
  }
  for (required_name in c("idx", "dist")) {
    if (!required_name %in% names(nn)) {
      errors <- c(errors, paste0("missing nn element: ", required_name))
    }
  }
  if (length(errors) > 0L) {
    return(list(errors = errors, row = NULL, nn_rows_match = NA, nn_k = NA_integer_))
  }

  x_dim <- dim(x)
  y_dim <- dim(y)
  idx_dim <- dim(nn$idx)
  dist_dim <- dim(nn$dist)
  nn_k <- if (!is.null(idx_dim) && length(idx_dim) >= 2L) idx_dim[[2L]] else NA_integer_
  nn_rows_match <- !is.null(idx_dim) && !is.null(dist_dim) &&
    idx_dim[[1L]] == x_dim[[1L]] &&
    dist_dim[[1L]] == x_dim[[1L]]

  if (is.null(idx_dim) || length(idx_dim) < 2L || idx_dim[[2L]] != 150L) {
    errors <- c(errors, paste0("nn$idx is not nrow(X) x 150: ", dim_string(nn$idx)))
  }
  if (is.null(dist_dim) || length(dist_dim) < 2L || dist_dim[[2L]] != 150L) {
    errors <- c(errors, paste0("nn$dist is not nrow(X) x 150: ", dim_string(nn$dist)))
  }
  if (!isTRUE(nn_rows_match)) {
    errors <- c(errors, "nn row counts do not match nrow(X)")
  }

  row_out <- data.frame(
    file = name,
    path = path,
    basename = expected_basename,
    X_nrow = x_dim[[1L]],
    X_ncol = x_dim[[2L]],
    Y_nrow = if (is.null(y_dim)) length(y) else y_dim[[1L]],
    Y_ncol = if (is.null(y_dim) || length(y_dim) < 2L) "" else y_dim[[2L]],
    Y_length = length(y),
    Y_class = paste(class(y), collapse = "/"),
    Y_colnames = empty_string(colnames(y)),
    color_by = field(row, "color_by"),
    nn_idx_dim = dim_string(nn$idx),
    nn_dist_dim = dim_string(nn$dist),
    nn_k = nn_k,
    notes = field(row, "notes"),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )

  if (!identical(as.integer(row_out$X_nrow), as.integer(row$X_nrow))) {
    errors <- c(errors, paste0("manifest X_nrow mismatch: ", row$X_nrow, " != ", row_out$X_nrow))
  }
  if (!identical(as.integer(row_out$X_ncol), as.integer(row$X_ncol))) {
    errors <- c(errors, paste0("manifest X_ncol mismatch: ", row$X_ncol, " != ", row_out$X_ncol))
  }
  if (as.integer(row_out$nn_k) != 150L) {
    errors <- c(errors, paste0("nn_k is not 150: ", row_out$nn_k))
  }

  list(errors = errors, row = row_out, nn_rows_match = nn_rows_match, nn_k = nn_k)
}

main <- function() {
  opts <- parse_args(commandArgs(trailingOnly = TRUE))
  manifest <- read_manifest(opts$manifest)
  if (!is.na(opts$max_rows)) {
    manifest <- manifest[seq_len(min(opts$max_rows, nrow(manifest))), , drop = FALSE]
  }
  data_root <- dirname(opts$manifest)

  results <- vector("list", nrow(manifest))
  all_errors <- character()

  for (i in seq_len(nrow(manifest))) {
    row <- manifest[i, , drop = FALSE]
    result <- inspect_row(row, data_root)
    results[[i]] <- result
    if (length(result$errors) > 0L) {
      all_errors <- c(all_errors, paste0(row$file, " -> ", row$path, "\n  ", result$errors))
    }
    rm(row, result)
    invisible(gc())
  }

  nn_k <- vapply(results, function(x) x$nn_k, integer(1L))
  nn_rows_match <- vapply(results, function(x) isTRUE(x$nn_rows_match), logical(1L))
  cat("rows ", nrow(manifest), "\n", sep = "")
  cat("errors ", length(all_errors), "\n", sep = "")
  cat("all_nn_k_150 ", all(!is.na(nn_k) & nn_k == 150L), "\n", sep = "")
  cat("all_nn_rows_match ", all(nn_rows_match), "\n", sep = "")

  if (length(all_errors) > 0L) {
    cat("\nValidation failures:\n", paste(all_errors, collapse = "\n"), "\n", sep = "")
    quit(status = 1L)
  }

  rows <- lapply(results, `[[`, "row")
  draft <- do.call(rbind, rows)
  write.table(
    draft,
    file = opts$draft,
    sep = "\t",
    quote = TRUE,
    row.names = FALSE,
    na = ""
  )
  cat("draft ", opts$draft, "\n", sep = "")

  if (opts$replace) {
    ok <- file.copy(opts$draft, opts$manifest, overwrite = TRUE)
    if (!ok) {
      stop("failed to replace manifest: ", opts$manifest, call. = FALSE)
    }
    cat("replaced ", opts$manifest, "\n", sep = "")
  }
}

tryCatch(
  main(),
  error = function(e) {
    cat("error: ", conditionMessage(e), "\n", sep = "", file = stderr())
    quit(status = 1L)
  }
)
