"""PNG decoding, scaling and 16-colour palettes for the VGA (timur_tools.image, img2vga)."""

from __future__ import annotations

import struct
import zlib
from collections import Counter
from pathlib import Path

import pytest

import img2vga
from timur_tools import image, memmap


def chunk(kind: bytes, body: bytes) -> bytes:
    crc = zlib.crc32(kind + body)
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", crc)


def png(
    width: int, height: int, colour: int, depth: int, rows: list[bytes], **extra: bytes
) -> bytes:
    """A PNG file; each row already starts with its filter byte."""
    header = struct.pack(
        ">IIBBBBB", width, height, depth, colour, 0, 0, extra.pop("interlace", b"\0")[0]
    )
    body = b"".join(chunk(kind.encode(), value) for kind, value in extra.items())
    return (
        image.PNG_SIGNATURE
        + chunk(b"IHDR", header)
        + body
        + chunk(b"IDAT", zlib.compress(b"".join(rows)))
        + chunk(b"IEND", b"")
    )


RED, GREEN, BLUE, WHITE = (255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 255)


def test_rgb_png_with_every_filter() -> None:
    # 2 x 5 RGB: row 0 unfiltered, then Sub, Up, Average and Paeth rows that
    # decode to the same two pixels (red, green)
    plain = bytes([255, 0, 0, 0, 255, 0])
    sub = bytes([255, 0, 0, (0 - 255) & 0xFF, 255, 0])
    up = bytes(6)
    average = bytes([255 - 255 // 2, 0, 0, (0 - 255 // 2) & 0xFF, 255 - 255 // 2, 0])
    # Paeth: for the first pixel the predictor is 'up' (left and upper-left are 0)
    paeth = bytes([0, 0, 0, (0 - 0) & 0xFF, (255 - 255) & 0xFF, 0])
    rows = [b"\0" + plain, b"\1" + sub, b"\2" + up, b"\3" + average, b"\4" + paeth]

    decoded = image.read_png(png(2, 5, 2, 8, rows))

    assert (decoded.width, decoded.height) == (2, 5)
    assert all(decoded.at(0, y) == RED and decoded.at(1, y) == GREEN for y in range(5))


def test_palette_png_at_4_bits_and_grey_alpha_and_16_bit() -> None:
    palette = bytes([*RED, *GREEN, *BLUE])
    four_bit = image.read_png(png(3, 1, 3, 4, [b"\0" + bytes([0x01, 0x20])], PLTE=palette))
    assert four_bit.pixels == (RED, GREEN, BLUE)

    grey_alpha = image.read_png(png(2, 1, 4, 8, [b"\0" + bytes([200, 255, 200, 0])]))
    assert grey_alpha.pixels == ((200, 200, 200), (0, 0, 0))  # alpha blended over black

    sixteen = image.read_png(png(1, 1, 6, 16, [b"\0" + bytes([255, 1, 0, 0, 128, 0, 255, 255])]))
    assert sixteen.pixels == ((255, 0, 128),)


@pytest.mark.parametrize(
    ("data", "message"),
    [
        (b"GIF89a", "not a PNG"),
        (png(1, 1, 2, 8, [b"\0" + bytes(3)], interlace=b"\1"), "interlaced"),
        (png(1, 1, 2, 4, [b"\0" + bytes(2)]), "unsupported PNG format"),
        (png(1, 1, 2, 8, [b"\7" + bytes(3)]), "filter type 7"),
        (png(1, 2, 2, 8, [b"\0" + bytes(3)]), "cut short"),
        (png(1, 1, 3, 8, [b"\0" + bytes([5])], PLTE=bytes(3)), "palette index 5"),
        (image.PNG_SIGNATURE + chunk(b"IHDR", bytes(5)), "IHDR chunk has the wrong length"),
    ],
)
def test_bad_png_files_are_reported(data: bytes, message: str) -> None:
    with pytest.raises(image.ImageError, match=message):
        image.read_png(data)


def test_resize_averages_when_shrinking_and_repeats_when_growing() -> None:
    picture = image.Image(2, 2, (WHITE, (0, 0, 0), (0, 0, 0), (0, 0, 0)))
    assert image.resize(picture, 1, 1).pixels == ((63, 63, 63),)
    assert image.resize(picture, 4, 2).pixels[:4] == (WHITE, WHITE, (0, 0, 0), (0, 0, 0))


def test_fit_keeps_the_aspect_ratio() -> None:
    wide = image.Image(4, 1, (RED,) * 4)
    fitted = image.fit(wide, 4, 4)  # one row of red, centred

    assert [fitted.at(0, y) for y in range(4)] == [(0, 0, 0), RED, (0, 0, 0), (0, 0, 0)]


def test_quantize_keeps_few_colours_exactly() -> None:
    picture = image.Image(3, 1, (RED, GREEN, RED))
    indexed = image.quantize(picture)

    assert indexed.palette[:2] == (0xF00, 0x0F0)  # most frequent first
    assert indexed.indices == (0, 1, 0)
    assert len(indexed.palette) == memmap.VGA_COLOURS


def test_median_cut_reduces_to_16_colours() -> None:
    counts = Counter({(r << 8) | (g << 4) | 8: 1 + r for r in range(16) for g in range(16)})
    palette = image.median_cut(counts)

    assert 1 < len(palette) <= 16
    assert palette == sorted(palette)
    assert image.median_cut(counts) == palette  # deterministic


def test_vga_palette_and_packing() -> None:
    picture = image.Image(3, 2, (WHITE, (0, 0, 0), (170, 0, 0), BLUE, BLUE, BLUE))
    indexed = image.quantize(picture, memmap.VGA_PALETTE_RESET)

    assert indexed.indices == (15, 0, 4, 1, 1, 1)  # white, black, red, blue
    assert indexed.packed() == bytes([0x0F, 0x04, 0x11, 0x01])  # left pixel low, rows padded


def test_img2vga_writes_a_c_header(tmp_path: Path) -> None:
    source = tmp_path / "Logo 2.png"
    source.write_bytes(png(2, 1, 2, 8, [b"\0" + bytes([*RED, *WHITE])]))
    out = tmp_path / "logo.h"

    assert img2vga.main([str(source), "-o", str(out), "--size", "4x2", "--palette", "vga"]) == 0

    text = out.read_text()
    assert "#define LOGO_2_WIDTH  4" in text
    assert "static const uint8_t logo_2_pixels[4] __attribute__((aligned(4)))" in text
    assert "0x44, 0xFF, 0x44, 0xFF," in text  # red, white: the nearest standard colours


def test_img2vga_rejects_sizes_beyond_the_screen() -> None:
    with pytest.raises(SystemExit):
        img2vga.main(["x.png", "--size", "321x10"])
    assert img2vga.identifier("3d-model") == "image_3d_model"
