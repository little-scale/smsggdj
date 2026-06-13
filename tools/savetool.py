#!/usr/bin/env python3
"""SMSDJ save manager: list/export/import song slots in a .sav image.

The .sav is a raw cart-SRAM image (Emulicious, Everdrive X7 and real
battery carts all use the same bytes). See SAVEFORMAT.md.

usage:
  savetool.py FILE.sav list
  savetool.py FILE.sav export SLOT OUT.smdj    (SLOT = 1..3)
  savetool.py FILE.sav import SLOT IN.smdj
  savetool.py FILE.sav export-all [PREFIX]     (every valid slot)
  savetool.py build OUT.sav A.smdj [B.smdj [C.smdj]]
  savetool.py wrap OUT.smdj BLOCK.bin          (bare 5,376-byte
                                song block -> valid .smdj)
"""
import os
import sys

MAGIC = b"SMDJ3"
STRIDE = 0x1520
HDR = 16
DATA = 5376
BLOB = HDR + DATA
SLOTS = 3
SAV_SIZE = 32768


def checksum(data):
    return sum(data) & 0xFFFF


def slot_state(img, n):
    base = n * STRIDE
    blob = img[base:base + BLOB]
    if len(blob) < BLOB or blob[:5] != MAGIC:
        return "empty"
    stored = blob[5] | (blob[6] << 8)
    if stored != checksum(blob[HDR:]):
        return "corrupt (bad checksum)"
    return "song (checksum ok)"


def make_blob(data):
    assert len(data) == DATA
    c = checksum(data)
    return MAGIC + bytes([c & 0xFF, c >> 8]) + bytes(9) + data


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)

    if sys.argv[1] == "build":
        songs = sys.argv[3:]
        if not 1 <= len(songs) <= SLOTS:
            sys.exit("build takes 1..%d songs" % SLOTS)
        img = bytearray(b"\xFF" * SAV_SIZE)
        for n, p in enumerate(songs):
            blob = open(p, "rb").read()
            if len(blob) != BLOB or blob[:5] != MAGIC:
                sys.exit(p + ": not an .smdj song blob")
            if (blob[5] | (blob[6] << 8)) != checksum(blob[HDR:]):
                sys.exit(p + ": failed its checksum")
            img[n * STRIDE:n * STRIDE + BLOB] = blob
            print("slot %d <- %s" % (n + 1, p))
        open(sys.argv[2], "wb").write(img)
        print("built " + sys.argv[2])
        return

    if sys.argv[1] == "wrap":
        data = open(sys.argv[3], "rb").read()
        if len(data) != DATA:
            sys.exit("song block must be exactly %d bytes" % DATA)
        open(sys.argv[2], "wb").write(make_blob(data))
        print("wrapped %s -> %s" % (sys.argv[3], sys.argv[2]))
        return

    path, cmd = sys.argv[1], sys.argv[2]

    if cmd == "export-all" and os.path.exists(path):
        img = open(path, "rb").read()
        prefix = sys.argv[3] if len(sys.argv) > 3 else \
            os.path.splitext(path)[0]
        n_out = 0
        for n in range(SLOTS):
            base = n * STRIDE
            blob = img[base:base + BLOB]
            if blob[:5] != MAGIC or \
               (blob[5] | (blob[6] << 8)) != checksum(blob[HDR:]):
                continue
            out = "%s-slot%d.smdj" % (prefix, n + 1)
            open(out, "wb").write(blob)
            print("slot %d -> %s" % (n + 1, out))
            n_out += 1
        print("%d song(s) exported" % n_out)
        return

    if os.path.exists(path):
        img = bytearray(open(path, "rb").read())
    elif cmd == "import":
        img = bytearray(b"\xFF" * SAV_SIZE)
        print("creating new %d-byte save image" % SAV_SIZE)
    else:
        sys.exit("no such file: " + path)

    if cmd == "list":
        for n in range(SLOTS):
            print("slot %d: %s" % (n + 1, slot_state(img, n)))
        return

    if cmd in ("export", "import") and len(sys.argv) == 5:
        n = int(sys.argv[3]) - 1
        if not 0 <= n < SLOTS:
            sys.exit("slot must be 1..%d" % SLOTS)
        base = n * STRIDE
        if cmd == "export":
            blob = bytes(img[base:base + BLOB])
            if blob[:5] != MAGIC:
                sys.exit("slot %d is empty" % (n + 1))
            if (blob[5] | (blob[6] << 8)) != checksum(blob[HDR:]):
                sys.exit("slot %d failed its checksum" % (n + 1))
            open(sys.argv[4], "wb").write(blob)
            print("exported slot %d -> %s" % (n + 1, sys.argv[4]))
        else:
            blob = open(sys.argv[4], "rb").read()
            if len(blob) != BLOB or blob[:5] != MAGIC:
                sys.exit("not an .smdj song blob")
            if (blob[5] | (blob[6] << 8)) != checksum(blob[HDR:]):
                sys.exit("song blob failed its checksum")
            if len(img) < SAV_SIZE:
                img.extend(b"\xFF" * (SAV_SIZE - len(img)))
            img[base:base + BLOB] = blob
            open(path, "wb").write(img)
            print("imported %s -> slot %d" % (sys.argv[4], n + 1))
        return

    sys.exit(__doc__)


if __name__ == "__main__":
    main()
