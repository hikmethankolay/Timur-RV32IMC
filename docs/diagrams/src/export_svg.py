#!/usr/bin/env python3
"""Cut the diagram out of a docs/diagrams/src/*.html page into a standalone SVG.

Each page holds one inline <svg> styled only with presentation attributes and
system font stacks (diagram-design skill, profile `timur`), so the exported file
renders the same as an <img> on GitHub: no CSS to carry, no web fonts to load.
The SVG paints its own background, so it also reads on GitHub's dark theme.

Usage:  python3 docs/diagrams/src/export_svg.py PAGE.html OUT.svg
"""

from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SVG = re.compile(r"<svg\s.*?</svg>", re.DOTALL)


def export(page: str) -> str:
    """The <svg> element of the page as a standalone, well-formed SVG document."""
    found: list[str] = SVG.findall(page)
    if len(found) != 1:
        raise ValueError(f"expected one <svg> element, found {len(found)}")
    svg = found[0]
    ET.fromstring(svg)  # raises if the fragment is not well-formed XML
    return '<?xml version="1.0" encoding="UTF-8"?>\n' + svg + "\n"


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    page, out = (Path(name) for name in argv)
    out.write_text(export(page.read_text(encoding="utf-8")), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
