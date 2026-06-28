# FM pitch modulation (F / P / V on FM) — investigation notes

**Status: implemented but DISABLED.** The goal was to make the pitch-modulating
commands work on YM2413 FM voices (the PSG path drives them via the period table;
FM channels never went through it):

- `F` (finetune), `P` (pitch bend), `V` (vibrato), and the instrument SWP/VIB
  fields — all should bend an FM voice's pitch live.

A full implementation exists (`fm_pitch_mod` + `fm_vib_delta` in `src/engine.asm`,
bank-1 `SetTempo` section) but **never produced an audible wobble on FM**, despite
an exhaustive bisection proving every individual piece works. It is wired off: the
`cf_out` hook (`call chan_is_fm` / `jp z, fm_pitch_mod`) is commented out, so FM
playback is byte-for-byte the original hardware-verified behaviour. PSG `F`/`P`/`V`
are unaffected (and the `F`-finetune *direction* fix on PSG/tone is separate and
kept).

## Design

- `cf_out` (channels_fx, per tick) would branch FM channels to `fm_pitch_mod`
  instead of writing a (muted) PSG period via `calc_period`.
- `fm_pitch_mod` recomputes the YM2413 F-number from the note (`ix+0` + table
  offset `ix+24`), looks it up in `fm_note_ptr`, adds a signed offset, handles
  block carry, and writes `$10`/`$20`.
- Offset = `finetune(ix+27) − (Pbend_acc(ix+13/14) >> 4) − vibrato`.
- `fm_vib_delta` = the same `vib_tables[depth*32 + step]` lookup the PSG path uses
  (`cpd_vib`), advancing the phase counter `ix+15` by `speed*4` per tick.
- `ix+13/14` (idle PSG sweep acc on FM) reused as the bend accumulator; `ix+12`
  (pitched-noise flag, unused on FM) was reused as a "voice keyed on" flag.

## What was proven WORKING (by forced-value probes in `fm_pitch_mod`)

1. **Write path / per-tick execution.** Driving the offset off the global frame
   counter made every FM note glide up/down ~1 Hz. So the routine runs every tick
   and the `$10`/`$20` writes update pitch live, without re-triggering.
2. **Constant offset.** Forcing a constant −64 fnum offset played every FM note a
   clean, steady ~3 semitones flat. So the F-number math + block carry + register
   writes are correct, and per-tick `$20` writes with key-on held do **not**
   audibly re-trigger.
3. **The `V` param reaches `ix+18` correctly.** With offset = `ix+18 & $F0`, a
   `V3F` note played sharp (speed nibble = 3 present) while a plain note stayed
   normal. So there is **no** editor/storage/read bug — the displayed param is the
   param the engine reads (display, `de_param`, and `pr_cmd` all use step+3).
4. **Phase counter `ix+15` persists across ticks** (manually advancing it in
   `fmpm_go` produced a clean sawtooth glide) — so there is **no** hidden per-tick
   re-trigger resetting the phase.
5. **The `fm_vib_delta` call/return works** — replacing its body with a slow
   sawtooth (advance `ix+15`, return `ix+15−128`) produced a clear glide.

## What FAILS

- The **real `fm_vib_delta`** (the `vib_tables` lookup with the speed-based phase
  advance) produces **no audible wobble** for any tested `V` value, even with the
  `ix+12` gate removed and key-on forced on, and even forcing `ix+18 = $FF`.

So: constant offsets work, a hand-rolled sawtooth in `fm_vib_delta` works, but the
real `vib_tables`-based oscillation does not.

## The `ix+12` red herring

The keyed-on gate (`jp z, cf_vol` when `ix+12 == 0`) was found to **bail** on the
test note — the FM voice keys off (finite HLD / hold expiry) and `ix+12` goes 0,
so modulation only ran during the brief keyed-on window. Removing the gate (and
trying key-on-per-`ix+12` so a releasing note bends without re-keying) did **not**
fix it, so the gate was a confound, not the root cause.

## Next step (not run)

The last untested probe (#15) would isolate the remaining two suspects: keep the
real **speed-based phase advance + step**, but return a sawtooth derived from
`step` instead of the `vib_tables` lookup.

- **Wobbles** ⇒ the `vib_tables` *lookup* is the bug. Prime suspect: reading
  bank-0 `vib_tables` from the bank-1 `fm_vib_delta` at runtime (verify the
  address resolves and the bank is actually mapped; `cpd_vib` reads the same table
  but from a different section/bank). Also recheck the `ld bc, vib_tables` /
  `add hl, bc` index math under the live `ix` values.
- **Steady** ⇒ the **speed-based phase advance** is the bug (e.g. the step
  changes too fast — `speed*4` gives ~14 Hz at speed F, which reads as buzz not
  vibrato — or the step→value mapping degenerates). Consider scaling the FM
  vibrato speed down and/or rate-limiting how often `$20` is rewritten.

Other angles worth a look:

- Whether the rapid per-tick `$20` rewrites at higher speeds confuse the YM2413 /
  emulator even if the math is right (try writing `$10` only when block/fnum8 are
  unchanged, to avoid touching the key/sustain bits every tick).
- Whether `vib_tables` row indexing (`depth*32`) lands where expected for the
  depth values actually used.

## To fully back this out (if abandoning)

Remove `fm_pitch_mod` + `fm_vib_delta`, the `cf_out` comment block, and the
`ix+12` writes added to `tn_fm` / `ahd_fmhold` / `xc_kill` (harmless on FM
channels, which don't otherwise read `ix+12`). The `F`-finetune direction fix in
`calc_period_delta` (PSG) is unrelated and should stay.
