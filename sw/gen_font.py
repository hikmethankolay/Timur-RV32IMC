#!/usr/bin/env python3
"""The 8x8 console font of the VGA driver: writes sw/runtime/vga_font.c.

The glyphs of the printable ASCII characters 0x20-0x7E are drawn below as
5 x 8 pictures ('#' = foreground), eight characters side by side under a
';' comment that names them; row 7 is for descenders. Each glyph is placed
in columns 1-5 of an 8-pixel cell, so characters drawn next to each other are
three pixels apart. In the generated
table, byte r of a glyph is row r, with bit 7 the leftmost pixel of the cell.

Usage:  python3 sw/gen_font.py [--root DIR]
"""

from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence

from timur_tools import cli, romimage
from timur_tools.errors import GenerationError
from timur_tools.paths import Project

FONT_FILE = "vga_font.c"
FIRST, LAST = 0x20, 0x7E
GLYPH_WIDTH, GLYPH_ROWS = 5, 8
GLYPH_SHIFT = 2  # columns 1-5 of the cell: bits 6..2

ART = r"""
; 20-27: sp    !     "     #     $     %     &     '
..... ..#.. .#.#. .#.#. ..#.. ##... .##.. ..#..
..... ..#.. .#.#. .#.#. .#### ##..# #..#. ..#..
..... ..#.. .#.#. ##### #.#.. ...#. #.#.. .#...
..... ..#.. ..... .#.#. .###. ..#.. .#... .....
..... ..#.. ..... ##### ..#.# .#... #.#.# .....
..... ..... ..... .#.#. ####. #..## #..#. .....
..... ..#.. ..... .#.#. ..#.. ...## .##.# .....
..... ..... ..... ..... ..... ..... ..... .....
; 28-2F: (     )     *     +     ,     -     .     /
...#. .#... ..... ..... ..... ..... ..... .....
..#.. ..#.. ..#.. ..#.. ..... ..... ..... ....#
.#... ...#. #.#.# ..#.. ..... ..... ..... ...#.
.#... ...#. .###. ##### ..... ##### ..... ..#..
.#... ...#. #.#.# ..#.. ..... ..... ..... .#...
..#.. ..#.. ..#.. ..#.. .##.. ..... .##.. #....
...#. .#... ..... ..... ..#.. ..... .##.. .....
..... ..... ..... ..... .#... ..... ..... .....
; 30-37: 0     1     2     3     4     5     6     7
.###. ..#.. .###. ##### ...#. ##### ..##. #####
#...# .##.. #...# ...#. ..##. #.... .#... ....#
#..## ..#.. ....# ..#.. .#.#. ####. #.... ...#.
#.#.# ..#.. ...#. ...#. #..#. ....# ####. ..#..
##..# ..#.. ..#.. ....# ##### ....# #...# .#...
#...# ..#.. .#... #...# ...#. #...# #...# .#...
.###. .###. ##### .###. ...#. .###. .###. .#...
..... ..... ..... ..... ..... ..... ..... .....
; 38-3F: 8     9     :     ;     <     =     >     ?
.###. .###. ..... ..... ...#. ..... .#... .###.
#...# #...# .##.. .##.. ..#.. ..... ..#.. #...#
#...# #...# .##.. .##.. .#... ##### ...#. ....#
.###. .#### ..... ..... #.... ..... ....# ...#.
#...# ....# .##.. .##.. .#... ##### ...#. ..#..
#...# ...#. .##.. ..#.. ..#.. ..... ..#.. .....
.###. .##.. ..... .#... ...#. ..... .#... ..#..
..... ..... ..... ..... ..... ..... ..... .....
; 40-47: @     A     B     C     D     E     F     G
.###. .###. ####. .###. ###.. ##### ##### .###.
#...# #...# #...# #...# #..#. #.... #.... #...#
....# #...# #...# #.... #...# #.... #.... #....
.##.# ##### ####. #.... #...# ####. ####. #.###
#.#.# #...# #...# #.... #...# #.... #.... #...#
#.#.# #...# #...# #...# #..#. #.... #.... #...#
.###. #...# ####. .###. ###.. ##### #.... .####
..... ..... ..... ..... ..... ..... ..... .....
; 48-4F: H     I     J     K     L     M     N     O
#...# .###. ..### #...# #.... #...# #...# .###.
#...# ..#.. ...#. #..#. #.... ##.## #...# #...#
#...# ..#.. ...#. #.#.. #.... #.#.# ##..# #...#
##### ..#.. ...#. ##... #.... #.#.# #.#.# #...#
#...# ..#.. ...#. #.#.. #.... #...# #..## #...#
#...# ..#.. #..#. #..#. #.... #...# #...# #...#
#...# .###. .##.. #...# ##### #...# #...# .###.
..... ..... ..... ..... ..... ..... ..... .....
; 50-57: P     Q     R     S     T     U     V     W
####. .###. ####. .#### ##### #...# #...# #...#
#...# #...# #...# #.... ..#.. #...# #...# #...#
#...# #...# #...# #.... ..#.. #...# #...# #...#
####. #...# ####. .###. ..#.. #...# #...# #.#.#
#.... #.#.# #.#.. ....# ..#.. #...# #...# #.#.#
#.... #..#. #..#. ....# ..#.. #...# .#.#. #.#.#
#.... .##.# #...# ####. ..#.. .###. ..#.. .#.#.
..... ..... ..... ..... ..... ..... ..... .....
; 58-5F: X     Y     Z     [     \     ]     ^     _
#...# #...# ##### .###. ..... .###. ..#.. .....
#...# #...# ....# .#... #.... ...#. .#.#. .....
.#.#. .#.#. ...#. .#... .#... ...#. #...# .....
..#.. ..#.. ..#.. .#... ..#.. ...#. ..... .....
.#.#. ..#.. .#... .#... ...#. ...#. ..... .....
#...# ..#.. #.... .#... ....# ...#. ..... .....
#...# ..#.. ##### .###. ..... .###. ..... #####
..... ..... ..... ..... ..... ..... ..... .....
; 60-67: `     a     b     c     d     e     f     g
.#... ..... #.... ..... ....# ..... ..##. .....
..#.. ..... #.... ..... ....# ..... .#..# .....
...#. .###. #.##. .###. .##.# .###. .#... .####
..... ....# ##..# #.... #..## #...# ###.. #...#
..... .#### #...# #.... #...# ##### .#... #...#
..... #...# #...# #...# #...# #.... .#... .####
..... .#### ####. .###. .#### .###. .#... ....#
..... ..... ..... ..... ..... ..... ..... .###.
; 68-6F: h     i     j     k     l     m     n     o
#.... ..#.. ...#. #.... .##.. ..... ..... .....
#.... ..... ..... #.... ..#.. ..... ..... .....
#.##. .##.. ..##. #..#. ..#.. ##.#. #.##. .###.
##..# ..#.. ...#. #.#.. ..#.. #.#.# ##..# #...#
#...# ..#.. ...#. ##... ..#.. #.#.# #...# #...#
#...# ..#.. ...#. #.#.. ..#.. #...# #...# #...#
#...# .###. #..#. #..#. .###. #...# #...# .###.
..... ..... .##.. ..... ..... ..... ..... .....
; 70-77: p     q     r     s     t     u     v     w
..... ..... ..... ..... .#... ..... ..... .....
..... ..... ..... ..... .#... ..... ..... .....
####. .#### #.##. .#### ###.. #...# #...# #...#
#...# #...# ##..# #.... .#... #...# #...# #...#
#...# #...# #.... .###. .#... #...# #...# #.#.#
####. .#### #.... ....# .#..# #..## .#.#. #.#.#
#.... ....# #.... ####. ..##. .##.# ..#.. .#.#.
#.... ....# ..... ..... ..... ..... ..... .....
; 78-7E: x     y     z     {     |     }     ~
..... ..... ..... ...#. ..#.. .#... .....
..... ..... ..... ..#.. ..#.. ..#.. .....
#...# #...# ##### ..#.. ..#.. ..#.. .#...
.#.#. #...# ...#. .#... ..#.. ...#. #.#.#
..#.. #...# ..#.. ..#.. ..#.. ..#.. ...#.
.#.#. .#### .#... ..#.. ..#.. ..#.. .....
#...# ....# ##### ...#. ..#.. .#... .....
..... .###. ..... ..... ..... ..... .....
"""


def glyphs(art: str = ART) -> list[list[int]]:
    """The rows of every glyph, FIRST to LAST, as bytes of the 8-pixel cell."""
    lines = [line for line in art.splitlines() if line.strip() and not line.startswith(";")]
    if len(lines) % GLYPH_ROWS:
        raise GenerationError(
            "font art: %d picture rows is not a multiple of %d" % (len(lines), GLYPH_ROWS)
        )
    result: list[list[int]] = []
    for block in range(0, len(lines), GLYPH_ROWS):
        rows = [line.split() for line in lines[block : block + GLYPH_ROWS]]
        for column in range(len(rows[0])):
            picture = [row[column] for row in rows]
            if any(len(row) != GLYPH_WIDTH or set(row) - {".", "#"} for row in picture):
                raise GenerationError("font art: bad picture for 0x%02X" % (FIRST + len(result)))
            result.append(
                [int(row.replace(".", "0").replace("#", "1"), 2) << GLYPH_SHIFT for row in picture]
            )
    if len(result) != LAST - FIRST + 1:
        raise GenerationError("font art: %d glyphs instead of %d" % (len(result), LAST - FIRST + 1))
    return result


def source_lines(table: list[list[int]]) -> list[str]:
    """The C source of the font table."""
    lines = [
        "/* vga_font.c: the 8x8 console font of the VGA driver (vga.c).",
        " * Generated by sw/gen_font.py from the glyph pictures there; do not edit.",
        " * vga_font[c - VGA_FONT_FIRST][r] is row r of character c, bit 7 the leftmost pixel. */",
        "",
        "#include <stdint.h>",
        "",
        '#include "timur_runtime.h"',
        "",
        "const uint8_t vga_font[VGA_FONT_GLYPHS][VGA_FONT_ROWS] = {",
    ]
    for offset, rows in enumerate(table):
        code = FIRST + offset
        name = "'\\\\'" if chr(code) == "\\" else "'%s'" % chr(code)
        lines.append(
            "    { %s }, /* 0x%02X %s */" % (", ".join("0x%02X" % row for row in rows), code, name)
        )
    lines.append("};")
    return lines


def generate(project: Project) -> None:
    """Write the font table into the runtime."""
    path = project.runtime / FONT_FILE
    romimage.write_lines(path, source_lines(glyphs()))
    print("wrote %s" % path.relative_to(project.root))


def main(argv: Sequence[str] | None = None) -> int:
    """Generate the console font; returns the exit status."""
    parser = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[0])
    cli.add_common_arguments(parser)
    args = parser.parse_args(argv)
    generate(cli.project_from(args))
    return 0


if __name__ == "__main__":
    sys.exit(cli.run(main, "gen_font"))
