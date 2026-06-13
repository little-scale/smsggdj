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
BANKSTOTAL 8
BANKSIZE $4000
BANKS 8
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

; =============================================================
; build flavor. TARGET_GG = native Game Gear ROM: the LCD shows a
; 20x18-tile window of the 256x192 frame starting at tile (6,3),
; so the whole UI shifts there (nt_addr_hl applies UI_X/UI_Y) and
; the chrome compresses into two header rows. The WAVE screen is
; not reachable on GG yet (32-step canvas needs its own layout).
.IFDEF TARGET_GG
.DEFINE UI_X        6
.DEFINE UI_Y        3
.DEFINE GRID_ROW    2            ; first window row of the grid
.DEFINE STATE_ROW   0            ; PLAY/STOP/WAIT
.DEFINE STATE_COL   14
.DEFINE SYNC_COL    19           ; sync symbol
.DEFINE NAME_ROW    0            ; screen name row
.DEFINE NAME_COL    0
.ELSE
.DEFINE UI_X        0
.DEFINE UI_Y        0
.DEFINE GRID_ROW    4
.DEFINE STATE_ROW   2
.DEFINE STATE_COL   26
.DEFINE SYNC_COL    31
.DEFINE NAME_ROW    1
.DEFINE NAME_COL    1
.DEFINE REGION_ROW  2
.DEFINE REGION_COL  1
.ENDIF

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
  pal_sel        db           ; colour scheme (pal_presets index)
  start_prev     db           ; GG START level last frame
  region_timer   db           ; frames left on the boot region line
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
  ; ---- line interrupt: feed one sample/wave tick ----
  ld a, (smp_active)
  or a
  jr z, irq_ldone
  exx
  call smp_feed_any
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

.IFDEF TARGET_GG
  xor a                      ; GG hardware is NTSC-clocked
  ld (region_pal), a
.ENDIF
  call psg_init
  call vdp_init
  call vdp_clear_vram
  ld a, 6                    ; KIDD is the house palette
  ld (pal_sel), a
  call load_palette          ; the splash renders in it too
  call load_font
  call splash                ; logo + version; SMS region detect inside
.IFDEF DEMO_MODE
  call song_init             ; demo build: the demo song
.ELSE
  call song_new              ; normal build: a blank song
.ENDIF
  call editor_init
  ; sample pool directory (bank 2 sits in slot 2 from boot)
  xor a
  ld (smp_count), a
  ld a, ($8000)
  cp 'S'
  jr nz, init_nopool
  ld a, ($8005)
  ld (smp_count), a
init_nopool:
  call sram_detect
  ; boot lands on the ROM demo (no slot-1 autoload for now: a
  ; first power-on should make sound - saves load via PROJECT)
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
  ld hl, winc_table_ntsc
  ld a, (region_pal)
  or a
  jr z, init_wi
  ld hl, winc_table_pal
init_wi:
  ld (winc_ptr), hl
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
  ld a, 34                   ; NTSC: 70 vblank lines, minus one
  jr z, init_vbc             ; slot of slack - overrunning into
  ld a, 59                   ; the first pending line IRQ double-
                             ; fires a sample (a click per frame)
init_vbc:
  ld (smp_vbcnt), a
  ld a, SYNC_OFF             ; sync stays off until asked for
  ld (sync_mode), a

  ; ---- static screen ----
  xor a
  ld (text_attr), a
.IFDEF TARGET_GG
  ld b, 0
  ld c, 9
.ELSE
  ld b, 0
  ld c, 1
.ENDIF
  ld hl, str_title
  call print_at

.IFNDEF TARGET_GG
  ld hl, str_region_ntsc
  ld a, (region_pal)
  or a
  jr z, init_region_pr
  ld hl, str_region_pal
init_region_pr:
  ld b, REGION_ROW
  ld c, REGION_COL
  call print_at
  ld a, 90                   ; reclaim the row from the main loop
  ld (region_timer), a
.ENDIF

  ld a, 1
  ld (state_dirty), a

  ; pre-paint the whole grid while the display is off (the
  ; per-frame budget is 3 rows: 8 passes drain all 16 + labels)
  ld b, 8
init_paint:
  push bc
  call editor_draw
  pop bc
  djnz init_paint

  call display_on
  ld a, 1
  ld (ints_on), a
  ei
.IFDEF DEMO_MODE
  ld a, MODE_SONG            ; demo build: auto-play from row 0
  call engine_play
  ld a, 1
  ld (state_dirty), a
.ENDIF

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

  ; --- logic + engine first: the tick's PSG writes land at a
  ;     fixed frame phase. Drawing cost varies row to row, and
  ;     while a wave/sample plays the vblank feeder + line IRQs
  ;     already push the tick into active display at half speed -
  ;     ticking after the draws audibly jittered row timing. ---
  call read_input
  call handle_pause
  call editor_input
  call smp_housekeep
  call engine_frame
  ld a, (play_state)
  or a
  call z, channels_fx          ; prelisten envelopes while stopped
  call psg_flush

  ; --- VRAM updates after: still inside vblank when idle, and
  ;     spacing-safe in active display while a sample feeds ---
  call draw_frame_counter
  call draw_state
  call draw_region_boot
  call editor_draw

  ld hl, (frame)
  inc hl
  ld (frame), hl
  jr main_loop

.ENDS

; the splash lives in bank 1 (slot 1, always mapped): bank 0 is
; full. It is boot-only, so the cross-bank calls cost nothing.
.BANK 1 SLOT 1
.SECTION "Splash" FREE

; =============================================================
; boot splash: the SMSGGDJ logo (tools/makelogo.py), centred, in
; the house palette - index 0 is the scheme's background (border
; too), index 1 its ink. The SMS region-detect busy-wait runs
; inside the display window so it costs less boot than it shows.
; The logo uses its own tiles (0..LOGO_TILES-1); load_font runs
; after and overwrites them.
splash:
  ld hl, $4800               ; logo tiles -> VRAM tile 64 (past the
  call vdp_set_addr          ; font), plane 0
  ld hl, logo_tiles
  ld bc, LOGO_TILES*8
spl_t:
  ld a, (hl)                 ; 1bpp source -> plane 0 (planes 1-3 = 0)
  out (VDP_DATA), a
  xor a
  out (VDP_DATA), a
  out (VDP_DATA), a
  out (VDP_DATA), a
  inc hl
  dec bc
  ld a, b
  or c
  jr nz, spl_t
  ; logo map at row 10, column 6 (absolute: the GG window centre is
  ; the frame centre, so one placement fits both flavours); each
  ; map byte is offset by the tile-64 base
  ld hl, logo_map
  ld d, 0                    ; row counter
spl_row:
  push hl
  push de
  ld a, d
  add a, 10
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl                 ; row * 64
  ld de, NT_WADDR + 12       ; + column 6 * 2
  add hl, de
  call vdp_set_addr
  pop de
  pop hl
  ld b, LOGO_W
spl_col:
  ld a, (hl)
  add a, 64                  ; logo tiles start at 64
  out (VDP_DATA), a
  xor a
  out (VDP_DATA), a
  inc hl
  djnz spl_col
  inc d
  ld a, d
  cp LOGO_H
  jr c, spl_row
  ; "LITTLE-SCALE'S" inverted band at row 6 (row 7 stays blank as
  ; the gap before the logo at row 8) - mirrors the version bar
  ld hl, NT_WADDR + 8*64
  call vdp_set_addr
  ld b, 32
spl_cbar:
  xor a
  out (VDP_DATA), a
  ld a, $08
  out (VDP_DATA), a
  djnz spl_cbar
  ld hl, NT_WADDR + 8*64 + 9*2     ; 14 chars, centred
  call vdp_set_addr
  ld a, $08
  ld (text_attr), a
  ld hl, str_credit
spl_cred:
  ld a, (hl)
  or a
  jr z, spl_creddone
  push hl
  call print_char
  pop hl
  inc hl
  jr spl_cred
spl_creddone:
  xor a
  ld (text_attr), a
  ; fill the whole version row with an inverted bar (display is
  ; off here, so no write-spacing needed), then the version text
  ; on it (absolute coords, like the logo)
  ld hl, NT_WADDR + 15*64    ; row 15, column 0
  call vdp_set_addr
  ld b, 32
spl_bar:
  xor a                      ; tile 0 (space) -> solid inverse block
  out (VDP_DATA), a
  ld a, $08                  ; inverted attribute
  out (VDP_DATA), a
  djnz spl_bar
  ld hl, NT_WADDR + 15*64 + 14*2   ; version at column 14
  call vdp_set_addr
  ld a, $08
  ld (text_attr), a
  ld hl, str_version
spl_ver:
  ld a, (hl)
  or a
  jr z, spl_verdone
  push hl
  call print_char
  pop hl
  inc hl
  jr spl_ver
spl_verdone:
  xor a
  ld (text_attr), a
  call display_on
  ei
.IFNDEF TARGET_GG
  call detect_region         ; ~0.5 s of the splash, not extra
.ENDIF
  ld b, 100
spl_wait:
  halt
  djnz spl_wait
  di
  ld a, $A0                  ; display off for the UI build-up
  out (VDP_CTRL), a
  ld a, $81
  nop
  nop
  nop
  out (VDP_CTRL), a
  ld hl, NT_WADDR            ; wipe the splash
  call vdp_set_addr
  ld bc, 32*24*2
spl_clear:
  xor a
  out (VDP_DATA), a
  dec bc
  ld a, b
  or c
  jr nz, spl_clear
  ret

.ENDS

.BANK 0 SLOT 0
.SECTION "Main2" FREE

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
handle_pause:                  ; PAUSE: plain transport toggle.
.IFDEF TARGET_GG
  ; the GG has START instead of PAUSE: port $00 bit 7, active
  ; low - a press edge sets the same transport flag
  in a, ($00)
  and $80
  ld b, a
  ld a, (start_prev)
  ld c, a
  ld a, b
  ld (start_prev), a
  or a
  jr nz, hp_nostart          ; not held now
  ld a, c
  or a
  jr z, hp_nostart           ; was already held
  ld a, 1
  ld (nmi_event), a
hp_nostart:
.ENDIF
  ld a, (nmi_event)            ; Never queues - in LIVE mode it
  or a                         ; is the global stop.
  ret z
  xor a
  ld (nmi_event), a
  ld a, (play_state)
  or a
  jp z, tp_start
  jp tp_stop

toggle_play:
  ld a, (play_state)
  or a
  jr z, tp_start
  ; LIVE mode on the SONG screen: the gesture queues, not stops
  ld a, (play_mode)
  or a
  jr z, tp_stop
  ld a, (scr_mode)
  or a                       ; SCR_SONG = 0
  jr nz, tp_stop
  ld a, (hdr_cur)
  or a
  jr nz, tp_tstop
  ld a, (song_col)
  ld c, a
  ld a, (song_cur)
  jp live_queue              ; queue the cell under the cursor
tp_tstop:
  ld a, (song_col)
  jp live_track_stop         ; header: stop this track now
tp_stop:
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
.IFDEF TARGET_GG
  ret                        ; no room in the 20-column window
.ENDIF
  ld b, 0
  ld c, 27
  call nt_addr_hl
  call vdp_set_addr
  ld a, (frame+1)
  call print_hex_a
  ld a, (frame)
  call print_hex_a
  ret

; the boot region line stays up ~1.8 s, then yields its row -
; without ever blocking the main loop
draw_region_boot:
.IFDEF TARGET_GG
  ret                        ; no region line on the GG
.ENDIF
  ld a, (region_timer)
  or a
  ret z
  dec a
  ld (region_timer), a
  ret nz
.IFNDEF TARGET_GG
  ld b, REGION_ROW
  ld c, REGION_COL
.ENDIF
  ld hl, str_blank
  jp print_at

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
  ld a, (sync_wait)          ; slave armed, no clock yet
  or a
  jr z, ds_print
  ld hl, str_wait
ds_print:
  ld b, STATE_ROW
  ld c, STATE_COL
  call print_at
  ; sync mode symbol, one tile after the state (col 31): right
  ; triangle = OUT, pulse = PULSE, left triangle = IN, blank = OFF
  xor a
  ld (text_attr), a
  ld a, (sync_mode)
  ld e, a
  ld d, 0
  ld hl, str_syncsym
  add hl, de
  ld a, (hl)
  push af
  ld b, STATE_ROW
  ld c, SYNC_COL
  call nt_addr_hl
  call vdp_set_addr
  pop af
  jp print_char

; =============================================================
; strings
; =============================================================
.IFDEF TARGET_GG
str_title:       .db "GGDJ", 0
.ELSE
str_title:       .db "SMSGGDJ", 0
.ENDIF
str_region_pal:  .db "REGION: PAL 50HZ ", 0
str_region_ntsc: .db "REGION: NTSC 60HZ", 0
str_play:        .db "PLAY", 0
str_stop:        .db "STOP", 0
str_wait:        .db "WAIT", 0
str_version:     .db "V0.2", 0
str_credit:      .db "LITTLE-SCALE'S", 0
str_syncsym:     .db $3E, $5C, $40, $20  ; > pulse < space
str_rest:        .db "---"

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

; boot splash logo (generated by tools/makelogo.py)
.INCLUDE "logo.inc"

; sample pool: banks 2-7, self-describing (directory at bank 2,
; $8000 - see tools/smsdj_sample.py for the contract)
.INCLUDE "pool.inc"
