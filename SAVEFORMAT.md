# SMSGGDJ save format

## Where saves live

SMSGGDJ stores songs in **cart SRAM** — the battery-backed RAM that Sega
mapper carts expose at `$8000–$BFFF` when bit 3 of mapper register
`$FFFC` is set.

| Environment | What holds the SRAM image |
|---|---|
| Emulicious (and most emulators) | a raw `.sav` file written next to the ROM (`build/smsggdj.sav`), created/updated when the emulator exits or flushes saves |
| Master Everdrive X7 | a raw `.srm` on the SD card (e.g. `SMSGGDJ.SRM`), same byte-for-byte format — confirmed readable by `savetool.html` |
| Real battery cart | the physical SRAM chip |

All three are interchangeable: the `.sav` from Emulicious copied onto an
Everdrive X7 SD card (or vice versa) carries your songs across. It is a
plain memory image with **no container or byte-order tricks**, so it is
fully exportable/importable — `tools/savetool.py` works directly on it, and
`savetool.html` reads it by content (extension-agnostic: `.sav`, `.srm`, …).

**Uncompressed by design.** A song is a flat, verbatim copy of the live RAM
block (offsets below) — not a compressed stream. This is a deliberate trade:
the format stays trivially parseable, which is exactly what lets the tools
(`savetool.py`/`savetool.html`, the `als2smdj.html` Ableton converter) read and
write songs by fixed offsets with no codec on either side. The cost is that the
phrase/chain/instrument/table/groove pools are **fixed-size** (sized to the slot
budget — see Layout), since every entry costs bytes whether used or not, so the
counts are smaller than LSDJ's. **Compression (e.g. RLE) is the lever** if those
pools ever need to grow — at the price of a decoder in every tool that touches a
save. But the small, fixed pools are an **embraced constraint**, in keeping with
the project's spirit (four voices, two buttons, a flat save) — not a limitation
waiting to be removed. The flat format is a feature.

## Layout

The 16 KB SRAM window holds up to **3 song slots** at a stride of
`$1520` (5,408 bytes). 8 KB carts mirror the upper half and hold 1 slot.
A **32 KB cart adds a second 16 KB bank** (`$FFFC` bit 2), giving **6
slots** (3 per bank) — detected at boot (see below). Slots 0-2 live in
bank 0, slots 3-5 in bank 1; both use the same `$8000` window.

```
slot n base = (n mod 3) * $1520   in SRAM bank (n / 3)   (n = 0..5)
  (16 KB cart: n = 0..2, bank 0 only; 8 KB cart: n = 0)

offset  size  contents
+$00    5     magic "SMDJ3"
+$05    2     checksum: 16-bit little-endian sum of the 5,376 data bytes
+$07    8     echo settings: mode, tap1, tap2, red1, red2, stereo,
              tsp1, tsp2 (tap1/tap2 are in rows; see the manual). Not
              covered by the checksum; the baked-in demo song carries
              its own copy (build/demo_echo.bin).
+$0F    1     reserved
+$10    5376  song data, the contiguous RAM block:
              +$0000  wave_ram      8 waves x 32 B ($D0 | 15-minus-level per
                                    step; the drawn shape — playback maps levels
                                    through the log-DAC correction separately)
              +$0100  phrase_pool   32 phrases x 64 B (16 steps x note,instr,cmd,param)
              +$0900  chains        32 chains x 32 B (16 x phrase#,transpose)
              +$0D00  song          128 rows x 4 chain numbers ($FF empty)
              +$0F00  instruments   16 x 16 B records
              +$1000  tables        16 x 64 B (16 rows x vol,pitch,cmd,param)
              +$1400  grooves       16 x 16 tick bytes
```

Format history: `SMDJ1` lacked wave_ram (5,120 data bytes); `SMDJ2`
had 4 waves (5,248 data bytes, stride `$1500`). Older saves are not
loaded by newer builds.

**Size detection** (`sram_detect`, at boot): probes `$8000` for RAM, then
whether `$A000` mirrors it (8 KB) or not (16 KB), then writes distinct
markers to `$8000` in bank 0 and bank 1 — if both persist independently the
cart has a real second bank (32 KB → 6 slots). This detects *live* RAM only;
whether a flashcart **battery-backs** the second bank is a separate question,
confirmable only by a power-cycle test — **confirmed on real hardware** (a Master
Everdrive X7 on a PAL SMS1: slot 1 and slot 4 both persisted across
power-off). Verify
your own cart the same way before trusting slots 4-6. `savetool.py` and
`savetool.html`
handle all three sizes — slots 3-5 sit in the second bank at file offset
`+$4000`; the browser tool has an 8/16/32 KB cart-size selector that sets the
slot count and `.sav` size.

**OPTIONS config block** (colour scheme, sync mode, video) lives outside the
song slots, written by the ROM at CPU `$BF60` and read at boot. That's file
offset `$3F60` on a 16/32 KB image (the free tail past slot 2); on an 8 KB cart
the window mirrors, so it lands at `$1F60` (past slot 0). 7 bytes: `'C' 'F'
pal_sel sync_mode vid_sel fm_on checksum` (checksum = `pal_sel + sync_mode +
vid_sel + fm_on` & `$FF`). `vid_sel` is the VIDEO choice: `0` AUTO (follow
region detection), `1` PAL, `2` NTSC; `fm_on` is the FM unit toggle (`0` off,
`1` on). It's saved whenever you save a song, and `savetool.html` can
read/write it (the **config** controls).

A slot is valid when the magic matches **and** the checksum verifies;
SMSGGDJ refuses to load anything else (`NO DATA`). Slot 1 (offset 0)
autoloads at boot.

## tools/savetool.py

```
python3 tools/savetool.py build/smsggdj.sav list
python3 tools/savetool.py build/smsggdj.sav export 1 mysong.smdj
python3 tools/savetool.py build/smsggdj.sav import 2 mysong.smdj
python3 tools/savetool.py build/smsggdj.sav export-all backups/mysav
python3 tools/savetool.py build setlist.sav a.smdj b.smdj c.smdj
python3 tools/savetool.py wrap demo.smdj build/demo.bin
```

**Browser version: `tools/savetool.html`** — drop a `.sav` to unpack
its songs, drop `.smdj` files (bare song blocks wrap automatically)
and download the assembled cart image; fully client-side, validated
byte-identical against this tool.

`export-all` extracts every checksum-valid slot; `build` assembles a
fresh cart image from up to three songs (a "setlist" .sav for the
Everdrive); `wrap` turns a bare 5,376-byte song block (e.g. the ROM
demo, or makedemo.py output) into a shareable `.smdj`.

`.smdj` files are a single slot (header + data, 5,392 bytes) — share
them, back them up, or move songs between slots/carts. `import`
revalidates the checksum and creates the `.sav` (32 KB, `$FF`-filled)
if it doesn't exist yet, so you can prepare a cart image entirely
offline.
