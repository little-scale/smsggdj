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
;   +12 pitched-noise flag / FM voice-keyed-on flag   +13/+14 sweep accumulator
;   +15 vib phase  +16 trem phase
;   +17 sweep / +18 vib / +19 trem (cached at trigger)
;   +20 table # ($FF off)  +21 table row  +22 table tick ctr
;   +23 table speed        +24 table pitch offset (signed)
;   +25 arp param (C cmd)  +26 arp phase  +27 finetune (signed)
;   +28 delay ctr  +29 delayed note  +30 porta speed
;   +31 retrig (counter hi | interval lo)
;
; Instrument record (16 bytes): +0 type (0=TONE 1=NOISE 2=SMP),
;   +1 init volume, +2 envelope, +3 length, +4 noise control,
;   +5 sweep (signed, period/tick), +6 vib (speed|depth),
;   +7 trem (speed|depth), +8 transpose (signed semitones),
;   +9 table ($FF = none), +10 table speed (ticks/row).
; Commands: 0 = none, 1 = K (kill after param ticks).
; =============================================================

.DEFINE CMD_NONE    0
.DEFINE CMD_KILL    1          ; K: cut after param ticks
.DEFINE CMD_HOP     2          ; H: phrase -> end now; table -> jump
.DEFINE CMD_TBL     3          ; A: start/switch table (>=16 off)
.DEFINE CMD_ARP     4          ; C: chord arp 0,x,y
.DEFINE CMD_ENV     5          ; E: ATK x, DCY y (re-slope AHD live)
.DEFINE CMD_FINE    6          ; F: finetune, period units
.DEFINE CMD_GRV     7          ; G: select groove
.DEFINE CMD_NOI     8          ; N: noise control override
.DEFINE CMD_PB      9          ; P: pitch bend (signed sweep/tick)
.DEFINE CMD_TPO     10         ; T: tempo, BPM -> even groove
.DEFINE CMD_VIB     11         ; V: vibrato override (speed|depth)
.DEFINE CMD_WAIT    12         ; W: shorten this row to param ticks
.DEFINE CMD_TREM    13         ; M: amp mod override (speed|depth)
.DEFINE CMD_DELAY   14         ; D: delay the note by param ticks
.DEFINE CMD_SLIDE   15         ; L: slide to the note, param = speed
.DEFINE CMD_RETRIG  16         ; R: retrigger every param ticks
.DEFINE CMD_PAN     17         ; O: GG stereo - x = left, y = right
.DEFINE CMD_ITER    18         ; I: play when (repeats mod x) == y
.DEFINE CMD_SPEED   19         ; S: sample speed (0 norm, 1 2x, 2 half)
.DEFINE CMD_WSET    20         ; B: set this note's wavetable (0-7)
.DEFINE CMD_VOL     21         ; X: set this note's volume (AHD peak 0-F)
.DEFINE CMD_FMPROG  22         ; Y: set this note's FM program (patch 1-15)
.DEFINE CMD_PROB    23         ; Z: chance the note triggers (00 never .. FF always)
.DEFINE CMD_JTRANS  24         ; J: signed transpose (x) on plays masked by y (mod 4)
.DEFINE CMD_COUNT   25

.DEFINE NUM_TABLES  16
.DEFINE NUM_GROOVES 16

; AHD envelope stages (ix+4). Anything else reads as idle.
.DEFINE STG_ATK     0          ; ramp 0 -> peak at ATK rate
.DEFINE STG_HLD     1          ; sit at peak (ix+3 ticks, $FF = forever)
.DEFINE STG_DCY     2          ; ramp peak -> 0 at DCY rate
.DEFINE STG_KILL    3          ; K command: count down then hard cut
.DEFINE STG_IDLE    4          ; finished/silent
.DEFINE STG_FMHOLD  5          ; FM note: count down then key off the FM voice
.DEFINE STG_FMDRUMHOLD 6       ; FM drum: count down then key off the rhythm voice
.DEFINE PRELISTEN_CAP 32       ; ticks: cap a forever-hold while stopped

.DEFINE MODE_SONG   0
.DEFINE MODE_CHAIN  1
.DEFINE MODE_PHRASE 2

; sync over controller port 2 (TR = pin 9, TH = pin 7, GND = 8)
; Sync modes mirror genmddj for cross-machine parity. OUT/IN are 1-clock-per-row
; (lock two units at any tempo); IN24 is the old 2-bit 24-PPQN method (the ESP32
; Ableton-Link bridge still sends 24 PPQN). MIDI is a reserved genmddj slot, not
; selectable on SMSGGDJ (it behaves as OFF if ever loaded).
.DEFINE SYNC_OFF    0          ; port untouched
.DEFINE SYNC_OUT    1          ; 2-bit counter out on TR+TH, one clock per row
.DEFINE SYNC_PULSE  2          ; Volca/PO pulse out on TR (2 PPQN)
.DEFINE SYNC_IN     3          ; follow an OUT master, one row per clock (/1)
.DEFINE SYNC_MIDI   4          ; reserved (genmddj parity); unused on SMSGGDJ
.DEFINE SYNC_IN24   5          ; follow a 24-PPQN sender, /6 (ESP32 Link bridge)
.DEFINE PULSE_DIV   12         ; ticks per pulse (2 PPQN, groove 6)

.DEFINE SONG_ROWS   128
.DEFINE NUM_PHRASES 52
.DEFINE NUM_CHAINS  40

.RAMSECTION "engvars" SLOT 3
  play_state   db
  eng_mode     db
  cur_row      db            ; row currently being processed (scratch)
  chan_row     dsb 4         ; per-channel within-phrase row (independent hop)
  groove_cnt   db
  groove_pos   db
  mute_flags   db            ; bits 0-3
  eng_start    db            ; song row playback began on
  eng_len      db            ; song rows until the wrap to row 0
  groove_sel   db            ; active groove
  hop_now      db            ; H just fired on this channel: hop NOW, same tick
  hop_guard    db            ; per-tick hop budget (kills an all-H spin)
  cur_trig_ch  db            ; channel being processed (for WAV)
  sync_mode    db            ; SYNC_* (0 = OFF, the default)
  sync_cnt     db            ; master row counter (OUT) / pulse divider (PULSE)
  sync_last    db            ; slave: counter value last frame
  sync_wait    db            ; slave: armed, waiting for a clock
  sync_acc     db            ; slave: received clocks toward the next row
  sync_ticks   db            ; (scratch)
  play_mode    db            ; 0 = SONG, 1 = LIVE
  trk_rep      dsb 4         ; chain repeat count per track (legacy)
  phrase_plays dsb NUM_PHRASES ; per-phrase play count (I command)
  echo_mode    db            ; 0 off, 1 = T2, 2 = T2+T3
  echo_tap1    db            ; T2 delay in rows (1-15, groove-scaled)
  echo_tap2    db            ; T3 delay in rows (1-15, groove-scaled)
  echo_red1    db            ; T2 attenuation added (quieter)
  echo_red2    db            ; T3 attenuation added
  echo_stereo  db            ; 1 = pan T2 left, T3 right (GG)
  echo_tsp1    db            ; tap1 transpose, signed semitones
  echo_tsp2    db            ; tap2 transpose, signed semitones
  echo_head    db            ; ring write index (0-63)
  echo_ring    dsb 64*4      ; T1 hist: period lo, hi, atten, note
  wav_ovr      db            ; B cmd: one-shot wave # ($FF = none)
  fm_ovr       db            ; Y cmd: one-shot FM program ($FF = none)
  tbl_ovr      db            ; A cmd: one-shot table # for this note ($FF = none)
  proj_tsp     db            ; global transpose, signed semitones
  live_q       dsb 4         ; queued song row per track ($FF -)
  sram_ok      db            ; cart SRAM detected at boot
  sram_slots   db            ; save slots available (0/1/3/6)
  sd4_cap      dw            ; SMDJ4 heap capacity in bytes (from the detected size)
  rng_state    dw            ; 16-bit LFSR for the Z (probability) command
  purge_used   dsb NUM_PHRASES ; PURGE: per-record "referenced" flags (reused for
                              ;   chains; 52 >= 40, and the two never run at once)
  purge_freed  db            ; PURGE: count of records blanked by the last run
  purge_ui     db            ; PURGE FILES-menu state: 0 idle, 3/4 = PRGC/PRGP
                              ;   armed ("SURE"), $80 = result shown ("FREED nn")
  chst         dsb 4*32      ; channel state structs (stride 32)
.ENDS

; 256-aligned so the wavetable feed can index waves by low byte;
; wave_ram leads the block so saves stay one contiguous copy
.RAMSECTION "songdata" SLOT 3 ALIGN 256
  wave_ram     dsb 8*32            ; 8 waves x 32 pre-OR'd bytes
  phrase_pool  dsb NUM_PHRASES*64
  chains       dsb NUM_CHAINS*32   ; 16 x (phrase #, transpose)
  song         dsb SONG_ROWS*4     ; chain # per track, $FF empty
  instruments  dsb 16*16
  tables       dsb NUM_TABLES*64  ; 16 x (vol, pitch, cmd, param)
  grooves      dsb NUM_GROOVES*16
.ENDS

.SECTION "Engine" FREE

; -------------------------------------------------------------
; start playback. A = mode; for MODE_SONG the start row comes
; from song_cur, for chain/phrase modes cur_chain/cur_phrase and
; ed_track select the material (editor variables).
engine_play:
  ld (eng_mode), a
  push af
  ld hl, (frame)             ; re-seed the Z-command RNG from the frame counter
  ld a, h
  or l                       ;   (so probabilities vary per playback; LFSR must
  jr nz, ep_seed             ;    stay non-zero)
  inc hl
ep_seed:
  ld (rng_state), hl
  xor a
  ld (hop_now), a            ; immediate-hop flag clear
  ld a, $FF
  ld (wav_ovr), a
  ld (fm_ovr), a
  ld (tbl_ovr), a
  pop af
  ld a, $FF                  ; per-channel rows: first tick advances each to row 0
  ld (chan_row+0), a
  ld (chan_row+1), a
  ld (chan_row+2), a
  ld (chan_row+3), a
  ld a, 1
  ld (groove_cnt), a
  xor a
  ld (groove_pos), a
  ld a, (song_cur)
  ld (eng_start), a
  ; song length: the wrap point is one past the last row that
  ; holds any chain on any track (empty cells are silent rows)
  ld hl, song + SONG_ROWS*4 - 1
  ld bc, SONG_ROWS*4
ep_scan:
  ld a, (hl)
  cp $FF
  jr nz, ep_found
  dec hl
  dec bc
  ld a, b
  or c
  jr nz, ep_scan
ep_found:
  ld h, b                    ; eng_len = ceil(bytes/4), min 1
  ld l, c
  ld de, 3
  add hl, de
  srl h
  rr l
  srl h
  rr l
  ld a, l
  or a
  jr nz, ep_lok
  inc a
ep_lok:
  ld (eng_len), a

  ld ix, chst
  ld c, 0
ep_chl:
  ld (ix+0), $FF
  ld (ix+2), 0
  ld (ix+3), 1
  ld (ix+4), STG_IDLE
  ld (ix+5), 0
  ld (ix+8), $FF             ; chain step: load on first boundary
  ld (ix+9), 0
  ld (ix+10), $FF
  ld (ix+11), $FF
  ld (ix+12), 0              ; pitched-noise flag
  ld (ix+20), $FF            ; table off
  ld (ix+24), 0              ; table pitch offset
  ld (ix+25), 0              ; arp off
  ld (ix+26), 0
  ld (ix+27), 0              ; finetune
  ld (ix+28), 0              ; delay
  ld (ix+30), 0              ; porta
  ld (ix+31), 0              ; retrig
  ld a, (song_cur)
  ld (ix+7), a
  ; active?
  ld a, (eng_mode)
  cp MODE_SONG
  jr z, ep_songstart
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
ep_songstart:
  ld a, (play_mode)          ; LIVE: every track starts silent; the
  or a                       ;   performer triggers chains one at a time
  jr nz, eps_off
  ; LSDJ start: the track begins at the first populated cell at
  ; or below the start row; a column with nothing there at all
  ; does not play
  ld a, (song_cur)
  ld e, a
  call col_next_pop
  cp $FF
  jr z, eps_off
  ld (ix+7), a
  jr ep_active
eps_off:
  ld (ix+6), 0
  jr ep_next
ep_active:
  ld (ix+6), 1
ep_next:
  ld de, 32
  add ix, de
  inc c
  ld a, c
  cp 4
  jp c, ep_chl

  ; echo ring starts silent (atten $0F) so it doesn't echo stale
  ; data before T1 has filled it
  xor a
  ld (echo_head), a
  ld hl, echo_ring + 2
  ld b, 64
ep_eclr:
  ld (hl), $0F
  inc hl
  inc hl
  inc hl
  djnz ep_eclr
  ; fresh repeat counts
  xor a
  ld (trk_rep), a
  ld (trk_rep+1), a
  ld (trk_rep+2), a
  ld (trk_rep+3), a
  ; per-phrase play counts: $FF so the first play of each reads 0
  ld hl, phrase_plays
  ld b, NUM_PHRASES
  ld a, $FF
ep_pclr:
  ld (hl), a
  inc hl
  djnz ep_pclr
  ; live queue starts empty
  ld a, $FF
  ld (live_q), a
  ld (live_q+1), a
  ld (live_q+2), a
  ld (live_q+3), a
  ; sync transport
  xor a
  ld (sync_cnt), a
  ld (sync_acc), a
  call sync_is_slave         ; IN or IN24: arm the slave (waits for the clock)
  jr nz, ep_nosl
  ; row-clock head-start = divisor-1 so the FIRST clock plays row 0 with no
  ; startup race: IN (/1) -> 0, IN24 (/6) -> 5.
  ld a, (sync_mode)
  cp SYNC_IN24
  jr nz, ep_slatch
  ld a, 5
  ld (sync_acc), a
ep_slatch:
  call sync_read             ; latch the line state at arm time:
  ld a, b                    ; stale levels must not count as a
  ld (sync_last), a          ; clock
  ld a, 1
  ld (sync_wait), a
  ld (state_dirty), a        ; show WAIT
ep_nosl:
  ld a, 1
  ld (play_state), a
  ret

engine_stop:
  xor a
  ld (play_state), a
  ld (sync_wait), a
  ld a, $FF                  ; release the port-2 sync lines
  out ($3F), a
  ; drop pending live queues (and their markers)
  ld hl, live_q
  ld b, 4
es_lq:
  ld a, (hl)
  cp $FF
  jr z, es_lqn
  call mark_vis_a            ; preserves HL/BC
  ld (hl), $FF
es_lqn:
  inc hl
  djnz es_lq
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
; called once per frame: always runs exactly one engine tick. The ROW advance
; inside engine_tick is groove-driven (master/off) or clock-driven (slave): a
; slave accumulates the master's received clocks here and advances a row per
; /1 (IN) or /6 (IN24) below.
engine_frame:
  ld a, (play_state)
  or a
  ret z
  call sync_is_slave         ; IN or IN24?
  jr nz, ef_tick
  call sync_in_delta         ; A = clocks received this frame (0-3)
  ld hl, sync_acc
  add a, (hl)
  ld (hl), a                 ; pile them toward the next row
ef_tick:
  call engine_tick
  ld a, (sync_mode)          ; PULSE drives once per frame (2 PPQN)
  cp SYNC_PULSE
  call z, sync_pulse_out
ef_mute:
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

; -------------------------------------------------------------
; first populated song cell in column C at/after row E -> A
; (row), or $FF when the rest of the column is empty
col_next_pop:
  ld a, (eng_len)
  ld d, a
cnp_l:
  ld a, e
  cp d
  jr nc, cnp_none
  push de
  ld l, e
  ld h, 0
  add hl, hl
  add hl, hl                 ; row * 4
  ld e, c
  ld d, 0
  add hl, de
  ld de, song
  add hl, de
  pop de
  ld a, (hl)
  cp $FF
  jr nz, cnp_hit
  inc e
  jr cnp_l
cnp_hit:
  ld a, e
  ret
cnp_none:
  ld a, $FF
  ret

.ENDS

; sync I/O is cold per-frame code; park it in bank 1 (always mapped) so the
; engine_tick row rework fits the tighter GG bank 0. Cross-bank calls are free.
.BANK 1 SLOT 1
.SECTION "Sync" FREE

; -------------------------------------------------------------
; sync I/O on controller port 2. Port $3F: low nibble = pin
; directions (0 = output), high nibble = levels; $FF = released.
; Levels only drive on export consoles - sync needs one.

; read the master's counter: B = TH<<1 | TR. Counter bit 0 is
; TR AND TL: a Gear-to-Gear cable crosses the far side's TR onto
; our TL (its serial TX/RX swap), while straight cables (3-wire
; DE-9, Master Link chains) leave TL floating high - the AND
; passes whichever line carries the signal, so every cable type
; works with no setting. Clobbers C.
sync_read:
  in a, ($DD)                ; bit 3 = TR, bit 2 = TL, bit 7 = TH
  ld c, a
  ld b, 0
  and $0C                    ; TR AND TL
  cp $0C
  jr nz, sr_th
  ld b, 1
sr_th:
  bit 7, c
  ret z
  set 1, b
  ret

; OUT: bump the 2-bit counter onto TR+TH. Called once per ROW advance (not per
; frame), so the clock follows the master's tempo and a /1 slave stays locked.
sync_out:
  ld a, (sync_cnt)
  inc a
  and $03
  ld (sync_cnt), a
  rrca
  rrca                       ; counter bits 0-1 -> levels 6-7
  or $33                     ; P2 TR+TH outputs, P1 untouched
  out ($3F), a
  ret

; PULSE: raise TR for one tick every PULSE_DIV ticks (2 PPQN). Called per frame.
sync_pulse_out:
  ld a, (sync_cnt)
  or a
  ld a, $FB                  ; tick 0: TR high (pulse edge)
  jr z, syp_w
  ld a, $BB                  ; TR low
syp_w:
  out ($3F), a
  ld a, (sync_cnt)
  inc a
  cp PULSE_DIV
  jr c, syp_st
  xor a
syp_st:
  ld (sync_cnt), a
  ret

; IN/IN24 slave: A = clocks received this frame (0-3). Reads the counter delta,
; and while armed (sync_wait) holds at 0 until the first clock, which counts as
; exactly one and flips WAIT -> PLAY. Clobbers BC.
sync_in_delta:
  call sync_read             ; B = 2-bit counter
  ld a, (sync_last)
  ld c, a
  ld a, b
  ld (sync_last), a
  sub c
  and $03
  ld b, a                    ; B = clocks since last frame
  ld a, (sync_wait)
  or a
  jr z, sid_have             ; running: return B
  ld a, b
  or a
  jr z, sid_zero             ; armed, no clock yet
  xor a                      ; first clock = transport start
  ld (sync_wait), a
  inc a
  ld (state_dirty), a        ; WAIT -> PLAY
  ret                        ; A = 1 (don't over-count the idle->counter jump)
sid_have:
  ld a, b
  ret
sid_zero:
  xor a
  ret

; Z if sync_mode is a slave (IN or IN24). Clobbers A.
sync_is_slave:
  ld a, (sync_mode)
  cp SYNC_IN
  ret z
  cp SYNC_IN24
  ret

.ENDS

.BANK 0 SLOT 0
.SECTION "Engine1b" FREE

engine_tick:
  call sync_is_slave         ; IN/IN24: the external clock drives row advance
  jr z, et_slave
  ; --- master / off / pulse: groove-driven row advance ---
  ld hl, groove_cnt
  dec (hl)
  jr nz, et_fx

  ; reload groove counter from the selected groove
  call groove_base
  ld a, (groove_pos)
  ld e, a
  ld d, 0
  add hl, de
  ld a, (hl)
  or a
  jr nz, et_gok
  ld a, 6                    ; safety for empty groove
et_gok:
  ld (groove_cnt), a
  ; advance groove pos (wrap at 16 or on 0-terminator)
  call groove_base
  ld a, (groove_pos)
  inc a
  cp 16
  jr nc, et_gwrap
  ld e, a
  ld d, 0
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

  ; advance + process every track at its own row (per-channel hop)
  call step_channels
  ld a, (sync_mode)          ; OUT: emit exactly one clock per row, so a /1
  cp SYNC_OUT                ;   slave steps with us and never runs ahead
  call z, sync_out
  jr et_fx
et_slave:
  ; clock-driven: advance one row per /1 (IN) or /6 (IN24) received clocks
  ld c, 1
  ld a, (sync_mode)
  cp SYNC_IN24
  jr nz, et_sdiv
  ld c, 6
et_sdiv:
  ld a, (sync_acc)
  cp c
  jr c, et_fx                ; not enough clocks yet: hold the row
  sub c                      ; lossless: a multi-clock frame keeps the excess
  ld (sync_acc), a
  call step_channels
et_fx:
  call channels_fx
  jp echo_pass

.ENDS

; echo lives in bank 1 (slot 1, always mapped): bank 0 is full.
.BANK 1 SLOT 1
.SECTION "Echo" FREE

; ===========================================================
; echo post-pass (once per tick, after channels_fx): record T1's
; output in a ring, and replay it delayed + attenuated onto T2
; (tap1) and T3 (tap2) when those channels are otherwise silent.
; A delay-line echo - it follows T1's pitch and volume exactly.
; ===========================================================
echo_pass:
  ; ring[head] = T1 (period lo, hi, attenuation)
  ld a, (echo_head)
  call echo_slot             ; HL = &ring[head]
  ld a, (psg_tone0)
  ld (hl), a
  inc hl
  ld a, (psg_tone0+1)
  ld (hl), a
  inc hl
  ld a, (psg_vols)
  ld (hl), a
  inc hl
  ld a, (chst+0)             ; T1's base note index ($FF = none)
  ld (hl), a
  ld a, (echo_mode)
  or a
  jp z, echo_adv             ; off: just keep the ring warm
  ; stereo: recenter T2+T3 each tick - the driven taps re-pan
  ; themselves below, and any channel the song reclaims (or that
  ; isn't echoing this tick) is left centred, not stuck off-side.
  ld a, (echo_stereo)
  or a
  jr z, echo_t1ok
  ld a, (psg_pan)
  or  %01100110
  ld (psg_pan), a
echo_t1ok:
  ; --- TAP1 -> T2, only if the song left T2 silent ---
  ld a, (psg_vols+1)
  cp $0F
  jr nz, echo_t3
  ld a, (echo_tap1)
  call echo_taprows          ; rows -> ticks at the current groove
  ld c, a
  ld a, (echo_head)
  sub c
  call echo_slot             ; HL = &ring[head - tap1]
  ld a, (echo_tsp1)
  call echo_fetch            ; DE = period (transposed), C = atten
  ld a, e
  ld (psg_tone1), a
  ld a, d
  ld (psg_tone1+1), a
  ld a, (echo_red1)
  add a, c
  cp $10
  jr c, echo_t2v
  ld a, $0F
echo_t2v:
  ld (psg_vols+1), a
  ld a, (echo_stereo)
  or a
  jr z, echo_t3
  ld a, (psg_pan)            ; T2 = left only (ch1: L bit5, R bit1)
  and %11011101
  or  %00100000
  ld (psg_pan), a
echo_t3:
  ld a, (echo_mode)
  cp 2
  jr nz, echo_adv
  ld a, (smp_active)         ; T3 owned by a sample/wave: skip
  or a
  jr nz, echo_adv
  ld a, (psg_vols+2)
  cp $0F
  jr nz, echo_adv
  ld a, (echo_tap2)
  call echo_taprows          ; rows -> ticks at the current groove
  ld c, a
  ld a, (echo_head)
  sub c
  call echo_slot
  ld a, (echo_tsp2)
  call echo_fetch            ; DE = period (transposed), C = atten
  ld a, e
  ld (psg_tone2), a
  ld a, d
  ld (psg_tone2+1), a
  ld a, (echo_red2)
  add a, c
  cp $10
  jr c, echo_t3v
  ld a, $0F
echo_t3v:
  ld (psg_vols+2), a
  ld a, (echo_stereo)
  or a
  jr z, echo_adv
  ld a, (psg_pan)            ; T3 = right only (ch2: L bit6, R bit2)
  and %10111011
  or  %00000100
  ld (psg_pan), a
echo_adv:
  ld a, (echo_head)
  inc a
  and $3F
  ld (echo_head), a
  ret

; A = ring index (mod 64) -> HL = &echo_ring[index*4]
echo_slot:
  and $3F
  ld l, a
  ld h, 0
  add hl, hl                 ; *2
  add hl, hl                 ; *4
  ld de, echo_ring
  add hl, de
  ret

; HL = ring slot, A = transpose (signed semitones)
; -> DE = period to play, C = source attenuation.
; tsp 0 (or no note) replays the recorded period verbatim (keeps
; vibrato/bends); otherwise the base note is shifted and looked up
; fresh in the note table - no multiply, just the existing table.
echo_fetch:
  ld b, a                    ; B = transpose
  ld e, (hl)                 ; recorded period lo
  inc hl
  ld d, (hl)                 ; recorded period hi
  inc hl
  ld c, (hl)                 ; source attenuation
  inc hl
  ld a, (hl)                 ; recorded note
  cp $FF
  ret z                      ; no note: keep recorded period
  ld l, a
  ld a, b
  or a
  ret z                      ; no transpose: keep recorded period
  add a, l                   ; note + semitones, clamp to table
  jp p, ef_hi
  xor a
ef_hi:
  cp NOTE_COUNT
  jr c, ef_ok
  ld a, NOTE_COUNT-1
ef_ok:
  add a, a
  ld e, a
  ld d, 0
  ld hl, (note_ptr)
  add hl, de
  ld e, (hl)
  inc hl
  ld d, (hl)                 ; DE = transposed period
  ret

; A = tap in rows -> A = ring offset in ticks (1..63), scaled by the
; active groove's row length. This is what ties the echo to the
; musical grid: a 2-row tap is an 8th note at any tempo or swing.
echo_taprows:
  or a
  ret z
  ld b, a                    ; B = rows
  push hl
  call groove_base           ; HL = active groove
  ld c, (hl)                 ; ticks per row (downbeat of the groove)
  ld a, c
  or a
  jr nz, etr_have
  ld c, 6                    ; never divide-by-feel on a 0 groove
etr_have:
  xor a
etr_loop:
  add a, c
  cp 64
  jr c, etr_next
  ld a, 63                   ; clamp to the ring depth
  jr etr_done
etr_next:
  djnz etr_loop
etr_done:
  pop hl
  ret

; recenter T2+T3 (full L+R) - used when echo or its stereo mode is
; switched off, so the taps don't leave the channels stuck off-side
echo_pan_reset:
  ld a, (psg_pan)
  or %01100110
  ld (psg_pan), a
  ret

; echo defaults: off, but taps/reductions preset so turning it on
; sounds musical right away (eighth + quarter, fading)
echo_defaults:
  xor a
  ld (echo_mode), a
  ld (echo_stereo), a
  ld (echo_tsp1), a
  ld (echo_tsp2), a
  ld a, 2
  ld (echo_tap1), a
  ld a, 4
  ld (echo_tap2), a
  ld a, 4
  ld (echo_red1), a
  ld a, 8
  ld (echo_red2), a
  ld a, $FF
  ld (wav_ovr), a
  ret

; clamp loaded echo settings into valid ranges
echo_sanitize:
  ld a, (echo_mode)
  cp 3
  jr c, esan_m
  xor a
  ld (echo_mode), a
esan_m:
  ld hl, echo_tap1
  call esan_tap
  ld hl, echo_tap2
  call esan_tap
  ld a, (echo_red1)
  and $0F
  ld (echo_red1), a
  ld a, (echo_red2)
  and $0F
  ld (echo_red2), a
  ld a, (echo_stereo)
  and 1
  ld (echo_stereo), a
  ret
esan_tap:
  ld a, (hl)
  or a
  jr nz, esan_hi
  ld (hl), 1
  ret
esan_hi:
  cp 16
  ret c
  ld (hl), 15
  ret

.ENDS

.BANK 0 SLOT 0
.SECTION "Engine2" FREE

; HL = start of the selected groove
groove_base:
  ld a, (groove_sel)
  add a, a
  add a, a
  add a, a
  add a, a
  ld e, a
  ld d, 0
  ld hl, grooves
  add hl, de
  ret

; -------------------------------------------------------------
; phrase boundary: move every active track to its next phrase
; once per row-tick: for each active channel, advance its own row (and its
; chain/phrase position at its own boundary, or early on a pending hop), then
; process that channel's row. The groove clock stays global; only the row
; position is per-channel, so H ends only the track it's written on.
step_channels:
  ld ix, chst
  ld c, 0
sc_loop:
  ld a, c
  ld (cur_trig_ch), a
  ; advance this channel's row EVERY tick (active or not) so all tracks track
  ; the beat: a silent track re-armed in LIVE then still starts bar-aligned.
  ld d, 0
  ld e, c
  ld hl, chan_row
  add hl, de
  ld a, (hl)
  inc a
  and $0F
  ld (hl), a
  jr z, sc_bound             ; row wrapped -> phrase boundary
  ld a, (ix+6)               ; mid-phrase: process only if active
  or a
  jp z, sc_next
  jr sc_setrow
sc_bound:
  ld a, (ix+6)               ; boundary: only active tracks load + process
  or a
  jp z, sc_next
  call advance_track         ; walk this track's chain/song (or take a queue)
sc_setrow:
  xor a
  ld (hop_guard), a          ; fresh per-row hop budget
sc_reproc:
  ld d, 0                    ; cur_row = this channel's row (advance_track
  ld e, c                    ;   clobbers DE, so recompute the index)
  ld hl, chan_row
  add hl, de
  ld a, (hl)
  ld (cur_row), a
  call process_chan
  ; immediate H: a hop on this row jumps to row 0 and re-processes NOW, so the
  ; H row spends no tick of its own. Guarded so an all-H phrase can't spin.
  ld a, (hop_now)
  or a
  jr z, sc_next
  xor a
  ld (hop_now), a
  ld a, (hop_guard)
  inc a
  ld (hop_guard), a
  cp 16
  jr nc, sc_next             ; pathological hop chain: bail this tick
  ld a, (ix+6)               ; advance_track may have silenced the track
  or a
  jr z, sc_next
  ld d, 0
  ld e, c
  ld hl, chan_row
  add hl, de
  ld (hl), 0                 ; hop target = row 0
  call advance_track         ; loop the phrase / step the chain, as a boundary
  jr sc_reproc
sc_next:
  ld de, 32
  add ix, de
  inc c
  ld a, c
  cp 4
  jp c, sc_loop
  ret

advance_track:
  ld a, (eng_mode)
  cp MODE_PHRASE
  jp z, rep_bump             ; phrase loops in place: count it
  cp MODE_CHAIN
  jr nz, at_song

  ; ---- chain loop mode ----
  ld a, (ix+8)
  inc a                      ; $FF -> 0 on first boundary
  cp 16
  jr c, at_cread
  call rep_bump              ; the chain wrapped: a repeat
  xor a
at_cread:
  ld (ix+8), a
  call chain_entry           ; uses (ix+11), (ix+8) -> HL
  ld a, (hl)
  cp $FF
  jr nz, at_cset
  call rep_bump              ; the chain wrapped: a repeat
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
  ld a, (play_mode)          ; LIVE: a queued chain lands at the next phrase
  or a                       ;   boundary (next bar), not at chain-end
  jr z, ats_norm
  ld hl, live_q
  ld e, c
  ld d, 0
  add hl, de
  ld a, (hl)
  cp $FF
  jr z, ats_norm             ; nothing queued: normal advance / chain loop
  ld (ix+7), a               ; take the queued song row now
  ld (hl), $FF
  call mark_vis_a            ; clear its queued marker (A = the row)
  jp at_load
ats_norm:
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
  ld a, (play_mode)
  or a
  jr z, at_adv
  ; ---- LIVE: take the queued row, else loop this chain ----
  ld hl, live_q
  ld e, c
  ld d, 0
  add hl, de
  ld a, (hl)
  cp $FF
  jr z, at_load              ; nothing queued: reload = loop
  ld (ix+7), a
  ld (hl), $FF
  call mark_vis_a            ; marker off (A = the queued row)
  jr at_load
at_adv:
  ld a, (eng_len)
  ld d, a
  ld a, (ix+7)
  inc a
  cp d
  jr c, at_setrow            ; still inside the song
  xor a                      ; past the last row: wrap to the top
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
  jr z, at_wrap              ; empty cell: column loops
  cp (ix+11)                 ; same chain again = one more repeat
  jr z, atl_rep
  push hl
  ld hl, trk_rep
  ld e, c
  ld d, 0
  add hl, de
  ld (hl), 0                 ; different chain: fresh count
  pop hl
  jr atl_st
atl_rep:
  call rep_bump
atl_st:
  ld (ix+11), a
  ld (ix+8), 0
  call chain_entry
  ld a, (hl)
  cp $FF
  jr z, at_silent            ; empty chain: a rest row
  ld (ix+10), a
  inc hl
  ld a, (hl)
  ld (ix+9), a
  ret
at_wrap:
  ; empty cell ends the column. SONG: loop back to the column's
  ; top (its first populated cell). LIVE: a queued stop.
  ld a, (play_mode)
  or a
  jr nz, at_off
  ld e, 0
  call col_next_pop
  cp $FF
  jr z, at_off               ; the column emptied under us
  ld (ix+7), a
  jp at_load
at_silent:
  ; populated cell, empty chain: one deliberate rest row
  ld (ix+10), $FF
  ld (ix+8), 15              ; next boundary advances the row
  ret
at_off:
  ld (ix+6), 0
  ld (ix+10), $FF
  ret

; -------------------------------------------------------------
; LIVE performance actions (transport gesture on the SONG screen
; while playing). Main thread.

; queue song row A on track C: a playing track swaps when its
; current chain ends; a silent track starts at the next phrase
; boundary
live_queue:
  ld hl, live_q
  ld e, c
  ld d, 0
  add hl, de
  ld b, a                    ; B = row to queue
  ld a, c
  add a, a
  add a, a
  add a, a
  add a, a
  add a, a                   ; * 32
  ld e, a
  ld ix, chst
  add ix, de
  ld a, (ix+6)
  or a
  jr z, lq_arm
  ld a, (ix+7)               ; starting the chain that is already
  cp b                       ; playing = stop the track
  jr nz, lq_q
  ld a, c
  jp live_track_stop
lq_q:
  ld a, (hl)
  cp $FF
  jr z, lq_on
  call mark_vis_a            ; re-queue: clear the old marker
lq_on:
  ld a, b
  ld (hl), a
  jp mark_vis_a              ; marker on
lq_arm:
  ld (ix+7), b               ; silent track: load this row at
  ld (ix+8), $FF             ; the next phrase boundary
  ld (ix+10), $FF
  ld (ix+6), 1
  ret

; stop track A immediately (header gesture)
live_track_stop:
  ld c, a
  ld hl, live_q
  ld e, a
  ld d, 0
  add hl, de
  ld a, (hl)                 ; clear a pending queue + marker
  cp $FF
  jr z, lts_ch
  call mark_vis_a
  ld (hl), $FF
lts_ch:
  ld a, c
  add a, a
  add a, a
  add a, a
  add a, a
  add a, a
  ld e, a
  ld ix, chst
  add ix, de
  ld (ix+6), 0
  ld (ix+10), $FF
  ld (ix+2), 0               ; volume 0: the wave gate sees it
  ld hl, psg_vols
  ld e, c
  ld d, 0
  add hl, de
  ld (hl), $0F               ; silence the channel now
  ret

; one more repeat of the current chain/phrase on track C
; (preserves A/HL/DE)
rep_bump:
  push hl
  push de
  ld hl, trk_rep
  ld e, c
  ld d, 0
  add hl, de
  inc (hl)
  pop de
  pop hl
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
; process one channel's current row (ix = channel, cur_row + cur_trig_ch set
; by step_channels). Preserves C/IX for the caller's loop.
process_chan:
  ld a, (ix+6)               ; advance_track may have silenced an empty chain
  or a
  jp z, pr_next
  ld a, (ix+10)
  cp $FF
  jp z, pr_next
  ; per-phrase play counter: +1 on row 0 (phrase start), so the I
  ; command can vary a phrase across its plays without cloning it
  ld e, a                    ; E = phrase #
  ld a, (cur_row)
  or a
  jr nz, pr_ppdone
  push hl
  ld d, 0
  ld hl, phrase_plays
  add hl, de
  inc (hl)
  pop hl
pr_ppdone:
  ld a, e                    ; A = phrase # again

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
  jp z, pr_cmd
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
  ld b, a                    ; B = note index
  ; peek the command: D delays the trigger, L slides into it
  push hl
  inc hl
  inc hl
  ld a, (hl)
  inc hl
  ld d, (hl)
  pop hl
  cp CMD_DELAY
  jr z, prn_delay
  cp CMD_SLIDE
  jr z, prn_slide
  cp CMD_ITER
  jp z, prn_iter
  cp CMD_WSET
  jp z, prn_wset
  cp CMD_FMPROG
  jp z, prn_fmprog
  cp CMD_TBL
  jp z, prn_tbl
  cp CMD_PROB
  jp z, prn_prob
  cp CMD_JTRANS
  jp z, prn_jump
prn_norm:
  ld (ix+0), b
  push hl
  push bc
  call trigger_note
  pop bc
  pop hl
  jp pr_cmd
prn_wset:                    ; set this note's wavetable, then trigger
  ld a, d
  and $07
  ld (wav_ovr), a
  jr prn_norm
prn_fmprog:                  ; set this note's FM program, then trigger
  ld a, d
  ld (fm_ovr), a
  jr prn_norm
prn_tbl:                     ; A cmd: latch a one-shot table override for this
  ld a, d                    ; note (>=NUM_TABLES = off), consumed by the trigger
  ld (tbl_ovr), a
  jr prn_norm
prn_delay:
  ld a, d
  or a
  jr z, prn_norm
  ld (ix+29), b              ; trigger when the delay expires
  ld (ix+28), d
  jp pr_cmd
prn_slide:
  ld a, d
  or a
  jr z, prn_norm
  ld a, (ix+0)               ; need a previous note to slide from
  cp $FF
  jr z, prn_norm
  push hl
  push de
  add a, a                   ; old note's period
  ld e, a
  ld d, 0
  ld hl, (note_ptr)
  add hl, de
  ld e, (hl)
  inc hl
  ld d, (hl)
  push de
  ld (ix+0), b
  push bc
  call trigger_note
  pop bc
  ld a, b                    ; new note's period
  add a, a
  ld e, a
  ld d, 0
  ld hl, (note_ptr)
  add hl, de
  ld e, (hl)
  inc hl
  ld d, (hl)
  pop hl                     ; sweep acc = old - new: pitch
  or a                       ; starts at the old note and the
  sbc hl, de                 ; porta pulls the acc to zero
  ld (ix+13), l
  ld (ix+14), h
  pop de
  ld a, d
  ld (ix+30), a              ; porta speed
  pop hl
  jp pr_cmd
prn_iter:
  ; I xx: the param is an 8-bit play mask sampled by this phrase's
  ; play count (how many times the phrase has played this song). On
  ; play N, play the note only if bit (N mod 8) of the mask is set.
  ; I00 never, IFF always, I0F first four of eight, IF0 last four,
  ; I55/IAA odd/even plays. D = mask.
  push hl
  ld hl, phrase_plays
  ld a, (ix+10)              ; how many times this phrase has played
  add a, l
  ld l, a
  adc a, h
  sub l
  ld h, a
  ld a, (hl)
  pop hl
  and 7                      ; bit index = repeat mod 8
  inc a                      ; rotate (index + 1) times -> bit in carry
  ld e, a
  ld a, d                    ; the mask
prn_ibit:
  rrca
  dec e
  jr nz, prn_ibit
  jp nc, pr_cmd              ; bit clear: rest this repeat
  jp prn_norm
prn_prob:
  ; Z xx: D = chance the note triggers. FF always, 00 never, else a fresh roll
  ; plays when random < param. The note's command is a no-op (handled here).
  ld a, d
  cp $FF
  jp z, prn_norm             ; always
  or a
  jp z, pr_cmd               ; never -> rest this row
  push hl                    ; preserve the step pointer (rng clobbers HL)
  call rng                   ; A = random byte (preserves B = note, D = param)
  pop hl
  cp d                       ; carry if random < param
  jp c, prn_norm             ; play
  jp pr_cmd                  ; skip the note
prn_jump:
  ; J xy: x = signed semitone transpose (0..7 = +1..+7, 8..F = -8..-1),
  ; applied to this note only on plays whose (play mod 4) bit is set in the
  ; low nibble y. A sibling to I: same per-phrase play count, but it varies
  ; pitch instead of gating the note. y=0 never transposes, y=F always.
  push hl
  ld hl, phrase_plays
  ld a, (ix+10)              ; how many times this phrase has played
  add a, l
  ld l, a
  adc a, h
  sub l
  ld h, a
  ld a, (hl)                 ; play count N
  pop hl
  and 3                      ; bit index = N mod 4
  inc a                      ; rotate (index + 1) times -> bit in carry
  ld e, a
  ld a, d                    ; the 4-bit mask (low nibble; high nibble ignored)
prn_jbit:
  rrca
  dec e
  jr nz, prn_jbit
  jp nc, prn_norm            ; bit clear: play untransposed
  ld a, d                    ; high nibble = signed transpose
  rrca
  rrca
  rrca
  rrca
  and $0F
  cp 8
  jr c, prn_jadd
  sub 16                     ; 8..15 -> -8..-1
prn_jadd:
  add a, b                   ; note + transpose
  jp m, prn_jlo              ; wrapped below 0 (NOTE_COUNT < 128, so +overflow
  cp NOTE_COUNT              ;   never sets sign): clamp to floor
  jr c, prn_jok
  ld a, NOTE_COUNT-1
  jr prn_jok
prn_jlo:
  xor a
prn_jok:
  ld b, a
  jp prn_norm
pr_cmd:
  inc hl
  inc hl
  ld a, (hl)                 ; command
  or a
  jr z, pr_next
  inc hl
  ld d, (hl)                 ; param
  ; global commands first
  cp CMD_GRV
  jr z, prc_grv
  cp CMD_HOP
  jr z, prc_hop
  cp CMD_TPO
  jr z, prc_tpo
  cp CMD_WAIT
  jr z, prc_wait
  cp CMD_WSET
  jr z, pr_next              ; applied in the trigger peek above
  cp CMD_FMPROG
  jr z, pr_next              ; applied in the trigger peek above
  cp CMD_TBL
  jr z, pr_next              ; A is a one-shot, resolved in the trigger peek
  cp CMD_PROB
  jr z, pr_next              ; Z (probability) is resolved in the trigger peek
  cp CMD_JTRANS
  jr z, pr_next              ; J (transpose mask) is resolved in the trigger peek
  call exec_command          ; channel-scope
  jp pr_next
prc_grv:
  ld a, d
  and $0F
  ld (groove_sel), a
  xor a
  ld (groove_pos), a
  jp pr_next
prc_hop:
  ld a, 1                    ; H ends this track's phrase NOW, same tick: the
  ld (hop_now), a            ; H row costs no time (step_channels re-processes
  jp pr_next                 ; row 0 immediately). Per-channel: only cur_trig_ch.
prc_wait:
  call sync_is_slave         ; W shortens a row via groove_cnt; a slave's rows
  jp z, pr_next              ; are clock-driven, so it has no effect -- skip it
  ld a, d
  or a
  jr nz, prc_wst
  inc a
prc_wst:
  ld (groove_cnt), a
  jp pr_next
prc_tpo:
  call set_tempo
pr_next:
  ret

; -------------------------------------------------------------
; channel-scope commands: A = command, D = param, IX = channel.
; Shared by phrase rows and table rows.
exec_command:
  cp CMD_KILL
  jp z, xc_kill
  cp CMD_TBL
  jp z, xc_tbl
  cp CMD_ARP
  jp z, xc_arp
  cp CMD_ENV
  jp z, xc_env
  cp CMD_FINE
  jp z, xc_fine
  cp CMD_NOI
  jp z, xc_noi
  cp CMD_PB
  jp z, xc_pb
  cp CMD_VIB
  jp z, xc_vib
  cp CMD_TREM
  jp z, xc_trem
  cp CMD_RETRIG
  jp z, xc_retrig
  cp CMD_PAN
  jp z, xc_pan
  cp CMD_SPEED
  jp z, xc_speed
  cp CMD_VOL
  jp z, xc_vol
  ret
xc_vol:                      ; X xx: set this note's volume (0-F). PSG: the
  ld a, d                    ; AHD peak the attack ramps to. FM: live volume.
  cp 16
  jr c, xv_ok
  ld a, 15
xv_ok:
  ld e, a                    ; e = volume 0-15
  rlca
  rlca
  rlca
  rlca
  and $F0
  ld d, a
  ld a, (ix+4)
  and $0F                    ; keep the stage; set the peak (high nibble)
  or d
  ld (ix+4), a
  call chan_is_fm            ; FM voice? push it to the FM volume reg
  jr z, xv_fm
  call chan_is_fmdrum        ; FM drum? re-level the hit (no re-key)
  ret nz
  ld a, e                    ; a = volume (e holds it from xv_ok)
  push af
  call tn_fd_drum            ; e = drum index from the note in ix+0
  pop af
  jp fm_drum_vol
xv_fm:
  ld a, (cur_trig_ch)
  ld d, a
  ld a, e                    ; a = volume
  ld e, d                    ; e = channel
  jp fm_set_vol
; Z if the IX channel's current instrument is FM (type 4). Preserves regs.
chan_is_fm:
  push hl
  push de
  ld a, (ix+1)
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  ld de, instruments
  add hl, de
  ld a, (hl)
  pop de
  pop hl
  cp 4
  ret
; Z if the IX channel's current instrument is FMDRUM (type 5). Preserves regs.
chan_is_fmdrum:
  push hl
  push de
  ld a, (ix+1)
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  ld de, instruments
  add hl, de
  ld a, (hl)
  pop de
  pop hl
  cp 5
  ret
xc_speed:                    ; S xx: sample playback speed (0-3)
  ld a, d
  cp 4
  ret nc
  ld (smp_speed), a
  xor a
  ld (smp_hold), a
  ret
xc_trem:
  ld a, d
  ld (ix+19), a
  ret
xc_retrig:
  ld a, d
  and $0F
  ret z
  ld d, a                    ; pack counter|interval
  rlca
  rlca
  rlca
  rlca
  or d
  ld (ix+31), a
  ret
xc_pan:
  ; O xy on channel C: x = left enable, y = right enable. The GG
  ; stereo byte is right enables in bits 0-3, left in bits 4-7.
  push bc
  ld a, c
  ld b, a
  ld a, 1
  inc b
xcp_sh:
  dec b
  jr z, xcp_have
  add a, a
  jr xcp_sh
xcp_have:
  ld e, a                    ; E = right bit for this channel
  add a, a
  add a, a
  add a, a
  add a, a
  or e                       ; both bits
  cpl
  ld b, a
  ld a, (psg_pan)
  and b                      ; clear this channel's bits
  ld b, a
  ld a, d
  and $F0
  jr z, xcp_right
  ld a, e
  add a, a
  add a, a
  add a, a
  add a, a
  or b                       ; left on
  ld b, a
xcp_right:
  ld a, d
  and $0F
  jr z, xcp_store
  ld a, e
  or b                       ; right on
  ld b, a
xcp_store:
  ld a, b
  ld (psg_pan), a
  pop bc
  ret

xc_kill:
  ld a, d
  or a
  jr nz, xc_klater
  ld (ix+2), 0               ; K00: cut now
  ld (ix+4), STG_IDLE        ; envelope done
  ld (ix+12), 0              ; FM voice off (stops fm_pitch_mod re-keying it)
  ld a, (cur_trig_ch)
  call smp_kill_owned        ; K00 also cuts the sample
  ld a, (cur_trig_ch)        ; ...and keys off the FM channel (harmless
  add a, $20                 ;   if this track isn't an FM voice)
  ld c, a
  ld b, 0
  jp fm_w
xc_klater:
  ld (ix+3), a               ; Kxx: count down xx ticks...
  ld (ix+4), STG_KILL        ; ...then hard cut (overrides the AHD)
  ret

; A = channel; if it owns the playing sample, stop it (smp_abort
; no-ops unless a PCM sample is active). Preserves BC/DE/HL.
smp_kill_owned:
  push hl
  ld hl, smp_owner
  cp (hl)
  pop hl
  ret nz
  jp smp_abort
xc_tbl:
  ld a, d
  cp NUM_TABLES
  jr nc, xc_toff
  ld (ix+20), a
  ld (ix+21), 0
  ld (ix+22), 1
  ret
xc_toff:
  ld (ix+20), $FF
  ld (ix+24), 0
  ret
xc_arp:
  ld a, d
  ld (ix+25), a
  ld (ix+26), 0
  ret
xc_env:
  ld (ix+5), d               ; E xy: set ATK=x, DCY=y live; the
  ret                        ; cached rate byte IS the E param,
                             ; HLD and the current stage untouched
xc_fine:
  ld a, d
  ld (ix+27), a
  ret
xc_noi:
  ld a, d
  and $07
  ld (psg_noisectl), a
  and $03
  cp $03
  ld (ix+12), 0
  ret nz
  ld (ix+12), 1
  ret
xc_pb:
  ld a, d
  ld (ix+17), a
  ret
xc_vib:
  ld a, d
  ld (ix+18), a
  ret

.ENDS

; set_tempo is cold (T command / PROJECT): park it in bank 1.
.BANK 1 SLOT 1
.SECTION "SetTempo" FREE

; D = BPM: write an even groove into the selected groove
set_tempo:
  ld a, d
  or a
  ret z
  push bc
  ld a, (region_pal)
  or a
  ld hl, 900                 ; NTSC: ticks = 900/BPM
  jr z, st_div
  ld hl, 750                 ; PAL: 750/BPM
st_div:
  ld e, d
  ld d, 0
  ld b, 0
  or a
st_loop:
  sbc hl, de
  jr c, st_done
  inc b
  jr st_loop
st_done:
  ld a, b
  or a
  jr nz, st_min
  inc a
st_min:
  cp 16
  jr c, st_ok
  ld a, 15
st_ok:
  ld b, a                    ; groove_base clobbers A
  call groove_base
  ld (hl), b
  inc hl
  ld (hl), b
  inc hl
  ld (hl), 0
  pop bc
  ret

; tbl_skip_hops: advance ix+21 (the table's next row) past any H rows, so an H
; costs no table step *and* the pointer rests on the real loop target (which
; then plays on its own step). Detected at advance time -- the H row is never
; applied. Guarded against an all-H / self-referential spin. Clobbers A/HL/DE,
; preserves BC/IX. (Bank 1, always mapped -- callable from the bank-0 hot path.)
tbl_skip_hops:
  xor a
  ld (hop_guard), a
tsh_loop:
  ld a, (ix+20)
  cp NUM_TABLES
  ret nc                     ; no table running
  ld l, a                    ; HL = tables + tbl*64 + row*4 + 2 (command column)
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  ld a, (ix+21)
  add a, a
  add a, a
  ld e, a
  ld d, 0
  add hl, de
  ld de, tables
  add hl, de
  inc hl
  inc hl
  ld a, (hl)                 ; command column
  cp CMD_HOP
  ret nz                     ; real row: stop here, it gets applied next step
  inc hl
  ld a, (hl)                 ; param low nibble = loop target row
  and $0F
  ld (ix+21), a
  ld a, (hop_guard)
  inc a
  ld (hop_guard), a
  cp 16
  ret nc                     ; pathological hop chain: bail
  jr tsh_loop

; fm_pitch_mod: per-tick FM pitch modulation (F/P/V on FM). *** CURRENTLY
; DISABLED *** -- the cf_out hook that calls it is commented out. It never
; produced an audible wobble despite the write path, the V param, and the phase
; counter all being verified working in isolation. Left intact as a starting
; point; see FM_VIBRATO_NOTES.md for the full investigation before re-enabling.
;
; FM doesn't use the PSG period, so the bend is recomputed here in F-number space
; and written to the YM2413 each tick. ix+13/14 (the PSG sweep acc, unused on FM)
; holds the accumulated P bend. c = channel, ix = struct; ends at cf_vol (keeps
; c). fm_w clobbers only A, so DE/HL survive across the two register writes.
; Offset = finetune - (bendacc >> 4) - vibrato; + raises pitch (more fnum).
fm_pitch_mod:
  ; Modulate whenever a note has played (cf_out already filtered ix+0==$FF).
  ; The voice may have keyed off (hold expired / K) and be ringing out -- we
  ; still bend its pitch, but write key-on=0 in that case (ix+12) so the pitch
  ; updates without re-triggering the envelope.
  ld a, (ix+17)              ; accumulate the P sweep (signed/tick) into 13/14
  or a
  jr z, fmpm_gate
  ld e, a
  rlca
  sbc a, a
  ld d, a
  ld l, (ix+13)
  ld h, (ix+14)
  add hl, de
  ld (ix+13), l
  ld (ix+14), h
fmpm_gate:
  ld a, (ix+17)
  or (ix+27)
  jr nz, fmpm_go
  ld a, (ix+18)
  and $0F                    ; vibrato depth active?
  jr nz, fmpm_go
  ld a, (ix+13)
  or (ix+14)
  jp z, cf_vol               ; keyed on but nothing bending: leave the pitch
fmpm_go:
  ; build the signed fnum offset in HL = finetune - (acc>>4) - vibrato
  ld a, (ix+27)              ; HL = sign-extended finetune (+ = up)
  ld l, a
  rlca
  sbc a, a
  ld h, a
  ld e, (ix+13)              ; DE = acc >> 4 (signed)
  ld d, (ix+14)
  ld b, 4
fmpm_sra:
  sra d
  rr e
  djnz fmpm_sra
  or a
  sbc hl, de                 ; HL = finetune - acc>>4   (+P = down)
  call fm_vib_delta          ; A = signed vib_tables value (0 if depth 0)
  ld e, a
  rlca
  sbc a, a
  ld d, a
  or a
  sbc hl, de                 ; HL -= vibrato  (period-domain delta -> fnum sign)
  ex de, hl                  ; DE = signed fnum offset
fmpm_lookup:
  ld a, (ix+24)              ; base note = clamp(note + table semitone offset)
  add a, (ix+0)
  jp p, fmpm_nn
  xor a
fmpm_nn:
  cp NOTE_COUNT
  jr c, fmpm_nok
  ld a, NOTE_COUNT-1
fmpm_nok:
  add a, a
  ld l, a
  ld h, 0
  push de
  ld de, (fm_note_ptr)
  add hl, de
  pop de
  ld a, (hl)                 ; fnum low
  inc hl
  ld b, (hl)                 ; block<<1 | fnum8
  ld l, a
  ld a, b
  and $01
  ld h, a                    ; HL = 9-bit base fnum
  ld a, b
  rrca
  and $07
  ld b, a                    ; B = block 0-7
  add hl, de                 ; fnum += offset
  bit 7, d                   ; offset negative?
  jr nz, fmpm_neg
fmpm_ovf:
  ld a, h
  cp 2                       ; fnum >= 512: carry into the next block
  jr c, fmpm_wr
  srl h
  rr l
  inc b
  ld a, b
  cp 8
  jr c, fmpm_ovf
  ld hl, 511                 ; block maxed: clamp
  ld b, 7
  jr fmpm_wr
fmpm_neg:
  bit 7, h                   ; underflowed below 0: floor the fnum
  jr z, fmpm_wr
  ld hl, 0
fmpm_wr:
  ld d, c                    ; D = channel (fm_w preserves DE)
  ld e, b                    ; E = block
  ld a, d
  add a, $10
  ld c, a
  ld b, l                    ; $10+ch = fnum low
  call fm_w
  ld a, e
  add a, a                   ; block << 1
  bit 0, h
  jr z, fmpm_nf8
  inc a                      ; | fnum8
fmpm_nf8:
  or $30                     ; | key-on | sustain (held: bend without re-keying)
  ld b, a
  ld a, d
  add a, $20
  ld c, a                    ; $20+ch = block | fnum8 | key-on
  call fm_w
  ld c, d                    ; restore c = channel for cf_vol
  jp cf_vol

; fm_vib_delta: A = signed vibrato delta from ix+18 (speed|depth) and ix+15
; (phase), advancing the phase -- the same vib_tables lookup the PSG path uses.
; Returns 0 when depth is 0. Preserves HL/IX; clobbers A/BC/DE.
fm_vib_delta:
  ld a, (ix+18)
  and $0F
  ret z                      ; depth 0: no vibrato
  push hl
  ld b, a                    ; depth
  ld a, (ix+18)
  and $F0
  rrca
  rrca                       ; speed * 4
  ld c, a
  ld a, (ix+15)
  add a, c
  ld (ix+15), a              ; advance phase
  rrca
  rrca
  rrca
  and $1F                    ; step 0-31
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
  pop hl
  ret

.ENDS

.BANK 0 SLOT 0
.SECTION "Engine3" FREE

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
  inc hl                     ; -> +1
  ld a, (hl)                 ; +1 init volume = AHD peak
  rlca
  rlca
  rlca
  rlca
  and $F0                    ; peak in the stage byte's high nibble; the
  ld (ix+4), a               ;   X command can override it (STG_ATK = 0)
  inc hl                     ; -> +2
  ld a, (hl)                 ; +2 ATK|DCY rates (the byte E writes)
  ld (ix+5), a
  xor a
  ld (ix+2), a               ; AHD starts silent in the attack stage
  inc a
  ld (ix+3), a               ; pace = 1: first ramp step next tick
  inc hl                     ; -> +3 (HLD; ahd re-reads on entering hold)
  inc hl                     ; -> +4
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
  ld d, (hl)                 ; +8 transpose (apply below)
  inc hl
  ld a, (ix+20)              ; old table # (compare before overwrite)
  ld e, a
  ld a, (hl)                 ; +9 instrument table # ($FF = none)
  ld (ix+20), a              ; default: the instrument's own table
  inc hl
  ; one-shot A override: a row's A command wins for THIS note only, then is
  ; consumed -- so A behaves like B (wave) / Y (FM), not as sticky state.
  ld a, (tbl_ovr)
  cp $FF
  jr z, tn_tovrdone
  cp NUM_TABLES
  jr c, tn_tovrset
  ld a, $FF                  ; A>=NUM_TABLES = table off
tn_tovrset:
  ld (ix+20), a
  ld a, $FF
  ld (tbl_ovr), a            ; consume the one-shot
tn_tovrdone:
  ld a, (hl)                 ; +10 table speed; TBS 0 = advance one row
  ld (ix+23), a              ;   per triggered note, else ticks/row
  ld (ix+22), 1              ; arm: one table row applies this trigger
  or a                       ; note mode (TBS 0)?
  jr z, tn_tnote
  ld (ix+21), 0              ; tick mode: table restarts on every note
  jr tn_tdone
tn_tnote:                    ; note mode: restart only when the table #
  ld a, (ix+20)              ;   changed (else the row persists and steps
  cp e                       ;   one row per note)
  jr z, tn_tdone
  ld (ix+21), 0
tn_tdone:
  ld (ix+24), 0
  ld (ix+25), 0              ; arp clears on new note
  ld (ix+26), 0
  ld (ix+28), 0              ; delay
  ld (ix+30), 0              ; porta
  ld (ix+31), 0              ; retrig
  ld a, b
  cp 2                       ; SMP: the note picks the sample
  ld a, d                    ; slot - never transpose it
  jr z, tn_tnone
  ld a, b
  cp 5                       ; FMDRUM: the note picks the drum
  ld a, d
  jr z, tn_tnone
  ld a, (proj_tsp)
  add a, d                   ; instrument + global transpose
tn_tnone:
  or a
  jr z, tn_mods
  add a, (ix+0)
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
  cp 2                       ; SMP: note picks the sample
  jr z, tn_smp
  cp 3                       ; WAV: wavetable through the DAC
  jr z, tn_wav
  cp 4                       ; FM: YM2413 voice
  jp z, tn_fm
  cp 5                       ; FMDRUM: YM2413 rhythm voice
  jp z, tn_fmdrum
  cp 1                       ; NOISE instrument?
  ret nz
  ld a, c
  ld (psg_noisectl), a
  and $03
  cp $03                     ; rate 3 = clock from tone 3
  ret nz
  ld (ix+12), 1              ; pitched: steal T3 (design doc 5.3)
  ret
tn_smp:
  ld a, c                    ; +4 byte = playback speed (0-3)
  cp 4
  jr c, tn_sspd
  xor a
tn_sspd:
  ld (smp_speed), a
  xor a
  ld (smp_hold), a
  ld a, (cur_trig_ch)
  ld (smp_owner), a
  ld a, (smp_count)
  or a
  jr z, tn_squiet            ; empty pool: just silence the host
  ld d, a                    ; D = sample count
  ; kit system: 8 kits of 8 -> sample = kit*8 + (note & 7). kit = instrument
  ; record +2 (0-7); slots past the loaded count are empty -> silence.
  ld a, (ix+1)               ; HL = instruments + instr*16 + 2  (the kit byte)
  add a, a
  add a, a
  add a, a
  add a, a
  ld l, a
  ld h, 0
  ld bc, instruments+2
  add hl, bc
  ld a, (hl)
  and 7                      ; kit 0-7
  add a, a
  add a, a
  add a, a                   ; kit * 8
  ld e, a
  ld a, (ix+0)               ; note
  and 7                      ; within-kit slot 0-7
  add a, e                   ; sample = kit*8 + (note & 7)
  cp d
  jr nc, tn_squiet           ; past the loaded samples -> empty slot, silence
  call smp_play
tn_squiet:
  ; the note only selects the sample (played on T3): the host
  ; track's own channel must stay silent. No envelope/length/table.
  ld (ix+0), $FF
  ld (ix+2), 0
  ld (ix+5), 0
  ld (ix+4), $FF
  ld (ix+20), $FF            ; samples don't run tables
  ret
tn_wav:
  ld a, c                    ; +4 byte = wave number
  and $07
  ld c, a
  ld a, (wav_ovr)            ; B command overrides it for this note
  cp $FF
  jr z, tnw_go
  and $07
  ld c, a
  ld a, $FF
  ld (wav_ovr), a            ; one-shot: consume the override
tnw_go:
  ld a, (cur_trig_ch)
  ld (wav_owner), a
  ld a, (ix+0)               ; transposes already baked in at
  call wav_play              ; trigger (instrument + global)
  ; host channel synthesizes nothing, but its volume gates the wave
  ; (vol 0 stops it). The gate doesn't scale the wave, so ATK/DCY are
  ; inaudible -- and a non-zero DCY would just trail the wave on at full
  ; level past HLD. Clear the cached ATK|DCY so the envelope is instant
  ; on -> hold (HLD) -> instant cut: HLD alone is the wave's length.
  ld (ix+5), 0
  ld (ix+0), $FF
  ld (ix+20), $FF            ; waves don't run tables
  ret

; FM (YM2413): key the note onto this track's FM channel (0-3).
; c = instrument +4 = ROM patch (1-15). Volume = instrument VOL (the
; AHD peak in ix+4 hi nibble) -> attenuation. F-number/block from the
; region table. The PSG host channel is silenced (FM has its own HW
; envelope; no per-tick engine work).
tn_fm:
  ld a, (fm_on)              ; FM disabled in OPTIONS? play nothing
  or a
  jr nz, tn_fm_go
  ld (ix+0), $FF             ; silence the PSG host either way
  ld (ix+2), 0
  ld a, STG_IDLE
  ld (ix+4), a
  ret
tn_fm_go:
  ld a, (ix+0)               ; note -> F-number low (e) + $20 pitch bits (d)
  add a, a
  ld e, a
  ld d, 0
  ld hl, (fm_note_ptr)
  add hl, de
  ld e, (hl)                 ; F-number low ($10-reg)
  inc hl
  ld a, (hl)
  or $30                     ; key-on ($10) | sustain ($20) | block | fnum8
  ld d, a                    ; -> $20-reg
  ld a, (fm_ovr)             ; Y command overrides the program for this note
  inc a
  jr z, tn_fm_noovr          ; $FF -> no override
  ld a, (fm_ovr)
  ld c, a
  ld a, $FF
  ld (fm_ovr), a             ; one-shot: consume the override
  jr tn_fm_inst              ; Y forces a ROM patch (ignores any preset)
tn_fm_noovr:
  ; FM preset is instrument byte +11 -- read the instrument record, NOT
  ; ix+11 (ix is the channel struct here; its +11 is the chain number).
  push de                    ; keep d=$20-reg, e=F-num low
  ld a, (ix+1)
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  ld de, instruments+11
  add hl, de
  ld a, (hl)                 ; +11: 0 = ROM patch, 1-8 = custom timbre
  pop de
  or a
  jr z, tn_fm_inst
  dec a                      ; preset index 0-7
  call fm_load_preset        ; load $00-$07 if it changed (preserves de)
  xor a                      ; patch 0 = the user (custom) patch
  jr tn_fm_p
tn_fm_inst:
  ld a, c                    ; patch (1-15); 0 would be the user patch
  and $0F
  jr nz, tn_fm_p
  inc a                      ; force patch 1 if unset
tn_fm_p:
  rlca
  rlca
  rlca
  rlca                       ; patch << 4
  ld l, a
  ld a, (ix+4)               ; VOL (AHD peak, high nibble) -> attenuation
  rrca
  rrca
  rrca
  rrca
  cpl
  and $0F                    ; 15 - VOL
  or l
  ld l, a                    ; -> $30-reg (patch | attenuation)
  ; mute the PSG host (vol 0); keep the note in ix+0 so a table can
  ; re-key the FM voice for arps (the silent PSG period write dedups)
  ld (ix+2), 0
  ; write FM channel cur_trig_ch: key-off, patch|vol, F-num, key-on
  ld a, (cur_trig_ch)
  add a, $20
  ld c, a
  ld b, 0
  call fm_w                  ; key off (retrigger); preserves d/e/l
  ld a, (cur_trig_ch)
  add a, $30
  ld c, a
  ld b, l
  call fm_w                  ; patch | attenuation
  ld a, (cur_trig_ch)
  add a, $10
  ld c, a
  ld b, e
  call fm_w                  ; F-number low
  ld a, (cur_trig_ch)
  add a, $20
  ld c, a
  ld b, d
  call fm_w                  ; key-on | sustain | block | fnum8
  ld (ix+12), 1              ; FM voice keyed on (gates fm_pitch_mod; ix+12 is
                             ;   the pitched-noise flag, free on FM channels)
  ; HLD: F (or 0) = ring per the FM patch envelope; 1-E = auto key-off
  ; after nibble*2 ticks (handled by ahd_process / STG_FMHOLD)
  call ahd_hldval            ; a = instrument HLD nibble
  or a
  jr z, tn_fm_ring
  cp $0F
  jr z, tn_fm_ring
  add a, a                   ; nibble * 2 = hold ticks
  ld (ix+3), a
  ld a, STG_FMHOLD
  ld (ix+4), a
  ret
tn_fm_ring:
  ld a, STG_IDLE
  ld (ix+4), a
  ret

; FM rhythm drum: the kit is one instrument, the note picks the drum
; (BD/SD/TT/TC/HH cycling every 5 semitones). No tables, no transpose.
tn_fmdrum:
  ld a, (fm_on)              ; FM disabled? play nothing
  or a
  jr nz, tn_fd_go
  ld (ix+0), $FF
  ld (ix+2), 0
  ld a, STG_IDLE
  ld (ix+4), a
  ret
tn_fd_go:
  ld (ix+20), $FF            ; drums ignore tables (kit = note picks drum)
  call tn_fd_drum            ; e = drum index 0-4 (from ix+0 note)
  ld a, (ix+4)               ; VOL (AHD peak high nibble) -> musical 0-F
  rrca
  rrca
  rrca
  rrca
  and $0F
  call fm_drum_trig          ; e = drum, a = vol; pulses the key-on edge
  ld (ix+2), 0               ; mute the PSG host
  ; HLD: F (or 0) = ring per the chip's drum envelope; 1-E = key-off
  ; after nibble*2 ticks (ahd_process / STG_FMDRUMHOLD)
  call ahd_hldval
  or a
  jr z, tn_fd_ring
  cp $0F
  jr z, tn_fd_ring
  add a, a
  ld (ix+3), a
  ld a, STG_FMDRUMHOLD
  ld (ix+4), a
  ret
tn_fd_ring:
  ld a, STG_IDLE
  ld (ix+4), a
  ret
; ix+0 note -> e = drum index 0-4 (note % 12 through the kit map)
tn_fd_drum:
  ld a, (ix+0)
tn_fd_mod:
  cp 12
  jr c, tn_fd_modd
  sub 12
  jr tn_fd_mod
tn_fd_modd:
  ld e, a
  ld d, 0
  ld hl, fm_drum_map
  add hl, de
  ld e, (hl)
  ret
fm_drum_map:                 ; note % 12 -> BD/SD/TT/TC/HH (cycling)
  .db 0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1

; -------------------------------------------------------------
; A = note index -> DE = period with sweep + pitch mod applied,
; clamped to 1..1023. Uses the IX channel's mod state.
calc_period:
  add a, (ix+24)             ; table pitch offset (semitones)
  ld d, a
  ld a, (ix+25)              ; C command arp: 0, +x, +y
  or a
  ld a, d
  jr z, cpd_noarp
  ld a, (ix+26)
  or a
  ld a, d
  jr z, cpd_noarp            ; phase 0: root
  ld e, a
  ld a, (ix+25)
  dec e
  jr nz, cpd_arpy
  rrca
  rrca
  rrca
  rrca                       ; phase 1: +x
cpd_arpy:
  and $0F
  add a, d
cpd_noarp:
  jp p, cpd_idx
  xor a
cpd_idx:
  cp NOTE_COUNT
  jr c, cpd_idx2
  ld a, NOTE_COUNT-1
cpd_idx2:
  add a, a
  ld e, a
  ld d, 0
  ld hl, (note_ptr)
  add hl, de
  ld e, (hl)
  inc hl
  ld d, (hl)                 ; base period
  ; --- porta (L): pull the accumulator toward zero ---
  ld a, (ix+30)
  or a
  jr z, cpd_swp
  ld l, (ix+13)
  ld h, (ix+14)
  ld a, h
  or l
  jr z, cpd_swp
  ld c, (ix+30)
  ld b, 0
  bit 7, h
  jr z, cpd_pdn
  add hl, bc                 ; negative side: rise toward 0
  bit 7, h
  jr nz, cpd_pst
  ld hl, 0
  jr cpd_pst
cpd_pdn:
  or a
  sbc hl, bc                 ; positive side: fall toward 0
  jr c, cpd_pzero
  bit 7, h
  jr z, cpd_pst
cpd_pzero:
  ld hl, 0
cpd_pst:
  ld (ix+13), l
  ld (ix+14), h
cpd_swp:
  ; --- sweep (instrument / P): acc += param ---
  ld a, (ix+17)
  or a
  jr z, cpd_acc
  ld c, a                    ; sign-extend into BC
  rlca
  sbc a, a
  ld b, a
  ld l, (ix+13)
  ld h, (ix+14)
  add hl, bc
  ld (ix+13), l
  ld (ix+14), h
cpd_acc:
  ; --- apply the accumulator to the period ---
  ld l, (ix+13)
  ld h, (ix+14)
  ld a, h
  or l
  jr z, cpd_vib
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
  ; finetune (F command), signed period units. Positive F raises pitch, so it
  ; SUBTRACTS from the period (period is inverse-frequency): negate, then add.
  ld a, (ix+27)
  or a
  jr z, cpd_fdone
  neg
  ld c, a
  rlca
  sbc a, a
  ld b, a
  ex de, hl
  add hl, bc
  ex de, hl
cpd_fdone:
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
  ld a, c
  ld (cur_trig_ch), a
  ; --- delayed note (D command) ---
  ld a, (ix+28)
  or a
  jr z, cf_retrig
  dec a
  ld (ix+28), a
  jr nz, cf_retrig
  ld a, (ix+29)
  ld (ix+0), a
  push bc
  call trigger_note
  pop bc
cf_retrig:
  ; --- retrigger (R command): counter hi, interval lo ---
  ld a, (ix+31)
  or a
  jr z, cf_table
  sub $10
  cp $10
  jr nc, cf_rst
  and $0F                    ; expired: retrigger, reload
  ld d, a
  push bc
  push de
  call trigger_note          ; (resets +31; restored below)
  pop de
  pop bc
  ld a, d
  rlca
  rlca
  rlca
  rlca
  or d
cf_rst:
  ld (ix+31), a
cf_table:
  ; --- table: per-tick (TBS 1-F) or per-note (TBS 0) advance ---
  ld a, (ix+20)
  cp NUM_TABLES
  jp nc, cf_env
  ld a, (ix+23)
  or a
  jr z, ct_note              ; TBS 0 = advance one row per triggered note
  dec (ix+22)                ; tick mode: a row every (ix+23) ticks
  jp nz, cf_env
  ld (ix+22), a              ; reload speed counter (a = TBS)
  jr ct_apply
ct_note:
  ld a, (ix+22)              ; note mode: only when a trigger armed us
  or a
  jp z, cf_env
  ld (ix+22), 0              ; disarm: exactly one row per note
ct_apply:
  ld a, (ix+20)              ; row ptr = tables + tbl*64 + row*4
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  ld a, (ix+21)
  add a, a
  add a, a
  ld e, a
  ld d, 0
  add hl, de
  ld de, tables
  add hl, de
  call chan_is_fm
  jr z, ct_fm_row            ; FM voice: route vol/pitch to the FM channel
  ld a, (hl)                 ; vol column ($FF = no change)
  cp $10
  jr nc, cf_tpitch
  ld (ix+2), a
cf_tpitch:
  inc hl
  ld a, (hl)                 ; pitch column (signed semitones)
  ld (ix+24), a
  inc hl
  jr ct_cmd
ct_fm_row:                   ; FM: vol -> FM volume, pitch -> FM re-key (arp)
  ld a, (hl)                 ; vol column ($FF = no change)
  cp $10
  jr nc, ctf_pitch
  push hl
  push bc
  ld d, a
  ld a, (cur_trig_ch)
  ld e, a
  ld a, d                    ; vol
  call fm_set_vol
  pop bc
  pop hl
ctf_pitch:
  inc hl
  ld a, (hl)                 ; pitch offset (signed)
  ld d, a
  ld a, (ix+24)
  cp d                       ; unchanged since last step? don't re-key
  jr z, ctf_skip             ;   (a flat/blank table must not retrigger)
  ld a, d
  ld (ix+24), a
  push hl
  push bc
  add a, (ix+0)              ; base note + offset, clamp to 0..NOTE_COUNT-1
  jp m, ctf_lo
  cp NOTE_COUNT
  jr c, ctf_hi
  ld a, NOTE_COUNT-1
  jr ctf_hi
ctf_lo:
  xor a
ctf_hi:
  ld d, a
  ld a, (cur_trig_ch)
  ld e, a
  ld a, d                    ; note index
  call fm_set_pitch
  pop bc
  pop hl
ctf_skip:
  inc hl
ct_cmd:
  ld a, (hl)                 ; command column
  or a
  jr z, cf_tadv
  cp CMD_HOP
  jr z, cf_thop
  inc hl
  ld d, (hl)
  push bc
  call exec_command          ; same set as phrase commands
  pop bc
cf_tadv:
  ld a, (ix+21)
  inc a
  and $0F
  ld (ix+21), a
  call tbl_skip_hops         ; step over any H row(s): the loop point rests on
  jr cf_env                  ; the real target, which plays on its own step
cf_thop:
  ; reached only if the *current* row is itself H (e.g. the first row after a
  ; trigger). Redirect, skip any chained H, then apply the real target now.
  inc hl
  ld a, (hl)                 ; jump target row (loop point)
  and $0F
  ld (ix+21), a
  call tbl_skip_hops
  jp ct_apply

cf_env:
  ; --- arp phase (C command): cycle 0,x,y each tick ---
  ld a, (ix+25)
  or a
  jr z, cf_env2
  ld a, (ix+26)
  inc a
  cp 3
  jr c, cf_arpst
  xor a
cf_arpst:
  ld (ix+26), a
cf_env2:
  ; --- AHD volume envelope (attack / hold / decay) ---
  ; full state machine lives in bank 1 (ahd_process); it walks
  ; ix+2 vol through the stage in ix+4, paced by ix+3, with the
  ; cached ATK|DCY rates in ix+5. Cuts the channel's sample when
  ; the decay/kill finishes.
  call ahd_process

  ; --- write shadows ---
cf_out:
  ld a, c
  cp 2                       ; T3 belongs to a playing sample
  jr nz, cf_not2
  ld a, (smp_active)
  or a
  jp nz, cf_next
cf_not2:
  ld a, c
  cp 3
  jr z, cf_noise
  ld a, (ix+0)
  cp $FF
  jr z, cf_vol
  ; NOTE: live FM pitch modulation (F/P/V on FM) is implemented in fm_pitch_mod
  ; below but currently DISABLED -- it never produced an audible wobble despite
  ; the write path, param, and phase all verified working. See
  ; FM_VIBRATO_NOTES.md before re-enabling (re-add: call chan_is_fm / jp z,
  ; fm_pitch_mod / reload ix+0 here).
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
  ld a, (smp_active)
  or a
  jr z, cf_npitch
  ; the DAC owns T3 and rate-3 noise is HARDWIRED to T3's
  ; period on the chip: fall back to the nearest fixed rate
  ; (design doc 5.3) so the noise voice keeps its character
  ld a, (psg_noisectl)
  and $04                    ; keep white/periodic mode
  or $02                     ; clk/2048, the lowest fixed rate
  ld (psg_noisectl), a
  jr cf_vol
cf_npitch:
  ld a, (psg_noisectl)       ; restore pitched clocking when
  and $04                    ; the DAC lets go (flush dedups,
  or $03                     ; so no LFSR-resetting rewrites)
  ld (psg_noisectl), a
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
cf_next:
  ; a wavetable stops when its owning channel falls silent
  ld a, (smp_mode)
  cp 2
  jr nz, cf_adv
  ld a, (wav_owner)
  cp c
  jr nz, cf_adv
  ld a, (ix+2)
  or a
  call z, wav_stop
cf_adv:
  ld de, 32
  add ix, de
  inc c
  ld a, c
  cp 4
  jp c, cf_loop
  ; wavetables no longer claim the noise channel: like samples, the
  ; noise voice plays normally alongside a wave (its own volume gate
  ; handles silence). Only *pitched* (rate-3) noise needs care - it is
  ; hardwired to T3's period, so cf_npitch falls it back to a fixed
  ; rate while the DAC owns T3 (the wave feed writes only T3's volume).
  ret

; =============================================================
; persistence: cart SRAM at $8000 via mapper reg $FFFC bit 3
; layout: slot base: magic "SMDJ3", +5 checksum16, +16 song data
; =============================================================
.DEFINE SRAM_DATA $8010
.DEFINE SAVE_SIZE 6912       ; wave_ram..grooves, contiguous (52 phrases / 40 chains)
.DEFINE CFG_ADDR  $BF60      ; OPTIONS config: tail of bank 0 (8K cart mirrors -> $1F60)

.ENDS

; the SRAM probe is boot-only (cold): park it in bank 1.
.BANK 1 SLOT 1
.SECTION "SramDetect" FREE

sram_detect:
  ld a, $08
  ld ($FFFC), a
  ld hl, $8000
  ld b, (hl)
  ld (hl), $A5
  ld a, (hl)
  cp $A5
  jr nz, sd_no
  ld (hl), $5A
  ld a, (hl)
  cp $5A
  jr nz, sd_no
  ld (hl), b
  ; size: does $A000 alias $8000 (8K mirror) or not (16K)?
  ld de, $A000
  ld a, (de)
  ld c, a
  ld a, $11
  ld (hl), a
  ld a, $33
  ld (de), a
  ld a, (hl)
  cp $33
  jr z, sd_8k
  ld a, b
  ld (hl), a
  ld a, c
  ld (de), a
  ; --- probe for a distinct second 16K bank (32K cart -> 6 slots) ---
  ; write different markers to $8000 in bank 0 and bank 1; only a
  ; real, independent second bank keeps both. The bank-0 read between
  ; the writes re-drives the bus, so open bus fails the bank-1 check.
  ld a, $08
  ld ($FFFC), a
  ld b, (hl)                 ; bank 0 original
  ld (hl), $C3               ; marker A -> bank 0
  ld a, $0C
  ld ($FFFC), a
  ld c, (hl)                 ; bank 1 original
  ld (hl), $3C               ; marker B -> bank 1
  ld a, $08
  ld ($FFFC), a
  ld a, (hl)
  cp $C3                     ; bank 0 clobbered -> aliased -> 16K
  jr nz, sd_16
  ld a, $0C
  ld ($FFFC), a
  ld a, (hl)
  cp $3C                     ; bank 1 didn't hold -> open bus -> 16K
  jr nz, sd_16
  ld a, c                    ; distinct second bank: restore both
  ld (hl), a                 ; bank 1 (selected)
  ld a, $08
  ld ($FFFC), a
  ld a, b
  ld (hl), a                 ; bank 0
  ld a, 6                    ; 32K: 6 slots
  jr sd_slots
sd_16:
  ld a, $08
  ld ($FFFC), a
  ld a, b
  ld (hl), a                 ; restore bank 0
  ld a, 3                    ; 16K window: 3 slots
  jr sd_slots
sd_8k:
  ld a, b
  ld (hl), a
  ld a, 1
sd_slots:
  ld (sram_slots), a
  ld hl, $2000               ; SMDJ4 heap capacity from the size: 8K
  cp 1
  jr z, sd_capset
  ld hl, $4000               ;   16K (3 slots)
  cp 3
  jr z, sd_capset
  ld hl, $8000               ;   32K (6 slots)
sd_capset:
  ld (sd4_cap), hl
  ld a, 1
  jr sd_st
sd_no:
  xor a
  ld (sram_slots), a
  ld (sd4_cap), a            ; no SRAM -> capacity 0
  ld (sd4_cap+1), a
sd_st:
  ld (sram_ok), a
  xor a
  ld ($FFFC), a
  ret

; rng: 16-bit Galois LFSR -> A = a pseudo-random byte. Advances rng_state, which
; must stay non-zero (seeded at boot, re-seeded from the frame counter on play).
; Preserves BC/DE/IX. Used by the Z (probability) command.
rng:
  ld hl, (rng_state)
  srl h
  rr l                       ; HL >>= 1, low bit -> carry
  jr nc, rng_nt
  ld a, h
  xor $B4                    ; tap polynomial $B400 (period 65535)
  ld h, a
rng_nt:
  ld (rng_state), hl
  ld a, l
  ret

; -------------------------------------------------------------
; OPTIONS config block (colour, sync, video) at CFG_ADDR ($BF60),
; separate from the song slots. On a 16K/32K cart that's the free tail
; past slot 2; on an 8K cart the window mirrors, so $BF60 lands at real
; $1F60 - also free (past slot 0). 6 bytes:
;   'C' 'F' pal_sel sync_mode vid_sel checksum(=pal+sync+vid & FF)
config_save:                 ; called by song_save (SRAM already on)
  ld a, $08                  ; select bank 0
  ld ($FFFC), a
  ld hl, CFG_ADDR
  ld (hl), 'C'
  inc hl
  ld (hl), 'F'
  inc hl
  ld a, (pal_sel)
  ld (hl), a
  ld b, a                    ; b = running checksum
  inc hl
  ld a, (sync_mode)
  ld (hl), a
  add a, b
  ld b, a
  inc hl
  ld a, (vid_sel)
  ld (hl), a
  add a, b
  ld b, a
  inc hl
  ld a, (fm_on)
  ld (hl), a
  add a, b
  inc hl
  ld (hl), a                 ; checksum = pal+sync+vid+fm
  ret

config_load:                 ; boot: restore OPTIONS if a valid block exists
  ld a, (sram_ok)
  or a
  ret z
  ld a, $08
  ld ($FFFC), a
  ld hl, CFG_ADDR
  ld a, (hl)
  cp 'C'
  jr nz, cfgl_done
  inc hl
  ld a, (hl)
  cp 'F'
  jr nz, cfgl_done
  inc hl
  ld c, (hl)                 ; pal_sel
  inc hl
  ld b, (hl)                 ; sync_mode
  inc hl
  ld e, (hl)                 ; vid_sel
  inc hl
  ld d, (hl)                 ; fm_on
  inc hl
  ld a, c
  add a, b
  add a, e
  add a, d
  cp (hl)                    ; checksum match? (pal+sync+vid+fm)
  jr nz, cfgl_done
  ld a, c
  cp 8                       ; pal_sel 0-7?
  jr nc, cfgl_done
  ld (pal_sel), a
  ld a, b                    ; sync_mode 0-5 (else fall back to OFF)
  cp SYNC_IN24+1
  jr c, cfgl_syncok
  xor a
cfgl_syncok:
  ld (sync_mode), a
  ld a, d
  and 1                      ; fm_on 0/1
  ld (fm_on), a
  ld a, e
  cp 3                       ; vid_sel 0-2? (else keep AUTO)
  jr nc, cfgl_done
  ld (vid_sel), a
cfgl_done:
  xor a
  ld ($FFFC), a
  ld a, (pal_sel)
  jp load_palette            ; apply (default or restored)

.ENDS

.BANK 0 SLOT 0
.SECTION "Engine4" FREE

; HL = base of the selected save slot ($1520 stride); also pages in
; its SRAM bank via $FFFC (slots 0-2 = bank 0, 3-5 = bank 1 on 32K).
sram_slot_base:
  ld a, (prj_slot)
  ld b, $08                  ; bank 0 enable
  cp 3
  jr c, ssb_bank
  sub 3                      ; second bank: slot 3-5 -> index 0-2
  ld b, $0C                  ; bank 1 enable
ssb_bank:
  push af
  ld a, b
  ld ($FFFC), a
  pop af
  ld hl, $8000
  or a
  ret z
  ld de, $1520
ssb_l:
  add hl, de
  dec a
  jr nz, ssb_l
  ret

; 16-bit byte sum over SAVE_SIZE bytes at HL -> DE
sram_sum:
  ld bc, SAVE_SIZE
  ld de, 0
ss_l:
  ld a, e
  add a, (hl)
  ld e, a
  ld a, d
  adc a, 0
  ld d, a
  inc hl
  dec bc
  ld a, b
  or c
  jr nz, ss_l
  ret

; save the song; prj_stat: 1 saved / 3 no sram or SRAM full.
; SMDJ4: RLE-pack into the directory/heap (src/rle.asm) instead of a fixed slot.
song_save:
  ld a, (sram_ok)
  or a
  jr nz, sv_go
  ld a, 3
  ld (prj_stat), a
  ret
sv_go:
  call engine_stop
  call smp_abort             ; SRAM is about to cover the pool
  call rle_dir_ensure        ; init the SMDJ4 directory on a fresh cart
  ld a, (prj_slot)
  call rle_song_save         ; Z = saved, NZ = SRAM full
  jr nz, sv_full
  call config_save           ; persist OPTIONS (colour, sync) in bank 0
  xor a
  ld ($FFFC), a
  ld a, 1
  ld (prj_stat), a
  ret
sv_full:
  xor a
  ld ($FFFC), a
  ld a, 3
  ld (prj_stat), a
  ret

; load the song; prj_stat: 2 loaded / 3 no sram / 4 no data
song_load:
  ld a, (sram_ok)
  or a
  jr nz, ld_go
  ld a, 3
  ld (prj_stat), a
  ret
ld_go:
  call engine_stop
  call smp_abort             ; SRAM is about to cover the pool
  ld a, (prj_slot)
  call rle_song_load         ; Z = loaded, NZ = empty slot / bad checksum
  jr nz, ld_bad
  call echo_sanitize         ; clamp any stray echo values
  xor a
  ld ($FFFC), a
  ld a, 2
  ld (prj_stat), a
  ret
ld_bad:
  xor a
  ld ($FFFC), a
  ld a, 4
  ld (prj_stat), a
  ret


; -------------------------------------------------------------
; copy demo song from ROM into the RAM song structures
; fresh blank song: the 8 preset waves, audible default
; instruments, groove 6,6 - everything else empty
song_new:
  ld hl, default_waves       ; the 8 stamp presets lead wave_ram
  ld de, wave_ram
  ld bc, 8*32
  ldir
  ld hl, phrase_pool         ; steps: note 0, instr $FF, cmd 0,
  ld bc, NUM_PHRASES*16      ; param 0
sn_phl:
  ld (hl), 0
  inc hl
  ld (hl), $FF
  inc hl
  ld (hl), 0
  inc hl
  ld (hl), 0
  inc hl
  dec bc
  ld a, b
  or c
  jr nz, sn_phl
  ld hl, chains              ; chains + song are contiguous: $FF
  ld de, chains+1
  ld bc, NUM_CHAINS*32 + SONG_ROWS*4 - 1
  ld (hl), $FF
  ldir
  ld de, instruments         ; 16 x the default record
  ld b, 16
sn_inl:
  push bc
  ld hl, instr_default
  ld bc, 16
  ldir
  pop bc
  djnz sn_inl
  ld hl, tables              ; vol $FF (no change), rest 0
  ld b, 0                    ; 256 rows
sn_tbl:
  ld (hl), $FF
  inc hl
  ld (hl), 0
  inc hl
  ld (hl), 0
  inc hl
  ld (hl), 0
  inc hl
  djnz sn_tbl
  ld hl, grooves
  ld de, grooves+1
  ld bc, NUM_GROOVES*16-1
  ld (hl), 0
  ldir
  ld a, 6                    ; groove 0 = 6,6
  ld (grooves), a
  ld (grooves+1), a
  call rle_name_default
  jp echo_defaults

.ENDS

; -------------------------------------------------------------
; AHD volume envelope state machine (bank 1, always-mapped slot).
; IN: ix = channel struct, c = channel index. Walks ix+2 (current
; vol) through the stage (low nibble of ix+4), paced by ix+3, with
; the cached ATK|DCY rates in ix+5 (ATK high nibble, DCY low). The
; peak sits in the HIGH nibble of ix+4 (snapshotted from the
; instrument VOL at trigger; the X command overrides it); HLD time
; is re-read live from the instrument (ix+1), so E re-slopes ATK/DCY
; without disturbing it. Preserves c and ix. ATK/DCY are ticks-per-
; volume-step (rate 0 = instant); HLD is raw ticks, nibble $F = hold
; forever.
.BANK 1 SLOT 1
.SECTION "AHD" FREE
ahd_process:
  ld a, (ix+4)
  and $07                    ; stage (high nibble carries the peak in attack)
  jr z, ahd_atk
  cp STG_HLD
  jp z, ahd_hld
  cp STG_DCY
  jp z, ahd_dcy
  cp STG_KILL
  jp z, ahd_kill
  cp STG_FMHOLD
  jp z, ahd_fmhold
  cp STG_FMDRUMHOLD
  jp z, ahd_fmdrumhold
  ret                        ; idle: hold current vol

; ---- attack: ramp 0 -> peak ----
ahd_atk:
  ld a, (ix+5)
  and $F0
  jr z, ahd_atk_now          ; ATK rate 0 -> instant to peak
  rrca
  rrca
  rrca
  rrca                       ; a = ATK rate 1..F (ticks/step)
  dec (ix+3)
  ret nz
  ld (ix+3), a               ; reload pace counter
  call ahd_peak              ; e = peak VOL
  ld a, (ix+2)
  inc a
  cp e
  jr c, ahd_atk_set          ; below peak: keep climbing
  ld a, e
  ld (ix+2), a
  jr ahd_enter_hold
ahd_atk_set:
  ld (ix+2), a
  ret
ahd_atk_now:
  call ahd_peak
  ld a, e
  ld (ix+2), a
  ; fall into enter_hold

; ---- attack done -> set up hold (HLD nibble) ----
ahd_enter_hold:
  call ahd_hldval            ; a = HLD nibble 0..F
  cp $0F
  jr z, ahd_hold_inf         ; F = hold forever
  or a
  jr z, ahd_begin_decay      ; 0 = no hold -> straight to decay
  add a, a                   ; 1..E -> hold 2..28 ticks
  ld (ix+3), a
  ld a, STG_HLD
  ld (ix+4), a
  ret
ahd_hold_inf:
  ld a, (play_state)         ; while stopped (prelisten), a forever-
  or a                       ; hold note would drone, so cap it
  ld a, $FF                  ; playing: sentinel = hold forever
  jr nz, ahd_hold_set
  ld a, PRELISTEN_CAP
ahd_hold_set:
  ld (ix+3), a
  ld a, STG_HLD
  ld (ix+4), a
  ret

; ---- hold: sit at peak ----
ahd_hld:
  ld a, (ix+3)
  inc a
  ret z                      ; $FF -> forever
  dec (ix+3)
  ret nz
  ; fall into begin_decay

; ---- hold done -> set up decay (DCY rate) ----
ahd_begin_decay:
  ld a, (ix+5)
  and $0F                    ; DCY rate
  jr z, ahd_cut              ; DCY 0 -> instant cut
  ld (ix+3), a               ; pace counter
  ld a, STG_DCY
  ld (ix+4), a
  ret

; ---- decay: ramp peak -> 0 ----
ahd_dcy:
  ld a, (ix+5)
  and $0F
  jr z, ahd_cut
  dec (ix+3)
  ret nz
  ld (ix+3), a               ; reload pace
  ld a, (ix+2)
  or a
  jr z, ahd_cut
  dec a
  ld (ix+2), a
  ret nz
ahd_cut:
  ld (ix+2), 0
  ld a, STG_IDLE
  ld (ix+4), a
  ld a, c                    ; stop a sample this channel owns
  jp smp_kill_owned

; ---- K command: count down then hard cut ----
ahd_kill:
  dec (ix+3)
  ret nz
  jr ahd_cut

; ---- FM note hold: count down, then key off the FM channel (= c) ----
ahd_fmhold:
  dec (ix+3)
  ret nz
  ld a, STG_IDLE
  ld (ix+4), a
  ld (ix+12), 0              ; FM voice keyed off: stop fm_pitch_mod re-keying it
  push bc
  ld a, c
  add a, $20                 ; $20 + channel = key-off register
  ld c, a
  ld b, 0
  call fm_w
  pop bc
  ret

; FM drum hold expired: key off the rhythm voice (recompute the drum
; from the kept note in ix+0). Preserves c and ix.
ahd_fmdrumhold:
  dec (ix+3)
  ret nz
  ld a, STG_IDLE
  ld (ix+4), a
  call tn_fd_drum            ; e = drum index from ix+0
  jp fm_drum_off

; helper: e = this note's peak volume (high nibble of the stage byte
; ix+4, snapshotted from the instrument at trigger; X overrides it)
ahd_peak:
  ld a, (ix+4)
  rrca
  rrca
  rrca
  rrca
  and $0F
  ld e, a
  ret

; helper: a = HLD nibble (instruments[(ix+1)*16]+3 low nibble)
ahd_hldval:
  push hl
  push bc
  ld a, (ix+1)
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  ld bc, instruments+3
  add hl, bc
  ld a, (hl)
  pop bc
  pop hl
  and $0F
  ret
.ENDS

.BANK 0 SLOT 0
