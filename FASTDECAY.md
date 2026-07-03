# Spec: PSG fast decay for `DCY = 0` (port from genmddj)

Ported concept from genmddj (built + verified there 2026-07-01, commit `73e9c78`; refined by
`e0aa0a4` and `f2ed2cb`). genmddj's PSG AHD envelope is SMSGGDJ's, so this maps 1:1.

## Problem

The PSG AHD envelope steps **one volume level per `DCY` ticks**, so the fastest smooth release
is `DCY=1` ≈ 15 frames (~250 ms @60 Hz) from full volume. `DCY=0` hard-cuts to 0 in a single
frame — an audible click, and useless as a percussion tail.

## Change

Repurpose `DCY=0` from "instant cut" to a **fast multi-step decay: subtract 4 volume levels per
frame** until silent.

- From full volume: `15 → 11 → 7 → 3 → 0` = **5 frames ≈ 66 ms** @60 Hz (80 ms PAL).
- One step per existing envelope tick — no sub-frame / sample-IRQ work.
- Lives in the shared PSG envelope → covers tone + noise (tight hats/snares on noise are the
  main win).
- Instant cut remains available via **`K00`**, so nothing is lost.

## Algorithm (decay state, replacing the old `DCY=0` branch)

```
decay state, per tick:
  if DCY != 0:                      ; unchanged ramp
      every DCY ticks: vol -= 1; if vol == 0 -> envelope off
  else:                             ; DCY == 0: fast decay
      if vol <= 4:
          vol = 0
          estate = OFF              ; envelope done
      else:
          vol -= 4                  ; one step per FRAME, no tick counter
```

genmddj reference (68k `env_ch .e_decay` — transliterate to Z80):

```
.e_decay:
    <resolve effective DCY>          ; (genmddj: the E command may override it)
    tst.b   d1                       ; DCY == 0 ?
    bne.s   .d_ramp                  ; no -> normal one-step-per-DCY-ticks ramp
    move.b  c_vol(a6), d1
    cmpi.b  #4, d1                   ; <= 4 -> final step
    bls.s   .d_fastcut
    subq.b  #4, d1
    move.b  d1, c_vol(a6)
    rts
.d_fastcut:
    move.b  #0, c_vol(a6)
    move.b  #0, c_estate(a6)         ; envelope off
    rts
```

## Notes / edge cases (learned the hard way in genmddj)

1. **No tick counter** on the fast path — it steps every frame unconditionally; don't touch the
   envelope counter.
2. **Macro-table interaction:** if the table/macro advance is gated on the envelope being active
   (`estate != 0`), the fast decay reaching 0 **freezes the table mid-note**. genmddj fix
   (`e0aa0a4`): advance the table whenever one is assigned, regardless of envelope state; gate
   only the volume state machine on `estate`. Port this in the same change or tables audibly
   stop at the end of every `DCY=0` note.
3. **`K00` consistency:** with tables running independently (note 2), a table's VOL column can
   *revive* a "cut" note. Make `K00` a hard kill: volume 0 + envelope off **+ detach the table**
   (genmddj `f2ed2cb`).
4. The step size 4 is a taste constant — 4/frame ≈ 66 ms tail; 8/frame ≈ 33 ms if snappier is
   wanted. Keep the final-step clamp (`vol ≤ step → 0`) so it can't wrap.
5. **Save-format impact: none** — no new fields; it reinterprets an existing `DCY` value.
   Existing songs using `DCY=0` get a 5-frame tail instead of a click (arguably a fix, but it
   *is* a behaviour change — changelog it).

## Verification

Headless RAM-dump of the channel volume across frames: a `DCY=0` note must emit the
intermediate values (11/7/3), not jump 15→0. On SMSGGDJ, equivalently watch the attenuation
writes in the PSG shadow/flush.
