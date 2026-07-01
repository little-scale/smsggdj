; =============================================================
; SMSDJ - SN76489 PSG driver
;
; The engine writes to shadow registers in RAM; psg_flush sends
; only what changed (deduplicated writes, per the design doc).
; Tone periods are 10-bit, volumes are stored as ATTENUATION
; (0 = loudest, $F = silent), noise control is the raw nibble:
;   bit 2: 1 = white, 0 = periodic
;   bits 1-0: rate (0=clk/512, 1=clk/1024, 2=clk/2048, 3=tone 2)
; =============================================================

.DEFINE PSG_PORT $7F

.RAMSECTION "psgvars" SLOT 3
  psg_tone0      dw
  psg_tone1      dw
  psg_tone2      dw
  psg_t0_sent    dw
  psg_t1_sent    dw
  psg_t2_sent    dw
  psg_vols       dsb 4         ; attenuation, channels 0-3
  psg_vols_sent  dsb 4
  psg_noisectl   db
  psg_noise_sent db
  psg_pan        db          ; GG stereo: R enables 0-3, L 4-7
  psg_pan_sent   db
.ENDS

.SECTION "PSG" FREE

; silence everything and sync shadows
psg_init:
  ld a, $9F
  out (PSG_PORT), a
  ld a, $BF
  out (PSG_PORT), a
  ld a, $DF
  out (PSG_PORT), a
  ld a, $FF
  out (PSG_PORT), a
  ld a, $FF                  ; pan: all channels both sides
  ld (psg_pan), a
  ld (psg_pan_sent), a
  ld hl, 1
  ld (psg_tone0), hl
  ld (psg_tone1), hl
  ld (psg_tone2), hl
  ld (psg_t0_sent), hl
  ld (psg_t1_sent), hl
  ld (psg_t2_sent), hl
  ld a, $0F
  ld (psg_vols), a
  ld (psg_vols+1), a
  ld (psg_vols+2), a
  ld (psg_vols+3), a
  ld (psg_vols_sent), a
  ld (psg_vols_sent+1), a
  ld (psg_vols_sent+2), a
  ld (psg_vols_sent+3), a
  ld a, $04                    ; white, rate 0
  ld (psg_noisectl), a
  ld (psg_noise_sent), a
  or $E0                       ; assert it on the chip too ($E4): psg_flush only
  out (PSG_PORT), a            ;   writes the noise reg on a *change*, so a first
                               ;   $04 noise note would skip it and leave the
                               ;   power-on (pitched/periodic) state playing
  ret

; send shadow -> sent diffs. Tone write = latch byte (low 4 bits
; of period + channel) then data byte (high 6 bits).
.MACRO PSGFLUSHTONE ARGS shadow, sent, latchbits
  ld hl, (shadow)
  ld a, (sent)
  cp l
  jr nz, +
  ld a, (sent+1)
  cp h
  jr z, ++
+:
  ld (sent), hl
  ld a, l
  rrca
  rrca
  rrca
  rrca
  and $0F
  ld b, a
  ld a, h
  add a, a
  add a, a
  add a, a
  add a, a
  or b
  and $3F
  ld b, a                    ; data byte prepared up front
  ld a, l
  and $0F
  or latchbits
  di                         ; latch+data must be atomic: a
  out (PSG_PORT), a          ; sample IRQ between them re-latches
  ld a, b                    ; the PSG to T3 volume and the data
  out (PSG_PORT), a          ; byte lands in the wrong register
  ei
++:
.ENDM

psg_flush:
  PSGFLUSHTONE psg_tone0, psg_t0_sent, $80
  PSGFLUSHTONE psg_tone1, psg_t1_sent, $A0
  PSGFLUSHTONE psg_tone2, psg_t2_sent, $C0

  ; volumes: latch $90/$B0/$D0/$F0 + attenuation
  ld hl, psg_vols
  ld de, psg_vols_sent
  ld c, $90
  ld b, 4
pf_vol:
  ld a, (de)
  cp (hl)
  jr z, pf_vskip
  ld a, (hl)
  ld (de), a
  and $0F
  or c
  out (PSG_PORT), a
pf_vskip:
  inc hl
  inc de
  ld a, c
  add a, $20
  ld c, a
  djnz pf_vol

  ; noise control (writing also resets the LFSR)
  ld a, (psg_noise_sent)
  ld b, a
  ld a, (psg_noisectl)
  cp b
  jr z, pf_pan
  ld (psg_noise_sent), a
  and $07
  or $E0
  out (PSG_PORT), a
pf_pan:
.IFNDEF TARGET_GG
  ret                        ; port $06 is memory control on SMS
.ENDIF
  ld a, (psg_pan_sent)
  ld b, a
  ld a, (psg_pan)
  cp b
  ret z
  ld (psg_pan_sent), a
  out ($06), a
  ret

.ENDS
