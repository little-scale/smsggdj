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
.DEFINE FM_ADDR     $F0          ; YM2413 FM unit: register address latch
.DEFINE FM_DATA     $F1          ;   data write
.DEFINE FM_CTRL     $F2          ;   audio control / detect

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
  key_delay      db           ; DAS repeat delay (frames), OPTIONS-set + persisted
  key_speed      db           ; DAS repeat interval (frames), OPTIONS-set + persisted
  pal_sel        db           ; colour scheme (pal_presets index)
  vid_sel        db           ; VIDEO choice: 0 AUTO, 1 PAL, 2 NTSC
  region_detected db          ; region from boot detection (1 = PAL)
  fm_on          db           ; OPTIONS FM toggle: 0 off, 1 on (persisted)
  start_prev     db           ; GG START level last frame
  region_timer   db           ; frames left on the boot region line
  ints_on        db           ; init done: helpers may EI
  text_attr      db            ; $00 normal, $08 inverted (palette bit)
  note_ptr       dw            ; active region note table
  fm_note_ptr    dw            ; active region YM2413 F-num/block table
  fm_rhythm      db            ; $0E shadow: bit5 rhythm enable | bits0-4 drum key-on
  fm_drumv       ds 3          ; volume shadows for $36/$37/$38 (packed drum levels)
  fm_dscr        ds 2          ; fm_drum_trig scratch (atten, vreg)
  fm_user_preset db            ; custom patch currently in $00-$07 ($FF = none)
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
  ld a, 0                    ; palette 0 (white on black) is the house default
  ld (pal_sel), a            ;   (used if no valid saved config)
  call load_palette
  ld a, SYNC_OFF             ; defaults config_load may override; set
  ld (sync_mode), a          ;   before it now that it runs pre-splash
  ld a, DAS_DELAY            ; key-repeat delay/speed defaults (OPTIONS may
  ld (key_delay), a          ;   override via a saved v3 config block)
  ld a, DAS_SPEED
  ld (key_speed), a
  ld a, $FF
  ld (fm_ovr), a             ; one-shot FM program override starts clear
  call load_font
  call sram_detect           ; restore persisted OPTIONS (colour, sync,
  call config_load           ;   video) before the splash, so it renders
                             ;   in the saved palette (config reapplies it)
  call splash                ; logo + version; SMS region detect inside
.IFDEF RLE_SELFTEST
  call rle_selftest_show     ; freezes on the splash showing RLE OK / RLE ERR
.ENDIF
  call song_new              ; boot a blank song; the baked demo
                             ; loads from PROJECT (DEMO, two-press)
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
  ; boot lands on the ROM demo (no slot-1 autoload for now: a
  ; first power-on should make sound - saves load via PROJECT)
  xor a
  ld (prj_stat), a

  ; region: detection ran during the splash. Remember it, then let the
  ; VIDEO choice pick the effective region (AUTO follows detection) and
  ; point the region tables (note/winc) + the vblank sample budget.
  ld a, (region_pal)
  ld (region_detected), a
  call apply_video
  ld a, 150                  ; default tempo display by region (boot seed;
  ld b, a                    ;   TMPO tracks the groove live thereafter)
  ld a, (region_pal)
  or a
  jr z, init_bpm
  ld b, 125
init_bpm:
  ld a, b
  ld (proj_bpm), a

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
  call fm_init               ; ready the YM2413 FM unit (if present)

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
  ; logo map at row 8, column 6 (absolute: the GG window centre is
  ; the frame centre, so one placement fits both flavours); each
  ; map byte is offset by the tile-64 base
  ld hl, logo_map
  ld d, 0                    ; row counter
spl_row:
  push hl
  push de
  ld a, d
  add a, 8
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
  ; fill the whole version row with an inverted bar (display is
  ; off here, so no write-spacing needed), then the version text
  ; on it (absolute coords, like the logo)
  ld hl, NT_WADDR + 13*64    ; row 13, column 0
  call vdp_set_addr
  ld b, 32
spl_bar:
  xor a                      ; tile 0 (space) -> solid inverse block
  out (VDP_DATA), a
  ld a, $08                  ; inverted attribute
  out (VDP_DATA), a
  djnz spl_bar
  ld hl, NT_WADDR + 13*64 + 13*2   ; version at column 13
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
  ; build id under the version (dev aid: a stale flash is obvious at boot)
  ld hl, NT_WADDR + 14*64 + 12*2
  call vdp_set_addr
  ld hl, str_buildid
spl_bid:
  ld a, (hl)
  or a
  jr z, spl_biddone
  push hl
  call print_char
  pop hl
  inc hl
  jr spl_bid
spl_biddone:
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

; resolve the VIDEO choice (vid_sel) against the detected region into
; the effective region_pal, then point the region tables. Called at
; boot and whenever OPTIONS VID changes. vid_sel: 0 AUTO, 1 PAL, 2 NTSC.
apply_video:
  ld a, (vid_sel)
  dec a
  jr z, av_pal               ; 1 = force PAL
  dec a
  jr z, av_ntsc              ; 2 = force NTSC
  ld a, (region_detected)    ; 0 = AUTO: follow detection
  jr av_set
av_pal:
  ld a, 1
  jr av_set
av_ntsc:
  xor a
av_set:
  ld (region_pal), a
  ; fall into apply_region

; point note/winc tables and the vblank sample budget at region_pal.
apply_region:
  ld hl, note_table_ntsc
  ld de, winc_table_ntsc
  ld b, 34                   ; NTSC: 70 vblank lines / 2, minus one slot
  ld a, (region_pal)         ;   of slack (overrun double-fires a sample)
  or a
  jr z, ar_set
  ld hl, note_table_pal
  ld de, winc_table_pal
  ld b, 59                   ; PAL
ar_set:
  ld (note_ptr), hl
  ld (winc_ptr), de
  ld a, b
  ld (smp_vbcnt), a
  ld hl, fm_note_ntsc        ; FM note table by region
  ld a, (region_pal)
  or a
  jr z, ar_fm
  ld hl, fm_note_pal
ar_fm:
  ld (fm_note_ptr), hl
  ret

; =============================================================
; YM2413 FM Sound Unit (SMS FM add-on / Japanese built-in)
; =============================================================
; boot / FM-ON: enable FM audio (if the OPTIONS toggle is on) and clear
fm_init:
  ld a, (fm_on)
  or a
  ret z                      ; FM off: leave the unit (and the PSG) alone
  ld a, $01                  ; $F2: enable FM (sums with PSG on real HW /
  out (FM_CTRL), a           ;   SMSPlus; Emulicious muxes to FM-only)
  call fm_clear              ; melody mode, all voices keyed off
  ; rhythm mode: fixed drum pitches + silent levels, then enable. The
  ; tracker only uses melodic FM channels 0-3, so channels 6-8 are free
  ; for rhythm at no cost to the 4 tracks.
  ld hl, fm_rhythm_tab
  ld a, 9
fri_loop:
  ld c, (hl)
  inc hl
  ld b, (hl)
  inc hl
  push hl
  push af
  call fm_w
  pop af
  pop hl
  dec a
  jr nz, fri_loop
  ld a, $0F                  ; volume shadows: silent (BD low / HH-SD / TT-CYM)
  ld (fm_drumv+0), a
  ld a, $FF
  ld (fm_drumv+1), a
  ld (fm_drumv+2), a
  ld a, $FF                  ; no custom patch loaded yet
  ld (fm_user_preset), a
  ld a, $20                  ; $0E: rhythm enable (bit5), all drum keys off
  ld (fm_rhythm), a
  ld c, $0E
  ld b, a
  jp fm_w

; Load custom FM preset A (0-7) into the YM2413 user patch ($00-$07),
; but only if it isn't already there (one user patch, global).
; IN: a = preset index. Preserves DE; clobbers A/B/C/HL.
fm_load_preset:
  ld hl, fm_user_preset
  cp (hl)
  ret z                      ; already loaded
  ld (hl), a                 ; remember it
  ld l, a                    ; hl = fm_presets + a*8
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  ld bc, fm_presets
  add hl, bc
  ld c, $00                  ; user-patch registers $00..$07
flp_loop:
  ld b, (hl)                 ; value
  push hl
  call fm_w                  ; reg c, value b (preserves de)
  pop hl
  inc hl
  inc c
  ld a, c
  cp $08
  jr c, flp_loop
  ret
; STOP: key off every FM voice + all rhythm drums, but keep rhythm MODE enabled
; (this tracker runs channels 0-5 melody / 6-8 drums, rhythm always on) and keep
; FM routing, so a stopped song leaves no FM/table note ringing and PLAY resumes
; cleanly. Caller gates on fm_on. Clobbers A/BC.
fm_hush:
  ld c, $30                  ; force melody channels 0..8 to max attenuation, so a
fmh_vol:                     ;   note held keyed-on by a table is silenced NOW (not
  ld b, $0F                  ;   left to ring out its patch release after key-off)
  call fm_w
  inc c
  ld a, c
  cp $39
  jr c, fmh_vol
  ld c, $20                  ; key off melody channels 0..8 ($20+ch = 0)
fmh_off:
  ld b, $00
  call fm_w
  inc c
  ld a, c
  cp $29
  jr c, fmh_off
  ld c, $0E                  ; rhythm mode on, all drum keys off
  ld b, $20
  call fm_w
  ld a, $20
  ld (fm_rhythm), a          ; shadow matches: no stale drum keys on resume
  ret

; FM-OFF: drop FM routing and key everything off
fm_silence:
  xor a
  out (FM_CTRL), a
  ld (fm_rhythm), a          ; a = 0: rhythm disabled in the shadow too
fm_clear:                    ; melody mode + key off channels 0..8
  ld c, $0E                  ; rhythm control: 0 = melody mode
  ld b, $00
  call fm_w
  ld c, $20                  ; key off channels 0..8 ($20..$28 = 0)
fmi_off:
  ld b, $00
  call fm_w
  inc c
  ld a, c
  cp $29
  jr c, fmi_off
  ret

; YM2413 rhythm-mode setup: (reg, value) pairs — fixed drum pitch
; (F-num/block for channels 6/7/8) and silent starting levels.
fm_rhythm_tab:
  .db $16, $20, $26, $05     ; ch6 BD pitch
  .db $17, $50, $27, $05     ; ch7 HH+SD pitch
  .db $18, $C0, $28, $01     ; ch8 TT+CYM pitch
  .db $36, $0F, $37, $FF, $38, $FF  ; all drum levels silent

; --- FM drum tables: indexed by drum 0-4 (BD, SD, TT, TC, HH) ---
fm_drum_bit:  .db $10, $08, $04, $02, $01   ; $0E key-on bit
fm_drum_vreg: .db $36, $37, $38, $38, $37   ; volume register
fm_drum_vhi:  .db $00, $00, $01, $00, $01   ; 1 = high nibble of that reg

; Set a drum's level: merge the volume into the shared register's nibble
; (via shadow, since the chip can't be read back) and write it. No re-key,
; so the X command can re-level a hit. IN: e = drum 0-4, a = musical vol
; 0-F. Preserves e. Clobbers A/B/C/D/HL.
fm_drum_vol:
  cpl
  and $0F                    ; attenuation 0-F
  ld (fm_dscr+0), a          ; stash atten
  ld d, 0
  ld hl, fm_drum_vreg
  add hl, de
  ld a, (hl)                 ; volume register
  ld (fm_dscr+1), a
  ld hl, fm_drum_vhi
  add hl, de
  ld c, (hl)                 ; nibble flag (1 = high)
  ld a, (fm_dscr+1)          ; shadow ptr = fm_drumv + (vreg - $36)
  sub $36
  ld hl, fm_drumv
  add a, l                   ; 8-bit add (keeps de=drum, c=nibble flag)
  ld l, a
  jr nc, fdt_sptr
  inc h
fdt_sptr:
  ld a, (fm_dscr+0)          ; merge atten into the right nibble
  bit 0, c
  jr z, fdt_lo
  rlca
  rlca
  rlca
  rlca
  ld b, a
  ld a, (hl)
  and $0F
  or b
  jr fdt_store
fdt_lo:
  ld b, a
  ld a, (hl)
  and $F0
  or b
fdt_store:
  ld (hl), a                 ; updated level shadow
  ld b, a
  ld a, (fm_dscr+1)
  ld c, a
  jp fm_w                    ; write the volume register

; Trigger an FM rhythm drum: set its level then pulse its $0E key-on bit
; (off->on = attack). IN: e = drum index 0-4, a = musical volume 0-F.
; e = drum 0-4, ix+0 = note -> write the note's fnum/block (from the FM note
; table, which is voiced down FM_OCT_SHIFT octaves) into the drum's rhythm-channel
; carrier registers ($16+off fnum-low, $26+off block|fnum8), so the note tunes the
; drum's operators. Channels are shared: BD=ch6, SD/HH=ch7, TOM/TCY=ch8. Preserves
; e (the caller keys the drum next). Clobbers A/BC/HL.
fm_drum_pitch:
  push de                    ; keep e = drum for the caller
  ld a, (ix+0)               ; note*2 -> FM note table entry
  add a, a
  ld l, a
  ld h, 0
  ld bc, (fm_note_ptr)
  add hl, bc                 ; HL -> [fnum_low][block|fnum8]
  ld a, e                    ; drum -> $16/$26 register offset (0=ch6,1=ch7,2=ch8)
  ld bc, fm_drum_preg
  add a, c
  ld c, a
  ld a, b
  adc a, 0
  ld b, a
  ld a, (bc)
  ld e, a                    ; e = register offset (drum saved on the stack)
  ld b, (hl)                 ; fnum low
  ld a, $16
  add a, e
  ld c, a
  call fm_w                  ; $16+off = fnum low (preserves de/hl)
  inc hl
  ld b, (hl)                 ; block | fnum8
  ld a, $26
  add a, e
  ld c, a
  call fm_w                  ; $26+off = block | fnum8
  pop de                     ; restore e = drum
  ret
fm_drum_preg:                ; drum 0-4 -> pitch-register offset (BD/SD/TOM/TCY/HH)
  .db 0, 1, 2, 2, 1

fm_drum_trig:
  call fm_drum_vol           ; set the level (preserves e = drum)
  ; key-on edge: clear the drum's bit, write $0E, set it, write again
  ld hl, fm_drum_bit
  ld d, 0
  add hl, de
  ld a, (hl)
  ld e, a                    ; e = key-on bit mask (survives fm_w)
  ld a, (fm_rhythm)
  ld d, a
  ld a, e
  cpl
  and d
  ld (fm_rhythm), a
  ld b, a
  ld c, $0E
  call fm_w                  ; key off (edge low)
  ld a, (fm_rhythm)
  or e
  ld (fm_rhythm), a
  ld b, a
  ld c, $0E
  jp fm_w                    ; key on (edge high)

; Key off one rhythm drum (HLD expiry). IN: e = drum index 0-4.
fm_drum_off:
  ld hl, fm_drum_bit
  ld d, 0
  add hl, de
  ld a, (hl)
  cpl
  ld e, a
  ld a, (fm_rhythm)
  and e
  ld (fm_rhythm), a
  ld b, a
  ld c, $0E
  jp fm_w
; write YM2413 reg C = value B, honouring the chip's address/data wait.
; Preserves DE/HL (and BC); clobbers A.
fm_w:
  ld a, c
  out (FM_ADDR), a
  call fm_wwait
  ld a, b
  out (FM_DATA), a
fm_wwait:
  push bc
  ld b, 12
fmw_loop:
  djnz fmw_loop              ; ~30 us busy delay
  pop bc
  ret

; write FM channel volume live (X command / table vol column).
; IN: ix = channel struct, e = channel (0-3), a = musical volume (0-F).
; Keeps the instrument's patch in the $30-reg high nibble.
fm_set_vol:
  cpl
  and $0F                    ; attenuation = 15 - volume
  ld d, a
  push de                    ; save channel (e) + attenuation (d)
  ld a, (ix+1)               ; hl = instrument record base
  call instr_rec
  push hl                    ; record base
  ld de, 11
  add hl, de
  ld a, (hl)                 ; +11: 0 = ROM patch, 1-8 = custom (patch 0)
  pop hl
  or a
  jr nz, fsv_cust
  ld de, 4
  add hl, de
  ld a, (hl)                 ; +4 ROM patch
  and $0F
  jr nz, fsv_p
  inc a                      ; patch 0 -> 1
  jr fsv_p
fsv_cust:
  xor a                      ; custom preset -> patch 0 (user patch)
fsv_p:
  rlca
  rlca
  rlca
  rlca                       ; patch << 4
  pop de                     ; d = atten, e = channel
  or d                       ; | attenuation
  ld b, a                    ; $30-reg data
  ld a, e
  add a, $30                 ; $30 + channel
  ld c, a
  jp fm_w

; write FM channel pitch live, keeping the note keyed on (table arp /
; pitch column). IN: ix, e = channel (0-3), a = note index (clamped).
; Looks up F-number/block from the region table; key-on stays set.
fm_set_pitch:
  cp NOTE_COUNT
  jr c, fsp_ok
  ld a, NOTE_COUNT-1
fsp_ok:
  add a, a                   ; note * 2
  ld l, a
  ld h, 0
  ld bc, (fm_note_ptr)
  add hl, bc
  ld a, (hl)                 ; F-number low ($10-reg)
  ld d, a
  inc hl
  ld a, (hl)
  or $30                     ; key-on ($10) | sustain ($20) | block | fnum8
  push af                    ; save the $20-reg value
  ld a, e
  add a, $10                 ; $10 + channel
  ld c, a
  ld b, d
  call fm_w                  ; F-number low
  pop af
  ld b, a                    ; $20-reg value
  ld a, e
  add a, $20                 ; $20 + channel
  ld c, a
  jp fm_w

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
  ; LIVE on the SONG screen: start the clock with every track silent, then
  ; trigger only the cell under the cursor (don't fire the whole song)
  ld a, (play_mode)
  or a
  jr z, tp_start_song
  ld a, (scr_mode)
  or a                       ; SCR_SONG = 0
  jr nz, tp_start_song
  ld a, MODE_SONG
  call engine_play           ; LIVE: engine_play leaves all tracks silent
  ld a, (hdr_cur)
  or a
  jr nz, tp_dirty            ; header gesture: just the silent clock
  ld a, (song_col)
  ld c, a
  ld a, (song_cur)
  call live_queue            ; arm only this track
  jr tp_dirty
tp_start_song:
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

; 2-held + double-tap-1: (re)start the whole song from the contextual row, so a
; phrase/chain being edited can be heard in full arrangement context. Stop first
; so a solo preview from the first tap (or any in-flight sample) ends cleanly.
play_song_here:
  call engine_stop
  ld a, MODE_SONG
  call engine_play
  jr tp_dirty

; =============================================================
; drawing
; =============================================================
draw_frame_counter:
.IFDEF TARGET_GG
  ret                        ; no room in the 20-column window
.ENDIF
  ld b, 0
  ld c, 26
  call set_text_at
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
  call set_text_at
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
str_version:     .db "V0.37", 0
str_syncsym:     .db $20, $3E, $5C, $40, $20, $5E  ; OFF OUT> PULSE IN< MIDI IN24<<
str_rest:        .db "---"

.ENDS

.INCLUDE "src/vdp.asm"
.INCLUDE "src/input.asm"
.INCLUDE "src/psg.asm"
.INCLUDE "src/engine.asm"
.INCLUDE "src/sample.asm"
.INCLUDE "src/editor.asm"
.INCLUDE "src/rle.asm"
.INCLUDE "notes.inc"
.INCLUDE "buildid.inc"

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
