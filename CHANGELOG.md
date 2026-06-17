# Changelog

All notable, user-facing changes to **SMSGGDJ**. Dates are YYYY-MM-DD.
The git history has the full detail; this is the curated summary.

## v0.28 — unreleased

## v0.27 — 2026-06-17

### Changed
- **Version-stamped builds.** Release ROMs are named `smsggdj_<ver>.sms` / `.gg`,
  and the boot splash shows the git build hash beneath the version — so a stale
  flash is obvious at a glance.
- **LIVE chain swaps now quantize to the next bar.** Queueing a chain on the SONG
  screen in LIVE mode lands on the next 16-row phrase boundary, regardless of the
  current chain's length (previously it waited for the whole chain to finish). All
  tracks keep their row counters running while silent, so a chain queued onto a
  stopped track starts bar-aligned with the playing tracks.
- **LIVE mode starts silent.** Triggering from a stopped state in LIVE no longer
  fires the whole song — the clock starts with every track silent and only the
  cell you trigger plays, so you build the mix one track at a time.

### Fixed
- **`H` (hop) is now per-channel.** Ending a phrase early with `H` affected *all*
  tracks because the row counter was shared. Each track now keeps its own
  phrase-row position, so `H` ends only the phrase it's written on — tracks can
  run independent phrase lengths against the shared tempo/groove. (Tempo `T`,
  groove `G` and wait `W` remain global.)

## v0.26 — 2026-06-17

### Added
- **FM preset editor** (`tools/fmpatch.html`). Drop a built `.sms` ROM and edit
  its 8 custom FM presets in the browser — per-operator MUL/AR/DR/SL/RR/KSL/TL,
  feedback, waveforms, and the 5-char names — then download the patched ROM. It
  finds the `FMPRST` marker block, so it survives ROM-layout changes. Each preset
  has an **audition** button backed by a JS port of the **emu2413** YM2413 core
  (Okazaki, MIT) — the same register-level model chip-music players use — so the
  envelopes, feedback, modulation and waveforms match the chip. No toolchain.
- **FM custom presets.** FM instruments gain a **PRST** field: `OFF` uses the
  ROM **PROG** patch (unchanged), `1`–`8` select one of 8 ROM-baked custom
  timbres (LEAD, EPNO, SBASS, BELL, BRASS, PAD, PLUCK, SINE) loaded into the
  YM2413's user patch. Because the chip has a single user patch, only one
  custom timbre sounds at a time (most recent trigger wins); `Y` still forces a
  ROM patch. The presets live in a marker-delimited ROM block (`FMPRST`) so a
  browser tool can rewrite them; the baked values are a tunable starting set.
- **FM drums (FMDRM)** — a new instrument type driving the YM2413's rhythm
  mode: the chip's 5 fixed percussion voices (bass drum, snare, tom, cymbal,
  hi-hat). It's a kit — one instrument, the **note picks the drum** (C/C♯/D/D♯/E
  for BD/SD/TT/TC/HH, repeating every 5 semitones so any octave works). **VOL**
  sets the level, **HLD** the length (`F` = ring). It rides on spare FM voices,
  so it costs none of the 4 tracks and plays alongside melodic FM. Needs the FM
  Sound Unit (**OPTIONS → FM**); SMS only.
- **FM honours tables (TBL/TBS) and the `X` command.** An FM instrument can now
  run a table: its volume column rewrites the FM channel level live, and its
  pitch column arps the note by re-keying the FM voice. `X` (per-note volume)
  also works on FM voices. A flat/blank table holds the note steady — it
  re-keys only when the pitch offset actually changes, so it no longer
  retriggers every step.
- **FM transpose + program command.** FM instruments now expose **TSP**
  (transpose), and the new **`Y`** command sets a note's FM program/patch
  (1–15), overriding the instrument's PROG one-shot (like `B` for wavetables).
- **FM synthesis (YM2413 / SMS FM Sound Unit)** — a new **FM** instrument type
  (5th type) plays the chip's 15 ROM patches. Pick a **PROG** (patch 1–15) and
  **VOL**; notes play in tune from a region F-number table on the FM channel
  matching the track. **HLD** sets the note length (`F` = ring per the patch
  envelope; `1`–`E` = auto key-off). Enable it with **OPTIONS → FM: ON**
  (persisted) — FM sums with the PSG on the built-in/FM-unit hardware and
  SMSPlus; emulators that mux `$F2` (e.g. Emulicious) play FM in place of PSG.
  Default OFF, so PSG-only songs are unaffected. SMS only.

### Changed
- **PHRASE column spacing** — the instrument (`I`) and command columns sit one
  tile right of the `NOTE` field on both SMS and Game Gear, so the header reads
  `NOTE  I  CMD` with room to breathe.

### Fixed
- **WAV instruments: HLD is editable again.** The cursor was skipping the HLD
  field (a leftover from the AHD rework moving WAV's length onto it), so it
  showed but couldn't be changed.

## v0.25 — 2026-06-16

### Added
- **`X` command — per-note volume.** `Xxx` sets a triggered note's volume
  (`0`–`F`, the AHD peak the attack ramps to) — the per-note accent that went
  missing when `E` became ATK/DCY. The Ableton converter's velocity option now
  maps to `X` (it was wrongly using `V` = vibrato).
- **VIDEO choice in OPTIONS** (SMS). The `VID` field is now editable —
  **AUTO** (follow region auto-detection, the default), **PAL**, or **NTSC** —
  letting you override the detected region's tuning/timing. The choice persists
  in the SRAM config block (alongside colour/sync) and re-tunes the note tables
  and sample feed live. (Game Gear stays NTSC.)
- **Note-advanced tables.** Set an instrument's **TBS** to **`0`** (shown `N`)
  and its table steps **one row per triggered note** instead of per tick. The
  row persists across notes (restarting only when the table # is reassigned)
  and `H` loops as usual, so a short table running against a longer phrase gives
  arpeggios, polymeter, and phrase↔table interplay. TBS `1`–`F` are unchanged.
- **SMP transpose** — the **TSP** field is back on SMP instruments. Because the
  note selects the sample, an instrument transpose of `+1`/`+2`/`+3` auditions
  adjacent samples in the pool — handy when kicks/snares/etc. are grouped in
  banks. (The engine already applied it; it just had no field.)
- **Ableton → song converter** (`tools/als2smdj.html`). Drop a Live Set and the
  first 3 MIDI tracks' Session clips convert to a `.smdj`: each clip becomes
  phrases (cut to a 16th-note grid; long clips spill across phrases), a track's
  clips fill its chain, identical phrases de-dup. Highest note wins, out-of-range
  notes octave-fold in, note-offs are dropped; optional velocity→`X`. Loads via
  `savetool.html`.

### Changed
- **Saved colour scheme now applies before the boot splash** — `config_load`
  runs ahead of the splash, so the logo renders in your chosen palette instead
  of flashing the default first.

### Fixed
- **Game Gear PHRASE spacing.** The instrument (`I`) and command columns shift
  one tile right, opening a gap after the `NOTE` field so the header reads
  `NOTE  I  CMD` instead of a crammed `NOTEI`. SMS layout unchanged.
- Restoring the persisted **sync mode** at boot no longer gets clobbered by the
  boot default (a side effect of moving config load before the splash).
- **Game Gear PHRASE/CHAIN headers.** The phrase/chain number, track tag, and
  column headers were pinned to fixed rows that only matched the SMS layout, so
  on GG the number sat a row low and the `NOTE`/`I`/`CMD` (and `PHR`/`TSP`)
  headers were drawn inside the grid and never showed. They now use the layout
  constants, so the number/tag sit on the name row and the headers on the row
  above the grid (SMS layout unchanged).

## v0.24 — 2026-06-15

### Added
- **Ableton Link sync** via the new companion bridge
  [smsggdj-link-esp32](https://github.com/little-scale/smsggdj-link-esp32) — an
  ESP32-C3 joins a Link session over WiFi and drives `SYNC: IN`, so the tracker
  follows Ableton Live's tempo and transport. Verified on real hardware; relies
  on the flat-groove-6 lock below. Wiring in HARDWARE.md.

### Changed
- **Instrument envelopes are now AHD (attack / hold / decay).** The old
  VOL + ENV(UP/DN/OFF) + SPD + LEN cluster is replaced by **VOL** (peak/hold
  level) + **ATK** + **HLD** + **DCY** — all nibbles. ATK/DCY are ramp rates
  (ticks per volume step, `0` = instant; full ramp = VOL × rate); HLD is
  `0` = none, `1`–`E` = ×2 ticks, **`F` = hold forever**. `E xy` re-slopes the
  ramps live (ATK = x, DCY = y); `K` still hard-cuts. New instruments default
  to ATK 0 / HLD 1 / DCY 3. WAV uses HLD as its length (its volume gates the
  DAC, so ramps are inaudible); SMP is unaffected. The envelope engine moved to
  a bank-1 state machine.
- **SYNC IN** now locks the engine to a flat **groove 6** (24 PPQN) and ignores
  the song's stored groove (and the `W` command) while following, so a song
  stays beat-aligned with the master at any tempo regardless of its groove.
  Non-destructive — the stored groove returns when you leave SYNC IN.

## v0.23 — 2026-06-15

### Added
- **OPTIONS persist**: colour scheme + sync mode save to a 5-byte config block
  in SRAM (written on song-save, restored at boot). Works on 8/16/32 KB carts
  (8 KB lands it via the window mirror). `savetool.html` can read/write it.
- **Colour palettes are user-patchable** — OPTIONS COLR is now just palettes
  **0–7** (names dropped); recolour any of the 8 bg/fg pairs in the new
  `tools/palette.html` (browser, finds the `PAL8` block, exports a patched ROM).
- **32 KB SRAM detection** — boots probe for a distinct second 16 KB bank
  (`$FFFC` bit 2); carts that have it expose **6 save slots** instead of 3
  (3 per bank). Degrades to 3 (16 KB) or 1 (8 KB) everywhere else. The
  OPTIONS SRAM readout now shows 8K / 16K / 32K. Confirmed end-to-end on
  real hardware (Master Everdrive X7 on a PAL SMS1 — slot 4 persists across
  power-off).
- `savetool.py` and `savetool.html` handle 6 slots / the second bank; the
  browser tool gains an **8 / 16 / 32 KB cart-size selector** (sets the slot
  count and output `.sav` size) and a **song viewer** — click a slot to
  decode it (song map, chains, phrases as note/cmd grids, instruments, echo,
  grooves) in human-readable form.

### Changed
- ROM outputs renamed `smsdj.sms` / `smsdj.gg` → **`smsggdj.sms` / `smsggdj.gg`**
  (and `smsdj_sample.py` → `smsggdj_sample.py`) to match the project name.
- `I` command now indexes its play-mask by a **per-phrase play count** (how
  many times that phrase has played this song, accumulating across the whole
  arrangement) instead of the per-track chain-repeat count — so a phrase
  varies consistently across its plays. Variation without cloning.

## v0.22 — 2026-06-15

### Added
- Sample **4× speed** (`S03` / RATE 4X) — two octaves up, plays every 4th
  sample. Same flat-CPU decimation as 2×.

### Changed
- Boot opens a blank song. Removed the DEMO build flavor (the `-demo` ROMs and
  boot auto-play); the demo song is still baked in and loads from the PROJECT
  screen (DEMO).

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
System and Game Gear, one source tree building two ROMs (`smsggdj.sms` /
`smsggdj.gg`).

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
