# SMSGGDJ — User Manual

An LSDJ-inspired music tracker for the Sega Master System and Game Gear.
Make music on real hardware (via flashcart) or in an emulator, using just
the D-pad and two buttons.

There are two builds from the same tracker:
- **`smsggdj.sms`** — Master System (full-size screen).
- **`smsggdj.gg`** — Game Gear (GGDJ): fits the handheld screen, and adds
  real stereo panning.

Everything in this manual applies to both unless noted.

---

## 1. Getting started

1. Put the `.sms` (or `.gg`) file on your flashcart's SD card, or open it
   in an emulator.
2. On boot you'll see the SMSGGDJ logo, then the tracker opens on an empty
   song, ready to edit. The eight wavetables come preloaded with the stamp
   presets, so a fresh song can make sound right away.
3. Drop a note or two in a phrase, point a chain and the SONG screen at it,
   and press **Play**.

Nothing is loaded or playing until you ask.

---

## 2. The controls

SMSGGDJ uses only the **D-pad**, **button 1**, and **button 2**. The trick is
that **1** and **2** are *modifiers* — what they do depends on whether you
tap them or hold one while pressing the other.

Think of it as:
- **Button 1 = the item button** — insert, edit, audition a note or value.
- **Button 2 = the project button** — move between screens, and transport.

| You do this | It does this |
|---|---|
| **D-pad** | Move the cursor (hold to repeat) |
| **1** tap | Insert a note/value into the empty cell (repeats the last one you entered) |
| **1** hold + D-pad | **Edit** the value under the cursor. Left/Right = small step (±1). Up/Down = big step (±octave, or ±16) |
| **1** double-tap | **Paste** the clipboard here. With nothing copied: on an *empty* cell it grabs the next **free** (blank) chain/phrase/instrument; on a *populated* SONG or CHAIN cell it **clones** that chain/phrase into a fresh slot (see *Cloning*) |
| **2** tap | **Back** — step out: PHRASE → CHAIN → SONG |
| **2** hold + D-pad | **Move between screens** (the screen map, below) |
| **2** hold + **1** tap | **Play / Stop** |
| **1** hold + **2** tap | **Cut** the value under the cursor (into the clipboard) |
| **1** hold + **2** held (~⅓ s) | **Block select** (see below) |
| **PAUSE** button | Also Play/Stop. (Game Gear: use **START** instead.) |

You never have to time two simultaneous presses — whichever button you're
*already holding* when you press the other decides the action. Only paste
uses a quick double-tap.

### Transport (Play/Stop) is context-sensitive

Where you press **2-hold + 1** decides what plays:
- **SONG screen** — plays the whole song from the cursor row.
- **CHAIN screen** — loops the chain you're looking at.
- **PHRASE screen** — loops that phrase.
- **INSTR / TABLE** — loops the phrase, so you can audition while editing.

**2-hold + double-tap 1** plays the **whole song from the contextual row** instead
— so you can hear the chain/phrase you're editing in full arrangement context. Tap
once to solo what you're looking at; tap twice to drop it back into the mix. (The
contextual row is the SONG cursor you drilled down from.)

### Block select (copy/cut a region)

On SONG, CHAIN, PHRASE or TABLE: hold **1**, then keep **2** held for about a
third of a second. You enter **SELECT** mode anchored at the cursor.
- **D-pad** stretches the selection box.
- **1** tap = **copy** the block.
- **1** hold + **2** = **cut** the block.
- **2** on its own = cancel.

Then **double-tap 1** to paste: the block drops in at the cursor, and each
column lands back on its own column type so nothing gets scrambled.

---

## 3. The screens

Hold **2** and press the D-pad to move around this map:

```
   [OPTIONS][PROJECT]           [WAVE]
   [ SONG ][ CHAIN ][PHRASE][ INSTR ][ TABLE ]
   [ FILES][GROOVE ]          [ ECHO ]
```

Navigation stops at the edges of the map — it doesn't wrap around. **FILES** and
**GROOVE** sit side by side on the bottom row, so `2+Right` from FILES goes to
GROOVE and `2+Left` from GROOVE comes back.

- **SONG** — the arrangement: which chains play on each of the 4 tracks.
- **CHAIN** — a list of phrases (with transpose), played in order.
- **PHRASE** — 16 steps of notes, instruments and commands. The heart of it.
- **INSTR** — design the sound of one instrument.
- **TABLE** — a little automation sequencer an instrument can run.
- **GROOVE** — swing and timing.
- **WAVE** — draw the 8 wavetable shapes (above INSTR).
- **ECHO** — a tempo-synced delay that echoes T1 onto T2/T3 (below INSTR).
- **PROJECT** — this song: name, tempo, transpose, mode, continuous play
  (**CONT**), and an `UNSAVED` flag when there are changes not yet written to a
  slot. Set **CONT** to **T1 / T2 / T3 / NO** (1+L/R cycles; `OFF` is default) and
  going to FILES doesn't stop playback, and **LOAD swaps the song under the
  running clock** — playing tracks keep their positions and pick up the new song's
  material on the beat. The **chosen channel's playing phrase is carried across
  the load** (planted in reserved slots phrase 51 / chain 39, so keep those free
  in songs you perform with CONT): in LIVE it loops until you queue something new,
  in SONG it plays out and merges. Pick the channel holding your groove (NO for
  drums, T1–T3 for a bass or pad). Samples are silent while FILES is open (they
  return when you leave), and the carried phrase sounds with the new song's
  instruments.
- **FILES** — save, load and manage your songs on the cartridge (below SONG).
- **OPTIONS** — this machine: region, sync, colours (above SONG; PROJECT is
  to its right).

A small map of these screens shows in the top-right of every screen (on Game
Gear, every screen except SONG and WAVE), with the current one highlighted.

The four tracks are **T1, T2, T3** (melodic) and **NO** (noise/drums).

---

## 4. Making a song

SMSGGDJ is built in layers, smallest first — the same idea as LSDJ:

1. **PHRASE** — write a short pattern: 16 steps, each with a note, an
   instrument number, and optionally a command. Tap **1** on an empty step to
   drop a note; **1**-hold + D-pad to change it.
2. **CHAIN** — list the phrases you want, in order, one per row. Add a
   transpose if you want the same phrase a few semitones up or down.
3. **SONG** — place chains into the four track columns, row by row, to build
   the full arrangement.

**How playback flows down a column:** each track plays its chains down the
SONG column and **loops back to the top** when it hits an empty cell. An
empty cell ends that track's loop; a cell pointing at an empty chain is a
one-row rest. Tracks loop independently, so columns of different lengths
create polyrhythms.

**Tip — quick duplicates:** on an empty SONG or CHAIN cell, tap **1** to
insert, then quickly tap **1** again to get the next *free* (blank) chain or
phrase to fill in. Same trick gives a fresh instrument on the PHRASE
instrument column.

### Cloning

Want a copy of a chain or phrase you can edit separately? **Double-tap 1 on a
populated cell:**
- on a **SONG** cell → clones that chain into the next free chain;
- on a **CHAIN** phrase cell → clones that phrase into the next free phrase.

The cell repoints to the new copy, so editing it leaves the original alone.

**OPTIONS → CLONE** sets how chains clone:
- **SLIM** (default) — the new chain reuses the *same phrases* (sharing them).
  Cheap; good for the same melody re-arranged or transposed. Editing a shared
  phrase changes every chain that uses it.
- **DEEP** — also makes fresh copies of every phrase the chain uses, so the
  clone is completely independent. Uses more phrase slots.

Phrase cloning is always an independent copy. If there's no free slot (or DEEP
won't fit), the cursor flashes and nothing is cloned.

---

## 5. Instruments

Each instrument has a **type**, set on the INSTR screen:

- **TONE** — a melodic voice. Volume, an AHD volume envelope (attack / hold /
  decay), transpose, plus vibrato / pitch-sweep / tremolo modulation,
  and an optional table.
- **NOISE** — the noise channel. White or periodic noise, at fixed rates or
  **pitched** (which borrows tone-3 to tune it — great for periodic-noise
  bass).
- **KIT** — a **drum kit of samples** from the ROM's sample bank (drums, vocals…).
  The pool is **up to 8 kits of 8 samples**; the **KIT** field (0–7) picks which kit
  and the note maps chromatically to the 8 slots (wrapping every octave). A **RATE**
  field plays it at **1× / 2× / 4× / .5×** speed (the `S` command overrides per
  note). **TSP** transposes. *(This type was called **SMP** before v0.35.)*
- **WAV** — plays one of the **8 wavetables** you draw on the WAVE screen.
- **FM** — a YM2413 FM voice (needs the SMS **FM Sound Unit**; enable it in
  **OPTIONS → FM**). **PROG** picks one of the chip's 15 ROM patches, **VOL**
  sets the level, **HLD** the length (`F` = ring). **TSP** transposes and a
  **TBL**/**TBS** table drives it like any other voice — the table's volume
  column rewrites the FM level live and its pitch column arps the note
  (re-keying only when the offset changes, so a flat table holds steady). The
  `X` (volume) and `Y` (program) commands also work on FM. A **PRST** field
  picks a custom timbre: `OFF` uses the ROM **PROG** patch, `1`–`8` use one of
  8 ROM-baked presets (LEAD, EPNO, SBASS, BELL, BRASS, PAD, PLUCK, SINE) loaded
  into the chip's user patch. Only one custom timbre sounds at a time (the chip
  has a single user patch), so the most recent triggered preset wins. Edit and
  audition those 8 presets in `tools/fmpatch.html` (a browser tool) and reflash.
  SMS only.
- **FMDRM** — the YM2413's drum kit (rhythm mode). One instrument is the whole
  kit; the **note picks the drum** — C = bass drum, C♯ = snare, D = tom, D♯ =
  cymbal, E = hi-hat (and it repeats every 5 semitones, so any octave works).
  **VOL** sets the level and **HLD** the length (`F` = ring). It uses spare FM
  voices, so it costs none of the 4 tracks. Needs the FM Sound Unit
  (**OPTIONS → FM**); SMS only.

Put an instrument's number next to a note in a PHRASE to play that note with
that sound. Unedited instruments default to full volume with an instant attack
and a short decay tail, so a fresh one makes sound right away.

### INSTR fields in detail

Timing is measured in **ticks** — one tick = one video frame, so 1/60 s on
NTSC and 1/50 s on PAL. Volume is the 0–F musical scale (16 levels).

- **VOL** — peak / hold volume, `0`–`F` (`F` = loudest). The note swells up to
  this level and decays back from it.
- **ATK** / **HLD** / **DCY** — an **AHD volume envelope**: the note ramps up
  from silence (attack), sits at VOL (hold), then ramps down to silence
  (decay).
  - **ATK** `0`–`F` — attack rate, **ticks per volume step** on the way up
    (`0` = instant). A full ramp takes `VOL × ATK` ticks, so at VOL `F`,
    ATK `1` ≈ 0.25 s and ATK `F` ≈ 3.7 s on NTSC.
  - **HLD** `0`–`F` — how long it holds at VOL: `0` = no hold, `1`–`E` =
    nibble × 2 ticks (up to ~0.5 s), **`F` = ∞** (sustain until the note
    retriggers or a `K` cuts it).
  - **DCY** `0`–`F` — decay rate, ticks per volume step on the way down;
    same `VOL × DCY` timing. **`0` = fast decay**: 4 levels per tick
    (15→11→7→3→0, a ~5-frame percussion tail — tight hats and snares on
    noise). For a true instant cut, use `K00`.

  A plain sustained tone is **ATK 0 / HLD F / DCY 0**, a pluck is
  **ATK 0 / HLD 0 / DCY 3**, a pad is **ATK 8 / HLD 4 / DCY 8**. Note an `F`
  (infinite) hold never reaches the decay stage — give HLD a finite value for
  a fade-out tail.

- **TSP** — transpose this instrument in semitones (signed).
- **SWP** — pitch sweep: a single **signed** byte added to the pitch every
  tick (a continuous glide; same engine as the `P` command). Positive (`01`–
  `7F`) slides **down**, negative (`80`–`FF`) slides **up**; bigger = steeper.
- **VIB** — vibrato (pitch wobble). Two nibbles, **speed**·**depth**. Speed
  (high) sets the rate ≈ speed × 0.9 Hz on NTSC (so `1` ≈ 1 Hz up to `F` ≈
  14 Hz); depth (low) sets how wide (`0` = none). E.g. `48` = ~3.8 Hz, depth 8.
- **TRM** — tremolo (volume wobble): same **speed**·**depth** as VIB, but it
  dips the volume (only downward from the set level).
- **TBL** / **TBS** — table to run, and its speed. `1`–`F` step the table one
  row every N ticks; **`N` (TBS 0)** steps it one row **per played note**
  instead — the row carries over from note to note (restarting only when you
  change which table the instrument uses), so a looping table (`H`) runs against
  the phrase for arpeggios and polymeter. See §6.
- **KIT** — drum kit (KIT type only, 0–7): picks which 8-sample kit the note plays from.
- **MODE** / **RATE** — wavetable selection (WAV) / sample speed (KIT: 1×/2×/4×/.5×).

Not every type shows every field — the INSTR screen only lists the ones that
do something for that type:

- **TONE** — VOL, ATK/HLD/DCY, TSP, SWP, VIB, TRM, TBL/TBS.
- **NOISE** — same as TONE plus a MODE (noise tone) field.
- **WAV** — VOL, **HLD** (the wave's length), TSP, TBL/TBS, and a WAVE (0–7)
  selector. ATK/DCY don't show — the wave is gated on/off by volume, so the
  ramps are inaudible; HLD `F` rings the wave until the next note.
- **KIT** — **KIT**, **RATE** and **TSP**. A sample plays as a raw stream on T3,
  so the envelope, pitch mods, volume and tables don't apply; shape
  loudness/fades at convert time in the patcher instead.

A command in a PHRASE (`E`, `P`, `V`, `M`, `L`…) overrides the matching field
for that note.

### Wavetables (WAVE screen)

Eight 32-step waveforms. They boot loaded with presets (sine, triangle, saw,
square, two pulses, organ, random), so the WAVE field on a WAV instrument is
an instant 8-timbre selector. To edit: **1**-hold + Up/Down raises/lowers a
step, **1**-hold + Left/Right draws across. Hold **1** + **2** to stamp the
next preset over the current wave. (On Game Gear the wide canvas is shown in
two halves — **1** + Left/Right jumps between them.)

---

### Echo (ECHO screen)

A tempo-synced delay built into the engine. Reach it with **2 + Down** from
INSTR. It copies whatever **T1** is playing and replays it, quieter, on T2
(and optionally T3), delayed:

- **MODE** — off / `T2` / `T2T3` (one or both echo channels).
- **TAP1 / TAP2** — the delay of each tap **in rows**, so it tracks tempo and
  swing (2 rows = an 8th note, 4 = a quarter…).
- **RD1 / RD2** — how much quieter each tap is (attenuation added).
- **STER** — on Game Gear, pans tap 1 left and tap 2 right (ping-pong).
- **TSP1 / TSP2** — transpose each tap in semitones (octave-up shimmer, fifths…).

Echo only sounds on T2/T3 when your song isn't using them — the moment a note
plays there, the song takes the channel back. T3 also yields to samples and
wavetables.

## 6. Tables

A **table** is a 16-row automation strip an instrument can run while a note
holds: a volume column, a pitch column (for arpeggios), and a command column.
Assign a table to an instrument, or trigger one with the `A` command. The `H`
command inside a table loops it. Tables are how you get LSDJ-style arps,
stutters and evolving timbres without writing them out by hand.

---

## 7. Command reference

A command sits in a PHRASE step (or a TABLE row) and shapes that note. Most
take a two-digit parameter `xy`.

| Cmd | Name | What it does |
|---|---|---|
| `A` | Table | Run a table on **this note** (`A0`–`AF` pick the table, `A20` = none) — a one-shot override like `B`/`Y`: it wins for the note it's on, then the instrument's own table governs again. Put it next to a note |
| `B` | Wave bank | Set this note's wavetable 0–7, overriding the instrument's wave (`B0`–`B7`, just that note) |
| `C` | Chord | Looping arpeggio: note, +x, +y semitones (`C00` off) |
| `D` | Delay | Delay the note by a number of ticks |
| `E` | Envelope | Re-slope the AHD ramps live: `Exy` sets ATK = x, DCY = y (hold is left alone) |
| `F` | Finetune | Detune slightly (positive = sharper) |
| `G` | Groove | Switch groove from this row (this track) |
| `H` | Hop | PHRASE: end this track's phrase **immediately** — the H row takes no time, play jumps straight back to row 0 in the same tick (only this channel). Put `H` on the row *after* your last step to loop tightly with no wasted 16th. TABLE: loop back to a row — **also immediate**, so a looping table runs with no wasted step (great for tight arps) |
| `I` | Iteration | An 8-bit play mask over **this phrase's play count**: on the Nth play of the phrase the note sounds if bit (N mod 8) is set. `IFF` = always, `I00` = never, `I55`/`IAA` = odd/even plays, `I0F` = first four of eight, `IF0` = last four. Lets one phrase vary across its repeats without cloning |
| `J` | Jump (transpose) | A sibling to `I`: `Jxy` transposes the note by **x semitones** (`0`–`7` up, `8`–`F` = −8…−1, so `F` = −1) on the plays whose **(play mod 4)** bit is set in the 4-bit mask **y**. `J00` never, `J2F` = +2 always, `J21` = +2 on every 4th play; varies pitch across a phrase's repeats without cloning |
| `K` | Kill | Cut the note after xy ticks (`K00` = instant; also stops samples) |
| `L` | Slide | Glide (portamento) to this note |
| `M` | Amp mod | Tremolo: speed x, depth y |
| `N` | Noise | Override noise mode/rate for this note |
| `O` | Output (pan) | **Game Gear stereo:** `O11` centre, `O10` left, `O01` right |
| `P` | Pitch bend | Continuous bend (positive bends down) |
| `R` | Retrigger | Re-fire the note every y ticks; x fades the volume each re-fire (TONE/NOISE — ignored on samples) |
| `S` | Speed | Sample playback rate: `S01` = 2× (up an octave, half length), `S02` = ½× (down an octave), `S03` = 4× (up two octaves); `S00` = normal |
| `T` | Tempo | Set tempo in BPM |
| `V` | Vibrato | One-shot vibrato: speed x, depth y |
| `W` | Wait-skip | Shorten this row (for shuffle/swing fills) |
| `X` | Volume | Set this note's volume `0`–`F` (accent). Use it on a note — the attack ramps to that level |
| `Y` | FM program | Set this note's FM patch `1`–`15`, overriding an FM instrument's PROG (for FM voices) |
| `Z` | Probability | Chance the note triggers: `Z00` never, `ZFF` always, in between rolls a fresh random each play (`Z80` ≈ 50/50) |
| `Q` | Echo on/off | `Q00` mutes the echo, any non-zero (`Q01`) turns it back on — live, for echo'd vs dry sections. Your ECHO-screen settings (mode, taps, feedback…) are untouched, just gated; echo starts **on** each time you press play |

### Varying a phrase — the I / J / Z trio

`I`, `J` and `Z` are built to make **one phrase sound different across its
repeats**, so you can avoid cloning a phrase just to add a fill or a variation:

- **`I`** — *whether* the note plays, on a fixed schedule (the play-count mask).
- **`J`** — *what pitch* it plays, transposing on a schedule (a sibling mask).
- **`Z`** — *whether* it plays, by random chance.

`I` and `J` are deterministic and loop with the phrase's play count (so a fill
lands in the same place every time round), while `Z` adds genuine randomness.
Combine them — e.g. a steady hat with `Z` ghost notes, an `I` accent every 4th
bar, and a `J` octave jump on the last repeat — and a single 16-step phrase
carries a whole evolving part.

---

## 8. Timing & grooves

**Grooves** are the clock. A groove is a short list of tick-counts per row
(ticks run at the fixed 50/60 Hz frame rate), so uneven pairs (like `8,4`)
shuffle the feel. The GROOVE screen edits the 16 ticks of one groove; the `G`
command switches groove mid-song.

There are 16 grooves. The groove number is an **editable field** at the top of
the GROOVE screen: move the cursor **up** past the first tick onto the number,
then **hold 1 + Left/Right** to pick which groove you're editing.

Tempo *is* the groove — there's no separate tempo. **TMPO** (on PROJECT)
shows the BPM of the current groove and Left/Right steps it tick-by-tick
through the achievable BPMs (e.g. 150 → 128 → 112 on NTSC), shifting the
whole groove together so your swing is kept. The `T` command sets a flat
tempo by BPM mid-song. Because the groove is the grid, anything beat-locked
(like echo taps) is measured in rows and follows the tempo automatically.

**TSP** (on PROJECT) transposes the whole song up or down in semitones —
handy for matching a vocalist or another instrument. It doesn't move sample
drums.

---

## 9. Live mode

PROJECT → **MODE: LIVE** turns the SONG screen into a performance launcher.
Instead of playing straight down, each chain **loops**, and you trigger
changes by hand:

- On the SONG screen while playing, **2-hold + 1** on a cell **queues** it
  for that track. It swaps in at the **next bar** (phrase boundary), so changes
  land on the beat. A hollow `<` marks a queued cell; a solid `>` marks what's
  playing.
- Queue an **empty** cell to stop that track at the next bar.
- **2-hold + 1** on the cell that's *already playing* queues a **stop at the end
  of that chain** — the loop plays out, then the track drops away. An `X` marks
  the playing cell while the stop is pending; tap again to cancel.
- For an instant stop: **PAUSE / START** stops everything; the **track header**
  gesture (2-hold + 1 on the header row) stops a single track immediately.

Switch back to **MODE: SONG** for normal start-to-finish playback.

---

## 10. Saving & loading — the FILES screen

Songs live in the cartridge's battery-backed save RAM (or your emulator's
`.sav` file). Manage them on the **FILES** screen (below SONG on the map).
Playback stops while you're here.

FILES shows a **packed list** of your saved songs — `00`, `01`, `02`, … with an
8-character name beside each — plus one **empty slot** at the end whenever
there's room for another song. The list has no gaps: deleting a song closes
the space up. The list **scrolls** (12 rows at a time) so you can hold up to 32
songs. A **song count** sits above the list, and a small **SRAM / FREE / SONG**
readout (in KB — total, free, and the selected song's size) sits under the map.

**Moving around and naming**

- **Up / Down** — pick a slot (including the trailing empty one); the list
  scrolls to follow.
- **Hold 1 + Up / Down** — change the letter under the name cursor (it cycles
  blank → A–Z → punctuation → 0–9).
- **Hold 1 + Left / Right** — move the name cursor along the 8 characters (wraps).

The name is stored *inside* the song, so it travels with it.

**The action menu**

**Hold 2, then tap 1** to open the action menu on the right; tap **1** again (or
pick **CANC**) to close it. With the menu open, **Up / Down** choose an action
and **tap 1** runs it and closes the menu:

- **SAVE** — write the current song to the selected slot. On an existing slot it
  overwrites; on the **empty slot** it creates a new file. *Saving only happens
  when you press SAVE* — your edits aren't auto-saved, so save often.
- **LOAD** — load the selected song. On the **empty slot** it blanks the working
  song instead (a fresh start).
- **CLEA** (clear) — delete the selected song and close the gap (the remaining
  songs slide down to reclaim the space).
- **PRGP** (purge phrases) — blank every phrase **not reachable** from the SONG
  (song → chain → phrase), freeing those phrase slots and shrinking the save. Acts
  on the **working song** (not the selected save slot) — save afterwards to bank it.
- **PRGC** (purge chains) — blank every chain **not placed in the SONG**, freeing
  those chain slots. Also acts on the working song.
- **CANC** — close the menu, do nothing.

**PRGC** and **PRGP** delete on-the-side ideas (a chain you never placed, a phrase
you never used), so they ask first: the word shows **`SURE`** — tap **1** again to
go through (any d-pad move cancels). After running, the header shows **`FREED nn`**
(how many records were reclaimed). They only blank *unused* records and never
renumber the rest, so nothing in your song breaks.

On a real flashcart with a battery, SAVE persists instantly. In an emulator,
the `.sav` file is usually written when you **quit the emulator** — so save
in SMSGGDJ, then close the emulator normally, to keep your songs.

> **OPTIONS → SRAM** tells you if save RAM was found. If it says `NONE`, the
> cart has no battery save — songs are temporary and lost on power-off
> (emulator save-states still work).

---

## 11. Options (the OPTIONS screen)

Settings that belong to the *machine*, not the song:

- **VID** — video region: **AUTO** (follow auto-detection, the default),
  **PAL**, or **NTSC**. Affects tuning and tempo math (the refresh rate itself
  is fixed by the console). Leave it on AUTO and it detects PAL/NTSC at boot;
  force PAL/NTSC to override a misreporting setup. Your choice persists in SRAM
  and applies instantly. Game Gear is NTSC-only.
- **SRAM** — save-RAM readout (read-only).
- **SYNC** — clock sync mode (see below).
- **COLR** — UI colour palette **0–7** (8 background/foreground pairs). Recolour
  any of them in `tools/palette.html` and reflash. Your choice persists in SRAM
  (saved when you save a song).
  Changes apply instantly.
- **CLONE** — SLIM or DEEP, how chain cloning works (see *Cloning*).
- **FM** — `OFF`/`ON`: enable the YM2413 FM Sound Unit (for FM instruments).
  On hardware with the FM unit (or SMSPlus) FM plays alongside the PSG; some
  emulators route the single output to FM instead. Default OFF. SMS only.

---

## 12. Syncing to other gear

SMSGGDJ can lock its tempo to another machine over **controller port 2**
(Master System) — useful for jamming with another SMSGGDJ, a **genmddj** (Mega
Drive), a Game Gear, or analog-clock gear. Set it on **OPTIONS → SYNC**:

- **OFF** — no sync (default).
- **OUT** — this unit is the **master**; it sends one clock per row while
  playing. Another SMSGGDJ (or a genmddj) set to **IN** locks to it at any tempo.
- **PULSE** — sends a simple analog-style pulse (2 PPQN) for gear like
  Volca / Pocket Operator.
- **IN** — this unit **follows** an **OUT** master (one row per clock). Press
  Play and it waits (top bar shows **WAIT**) until the clock starts, then locks
  on. While following, the master's clock drives the timing, so your stored
  groove and the `W` command are ignored (and restored when you leave IN).
- **IN24** — follows a **24-PPQN** source (six clocks per 16th-note row): the
  **ESP32 Ableton Link bridge**, ares-link-sync, or any 24-PPQN sender. Same
  WAIT-then-lock behaviour as IN. *(Before v0.33 this was just "IN".)*

Cross-sync with **genmddj** uses the identical wire protocol: SMSGGDJ `OUT` ↔
genmddj `IN`, and either unit's `IN24` follows the Link bridge.

The top bar shows a small arrow by the transport: ▶ when sending (OUT), ◀
when following (IN or IN24), a pulse mark for PULSE.

**Cables:** Master-to-Master uses a straight 3-wire link on port 2 (pins 9,
7, 8). Master System to Game Gear uses a Master Link cable. Game Gear to Game
Gear uses a standard Gear-to-Gear cable. The slave unit reads whichever cable
is plugged in automatically. (Sending a clock as master needs an *export*
Master System — Japanese units can't drive the port.)

**Ableton Link:** with `SYNC: IN24` you can follow Ableton Live (or any Link
app) using the companion **smsggdj-link-esp32** bridge — a small ESP32 board
that joins your Link session over WiFi and feeds the clock into port 2.
SMSGGDJ then plays in time with Live's tempo and transport. Build and wiring
details are in the bridge's repo (github.com/little-scale/smsggdj-link-esp32)
and in HARDWARE.md.

---

## 13. Game Gear notes (GGDJ)

The Game Gear build shows the same tracker on the smaller screen — the same
16 rows, with the layout tightened to fit. A few differences:

- **START** is Play/Stop (there's no PAUSE button).
- **Stereo!** The `O` command pans per channel: `O10` hard left, `O01` hard
  right, `O11` centre. Put alternating `O10`/`O01` in a table for an
  auto-panner. (On Master System the same song plays in mono — pan data is
  simply ignored.)
- The WAVE screen shows its 32 steps in two halves; **1** + Left/Right flips
  pages.

---

## 14. Quick reference

```
MOVE        D-pad
INSERT      1 tap
EDIT        1 hold + D-pad        (L/R small, U/D big)
PASTE       1 double-tap
CUT         1 hold + 2 tap
SELECT      1 hold + 2 held (~1/3s)
BACK        2 tap
SCREENS     2 hold + D-pad
PLAY/STOP   2 hold + 1   (or PAUSE / Game Gear START)
PLAY SONG   2 hold + 1 double-tap   (full song from the contextual row)
```

```
SCREEN MAP
   OPTIONS  PROJECT                  WAVE
   SONG     CHAIN    PHRASE   INSTR   TABLE
   FILES    GROOVE                    ECHO
```

Have fun. Save often.
