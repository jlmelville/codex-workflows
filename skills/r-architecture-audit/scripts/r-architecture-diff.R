#!/usr/bin/env Rscript

usage <- function() {
  cat(
    "Usage: r-architecture-diff.R --before DIR --after DIR [--out DIR] [--top N]\n",
    "       r-architecture-diff.R --self-test\n",
    "\n",
    "Compare two report directories produced by r-architecture-map.R.\n",
    "Without --out, the Markdown summary is written to standard output.\n",
    sep = ""
  )
}

abort <- function(...) {
  stop(..., call. = FALSE)
}

parse_args <- function(args) {
  opts <- list(
    before = NULL,
    after = NULL,
    out = NULL,
    top = 20L,
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
    if (!key %in% c("--before", "--after", "--out", "--top")) {
      abort("unknown argument: ", key)
    }
    if (i == length(args)) {
      abort("missing value for ", key)
    }
    value <- args[[i + 1L]]
    if (key == "--before") {
      opts$before <- value
    } else if (key == "--after") {
      opts$after <- value
    } else if (key == "--out") {
      opts$out <- value
    } else {
      opts$top <- suppressWarnings(as.integer(value))
    }
    i <- i + 2L
  }

  if (opts$self_test) {
    if (length(args) != 1L) {
      abort("--self-test cannot be combined with other arguments")
    }
    return(opts)
  }
  for (name in c("before", "after")) {
    value <- opts[[name]]
    if (is.null(value) || is.na(value) || !nzchar(value)) {
      abort("--", name, " requires a non-empty directory")
    }
  }
  if (!is.null(opts$out) && (is.na(opts$out) || !nzchar(opts$out))) {
    abort("--out requires a non-empty directory")
  }
  if (is.na(opts$top) || opts$top < 1L) {
    abort("--top must be a positive integer")
  }
  opts
}

table_contracts <- list(
  functions = c(
    "name",
    "file",
    "line",
    "lines",
    "public_root",
    "reachable",
    "complexity",
    "inbound_internal",
    "outbound_internal",
    "test_file_count"
  ),
  edges = c(
    "caller",
    "callee",
    "reference_kind",
    "caller_file",
    "callee_file"
  ),
  `file-coupling` = c(
    "source_file",
    "target_file",
    "edge_count",
    "source_functions",
    "target_functions"
  ),
  sccs = c("scc_id", "size", "files", "members"),
  `private-test-coupling` = c("symbol", "source_file", "test_file")
)

read_table <- function(report_dir, table_name, required_columns) {
  if (!dir.exists(report_dir)) {
    abort("map report directory not found: ", report_dir)
  }
  table_path <- file.path(report_dir, paste0(table_name, ".tsv"))
  if (!file.exists(table_path)) {
    abort("map report is missing ", basename(table_path), ": ", report_dir)
  }
  data <- tryCatch(
    read.delim(
      table_path,
      check.names = FALSE,
      stringsAsFactors = FALSE,
      quote = "\"",
      na.strings = ""
    ),
    error = function(error) {
      abort(basename(table_path), ": ", conditionMessage(error))
    }
  )
  missing <- setdiff(required_columns, names(data))
  if (length(missing) > 0L) {
    abort(
      basename(table_path),
      " is missing required columns: ",
      paste(missing, collapse = ", ")
    )
  }
  data
}

read_map <- function(report_dir) {
  normalized <- normalizePath(report_dir, winslash = "/", mustWork = TRUE)
  result <- lapply(names(table_contracts), function(table_name) {
    read_table(normalized, table_name, table_contracts[[table_name]])
  })
  names(result) <- names(table_contracts)
  result
}

require_unique_key <- function(data, columns, label) {
  if (nrow(data) == 0L) {
    return(invisible(NULL))
  }
  values <- lapply(data[, columns, drop = FALSE], function(column) {
    value <- as.character(column)
    value[is.na(value)] <- "<NA>"
    value
  })
  keys <- do.call(paste, c(values, sep = "\034"))
  if (anyDuplicated(keys)) {
    abort(label, " contains duplicate identity rows")
  }
  invisible(NULL)
}

logical_values <- function(values, label) {
  normalized <- tolower(as.character(values))
  valid <- normalized %in% c("true", "false", "t", "f", "1", "0")
  if (any(!valid & !is.na(values))) {
    abort(label, " contains a non-logical value")
  }
  normalized %in% c("true", "t", "1")
}

numeric_values <- function(values, label) {
  result <- suppressWarnings(as.numeric(values))
  if (any(is.na(result) & !is.na(values))) {
    abort(label, " contains a non-numeric value")
  }
  result
}

canonical_members <- function(values) {
  vapply(
    values,
    function(value) {
      members <- trimws(strsplit(as.character(value), ",", fixed = TRUE)[[1L]])
      paste(sort(unique(members[nzchar(members)])), collapse = ",")
    },
    character(1L)
  )
}

same_scalar <- function(left, right) {
  if (length(left) == 0L || length(right) == 0L) {
    return(FALSE)
  }
  if (is.na(left) && is.na(right)) {
    return(TRUE)
  }
  if (is.na(left) || is.na(right)) {
    return(FALSE)
  }
  identical(as.character(left), as.character(right))
}

scalar_or_na <- function(data, row, column) {
  if (is.na(row)) NA else data[[column]][[row]]
}

numeric_or_na <- function(value) {
  if (length(value) == 0L || is.na(value)) {
    return(NA_real_)
  }
  as.numeric(value)
}

function_changes <- function(before, after) {
  require_unique_key(before, "name", "before functions.tsv")
  require_unique_key(after, "name", "after functions.tsv")
  fields <- c(
    "file",
    "lines",
    "public_root",
    "reachable",
    "complexity",
    "inbound_internal",
    "outbound_internal",
    "test_file_count"
  )
  rows <- list()
  for (name in sort(union(before$name, after$name))) {
    before_row <- match(name, before$name)
    after_row <- match(name, after$name)
    change <- if (is.na(before_row)) {
      "added"
    } else if (is.na(after_row)) {
      "removed"
    } else if (
      all(vapply(
        fields,
        function(field) {
          same_scalar(
            before[[field]][[before_row]],
            after[[field]][[after_row]]
          )
        },
        logical(1L)
      ))
    ) {
      "unchanged"
    } else {
      "modified"
    }
    if (change == "unchanged") {
      next
    }
    before_complexity <- numeric_or_na(
      scalar_or_na(before, before_row, "complexity")
    )
    after_complexity <- numeric_or_na(
      scalar_or_na(after, after_row, "complexity")
    )
    complexity_delta <- if (is.na(before_complexity)) {
      after_complexity
    } else if (is.na(after_complexity)) {
      -before_complexity
    } else {
      after_complexity - before_complexity
    }
    rows[[length(rows) + 1L]] <- data.frame(
      name = name,
      change = change,
      before_file = scalar_or_na(before, before_row, "file"),
      after_file = scalar_or_na(after, after_row, "file"),
      before_lines = numeric_or_na(scalar_or_na(before, before_row, "lines")),
      after_lines = numeric_or_na(scalar_or_na(after, after_row, "lines")),
      before_public_root = scalar_or_na(before, before_row, "public_root"),
      after_public_root = scalar_or_na(after, after_row, "public_root"),
      before_reachable = scalar_or_na(before, before_row, "reachable"),
      after_reachable = scalar_or_na(after, after_row, "reachable"),
      before_complexity = before_complexity,
      after_complexity = after_complexity,
      complexity_delta = complexity_delta,
      before_inbound = numeric_or_na(
        scalar_or_na(before, before_row, "inbound_internal")
      ),
      after_inbound = numeric_or_na(
        scalar_or_na(after, after_row, "inbound_internal")
      ),
      before_outbound = numeric_or_na(
        scalar_or_na(before, before_row, "outbound_internal")
      ),
      after_outbound = numeric_or_na(
        scalar_or_na(after, after_row, "outbound_internal")
      ),
      before_test_files = numeric_or_na(
        scalar_or_na(before, before_row, "test_file_count")
      ),
      after_test_files = numeric_or_na(
        scalar_or_na(after, after_row, "test_file_count")
      ),
      stringsAsFactors = FALSE
    )
  }
  if (length(rows) == 0L) {
    return(data.frame(
      name = character(),
      change = character(),
      before_file = character(),
      after_file = character(),
      before_lines = numeric(),
      after_lines = numeric(),
      before_public_root = logical(),
      after_public_root = logical(),
      before_reachable = logical(),
      after_reachable = logical(),
      before_complexity = numeric(),
      after_complexity = numeric(),
      complexity_delta = numeric(),
      before_inbound = numeric(),
      after_inbound = numeric(),
      before_outbound = numeric(),
      after_outbound = numeric(),
      before_test_files = numeric(),
      after_test_files = numeric(),
      stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, rows)
}

row_keys <- function(data, columns) {
  if (nrow(data) == 0L) {
    return(character())
  }
  do.call(
    paste,
    c(lapply(data[, columns, drop = FALSE], as.character), sep = "\034")
  )
}

set_changes <- function(before, after, columns, label) {
  before <- before[, columns, drop = FALSE]
  after <- after[, columns, drop = FALSE]
  require_unique_key(before, columns, paste("before", label))
  require_unique_key(after, columns, paste("after", label))
  before_keys <- row_keys(before, columns)
  after_keys <- row_keys(after, columns)
  removed <- before[!before_keys %in% after_keys, , drop = FALSE]
  added <- after[!after_keys %in% before_keys, , drop = FALSE]
  if (nrow(removed) > 0L) {
    removed <- data.frame(change = "removed", removed, stringsAsFactors = FALSE)
  }
  if (nrow(added) > 0L) {
    added <- data.frame(change = "added", added, stringsAsFactors = FALSE)
  }
  result <- rbind(removed, added)
  if (nrow(result) == 0L) {
    result <- data.frame(
      change = character(),
      before[FALSE, , drop = FALSE],
      stringsAsFactors = FALSE
    )
  }
  result[do.call(order, result[c(columns, "change")]), , drop = FALSE]
}

coupling_changes <- function(before, after) {
  key_columns <- c("source_file", "target_file")
  value_columns <- c("edge_count", "source_functions", "target_functions")
  require_unique_key(before, key_columns, "before file-coupling.tsv")
  require_unique_key(after, key_columns, "after file-coupling.tsv")
  rows <- list()
  keys <- sort(union(
    row_keys(before, key_columns),
    row_keys(after, key_columns)
  ))
  before_keys <- row_keys(before, key_columns)
  after_keys <- row_keys(after, key_columns)
  for (key in keys) {
    before_row <- match(key, before_keys)
    after_row <- match(key, after_keys)
    before_values <- vapply(
      value_columns,
      function(column) {
        numeric_or_na(scalar_or_na(before, before_row, column))
      },
      numeric(1L)
    )
    after_values <- vapply(
      value_columns,
      function(column) {
        numeric_or_na(scalar_or_na(after, after_row, column))
      },
      numeric(1L)
    )
    if (
      !is.na(before_row) &&
        !is.na(after_row) &&
        identical(before_values, after_values)
    ) {
      next
    }
    source_row <- if (!is.na(after_row)) after_row else before_row
    source_data <- if (!is.na(after_row)) after else before
    before_zero <- ifelse(is.na(before_values), 0, before_values)
    after_zero <- ifelse(is.na(after_values), 0, after_values)
    rows[[length(rows) + 1L]] <- data.frame(
      source_file = source_data$source_file[[source_row]],
      target_file = source_data$target_file[[source_row]],
      before_edge_count = before_values[["edge_count"]],
      after_edge_count = after_values[["edge_count"]],
      edge_count_delta = after_zero[["edge_count"]] -
        before_zero[["edge_count"]],
      before_source_functions = before_values[["source_functions"]],
      after_source_functions = after_values[["source_functions"]],
      before_target_functions = before_values[["target_functions"]],
      after_target_functions = after_values[["target_functions"]],
      stringsAsFactors = FALSE
    )
  }
  if (length(rows) == 0L) {
    return(data.frame(
      source_file = character(),
      target_file = character(),
      before_edge_count = numeric(),
      after_edge_count = numeric(),
      edge_count_delta = numeric(),
      before_source_functions = numeric(),
      after_source_functions = numeric(),
      before_target_functions = numeric(),
      after_target_functions = numeric(),
      stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, rows)
}

scc_changes <- function(before, after) {
  before$member_set <- canonical_members(before$members)
  after$member_set <- canonical_members(after$members)
  require_unique_key(before, "member_set", "before sccs.tsv")
  require_unique_key(after, "member_set", "after sccs.tsv")
  rows <- list()
  for (members in sort(union(before$member_set, after$member_set))) {
    before_row <- match(members, before$member_set)
    after_row <- match(members, after$member_set)
    change <- if (is.na(before_row)) {
      "added"
    } else if (is.na(after_row)) {
      "removed"
    } else if (
      same_scalar(before$files[[before_row]], after$files[[after_row]]) &&
        same_scalar(before$size[[before_row]], after$size[[after_row]])
    ) {
      "unchanged"
    } else {
      "modified"
    }
    if (change == "unchanged") {
      next
    }
    rows[[length(rows) + 1L]] <- data.frame(
      members = members,
      change = change,
      before_size = numeric_or_na(scalar_or_na(before, before_row, "size")),
      after_size = numeric_or_na(scalar_or_na(after, after_row, "size")),
      before_files = scalar_or_na(before, before_row, "files"),
      after_files = scalar_or_na(after, after_row, "files"),
      stringsAsFactors = FALSE
    )
  }
  if (length(rows) == 0L) {
    return(data.frame(
      members = character(),
      change = character(),
      before_size = numeric(),
      after_size = numeric(),
      before_files = character(),
      after_files = character(),
      stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, rows)
}

metric_values <- function(map) {
  functions <- map$functions
  reachable <- logical_values(functions$reachable, "functions.tsv reachable")
  public <- logical_values(functions$public_root, "functions.tsv public_root")
  complexity <- numeric_values(functions$complexity, "functions.tsv complexity")
  lines <- numeric_values(functions$lines, "functions.tsv lines")
  coupling_edges <- numeric_values(
    map$`file-coupling`$edge_count,
    "file-coupling.tsv edge_count"
  )
  scc_sizes <- numeric_values(map$sccs$size, "sccs.tsv size")
  c(
    active_functions = nrow(functions),
    public_roots = sum(public),
    reachable_functions = sum(reachable),
    unreachable_candidates = sum(!reachable),
    mapped_function_lines = sum(lines, na.rm = TRUE),
    complexity_sum = sum(complexity, na.rm = TRUE),
    maximum_complexity = if (length(complexity) == 0L) 0 else
      max(complexity, na.rm = TRUE),
    internal_edges = nrow(map$edges),
    cross_file_edges = sum(coupling_edges, na.rm = TRUE),
    multi_function_sccs = sum(scc_sizes > 1L, na.rm = TRUE),
    private_test_references = nrow(map$`private-test-coupling`)
  )
}

compare_maps <- function(before, after) {
  before_metrics <- metric_values(before)
  after_metrics <- metric_values(after)
  metrics <- data.frame(
    metric = names(before_metrics),
    before = unname(before_metrics),
    after = unname(after_metrics),
    delta = unname(after_metrics - before_metrics),
    stringsAsFactors = FALSE
  )
  list(
    metrics = metrics,
    functions = function_changes(before$functions, after$functions),
    edges = set_changes(
      before$edges,
      after$edges,
      table_contracts$edges,
      "edges.tsv"
    ),
    file_coupling = coupling_changes(
      before$`file-coupling`,
      after$`file-coupling`
    ),
    sccs = scc_changes(before$sccs, after$sccs),
    private_test_coupling = set_changes(
      before$`private-test-coupling`,
      after$`private-test-coupling`,
      table_contracts$`private-test-coupling`,
      "private-test-coupling.tsv"
    )
  )
}

markdown_escape <- function(value) {
  gsub("[|]", "\\\\|", as.character(value))
}

markdown_table <- function(data, columns = names(data)) {
  if (nrow(data) == 0L) {
    return("_None._")
  }
  data <- data[, columns, drop = FALSE]
  data[is.na(data)] <- ""
  header <- paste0(
    "| ",
    paste(markdown_escape(names(data)), collapse = " | "),
    " |"
  )
  rule <- paste0("| ", paste(rep("---", ncol(data)), collapse = " | "), " |")
  rows <- apply(data, 1L, function(row) {
    paste0("| ", paste(markdown_escape(row), collapse = " | "), " |")
  })
  paste(c(header, rule, rows), collapse = "\n")
}

build_summary <- function(result, top) {
  functions <- result$functions
  added_removed <- functions[
    functions$change %in% c("added", "removed"),
    c("name", "change", "before_file", "after_file"),
    drop = FALSE
  ]
  reachability <- functions[
    !is.na(functions$before_reachable) &
      !is.na(functions$after_reachable) &
      as.character(functions$before_reachable) !=
        as.character(functions$after_reachable),
    c("name", "before_reachable", "after_reachable"),
    drop = FALSE
  ]
  complexity <- functions[
    !is.na(functions$complexity_delta) & functions$complexity_delta != 0,
    c(
      "name",
      "before_complexity",
      "after_complexity",
      "complexity_delta"
    ),
    drop = FALSE
  ]
  if (nrow(complexity) > 0L) {
    complexity <- complexity[
      order(-abs(complexity$complexity_delta), complexity$name),
      ,
      drop = FALSE
    ]
  }
  lines <- c(
    "# R Architecture Map Difference",
    "",
    "## Metric Deltas",
    "",
    markdown_table(result$metrics),
    "",
    "## Added And Removed Functions",
    "",
    markdown_table(head(added_removed, top)),
    "",
    "## Reachability Changes",
    "",
    markdown_table(head(reachability, top)),
    "",
    "## Largest Complexity Changes",
    "",
    markdown_table(head(complexity, top)),
    "",
    "## Structural Change Counts",
    "",
    paste0("- Function changes: ", nrow(result$functions)),
    paste0("- Added or removed edges: ", nrow(result$edges)),
    paste0("- Cross-file coupling changes: ", nrow(result$file_coupling)),
    paste0("- Component changes: ", nrow(result$sccs)),
    paste0(
      "- Added or removed private-test references: ",
      nrow(result$private_test_coupling)
    ),
    "",
    "## Interpretation Boundary",
    "",
    "These deltas are navigation evidence, not quality scores or pass/fail gates.",
    "Confirm changes against source behavior, dynamic consumers, public contracts,",
    "and the cleanup question that motivated the comparison."
  )
  paste(lines, collapse = "\n")
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

write_report <- function(result, out, top) {
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
  stage <- tempfile(pattern = ".r-architecture-diff.", tmpdir = parent)
  if (!dir.create(stage)) {
    abort("could not create temporary report directory beneath: ", parent)
  }
  completed <- FALSE
  on.exit(
    if (!completed && dir.exists(stage)) {
      unlink(stage, recursive = TRUE, force = TRUE)
    },
    add = TRUE
  )

  write_atomic(file.path(stage, "summary.md"), function(path) {
    writeLines(build_summary(result, top), path, useBytes = TRUE)
  })
  write_tsv(result$metrics, file.path(stage, "metrics.tsv"))
  write_tsv(result$functions, file.path(stage, "functions.tsv"))
  write_tsv(result$edges, file.path(stage, "edges.tsv"))
  write_tsv(result$file_coupling, file.path(stage, "file-coupling.tsv"))
  write_tsv(result$sccs, file.path(stage, "sccs.tsv"))
  write_tsv(
    result$private_test_coupling,
    file.path(stage, "private-test-coupling.tsv")
  )
  if (!file.rename(stage, destination)) {
    abort("could not move completed report into place: ", destination)
  }
  completed <- TRUE
  normalizePath(destination, winslash = "/", mustWork = TRUE)
}

write_fixture_map <- function(root, functions, edges, coupling, sccs, tests) {
  dir.create(root)
  write.table(
    functions,
    file.path(root, "functions.tsv"),
    sep = "\t",
    row.names = FALSE,
    quote = TRUE
  )
  write.table(
    edges,
    file.path(root, "edges.tsv"),
    sep = "\t",
    row.names = FALSE,
    quote = TRUE
  )
  write.table(
    coupling,
    file.path(root, "file-coupling.tsv"),
    sep = "\t",
    row.names = FALSE,
    quote = TRUE
  )
  write.table(
    sccs,
    file.path(root, "sccs.tsv"),
    sep = "\t",
    row.names = FALSE,
    quote = TRUE
  )
  write.table(
    tests,
    file.path(root, "private-test-coupling.tsv"),
    sep = "\t",
    row.names = FALSE,
    quote = TRUE
  )
}

run_self_test <- function() {
  root <- tempfile("r-architecture-diff-test.")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  before_root <- file.path(root, "before")
  after_root <- file.path(root, "after")

  before_functions <- data.frame(
    name = c("alpha", "beta"),
    file = c("R/a.R", "R/b.R"),
    line = c(1L, 1L),
    lines = c(3L, 2L),
    public_root = c(TRUE, FALSE),
    reachable = c(TRUE, FALSE),
    complexity = c(2L, 1L),
    inbound_internal = c(0L, 0L),
    outbound_internal = c(1L, 0L),
    test_file_count = c(0L, 1L)
  )
  after_functions <- rbind(
    transform(before_functions[1L, ], complexity = 4L),
    before_functions[2L, ],
    data.frame(
      name = "gamma",
      file = "R/b.R",
      line = 4L,
      lines = 2L,
      public_root = FALSE,
      reachable = TRUE,
      complexity = 1L,
      inbound_internal = 1L,
      outbound_internal = 0L,
      test_file_count = 0L
    )
  )
  before_edges <- data.frame(
    caller = "alpha",
    callee = "beta",
    reference_kind = "call",
    caller_file = "R/a.R",
    callee_file = "R/b.R"
  )
  after_edges <- rbind(
    before_edges,
    data.frame(
      caller = "alpha",
      callee = "gamma",
      reference_kind = "call",
      caller_file = "R/a.R",
      callee_file = "R/b.R"
    )
  )
  before_coupling <- data.frame(
    source_file = "R/a.R",
    target_file = "R/b.R",
    edge_count = 1L,
    source_functions = 1L,
    target_functions = 1L
  )
  after_coupling <- transform(
    before_coupling,
    edge_count = 2L,
    target_functions = 2L
  )
  before_sccs <- data.frame(
    scc_id = c("SCC001", "SCC002"),
    size = c(1L, 1L),
    files = c("R/a.R", "R/b.R"),
    members = c("alpha", "beta")
  )
  after_sccs <- data.frame(
    scc_id = c("SCC099", "SCC100", "SCC101"),
    size = c(1L, 1L, 1L),
    files = c("R/a.R", "R/b.R", "R/b.R"),
    members = c("alpha", "beta", "gamma")
  )
  before_tests <- data.frame(
    symbol = "beta",
    source_file = "R/b.R",
    test_file = "tests/testthat/test-b.R"
  )
  after_tests <- before_tests

  write_fixture_map(
    before_root,
    before_functions,
    before_edges,
    before_coupling,
    before_sccs,
    before_tests
  )
  write_fixture_map(
    after_root,
    after_functions,
    after_edges,
    after_coupling,
    after_sccs,
    after_tests
  )
  before_map <- read_map(before_root)
  after_map <- read_map(after_root)
  result <- compare_maps(before_map, after_map)
  stopifnot(identical(result, compare_maps(before_map, after_map)))
  stopifnot(
    result$metrics$delta[result$metrics$metric == "active_functions"] == 1
  )
  stopifnot(
    result$functions$change[result$functions$name == "gamma"] == "added"
  )
  stopifnot(
    result$functions$complexity_delta[result$functions$name == "alpha"] == 2
  )
  stopifnot(nrow(result$edges) == 1L)
  stopifnot(nrow(result$sccs) == 1L)
  stopifnot(result$sccs$members[[1L]] == "gamma")
  stopifnot(nrow(result$private_test_coupling) == 0L)

  out <- file.path(root, "diff")
  write_report(result, out, 10L)
  stopifnot(all(file.exists(file.path(
    out,
    c("summary.md", "metrics.tsv", "functions.tsv", "sccs.tsv")
  ))))
  invisible(TRUE)
}

main <- function(args) {
  opts <- parse_args(args)
  if (opts$self_test) {
    run_self_test()
    cat("R architecture diff self-test passed.\n")
    return(invisible(NULL))
  }
  result <- compare_maps(read_map(opts$before), read_map(opts$after))
  if (is.null(opts$out)) {
    cat(build_summary(result, opts$top), "\n", sep = "")
  } else {
    destination <- write_report(result, opts$out, opts$top)
    cat(destination, "\n", sep = "")
  }
  invisible(NULL)
}

tryCatch(
  main(commandArgs(trailingOnly = TRUE)),
  error = function(error) {
    message("r-architecture-diff.R: ", conditionMessage(error))
    quit(status = 1L)
  }
)
