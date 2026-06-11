# SMSDJ — an LSDJ-inspired tracker for the Sega Master System
**Design document v0.2 — 2026-06-11**

Target: a single ROM that runs on real SMS hardware (via flashcart) and in emulators.
Sound: SN76489 PSG only (including 4-bit PCM on it — see §10). CPU: Z80 @ 3.546893 MHz (PAL, default) / 3.579545 MHz (NTSC).

Changes in v0.2:
- PAL **and** NTSC support; PAL is the default assumption, auto-detected at boot with user override (§5.1).
- Optional **sample channel**: 4-bit PCM via the SN76489 volume-register DAC trick, plus a PC-side sample conversion tool (§10, §14).
- **MIDI clock sync (slave)** on controller port 2 — responds to MIDI Start/Stop/Continue/Clock (§11). PAUSE demoted to a secondary control.
- ROM moves from 48 KB flat to the standard Sega mapper (128 KB) to hold sample data.
- Confirmed decisions: double-tap-1 deep-edit jump; CH3-steal policy for pitched noise.

Post-v0.2 addenda (implemented):
- **Wavetable mode**: WAV instrument type + WAVE editor screen — 4 user-drawn waves played through the T3 volume DAC via a phase accumulator (§10.6). Waves save with the song (SMDJ2).

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
| Controller port 2 | 5 readable pins (Up/Down/Left/Right/TL) + TH; TR and TH drivable as *outputs* via port 0x3F. No interrupt capability on these pins. | Enough for a polled, handshaked parallel-nibble protocol → MIDI sync adapter (§11). Raw 31,250-baud bit-banging is not viable alongside a running tracker (§11.4). |
| Video timing | 50/60 Hz is fixed by the console's hardware (crystal + VDP); software cannot switch it. | "PAL/NTSC support" = the *timing engine* adapts (tick rate, BPM math, sample cadence), not the video output. Auto-detect + override, §5.1. |
| ROM | Standard Sega mapper, header at 0x7FF0 ("TMR SEGA") required by export BIOS. | 128 KB ROM: 3 fixed/banked code+table pages, rest = sample pool banks. |

Explicitly **out of scope**: FM (YM2413) and any other expansion audio, stereo (Game Gear only), MIDI *output* (parked for v2).

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
| **1** double-tap | Paste the clipboard at the cursor (same screen/column as the cut) |
| **2** tap | Back: PHRASE → CHAIN → SONG (pops the navigation stack) |
| **2** hold + D-pad | Navigate the screen map (LSDJ SELECT+dpad equivalent) |
| **2** held + **1** tap | **Play/stop** (transport — primary control; 2 is the "project" modifier: navigation and transport). Context-sensitive: SONG screen = play song from cursor row; CHAIN/PHRASE = loop that chain/phrase |
| **1** held + **2** tap | Cut (delete the field into the clipboard) |
| Block selection | TBD — gesture to be redefined (2-held+1 now means transport) |
| **PAUSE** (NMI) | Alias for play/stop. Double-press = panic (silence all channels, abort sample, re-arm MIDI sync) |
| Track mute/solo | Cursor on a track header (SONG screen) + 1 = mute toggle, 1 double-tap = solo |

No timing disambiguation is needed: the button already held when the other arrives selects the action (1 held + 2 = cut, 2 held + 1 = transport), and a lone 1 press inserts instantly. Only paste uses a window (double-tap, ~0.3 s).

PAUSE generates an NMI whose handler only sets a flag — it is never *required*, so the tracker remains fully usable on hardware without a working PAUSE button.

---

## 4. GUI layout and screens

256×192 = 32×24 characters. Custom 8×8 font (hex digits get heavy use; design them first). Palette 0 = normal text, palette 1 = inverted (cursor, playhead row, selection) via the tilemap palette bit.

Persistent chrome:
- **Top bar (rows 0–1):** screen name, song title, BPM (derived from groove + tick source), play state, sync status (`INT 50` / `INT 60` / `MIDI` + clock-activity dot), current position `SS:CC:PP`.
- **Bottom bar (row 23):** screen map indicator + context-sensitive key hints.
- **Right column (cols 27–31):** 4 channel activity meters (current attenuation as a bar; sample-playback glyph on the sample channel, steal glyph on T3) + current octave + current instrument number.

Screen map (navigated with 2+D-pad):

```
            [PROJECT]
[SONG] [CHAIN] [PHRASE] [INSTR] [TABLE]
            [GROOVE]
```

| Screen | Contents |
|---|---|
| **SONG** | 4 columns of chain numbers, 16 visible rows (scrolls), playhead per track, track mute/solo headers |
| **CHAIN** | 16 rows × (phrase #, transpose ±semitones) |
| **PHRASE** | 16 rows × (note, instrument, command, param). Noise track shows noise pitch/preset names; sample instruments show sample names |
| **INSTR** | All parameters of one instrument (form layout, §6) |
| **TABLE** | 16 rows × (vol, pitch, cmd+param) with tick-speed field and loop via `H` command |
| **GROOVE** | 16 tick values, live BPM readout (uses active tick rate, §5.1) |
| **PROJECT** | Song name, default groove, save/load/erase, clone mode, prelisten, key-repeat speed, **VIDEO: AUTO/PAL/NTSC**, **SYNC: OFF/MIDI**, **SYNC RES: 24/12/6 PPQN**, **SMP CH: T1/T2/T3/OFF**, blocks free, version |

Rendering: dirty-row queue, VBlank flushes up to 4 rows (≈256 bytes VRAM) per frame. While a sample is playing, UI flushes move into active display at the VDP-safe write spacing (§10.4) and throttle to 2 rows/frame. No sprites required.

---

## 5. Sound engine

### 5.1 Timing, PAL/NTSC

The engine tick is decoupled from its **tick source**:

- **INTERNAL** (default): one tick per VBlank — 50 Hz on PAL, 60 Hz on NTSC.
- **MIDI SLAVE**: ticks are driven by incoming MIDI clocks (§11); VBlank still drives UI/meters.

Region handling:
- **Auto-detect at boot** (count scanlines / time VBlank-to-VBlank); result shown on PROJECT.
- **PROJECT → VIDEO: AUTO / PAL / NTSC** — manual override for modded 50/60 Hz consoles or misreporting emulators. When detection is ambiguous, **PAL is assumed** (project default).
- The setting governs *timing and tuning math* (refresh rate is fixed by the console): BPM display, the `T` tempo command's BPM→groove conversion, groove BPM readouts, sample-cadence constants, **and the note table**. Grooves are stored in ticks, so a song authored at PAL 50 Hz runs ~20 % faster on NTSC; the `T` command always re-derives ticks from BPM at the *active* rate, so `T`-driven songs stay tempo-true across regions.
- **Region tuning:** the PSG divides the system clock, which differs by region (3.546893 MHz PAL vs 3.579545 MHz NTSC) — the same period value sounds **~15.9 cents sharper on NTSC**. Two complete note-period tables live in ROM, each computed for A=440 against its own clock, selected by the VIDEO setting at boot. This also covers everything derived from tone periods: pitched/periodic-noise bass (driven by T3's divider) and finetune deltas. Residual region differences are only quantization (10-bit periods round differently per region, worst in the top octave) and the sample channel's fixed cadence (~12 cents, §10.4).
- Default groove `6,6` = 125 BPM at 50 Hz (150 at 60 Hz), 4 rows per beat.

### 5.2 Per-tick pipeline

Per tick, per channel (fixed order, deterministic):

1. **Groove counter** — on expiry, advance phrase row; read note/instr/cmd; apply per-step command.
2. **Table tick** (at table speed) — volume column, pitch column, table command.
3. **Software envelope** — initial volume + fade up/down at rate.
4. **Pitch effects** — slide, tone-portamento, vibrato (ROM LFO tables), detune.
5. **Final write** — note + transposes → ROM note table (10-bit period) + finetune; clamp; write PSG only on change (shadow registers, `OUT (0x7F)`).

Engine budget: **≤6,000 cycles/tick (~10 % of the NTSC frame)** worst case.

### 5.3 Noise/CH3 coupling *(confirmed)*

When a noise instrument uses *pitched* mode, the engine writes the noise pitch to tone-3's period and mutes T3, **only if** the song setting `NOI MODE = STEAL` is on (default). With `FREE`, pitched noise falls back to the nearest fixed rate and T3 stays playable. Warning glyph on T3's meter when stolen. Sample playback adds one more claimant on its host channel — arbitration in §10.2.

### 5.4 Playback modes

Play song from row / loop chain / loop phrase (transport context, §3); per-track mute/solo; **prelisten** (notes audition on entry, PROJECT toggle). LSDJ-style LIVE mode deferred to v2.

---

## 6. Instruments — all parameters

16 bytes each. Four types. Every parameter is hex-editable in a form layout.

### Common to all types
| Param | Range | Meaning |
|---|---|---|
| TYPE | TONE / NOISE / KIT / SMP | |
| NAME | 5 chars | shown in PHRASE column hint |
| VOL | 0–F | initial volume (F = loudest) |
| ENV | dir + speed | fade UP / DOWN / OFF, speed 0–F ticks per step |
| LEN | 0–3F | auto note-cut after N ticks, 0 = hold |
| TBL | 0–1F / -- | table assignment |
| TBL SPD | 1–F | ticks per table row |
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

### SMP (sample) — new in v0.2
| Param | Range | Meaning |
|---|---|---|
| MAP | SINGLE / KIT | SINGLE: note column ignored (or selects nothing), plays SAMPLE; KIT: each note in an octave maps to a sample slot |
| SAMPLE | pool slot # | which sample (SINGLE mode) |
| VOL OFS | 0–7 | software attenuation added to every nibble at ring-refill time (2 dB steps — free at playback time, §10.3) |
| LOOP | ON/OFF | loop sample to end of note |
| ENV/TBL | — | tables and envelopes do **not** run during sample playback v1 (volume is the DAC); LEN and `K` still cut |

Notes on SMP: playback rate is fixed (§10.4); pitched sample playback via phase accumulator is a v2 stretch. The note table maps to sample slots in KIT mode, mirroring the KIT type.

### WAV (wavetable) — post-v0.2 addendum
| Param | Range | Meaning |
|---|---|---|
| WAVE | 0–3 | which user-drawn wave plays (§10.6) |

Common params apply; the host channel's volume/envelope *gate* the wave (volume 0 stops it) rather than scaling the DAC. The note column is pitched normally — wavetables are melodic instruments.

---

## 7. Tables (macro sequencer)

16 rows, running at TBL SPD ticks/row:

| Column | Range | Effect |
|---|---|---|
| VOL | 0–F / -- | set volume (feeds envelope stage) |
| PITCH | ±7F | signed semitone offset (arpeggio chords live here) |
| CMD+PARAM | any phrase command | `H xy` inside a table = loop to row x, y times (y=0 → forever) |

Triggered three ways, like LSDJ: instrument assignment (restarts on note), `A xx` command mid-note, runs until note-off/next note.

---

## 8. Command set (PHRASE and TABLE command columns)

| Cmd | Name | Param | Effect |
|---|---|---|---|
| `A xx` | tAble | table # / 20=off | start/switch table |
| `C xy` | Chord | +x, +y semitones | looping 0,x,y arpeggio (00 = off) |
| `D xx` | Delay | ticks | delay note trigger |
| `E xy` | Envelope | vol x, fade y | override instrument envelope |
| `F xx` | Finetune | signed | detune in period units |
| `G xx` | Groove | groove # | switch groove from this row (this track) |
| `H xx` | Hop | position | PHRASE: end phrase / jump to song row; TABLE: loop |
| `K xx` | Kill | ticks | note cut after xx ticks (00 = instant; also aborts samples) |
| `L xx` | sLide | speed | tone portamento toward this row's note |
| `M xy` | aMp mod | speed x, depth y | tremolo override (LSDJ's M is master volume, which the PSG lacks — letter reused) |
| `N xy` | Noise | x=mode, y=rate | override noise mode/rate; on T3: release from STEAL for this note |
| `P xx` | Pitch bend | signed | continuous bend, period units per tick |
| `R xy` | Retrig | vol-delta x, rate y | retrigger every y ticks, stepping volume by x |
| `T xx` | Tempo | BPM (hex) | set global tempo — converts BPM→groove using the **active tick rate** (region-true) |
| `V xy` | Vibrato | speed x, depth y | one-shot vibrato override |
| `W xx` | Wait-skip | ticks | shorten this row to xx ticks (shuffle fills) |

Omitted vs LSDJ: `O` (no panning), `S` (covered by `P`), wave/duty (no hardware). `M` is repurposed (amp mod). `F` = finetune and `W` = wait-skip also diverge from LSDJ (whose F/W are wave-channel commands). `Z` (random) → v2.

---

## 9. Timing: grooves

Identical model to LSDJ: a groove is up to 16 tick-counts (1–15 ticks per phrase row). Swing = uneven pairs (`8,4`). Groove is global by default; `G` sets per-track grooves for polyrhythms; `T` gives direct BPM entry. In MIDI SLAVE mode grooves still shape row lengths — only the tick *source* changes (at the default SYNC RES of 24 ppqn, groove 6 = 16th-note rows at any external tempo; see §11.3).

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
- Sample pool lives in **banked ROM** (mapper slot 2 pages). Pool header per sample: name (5 ch), bank+offset, length, loop point/flag.
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
`smsdj-sample` — Python 3, stdlib-only (`wave`, `struct`); CLI:

```
smsdj-sample in.wav [in2.wav …] -o pool.bin --asm pool.inc
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

- **4 user waves**, 32 steps × 16 levels each, drawn on the **WAVE screen** (above INSTR on the screen map; 2+left/right selects the wave; the cut gesture stamps ROM presets: sine, triangle, saw, square, 25%, 12.5%, organ, random). `wave_ram` (128 B) leads the song block and saves with the song (format SMDJ2).
- **Pitch** = 8.8 fixed-point phase accumulator over the 32 steps. Per-region increment tables (`winc_table_pal/ntsc`, generated by maketables.py): `inc = f × 8192 / feed_rate`, so output frequency = feed × inc / (256 × 32). Same note range as the tone channels.
- **Log-DAC correction:** the DAC's 16 levels are logarithmic (2 dB/step) but drawn levels are linear. At note trigger — and live on every WAVE-screen edit — the drawn wave is copied through the `wav_lin2log` map (nearest attenuation to v/15) into `wav_buf`, a 32-byte-aligned play buffer in internal RAM. `wave_ram` always holds the *drawn* shape (what the editor shows and the save stores); only the play buffer is corrected. Quantization is coarse near full scale (the 2 dB grid spans levels 11–15 with two steps) — inherent to the hardware.
- **Arbitration:** one wave at a time (it owns the T3 DAC, like samples — last trigger wins). The owning track's volume/envelope gate the wave: volume 0 stops it. The noise channel is silenced for exactly as long as a wave plays (shadow, sent state and chip — wavetables are melodic; samples leave noise audible).
- **Shadow register contract** while a wave plays: HL' = `wav_buf`, DE' = phase increment, BC' = 8.8 phase (PCM uses HL' = pointer, DE' = end, B' = byte, C' = nibble phase). Both feed paths dispatch through `smp_feed_any` from *both* the line IRQ and the vblank feeder — feeding a wave through the PCM path corrupts the shadow state.

---

## 11. MIDI clock sync (controller port 2) — **must-have**

### 11.1 Scope
SMSDJ is a tempo **slave**: it responds to MIDI real-time bytes **Clock (0xF8), Start (0xFA), Continue (0xFB), Stop (0xFC)**. MIDI out, note input, and Song Position Pointer are v2 parking-lot items.

### 11.2 Why an adapter (the Arduinoboy model)
MIDI is 31,250-baud async serial = ~114 Z80 cycles per bit, and the controller ports cannot generate interrupts — catching an asynchronous 32 µs start bit would require polling every ~100 cycles, forever, which no tracker can do while running an engine, UI, and sample IRQs. LSDJ solves this identically: Arduinoboy translates MIDI to a Game Boy-friendly link protocol. SMSDJ specifies a small adapter (RP2040/ATtiny — firmware + schematic are project deliverables) that receives MIDI and presents *latched* data on port 2:

| Port 2 pin | Direction | Role |
|---|---|---|
| Up/Down/Left/Right | adapter → console | data nibble D0–D3 |
| TL | adapter → console | data-valid / strobe |
| TR | console → adapter (output via port 0x3F) | poll request / ACK |
| TH | reserved | (v2: MIDI clock thru/out) |

**Transaction (console-initiated, polled):** console toggles TR; adapter answers with two strobed nibbles — (1) event flags: START / STOP / CONTINUE pending, (2) **count of MIDI clocks elapsed since last poll** (0–15). The console polls at VBlank plus one mid-frame line IRQ (≈100 Hz), so the count nibble never overflows below ~2,400 BPM and **no clock is ever missed** — the adapter accumulates between polls; the console catches up by running multiple engine ticks in one frame when needed.

### 11.3 Slave-mode semantics
- PROJECT → `SYNC: OFF / MIDI`. In MIDI mode the internal 50/60 Hz tick source is replaced by a divided MIDI clock, PROJECT → `SYNC RES: 24 / 12 / 6 PPQN` (a divider on the accumulated clock count; the wire is always 24 ppqn — the MIDI spec fixes that).
  - **24 (default):** 1 clock = 1 tick. At 125 BPM this is exactly 50 ticks/s = the internal PAL tick rate, so songs authored in internal mode slave with identical envelope/table/groove feel; groove 6 = 16th-note rows, LSDJ-equivalent.
  - **12:** 2 clocks = 1 tick — headroom mode. Tick collapse (two ticks forced into one frame) starts at 250 BPM instead of 125 on PAL; preferred for fast tempos or sample-heavy songs. Track with groove `3,3` for 16th rows; swing quantizes twice as coarse.
  - **6:** half-time experiments.
  - No ×2 upsampling to 48 ppqn: the adapter would have to interpolate clock intervals (lag + jitter on tempo changes) and 48 ppqn exceeds the PAL frame rate above 62 BPM.
  - Protocol load is constant regardless of SYNC RES (one 2-nibble transaction per poll); the count nibble overflows only beyond ~3,750 BPM.
- **Start** → reset to song top, play armed. **Continue** → resume from current position. **Stop** → stop, silence channels (samples finish their ring buffer and stop).
- Top bar shows `MIDI` + a clock-activity dot; "WAITING" state when armed but no clock arriving.
- PAUSE in slave mode = local arm/disarm (never sends anything); double-PAUSE = panic + resync (clears clock accumulator).
- Jitter: ticks quantize to poll points (≤10 ms) — same order as LSDJ slave mode; tempo accuracy is exact over time because clocks are counted, not timed.

### 11.4 Raw bit-bang mode
Direct MIDI-cable-to-port reception is documented as **experimental/research only** (a dedicated listen mode could read bytes in a tight loop, but the tracker cannot run meanwhile). Not part of v1 spec.

---

## 12. Persistence

- **With cart SRAM:** song data lives directly in SRAM (slot 2 via mapper reg 0xFFFC) → every edit instantly persistent, LSDJ-style. 32 KB = 2 song slots (load/save/erase/copy on PROJECT). Save format: magic + version + structure counts + checksum; failure → offer "init new song". Config block (VIDEO, SYNC, SMP CH, key repeat) saved alongside.
- **Without SRAM** (boot write-test): song in internal 8 KB at baseline limits, visible "NO SAVE RAM — song is volatile" warning. Emulator save-states still work.
- **Clone modes** (PROJECT): SLIM = reference shared chains/phrases; DEEP = duplicate on edit ("\*" marks shared items).

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
1. `smsdj.sms` — the ROM (128 KB, standard Sega mapper, valid TMR SEGA header + checksum).
2. `tools/smsdj-sample` — sample conversion tool (§10.5).
3. `adapter/` — MIDI sync adapter firmware (RP2040 primary target) + protocol doc + schematic.
4. Demo song + default sample pool + manual.

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

**v2 parking lot:** LIVE mode, `Z` random command, pitched sample playback (phase accumulator), per-sample cadence, MIDI clock out / thru on TH, Song Position Pointer, 255-phrase SRAM tier, tap-tempo, raw bit-bang MIDI listen mode.
