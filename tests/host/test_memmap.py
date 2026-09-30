"""One set of hardware facts: timur_defs.h, linker.ld, memmap.py and the RTL agree."""

from __future__ import annotations

import ast
import operator
import re
from collections.abc import Callable

import pytest

from timur_tools import memmap

from conftest import REPO

DEFS = REPO / "sw" / "runtime" / "include" / "timur_defs.h"
LINKER = REPO / "sw" / "runtime" / "linker.ld"

_OPERATORS: dict[type, Callable[[int, int], int]] = {
    ast.Add: operator.add,
    ast.Sub: operator.sub,
    ast.LShift: operator.lshift,
}


def _evaluate(node: ast.expr) -> int:
    if isinstance(node, ast.Constant) and isinstance(node.value, int):
        return node.value
    if isinstance(node, ast.BinOp) and type(node.op) in _OPERATORS:
        return _OPERATORS[type(node.op)](_evaluate(node.left), _evaluate(node.right))
    raise ValueError("unsupported expression: %s" % ast.dump(node))


def c_defines() -> dict[str, int]:
    """Values of the object-like macros of timur_defs.h."""
    raw = dict(
        re.findall(
            r"^#define[ \t]+([A-Z_][A-Z0-9_]*)[ \t]+(.+?)[ \t]*(?:/\*.*)?$", DEFS.read_text(), re.M
        )
    )

    def value(name: str) -> int:
        expression = re.sub(r"TIMUR_U\(([^)]*)\)", r"\1", raw[name])
        expression = re.sub(
            r"\b([A-Z_][A-Z0-9_]+)\b", lambda match: str(value(match.group(1))), expression
        )
        return _evaluate(ast.parse(expression, mode="eval").body)

    return {name: value(name) for name in raw}


DEFINES = c_defines()

PAIRS = {
    "TIMUR_ROM_BASE": memmap.ROM_BASE,
    "TIMUR_ROM_SIZE": memmap.ROM_SIZE,
    "TIMUR_RAM_BASE": memmap.RAM_BASE,
    "TIMUR_RAM_SIZE": memmap.RAM_SIZE,
    "TIMUR_APB_BASE": memmap.APB_BASE,
    "TIMUR_UART_BASE": memmap.UART_BASE,
    "TIMUR_GPIO_BASE": memmap.GPIO_BASE,
    "TIMUR_DMAC_BASE": memmap.DMAC_BASE,
    "TIMUR_CLOCK_HZ": memmap.CLOCK_HZ,
    "UART_BAUD": memmap.UART_BAUD,
    "UART_DATA_OFFSET": memmap.UART_DATA,
    "UART_STATUS_OFFSET": memmap.UART_STATUS,
    "UART_CTRL_OFFSET": memmap.UART_CTRL,
    "UART_TX_BUSY": memmap.UART_STATUS_TX_BUSY,
    "UART_RX_VALID": memmap.UART_STATUS_RX_VALID,
    "UART_RX_ENABLE": memmap.UART_CTRL_RX_ENABLE,
    "UART_RX_IRQ": memmap.UART_CTRL_RX_IRQ,
    "GPIO_OUT_OFFSET": memmap.GPIO_OUT,
    "GPIO_IN_OFFSET": memmap.GPIO_IN,
    "GPIO_DIR_OFFSET": memmap.GPIO_DIR,
    "GPIO_WIDTH": memmap.GPIO_WIDTH,
    "GPIO_PIN_MASK": memmap.GPIO_MASK,
    "DMAC_SRC_OFFSET": memmap.DMAC_SRC,
    "DMAC_DST_OFFSET": memmap.DMAC_DST,
    "DMAC_LEN_OFFSET": memmap.DMAC_LEN,
    "DMAC_CTRL_OFFSET": memmap.DMAC_CTRL,
    "DMAC_STATUS_OFFSET": memmap.DMAC_STATUS,
    "DMAC_START": memmap.DMAC_CTRL_START,
    "DMAC_IRQ": memmap.DMAC_CTRL_IRQ,
    "DMAC_BUSY": memmap.DMAC_STATUS_BUSY,
    "DMAC_DONE": memmap.DMAC_STATUS_DONE,
    "MSTATUS_MIE": memmap.MSTATUS_MIE,
    "MSTATUS_MPIE": memmap.MSTATUS_MPIE,
    "MIE_MEIE": memmap.MIE_MEIE,
    "MIP_MEIP": memmap.MIP_MEIP,
    "MISA_VALUE": memmap.MISA_VALUE,
    "MCAUSE_EXTERNAL_IRQ": memmap.CAUSE_EXTERNAL_INTERRUPT,
    "CAUSE_ILLEGAL_INSTRUCTION": memmap.CAUSE_ILLEGAL_INSTRUCTION,
    "CAUSE_BREAKPOINT": memmap.CAUSE_BREAKPOINT,
    "CAUSE_LOAD_MISALIGNED": memmap.CAUSE_LOAD_MISALIGNED,
    "CAUSE_STORE_MISALIGNED": memmap.CAUSE_STORE_MISALIGNED,
    "CAUSE_ECALL": memmap.CAUSE_ECALL_M,
}


@pytest.mark.parametrize(("name", "expected"), sorted(PAIRS.items()))
def test_c_header_matches_python(name: str, expected: int) -> None:
    assert DEFINES[name] == expected


def test_linker_script_matches_the_memory_map() -> None:
    regions = {
        name: (int(origin, 16), int(length) * 1024)
        for name, origin, length in re.findall(
            r"^\s*(ROM|RAM)\s*\(\w+\)\s*:\s*ORIGIN\s*=\s*(0x[0-9A-Fa-f]+),\s*LENGTH\s*=\s*(\d+)K",
            LINKER.read_text(),
            re.M,
        )
    }

    assert regions == {
        "ROM": (memmap.ROM_BASE, memmap.ROM_SIZE),
        "RAM": (memmap.RAM_BASE, memmap.RAM_SIZE),
    }


def test_trap_frame_offsets_are_consecutive_words() -> None:
    order = ["RA", "T0", "T1", "T2", "A0", "A1", "A2", "A3", "A4", "A5", "A6", "A7"]
    order += ["T3", "T4", "T5", "T6"]

    assert [DEFINES["TRAP_FRAME_" + reg] for reg in order] == list(range(0, 64, 4))
    assert DEFINES["TRAP_FRAME_SIZE"] == 64


def test_rtl_address_decoder_and_uart_divider() -> None:
    decoder = (REPO / "rtl" / "bus" / "ahb_decoder.v").read_text()
    for select, base in (("ROM", memmap.ROM_BASE), ("RAM", memmap.RAM_BASE)):
        assert "HSEL_%s = (HADDR[31:16] == 16'h%04X)" % (select, base >> 16) in decoder
    assert "HSEL_APB = (HADDR[31:16] == 16'h%04X)" % (memmap.APB_BASE >> 16) in decoder

    soc = (REPO / "rtl" / "top" / "timur_soc.v").read_text()
    divider = int(re.search(r"parameter UART_DIVIDER = (\d+)", soc).group(1))  # type: ignore[union-attr]
    assert divider + 1 == memmap.UART_CYCLES_PER_BIT
    assert memmap.CLOCK_HZ // memmap.UART_BAUD == memmap.UART_CYCLES_PER_BIT

    tb = (REPO / "tb" / "timur_soc_tb.v").read_text()
    assert "gpio_in = 10'h%03X;" % memmap.TB_SWITCHES in tb
    sw_tb = (REPO / "tb" / "timur_sw_tb.v").read_text()
    assert ".UART_DIVIDER (%d)" % (memmap.TB_SW_UART_CYCLES_PER_BIT - 1) in sw_tb
