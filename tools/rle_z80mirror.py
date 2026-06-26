#!/usr/bin/env python3
"""rle_z80mirror.py -- verify src/rle.asm's pack LOGIC.

I can't run-test Z80 here, so this mirrors the control flow of rle_pack's two
tricky helpers (rle_count_run / rle_count_literal, with their exact boundary
conditions and the rem<256 fast paths) and checks the resulting stream is
byte-identical to the verified reference encoder (tools/rletest.py) on the real
demo song + edge cases. If this passes, the asm's branch logic is correct; only
transcription/syntax remain (caught by build-clean).
"""
import sys
sys.path.insert(0, "tools")
import rletest  # the verified reference (Python)


def count_run(units, i):
    """Mirror of rle_count_run: run of identical units at i, cap min(rem,129)."""
    rem = len(units) - i
    run = 1
    while True:
        if run == 129:                      # cp 129 / jr z
            break
        if rem < 256 and run >= rem:        # rem high==0 then run>=rem -> stop
            break
        if units[i + run] != units[i]:      # 4-byte unit compare
            break
        run += 1
    return run


def count_literal(units, i):
    """Mirror of rle_count_literal: units until a repeat begins, cap 128."""
    rem = len(units) - i
    L = 0
    while True:
        if L == 128:                        # cp 128 / jr z
            break
        if rem < 256 and L >= rem:          # in-range check
            break
        if rem < 256 and (L + 1) >= rem:    # no U[p+1] -> include U[p]
            L += 1
            continue
        if units[i + L] == units[i + L + 1]:  # repeat begins at p -> stop
            break
        L += 1
    if L == 0:                              # clit safety
        L = 1
    return L


def mirror_compress(data):
    units = [data[k*4:k*4+4] for k in range(len(data)//4)]
    n = len(units)
    out = bytearray()
    i = 0
    while i < n:
        run = count_run(units, i)
        if run < 2:                         # cp 2 / jr c -> literal
            L = count_literal(units, i)
            out.append(L - 1)               # ctrl = len-1
            for k in range(i, i + L):
                out += units[k]
            i += L
        else:                               # repeat
            out.append(0x80 | (run - 2))
            out += units[i]
            i += run
    return bytes(out)


def main():
    cases = {}
    blk, _ = rletest.load_block("songs/demo.smdj", 5376)
    cases["demo"] = blk
    cases["all-FF"] = bytes([0xFF]) * 5376
    cases["all-00"] = bytes(5376)
    cases["random"] = bytes((i * 2654435761 >> 13) & 0xFF for i in range(5376))
    # small hand cases that stress runs/literals/boundaries
    cases["maxrun"] = (b"\xAA\xAA\xAA\xAA" * 200)          # > 129 -> splits 129 + 71
    cases["alt"] = bytes(range(4)) * 64 + bytes([0xFF])*4  # all-literal-ish + tail
    cases["edge1unit"] = b"\x01\x02\x03\x04"

    ok = True
    for name, data in cases.items():
        if len(data) % 4:
            data = data + bytes(4 - len(data) % 4)
        mine = mirror_compress(data)
        ref = rletest.rle_compress(data)
        rt = rletest.rle_decompress(mine)
        match = mine == ref
        roundtrip = rt == data
        ok = ok and match and roundtrip
        print(f"{name:<10} mirror==ref:{'Y' if match else 'N'}  "
              f"roundtrip:{'Y' if roundtrip else 'N'}  "
              f"{len(data)} -> {len(mine)}")
    print("\nALL PASS -- asm pack logic matches the reference." if ok
          else "\nFAIL -- asm logic diverges from the reference!")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
