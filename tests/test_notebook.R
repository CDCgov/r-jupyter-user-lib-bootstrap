# Offline checks only: never source/evaluate the installer cell as a whole.
args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
installer <- parse(file = args[[1]])
persistence <- parse(file = args[[2]])

# The installer writes three literal R scripts. Parse their actual text too;
# parsing the outer notebook alone would miss quoting errors in these scripts.
worker_count <- 0L
for (node in installer) {
  if (!is.call(node) || !identical(node[[1]], as.name("writeLines")) ||
      length(node) < 3L || !is.call(node[[2]]) ||
      !identical(node[[2]][[1]], as.name("c"))) next
  pieces <- as.list(node[[2]])[-1L]
  if (!length(pieces) || !all(vapply(
    pieces, function(piece) is.character(piece) && length(piece) == 1L,
    logical(1)
  ))) next
  parse(text = unlist(pieces, use.names = FALSE))
  worker_count <- worker_count + 1L
}
stopifnot(worker_count == 3L)

helpers <- new.env(parent = globalenv())
wanted <- c(
  "%||%", "as_flag", "opt_get", "version_at_least", "clean_names",
  "split_path_list", "find_cmake_candidates",
  "split_dependency_spec", "parse_dependency_field", "constraints_for",
  "satisfies_version_predicate", "version_satisfies_constraints",
  "topo_sort", "env_assignment"
)
loaded <- character()
for (node in installer) {
  if (!is.call(node) || !identical(node[[1]], as.name("<-")) ||
      !is.symbol(node[[2]]) || !is.call(node[[3]]) ||
      !identical(node[[3]][[1]], as.name("function"))) next
  name <- as.character(node[[2]])
  if (name %in% wanted) {
    eval(node, envir = helpers)
    loaded <- c(loaded, name)
  }
}
stopifnot(setequal(wanted, loaded))

probe <- helpers$split_dependency_spec("Rcpp (>= 1.1.1-1.1)")
stopifnot(
  identical(probe$name, "Rcpp"), identical(probe$op, ">="),
  identical(probe$version, "1.1.1-1.1"),
  !helpers$satisfies_version_predicate("1.1.1", ">=", "1.1.1-1.1"),
  helpers$satisfies_version_predicate("1.1.2", ">=", "1.1.1-1.1"),
  helpers$satisfies_version_predicate("2.0", "<", "3.0"),
  !helpers$satisfies_version_predicate("2.0", "<", "2.0"),
  !helpers$satisfies_version_predicate(NA_character_, ">=", "1.0")
)
helpers$version_requirements <- helpers$parse_dependency_field(
  "target", "Imports", "dep (>= 2.0), other, R (>= 4.0)"
)
stopifnot(
  nrow(helpers$version_requirements) == 2L,
  !"R" %in% helpers$version_requirements$dependency,
  !helpers$version_satisfies_constraints("dep", "1.9"),
  helpers$version_satisfies_constraints("dep", "2.0")
)
order <- helpers$topo_sort(c("target", "dep", "leaf"), list(
  target = "dep", dep = "leaf", leaf = character()
))
stopifnot(identical(order$order, c("leaf", "dep", "target")),
          length(order$cycle_members) == 0L)
cycle <- helpers$topo_sort(c("a", "b"), list(a = "b", b = "a"))
stopifnot(setequal(cycle$cycle_members, c("a", "b")))

# Round-trip shell-sensitive values through the same system2 env mechanism
# used for install workers, but run only a child R process that prints a value.
shell_value <- "space 'single' \"double\" $literal `literal` ; literal"
child <- system2(
  file.path(R.home("bin"), "Rscript"),
  c("--vanilla", "-e", shQuote('cat(Sys.getenv("BOOTSTRAP_TEST_VALUE"))')),
  env = helpers$env_assignment("BOOTSTRAP_TEST_VALUE", shell_value),
  stdout = TRUE, stderr = TRUE
)
stopifnot(is.null(attr(child, "status")),
          identical(paste(child, collapse = "\n"), shell_value))
newline_error <- try(helpers$env_assignment("BOOTSTRAP_TEST_VALUE", "a\nb"), silent = TRUE)
stopifnot(inherits(newline_error, "try-error"))

# Use disposable no-op executables to test real candidate discovery and the
# actual selection/PATH blocks without calling bootstrap or any installer.
cmake_sandbox <- tempfile("r-bootstrap-cmake-")
dir.create(cmake_sandbox)
local({
  on.exit(unlink(cmake_sandbox, recursive = TRUE), add = TRUE)
  explicit <- file.path(cmake_sandbox, "explicit", "bin", "cmake")
  native <- file.path(cmake_sandbox, "native", "bin", "cmake")
  discovered <- file.path(cmake_sandbox, "tools", "cmake-old", "bin", "cmake")
  for (path in c(explicit, native, discovered)) {
    dir.create(dirname(path), recursive = TRUE)
    writeLines(c("#!/bin/sh", "exit 0"), path)
    Sys.chmod(path, "0755")
  }
  context <- new.env(parent = helpers)
  context$cmake_tools_dir <- file.path(cmake_sandbox, "tools")
  context$Sys.getenv <- function(x, unset = "", ...) {
    switch(x, CMAKE_BIN = explicit, CMAKE = "", PATH = dirname(native), unset)
  }
  context$Sys.which <- function(x) {
    if (identical(x, "cmake")) native else ""
  }
  context$find_cmake_candidates <- helpers$find_cmake_candidates
  environment(context$find_cmake_candidates) <- context
  context$cmake_candidates <- context$find_cmake_candidates()
  stopifnot(identical(context$cmake_candidates,
                      normalizePath(c(explicit, native, discovered))))
  context$build_env <- character()
  context$path_prepend <- dirname(native)
  selection_count <- 0L
  for (node in installer) {
    if (!is.call(node) || !identical(node[[1]], as.name("if"))) next
    if (identical(node[[2]], quote(length(cmake_candidates))) ||
        identical(node[[2]], quote(length(path_prepend)))) {
      eval(node, envir = context)
      selection_count <- selection_count + 1L
    }
  }
  stopifnot(
    selection_count == 2L,
    identical(unname(context$build_env[["CMAKE_BIN"]]), normalizePath(explicit)),
    identical(unname(context$build_env[["CMAKE"]]), normalizePath(explicit)),
    identical(helpers$split_path_list(context$build_env[["PATH"]]),
              c(dirname(normalizePath(explicit)), dirname(normalizePath(native))))
  )
})

# Persistence integration tests below execute only the optional persistence
# cell, with all home/project paths redirected into a disposable directory.
sandbox <- tempfile("r-bootstrap-persistence-")
dir.create(sandbox)
local({
  old_wd <- getwd()
  on.exit({ setwd(old_wd); unlink(sandbox, recursive = TRUE) }, add = TRUE)
  setwd(sandbox)
  test_home <- file.path(sandbox, "home")
  dir.create(test_home)
  renviron <- file.path(test_home, ".Renviron")
  custom_lib <- file.path(test_home, "custom library")
  dir.create(custom_lib)
  secret <- "PRIVATE_TEST_VALUE_MUST_NOT_BE_PRINTED"
  original <- c(paste0("EXAMPLE_SECRET=", secret), "# preserve this comment",
                'R_LIBS_USER="old/path"')
  writeLines(original, renviron)

  new_context <- function() {
    context <- new.env(parent = globalenv())
    context$installer_completed <- TRUE
    context$deploy_lib <- custom_lib
    context$default_deploy_lib <- file.path(test_home, "R/library/default")
    context$targets <- "stats"
    context$target_validation <- data.frame(pkg = "stats", load_ok = TRUE)
    context$path.expand <- function(path) {
      if (identical(path, "~/.Renviron")) return(renviron)
      base::path.expand(path)
    }
    context$Sys.getenv <- function(x = NULL, unset = "", names = NA) {
      if (identical(x, "R_ENVIRON_USER")) return("")
      base::Sys.getenv(x, unset = unset, names = names)
    }
    context
  }

  output <- capture.output(eval(persistence, envir = new_context()))
  saved <- readLines(renviron)
  stopifnot(
    all(original[1:2] %in% saved),
    sum(grepl("^R_LIBS_USER=", saved)) == 1L,
    any(grepl(normalizePath(custom_lib), saved, fixed = TRUE)),
    !any(grepl(secret, output, fixed = TRUE))
  )
  backup <- list.files(test_home, pattern = "^\\.Renviron\\.bak-", all.files = TRUE,
                       full.names = TRUE)
  stopifnot(length(backup) >= 1L,
            identical(readLines(backup[[1]]), original))

  output <- capture.output(eval(persistence, envir = new_context()))
  stopifnot(identical(readLines(renviron), saved),
            !any(grepl(secret, output, fixed = TRUE)))

  failed_context <- new_context()
  failed_context$file.copy <- function(...) FALSE
  failed <- try(eval(persistence, envir = failed_context), silent = TRUE)
  stopifnot(inherits(failed, "try-error"), identical(readLines(renviron), saved))

  failed_context <- new_context()
  failed_context$file.rename <- function(...) FALSE
  failed <- try(eval(persistence, envir = failed_context), silent = TRUE)
  stopifnot(inherits(failed, "try-error"), identical(readLines(renviron), saved))

  failed_context <- new_context()
  failed_context$installer_completed <- FALSE
  failed <- try(eval(persistence, envir = failed_context), silent = TRUE)
  stopifnot(inherits(failed, "try-error"), identical(readLines(renviron), saved))

  failed_context <- new_context()
  failed_context$Sys.getenv <- function(...) "/another/startup/file"
  failed <- try(eval(persistence, envir = failed_context), silent = TRUE)
  stopifnot(inherits(failed, "try-error"), identical(readLines(renviron), saved))

  project_renviron <- file.path(sandbox, ".Renviron")
  writeLines("# project startup takes precedence", project_renviron)
  failed <- try(eval(persistence, envir = new_context()), silent = TRUE)
  stopifnot(inherits(failed, "try-error"), identical(readLines(renviron), saved))
  unlink(project_renviron)

  # The default path keeps R's version/platform expansion rather than freezing
  # the current R version in the home startup file.
  default_context <- new_context()
  default_context$default_deploy_lib <- custom_lib
  output <- capture.output(eval(persistence, envir = default_context))
  default_saved <- readLines(renviron)
  stopifnot(
    'R_LIBS_USER="${HOME}/R/library/%v/%p"' %in% default_saved,
    all(original[1:2] %in% default_saved),
    sum(grepl("^R_LIBS_USER=", default_saved)) == 1L,
    !any(grepl(secret, output, fixed = TRUE))
  )
})

cat("R parsing, generated-worker parsing, helper and persistence checks passed.\n")
