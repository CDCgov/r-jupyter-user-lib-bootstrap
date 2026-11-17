# Thanks and Acknowledgements

We thank the following individuals for technical support in the development and validation of the Jupyter bootstrap:

- Chenchen Feng
- Li Wang
- Jeremy Duke

This study was funded by the US Centers for Disease Control and Prevention (CDC). The findings and conclusions are those of the authors and do not necessarily represent the official position of the US CDC.

# Third Party Software

The notebook uses [R](https://www.r-project.org/), base/recommended R facilities, and packages obtained from [CRAN](https://cran.r-project.org/) or a user-selected CRAN-compatible repository. Default requested packages are `tidyverse`, `drc`, `ggplot2`, `dplyr`, `scales`, `mgcv`, and `bit64`; recursive dependencies vary with repository metadata and optional Suggests. Each package and its native dependencies retain their own authorship, license, and notices.

Optional automatic CMake bootstrap downloads official [Kitware CMake](https://github.com/Kitware/CMake) release assets. R packages, CMake binaries, and native libraries are not bundled with this repository.

Development automation uses [actions/checkout](https://github.com/actions/checkout) and [github/codeql-action](https://github.com/github/codeql-action), maintained and licensed by their respective projects. The Python validation helper uses only the standard library; the R tests use base R facilities.
