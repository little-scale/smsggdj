; =============================================================
; SMSDJ - sequencer engine core (milestone 3)
;
; Per-tick pipeline (design doc 5.2, subset):
;   groove counter -> row advance -> trigger/commands
;   -> software envelope -> length/kill -> PSG shadows
;
; Tick source abstraction: engine_frame asks the tick source how
; many ticks elapsed (internal source = 1 per VBlank; the MIDI
; slave source will return the adapter's clock count instead).
;
; Channel state: 4 structs of 8 bytes, walked with IX.
; (IX is fine at this scale; revisit if the fx loop grows hot.)
;   +0 note index ($FF = none)
;   +1 instrument index
;   +2 current volume (musical 0-F)
;   +3 envelope tick counter
;   +4 length/kill countdown ($FF = off)
;   +5 envelope cache (hi: dir 0=off/1=down/2=up, lo: speed)
;   +6,+7 reserved
;
; Instrument record (16 bytes, design doc layout, subset used):
;   +0 type (0=TONE, 1=NOISE)  +1 initial volume
;   +2 envelope (dir<<4|speed) +3 length (ticks, 0=hold)
;   +4 noise control nibble    +5..+15 reserved
;
; Commands: 0 = none, 1 = K (kill: cut note after param ticks,
; param 0 = cut immediately).
; =============================================================

.DEFINE CMD_NONE 0
.DEFINE CMD_KILL 1

.RAMSECTION "engvars" SLOT 3
  play_state   db
  cur_row      db
  drawn_row    db            ; last row highlighted by the UI
  groove_cnt   db
  groove_pos   db
  chst         dsb 4*8       ; channel state structs
  phrase_ptrs  dsb 4*2       ; phrase base per track
.ENDS

.RAMSECTION "songdata" SLOT 3
  phrase_pool  dsb 8*64      ; 8 phrases (grows per design doc)
  instruments  dsb 16*16
  grooves      dsb 16
.ENDS

.SECTION "Engine" FREE

; -------------------------------------------------------------
engine_play:
  ld a, $FF
  ld (cur_row), a            ; first tick advances to row 0
  ld (drawn_row), a
  ld a, 1
  ld (groove_cnt), a
  xor a
  ld (groove_pos), a
  ld ix, chst
  ld de, 8
  ld b, 4
ep_chl:
  ld (ix+0), $FF
  ld (ix+2), 0
  ld (ix+3), 1
  ld (ix+4), $FF
  ld (ix+5), 0
  add ix, de
  djnz ep_chl
  ld a, 1
  ld (play_state), a
  ret

engine_stop:
  xor a
  ld (play_state), a
  ld a, $0F                  ; silence all channels
  ld (psg_vols), a
  ld (psg_vols+1), a
  ld (psg_vols+2), a
  ld (psg_vols+3), a
  ret

; -------------------------------------------------------------
; called once per frame; runs N engine ticks (tick source)
engine_frame:
  ld a, (play_state)
  or a
  ret z
  ; tick source: INTERNAL = exactly 1 tick per VBlank.
  ; (MIDI SLAVE will instead run the adapter's clock count.)
  ; fall through to engine_tick

engine_tick:
  ld hl, groove_cnt
  dec (hl)
  jr nz, et_fx

  ; reload groove counter from table
  ld a, (groove_pos)
  ld e, a
  ld d, 0
  ld hl, grooves
  add hl, de
  ld a, (hl)
  ld (groove_cnt), a
  ; advance groove pos (wrap at 16 or on 0-terminator)
  ld a, (groove_pos)
  inc a
  cp 16
  jr nc, et_gwrap
  ld e, a
  ld d, 0
  ld hl, grooves
  add hl, de
  ld b, a
  ld a, (hl)
  or a
  ld a, b
  jr nz, et_gstore
et_gwrap:
  xor a
et_gstore:
  ld (groove_pos), a

  ; advance row and process it
  ld a, (cur_row)
  inc a
  and $0F
  ld (cur_row), a
  call process_row
et_fx:
  jp channels_fx

; -------------------------------------------------------------
; read the new row on all 4 tracks
process_row:
  ld ix, chst
  ld c, 0
pr_loop:
  ; HL = step = phrase_ptrs[c] + row*4
  ld a, c
  add a, a
  ld e, a
  ld d, 0
  ld hl, phrase_ptrs
  add hl, de
  ld e, (hl)
  inc hl
  ld d, (hl)
  ld a, (cur_row)
  add a, a
  add a, a
  ld l, a
  ld h, 0
  add hl, de                 ; hl = step base

  ; instrument byte first, so a trigger uses it
  inc hl
  ld a, (hl)
  cp $10
  jr nc, pr_note
  ld (ix+1), a
pr_note:
  dec hl
  ld a, (hl)
  or a
  jr z, pr_cmd
  dec a
  ld (ix+0), a
  push hl
  push bc
  call trigger_note
  pop bc
  pop hl
pr_cmd:
  inc hl
  inc hl
  ld a, (hl)                 ; command
  cp CMD_KILL
  jr nz, pr_next
  inc hl
  ld a, (hl)                 ; param
  or a
  jr nz, pr_kill_later
  ld (ix+2), 0               ; K00: cut now
  jr pr_next
pr_kill_later:
  ld (ix+4), a
pr_next:
  ld de, 8
  add ix, de
  inc c
  ld a, c
  cp 4
  jr c, pr_loop
  ret

; trigger note on channel struct IX from instrument (ix+1)
trigger_note:
  ld a, (ix+1)
  add a, a
  add a, a
  add a, a
  add a, a                   ; * 16
  ld e, a
  ld d, 0
  ld hl, instruments
  add hl, de
  ld a, (hl)                 ; +0 type
  ld b, a
  inc hl
  ld a, (hl)                 ; +1 initial volume
  ld (ix+2), a
  inc hl
  ld a, (hl)                 ; +2 envelope
  ld (ix+5), a
  and $0F
  jr nz, tn_spd
  ld a, 1                    ; keep counter sane when env off
tn_spd:
  ld (ix+3), a
  inc hl
  ld a, (hl)                 ; +3 length
  or a
  jr nz, tn_len
  ld a, $FF
tn_len:
  ld (ix+4), a
  inc hl
  ld a, b
  cp 1                       ; NOISE instrument?
  ret nz
  ld a, (hl)                 ; +4 noise control
  ld (psg_noisectl), a
  ret

; -------------------------------------------------------------
; per-tick: envelopes, length, write PSG shadows
channels_fx:
  ld ix, chst
  ld c, 0
cf_loop:
  ; --- envelope ---
  ld a, (ix+5)
  and $0F
  jr z, cf_len               ; speed 0 = env off
  ld b, a
  ld a, (ix+5)
  and $F0
  jr z, cf_len               ; dir 0 = env off
  dec (ix+3)
  jr nz, cf_len
  ld (ix+3), b               ; reload counter
  cp $10
  jr z, cf_envdn
  ld a, (ix+2)               ; fade up
  cp $0F
  jr nc, cf_len
  inc a
  ld (ix+2), a
  jr cf_len
cf_envdn:
  ld a, (ix+2)               ; fade down
  or a
  jr z, cf_len
  dec a
  ld (ix+2), a

  ; --- length / kill countdown ---
cf_len:
  ld a, (ix+4)
  cp $FF
  jr z, cf_out
  dec a
  ld (ix+4), a
  jr nz, cf_out
  ld (ix+2), 0               ; cut
  ld (ix+4), $FF

  ; --- write shadows ---
cf_out:
  ld a, c
  cp 3
  jr z, cf_vol               ; noise: ctl set at trigger
  ld a, (ix+0)
  cp $FF
  jr z, cf_vol
  add a, a                   ; period lookup
  ld e, a
  ld d, 0
  ld hl, (note_ptr)
  add hl, de
  ld e, (hl)
  inc hl
  ld d, (hl)
  push de
  ld hl, psg_tone0
  ld a, c
  add a, a
  ld e, a
  ld d, 0
  add hl, de
  pop de
  ld (hl), e
  inc hl
  ld (hl), d
cf_vol:
  ld a, (ix+2)
  cpl
  and $0F                    ; attenuation = 15 - volume
  ld hl, psg_vols
  ld e, c
  ld d, 0
  add hl, de
  ld (hl), a
  ld de, 8
  add ix, de
  inc c
  ld a, c
  cp 4
  jp c, cf_loop
  ret

; -------------------------------------------------------------
; copy demo song from ROM into the RAM song structures
song_init:
  ld hl, demo_phrases
  ld de, phrase_pool
  ld bc, 4*64
  ldir
  ld hl, demo_instruments
  ld de, instruments
  ld bc, 5*16
  ldir
  ld hl, demo_groove
  ld de, grooves
  ld bc, 16
  ldir
  ; track n -> phrase n
  ld hl, phrase_pool
  ld (phrase_ptrs), hl
  ld hl, phrase_pool+64
  ld (phrase_ptrs+2), hl
  ld hl, phrase_pool+128
  ld (phrase_ptrs+4), hl
  ld hl, phrase_pool+192
  ld (phrase_ptrs+6), hl
  ret

; -------------------------------------------------------------
; demo data. note byte = note index + 1 (0 = rest)
; A-2=1 E-3=8 G-3=11 A-3=13 E-4=20 B-4=27 A-4=25 C-5=28
; D-5=30 E-5=32 G-5=35 A-5=37
; -------------------------------------------------------------
demo_phrases:
; T1: lead (instr 0)
  .db 25,0,0,0,    0,$FF,0,0,  28,0,0,0,    32,0,0,0
  .db 37,0,0,0,    0,$FF,0,0,  35,0,0,0,    32,0,0,0
  .db 0,$FF,0,0,   28,0,0,0,   30,0,0,0,    0,$FF,0,0
  .db 32,0,0,0,    0,$FF,0,0,  27,0,0,0,    0,$FF,CMD_KILL,3
; T2: offbeat comp (instr 1)
  .db 0,$FF,0,0,   13,1,0,0,   0,$FF,0,0,   20,1,0,0
  .db 0,$FF,0,0,   13,1,0,0,   0,$FF,0,0,   20,1,0,0
  .db 0,$FF,0,0,   13,1,0,0,   0,$FF,0,0,   20,1,0,0
  .db 0,$FF,0,0,   13,1,0,0,   0,$FF,0,0,   20,1,0,0
; T3: bass (instr 2)
  .db 1,2,0,0,     0,$FF,0,0,  1,2,0,0,     0,$FF,0,0
  .db 13,2,0,0,    0,$FF,0,0,  1,2,0,0,     0,$FF,0,0
  .db 1,2,0,0,     0,$FF,0,0,  11,2,0,0,    0,$FF,0,0
  .db 8,2,0,0,     0,$FF,0,0,  1,2,0,0,     0,$FF,CMD_KILL,4
; NO: drums (instr 3 hat, 4 snare)
  .db 1,3,0,0,     0,$FF,0,0,  1,3,0,0,     0,$FF,0,0
  .db 1,4,0,0,     0,$FF,0,0,  1,3,0,0,     0,$FF,0,0
  .db 1,3,0,0,     0,$FF,0,0,  1,3,0,0,     0,$FF,0,0
  .db 1,4,0,0,     0,$FF,0,0,  1,3,0,0,     1,3,0,0

; type, vol, env(dir|speed), len, noisectl, pad to 16
demo_instruments:
  .db 0,$0F,$12,0,$00, 0,0,0,0,0,0,0,0,0,0,0   ; 0 lead
  .db 0,$0A,$11,0,$00, 0,0,0,0,0,0,0,0,0,0,0   ; 1 pluck
  .db 0,$0F,$13,0,$00, 0,0,0,0,0,0,0,0,0,0,0   ; 2 bass
  .db 1,$0B,$11,2,$04, 0,0,0,0,0,0,0,0,0,0,0   ; 3 hat (white /512)
  .db 1,$0F,$12,8,$05, 0,0,0,0,0,0,0,0,0,0,0   ; 4 snare (white /1024)

demo_groove:
  .db 6,6,0,0,0,0,0,0,0,0,0,0,0,0,0,0

.ENDS
