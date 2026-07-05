; ============================================================================
; src/midi.asm -- SYNC=MIDI takeover mode.
;
; An ESP32-S3 USB-MIDI adapter feeds note events over the existing 2-wire sync
; link; the tracker's sequencer steps aside and MIDI drives the PSG voices live
; as a 4-part multitimbral module (DAW ch 1-4 -> T1/T2/T3/NO).
;
; Z80 port of genmddj's console side (genmddj/src/main.asm midi_poll/dispatch).
; The WIRE PROTOCOL is genmddj/MIDI.md §3 and must match byte-for-byte -- the SMS
; reads the identical wire the S3 drives. SMS deltas: $DD/$3F port I/O (TR=CLK
; out, TH=DAT in), 4 voices instead of 10, no FM, 16 instruments, PSG note/vol.
; ============================================================================

.DEFINE MIDI_CAP     16        ; max events drained per frame (bounds shift-in time)
.DEFINE MIDI_SETTLE  12        ; midi_clock_bit inter-edge settle (djnz); HW-tunable
.DEFINE MIDI_NOTE_OFF 21       ; MIDI note - this -> tracker note index (calibrate)

.RAMSECTION "MidiVars" BANK 0 SLOT 3
  midi_cnt    db               ; midi_poll per-frame event cap counter
  midi_st     db               ; current event status (type<<4 | channel)
  midi_d1     db               ;   data 1
  midi_d2     db               ;   data 2
  midi_instr  dsb 4            ; per-track current instrument (from Program Change)
  midi_held   dsb 4            ; per-track held MIDI note ($FF = none) -- note-off match
.ENDS

; bank 1 (always mapped): bank 0 is full, and this is only reached by call/jp.
.BANK 1 SLOT 1
.SECTION "Midi" FREE

; ---------------------------------------------------------------------------
; frame_render: replaces the main loop's stopped-render check. MIDI takeover ->
; poll + render; else the normal path (playing = engine_frame already rendered;
; stopped = the prelisten envelope pass). Bank-0-neutral (one call in, no logic).
; ---------------------------------------------------------------------------
frame_render:
  ld a, (sync_mode)
  cp SYNC_MIDI
  jr z, midi_frame
  ld a, (play_state)
  or a
  ret nz                       ; playing: engine_frame already did the tick
  jp channels_fx               ; stopped: prelisten envelopes

; MIDI takeover frame: clock in queued events, then render the held voices with
; the same per-tick envelope/table pass the stopped path uses. Transport is held
; stopped in this mode, so there is no sequencer advance to interleave.
midi_frame:
  call midi_poll
  jp channels_fx

; ---------------------------------------------------------------------------
; 2-wire shift-in (genmddj/MIDI.md §3.1). SMS is the clock master: TR = CLK
; (output), TH = DAT (input). Sample DAT on the rising edge (CLK high); the S3
; changes DAT on the falling edge. MSB first. Port idiom matches sync_pulse_out:
; $FB = CLK(TR) high with TH input, $BB = CLK low; DAT read from $DD bit 7.
; ---------------------------------------------------------------------------
midi_clock_bit:                ; -> CARRY = sampled DAT bit
  ld a, $FB
  out ($3F), a                 ; CLK high (rising edge): the presented bit is stable
  in a, ($DD)                  ; read DAT (TH = bit 7)
  ld c, a                      ; stash before A is clobbered driving CLK low
  ld a, $BB
  out ($3F), a                 ; CLK low (falling edge): S3 sets up the next bit
  ld b, MIDI_SETTLE
mcb_settle:
  djnz mcb_settle              ; let the S3's edge ISR update DAT before next edge
  rl c                         ; DAT (bit 7) -> CARRY
  ret

midi_clock_byte:               ; -> A = one byte, MSB first
  ld d, 8
  ld e, 0
mcby_l:
  call midi_clock_bit          ; CARRY = next bit
  rl e                         ; acc <<= 1, bring the bit in at bit 0
  dec d
  jr nz, mcby_l
  ld a, e
  ret

; drain the S3 FIFO once per frame + dispatch (genmddj/MIDI.md §3.3). The
; inter-frame gap re-arms the S3's leading flag bit. Per event: flag bit (1 -> a
; 3-byte frame follows; 0 -> queue empty), then status/d1/d2.
midi_poll:
  ld a, $BB
  out ($3F), a                 ; CLK low = idle (the frame gap armed the flag)
  ld a, MIDI_CAP
  ld (midi_cnt), a
mp_loop:
  call midi_clock_bit          ; CARRY = leading flag bit
  jr nc, mp_done               ; 0 -> queue empty
  call midi_clock_byte
  ld (midi_st), a
  call midi_clock_byte
  ld (midi_d1), a
  call midi_clock_byte
  ld (midi_d2), a
  call midi_dispatch
  ld a, (midi_cnt)
  dec a
  ld (midi_cnt), a
  jr nz, mp_loop
mp_done:
  ld a, $BB
  out ($3F), a                 ; leave CLK low (idle)
  ret

; ---------------------------------------------------------------------------
; dispatch (genmddj/MIDI.md §3.4). status = type<<4 | channel. channel 0-3 ->
; track (IX); 4-15 ignored. type 2=NoteOn 1=NoteOff 4=PgmChange 7=Panic. The S3
; normalises MIDI (running status expanded, vel-0 -> NoteOff, CC120/123 -> Panic),
; so this is a bounded type switch; CC/bend/pressure are ignored in v1.
; ---------------------------------------------------------------------------
midi_dispatch:
  ld a, (midi_st)
  and $0F                      ; MIDI channel 0-15
  cp 4                         ; SMS has 4 voices -> ignore ch >= 4
  ret nc
  ld (cur_trig_ch), a          ; PSG write routing
  add a, a
  add a, a
  add a, a
  add a, a
  add a, a                     ; * 32 (struct stride)
  ld e, a
  ld d, 0
  ld ix, chst
  add ix, de                   ; IX = the addressed channel
  ld a, (midi_st)
  and $F0
  cp $20
  jr z, midi_note_on           ; type 2
  cp $10
  jr z, midi_note_off          ; type 1
  cp $40
  jr z, midi_pgm               ; type 4
  cp $70
  jr z, midi_panic             ; type 7
  ret                          ; CC/bend/pressure: ignored (v1)

; NoteOn: IX = channel, cur_trig_ch set. d1 = note, d2 = velocity.
midi_note_on:
  ld a, (midi_d2)
  or a
  jr z, midi_note_off          ; vel 0 = note off (S3 normalises, but be safe)
  ld a, (midi_d1)              ; MIDI note -> tracker note index (clamped)
  sub MIDI_NOTE_OFF
  jr nc, mno_hi
  xor a
mno_hi:
  cp NOTE_COUNT
  jr c, mno_set
  ld a, NOTE_COUNT-1
mno_set:
  ld (ix+0), a                 ; note index (trigger_note adds the instr transpose)
  call midi_track_ptr          ; HL = midi_instr + track
  ld a, (hl)
  ld (ix+1), a                 ; instrument = this track's current MIDI instrument
  ld (ix+6), 1                 ; active
  call trigger_note            ; key-on: AHD peak from the instrument, STG_ATK
  ld a, (midi_d2)              ; velocity -> AHD peak (override the instrument's)
  rrca
  rrca
  rrca
  and $0F                      ; 0-15
  rlca
  rlca
  rlca
  rlca                         ; peak into the high nibble
  ld c, a
  ld a, (ix+4)
  and $0F                      ; keep the envelope stage (STG_ATK)
  or c
  ld (ix+4), a
  call midi_track_held         ; HL = midi_held + track
  ld a, (midi_d1)
  ld (hl), a                   ; record the held note for note-off matching
  ret

; NoteOff: IX = channel. Release = enter the decay stage (envelope release).
midi_note_off:
  call midi_track_held         ; HL = midi_held + track
  ld a, (midi_d1)
  cp (hl)
  ret nz                       ; stale note-off (a different note holds): ignore
  ld (hl), $FF
  ld a, (ix+4)                 ; keep the peak, ramp it down at the DCY rate
  and $F0
  or STG_DCY
  ld (ix+4), a
  ret

; PgmChange: IX = channel, d1 = PC. SMS has 16 instruments -> clamp to 0-15.
midi_pgm:
  ld a, (midi_d1)
  cp 16
  jr c, mpg_ok
  ld a, 15
mpg_ok:
  ld c, a
  call midi_track_ptr          ; HL = midi_instr + track
  ld (hl), c
  ret

; Panic / all-notes-off (channel byte ignored). Also used on mode entry/exit.
midi_panic:
  ld ix, chst
  ld c, 0
mpn_l:
  ld (ix+4), STG_IDLE          ; silence the envelope
  ld (ix+6), 0                 ; inactive
  ld (ix+0), $FF               ; no note
  ld de, 32
  add ix, de
  inc c
  ld a, c
  cp 4
  jr c, mpn_l
  ld a, $FF                    ; clear held-note state
  ld (midi_held+0), a
  ld (midi_held+1), a
  ld (midi_held+2), a
  ld (midi_held+3), a
  ld hl, psg_vols              ; silence all four channels now
  ld (hl), $0F
  inc hl
  ld (hl), $0F
  inc hl
  ld (hl), $0F
  inc hl
  ld (hl), $0F
  ret

; ---------------------------------------------------------------------------
; midi_mode_change: SYNC entered or left MIDI. Panic (clean slate), then set the
; port pins: MIDI -> TR=CLK output (idle low), TH=DAT input; else release. Called
; from stp_sync after sync_mode is written.
; ---------------------------------------------------------------------------
midi_mode_change:
  call midi_panic
  ld a, (sync_mode)
  cp SYNC_MIDI
  jr nz, mmc_off
  ld a, $BB                    ; CLK(TR) low idle, TH input (sync_pulse_out idiom)
  out ($3F), a
  xor a                        ; reset the per-track instrument selection
  ld (midi_instr+0), a
  ld (midi_instr+1), a
  ld (midi_instr+2), a
  ld (midi_instr+3), a
  ret
mmc_off:
  ld a, $FF                    ; release the port-2 lines
  out ($3F), a
  ret

; HL = midi_instr + cur_trig_ch. Clobbers A/DE.
midi_track_ptr:
  ld a, (cur_trig_ch)
  ld e, a
  ld d, 0
  ld hl, midi_instr
  add hl, de
  ret

; HL = midi_held + cur_trig_ch. Clobbers A/DE.
midi_track_held:
  ld a, (cur_trig_ch)
  ld e, a
  ld d, 0
  ld hl, midi_held
  add hl, de
  ret

.ENDS
