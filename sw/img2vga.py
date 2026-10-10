#!/usr/bin/env python3
"""Convert a PNG image into a C header for the Timur VGA framebuffer.

The image is scaled to the requested size (default the whole screen, 320 x 240;
--keep-aspect fits it inside and fills the rest with black), its colours are
reduced to a palette of 16 12-bit colours (median cut, or --palette vga for the
standard colours the VGA has after reset), and the 4-bit pixels are written as
a C array in the framebuffer's layout. Example, in apps/:

    python3 sw/img2vga.py photo.png -o apps/photo.h
    #include "photo.h"
    for (int i = 0; i < 16; i++) vga_set_palette(i, photo_palette[i]);
    vga_show_image(photo_pixels);          /* a 320 x 240 image, copied by the DMAC */

A full-screen image takes 38,400 of the ROM's 65,536 bytes.

Usage:  python3 sw/img2vga.py IMAGE.png [-o OUT.h] [--name NAME] [--size WxH]
                              [--keep-aspect] [--palette auto|vga]
"""

from __future__ import annotations

import argparse
import re
import sys
from collections.abc import Sequence
from pathlib import Path

from timur_tools import cli, image, memmap, romimage


def size(text: str) -> tuple[int, int]:
    """argparse type: WxH within the screen."""
    match = re.fullmatch(r"(\d+)[xX](\d+)", text)
    if not match:
        raise argparse.ArgumentTypeError("%r is not WIDTHxHEIGHT" % text)
    width, height = int(match.group(1)), int(match.group(2))
    if not (0 < width <= memmap.VGA_WIDTH and 0 < height <= memmap.VGA_HEIGHT):
        raise argparse.ArgumentTypeError(
            "%dx%d does not fit the %dx%d screen"
            % (width, height, memmap.VGA_WIDTH, memmap.VGA_HEIGHT)
        )
    return width, height


def identifier(stem: str) -> str:
    """A C identifier made from a file name."""
    name = re.sub(r"\W", "_", stem).strip("_").lower() or "image"
    return "image_" + name if name[0].isdigit() else name


def main(argv: Sequence[str] | None = None) -> int:
    """Convert one image; returns the exit status."""
    parser = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[0])
    parser.add_argument("image", type=Path, help="PNG file")
    parser.add_argument("-o", "--output", type=Path, help="C header (default: NAME.h here)")
    parser.add_argument("--name", help="C name of the image (default: from the file name)")
    parser.add_argument(
        "--size", type=size, default=(memmap.VGA_WIDTH, memmap.VGA_HEIGHT), metavar="WxH",
        help="size in framebuffer pixels (default: %dx%d)" % (memmap.VGA_WIDTH, memmap.VGA_HEIGHT),
    )  # fmt: skip
    parser.add_argument("--keep-aspect", action="store_true", help="fit inside WxH, the rest black")
    parser.add_argument(
        "--palette", choices=("auto", "vga"), default="auto",
        help="auto: the 16 colours that suit the image best; vga: the reset palette",
    )  # fmt: skip
    cli.add_common_arguments(parser, root=False)
    args = parser.parse_args(argv)
    cli.configure_logging(args.verbose)

    name = identifier(args.name or args.image.stem)
    output = args.output or Path(name + ".h")
    width, height = args.size
    picture = image.read_png(args.image.read_bytes())
    scaled = (
        image.fit(picture, width, height)
        if args.keep_aspect
        else image.resize(picture, width, height)
    )
    palette = memmap.VGA_PALETTE_RESET if args.palette == "vga" else None
    indexed = image.quantize(scaled, palette)
    romimage.write_lines(output, image.c_header(indexed, name, args.image.name))
    print(
        "wrote %s: %s, %dx%d, %d bytes of pixels"
        % (output, name, width, height, len(indexed.packed()))
    )
    return 0


if __name__ == "__main__":
    sys.exit(cli.run(main, "img2vga"))
