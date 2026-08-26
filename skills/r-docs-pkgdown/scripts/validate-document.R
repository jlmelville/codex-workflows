#!/usr/bin/env Rscript

usage <- function(status = 0L, message = NULL) {
  if (!is.null(message)) {
    writeLines(paste0("validate-document.R: ", message), stderr())
  }

  writeLines(
    c(
      "Usage:",
      "  validate-document.R --rmarkdown DOCUMENT [--build-source] [--expect-installed-doc PATH]...",
      "  validate-document.R --pkgdown ARTICLE [--build-source] [--expect-installed-doc PATH]...",
      "",
      "Install the current R package into a temporary library, then render one",
      "R Markdown document or configured pkgdown article in the same fresh process.",
      "Rendered output and the temporary library are removed after validation.",
      "",
      "Options:",
      "  --rmarkdown DOCUMENT        Render one R Markdown document.",
      "  --pkgdown ARTICLE           Build one configured pkgdown article.",
      "  --build-source              Build and install a source tarball instead of the source directory.",
      "  --expect-installed-doc PATH Require PATH beneath the installed package's doc/ directory.",
      "  --help                      Show this help."
    ),
    if (status == 0L) stdout() else stderr()
  )
  quit(status = status, save = "no")
}

parse_args <- function(arguments) {
  options <- list(
    mode = NULL,
    target = NULL,
    build_source = FALSE,
    expected_docs = character()
  )

  index <- 1L
  while (index <= length(arguments)) {
    argument <- arguments[[index]]
    if (argument == "--help") {
      usage()
    } else if (argument %in% c("--rmarkdown", "--pkgdown", "--expect-installed-doc")) {
      if (index == length(arguments)) {
        usage(2L, paste(argument, "requires a value"))
      }
      value <- arguments[[index + 1L]]
      if (!nzchar(value)) {
        usage(2L, paste(argument, "requires a non-empty value"))
      }
      if (argument == "--expect-installed-doc") {
        options$expected_docs <- c(options$expected_docs, value)
      } else {
        mode <- sub("^--", "", argument)
        if (!is.null(options$mode)) {
          usage(2L, "choose exactly one of --rmarkdown or --pkgdown")
        }
        options$mode <- mode
        options$target <- value
      }
      index <- index + 2L
      next
    } else if (argument == "--build-source") {
      options$build_source <- TRUE
    } else {
      usage(2L, paste("unknown option", argument))
    }
    index <- index + 1L
  }

  if (is.null(options$mode)) {
    usage(2L, "choose exactly one of --rmarkdown or --pkgdown")
  }
  if (length(options$expected_docs) > 0L && !options$build_source) {
    usage(2L, "--expect-installed-doc requires --build-source")
  }
  options
}

run_command <- function(command, arguments, label) {
  output <- suppressWarnings(
    system2(command, arguments, stdout = TRUE, stderr = TRUE)
  )
  status <- attr(output, "status")
  if (is.null(status)) {
    status <- 0L
  }
  if (status != 0L) {
    details <- if (length(output) == 0L) "no command output" else paste(output, collapse = "\n")
    stop(label, " failed with status ", status, ":\n", details, call. = FALSE)
  }
  invisible(output)
}

validate_expected_doc <- function(relative_path, package_name, library_path) {
  if (grepl("^(/|[A-Za-z]:[/\\\\])", relative_path) ||
      any(strsplit(relative_path, "[/\\\\]")[[1L]] == "..")) {
    stop("installed doc paths must be relative and stay beneath doc/: ", relative_path, call. = FALSE)
  }

  doc_root <- system.file("doc", package = package_name, lib.loc = library_path)
  if (!nzchar(doc_root)) {
    stop("installed package has no doc/ directory", call. = FALSE)
  }
  expected <- file.path(doc_root, relative_path)
  if (!file.exists(expected)) {
    stop("installed doc artifact not found: ", relative_path, call. = FALSE)
  }
}

main <- function() {
  options <- parse_args(commandArgs(trailingOnly = TRUE))
  package_root <- normalizePath(".", mustWork = TRUE)
  description_path <- file.path(package_root, "DESCRIPTION")
  if (!file.exists(description_path)) {
    stop("run from an R package root containing DESCRIPTION", call. = FALSE)
  }

  description <- read.dcf(description_path, fields = "Package")
  package_name <- unname(description[[1L, "Package"]])
  if (!nzchar(package_name)) {
    stop("DESCRIPTION has no Package field", call. = FALSE)
  }

  if (options$mode == "rmarkdown") {
    document <- normalizePath(options$target, mustWork = TRUE)
    root_prefix <- paste0(package_root, .Platform$file.sep)
    if (!identical(document, package_root) && !startsWith(document, root_prefix)) {
      stop("R Markdown document must be beneath the package root", call. = FALSE)
    }
    if (!requireNamespace("rmarkdown", quietly = TRUE)) {
      stop("rmarkdown is required for --rmarkdown", call. = FALSE)
    }
  } else if (!requireNamespace("pkgdown", quietly = TRUE)) {
    stop("pkgdown is required for --pkgdown", call. = FALSE)
  }

  temporary_root <- tempfile("document-validation-")
  dir.create(temporary_root)
  on.exit(unlink(temporary_root, recursive = TRUE, force = TRUE), add = TRUE)

  library_path <- file.path(temporary_root, "library")
  render_path <- file.path(temporary_root, "rendered")
  cache_path <- file.path(temporary_root, "cache")
  dir.create(library_path)
  dir.create(render_path)
  dir.create(cache_path)

  install_target <- package_root
  if (options$build_source) {
    build_path <- file.path(temporary_root, "build")
    dir.create(build_path)
    previous_path <- setwd(build_path)
    on.exit(setwd(previous_path), add = TRUE)
    run_command(
      file.path(R.home("bin"), "R"),
      c("CMD", "build", shQuote(package_root)),
      "R CMD build"
    )
    setwd(previous_path)
    tarballs <- list.files(build_path, pattern = "[.]tar[.]gz$", full.names = TRUE)
    if (length(tarballs) != 1L) {
      stop("R CMD build did not produce exactly one source tarball", call. = FALSE)
    }
    install_target <- tarballs[[1L]]
  }

  run_command(
    file.path(R.home("bin"), "R"),
    c("CMD", "INSTALL", "-l", shQuote(library_path), shQuote(install_target)),
    "R CMD INSTALL"
  )

  old_library_paths <- .libPaths()
  old_r_libs_user <- Sys.getenv("R_LIBS_USER", unset = NA_character_)
  old_cache <- Sys.getenv("XDG_CACHE_HOME", unset = NA_character_)
  on.exit(.libPaths(old_library_paths), add = TRUE)
  on.exit({
    if (is.na(old_r_libs_user)) Sys.unsetenv("R_LIBS_USER") else Sys.setenv(R_LIBS_USER = old_r_libs_user)
    if (is.na(old_cache)) Sys.unsetenv("XDG_CACHE_HOME") else Sys.setenv(XDG_CACHE_HOME = old_cache)
  }, add = TRUE)
  .libPaths(c(library_path, old_library_paths))
  Sys.setenv(R_LIBS_USER = library_path, XDG_CACHE_HOME = cache_path)

  for (relative_path in options$expected_docs) {
    validate_expected_doc(relative_path, package_name, library_path)
  }

  if (options$mode == "rmarkdown") {
    output <- rmarkdown::render(
      document,
      output_dir = render_path,
      envir = new.env(parent = globalenv()),
      quiet = TRUE
    )
    if (length(output) == 0L || any(!file.exists(output))) {
      stop("rmarkdown did not produce the expected rendered output", call. = FALSE)
    }
  } else {
    pkgdown::build_article(
      options$target,
      pkg = package_root,
      new_process = FALSE,
      override = list(destination = render_path),
      quiet = TRUE
    )
    if (length(list.files(render_path, recursive = TRUE, all.files = TRUE)) == 0L) {
      stop("pkgdown did not produce article output", call. = FALSE)
    }
  }

  source_kind <- if (options$build_source) "built source tarball" else "source directory"
  writeLines(sprintf("Validated %s target %s using a temporary install of the %s.", options$mode, options$target, source_kind))
}

tryCatch(
  main(),
  error = function(error) {
    writeLines(paste0("validate-document.R: ", conditionMessage(error)), stderr())
    quit(status = 1L, save = "no")
  }
)
