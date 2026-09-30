# Timur RV32IMC - checks for the software layer (C runtime, assembly, Python tools).
#
#   make venv       create .venv with the development tools (requirements-dev.txt)
#   make check      everything that needs no simulator: lint, types, host tests
#   make lint       ruff, clang-format and shellcheck (no files are changed)
#   make format     apply ruff format and clang-format
#   make typecheck  mypy --strict on the Python tools
#   make test       host tests (pytest): unit tests and the golden-file comparison
#   make coverage   host tests with a coverage report
#   make analyze    static analysis of the C runtime: gcc -fanalyzer, plus cppcheck
#                   and clang-tidy when they are installed
#   make regen      regenerate vectors/, rom*.hex/.mif and sw/bringup/
#   make sim        RTL regression with Icarus Verilog (./run_tests.sh)
#   make all        check, analyze and sim
#
# The tools come from .venv when it exists, otherwise from PATH. The RISC-V
# toolchain is found by sw/timur_tools/toolchain.py (TIMUR_TOOLCHAIN_PREFIX,
# PATH, or .tools/xpack-riscv-none-elf-gcc-*).

VENV    := .venv
BIN     := $(if $(wildcard $(VENV)/bin/python),$(VENV)/bin/,)
PYTHON  := $(if $(BIN),$(BIN)python,python3)

C_FORMATTED := $(wildcard sw/runtime/*.c sw/runtime/include/*.h)
SHELL_FILES := run_tests.sh sw/program_board.sh
GENERATORS  := gen_unit_vectors gen_decompressor_vectors gen_soc_tests gen_sw_tests

.PHONY: all check lint format typecheck test coverage analyze regen sim venv

all: check analyze sim

check: lint typecheck test

venv:
	python3 -m venv $(VENV)
	$(VENV)/bin/pip install -r requirements-dev.txt

lint:
	$(BIN)ruff check sw tests/host
	$(BIN)ruff format --check sw tests/host
	$(BIN)clang-format --dry-run -Werror $(C_FORMATTED)
	@if command -v $(BIN)shellcheck > /dev/null 2>&1; then \
	    $(BIN)shellcheck $(SHELL_FILES); \
	elif command -v shellcheck > /dev/null 2>&1; then \
	    shellcheck $(SHELL_FILES); \
	else echo "shellcheck not installed: skipped"; fi

format:
	$(BIN)ruff check --fix sw tests/host
	$(BIN)ruff format sw tests/host
	$(BIN)clang-format -i $(C_FORMATTED)

typecheck:
	$(BIN)mypy

test:
	$(BIN)pytest

coverage:
	$(BIN)pytest --cov --cov-report=term-missing

analyze:
	$(PYTHON) sw/analyze.py

regen:
	@for generator in $(GENERATORS); do \
	    echo "== $$generator"; \
	    $(PYTHON) sw/$$generator.py || exit 1; \
	done

sim:
	./run_tests.sh
