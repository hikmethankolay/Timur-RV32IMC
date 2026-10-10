#!/usr/bin/env python3
"""Give SVG files an opaque #fafafa background (make diagrams runs it).

WaveDrom draws on a transparent canvas, which GitHub's dark theme turns into
black-on-dark. This inserts a background rectangle as the first child of the root
<svg> element; a file that already has it is left unchanged. WaveDrom output
also gets the palette of the D2 diagrams (_style.d2): dark grey names and
lines, the accent tint and greys for the data fills.

Usage:  python3 docs/diagrams/src/whiten.py FILE.svg...
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

MARK = 'id="timur-background"'
#: WaveDrom default colours -> the shared palette (zinc greys, cobalt tint).
WAVEDROM_COLOURS = {
    "#0041c4": "#18181b",  # signal names
    "#ffffb4": "#eef2fd",  # data value 3
    "#ffe0b9": "#f4f4f5",  # data value 4
    "#b9e0ff": "#e4e4e7",  # data value 5
    "#000": "#27272a",  # waves and text
    "#111": "#27272a",
}
ROOT = re.compile(r"<svg\b[^>]*>", re.DOTALL)


def whiten(text: str) -> str:
    """The SVG text with a background rectangle (and WaveDrom recoloured), added once."""
    if MARK in text:
        return text
    if 'class="WaveDrom"' in text:
        # only colour values: WaveDrom also names its wave bricks "#000", "#111"
        for old, new in WAVEDROM_COLOURS.items():
            text = re.sub(
                r'((?:fill|stroke|color)\s*[:=]\s*"?)' + re.escape(old) + r"(?![0-9a-fA-F])",
                lambda m, new=new: m.group(1) + new,
                text,
            )
    match = ROOT.search(text)
    if not match:
        raise ValueError("no <svg> element")
    # cover the viewBox, which need not start at 0,0; else the whole viewport
    box = re.search(r'viewBox="([-\d.]+)[ ,]+([-\d.]+)[ ,]+([\d.]+)[ ,]+([\d.]+)"', match.group())
    x, y, w, h = box.groups() if box else ("0", "0", "100%", "100%")
    rect = '<rect %s x="%s" y="%s" width="%s" height="%s" fill="#fafafa"/>' % (MARK, x, y, w, h)
    return text[: match.end()] + rect + text[match.end() :]


def main(argv: list[str]) -> int:
    for name in argv:
        path = Path(name)
        path.write_text(whiten(path.read_text(encoding="utf-8")), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
