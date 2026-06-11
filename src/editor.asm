; =============================================================
; SMSDJ - editor: SONG / CHAIN / PHRASE screens (milestone 5)
;
; Screen map (design doc section 4, subset implemented):
;   [SONG] <-> [CHAIN] <-> [PHRASE]      (2 held + left/right)
; Context flows right: entering CHAIN opens the chain under the
; SONG cursor (and selects its track); entering PHRASE opens the
; phrase under the CHAIN cursor.
;
; Common controls (hold-time disambiguation as before):
;   dpad           cursor       1 tap        insert/audition
;   1 + dpad       edit         2 long + 1   cut
;   1+2 together   play/stop (mode follows the current screen)
; SONG header row (up from row 0): 1 = mute, 2 long + 1 = solo.
; =============================================================

.DEFINE DT_WINDOW    15        ; frames: double-tap window
.DEFINE PRELISTEN_LEN 32       ; ticks: cap sustained prelisten

.DEFINE SCR_SONG    0          ; values match MODE_* on purpose
.DEFINE SCR_CHAIN   1
.DEFINE SCR_PHRASE  2
.DEFINE SCR_INSTR   3
.DEFINE SCR_TABLE   4
.DEFINE SCR_GROOVE  5

.RAMSECTION "edvars" SLOT 3
  scr_mode     db
  ed_track     db
  cur_chain    db
  cur_phrase   db
  cur_instr    db
  ins_row      db
  cur_table    db
  tbl_row      db
  tbl_col      db
  cur_groove   db
  grv_row      db
  song_cur     db            ; absolute song row of the cursor
  song_col     db
  song_view    db            ; top visible song row
  hdr_cur      db            ; 1 = cursor on the track header
  chn_row      db
  chn_col      db
  phr_row      db
  phr_col      db
  last_note    db
  last_instr   db
  last_chain   db
  last_phrase  db
  dt1_timer    db            ; double-tap countdown
  clip_scr     db            ; clipboard: screen ($FF = empty)
  clip_col     db            ;   column
  clip_a       db            ;   primary byte
  clip_b       db            ;   secondary byte
  label_dirty  db
  ed_rep       db
  tmp_note     db
  tmp_instr    db
  tmp_cmd      db
  tmp_param    db
  ed_field     db            ; INSTR: field being drawn
  drawn_a      dsb 4         ; playhead rows currently on screen
  dirty_rows   dsb 16
.ENDS

.SECTION "Editor" FREE

editor_init:
  ld a, 25                   ; A-4
  ld (last_note), a
  xor a
  ld (last_instr), a
  ld (last_chain), a
  ld (last_phrase), a
  ld (scr_mode), a           ; start on SONG
  ld (ed_track), a
  ld (cur_chain), a
  ld (cur_phrase), a
  ld (song_cur), a
  ld (song_col), a
  ld (song_view), a
  ld (hdr_cur), a
  ld (chn_row), a
  ld (chn_col), a
  ld (phr_row), a
  ld (phr_col), a
  ld (cur_instr), a
  ld (ins_row), a
  ld (cur_table), a
  ld (tbl_row), a
  ld (tbl_col), a
  ld (cur_groove), a
  ld (grv_row), a
  ld (dt1_timer), a
  ld a, $FF
  ld (clip_scr), a
  xor a
  ld hl, drawn_a
  ld a, $FF
  ld (hl), a
  inc hl
  ld (hl), a
  inc hl
  ld (hl), a
  inc hl
  ld (hl), a
  ld a, 1
  ld (label_dirty), a
  jp mark_all_dirty

; =============================================================
; input
; =============================================================
editor_input:
  ; held-state disambiguation (no timing windows):
  ;   1 while 2 held = transport   2 while 1 held = cut
  ;   1 alone = insert/audition    1 double-tap = paste
  ; ---- button 1 pressed ----
  ld a, (pad_edge)
  and PAD_B1
  jr z, ei_no1
  ld a, (pad_raw)
  and PAD_B2
  jr z, ei_1alone
  call toggle_play           ; 2 held + 1 = play/stop
  jr ei_dtick                ; consume: no cut on the same press
ei_1alone:
  ld a, (dt1_timer)
  or a
  jr z, ei_1first
  xor a
  ld (dt1_timer), a
  call do_paste              ; second tap = paste
  jr ei_no1
ei_1first:
  ld a, DT_WINDOW
  ld (dt1_timer), a
  call do_press              ; insert/audition immediately
ei_no1:
  ; ---- button 2 pressed ----
  ld a, (pad_edge)
  and PAD_B2
  jr z, ei_dtick
  ld a, (pad_raw)
  and PAD_B1
  jr z, ei_dtick
  call do_cut                ; 1 held + 2 = cut
ei_dtick:
  ; ---- double-tap countdown ----
  ld a, (dt1_timer)
  or a
  jr z, ei_dpad
  dec a
  ld (dt1_timer), a
ei_dpad:
  ; ---- dpad routing ----
  ld a, (pad_raw)
  and PAD_B1
  jr nz, ei_edit
  ld a, (pad_raw)
  and PAD_B2
  jr nz, ei_nav
  jp cursor_move
ei_edit:
  jp do_edit
ei_nav:
  jp screen_nav

; =============================================================
; screen map: 2 held + L/R
; =============================================================
screen_nav:
  ; on INSTR/TABLE, 2 + up/down selects the item being edited
  ld a, (scr_mode)
  cp SCR_INSTR
  jr z, sn_seli
  cp SCR_TABLE
  jr z, sn_selt
  cp SCR_GROOVE
  jr z, sn_selg
  jr sn_lr
sn_seli:
  ld a, (pad_edge)
  and PAD_UP|PAD_DOWN
  jr z, sn_lr
  and PAD_UP
  ld a, (cur_instr)
  jr z, sni_dn
  inc a
  jr sni_st
sni_dn:
  dec a
sni_st:
  and $0F
  ld (cur_instr), a
  ld a, 1
  ld (label_dirty), a
  jp mark_all_dirty
sn_selt:
  ld a, (pad_edge)
  and PAD_UP|PAD_DOWN
  jr z, sn_lr
  and PAD_UP
  ld a, (cur_table)
  jr z, snt_dn
  inc a
  jr snt_st
snt_dn:
  dec a
snt_st:
  and $0F
  ld (cur_table), a
  ld a, 1
  ld (label_dirty), a
  jp mark_all_dirty
sn_selg:
  ld a, (pad_edge)
  and PAD_UP|PAD_DOWN
  jr z, sn_lr
  and PAD_UP
  ld a, (cur_groove)
  jr z, sng_dn
  inc a
  jr sng_st
sng_dn:
  dec a
sng_st:
  and $0F
  ld (cur_groove), a
  ld a, 1
  ld (label_dirty), a
  jp mark_all_dirty
sn_lr:
  ld a, (pad_edge)
  and PAD_LEFT|PAD_RIGHT
  ret z
  and PAD_RIGHT
  jr nz, sn_right
  ; ---- left: PHRASE -> CHAIN -> SONG ----
  ld a, (scr_mode)
  or a
  ret z
  dec a
  jr sn_switch
sn_right:
  ld a, (scr_mode)
  cp SCR_SONG
  jr z, sn_tochain
  cp SCR_PHRASE
  jr z, sn_toinstr
  cp SCR_INSTR
  jr z, sn_totable
  cp SCR_TABLE
  jr z, sn_togroove
  cp SCR_CHAIN
  ret nz
  ; CHAIN -> PHRASE: phrase under cursor
  ld a, (chn_row)
  ld e, a
  call ch_entry_ptr
  ld a, (hl)
  cp $FF
  ret z
  ld (cur_phrase), a
  ld a, SCR_PHRASE
  jr sn_switch
sn_toinstr:
  ; PHRASE -> INSTR: instrument under cursor (or last used)
  ld a, (phr_row)
  ld e, a
  call ed_step_ptr
  inc hl
  ld a, (hl)
  cp $10
  jr c, sn_iset
  ld a, (last_instr)
sn_iset:
  ld (cur_instr), a
  xor a
  ld (ins_row), a
  ld a, SCR_INSTR
  jr sn_switch
sn_togroove:
  ld a, SCR_GROOVE
  jp sn_switch
sn_totable:
  ; INSTR -> TABLE: the instrument's table when assigned
  call ins_ptr
  ld de, 9
  add hl, de
  ld a, (hl)
  cp $10
  jr nc, sn_tset
  ld (cur_table), a
sn_tset:
  ld a, SCR_TABLE
  jp sn_switch
sn_tochain:
  ; SONG -> CHAIN: chain under cursor, track from column
  ld a, (hdr_cur)
  or a
  ret nz
  call so_cell_ptr
  ld a, (hl)
  cp $FF
  ret z
  ld (cur_chain), a
  ld a, (song_col)
  ld (ed_track), a
  ld a, SCR_CHAIN
sn_switch:
  ld (scr_mode), a
  ld a, 1
  ld (label_dirty), a
  ld hl, drawn_a
  ld a, $FF
  ld (hl), a
  inc hl
  ld (hl), a
  inc hl
  ld (hl), a
  inc hl
  ld (hl), a
  jp mark_all_dirty

; =============================================================
; cursor movement
; =============================================================
cursor_move:
  ld a, (pad_rep)
  and $0F
  ret z
  ld c, a
  ld a, (scr_mode)
  cp SCR_CHAIN
  jp z, cm_chain
  cp SCR_PHRASE
  jp z, cm_phrase
  cp SCR_INSTR
  jp z, cm_instr
  cp SCR_TABLE
  jp z, cm_table
  cp SCR_GROOVE
  jp z, cm_groove

  ; ---- SONG ----
  ld a, (hdr_cur)
  or a
  jr z, cm_sbody
  bit 1, c                   ; down: leave header
  jr z, cm_scol
  xor a
  ld (hdr_cur), a
  ld a, 1
  ld (label_dirty), a
  ld a, (song_cur)
  jp mark_vis_a
cm_sbody:
  bit 1, c                   ; down
  jr z, cm_sup
  ld a, (song_cur)
  cp SONG_ROWS-1
  jr nc, cm_sup
  call so_mark_cur
  ld a, (song_cur)
  inc a
  ld (song_cur), a
  call so_scroll
cm_sup:
  bit 0, c                   ; up
  jr z, cm_scol
  ld a, (song_cur)
  ld b, a
  ld a, (song_view)
  cp b
  jr nz, cm_supgo
  ; at top of view: up enters the header row
  ld a, 1
  ld (hdr_cur), a
  ld (label_dirty), a
  ld a, (song_cur)
  jp mark_vis_a
cm_supgo:
  call so_mark_cur
  ld a, (song_cur)
  dec a
  ld (song_cur), a
  call so_scroll
cm_scol:
  ld a, c
  and PAD_LEFT|PAD_RIGHT
  ret z
  call so_mark_cur
  bit 3, c
  jr z, cm_sleft
  ld a, (song_col)
  inc a
  and $03
  ld (song_col), a
cm_sleft:
  bit 2, c
  jr z, cm_sfin
  ld a, (song_col)
  dec a
  and $03
  ld (song_col), a
cm_sfin:
  ld a, (hdr_cur)
  or a
  jp z, so_mark_cur
  ld a, 1
  ld (label_dirty), a
  ret

  ; ---- CHAIN ----
cm_chain:
  ld a, (chn_row)
  call mark_dirty_a
  bit 1, c
  jr z, cm_cup
  ld a, (chn_row)
  inc a
  and $0F
  ld (chn_row), a
cm_cup:
  bit 0, c
  jr z, cm_ccol
  ld a, (chn_row)
  dec a
  and $0F
  ld (chn_row), a
cm_ccol:
  bit 3, c
  jr z, cm_cleft
  ld a, (chn_col)
  xor 1
  ld (chn_col), a
cm_cleft:
  bit 2, c
  jr z, cm_cfin
  ld a, (chn_col)
  xor 1
  ld (chn_col), a
cm_cfin:
  ld a, (chn_row)
  jp mark_dirty_a

  ; ---- INSTR: up/down over the form fields ----
cm_instr:
  call ins_max_row
  ld b, a
  bit 1, c                   ; down
  jr z, cmi_up
  ld a, (ins_row)
  cp b
  jr nc, cmi_up
  call ins_mark_field
  inc a
  ld (ins_row), a
  call ins_mark_field
cmi_up:
  bit 0, c                   ; up
  ret z
  ld a, (ins_row)
  or a
  ret z
  call ins_mark_field
  dec a
  ld (ins_row), a
  jp ins_mark_field

; mark the grid row of field A dirty (A preserved)
ins_mark_field:
  push hl
  push de
  push af
  call ins_f2r
  call mark_dirty_a
  pop af
  pop de
  pop hl
  ret

; A = field index -> A = grid row (layout depends on type)
ins_f2r:
  push hl
  push de
  ld e, a
  call ins_ptr
  ld a, (hl)
  or a
  ld hl, f2r_tone
  jr z, if2r_go
  ld hl, f2r_noise
if2r_go:
  ld d, 0
  add hl, de
  ld a, (hl)
  pop de
  pop hl
  ret

; ---- TABLE: 4 columns x 16 rows ----
cm_table:
  ld a, (tbl_row)
  call mark_dirty_a
  bit 1, c
  jr z, ct_up
  ld a, (tbl_row)
  inc a
  and $0F
  ld (tbl_row), a
ct_up:
  bit 0, c
  jr z, ct_r
  ld a, (tbl_row)
  dec a
  and $0F
  ld (tbl_row), a
ct_r:
  bit 3, c
  jr z, ct_l
  ld a, (tbl_col)
  inc a
  and $03
  ld (tbl_col), a
ct_l:
  bit 2, c
  jr z, ct_f
  ld a, (tbl_col)
  dec a
  and $03
  ld (tbl_col), a
ct_f:
  ld a, (tbl_row)
  jp mark_dirty_a

; A = last valid field row for the current instrument type
ins_max_row:
  call ins_ptr
  ld a, (hl)
  or a
  ld a, 10                   ; TONE: ...TSP/SWP/VIB/TRM/TBL/TBS
  ret z
  ld a, 12                   ; NOISE: + MODE/RATE
  ret

; HL = current instrument record (preserves DE: callers hold
; the row number in E)
ins_ptr:
  push de
  ld a, (cur_instr)
  add a, a
  add a, a
  add a, a
  add a, a                   ; * 16
  ld e, a
  ld d, 0
  ld hl, instruments
  add hl, de
  pop de
  ret

  ; ---- PHRASE ----
cm_phrase:
  ld a, (phr_row)
  call mark_dirty_a
  bit 1, c
  jr z, cm_pup
  ld a, (phr_row)
  inc a
  and $0F
  ld (phr_row), a
cm_pup:
  bit 0, c
  jr z, cm_pright
  ld a, (phr_row)
  dec a
  and $0F
  ld (phr_row), a
cm_pright:
  bit 3, c
  jr z, cm_pleft
  ld a, (phr_col)
  inc a
  and $03
  ld (phr_col), a
cm_pleft:
  bit 2, c
  jr z, cm_pfin
  ld a, (phr_col)
  dec a
  and $03
  ld (phr_col), a
cm_pfin:
  ld a, (phr_row)
  jp mark_dirty_a

; song-screen scroll bookkeeping after a row move
so_scroll:
  ld a, (song_cur)
  ld b, a
  ld a, (song_view)
  cp b
  jr c, ss_below
  jr z, ss_inview
  ld a, b                    ; cursor above window
  ld (song_view), a
  jp mark_all_dirty
ss_below:
  add a, 15
  cp b
  jr nc, ss_inview
  ld a, b                    ; cursor below window
  sub 15
  ld (song_view), a
  jp mark_all_dirty
ss_inview:
  jp so_mark_cur

; mark the cursor's visible song row dirty
so_mark_cur:
  ld a, (song_cur)
mark_vis_a:                  ; A = absolute song row
  push bc
  ld b, a
  ld a, (song_view)
  ld c, a
  ld a, b
  sub c
  pop bc
  cp 16
  ret nc                     ; off screen
  jp mark_dirty_a

; =============================================================
; press / edit / cut dispatch
; =============================================================
do_press:
  ld a, (scr_mode)
  cp SCR_CHAIN
  jp z, chp_press
  cp SCR_PHRASE
  jp z, php_press
  cp SCR_INSTR
  jp z, inp_press
  cp SCR_TABLE
  jp z, tbp_press
  cp SCR_GROOVE
  jp z, grp_press
  ; ---- SONG ----
  ld a, (hdr_cur)
  or a
  jr z, sop_body
  ; header: mute toggle
  ld a, (song_col)
  call bit_for_a
  ld b, a
  ld a, (mute_flags)
  xor b
  ld (mute_flags), a
  ld a, 1
  ld (label_dirty), a
  ret
sop_body:
  call so_cell_ptr
  ld a, (hl)
  cp $FF
  ret nz
  ld a, (last_chain)
  ld (hl), a
  jp so_mark_cur

do_cut:
  ld a, (scr_mode)
  cp SCR_INSTR
  ret z
  cp SCR_CHAIN
  jp z, chp_cut
  cp SCR_PHRASE
  jp z, php_cut
  cp SCR_TABLE
  jp z, tbp_cut
  cp SCR_GROOVE
  jp z, grp_cut
  ; ---- SONG ----
  ld a, (hdr_cur)
  or a
  jr z, soc_body
  ; header: solo (cut = "cut everything else")
  ld a, (song_col)
  call bit_for_a
  cpl
  and $0F
  ld b, a
  ld a, (mute_flags)
  cp b
  jr nz, soc_solo
  xor a                      ; already solo: unmute all
  jr soc_store
soc_solo:
  ld a, b
soc_store:
  ld (mute_flags), a
  ld a, 1
  ld (label_dirty), a
  ret
soc_body:
  call so_cell_ptr
  ld a, (hl)
  ld (clip_a), a
  ld a, (song_col)
  call clip_set
  ld a, $FF
  ld (hl), a
  jp so_mark_cur

do_edit:
  ld a, (pad_rep)
  and $0F
  ret z
  ld (ed_rep), a
  ld a, (scr_mode)
  cp SCR_CHAIN
  jp z, chp_edit
  cp SCR_PHRASE
  jp z, php_edit
  cp SCR_INSTR
  jp z, inp_edit
  cp SCR_TABLE
  jp z, tbp_edit
  cp SCR_GROOVE
  jp z, grp_edit
  ; ---- SONG: edit chain number ----
  ld a, (hdr_cur)
  or a
  ret nz
  call so_cell_ptr
  ld a, (hl)
  cp $FF
  jr nz, soe_have
  ld a, (last_chain)
soe_have:
  ld d, a
  ld a, (ed_rep)
  ld c, a
  bit 3, c                   ; right +1
  jr z, soe_l
  ld a, d
  cp NUM_CHAINS-1
  jr nc, soe_l
  inc d
soe_l:
  bit 2, c                   ; left -1
  jr z, soe_u
  ld a, d
  or a
  jr z, soe_u
  dec d
soe_u:
  bit 0, c                   ; up +8
  jr z, soe_d
  ld a, d
  add a, 8
  cp NUM_CHAINS
  jr c, soe_ust
  ld a, NUM_CHAINS-1
soe_ust:
  ld d, a
soe_d:
  bit 1, c                   ; down -8
  jr z, soe_store
  ld a, d
  sub 8
  jr nc, soe_dst
  xor a
soe_dst:
  ld d, a
soe_store:
  ld (hl), d
  ld a, d
  ld (last_chain), a
  jp so_mark_cur

; -------------------------------------------------------------
; CHAIN screen handlers
chp_press:
  ld a, (chn_row)
  ld e, a
  call ch_entry_ptr
  ld a, (chn_col)
  or a
  ret nz                     ; transpose column: nothing
  ld a, (hl)
  cp $FF
  ret nz
  ld a, (last_phrase)
  ld (hl), a
  ld a, (chn_row)
  jp mark_dirty_a

chp_cut:
  ld a, (chn_row)
  ld e, a
  call ch_entry_ptr
  ld a, (chn_col)
  or a
  jr nz, chc_tsp
  ld a, (hl)
  ld (clip_a), a
  xor a
  call clip_set
  ld a, $FF
  ld (hl), a
  ld a, (chn_row)
  jp mark_dirty_a
chc_tsp:
  inc hl
  ld a, (hl)
  ld (clip_a), a
  ld a, 1
  call clip_set
  ld (hl), 0
  ld a, (chn_row)
  jp mark_dirty_a

chp_edit:
  ld a, (chn_row)
  ld e, a
  call ch_entry_ptr
  ld a, (chn_col)
  or a
  jr nz, che_tsp
  ; phrase number
  ld a, (hl)
  cp $FF
  jr nz, che_have
  ld a, (last_phrase)
che_have:
  ld d, a
  ld a, (ed_rep)
  ld c, a
  bit 3, c
  jr z, che_l
  ld a, d
  cp NUM_PHRASES-1
  jr nc, che_l
  inc d
che_l:
  bit 2, c
  jr z, che_u
  ld a, d
  or a
  jr z, che_u
  dec d
che_u:
  bit 0, c
  jr z, che_d
  ld a, d
  add a, 8
  cp NUM_PHRASES
  jr c, che_ust
  ld a, NUM_PHRASES-1
che_ust:
  ld d, a
che_d:
  bit 1, c
  jr z, che_store
  ld a, d
  sub 8
  jr nc, che_dst
  xor a
che_dst:
  ld d, a
che_store:
  ld (hl), d
  ld a, d
  ld (last_phrase), a
  ld a, (chn_row)
  jp mark_dirty_a
che_tsp:
  ; transpose: L/R +-1, U/D +-12 (octave), wraps
  inc hl
  ld d, (hl)
  ld a, (ed_rep)
  ld c, a
  bit 3, c
  jr z, cht_l
  inc d
cht_l:
  bit 2, c
  jr z, cht_u
  dec d
cht_u:
  bit 0, c
  jr z, cht_d
  ld a, d
  add a, 12
  ld d, a
cht_d:
  bit 1, c
  jr z, cht_store
  ld a, d
  sub 12
  ld d, a
cht_store:
  ld (hl), d
  ld a, (chn_row)
  jp mark_dirty_a

; -------------------------------------------------------------
; PHRASE screen handlers (note/instr/cmd/param, as milestone 4)
php_press:
  ld a, (phr_row)
  ld e, a
  call ed_step_ptr
  ld a, (phr_col)
  or a
  jr z, dp_note
  cp 1
  jr z, dp_instr
  cp 2
  jr z, dp_cmd
  ret
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
  call mark_phr_dirty
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
  ret c
  ld a, (last_instr)
  ld (hl), a
  jp mark_phr_dirty
dp_cmd:
  inc hl
  inc hl
  ld a, (hl)
  or a
  ret nz
  ld a, CMD_KILL
  ld (hl), a
  jp mark_phr_dirty

php_cut:
  ld a, (phr_row)
  ld e, a
  call ed_step_ptr
  ld a, (phr_col)
  or a
  jr z, dc_note
  cp 1
  jr z, dc_instr
  cp 2
  jr z, dc_cmd
  inc hl
  inc hl
  inc hl
  ld a, (hl)
  ld (clip_a), a
  ld a, 3
  call clip_set
  ld (hl), 0
  jp mark_phr_dirty
dc_note:
  ld a, (hl)
  ld (clip_a), a
  inc hl
  ld a, (hl)
  ld (clip_b), a
  xor a
  call clip_set
  ld (hl), $FF
  dec hl
  ld (hl), 0
  jp mark_phr_dirty
dc_instr:
  inc hl
  ld a, (hl)
  ld (clip_a), a
  ld a, 1
  call clip_set
  ld (hl), $FF
  jp mark_phr_dirty
dc_cmd:
  inc hl
  inc hl
  ld a, (hl)
  ld (clip_a), a
  inc hl
  ld a, (hl)
  ld (clip_b), a
  ld a, 2
  call clip_set
  ld (hl), 0
  dec hl
  ld (hl), 0
  jp mark_phr_dirty

php_edit:
  ld a, (phr_row)
  ld e, a
  call ed_step_ptr
  ld a, (phr_col)
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
  call mark_phr_dirty
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
  jp mark_phr_dirty

de_cmd:
  ld a, (pad_edge)           ; cycle commands on edge only
  and $0F
  ret z
  ld c, a
  inc hl
  inc hl
  ld a, c
  and PAD_RIGHT|PAD_UP
  ld a, (hl)
  jr z, dcm_dn
  inc a
  cp CMD_COUNT
  jr c, dcm_st
  xor a
  jr dcm_st
dcm_dn:
  or a
  jr nz, dcm_dec
  ld a, CMD_COUNT-1
  jr dcm_st
dcm_dec:
  dec a
dcm_st:
  ld (hl), a
  jp mark_phr_dirty

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
  jp mark_phr_dirty

; -------------------------------------------------------------
; INSTR screen handlers
inp_press:                   ; audition the instrument
  ld a, (last_note)
  ld d, a
  ld a, (cur_instr)
  ld c, a
  jp prelisten

inp_edit:
  call ins_ptr
  ld a, (ins_row)
  or a
  jp z, ine_type
  cp 1
  jp z, ine_vol
  cp 2
  jp z, ine_dir
  cp 3
  jp z, ine_spd
  cp 4
  jp z, ine_len
  cp 5
  jp z, ine_tsp
  cp 6
  jp z, ine_swp
  cp 7
  jp z, ine_vib
  cp 8
  jp z, ine_trm
  cp 9
  jp z, ine_tbl
  cp 10
  jp z, ine_tbs
  cp 11
  jp z, ine_mode
  jp ine_rate

; TBL: -- <-> 0..F (down past 0 switches the table off)
ine_tbl:
  ld de, 9
  add hl, de
  ld d, (hl)
  ld a, (ed_rep)
  ld c, a
  and PAD_RIGHT|PAD_UP
  jr z, itb_dn
  ld a, d
  cp $10
  jr c, itb_inc
  ld d, 0                    ; off -> table 0
  jr itb_st
itb_inc:
  cp $0F
  jr nc, itb_st
  inc d
  jr itb_st
itb_dn:
  ld a, c
  and PAD_LEFT|PAD_DOWN
  jr z, itb_st
  ld a, d
  cp $10
  jr nc, itb_st
  or a
  jr nz, itb_dec
  ld d, $FF                  ; below 0 -> off
  jr itb_st
itb_dec:
  dec d
itb_st:
  ld (hl), d
  jp ine_mark

; TBS: ticks per table row, 1-F
ine_tbs:
  ld de, 10
  add hl, de
  ld d, (hl)
  ld a, (ed_rep)
  ld c, a
  and PAD_RIGHT|PAD_UP
  jr z, its_dn
  ld a, d
  cp $0F
  jr nc, its_dn
  inc d
its_dn:
  ld a, c
  and PAD_LEFT|PAD_DOWN
  jr z, its_st
  ld a, d
  cp 2
  jr c, its_st
  dec d
its_st:
  ld (hl), d
  jp ine_mark

; TSP: signed semitones, L/R +-1, U/D +-12 (octave), wraps
ine_tsp:
  ld de, 8
  add hl, de
  ld d, (hl)
  ld a, (ed_rep)
  ld c, a
  bit 3, c
  jr z, int_l
  inc d
int_l:
  bit 2, c
  jr z, int_u
  dec d
int_u:
  bit 0, c
  jr z, int_d
  ld a, d
  add a, 12
  ld d, a
int_d:
  bit 1, c
  jr z, int_st
  ld a, d
  sub 12
  ld d, a
int_st:
  ld (hl), d
  jp ine_mark

; SWP/VIB/TRM: plain hex byte, L/R +-1, U/D +-$10, wraps
ine_swp:
  ld de, 5
  jr ine_bofs
ine_vib:
  ld de, 6
  jr ine_bofs
ine_trm:
  ld de, 7
ine_bofs:
  add hl, de
  ld d, (hl)
  ld a, (ed_rep)
  ld c, a
  bit 3, c
  jr z, inb_l
  inc d
inb_l:
  bit 2, c
  jr z, inb_u
  dec d
inb_u:
  bit 0, c
  jr z, inb_d
  ld a, d
  add a, 16
  ld d, a
inb_d:
  bit 1, c
  jr z, inb_st
  ld a, d
  sub 16
  ld d, a
inb_st:
  ld (hl), d
  jp ine_mark

ine_type:                    ; TONE <-> NOISE (edge-gated)
  ld a, (pad_edge)
  and $0F
  ret z
  ld a, (hl)
  xor 1
  ld (hl), a
  call ins_max_row
  ld b, a
  ld a, (ins_row)
  cp b
  jr c, ine_tym
  ld a, b
  ld (ins_row), a
ine_tym:
  jp mark_all_dirty          ; field set changed

ine_vol:
  inc hl
  ld d, (hl)
  ld a, (ed_rep)
  ld c, a
  bit 3, c
  jr z, inv_l
  ld a, d
  cp $0F
  jr nc, inv_l
  inc d
inv_l:
  bit 2, c
  jr z, inv_u
  ld a, d
  or a
  jr z, inv_u
  dec d
inv_u:
  bit 0, c
  jr z, inv_d
  ld a, d
  add a, 4
  cp $10
  jr c, inv_us
  ld a, $0F
inv_us:
  ld d, a
inv_d:
  bit 1, c
  jr z, inv_st
  ld a, d
  sub 4
  jr nc, inv_ds
  xor a
inv_ds:
  ld d, a
inv_st:
  ld (hl), d
  jp ine_mark

ine_dir:                     ; envelope dir OFF -> DN -> UP
  ld a, (pad_edge)
  and $0F
  ret z
  inc hl
  inc hl
  ld a, (hl)
  and $F0
  rrca
  rrca
  rrca
  rrca
  inc a
  cp 3
  jr c, ind_ok
  xor a
ind_ok:
  rlca
  rlca
  rlca
  rlca
  ld d, a
  ld a, (hl)
  and $0F
  or d
  ld (hl), a
  jp ine_mark

ine_spd:
  inc hl
  inc hl
  ld a, (hl)
  and $0F
  ld d, a
  ld a, (ed_rep)
  ld c, a
  bit 3, c
  jr nz, ins_inc
  bit 0, c
  jr z, ins_dec
ins_inc:
  ld a, d
  cp $0F
  jr nc, ins_dec
  inc d
ins_dec:
  bit 2, c
  jr nz, ins_d2
  bit 1, c
  jr z, ins_st
ins_d2:
  ld a, d
  or a
  jr z, ins_st
  dec d
ins_st:
  ld a, (hl)
  and $F0
  or d
  ld (hl), a
  jp ine_mark

ine_len:
  inc hl
  inc hl
  inc hl
  ld d, (hl)
  ld a, (ed_rep)
  ld c, a
  bit 3, c
  jr z, inl_l
  ld a, d
  cp $3F
  jr nc, inl_l
  inc d
inl_l:
  bit 2, c
  jr z, inl_u
  ld a, d
  or a
  jr z, inl_u
  dec d
inl_u:
  bit 0, c
  jr z, inl_d
  ld a, d
  add a, 8
  cp $40
  jr c, inl_us
  ld a, $3F
inl_us:
  ld d, a
inl_d:
  bit 1, c
  jr z, inl_st
  ld a, d
  sub 8
  jr nc, inl_ds
  xor a
inl_ds:
  ld d, a
inl_st:
  ld (hl), d
  jp ine_mark

ine_mode:                    ; WHITE <-> PERIODIC (edge-gated)
  ld a, (pad_edge)
  and $0F
  ret z
  inc hl
  inc hl
  inc hl
  inc hl
  ld a, (hl)
  xor $04
  ld (hl), a
  jp ine_mark

ine_rate:                    ; 512 -> 1K -> 2K -> PITCH (edge)
  ld a, (pad_edge)
  and $0F
  ret z
  inc hl
  inc hl
  inc hl
  inc hl
  ld a, (hl)
  and $FC
  ld d, a
  ld a, (hl)
  inc a
  and $03
  or d
  ld (hl), a
ine_mark:
  ld a, (ins_row)
  jp ins_mark_field

; -------------------------------------------------------------
; GROOVE screen: one column of tick counts (0 ends the groove)
gr_entry_ptr:                ; E = row -> HL
  ld a, (cur_groove)
  add a, a
  add a, a
  add a, a
  add a, a
  ld d, 0
  add a, e
  ld e, a
  ld hl, grooves
  add hl, de
  ret

cm_groove:
  ld a, (grv_row)
  call mark_dirty_a
  bit 1, c
  jr z, cg_up
  ld a, (grv_row)
  inc a
  and $0F
  ld (grv_row), a
cg_up:
  bit 0, c
  jr z, cg_f
  ld a, (grv_row)
  dec a
  and $0F
  ld (grv_row), a
cg_f:
  ld a, (grv_row)
  jp mark_dirty_a

grp_press:
  ld a, (grv_row)
  ld e, a
  call gr_entry_ptr
  ld a, (hl)
  or a
  ret nz
  ld (hl), 6
  jr gr_mark

grp_cut:
  ld a, (grv_row)
  ld e, a
  call gr_entry_ptr
  ld (hl), 0
gr_mark:
  ld a, (grv_row)
  jp mark_dirty_a

grp_edit:
  ld a, (grv_row)
  ld e, a
  call gr_entry_ptr
  ld d, (hl)
  ld a, (ed_rep)
  ld c, a
  and PAD_RIGHT|PAD_UP
  jr z, gre_dn
  ld a, d
  cp $0F
  jr nc, gre_dn
  inc d
gre_dn:
  ld a, c
  and PAD_LEFT|PAD_DOWN
  jr z, gre_st
  ld a, d
  or a
  jr z, gre_st
  dec d
gre_st:
  ld (hl), d
  jr gr_mark

; -------------------------------------------------------------
; TABLE screen handlers (columns: 0 vol, 1 pitch, 2 cmd, 3 param)
tb_entry_ptr:                ; E = row -> HL = table row
  ld a, (cur_table)
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl                 ; * 64
  ld a, e
  add a, a
  add a, a
  ld e, a
  ld d, 0
  add hl, de
  ld de, tables
  add hl, de
  ret

tbp_press:
  ld a, (tbl_row)
  ld e, a
  call tb_entry_ptr
  ld a, (tbl_col)
  or a
  jr z, tbp_vol
  cp 2
  ret nz
  inc hl
  inc hl
  ld a, (hl)
  or a
  ret nz
  ld a, CMD_KILL
  ld (hl), a
  jr tb_mark
tbp_vol:
  ld a, (hl)
  cp $10
  ret c
  ld a, $0F
  ld (hl), a
tb_mark:
  ld a, (tbl_row)
  jp mark_dirty_a

tbp_cut:
  ld a, (tbl_row)
  ld e, a
  call tb_entry_ptr
  ld a, (tbl_col)
  or a
  jr z, tbc_vol
  cp 1
  jr z, tbc_pitch
  cp 2
  jr z, tbc_cmd
  inc hl
  inc hl
  inc hl
  ld a, (hl)
  ld (clip_a), a
  ld a, 3
  call clip_set
  ld (hl), 0
  jr tb_mark
tbc_vol:
  ld a, (hl)
  ld (clip_a), a
  xor a
  call clip_set
  ld (hl), $FF
  jr tb_mark
tbc_pitch:
  inc hl
  ld a, (hl)
  ld (clip_a), a
  ld a, 1
  call clip_set
  ld (hl), 0
  jr tb_mark
tbc_cmd:
  inc hl
  inc hl
  ld a, (hl)
  ld (clip_a), a
  inc hl
  ld a, (hl)
  ld (clip_b), a
  ld a, 2
  call clip_set
  ld (hl), 0
  dec hl
  ld (hl), 0
  jr tb_mark

tbp_edit:
  ld a, (tbl_row)
  ld e, a
  call tb_entry_ptr
  ld a, (tbl_col)
  or a
  jr z, tbe_vol
  cp 1
  jr z, tbe_pitch
  cp 2
  jp z, tbe_cmd
  ; param: L/R +-1, U/D +-$10
  inc hl
  inc hl
  inc hl
  ld d, (hl)
  ld a, (ed_rep)
  ld c, a
  bit 3, c
  jr z, tep_l
  inc d
tep_l:
  bit 2, c
  jr z, tep_u
  dec d
tep_u:
  bit 0, c
  jr z, tep_d
  ld a, d
  add a, 16
  ld d, a
tep_d:
  bit 1, c
  jr z, tep_st
  ld a, d
  sub 16
  ld d, a
tep_st:
  ld (hl), d
  jp tb_mark

tbe_vol:                     ; nibble, clamp 0-F ($FF base = F)
  ld a, (hl)
  cp $10
  jr c, tev_have
  ld a, $0F
tev_have:
  ld d, a
  ld a, (ed_rep)
  ld c, a
  and PAD_RIGHT|PAD_UP
  jr z, tev_dn
  ld a, d
  cp $0F
  jr nc, tev_dn
  inc d
tev_dn:
  ld a, c
  and PAD_LEFT|PAD_DOWN
  jr z, tev_st
  ld a, d
  or a
  jr z, tev_st
  dec d
tev_st:
  ld (hl), d
  jp tb_mark

tbe_pitch:                   ; signed semitones, U/D = octave
  inc hl
  ld d, (hl)
  ld a, (ed_rep)
  ld c, a
  bit 3, c
  jr z, tpi_l
  inc d
tpi_l:
  bit 2, c
  jr z, tpi_u
  dec d
tpi_u:
  bit 0, c
  jr z, tpi_d
  ld a, d
  add a, 12
  ld d, a
tpi_d:
  bit 1, c
  jr z, tpi_st
  ld a, d
  sub 12
  ld d, a
tpi_st:
  ld (hl), d
  jp tb_mark

tbe_cmd:                     ; cycle the command set (edge-gated)
  ld a, (pad_edge)
  and $0F
  ret z
  ld c, a
  inc hl
  inc hl
  ld a, c
  and PAD_RIGHT|PAD_UP
  ld a, (hl)
  jr z, tcm_dn
  inc a
  cp CMD_COUNT
  jr c, tcm_st
  xor a
  jr tcm_st
tcm_dn:
  or a
  jr nz, tcm_dec
  ld a, CMD_COUNT-1
  jr tcm_st
tcm_dec:
  dec a
tcm_st:
  ld (hl), a
  jp tb_mark

; -------------------------------------------------------------
; clipboard: A = column (preserves HL)
clip_set:
  ld (clip_col), a
  ld a, (scr_mode)
  ld (clip_scr), a
  ret

; double-tap 1: paste the clipboard at the cursor when the
; screen and column context matches the cut
do_paste:
  ld a, (clip_scr)
  ld b, a
  ld a, (scr_mode)
  cp b
  ret nz
  cp SCR_INSTR
  ret z
  ; current column per screen
  or a
  jr nz, dpa_notsong
  ld a, (hdr_cur)
  or a
  ret nz
  ld a, (song_col)
  jr dpa_col
dpa_notsong:
  cp SCR_CHAIN
  jr nz, dpa_nc
  ld a, (chn_col)
  jr dpa_col
dpa_nc:
  cp SCR_PHRASE
  jr nz, dpa_np
  ld a, (phr_col)
  jr dpa_col
dpa_np:
  ld a, (tbl_col)
dpa_col:
  ld b, a
  ld a, (clip_col)
  cp b
  ret nz
  ; dispatch
  ld a, (scr_mode)
  or a
  jr z, dpa_song
  cp SCR_CHAIN
  jr z, dpa_chain
  cp SCR_PHRASE
  jr z, dpa_phrase
  ; ---- TABLE ----
  ld a, (tbl_row)
  ld e, a
  call tb_entry_ptr
  ld a, (clip_col)
  ld e, a
  ld d, 0
  add hl, de                 ; columns are bytes in order
  ld a, (clip_a)
  ld (hl), a
  ld a, (clip_col)
  cp 2
  jr nz, dpa_tbm
  inc hl
  ld a, (clip_b)
  ld (hl), a
dpa_tbm:
  ld a, (tbl_row)
  jp mark_dirty_a
dpa_song:
  call so_cell_ptr
  ld a, (clip_a)
  ld (hl), a
  jp so_mark_cur
dpa_chain:
  ld a, (chn_row)
  ld e, a
  call ch_entry_ptr
  ld a, (clip_col)
  or a
  jr z, dpa_chp
  inc hl
dpa_chp:
  ld a, (clip_a)
  ld (hl), a
  ld a, (chn_row)
  jp mark_dirty_a
dpa_phrase:
  ld a, (phr_row)
  ld e, a
  call ed_step_ptr
  ld a, (clip_col)
  or a
  jr z, dpa_pnote
  ld e, a
  ld d, 0
  add hl, de
  ld a, (clip_a)
  ld (hl), a
  ld a, (clip_col)
  cp 2
  jr nz, dpa_phm
  inc hl
  ld a, (clip_b)
  ld (hl), a
dpa_phm:
  jp mark_phr_dirty
dpa_pnote:
  ld a, (clip_a)
  ld (hl), a
  inc hl
  ld a, (clip_b)
  ld (hl), a
  call mark_phr_dirty
  ; audition the pasted note
  ld a, (clip_a)
  or a
  ret z
  ld d, a
  ld a, (clip_b)
  cp $10
  jr c, dpa_pl
  ld a, (last_instr)
dpa_pl:
  ld c, a
  jp prelisten

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
  add a, a
  add a, a
  add a, a                   ; * 32 (struct stride)
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

; =============================================================
; pointers & dirty bookkeeping
; =============================================================
; HL = &song[song_cur][song_col]
so_cell_ptr:
  ld a, (song_cur)
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl                 ; * 4
  ld a, (song_col)
  ld e, a
  ld d, 0
  add hl, de
  ld de, song
  add hl, de
  ret

; E = chain row -> HL = &chains[cur_chain][E]
ch_entry_ptr:
  ld a, (cur_chain)
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl                 ; * 32
  ld a, e
  add a, a
  ld e, a
  ld d, 0
  add hl, de
  ld de, chains
  add hl, de
  ret

; E = phrase row -> HL = step address in cur_phrase
ed_step_ptr:
  ld a, (cur_phrase)
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl                 ; * 64
  ld a, e
  add a, a
  add a, a                   ; * 4
  ld e, a
  ld d, 0
  add hl, de
  ld de, phrase_pool
  add hl, de
  ret

; A = track (0-3) -> A = bit mask
bit_for_a:
  ld b, a
  ld a, 1
  inc b
bfa_l:
  dec b
  ret z
  add a, a
  jr bfa_l

mark_phr_dirty:
  ld a, (phr_row)
mark_dirty_a:                ; A = visible row (preserves HL/DE)
  push hl
  push de
  ld hl, dirty_rows
  ld e, a
  ld d, 0
  add hl, de
  ld (hl), 1
  pop de
  pop hl
  ret

mark_all_dirty:
  ld hl, dirty_rows
  ld b, 16
mad_l:
  ld (hl), 1
  inc hl
  djnz mad_l
  ret

; =============================================================
; drawing
; =============================================================
editor_draw:
  ; label frames are expensive: drop the row budget to 1 so the
  ; VRAM burst stays inside VBlank (writes that spill into the
  ; active display get dropped -> white garbage blocks)
  ld a, (label_dirty)
  or a
  jr z, edr_nolbl
  call draw_labels
  call playhead_update
  ld d, 1
  jr edr_flush0
edr_nolbl:
  call playhead_update
  ld d, 3                    ; rows-per-frame budget
edr_flush0:
  ld e, 0                    ; row
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
  call draw_row
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

draw_row:
  ; wipe the full row first: screens use different columns, so
  ; switching would otherwise leave stale fields behind
  push de
  xor a
  ld (text_attr), a
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, 1
  ld hl, str_blank
  call print_at
  pop de
  ld a, (scr_mode)
  cp SCR_CHAIN
  jp z, ch_draw_row
  cp SCR_PHRASE
  jp z, ph_draw_row
  cp SCR_INSTR
  jp z, in_draw_row
  cp SCR_TABLE
  jp z, tb_draw_row
  cp SCR_GROOVE
  jp z, gr_draw_row
  jp so_draw_row

; -------------------------------------------------------------
; playhead bookkeeping: compare engine position against what is
; highlighted, mark changed rows dirty
playhead_update:
  ld a, (scr_mode)
  cp SCR_INSTR
  ret z                      ; no playhead on the form screen
  cp SCR_GROOVE
  jr z, pu_groove
  cp SCR_TABLE
  jr z, pu_table
  or a
  jp z, pu_song
  cp SCR_CHAIN
  jp z, pu_chain

  ; PHRASE: playing row if our phrase is sounding on ed_track
  call ed_chst
  ld b, $FF
  ld a, (play_state)
  or a
  jr z, pu_ph_set
  ld a, (ix+10)
  ld c, a
  ld a, (cur_phrase)
  cp c
  jr nz, pu_ph_set
  ld a, (cur_row)
  ld b, a
pu_ph_set:
  ld a, (drawn_a)
  cp b
  ret z
  cp $FF
  jr z, pu_ph_new
  call mark_dirty_a
pu_ph_new:
  ld a, b
  ld (drawn_a), a
  cp $FF
  ret z
  jp mark_dirty_a

pu_groove:
  ; GROOVE: position within the selected groove while playing
  ld b, $FF
  ld a, (play_state)
  or a
  jr z, pug_set
  ld a, (groove_sel)
  ld c, a
  ld a, (cur_groove)
  cp c
  jr nz, pug_set
  ld a, (groove_pos)
  ld b, a
pug_set:
  jp pu_ph_set

pu_table:
  ; TABLE: playing row if our table runs on the edited track
  call ed_chst
  ld b, $FF
  ld a, (play_state)
  or a
  jr z, pu_ph_set
  ld a, (ix+20)
  ld c, a
  ld a, (cur_table)
  cp c
  jr nz, pu_ph_set
  ld b, (ix+21)
  jr pu_ph_set

pu_chain:
  ; CHAIN: playing step if our chain is active on ed_track
  call ed_chst
  ld b, $FF
  ld a, (play_state)
  or a
  jr z, pu_ch_set
  ld a, (ix+6)
  or a
  jr z, pu_ch_set
  ld a, (ix+11)
  ld c, a
  ld a, (cur_chain)
  cp c
  jr nz, pu_ch_set
  ld a, (ix+8)
  ld b, a
pu_ch_set:
  ld a, (drawn_a)
  cp b
  ret z
  cp $FF
  jr z, pu_ch_new
  call mark_dirty_a
pu_ch_new:
  ld a, b
  ld (drawn_a), a
  cp $FF
  ret z
  jp mark_dirty_a

pu_song:
  ; SONG: one playhead per track (absolute song rows)
  ld ix, chst
  ld hl, drawn_a
  ld c, 4
pu_so_l:
  ld b, $FF
  ld a, (play_state)
  or a
  jr z, pu_so_cmp
  ld a, (eng_mode)
  cp MODE_SONG
  jr nz, pu_so_cmp
  ld a, (ix+6)
  or a
  jr z, pu_so_cmp
  ld b, (ix+7)
pu_so_cmp:
  ld a, (hl)
  cp b
  jr z, pu_so_next
  cp $FF
  jr z, pu_so_new
  push bc
  call mark_vis_a
  pop bc
pu_so_new:
  ld (hl), b
  ld a, b
  cp $FF
  jr z, pu_so_next
  push bc
  call mark_vis_a
  pop bc
pu_so_next:
  inc hl
  ld de, 32
  add ix, de
  dec c
  jr nz, pu_so_l
  ret

; IX = chst struct of the edited track
ed_chst:
  ld a, (ed_track)
  add a, a
  add a, a
  add a, a
  add a, a
  add a, a                   ; * 32 (struct stride)
  ld e, a
  ld d, 0
  ld ix, chst
  add ix, de
  ret

; -------------------------------------------------------------
; labels: screen name + context (row 1), column headers (row 3)
draw_labels:
  xor a
  ld (label_dirty), a
  ld (text_attr), a
  ; wipe both lines
  ld b, 1
  ld c, 1
  ld hl, str_blank
  call print_at
  ld b, 3
  ld c, 1
  ld hl, str_blank
  call print_at
  call draw_scrmap

  ld a, (scr_mode)
  cp SCR_CHAIN
  jp z, dl_chain
  cp SCR_PHRASE
  jp z, dl_phrase
  cp SCR_INSTR
  jp z, dl_instr
  cp SCR_TABLE
  jp z, dl_table
  cp SCR_GROOVE
  jp z, dl_groove

  ; ---- SONG ----
  ld b, 1
  ld c, 1
  ld hl, str_song
  call print_at
  ; track headers with mute state, cursor when in header
  ld c, 0                    ; track
dl_so_hdr:
  push bc
  ; attr: cursor on header?
  xor a
  ld (text_attr), a
  ld a, (hdr_cur)
  or a
  jr z, dl_so_attr
  ld a, (song_col)
  cp c
  jr nz, dl_so_attr
  ld a, $08
  ld (text_attr), a
dl_so_attr:
  ; name or ".." when muted
  ld a, (song_col)           ; (reuse C before it is clobbered)
  ld a, (mute_flags)
  ld d, a
  ld a, c
  call bit_for_a
  and d
  jr z, dl_so_name
  ld hl, str_muted
  jr dl_so_pr
dl_so_name:
  ld a, c
  add a, a
  ld e, a
  ld d, 0
  ld hl, track_names
  add hl, de
dl_so_pr:
  push hl
  ld a, c
  call so_track_col
  ld c, a
  ld b, 3
  call nt_addr_hl
  call vdp_set_addr
  pop hl
  ld b, 2
  call print_raw
  pop bc
  inc c
  ld a, c
  cp 4
  jr c, dl_so_hdr
  xor a
  ld (text_attr), a
  ret

dl_chain:
  ld b, 1
  ld c, 1
  ld hl, str_chain
  call print_at
  ld b, 1
  ld c, 7
  call nt_addr_hl
  call vdp_set_addr
  ld a, (cur_chain)
  call print_hex_a
  call dl_track_tag
  ld b, 3
  ld c, 4
  ld hl, str_hphr
  call print_at
  ld b, 3
  ld c, 8
  ld hl, str_htsp
  call print_at
  ret

dl_phrase:
  ld b, 1
  ld c, 1
  ld hl, str_phrase
  call print_at
  ld b, 1
  ld c, 8
  call nt_addr_hl
  call vdp_set_addr
  ld a, (cur_phrase)
  call print_hex_a
  call dl_track_tag
  ld b, 3
  ld c, 4
  ld hl, str_hnote
  call print_at
  ld b, 3
  ld c, 9
  ld hl, str_hinstr
  call print_at
  ld b, 3
  ld c, 12
  ld hl, str_hcmd
  call print_at
  ret

dl_groove:
  ld b, 1
  ld c, 1
  ld hl, str_grv
  call print_at
  ld b, 1
  ld c, 8
  call nt_addr_hl
  call vdp_set_addr
  ld a, (cur_groove)
  call print_hex_a
  ld b, 3
  ld c, 4
  ld hl, str_htik
  call print_at
  ret

dl_table:
  ld b, 1
  ld c, 1
  ld hl, str_tabl
  call print_at
  ld b, 1
  ld c, 7
  call nt_addr_hl
  call vdp_set_addr
  ld a, (cur_table)
  call print_hex_a
  ld b, 3
  ld c, 4
  ld hl, str_hv
  call print_at
  ld b, 3
  ld c, 7
  ld hl, str_hpit
  call print_at
  ld b, 3
  ld c, 11
  ld hl, str_hcmd
  call print_at
  ret

dl_instr:
  ld b, 1
  ld c, 1
  ld hl, str_instr
  call print_at
  ld b, 1
  ld c, 7
  call nt_addr_hl
  call vdp_set_addr
  ld a, (cur_instr)
  jp print_hex_a

; "Tn" tag at row 1 col 12
dl_track_tag:
  ld a, (ed_track)
  add a, a
  ld e, a
  ld d, 0
  ld hl, track_names
  add hl, de
  push hl
  ld b, 1
  ld c, 12
  call nt_addr_hl
  call vdp_set_addr
  pop hl
  ld b, 2
  jp print_raw

; screen map indicator, top right: current screen inverted.
; grows to S C P I T (+ project/groove) as screens are added.
draw_scrmap:
  ld d, 0                    ; screen index
dsm_l:
  ld a, (scr_mode)
  cp d
  ld a, $00
  jr nz, dsm_attr
  ld a, $08
dsm_attr:
  ld (text_attr), a
  ld a, d
  add a, 27
  ld c, a
  ld b, 4
  push de
  call nt_addr_hl
  call vdp_set_addr
  pop de
  push de
  ld e, d
  ld d, 0
  ld hl, map_letters
  add hl, de
  ld a, (hl)
  call print_char
  pop de
  inc d
  ld a, d
  cp 6
  jr c, dsm_l
  xor a
  ld (text_attr), a
  ret
map_letters:
  .db "SCPITG"

; A = track -> A = screen column of its song-screen cell
so_track_col:
  add a, a
  ld e, a
  ld d, 0
  ld hl, so_cols
  add hl, de
  ld a, (hl)
  ret
so_cols:
  .db 5, 0, 11, 0, 17, 0, 23, 0

; -------------------------------------------------------------
; SONG screen row (E = visible row 0-15)
so_draw_row:
  ; absolute row
  ld a, (song_view)
  add a, e
  ld (tmp_note), a           ; tmp_note = absolute song row
  ; label
  xor a
  ld (text_attr), a
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, 1
  push de
  call nt_addr_hl
  call vdp_set_addr
  pop de
  ld a, (tmp_note)
  push de
  call print_hex_a
  pop de
  ; four chain cells
  ld c, 0
sdr_cell:
  push bc
  push de
  ; attr: cursor first, then playhead
  xor a
  ld (text_attr), a
  ld a, (hdr_cur)
  or a
  jr nz, sdr_ph              ; cursor is on the header
  ld a, (song_col)
  cp c
  jr nz, sdr_ph
  ld a, (song_cur)
  ld b, a
  ld a, (tmp_note)
  cp b
  jr nz, sdr_ph
  ld a, $08
  ld (text_attr), a
  jr sdr_val
sdr_ph:
  ld hl, drawn_a
  ld b, 0
  add hl, bc
  ld a, (hl)
  ld b, a
  ld a, (tmp_note)
  cp b
  jr nz, sdr_val
  ld a, $08
  ld (text_attr), a
sdr_val:
  ; cell value
  ld a, (tmp_note)
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl
  ld b, 0
  add hl, bc
  ld de, song
  add hl, de
  ld a, (hl)
  ld (tmp_instr), a          ; cell value
  ; position
  ld a, c
  call so_track_col
  ld c, a
  pop de
  push de
  ld a, e
  add a, GRID_ROW
  ld b, a
  push af
  call nt_addr_hl
  call vdp_set_addr
  pop af
  ld a, (tmp_instr)
  cp $FF
  jr nz, sdr_hex
  ld a, '-'
  call print_char
  ld a, '-'
  call print_char
  jr sdr_next
sdr_hex:
  call print_hex_a
sdr_next:
  pop de
  pop bc
  inc c
  ld a, c
  cp 4
  jr c, sdr_cell
  ret

; -------------------------------------------------------------
; CHAIN screen row (E = row)
ch_draw_row:
  ; label, inverted at the playing chain step
  xor a
  ld (text_attr), a
  ld a, (drawn_a)
  cp e
  jr nz, cdr_lbl
  ld a, $08
  ld (text_attr), a
cdr_lbl:
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
  ; entry
  push de
  call ch_entry_ptr
  pop de
  ld a, (hl)
  ld (tmp_note), a           ; phrase #
  inc hl
  ld a, (hl)
  ld (tmp_instr), a          ; transpose
  ; phrase cell (col 4)
  xor a
  call ch_field_attr
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, 4
  push de
  call nt_addr_hl
  call vdp_set_addr
  pop de
  ld a, (tmp_note)
  cp $FF
  jr nz, cdr_phex
  ld a, '-'
  push de
  call print_char
  ld a, '-'
  call print_char
  pop de
  jr cdr_tsp
cdr_phex:
  push de
  call print_hex_a
  pop de
cdr_tsp:
  ; transpose cell (col 8)
  ld a, 1
  call ch_field_attr
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, 8
  push de
  call nt_addr_hl
  call vdp_set_addr
  pop de
  ld a, (tmp_instr)
  push de
  call print_hex_a
  pop de
  ret

; -------------------------------------------------------------
; TABLE screen row (E = row)
tb_draw_row:
  xor a
  ld (text_attr), a
  ld a, (drawn_a)
  cp e
  jr nz, tdr_lbl
  ld a, $08
  ld (text_attr), a
tdr_lbl:
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
  ; fetch row
  push de
  call tb_entry_ptr
  pop de
  ld a, (hl)
  ld (tmp_note), a           ; vol
  inc hl
  ld a, (hl)
  ld (tmp_instr), a          ; pitch
  inc hl
  ld a, (hl)
  ld (tmp_cmd), a
  inc hl
  ld a, (hl)
  ld (tmp_param), a
  ; vol (1 char, col 4)
  xor a
  call tb_field_attr
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, 4
  push de
  call nt_addr_hl
  call vdp_set_addr
  pop de
  ld a, (tmp_note)
  cp $10
  jr nc, tdr_vdash
  push de
  call print_hex_nib
  pop de
  jr tdr_pitch
tdr_vdash:
  ld a, '-'
  push de
  call print_char
  pop de
tdr_pitch:
  ; pitch (2 chars, col 7)
  ld a, 1
  call tb_field_attr
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, 7
  push de
  call nt_addr_hl
  call vdp_set_addr
  pop de
  ld a, (tmp_instr)
  push de
  call print_hex_a
  pop de
  ; cmd (1 char, col 11)
  ld a, 2
  call tb_field_attr
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, 11
  push de
  call nt_addr_hl
  call vdp_set_addr
  pop de
  ld a, (tmp_cmd)
  call cmd_char
tdr_cpr:
  push de
  call print_char
  pop de
  ; param (2 chars, col 12)
  ld a, 3
  call tb_field_attr
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
  jr z, tdr_pdash
  ld a, (tmp_param)
  push de
  call print_hex_a
  pop de
  ret
tdr_pdash:
  ld a, '-'
  push de
  call print_char
  ld a, '-'
  call print_char
  pop de
  ret

; -------------------------------------------------------------
; GROOVE screen row (E = row)
gr_draw_row:
  xor a
  ld (text_attr), a
  ld a, (drawn_a)
  cp e
  jr nz, gdr_lbl
  ld a, $08
  ld (text_attr), a
gdr_lbl:
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
  ; tick value, cursor-inverted
  xor a
  ld (text_attr), a
  ld a, (grv_row)
  cp e
  jr nz, gdr_val
  ld a, $08
  ld (text_attr), a
gdr_val:
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, 4
  push de
  call nt_addr_hl
  call vdp_set_addr
  pop de
  push de
  call gr_entry_ptr
  pop de
  ld a, (hl)
  or a
  jr z, gdr_dash
  push de
  call print_hex_nib
  pop de
  ret
gdr_dash:
  ld a, '-'
  push de
  call print_char
  pop de
  ret

; A = column id, E = row: text_attr for the table screen
tb_field_attr:
  ld d, a
  ld a, (tbl_row)
  cp e
  jr nz, tfa_norm
  ld a, (tbl_col)
  cp d
  jr nz, tfa_norm
  ld a, $08
  jr tfa_set
tfa_norm:
  xor a
tfa_set:
  ld (text_attr), a
  ret

; A = column id, E = row: text_attr for the chain screen
ch_field_attr:
  ld d, a
  ld a, (chn_row)
  cp e
  jr nz, cfa_norm
  ld a, (chn_col)
  cp d
  jr nz, cfa_norm
  ld a, $08
  jr cfa_set
cfa_norm:
  xor a
cfa_set:
  ld (text_attr), a
  ret

; -------------------------------------------------------------
; PHRASE screen row (E = row), as milestone 4
ph_draw_row:
  xor a
  ld (text_attr), a
  ld a, (drawn_a)
  cp e
  jr nz, pdr_lbl
  ld a, $08
  ld (text_attr), a
pdr_lbl:
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

  ; note (3 chars, col 4)
  xor a
  call ph_field_attr
  ld a, (tmp_note)
  or a
  jr nz, pdr_name
  ld hl, str_rest
  jr pdr_npr
pdr_name:
  dec a
  ld l, a
  add a, a
  add a, l
  push de
  ld e, a
  ld d, 0
  ld hl, note_names
  add hl, de
  pop de
pdr_npr:
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

  ; instrument (1 char, col 9)
  ld a, 1
  call ph_field_attr
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
  jr c, pdr_ihex
  ld a, '-'
  push de
  call print_char
  pop de
  jr pdr_cmd
pdr_ihex:
  push de
  call print_hex_nib
  pop de

pdr_cmd:
  ; command (1 char, col 12)
  ld a, 2
  call ph_field_attr
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, 12
  push de
  call nt_addr_hl
  call vdp_set_addr
  pop de
  ld a, (tmp_cmd)
  call cmd_char
pdr_cpr:
  push de
  call print_char
  pop de

  ; param (2 chars, col 13)
  ld a, 3
  call ph_field_attr
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
  jr z, pdr_pdash
  ld a, (tmp_param)
  push de
  call print_hex_a
  pop de
  ret
pdr_pdash:
  ld a, '-'
  push de
  call print_char
  ld a, '-'
  call print_char
  pop de
  ret

; -------------------------------------------------------------
; INSTR screen: form rows (E = grid row), fields grouped with
; blank spacer rows between sections:
;   TYPE/VOL | ENV/SPD/LEN | TSP | SWP/VIB/TRM | MODE/RATE
in_draw_row:
  ; grid row -> field index ($FF = spacer row)
  push de
  call ins_ptr
  ld a, (hl)
  or a
  ld hl, r2f_tone
  jr z, idr_map
  ld hl, r2f_noise
idr_map:
  ld d, 0
  add hl, de
  ld a, (hl)
  pop de
  cp $FF
  ret z
  ld (ed_field), a
  ld b, a
  call ins_max_row           ; (preserves DE and B)
  cp b
  ret c                      ; field beyond this type's form
  ; label (col 4)
  xor a
  ld (text_attr), a
  ld a, (ed_field)
  ld d, a
  add a, a
  add a, a
  add a, d                   ; * 5 ("XXXX",0 entries)
  push de
  ld e, a
  ld d, 0
  ld hl, ins_lbls
  add hl, de
  pop de
  push hl
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, 4
  pop hl
  push de
  call print_at
  pop de
  ; value attr: inverted under the cursor
  xor a
  ld (text_attr), a
  ld a, (ins_row)
  ld d, a
  ld a, (ed_field)
  cp d
  jr nz, idr_addr
  ld a, $08
  ld (text_attr), a
idr_addr:
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, 10
  push de
  call nt_addr_hl
  call vdp_set_addr
  pop de
  ; value per field
  push de
  call ins_ptr
  pop de
  ld a, (ed_field)
  or a
  jp z, idr_type
  cp 1
  jp z, idr_vol
  cp 2
  jp z, idr_dir
  cp 3
  jp z, idr_spd
  cp 4
  jp z, idr_len
  cp 5
  jp z, idr_tsp
  cp 6
  jp z, idr_swp
  cp 7
  jp z, idr_vib
  cp 8
  jp z, idr_trm
  cp 9
  jp z, idr_tbl
  cp 10
  jp z, idr_tbs
  cp 11
  jp z, idr_mode
  jp idr_rate
idr_skip:
  ret
idr_tbl:
  ld de, 9
  add hl, de
  ld a, (hl)
  cp $10
  jp c, print_hex_nib
  ld a, '-'
  jp print_char
idr_tbs:
  ld de, 10
  add hl, de
  ld a, (hl)
  jp print_hex_nib
idr_tsp:
  ld de, 8
  jr idr_bhex
idr_swp:
  ld de, 5
  jr idr_bhex
idr_vib:
  ld de, 6
  jr idr_bhex
idr_trm:
  ld de, 7
idr_bhex:
  add hl, de
  ld a, (hl)
  jp print_hex_a
idr_type:
  ld a, (hl)
  or a
  ld hl, str_tone
  jr z, idr_p5
  ld hl, str_noise
idr_p5:
  ld b, 5
  jp print_raw
idr_vol:
  inc hl
  ld a, (hl)
  jp print_hex_nib
idr_dir:
  inc hl
  inc hl
  ld a, (hl)
  and $F0
  cp $20
  ld hl, str_edn
  jr nz, idr_p3
  ld hl, str_eup
idr_p3:
  ld b, 3
  jp print_raw
idr_spd:
  inc hl
  inc hl
  ld a, (hl)
  jp print_hex_nib
idr_len:
  inc hl
  inc hl
  inc hl
  ld a, (hl)
  jp print_hex_a
idr_mode:
  inc hl
  inc hl
  inc hl
  inc hl
  ld a, (hl)
  and $04
  ld hl, str_perio
  jr z, idr_p5b
  ld hl, str_white
idr_p5b:
  ld b, 5
  jp print_raw
idr_rate:
  inc hl
  inc hl
  inc hl
  inc hl
  ld a, (hl)
  and $03
  ld d, a
  add a, a
  add a, a
  add a, d                   ; * 5
  ld e, a
  ld d, 0
  ld hl, str_rates
  add hl, de
  ld b, 5
  jp print_raw

; field index -> grid row (groups separated by spacer rows);
; noise packs tighter to fit MODE/RATE in 16 rows
f2r_tone:
  .db 0, 1, 3, 4, 5, 7, 9, 10, 11, 13, 14
f2r_noise:
  .db 0, 1, 3, 4, 5, 7, 8, 9, 10, 12, 13, 14, 15
; grid row -> field index ($FF = spacer)
r2f_tone:
  .db 0, 1, $FF, 2, 3, 4, $FF, 5, $FF, 6, 7, 8, $FF, 9, 10, $FF
r2f_noise:
  .db 0, 1, $FF, 2, 3, 4, $FF, 5, 6, 7, 8, $FF, 9, 10, 11, 12

ins_lbls:
  .db "TYPE", 0
  .db "VOL ", 0
  .db "ENV ", 0
  .db "SPD ", 0
  .db "LEN ", 0
  .db "TSP ", 0
  .db "SWP ", 0
  .db "VIB ", 0
  .db "TRM ", 0
  .db "TBL ", 0
  .db "TBS ", 0
  .db "MODE", 0
  .db "RATE", 0
str_tone:   .db "TONE "
str_noise:  .db "NOISE"
str_white:  .db "WHITE"
str_perio:  .db "PERIO"
str_eoff:   .db "OFF"
str_edn:    .db "DN "
str_eup:    .db "UP "
str_rates:
  .db "512  "
  .db "1K   "
  .db "2K   "
  .db "PITCH"

ph_field_attr:
  ld d, a
  ld a, (phr_row)
  cp e
  jr nz, pfa_norm
  ld a, (phr_col)
  cp d
  jr nz, pfa_norm
  ld a, $08
  jr pfa_set
pfa_norm:
  xor a
pfa_set:
  ld (text_attr), a
  ret

; -------------------------------------------------------------
; A = command id -> A = display letter
cmd_char:
  cp CMD_COUNT
  jr c, cch_ok
  xor a
cch_ok:
  push hl
  push de
  ld e, a
  ld d, 0
  ld hl, cmd_chars
  add hl, de
  ld a, (hl)
  pop de
  pop hl
  ret
cmd_chars:
  .db "-KHACEFGNPTVWMDLR"

str_song:        .db "SONG", 0
str_chain:       .db "CHAIN", 0
str_phrase:      .db "PHRASE", 0
str_instr:       .db "INSTR", 0
str_tabl:        .db "TABLE", 0
str_grv:         .db "GROOVE", 0
str_htik:        .db "TIK", 0
str_hv:          .db "V", 0
str_hpit:        .db "PIT", 0
str_hphr:        .db "PHR", 0
str_htsp:        .db "TSP", 0
str_hnote:       .db "NOTE", 0
str_hinstr:      .db "I", 0
str_hcmd:        .db "CMD", 0
str_blank:       .db "                          ", 0
str_muted:       .db ".."
track_names:
  .db "T1T2T3NO"

.ENDS
