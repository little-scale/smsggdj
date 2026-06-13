# SMSGGDJ — User Manual

An LSDJ-inspired music tracker for the Sega Master System and Game Gear.
Make music on real hardware (via flashcart) or in an emulator, using just
the D-pad and two buttons.

There are two builds from the same tracker:
- **`smsdj.sms`** — Master System (full-size screen).
- **`smsdj.gg`** — Game Gear (GGDJ): fits the handheld screen, and adds
  real stereo panning.

Everything in this manual applies to both unless noted.

---

## 1. Getting started

1. Put the `.sms` (or `.gg`) file on your flashcart's SD card, or open it
   in an emulator.
2. On boot you'll see the SMSGGDJ logo, then the tracker opens on a **demo
   song** that's already loaded. Press **Play** (see controls below) to hear
   it — it's a tour of what the tracker can do.
3. To start your own song, go to the **PROJECT** screen and choose **NEW**
   (described in *Saving & Loading*).

The demo plays on every fresh boot, so you can always hear something
immediately.

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
   [OPTIONS] [PROJECT]                    [WAVE]
   [ SONG  ][ CHAIN ][ PHRASE ][ INSTR ][ TABLE ]
                     [ GROOVE ]
```

- **SONG** — the arrangement: which chains play on each of the 4 tracks.
- **CHAIN** — a list of phrases (with transpose), played in order.
- **PHRASE** — 16 steps of notes, instruments and commands. The heart of it.
- **INSTR** — design the sound of one instrument.
- **TABLE** — a little automation sequencer an instrument can run.
- **GROOVE** — swing and timing.
- **WAVE** — draw the 8 wavetable shapes (above INSTR).
- **PROJECT** — this song: tempo, transpose, mode, save/load.
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

- **TONE** — a melodic voice. Volume, a software envelope (fade up/down),
  note length, transpose, plus vibrato / pitch-sweep / tremolo modulation,
  and an optional table.
- **NOISE** — the noise channel. White or periodic noise, at fixed rates or
  **pitched** (which borrows tone-3 to tune it — great for periodic-noise
  bass).
- **SMP** — plays a **sample** from the ROM's sample bank (drums, vocals…). A **RATE** field plays it at NORM / 2× / HALF speed (the `S` command overrides per note).
- **WAV** — plays one of the **8 wavetables** you draw on the WAVE screen.

Put an instrument's number next to a note in a PHRASE to play that note with
that sound. Unedited instruments default to full volume, so a fresh one makes
sound right away.

### Wavetables (WAVE screen)

Eight 32-step waveforms. They boot loaded with presets (sine, triangle, saw,
square, two pulses, organ, random), so the WAVE field on a WAV instrument is
an instant 8-timbre selector. To edit: **1**-hold + Up/Down raises/lowers a
step, **1**-hold + Left/Right draws across. Hold **1** + **2** to stamp the
next preset over the current wave. (On Game Gear the wide canvas is shown in
two halves — **1** + Left/Right jumps between them.)

---

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
| `A` | Table | Start/switch a table (`A20` = off) |
| `C` | Chord | Looping arpeggio: note, +x, +y semitones (`C00` off) |
| `D` | Delay | Delay the note by a number of ticks |
| `E` | Envelope | Override the instrument's volume envelope |
| `F` | Finetune | Detune slightly |
| `G` | Groove | Switch groove from this row (this track) |
| `H` | Hop | PHRASE: end / jump. TABLE: loop |
| `I` | Iteration | Play this note only on certain loop passes — variation without copies. `I20` = odd passes, `I21` = even, `I40` = every 4th, `I00` = never |
| `K` | Kill | Cut the note after xy ticks (`K00` = instant; also stops samples) |
| `L` | Slide | Glide (portamento) to this note |
| `M` | Amp mod | Tremolo: speed x, depth y |
| `N` | Noise | Override noise mode/rate for this note |
| `O` | Output (pan) | **Game Gear stereo:** `O11` centre, `O10` left, `O01` right |
| `P` | Pitch bend | Continuous bend |
| `R` | Retrigger | Re-fire the note every y ticks, stepping volume by x |
| `S` | Speed | Sample playback rate: `S01` = 2× (up an octave, half length), `S02` = ½× (down an octave); `S00` = normal |
| `T` | Tempo | Set tempo in BPM |
| `V` | Vibrato | One-shot vibrato: speed x, depth y |
| `W` | Wait-skip | Shorten this row (for shuffle/swing fills) |

---

## 8. Timing & grooves

Tempo is set on PROJECT (**TMPO**) or with the `T` command. **Grooves** add
swing: a groove is a short list of tick-counts per row, so uneven pairs (like
`8,4`) shuffle the feel. The GROOVE screen edits them; the `G` command
switches groove mid-song.

**TSP** (on PROJECT) transposes the whole song up or down in semitones —
handy for matching a vocalist or another instrument. It doesn't move sample
drums.

---

## 9. Live mode

PROJECT → **MODE: LIVE** turns the SONG screen into a performance launcher.
Instead of playing straight down, each chain **loops**, and you trigger
changes by hand:

- On the SONG screen while playing, **2-hold + 1** on a cell **queues** it
  for that track. It swaps in when the current chain finishes (so changes
  land on the beat). A small triangle marks a queued cell; a solid triangle
  marks what's playing.
- Queue an **empty** cell to stop that track at the next boundary.
- **2-hold + 1** on the cell that's *already playing* stops that track now.
- **PAUSE / START** stops everything.

Switch back to **MODE: SONG** for normal start-to-finish playback.

---

## 10. Saving & loading

Songs live in the cartridge's battery-backed save RAM (or your emulator's
`.sav` file). On the **PROJECT** screen:

- **SLOT** — choose save slot 1, 2 or 3.
- **SAVE** — write the current song to the chosen slot. *Saving only happens
  when you press SAVE* — your edits aren't auto-saved, so save often.
- **LOAD** — load the song from the chosen slot.
- **NEW** — start a blank song. **Press it twice** (it shows `SURE?` first)
  because it clears your work.
- **DEMO** — reload the built-in demo song. Also a two-press confirm.

On a real flashcart with a battery, SAVE persists instantly. In an emulator,
the `.sav` file is usually written when you **quit the emulator** — so save
in SMSGGDJ, then close the emulator normally, to keep your songs.

> **OPTIONS → SRAM** tells you if save RAM was found. If it says `NONE`, the
> cart has no battery save — songs are temporary and lost on power-off
> (emulator save-states still work).

---

## 11. Options (the OPTIONS screen)

Settings that belong to the *machine*, not the song:

- **VID** — PAL / NTSC region. Affects tuning and tempo math. Auto-detected
  on Master System; fixed NTSC on Game Gear.
- **SRAM** — save-RAM readout (read-only).
- **SYNC** — clock sync mode (see below).
- **COLR** — colour scheme: KIDD (default), WHT, GRN, AMBR, CYAN, PINK, NEON.
  Changes apply instantly.
- **CLONE** — SLIM or DEEP, how chain cloning works (see *Cloning*).

---

## 12. Syncing to other gear

SMSGGDJ can lock its tempo to another machine over **controller port 2**
(Master System) — useful for jamming with another SMSGGDJ, a Game Gear, or
analog-clock gear. Set it on **OPTIONS → SYNC**:

- **OFF** — no sync (default).
- **OUT** — this unit is the **master**; it sends a clock while playing.
- **IN** — this unit **follows** an incoming clock. Press Play and it waits
  (top bar shows **WAIT**) until the clock starts, then locks on.
- **PULSE** — sends a simple analog-style pulse (2 PPQN) for gear like
  Volca / Pocket Operator.

The top bar shows a small arrow by the transport: ▶ when sending (OUT), ◀
when following (IN), a pulse mark for PULSE.

**Cables:** Master-to-Master uses a straight 3-wire link on port 2 (pins 9,
7, 8). Master System to Game Gear uses a Master Link cable. Game Gear to Game
Gear uses a standard Gear-to-Gear cable. The slave unit reads whichever cable
is plugged in automatically. (Sending a clock as master needs an *export*
Master System — Japanese units can't drive the port.)

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
```

```
SCREEN MAP
   OPTIONS  PROJECT                  WAVE
   SONG     CHAIN    PHRASE   INSTR   TABLE
                     GROOVE
```

Have fun. Save often.
