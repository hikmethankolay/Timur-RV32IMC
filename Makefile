# Timur RV32IMC - checks for the software layer (C runtime, assembly, Python tools).
#
#   make venv       (re)create .venv with the development tools (requirements-dev.txt)
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

.PHONY: all check lint format typecheck test coverage analyze regen sim venv venv-check

all: check analyze sim

check: lint typecheck test

# --clear: a .venv made by another Python is rebuilt, not patched.
venv:
	python3 -m venv --clear $(VENV)
	$(VENV)/bin/pip install -r requirements-dev.txt

# A .venv made by another Python (another machine or container, or before a
# system upgrade) still has its compiled tools (ruff), but the Python-based ones
# cannot find their modules: stop with the fix instead of a traceback.
venv-check:
ifneq ($(BIN),)
	@$(PYTHON) -c "import clang_format, mypy, pytest" 2> /dev/null || { \
	    echo "$(VENV) cannot run its Python tools (it was made for Python" \
	         "$$(sed -n 's/^version = //p' $(VENV)/pyvenv.cfg); python3 here is" \
	         "$$(python3 -c 'import platform; print(platform.python_version())'))."; \
	    echo "Rebuild it:  rm -rf $(VENV) && make venv"; \
	    exit 1; }
endif

lint: venv-check
	$(BIN)ruff check sw tests/host
	$(BIN)ruff format --check sw tests/host
	$(BIN)clang-format --dry-run -Werror $(C_FORMATTED)
	@if command -v $(BIN)shellcheck > /dev/null 2>&1; then \
	    $(BIN)shellcheck $(SHELL_FILES); \
	elif command -v shellcheck > /dev/null 2>&1; then \
	    shellcheck $(SHELL_FILES); \
	else echo "shellcheck not installed: skipped"; fi

format: venv-check
	$(BIN)ruff check --fix sw tests/host
	$(BIN)ruff format sw tests/host
	$(BIN)clang-format -i $(C_FORMATTED)

typecheck: venv-check
	$(BIN)mypy

test: venv-check
	$(BIN)pytest

coverage: venv-check
	$(BIN)pytest --cov --cov-report=term-missing

analyze: venv-check
	$(PYTHON) sw/analyze.py

regen:
	@for generator in $(GENERATORS); do \
	    echo "== $$generator"; \
	    $(PYTHON) sw/$$generator.py || exit 1; \
	done

sim:
	./run_tests.sh
