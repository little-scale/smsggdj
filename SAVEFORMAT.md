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
fully exportable/importable.

## SMDJ4: compressed directory + heap

As of v0.30 the save format is **SMDJ4**. The whole SRAM image is one
self-describing structure — a **superblock**, a fixed **directory** of song
entries, and a **heap** of compressed song blobs — rather than the old
fixed-stride flat slots (SMDJ3, see *History*).

Why the change: the song block grew (52 phrases / 40 chains = 6,912 B), and
storing every song at full size would fit only a handful per cart. Instead each
song is **RLE-packed** into the heap, so a sparse song costs a fraction of its
size and many more fit. The cost is a decoder in every tool that reads a save;
the lever was worth pulling once the pools needed to grow. The on-cart codec is
`src/rle.asm` (cross-checked against `tools/rletest.py` / `tools/rle.js`).

```
offset   size   contents
$0000    32     superblock
$0020    1024   directory: 32 entries × 32 B
$0420    ...    heap: song blobs (RLE or store-raw), grows upward
```

`$0420` = 1056 = `SD4_HEAP` (the heap base). On a 32 KB cart the image spans
**two 16 KB SRAM banks** (`$FFFC` selects bank 0 = `$08` / bank 1 = `$0C`), and
the heap addresses them as one logical linear space; the ROM maps the right bank
per blob. 8/16 KB carts have no second bank.

### Superblock (32 B at `$0000`)

```
+$00   5   magic "SMDJ4"
+$05   1   version (1)
+$06   1   directory entry count (32)
+$07  25   reserved
```

### Directory entry (32 B; entry n at `$20 + n*32`)

```
+$00   1   valid: $A5 = used, anything else = free
+$01   1   raw flag: 1 = store-raw (blob is the verbatim 6,912 B), 0 = RLE
+$02   2   heap_off: blob start, little-endian, relative to the heap base ($0420)
+$04   2   blob_len: stored blob length, little-endian
+$06   2   checksum: 16-bit LE sum of the 6,912 *decompressed* song bytes
+$08   8   echo settings: mode, tap1, tap2, red1, red2, stereo, tsp1, tsp2
+$10   8   name: 8 chars (the song name shown on the FILES screen)
+$18   8   reserved
```

The directory is kept **packed** by the ROM: valid entries are contiguous
`0..count-1` (deleting a song shifts the rest down). The name and echo settings
travel **inside the entry**, so they're carried per-song, not in the blob.

### Heap

Each song is one blob: an **RLE stream** of the 6,912-byte song block, or a
verbatim copy if RLE didn't shrink it (`raw = 1` — random data hits this
store-raw floor and never expands). Blobs are allocated **no-straddle**: a blob
never crosses the 16 KB bank boundary, so the ROM sets `$FFFC` to the blob's
bank and reuses the flat codec with no bank-aware stream I/O. New saves append
after the highest blob. **Deleting a song compacts the heap** (`rle_compact`):
the surviving blobs are slid down in offset order to close the gap — including
pulling a blob across the bank boundary when room opens below it — and each
entry's `heap_off` is rewritten. So free space is always one contiguous region
at the top, with no stranded mid-heap holes.

### The 6,912-byte song block (the decompressed payload)

The contiguous live-RAM block, identical in both ROM flavors:

```
+$0000  wave_ram      256   8 waves × 32 B ($D0 | 15-minus-level per step; the
                            drawn shape — playback maps levels through the
                            log-DAC correction separately)
+$0100  phrase_pool   3328  52 phrases × 64 B (16 steps × note,instr,cmd,param)
+$0E00  chains        1280  40 chains × 32 B (16 × phrase#,transpose)
                            [all 52 phrases / 40 chains are fully usable. The CONT
                            handoff plays its bridge from a private RAM buffer, so
                            it touches no pool slot -- nothing here is overwritten
                            by a load.]
+$1300  song          512   128 rows × 4 chain numbers ($FF empty)
+$1500  instruments   256   16 × 16 B records [all 16 fully usable; the CONT
                            handoff plays its bridge instrument from a private
                            buffer, touching no slot.]
+$1600  tables        1024  16 × 64 B (16 rows × vol,pitch,cmd,param)
+$1A00  grooves       256   16 × 16 tick bytes
        (end          $1B00 = 6912)
```

The RLE codec works on **4-byte units** (1,728 units), a PackBits-style scheme.
Each run starts with a control byte:

- **bit 7 set** — *repeat* run: emit the next single 4-byte unit `(c & $7F) + 2`
  times (2..129).
- **bit 7 clear** — *literal* run: copy the next `(c & $7F) + 1` units verbatim
  (1..128).

All encoders (`src/rle.asm`, `tools/rletest.py`, `tools/rle.js`) agree on one
canonical decoder; random data falls back to the store-raw blob so the stream
can never expand past 6,912 B.

## Cart-size detection

`sram_detect` (at boot) probes `$8000` for RAM, then whether `$A000` mirrors it
(8 KB) or not (16 KB), then writes distinct markers to `$8000` in bank 0 and
bank 1 — if both persist independently the cart has a real second bank
(32 KB). This detects *live* RAM only; whether a flashcart **battery-backs** the
second bank is a separate question, confirmable only by a power-cycle test —
**confirmed on real hardware** (a Master Everdrive X7 on a PAL SMS1, both banks
persisted across power-off). Verify your own cart the same way before trusting
the second bank.

The detected size sets the **runtime heap capacity** (`sd4_cap`: 8K→`$2000`,
16K→`$4000`, 32K→`$8000`), which the save's capacity check and the FILES readout
both use — so a save is never placed past the real SRAM, and the readout shows
the true size. The no-straddle bank bump only applies on a 32 KB cart (the only
one with two banks); single-bank carts pack contiguously. Note the capacity
check reserves the worst-case 6912 B before packing (the packer writes straight
to SRAM, no scratch buffer), so the top ~7 KB of any cart isn't usable for a new
save — negligible on 32 KB, but it leaves an 8 KB cart room for only ~one song.

## OPTIONS config block

The machine config (colour scheme, sync mode, video, FM toggle, CONT, key
repeat) lives **outside** the SMDJ4 structure, at CPU `$BF60` (`CFG_ADDR`) in
bank 0 — file offset `$3F60` on a 16/32 KB image; on an 8 KB cart the window
mirrors, so it lands at `$1F60`. 10 bytes (v3, since v0.37):
`'C' 'F' pal_sel sync_mode vid_sel fm_on cont key_delay key_speed checksum`
(checksum = sum of the seven value bytes & `$FF`). `vid_sel`: `0` AUTO, `1`
PAL, `2` NTSC; `fm_on`: `0` off / `1` on; `cont`: `0` OFF / `1`–`4` =
T1/T2/T3/NO (the continuous-play carry channel); `key_delay` (1–60) and
`key_speed` (1–30) are the DAS cursor-repeat delay/interval in frames (OPTIONS
→ RDLY/RSPD). Written whenever you save a song, read at boot. **Legacy blocks**
are still accepted — the loader tries the checksum at each length in turn:
7-byte v1 (no `cont`/key-repeat, checksum of four at `+6`), then 8-byte v2 (no
key-repeat, checksum at `+7`), then v3.

> The config offset (`$3F60` = 16224) sits inside bank 0's heap range, so
> **bank-0 blob placement is capped below it**: a blob that would cross `$3F60`
> bumps to bank 1 on a 32 KB cart (this subsumes the no-straddle `$4000` bump)
> or reports SRAM FULL on a single-bank cart. Enforced by both the ROM
> (`rle_can_save` *and* `rle_compact` in `src/rle.asm` — compaction could
> otherwise pull a bank-1 blob down over the config) and `tools/smdj4.js
> buildSav` (covered by its self-test).

A song entry loads only when `valid == $A5` and the stored checksum matches the
decompressed block; SMSGGDJ refuses anything else.

## Tools

- **`tools/migrate.html`** — drop an old SMDJ3 `.sav`/`.smdj`; it expands every
  song to the 6,912-byte layout, RLE-packs it, and writes an SMDJ4 `.sav`
  (directory + heap) with a per-slot size table and a free-space meter. This is
  the path for carrying old saves forward.
- **`tools/savetool.html`** — drop an SMDJ4 image to view the directory (per-song
  name/size/checksum) and export each song as `.smdj4`. Fully client-side.
- **`tools/smdj4.js`** — the node-tested format library behind both
  (`expand`, `buildSav`/`readSav`, `wrapSmdj4`). Self-test:
  `node tools/smdj4.js` → `ALL PASS`.

## History

`SMDJ1` lacked wave_ram (5,120 data bytes). `SMDJ2` had 4 waves (5,248 B, stride
`$1500`). `SMDJ3` was the last **flat** format: 8 waves, 32 phrases / 32 chains
(5,376-byte block), stored verbatim in fixed `$1520`-stride slots (3 per 16 KB
bank, up to 6 on a 32 KB cart). `SMDJ4` replaces the flat slots with the
compressed directory + heap above and grows the pools to 52/40. Older images are
not loaded directly by SMDJ4 builds — migrate them with `tools/migrate.html`.
