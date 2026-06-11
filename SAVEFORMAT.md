# SMSDJ save format

## Where saves live

SMSDJ stores songs in **cart SRAM** — the battery-backed RAM that Sega
mapper carts expose at `$8000–$BFFF` when bit 3 of mapper register
`$FFFC` is set.

| Environment | What holds the SRAM image |
|---|---|
| Emulicious (and most emulators) | a raw `.sav` file written next to the ROM (`build/smsdj.sav`), created/updated when the emulator exits or flushes saves |
| Master Everdrive X7 | a raw save file on the SD card, same byte-for-byte format |
| Real battery cart | the physical SRAM chip |

All three are interchangeable: the `.sav` from Emulicious copied onto an
Everdrive X7 SD card (or vice versa) carries your songs across. It is a
plain memory image with **no container or byte-order tricks**, so it is
fully exportable/importable — `tools/savetool.py` works directly on it.

## Layout

The 16 KB SRAM window holds up to **3 song slots** at a stride of
`$1500` (5,376 bytes). 8 KB carts mirror the upper half and hold 1 slot.

```
slot n base = n * $1500          (n = 0..2)

offset  size  contents
+$00    5     magic "SMDJ2"
+$05    2     checksum: 16-bit little-endian sum of the 5,248 data bytes
+$07    9     reserved
+$10    5248  song data, the contiguous RAM block:
              +$0000  wave_ram      4 waves x 32 B ($D0 | 15-minus-level per
                                    step; the drawn shape — playback maps levels
                                    through the log-DAC correction separately)
              +$0080  phrase_pool   32 phrases x 64 B (16 steps x note,instr,cmd,param)
              +$0880  chains        32 chains x 32 B (16 x phrase#,transpose)
              +$0C80  song          128 rows x 4 chain numbers ($FF empty)
              +$0E80  instruments   16 x 16 B records
              +$0F80  tables        16 x 64 B (16 rows x vol,pitch,cmd,param)
              +$1380  grooves       16 x 16 tick bytes
```

Format history: `SMDJ1` lacked wave_ram (5,120 data bytes); v1
saves are not loaded by v2 builds.

A slot is valid when the magic matches **and** the checksum verifies;
SMSDJ refuses to load anything else (`NO DATA`). Slot 1 (offset 0)
autoloads at boot.

## tools/savetool.py

```
python3 tools/savetool.py build/smsdj.sav list
python3 tools/savetool.py build/smsdj.sav export 1 mysong.smdj
python3 tools/savetool.py build/smsdj.sav import 2 mysong.smdj
```

`.smdj` files are a single slot (header + data, 5,264 bytes) — share
them, back them up, or move songs between slots/carts. `import`
revalidates the checksum and creates the `.sav` (32 KB, `$FF`-filled)
if it doesn't exist yet, so you can prepare a cart image entirely
offline.
