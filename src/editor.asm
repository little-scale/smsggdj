; =============================================================
; SMSDJ - PHRASE editor (milestone 4)
;
; Screen: one phrase (16 rows) of the selected track.
;   columns: 0=note (3 ch), 1=instrument (1 ch),
;            2=command (1 ch), 3=param (2 ch)
; Cursor and playhead are palette-bit inverse video; rows are
; redrawn through a dirty-row queue, max 4 rows per VBlank.
;
; Controls (design doc section 3, with hold-time disambiguation):
;   dpad            move cursor (key repeat)
;   1 (tap)         insert last note/instr on empty step,
;                   prelisten existing note (when stopped)
;   1 held + dpad   edit field (L/R small, U/D big)
;   2 held + L/R    switch track (placeholder for screen map)
;   2 held >TH, +1  cut step field
;   1+2 together    play/stop (within COMBO_WINDOW frames)
;
; A 1-press is held pending for COMBO_WINDOW frames so a
; near-simultaneous 2 means transport, not insert.
; =============================================================

.DEFINE COMBO_WINDOW 4         ; frames: 1+2 counts as transport
.DEFINE HOLD_TH      10        ; frames: button counts as "held"
.DEFINE PRELISTEN_LEN 32       ; ticks: cap sustained prelisten

.RAMSECTION "edvars" SLOT 3
  ed_track     db
  ed_row       db
  ed_col       db
  last_note    db
  last_instr   db
  b1_frames    db
  b2_frames    db
  pend1        db            ; pending-insert countdown, 0 = none
  label_dirty  db
  ed_rep       db
  tmp_note     db
  tmp_instr    db
  tmp_cmd      db
  tmp_param    db
  eng_drawn_row db           ; playhead row currently on screen
  dirty_rows   dsb 16
.ENDS

.SECTION "Editor" FREE

editor_init:
  ld a, 25                   ; A-4
  ld (last_note), a
  xor a
  ld (last_instr), a
  ld (ed_track), a
  ld (ed_row), a
  ld (ed_col), a
  ld (pend1), a
  ld a, $FF
  ld (eng_drawn_row), a
  ld a, 1
  ld (label_dirty), a
  jp mark_all_dirty

; =============================================================
; input
; =============================================================
editor_input:
  ; ---- button 1 pressed ----
  ld a, (pad_edge)
  and PAD_B1
  jr z, ei_no1
  ld a, (pad_raw)
  and PAD_B2
  jr z, ei_1alone
  ld a, (b2_frames)          ; 1 while 2 down: cut or transport
  cp HOLD_TH
  jr c, ei_1trans
  call do_cut
  jr ei_no1
ei_1trans:
  call toggle_play
  jr ei_no1
ei_1alone:
  ld a, COMBO_WINDOW         ; defer insert: 2 may follow
  ld (pend1), a
ei_no1:
  ; ---- button 2 pressed ----
  ld a, (pad_edge)
  and PAD_B2
  jr z, ei_no2
  ld a, (pad_raw)
  and PAD_B1
  jr z, ei_no2
  ld a, (b1_frames)          ; 2 while 1 down: transport if
  cp HOLD_TH                 ; near-simultaneous (paste later)
  jr nc, ei_no2
  xor a
  ld (pend1), a
  call toggle_play
ei_no2:
  ; ---- pending insert ----
  ld a, (pend1)
  or a
  jr z, ei_pdone
  ld a, (pad_edge)           ; dpad while pending: flush now so
  and $0F                    ; insert-then-edit feels instant
  jr nz, ei_flush
  ld a, (pend1)
  dec a
  ld (pend1), a
  jr nz, ei_pdone
ei_flush:
  xor a
  ld (pend1), a
  call do_press
ei_pdone:
  ; ---- dpad routing ----
  ld a, (pad_raw)
  and PAD_B1
  jr nz, ei_edit
  ld a, (pad_raw)
  and PAD_B2
  jr nz, ei_nav
  call cursor_move
  jr ei_holds
ei_edit:
  call do_edit
  jr ei_holds
ei_nav:
  call track_nav
ei_holds:
  ; ---- hold counters ----
  ld a, (pad_raw)
  and PAD_B1
  jr z, ei_h1z
  ld a, (b1_frames)
  cp 200
  jr nc, ei_h2
  inc a
  ld (b1_frames), a
  jr ei_h2
ei_h1z:
  xor a
  ld (b1_frames), a
ei_h2:
  ld a, (pad_raw)
  and PAD_B2
  jr z, ei_h2z
  ld a, (b2_frames)
  cp 200
  ret nc
  inc a
  ld (b2_frames), a
  ret
ei_h2z:
  xor a
  ld (b2_frames), a
  ret

; -------------------------------------------------------------
; cursor movement (no modifier)
cursor_move:
  ld a, (pad_rep)
  and $0F
  ret z
  ld c, a
  ld a, (ed_row)
  call mark_dirty_a
  bit 1, c                   ; down
  jr z, cm_up
  ld a, (ed_row)
  inc a
  and $0F
  ld (ed_row), a
cm_up:
  bit 0, c
  jr z, cm_right
  ld a, (ed_row)
  dec a
  and $0F
  ld (ed_row), a
cm_right:
  bit 3, c
  jr z, cm_left
  ld a, (ed_col)
  inc a
  and $03
  ld (ed_col), a
cm_left:
  bit 2, c
  jr z, cm_done
  ld a, (ed_col)
  dec a
  and $03
  ld (ed_col), a
cm_done:
  ld a, (ed_row)
  jp mark_dirty_a

; -------------------------------------------------------------
; 2 held + L/R: switch track (until the screen map exists)
track_nav:
  ld a, (pad_edge)
  and PAD_LEFT|PAD_RIGHT
  ret z
  and PAD_RIGHT
  ld a, (ed_track)
  jr z, tn_left
  inc a
  jr tn_store
tn_left:
  dec a
tn_store:
  and $03
  ld (ed_track), a
  ld a, 1
  ld (label_dirty), a
  jp mark_all_dirty

; -------------------------------------------------------------
; 1 pressed (no dpad yet): insert / audition at cursor
do_press:
  ld a, (ed_row)
  ld e, a
  call ed_step_ptr
  ld a, (ed_col)
  or a
  jr z, dp_note
  cp 1
  jr z, dp_instr
  cp 2
  jr z, dp_cmd
  ret                        ; param column: nothing
dp_note:
  ld a, (hl)
  or a
  jr nz, dp_audit
  ld a, (last_note)
  ld (hl), a
  inc hl
  ld a, (last_instr)
  ld (hl), a
  dec hl
  call mark_cur_dirty
dp_audit:
  ld d, (hl)
  inc hl
  ld a, (hl)
  cp $10
  jr c, dp_pl
  ld a, (last_instr)
dp_pl:
  ld c, a
  jp prelisten
dp_instr:
  inc hl
  ld a, (hl)
  cp $10
  ret c                      ; already set
  ld a, (last_instr)
  ld (hl), a
  jp mark_cur_dirty
dp_cmd:
  inc hl
  inc hl
  ld a, (hl)
  or a
  ret nz
  ld a, CMD_KILL
  ld (hl), a
  jp mark_cur_dirty

; -------------------------------------------------------------
; 2 held + 1: cut field under cursor
do_cut:
  ld a, (ed_row)
  ld e, a
  call ed_step_ptr
  ld a, (ed_col)
  or a
  jr z, dc_note
  cp 1
  jr z, dc_instr
  cp 2
  jr z, dc_cmd
  inc hl                     ; param
  inc hl
  inc hl
  ld (hl), 0
  jp mark_cur_dirty
dc_note:
  ld (hl), 0
  inc hl
  ld (hl), $FF
  jp mark_cur_dirty
dc_instr:
  inc hl
  ld (hl), $FF
  jp mark_cur_dirty
dc_cmd:
  inc hl
  inc hl
  ld (hl), 0
  inc hl
  ld (hl), 0
  jp mark_cur_dirty

; -------------------------------------------------------------
; 1 held + dpad: edit field under cursor
do_edit:
  ld a, (pad_rep)
  and $0F
  ret z
  ld (ed_rep), a
  ld a, (ed_row)
  ld e, a
  call ed_step_ptr
  ld a, (ed_col)
  or a
  jr z, de_note
  cp 1
  jr z, de_instr
  cp 2
  jp z, de_cmd
  jp de_param

de_note:
  ld a, (hl)
  or a
  jr nz, den_have
  ld a, (last_note)
den_have:
  ld d, a
  ld a, (ed_rep)
  ld c, a
  bit 3, c                   ; right: +1 semitone
  jr z, den_l
  inc d
  ld a, d
  cp NOTE_COUNT+1
  jr c, den_l
  ld d, NOTE_COUNT
den_l:
  bit 2, c                   ; left: -1 semitone
  jr z, den_u
  dec d
  jr nz, den_u
  ld d, 1
den_u:
  bit 0, c                   ; up: +octave
  jr z, den_d
  ld a, d
  add a, 12
  cp NOTE_COUNT+1
  jr c, den_ust
  ld a, NOTE_COUNT
den_ust:
  ld d, a
den_d:
  bit 1, c                   ; down: -octave
  jr z, den_store
  ld a, d
  sub 12
  jr z, den_floor
  jr nc, den_dst
den_floor:
  ld a, 1
den_dst:
  ld d, a
den_store:
  ld (hl), d
  ld a, d
  ld (last_note), a
  call mark_cur_dirty
  ; prelisten with the step's instrument
  inc hl
  ld a, (hl)
  cp $10
  jr c, den_pl
  ld a, (last_instr)
den_pl:
  ld c, a
  jp prelisten

de_instr:
  inc hl
  ld a, (hl)
  cp $10
  jr c, dei_have
  ld a, (last_instr)
dei_have:
  ld d, a
  ld a, (ed_rep)
  ld c, a
  bit 3, c
  jr nz, dei_inc
  bit 0, c
  jr z, dei_dec
dei_inc:
  ld a, d
  cp $0F
  jr nc, dei_dec
  inc d
dei_dec:
  bit 2, c
  jr nz, dei_d2
  bit 1, c
  jr z, dei_store
dei_d2:
  ld a, d
  or a
  jr z, dei_store
  dec d
dei_store:
  ld (hl), d
  ld a, d
  ld (last_instr), a
  jp mark_cur_dirty

de_cmd:
  ld a, (pad_edge)           ; toggle on edge only
  and $0F
  ret z
  inc hl
  inc hl
  ld a, (hl)
  xor CMD_KILL
  ld (hl), a
  jp mark_cur_dirty

de_param:
  inc hl
  inc hl
  inc hl
  ld d, (hl)
  ld a, (ed_rep)
  ld c, a
  bit 3, c
  jr z, dep_l
  inc d
dep_l:
  bit 2, c
  jr z, dep_u
  dec d
dep_u:
  bit 0, c
  jr z, dep_d
  ld a, d
  add a, 16
  ld d, a
dep_d:
  bit 1, c
  jr z, dep_store
  ld a, d
  sub 16
  ld d, a
dep_store:
  ld (hl), d
  jp mark_cur_dirty

; -------------------------------------------------------------
; audition note D (note byte) instr C on the edited track,
; only while stopped; sustained instruments are capped
prelisten:
  ld a, (play_state)
  or a
  ret nz
  ld a, (ed_track)
  add a, a
  add a, a
  add a, a                   ; * 8
  push de
  ld e, a
  ld d, 0
  ld ix, chst
  add ix, de
  pop de
  ld a, d
  dec a
  ld (ix+0), a
  ld (ix+1), c
  call trigger_note
  ld a, (ix+4)
  cp $FF
  ret nz
  ld (ix+4), PRELISTEN_LEN
  ret

; -------------------------------------------------------------
; dirty-row bookkeeping
mark_cur_dirty:
  ld a, (ed_row)
mark_dirty_a:                ; A = phrase row
  ld hl, dirty_rows
  ld e, a
  ld d, 0
  add hl, de
  ld (hl), 1
  ret

mark_all_dirty:
  ld hl, dirty_rows
  ld b, 16
mad_l:
  ld (hl), 1
  inc hl
  djnz mad_l
  ret

; E = row -> HL = step address in the edited track's phrase
ed_step_ptr:
  ld a, (ed_track)
  add a, a
  add a, a
  add a, a
  add a, a
  add a, a
  add a, a                   ; * 64
  ld d, a
  ld a, e
  add a, a
  add a, a                   ; * 4
  add a, d
  ld e, a
  ld d, 0
  ld hl, phrase_pool
  add hl, de
  ret

; =============================================================
; drawing
; =============================================================
editor_draw:
  ; track label
  ld a, (label_dirty)
  or a
  jr z, edr_ph
  xor a
  ld (label_dirty), a
  ld (text_attr), a
  ld a, (ed_track)
  add a, a
  ld e, a
  ld d, 0
  ld hl, track_names
  add hl, de
  push hl
  ld b, 1
  ld c, 16
  call nt_addr_hl
  call vdp_set_addr
  pop hl
  ld b, 2
  call print_raw

edr_ph:
  ; playhead row changed?
  ld a, (play_state)
  or a
  jr z, edr_phstop
  ld a, (cur_row)
  ld b, a
  ld a, (eng_drawn_row)
  cp b
  jr z, edr_flush
  cp $FF
  jr z, edr_phnew
  call mark_dirty_a
edr_phnew:
  ld a, b
  ld (eng_drawn_row), a
  cp $FF
  jr z, edr_flush
  call mark_dirty_a
  jr edr_flush
edr_phstop:
  ld a, (eng_drawn_row)
  cp $FF
  jr z, edr_flush
  call mark_dirty_a
  ld a, $FF
  ld (eng_drawn_row), a

edr_flush:
  ld e, 0                    ; row
  ld d, 4                    ; rows-per-frame budget
edr_fl:
  ld a, d
  or a
  jr z, edr_done
  ld hl, dirty_rows
  push de
  ld d, 0
  add hl, de
  pop de
  ld a, (hl)
  or a
  jr z, edr_next
  ld (hl), 0
  push de
  call draw_ed_row
  pop de
  dec d
edr_next:
  inc e
  ld a, e
  cp 16
  jr c, edr_fl
edr_done:
  xor a
  ld (text_attr), a
  ret

; render one full phrase row (E = row)
draw_ed_row:
  ; ---- row label, inverted when it is the playhead ----
  xor a
  ld (text_attr), a
  ld a, (eng_drawn_row)
  cp e
  jr nz, der_lbl
  ld a, $08
  ld (text_attr), a
der_lbl:
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, 1
  push de
  call nt_addr_hl
  call vdp_set_addr
  pop de
  ld a, e
  push de
  call print_hex_nib
  pop de

  ; ---- fetch step into temps ----
  push de
  call ed_step_ptr
  pop de
  ld a, (hl)
  ld (tmp_note), a
  inc hl
  ld a, (hl)
  ld (tmp_instr), a
  inc hl
  ld a, (hl)
  ld (tmp_cmd), a
  inc hl
  ld a, (hl)
  ld (tmp_param), a

  ; ---- note (3 chars, col 4) ----
  xor a
  call field_attr
  ld a, (tmp_note)
  or a
  jr nz, der_name
  ld hl, str_rest
  jr der_npr
der_name:
  dec a
  ld l, a
  add a, a
  add a, l                   ; * 3
  push de
  ld e, a
  ld d, 0
  ld hl, note_names
  add hl, de
  pop de
der_npr:
  push hl
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, 4
  push de
  call nt_addr_hl
  call vdp_set_addr
  pop de
  pop hl
  ld b, 3
  call print_raw

  ; ---- instrument (1 char, col 9) ----
  ld a, 1
  call field_attr
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, 9
  push de
  call nt_addr_hl
  call vdp_set_addr
  pop de
  ld a, (tmp_instr)
  cp $10
  jr c, der_ihex
  ld a, '-'
  push de
  call print_char
  pop de
  jr der_cmd
der_ihex:
  push de
  call print_hex_nib
  pop de

  ; ---- command (1 char, col 12) ----
der_cmd:
  ld a, 2
  call field_attr
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, 12
  push de
  call nt_addr_hl
  call vdp_set_addr
  pop de
  ld a, (tmp_cmd)
  or a
  ld a, '-'
  jr z, der_cpr
  ld a, 'K'
der_cpr:
  push de
  call print_char
  pop de

  ; ---- param (2 chars, col 13) ----
  ld a, 3
  call field_attr
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, 13
  push de
  call nt_addr_hl
  call vdp_set_addr
  pop de
  ld a, (tmp_cmd)
  or a
  jr z, der_pdash
  ld a, (tmp_param)
  push de
  call print_hex_a
  pop de
  ret
der_pdash:
  ld a, '-'
  push de
  call print_char
  ld a, '-'
  call print_char
  pop de
  ret

; A = column id, E = row: set text_attr (inverted under cursor)
field_attr:
  ld d, a
  ld a, (ed_row)
  cp e
  jr nz, fa_norm
  ld a, (ed_col)
  cp d
  jr nz, fa_norm
  ld a, $08
  jr fa_set
fa_norm:
  xor a
fa_set:
  ld (text_attr), a
  ret

track_names:
  .db "T1T2T3NO"

.ENDS
