; =============================================================
; SMSDJ - input: raw / edge / repeat (DAS) for pad 1
; =============================================================

.SECTION "Input" FREE

; updates pad_raw, pad_prev, pad_edge, pad_rep, das_timer.
; pad_rep = new presses, plus held d-pad directions re-fired at
; DAS_SPEED after DAS_DELAY frames (LSDJ-style cursor repeat).
read_input:
  ld a, (pad_raw)
  ld (pad_prev), a
  in a, (IO_PORT_A)
  cpl
  and $3F
  ld (pad_raw), a
  ld b, a                      ; raw
  ld a, (pad_prev)
  cpl
  and b
  ld (pad_edge), a
  ld c, a                      ; edge

  ld a, b
  and $0F                      ; any direction held?
  jr nz, ri_dirs_held
  ld a, c                      ; no: repeat = edges only
  ld (pad_rep), a
  ret

ri_dirs_held:
  ld a, c
  and $0F                      ; direction newly pressed?
  jr z, ri_das_tick
  ld a, (key_delay)            ; yes: restart delay (OPTIONS-set)
  ld (das_timer), a
  ld a, c
  ld (pad_rep), a
  ret

ri_das_tick:
  ld a, (das_timer)
  dec a
  ld (das_timer), a
  jr z, ri_das_fire
  ld a, c
  ld (pad_rep), a
  ret

ri_das_fire:
  ld a, (key_speed)            ; OPTIONS-set repeat interval
  ld (das_timer), a
  ld a, b
  and $0F                      ; re-fire held directions
  or c
  ld (pad_rep), a
  ret

.ENDS
