#!/usr/bin/env python3
"""expanddemo.py -- expand a 5376-byte (SMDJ3, 32/32) song block on stdin to a
6912-byte (SMDJ4, 52/40) block on stdout, for baking the demo at the new pool
sizes. Mirrors smdj4.js expand(): relocate each pool, blank the new phrases
(rows of 00 FF 00 00) and new chains ($FF), per song_new. See COMPRESSION.md."""
import sys

SMDJ3 = {  # name: (src_off, len)
    "wave": (0, 256), "phrases": (256, 2048), "chains": (2304, 1024),
    "song": (3328, 512), "instr": (3840, 256), "tables": (4096, 1024),
    "grooves": (5120, 256),
}
SMDJ4 = {  # name: dst_off  (sizes: phrases 3328=52*64, chains 1280=40*32)
    "wave": 0, "phrases": 256, "chains": 3584, "song": 4864,
    "instr": 5376, "tables": 5632, "grooves": 6656,
}
OUT_LEN = 6912


def expand(b3: bytes) -> bytes:
    if len(b3) != 5376:
        raise SystemExit(f"expanddemo: expected 5376 bytes, got {len(b3)}")
    b4 = bytearray(OUT_LEN)
    for k, (so, sl) in SMDJ3.items():
        b4[SMDJ4[k]:SMDJ4[k] + sl] = b3[so:so + sl]
    # new phrases 32..51: rows of 00 FF 00 00
    po = SMDJ4["phrases"]
    for off in range(po + SMDJ3["phrases"][1], po + 3328, 4):
        b4[off:off + 4] = bytes([0x00, 0xFF, 0x00, 0x00])
    # new chains 32..39: $FF
    co = SMDJ4["chains"]
    for off in range(co + SMDJ3["chains"][1], co + 1280):
        b4[off] = 0xFF
    return bytes(b4)


if __name__ == "__main__":
    sys.stdout.buffer.write(expand(sys.stdin.buffer.read()))
