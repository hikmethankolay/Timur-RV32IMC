"""Images for the VGA framebuffer: PNG decoding, resizing, 16-colour palettes.

Standard library only, like the rest of the tools: PNG is decoded with zlib
(no interlacing; grey, grey + alpha, RGB, RGBA at 8 or 16 bits, palette at
1, 2, 4 or 8 bits). Alpha is blended over black. The framebuffer takes 4-bit
pixels that index a palette of 12-bit colours ({R, G, B}, 4 bits each), two
pixels per byte with the left one in the low nibble.
"""

from __future__ import annotations

import struct
import zlib
from collections import Counter
from collections.abc import Sequence
from dataclasses import dataclass

from . import memmap
from .errors import TimurError

RGB = tuple[int, int, int]

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
_CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}  # colour type -> samples per pixel
_DEPTHS = {0: (8, 16), 2: (8, 16), 3: (1, 2, 4, 8), 4: (8, 16), 6: (8, 16)}
_PALETTE, _GREY, _GREY_ALPHA, _RGBA = 3, 0, 4, 6


class ImageError(TimurError):
    """The image cannot be read or converted."""


@dataclass(frozen=True)
class Image:
    """An RGB image, 8 bits per channel, rows top to bottom."""

    width: int
    height: int
    pixels: tuple[RGB, ...]  # width * height, row by row

    def at(self, x: int, y: int) -> RGB:
        """The pixel at column x, row y."""
        return self.pixels[y * self.width + x]


# ---- PNG -------------------------------------------------------------------------------


def _chunks(data: bytes) -> list[tuple[bytes, bytes]]:
    if not data.startswith(PNG_SIGNATURE):
        raise ImageError("not a PNG file")
    chunks: list[tuple[bytes, bytes]] = []
    offset = len(PNG_SIGNATURE)
    while offset + 8 <= len(data):
        length, kind = struct.unpack(">I4s", data[offset : offset + 8])
        body = data[offset + 8 : offset + 8 + length]
        if len(body) != length:
            raise ImageError("PNG chunk %r is cut short" % kind.decode("latin-1"))
        chunks.append((kind, body))
        offset += 12 + length
        if kind == b"IEND":
            break
    return chunks


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def _unfilter(raw: bytes, row_bytes: int, height: int, bpp: int) -> list[bytearray]:
    """The scanlines of the decompressed image data, with the filters undone."""
    rows: list[bytearray] = []
    previous = bytearray(row_bytes)
    offset = 0
    for _ in range(height):
        if offset + 1 + row_bytes > len(raw):
            raise ImageError("PNG image data is cut short")
        kind = raw[offset]
        if kind > 4:
            raise ImageError("unknown PNG filter type %d" % kind)
        row = bytearray(raw[offset + 1 : offset + 1 + row_bytes])
        offset += 1 + row_bytes
        for i in range(row_bytes):
            left = row[i - bpp] if i >= bpp else 0
            up = previous[i]
            if kind == 1:
                row[i] = (row[i] + left) & 0xFF
            elif kind == 2:
                row[i] = (row[i] + up) & 0xFF
            elif kind == 3:
                row[i] = (row[i] + (left + up) // 2) & 0xFF
            elif kind == 4:
                upper_left = previous[i - bpp] if i >= bpp else 0
                row[i] = (row[i] + _paeth(left, up, upper_left)) & 0xFF
        rows.append(row)
        previous = row
    return rows


def _samples(row: bytearray, depth: int, count: int) -> list[int]:
    """The first count samples of a scanline, at 1, 2, 4, 8 or 16 bits each."""
    if depth == 8:
        return list(row[:count])
    if depth == 16:  # keep the high byte
        return list(row[0 : 2 * count : 2])
    per_byte = 8 // depth
    mask = (1 << depth) - 1
    return [(row[i // per_byte] >> (8 - depth * (i % per_byte + 1))) & mask for i in range(count)]


def read_png(data: bytes) -> Image:
    """Decode a PNG file into an RGB image."""
    chunks = _chunks(data)
    if not chunks or chunks[0][0] != b"IHDR":
        raise ImageError("PNG file without an IHDR chunk")
    width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", chunks[0][1])
    if colour not in _CHANNELS or depth not in _DEPTHS[colour]:
        raise ImageError("unsupported PNG format: colour type %d, %d bits" % (colour, depth))
    if interlace:
        raise ImageError("interlaced PNG files are not supported; save it without interlacing")
    if width == 0 or height == 0:
        raise ImageError("empty PNG image")
    palette = b"".join(body for kind, body in chunks if kind == b"PLTE")
    try:
        raw = zlib.decompress(b"".join(body for kind, body in chunks if kind == b"IDAT"))
    except zlib.error as error:
        raise ImageError("PNG image data is corrupt: %s" % error) from None

    channels = _CHANNELS[colour]
    row_bytes = (width * channels * depth + 7) // 8
    rows = _unfilter(raw, row_bytes, height, max(1, channels * depth // 8))

    pixels: list[RGB] = []
    for row in rows:
        samples = _samples(row, depth, width * channels)
        for x in range(width):
            s = samples[x * channels : (x + 1) * channels]
            if colour == _PALETTE:
                if 3 * s[0] + 3 > len(palette):
                    raise ImageError("PNG palette index %d out of range" % s[0])
                r, g, b = palette[3 * s[0] : 3 * s[0] + 3]
                pixels.append((r, g, b))
                continue
            rgb: RGB = (s[0], s[0], s[0]) if colour in (_GREY, _GREY_ALPHA) else (s[0], s[1], s[2])
            if colour in (_GREY_ALPHA, _RGBA):  # blend over black
                alpha = s[-1]
                rgb = (rgb[0] * alpha // 255, rgb[1] * alpha // 255, rgb[2] * alpha // 255)
            pixels.append(rgb)
    return Image(width, height, tuple(pixels))


# ---- geometry --------------------------------------------------------------------------


def resize(image: Image, width: int, height: int) -> Image:
    """Scale to width x height: averages when shrinking both ways, else nearest pixel."""
    if (image.width, image.height) == (width, height):
        return image
    if image.width >= width and image.height >= height:
        sums = [[0, 0, 0, 0] for _ in range(width * height)]
        for y in range(image.height):
            row = (y * height // image.height) * width
            for x in range(image.width):
                cell = sums[row + x * width // image.width]
                r, g, b = image.at(x, y)
                cell[0] += r
                cell[1] += g
                cell[2] += b
                cell[3] += 1
        pixels = tuple((r // n, g // n, b // n) for r, g, b, n in sums)
    else:
        pixels = tuple(
            image.at(x * image.width // width, y * image.height // height)
            for y in range(height)
            for x in range(width)
        )
    return Image(width, height, pixels)


def fit(image: Image, width: int, height: int) -> Image:
    """Scale to fit width x height with the aspect ratio kept, centred on black."""
    width_limits = width * image.height <= height * image.width
    inner_w = width if width_limits else max(1, image.width * height // image.height)
    inner_h = max(1, image.height * width // image.width) if width_limits else height
    inner = resize(image, inner_w, inner_h)
    left, top = (width - inner_w) // 2, (height - inner_h) // 2
    black: RGB = (0, 0, 0)
    pixels = [black] * (width * height)
    for y in range(inner_h):
        start = (top + y) * width + left
        pixels[start : start + inner_w] = inner.pixels[y * inner_w : (y + 1) * inner_w]
    return Image(width, height, tuple(pixels))


# ---- colours ---------------------------------------------------------------------------


def to_rgb444(rgb: RGB) -> int:
    """The nearest 12-bit colour, 0xRGB."""
    r, g, b = ((value * 15 + 127) // 255 for value in rgb)
    return (r << 8) | (g << 4) | b


def _channels(colour: int) -> RGB:
    return (colour >> 8) & 15, (colour >> 4) & 15, colour & 15


def _widest(box: list[int], counts: Counter[int]) -> tuple[int, int]:
    """(channel range times pixel count, the channel) of a median-cut box."""
    ranges = [
        max(_channels(c)[k] for c in box) - min(_channels(c)[k] for c in box) for k in range(3)
    ]
    channel = max(range(3), key=lambda k: ranges[k])
    return ranges[channel] * sum(counts[c] for c in box), channel


def median_cut(counts: Counter[int], size: int = memmap.VGA_COLOURS) -> list[int]:
    """A palette of at most size 12-bit colours for the given colour counts."""
    if len(counts) <= size:
        return sorted(counts, key=lambda colour: (-counts[colour], colour))
    boxes: list[list[int]] = [sorted(counts)]
    while len(boxes) < size:
        index = max(range(len(boxes)), key=lambda i: _widest(boxes[i], counts)[0])
        score, channel = _widest(boxes[index], counts)
        if score == 0:
            break
        box = sorted(boxes[index], key=lambda c: (_channels(c)[channel], c))
        total, running, cut = sum(counts[c] for c in box), 0, 1
        for i, c in enumerate(box[:-1]):  # split at the weighted median
            running += counts[c]
            if 2 * running >= total:
                cut = i + 1
                break
        boxes[index : index + 1] = [box[:cut], box[cut:]]
    palette = set()
    for box in boxes:
        weight = sum(counts[c] for c in box)
        r, g, b = (
            (sum(_channels(c)[k] * counts[c] for c in box) + weight // 2) // weight
            for k in range(3)
        )
        palette.add((r << 8) | (g << 4) | b)
    return sorted(palette)


def nearest(colour: int, palette: Sequence[int]) -> int:
    """Index of the palette entry closest to colour (squared distance, 4-bit channels)."""
    r, g, b = _channels(colour)

    def distance(entry: int) -> tuple[int, int]:
        pr, pg, pb = _channels(palette[entry])
        return (pr - r) ** 2 + (pg - g) ** 2 + (pb - b) ** 2, entry

    return min(range(len(palette)), key=distance)


@dataclass(frozen=True)
class Indexed:
    """An image of palette indices, ready for the framebuffer."""

    width: int
    height: int
    palette: tuple[int, ...]  # VGA_COLOURS entries, 0xRGB
    indices: tuple[int, ...]  # width * height

    def packed(self) -> bytes:
        """Rows of (width + 1) // 2 bytes, two pixels per byte, the left one low."""
        out = bytearray()
        for y in range(self.height):
            row = self.indices[y * self.width : (y + 1) * self.width]
            for x in range(0, self.width, 2):
                right = row[x + 1] if x + 1 < self.width else 0
                out.append(row[x] | right << 4)
        return bytes(out)


def quantize(image: Image, palette: Sequence[int] | None = None) -> Indexed:
    """Map every pixel to a palette of up to VGA_COLOURS entries; without one, choose it."""
    colours = [to_rgb444(rgb) for rgb in image.pixels]
    chosen = list(palette) if palette is not None else median_cut(Counter(colours))
    if not chosen or len(chosen) > memmap.VGA_COLOURS:
        raise ImageError("a palette needs 1 to %d colours" % memmap.VGA_COLOURS)
    lookup = {colour: nearest(colour, chosen) for colour in set(colours)}
    full = tuple(chosen) + (0,) * (memmap.VGA_COLOURS - len(chosen))
    return Indexed(image.width, image.height, full, tuple(lookup[c] for c in colours))


# ---- C source --------------------------------------------------------------------------


def c_header(indexed: Indexed, name: str, source: str) -> list[str]:
    """A C header defining NAME_WIDTH, NAME_HEIGHT, name_palette and name_pixels."""
    upper = name.upper()
    data = indexed.packed()
    lines = [
        "/* %s.h: a %d x %d image for the Timur VGA, made by sw/img2vga.py from %s."
        % (name, indexed.width, indexed.height, source),
        " * Pixels: 4-bit palette indices, rows of (%s_WIDTH + 1) / 2 bytes, the left pixel"
        % upper,
        " * of each byte in its low nibble. Show it: vga_set_palette for each entry of",
        " * %s_palette, then vga_blit, or vga_show_image for a 320 x 240 image. */" % name,
        "#ifndef %s_H" % upper,
        "#define %s_H" % upper,
        "",
        "#include <stdint.h>",
        "",
        "#define %s_WIDTH  %d" % (upper, indexed.width),
        "#define %s_HEIGHT %d" % (upper, indexed.height),
        "",
        "static const uint16_t %s_palette[16] = {" % name,
        "    " + ", ".join("0x%03X" % colour for colour in indexed.palette[:8]) + ",",
        "    " + ", ".join("0x%03X" % colour for colour in indexed.palette[8:]) + ",",
        "};",
        "",
        "static const uint8_t %s_pixels[%d] __attribute__((aligned(4))) = {" % (name, len(data)),
    ]
    for offset in range(0, len(data), 16):
        chunk = data[offset : offset + 16]
        lines.append("    " + ", ".join("0x%02X" % byte for byte in chunk) + ",")
    lines += ["};", "", "#endif /* %s_H */" % upper]
    return lines
