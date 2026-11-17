#!/usr/bin/env python3
"""Check the distributable notebook without executing its installer."""

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
NOTEBOOK = ROOT / "r-jupyter-user-lib-bootstrap.ipynb"


def check_notebook(path):
    notebook = json.loads(path.read_text(encoding="utf-8"))
    if notebook.get("nbformat") != 4:
        raise ValueError("Expected a Jupyter notebook in format 4")
    if not isinstance(notebook.get("nbformat_minor"), int):
        raise ValueError("Missing notebook minor version")
    metadata = notebook.get("metadata", {})
    kernel = metadata.get("kernelspec", {})
    language = metadata.get("language_info", {})
    if kernel.get("name") != "ir" or kernel.get("language", "").lower() != "r":
        raise ValueError("Expected the IRkernel R kernel")
    if language.get("name", "").lower() != "r":
        raise ValueError("Expected R language metadata")
    if set(metadata) - {"kernelspec", "language_info"}:
        raise ValueError("Remove execution-specific notebook metadata before sharing")
    cells = notebook.get("cells")
    if not isinstance(cells, list) or not cells:
        raise ValueError("Notebook has no cells")
    code = []
    for number, cell in enumerate(cells, start=1):
        kind = cell.get("cell_type")
        if kind not in {"code", "markdown"}:
            raise ValueError(f"Cell {number}: unsupported cell type")
        source = cell.get("source")
        if isinstance(source, list) and all(isinstance(line, str) for line in source):
            source = "".join(source)
        if not isinstance(source, str):
            raise ValueError(f"Cell {number}: invalid source")
        if not isinstance(cell.get("metadata"), dict):
            raise ValueError(f"Cell {number}: invalid metadata")
        if set(cell["metadata"]) - {"tags"}:
            raise ValueError(f"Cell {number}: remove execution-specific metadata")
        if kind == "code":
            if cell.get("outputs") != [] or cell.get("execution_count", "missing") is not None:
                raise ValueError(f"Cell {number}: clear outputs and execution count")
            code.append(source)
    if len(code) != 2:
        raise ValueError("Expected the installer and optional persistence code cells")
    return code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--r-check", action="store_true",
        help="also parse R code and run isolated offline regression checks; requires Rscript",
    )
    args = parser.parse_args()
    try:
        code = check_notebook(NOTEBOOK)
        print("Notebook structure and clean-output checks passed.", flush=True)
        if args.r_check:
            rscript = shutil.which("Rscript")
            if not rscript:
                raise ValueError("Rscript is required for --r-check; R checks did not run")
            with tempfile.TemporaryDirectory(prefix="r-bootstrap-check-") as temporary:
                extracted = []
                for number, source in enumerate(code, start=1):
                    path = Path(temporary) / f"cell-{number}.R"
                    path.write_text(source, encoding="utf-8")
                    extracted.append(str(path))
                subprocess.run(
                    [rscript, "--vanilla", str(ROOT / "tests" / "test_notebook.R"), *extracted],
                    check=True,
                )
        else:
            print("R checks were not requested; use --r-check where Rscript is available.")
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Check failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
