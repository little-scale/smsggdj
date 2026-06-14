# Changelog

All notable, user-facing changes to **SMSGGDJ**. Dates are YYYY-MM-DD.
The git history has the full detail; this is the curated summary.

## v0.22 — unreleased

### Added
- Sample **4× speed** (`S03` / RATE 4X) — two octaves up, plays every 4th
  sample. Same flat-CPU decimation as 2×.

### Fixed
- Sample 2x speed (`S01` / RATE 2X) no longer slows the whole song. It now
  decimates the source (plays every other sample) for one DAC write per tick,
  instead of feeding two nibbles per interrupt and overrunning the per-frame
  CPU budget.

## v0.21 — 2026-06-14

### Added
- **Echo** — a tempo-synced delay built into the engine (ECHO screen, 2+Down
  from INSTR). Copies T1 onto T2 (and optionally T3), with per-tap delay in
  rows, volume falloff, per-tap transpose, and Game Gear stereo ping-pong.
- **`B` command** — set a note's wavetable (0–7), overriding the instrument's
  wave for that note.
- **Bundled demo song** — both ROMs boot it; the `-demo` builds auto-play it
  (a committed `songs/demo.smdj`, swappable).
- **INSTR field reference** and per-type field notes in the manual; a
  `CHANGELOG.md`.

### Changed
- **Tempo is the groove.** TMPO (PROJECT) is now a live readout derived from
  the active groove and steps it tick-by-tick through the achievable BPMs,
  shifting the whole groove together so swing is preserved (no more drift or
  flattening).
- **`I` command** reworked into an 8-bit play mask: on repeat N the note plays
  if bit (N mod 8) is set (`IFF` always, `I00` never, `I55`/`IAA` odd/even,
  `I0F`/`IF0` first/last four of eight).
- **SMP instruments** show only INST/TYPE/RATE (samples ignore the envelope,
  length, pitch mods, volume and tables).
- **WAV instruments** drop ENV/SPD and tables, keep LEN.
- Inserting a command on an empty cell repeats the **last command** used
  instead of always defaulting to `K`.
- Splash: removed the credit band, raised two rows, version → V0.21.

### Fixed
- `K` now cuts a playing sample/wavetable owned by that channel.
- Stereo echo recenters T2/T3 when switched off (no stuck panning).
- PHRASE column headers align with their data.
- `make run` Makefile target (a stray `;` ran the comment as a recipe).

## v0.2

First public release — a complete LSDJ-inspired tracker for the Sega Master
System and Game Gear, one source tree building two ROMs (`smsdj.sms` /
`smsdj.gg`).

### Added
- **Sound:** SN76489 PSG — 3 tone channels + noise, 4-bit PCM samples and 8
  drawn wavetables via the volume-register DAC trick, Game Gear stereo.
- **Screens:** SONG, CHAIN, PHRASE, INSTR, TABLE, GROOVE, WAVE, OPTIONS,
  PROJECT, navigated on a 2-D map (hold 2 + D-pad).
- **Engine:** per-tick sequencer with grooves (swing), instruments
  (envelope, length, transpose, sweep, vibrato, tremolo, tables), and the
  command set (A/C/D/E/F/G/H/I/K/L/M/N/O/P/R/S/T/V/W).
- **Editing:** LSDJ-style two-button control scheme, DAS key repeat, block
  select/copy/paste, chain/phrase cloning (SLIM/DEEP).
- **Live mode** for performance; **native console sync** over controller
  port 2 (OUT/PULSE/IN/OFF).
- **Game Gear build (GGDJ):** 20×18 window layout, real stereo, NTSC tuning.
- **128 KB cartridge** with a self-describing sample pool baked from
  `samples/pool.bin` (or converted from WAVs).
- **Tools:** `patcher.html` (browser sample patcher), `savetool` (CLI +
  browser song/save manager), plus the Python build pipeline.
- Colour-scheme presets, region auto-detect (PAL/NTSC), SRAM save/load.
