# COMPRESSION.md — RLE save compression + larger pools (SMSGGDJ)

**Status: M1 IN PROGRESS (2026-06-26).** Ported from the genmddj design
(`~/Documents/genmddj/COMPRESSION.md`), where the codec + directory backend are
already built and **hardware-verified on the 68k**. This is the SMSGGDJ (Z80)
implementation spec.

**M1 measurement (done, `tools/rletest.py`):** the real `demo.smdj` block packs
**5,376 → 702 B (13.1 %)** → ~44 songs/32 KB (vs 6 today), ~90/64 KB. Per pool:
phrases 9 %, chains 3.8 %, song 2 %, tables 1 %; the dense pools (wave_ram 75 %,
instruments 100 %) don't compress but are tiny. Random data hits the store-raw
floor (never expands). **Ratio confirmed on real data.**

**M1 reference codecs (done):** `tools/rletest.py` (Python) and `tools/rle.js` (JS,
for the browser tools) — **cross-verified byte-for-byte** on the demo song + edge
cases (empty/zero → 55 B, random → store-raw +11 B), all round-tripping. Two
independent implementations agree, so they're the oracle the Z80 cart codec
(`src/rle.asm`, next) must match. **Verification status of the Z80 codec: built
clean + faithful transcription only — needs an in-emulator self-test run (I can't
run-test Z80 headlessly here).**

## 0. Goal (locked)

Two wins, delivered together:

1. **Larger pools** — phrases 32 → **52**, chains 32 → **40** (balanced split).
2. **More songs per cart** — replace the fixed numbered SRAM slots with a
   directory + packed heap, so sparse songs store at a fraction of their size.

RLE compresses **only the SRAM save image**. Work RAM, the engine, the editor,
and the shared `.smdj` block stay byte-identical — we compress on the way *into*
SRAM and decompress on the way *out*. Nothing real-time touches it.

## 1. The binding constraint: work RAM, not SRAM

The live song is **uncompressed in work RAM** — the engine walks
`phrase_pool`/`chains`/etc. directly every tick, no decode on the play path. So
**RLE cannot make the pools bigger**; the pool ceiling is pure free RAM:

- Free work RAM at 32/32 today: **2,109 B** (8 KB total, song block + state eat the rest).
- Cost: **65 B/phrase** (64 B pool + 1 B `phrase_plays`), **32 B/chain**.
- 52/40 spend: `20×65 + 8×32 = 1,556 B` → **~553 B free remaining**.
- ⚠️ **The Z80 stack lives in that free space** (it's not a separate allocation),
  so ~553 B is the real margin to protect. Measure peak stack before trusting it;
  don't grow the pools further without reclaiming RAM elsewhere.

RLE's role for the *pools* is only the **save side**: a 6,912 B song no longer
fits the old 5,408 B fixed slot (even a saturated song hits the store-raw floor at
6,912 B), so the directory/heap is what lets the grown song be stored at all.

## 2. The codec — 4-byte-unit RLE

**Operate on 4-byte units** (= one phrase row `note/instr/cmd/param`), not bytes.
An empty row is a single repeated unit, so the (huge) phrase pool of mostly-empty
rows collapses; byte-wise RLE would miss it (the empty row alternates every 2
bytes). This is the whole point — see genmddj §2 (66.9% byte → 8.5% unit).

**Stream format** (PackBits-style, canonical decode):

```
control byte c:
  bit7 = 1  -> repeat run : run = (c & 0x7F) + 2  (2..129), then 1 unit (4 bytes)
  bit7 = 0  -> literal run : n   = (c & 0x7F) + 1  (1..128), then n units
```

**Store-raw fallback.** If `compressed_len >= raw_len`, store raw and set a
per-song `raw` flag — never worse than the flat save.

**SMSGGDJ specifics (vs the genmddj 68k codec):**

- **Z80, byte-oriented, no alignment constraint** → genmddj's §3 odd-address fault
  and §5 odd-byte SRAM stride **do not apply**. SMSGGDJ SRAM is plain
  byte-addressable at `$8000–$BFFF`, banked via `$FFFC` (standard Sega mapper).
- **No staging buffer** (only ~553 B free RAM, vs genmddj's 28 KB gap): the live
  song is in work RAM (`$C000+`) and SRAM is at `$8000`, **both mapped at once**,
  so **pack source-RAM → SRAM directly** and **unpack SRAM → source-RAM directly**,
  streaming. Decide store-raw with a cheap length-sizing pass first (no buffer).
- **Confirm the empty phrase-row pattern** SMSGGDJ writes on blank (`song_init`)
  — it sets the achievable ratio (the §2 insight). Verify before writing asm.

## 3. New save format: SMDJ4

Bump the magic `SMDJ3` → `SMDJ4` (bigger pools + directory storage). Data block:

| offset | size | pool |
|---|---|---|
| `$0000` | 256 | wave_ram (8 × 32) |
| `$0100` | 3328 | **phrase_pool (52 × 64)** |
| `$0E00` | 1280 | **chains (40 × 32)** |
| `$1300` | 512 | song (128 × 4) |
| `$1500` | 256 | instruments (16 × 16) |
| `$1600` | 1024 | tables (16 × 64) |
| `$1A00` | 256 | grooves (16 × 16) |
| `$1B00` | — | **end → `SAVE_SIZE = 6912`** |

RLE unit count = `6912 / 4 = 1728`. `phrase_plays` grows to 52 B (runtime, not saved).

## 4. SRAM directory + heap

Replaces the fixed `sram_slot_base` map (`$8000 + n*$1520`) with a directory + a
packed heap, so capacity is elastic. Adapted from genmddj §4 (its odd-byte stride
dropped; SMSGGDJ adds **bank-awareness** instead).

```
SRAM (per 16 KB bank window $8000–$BFFF, $FFFC-switched):
  [config][DIRECTORY][heap →→→][free]
DIRECTORY: N entries x 16 B:
   +0 valid($A5) · +1 raw · +2 heap_offset(2) · +4 blob_len(2)
   +6 name(8) · +14 checksum(2, of the decompressed block)
HEAP: compressed (or raw) blobs, packed contiguous.
FREE = capacity - heap_end  -> the OPTIONS free meter
```

- **save**: gather block → `rle_pack` → store-raw fallback → checksum → find entry
  (name match → reuse, else first free) → refuse if `heap_end + len > capacity`
  ("SRAM FULL") → write blob + entry.
- **load**: find name → read blob → `raw ? copy : rle_unpack` → scatter → verify checksum.
- **delete**: free entry, **compact** the heap (shift later blobs, fix offsets).
- **Bank boundary**: on a 32 KB cart the heap spans two 16 KB banks (`$FFFC`); the
  allocator/heap I/O must cross the bank boundary cleanly. Open design point.
- Keep the existing OPTIONS **config block** (colour/sync/video, currently
  `CFG_ADDR $BF60`) — relocate if it collides with the directory.

## 5. Migration SMDJ3 → SMDJ4 (browser-side, not in-ROM)

Old saves are 5,376 B, 32/32, at the old offsets, in fixed slots. New build is
6,912 B, 52/40, in the directory. Pool offsets shift, so each pool must be
**expanded** into its new (shifted) slot, with the new phrase/chain entries
zero/`$FF`-filled. **This conversion lives in the browser, not the ROM** — the
ROM only reads the SMDJ4 directory and never has to understand the old layout
(keeps scarce bank-0 code out of it). Two browser deliverables:

- **`savetool.html` → v2.** The existing song-save tool gains a **directory +
  per-blob RLE** reader/writer for SMDJ4 (alongside its current fixed-slot SMDJ3
  reader, for *reading* old `.sav`s). It builds/unpacks SMDJ4 cart images and
  shows the directory + free-space meter.
- **A browser migration tool** (its own page, or a mode of `savetool.html`):
  drop an **SMDJ3** `.sav`/`.smdj`, it expands each song's pools into the 52/40
  layout, RLE-packs them, and emits an **SMDJ4** cart image (directory + heap).
  The reference RLE codec is shared with `rletest.py`/the ROM (one decoder, §2).

`.smdj` single-song files get a parallel v3→v4 bump (header notes the pool sizes
so a reader can tell them apart). Songs migrate by running them through the tool;
the ROM shows "OLD FMT"/ignores any stale SMDJ3 bytes it finds.

## 6. Milestones

- **M1 — Codec.** Z80 `rle_pack`/`rle_unpack` (4-byte unit, store-raw), streaming
  RAM↔SRAM. Validate first with `rletest.py` (SMSGGDJ `DATA_LEN=6912`/`UNIT=4`) on
  a real song to confirm the ratio, then the asm round-trips in-emulator.
- **M2 — Directory + heap, pools still 32/32.** Replace fixed slots; save (raw
  fallback + full-refusal), load, delete + compact; bank-aware heap. SMDJ3
  migration. **Ships "more songs per cart" on its own.**
- **M3 — Grow pools 52/40.** Bump `NUM_PHRASES`/`NUM_CHAINS`, re-layout the block
  (§3), update editor limits; the M2 storage already handles the bigger song.
- **M4 — Browser tools.** Update **`savetool.html` → v2** (read/write the SMDJ4
  directory + per-blob RLE; free-space meter), and build the **browser migration
  tool** (SMDJ3 → SMDJ4 expander + packer, §5). Both share the JS reference codec.
- **M5 — Docs + hardware.** Rewrite `SAVEFORMAT.md` (and reverse its "uncompressed
  by design" note); update `MANUAL.md`/`DESIGN.md`; re-verify save/load + the
  directory on the Everdrive X7 (PAL SMS1).

## 7. Files / references

- `src/engine.asm` — `song_save`/`song_load`/`sram_slot_base`/`sram_sum`/`sram_detect`
  (the fixed-slot layer the directory replaces); `NUM_PHRASES`/`NUM_CHAINS`/`SAVE_SIZE`.
- `SAVEFORMAT.md` — the current flat format being superseded.
- `~/Documents/genmddj/COMPRESSION.md` — the reference design (built + 68k-verified).
- `tools/rletest.py` (to be ported from genmddj) — measurement + reference codec.
