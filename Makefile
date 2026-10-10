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
#   make regen      regenerate the VGA font, vectors/, rom*.hex/.mif and sw/bringup/
#   make sim        RTL regression with Icarus Verilog (./run_tests.sh)
#   make diagrams   render docs/diagrams/src (D2, WaveDrom) to docs/diagrams/*.svg
#   make diagram-tools  install the pinned d2 and wavedrom-cli into .tools/
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
GENERATORS  := gen_font gen_unit_vectors gen_decompressor_vectors gen_soc_tests gen_sw_tests

.PHONY: all check lint format typecheck test coverage analyze regen sim venv venv-check \
        diagrams diagram-tools

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

# ---- diagrams ----------------------------------------------------------------
# Sources in docs/diagrams/src: *.d2 (block and flow diagrams; _style.d2 holds
# the shared layout engine, theme and classes) and *.json (WaveDrom timing
# diagrams). The SVGs are committed; whiten.py gives each a white background
# for GitHub's dark theme. The tools come from .tools/ (make diagram-tools,
# Linux x86-64) or PATH; the pinned versions keep re-renders identical.
D2_VERSION       := v0.9.0
D2_SHA256        := 5669ddc46b99e942cc96078f4a4e36d5e62103348f4c05179ede27802fdd87a9
WAVEDROM_VERSION := 3.2.0
D2       ?= $(firstword $(wildcard .tools/bin/d2) d2)
WAVEDROM ?= $(firstword $(wildcard .tools/wavedrom/node_modules/.bin/wavedrom-cli) wavedrom-cli)

DIAGRAM_SRC := docs/diagrams/src
D2_SOURCES  := $(filter-out $(DIAGRAM_SRC)/_%,$(wildcard $(DIAGRAM_SRC)/*.d2))
DIAGRAMS    := $(patsubst $(DIAGRAM_SRC)/%.d2,docs/diagrams/%.svg,$(D2_SOURCES)) \
               $(patsubst $(DIAGRAM_SRC)/%.json,docs/diagrams/%.svg,$(wildcard $(DIAGRAM_SRC)/*.json))

diagrams: $(DIAGRAMS)

docs/diagrams/%.svg: $(DIAGRAM_SRC)/%.d2 $(DIAGRAM_SRC)/_style.d2 $(DIAGRAM_SRC)/whiten.py
	$(D2) $< $@
	$(PYTHON) $(DIAGRAM_SRC)/whiten.py $@

docs/diagrams/%.svg: $(DIAGRAM_SRC)/%.json $(DIAGRAM_SRC)/whiten.py
	$(WAVEDROM) -i $< -s $@
	$(PYTHON) $(DIAGRAM_SRC)/whiten.py $@

diagram-tools:
	mkdir -p .tools/bin
	curl -sSL -o .tools/d2.tar.gz \
	    https://github.com/d2lang/d2/releases/download/$(D2_VERSION)/d2-$(D2_VERSION)-linux-amd64.tar.gz
	echo "$(D2_SHA256)  .tools/d2.tar.gz" | sha256sum -c -
	tar -xzf .tools/d2.tar.gz -C .tools d2-$(D2_VERSION)/bin/d2
	mv .tools/d2-$(D2_VERSION)/bin/d2 .tools/bin/d2
	rm -rf .tools/d2.tar.gz .tools/d2-$(D2_VERSION)
	npm install --prefix .tools/wavedrom --no-audit --no-fund wavedrom-cli@$(WAVEDROM_VERSION)
