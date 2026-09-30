"""ROM image files: word hex, the two 16-bit banks, Quartus .mif (timur_tools.romimage)."""

from __future__ import annotations

from pathlib import Path

import pytest
from timur_tools import memmap
from timur_tools.romimage import (
    ConvertError,
    convert,
    image_words,
    read_word_hex,
    words_from_binary,
    write_word_hex,
)


def test_words_are_little_endian_and_padded() -> None:
    assert words_from_binary(b"") == []
    assert words_from_binary(bytes.fromhex("78563412ef")) == [0x12345678, 0x000000EF]


def test_the_rom_size_is_the_limit() -> None:
    assert len(words_from_binary(bytes(memmap.ROM_SIZE))) == memmap.ROM_SIZE // 4
    with pytest.raises(ConvertError, match="larger than the 65536-byte ROM"):
        words_from_binary(bytes(memmap.ROM_SIZE + 1))


def test_convert_writes_five_files(tmp_path: Path) -> None:
    prefix = tmp_path / "out" / "image"
    prefix.parent.mkdir()

    words = convert(bytes.fromhex("78563412efcdab89"), prefix, "a title")

    assert words == [0x12345678, 0x89ABCDEF]
    assert sorted(p.name for p in prefix.parent.iterdir()) == [
        "image.hex", "image_hi.hex", "image_hi.mif", "image_lo.hex", "image_lo.mif",
    ]  # fmt: skip
    assert (tmp_path / "out" / "image_lo.hex").read_text() == "5678\nCDEF\n"
    mif = (tmp_path / "out" / "image_lo.mif").read_text()
    assert mif.startswith(
        "-- Timur RV32IMC instruction ROM, LO bank (halfwords at byte offset 0 mod 4): a title\n"
    )
    assert "DEPTH = 16384;\nWIDTH = 16;\n" in mif
    assert mif.endswith("    0001 : CDEF;\n    [0002..3FFF] : 0000;\nEND;\n")


def test_a_full_rom_has_no_fill_line(tmp_path: Path) -> None:
    convert(bytes(memmap.ROM_SIZE), tmp_path / "full", "full")

    mif = (tmp_path / "full_hi.mif").read_text()
    assert "    3FFF : 0000;\nEND;\n" in mif
    assert ".." not in mif.split("CONTENT BEGIN")[1]


def test_word_hex_round_trip_with_tags_and_comments(tmp_path: Path) -> None:
    path = tmp_path / "p.hex"
    path.write_text(
        "// hello (rv32imc_zicsr): built by sw/build.py\n"
        "// symbol _halt 00000042\n"
        "// label start 00000000\n"
        "00500093  // 0000: addi x1, x0, 5\n"
        "\n"
        "0000006F\n"
    )

    image = read_word_hex(path)

    assert image.words == [0x00500093, 0x0000006F]
    assert image.tags == {"_halt": 0x42, "start": 0}
    assert image.memory() == {0: 0x00500093, 4: 0x0000006F}

    write_word_hex(tmp_path / "copy.hex", image.words)
    assert read_word_hex(tmp_path / "copy.hex").words == image.words


def test_reading_a_missing_or_malformed_image_is_a_convert_error(tmp_path: Path) -> None:
    with pytest.raises(ConvertError, match=r"nothing\.hex"):
        read_word_hex(tmp_path / "nothing.hex")
    bad = tmp_path / "bad.hex"
    bad.write_text("0000006F\nnot hex\n")
    with pytest.raises(ConvertError, match=r"bad\.hex:2"):
        read_word_hex(bad)


def test_image_words_fills_gaps_with_zero() -> None:
    assert image_words({0: 1, 12: 2}) == [1, 0, 0, 2]
