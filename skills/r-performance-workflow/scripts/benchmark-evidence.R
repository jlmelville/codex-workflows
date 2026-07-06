#!/usr/bin/env Rscript

usage <- function() {
  cat(
    "Usage: benchmark-evidence.R cases.R [--reps N] [--seed N] [--baseline NAME] [--out PREFIX]\n",
    "\n",
    "cases.R must define benchmark_cases, a named list of zero-argument functions.\n",
    "Optional objects: benchmark_setup() and benchmark_metadata, a named list.\n",
    sep = ""
  )
}

parse_args <- function(args) {
  if (length(args) < 1L || args[[1L]] %in% c("-h", "--help")) {
    usage()
    quit(status = if (length(args) < 1L) 1L else 0L)
  }

  opts <- list(
    cases = args[[1L]],
    reps = 5L,
    seed = 1L,
    baseline = NA_character_,
    out = "benchmark-evidence"
  )

  i <- 2L
  while (i <= length(args)) {
    key <- args[[i]]
    if (!key %in% c("--reps", "--seed", "--baseline", "--out")) {
      stop("Unknown argument: ", key, call. = FALSE)
    }
    if (i == length(args)) {
      stop("Missing value for ", key, call. = FALSE)
    }
    value <- args[[i + 1L]]
    if (key == "--reps") {
      opts$reps <- as.integer(value)
    } else if (key == "--seed") {
      opts$seed <- as.integer(value)
    } else if (key == "--baseline") {
      opts$baseline <- value
    } else if (key == "--out") {
      opts$out <- value
    }
    i <- i + 2L
  }

  if (is.na(opts$reps) || opts$reps < 1L) {
    stop("--reps must be a positive integer", call. = FALSE)
  }
  if (is.na(opts$seed)) {
    stop("--seed must be an integer", call. = FALSE)
  }
  opts
}

source_cases <- function(path) {
  env <- new.env(parent = globalenv())
  sys.source(path, envir = env)

  if (!exists("benchmark_cases", envir = env, inherits = FALSE)) {
    stop("cases file must define benchmark_cases", call. = FALSE)
  }
  cases <- get("benchmark_cases", envir = env, inherits = FALSE)
  if (!is.list(cases) || length(cases) == 0L || is.null(names(cases)) ||
      any(names(cases) == "")) {
    stop("benchmark_cases must be a non-empty named list", call. = FALSE)
  }
  if (!all(vapply(cases, is.function, logical(1)))) {
    stop("every benchmark_cases entry must be a function", call. = FALSE)
  }

  setup <- NULL
  if (exists("benchmark_setup", envir = env, inherits = FALSE)) {
    setup <- get("benchmark_setup", envir = env, inherits = FALSE)
    if (!is.function(setup)) {
      stop("benchmark_setup must be a function when defined", call. = FALSE)
    }
  }

  metadata <- list()
  if (exists("benchmark_metadata", envir = env, inherits = FALSE)) {
    metadata <- get("benchmark_metadata", envir = env, inherits = FALSE)
    if (!is.list(metadata) || is.null(names(metadata))) {
      stop("benchmark_metadata must be a named list when defined", call. = FALSE)
    }
  }

  list(cases = cases, setup = setup, metadata = metadata)
}

time_case <- function(name, fun, reps, seed, setup) {
  rows <- vector("list", reps)
  for (rep in seq_len(reps)) {
    set.seed(seed + rep - 1L)
    if (!is.null(setup)) {
      setup()
    }
    gc()
    timing <- system.time(value <- fun())
    rows[[rep]] <- data.frame(
      case = name,
      rep = rep,
      elapsed = unname(timing[["elapsed"]]),
      user = unname(timing[["user.self"]]),
      system = unname(timing[["sys.self"]]),
      result_class = paste(class(value), collapse = "/"),
      result_length = length(value),
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

summarize_results <- function(results, baseline) {
  cases <- split(results, results$case)
  case_order <- unique(results$case)
  summary <- do.call(
    rbind,
    lapply(case_order, function(name) {
      elapsed <- cases[[name]]$elapsed
      data.frame(
        case = name,
        reps = length(elapsed),
        median_elapsed = median(elapsed),
        min_elapsed = min(elapsed),
        max_elapsed = max(elapsed),
        stringsAsFactors = FALSE
      )
    })
  )

  if (is.na(baseline)) {
    baseline <- summary$case[[1L]]
  }
  if (!baseline %in% summary$case) {
    stop("Unknown benchmark baseline: ", baseline, call. = FALSE)
  }
  baseline_elapsed <- summary$median_elapsed[summary$case == baseline]
  if (length(baseline_elapsed) == 1L && is.finite(baseline_elapsed) &&
      baseline_elapsed > 0) {
    summary$relative_speed <- baseline_elapsed / summary$median_elapsed
    summary$relative_speed[summary$median_elapsed <= 0] <- NA_real_
  } else {
    stop("Benchmark baseline has non-positive or non-finite median elapsed time: ",
      baseline,
      call. = FALSE
    )
  }
  summary
}

write_markdown <- function(path, opts, metadata, summary) {
  con <- file(path, open = "w", encoding = "UTF-8")
  on.exit(close(con), add = TRUE)

  cat("# Benchmark Evidence\n\n", file = con)
  cat("## Command\n\n", file = con)
  cat("```sh\n", file = con)
  cat(paste(commandArgs(FALSE), collapse = " "), "\n", sep = "", file = con)
  cat("```\n\n", file = con)

  cat("## Metadata\n\n", file = con)
  metadata <- c(
    list(
      cases = opts$cases,
      reps = opts$reps,
      seed = opts$seed,
      baseline = if (is.na(opts$baseline)) summary$case[[1L]] else opts$baseline,
      r_version = paste(R.version$major, R.version$minor, sep = "."),
      platform = R.version$platform
    ),
    metadata
  )
  for (name in names(metadata)) {
    cat("- ", name, ": ", as.character(metadata[[name]]), "\n", sep = "", file = con)
  }

  cat("\n## Summary\n\n", file = con)
  cat("| case | reps | median_elapsed | min_elapsed | max_elapsed | relative_speed |\n", file = con)
  cat("|---|---:|---:|---:|---:|---:|\n", file = con)
  for (i in seq_len(nrow(summary))) {
    cat(
      "| ", summary$case[[i]],
      " | ", summary$reps[[i]],
      " | ", sprintf("%.6f", summary$median_elapsed[[i]]),
      " | ", sprintf("%.6f", summary$min_elapsed[[i]]),
      " | ", sprintf("%.6f", summary$max_elapsed[[i]]),
      " | ", sprintf("%.3f", summary$relative_speed[[i]]),
      " |\n",
      sep = "",
      file = con
    )
  }
}

main <- function() {
  opts <- parse_args(commandArgs(trailingOnly = TRUE))
  loaded <- source_cases(opts$cases)

  results <- do.call(
    rbind,
    lapply(names(loaded$cases), function(name) {
      time_case(name, loaded$cases[[name]], opts$reps, opts$seed, loaded$setup)
    })
  )
  summary <- summarize_results(results, opts$baseline)

  csv_path <- paste0(opts$out, ".csv")
  md_path <- paste0(opts$out, ".md")
  dir.create(dirname(csv_path), recursive = TRUE, showWarnings = FALSE)
  write.csv(results, csv_path, row.names = FALSE)
  write_markdown(md_path, opts, loaded$metadata, summary)

  print(summary, row.names = FALSE)
  cat("Wrote ", csv_path, "\n", sep = "")
  cat("Wrote ", md_path, "\n", sep = "")
}

main()
