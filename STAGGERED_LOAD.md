# Staggered CONT load (piece 2) — devised plan

Status: **not built.** Piece 1 (the CONT bridge playing from private buffers) is
on `main` and is the prerequisite. This doc captures the design so piece 2 can be
picked up as a self-contained effort.

## Goal

Kill the short "sound-chip holds its last value" stall you hear when a CONT load
decompresses the new song. Today `rle_song_load` decompresses the ~6.9 KB song
block in one blocking pass (~1 frame after the path-A speedup, was ~4), during
which `engine_tick` never fires, so the sequencer freezes. Piece 2 spreads the
decompress across frames and **ticks the engine between chunks**, so the bridge
keeps playing and the beat never stalls.

## Why it needs piece 1

If the engine ticks mid-decode, it must read **only safe data** — the song block
is being overwritten, and there's no room to decode into a second 6.9 KB buffer
(≈250 B RAM free). Piece 1 already makes the only thing playing during a load —
the CONT bridge — read from private buffers (`carry_buf` / `carry_instr`, via the
`BRIDGE_MK` / `NUM_INSTR` sentinels), not the pool. So the safe-read problem is
solved for the bridge; piece 2 just has to make sure nothing *else* reads the
block while it streams in.

## The four parts

1. **Resumable decode.** Path A made `rle_unpack` register-resident (HL=src,
   DE=dst, one burst). Make it yield: after each run (control byte), if a per-call
   unit budget is spent, stash `HL`→`rle_sp`, `DE`→`rle_bp` and return "more to
   do"; the resume entry restores them and continues (the loop is already
   between-run re-entrant, and `rle_end` persists in RAM). Yield **between runs**
   only — never mid-`ldir` — so no extra mid-run state is needed. Add a
   `rle_song_load_start` (open the directory entry, set src/dst/`rle_end`) and a
   `rle_unpack_chunk` (do up to N units, return Z when done).

2. **Groove on the scratch, at the old tempo, before the decode.** The grooves
   live in the block being overwritten, so before streaming starts, seed the glide
   scratch groove (`glide_scratch`) with the old tempo and set `groove_sel =
   NUM_GROOVES` (the existing sentinel in `groove_base`). The clock then reads the
   scratch, never half-loaded grooves. On completion, hand off to `cont_tempo_glide`
   (which ramps to the new tempo) as today.

3. **Bridge up + others silenced, before the decode.** Put the carried channel in
   bridge mode (the piece-1 plant) and silence the non-carried tracks (the LIVE
   path already does this via `live_track_stop`) *up front*, so from the first
   ticked frame only the bridge sounds. SONG's "restart others at row 0" is
   deferred to completion (they can't read the block yet) — in SONG the non-bridge
   tracks come in when the load finishes, which reads as intentional.

4. **Main-loop load state machine.** Replace the blocking `fpx_load` body with a
   state: `LOAD_IDLE` / `LOAD_RUN`. Entering FILES→LOAD does `load_carry_pre` +
   part 2 + part 3, then arms `LOAD_RUN`. Each main-loop frame while `LOAD_RUN`:
   `call rle_unpack_chunk`; the normal `engine_tick` still runs (bridge plays).
   When the chunk returns "done": run the finalize path — the current `load_rebase`
   body (rescan `eng_len`, clear `live_q`, `cont_tempo_glide`, `cont_restart_all`,
   `load_carry_post`) — then `LOAD_IDLE`.

## Flow, before → after

```
before (blocking):
  fpx_load: load_carry_pre; rle_song_load (blocks ~1 frame); load_rebase

after (staggered):
  fpx_load: load_carry_pre; setup bridge + scratch-groove(old tempo) + silence;
            rle_song_load_start; arm LOAD_RUN; return
  main loop (each frame, LOAD_RUN): rle_unpack_chunk; engine_tick (bridge plays)
  on chunk done: load_rebase-body (rebase, glide, restart/finalize); LOAD_IDLE
```

## Chunk sizing

Total 1728 units. Spread over a handful of frames (e.g. ~300–450 units/frame → 4–6
frames of overlap) so each frame's `ldir` burst stays well inside VBlank and never
starves the sequencer tick. Expose the chunk size as a define and tune by ear /
by watching the tick stay on time.

## Edge cases

- **Sync slave (IN/IN24):** the external clock drives row timing; the glide is
  already skipped there. The staggered decode still applies (it's about the block
  copy, not the clock) — but verify the slave tick and the chunking don't fight.
- **Stop during load:** treat like `engine_stop` — abort `LOAD_RUN`, finish or
  discard the partial decode (the block is inconsistent, so on stop just finish
  the copy synchronously before returning, or mark the working song invalid).
- **Load while a bridge is already looping (LIVE):** piece 1 already handles the
  re-stash guard (ix+10 = $FF → no re-stash); confirm the chunked path preserves
  that.
- **FILES UI redraw:** the FILES screen is up during the load; make sure its
  redraw budget and the decode chunk don't both blow VBlank in the same frame.

## Risk

Medium–high: a resumable decoder over the save path (data integrity) plus a new
main-loop state machine. No `make test` coverage for the ASM decoder — verify by
loading songs in Emulicious + the optional in-ROM `RLE_SELFTEST`. Do it on its own
branch. Round-trip the resumable decode in Python (as path A did) before flashing.

## Payoff vs. cost

The remaining stall is ~1 frame (~17–20 ms) and, per testing, barely audible.
Piece 2 removes it entirely but is the riskiest change in the CONT feature. Worth
doing only if a fully seamless transition is wanted; otherwise piece 1 (already
merged) is a clean stopping point.
