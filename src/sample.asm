; =============================================================
; SMSDJ - 4-bit PCM sample playback (design doc section 10)
;
; The Sega PSG quirk: tone period 1 stops the flip-flop and the
; channel outputs a DC level equal to its volume - the volume
; register becomes a 4-bit logarithmic DAC. We commandeer T3.
;
; Timing (hybrid scheme, 10.4):
;  - active display: VDP line interrupt every 2 scanlines feeds
;    one nibble (~3,906 Hz x2 = 7,813 Hz PAL / 7,867 NTSC)
;  - vblank: the line counter does not run, so the frame handler
;    runs a cycle-counted feeder for the vblank's worth of
;    samples before releasing the main loop
;
; The Z80 shadow registers belong to the sample feed:
;   HL' = pointer  DE' = end  B' = current byte  C' = phase
; Main-thread code must never use EXX / EX AF,AF'.
; =============================================================

.RAMSECTION "smpvars" SLOT 3
  smp_active   db            ; 1 = feeding
  smp_mode     db            ; 1 = sample stream, 2 = wavetable
  smp_irq_on   db            ; line interrupts enabled
  smp_vbcnt    db            ; samples to feed across vblank
  smp_tmp      db
  wav_owner    db            ; track whose volume gates the wave
  winc_ptr     dw            ; region pitch-increment table
.ENDS

.SECTION "Sample" FREE

; one feed tick, shadow context (caller did EX AF,AF' + EXX)
smp_feed_any:
  ld a, (smp_mode)
  cp 2
  jr z, wav_feed_one
  jr smp_feed_one

; wavetable: HL = wave base (page:wave*32), DE = increment,
; BC = 8.8 phase. Bytes are pre-OR'd $D0|attenuation.
wav_feed_one:
  ld a, c
  add a, e
  ld c, a
  ld a, b
  adc a, d
  ld b, a
  and $1F
  or l
  push hl
  ld l, a
  ld a, (hl)
  pop hl
  out (PSG_PORT), a
  ret

; feed one nibble to the T3 volume DAC. Shadow context: caller
; has done EX AF,AF' + EXX.
smp_feed_one:
  ld a, c
  or a
  jr nz, sf_lo
  ld a, h                    ; fetch a new byte; end reached?
  cp d
  jr nz, sf_go
  ld a, l
  cp e
  jr z, sf_end
sf_go:
  ld a, (hl)
  inc hl
  ld b, a
  rrca
  rrca
  rrca
  rrca
  and $0F
  or $D0                     ; T3 volume latch
  out (PSG_PORT), a
  ld c, 1
  ret
sf_lo:
  ld a, b
  and $0F
  or $D0
  out (PSG_PORT), a
  ld c, 0
  ret
sf_end:
  ld a, $DF                  ; T3 silent
  out (PSG_PORT), a
  xor a
  ld (smp_active), a
  ret

; start sample A (0..SAMPLE_COUNT-1); main-thread only
smp_play:
  cp SAMPLE_COUNT
  ret nc
  add a, a
  add a, a
  ld e, a
  ld d, 0
  ld hl, sample_table
  add hl, de
  ld e, (hl)
  inc hl
  ld d, (hl)
  inc hl
  ld c, (hl)
  inc hl
  ld b, (hl)                 ; BC = length
  ld hl, sample_pool
  add hl, de                 ; HL = start
  ld d, h
  ld e, l
  add hl, bc                 ; HL = end, DE = start
  di
  push de
  push hl
  exx
  pop de                     ; end
  pop hl                     ; pointer
  ld c, 0                    ; phase: fetch next
  exx
  ld a, 1
  ld (smp_mode), a
  jr smp_dac_on

; start wavetable playback: A = note index, C = wave 0-3
wav_play:
  add a, a
  ld e, a
  ld d, 0
  ld hl, (winc_ptr)
  add hl, de
  ld e, (hl)
  inc hl
  ld d, (hl)                 ; DE = phase increment
  ld a, c
  rrca
  rrca
  rrca
  and $E0                    ; wave# * 32
  ld c, a
  ld hl, wave_ram            ; 256-aligned: low byte is the slot
  ld l, c
  di
  push hl
  push de
  exx
  pop de                     ; increment
  pop hl                     ; wave base
  ld bc, 0                   ; phase
  exx
  ld a, 2
  ld (smp_mode), a
  ; fall through

; common DAC engage: T3 period 1, shadows synced, line IRQs on
smp_dac_on:
  ld a, 1
  ld (smp_active), a
  ld a, $C1
  out (PSG_PORT), a
  xor a
  out (PSG_PORT), a
  ld hl, 1
  ld (psg_tone2), hl
  ld (psg_t2_sent), hl
  ld a, (smp_irq_on)
  or a
  jr nz, sp_done
  ld a, $16                  ; R0: mode 4 + line ints
  out (VDP_CTRL), a
  ld a, $80
  out (VDP_CTRL), a
  ld a, 1
  ld (smp_irq_on), a
sp_done:
  ei
  ret

; stop wavetable output (main thread)
wav_stop:
  xor a
  ld (smp_active), a
  ld (smp_mode), a
  ld a, $DF
  out (PSG_PORT), a
  ret

; called each frame from the main loop: drop the line IRQs once
; playback has ended
smp_housekeep:
  ld a, (smp_active)
  or a
  ret nz
  ld a, (smp_irq_on)
  or a
  ret z
  xor a
  ld (smp_irq_on), a
  di
  ld a, $06                  ; R0: line ints off
  out (VDP_CTRL), a
  ld a, $80
  out (VDP_CTRL), a
  ei
  ret

; cycle-counted vblank feeder, run from the frame interrupt in
; shadow context. Each iteration targets ~456 cycles (2 lines).
smp_vblank_feed:
  ld a, (smp_vbcnt)
  ld (smp_tmp), a
svf_loop:
  call smp_feed_any          ; ~100 cycles
  ld a, (smp_active)
  or a
  ret z                      ; sample ended mid-vblank
  push bc                    ; ~310 cycles of padding
  ld b, 22
svf_dly:
  djnz svf_dly
  pop bc
  ld a, (smp_tmp)
  dec a
  ld (smp_tmp), a
  jr nz, svf_loop
  ret

.ENDS
