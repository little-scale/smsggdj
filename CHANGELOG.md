# Changelog

All notable, user-facing changes to **SMSGGDJ**. Dates are YYYY-MM-DD.
The git history has the full detail; this is the curated summary.

## v0.38 — unreleased

### Added
- **CONT tempo glide (prototype).** After a CONT load, the tempo now **ramps**
  from the old song's BPM to the new song's instead of jumping. It plays a scratch
  groove whose average frames-per-row steps toward the target each bar, then hands
  off to the new song's real groove. Skipped when the tempos already match or when
  clock-slaved (SYNC IN/IN24). Because tempo is quantised (integer frames per row),
  this MVP steps through whole rungs — smooth for small changes, a little steppy
  for big jumps; a finer (fractional-average) version can follow.
- **PROJECT → SLID** sets the tempo-slide length: **OFF** (instant, the old jump)
  or **1–16 bars**. Sits below CONT; default 4 bars. (Not yet persisted across a
  reboot — resets to 4.)
- **CONT handover track marker.** On the SONG header, the track CONT is set to
  carry shows a **`*`** beside its name whenever CONT is on, so you can see at a
  glance which track will bridge the next load (it becomes `>` while it's actually
  bridging).

### Changed
- **Switching MODE (SONG ↔ LIVE) no longer stops the transport.** Toggling the
  PROJECT **MODE** field while playing now flips live: from the next bar each
  track just changes how it advances — in LIVE it loops its current chain, in
  SONG it resumes walking the arrangement from where it is. So you can play a song
  through, drop into LIVE to loop/jam a section, and return to SONG without
  breaking playback. Pending LIVE queues are cleared on the switch.
- **CONT LOAD now drops the new song in beat-matched from its top.** Loading a
  song while CONT is playing (SONG mode) restarts every track at the **top of the
  new song** (song row 1) but keeps each track's **position within the phrase**
  (the 16th-note step it was on), so the incoming song enters on the beat with no
  rhythmic hiccup — instead of continuing from wherever the old song happened to
  be. The CONT channel (T1/T2/T3/NO) still carries its playing phrase across the
  load as a bridge: in SONG it plays once and then rejoins the others at the top;
  in LIVE it **loops** and holds the groove until you queue a chain from the new
  song. **In LIVE the other tracks are silenced on the load** — only the carried
  bridge keeps playing, and you bring the rest back in by queuing chains, so the
  transition stays performer-driven (they no longer auto-play the new song).
- **The bridging track no longer shows a false playhead on the SONG grid.** The
  bridge plays a reserved off-grid chain, so the old `>` on that track's row
  wrongly flagged a cell as already-playing — now suppressed, so you can queue and
  newly trigger that chain. Instead, a **`>` appears beside the track's name**
  (T1/T2/T3/NO header) while it's holding the bridge (and clears the moment you
  trigger a chain there), so you can still see which track is carrying the groove.
  In LIVE, triggering **any** row on the bridging track — including the very first
  — reliably queues that chain (the "tap the row you're on = stop" gesture no
  longer misfires on the bridge, which has no song position).
- **Fixed as part of the above:** the CONT bridge phrase now actually loops in
  LIVE. The reserved handoff chain is planted outside the song grid, so the old
  "reload = loop" step re-derived a chain from the song and dropped the bridge
  after one bar; it now loops the reserved chain in place until a chain is queued.
- **The CONT handoff slots are now permanently reserved**, so the bridge always
  lands. It borrows the last phrase and last chain; previously, if the loaded song
  happened to use those slots the whole handoff was silently skipped (a chain from
  the new song loaded instead). The editor now caps at **51 phrases / 39 chains**
  (the top slot of each is reserved), so a song can't occupy them. The pools stay
  full-size, so the save format is unchanged; a song written before this that used
  the last phrase/chain still loads (a CONT load overwrites those slots).
- **The CONT bridge now keeps its own instrument sound.** Previously the carried
  phrase played through whatever the *newly loaded* song had at those instrument
  numbers, so the timbre could change completely across a load. Now the carried
  instrument (the first note's, or the channel's current one) is snapshotted and
  baked into a reserved instrument slot, and the bridge's notes are pointed at it —
  so it sounds the same through the transition. Cost: **15 usable instruments**
  (the last slot is reserved; save format unchanged). Note a table the instrument
  uses still reads the new song's tables.

## v0.37 — 2026-07-04

### Added
- **Note range extended up to B11** for pitched noise (as high as the SN76489
  goes). Notes above A#9 show a `+` marker and are re-labelled from `A-2` up
  (`A-2+`, `A#2+`, …) — the extended range reuses the low names + `+`, so the
  display stays 3 chars. Existing notes are unaffected (the low end is unchanged,
  so saved note indices don't shift).
- **FM instruments reach lower octaves.** The YM2413 note table is voiced two
  octaves below the PSG note of the same index, so walking the note pitch field
  (including up into the new `+` range) covers the whole FM range directly — no
  per-instrument octave setting. The note name is PSG-referenced, so an FM
  instrument sounds two octaves below its label.
- **Per-instrument FINE tune** on TONE and FM instruments (INSTR screen). A
  signed offset (`00` = no change, `01` = a touch sharper, `FF` = a touch
  flatter) — applied to the PSG period on TONE and to the YM2413 F-number on FM.
  On TONE it's the base pitch trim the `F` command then tweaks per-row. Left/right
  nudge by 1; up/down step by a coarser amount — 16 on TONE, but only 4 on FM (an
  FM F-number unit is ~6 cents, so a 16-step would leap nearly a semitone and
  audibly shift the patch's brightness). FINE never alters the FM patch itself; it
  only detunes the pitch.
- **Tunable FM drums.** The FMDRUM instrument gains a `DRUM` field: `ALL` (the
  default — the note picks the drum at a fixed pitch, as before) or a single drum
  (`BD`/`SD`/`TOM`/`TCY`/`HH`). Pick a single drum and the **note's pitch drives
  that drum's carrier frequency** (the classic YM2413 drum-tuning trick), so you
  play tuned/melodic drums. Note the chip shares carriers — `SD`+`HH` are on one
  rhythm channel, `TOM`+`TCY` on another — so two of a shared pair can't hold
  different pitches at the same instant. Existing songs default to `ALL`.
- **CONT — continuous play across FILES and LOAD** (PROJECT, below MODE). Set
  `CONT` to **T1 / T2 / T3 / NO** (1+L/R cycles; `OFF` is the default) and
  entering FILES no longer stops the transport: whatever chains are playing keep
  sounding while you browse, and **LOAD swaps the song under the running clock** —
  the playing tracks keep their grid positions and seamlessly pick up the new
  song's material, so you can transition between songs in a set without dropping
  the beat. **The chosen channel's playing phrase is carried across the load**:
  it's stashed before the swap and planted in the reserved transition slots
  (**phrase 51 / chain 39**), so that part keeps rolling through the load — in
  LIVE it loops until you queue new material, in SONG it plays out and merges into
  the new song's column. Pick the channel that carries your groove (NO for a
  drum part, T1–T3 for a bassline or pad). Notes: the carried phrase triggers the
  *new* song's instrument numbers (RAM holds one song, so timbre follows the
  load); samples (KIT) are silent while FILES has the cartridge SRAM mapped over
  the sample pool (hardware constraint — tone, noise, wave and FM keep playing)
  and return when you leave; a transition dirties phrase 51 / chain 39 in the
  working copy, so treat those slots as reserved if you perform with CONT. If the
  incoming song already **uses** phrase 51 or chain 39, the carry skips rather
  than clobber that material (the carried channel just plays the new song's
  content at its position). Any **queued LIVE cells are cleared on a load** —
  they referenced the old song's grid.
- **FILES header restyled** — a genmddj-style dash rule around the `nn SONGS`
  count (the SONG-screen title rule from the last dev build is gone).
- **Adjustable cursor key-repeat** on the OPTIONS screen: **RDLY** (repeat
  delay, 1–60 frames — how long a held d-pad direction waits before auto-repeat)
  and **RSPD** (repeat interval, 1–30 frames — how fast it then fires). 1+L/R
  nudges each. Defaults are the old fixed values (14 / 3). Persisted with the
  rest of the machine config. On the **Game Gear** the **FM** field is omitted
  from OPTIONS (the YM2413 is SMS-only), so RDLY/RSPD take its place.

### Changed
- **Game Gear hides the FM-only features.** The OPTIONS **FM** toggle is gone
  (above) and the instrument **TYPE** cycler stops at **WAV** — `FM` and `FMDRM`
  aren't selectable on GG, since the YM2413 is SMS-only and would only play
  silence. An FM instrument carried in from an SMS-made song still displays and
  can be cycled *away* from; it just can't be newly selected.
- **The CONT and key-repeat settings are persisted** with the rest of the
  machine config (the `CF` block grows to 10 bytes, v3 — legacy 8-byte v2 and
  7-byte v1 configs still load, with the missing fields defaulting).
- **`tools/savetool.html` is now SMDJ4-native** — it builds and edits current
  cart images directly (slots, config, per-slot view/download as `.smdj4`)
  instead of the old SMDJ3 editor + read-only SMDJ4 view; legacy SMDJ3 saves
  and `.smdj` songs are migrated to SMDJ4 when dropped. All the browser tools
  now share the block/save geometry from `tools/smdj4.js`, and a `make test`
  target runs the format self-tests.
- **`DCY 0` is now a fast decay, not an instant cut** (ported from genmddj).
  It steps the volume down 4 levels per tick — 15→11→7→3→0, a ~5-frame
  (~66 ms NTSC / 80 ms PAL) percussion tail — instead of hard-cutting to
  silence in one frame with an audible click. The main win is tight hats and
  snares on the noise channel. An instant cut is still available via `K00`,
  which is now also a **hard** kill: it detaches a running table so its VOL
  column can't revive the cut note. Existing songs using `DCY 0` gain the
  short tail (no save-format change).

### Fixed
- **Switching an instrument to KIT now defaults to kit 0, not 3.** The KIT
  number shares its record byte with DCY (whose default is 3), and the type
  switch wasn't re-seeding it — so a fresh KIT instrument read back kit 3. It
  now seeds kit 0 (like the other types seed their own defaults).
- **The `J` command's nibbles now match genmddj: `Jxy` = repeat mask (x) +
  signed transpose (y).** They were swapped (transpose in x, mask in y), and the
  repeat index is now `(play−1) mod 4` like genmddj, so songs/muscle-memory carry
  over. Transpose still `0`–`7` = +0…+7, `8`–`F` = −8…−1.
- **The ECHO screen fields respond to up/down for a coarse step.** Up/down did
  nothing before; now TAP/REDUCE step by 4 and TSP by an octave (left/right stay
  ±1). *(Earlier in this cycle TAP/REDUCE up/down slammed to min/max; a step of 4
  is easier to dial in.)*
- **An FM instrument driven by a table no longer rings after the song stops.**
  Stop keyed the FM voices off, but a table can hold a voice keyed-on (defeating
  the HLD auto-key-off), so keying off just started the patch's release, which
  rang out. Stop now also forces the FM channels to silence.
- **An `H` command on a table's first step no longer hangs the tracker.** A
  self-referential or all-`H` table (e.g. `H00` on row 0 looping to itself)
  span forever within a tick; it now detaches the malformed table and the note
  plays on.
- **`K00` no longer makes channels repeat a row / fall out of sync.** The cut
  command clobbered the sequencer's channel-loop index (via the FM key-off), so
  later tracks skipped a tick each time it fired. The index is now preserved.
- **Tables and FM instruments go silent when the song stops.** Stop only
  silenced the PSG; the FM voices held their note. Stop now keys off every FM
  voice and drum (rhythm mode stays enabled for a clean resume).
- **The `R` (retrigger) interval can no longer be dialled to 0.** `Rx0` armed no
  retrigger (a dead value); editing an `R` command's parameter now floors the
  interval nibble at 1, so it steps straight to `Rx1` (phrase and table columns).
  Note that a very small interval re-strikes faster than the envelope decays, so
  it sustains — for audible rolls, use `R08`-ish with `DCY 0` (see the manual).
- **KIT (sample) instruments play again.** A regression in the CONT work left the
  new `sram_live` guard clobbering the accumulator that held the sample count, so
  the kit-slot bounds check silenced *every* KIT note (not just those over an
  empty slot). The count is now grabbed before the guard runs.
- **A save can no longer overwrite the OPTIONS config block.** Bank-0 heap
  placement (saving *and* compaction) is now capped below the config at `$3F60`
  ($1F60 on 8 KB carts): a near-raw blob bumps to bank 1 on a 32 KB cart or
  reports SRAM FULL on a single-bank cart. Previously a pathological
  incompressible song could clobber the stored palette/sync/video/FM.
- **Migrated saves keep their config.** `tools/smdj4.js buildSav` wrote the
  config block at a superblock offset the ROM never reads; it now lands at the
  real `$3F60`/`$1F60`, so a save migrated with `tools/migrate.html` boots with
  its palette/sync/video/FM intact.

## v0.36 — 2026-07-02

### Added
- **PROJECT screen shows the loaded song's NAME and an UNSAVED indicator.** A
  `NAME` readout displays the current song's name; below the fields, `UNSAVED`
  appears whenever the song has changes not yet written to a slot (blank once
  it matches the last save/load).
- **SONG screen dressed up** with a genmddj-style dashed rule from the title
  across to the screen map, plus a tick above the row-index column.
- **`tools/sramconvert.html`** — a new browser tool that converts a song save
  between a flashcart's raw `.srm` and SMS Plus's gzip-compressed `.sav`, both
  directions, so you can move a song between the cart and the emulator.
- **Song viewer in `tools/savetool.html`** — click a slot to see that song's
  arrangement, chains, phrases (notes/instruments/commands), instruments and
  grooves, for SMDJ4 saves.

### Changed
- **`tools/als2smdj.html` uses the full song pools.** The Ableton importer now
  builds native SMDJ4 songs with all **52 phrases / 40 chains** (it was capped at
  the old 32/32), so larger Live sets fit before it has to truncate.

### Fixed
- **Noise plays correctly on the first note after a fresh load.** `psg_init` set
  the noise-control shadow to white/rate-0 but never wrote it to the chip, and the
  flush only writes the noise register on a *change* — so a song whose first noise
  note used the default value found shadow==sent and skipped the write, leaving the
  PSG's power-on (pitched/periodic) noise state playing until you toggled the mode.
  Init now asserts the noise register on the chip.
- **The Game Gear ROM now identifies as a Game Gear cartridge.** The `.gg` header
  carried an SMS "Export" region code (the `.SMSTAG` default has no GG option), so
  a flashcart's system auto-detect could run it in **Master System mode** — a
  letterboxed margin on the GG LCD and a scrambled palette (SMS 6-bit CRAM
  misreading the GG's 12-bit colour writes). The build now stamps a Game Gear
  region code (`$6x`) into the `.gg` header at link time, so it runs in native GG
  mode deterministically. The `.sms` build is unchanged. (Latent since the GG
  flavour was first added; whether it surfaced depended on how the flashcart
  resolved the contradictory `.gg`-extension-but-SMS-header signal.)

## v0.35 — 2026-06-30

### Added
- **Play an edit in song context: 2-hold + double-tap 1.** While editing a chain or
  phrase, a quick double-tap of 1 (holding 2) plays the **whole song from the
  contextual row** instead of soloing what you're looking at — A/B a part on its
  own versus in the full mix. A single tap still does the per-screen preview.
- **OPTIONS screen shows the version + build hash** (above VID), so you can tell
  which build a cart/emulator is running without going back to the splash.
- **Export/import a single kit as a `.smskit` file** in the patcher. Each kit has
  **export / import / clear** buttons, so you can save a tuned drum kit on its own
  and drop it into any other ROM (parallel to a song's `.smdj`). It carries the 8
  slots' console-ready samples + names; empty slots are preserved.

### Changed
- **The `SMP` instrument type is now called `KIT`.** Same instrument (a sample drum
  kit, with KIT / RATE / TSP fields) — just a clearer name in the TYPE field, the
  patcher, and the docs.
- **Sample patcher (`tools/patcher.html`) is kit-aware.** It lays the pool out as
  **8 kits × 8 slots** (the directory index is the engine's `kit*8 + slot`): load a
  ROM, see each kit's 8 slots, drop sounds into a specific kit, move samples between
  kit/slot, clear a kit, and download. Empty slots are length-0 entries, so
  partially-filled kits stay aligned. Slot 0 is the lowest note in a kit.
- **Song columns loop by contiguous block.** A track that runs off the bottom of
  the chains it's playing loops back to the **top of that block**, not to the
  column's first cell. So a single cell (or any run separated by gaps) loops into
  itself instead of jumping to a block above it — compose material in independent
  blocks, then slide them together for a through-composed song or perform in LIVE.
  Columns with one unbroken block are unaffected.
- **LIVE: stopping a playing chain waits for the chain to finish.** 2-hold + 1 on
  the cell that's already playing used to kill the track instantly; it now queues a
  **stop at chain end**, so the loop plays out before the track drops (an `X` marks
  the pending stop; tap again to cancel). The track-header gesture still stops a
  track immediately, and PAUSE still stops everything.
- **"Add new" (double-tap 1 on an empty cell) mints a genuinely unused
  chain/phrase/instrument.** It used to hand out the lowest slot with no *content*,
  so a slot you'd just placed but not yet filled got reused — laying out several
  before filling them produced duplicates. It now skips any slot already placed (a
  chain in the SONG, a phrase in a chain, an instrument in a phrase), so you get
  00, 01, 02… Double-tap on the PHRASE instrument column mints a fresh instrument
  even when the cell already holds one (replacing it).

### Fixed
- **Echo no longer bursts noise on the first play of a fresh load.** The play-start
  routine that silences the echo delay line stepped 3 bytes per entry instead of 4,
  clearing only about a third of the ring — the rest replayed garbage until real
  notes cycled through. The whole ring now starts silent.
- **Screen changes no longer drag the tempo while playing.** The screen redraw is
  throttled to one row per frame during playback (and skips rows on the label-draw
  frame), so a redraw can't overrun a frame and slow the sequencer. The redraw is a
  touch slower to settle while playing — but the tempo stays steady.

## v0.34 — 2026-06-30

### Added
- **`Q` command — echo on/off mid-song.** `Q00` mutes the echo, any non-zero
  (`Q01`) turns it back on, so you can drop echo into a chorus and pull it out for
  a verse. It just gates the effect live — your ECHO-screen settings (mode, taps,
  feedback, transpose, stereo) are untouched and saved as-is, and echo starts on
  each time you press play. Works from phrase and table columns.
- **Sample KITS.** The pool is now organised as **up to 8 kits of 8 samples**, built
  in alphanumeric order from the `samples/` folder (one subfolder per kit, WAVs
  inside). A new **KIT** field (0–7) on the SMP instrument picks the kit; the note
  then maps chromatically to the 8 slots, wrapping every octave from the lowest. So
  one SMP instrument is a whole drum kit played across the keyboard.
- **Sample baking now trims trailing silence and applies a louder gain.** The pool
  builder strips each sample's silent tail (the feeder hard-mutes on end, so it's
  clickless) and drives the samples harder (peak-normalize → ×gain with clipping)
  for a punchier 4-bit DAC. Tunable via `make SAMPLE_GAIN=N`.
- **PURGE — reclaim unused chains/phrases.** The FILES action menu gains **PRGC**
  (purge chains not placed in the SONG) and **PRGP** (purge phrases not reachable
  from the SONG). Both blank the orphaned records so they drop out of the
  compressed save and free their pool slots — handy when you've left scratch ideas
  lying around. Two-tap to confirm (the word shows `SURE`); a `FREED nn` count
  shows after. Acts on the working song — save afterwards to bank the smaller image.

### Fixed
- **Re-saving a song no longer leaks SRAM free space.** Saving over an existing
  slot used to orphan the slot's previous data blob (the heap only grew, so
  repeated saves ate free space). Save now frees the old blob and compacts the
  heap first — and since compaction closes *all* holes, the first save after this
  fix reclaims any space already lost to earlier re-saves.
- **A retriggered sample no longer freezes the UI after you stop.** Stopping now
  clears each channel's pending retrigger/delay and idles its envelope, so the
  stopped "audition" pass can't keep re-firing a note. Previously an `R` on a
  sample track left the retrigger running after Stop, machine-gunning the sample
  and pinning the playback IRQ — which throttled screen redraws so hard that
  navigating (e.g. CHAIN → PHRASE) looked dead.

### Changed
- **`R` (retrigger) fixed for kits/samples + volume step added.** Each retrigger
  now re-fires the note you played, so on a kit/sample instrument the correct
  slot repeats (it used to re-trigger the kit's last sample). The `R xy` **x**
  nibble now works: it fades the volume a step per re-fire on **TONE/NOISE** (great
  for echo/roll fades); it's ignored on samples (pointless on the 4-bit DAC). Also
  fixes a latent double-transpose on retriggered tone notes.
- **SMP RATE field renamed and reordered.** The sample-speed values now read
  **1X / 2X / 4X / .5X** (cycled in that order with Left/Right), replacing the old
  NORM/2X/HALF/4X labels. The SMP form fields are laid out **KIT, RATE, TSP**.
- **`SYNC: IN24` shows a `<<` glyph** in the top bar (vs `<` for plain IN), so the
  two follow modes are distinguishable at a glance.

## v0.33 — 2026-06-29

### Added
- **`SYNC: IN24` mode** (OPTIONS → SYNC) follows a **24-PPQN** source — the ESP32
  Ableton Link bridge, ares-link-sync, or any 24-PPQN counter. This is what the
  old `IN` did; plain `IN` is now the 1-clock-per-row mode (below). *If you use the
  Link bridge, switch from IN to IN24.*

### Changed
- **Sync reworked to match genmddj (cross-machine sync).** `OUT`/`IN` are now
  **one clock per row** — a SMSGGDJ `OUT` locks a genmddj (or another SMSGGDJ) `IN`
  in lockstep at any tempo, and vice versa. The mode list/order now mirrors genmddj
  (`OFF / OUT / PULSE / IN / IN24`). The wire protocol is unchanged.
- **`F` (finetune) direction fixed.** Positive `F` now raises pitch (it was
  lowering it) on PSG tone channels.
- **The `A` (table) command is now a one-shot per-note override.** Like `B` (wave)
  and `Y` (FM program), `A` now sets the table for *just the note it's on* and no
  longer lingers as channel state — every other note follows the instrument's own
  table. (`A` inside a table's command column still switches immediately, as before.)
- **Table `H` (loop) no longer costs a step.** Like the phrase hop in v0.32, an
  `H` in a table is stepped over instead of holding the current row for an extra
  tick — the table loops straight to the target row, which plays on its own step.
  So a looping table (e.g. a 2-step arp) runs tight with no wasted/held step, and
  the playhead rests on the loop target.

## v0.32 — 2026-06-28

### Added
- **`J` command — probabilistic transpose.** A sibling to `I`/`Z` for making one
  phrase vary across its repeats. `Jxy` transposes the note by a **signed** semitone
  amount `x` (`0`–`7` = +1…+7, `8`–`F` = −8…−1, so `F` = −1) on the plays whose
  **(play mod 4)** bit is set in the mask `y` (`y=0` never, `y=F` always). Pairs with
  `I` (gate the note) and `Z` (random chance) to keep a single phrase moving.

### Changed
- **`H` (hop) is now immediate.** Hitting `H` in a phrase jumps back to row 0 in
  the **same tick** instead of spending a 16th on the H row — so a row of `H` is a
  zero-time loop marker. Put it right after your last step and the phrase loops
  with no wasted step (e.g. `H` on row 4 now loops a 4-step phrase, not 5).

## v0.31 — 2026-06-28

### Added
- **`Z` command — note probability.** `Zxx` gives the row's note a chance to
  trigger: `Z00` never plays, `ZFF` always plays, and values in between roll a
  fresh random number each time (e.g. `Z80` ≈ 50/50). Works in phrase and table
  columns.
- **FILES screen scrolls** through all 32 song slots (12 visible at a time), with
  a **song count** above the list and a **SRAM / FREE / SONG** space readout (in
  KB) stacked under the mini-map.

### Changed
- **The save system now respects the detected cart size.** The heap capacity (and
  the FILES `SRAM`/`FREE` readout) comes from `sram_detect` (8/16/32 KB) instead
  of assuming 32 KB, so a save can't be placed past the real SRAM on a smaller
  cart, and the bank-crossing logic only kicks in on a true 32 KB (two-bank) cart.
- **Deleting a song now compacts the cartridge heap.** Clearing a song slides the
  remaining songs down to close the gap (across the 16 KB bank boundary when
  needed), so freed space is always reclaimed — no more stranded holes that only
  came back if you deleted from the top of the list.
- **The groove number is now an editable field.** On the GROOVE screen, move the
  cursor up past the top tick onto the groove number, then **hold 1 + Left/Right**
  to pick the groove. This frees **2 + Left/Right** for navigation, so you can now
  hop **FILES ↔ GROOVE** (FILES 2+Right → GROOVE, GROOVE 2+Left → FILES).
- **DEMO removed.** The built-in demo song is gone; the FILES action menu is now
  **SAVE / LOAD / CLEA / CANC**. (Fresh songs still boot with the preset waves.)

## v0.30 — 2026-06-27

### Added
- **FILES screen (F, below S).** A dedicated screen to manage saved songs. It
  shows a **packed list** of your songs plus one empty slot at the end (whenever
  there's room for another). Up/Down picks a slot; **hold 1 + Up/Down** cycles the
  letter under the name cursor (blank, A–Z, specials, 0–9); **hold 1 + Left/Right**
  moves the cursor across the 8-char name (wraps). **Hold 2 + 1** opens an action
  menu on the right — **SAVE / LOAD / CLEA / DEMO / CANC** — Up/Down to choose,
  tap 1 to run it and close. **SAVE** on the empty slot creates a new file;
  **LOAD** on the empty slot blanks the working song; **CLEAR** removes a file and
  closes the gap. Song names are stored inside the slot.
- **Bigger pools.** Songs now hold **52 phrases and 40 chains** (was 32/32),
  made affordable by RLE save compression.

### Changed
- **New save format (SMDJ4).** Song data is RLE-compressed before it hits SRAM
  and stored in a directory + heap, so many more songs fit on one cartridge
  alongside the larger pools. **This is a breaking change** — older (SMDJ3) saves
  don't load directly; bring them forward with `tools/migrate.html`.
- **PROJECT screen trimmed to TMPO / TSP / MODE.** NEW, DEMO, SLOT and SAVE/LOAD
  moved to the FILES screen — slot management now lives in one place.
- **Palette 1 is now black-on-white** (was the green KIDD scheme); palette 0
  (white on black) remains the boot default. Pick any via OPTIONS → COLR.

### Fixed
- **Game Gear: OPTIONS and PROJECT values no longer crowd the mini-map.** Their
  labels and values shift left by two columns on GG (as the INSTR form already
  did), clearing the screen map on the right. SMS is unchanged.
- **Game Gear: leaving the WAVE screen no longer smears the display.** The
  canvas-clear wiped a full 32-tile-wide row, which overflowed the narrower GG
  window and wrapped onto other rows; it now clears only the window width.

### Tools
- **`als2smdj.html`** now exports a ready-to-load **SMDJ4 `.sav`** (one song,
  named from the file, at your 8/16/32 KB cart size) — no separate migrate step.
- **`tools/migrate.html`** (new) carries an old SMDJ3 `.sav`/`.smdj` forward to
  SMDJ4; **`savetool.html`** reads SMDJ4 images (view + export `.smdj4`).
- The old `savetool.py` CLI (SMDJ3-only) was removed in favour of the browser
  tools.

## v0.29 — 2026-06-19

### Fixed
- **INSTR TYPE and noise RATE now adjust both ways.** Holding 2 and tapping
  Left/Right (or Up/Down) on the instrument **TYPE** row, or a noise instrument's
  **RATE** row, only ever cycled forward. Both fields now step **back with
  2+Left/Down** and **forward with 2+Right/Up**, matching every other field.

## v0.28 — 2026-06-17

### Changed
- **WAV note length now follows HLD.** A wavetable used to trail on at full level
  through its (hidden, uneditable) decay, so HLD barely changed the length. WAV
  now plays for exactly the hold then cuts — HLD `1`–`E` set the length, `F`
  rings. New WAV instruments default to **HLD 6**.

### Fixed
- **WAV instruments no longer mute the noise channel.** A wavetable on a tone
  channel used to silence the noise voice for as long as it played; now noise
  plays alongside a wave (as it already did with samples), so you can layer a
  WAV lead/pad with a noise hat/snare. Pitched (rate-3) noise still falls back
  to a fixed rate while the wave's DAC owns tone 3.

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
