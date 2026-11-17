# R Jupyter user library bootstrap

> As a first step, this document is under governance review. When the review completes as appropriate per local and agency processes, the project team will be allowed to remove this notice. This material is draft.

## Overview

A standalone R notebook for installing CRAN packages and their dependencies into a writable user library on Linux Jupyter environments. IIt is intended for managed institutional environments where users cannot install system packages or write to R’s system library.
In general, the goal is to help users work with R in Jupyter under common permission restrictions, with minimal additional support.

The installer resolves recursive `Depends`, `Imports`, and `LinkingTo` dependencies, orders builds, checks version constraints, and installs packages in separate `Rscript --vanilla` processes. It reuses compatible installed packages by default and validates target namespaces in fresh R processes. Optional direct `Suggests` are disabled by default.

This project stays focused on that bootstrap task. It does not provision Jupyter, replace administrator-managed native libraries, or provide an environment lockfile.

## Project responsibility and status

**Code/programming contact:** Michael Currier, Influenza Division, National Center for Immunization and Respiratory Diseases, CDC — ovn5@cdc.gov


## Requirements

- Linux with R, a working `Rscript`, and a Jupyter R kernel (`IRkernel`) already installed. Other operating systems are rejected before installation starts.  We believe this makes up the majority of institutional cases where this bootstrap may be helpful. 
- A writable home directory and deployment library, sufficient disk space, and an appropriate C/C++/Fortran compiler/build toolchain for the selected source packages.
- Network access to the selected CRAN-compatible repository. The default is `https://cloud.r-project.org`. Some packages download additional build inputs.
- Native development headers and libraries required by the selected packages. The notebook discovers existing dependencies; it does not install OS packages. Ask the environment administrator to supply missing native requirements.
- If automatic CMake bootstrap is needed: access to official Kitware GitHub release assets, a supported Linux architecture (`x86_64` or `aarch64`), and `sha256sum` or `shasum` for archive verification.

Use only repositories and executable downloads approved for your environment. An existing CMake is preferred; automatic bootstrap is enabled by default and can be disabled. Source package installation executes third-party build code with the user's permissions.

## Use

1. Download [r-jupyter-user-lib-bootstrap.ipynb](r-jupyter-user-lib-bootstrap.ipynb) and open it with the existing **R** kernel.
2. Review the `user_options` list in the installer cell. The default targets are `tidyverse`, `drc`, `ggplot2`, `dplyr`, `scales`, `mgcv`, and `bit64`.
3. Run the installer cell in a fresh kernel. Avoid simultaneous installs into the same library; the worker removes a package-specific `00LOCK-<package>` directory before attempting that package. Do not interrupt another installation using that library.
4. Inspect the printed summary, `status.csv`, and `target-validation.csv`. Completion of the cell alone does not mean every package succeeded: failures are recorded in reports. All requested targets should have `load_ok = TRUE` before relying on them. Resolve missing system requirements with the administrator and rerun as needed.
5. Optionally run the final persistence cell after reviewing the chosen destination. It backs up an existing `~/.Renviron` and replaces only its `R_LIBS_USER` assignment. Restart the R kernel afterward. To undo persistence, restore the backup or remove the added assignment; keep unrelated settings intact.

The persistence cell refuses to change the home file when a project-local `.Renviron` or `R_ENVIRON_USER` selects another startup file. It also refuses custom paths containing startup-expansion characters rather than saving an ambiguous value. Configure those cases with your administrator. Confirm the active library after restarting:

```r
Sys.getenv("R_LIBS_USER")
.libPaths()
find.package("drc")
```

## Configuration

Set an inline option in `user_options`, or leave it `NULL` to use its environment variable, then the built-in default. Inline values take precedence.

| Inline option | Environment variable | Default / behavior |
| --- | --- | --- |
| `targets` | None | Seven target packages listed above |
| `install_policy` | `INSTALL_POLICY` | `missing-only`: reuse compatible packages, upgrade an incompatible hard dependency |
| `include_direct_suggests` | `INCLUDE_DIRECT_SUGGESTS` | `FALSE`; enabling it can substantially expand the install |
| `deploy_lib` | `R_DEPLOY_LIB` | `~/R/library/<R major.minor>/<platform>` |
| `cran_repo` | `CRAN_REPO` | `https://cloud.r-project.org` |
| `install_ncpus` | `INSTALL_NCPUS` | `2`; a build parallelism hint, not parallel package scheduling |
| `install_timeout_seconds` | `INSTALL_TIMEOUT_SECONDS` | `7200` per package worker |
| `auto_bootstrap_cmake` | `AUTO_BOOTSTRAP_CMAKE` | `TRUE` |
| `cmake_bootstrap_version` | `CMAKE_BOOTSTRAP_VERSION` | `4.4.2`, used only when no usable CMake is found |
| `native_prefixes` | `NATIVE_PREFIXES` | Additional path-separated prefixes; also searches Conda and conventional Linux prefixes |

Other existing environment controls are `CMAKE_TOOLS_DIR` (default `~/R/tools`), `CMAKE_BIN`, `CMAKE`, and `PKG_CONFIG_BIN`. Configure these before running the installer. An explicitly supplied CMake is considered before PATH and discovered user-local copies; a runnable executable is not a guarantee that its version satisfies every package.

`missing-or-outdated` also updates packages older than repository metadata. `all-to-deploy` ensures planned compatible repository versions are available in the deployment library; it reuses an adequate deployment copy. Base/recommended packages are reused from system libraries under all policies, so a too-old system package can still require an administrator-managed R update.

## Outputs and limitations

Runs create `~/R/deps-install-logs-<timestamp>/` with status and installation-plan CSVs, target load checks, dependency/version reports, native-library discovery, environment/tool diagnostics, source archives, and failure logs. CMake downloads and tools are retained under `~/R/tools` by default. Installed packages remain in the deployment library. The current session's library search path and R options are changed; only the optional final cell writes `~/.Renviron`.

Logs and notebook outputs can contain usernames, internal paths, repository URLs, and environment values. Review and redact them before sharing. Do not upload complete environment files, unreviewed logs, credentials, PII, or PHI. Keep committed notebook outputs cleared.

The package set follows the selected repository at run time; it is not pinned or guaranteed reproducible across dates. CMake archive SHA-256 validation checks the downloaded archive against the publisher's checksum file. Source archive hashes are recorded for diagnostics; that recording is not a security audit. Dependabot updates workflow actions and does not inventory these runtime CRAN/CMake downloads.

## Development and validation

Make focused changes through pull requests, review code and licenses, and update documentation when behavior changes. Maintainers review test evidence and obtain applicable governance/security review before merging or releasing; unresolved release gates remain visible. Follow [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), [open practices](open_practices.md), and [rules of behavior](rules_of_behavior.md).

```sh
python3 scripts/check_notebook.py
python3 scripts/check_notebook.py --r-check
```

The first command checks notebook structure and committed-output hygiene using Python's standard library. The second additionally requires R and runs offline syntax/helper/persistence regression tests without running the installer. CI uses the second command. These checks do not replace an approved static/dynamic security review or a controlled installation test on the intended managed Linux/Jupyter environment. CodeQL covers the Python support code and GitHub Actions workflows; it does not analyze R.

## Acknowledgements

See [thanks.md](thanks.md) for source and dependency attribution. 


## Public Domain Standard Notice

Works of the United States Government are not subject to domestic copyright protection under 17 USC § 105. Confirm which project portions qualify and record any third-party exceptions before release. The supplied export does not establish the authorship or employment status of the notebook author. No blanket CC0 waiver is asserted for unidentified contributors or dependencies.

## License Standard Notice

The source code is licensed under the Apache Software License, Version 2.0 or later. See [`LICENSE`](LICENSE).

The source code is distributed in the hope that it will be useful, but without warranty of any kind, including any implied warranty of merchantability or fitness for a particular purpose.

## Privacy Standard Notice

This repository contains only non-sensitive, publicly available data and information. Do not submit or store personally identifiable information, protected health information, sensitive laboratory information, or other non-public data. See the [Disclaimer](https://github.com/CDCgov/template/blob/main/DISCLAIMER.md) and [Code of Conduct](https://github.com/CDCgov/template/blob/main/code-of-conduct.md).

## Contributing Standard Notice

Anyone is encouraged to contribute by [forking](https://help.github.com/articles/fork-a-repo) and submitting a pull request. By contributing, you grant a world-wide, royalty-free, perpetual, irrevocable, non-exclusive, transferable license to all users under the terms of the [Apache Software License v2](http://www.apache.org/licenses/LICENSE-2.0.html) or later. All submissions received through CDC GitHub may be subject to applicable federal law, including the Federal Records Act, and may be archived. See [`CONTRIBUTING`](CONTRIBUTING.md).

## Records Management Standard Notice

This repository is not a source of government records, but is a copy intended to increase collaboration and collaborative potential. Government records are maintained through applicable CDC records-management processes.

## Additional Standard Notices

Please refer to [CDC's Template Repository](https://github.com/CDCgov/template) for more information about contributing, public domain notices and disclaimers, and the code of conduct.