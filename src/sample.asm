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
;   PCM:  HL' = pointer  DE' = end        B' = byte  C' = phase
;   wave: HL' = wav_buf  DE' = increment  BC' = 8.8 phase
; Main-thread code must never use EXX / EX AF,AF'.
;
; Waves play from wav_buf, not wave_ram: the DAC is logarithmic
; (2 dB/attenuation step), so the drawn-linear levels are mapped
; through wav_lin2log when the buffer is (re)filled. wave_ram
; keeps the drawn shape - what the editor shows and saves.
; =============================================================

.RAMSECTION "smpvars" SLOT 3
  smp_active   db            ; 1 = feeding
  smp_mode     db            ; 1 = sample stream, 2 = wavetable
  smp_irq_on   db            ; line interrupts enabled
  smp_vbcnt    db            ; samples to feed across vblank
  smp_tmp      db
  wav_owner    db            ; track whose volume gates the wave
  wav_cur      db            ; wave # loaded in wav_buf
  winc_ptr     dw            ; region pitch-increment table
  smp_count    db            ; samples in the pool (boot-cached)
.ENDS

.RAMSECTION "wavbuf" SLOT 3 ALIGN 32
  wav_buf      dsb 32        ; log-corrected ready-to-OUT copy
.ENDS

.SECTION "Sample" FREE

; one feed tick, shadow context (caller did EX AF,AF' + EXX)
smp_feed_any:
  ld a, (smp_mode)
  cp 2
  jr z, wav_feed_one
  jr smp_feed_one

; wavetable: HL = wav_buf (32-aligned), DE = increment,
; BC = 8.8 phase. Buffer bytes are pre-OR'd $D0|attenuation.
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

; start sample A (0..smp_count-1); main-thread only. The pool
; directory lives in bank 2; the sample's own bank is left paged
; into slot 2 for the feeder (which owns $FFFF while playing).
smp_play:
  ld b, a
  ld a, (smp_count)
  ld c, a
  ld a, b
  cp c
  ret nc
  ld l, a                    ; directory entry = $8008 + A * 10
  ld h, 0
  add hl, hl
  ld d, h
  ld e, l
  add hl, hl
  add hl, hl
  add hl, de                 ; * 10
  ld de, $8008
  add hl, de
  di
  ld a, 2                    ; page the directory in
  ld ($FFFF), a
  ld a, (hl)                 ; +0 sample's bank
  inc hl
  ld e, (hl)
  inc hl
  ld d, (hl)                 ; DE = start ($8000-based)
  inc hl
  ld c, (hl)
  inc hl
  ld b, (hl)                 ; BC = length
  ld ($FFFF), a              ; page the sample's bank
  ld h, d
  ld l, e
  add hl, bc                 ; HL = end, DE = start
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
  push de
  ld a, c
  call wav_copybuf           ; drawn wave -> corrected play buf
  pop de
  ld hl, wav_buf
  di
  push hl
  push de
  exx
  pop de                     ; increment
  pop hl                     ; play buffer
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
  di
  out (VDP_CTRL), a
  ld a, $80
  nop
  nop
  nop
  out (VDP_CTRL), a
  ld a, 1
  ld (smp_irq_on), a
sp_done:
  ei
  ret

; re-run the copy after a wave_ram edit so a playing wave follows
; the drawing live. No shadow access: the feed reads wav_buf and
; single-byte writes are IRQ-safe. Main thread only.
wav_refresh:
  ld a, (smp_mode)
  cp 2
  ret nz
  ld a, (wav_cur)
  ; fall through

; fill wav_buf from wave A (0-3), mapping each drawn level
; through the log-DAC correction. Main thread only.
wav_copybuf:
  ld (wav_cur), a
  rrca
  rrca
  rrca
  and $E0                    ; wave# * 32
  ld hl, wave_ram            ; 256-aligned: low byte is the slot
  ld l, a
  ld de, wav_buf
  ld b, 32
wcb_loop:
  ld a, (hl)
  and $0F                    ; stored 15-level nibble
  push hl
  ld hl, wav_lin2log
  add a, l
  ld l, a
  adc a, h
  sub l
  ld h, a
  ld a, (hl)
  pop hl
  ld (de), a
  inc l
  inc de
  djnz wcb_loop
  ret

; drawn level is linear (0..15 = 0..full scale) but attenuation
; is 2 dB/step: pick the attenuation nearest 10^(-n/10) = v/15.
; Indexed by the stored nibble (15 - level), pre-OR'd with $D0.
wav_lin2log:
  .db $D0, $D0, $D1, $D1, $D1, $D2, $D2, $D3
  .db $D3, $D4, $D5, $D6, $D7, $D9, $DC, $DF

; abort an in-flight sample immediately (main thread) - needed
; before mapping SRAM over the pool banks in slot 2
smp_abort:
  ld a, (smp_mode)
  cp 1
  ret nz
  di
  xor a
  ld (smp_active), a
  ld (smp_mode), a
  ld a, $DF                  ; T3 silent
  out (PSG_PORT), a
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
  nop
  nop
  nop
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
  push bc                    ; pad to ~456 cycles/iteration:
  ld b, 18                   ; fixed cost is ~224, 13*18=234.
svf_dly:                     ; (mistuned at 22 this ran 11% slow
  djnz svf_dly               ; through vblank - frame-rate pitch
  pop bc                     ; warble on sustained wavetables)
  ld a, (smp_tmp)
  dec a
  ld (smp_tmp), a
  jr nz, svf_loop
  ret

.ENDS
