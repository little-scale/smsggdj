; =============================================================
; SMSDJ - LSDJ-inspired tracker for the Sega Master System
; Milestone 4: PHRASE editor (first playable build)
;   - cursor over note/instrument/command/param columns
;   - insert, edit, cut with the 2-button scheme + hold timing
;   - prelisten on entry while stopped, live edit while playing
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
.DEFINE GRID_ROW    4            ; first screen row of the grid

; =============================================================
.RAMSECTION "vars" SLOT 3
  vblank_flag    db
  nmi_event      db
  state_dirty    db
  region_pal     db            ; 1 = PAL
  frame         dw
  pad_raw        db
  pad_prev       db
  pad_edge       db
  pad_rep        db
  das_timer      db
  ints_on        db           ; init done: helpers may EI
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
  ex af, af'
  in a, (VDP_CTRL)             ; ack (IN A,(n) sets no flags!)
  rlca                         ; bit 7 -> carry
  jp c, irq_frame
  ; ---- line interrupt: feed one sample nibble ----
  ld a, (smp_active)
  or a
  jr z, irq_ldone
  exx
  call smp_feed_one
  exx
irq_ldone:
  ex af, af'
  ei
  reti
irq_frame:
  ; while a sample plays, feed it through the whole vblank
  ; (cycle-counted; the line counter only runs in active display)
  ld a, (smp_active)
  or a
  jr z, irq_fdone
  exx
  call smp_vblank_feed
  exx
irq_fdone:
  ld a, 1
  ld (vblank_flag), a
  ex af, af'
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
  call editor_init
  call sram_detect
  ld a, (sram_ok)
  or a
  call nz, song_load         ; autoload a saved song
  xor a
  ld (prj_stat), a

  ; region-specific note table
  ld hl, note_table_ntsc
  ld a, (region_pal)
  or a
  jr z, init_nt
  ld hl, note_table_pal
init_nt:
  ld (note_ptr), hl
  ld a, 150                  ; default tempo display by region
  ld b, a
  ld a, (region_pal)
  or a
  jr z, init_bpm
  ld b, 125
init_bpm:
  ld a, b
  ld (proj_bpm), a
  ; vblank sample budget: (lines-192)/2
  ld a, (region_pal)
  or a
  ld a, 35                   ; NTSC: 70 vblank lines
  jr z, init_vbc
  ld a, 60                   ; PAL: 121 vblank lines
init_vbc:
  ld (smp_vbcnt), a

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

  ; key hints
  ld b, 21
  ld c, 1
  ld hl, str_hint1
  call print_at
  ld b, 22
  ld c, 1
  ld hl, str_hint2
  call print_at

  ld a, 1
  ld (state_dirty), a

  ; pre-paint the whole grid while the display is off
  ld b, 4
init_paint:
  push bc
  call editor_draw
  pop bc
  djnz init_paint

  call display_on
  ld a, 1
  ld (ints_on), a
  ei

  ; show the region line briefly at boot, then reclaim the row
  ld b, 90
init_wait:
  halt
  djnz init_wait
  ld b, 2
  ld c, 1
  ld hl, str_blank
  call print_at
  ld a, 1
  ld (state_dirty), a

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
  call draw_state
  call editor_draw

  ; --- logic ---
  call read_input
  call handle_pause
  call editor_input
  call smp_housekeep
  call engine_frame
  ld a, (play_state)
  or a
  call z, channels_fx          ; prelisten envelopes while stopped
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
; transport
; =============================================================
handle_pause:                  ; PAUSE = transport alias
  ld a, (nmi_event)
  or a
  ret z
  xor a
  ld (nmi_event), a
  ; fall through

toggle_play:
  ld a, (play_state)
  or a
  jr z, tp_start
  call engine_stop
  jr tp_dirty
tp_start:
  ld a, (scr_mode)           ; transport context (design doc 3):
  cp SCR_INSTR               ; SONG/CHAIN/PHRASE play themselves,
  jr c, tp_go                ; INSTR/TABLE loop the phrase for
  cp SCR_GROOVE              ; auditioning, GROOVE/PROJECT play
  jr c, tp_phr               ; the whole song
  ld a, MODE_SONG
  jr tp_go
tp_phr:
  ld a, MODE_PHRASE
tp_go:
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

; =============================================================
; strings
; =============================================================
str_title:       .db "SMSDJ V0.1", 0
str_region_pal:  .db "REGION: PAL 50HZ ", 0
str_region_ntsc: .db "REGION: NTSC 60HZ", 0
str_play:        .db "PLAY", 0
str_stop:        .db "STOP", 0
str_rest:        .db "---"
str_hint1:       .db "1=INS 2X1=PASTE 1H+2=CUT", 0
str_hint2:       .db "2+L/R=SCREEN 2H+1=PLAY", 0

.ENDS

.INCLUDE "src/vdp.asm"
.INCLUDE "src/input.asm"
.INCLUDE "src/psg.asm"
.INCLUDE "src/engine.asm"
.INCLUDE "src/sample.asm"
.INCLUDE "src/editor.asm"
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

.SECTION "SamplePool" FREE
.INCLUDE "pool.inc"
sample_pool:
  .INCBIN "pool.bin"
.ENDS
