# SMSGGDJ — an LSDJ-inspired tracker for the Sega Master System & Game Gear
**Design document v0.2 — 2026-06-11**

Target: a single ROM that runs on real SMS hardware (via flashcart) and in emulators.
Sound: SN76489 PSG only (including 4-bit PCM on it — see §10). CPU: Z80 @ 3.546893 MHz (PAL, default) / 3.579545 MHz (NTSC).

Changes in v0.2:
- PAL **and** NTSC support; PAL is the default assumption, auto-detected at boot with user override (§5.1).
- Optional **sample channel**: 4-bit PCM via the SN76489 volume-register DAC trick, plus a PC-side sample conversion tool (§10, §14).
- **MIDI clock sync (slave)** on controller port 2 — responds to MIDI Start/Stop/Continue/Clock (§11). PAUSE demoted to a secondary control.
- ROM moves from 48 KB flat to the standard Sega mapper (128 KB) to hold sample data. *(Done post-v0.2.)*
- Confirmed decisions: double-tap-1 deep-edit jump; CH3-steal policy for pitched noise.

Post-v0.2 addenda (implemented):
- **Wavetable mode**: WAV instrument type + WAVE editor screen — 8 user-drawn waves played through the T3 volume DAC via a phase accumulator (§10.6). Waves save with the song (SMDJ3).
- **Block select/copy/cut/paste** on the grid screens (§3).
- **LIVE mode** (§5.4): per-track looping chains with quantized swaps, queued from the SONG screen.
- **128 KB mapper move**: 8 banks, sample pool in banks 2-7 with a self-describing directory (§10.3) — the contract for **tools/patcher.html**, a single-file browser patcher: drop a built ROM + sounds (any decodable format), trim/gain/tanh/normalize/gate/fade per sample, audition the bit-exact DAC render, and download a patched ROM — no toolchain needed.
- **GGDJ**, the native Game Gear build (§15): same tree, `make` emits `smsggdj.sms` + `smsggdj.gg`.
- **8 user waves** (up from 4), booting as the 8 stamp presets; save format SMDJ3.
- **Native sync** replaces the MIDI-adapter plan: OUT/PULSE/IN/OFF on controller port 2 — SMSGGDJ↔SMSGGDJ tick-counter sync plus Volca/PO pulse out (§11). MIDI itself moves to v2.

---

## 1. Hardware constraints that drive the design

| Resource | Reality | Design consequence |
|---|---|---|
| SN76489 | 3 square-wave channels + 1 noise channel. Per channel: 10-bit tone period, 4-bit attenuation (2 dB steps, 0xF = silent). No duty cycle, no waveform, no hardware envelope, no panning (SMS PSG is mono). | All timbre comes from *software macros*: volume envelopes, arpeggios, pitch effects, retriggers, noise-mode switching. Instruments are macro containers, not waveform descriptions. |
| PSG DC-offset quirk | On the Sega VDP-integrated SN76489, tone value **1** stops the flip-flop: the channel outputs a DC level equal to its volume setting. | The volume register becomes a 4-bit (logarithmic) DAC → optional PCM sample channel (§10). |
| Noise channel | 4-bit register: white/periodic mode, rate = clk/512, clk/1024, clk/2048, or **tone-3 period**. Periodic noise = 1/15-duty pulse ≈ tone 4 octaves down. | "Pitched noise" and the classic **periodic-noise bass** trick are first-class instrument modes, with an explicit CH3-stealing policy (confirmed). |
| Tone range & tuning | freq = clk / (32 × period), period 1–1023 → lowest tone ≈ 109 Hz (≈A2). PSG clock is region-dependent: same period plays ~16 cents sharper on NTSC than PAL. | Tone channels cover ~A2–B7. Bass below A2 only via periodic noise (down ~3.5 octaves further). **Two region-specific note tables in ROM**, selected by the VIDEO setting (§5.1). |
| Z80 3.55/3.58 MHz | ~70,938 cycles/frame PAL, ~59,736 NTSC. No mul/div. | Tick engine + lookup tables for everything, fixed cycle budget per subsystem. PAL (the default) has ~19 % more cycles per frame — budgets are set against the tighter NTSC frame. |
| RAM | 8 KB internal (0xC000–0xDFFF). Optional battery cart SRAM 8–32 KB at 0x8000–0xBFFF (Everdrive etc.). | Two data tiers: baseline song fits in ~6 KB internal RAM; if SRAM is detected, song lives there (bigger limits + battery save). |
| Slot-2 sharing | Cart SRAM and ROM banks both map at 0x8000–0xBFFF, selected by mapper reg 0xFFFC. | Sample data (ROM) and song data (SRAM) contend for slot 2 → samples stream through a small internal-RAM ring buffer (§10.3). |
| VDP | Mode 4, 256×192, 32×24 tile grid, 2 × 16-color palettes, per-tile palette-select bit; line-interrupt counter (active display only). | Text UI on 8×8 font tiles. Cursor/playhead = palette-bit flip (no redraws). Line IRQs drive sample playback. VRAM writes budgeted with a dirty-row queue. |
| Input | D-pad + buttons **1** and **2** only. PAUSE is wired to NMI (edge-triggered, state not readable). | One fewer button than the Game Boy. All primary functions live on D-pad + 1 + 2; PAUSE is a convenience alias only (works even if a clone/handheld lacks it). |
| Controller port 2 | 5 readable pins (Up/Down/Left/Right/TL) + TH; TR and TH drivable as *outputs* via port 0x3F. No interrupt capability on these pins. | Enough for native master/slave sync: a 2-bit tick counter out/in on TR+TH, plus Volca-style pulse out (§11). Raw 31,250-baud MIDI bit-banging is not viable alongside a running tracker. |
| Video timing | 50/60 Hz is fixed by the console's hardware (crystal + VDP); software cannot switch it. | "PAL/NTSC support" = the *timing engine* adapts (tick rate, BPM math, sample cadence), not the video output. Auto-detect + override, §5.1. |
| ROM | Standard Sega mapper, header at 0x7FF0 ("TMR SEGA") required by export BIOS. | 128 KB ROM: 3 fixed/banked code+table pages, rest = sample pool banks. |

Explicitly **out of scope**: FM (YM2413) and any other expansion audio, MIDI *output* (parked for v2). *(Game Gear stereo and a native GG build joined the scope post-v0.2 — §15.)*

---

## 2. Song data model (LSDJ hierarchy)

```
SONG  →  CHAIN  →  PHRASE  →  notes + INSTRUMENT refs + commands
                              INSTRUMENT → optional TABLE (macro sequence)
GROOVE tables control tick timing globally and per-command
```

Four tracks: **T1, T2, T3** (tone) and **NO** (noise). Samples don't add a fifth track — they are an instrument type placed on a tone track (default T3, §10.2).

### Structure sizes and RAM budget

| Structure | Per-unit layout | Baseline (8 KB internal) | Extended (≥8 KB cart SRAM) |
|---|---|---|---|
| Song | 4 tracks × rows of chain numbers (1 B) | 128 rows = 512 B | 256 rows |
| Chains | 16 steps × (phrase #, transpose) = 32 B | 32 chains = 1 KB | 64 |
| Phrases | 16 steps × (note 1 B, instr 1 B, cmd 1 B, param 1 B) = 64 B | 48 phrases = 3 KB | 128 |
| Instruments | 16 B fixed record | 16 = 256 B | 32 |
| Tables | 16 rows × (vol, pitch, cmd, param) = 64 B | 16 = 1 KB | 32 |
| Grooves | 16 ticks × 1 B | 16 = 256 B | 16 |
| **Song data total** | | **≈ 6.0 KB** | ≈ 16 KB |
| Engine + UI state | channel state ×4, cursor stack, clipboard, key repeat, MIDI sync state | ≈ 1.3 KB | (internal RAM) |
| Sample ring buffer | 256 B page-aligned (§10.3) | only allocated in SRAM tier* | 256 B internal |
| Stack | | 256 B | (internal RAM) |

\* In the baseline (no SRAM) configuration slot 2 is free for ROM banks, so samples are read straight from ROM and no ring buffer is needed — the two configurations each fit naturally.

Empty slots use 0xFF sentinels. A "blocks free" counter is shown on the PROJECT screen, like LSDJ.

---

## 3. Control input

Only D-pad + 1 + 2; PAUSE is auxiliary. Button 1 ≈ LSDJ's A (edit), button 2 ≈ LSDJ's B + SELECT combined (back *and* modifier).

| Input | Action |
|---|---|
| D-pad | Move cursor (with key-repeat) |
| **1** tap | On empty step: insert note/value (repeats last entered). On PROJECT/menu: activate |
| **1** hold + D-pad | Edit value under cursor — left/right = small step (±1 semitone / ±1), up/down = big step (±octave / ±0x10) |
| **1** double-tap | Paste when a clipboard is armed for this screen. Otherwise on an **empty** SONG/CHAIN/PHRASE cell = mint the next **free** (blank) chain/phrase/instrument; on a **populated** SONG cell = **clone** that chain, on a populated CHAIN phrase cell = clone that phrase, into the next free slot (no free slot → cursor flashes, no-op) |
| **2** tap | Back: PHRASE → CHAIN → SONG (pops the navigation stack) |
| **2** hold + D-pad | Navigate the screen map (LSDJ SELECT+dpad equivalent) |
| **2** held + **1** tap | **Play/stop** (transport — primary control; 2 is the "project" modifier: navigation and transport). Context-sensitive: SONG screen = play song from cursor row; CHAIN/PHRASE = loop that chain/phrase |
| **1** held + **2** tap | Cut (delete the field into the clipboard) |
| **1** held + **2** long-hold (~⅓ s) | **Block SELECT** (SONG/CHAIN/PHRASE/TABLE): anchors at the cursor. D-pad extends the box; **1** tap = copy, **1** held + **2** = cut, **2** alone = cancel. Paste = double-tap-1: rows anchor at the cursor, columns stay where they were cut (type-safe). A short 2-tap while holding 1 stays cut-field — cut fires on 2's release on these screens. |
| **PAUSE** (NMI) | Alias for play/stop. Double-press = panic (silence all channels, abort sample, re-arm sync) |
| Track mute/solo | *Parked — gesture TBD.* The header row is labels only; the cursor never leaves the grid. (In LIVE mode, single tracks stop via the transport gesture on the playing cell, or a queued empty cell.) |

No timing disambiguation is needed: the button already held when the other arrives selects the action (1 held + 2 = cut, 2 held + 1 = transport), and a lone 1 press inserts instantly. Only paste uses a window (double-tap, ~0.3 s).

PAUSE generates an NMI whose handler only sets a flag — it is never *required*, so the tracker remains fully usable on hardware without a working PAUSE button.

---

## 4. GUI layout and screens

256×192 = 32×24 characters. Custom 8×8 font (hex digits get heavy use; design them first). Palette 0 = normal text, palette 1 = inverted (cursor, playhead row, selection) via the tilemap palette bit.

Persistent chrome:
- **Top bar (rows 0–1):** screen name, song title, BPM (derived from groove + tick source), play state, sync status (`INT 50` / `INT 60` / `MIDI` + clock-activity dot), current position `SS:CC:PP`.
- **Bottom bar:** removed — the grid gets the rows; the screen map indicator lives in the right column.
- **Right column (cols 27–31):** 4 channel activity meters (current attenuation as a bar; sample-playback glyph on the sample channel, steal glyph on T3) + current octave + current instrument number.

Screen map (navigated with 2+D-pad):

```
[OPTIONS] [PROJECT]          [WAVE]
[SONG]  [CHAIN]  [PHRASE]  [INSTR]  [TABLE]
          [GROOVE]            [ECHO]
```

(OPTIONS and PROJECT link left/right along the top row.)

The map is drawn as a mini-indicator in the top-right of each screen
(SMS: far-right margin; GG: the free right columns, on every screen but
SONG and WAVE, redrawn each frame since the GG row-wipe reaches there).

| Screen | Contents |
|---|---|
| **SONG** | 4 columns of chain numbers, 16 visible rows (scrolls), playhead per track, track mute/solo headers |
| **CHAIN** | 16 rows × (phrase #, transpose ±semitones) |
| **PHRASE** | 16 rows × (note, instrument, command, param). Noise track shows noise pitch/preset names; sample instruments show sample names |
| **INSTR** | All parameters of one instrument (form layout, §6) |
| **TABLE** | 16 rows × (vol, pitch, cmd+param) with tick-speed field and loop via `H` command |
| **GROOVE** | 16 tick values, live BPM readout (uses active tick rate, §5.1) |
| **ECHO** | delay/echo of T1 onto T2/T3 (below INSTR): MODE off/T2/T2+T3, TAP1/TAP2 (rows, groove-scaled), RD1/RD2 (volume falloff), STER (GG ping-pong), TSP1/TSP2 (per-tap transpose). A once-per-tick engine post-pass reads a 64-tick ring of T1's output |
| **OPTIONS** | The machine/rig page — the shape of the future persisted config block: **VIDEO: AUTO/PAL/NTSC**, SRAM readout, **SYNC: OUT/PULSE/IN/OFF**, **COLR** (8 palettes 0-7, patchable via tools/palette.html), **CLONE: SLIM/DEEP** (§12) |
| **PROJECT** | Song name, default groove, **NEW** (two-press arm/confirm blank song), **DEMO** (two-press load of the ROM demo song), save/load/erase, clone mode, prelisten, key-repeat speed, **VIDEO: AUTO/PAL/NTSC**, **SYNC: OUT/PULSE/IN/OFF** (default OFF, §11), **MODE: SONG/LIVE** (§5.4), **TSP** (global transpose ±24, applied at note trigger; sample slots exempt), **COLR** (UI palette 0-7), **SMP CH: T1/T2/T3/OFF**, blocks free, version |

Rendering: dirty-row queue, VBlank flushes up to 4 rows (≈256 bytes VRAM) per frame. While a sample is playing, UI flushes move into active display at the VDP-safe write spacing (§10.4) and throttle to 2 rows/frame. No sprites required.

---

## 5. Sound engine

### 5.1 Timing, PAL/NTSC

The engine tick is decoupled from its **tick source**:

- **INTERNAL** (default): one tick per VBlank — 50 Hz on PAL, 60 Hz on NTSC.
- **MIDI SLAVE**: ticks are driven by incoming MIDI clocks (§11); VBlank still drives UI/meters.

Region handling:
- **Auto-detect at boot** (count scanlines / time VBlank-to-VBlank); the effective region shows on the OPTIONS **VIDEO** field.
- **OPTIONS → VIDEO: AUTO / PAL / NTSC** — AUTO follows detection (default); PAL/NTSC force the timing/tuning math for modded 50/60 Hz consoles or misreporting emulators. When detection is ambiguous, **PAL is assumed** (project default). The choice persists in the SRAM config block (alongside colour/sync) and re-points the note/wave tables + sample budget live; Game Gear is NTSC-only.
- The setting governs *timing and tuning math* (refresh rate is fixed by the console): BPM display, the `T` tempo command's BPM→groove conversion, groove BPM readouts, sample-cadence constants, **and the note table**. Grooves are stored in ticks, so a song authored at PAL 50 Hz runs ~20 % faster on NTSC; the `T` command always re-derives ticks from BPM at the *active* rate, so `T`-driven songs stay tempo-true across regions.
- **Region tuning:** the PSG divides the system clock, which differs by region (3.546893 MHz PAL vs 3.579545 MHz NTSC) — the same period value sounds **~15.9 cents sharper on NTSC**. Two complete note-period tables live in ROM, each computed for A=440 against its own clock, selected by the VIDEO setting at boot. This also covers everything derived from tone periods: pitched/periodic-noise bass (driven by T3's divider) and finetune deltas. Residual region differences are only quantization (10-bit periods round differently per region, worst in the top octave) and the sample channel's fixed cadence (~12 cents, §10.4).
- Default groove `6,6` = 125 BPM at 50 Hz (150 at 60 Hz), 4 rows per beat.

### 5.2 Per-tick pipeline

Per tick, per channel (fixed order, deterministic):

1. **Groove counter** — on expiry, advance phrase row; read note/instr/cmd; apply per-step command.
2. **Table tick** (at table speed) — volume column, pitch column, table command.
3. **Software AHD envelope** — attack 0→VOL, hold at VOL, decay VOL→0.
4. **Pitch effects** — slide, tone-portamento, vibrato (ROM LFO tables), detune.
5. **Final write** — note + transposes → ROM note table (10-bit period) + finetune; clamp; write PSG only on change (shadow registers, `OUT (0x7F)`).

Engine budget: **≤6,000 cycles/tick (~10 % of the NTSC frame)** worst case.

### 5.3 Noise/CH3 coupling *(confirmed)*

When a noise instrument uses *pitched* mode, the engine writes the noise pitch to tone-3's period and mutes T3, **only if** the song setting `NOI MODE = STEAL` is on (default). With `FREE`, pitched noise falls back to the nearest fixed rate and T3 stays playable. Warning glyph on T3's meter when stolen. Sample playback adds one more claimant on its host channel — arbitration in §10.2.

### 5.4 Playback modes

Play song from row / loop chain / loop phrase (transport context, §3); **prelisten** (notes audition on entry, PROJECT toggle).

**Song-column semantics** (LSDJ-style, settled post-v0.2): starting playback, each track enters at the first populated cell at or below the start row — a column with nothing there does not play. An **empty cell ends the column**: the track immediately loops to the column's top (its first populated cell). A populated cell holding an **empty chain** is one deliberate rest row. Columns loop independently — equal spans stay locked, unequal spans are polymetric.

**LIVE mode** (PROJECT → `PLAY: SONG/LIVE`, implemented post-v0.2): the song grid becomes a bank of loops — each track's chain repeats instead of advancing down the song. On the SONG screen while playing, the transport gesture (2H+1) *queues* the cell under the cursor onto its track; the swap lands when that track's current chain finishes (LSDJ-style quantize), shown by a triangle marker beside the queued cell. Queueing an empty cell is a quantized track stop; a queued chain on a silent track starts at the next phrase boundary. the transport gesture on the cell that is *already playing* kills that track instantly (starting the playing chain = stopping it); **PAUSE is the global stop**. Tracks at different chain lengths run polymetrically, exactly as in song mode.

---

## 6. Instruments — all parameters

16 bytes each. Four types. Every parameter is hex-editable in a form layout.

### Common to all types
| Param | Range | Meaning |
|---|---|---|
| TYPE | TONE / NOISE / KIT / SMP | |
| NAME | 5 chars | shown in PHRASE column hint |
| VOL | 0–F | peak / hold volume (F = loudest) |
| ATK | 0–F | attack: ticks per volume step on the way up (0 = instant). Full ramp = VOL × ATK ticks |
| HLD | 0–F | hold at VOL: 0 = none, 1–E = nibble × 2 ticks, **F = ∞** (sustain until retrigger / `K`) |
| DCY | 0–F | decay: ticks per volume step on the way down (0 = instant cut at end of hold) |
| TBL | 0–1F / -- | table assignment |
| TBL SPD | 0–F | ticks per table row; **0 (shown `N`) = advance one row per triggered note** instead of per tick |
| TSP | ±24 | semitone transpose |

### TONE
| Param | Range | Meaning |
|---|---|---|
| FINE | ±F | finetune in raw period units |
| VIB TYPE / SPD / DEP / DLY | OFF/TRI/SAW/SQR, 0–F each | LFO shape, speed, depth, onset delay |
| PORTA | 0–F | default tone-portamento speed (`L` command overrides) |

### NOISE
| Param | Range | Meaning |
|---|---|---|
| MODE | WHITE / PERIODIC | LFSR feedback mode |
| RATE | F0 / F1 / F2 / PITCHED | clk/512, /1024, /2048, or CH3-period-driven |
| (PITCHED) | — | note column tracks pitch via T3 divider. PERIODIC+PITCHED = **bass instrument** |

### KIT (drum kit)
| Param | Range | Meaning |
|---|---|---|
| SLOT 0–B | preset # | maps each note in an octave to a ROM-defined drum preset (periodic-noise kick drops, white-burst snares, tick hats, tone-drop toms) — free, no user tables consumed |

### SMP (sample) — new in v0.2 (RATE added post-v0.2)
| Param | Range | Meaning |
|---|---|---|
| MAP | SINGLE / KIT | SINGLE: note column ignored (or selects nothing), plays SAMPLE; KIT: each note in an octave maps to a sample slot |
| SAMPLE | pool slot # | which sample (SINGLE mode) |
| VOL OFS | 0–7 | software attenuation added to every nibble at ring-refill time (2 dB steps — free at playback time, §10.3) |
| LOOP | ON/OFF | loop sample to end of note |
| ENV/TBL | — | tables and the AHD envelope do **not** run during sample playback v1 (volume is the DAC); `K` still cuts |

Notes on SMP: playback rate is fixed (§10.4); pitched sample playback via phase accumulator is a v2 stretch. The note table maps to sample slots in KIT mode, mirroring the KIT type.

### WAV (wavetable) — post-v0.2 addendum
| Param | Range | Meaning |
|---|---|---|
| WAVE | 0–3 | which user-drawn wave plays (§10.6) |

Common params apply; the host channel's volume/envelope *gate* the wave (volume 0 stops it) rather than scaling the DAC, so a WAV instrument only uses **HLD** as its length (ATK/DCY are inaudible through the gate). The note column is pitched normally — wavetables are melodic instruments.

### FM (YM2413) — post-v0.2 addendum (SMS only)
| Param | Range | Meaning |
|---|---|---|
| PROG | 1–15 | which YM2413 ROM patch (voice) |
| VOL | 0–F | level (→ FM carrier attenuation) |
| HLD | 0–F | note length: `F` = ring per the chip's hardware envelope, `1`–`E` = key-off after nibble×2 ticks |
| TSP | ±  | transpose (instrument + global), applied before the F-number lookup |
| TBL/TBS | — | table # / speed — FM honours tables (below) |

Needs the SMS **FM Sound Unit** (ports `$F0`/`$F1`/`$F2`), enabled by **OPTIONS → FM** (persisted; default OFF). Pitch comes from a region F-number/block table (`maketables.py`, like the PSG note table). A track hosting an FM instrument plays on the FM channel of the same index and **silences its PSG voice**; the FM note uses the chip's own envelope (no per-tick engine work beyond the HLD key-off). `$F2` is a PSG/FM mux on the external unit (and Emulicious) but sums on the built-in FM hardware (and SMSPlus).

**Custom presets.** Beyond the 15 ROM patches, an FM instrument's **PRST** field (instrument byte +11; `OFF` = use the ROM PROG, `1`–`8` = a custom timbre) selects one of 8 ROM-baked user-patch presets. On trigger the preset's 8 bytes load into the YM2413 user patch (`$00`–`$07`) and the note plays patch 0 — but only re-loaded when the selected preset actually changes (tracked in `fm_user_preset`), so repeated notes stay off the hot path. **There is only one user patch (global), so only one custom timbre sounds at a time** — the most recent trigger wins; two instruments on different presets fight. `Y` forces a ROM patch and ignores the preset for that note. The presets are a self-describing, marker-delimited block (`"FMPRST"` magic + version + count, then 8×8 patch bytes, then 8×5 names) so a browser tool can find and rewrite them like the palette/sample-pool blocks; values are a tunable starting palette (LEAD/EPNO/SBASS/BELL/BRASS/PAD/PLUCK/SINE).

**FM drums (rhythm mode).** A second FM instrument type, **FMDRUM** (type 5), drives the YM2413's rhythm mode (`$0E` bit 5): the chip's 5 fixed percussion voices — **BD, SD, TT** (tom), **TC** (cymbal), **HH** (hi-hat). It's a *kit*: one instrument, the **note picks the drum** (note % 12 cycles BD/SD/TT/TC/HH every 5 semitones — C/C♯/D/D♯/E in any octave). Rhythm mode uses FM channels 6–8, which the tracker never allocates for melodic FM (only 0–3), so it's enabled permanently alongside melodic FM at **zero cost** to the 4 tracks. Trigger pulses the drum's `$0E` key-on bit (off→on edge = re-attack); the drum's level lands in the shared `$36/$37/$38` register via a RAM shadow (the two-drum-per-register packing means we can't read-modify-write the chip). **VOL** sets the level, **HLD** the length (`F` = ring per the chip's percussion envelope, `1`–`E` = key-off after nibble×2 ticks). No transpose, no tables, no per-note program. The fixed drum pitches (`$16/$26`…`$18/$28`) are set once at FM init.

**FM tables.** An FM instrument runs a table like any other voice. The table's **volume** column rewrites the FM channel level register (`$30` low nibble) live; the **pitch** column offsets the note and re-keys the FM voice — but only when the offset *changes* from the previous step, so a flat/blank table holds the note steady instead of retriggering every step (the chip key-on edge is what re-attacks). The trigger keeps the base note in the channel struct so the table arps relative to it. The `X` (volume) and `Y` (program) commands also resolve to the FM channel for FM voices.

---

## 7. Tables (macro sequencer)

16 rows, running at TBL SPD ticks/row:

| Column | Range | Effect |
|---|---|---|
| VOL | 0–F / -- | set volume (feeds envelope stage) |
| PITCH | ±7F | signed semitone offset (arpeggio chords live here) |
| CMD+PARAM | any phrase command | `H xy` inside a table = loop to row x, y times (y=0 → forever) |

Triggered three ways, like LSDJ: instrument assignment (restarts on note), `A xx` command mid-note, runs until note-off/next note.

**Advance modes (TBL SPD):** `1–F` = a row every N ticks (time-based, restarts at
row 0 on every note). **`0` = per-note**: the table advances exactly one row per
*triggered note* (nothing happens on held ticks), and the row **persists across
notes** — it only restarts at row 0 when the table # is (re)assigned. `H` loops
as usual, so a short note-mode table run against a longer phrase gives polymeter
and phrase↔table interplay. (Retriggers via `R` count as triggered notes.)

---

## 8. Command set (PHRASE and TABLE command columns)

| Cmd | Name | Param | Effect |
|---|---|---|---|
| `A xx` | tAble | table # / 20=off | start/switch table |
| `B x`  | wave Bank | wave # 0-7 | set this note's wavetable, overriding the instrument's (one-shot, in PHRASE) |
| `C xy` | Chord | +x, +y semitones | looping 0,x,y arpeggio (00 = off) |
| `D xx` | Delay | ticks | delay note trigger |
| `E xy` | Envelope | ATK x, DCY y | re-slope the AHD ramps live (HLD and the current stage are untouched) |
| `F xx` | Finetune | signed | detune in period units |
| `G xx` | Groove | groove # | switch groove from this row (this track) |
| `H xx` | Hop | position | PHRASE: end phrase / jump to song row; TABLE: loop |
| `K xx` | Kill | ticks | note cut after xx ticks (00 = instant; also aborts samples) |
| `L xx` | sLide | speed | tone portamento toward this row's note |
| `M xy` | aMp mod | speed x, depth y | tremolo override (LSDJ's M is master volume, which the PSG lacks — letter reused) |
| `N xy` | Noise | x=mode, y=rate | override noise mode/rate; on T3: release from STEAL for this note |
| `P xx` | Pitch bend | signed | continuous bend, period units per tick |
| `R xy` | Retrig | vol-delta x, rate y | retrigger every y ticks, stepping volume by x |
| `S xx` | Speed | 0-3 | sample playback speed — 0 normal, 1 = 2× (octave up, half length, decimated), 2 = ½× (octave down, nibble-held), 3 = 4× (two octaves up, every 4th sample). Walks the sample data faster/slower at a fixed output clock, so no IRQ-timing change. Live (can re-speed a playing sample). The SMP instrument's RATE field is the per-note default |
| `O xy` | Output (pan) | x = left, y = right | Game Gear stereo (post-v0.2): `O11` centre, `O10` left, `O01` right. Per-channel, persists, works from tables. The `.gg` build writes the stereo port; the `.sms` build only tracks state (port $06 is memory control on an SMS) — one song pans wherever panning exists |
| `I xx` | Iteration | 8-bit play mask | play this row's note only on the repeats whose bit is set: on repeat N, play if bit (N mod 8) of the mask is set. `I00` never, `IFF` always, `I55`/`IAA` odd/even repeats, `I0F` first four of eight, `IF0` last four — phrase variation without cloning. The index is **this phrase's play count** (how many times it has played this song, mod 8), accumulating across the whole arrangement; reset only at play-start |
| `T xx` | Tempo | BPM (hex) | set global tempo — converts BPM→groove using the **active tick rate** (region-true) |
| `V xy` | Vibrato | speed x, depth y | one-shot vibrato override |
| `W xx` | Wait-skip | ticks | shorten this row to xx ticks (shuffle fills) |
| `X xx` | volume | level 0–F | set this note's volume (the AHD peak); pair with a note — the attack ramps to it. Accents a single note (the only per-note volume control after `E` became ATK/DCY) |
| `Y xx` | FM program | patch 1–15 | set this note's FM program/patch, overriding the FM instrument's PROG (one-shot, like `B` for wavetables) |

Omitted vs LSDJ: `S` (covered by `P`), wave/duty (no hardware). `O` gained its LSDJ meaning post-v0.2 (Game Gear stereo only). `M` is repurposed (amp mod). `F` = finetune and `W` = wait-skip also diverge from LSDJ (whose F/W are wave-channel commands). `Z` (random) → v2. `B` (wave-bank select) is new — no LSDJ equivalent.

---

## 9. Timing: grooves

Identical model to LSDJ: a groove is up to 16 tick-counts (1–15 ticks per phrase row). Swing = uneven pairs (`8,4`). Groove is global by default; `G` sets per-track grooves for polyrhythms.

The groove is the single musical clock: tempo *is* the groove (ticks/row at the fixed 50/60 Hz frame rate), so there is no separate tempo store. The PROJECT **TMPO** field is a live readout derived from the active groove and steps it one tick at a time — i.e. it walks the achievable BPM rungs (NTSC flat groove: 60, 75, 90, 100, 112, 128, 150, 180, 225…), shifting every groove entry together so swing is preserved, never flattened. The `T` command still does direct BPM→groove entry mid-song (it flattens, by design — an explicit "set this tempo now"). Anything that should track the beat is expressed in rows against this grid (e.g. echo taps); only the sample/wave DAC feed uses raw frame-ticks. In sync-IN mode the engine **locks to a flat 6-tick row** (24 PPQN) and ignores the song's stored groove, so the song stays beat-aligned with the master at any tempo regardless of its groove (1 wire clock = 1 tick; groove 6 = 16th-note rows). The stored groove is untouched — it returns when SYNC leaves IN; `W` is also ignored while following. See §11.3.

---

## 10. Sample channel (optional) — 4-bit PCM on the SN76489

Reference: SMS Power "Sample Playback" (smspower.org/Development/SamplePlayback); SN76489 datasheet attenuation spec (2 dB/step).

### 10.1 The technique
Set a tone channel's period to **1**: on the Sega VDP-integrated SN76489 the flip-flop stops and the channel outputs a DC level equal to its 4-bit volume setting. Rapidly rewriting the volume register turns it into a 4-bit DAC. The 16 levels are **logarithmic** — attenuation register n gives amplitude 10^(−n/10) (2 dB per step, per the datasheet), with level 0xF = 0. So the available DAC levels are:

```
n:  0     1     2     3     4     5     6     7     8     9     A     B     C     D     E     F
A:  1.000 .794  .631  .501  .398  .316  .251  .200  .158  .126  .100  .079  .063  .050  .040  0
```

Linear PCM must be pre-mapped to these levels — that correction is the conversion tool's job (§10.5), not the Z80's. Effective dynamic range ≈ 28 dB; the log spacing actually flatters low-level detail (µ-law-like).

### 10.2 Channel allocation & arbitration
- Samples are **SMP instruments on a tone track** — no fifth track. Host channel = PROJECT setting `SMP CH` (T1/T2/T3/**OFF**, default T3). OFF removes all sample overhead.
- While a sample plays, the host channel's tone/volume belong to the DAC; a tracker note on that track stops the sample (and vice versa — last trigger wins).
- T3 conflict matrix: pitched noise needs T3's *period*; samples need T3's period **= 1**. They cannot coexist. Priority: **sample > pitched noise** — while a sample plays on T3, pitched-noise instruments fall back to their nearest fixed rate (same fallback as `NOI MODE = FREE`); the steal glyph shows on the meter. Putting `SMP CH = T1` avoids the conflict entirely at the cost of a melodic channel.

### 10.3 Data path
- Sample pool lives in **banked ROM**: banks 2-7 (96 KB ≈ 24 s), implemented post-v0.2. The pool is **self-describing** (the contract for external patchers — file offset $8000, 96 KB): bank 2 starts `"SMPL"`, version, count, rate (word), then 32 directory entries × 10 bytes — bank, offset (word, $8000-based), length (word), name (5 ch). Samples never cross a bank (≤ ~16 KB ≈ 4 s each); placement is first-fit. The engine caches the count at boot and reads directory entries at trigger time (interrupts held while the directory bank is paged); the playing sample's bank stays in slot 2, owned by the feeder. **SRAM mapping covers the pool banks**, so save/load abort any in-flight sample first.
- Slot 2 is shared with song SRAM, so playback never reads ROM directly when SRAM is active: a **256-byte page-aligned ring buffer** in internal RAM is refilled once per frame (~160 samples/frame at 7.8 kHz/50 Hz) by briefly paging ROM into slot 2, unpacking, and restoring SRAM.
- Refill-time unpacking does all per-sample work for free at playback time: split the two nibbles, add the instrument's VOL OFS (clamp at 0xF), and pre-OR the PSG latch/channel command bits — the ring holds **ready-to-OUT bytes**. Refill cost ≈ 5–7 k cycles/frame.
- No SRAM present → song is in internal RAM, slot 2 is free, samples stream straight from ROM (no ring needed).

### 10.4 Playback timing (hybrid scheme)
Constraint: the VDP line-interrupt counter only runs during active display, and VBlank is long (70 lines NTSC, 121 lines PAL) — a per-frame gap would buzz at frame rate. So:

- **Active display:** line IRQ every 2 scanlines (VDP reg 10 = 1). Handler uses the Z80 shadow register set (`EXX`/`EX AF,AF'` — reserved for this) → ~80 cycles per sample: ack VDP, `LD A,(HL)`, `OUT (0x7F),A`, `INC L` (ring is page-aligned).
- **VBlank:** a cycle-counted loop feeds samples at the same cadence; engine tick, ring refill, and UI work shift into active display between line IRQs (PSG writes are safe anytime; VRAM writes obey the ~29-cycle active-display spacing rule, UI throttled to 2 rows/frame).
- **Sample rate** = line rate ÷ 2: **7,813 Hz PAL / 7,867 Hz NTSC** — 0.7 % apart (≈12 cents), effectively region-proof. ROM cost ≈ 3.9 KB/s; a 128 KB ROM holds ~20 s of samples (~25 drum/vocal hits).
- **CPU cost while a sample plays:** IRQ feed ~7.7 k + refill ~6 k ≈ **14 k cycles ≈ 23 % of an NTSC frame** (19 % PAL). Budgeted in §13; silence costs nothing (IRQs disabled when no sample active).
- Per-sample cadence options (÷1 = 15.6 kHz, ÷3 = 5.2 kHz) are a stretch goal; v1 is fixed ÷2.

### 10.5 Sample conversion tool (PC-side, part of the repo)
`smsggdj-sample` — Python 3, stdlib-only (`wave`, `struct`); CLI:

```
smsggdj-sample in.wav [in2.wav …] -o pool.bin --asm pool.inc
   --rate 7813      target rate (default PAL ÷2 cadence)
   --gain/--norm    normalize to full scale (default on)
   --comp X         optional dynamic-range compression (quiet detail survives 4 bits)
   --dither         error-diffusion dithering against the LOG level table (default on)
   --gate X         silence-gate threshold — mute sub-1-bit passages to kill noise floor
   --loop N         loop point (samples)
   --preview        also write a WAV rendered through the exact level table for auditioning
```

Pipeline: mix to mono → resample to target rate → normalize/compress → map each sample to the nearest of the 16 logarithmic amplitudes (the 2 dB table above, signed audio mapped onto the unipolar DC range) with 1-D error diffusion → silence-gate → pack two nibbles/byte → emit binary pool + assembly include with the pool index (names, banks, offsets, lengths, loop points). The `--preview` render is bit-exact to what the console will output, so sample tuning happens on the PC, not in burn-and-listen cycles.

### 10.6 Wavetable mode (WAV instruments) — post-v0.2 addendum

Wavetable synthesis through the same T3 DC-DAC as PCM samples, sharing the entire §10.4 feed machinery (line IRQ + vblank feeder; `smp_mode` selects PCM vs wave per feed tick).

- **8 user waves**, 32 steps × 16 levels each (booting as the 8 stamp presets — a ready-made timbre selector), drawn on the **WAVE screen** (above INSTR on the screen map; 2+left/right selects the wave; the cut gesture stamps ROM presets: sine, triangle, saw, square, 25%, 12.5%, organ, random). `wave_ram` (256 B) leads the song block and saves with the song (format SMDJ3).
- **Pitch** = 8.8 fixed-point phase accumulator over the 32 steps. Per-region increment tables (`winc_table_pal/ntsc`, generated by maketables.py): `inc = f × 8192 / feed_rate`, so output frequency = feed × inc / (256 × 32). Same note range as the tone channels.
- **Log-DAC correction:** the DAC's 16 levels are logarithmic (2 dB/step) but drawn levels are linear. At note trigger — and live on every WAVE-screen edit — the drawn wave is copied through the `wav_lin2log` map (nearest attenuation to v/15) into `wav_buf`, a 32-byte-aligned play buffer in internal RAM. `wave_ram` always holds the *drawn* shape (what the editor shows and the save stores); only the play buffer is corrected. Quantization is coarse near full scale (the 2 dB grid spans levels 11–15 with two steps) — inherent to the hardware.
- **Arbitration:** one wave at a time (it owns the T3 DAC, like samples — last trigger wins). The owning track's volume/envelope gate the wave: volume 0 stops it. The noise channel is silenced for exactly as long as a wave plays (shadow, sent state and chip — wavetables are melodic; samples leave noise audible).
- **Shadow register contract** while a wave plays: HL' = `wav_buf`, DE' = phase increment, BC' = 8.8 phase (PCM uses HL' = pointer, DE' = end, B' = byte, C' = nibble phase). Both feed paths dispatch through `smp_feed_any` from *both* the line IRQ and the vblank feeder — feeding a wave through the PCM path corrupts the shadow state.

---

## 11. Sync (controller port 2) — native master/slave

Replaces the v0.2 MIDI-adapter-first plan: SMSGGDJ instances sync **directly to each
other** over controller port 2, no adapter needed. PROJECT → `SYNC: OUT / PULSE /
IN / OFF` (**OFF is the default** — the port is never driven unasked). The port only drives while the transport
runs; stopping (or changing mode) releases the lines (`OUT ($3F), $FF`).

Wiring — three cable scenarios, all accepted by the same firmware (the IN
reader takes counter bit 0 as **TR AND TL**, so a crossed or straight cable
works with no setting; pull-ups hold the unused line high):

- **SMS ↔ SMS**: straight 3-wire DE-9 — pin 9 (TR), pin 7 (TH), pin 8 (GND).
- **SMS ↔ Game Gear**: SMS port 2 → male-male DE-9 → **Master Link Cable** →
  GG EXT (straight signal mapping; the GG runs in SMS mode, screen cropped).
- **GG ↔ GG**: a stock **Gear-to-Gear cable** — it crosses TR↔TL (its serial
  TX/RX swap) and passes TH straight; the AND read absorbs the crossover.

TR/TH are software-direction pins: outputs via port `$3F` on the master, read
back on port `$DD` on the slave (TR bit 3, TL bit 2, TH bit 7). **Export
consoles only** — Japanese SMS hardware ignores `$3F` level drive.

### 11.1 OUT — 2-bit tick counter on TR+TH

One count per **engine tick** while playing (nominally 24 PPQN: groove 6 gives
24 ticks per quarter; the wire unit is ticks, so other grooves shift the
effective PPQN). A naive one-line pulse would drop clocks when a 60 Hz master
feeds a 50 Hz slave (poll rate must exceed toggle rate); the mod-4 counter is
lossless up to 3 ticks per slave frame — region-proof in every pairing, no
interrupts, tempo exact over time because clocks are counted, not timed.

### 11.2 PULSE — Volca / Pocket Operator sync out

TR carries a 5 V pulse, high for one tick, every 12 ticks = **2 PPQN at the
default groove** (the analog-sync convention); TH stays an input. The SMS can
drive a Volca/PO sync-in directly: tip = TR, sleeve = GND.

### 11.3 IN semantics

- Play arms the transport (top bar shows **WAIT**, inverted); the first counter
  change starts it and counts as exactly one tick, so the idle→counter jump is
  never over-counted. Each frame the slave applies `(read − last) & 3` engine
  ticks — catch-up runs multiple ticks in one frame when regions mismatch.
- Master stops → counter freezes → slave holds position silently mid-row;
  master resumes → both continue. No song-position pointer: each unit plays
  from its own cursor (LSDJ live-sync model).
- Grooves/envelopes/tables consume ticks identically in both units; at the
  default groove both run 16th-note rows in lockstep.
- Jitter: slave ticks quantize to its own frame (≤20 ms, slowly wandering
  between same-region units) — same order as LSDJ slave mode. A mid-frame
  poll can halve this later if needed.
- Under `SYNC: IN` the engine also locks to a flat **groove 6** (24 PPQN) and
  ignores the song's stored groove and the `W` command (v0.24, non-destructive
  — the stored groove returns on leaving IN), so any song stays beat-aligned at
  one tick = 1/24 beat regardless of its own groove.

### 11.4 Ableton Link bridge (external)

The 2-bit counter is host-agnostic, so anything that can present a monotonic
counter on TR/TH can be the master. The companion project
**[smsggdj-link-esp32](https://github.com/little-scale/smsggdj-link-esp32)** is
a Seeed XIAO ESP32-C3 that joins an **Ableton Link** session over WiFi, derives
the 24 PPQN tick clock from the shared beat timeline (bar-aligned launch), and
drives the counter into port 2 via open-drain GPIOs. SMSGGDJ in `SYNC: IN` then
follows Live's tempo and transport. Verified on real PAL SMS1 hardware; wiring
in HARDWARE.md. It relies on the flat-groove-6 lock above to stay aligned.

### 11.5 MIDI (future)

A MIDI adapter now reduces to: receive MIDI clock/start/stop, drive the same
2-bit counter on two pins. Far simpler than the v0.2 polled-nibble protocol;
parked for v2 along with MIDI out and Song Position Pointer.

---

## 12. Persistence

- **With cart SRAM:** song data lives directly in SRAM (slot 2 via mapper reg 0xFFFC) → every edit instantly persistent, LSDJ-style. 32 KB = 2 song slots (load/save/erase/copy on PROJECT). Save format: magic + version + structure counts + checksum; failure → offer "init new song". Config block (VIDEO, SYNC, SMP CH, key repeat) saved alongside.
- **Without SRAM** (boot write-test): song in internal 8 KB at baseline limits, visible "NO SAVE RAM — song is volatile" warning. Emulator save-states still work.
- **Clone** (double-tap-1 on a populated cell, §3): duplicates the chain (SONG) or phrase (CHAIN) into the next free slot. **OPTIONS → CLONE: SLIM/DEEP** (default SLIM) governs *chain* cloning — SLIM = new chain, phrases shared (same numbers); DEEP = new chain plus fresh copies of every phrase it references (checked up front against the free-phrase budget). Phrase cloning is always an independent copy. No free slot → the cursor flashes and nothing changes (no partial clone).

---

## 13. Z80 / frame budget

Budgeted against the tighter NTSC frame (~59,736 cycles); PAL (default) has ~71 k.

| Subsystem | Budget | Notes |
|---|---|---|
| Sound engine tick | ≤ 6,000 | first in VBlank IRQ; PSG writes never jitter |
| Sample playback (when active) | ≤ 14,000 | line-IRQ feed ~7.7 k + ring refill ~6 k (§10.4); zero when silent |
| VRAM flush (dirty rows) | ≤ 6,000 | 4 rows/frame; 2 rows + active-display spacing while sampling |
| Input + UI logic + MIDI poll | ≤ 8,000 | MIDI poll transaction is a few hundred cycles |
| Headroom | remainder | screen transitions, copy/paste amortized |

Implementation rules: no mul/div on hot paths — note tables, LFO tables, BPM↔groove tables in ROM; channel state in contiguous structs (no IX/IY on hot paths); PSG shadow registers; **shadow register set (EXX/AF') reserved for the sample IRQ**; NMI handler = set flag + RETN; engine fully interrupt-driven so editing never glitches audio; all timing constants **and note-period tables** assembled per-region (PAL + NTSC pairs in ROM) and selected at boot per the VIDEO setting.

---

## 14. Deliverables, toolchain, milestones

**Deliverables:**
1. `smsggdj.sms` — the ROM (128 KB, standard Sega mapper, valid TMR SEGA header + checksum).
2. `tools/smsggdj-sample` — sample conversion tool (§10.5); `tools/patcher.html` — browser sample patcher (done).
3. `adapter/` — MIDI sync adapter firmware (RP2040 primary target) + protocol doc + schematic.
4. Demo song + production sample pool (`samples/pool.bin`, baked into builds) + manual (`MANUAL.md`).

**Toolchain:** WLA-DX (z80) or sjasmplus, pure assembly; Makefile drives ROM + sample-pool build. **Test targets:** Emulicious (primary — debugger + accurate PSG, PAL and NTSC modes), MEKA/Genesis Plus GX (sanity), real PAL SMS via Master Everdrive (timing + SRAM + sample/MIDI truth), real NTSC pass before release.

**Milestones:**
1. Boot skeleton: header, mapper init, PAL/NTSC detect (PAL fallback), font, VBlank loop, input + repeat, NMI flag.
2. PSG driver + note table + shadow registers; test-tone keyboard.
3. Engine core: phrase playback with groove, envelope, `K` command; tick-source abstraction in from day one.
4. PHRASE editor (cursor, edit, insert, prelisten) — *first playable build*.
5. CHAIN + SONG screens, transport (1+2 / PAUSE alias), mute/solo.
6. Instruments (TONE/NOISE/KIT) + INSTR screen; tables + TABLE screen.
7. Full command set, GROOVE screen, copy/paste/clone.
8. SRAM detect + save/load, PROJECT screen (incl. VIDEO/SYNC/SMP CH settings).
9. **Sample subsystem:** conversion tool first, then line-IRQ/VBlank hybrid player, SMP instruments, ring streaming. Hardware-verify early — emulator PSG-DAC accuracy varies.
10. **MIDI sync:** adapter firmware + port protocol, SLAVE tick source, transport semantics. Hardware loopback test rig.
11. Polish: meters, key hints, demo song, dual-region hardware regression pass.

## 15. GGDJ — the native Game Gear build *(post-v0.2)*

One tree, two ROMs: `TARGET_GG` selects the flavor; everything musical
(engine, sampler, waves, save format, pool contract, patcher) is shared.

- **Window layout:** the GG LCD shows a 20×18-tile window of the 256×192 frame
  (origin tile 6,3). The whole UI shifts there via a single origin in
  `nt_addr_hl`; the chrome compresses to two header rows — screen name left,
  **GGDJ** centre, transport + sync symbol right; track headers/status on row
  1 — and the grid keeps all 16 rows. SONG's track columns tighten; the side
  map column is dropped (the screen name orients).
- **WAVE screen:** paged — 16 steps at full height, the view (and hex readout,
  with a page digit) follows the cursor across the halves; **1+left/right
  jumps pages** (on SMS it remains drag-draw). Presets stamp as on SMS.
- **Platform:** START (GG port `$00`) replaces PAUSE as the transport alias;
  CRAM writes are 12-bit pairs (COLR schemes upscale ×5 per channel); region
  is fixed NTSC (no region line); `O` pan writes the stereo register natively
  (the SMS build only tracks state).
- **Sync (decided, not yet built):** the GG flavor will use the EXT port's
  **serial mode** (hardware UART, 4800 8N1, NMI-on-receive) speaking MIDI
  real-time bytes — not parallel mode. GG↔GG via a stock Gear-to-Gear cable;
  the SMS counter protocol stays for SMS rigs.

**v2 parking lot:** `Z` random command, pitched sample playback (phase accumulator), per-sample cadence, MIDI clock out / thru on TH, Song Position Pointer, 255-phrase SRAM tier, tap-tempo, raw bit-bang MIDI listen mode.
