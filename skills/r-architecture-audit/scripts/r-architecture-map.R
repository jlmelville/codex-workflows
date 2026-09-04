#!/usr/bin/env Rscript

usage <- function() {
  cat(
    "Usage: r-architecture-map.R --package DIR [--out DIR] [--top N]\n",
    "       r-architecture-map.R --self-test\n",
    "\n",
    "Build a read-only static architecture map for a conventional R package.\n",
    "Without --out, the Markdown summary is written to standard output.\n",
    sep = ""
  )
}

abort <- function(...) {
  stop(..., call. = FALSE)
}

map_metadata <- function(reference_method) {
  data.frame(
    format_version = "1",
    producer = "r-architecture-map.R",
    producer_version = "1",
    reference_method = reference_method,
    stringsAsFactors = FALSE
  )
}

parse_args <- function(args) {
  opts <- list(package = NULL, out = NULL, top = 20L, self_test = FALSE)
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
    if (!key %in% c("--package", "--out", "--top")) {
      abort("unknown argument: ", key)
    }
    if (i == length(args)) {
      abort("missing value for ", key)
    }
    value <- args[[i + 1L]]
    if (key == "--package") {
      opts$package <- value
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
  if (is.null(opts$package) || is.na(opts$package) || !nzchar(opts$package)) {
    abort("--package requires a non-empty directory")
  }
  if (!is.null(opts$out) && (is.na(opts$out) || !nzchar(opts$out))) {
    abort("--out requires a non-empty directory")
  }
  if (is.na(opts$top) || opts$top < 1L) {
    abort("--top must be a positive integer")
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

source_order <- function(package_root, files) {
  description <- file.path(package_root, "DESCRIPTION")
  if (!file.exists(description)) {
    abort("package DESCRIPTION not found: ", description)
  }
  fields <- tryCatch(read.dcf(description), error = function(error) {
    abort("cannot parse DESCRIPTION: ", conditionMessage(error))
  })
  collate <- if ("Collate" %in% colnames(fields)) fields[[1L, "Collate"]] else
    NA_character_
  if (is.na(collate) || !nzchar(trimws(collate))) {
    return(sort(files))
  }

  names <- scan(text = collate, what = character(), quiet = TRUE)
  ordered <- vapply(
    names,
    function(name) {
      matches <- files[basename(files) == name]
      if (length(matches) == 1L) matches else NA_character_
    },
    character(1L)
  )
  ordered <- ordered[!is.na(ordered)]
  c(ordered, setdiff(sort(files), ordered))
}

source_extent <- function(ref) {
  if (is.null(ref)) {
    return(c(line = NA_integer_, end_line = NA_integer_, lines = NA_integer_))
  }
  values <- as.integer(ref)
  start <- values[[1L]]
  end <- values[[3L]]
  c(line = start, end_line = end, lines = end - start + 1L)
}

assignment_parts <- function(expr) {
  if (!is.call(expr)) {
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

is_function_literal <- function(expr) {
  is.call(expr) && identical(expr[[1L]], as.name("function"))
}

empty_diagnostics <- function() {
  data.frame(
    kind = character(),
    file = character(),
    line = integer(),
    detail = character(),
    stringsAsFactors = FALSE
  )
}

add_diagnostic <- function(diagnostics, kind, file, line, detail) {
  rbind(
    diagnostics,
    data.frame(
      kind = kind,
      file = file,
      line = line,
      detail = detail,
      stringsAsFactors = FALSE
    )
  )
}

inventory_definitions <- function(package_root) {
  r_dir <- file.path(package_root, "R")
  if (!dir.exists(r_dir)) {
    abort("package R directory not found: ", r_dir)
  }
  files <- list.files(
    r_dir,
    pattern = "[.][Rr]$",
    recursive = TRUE,
    full.names = TRUE
  )
  files <- normalizePath(files, winslash = "/", mustWork = TRUE)
  files <- source_order(package_root, files)
  if (length(files) == 0L) {
    abort("no R source files found beneath: ", r_dir)
  }

  definitions <- list()
  diagnostics <- empty_diagnostics()
  dynamic_heads <- c(
    "assign",
    "delayedAssign",
    "get",
    "do.call",
    "setMethod",
    "setClass",
    "setRefClass",
    "R6Class",
    "registerS3method",
    ".Call",
    ".External"
  )

  for (file_index in seq_along(files)) {
    file <- files[[file_index]]
    relative <- package_relative_path(file, package_root)
    expressions <- tryCatch(
      parse(file = file, keep.source = TRUE, encoding = "UTF-8"),
      error = function(error) abort(relative, ": ", conditionMessage(error))
    )
    source_refs <- attr(expressions, "srcref")
    for (expression_index in seq_along(expressions)) {
      expr <- expressions[[expression_index]]
      source_ref <- if (length(source_refs) >= expression_index) {
        source_refs[[expression_index]]
      } else {
        attr(expr, "srcref")
      }
      extent <- source_extent(source_ref)
      parts <- assignment_parts(expr)
      if (!is.null(parts)) {
        fun <- NULL
        if (is_function_literal(parts$rhs)) {
          fun <- eval(parts$rhs, envir = baseenv())
        }
        definitions[[length(definitions) + 1L]] <- list(
          name = parts$name,
          file = relative,
          file_index = file_index,
          expression_index = expression_index,
          line = unname(extent[["line"]]),
          end_line = unname(extent[["end_line"]]),
          lines = unname(extent[["lines"]]),
          is_function = !is.null(fun),
          fun = fun
        )
      }

      heads <- intersect(
        unique(all.names(expr, functions = TRUE)),
        dynamic_heads
      )
      for (head in heads) {
        diagnostics <- add_diagnostic(
          diagnostics,
          "dynamic-construct",
          relative,
          unname(extent[["line"]]),
          paste0(head, " requires manual reachability review")
        )
      }
    }
  }

  if (length(definitions) == 0L) {
    abort("no conventional top-level assignments found beneath R/")
  }
  definition_names <- vapply(definitions, `[[`, character(1L), "name")
  duplicate_names <- names(Filter(
    function(items) length(items) > 1L,
    split(definitions, definition_names)
  ))
  for (name in duplicate_names) {
    locations <- vapply(
      definitions[definition_names == name],
      function(item) paste0(item$file, ":", item$line),
      character(1L)
    )
    diagnostics <- add_diagnostic(
      diagnostics,
      "duplicate-definition",
      paste(
        unique(vapply(
          definitions[definition_names == name],
          `[[`,
          character(1L),
          "file"
        )),
        collapse = ","
      ),
      NA_integer_,
      paste0(
        name,
        " is assigned at ",
        paste(locations, collapse = ", "),
        "; the last source-order binding is mapped"
      )
    )
  }

  active_index <- vapply(
    split(seq_along(definitions), definition_names),
    tail,
    integer(1L),
    1L
  )
  active <- definitions[sort(active_index)]
  list(definitions = definitions, active = active, diagnostics = diagnostics)
}

token_value <- function(value) {
  if (is.symbol(value)) {
    return(as.character(value))
  }
  if (is.character(value) && length(value) == 1L) {
    return(value)
  }
  paste(deparse(value, width.cutoff = 500L), collapse = "")
}

namespace_roots <- function(package_root, function_names) {
  namespace <- file.path(package_root, "NAMESPACE")
  if (!file.exists(namespace)) {
    abort("package NAMESPACE not found: ", namespace)
  }
  expressions <- tryCatch(parse(file = namespace), error = function(error) {
    abort("cannot parse NAMESPACE: ", conditionMessage(error))
  })
  roots <- character()
  public <- character()
  reasons <- character()
  diagnostics <- empty_diagnostics()

  add_root <- function(name, reason, is_public = TRUE) {
    if (!nzchar(name)) {
      return(invisible(NULL))
    }
    roots <<- c(roots, name)
    prior_reasons <- unname(reasons[name])
    prior_reasons <- prior_reasons[!is.na(prior_reasons)]
    reasons[[name]] <<- paste(unique(c(prior_reasons, reason)), collapse = ",")
    if (is_public) {
      public <<- c(public, name)
    }
    invisible(NULL)
  }

  for (expr in expressions) {
    if (!is.call(expr)) {
      next
    }
    head <- as.character(expr[[1L]])
    args <- as.list(expr)[-1L]
    if (head %in% c("export", "exportMethods", "exportClasses")) {
      for (arg in args) {
        add_root(token_value(arg), head)
      }
    } else if (head == "exportPattern" && length(args) >= 1L) {
      pattern <- token_value(args[[1L]])
      matches <- tryCatch(
        grep(pattern, function_names, value = TRUE),
        error = function(error) character()
      )
      for (name in matches) {
        add_root(name, "exportPattern")
      }
      diagnostics <- add_diagnostic(
        diagnostics,
        "namespace-pattern",
        "NAMESPACE",
        NA_integer_,
        paste0(
          "exportPattern(",
          pattern,
          ") matched ",
          length(matches),
          " mapped functions"
        )
      )
    } else if (head == "S3method" && length(args) >= 2L) {
      name <- if (length(args) >= 3L) {
        token_value(args[[3L]])
      } else {
        paste0(token_value(args[[1L]]), ".", token_value(args[[2L]]))
      }
      add_root(name, "S3method")
    }
  }

  lifecycle <- intersect(
    c(".onLoad", ".onAttach", ".onUnload", ".Last.lib"),
    function_names
  )
  for (name in lifecycle) {
    add_root(name, "load-hook", is_public = FALSE)
  }
  missing <- setdiff(unique(roots), function_names)
  for (name in missing) {
    diagnostics <- add_diagnostic(
      diagnostics,
      "unmapped-root",
      "NAMESPACE",
      NA_integer_,
      paste0(
        name,
        " is a namespace root without a conventional mapped function"
      )
    )
  }

  list(
    roots = intersect(unique(roots), function_names),
    public = intersect(unique(public), function_names),
    reasons = reasons,
    diagnostics = diagnostics
  )
}

internal_edges <- function(functions) {
  function_names <- names(functions)
  use_codetools <- requireNamespace("codetools", quietly = TRUE)
  rows <- list()
  for (caller in function_names) {
    fun <- functions[[caller]]$fun
    if (use_codetools) {
      globals <- codetools::findGlobals(fun, merge = FALSE)
      called <- intersect(unique(globals$functions), function_names)
      passed <- intersect(unique(globals$variables), function_names)
    } else {
      called <- intersect(
        unique(all.names(body(fun), functions = TRUE)),
        function_names
      )
      passed <- character()
    }
    callees <- sort(unique(c(called, passed)))
    for (callee in callees) {
      kind <- if (callee %in% called && callee %in% passed) {
        "call+value"
      } else if (callee %in% called) {
        "call"
      } else {
        "value"
      }
      rows[[length(rows) + 1L]] <- data.frame(
        caller = caller,
        callee = callee,
        reference_kind = kind,
        stringsAsFactors = FALSE
      )
    }
  }
  edges <- if (length(rows) == 0L) {
    data.frame(
      caller = character(),
      callee = character(),
      reference_kind = character()
    )
  } else {
    unique(do.call(rbind, rows))
  }
  list(
    edges = edges,
    method = if (use_codetools) "codetools" else "syntax-fallback"
  )
}

reachable_vertices <- function(vertices, edges, roots) {
  adjacency <- split(edges$callee, edges$caller)
  reached <- intersect(roots, vertices)
  queue <- reached
  while (length(queue) > 0L) {
    current <- queue[[1L]]
    queue <- queue[-1L]
    next_vertices <- setdiff(adjacency[[current]], reached)
    if (length(next_vertices) > 0L) {
      reached <- c(reached, next_vertices)
      queue <- c(queue, next_vertices)
    }
  }
  unique(reached)
}

strong_components <- function(vertices, edges) {
  adjacency <- split(edges$callee, edges$caller)
  index <- 0L
  indices <- setNames(rep(NA_integer_, length(vertices)), vertices)
  lowlink <- setNames(rep(NA_integer_, length(vertices)), vertices)
  on_stack <- setNames(rep(FALSE, length(vertices)), vertices)
  stack <- character()
  components <- list()

  visit <- function(vertex) {
    index <<- index + 1L
    indices[[vertex]] <<- index
    lowlink[[vertex]] <<- index
    stack <<- c(stack, vertex)
    on_stack[[vertex]] <<- TRUE

    for (next_vertex in sort(unique(adjacency[[vertex]]))) {
      if (is.na(indices[[next_vertex]])) {
        visit(next_vertex)
        lowlink[[vertex]] <<- min(lowlink[[vertex]], lowlink[[next_vertex]])
      } else if (on_stack[[next_vertex]]) {
        lowlink[[vertex]] <<- min(lowlink[[vertex]], indices[[next_vertex]])
      }
    }

    if (lowlink[[vertex]] == indices[[vertex]]) {
      component <- character()
      repeat {
        member <- tail(stack, 1L)
        stack <<- head(stack, -1L)
        on_stack[[member]] <<- FALSE
        component <- c(component, member)
        if (member == vertex) break
      }
      components[[length(components) + 1L]] <<- sort(component)
    }
  }

  for (vertex in sort(vertices)) {
    if (is.na(indices[[vertex]])) {
      visit(vertex)
    }
  }
  order <- order(vapply(
    components,
    function(component) component[[1L]],
    character(1L)
  ))
  components[order]
}

branch_count <- function(expr) {
  if (is.null(expr) || is.atomic(expr) || is.name(expr)) {
    return(0L)
  }
  values <- as.list(expr)
  own <- 0L
  if (is.call(expr)) {
    head <- as.character(expr[[1L]])
    if (head %in% c("if", "for", "while", "repeat", "&&", "||", "switch")) {
      own <- 1L
    }
  }
  own + sum(vapply(values, branch_count, integer(1L)))
}

function_complexity <- function(fun) {
  if (requireNamespace("cyclocomp", quietly = TRUE)) {
    value <- tryCatch(
      cyclocomp::cyclocomp(fun),
      error = function(error) NA_real_
    )
    if (length(value) == 1L && is.finite(value)) {
      return(list(value = as.integer(value), source = "cyclocomp"))
    }
  }
  list(value = 1L + branch_count(body(fun)), source = "branch-count")
}

private_test_references <- function(
  package_root,
  function_names,
  public_names,
  source_files
) {
  tests_dir <- file.path(package_root, "tests")
  columns <- data.frame(
    symbol = character(),
    source_file = character(),
    test_file = character(),
    stringsAsFactors = FALSE
  )
  if (!dir.exists(tests_dir)) {
    return(columns)
  }
  test_files <- sort(list.files(
    tests_dir,
    pattern = "[.][Rr]$",
    recursive = TRUE,
    full.names = TRUE
  ))
  rows <- list()
  for (test_file in test_files) {
    expressions <- tryCatch(
      parse(file = test_file, keep.source = FALSE, encoding = "UTF-8"),
      error = function(error)
        abort(
          package_relative_path(test_file, package_root),
          ": ",
          conditionMessage(error)
        )
    )
    names_used <- intersect(
      unique(all.names(expressions, functions = TRUE)),
      function_names
    )
    names_used <- setdiff(names_used, public_names)
    for (name in sort(names_used)) {
      rows[[length(rows) + 1L]] <- data.frame(
        symbol = name,
        source_file = source_files[[name]],
        test_file = package_relative_path(
          normalizePath(test_file, winslash = "/"),
          package_root
        ),
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(rows) == 0L) columns else unique(do.call(rbind, rows))
}

file_coupling <- function(edges, source_files) {
  if (nrow(edges) == 0L) {
    return(data.frame(
      source_file = character(),
      target_file = character(),
      edge_count = integer(),
      source_functions = integer(),
      target_functions = integer(),
      stringsAsFactors = FALSE
    ))
  }
  mapped <- transform(
    edges,
    source_file = unname(source_files[caller]),
    target_file = unname(source_files[callee])
  )
  mapped <- mapped[mapped$source_file != mapped$target_file, , drop = FALSE]
  if (nrow(mapped) == 0L) {
    return(data.frame(
      source_file = character(),
      target_file = character(),
      edge_count = integer(),
      source_functions = integer(),
      target_functions = integer(),
      stringsAsFactors = FALSE
    ))
  }
  groups <- split(
    mapped,
    interaction(mapped$source_file, mapped$target_file, drop = TRUE)
  )
  rows <- lapply(groups, function(group) {
    data.frame(
      source_file = group$source_file[[1L]],
      target_file = group$target_file[[1L]],
      edge_count = nrow(group),
      source_functions = length(unique(group$caller)),
      target_functions = length(unique(group$callee)),
      stringsAsFactors = FALSE
    )
  })
  result <- do.call(rbind, rows)
  result[order(result$source_file, result$target_file), , drop = FALSE]
}

markdown_escape <- function(value) {
  gsub("[|]", "\\\\|", as.character(value))
}

markdown_table <- function(data, columns = names(data)) {
  if (nrow(data) == 0L) {
    return("_None._")
  }
  data <- data[, columns, drop = FALSE]
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
  unreachable <- functions[!functions$reachable, , drop = FALSE]
  unreachable <- unreachable[
    order(-unreachable$lines, unreachable$name, na.last = TRUE),
    ,
    drop = FALSE
  ]
  hotspots <- functions[
    order(
      -functions$complexity,
      -functions$lines,
      functions$name,
      na.last = TRUE
    ),
    ,
    drop = FALSE
  ]
  multi_scc <- result$sccs[result$sccs$size > 1L, , drop = FALSE]
  public <- functions[
    functions$public_root,
    c("name", "file", "reachable"),
    drop = FALSE
  ]

  lines <- c(
    "# R Architecture Map",
    "",
    "## Summary",
    "",
    paste0("- Top-level assignments: ", result$definition_count),
    paste0("- Active functions: ", nrow(functions)),
    paste0("- Public function roots: ", nrow(public)),
    paste0("- Reachable functions: ", sum(functions$reachable)),
    paste0("- Unreachable function candidates: ", nrow(unreachable)),
    paste0(
      "- Cross-file coupling edges: ",
      sum(result$file_coupling$edge_count)
    ),
    paste0("- Multi-function strongly connected components: ", nrow(multi_scc)),
    paste0(
      "- Direct private-test references: ",
      nrow(result$private_test_coupling)
    ),
    paste0("- Reference analysis: ", result$reference_method),
    "",
    "## Public Roots",
    "",
    markdown_table(public),
    "",
    "## Largest Unreachable Candidates",
    "",
    markdown_table(
      head(unreachable, top),
      c("name", "file", "line", "lines", "test_file_count")
    ),
    "",
    "## Complexity Hotspots",
    "",
    markdown_table(
      head(hotspots, top),
      c(
        "name",
        "file",
        "line",
        "lines",
        "complexity",
        "complexity_source",
        "reachable"
      )
    ),
    "",
    "## Multi-function Components",
    "",
    markdown_table(multi_scc),
    "",
    "## Interpretation Boundary",
    "",
    "This is a conservative static map, not proof of liveness, dead code, or poor design.",
    "Confirm candidates against dynamic dispatch, generated registration, load hooks,",
    "repository-wide references, supported external consumers, and value-level behavior.",
    "Use complexity, cycles, and private tests to choose reading order rather than as",
    "automatic refactoring gates."
  )
  paste(lines, collapse = "\n")
}

analyze_package <- function(package) {
  package_root <- normalizePath(package, winslash = "/", mustWork = TRUE)
  inventory <- inventory_definitions(package_root)
  active_functions <- Filter(function(item) item$is_function, inventory$active)
  names(active_functions) <- vapply(
    active_functions,
    `[[`,
    character(1L),
    "name"
  )
  active_functions <- active_functions[order(names(active_functions))]
  function_names <- names(active_functions)
  if (length(function_names) == 0L) {
    abort("no conventional top-level function definitions found beneath R/")
  }

  namespace <- namespace_roots(package_root, function_names)
  edge_result <- internal_edges(active_functions)
  edges <- edge_result$edges
  reached <- reachable_vertices(function_names, edges, namespace$roots)
  components <- strong_components(function_names, edges)
  component_ids <- setNames(character(length(function_names)), function_names)
  component_sizes <- setNames(integer(length(function_names)), function_names)
  scc_rows <- list()
  source_files <- setNames(
    vapply(active_functions, `[[`, character(1L), "file"),
    function_names
  )
  for (i in seq_along(components)) {
    members <- components[[i]]
    id <- sprintf("SCC%03d", i)
    component_ids[members] <- id
    component_sizes[members] <- length(members)
    scc_rows[[i]] <- data.frame(
      scc_id = id,
      size = length(members),
      files = paste(
        sort(unique(unname(source_files[members]))),
        collapse = ","
      ),
      members = paste(members, collapse = ","),
      stringsAsFactors = FALSE
    )
  }
  sccs <- do.call(rbind, scc_rows)

  test_coupling <- private_test_references(
    package_root,
    function_names,
    namespace$public,
    source_files
  )
  test_counts <- table(test_coupling$symbol)
  definition_names <- vapply(inventory$definitions, `[[`, character(1L), "name")
  definition_counts <- table(definition_names)
  inbound <- table(edges$callee)
  outbound <- table(edges$caller)

  function_rows <- lapply(function_names, function(name) {
    item <- active_functions[[name]]
    complexity <- function_complexity(item$fun)
    data.frame(
      name = name,
      file = item$file,
      line = item$line,
      end_line = item$end_line,
      lines = item$lines,
      public_root = name %in% namespace$public,
      graph_root = name %in% namespace$roots,
      reachable = name %in% reached,
      complexity = complexity$value,
      complexity_source = complexity$source,
      inbound_internal = if (name %in% names(inbound))
        unname(inbound[[name]]) else 0L,
      outbound_internal = if (name %in% names(outbound))
        unname(outbound[[name]]) else 0L,
      scc_id = unname(component_ids[[name]]),
      scc_size = unname(component_sizes[[name]]),
      test_file_count = if (name %in% names(test_counts))
        unname(test_counts[[name]]) else 0L,
      definition_count = unname(definition_counts[[name]]),
      stringsAsFactors = FALSE
    )
  })
  functions <- do.call(rbind, function_rows)
  functions <- functions[
    order(functions$file, functions$line, functions$name),
    ,
    drop = FALSE
  ]

  edge_files <- if (nrow(edges) == 0L) {
    data.frame(
      caller = character(),
      callee = character(),
      reference_kind = character(),
      caller_file = character(),
      callee_file = character(),
      stringsAsFactors = FALSE
    )
  } else {
    transform(
      edges,
      caller_file = unname(source_files[caller]),
      callee_file = unname(source_files[callee])
    )[, c("caller", "callee", "reference_kind", "caller_file", "callee_file")]
  }
  diagnostics <- rbind(inventory$diagnostics, namespace$diagnostics)
  diagnostics <- diagnostics[
    order(diagnostics$kind, diagnostics$file, diagnostics$line, na.last = TRUE),
    ,
    drop = FALSE
  ]

  list(
    package_root = package_root,
    definition_count = length(inventory$definitions),
    metadata = map_metadata(edge_result$method),
    functions = functions,
    edges = edge_files,
    file_coupling = file_coupling(edges, source_files),
    sccs = sccs,
    private_test_coupling = test_coupling,
    diagnostics = diagnostics,
    reference_method = edge_result$method
  )
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
  stage <- tempfile(pattern = ".r-architecture-map.", tmpdir = parent)
  if (!dir.create(stage)) {
    abort("could not create temporary report directory beneath: ", parent)
  }
  completed <- FALSE
  on.exit(
    if (!completed && dir.exists(stage))
      unlink(stage, recursive = TRUE, force = TRUE),
    add = TRUE
  )

  summary <- build_summary(result, top)
  write_atomic(
    file.path(stage, "summary.md"),
    function(path) writeLines(summary, path, useBytes = TRUE)
  )
  write_tsv(result$metadata, file.path(stage, "metadata.tsv"))
  write_tsv(result$functions, file.path(stage, "functions.tsv"))
  write_tsv(result$edges, file.path(stage, "edges.tsv"))
  write_tsv(result$file_coupling, file.path(stage, "file-coupling.tsv"))
  write_tsv(result$sccs, file.path(stage, "sccs.tsv"))
  write_tsv(
    result$private_test_coupling,
    file.path(stage, "private-test-coupling.tsv")
  )
  write_tsv(result$diagnostics, file.path(stage, "diagnostics.tsv"))
  if (!file.rename(stage, destination)) {
    abort("could not move completed report into place: ", destination)
  }
  completed <- TRUE
  normalizePath(destination, winslash = "/", mustWork = TRUE)
}

run_self_test <- function() {
  root <- tempfile("r-architecture-map-test.")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  dir.create(file.path(root, "R"))
  dir.create(file.path(root, "tests", "testthat"), recursive = TRUE)
  writeLines(
    c("Package: architecturefixture", "Version: 0.0.1"),
    file.path(root, "DESCRIPTION")
  )
  writeLines("export(entry)", file.path(root, "NAMESPACE"))
  writeLines(
    c(
      "entry <- function(x) dispatch(worker, x)",
      "dispatch <- function(fun, x) fun(x)",
      "worker <- function(x) if (x > 0) x else -x",
      "dead_a <- function(x = 1) dead_b(x)",
      "dead_b <- function(x = 1) dead_a(x)"
    ),
    file.path(root, "R", "core.R")
  )
  writeLines(
    "testthat::test_that('private branch', testthat::expect_equal(dead_a(), 1))",
    file.path(root, "tests", "testthat", "test-private.R")
  )

  result <- analyze_package(root)
  by_name <- setNames(seq_len(nrow(result$functions)), result$functions$name)
  stopifnot(result$functions$public_root[[by_name[["entry"]]]])
  stopifnot(result$functions$reachable[[by_name[["dispatch"]]]])
  stopifnot(result$functions$reachable[[by_name[["worker"]]]])
  stopifnot(!result$functions$reachable[[by_name[["dead_a"]]]])
  stopifnot(result$functions$scc_size[[by_name[["dead_a"]]]] == 2L)
  stopifnot(any(
    result$edges$caller == "entry" &
      result$edges$callee == "worker" &
      result$edges$reference_kind == "value"
  ))
  stopifnot(any(result$private_test_coupling$symbol == "dead_a"))

  out <- file.path(root, "report")
  write_report(result, out, 10L)
  stopifnot(all(file.exists(file.path(
    out,
    c("summary.md", "metadata.tsv", "functions.tsv", "sccs.tsv")
  ))))
  metadata <- read.delim(
    file.path(out, "metadata.tsv"),
    stringsAsFactors = FALSE
  )
  stopifnot(nrow(metadata) == 1L)
  stopifnot(metadata$producer[[1L]] == "r-architecture-map.R")
  stopifnot(metadata$reference_method[[1L]] == result$reference_method)
  invisible(TRUE)
}

main <- function(args) {
  opts <- parse_args(args)
  if (opts$self_test) {
    run_self_test()
    cat("R architecture map self-test passed.\n")
    return(invisible(NULL))
  }
  result <- analyze_package(opts$package)
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
    message("r-architecture-map.R: ", conditionMessage(error))
    quit(status = 1L)
  }
)
