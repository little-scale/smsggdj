; =============================================================
; SMSDJ - editor: SONG / CHAIN / PHRASE screens (milestone 5)
;
; Screen map (design doc section 4, subset implemented):
;   [SONG] <-> [CHAIN] <-> [PHRASE]      (2 held + left/right)
; Context flows right: entering CHAIN opens the chain under the
; SONG cursor (and selects its track); entering PHRASE opens the
; phrase under the CHAIN cursor.
;
; Common controls (held-state disambiguation, no timing windows):
;   dpad           cursor       1 tap          insert/audition
;   1 + dpad       edit         1H + 2 tap     cut field
;   2H + 1 tap     play/stop    1H + 2 held    block SELECT
;   1 double-tap   paste        2H + dpad      screen map
; SELECT mode (SONG/CHAIN/PHRASE/TABLE): dpad extends the box,
;   1 tap copies, 1H + 2 cuts, 2 alone cancels. Paste anchors at
;   the cursor row; columns stay where they were cut.
; SONG screen: header row is labels only (mute/solo parked -
;   gesture TBD). LIVE: transport on the playing cell = kill.
; =============================================================

.DEFINE DT_WINDOW    15        ; frames: double-tap window
.DEFINE SEL_HOLD     16        ; frames: 1H+2 held = block select
.DEFINE PRELISTEN_LEN 32       ; ticks: cap sustained prelisten

.DEFINE SCR_SONG    0          ; values match MODE_* on purpose
.DEFINE SCR_CHAIN   1
.DEFINE SCR_PHRASE  2
.DEFINE SCR_INSTR   3
.DEFINE SCR_TABLE   4
.DEFINE SCR_GROOVE  5
.DEFINE SCR_PROJ    6
.DEFINE SCR_WAVE    7
.DEFINE SCR_SET     8         ; OPTIONS, above SONG
.DEFINE SCR_ECHO    9         ; ECHO, below INSTR
.DEFINE SCR_FILES   10        ; FILES, below SONG (slot manager)
.DEFINE FILES_SLOTS    12     ; visible slot rows (scrolls; directory holds 32)
.DEFINE FILES_LIST_TOP 2      ; the list starts this many rows below the header

; screen-map indicator position (SMS: far-right margin past the
; grid; GG: the free right columns of the 20-wide window)
.IFDEF TARGET_GG
.DEFINE MAP_COL     15
.DEFINE MAP_ROW     2
.DEFINE INS_LBL     2        ; form label/value cols (INSTR/OPTIONS/PROJECT),
.DEFINE INS_VAL     8        ; shifted left on GG to clear the map at MAP_COL 15
.DEFINE PH_INS_COL  9        ; PHRASE columns shifted +1 to gap NOTE/I
.DEFINE PH_CMD_COL  11
.ELSE
.DEFINE MAP_COL     25
.DEFINE MAP_ROW     4
.DEFINE INS_LBL     4
.DEFINE INS_VAL     10
.DEFINE PH_INS_COL  9        ; PHRASE columns shifted +1 to gap NOTE/I
.DEFINE PH_CMD_COL  11
.ENDIF

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
  cur_wave     db
  wav_col      db
  wv_preset    db
  prj_row      db
  stg_row      db            ; SETTINGS cursor field
  ech_row      db            ; ECHO cursor field
  files_row    db            ; FILES slot cursor (absolute, 0..directory max)
  files_view   db            ; FILES top visible slot (scroll offset)
  fl_slot      db            ; FILES draw scratch: absolute slot of the drawn row
  name_col     db            ; FILES name-edit cursor (0..7)
  fmenu        db            ; FILES action menu: 0 = slots, 1 = menu open
  fmsel        db            ; FILES menu selection (0..5 = SAVE/LOAD/CLEA/PRGP/PRGC/CANC)
  file_count   db            ; FILES: number of saved songs (directory kept packed)
  file_room    db            ; FILES: 1 = room for one more (trailing empty shown)
  prj_stat     db            ; 0 - / 1 saved / 2 loaded / 3 no sram / 4 no data
  proj_bpm     db
  prj_slot     db            ; save slot 0..sram_slots-1
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
  last_cmd     db
  last_chain   db
  last_phrase  db
  dt1_timer    db            ; double-tap countdown
  dt1_fresh    db            ; first tap filled an empty cell
  tp_dt        db            ; transport double-tap countdown (2-held + double-1)
  new_arm      db            ; PROJECT NEW: first press arms
  clone_deep   db            ; 0 = SLIM clone, 1 = DEEP
  cur_flash    db            ; cursor blink frames (clone-fail)
  clip_scr     db            ; clipboard: screen ($FF = empty)
  clip_col     db            ;   column
  clip_a       db            ;   primary byte
  clip_b       db            ;   secondary byte
  selhold      db            ; 1H+2 hold countdown (0 = idle)
  sel_active   db            ; 1 = SELECT mode
  sel_1press   db            ; 1 pressed in-mode (copy on release)
  sel_arow     db            ; anchor (row is absolute on SONG)
  sel_acol     db
  sel_r0       db            ; normalized box, inclusive
  sel_r1       db
  sel_c0       db
  sel_c1       db
  blk_scr      db            ; block clipboard: screen ($FF none)
  blk_c0       db            ;   origin column
  blk_w        db
  blk_h        db
  blk_data     dsb 64        ;   up to 4 cols x 16 rows
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
  ld a, CMD_KILL             ; first command insert defaults to K
  ld (last_cmd), a
  xor a
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
  ld (cur_wave), a
  ld (wav_col), a
  ld (wv_preset), a
  ld (prj_row), a
  ld (prj_stat), a
  ld (prj_slot), a
  ld (dt1_timer), a
  ld (selhold), a
  ld (sel_active), a
  ld a, $FF
  ld (clip_scr), a
  ld (blk_scr), a
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
  ;   1 while 2 held = transport   2 while 1 held = cut/select
  ;   1 alone = insert/audition    1 double-tap = paste
  ; an active block selection owns all the buttons
  ld a, (sel_active)
  or a
  jp nz, sel_input
  ; ---- button 1 pressed ----
  ld a, (pad_edge)
  and PAD_B1
  jr z, ei_no1
  ld a, (pad_raw)
  and PAD_B2
  jr z, ei_1alone
  ld a, (scr_mode)           ; 2 held + 1
  cp SCR_FILES
  jr nz, ei_toggle
  call fc_files              ; FILES: 2+1 toggles the action menu (no playback here)
  jp ei_dtick
ei_toggle:
  ld a, (tp_dt)              ; 2-held + double-tap-1: play the whole SONG from the
  or a                       ;   contextual row (hear a phrase/chain in arrangement
  jr nz, ei_tsong            ;   context). Single tap = the per-screen preview.
  ld a, DT_WINDOW            ; first tap: arm the window, do the normal context play
  ld (tp_dt), a
  call toggle_play           ; 2 held + 1 = play/stop (SONG/CHAIN/PHRASE per screen)
  jp ei_dtick                ; consume: no cut on the same press
ei_tsong:
  xor a
  ld (tp_dt), a
  call play_song_here        ; restart in MODE_SONG from song_cur
  jp ei_dtick
ei_1alone:
  ld a, (dt1_timer)
  or a
  jr z, ei_1first
  xor a
  ld (dt1_timer), a
  call dt_second             ; paste, or mint a free chain/phrase
  jr ei_no1
ei_1first:
  ld a, DT_WINDOW
  ld (dt1_timer), a
  xor a
  ld (dt1_fresh), a
  call do_press              ; insert/audition immediately
ei_no1:
  ; ---- button 2 pressed while 1 held ----
  ; grid screens: arm a pending cut - a short tap (release) cuts
  ; the field, holding past SEL_HOLD enters block SELECT. Other
  ; screens keep cut-on-press.
  ld a, (pad_edge)
  and PAD_B2
  jr z, ei_2pend
  ld a, (pad_raw)
  and PAD_B1
  jr z, ei_2pend
  call scr_has_sel
  jr z, ei_cutnow
  ld a, SEL_HOLD
  ld (selhold), a
  jr ei_dtick
ei_cutnow:
  call do_cut
  jr ei_dtick
ei_2pend:
  ; ---- pending cut: release fires it, holding on selects ----
  ld a, (selhold)
  or a
  jr z, ei_dtick
  ld a, (pad_raw)
  and PAD_B1|PAD_B2
  cp PAD_B1|PAD_B2
  jr z, ei_selcnt
  xor a                      ; either button released: field cut
  ld (selhold), a
  call do_cut
  jr ei_dtick
ei_selcnt:
  ld a, (selhold)
  dec a
  ld (selhold), a
  jr nz, ei_dtick
  jp sel_enter               ; threshold reached: SELECT mode
ei_dtick:
  ; ---- double-tap countdowns ----
  ld a, (tp_dt)              ; transport (2-held) double-tap window
  or a
  jr z, ei_dt1
  dec a
  ld (tp_dt), a
ei_dt1:
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
  ; map: PROJECT above CHAIN, GROOVE below CHAIN, WAVE above
  ; INSTR; horizontal row is SONG CHAIN PHRASE INSTR TABLE
  ld a, (scr_mode)
  or a
  jr z, sn_song
  cp SCR_SET
  jr z, sn_set
  cp SCR_PROJ
  jr z, sn_proj
  cp SCR_CHAIN
  jr z, sn_chain
  cp SCR_GROOVE
  jp z, sn_groove
  cp SCR_WAVE
  jp z, sn_wave
  cp SCR_ECHO
  jp z, sn_echo
  cp SCR_INSTR
  jp z, sn_instr_up
  cp SCR_TABLE
  jp z, sn_selt
  cp SCR_FILES
  jp z, sn_files
  jp sn_lr
sn_song:                     ; OPTIONS above SONG, FILES below
  ld a, (pad_edge)
  and PAD_UP
  jr z, sn_song_d
  ld a, SCR_SET
  jp sn_switch
sn_song_d:
  ld a, (pad_edge)
  and PAD_DOWN
  jp z, sn_lr
  ld a, SCR_FILES
  jp sn_switch
sn_files:                    ; FILES: up -> SONG, right -> GROOVE
  ld a, (pad_edge)
  and PAD_UP
  jr z, snf_r
  ld a, SCR_SONG
  jp sn_switch
snf_r:
  ld a, (pad_edge)
  and PAD_RIGHT
  ret z
  ld a, SCR_GROOVE
  jp sn_switch
sn_set:                      ; down to SONG, right to PROJECT
  ld a, (pad_edge)
  and PAD_DOWN
  jr z, sn_set_r
  ld a, 0                    ; SCR_SONG
  jp sn_switch
sn_set_r:
  ld a, (pad_edge)
  and PAD_RIGHT
  ret z
  ld a, SCR_PROJ
  jp sn_switch
sn_proj:
  ld a, (pad_edge)
  and PAD_LEFT
  jr z, sn_proj_d
  ld a, SCR_SET              ; left to SETTINGS
  jp sn_switch
sn_proj_d:
  ld a, (pad_edge)
  and PAD_DOWN
  ret z
  ld a, SCR_CHAIN            ; back down to CHAIN
  jp sn_switch
sn_chain:
  ld a, (pad_edge)
  and PAD_UP
  jr z, sn_chdn
  ld a, SCR_PROJ
  jp sn_switch
sn_chdn:
  ld a, (pad_edge)
  and PAD_DOWN
  jp z, sn_lr
  ld a, SCR_GROOVE
  jp sn_switch
sn_groove:                   ; 2+up -> CHAIN, 2+left -> FILES (groove # is a field now)
  ld a, (pad_edge)
  and PAD_UP
  jr z, sng_l
  ld a, SCR_CHAIN
  jp sn_switch
sng_l:
  ld a, (pad_edge)
  and PAD_LEFT
  ret z
  ld a, SCR_FILES
  jp sn_switch
sn_instr_up:                 ; WAVE above INSTR, ECHO below
  ld a, (pad_edge)
  and PAD_UP
  jr z, sni_dn
  ld a, SCR_WAVE
  jp sn_switch
sni_dn:
  ld a, (pad_edge)
  and PAD_DOWN
  jp z, sn_lr
  ld a, SCR_ECHO
  jp sn_switch
sn_echo:                     ; 2+up returns to INSTR
  ld a, (pad_edge)
  and PAD_UP
  ret z
  ld a, SCR_INSTR
  jp sn_switch
sn_wave:                     ; 2+down exits, 2+L/R selects wave
  ld a, (pad_edge)
  and PAD_DOWN
  jr z, sn_wsel
  ld a, SCR_INSTR
  jp sn_switch
sn_wsel:
  ld a, (pad_edge)
  and PAD_LEFT|PAD_RIGHT
  ret z
  and PAD_RIGHT
  ld a, (cur_wave)
  jr z, snw_dn
  inc a
  jr snw_st
snw_dn:
  dec a
snw_st:
  and $07
  ld (cur_wave), a
  ld a, 1
  ld (label_dirty), a
  jp mark_all_dirty
sn_selt:
  ld a, (pad_edge)
  and PAD_UP|PAD_DOWN
  jp z, sn_lr
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
sn_lr:
  ld a, (pad_edge)
  and PAD_LEFT|PAD_RIGHT
  ret z
  and PAD_RIGHT
  jr nz, sn_right
  ; ---- left: ... -> CHAIN -> SONG ----
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
  ld d, a
  ld a, (scr_mode)
  cp SCR_WAVE
  ld a, d
  call z, wv_cleanup
  ld a, (scr_mode)           ; leaving FILES -> restore the pool mapping
  cp SCR_FILES
  call z, files_leave
  ld a, d
  ld (scr_mode), a
  cp SCR_FILES               ; entering FILES -> stop + map SRAM over the pool
  call z, files_enter
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
  cp SCR_PROJ
  jp z, cm_proj
  cp SCR_SET
  jp z, cm_set
  cp SCR_ECHO
  jp z, cm_echo
  cp SCR_WAVE
  jp z, cm_wave
  cp SCR_FILES
  jp z, cm_files

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
  or a                       ; row 0 is the top: the header row
  jr z, cm_scol              ; is labels only, never the cursor
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
  call ins_wskip_d           ; WAV form: 7 -> 10
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
  call ins_wskip_u           ; WAV form: 9 -> 6
  ld (ins_row), a
  jp ins_mark_field

; WAV has no SWP/VIB/TRM (fields 7-9); SMP shows only INST/TYPE/TSP/
; RATE, so it skips the rest. Hop the gaps as the cursor moves.
ins_wskip_d:
  ld e, a                    ; E = candidate field (ins_is_* keep DE)
  call ins_is_smp
  jr z, iwsd_smp
  call ins_is_fm
  jr z, iwsd_fm
  call ins_is_fmdrum
  jr z, iwsd_fmdrum
  call ins_is_wav
  ld a, e
  ret nz                     ; TONE/NOISE: no gap
  cp 3                       ; WAV fields 0,1,2,4,6,12: hop the gaps
  ret c
  cp 4
  jr c, iwsd_w4              ; 3 -> 4 (HLD)
  cp 5
  ret c                      ; 4
  cp 7
  jr c, iwsd_w6              ; 5,6 -> 6 (TSP)
  cp 12
  ret nc                     ; 12
  ld a, 12                   ; 7..11 -> 12 (WAVE)
  ret
iwsd_w4:
  ld a, 4
  ret
iwsd_w6:
  ld a, 6
  ret
iwsd_smp:                    ; SMP down: INST TYPE KIT(5) RATE(12) TSP(13)
  ld a, e
  cp 2
  ret c                      ; 0,1 unchanged
  cp 6
  jr c, iwsd_s5              ; 2..5 -> 5 (KIT)
  cp 13
  ret nc                     ; 13 (TSP) unchanged
  ld a, 12                   ; 6..12 -> 12 (RATE)
  ret
iwsd_s5:
  ld a, 5
  ret
iwsd_fm:                     ; FM: INST TYPE VOL HLD(4) TSP(6) TBL(10) TBS(11) PROG(12)
  ld a, e
  cp 3
  ret c                      ; 0,1,2 unchanged
  cp 4
  jr c, iwsd_fm4             ; 3 -> 4 (HLD)
  cp 5
  ret c                      ; 4 unchanged
  cp 6
  jr c, iwsd_fm6             ; 5 -> 6 (TSP)
  cp 7
  ret c                      ; 6 unchanged
  cp 10
  jr c, iwsd_fm10            ; 7,8,9 -> 10 (TBL)
  cp 13
  ret c                      ; 10,11,12 unchanged
  ld a, 14                   ; 13 (spacer) -> 14 (PRESET)
  ret
iwsd_fm4:
  ld a, 4
  ret
iwsd_fm6:
  ld a, 6
  ret
iwsd_fm10:
  ld a, 10
  ret
iwsd_fmdrum:                 ; FMDRUM: INST TYPE VOL HLD(4)
  ld a, e
  cp 3
  ret c                      ; 0,1,2 unchanged
  ld a, 4                    ; 3 (spacer) -> 4 (HLD)
  ret
ins_wskip_u:
  ld e, a
  call ins_is_smp
  jr z, iwsu_smp
  call ins_is_fm
  jr z, iwsu_fm
  call ins_is_fmdrum
  jr z, iwsu_fmdrum
  call ins_is_wav
  ld a, e
  ret nz
  cp 3
  ret c
  cp 4
  jr c, iwsu_w2              ; 3 -> 2
  cp 5
  ret c                      ; 4
  cp 7
  jr c, iwsu_w4              ; 5,6 -> 4 (HLD)
  cp 12
  ret nc                     ; 12
  ld a, 6                    ; 7..11 -> 6 (TSP)
  ret
iwsu_w2:
  ld a, 2
  ret
iwsu_w4:
  ld a, 4
  ret
iwsu_smp:                    ; SMP up: TSP(13) RATE(12) KIT(5) TYPE INST
  ld a, e
  cp 2
  ret c                      ; 0,1 unchanged
  cp 5
  jr c, iwsu_s1              ; 2..4 -> 1 (TYPE)
  cp 12
  jr c, iwsu_sk              ; 5..11 -> 5 (KIT)
  ld a, 12                   ; 12 unchanged; 13 -> 12 (RATE)
  ret
iwsu_sk:
  ld a, 5
  ret
iwsu_s1:
  ld a, 1
  ret
iwsu_fm:                     ; FM up: PROG TBS TBL TSP HLD VOL TYPE INST
  ld a, e
  cp 3
  ret c                      ; 0,1,2 unchanged
  cp 4
  jr c, iwsu_fm2             ; 3 -> 2 (VOL)
  cp 5
  ret c                      ; 4 unchanged
  cp 7
  jr c, iwsu_fm4             ; 5,6 -> 4 (HLD)
  cp 10
  jr c, iwsu_fm6             ; 7,8,9 -> 6 (TSP)
  cp 13
  ret c                      ; 10,11,12 unchanged
  ld a, 12                   ; 13 (spacer) -> 12 (PROG)
  ret
iwsu_fm2:
  ld a, 2
  ret
iwsu_fm4:
  ld a, 4
  ret
iwsu_fm6:
  ld a, 6
  ret
iwsu_fmdrum:                 ; FMDRUM up: HLD(4) -> VOL(2) -> TYPE -> INST
  ld a, e
  cp 3
  ret c                      ; 0,1,2 unchanged
  ld a, 2                    ; 3 (spacer) -> 2 (VOL)
  ret
ins_is_wav:                  ; Z if the edited instrument is WAV (type 3)
  push de
  call ins_ptr
  ld a, (hl)
  cp 3
  pop de
  ret
ins_is_smp:                  ; Z if the edited instrument is SMP (type 2)
  push de
  call ins_ptr
  ld a, (hl)
  cp 2
  pop de
  ret
ins_is_fm:                   ; Z if the edited instrument is FM (type 4)
  push de
  call ins_ptr
  ld a, (hl)
  cp 4
  pop de
  ret
ins_is_fmdrum:               ; Z if the edited instrument is FMDRUM (type 5)
  push de
  call ins_ptr
  ld a, (hl)
  cp 5
  pop de
  ret

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
  cp 1
  ld hl, f2r_noise
  jr z, if2r_go
  cp 3
  ld hl, f2r_wav
  jr z, if2r_go
  cp 2
  ld hl, f2r_smp
  jr z, if2r_go
  cp 4
  ld hl, f2r_fm
  jr z, if2r_go
  cp 5
  ld hl, f2r_fmdrum
  jr z, if2r_go
  ld hl, f2r_tone
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
  cp 1
  jr z, imr_noise
  cp 3
  jr z, imr_wav
  cp 2
  jr z, imr_smp              ; SMP: + RATE(12) + TSP(13)
  cp 4
  jr z, imr_fm               ; FM: + PROG (12) + PRESET (14)
  cp 5
  jr z, imr_fmdrum
  ld a, 11                   ; TONE short form
  ret
imr_fm:
  ld a, 14                   ; FM: last field = PRESET
  ret
imr_fmdrum:
  ld a, 4                    ; FMDRUM: last field = HLD
  ret
imr_noise:
  ld a, 13                   ; NOISE: + MODE/RATE
  ret
imr_wav:
  ld a, 12                   ; WAV: + WAVE selector
  ret
imr_smp:
  ld a, 13                   ; SMP: RATE(12) + TSP(13)
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
  cp SCR_PROJ
  jp z, prp_press
  cp SCR_SET
  ret z                      ; nothing pressable on OPTIONS
  cp SCR_ECHO
  ret z
  cp SCR_WAVE
  ret z
  cp SCR_FILES
  jp z, fp_files
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
  ld a, 1
  ld (dt1_fresh), a          ; a second tap mints a free chain
  jp so_mark_cur

do_cut:
  ld a, (scr_mode)
  cp SCR_INSTR
  ret z
  cp SCR_PROJ
  ret z
  cp SCR_SET
  ret z
  cp SCR_ECHO
  ret z
  cp SCR_FILES
  ret z
  cp SCR_WAVE
  jp z, wvp_cut
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
  cp SCR_PROJ
  jp z, prp_edit
  cp SCR_SET
  jp z, stp_edit
  cp SCR_ECHO
  jp z, ep_edit
  cp SCR_FILES
  jp z, fe_edit
  cp SCR_WAVE
  jp z, wvp_edit
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
  inc hl
  ld (hl), 0                 ; clear transpose (init fill is $FF = -1)
  ld a, 1
  ld (dt1_fresh), a          ; a second tap mints a free phrase
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
  ld a, 1
  ld (dt1_fresh), a          ; a second tap mints a free one
  jp mark_phr_dirty
dp_cmd:
  inc hl
  inc hl
  ld a, (hl)
  or a
  ret nz
  ld a, (last_cmd)           ; repeat the last command inserted
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
  ld a, (hl)
  call cmd_cycle             ; alphabetical order (preserves HL)
  ld (hl), a
  ld (last_cmd), a           ; remember it for the next insert
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
  jp z, ine_inst
  cp 1
  jp z, ine_type
  cp 2
  jp z, ine_vol
  cp 3
  jp z, ine_dir
  cp 4
  jp z, ine_spd
  cp 5
  jp z, ine_len
  cp 6
  jp z, ine_tsp
  cp 7
  jp z, ine_swp
  cp 8
  jp z, ine_vib
  cp 9
  jp z, ine_trm
  cp 10
  jp z, ine_tbl
  cp 11
  jp z, ine_tbs
  cp 12
  jp z, ine_f11
  cp 13
  jp z, ine_f13
  cp 14
  jp z, ine_preset
  jp ine_rate
ine_f13:                     ; field 13: SMP transpose (+8), else NOISE rate
  ld a, (hl)                 ; type at +0 (HL = instrument record)
  cp 2
  jp z, ine_tsp
  jp ine_rate

; INST: which instrument the form edits (L/R +-1, U/D +-4)
ine_inst:
  ld a, (ed_rep)
  ld c, a
  ld a, (cur_instr)
  bit 3, c
  jr z, ini_l
  inc a
ini_l:
  bit 2, c
  jr z, ini_u
  dec a
ini_u:
  bit 0, c
  jr z, ini_d
  add a, 4
ini_d:
  bit 1, c
  jr z, ini_st
  sub 4
ini_st:
  and $0F
  ld (cur_instr), a
  ld a, 1
  ld (label_dirty), a
  jp mark_all_dirty

ine_f11:                     ; NOISE: mode; WAV: wave 0-7; SMP: rate; FM: patch
  push hl
  call ins_ptr
  ld a, (hl)
  pop hl
  cp 3
  jr z, if11_wav
  cp 2
  jr z, if11_smp
  cp 4
  jr z, if11_fm
  jp ine_mode
if11_fm:                     ; FM ROM patch 1-15 (instrument +4)
  ld a, (pad_edge)
  and $0F
  ret z
  ld c, a
  ld de, 4
  add hl, de
  ld a, (hl)
  and $0F
  jr nz, if11f_have
  inc a                      ; treat unset (0) as patch 1
if11f_have:
  ld b, a
  ld a, c
  and PAD_RIGHT|PAD_UP
  jr z, if11f_dn
  ld a, b                    ; up: +1, wrap 15 -> 1
  inc a
  cp 16
  jr c, if11f_st
  ld a, 1
  jr if11f_st
if11f_dn:
  ld a, b                    ; down: -1, wrap 1 -> 15
  dec a
  jr nz, if11f_st
  ld a, 15
if11f_st:
  ld (hl), a
  jp ine_mark
if11_wav:
  ld a, (pad_edge)
  and $0F
  ret z
  ld c, a
  ld de, 4
  add hl, de
  ld a, c
  and PAD_RIGHT|PAD_UP
  ld a, (hl)
  jr z, if11w_dn
  inc a
  jr if11w_st
if11w_dn:
  dec a
if11w_st:
  and $07                    ; wrap 0-7
  ld (hl), a
  jp ine_mark
if11_smp:                    ; sample rate 0-3 (NORM/2X/HALF/4X)
  ld a, (pad_edge)
  and $0F
  ret z
  ld c, a
  ld de, 4
  add hl, de
  ld a, c
  and PAD_RIGHT|PAD_UP
  ld a, (hl)
  jr z, if11s_dn
  inc a
  cp 4
  jr c, if11s_st
  xor a
  jr if11s_st
if11s_dn:
  dec a
  jp p, if11s_st
  ld a, 3
if11s_st:
  ld (hl), a
  jp ine_mark

; PRESET (FM, +11): OFF (0) <-> custom preset 1..8
ine_preset:
  ld a, (pad_edge)
  and $0F
  ret z
  ld c, a
  ld de, 11
  add hl, de                 ; hl -> +11
  ld a, c
  and PAD_RIGHT|PAD_UP
  ld a, (hl)
  jr z, ipr_dn
  inc a
  cp 9
  jr c, ipr_st
  xor a                      ; wrap 8 -> OFF
  jr ipr_st
ipr_dn:
  dec a
  jp p, ipr_st
  ld a, 8                    ; wrap OFF -> 8
ipr_st:
  ld (hl), a
  jp ine_mark

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
  cp 1                       ; allow TBS down to 0 (= per-note advance)
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

ine_type:                    ; TONE/NOISE/SMP/WAV/FM/FMDRUM (L/R both ways)
  ld a, (pad_edge)
  and $0F
  ret z
  and PAD_RIGHT|PAD_UP
  ld a, (hl)
  jr z, ine_typd             ; left/down -> previous type
  inc a                      ; right/up -> next type
  cp 6
  jr c, ine_tst
  xor a                      ; wrap 5 -> 0
  jr ine_tst
ine_typd:
  dec a                      ; previous type
  jp p, ine_tst
  ld a, 5                    ; wrap 0 -> 5 (FMDRUM)
ine_tst:
  ld (hl), a
  cp 3                       ; switching to WAV: default HLD = 6
  jr z, ine_seedwav
  cp 4                       ; switching to FM: seed ring HLD + a program
  jr z, ine_seedfm
  cp 5                       ; switching to FMDRUM: seed ring HLD
  jr z, ine_seeddrum
  jr ine_tsr
ine_seedwav:
  push hl
  inc hl
  inc hl
  inc hl
  ld (hl), 6                 ; +3 HLD = 6 (WAV note-length default)
  pop hl
  jr ine_tsr
ine_seedfm:
  push hl
  inc hl
  inc hl
  inc hl
  ld (hl), $0F               ; +3 HLD = F (ring per FM patch)
  inc hl
  ld a, (hl)                 ; +4 PROG: default 1 if unset
  and $0F
  jr nz, ine_tsfp
  ld (hl), 1
ine_tsfp:
  pop hl
  jr ine_tsr
ine_seeddrum:
  push hl
  inc hl
  inc hl
  inc hl
  ld (hl), $0F               ; +3 HLD = F (ring per the chip drum envelope)
  pop hl
ine_tsr:
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

; adjust the nibble in D (0-F) per the d-pad repeat bits (ed_rep)
ins_nib_adj:
  ld a, (ed_rep)
  ld c, a
  bit 3, c
  jr nz, ina_inc
  bit 0, c
  jr z, ina_dec
ina_inc:
  ld a, d
  cp $0F
  jr nc, ina_dec
  inc d
ina_dec:
  bit 2, c
  jr nz, ina_d2
  bit 1, c
  ret z
ina_d2:
  ld a, d
  or a
  ret z
  dec d
  ret

ine_dir:                     ; field 3 = ATK (+2 high nibble)
  inc hl
  inc hl
  ld a, (hl)
  rrca
  rrca
  rrca
  rrca
  and $0F
  ld d, a
  call ins_nib_adj
  ld a, d
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

ine_spd:                     ; field 4 = HLD (+3 low nibble; F = inf)
  inc hl
  inc hl
  inc hl
  ld a, (hl)
  and $0F
  ld d, a
  call ins_nib_adj
  ld a, (hl)
  and $F0
  or d
  ld (hl), a
  jp ine_mark

ine_len:                     ; field 5 = DCY (+2 low nibble), or KIT on SMP
  ld a, (hl)                 ; type at +0
  cp 2
  jr z, ine_kit
  inc hl
  inc hl
  ld a, (hl)
  and $0F
  ld d, a
  call ins_nib_adj
  ld a, (hl)
  and $F0
  or d
  ld (hl), a
  jp ine_mark
ine_kit:                     ; SMP: kit 0-7 in +2, L/R cycles (wraps)
  inc hl
  inc hl
  ld a, (ed_rep)
  ld c, a
  ld a, (hl)
  and 7
  bit 3, c                   ; Right: +1
  jr z, ink_l
  inc a
ink_l:
  bit 2, c                   ; Left: -1
  jr z, ink_st
  dec a
ink_st:
  and 7                      ; wrap 0-7
  ld (hl), a
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

ine_rate:                    ; 512 -> 1K -> 2K -> PITCH (L/R both ways)
  ld a, (pad_edge)
  and $0F
  ret z
  and PAD_RIGHT|PAD_UP
  inc hl
  inc hl
  inc hl
  inc hl                     ; hl -> noise control byte (+4)
  ld d, (hl)                 ; D = current byte (keeps the mode bit)
  ld a, d
  jr z, ine_rdn              ; left/down -> previous rate
  inc a                      ; right/up -> next rate
  jr ine_rst
ine_rdn:
  dec a                      ; previous rate
ine_rst:
  and $03                    ; wrap within 0..3
  ld e, a
  ld a, d
  and $FC                    ; preserve upper bits (noise mode)
  or e
  ld (hl), a
ine_mark:
  ld a, (ins_row)
  jp ins_mark_field

; -------------------------------------------------------------
; WAVE screen: 32 steps x 16 levels drawn as bars. Bytes in
; wave_ram are ready-to-OUT ($D0 | attenuation): drawn value =
; 15 - (byte & $0F).
wv_step_ptr:                 ; HL = &wave_ram[cur_wave][wav_col]
  ld a, (cur_wave)
  rrca
  rrca
  rrca
  and $E0
  ld hl, wave_ram
  ld l, a
  ld a, (wav_col)
  or l
  ld l, a
  ret

cm_wave:                     ; L/R move the step cursor
  ld a, (wav_col)
  ld e, a                    ; old position
  bit 3, c
  jr z, cw_l
  inc a
  and $1F
cw_l:
  bit 2, c
  jr z, cw_st
  dec a
  and $1F
cw_st:
  ld (wav_col), a
  ; fall through

; redraw what a cursor move touches: the old and new steps' dot
; rows - and on GG the whole canvas when the view pages
wv_cursor_dirty:
  ld a, (wav_col)
  cp e
  ret z
.IFDEF TARGET_GG
  xor e
  and $10                    ; crossed the half-way page?
  jr z, wvc_rows
  ld a, 1
  ld (label_dirty), a        ; the hex readout pages too
  jp mark_all_dirty
wvc_rows:
.ENDIF
  ld a, e
  call wv_mark_step
  ld a, (wav_col)
  ; fall through
wv_mark_step:                ; A = step: mark its dot's grid row
  push hl
  push de
  ld e, a
  ld a, (cur_wave)
  rrca
  rrca
  rrca
  and $E0
  ld hl, wave_ram
  or e
  ld l, a
  ld a, (hl)
  cpl
  and $0F                    ; drawn value
  ld e, a
  ld a, 15
  sub e                      ; its grid row
  call mark_dirty_a
  pop de
  pop hl
  ret

; cut gesture (1 held + 2): stamp the next ROM preset into the
; current wave (sine/tri/saw/square/25%/12.5%/organ/random).
; NOT on tap-1: every 1-press runs the press action, so a tap-1
; stamp would wipe the wave each time editing began.
wvp_cut:
  ld a, (wv_preset)
  ld d, a
  inc a
  and $07
  ld (wv_preset), a
  ld a, d
  rrca
  rrca
  rrca
  and $E0
  ld e, a
  ld d, 0
  ld hl, default_waves
  add hl, de
  ld a, (cur_wave)
  rrca
  rrca
  rrca
  and $E0
  ld de, wave_ram
  ld e, a
  ld bc, 32
  ldir
  call wav_refresh           ; stamp lands on a playing wave too
  ld a, 1
  ld (label_dirty), a
  jp mark_all_dirty

wvp_edit:                    ; 1+U/D = value; 1+L/R: SMS = move
  ld a, (ed_rep)             ; (drag-draw), GG = jump page
  ld c, a
.IFDEF TARGET_GG
  ld a, c
  and PAD_LEFT|PAD_RIGHT
  jr z, wve_u
  ld a, (wav_col)
  ld e, a
  xor $10                    ; other half, same step offset
  ld (wav_col), a
  ld a, 1
  ld (label_dirty), a        ; readout + page digit
  call mark_all_dirty
  jr wve_u
.ELSE
  bit 3, c
  jr z, wve_l
  ld a, (wav_col)
  inc a
  and $1F
  ld (wav_col), a
wve_l:
  bit 2, c
  jr z, wve_u
  ld a, (wav_col)
  dec a
  and $1F
  ld (wav_col), a
.ENDIF
wve_u:
  call wv_step_ptr
  ld a, (hl)
  cpl
  and $0F
  ld d, a                    ; drawn value
  bit 0, c
  jr z, wve_d
  ld a, d
  cp $0F
  jr nc, wve_d
  inc d
wve_d:
  bit 1, c
  jr z, wve_st
  ld a, d
  or a
  jr z, wve_st
  dec d
wve_st:
  ld a, d
  cpl
  and $0F
  or $D0
  ld (hl), a
  call wav_refresh           ; playing wave follows the pencil
  ld a, 1
  ld (label_dirty), a
  jp mark_all_dirty

; leaving the wave screen: the canvas is tile-dense and spills
; outside the columns other screens redraw - wipe the whole grid
; area (rows 3-20, all 32 columns) and let the dirty queue
; repaint the next screen over it
wv_cleanup:
  push af
  push de                    ; nt_addr_hl trashes DE; sn_switch holds the target
  ld b, GRID_ROW-1           ; screen in D across this call, so preserve it
wvc_row:
  push bc
  ld c, 0
  call nt_addr_hl
  call vdp_set_addr
.IFDEF TARGET_GG
  ld b, 40                   ; 20 tiles x (index, attr) - GG window width
.ELSE                        ; (32 tiles would overflow the 20-wide window and
  ld b, 64                   ; 32 tiles x (index, attr) - wrap onto later rows)
.ENDIF
wvc_col:
  xor a
  out (VDP_DATA), a          ; tile 0 = space, attr 0
  nop                        ; pad to the active-display write
  nop                        ; spacing in case a sample plays
  nop
  djnz wvc_col
  pop bc
  inc b
  ld a, b
  cp GRID_ROW+17
  jr c, wvc_row
  pop de
  pop af
  ret

dl_wave:
  ld b, NAME_ROW
  ld c, NAME_COL
  ld hl, str_wave
  call print_at
  ld b, NAME_ROW
  ld c, 6
  call nt_addr_hl
  call vdp_set_addr
  ld a, (cur_wave)
  call print_hex_nib
  ; per-step hex readout above the canvas (LSDJ-style)
  xor a
  ld (text_attr), a
.IFDEF TARGET_GG
  ld b, GRID_ROW-1           ; page number at the left edge
  ld c, 0
  call nt_addr_hl
  call vdp_set_addr
  ld a, (wav_col)
  and $10
  rrca
  rrca
  rrca
  rrca
  inc a                      ; '1' / '2'
  add a, '0'-$20+$20         ; ASCII digit
  call print_char
.ENDIF
  ld b, GRID_ROW-1
.IFDEF TARGET_GG
  ld c, 2
.ELSE
  ld c, 0
.ENDIF
  call nt_addr_hl
  call vdp_set_addr
  ld a, (cur_wave)
  rrca
  rrca
  rrca
  and $E0
  ld hl, wave_ram
  ld l, a
.IFDEF TARGET_GG
  ld a, (wav_col)
  and $10
  ld c, a
  or l
  ld l, a
  ld a, c
  add a, 16
  ld b, a
.ELSE
  ld c, 0
  ld b, 32
.ENDIF
dlw_hex:
  ld a, (hl)
  cpl
  and $0F
  call print_hex_nib
  inc hl
  inc c
  ld a, c
  cp b
  jr c, dlw_hex
  ret

; one grid row of the waveform (E = row): LSDJ-style dot plot -
; each step shows a single point at its level, cursor's point
; is a starred block
wv_draw_row:
  ld a, e
  add a, GRID_ROW
  ld b, a
.IFDEF TARGET_GG
  ld c, 2                    ; 16 steps at columns 2-17
.ELSE
  ld c, 0
.ENDIF
  push de
  call nt_addr_hl
  call vdp_set_addr
  pop de
  ld a, 15                   ; this row shows value 15 - row
  sub e
  ld d, a
  ld a, (cur_wave)
  rrca
  rrca
  rrca
  and $E0
  ld hl, wave_ram
  ld l, a
.IFDEF TARGET_GG
  ld a, (wav_col)
  and $10                    ; the cursor's half of the wave
  ld c, a
  or l
  ld l, a
  ld a, c
  add a, 16
  ld b, a                    ; loop bound
.ELSE
  ld c, 0                    ; step
  ld b, 32
.ENDIF
wvd_step:
  ld a, (hl)
  cpl
  and $0F                    ; drawn value
  cp d
  jr nz, wvd_empty
  ld a, (wav_col)            ; the dot lives on this row
  cp c
  ld a, 0                    ; solid block (inverted space)
  jr nz, wvd_put
  ld a, '*'-$20              ; cursor dot: starred block
wvd_put:
  out (VDP_DATA), a
  nop                        ; >=29 cycles between strobes:
  nop                        ; active-display writes get dropped
  nop                        ; below that and the tile/attr
  ld a, $08                  ; stream slips a byte
  out (VDP_DATA), a
  jr wvd_next
wvd_empty:
  xor a                      ; dark field
  out (VDP_DATA), a
  nop
  nop
  nop
  nop
  xor a
  out (VDP_DATA), a
wvd_next:
  inc hl
  inc c
  ld a, c
  cp b
  jr c, wvd_step
  ret

str_wave:   .db "WAVE", 0
str_wavlbl: .db "WAVE", 0
str_spdlbl: .db "RATE", 0
str_fmlbl:  .db "PROG", 0
str_kitlbl: .db "KIT ", 0
str_smpspd: .db "1X  2X  4X  .5X "
str_blank7: .db "       ", 0
str_sp1:    .db " ", 0

; -------------------------------------------------------------
; PROJECT screen: fields 0 TEMPO, 1 VIDEO, 2 SRAM, 3 SAVE, 4 LOAD
cm_proj:
  xor a
  ld (new_arm), a            ; moving away disarms NEW
  bit 1, c                   ; down
  jr z, cp_up
  ld a, (prj_row)
  cp 2
  jr nc, cp_up
  call prj_mark_field
  inc a
  ld (prj_row), a
  call prj_mark_field
cp_up:
  bit 0, c                   ; up
  ret z
  ld a, (prj_row)
  or a
  ret z
  call prj_mark_field
  dec a
  ld (prj_row), a
  jp prj_mark_field

prj_mark_field:              ; A = field (preserved)
  push hl
  push de
  push af
  ld e, a
  ld d, 0
  ld hl, prj_f2r
  add hl, de
  ld a, (hl)
  call mark_dirty_a
  pop af
  pop de
  pop hl
  ret

prp_press:
  ret                        ; NEW/DEMO/SAVE/LOAD live on the FILES screen now
prp_edit:
  ld a, (prj_row)
  cp 2
  jp z, prp_play
  cp 1
  jp z, prp_tsp
  or a
  ret nz
  ; TMPO steps the active groove by one tick = the next achievable
  ; BPM rung. Right = faster (fewer ticks), Left = slower. The whole
  ; groove shifts together, so swing is preserved.
  ld a, (ed_rep)
  ld c, a
  bit 3, c                   ; right -> faster
  jr z, pe_chkl
  ld a, $FF                  ; delta -1
  jr pe_apply
pe_chkl:
  bit 2, c                   ; left -> slower
  ret z
  ld a, 1                    ; delta +1
pe_apply:
  ld b, a                    ; B = signed delta
  call groove_base           ; HL = active groove
  ld c, 16
pe_loop:
  ld a, (hl)
  or a
  jr z, pe_done              ; groove terminator
  add a, b
  bit 7, a                   ; clamp each entry to 1..15
  jr nz, pe_min
  or a
  jr z, pe_min
  cp 16
  jr c, pe_set
  ld a, 15
  jr pe_set
pe_min:
  ld a, 1
pe_set:
  ld (hl), a
  inc hl
  dec c
  jr nz, pe_loop
pe_done:
  xor a
  jp prj_mark_field
prp_tsp:                     ; global transpose: L/R = semitone,
  ld a, (ed_rep)             ; U/D = octave, +-24
  ld c, a
  ld a, (proj_tsp)
  bit 3, c
  jr z, pt_l
  inc a
pt_l:
  bit 2, c
  jr z, pt_u
  dec a
pt_u:
  bit 0, c
  jr z, pt_d
  add a, 12
pt_d:
  bit 1, c
  jr z, pt_cl
  sub 12
pt_cl:
  cp 25                      ; 0..24: fine
  jr c, pt_st
  cp $E8                     ; -24..-1: fine
  jr nc, pt_st
  bit 7, a                   ; overshot: clamp by sign
  ld a, 24
  jr z, pt_st
  ld a, $E8
pt_st:
  ld (proj_tsp), a
  ld a, 1
  jp prj_mark_field
stp_colr:                    ; 1 + L/R cycles the colour scheme
  ld a, (ed_rep)
  and PAD_LEFT|PAD_RIGHT
  ret z
  ld a, (ed_rep)
  ld c, a
  ld a, (pal_sel)
  bit 3, c
  jr z, pc_l
  inc a
pc_l:
  bit 2, c
  jr z, pc_w
  dec a
pc_w:
  cp $FF                     ; wrap 0..7
  jr nz, pc_hi
  ld a, 7
pc_hi:
  cp 8
  jr c, pc_st
  xor a
pc_st:
  ld (pal_sel), a
  call load_palette          ; applies immediately
  ld a, 3
  jp stg_mark_field
stp_sync:                    ; 1 + L/R cycles the sync mode (skips reserved MIDI)
  ld a, (ed_rep)
  ld c, a
  ld a, (sync_mode)
  bit 3, c                   ; Right: forward (skip MIDI=4, wrap IN24->OFF)
  jr z, psy_nr
  inc a
  cp SYNC_MIDI
  jr nz, psy_rw
  inc a
psy_rw:
  cp SYNC_IN24+1
  jr c, psy_nr
  xor a
psy_nr:
  bit 2, c                   ; Left: back (skip MIDI, wrap OFF->IN24)
  jr z, psy_set
  dec a
  jp m, psy_lw
  cp SYNC_MIDI
  jr nz, psy_set
  dec a
  jr psy_set
psy_lw:
  ld a, SYNC_IN24
psy_set:
  ld b, a
  ld a, (sync_mode)
  cp b
  ret z
  push bc                    ; mode change stops the transport
  call engine_stop           ; and releases the port (out $FF)
  pop bc
  ld a, b
  ld (sync_mode), a
  ld a, 1
  ld (state_dirty), a
  ld a, 2
  jp stg_mark_field
prp_play:                    ; 1 + L/R toggles SONG/LIVE (MODE)
  ld a, (ed_rep)
  and PAD_LEFT|PAD_RIGHT
  ret z
  ld a, (play_mode)
  xor 1
  ld b, a
  push bc                    ; mode change stops the transport
  call engine_stop
  pop bc
  ld a, b
  ld (play_mode), a
  ld a, 1
  ld (state_dirty), a
  ld a, 2
  jp prj_mark_field

; -------------------------------------------------------------
; OPTIONS screen: the machine/rig page (persisted config block).
; Fields: 0 VID (AUTO/PAL/NTSC, SMS only), 1 SRAM (read-only),
; 2 SYNC, 3 COLR, 4 CLON.
cm_set:
  bit 1, c                   ; down
  jr z, cs_up
  ld a, (stg_row)
  cp 5
  jr nc, cs_up
  call stg_mark_field
  inc a
  ld (stg_row), a
  call stg_mark_field
cs_up:
  bit 0, c                   ; up
  ret z
  ld a, (stg_row)
  or a
  ret z
  call stg_mark_field
  dec a
  ld (stg_row), a
  jp stg_mark_field

stg_mark_field:              ; A = field (preserved)
  push hl
  push de
  push af
  ld e, a
  ld d, 0
  ld hl, stg_f2r
  add hl, de
  ld a, (hl)
  call mark_dirty_a
  pop af
  pop de
  pop hl
  ret

stp_edit:
  ld a, (stg_row)
.IFNDEF TARGET_GG
  or a
  jp z, stp_video            ; row 0 = VIDEO (SMS only; GG is NTSC)
.ENDIF
  cp 2
  jp z, stp_sync
  cp 3
  jp z, stp_colr
  cp 4
  jp z, stp_clone
  cp 5
  jp z, stp_fm
  ret
stp_fm:                      ; 1 + L/R toggles the FM unit OFF/ON
  ld a, (ed_rep)
  and PAD_LEFT|PAD_RIGHT
  ret z
  ld a, (fm_on)
  xor 1
  ld (fm_on), a
  or a
  jr z, spf_off
  call fm_init               ; ON: enable $F2 + clear (fm_init checks fm_on)
  jr spf_mk
spf_off:
  call fm_silence            ; OFF: drop FM routing + key everything off
spf_mk:
  ld a, 5
  jp stg_mark_field
.IFNDEF TARGET_GG
stp_video:                   ; 1 + L/R cycles AUTO / PAL / NTSC
  ld a, (ed_rep)
  and PAD_LEFT|PAD_RIGHT
  ret z
  ld a, (ed_rep)
  ld c, a
  ld a, (vid_sel)
  bit 3, c
  jr z, pv_l
  inc a
pv_l:
  bit 2, c
  jr z, pv_w
  dec a
pv_w:
  cp $FF                     ; wrap 0..2
  jr nz, pv_hi
  ld a, 2
pv_hi:
  cp 3
  jr c, pv_st
  xor a
pv_st:
  ld (vid_sel), a
  call apply_video           ; re-resolve region + retune note/sample tables
  xor a
  jp stg_mark_field          ; redraw the VID field
.ENDIF
stp_clone:                   ; 1 + L/R toggles SLIM/DEEP
  ld a, (ed_rep)
  and PAD_LEFT|PAD_RIGHT
  ret z
  ld a, (clone_deep)
  xor 1
  ld (clone_deep), a
  ld a, 4
  jp stg_mark_field

dl_set:
  ld b, NAME_ROW
  ld c, NAME_COL
  ld hl, str_set
  jp print_at

st_draw_row:
  push de
  ld d, 0
  ld hl, stg_r2f
  add hl, de
  ld a, (hl)
  pop de
  cp $FF
  ret z
  ld (ed_field), a
  ; label (col 4)
  xor a
  ld (text_attr), a
  ld a, (ed_field)
  ld d, a
  add a, a
  add a, a
  add a, d                   ; * 5
  push de
  ld e, a
  ld d, 0
  ld hl, stg_lbls
  add hl, de
  pop de
  push hl
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, INS_LBL
  pop hl
  push de
  call print_at
  pop de
  ; value attr
  xor a
  ld (text_attr), a
  ld a, (stg_row)
  ld d, a
  ld a, (ed_field)
  cp d
  jr nz, std_addr
  ld a, $08
  ld (text_attr), a
std_addr:
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, INS_VAL
  push de
  call nt_addr_hl
  call vdp_set_addr
  pop de
  ld a, (ed_field)
  or a
  jp z, prd_video
  cp 1
  jp z, prd_sram
  cp 2
  jp z, prd_sync
  cp 3
  jp z, prd_colr
  cp 4
  jr z, prd_clone
  ld a, (fm_on)              ; field 5 = FM toggle
  or a
  ld hl, str_fmoff
  jr z, prd_cl4
  ld hl, str_fmon
  jr prd_cl4
prd_clone:                   ; field 4 = CLONE
  ld a, (clone_deep)
  or a
  ld hl, str_slim
  jr z, prd_cl4
  ld hl, str_deep
prd_cl4:
  ld b, 4
  jp print_raw

stg_f2r:
  .db 0, 1, 3, 5, 7, 9
stg_r2f:
  .db 0, 1, $FF, 2, $FF, 3, $FF, 4, $FF, 5, $FF, $FF, $FF, $FF, $FF, $FF

prj_f2r:                     ; only TMPO/TSP/MODE; NEW/DEMO/SAVE/LOAD/SLOT on FILES
  .db 0, 1, 2
prj_r2f:
  .db 0, 1, 2, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF

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

; cm_groove: cursor over the groove-number field ($FF) then the 16 tick rows.
cm_groove:
  ld a, (grv_row)            ; mark the old cursor position
  cp $FF
  jr nz, cmg_oldtick
  ld a, 1
  ld (label_dirty), a        ; field lives in the header
  jr cmg_dn
cmg_oldtick:
  call mark_dirty_a
cmg_dn:
  bit 1, c                   ; down
  jr z, cmg_up
  ld a, (grv_row)
  cp $FF
  jr nz, cmg_dn_t
  xor a                      ; field -> tick 0
  ld (grv_row), a
  jr cmg_up
cmg_dn_t:
  cp $0F
  jr nc, cmg_up              ; bottom tick: stay
  inc a
  ld (grv_row), a
cmg_up:
  bit 0, c                   ; up
  jr z, cmg_done
  ld a, (grv_row)
  cp $FF
  jr z, cmg_done             ; field: already at the top
  or a
  jr nz, cmg_up_t
  ld a, $FF                  ; tick 0 -> field
  ld (grv_row), a
  jr cmg_done
cmg_up_t:
  dec a
  ld (grv_row), a
cmg_done:
  ld a, (grv_row)            ; mark the new cursor position
  cp $FF
  jr z, cmg_newhdr
  jp mark_dirty_a
cmg_newhdr:
  ld a, 1
  ld (label_dirty), a
  ret

grp_press:
  ld a, (grv_row)
  cp $FF
  ret z                      ; on the groove-number field: no tick to set
  ld e, a
  call gr_entry_ptr
  ld a, (hl)
  or a
  ret nz
  ld (hl), 6
  jr gr_mark

grp_cut:
  ld a, (grv_row)
  cp $FF
  ret z
  ld e, a
  call gr_entry_ptr
  ld (hl), 0
gr_mark:
  ld a, (grv_row)
  jp mark_dirty_a

grp_edit:
  ld a, (grv_row)
  cp $FF
  jr z, grpe_field           ; 1+L/R changes the selected groove
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
grpe_field:
  ld a, (ed_rep)
  ld c, a
  ld a, (cur_groove)
  bit 3, c                   ; right -> next groove
  jr z, grpf_l
  inc a
grpf_l:
  bit 2, c                   ; left -> previous groove
  jr z, grpf_st
  dec a
grpf_st:
  and $0F
  ld (cur_groove), a
  ld a, 1
  ld (label_dirty), a        ; the field + every tick belong to the new groove
  jp mark_all_dirty

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
  ld a, (hl)
  call cmd_cycle             ; alphabetical order (preserves HL)
  ld (hl), a
  jp tb_mark

; -------------------------------------------------------------
; clipboard: A = column (preserves HL)
clip_set:
  ld (clip_col), a
  ld a, (scr_mode)
  ld (clip_scr), a
  ret

; second tap of double-tap 1: paste wins whenever a clipboard is
; armed for this screen; otherwise, if the first tap filled an
; empty cell, upgrade it to the next FREE chain/phrase
dt_second:
  ld a, (blk_scr)
  ld b, a
  ld a, (scr_mode)
  cp b
  jp z, do_paste
  ld a, (clip_scr)
  ld b, a
  ld a, (scr_mode)
  cp b
  jp z, do_paste
  ld a, (dt1_fresh)
  or a
  jp z, dt_clone             ; populated cell, no clipboard: clone
  xor a
  ld (dt1_fresh), a
  ld a, (scr_mode)
  or a
  jr z, dnf_song
  cp SCR_PHRASE
  jr z, dnf_instr
  cp SCR_CHAIN
  ret nz
  ld a, (chn_col)            ; CHAIN: the phrase column only
  or a
  ret nz
  call find_free_phrase
  cp $FF
  ret z                      ; pool exhausted
  ld b, a
  ld a, (chn_row)
  ld e, a
  call ch_entry_ptr
  ld (hl), b
  ld a, b
  ld (last_phrase), a
  ld a, (chn_row)
  jp mark_dirty_a
dnf_song:
  call find_free_chain
  cp $FF
  ret z
  ld b, a
  call so_cell_ptr
  ld (hl), b
  ld a, b
  ld (last_chain), a
  jp so_mark_cur
dnf_instr:
  ld a, (phr_col)            ; PHRASE: the instrument column only
  cp 1
  ret nz
  call find_free_instr
  cp $FF
  ret z
  ld b, a
  ld a, (phr_row)
  ld e, a
  call ed_step_ptr
  inc hl
  ld (hl), b
  ld a, b
  ld (last_instr), a
  jp mark_phr_dirty

; lowest chain with no steps -> A ($FF if none)
find_free_chain:
  ld c, 0
ffc_chain:
  ld l, c
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl                 ; * 32
  ld de, chains
  add hl, de
  ld b, 16
ffc_step:
  ld a, (hl)
  cp $FF
  jr nz, ffc_next
  inc hl
  inc hl
  djnz ffc_step
  ld a, c
  ret
ffc_next:
  inc c
  ld a, c
  cp NUM_CHAINS
  jr c, ffc_chain
  ld a, $FF
  ret

; lowest instrument still matching a default record -> A
; (two shapes: the current vol-F default, and the all-zero
; record older saves carry for unedited slots)
find_free_instr:
  ld c, 0
ffi_ins:
  ld de, instr_default
  call ffi_cmp
  ret z
  ld de, instr_default_old
  call ffi_cmp
  ret z
  inc c
  ld a, c
  cp 16
  jr c, ffi_ins
  ld a, $FF
  ret
ffi_cmp:                     ; Z + A=C when instrument C == (DE)
  ld l, c
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl                 ; * 16
  push de
  ld de, instruments
  add hl, de
  pop de
  ld b, 16
ffc_byte:
  ld a, (de)
  cp (hl)
  jr nz, ffc_no
  inc hl
  inc de
  djnz ffc_byte
  ld a, c
  cp a                       ; force Z
  ret
ffc_no:
  or 1                       ; force NZ
  ret
instr_default:               ; TONE, vol F, ATK 0 / HLD 1 / DCY 3
  .db 0, $0F, $03, $01, 0, 0, 0, 0, 0, $FF, 1, 0, 0, 0, 0, 0
instr_default_old:           ; pre-vol-F saves: zeroed slots
  .db 0, 0, 0, 0, 0, 0, 0, 0, 0, $FF, 0, 0, 0, 0, 0, 0

; lowest phrase with no notes/instruments/commands -> A
find_free_phrase:
  ld c, 0
ffp_phr:
  ld l, c
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl                 ; * 64
  ld de, phrase_pool
  add hl, de
  ld b, 16
ffp_step:
  ld a, (hl)                 ; note
  or a
  jr nz, ffp_next
  inc hl
  ld a, (hl)                 ; instrument
  cp $FF
  jr nz, ffp_next
  inc hl
  ld a, (hl)                 ; command
  or a
  jr nz, ffp_next
  inc hl
  inc hl                     ; param rides with its command
  djnz ffp_step
  ld a, c
  ret
ffp_next:
  inc c
  ld a, c
  cp NUM_PHRASES
  jr c, ffp_phr
  ld a, $FF
  ret

.ENDS

; cloning is cold code; bank 0 has room again (PROJECT slimmed down), and bank 1
; is tight with the FILES manager, so park it in bank 0.
.BANK 0 SLOT 0
.SECTION "Clone" FREE

; ===========================================================
; cloning (double-tap-1 on a populated cell, no clipboard):
; duplicate the chain/phrase into the next free slot. SONG clones
; the chain (SLIM = share phrases, DEEP = clone them too); CHAIN's
; phrase column clones the phrase. No free slot -> flash, no-op.
; ===========================================================
dt_clone:
  ld a, (scr_mode)
  or a
  jr z, clone_chain
  cp SCR_CHAIN
  jr z, clone_phrase
  ret

; A = chain number -> HL = &chains[A]
chain_base:
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  ld de, chains
  add hl, de
  ret

; A = phrase number -> HL = &phrase_pool[A]
phrase_base:
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  ld de, phrase_pool
  add hl, de
  ret

; copy 64 bytes phrase tmp_note -> phrase tmp_instr
copy_phrase_blk:
  ld a, (tmp_note)
  call phrase_base
  push hl
  ld a, (tmp_instr)
  call phrase_base
  ex de, hl
  pop hl
  ld bc, 64
  ldir
  ret

clone_phrase:
  ld a, (chn_col)
  or a
  ret nz                     ; the phrase column only
  ld a, (chn_row)
  ld e, a
  call ch_entry_ptr
  ld a, (hl)
  cp $FF
  ret z                      ; empty cell: nothing to clone
  ld (tmp_note), a           ; source phrase
  call find_free_phrase
  cp $FF
  jp z, clone_fail
  ld (tmp_instr), a          ; dest phrase
  call copy_phrase_blk
  ld a, (chn_row)
  ld e, a
  call ch_entry_ptr
  ld a, (tmp_instr)
  ld (hl), a
  ld (last_phrase), a
  ld a, (chn_row)
  jp mark_dirty_a

clone_chain:
  ld a, (hdr_cur)
  or a
  ret nz                     ; not on the track header
  call so_cell_ptr
  ld a, (hl)
  cp $FF
  ret z                      ; empty cell
  ld (tmp_note), a           ; source chain
  ld a, (clone_deep)         ; DEEP needs a phrase per non-empty step
  or a
  jr z, ccl_alloc
  call chain_phrase_count
  ld b, a
  call count_free_phrases
  cp b
  jp c, clone_fail           ; not enough free phrases
ccl_alloc:
  call find_free_chain
  cp $FF
  jp z, clone_fail
  ld (tmp_instr), a          ; dest chain
  ld a, (tmp_note)
  call chain_base
  push hl
  ld a, (tmp_instr)
  call chain_base
  ex de, hl
  pop hl
  ld bc, 32
  ldir
  ld a, (clone_deep)
  or a
  call nz, deep_clone_chain
  call so_cell_ptr
  ld a, (tmp_instr)
  ld (hl), a
  ld (last_chain), a
  jp so_mark_cur

; non-empty steps (phrase != $FF) in chain tmp_note -> A
chain_phrase_count:
  ld a, (tmp_note)
  call chain_base
  ld b, 16
  ld c, 0
cpc_loop:
  ld a, (hl)
  cp $FF
  jr z, cpc_next
  inc c
cpc_next:
  inc hl
  inc hl
  djnz cpc_loop
  ld a, c
  ret

; count of free phrase slots -> A
count_free_phrases:
  push bc
  ld c, 0
  ld b, 0
cfp_loop:
  push bc
  call phrase_is_free
  pop bc
  jr nz, cfp_next
  inc b
cfp_next:
  inc c
  ld a, c
  cp NUM_PHRASES
  jr c, cfp_loop
  ld a, b
  pop bc
  ret

; C = phrase number -> Z if that phrase is free/empty
phrase_is_free:
  ld a, c
  call phrase_base
  ld b, 16
pif_step:
  ld a, (hl)
  or a
  jr nz, pif_used
  inc hl
  ld a, (hl)
  cp $FF
  jr nz, pif_used
  inc hl
  ld a, (hl)
  or a
  jr nz, pif_used
  inc hl
  inc hl
  djnz pif_step
  xor a
  ret
pif_used:
  or 1
  ret

; DEEP: clone every phrase the new chain (tmp_instr) references to
; a fresh slot and repoint the step. The precheck guarantees a
; free phrase is always available.
deep_clone_chain:
  ld a, (tmp_instr)
  call chain_base
  ld b, 16
dcc_loop:
  ld a, (hl)
  cp $FF
  jr z, dcc_next
  ld (tmp_note), a           ; source phrase
  push bc
  push hl
  call find_free_phrase
  ld (tmp_cmd), a            ; dest phrase
  ld a, (tmp_note)
  call phrase_base
  push hl
  ld a, (tmp_cmd)
  call phrase_base
  ex de, hl
  pop hl
  ld bc, 64
  ldir
  pop hl
  ld a, (tmp_cmd)
  ld (hl), a                 ; repoint the step to the clone
  pop bc
dcc_next:
  inc hl
  inc hl
  djnz dcc_loop
  ret

clone_fail:
  ld a, 18                   ; flash the cursor ~2 blinks
  ld (cur_flash), a
  ret

; cursor cell attribute: $08 (inverted) normally; blinks while a
; clone-fail flash is counting down
cursor_attr:
  ld a, (cur_flash)
  or a
  jr nz, cra_flash
  ld a, $08
  ret
cra_flash:
  and $04
  jr z, cra_off
  ld a, $08
  ret
cra_off:
  xor a
  ret

; mark the cursor row dirty (SONG / CHAIN - the clone screens)
mark_cursor_dirty:
  ld a, (scr_mode)
  or a
  jp z, so_mark_cur
  ld a, (chn_row)
  jp mark_dirty_a

; ===========================================================
; ECHO screen - a form like OPTIONS (in bank 1; bank 0 is full).
; Fields: MODE, TAP1, TAP2, RD1, RD2, STEREO. Values live in the
; echo_* engvars that the engine post-pass (echo_pass) reads.
; ===========================================================
cm_echo:
  bit 1, c                   ; down
  jr z, ce_up
  ld a, (ech_row)
  cp 7
  jr nc, ce_up
  call ep_mark
  inc a
  ld (ech_row), a
  call ep_mark
ce_up:
  bit 0, c                   ; up
  ret z
  ld a, (ech_row)
  or a
  ret z
  call ep_mark
  dec a
  ld (ech_row), a
  jp ep_mark

ep_mark:                     ; A = field -> mark its grid row dirty
  push hl
  push de
  push af
  ld e, a
  ld d, 0
  ld hl, ech_f2r
  add hl, de
  ld a, (hl)
  call mark_dirty_a
  pop af
  pop de
  pop hl
  ret

ep_edit:
  ld a, (ech_row)
  or a
  jr z, ee_mode
  cp 1
  jp z, ee_tap1
  cp 2
  jp z, ee_tap2
  cp 3
  jp z, ee_red1
  cp 4
  jp z, ee_red2
  cp 5
  jr z, ee_stereo
  cp 6
  jr z, ee_tsp1
  ld hl, echo_tsp2           ; field 7
  jr ee_tsp
ee_stereo:
  ld a, (ed_rep)
  and PAD_LEFT|PAD_RIGHT
  ret z
  ld a, (echo_stereo)
  xor 1
  ld (echo_stereo), a
  or a
  call z, echo_pan_reset     ; recenter once when STER goes off
  jp ee_dirty
ee_tsp1:
  ld hl, echo_tsp1
ee_tsp:
  ld a, (ed_rep)
  and PAD_LEFT|PAD_RIGHT
  ret z
  ld c, a
  ld a, (hl)
  bit 3, c                   ; right +1
  jr z, ets_l
  inc a
ets_l:
  bit 2, c                   ; left -1
  jr z, ets_cl
  dec a
ets_cl:
  bit 7, a                   ; clamp signed to -24..+24
  jr z, ets_pos
  cp $E8
  jr nc, ets_store
  ld a, $E8
  jr ets_store
ets_pos:
  cp 25
  jr c, ets_store
  ld a, 24
ets_store:
  ld (hl), a
  jp ee_dirty
ee_mode:
  ld a, (ed_rep)
  and PAD_LEFT|PAD_RIGHT
  ret z
  ld c, a
  ld a, (echo_mode)
  bit 3, c                   ; right: next (wrap 2->0)
  jr z, eem_l
  inc a
  cp 3
  jr c, eem_l
  ld a, 0
eem_l:
  bit 2, c                   ; left: prev (wrap 0->2)
  jr z, eem_set
  or a
  jr nz, eem_dec
  ld a, 2
  jr eem_set
eem_dec:
  dec a
eem_set:
  ld (echo_mode), a
  or a
  call z, echo_pan_reset     ; recenter once when echo goes off
  jp ee_dirty
ee_tap1:
  ld hl, echo_tap1
  jr ee_tap
ee_tap2:
  ld hl, echo_tap2
ee_tap:                      ; tap is in rows (1-15), L/R +-1 row
  ld a, (ed_rep)
  ld c, a
  ld a, (hl)
  bit 3, c                   ; right +1
  jr z, et_l
  inc a
et_l:
  bit 2, c                   ; left -1
  jr z, et_clamp
  dec a
et_clamp:
  or a                       ; clamp 1..15
  jr nz, et_hi
  inc a
et_hi:
  cp 16
  jr c, et_store
  ld a, 15
et_store:
  ld (hl), a
  jp ee_dirty
ee_red1:
  ld hl, echo_red1
  jr ee_red
ee_red2:
  ld hl, echo_red2
ee_red:
  ld a, (ed_rep)
  and PAD_LEFT|PAD_RIGHT
  ret z
  ld c, a
  ld a, (hl)
  bit 3, c                   ; right +1
  jr z, er_l
  inc a
er_l:
  bit 2, c                   ; left -1
  jr z, er_st
  dec a
er_st:
  and $0F
  ld (hl), a
ee_dirty:
  ld a, (ech_row)
  jp ep_mark

dl_echo:
  ld b, NAME_ROW
  ld c, NAME_COL
  ld hl, str_echo
  jp print_at

et_draw_row:                 ; E = visible row (like st_draw_row)
  push de
  ld d, 0
  ld hl, ech_r2f
  add hl, de
  ld a, (hl)
  pop de
  cp $FF
  ret z
  ld (ed_field), a
  ; label (col 4)
  xor a
  ld (text_attr), a
  ld a, (ed_field)
  ld d, a
  add a, a
  add a, a
  add a, d                   ; * 5
  push de
  ld e, a
  ld d, 0
  ld hl, ech_lbls
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
  ; value attr (highlight the cursor field)
  xor a
  ld (text_attr), a
  ld a, (ech_row)
  ld d, a
  ld a, (ed_field)
  cp d
  jr nz, etd_addr
  ld a, $08
  ld (text_attr), a
etd_addr:
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, 10
  push de
  call nt_addr_hl
  call vdp_set_addr
  pop de
  ld a, (ed_field)
  or a
  jr z, etd_mode
  cp 1
  jr z, etd_tap1
  cp 2
  jr z, etd_tap2
  cp 3
  jr z, etd_red1
  cp 4
  jr z, etd_red2
  cp 5
  jr z, etd_ster
  cp 6
  jr z, etd_tsp1
  ld a, (echo_tsp2)          ; field 7
  jr etd_tsp
etd_tsp1:
  ld a, (echo_tsp1)
etd_tsp:
  bit 7, a
  jr z, etd_tpos
  neg
  push af
  ld a, '-'
  call print_char
  pop af
  jp print_hex_a
etd_tpos:
  push af
  ld a, '+'
  call print_char
  pop af
  jp print_hex_a
etd_ster:
  ld a, (echo_stereo)
  or a
  ld hl, str_ech_off
  jr z, etd_pr
  ld hl, str_ech_on
etd_pr:
  ld b, 4
  jp print_raw
etd_mode:
  ld a, (echo_mode)
  add a, a
  add a, a                   ; * 4
  ld e, a
  ld d, 0
  ld hl, str_emode
  add hl, de
  ld b, 4
  jp print_raw
etd_tap1:
  ld a, (echo_tap1)
  jp print_hex_a
etd_tap2:
  ld a, (echo_tap2)
  jp print_hex_a
etd_red1:
  ld a, (echo_red1)
  jp print_hex_nib
etd_red2:
  ld a, (echo_red2)
  jp print_hex_nib

str_echo:
  .db "ECHO", 0
ech_lbls:
  .db "MODE", 0
  .db "TAP1", 0
  .db "TAP2", 0
  .db "RD1 ", 0
  .db "RD2 ", 0
  .db "STER", 0
  .db "TSP1", 0
  .db "TSP2", 0
str_emode:
  .db "OFF T2  T2T3"
str_ech_off:
  .db "OFF "
str_ech_on:
  .db "ON  "
ech_f2r:
  .db 0, 2, 3, 5, 6, 8, 10, 11
ech_r2f:
  .db 0, $FF, 1, 2, $FF, 3, 4, $FF, 5, $FF, 6, 7, $FF, $FF, $FF, $FF

.ENDS

.BANK 0 SLOT 0
.SECTION "Editor2" FREE

; double-tap 1: paste the clipboard at the cursor when the
; screen and column context matches the cut. A block clipboard
; for this screen takes the whole gesture.
do_paste:
  ld a, (blk_scr)
  ld b, a
  ld a, (scr_mode)
  cp b
  jp z, blk_paste
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
  ld a, (ed_track)
  ld (cur_trig_ch), a
  ld a, d
  dec a
  ld (ix+0), a
  ld (ix+1), c
  jp trigger_note            ; AHD plays out; a forever-hold note is
                             ; capped while stopped (see ahd_hold_inf)

; =============================================================
; block selection (SONG/CHAIN/PHRASE/TABLE)
; =============================================================
; NZ if the screen (and cursor position) supports block select
scr_has_sel:
  ld a, (scr_mode)
  or a
  jr z, shs_song
  cp SCR_CHAIN
  jr z, shs_yes
  cp SCR_PHRASE
  jr z, shs_yes
  cp SCR_TABLE
  jr z, shs_yes
shs_no:
  xor a
  ret
shs_song:
  ld a, (hdr_cur)            ; not on the track header
  or a
  jr nz, shs_no
shs_yes:
  ld a, 1
  or a
  ret

; cursor position on the grid screens (row is absolute on SONG)
sel_cur_row:
  ld a, (scr_mode)
  or a
  jr nz, scw_r1
  ld a, (song_cur)
  ret
scw_r1:
  cp SCR_CHAIN
  jr nz, scw_r2
  ld a, (chn_row)
  ret
scw_r2:
  cp SCR_PHRASE
  jr nz, scw_r3
  ld a, (phr_row)
  ret
scw_r3:
  ld a, (tbl_row)
  ret

sel_cur_col:
  ld a, (scr_mode)
  or a
  jr nz, scw_c1
  ld a, (song_col)
  ret
scw_c1:
  cp SCR_CHAIN
  jr nz, scw_c2
  ld a, (chn_col)
  ret
scw_c2:
  cp SCR_PHRASE
  jr nz, scw_c3
  ld a, (phr_col)
  ret
scw_c3:
  ld a, (tbl_col)
  ret

; enter SELECT: anchor at the cursor
sel_enter:
  xor a
  ld (selhold), a
  ld (sel_1press), a
  call sel_cur_row
  ld (sel_arow), a
  call sel_cur_col
  ld (sel_acol), a
  ld a, 1
  ld (sel_active), a
  call sel_norm
  jp mark_all_dirty

sel_exit:
  xor a
  ld (sel_active), a
  ld (sel_1press), a
  jp mark_all_dirty

; normalize anchor..cursor into sel_r0/r1/c0/c1 (inclusive)
sel_norm:
  call sel_cur_row
  ld b, a
  ld a, (sel_arow)
  cp b
  jr c, snm_r
  ld c, a
  ld a, b
  ld b, c
snm_r:
  ld (sel_r0), a
  ld a, b
  ld (sel_r1), a
  call sel_cur_col
  ld b, a
  ld a, (sel_acol)
  cp b
  jr c, snm_c
  ld c, a
  ld a, b
  ld b, c
snm_c:
  ld (sel_c0), a
  ld a, b
  ld (sel_c1), a
  ret

; ---- SELECT mode input: dpad extends, 1 tap copies,
;      1H + 2 cuts, 2 alone cancels ----
sel_input:
  ld a, (pad_edge)
  and PAD_B2
  jr z, si_no2
  ld a, (pad_raw)
  and PAD_B1
  jp nz, blk_cut             ; 1 held + 2 = cut block
  jp sel_exit                ; 2 alone = cancel
si_no2:
  ld a, (pad_edge)
  and PAD_B1
  jr z, si_1rel
  ld a, 1                    ; arm copy: the entry chord's own
  ld (sel_1press), a         ; release must not fire it
  jr si_dpad
si_1rel:
  ld a, (sel_1press)
  or a
  jr z, si_dpad
  ld a, (pad_raw)
  and PAD_B1
  jr nz, si_dpad
  jp blk_copy                ; armed 1 released = copy block
si_dpad:
  ld a, (pad_rep)
  and $0F
  ret z
  ld c, a
  ; fall through

; extend the selection: step the cursor, renormalize, redraw the
; union of the old and new row spans
sel_move:
  ld a, (sel_r0)
  ld d, a
  ld a, (sel_r1)
  ld e, a
  push de
  call sel_step
  call sel_norm
  pop de
  ld a, (sel_r0)
  cp d
  jr nc, smv_r0
  ld d, a
smv_r0:
  ld a, (sel_r1)
  cp e
  jr c, smv_r1
  ld e, a
smv_r1:
  ; fall through: mark rows D..E dirty

sel_mark_rows:
  ld a, (scr_mode)
  or a
  jr nz, smk_go
  ld a, (song_view)          ; SONG: absolute -> visible
  ld b, a
  ld a, d
  sub b
  jr nc, smk_d
  xor a
smk_d:
  cp 16
  ret nc                     ; span starts below the window
  ld d, a
  ld a, e
  sub b
  ret c                      ; span ends above the window
  cp 16
  jr c, smk_e
  ld a, 15
smk_e:
  ld e, a
smk_go:
  ld a, d
smk_l:
  push de
  call mark_dirty_a
  pop de
  cp e
  ret nc
  inc a
  jr smk_l

; step the cursor (C = dpad bits): clamped, no header entry, no
; column wrap; SONG scrolls and caps the span at 16 rows
sel_step:
  ld a, (scr_mode)
  or a
  jr z, sst_song
  cp SCR_CHAIN
  jr nz, sst_nc
  ld hl, chn_row
  ld de, chn_col
  ld b, 1
  jr sst_grid
sst_nc:
  cp SCR_PHRASE
  jr nz, sst_nt
  ld hl, phr_row
  ld de, phr_col
  ld b, 3
  jr sst_grid
sst_nt:
  ld hl, tbl_row
  ld de, tbl_col
  ld b, 3
sst_grid:
  bit 1, c                   ; down
  jr z, ssg_gup
  ld a, (hl)
  cp 15
  jr nc, ssg_gup
  inc (hl)
ssg_gup:
  bit 0, c                   ; up
  jr z, ssg_grt
  ld a, (hl)
  or a
  jr z, ssg_grt
  dec (hl)
ssg_grt:
  bit 3, c                   ; right
  jr z, ssg_glt
  ld a, (de)
  cp b
  jr nc, ssg_glt
  inc a
  ld (de), a
ssg_glt:
  bit 2, c                   ; left
  ret z
  ld a, (de)
  or a
  ret z
  dec a
  ld (de), a
  ret
sst_song:
  bit 1, c                   ; down
  jr z, ssg_up
  ld a, (song_cur)
  cp SONG_ROWS-1
  jr nc, ssg_up
  inc a
  ld b, a
  ld a, (sel_arow)           ; span cap: the clipboard holds 16
  add a, 15                  ; rows
  cp b
  jr c, ssg_up
  ld a, b
  ld (song_cur), a
ssg_up:
  bit 0, c                   ; up
  jr z, ssg_col
  ld a, (song_cur)
  or a
  jr z, ssg_col
  dec a
  ld b, a
  ld a, (sel_arow)
  sub 15
  jr nc, ssg_upf
  xor a
ssg_upf:
  cp b                       ; floor = max(0, anchor-15)
  jr z, ssg_upok
  jr nc, ssg_col
ssg_upok:
  ld a, b
  ld (song_cur), a
ssg_col:
  bit 3, c
  jr z, ssg_lt
  ld a, (song_col)
  cp 3
  jr nc, ssg_lt
  inc a
  ld (song_col), a
ssg_lt:
  bit 2, c
  jr z, ssg_done
  ld a, (song_col)
  or a
  jr z, ssg_done
  dec a
  ld (song_col), a
ssg_done:
  jp so_scroll               ; keep the cursor in view

; D = column, E = row (absolute on SONG): A = $08 if the cell is
; inside the active selection, else 0
sel_cell_attr:
  ld a, (sel_active)
  or a
  ret z
  ld a, (sel_r0)
  cp e
  jr z, sca_r1
  jr nc, sca_out             ; r0 > row
sca_r1:
  ld a, (sel_r1)
  cp e
  jr c, sca_out              ; r1 < row
  ld a, (sel_c0)
  cp d
  jr z, sca_c1
  jr nc, sca_out
sca_c1:
  ld a, (sel_c1)
  cp d
  jr c, sca_out
  ld a, $08
  ret
sca_out:
  xor a
  ret

; E = row (absolute on SONG) -> HL = first cell of the row
sel_row_ptr:
  ld a, (scr_mode)
  or a
  jr z, srp_song
  cp SCR_CHAIN
  jp z, ch_entry_ptr
  cp SCR_PHRASE
  jp z, ed_step_ptr
  jp tb_entry_ptr
srp_song:
  ld l, e
  ld h, 0
  add hl, hl
  add hl, hl
  ld de, song
  add hl, de
  ret

; HL = this screen's per-column empty values
sel_empties:
  ld a, (scr_mode)
  or a
  jr z, sem_s
  cp SCR_CHAIN
  jr z, sem_c
  cp SCR_PHRASE
  jr z, sem_p
  ld hl, empt_tbl
  ret
sem_s:
  ld hl, empt_song
  ret
sem_c:
  ld hl, empt_chain
  ret
sem_p:
  ld hl, empt_phr
  ret
empt_song:  .db $FF, $FF, $FF, $FF
empt_chain: .db $FF, $00
empt_phr:   .db $00, $FF, $00, $00
empt_tbl:   .db $FF, $00, $00, $00

blk_copy:
  call blk_grab
  jp sel_exit

blk_cut:
  call blk_grab
  call blk_erase
  jp sel_exit

; selection box -> block clipboard
blk_grab:
  ld a, (scr_mode)
  ld (blk_scr), a
  ld a, $FF
  ld (clip_scr), a           ; the field clipboard is stale now
  ld a, (sel_c0)
  ld (blk_c0), a
  ld b, a
  ld a, (sel_c1)
  sub b
  inc a
  ld (blk_w), a
  ld a, (sel_r0)
  ld b, a
  ld (tmp_note), a           ; row walker
  ld a, (sel_r1)
  sub b
  inc a
  ld (blk_h), a
  ld ix, blk_data
bgr_row:
  ld a, (tmp_note)
  ld e, a
  call sel_row_ptr
  ld a, (sel_c0)
  ld e, a
  ld d, 0
  add hl, de
  ld a, (blk_w)
  ld b, a
bgr_col:
  ld a, (hl)
  ld (ix+0), a
  inc hl
  inc ix
  djnz bgr_col
  ld a, (sel_r1)
  ld b, a
  ld a, (tmp_note)
  cp b
  ret nc
  inc a
  ld (tmp_note), a
  jr bgr_row

; write the per-column empties over the selection box
blk_erase:
  ld a, (sel_r0)
  ld (tmp_note), a
ber_row:
  ld a, (tmp_note)
  ld e, a
  call sel_row_ptr
  ld a, (sel_c0)
  ld e, a
  ld d, 0
  add hl, de
  ld a, (sel_c0)
  ld c, a
ber_col:
  push hl
  call sel_empties
  ld b, 0
  add hl, bc
  ld a, (hl)
  pop hl
  ld (hl), a
  inc hl
  ld a, (sel_c1)
  cp c
  jr z, ber_next
  inc c
  jr ber_col
ber_next:
  ld a, (sel_r1)
  ld b, a
  ld a, (tmp_note)
  cp b
  ret nc
  inc a
  ld (tmp_note), a
  jr ber_row

; paste the block: rows anchor at the cursor, columns stay where
; they were cut (keeps every byte on its own column type)
blk_paste:
  ld a, (scr_mode)
  or a
  jr nz, bpp_arm
  ld a, (hdr_cur)
  or a
  ret nz                     ; not onto the song header
bpp_arm:
  call sel_cur_row
  ld (tmp_note), a           ; dest row walker
  ld a, (blk_h)
  ld (tmp_instr), a          ; rows remaining
  ld ix, blk_data
bpp_row:
  ld a, (scr_mode)           ; clamp at the grid bottom
  or a
  jr z, bpp_smax
  ld a, (tmp_note)
  cp 16
  ret nc
  jr bpp_go
bpp_smax:
  ld a, (tmp_note)
  cp SONG_ROWS
  ret nc
bpp_go:
  ld a, (tmp_note)
  ld e, a
  call sel_row_ptr
  ld a, (blk_c0)
  ld e, a
  ld d, 0
  add hl, de
  ld a, (blk_w)
  ld b, a
bpp_col:
  ld a, (ix+0)
  ld (hl), a
  inc ix
  inc hl
  djnz bpp_col
  ld a, (scr_mode)
  or a
  jr nz, bpp_mark
  ld a, (tmp_note)
  call mark_vis_a
  jr bpp_step
bpp_mark:
  ld a, (tmp_note)
  call mark_dirty_a
bpp_step:
  ld a, (tmp_instr)
  dec a
  ld (tmp_instr), a
  ret z
  ld a, (tmp_note)
  inc a
  ld (tmp_note), a
  jr bpp_row

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
  ld a, (cur_flash)          ; clone-fail cursor blink
  or a
  jr z, edf_nofl
  dec a
  ld (cur_flash), a
  call mark_cursor_dirty
edf_nofl:
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
.IFDEF TARGET_GG
  call draw_scrmap           ; map lives in wiped columns - restore it
.ENDIF
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
  cp SCR_PROJ
  jp z, pr_draw_row
  cp SCR_SET
  jp z, st_draw_row
  cp SCR_ECHO
  jp z, et_draw_row
  cp SCR_WAVE
  jp z, wv_draw_row
  cp SCR_FILES
  jp z, fl_draw_row
  jp so_draw_row

; -------------------------------------------------------------
; playhead bookkeeping: compare engine position against what is
; highlighted, mark changed rows dirty
playhead_update:
  ld a, (scr_mode)
  cp SCR_INSTR
  ret z                      ; no playhead on form screens
  cp SCR_PROJ
  ret z
  cp SCR_SET
  ret z
  cp SCR_ECHO
  ret z
  cp SCR_WAVE
  ret z
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
  push hl                    ; playhead = this track's own row (per-channel)
  push de
  ld a, (ed_track)
  ld e, a
  ld d, 0
  ld hl, chan_row
  add hl, de
  ld a, (hl)
  pop de
  pop hl
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
  ld b, NAME_ROW
  ld c, NAME_COL
  ld hl, str_blank
  call print_at
  ld b, GRID_ROW-1           ; the track-header row
  ld c, 1
  ld hl, str_blank
  call print_at
.IFDEF TARGET_GG
  ; the name-row wipe takes the transport text with it
  ld a, 1
  ld (state_dirty), a
.ENDIF
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
  cp SCR_PROJ
  jp z, dl_proj
  cp SCR_SET
  jp z, dl_set
  cp SCR_ECHO
  jp z, dl_echo
  cp SCR_WAVE
  jp z, dl_wave
  cp SCR_FILES
  jp z, dl_files

  ; ---- SONG ----
  ld b, NAME_ROW
  ld c, NAME_COL
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
  ld b, GRID_ROW-1           ; the row above the grid
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
  ld b, NAME_ROW
  ld c, NAME_COL
  ld hl, str_chain
  call print_at
  ld b, NAME_ROW
  ld c, 7
  call nt_addr_hl
  call vdp_set_addr
  ld a, (cur_chain)
  call print_hex_a
  call dl_track_tag
  ld b, GRID_ROW-1
  ld c, 4
  ld hl, str_hphr
  call print_at
  ld b, GRID_ROW-1
  ld c, 8
  ld hl, str_htsp
  call print_at
  ret

dl_phrase:
  ld b, NAME_ROW
  ld c, NAME_COL
  ld hl, str_phrase
  call print_at
  ld b, NAME_ROW              ; phrase # on the name row (matches CHAIN)
  ld c, 8
  call nt_addr_hl
  call vdp_set_addr
  ld a, (cur_phrase)
  call print_hex_a
  call dl_track_tag
  ld b, GRID_ROW-1
  ld c, 4
  ld hl, str_hnote
  call print_at
  ld b, GRID_ROW-1
  ld c, PH_INS_COL            ; over the instrument digit
  ld hl, str_hinstr
  call print_at
  ld b, GRID_ROW-1
  ld c, PH_CMD_COL            ; over the command + param
  ld hl, str_hcmd
  call print_at
  ret

dl_groove:
  ld b, NAME_ROW
  ld c, NAME_COL
  ld hl, str_grv
  call print_at
  xor a                      ; groove-number field: invert when the cursor's on it
  ld (text_attr), a
  ld a, (grv_row)
  cp $FF
  jr nz, dlg_na
  ld a, $08
  ld (text_attr), a
dlg_na:
  ld b, NAME_ROW             ; on the GROOVE label row, after some space
  ld c, 8
  call nt_addr_hl
  call vdp_set_addr
  ld a, (cur_groove)
  call print_hex_a
  xor a
  ld (text_attr), a
  ret

dl_table:
  ld b, NAME_ROW
  ld c, NAME_COL
  ld hl, str_tabl
  call print_at
  ld b, NAME_ROW
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
  ld b, NAME_ROW
  ld c, NAME_COL
  ld hl, str_instr
  call print_at
  ld b, NAME_ROW
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
  ld b, NAME_ROW
  ld c, 12
  call nt_addr_hl
  call vdp_set_addr
  pop hl
  ld b, 2
  jp print_raw

; screen map indicator, top right: current screen inverted.
; grows to S C P I T (+ project/groove) as screens are added.
draw_scrmap:
.IFDEF TARGET_GG
  ld a, (scr_mode)
  or a
  ret z                      ; GG: SONG fills the window width
.ENDIF
  ld a, (scr_mode)           ; the wave editor uses the full
  cp SCR_WAVE                ; width: no map there
  ret z
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
  add a, MAP_COL             ; SCPIT row
  ld c, a
  ld b, MAP_ROW+1
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
  cp 5
  jr c, dsm_l
  ; OPTIONS indicator above the map's S
  ld a, (scr_mode)
  cp SCR_SET
  ld a, $00
  jr nz, dsm_sattr
  ld a, $08
dsm_sattr:
  ld (text_attr), a
  ld b, MAP_ROW
  ld c, MAP_COL
  call nt_addr_hl
  call vdp_set_addr
  ld a, 'O'
  call print_char
  ; PROJECT indicator above the map's C
  ld a, (scr_mode)
  cp SCR_PROJ
  ld a, $00
  jr nz, dsm_pattr
  ld a, $08
dsm_pattr:
  ld (text_attr), a
  ld b, MAP_ROW
  ld c, MAP_COL+1
  call nt_addr_hl
  call vdp_set_addr
  ld a, 'P'
  call print_char
  ; GROOVE indicator below the C
  ld a, (scr_mode)
  cp SCR_GROOVE
  ld a, $00
  jr nz, dsm_gattr
  ld a, $08
dsm_gattr:
  ld (text_attr), a
  ld b, MAP_ROW+2
  ld c, MAP_COL+1
  call nt_addr_hl
  call vdp_set_addr
  ld a, 'G'
  call print_char
  ; FILES indicator below the S
  ld a, (scr_mode)
  cp SCR_FILES
  ld a, $00
  jr nz, dsm_fattr
  ld a, $08
dsm_fattr:
  ld (text_attr), a
  ld b, MAP_ROW+2
  ld c, MAP_COL
  call nt_addr_hl
  call vdp_set_addr
  ld a, 'F'
  call print_char
  ; WAVE indicator above the I
  ld a, (scr_mode)
  cp SCR_WAVE
  ld a, $00
  jr nz, dsm_wattr
  ld a, $08
dsm_wattr:
  ld (text_attr), a
  ld b, MAP_ROW
  ld c, MAP_COL+3
  call nt_addr_hl
  call vdp_set_addr
  ld a, 'W'
  call print_char
  ; ECHO indicator below the I
  ld a, (scr_mode)
  cp SCR_ECHO
  ld a, $00
  jr nz, dsm_eattr
  ld a, $08
dsm_eattr:
  ld (text_attr), a
  ld b, MAP_ROW+2
  ld c, MAP_COL+3
  call nt_addr_hl
  call vdp_set_addr
  ld a, 'E'
  call print_char
  xor a
  ld (text_attr), a
  ; the FILES space readout sits under the map; draw it here so it survives the
  ; GG row-wipe (draw_scrmap is re-run after the rows on GG, like the map)
  ld a, (scr_mode)
  cp SCR_FILES
  jp z, fl_draw_space
.IFDEF TARGET_GG
  ret                        ; GG: col 15 is inside the row wipe -> auto-cleared
.ELSE
  jp fl_clear_space          ; SMS: col 25 escapes the wipe -> blank it explicitly
.ENDIF
map_letters:
  .db "SCPIT"

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
.IFDEF TARGET_GG
  .db 4, 0, 8, 0, 12, 0, 16, 0  ; 20-column window
.ELSE
  .db 5, 0, 10, 0, 15, 0, 20, 0
.ENDIF

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
  ld a, (song_col)
  cp c
  jr nz, sdr_sel
  ld a, (song_cur)
  ld b, a
  ld a, (tmp_note)
  cp b
  jr nz, sdr_sel
  call cursor_attr
  ld (text_attr), a
  jr sdr_val
sdr_sel:
  push de
  ld d, c                    ; track = column
  ld a, (tmp_note)
  ld e, a                    ; absolute row
  call sel_cell_attr
  pop de
  or a
  jr z, sdr_val
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
  ; track markers in the column before the cell: hollow
  ; triangle = queued, solid triangle = playing
  push bc
  push de
  ld hl, live_q
  ld e, c
  ld d, 0
  add hl, de
  ld a, (hl)
  ld b, a
  ld a, (tmp_note)           ; absolute row of this line
  cp b
  ld b, '<'                  ; hollow: queued
  jr z, sdr_mk
  ld hl, drawn_a
  ld e, c
  add hl, de
  ld a, (hl)
  ld b, a
  ld a, (tmp_note)
  cp b
  jr nz, sdr_nmk
  ld b, '>'                  ; solid: playing
  ld hl, live_q              ; ...show a stop glyph if a chain-end stop is queued
  ld e, c
  ld d, 0
  add hl, de
  ld a, (hl)
  cp $FE
  jr nz, sdr_mk
  ld b, 'X'                  ; playing, queued to stop at chain end
sdr_mk:
  ld a, b
  ld (tmp_cmd), a            ; stash the glyph
  ld a, c
  call so_track_col
  dec a
  ld c, a
  pop de
  push de
  ld a, e
  add a, GRID_ROW
  ld b, a
  call nt_addr_hl
  call vdp_set_addr
  xor a
  ld (text_attr), a
  ld a, (tmp_cmd)
  call print_char
sdr_nmk:
  pop de
  pop bc
  inc c
  ld a, c
  cp 4
  jp c, sdr_cell
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
  ld a, (tmp_note)           ; empty row: dash the transpose too
  cp $FF
  jr nz, cdr_tshex
  ld a, '-'
  push de
  call print_char
  ld a, '-'
  call print_char
  pop de
  ret
cdr_tshex:
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
; PROJECT screen row (E = grid row)
pr_draw_row:
  push de
  ld d, 0
  ld hl, prj_r2f
  add hl, de
  ld a, (hl)
  pop de
  cp $FF
  ret z
  ld (ed_field), a
  ; label (col 4)
  xor a
  ld (text_attr), a
  ld a, (ed_field)
  ld d, a
  add a, a
  add a, a
  add a, d                   ; * 5
  push de
  ld e, a
  ld d, 0
  ld hl, prj_lbls
  add hl, de
  pop de
  push hl
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, INS_LBL
  pop hl
  push de
  call print_at
  pop de
  ; value attr
  xor a
  ld (text_attr), a
  ld a, (prj_row)
  ld d, a
  ld a, (ed_field)
  cp d
  jr nz, prd_addr
  ld a, $08
  ld (text_attr), a
prd_addr:
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, INS_VAL
  push de
  call nt_addr_hl
  call vdp_set_addr
  pop de
  ld a, (ed_field)
  or a
  jp z, prd_tempo
  cp 1
  jr z, prd_tsp
  cp 2
  jp z, prd_play
  ret                        ; only fields 0..2 are drawn now
prd_tsp:
  ld a, (proj_tsp)
  or a
  jp m, ptd_neg
  ld b, '+'
  jr ptd_pr
ptd_neg:
  neg
  ld b, '-'
ptd_pr:
  push af
  ld a, b
  call print_char
  pop af
  jp print_hex_a
prd_colr:                    ; palettes are numbered 0-7 (patch the
  ld a, (pal_sel)            ; colours with tools/palette.html)
  call print_hex_nib
  ld a, ' '
  call print_char
  ld a, ' '
  call print_char
  ld a, ' '
  jp print_char
prd_play:
  ld a, (play_mode)
  or a
  ld hl, str_psong
  jr z, prd_pl4
  ld hl, str_plive
prd_pl4:
  ld b, 4
  jp print_raw
prd_sync:
  ld a, (sync_mode)
  add a, a
  ld d, a
  add a, a
  add a, d                   ; * 6
  ld e, a
  ld d, 0
  ld hl, str_syncm
  add hl, de
  ld b, 6
  jp print_raw
.ENDS

; the BPM-from-groove math is cold draw code; parked in bank 1 (always mapped)
; to keep the full bank 0 from overflowing on the tighter GG build.
.BANK 1 SLOT 1
.SECTION "TempoCalc" FREE

prd_tempo:                   ; BPM = rate * count / sum-of-ticks
  call groove_base           ; HL = active groove
  ld d, 0                    ; D = sum of ticks
  ld e, 0                    ; E = count of steps
  ld b, 16
tmd_sum:
  ld a, (hl)
  or a
  jr z, tmd_done
  add a, d
  ld d, a
  inc e
  inc hl
  djnz tmd_sum
tmd_done:
  ld a, e
  or a
  jr z, tmd_zero             ; empty groove
  ld a, (region_pal)
  or a
  ld bc, 900                 ; NTSC ticks-per-min / 60
  jr z, tmd_rate
  ld bc, 750                 ; PAL
tmd_rate:
  ld hl, 0
tmd_mul:
  add hl, bc                 ; HL = rate * count
  dec e
  jr nz, tmd_mul
  xor a                      ; A = quotient (BPM), clears carry
  ld e, d                    ; DE = sum (divisor)
  ld d, 0
tmd_div:
  sbc hl, de
  jr c, tmd_pr               ; HL < sum: done
  inc a
  jr tmd_div
tmd_pr:
  jp print_dec3
tmd_zero:
  xor a
  jp print_dec3

.ENDS

.BANK 1 SLOT 1
.SECTION "ProjDraw2" FREE

prd_video:
  ld a, (vid_sel)            ; 0 AUTO / 1 PAL / 2 NTSC
  add a, a
  add a, a                   ; * 4 (4-char tokens)
  ld e, a
  ld d, 0
  ld hl, str_video
  add hl, de
prd_p4:
  ld b, 4
  jp print_raw
prd_sram:
  ld a, (sram_slots)
  or a
  ld hl, str_snone
  jr z, prd_p4
  cp 1
  ld hl, str_s8k
  jr z, prd_p4
  cp 3
  ld hl, str_s16k
  jr z, prd_p4
  ld hl, str_s32k            ; 6 slots = 32K (two banks)
  jr prd_p4

dl_proj:
  ld b, NAME_ROW
  ld c, NAME_COL
  ld hl, str_proj
  call print_at
  ; status
  ld a, (prj_stat)
  ld d, a
  add a, a
  add a, a
  add a, a
  sub d                      ; * 7
  ld e, a
  ld d, 0
  ld hl, prj_stats
  add hl, de
  push hl
  ld b, 1
  ld c, 10
  call nt_addr_hl
  call vdp_set_addr
  pop hl
  ld b, 7
  jp print_raw

prj_lbls:
  .db "TMPO", 0
  .db "TSP ", 0
  .db "MODE", 0
stg_lbls:
  .db "VID ", 0
  .db "SRAM", 0
  .db "SYNC", 0
  .db "COLR", 0
  .db "CLON", 0
  .db "FM  ", 0
str_slim:   .db "SLIM"
str_deep:   .db "DEEP"
str_fmoff:  .db "OFF "
str_fmon:   .db "ON  "
str_syncm:                   ; indexed by sync_mode*6 (genmddj order)
  .db "OFF   "                ; 0
  .db "OUT   "                ; 1
  .db "PULSE "                ; 2
  .db "IN    "                ; 3
  .db "MIDI  "                ; 4 (reserved; not reachable via the menu)
  .db "IN24  "                ; 5
str_psong:  .db "SONG"
str_plive:  .db "LIVE"
prj_stats:
  .db "       "
  .db "SAVED  "
  .db "LOADED "
  .db "NO SRAM"
  .db "NO DATA"
  .db "SURE?  "
  .db "NEW    "
str_proj:   .db "PROJECT", 0
str_set:    .db "OPTIONS", 0
str_video:                   ; indexed by vid_sel (4-char tokens)
  .db "AUTO"
  .db "PAL "
  .db "NTSC"
str_s8k:    .db "8K  "
str_s32k:   .db "32K "
str_s16k:   .db "16K "
str_snone:  .db "NONE"

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
  call sel_cell_attr
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
  call cursor_attr
  jr cfa_set
cfa_norm:
  call sel_cell_attr
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

  ; instrument (1 char)
  ld a, 1
  call ph_field_attr
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, PH_INS_COL
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
  ; command (1 char)
  ld a, 2
  call ph_field_attr
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, PH_CMD_COL
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

  ; param (2 chars)
  ld a, 3
  call ph_field_attr
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, PH_CMD_COL+1
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
  cp 1
  ld hl, r2f_noise
  jr z, idr_map
  cp 3
  ld hl, r2f_wav
  jr z, idr_map
  cp 2
  ld hl, r2f_smp             ; SMP: only INST/TYPE/TBL/TBS/RATE
  jr z, idr_map
  cp 4
  ld hl, r2f_fm              ; FM: INST/TYPE/VOL/PATCH
  jr z, idr_map
  cp 5
  ld hl, r2f_fmdrum          ; FMDRUM: INST/TYPE/VOL/HLD
  jr z, idr_map
  ld hl, r2f_tone
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
  ; label (col 4); field 12 is WAVE on WAV instruments
  xor a
  ld (text_attr), a
  ld a, (ed_field)
  cp 5
  jr z, idrl_f5              ; field 5: KIT on SMP, else DCY
  cp 13
  jr z, idrl_f13             ; field 13: TSP on SMP, else RATE (NOISE)
  cp 12
  jr nz, idr_lblidx
  call ins_ptr
  ld a, (hl)
  cp 3
  jr z, idrl_wav
  cp 2
  jr z, idrl_smp
  cp 4
  jr z, idrl_fm
  ld a, 12                   ; NOISE field 12: ins_lbls[12]
  jr idr_lblidx
idrl_f5:
  call ins_ptr
  ld a, (hl)
  cp 2                       ; SMP -> "KIT", else DCY (ins_lbls[5])
  jr z, idrl_kit
  ld a, 5
  jr idr_lblidx
idrl_f13:                    ; SMP -> "TSP" (ins_lbls[6]), else RATE (ins_lbls[13])
  call ins_ptr
  ld a, (hl)
  cp 2
  ld a, 6
  jr z, idr_lblidx
  ld a, 13
  jr idr_lblidx
idrl_kit:
  ld hl, str_kitlbl
  jr idr_lblgo
idrl_wav:
  ld hl, str_wavlbl
  jr idr_lblgo
idrl_smp:
  ld hl, str_spdlbl
  jr idr_lblgo
idrl_fm:
  ld hl, str_fmlbl
  jr idr_lblgo
idr_lblidx:
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
idr_lblgo:
  push hl
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, INS_LBL
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
  ld c, INS_VAL
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
  jp z, idr_inst
  cp 1
  jp z, idr_type
  cp 2
  jp z, idr_vol
  cp 3
  jp z, idr_dir
  cp 4
  jp z, idr_spd
  cp 5
  jp z, idr_len
  cp 6
  jp z, idr_tsp
  cp 7
  jp z, idr_swp
  cp 8
  jp z, idr_vib
  cp 9
  jp z, idr_trm
  cp 10
  jp z, idr_tbl
  cp 11
  jp z, idr_tbs
  cp 12
  jp z, idr_f11
  cp 13
  jp z, idr_f13
  cp 14
  jp z, idr_preset
  jp idr_rate
idr_f13:                     ; field 13: SMP transpose (+8), else NOISE rate
  ld a, (hl)                 ; type at +0 (HL = instrument record)
  cp 2
  jp z, idr_tsp
  jp idr_rate
idr_inst:
  ld a, (cur_instr)
  jp print_hex_nib
idr_f11:
  push hl
  call ins_ptr
  ld a, (hl)
  pop hl
  cp 3
  jr z, idrf_wav
  cp 2
  jr z, idrf_smp
  cp 4
  jr z, idrf_fm
  jp idr_mode
idrf_fm:                     ; FM patch 1-15 (instrument +4 low nibble)
  ld de, 4
  add hl, de
  ld a, (hl)
  and $0F
  jp print_hex_nib
idr_preset:                  ; FM custom preset: OFF (0) or a 5-char name
  ld de, 11
  add hl, de
  ld a, (hl)
  or a
  jr nz, idp_name
  ld hl, str_prst_off
  ld b, 5
  jp print_raw
idp_name:
  dec a                      ; preset index 0-7 -> name (5 chars each)
  ld d, a
  add a, a
  add a, a
  add a, d                   ; * 5
  ld e, a
  ld d, 0
  ld hl, fm_preset_names
  add hl, de
  ld b, 5
  jp print_raw
idrf_wav:
  ld de, 4
  add hl, de
  ld a, 'W'
  push hl
  call print_char
  pop hl
  ld a, (hl)
  and $07
  jp print_hex_nib
idrf_smp:
  ld de, 4
  add hl, de
  ld a, (hl)
  cp 4
  jr c, idrf_sok
  xor a
idrf_sok:
  add a, a
  add a, a                   ; * 4 (NORM/2X  /HALF tokens)
  ld e, a
  ld d, 0
  ld hl, str_smpspd
  add hl, de
  ld b, 4
  jp print_raw
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
  or a
  jp nz, print_hex_nib
  ld a, 'N'                  ; TBS 0 = advance one row per triggered note
  jp print_char
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
  cp 1
  ld hl, str_noise
  jr z, idr_p5
  cp 2
  ld hl, str_smp
  jr z, idr_p5
  cp 3
  ld hl, str_wavt
  jr z, idr_p5
  cp 4
  ld hl, str_fm
  jr z, idr_p5
  ld hl, str_fmdrum
idr_p5:
  ld b, 5
  jp print_raw
idr_vol:
  inc hl
  ld a, (hl)
  jp print_hex_nib
idr_dir:                     ; field 3 = ATK (+2 high nibble)
  inc hl
  inc hl
  ld a, (hl)
  rrca
  rrca
  rrca
  rrca
  and $0F
  jp print_hex_nib
idr_spd:                     ; field 4 = HLD (+3 low nibble; F = inf)
  inc hl
  inc hl
  inc hl
  ld a, (hl)
  and $0F
  jp print_hex_nib
idr_len:                     ; field 5 = DCY (+2 low nibble), or KIT 0-7 on SMP
  ld a, (hl)                 ; type at +0
  cp 2
  jr z, idr_kit
  inc hl
  inc hl
  ld a, (hl)
  and $0F
  jp print_hex_nib
idr_kit:                     ; SMP: kit 0-7 in +2, shown 0-7
  inc hl
  inc hl
  ld a, (hl)
  and 7
  jp print_hex_nib
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

.ENDS

; -------------------------------------------------------------
; FM custom presets: a self-describing, marker-delimited block so a
; browser editor can find and rewrite it (like palette.html / the sample
; pool). Header "FMPRST" + version + count, then 8 YM2413 user-patch
; records (8 regs $00-$07 each), then 8 five-char display names. The
; engine reads fm_presets (stride 8); the editor reads fm_preset_names
; (stride 5). Values are a starting palette, tunable here or in the tool.
.BANK 1 SLOT 1
.SECTION "FMPresets" FREE
fm_preset_blk:
  .db "FMPRST", $01, 8        ; magic, format version, preset count
fm_presets:                    ; 8 x 8 bytes = regs $00..$07 (mod/car MULT,
  .db $21,$21,$0E,$07,$F8,$F7,$13,$13   ; 0 LEAD   KSL/TL, FB/wave, AR/DR, SL/RR)
  .db $13,$11,$1A,$00,$F2,$F4,$25,$26   ; 1 EPNO
  .db $31,$61,$0C,$00,$F8,$F8,$28,$29   ; 2 SBASS
  .db $01,$01,$16,$03,$F4,$F2,$13,$14   ; 3 BELL
  .db $21,$22,$1C,$07,$84,$64,$13,$13   ; 4 BRASS
  .db $25,$21,$24,$02,$53,$53,$53,$53   ; 5 PAD
  .db $01,$21,$18,$06,$F8,$F6,$47,$47   ; 6 PLUCK
  .db $21,$21,$3F,$00,$F0,$F0,$0F,$0F   ; 7 SINE
fm_preset_names:               ; 8 x 5 chars (display + web editor labels)
  .db "LEAD "
  .db "EPNO "
  .db "SBASS"
  .db "BELL "
  .db "BRASS"
  .db "PAD  "
  .db "PLUCK"
  .db "SINE "
str_prst_off: .db "OFF  "      ; PRESET = OFF readout (not part of the block)
.ENDS

; form-map tables are cold data: park in bank 1 (read cross-bank).
.BANK 1 SLOT 1
.SECTION "InsForm" FREE

; field index -> grid row (groups separated by spacer rows);
; noise packs tighter to fit MODE/RATE in 16 rows
f2r_tone:
  .db 0, 1, 2, 4, 5, 6, 8, 10, 11, 12, 14, 15
f2r_noise:
  .db 0, 1, 2, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 15
f2r_wav:                     ; field -> grid row (HLD=4 shown; 3,5,7-11 skipped)
  .db 0, 1, 2, 0, 4, 0, 5, 0, 0, 0, 0, 0, 7
; grid row -> field index ($FF = spacer)
r2f_tone:
  .db 0, 1, 2, $FF, 3, 4, 5, $FF, 6, $FF, 7, 8, 9, $FF, 10, 11
r2f_noise:
  .db 0, 1, 2, $FF, 3, 4, 5, $FF, 6, 7, 8, 9, 10, 11, 12, 13
r2f_wav:                     ; INST/TYPE/VOL/HLD/TSP/WAVE (no ATK/DCY/tables)
  .db 0, 1, 2, $FF, 4, 6, $FF, 12, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
; SMP form: VOL/ENV/SPD/LEN/TSP/SWP/VIB/TRM do nothing for samples,
; so show only INST, TYPE, TBL, TBS, RATE.
r2f_smp:                     ; grid row -> field (INST/TYPE/-/KIT/RATE/TSP)
  .db 0, 1, $FF, 5, 12, 13, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
f2r_smp:                     ; field -> grid row (blank row2; KIT=5 r3, RATE=12 r4, TSP=13 r5)
  .db 0, 1, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 4, 5
r2f_fm:                      ; FM, grouped: INST/TYPE/VOL/HLD | TSP | TBL/TBS | PROG/PRST
  .db 0, 1, 2, 4, $FF, 6, $FF, 10, 11, $FF, 12, 14, $FF, $FF, $FF, $FF
f2r_fm:                      ; field -> grid row (spacers after HLD, TSP, TBS)
  .db 0, 1, 2, 0, 3, 0, 5, 0, 0, 0, 7, 8, 10, 0, 11
r2f_fmdrum:                  ; FMDRUM kit: INST/TYPE/VOL/HLD (note picks drum)
  .db 0, 1, 2, $FF, 4, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
f2r_fmdrum:                  ; field -> grid row (0,1,2,4 shown)
  .db 0, 1, 2, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0

.ENDS

; cold instrument labels/strings: park in bank 1 (read cross-bank) to
; keep bank 0 from overflowing as the form grows.
.BANK 1 SLOT 1
.SECTION "InsData" FREE

ins_lbls:
  .db "INST", 0
  .db "TYPE", 0
  .db "VOL ", 0
  .db "ATK ", 0
  .db "HLD ", 0
  .db "DCY ", 0
  .db "TSP ", 0
  .db "SWP ", 0
  .db "VIB ", 0
  .db "TRM ", 0
  .db "TBL ", 0
  .db "TBS ", 0
  .db "MODE", 0
  .db "RATE", 0
  .db "PRST", 0              ; field 14: FM custom-preset selector
str_tone:   .db "TONE "
str_smp:    .db "KIT  "
str_wavt:   .db "WAV  "
str_fm:     .db "FM   "
str_fmdrum: .db "FMDRM"
str_noise:  .db "NOISE"
str_white:  .db "WHITE"
str_perio:  .db "PERIO"
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
  call sel_cell_attr
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
; cycle a command cell alphabetically: A = current command id,
; C = pad bits (right/up = forward). Internal ids never change -
; cmd_rank maps id -> alphabetical rank, cmd_order maps back.
; Preserves HL; clobbers A/DE.
cmd_cycle:
  push hl
  ld hl, cmd_rank
  ld e, a
  ld d, 0
  add hl, de
  ld a, (hl)                 ; current rank
  ld e, a
  ld a, c
  and PAD_RIGHT|PAD_UP
  ld a, e
  jr z, cc_dn
  inc a                      ; forward, wrap
  cp CMD_COUNT
  jr c, cc_set
  xor a
  jr cc_set
cc_dn:
  or a
  jr nz, cc_dec
  ld a, CMD_COUNT-1
  jr cc_set
cc_dec:
  dec a
cc_set:
  ld hl, cmd_order
  ld e, a
  ld d, 0
  add hl, de
  ld a, (hl)                 ; rank -> id
  pop hl
  ret

.ENDS

; command tables are cold lookup data: park them in bank 1 to keep
; bank 0 (full) from overflowing. Read cross-bank via ld hl,.
.BANK 1 SLOT 1
.SECTION "CmdTab" FREE

; rank (alphabetical) -> command id   (B = CMD_WSET sits after A)
cmd_order:
  .db CMD_NONE, CMD_TBL, CMD_WSET, CMD_ARP, CMD_DELAY, CMD_ENV
  .db CMD_FINE, CMD_GRV, CMD_HOP, CMD_ITER, CMD_JTRANS, CMD_KILL
  .db CMD_SLIDE, CMD_TREM, CMD_NOI, CMD_PAN, CMD_PB, CMD_ECHO, CMD_RETRIG
  .db CMD_SPEED, CMD_TPO, CMD_VIB, CMD_WAIT, CMD_VOL, CMD_FMPROG, CMD_PROB
; command id -> rank (inverse of cmd_order)
cmd_rank:
  .db 0, 11, 8, 1, 3, 5, 6, 7, 14, 16, 20, 21, 22, 13, 4, 12, 18, 15, 9, 19, 2, 23, 24, 25, 10, 17

; command id -> display letter
cmd_chars:
  .db "-KHACEFGNPTVWMDLROISBXYZJQ"

.ENDS

.BANK 1 SLOT 1
.SECTION "EdData" FREE

str_song:        .db "SONG", 0
str_chain:       .db "CHAIN", 0
str_phrase:      .db "PHRASE", 0
str_instr:       .db "INSTR", 0
str_tabl:        .db "TABLE", 0
str_grv:         .db "GROOVE", 0
str_hv:          .db "V", 0
str_hpit:        .db "PIT", 0
str_hphr:        .db "PHR", 0
str_htsp:        .db "TSP", 0
str_hnote:       .db "NOTE", 0
str_hinstr:      .db "I", 0
str_hcmd:        .db "CMD", 0
str_blank:       .db "                        ", 0  ; 24 cols: map lives at 25+
str_muted:       .db ".."
track_names:
  .db "T1T2T3NO"

.ENDS

; =============================================================
; FILES screen -- packed song manager (bank 1, slot 1).
; While here, playback is stopped and SRAM stays mapped over the
; pool (files_enter), so the directory is read directly. The list is
; kept packed (valid entries contiguous) with one trailing empty slot
; when there's heap room: SAVE there appends a new file, LOAD there
; blanks the working song. CLEAR shifts the directory down to stay
; packed (the freed heap blob is reclaimed by compaction, a later step).
; =============================================================
.BANK 1 SLOT 1
.SECTION "Files" FREE

files_enter:                 ; entering FILES: stop, map SRAM, ensure a directory
  call engine_stop
  ld a, 1
  ld (state_dirty), a        ; refresh the transport indicator (PLAY -> STOP)
  call smp_abort
  call rle_dir_ensure        ; init the SMDJ4 directory on a fresh cart (maps SRAM)
  call rle_dir_pack          ; normalise any holes -> contiguous packed list
  xor a
  ld (name_col), a
  ld (fmenu), a
  ld (files_row), a
  ld (files_view), a
  jp files_refresh

files_leave:                 ; leaving FILES: restore the pool mapping
  xor a
  ld ($FFFC), a
  ret

; files_refresh: recompute file_count + file_room (the trailing-empty gate) and
; clamp the cursor. Call after entering and after any save/clear. Re-maps SRAM
; (bank 0) for direct directory access on return.
files_refresh:
  call rle_dir_count
  ld (file_count), a
  ld b, a                    ; B = count
  ld a, SD4_DIRN
  cp b
  jr z, fr_noroom            ; directory full -> no trailing slot
  call rle_can_save          ; Z = heap has room for one more
  jr nz, fr_noroom
  ld a, 1
  jr fr_setroom
fr_noroom:
  xor a
fr_setroom:
  ld (file_room), a
  ld a, $08                  ; rle_* may have moved $FFFC; re-map SRAM bank 0
  ld ($FFFC), a
  ; clamp files_row to the max selectable row (count, or count-1 if no room)
  call files_maxrow
  ld b, a
  ld a, (files_row)
  cp b
  jr c, fr_clamped
  ld a, b
  ld (files_row), a
fr_clamped:
  ld a, 1
  ld (label_dirty), a        ; refresh the size readout (used/free changed)
  jp fl_fixview              ; keep the cursor on screen

; files_maxrow -> A = highest selectable (absolute) slot = file_count (when the
; trailing empty slot is shown) else file_count-1. Scrolling keeps it on screen.
files_maxrow:
  ld a, (file_room)
  or a
  ld a, (file_count)
  ret nz                     ; room: max = count (the trailing empty slot)
  or a
  ret z                      ; no room, count 0: max = 0
  dec a                      ; no room: max = count-1
  ret

; fl_fixview: scroll files_view so the cursor (files_row) is on screen.
fl_fixview:
  ld a, (files_row)
  ld b, a
  ld a, (files_view)
  cp b
  jr c, ffv_below            ; view < row -> maybe below the window
  ld a, b                    ; cursor at/above the top: view = row
  ld (files_view), a
  ret
ffv_below:
  add a, FILES_SLOTS-1       ; view + (window-1)
  cp b
  ret nc                     ; cursor already visible
  ld a, b                    ; cursor below the window: view = row - (window-1)
  sub FILES_SLOTS-1
  ld (files_view), a
  ret

; fl_mark_cur: mark the cursor's visible row dirty (absolute slot -> draw row).
fl_mark_cur:
  ld a, (files_view)
  ld b, a
  ld a, (files_row)
  sub b
  add a, FILES_LIST_TOP      ; the list is offset down from the top of the grid
  jp mark_dirty_a

dl_files:                    ; header label (the space readout is in draw_scrmap)
  ld b, NAME_ROW
  ld c, NAME_COL
  ld hl, str_files
  jp print_at

; fl_draw_space: SRAM total / heap used / heap free, in KB, stacked under the
; mini-map (left-aligned to MAP_COL). Drawn from draw_scrmap so it survives the
; GG post-row map restore. Reads the directory (bank 0, mapped during FILES).
fl_draw_space:
  ld hl, str_sram            ; labels, each on its own row under the map
  ld b, MAP_ROW+4
  call fsp_label
  ld hl, str_free
  ld b, MAP_ROW+7
  call fsp_label
  ld hl, str_size
  ld b, MAP_ROW+10
  call fsp_label
  ld hl, (sd4_cap)           ; SRAM = detected capacity
  ld b, MAP_ROW+5
  call fsp_kfix
  call rle_heap_end          ; HL = heap_end (maps bank 0)
  ex de, hl                  ; FREE = cap - heap_end
  ld hl, (sd4_cap)
  or a
  sbc hl, de
  ld b, MAP_ROW+8
  call fsp_kfix
  call fl_selsize            ; SIZE = selected song's blob length
  ld b, MAP_ROW+11
  jp fsp_kfix

.IFNDEF TARGET_GG
; fl_clear_space: blank the readout column (SMS only). Col 25+ is past the 24-col
; per-row wipe, so the SRAM/FREE/SONG block would otherwise linger off the FILES
; screen. Called from draw_scrmap on every non-FILES screen.
fl_clear_space:
  xor a
  ld (text_attr), a
  ld d, MAP_ROW+4
fcs_row:
  ld b, d
  ld c, MAP_COL
  push de
  call nt_addr_hl
  call vdp_set_addr
  pop de
  ld b, 6
fcs_col:
  ld a, ' '
  push bc
  call print_char
  pop bc
  djnz fcs_col
  inc d
  ld a, d
  cp MAP_ROW+12
  jr c, fcs_row
  ret
.ENDIF

; fsp_label: B = row, HL = label (0-term) -> print at (row, MAP_COL).
fsp_label:
  ld c, MAP_COL
  push hl
  call fl_set
  pop hl
  xor a
  ld (text_attr), a
fsp_str:                     ; HL = zero-term string -> print at current address
  ld a, (hl)
  or a
  ret z
  push hl
  call print_char
  pop hl
  inc hl
  jr fsp_str

; fsp_kfix: B = row, HL = byte count -> "NN.NK" (KB, one decimal) at MAP_COL.
fsp_kfix:
  push hl
  ld c, MAP_COL
  call fl_set
  pop hl
  ld a, h                    ; whole KB = value >> 10 = high byte >> 2
  srl a
  srl a
  call fsp_dec2
  ld a, '.'
  call print_char
  ld a, h                    ; tenths = ((value & 1023) * 10) >> 10
  and 3
  ld h, a
  ld d, h
  ld e, l
  add hl, hl
  add hl, hl
  add hl, de
  add hl, hl                 ; (value & 1023) * 10
  ld a, h
  srl a
  srl a
  add a, '0'
  call print_char
  ld a, 'K'
  jp print_char

fsp_dec2:                    ; A (0..99) -> two decimal digits at current address
  ld c, '0'
fd2_t:
  cp 10
  jr c, fd2_done
  sub 10
  inc c
  jr fd2_t
fd2_done:
  add a, '0'
  ld b, a
  ld a, c
  call print_char
  ld a, b
  jp print_char

; fl_selsize: HL = selected song's blob_len, 0 if the cursor is on the empty slot.
fl_selsize:
  ld a, (files_row)
  ld hl, file_count
  cp (hl)
  jr c, fss_have
  ld hl, 0
  ret
fss_have:
  ld a, (files_row)
  call fl_entry
  ld de, 4
  add hl, de
  ld e, (hl)
  inc hl
  ld d, (hl)
  ex de, hl
  ret

str_sram:  .db "SRAM", 0
str_free:  .db "FREE", 0
str_size:  .db "SONG", 0
str_songs: .db "SONGS", 0
str_sure:  .db "SURE "
str_freed: .db "FREED ", 0

; fl_entry: A = slot -> HL = directory entry ptr (SRAM). Preserves DE.
fl_entry:
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl                 ; slot*32
  push de
  ld de, $8000 + SD4_SUPER
  add hl, de
  pop de
  ret

; fl_set: B=row, C=col -> set VDP write address there. Preserves DE.
fl_set:
  push de
  call nt_addr_hl
  call vdp_set_addr
  pop de
  ret

; fl_draw_row: E = visible grid row (0..15). The slot list occupies rows
; [FILES_LIST_TOP, FILES_LIST_TOP+FILES_SLOTS-1]; the action menu (when open)
; sits beside the first rows of it.
fl_draw_row:
  ld a, e
  or a
  jp z, fld_count            ; the top row shows "nn SONGS"
  sub FILES_LIST_TOP
  jp c, fld_menu             ; above the list -> only a menu word, maybe
  cp FILES_SLOTS
  jp nc, fld_menu            ; below the list -> only a menu word, maybe
  ld b, a                    ; list index (0..FILES_SLOTS-1)
  ld a, (files_view)
  add a, b
  ld (fl_slot), a            ; absolute slot shown on this row
  ld hl, file_count
  ld a, (fl_slot)
  cp (hl)
  jr c, fld_show             ; slot < count -> a saved song
  jp nz, fld_menu            ; slot > count -> blank
  ld a, (file_room)          ; slot == count -> trailing empty only if room
  or a
  jp z, fld_menu
fld_show:
  xor a
  ld (text_attr), a
  ld a, e                    ; slot number at col 1 (at this visible row)
  add a, GRID_ROW
  ld b, a
  ld c, 1
  call fl_set
  ld a, (fl_slot)
  push de
  call print_hex_a
  pop de
  ld a, (fl_slot)
  call fl_entry              ; used dot at col 4: '*' / ' '
  ld a, (hl)
  cp $A5
  ld a, $2A
  jr z, fld_dot
  ld a, $20
fld_dot:
  push af
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, 3
  call fl_set
  pop af
  push de
  call print_char
  pop de
  ld a, e                    ; name (8 chars) at col 4 (right after the dot)
  add a, GRID_ROW
  ld b, a
  ld c, 4
  call fl_set
  ld a, (fl_slot)
  call fl_entry
  push de
  ld de, 16
  add hl, de                 ; HL = name ptr
  pop de
  ld b, 8                    ; count
  ld c, 0                    ; position
fld_nm:
  xor a                      ; invert the name cursor on the active slot
  ld (text_attr), a
  ld a, (files_row)
  push hl
  ld hl, fl_slot
  cp (hl)
  pop hl
  jr nz, fld_na
  ld a, (name_col)
  cp c
  jr nz, fld_na
  ld a, $08
  ld (text_attr), a
fld_na:
  ld a, (hl)
  cp $20
  jr nc, fld_pr
  ld a, $20                  ; non-printable -> space
fld_pr:
  push bc
  push de
  push hl
  call print_char
  pop hl
  pop de
  pop bc
  inc hl
  inc c
  djnz fld_nm
fld_menu:
  ; action menu word, aligned with the list (action i beside list row i)
  ld a, (fmenu)
  or a
  ret z
  ld a, e
  sub FILES_LIST_TOP
  ret c
  cp FMENU_N
  ret nc
  ld (fl_slot), a            ; reuse the draw scratch as the action index
  xor a
  ld (text_attr), a
  ld a, (fl_slot)
  ld hl, fmsel
  cp (hl)
  jr nz, flm_na
  ld a, $08
  ld (text_attr), a
flm_na:
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, 9                    ; left of the mini-map (col 25); names sit at 4..11
  call fl_set
  ld a, (purge_ui)           ; armed purge item shows "SURE" instead of its label
  cp 3
  jr c, flm_lbl
  cp $80
  jr nc, flm_lbl
  ld hl, fl_slot
  cp (hl)
  jr nz, flm_lbl
  ld hl, str_sure
  jr flm_draw
flm_lbl:
  ld a, (fl_slot)
  ld b, a
  add a, a
  add a, a
  add a, b                   ; index*5
  ld l, a
  ld h, 0
  ld de, fmenu_str
  add hl, de
flm_draw:
  ld b, 5
flm_w:
  ld a, (hl)
  push hl
  push bc
  call print_char
  pop bc
  pop hl
  inc hl
  djnz flm_w
  ret

fld_count:                   ; "nn SONGS" (or "FREED nn" after a purge)
  xor a
  ld (text_attr), a
  ld a, e
  add a, GRID_ROW
  ld b, a
  ld c, 1
  call fl_set
  ld a, (purge_ui)
  cp $80
  jr z, flc_freed
  ld a, (file_count)
  call fsp_dec2
  ld a, ' '
  call print_char
  ld hl, str_songs
  jp fsp_str
flc_freed:
  ld hl, str_freed           ; "FREED " + nn (same 8-wide footprint)
  call fsp_str
  ld a, (purge_freed)
  jp fsp_dec2

; cm_files: up/down = slot cursor; left/right = name cursor (wraps 0..7).
; When the menu is open, up/down move the menu selection instead.
cm_files:
  ld a, (fmenu)
  or a
  jr z, cmf_normal
  xor a                      ; any menu move cancels a pending purge confirm/result
  ld (purge_ui), a
  bit 1, c                   ; down
  jr z, cmf_menu_up
  ld a, (fmsel)
  cp FMENU_N-1
  jr nc, cmf_menu_up
  inc a
  ld (fmsel), a
cmf_menu_up:
  bit 0, c                   ; up
  jr z, cmf_menu_done
  ld a, (fmsel)
  or a
  jr z, cmf_menu_done
  dec a
  ld (fmsel), a
cmf_menu_done:
  jp mark_all_dirty
cmf_normal:                  ; plain dpad: up/down move the slot cursor
  ld a, 1
  ld (label_dirty), a        ; the SIZE readout follows the selection
  push bc
  call fl_mark_cur           ; old cursor row dirty
  pop bc
  bit 1, c                   ; down
  jr z, cmf_up
  call files_maxrow          ; highest selectable slot (list + trailing empty)
  ld b, a
  ld a, (files_row)
  cp b
  jr nc, cmf_up
  inc a
  ld (files_row), a
cmf_up:
  bit 0, c                   ; up
  jr z, cmf_done
  ld a, (files_row)
  or a
  jr z, cmf_done
  dec a
  ld (files_row), a
cmf_done:                    ; scroll to follow the cursor
  ld a, (files_view)
  ld b, a
  call fl_fixview
  ld a, (files_view)
  cp b
  jp nz, mark_all_dirty      ; view scrolled -> redraw the page
  jp fl_mark_cur             ; same view -> just mark the new cursor row

; fe_edit: FILES "1 held + dpad" (do_edit). up/down cycle the letter at the
; cursor through fe_charset (blank, A-Z, specials, 0-9).
fe_edit:
  ld a, (fmenu)
  or a
  ret nz                     ; menu open: don't edit the name
  ld a, (ed_rep)
  ld c, a                    ; C = dpad bits
  and PAD_LEFT|PAD_RIGHT
  jr z, fe_letter
  bit 3, c                   ; right: name cursor +1 (wrap)
  jr z, fe_posl
  ld a, (name_col)
  inc a
  and $07
  ld (name_col), a
fe_posl:
  bit 2, c                   ; left: name cursor -1 (wrap)
  jr z, fe_posdone
  ld a, (name_col)
  dec a
  and $07
  ld (name_col), a
fe_posdone:
  jp fl_mark_cur
fe_letter:
  ld a, c
  and PAD_UP|PAD_DOWN
  ret z
  ld b, a                    ; B = direction (bit0 up, bit1 down)
  ld a, (files_row)
  call fl_entry              ; A = slot -> HL = entry, preserves DE
  ld de, 16
  add hl, de
  ld a, (name_col)
  ld e, a
  ld d, 0
  add hl, de                 ; HL = char ptr (SRAM)
  push hl
  ld a, (hl)
  ld c, a                    ; C = current char
  ld hl, fe_charset          ; find its index in the charset
  ld d, 0
fee_find:
  ld a, (hl)
  cp c
  jr z, fee_found
  inc hl
  inc d
  ld a, d
  cp FE_CHARLEN
  jr c, fee_find
  ld d, 0                    ; not in the set -> blank (index 0)
fee_found:
  bit 0, b                   ; up = next, down = prev (wrap)
  jr z, fee_dn
  ld a, d
  inc a
  cp FE_CHARLEN
  jr c, fee_set
  xor a
  jr fee_set
fee_dn:
  ld a, d
  or a
  jr nz, fee_decn
  ld a, FE_CHARLEN
fee_decn:
  dec a
fee_set:
  ld e, a                    ; char = fe_charset[index]
  ld d, 0
  ld hl, fe_charset
  add hl, de
  ld a, (hl)
  pop hl                     ; char ptr
  ld (hl), a
  jp fl_mark_cur

; fp_files: 1-tap on FILES. In menu mode, run the selected action + close.
; The trailing empty slot (files_row == file_count) is the "new file" target:
; SAVE there appends; LOAD there blanks the working song (replaces the old NEW).
fp_files:
  ld a, (fmenu)
  or a
  ret z                      ; not in the menu: nothing
  ld a, (fmsel)
  cp 3
  jr z, fpx_prgp             ; 3 PRGP: purge unreachable phrases (2-tap confirm)
  cp 4
  jr z, fpx_prgc             ; 4 PRGC: purge unused chains (2-tap)
  xor a                      ; SAVE/LOAD/CLEA/CANC clear any purge confirm/result
  ld (purge_ui), a
  ld a, (fmsel)
  or a
  jr z, fpx_save             ; 0 SAVE
  cp 1
  jr z, fpx_load             ; 1 LOAD
  cp 2
  jr z, fpx_clear            ; 2 CLEAR
  jr fpx_close               ; 5 CANCEL (and anything else): close, no-op
fpx_prgp:
  ld a, (purge_ui)
  cp 3
  jr z, fpp_runp             ; second tap (armed) -> run it
  ld a, 3                    ; first tap -> arm: the word shows SURE
  ld (purge_ui), a
  jp mark_all_dirty
fpp_runp:
  call purge_phrases
  jr fpp_done
fpx_prgc:
  ld a, (purge_ui)
  cp 4
  jr z, fpp_runc
  ld a, 4
  ld (purge_ui), a
  jp mark_all_dirty
fpp_runc:
  call purge_chains
fpp_done:
  ld a, $80                  ; show FREED nn (menu stays open)
  ld (purge_ui), a
  jp mark_all_dirty
fpx_load:
  ld a, (files_row)          ; LOAD on the trailing empty slot = blank canvas
  ld hl, file_count
  cp (hl)
  jr c, fpl_file
  call song_new
  jr fpx_close
fpl_file:
  ld a, (files_row)
  call rle_song_load
  jr fpx_close
fpx_save:
  ld a, (files_row)          ; song_name = the slot's inline-edited name
  call fl_entry
  ld de, 16
  add hl, de
  ld de, song_name
  ld bc, 8
  ldir
  ld a, (files_row)
  call rle_song_save         ; slot == file_count appends a new file
  call config_save           ; persist OPTIONS (palette/sync/video/FM) too
  jr fpx_refresh             ; the saved-song count may have grown
fpx_clear:
  ld a, (files_row)          ; CLEAR only acts on an existing file
  ld hl, file_count
  cp (hl)
  jr nc, fpx_close           ; trailing empty / blank row: nothing to clear
  ld a, (files_row)
  call rle_song_delete       ; shift the directory down (kept packed)
fpx_refresh:
  xor a
  ld (fmenu), a
  call files_refresh         ; recompute count/room, clamp cursor, re-map SRAM
  jp mark_all_dirty
fpx_close:
  ld a, $08                  ; rle_* may have moved $FFFC; re-map SRAM bank 0
  ld ($FFFC), a
  xor a
  ld (fmenu), a
  jp mark_all_dirty

; fc_files: 1-hold+2 on FILES. Toggle the action menu.
fc_files:
  ld a, (fmenu)
  xor 1
  ld (fmenu), a
  xor a
  ld (fmsel), a
  ld (purge_ui), a           ; clear any pending purge confirm/result
  jp mark_all_dirty

str_files:   .db "FILES", 0
; name charset, in cycle order: blank, A-Z, specials, 0-9
fe_charset:
  .db " ABCDEFGHIJKLMNOPQRSTUVWXYZ-_.!?#:+=*/@()<>0123456789"
fe_charset_end:
.DEFINE FE_CHARLEN fe_charset_end - fe_charset
fmenu_str:                   ; action menu, 5 chars each (indexed E*5)
  .db "SAVE "
  .db "LOAD "
  .db "CLEAR"
  .db "PURGP"                ; purge unreachable phrases
  .db "PURGC"                ; purge unused chains
  .db "CANC "
.DEFINE FMENU_N 6

; ---- PURGE: blank orphaned (unreferenced) chains / phrases so they drop out of
; the compressed save and free their pool slots. Clear-only -- never renumber, so
; every song->chain#/chain->phrase# reference stays valid. Acts on the working
; song in RAM; the user saves afterwards to bank the smaller image. purge_freed
; counts only records that were non-empty and got blanked. Returns A = freed.

; HL = chains + C*32
purge_chain_ptr:
  ld l, c
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl                 ; *32
  ld de, chains
  add hl, de
  ret

; HL = phrase_pool + C*64
purge_phrase_ptr:
  ld l, c
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl                 ; *64
  ld de, phrase_pool
  add hl, de
  ret

; clear purge_used[0..NUM_PHRASES-1] (covers chains too: 52 >= 40)
purge_clear_used:
  ld hl, purge_used
  ld b, NUM_PHRASES
  xor a
pcu_l:
  ld (hl), a
  inc hl
  djnz pcu_l
  xor a
  ld (purge_freed), a
  ret

purge_chains:
  call purge_clear_used
  ; mark every chain placed in the SONG
  ld hl, song
  ld de, SONG_ROWS*4
pgc_scan:
  ld a, (hl)
  inc hl
  cp NUM_CHAINS              ; $FF (empty) or out of range -> no chain
  jr nc, pgc_snext
  push hl
  ld c, a
  ld b, 0
  ld hl, purge_used
  add hl, bc
  ld (hl), 1
  pop hl
pgc_snext:
  dec de
  ld a, d
  or e
  jr nz, pgc_scan
  ; blank unused, non-empty chains
  ld c, 0
pgc_blank:
  ld a, c
  cp NUM_CHAINS
  jr nc, pgc_ret
  ld b, 0
  ld hl, purge_used
  add hl, bc
  ld a, (hl)
  or a
  jr nz, pgc_bnext           ; referenced -> keep
  call purge_chain_ptr       ; HL = chain
  ; empty already? (all 16 steps' phrase# == $FF)
  push hl
  ld b, 16
pgc_emp:
  ld a, (hl)
  inc a                      ; $FF -> 0
  jr nz, pgc_ne
  inc hl
  inc hl
  djnz pgc_emp
  pop hl                     ; already blank -> nothing freed
  jr pgc_bnext
pgc_ne:
  pop hl
  ld b, 32                   ; blank: 32 x $FF
pgc_fill:
  ld (hl), $FF
  inc hl
  djnz pgc_fill
  ld hl, purge_freed
  inc (hl)
pgc_bnext:
  inc c
  jr pgc_blank
pgc_ret:
  ld a, (purge_freed)
  ret

purge_phrases:
  call purge_clear_used
  ; mark phrases reachable from the SONG (song -> placed chains -> their steps)
  ld hl, song
  ld de, SONG_ROWS*4
pgp_scan:
  ld a, (hl)
  inc hl
  cp NUM_CHAINS
  jr nc, pgp_snext
  push hl
  push de
  ld c, a
  call purge_chain_ptr       ; HL = chain c
  ld b, 16
pgp_step:
  ld a, (hl)                 ; phrase #
  cp NUM_PHRASES
  jr nc, pgp_stn
  push hl
  push bc
  ld c, a
  ld b, 0
  ld hl, purge_used
  add hl, bc
  ld (hl), 1
  pop bc
  pop hl
pgp_stn:
  inc hl
  inc hl
  djnz pgp_step
  pop de
  pop hl
pgp_snext:
  dec de
  ld a, d
  or e
  jr nz, pgp_scan
  ; blank unreachable, non-empty phrases
  ld c, 0
pgp_blank:
  ld a, c
  cp NUM_PHRASES
  jr nc, pgp_ret
  ld b, 0
  ld hl, purge_used
  add hl, bc
  ld a, (hl)
  or a
  jr nz, pgp_bnext
  call purge_phrase_ptr      ; HL = phrase
  ; empty already? (every row note==0 && instr==$FF && cmd==0)
  push hl
  ld b, 16
pgp_emp:
  ld a, (hl)                 ; note
  or a
  jr nz, pgp_ne
  inc hl
  ld a, (hl)                 ; instr
  inc a
  jr nz, pgp_ne              ; instr != $FF
  inc hl
  ld a, (hl)                 ; cmd
  or a
  jr nz, pgp_ne
  inc hl
  inc hl
  djnz pgp_emp
  pop hl                     ; already blank
  jr pgp_bnext
pgp_ne:
  pop hl
  ld b, 16                   ; blank: 16 rows of 0,$FF,0,0
pgp_fill:
  ld (hl), 0
  inc hl
  ld (hl), $FF
  inc hl
  ld (hl), 0
  inc hl
  ld (hl), 0
  inc hl
  djnz pgp_fill
  ld hl, purge_freed
  inc (hl)
pgp_bnext:
  inc c
  jr pgp_blank
pgp_ret:
  ld a, (purge_freed)
  ret

.ENDS
