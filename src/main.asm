; =============================================================
; SMSDJ - LSDJ-inspired tracker for the Sega Master System
; Milestone 3: sequencer engine core
;   - groove-driven phrase playback on all 4 tracks
;   - software envelopes, K (kill) command
;   - tick-source abstraction (internal 50/60 Hz)
;   - 4-track phrase view with palette-bit playhead
; =============================================================

.MEMORYMAP
DEFAULTSLOT 0
SLOT 0 $0000 $4000
SLOT 1 $4000 $4000
SLOT 2 $8000 $4000
SLOT 3 $C000 $2000
.ENDME

.ROMBANKMAP
BANKSTOTAL 2
BANKSIZE $4000
BANKS 2
.ENDRO

.SMSTAG

; ---- hardware ports ----
.DEFINE VDP_DATA    $BE
.DEFINE VDP_CTRL    $BF
.DEFINE VDP_VCNT    $7E
.DEFINE IO_PORT_A   $DC

.DEFINE NT_WADDR    $7800        ; name table $3800 | $4000 (write)

; pad bits (port $DC, active low -> inverted after read)
.DEFINE PAD_UP      $01
.DEFINE PAD_DOWN    $02
.DEFINE PAD_LEFT    $04
.DEFINE PAD_RIGHT   $08
.DEFINE PAD_B1      $10
.DEFINE PAD_B2      $20

; key repeat (frames)
.DEFINE DAS_DELAY   14
.DEFINE DAS_SPEED   3

; phrase grid layout
.DEFINE GRID_ROW    5            ; first screen row of the grid

; =============================================================
.RAMSECTION "vars" SLOT 3
  vblank_flag    db
  nmi_event      db
  state_dirty    db
  combo_latch    db
  region_pal     db            ; 1 = PAL
  frame         dw
  pad_raw        db
  pad_prev       db
  pad_edge       db
  pad_rep        db
  das_timer      db
  text_attr      db            ; $00 normal, $08 inverted (palette bit)
  note_ptr       dw            ; active region note table
.ENDS

; =============================================================
; vectors
; =============================================================
.BANK 0 SLOT 0

.ORGA $0000
.SECTION "Boot" FORCE
  di
  im 1
  ld sp, $DFF0
  jp init
.ENDS

.ORGA $0038
.SECTION "IRQ" FORCE
irq_handler:
  push af
  in a, (VDP_CTRL)             ; ack frame interrupt
  ld a, 1
  ld (vblank_flag), a
  pop af
  ei
  reti
.ENDS

.ORGA $0066
.SECTION "NMI" FORCE
nmi_handler:                   ; PAUSE: set a flag, nothing else
  push af
  ld a, 1
  ld (nmi_event), a
  pop af
  retn
.ENDS

; =============================================================
; init
; =============================================================
.SECTION "Main" FREE

init:
  ; standard Sega mapper init
  xor a
  ld ($FFFC), a
  ld ($FFFD), a
  inc a
  ld ($FFFE), a
  inc a
  ld ($FFFF), a

  ; clear work RAM (below stack)
  ld hl, $C000
  ld de, $C001
  ld bc, $1FEE
  ld (hl), 0
  ldir

  call detect_region
  call psg_init
  call vdp_init
  call vdp_clear_vram
  call load_font
  call load_palette
  call song_init

  ; region-specific note table
  ld hl, note_table_ntsc
  ld a, (region_pal)
  or a
  jr z, init_nt
  ld hl, note_table_pal
init_nt:
  ld (note_ptr), hl

  ; ---- static screen ----
  xor a
  ld (text_attr), a
  ld b, 0
  ld c, 1
  ld hl, str_title
  call print_at

  ld hl, str_region_ntsc
  ld a, (region_pal)
  or a
  jr z, init_region_pr
  ld hl, str_region_pal
init_region_pr:
  ld b, 2
  ld c, 1
  call print_at

  ; track headers
  ld b, 4
  ld c, 3
  ld hl, str_t1
  call print_at
  ld b, 4
  ld c, 10
  ld hl, str_t2
  call print_at
  ld b, 4
  ld c, 17
  ld hl, str_t3
  call print_at
  ld b, 4
  ld c, 24
  ld hl, str_no
  call print_at

  call draw_grid

  ld b, 22
  ld c, 1
  ld hl, str_hint
  call print_at

  ld a, 1
  ld (state_dirty), a

  call display_on
  ei

; =============================================================
; main loop
; =============================================================
main_loop:
  halt
  ld a, (vblank_flag)
  or a
  jr z, main_loop
  xor a
  ld (vblank_flag), a

  ; --- VRAM updates first, while we are in vblank ---
  call draw_frame_counter
  call draw_playhead
  call draw_state

  ; --- logic ---
  call read_input
  call update_transport
  call engine_frame
  call psg_flush

  ld hl, (frame)
  inc hl
  ld (frame), hl
  jr main_loop

; =============================================================
; region detection: max VCounter over ~15 frames
; PAL 192-line max = $F2, NTSC max = $DA -> threshold $E0.
; Anything odd falls back to PAL (project default).
; =============================================================
detect_region:
  ld bc, $4000
  ld e, 0
dr_loop:
  in a, (VDP_VCNT)
  cp e
  jr c, dr_nomax
  ld e, a
dr_nomax:
  dec bc
  ld a, b
  or c
  jr nz, dr_loop
  ld a, e
  cp $E0
  ld a, 1                      ; assume PAL
  jr nc, dr_store
  ld a, e
  cp $D0                       ; sane NTSC max?
  ld a, 0
  jr nc, dr_store
  ld a, 1                      ; implausible -> PAL fallback
dr_store:
  ld (region_pal), a
  ret

; =============================================================
; transport: PAUSE (NMI flag) or 1+2 pressed together
; =============================================================
update_transport:
  ld a, (nmi_event)
  or a
  jr z, ut_combo
  xor a
  ld (nmi_event), a
  call toggle_play
ut_combo:
  ld a, (pad_raw)
  and PAD_B1|PAD_B2
  cp PAD_B1|PAD_B2
  jr nz, ut_release
  ld a, (combo_latch)
  or a
  ret nz
  ld a, 1
  ld (combo_latch), a
  jp toggle_play
ut_release:
  xor a
  ld (combo_latch), a
  ret

toggle_play:
  ld a, (play_state)
  or a
  jr z, tp_start
  call engine_stop
  jr tp_dirty
tp_start:
  call engine_play
tp_dirty:
  ld a, 1
  ld (state_dirty), a
  ret

; =============================================================
; drawing
; =============================================================
draw_frame_counter:
  ld b, 0
  ld c, 27
  call nt_addr_hl
  call vdp_set_addr
  ld a, (frame+1)
  call print_hex_a
  ld a, (frame)
  call print_hex_a
  ret

draw_state:
  ld a, (state_dirty)
  or a
  ret z
  xor a
  ld (state_dirty), a
  ld a, (play_state)
  or a
  jr nz, ds_play
  xor a
  ld (text_attr), a
  ld hl, str_stop
  jr ds_print
ds_play:
  ld a, $08
  ld (text_attr), a
  ld hl, str_play
ds_print:
  ld b, 2
  ld c, 26
  call print_at
  xor a
  ld (text_attr), a
  ret

; full 16-row grid: row labels + note names for all tracks
draw_grid:
  ld d, 0                      ; phrase row
dg_row:
  ; row label (hex)
  ld a, d
  add a, GRID_ROW
  ld b, a
  ld c, 1
  push de
  call nt_addr_hl
  call vdp_set_addr
  pop de
  ld a, d
  push de
  call print_hex_nib
  pop de
  ; note columns
  xor a
  ld (text_attr), a
  ld e, d
  call draw_phrase_row
  inc d
  ld a, d
  cp 16
  jr c, dg_row
  ret

; redraw row E of all 4 tracks using current text_attr
draw_phrase_row:
  ld c, 0                      ; channel
dpr_ch:
  push bc
  push de
  ; HL = 3-char string for (channel C, row E)
  call step_note_str
  push hl
  ; screen position
  ld a, c
  ld hl, track_cols
  ld e, a
  ld d, 0
  add hl, de
  ld c, (hl)
  pop hl
  pop de
  push de
  ld a, e
  add a, GRID_ROW
  ld b, a
  push hl
  call nt_addr_hl
  call vdp_set_addr
  pop hl
  ld b, 3
  call print_raw
  pop de
  pop bc
  inc c
  ld a, c
  cp 4
  jr c, dpr_ch
  ret

track_cols:
  .db 3, 10, 17, 24

; C = channel, E = phrase row -> HL = 3-char note string
step_note_str:
  ld a, c
  add a, a
  push de
  ld e, a
  ld d, 0
  ld hl, phrase_ptrs
  add hl, de
  ld a, (hl)
  inc hl
  ld h, (hl)
  ld l, a                     ; hl = phrase base
  pop de
  ld a, e
  add a, a
  add a, a                    ; row * 4
  push de
  ld e, a
  ld d, 0
  add hl, de
  pop de
  ld a, (hl)                  ; note byte
  or a
  jr z, sns_rest
  dec a
  ld l, a
  add a, a
  add a, l                    ; * 3
  push de
  ld e, a
  ld d, 0
  ld hl, note_names
  add hl, de
  pop de
  ret
sns_rest:
  ld hl, str_rest
  ret

; move the inverse-video playhead when the row changes
draw_playhead:
  ld a, (play_state)
  or a
  ret z
  ld a, (cur_row)
  ld b, a
  ld a, (drawn_row)
  cp b
  ret z
  ; un-highlight old row (if any)
  cp $FF
  jr z, dp_new
  ld e, a
  xor a
  ld (text_attr), a
  call draw_phrase_row
dp_new:
  ld a, $08
  ld (text_attr), a
  ld a, (cur_row)
  ld e, a
  call draw_phrase_row
  ld a, (cur_row)
  ld (drawn_row), a
  xor a
  ld (text_attr), a
  ret

; =============================================================
; strings
; =============================================================
str_title:       .db "SMSDJ V0.1", 0
str_region_pal:  .db "REGION: PAL 50HZ ", 0
str_region_ntsc: .db "REGION: NTSC 60HZ", 0
str_t1:          .db "T1", 0
str_t2:          .db "T2", 0
str_t3:          .db "T3", 0
str_no:          .db "NO", 0
str_play:        .db "PLAY", 0
str_stop:        .db "STOP", 0
str_rest:        .db "---"
str_hint:        .db "1+2 OR PAUSE = PLAY/STOP", 0

.ENDS

.INCLUDE "src/vdp.asm"
.INCLUDE "src/input.asm"
.INCLUDE "src/psg.asm"
.INCLUDE "src/engine.asm"
.INCLUDE "notes.inc"

; =============================================================
; font (generated by tools/makefont.py)
; =============================================================
.BANK 1 SLOT 1
.SECTION "Font" FREE
font_data:
  .INCBIN "font.bin"
font_data_end:
.ENDS
