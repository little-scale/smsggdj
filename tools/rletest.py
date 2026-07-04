#!/usr/bin/env python3
"""rletest.py -- measure RLE compression of SMSGGDJ song data blocks.

Reference codec for the RLE save work (see COMPRESSION.md). The codec here is the
*canonical decoder* the Z80 cart codec and the JS savetool must both match -- two
encoders may emit different streams that decode identically, so everyone only has
to agree on this decoder, not on encoder output.

It answers the M1 question on REAL songs before any asm is written: does the flat
data block compress enough to be worth the directory + pool growth?

RLE stream format (PackBits-style, 4-byte unit):

    control byte c:
      bit7 = 0  -> literal run : copy the next (c & 0x7F)+1 units verbatim   (1..128)
      bit7 = 1  -> repeat run  : next 1 unit, output (c & 0x7F)+2 times       (2..129)

Paired on-cart with a STORE-RAW fallback so stored size is always min(rle, raw):
compression can only help, never hurt.

Usage:
    rletest.py                       # self-test on synthetic blocks
    rletest.py songs/demo.smdj ...   # measure real songs (.smdj or raw block)
    rletest.py --pools song.smdj     # add a per-pool breakdown
    rletest.py --grown ...           # measure against the 52/40 (6912 B) layout
"""

import sys

SMDJ_MAGIC = b"SMDJ3"
SMDJ_HDR   = 16            # .smdj header bytes before the data block

# UNIT=4 = one phrase/table row (note/instr/cmd/param). An empty row is ONE
# repeated unit; byte-RLE (UNIT=1) misses it because the empty pattern alternates
# every 2 bytes. Every pool length is a multiple of 4, so units divide cleanly.
UNIT = 4

# Block geometry mirrors SAVEFORMAT.md / tools/smdj4.js (the canonical source;
# Python can't import the JS, so keep these in sync by hand if the layout moves).
# Legacy (SMDJ3, 32 phrases / 32 chains) -- 5376 B.
DATA_LEN = 5376
POOLS = [
    ("wave_ram",       0,  256),
    ("phrases",      256, 2048),   # 32 x 64
    ("chains",      2304, 1024),   # 32 x 32
    ("song",        3328,  512),   # 128 x 4
    ("instruments", 3840,  256),   # 16 x 16
    ("tables",      4096, 1024),   # 16 x 64
    ("grooves",     5120,  256),   # 16 x 16
]

# Live (SMDJ4, 52 phrases / 40 chains) -- 6912 B.
DATA_LEN_GROWN = 6912
POOLS_GROWN = [
    ("wave_ram",       0,  256),
    ("phrases",      256, 3328),   # 52 x 64
    ("chains",      3584, 1280),   # 40 x 32
    ("song",        4864,  512),
    ("instruments", 5376,  256),
    ("tables",      5632, 1024),
    ("grooves",     6656,  256),
]

SRAM = {"32K": 32768, "64K": 65536}
RESERVE = 512          # config + directory base (SMSGGDJ has no instrument bank)
DIR_PER_SONG = 16


def rle_compress(data: bytes) -> bytes:
    out = bytearray()
    n = len(data) // UNIT
    U = [data[k*UNIT:(k+1)*UNIT] for k in range(n)]
    i = 0
    while i < n:
        run = 1
        while i + run < n and U[i + run] == U[i] and run < 129:
            run += 1
        if run >= 2:                                   # repeat: 1 ctrl + 1 unit
            out.append(0x80 | (run - 2)); out += U[i]; i += run
            continue
        j = i                                          # literal up to the next 2+ run
        while j < n and (j - i) < 128 and not (j + 1 < n and U[j + 1] == U[j]):
            j += 1
        if j == i:
            j = i + 1
        out.append((j - i) - 1)
        for k in range(i, j):
            out += U[k]
        i = j
    out += data[n*UNIT:]
    return bytes(out)


def rle_decompress(data: bytes) -> bytes:
    out = bytearray()
    i, n = 0, len(data)
    while i < n:
        c = data[i]; i += 1
        if c & 0x80:
            out += data[i:i + UNIT] * ((c & 0x7F) + 2); i += UNIT
        else:
            cnt = (c & 0x7F) + 1
            out += data[i:i + cnt*UNIT]; i += cnt*UNIT
    return bytes(out)


def measure(block: bytes) -> dict:
    rle = rle_compress(block)
    assert rle_decompress(rle) == block, "round-trip mismatch -- codec bug!"
    raw = len(block)
    store_raw = len(rle) >= raw
    on_cart = min(len(rle), raw)
    return {"raw": raw, "rle": len(rle), "on_cart": on_cart,
            "store_raw": store_raw, "ratio": on_cart / raw}


def songs_per_cart(on_cart: int) -> dict:
    return {k: max(0, (sz - RESERVE) // (on_cart + DIR_PER_SONG))
            for k, sz in SRAM.items()}


def load_block(path: str, data_len: int):
    raw = open(path, "rb").read()
    if raw[:5] == SMDJ_MAGIC and len(raw) >= SMDJ_HDR + data_len:
        return raw[SMDJ_HDR:SMDJ_HDR + data_len], path.split("/")[-1]
    if len(raw) == data_len:
        return raw, path.split("/")[-1]
    raise ValueError(f"{path}: not an SMDJ3 .smdj and not a {data_len}-byte block "
                     f"({len(raw)} bytes)")


def report(label: str, block: bytes, pools, want_pools: bool) -> dict:
    m = measure(block)
    flag = "  [STORE RAW]" if m["store_raw"] else ""
    spc = songs_per_cart(m["on_cart"])
    print(f"{label:<18} raw {m['raw']:>6}  ->  {m['on_cart']:>6}  "
          f"({m['ratio']*100:5.1f}%)   ~{spc['32K']}/32K  ~{spc['64K']}/64K{flag}")
    if want_pools:
        for name, off, ln in pools:
            pm = measure(block[off:off + ln])
            print(f"    {name:<12} {ln:>6}  ->  {pm['on_cart']:>6}  ({pm['ratio']*100:5.1f}%)")
    return m


def self_test(data_len: int, pools):
    print(f"self-test (synthetic {data_len}-byte blocks; round-trip verified):\n")
    blocks = {
        "all-FF (empty)":   bytes([0xFF]) * data_len,
        "all-00":           bytes(data_len),
        "sparse ~15% full": bytes(
            (i * 2654435761 & 0xFF) if (i * 40503 & 0xFFFF) < 9800 else 0xFF
            for i in range(data_len)),
        "random (worst)":   bytes((i * 2654435761 >> 13) & 0xFF for i in range(data_len)),
    }
    for name, b in blocks.items():
        report(name, b, pools, False)
    print("\nempty/sparse compress hard; random hits the store-raw floor (100%+epsilon).")
    print("feed real .smdj files for the numbers that matter.")


def main(argv):
    grown = "--grown" in argv
    want_pools = "--pools" in argv
    data_len = DATA_LEN_GROWN if grown else DATA_LEN
    pools = POOLS_GROWN if grown else POOLS
    args = [a for a in argv if not a.startswith("--")]
    if not args:
        self_test(data_len, pools); return
    print(f"layout: {'SMDJ4 52/40' if grown else 'SMDJ3 32/32'} ({data_len} B)\n")
    print(f"{'song':<18} {'raw':>10}      {'stored':>6}   ratio   songs/cart\n")
    totals = []
    for path in args:
        try:
            block, label = load_block(path, data_len)
        except (OSError, ValueError) as e:
            print(f"  skip: {e}"); continue
        totals.append(report(label, block, pools, want_pools))
    if len(totals) > 1:
        raw = sum(t["raw"] for t in totals)
        cart = sum(t["on_cart"] for t in totals)
        avg = sum(t["ratio"] for t in totals) / len(totals)
        print(f"\n{len(totals)} songs: {raw} -> {cart} stored, avg {avg*100:.1f}% of raw")


if __name__ == "__main__":
    main(sys.argv[1:])
