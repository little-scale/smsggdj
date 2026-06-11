; =============================================================
; SMSDJ - sequencer engine (milestone 5: song/chain playback)
;
; Per-tick pipeline (design doc 5.2, subset):
;   groove counter -> row advance (-> chain/song advance at
;   phrase boundaries) -> trigger/commands -> envelope ->
;   length/kill -> PSG shadows -> mute gate
;
; Playback modes (transport context, design doc 3/5.4):
;   MODE_SONG   all tracks walk song rows -> chains -> phrases
;   MODE_CHAIN  edited track loops the current chain (solo)
;   MODE_PHRASE edited track loops the current phrase (solo)
;
; Channel state: 4 structs of 32 bytes, walked with IX.
;   +0 note index ($FF = none)   +1 instrument index
;   +2 volume (musical 0-F)      +3 envelope tick counter
;   +4 length/kill ctr ($FF off) +5 envelope cache (dir|speed)
;   +6 active flag               +7 song row
;   +8 chain step ($FF = load)   +9 transpose (signed)
;   +10 phrase # ($FF = none)    +11 chain # ($FF = none)
;   +12 pitched-noise flag       +13/+14 sweep accumulator
;   +15 vib phase  +16 trem phase
;   +17 sweep / +18 vib / +19 trem (cached at trigger)
;
; Instrument record (16 bytes): +0 type (0=TONE 1=NOISE),
;   +1 init volume, +2 envelope, +3 length, +4 noise control,
;   +5 sweep (signed, period/tick), +6 vib (speed|depth),
;   +7 trem (speed|depth), +8 transpose (signed semitones).
; Commands: 0 = none, 1 = K (kill after param ticks).
; =============================================================

.DEFINE CMD_NONE    0
.DEFINE CMD_KILL    1

.DEFINE MODE_SONG   0
.DEFINE MODE_CHAIN  1
.DEFINE MODE_PHRASE 2

.DEFINE SONG_ROWS   128
.DEFINE NUM_PHRASES 32
.DEFINE NUM_CHAINS  32

.RAMSECTION "engvars" SLOT 3
  play_state   db
  eng_mode     db
  cur_row      db            ; phrase row, shared by all tracks
  groove_cnt   db
  groove_pos   db
  mute_flags   db            ; bits 0-3
  eng_start    db            ; song row playback began on (loop point)
  chst         dsb 4*32      ; channel state structs (stride 32)
.ENDS

.RAMSECTION "songdata" SLOT 3
  phrase_pool  dsb NUM_PHRASES*64
  chains       dsb NUM_CHAINS*32   ; 16 x (phrase #, transpose)
  song         dsb SONG_ROWS*4     ; chain # per track, $FF empty
  instruments  dsb 16*16
  grooves      dsb 16
.ENDS

.SECTION "Engine" FREE

; -------------------------------------------------------------
; start playback. A = mode; for MODE_SONG the start row comes
; from song_cur, for chain/phrase modes cur_chain/cur_phrase and
; ed_track select the material (editor variables).
engine_play:
  ld (eng_mode), a
  ld a, $FF
  ld (cur_row), a            ; first tick advances to row 0
  ld a, 1
  ld (groove_cnt), a
  xor a
  ld (groove_pos), a
  ld a, (song_cur)
  ld (eng_start), a          ; song loops back here

  ld ix, chst
  ld c, 0
ep_chl:
  ld (ix+0), $FF
  ld (ix+2), 0
  ld (ix+3), 1
  ld (ix+4), $FF
  ld (ix+5), 0
  ld (ix+8), $FF             ; chain step: load on first boundary
  ld (ix+9), 0
  ld (ix+10), $FF
  ld (ix+11), $FF
  ld (ix+12), 0              ; pitched-noise flag
  ld a, (song_cur)
  ld (ix+7), a
  ; active?
  ld a, (eng_mode)
  cp MODE_SONG
  jr z, ep_active
  ld a, (ed_track)
  cp c
  jr z, ep_solo
  ld (ix+6), 0
  jr ep_next
ep_solo:
  ld a, (eng_mode)
  cp MODE_CHAIN
  jr nz, ep_phr
  ld a, (cur_chain)
  ld (ix+11), a
  jr ep_active
ep_phr:
  ld a, (cur_phrase)
  ld (ix+10), a
ep_active:
  ld (ix+6), 1
ep_next:
  ld de, 32
  add ix, de
  inc c
  ld a, c
  cp 4
  jr c, ep_chl

  ld a, 1
  ld (play_state), a
  ret

engine_stop:
  xor a
  ld (play_state), a
  ; zero channel volumes so the prelisten fx pass stays silent
  ld hl, chst+2
  ld de, 32
  ld b, 4
es_vols:
  ld (hl), 0
  add hl, de
  djnz es_vols
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
  call engine_tick
  ; mute gate: muted tracks keep sequencing, output is silenced
  ld a, (mute_flags)
  ld b, a
  ld hl, psg_vols
  ld c, 4
mg_loop:
  rr b
  jr nc, mg_next
  ld (hl), $0F
mg_next:
  inc hl
  dec c
  jr nz, mg_loop
  ret

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
  or a
  jr nz, et_gok
  ld a, 6                    ; safety for empty groove
et_gok:
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

  ; advance row; at phrase boundaries walk chains/song
  ld a, (cur_row)
  inc a
  and $0F
  ld (cur_row), a
  or a
  call z, advance_positions
  call process_row
et_fx:
  jp channels_fx

; -------------------------------------------------------------
; phrase boundary: move every active track to its next phrase
advance_positions:
  ld ix, chst
  ld c, 0
ap_loop:
  ld a, (ix+6)
  or a
  jr z, ap_next
  call advance_track
ap_next:
  ld de, 32
  add ix, de
  inc c
  ld a, c
  cp 4
  jr c, ap_loop
  ret

advance_track:
  ld a, (eng_mode)
  cp MODE_PHRASE
  ret z                      ; phrase loops in place
  cp MODE_CHAIN
  jr nz, at_song

  ; ---- chain loop mode ----
  ld a, (ix+8)
  inc a                      ; $FF -> 0 on first boundary
  cp 16
  jr c, at_cread
  xor a
at_cread:
  ld (ix+8), a
  call chain_entry           ; uses (ix+11), (ix+8) -> HL
  ld a, (hl)
  cp $FF
  jr nz, at_cset
  ld (ix+8), 0               ; wrap to chain start
  call chain_entry
  ld a, (hl)
  cp $FF
  jr nz, at_cset
  ld (ix+6), 0               ; empty chain: go silent
  ret
at_cset:
  ld (ix+10), a
  inc hl
  ld a, (hl)
  ld (ix+9), a
  ret

  ; ---- song mode ----
at_song:
  ld a, (ix+8)
  cp $FF
  jr z, at_load              ; first boundary: load current row
  inc a
  cp 16
  jr nc, at_nextrow
  ld (ix+8), a
  call chain_entry
  ld a, (hl)
  cp $FF
  jr z, at_nextrow
  ld (ix+10), a
  inc hl
  ld a, (hl)
  ld (ix+9), a
  ret
at_nextrow:
  ld a, (ix+7)
  inc a
  cp SONG_ROWS
  jr c, at_setrow
  ld a, (eng_start)          ; ran off the end: loop
at_setrow:
  ld (ix+7), a
at_load:
  ; chain # from song[songrow][track]
  ld l, (ix+7)
  ld h, 0
  add hl, hl
  add hl, hl                 ; row * 4
  ld e, c
  ld d, 0
  add hl, de
  ld de, song
  add hl, de
  ld a, (hl)
  cp $FF
  jr z, at_wrap
  ld (ix+11), a
  ld (ix+8), 0
  call chain_entry
  ld a, (hl)
  cp $FF
  jr z, at_wrap              ; empty chain
  ld (ix+10), a
  inc hl
  ld a, (hl)
  ld (ix+9), a
  ret
at_wrap:
  ; empty slot: loop to the start row once; if we are already
  ; there (or it is empty too) the track goes silent
  ld a, (ix+7)
  ld d, a
  ld a, (eng_start)
  cp d
  jr z, at_off
  ld (ix+7), a
  jr at_load
at_off:
  ld (ix+6), 0
  ld (ix+10), $FF
  ret

; HL = &chains[(ix+11)][(ix+8)]
chain_entry:
  ld l, (ix+11)
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl                 ; chain * 32
  ld a, (ix+8)
  add a, a
  ld e, a
  ld d, 0
  add hl, de
  ld de, chains
  add hl, de
  ret

; -------------------------------------------------------------
; read the new row on all active tracks
process_row:
  ld ix, chst
  ld c, 0
pr_loop:
  ld a, (ix+6)
  or a
  jr z, pr_next
  ld a, (ix+10)
  cp $FF
  jr z, pr_next

  ; HL = step = phrase_pool + phrase*64 + row*4
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl                 ; * 64
  ld a, (cur_row)
  add a, a
  add a, a
  ld e, a
  ld d, 0
  add hl, de
  ld de, phrase_pool
  add hl, de

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
  ; apply chain transpose, clamp to table
  add a, (ix+9)
  jp p, pr_nclamp
  xor a
pr_nclamp:
  cp NOTE_COUNT
  jr c, pr_nok
  ld a, NOTE_COUNT-1
pr_nok:
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
  ld de, 32
  add ix, de
  inc c
  ld a, c
  cp 4
  jp c, pr_loop
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
  ld c, (hl)                 ; +4 noise control
  inc hl
  ld a, (hl)                 ; +5 sweep
  ld (ix+17), a
  inc hl
  ld a, (hl)                 ; +6 pitch mod (speed|depth)
  ld (ix+18), a
  inc hl
  ld a, (hl)                 ; +7 amp mod (speed|depth)
  ld (ix+19), a
  inc hl
  ld a, (hl)                 ; +8 transpose (signed semitones)
  or a
  jr z, tn_mods
  add a, (ix+0)              ; stacks with the chain transpose
  jp m, tn_tlo
  cp NOTE_COUNT
  jr c, tn_tst
  ld a, NOTE_COUNT-1
  jr tn_tst
tn_tlo:
  xor a
tn_tst:
  ld (ix+0), a
tn_mods:
  ; reset modulation state
  xor a
  ld (ix+13), a              ; sweep accumulator
  ld (ix+14), a
  ld (ix+15), a              ; vib phase
  ld (ix+16), a              ; trem phase
  ld (ix+12), a              ; pitched-noise flag off by default
  ld a, b
  cp 1                       ; NOISE instrument?
  ret nz
  ld a, c
  ld (psg_noisectl), a
  and $03
  cp $03                     ; rate 3 = clock from tone 3
  ret nz
  ld (ix+12), 1              ; pitched: steal T3 (design doc 5.3)
  ret

; -------------------------------------------------------------
; A = note index -> DE = period with sweep + pitch mod applied,
; clamped to 1..1023. Uses the IX channel's mod state.
calc_period:
  add a, a
  ld e, a
  ld d, 0
  ld hl, (note_ptr)
  add hl, de
  ld e, (hl)
  inc hl
  ld d, (hl)                 ; base period
  ; --- sweep: acc += param, period += acc ---
  ld a, (ix+17)
  or a
  jr z, cpd_vib
  ld c, a                    ; sign-extend into BC
  rlca
  sbc a, a
  ld b, a
  ld l, (ix+13)
  ld h, (ix+14)
  add hl, bc
  ld (ix+13), l
  ld (ix+14), h
  add hl, de
  ex de, hl
cpd_vib:
  ; --- pitch mod: phase += speed*2, += vib_tables[depth][step] ---
  ld a, (ix+18)
  and $0F
  jr z, cpd_clamp
  ld b, a                    ; depth
  ld a, (ix+18)
  and $F0
  rrca
  rrca                       ; speed * 4 (max ~12 Hz at 50 Hz)
  ld c, a
  ld a, (ix+15)
  add a, c
  ld (ix+15), a
  rrca
  rrca
  rrca
  and $1F                    ; 32 steps per cycle
  ld c, a
  ld l, b
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl                 ; depth * 32
  ld b, 0
  add hl, bc
  ld bc, vib_tables
  add hl, bc
  ld a, (hl)                 ; signed delta
  ld c, a
  rlca
  sbc a, a
  ld b, a
  ex de, hl
  add hl, bc
  ex de, hl
cpd_clamp:
  bit 7, d                   ; negative -> floor
  jr z, cpd_hi
  ld de, 1
  ret
cpd_hi:
  ld a, d
  cp 4                       ; >= 1024 -> ceiling
  jr c, cpd_zero
  ld de, 1023
  ret
cpd_zero:
  or e
  ret nz
  ld de, 1
  ret

; volume in A -> A with tremolo dip applied (uses IX phase)
calc_trem:
  ld d, a
  ld a, (ix+19)
  and $0F
  ld a, d
  ret z
  ld e, a                    ; depth nonzero: advance phase
  ld a, (ix+19)
  and $0F
  ld b, a                    ; depth
  ld a, (ix+19)
  and $F0
  rrca
  rrca                       ; speed * 4 (max ~12 Hz at 50 Hz)
  ld c, a
  ld a, (ix+16)
  add a, c
  ld (ix+16), a
  rrca
  rrca
  rrca
  and $1F
  ld c, a
  ld l, b
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl                 ; depth * 32
  ld b, 0
  add hl, bc
  ld bc, trem_tables
  add hl, bc
  ld a, e                    ; volume
  sub (hl)                   ; - dip
  ret nc
  xor a
  ret

; -------------------------------------------------------------
; per-tick: envelopes, length, write PSG shadows
channels_fx:
  ld ix, chst
  ld c, 0
cf_loop:
  ; --- envelope ---
  ; speed 1 = 4 vol steps/tick, 2 = 2 steps/tick, 3 = 1/tick,
  ; 4..F = one step every speed-2 ticks (ticks are the engine's
  ; finest resolution: one per frame)
  ld a, (ix+5)
  and $0F
  jr z, cf_len               ; speed 0 = env off
  ld b, a
  ld a, (ix+5)
  and $F0
  jr z, cf_len               ; dir 0 = env off
  ld a, b
  cp 3
  jr c, cf_envfast
  sub 2
  ld b, a
  dec (ix+3)
  jr nz, cf_len
  ld (ix+3), b               ; reload tick counter
  ld b, 1
  jr cf_envstep
cf_envfast:
  dec a                      ; 1 -> 4 steps, 2 -> 2 steps
  ld b, 2
  jr nz, cf_envstep
  ld b, 4
cf_envstep:
  ld a, (ix+5)
  and $F0
  cp $10
  jr z, cf_envdn
  ld a, (ix+2)               ; fade up
  add a, b
  cp $0F
  jr c, cf_envst
  ld a, $0F
  jr cf_envst
cf_envdn:
  ld a, (ix+2)               ; fade down
  sub b
  jr nc, cf_envst
  xor a
cf_envst:
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
  jr z, cf_noise
  ld a, (ix+0)
  cp $FF
  jr z, cf_vol
  push bc
  call calc_period           ; note -> DE with sweep/vib applied
  pop bc
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
  jr cf_vol
cf_noise:
  ; pitched noise: drive T3's period with our note and mute
  ; T3's own output (runs after c=2, so this wins)
  ld a, (ix+12)
  or a
  jr z, cf_vol
  ld a, (ix+0)
  cp $FF
  jr z, cf_vol
  push bc
  call calc_period
  pop bc
  ex de, hl
  ld (psg_tone2), hl
  ld a, $0F
  ld (psg_vols+2), a
cf_vol:
  ld a, (ix+2)
  push bc
  call calc_trem             ; amp mod dip
  pop bc
  cpl
  and $0F                    ; attenuation = 15 - volume
  ld hl, psg_vols
  ld e, c
  ld d, 0
  add hl, de
  ld (hl), a
  ld de, 32
  add ix, de
  inc c
  ld a, c
  cp 4
  jp c, cf_loop
  ret

; -------------------------------------------------------------
; copy demo song from ROM into the RAM song structures
song_init:
  ; empty song and chains ($FF = unused)
  ld hl, song
  ld de, song+1
  ld bc, SONG_ROWS*4-1
  ld (hl), $FF
  ldir
  ld hl, chains
  ld de, chains+1
  ld bc, NUM_CHAINS*32-1
  ld (hl), $FF
  ldir

  ld hl, demo_phrases
  ld de, phrase_pool
  ld bc, 4*64
  ldir
  ld hl, demo_instruments
  ld de, instruments
  ld bc, 6*16
  ldir
  ld hl, demo_groove
  ld de, grooves
  ld bc, 16
  ldir
  ld hl, demo_chains
  ld de, chains
  ld bc, 4*32
  ldir
  ld hl, demo_song
  ld de, song
  ld bc, 2*4
  ldir
  ret

; -------------------------------------------------------------
; demo data. note byte = note index + 1 (0 = rest)
; A-2=1 E-3=8 G-3=11 A-3=13 E-4=20 B-4=27 A-4=25 C-5=28
; D-5=30 E-5=32 G-5=35 A-5=37
; -------------------------------------------------------------
demo_phrases:
; phrase 0: lead (instr 0)
  .db 25,0,0,0,    0,$FF,0,0,  28,0,0,0,    32,0,0,0
  .db 37,0,0,0,    0,$FF,0,0,  35,0,0,0,    32,0,0,0
  .db 0,$FF,0,0,   28,0,0,0,   30,0,0,0,    0,$FF,0,0
  .db 32,0,0,0,    0,$FF,0,0,  27,0,0,0,    0,$FF,CMD_KILL,3
; phrase 1: offbeat comp (instr 1)
  .db 0,$FF,0,0,   13,1,0,0,   0,$FF,0,0,   20,1,0,0
  .db 0,$FF,0,0,   13,1,0,0,   0,$FF,0,0,   20,1,0,0
  .db 0,$FF,0,0,   13,1,0,0,   0,$FF,0,0,   20,1,0,0
  .db 0,$FF,0,0,   13,1,0,0,   0,$FF,0,0,   20,1,0,0
; phrase 2: bass (instr 2)
  .db 1,2,0,0,     0,$FF,0,0,  1,2,0,0,     0,$FF,0,0
  .db 13,2,0,0,    0,$FF,0,0,  1,2,0,0,     0,$FF,0,0
  .db 1,2,0,0,     0,$FF,0,0,  11,2,0,0,    0,$FF,0,0
  .db 8,2,0,0,     0,$FF,0,0,  1,2,0,0,     0,$FF,CMD_KILL,4
; phrase 3: drums (instr 3 hat, 4 snare)
  .db 1,3,0,0,     0,$FF,0,0,  1,3,0,0,     0,$FF,0,0
  .db 1,4,0,0,     0,$FF,0,0,  1,3,0,0,     0,$FF,0,0
  .db 1,3,0,0,     0,$FF,0,0,  1,3,0,0,     0,$FF,0,0
  .db 1,4,0,0,     0,$FF,0,0,  1,3,0,0,     1,3,0,0

; chains: 16 x (phrase, transpose), $FF = end
demo_chains:
; chain 0: lead phrase, then octave up
  .db 0,0, 0,12
  .db $FF,0, $FF,0, $FF,0, $FF,0, $FF,0, $FF,0, $FF,0
  .db $FF,0, $FF,0, $FF,0, $FF,0, $FF,0, $FF,0, $FF,0
; chain 1: comp twice
  .db 1,0, 1,0
  .db $FF,0, $FF,0, $FF,0, $FF,0, $FF,0, $FF,0, $FF,0
  .db $FF,0, $FF,0, $FF,0, $FF,0, $FF,0, $FF,0, $FF,0
; chain 2: bass twice
  .db 2,0, 2,0
  .db $FF,0, $FF,0, $FF,0, $FF,0, $FF,0, $FF,0, $FF,0
  .db $FF,0, $FF,0, $FF,0, $FF,0, $FF,0, $FF,0, $FF,0
; chain 3: drums twice
  .db 3,0, 3,0
  .db $FF,0, $FF,0, $FF,0, $FF,0, $FF,0, $FF,0, $FF,0
  .db $FF,0, $FF,0, $FF,0, $FF,0, $FF,0, $FF,0, $FF,0

; song rows: chain per track
demo_song:
  .db 0,1,2,3
  .db 0,1,2,3

; type, vol, env(dir|speed), len, noisectl, pad to 16
demo_instruments:
; env speeds remapped for the new scale (3 = old 1, 4 = old 2 ...)
  .db 0,$0F,$14,0,$00, $00,$33,$00,$00, 0,0,0,0,0,0,0   ; 0 lead (vib 3/3)
  .db 0,$0A,$13,0,$00, $00,$00,$00,$00, 0,0,0,0,0,0,0   ; 1 pluck
  .db 0,$0F,$15,0,$00, $00,$00,$00,$00, 0,0,0,0,0,0,0   ; 2 bass
  .db 1,$0B,$12,2,$04, $00,$00,$00,$00, 0,0,0,0,0,0,0   ; 3 hat (white /512)
  .db 1,$0F,$14,8,$05, $00,$00,$00,$00, 0,0,0,0,0,0,0   ; 4 snare (white /1024)
  .db 1,$0F,$15,0,$03, $00,$00,$00,$00, 0,0,0,0,0,0,0   ; 5 periodic bass (pitched)

demo_groove:
  .db 6,6,0,0,0,0,0,0,0,0,0,0,0,0,0,0

.ENDS
