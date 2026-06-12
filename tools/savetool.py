#!/usr/bin/env python3
"""SMSDJ save manager: list/export/import song slots in a .sav image.

The .sav is a raw cart-SRAM image (Emulicious, Everdrive X7 and real
battery carts all use the same bytes). See SAVEFORMAT.md.

usage:
  savetool.py FILE.sav list
  savetool.py FILE.sav export SLOT OUT.smdj    (SLOT = 1..3)
  savetool.py FILE.sav import SLOT IN.smdj
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


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    path, cmd = sys.argv[1], sys.argv[2]

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
