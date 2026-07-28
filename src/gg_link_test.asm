; =============================================================
; Game Gear EXT/link-port input diagnostic
;
; Polls the three bottom-row signal pins as parallel GPIO:
;   pin 6 = PC4 = port $01 bit 4
;   pin 7 = PC6 = port $01 bit 6
;   pin 9 = PC5 = port $01 bit 5
;
; START toggles the dedicated PC6 falling-edge NMI test.
; Button 1 clears the edge and NMI counters.
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

.DEFINE VDP_DATA $BE
.DEFINE VDP_CTRL $BF
.DEFINE VDP_VCNT $7E
.DEFINE NT_WRITE $7800

.RAMSECTION "GG link test vars" SLOT 3
  raw_pins    db
  last_pins   db
  edge6       dw
  edge7       dw
  edge9       dw
  nmi_count   dw
  nmi_armed   db
  start_prev  db
  b1_prev     db
  text_attr   db
.ENDS

.BANK 0 SLOT 0

.ORGA $0000
.SECTION "GG link test boot" FORCE
  di
  im 1
  ld sp, $DFF0
  jp init
.ENDS

.ORGA $0038
.SECTION "GG link test IRQ" FORCE
  reti
.ENDS

.ORGA $0066
.SECTION "GG link test NMI" FORCE
nmi_handler:
  push af
  push hl
  ld hl, (nmi_count)
  inc hl
  ld (nmi_count), hl

  ; PC6 edge NMI uses a latch.  Reset and re-arm it exactly as
  ; described by Sega: NINT=1, then NINT=0, then RETN.
  ld a, (nmi_armed)
  or a
  jr z, nmi_done
  ld a, $FF                  ; all inputs, PC6 NMI disabled
  out ($02), a
  ld a, $7F                  ; all inputs, PC6 falling-edge NMI armed
  out ($02), a
nmi_done:
  pop hl
  pop af
  retn
.ENDS

.SECTION "GG link test main" FREE
init:
  ; Standard Sega mapper setup.  Bank 1 contains the font.
  xor a
  ld ($FFFC), a
  ld ($FFFD), a
  inc a
  ld ($FFFE), a
  inc a
  ld ($FFFF), a

  ; Clear work RAM below the stack.
  ld hl, $C000
  ld de, $C001
  ld bc, $1FEE
  ld (hl), 0
  ldir

  ; Use raw parallel GPIO.  Serial TX/RX and both serial and PC6
  ; NMIs start disabled.  Explicit setup avoids relying on reset state.
  xor a
  out ($05), a               ; TON=0, RON=0, serial INT=0
  ld a, $FF
  out ($02), a               ; PC0-PC6 inputs, NINT=1 (disabled)

  ; Sega recommends waiting for V counter $B0 before first VDP access.
vdp_ready:
  in a, (VDP_VCNT)
  cp $B0
  jr nz, vdp_ready

  call vdp_init
  call vdp_clear
  call font_load
  call palette_load
  call draw_static

  in a, ($01)
  and $70
  ld (raw_pins), a
  ld (last_pins), a
  in a, ($00)
  and $80
  ld (start_prev), a
  in a, ($DC)
  and $10
  ld (b1_prev), a
  call draw_dynamic
  call display_on

main_loop:
  call wait_frame
  call sample_pins
  call handle_controls
  call draw_dynamic
  jr main_loop

; Wait for the start of VBlank, once per frame.
wait_frame:
wf_active:
  in a, (VDP_VCNT)
  cp $C0
  jr nc, wf_active
wf_vblank:
  in a, (VDP_VCNT)
  cp $C0
  jr c, wf_vblank
  ret

sample_pins:
  in a, ($01)
  and $70
  ld b, a
  ld a, (last_pins)
  xor b
  ld c, a                    ; C = bits that changed this frame
  ld a, b
  ld (raw_pins), a
  ld (last_pins), a
  bit 4, c
  call nz, inc_edge6
  bit 6, c
  call nz, inc_edge7
  bit 5, c
  call nz, inc_edge9
  ret

inc_edge6:
  ld hl, (edge6)
  inc hl
  ld (edge6), hl
  ret
inc_edge7:
  ld hl, (edge7)
  inc hl
  ld (edge7), hl
  ret
inc_edge9:
  ld hl, (edge9)
  inc hl
  ld (edge9), hl
  ret

handle_controls:
  ; START is active low at port $00 bit 7.
  in a, ($00)
  and $80
  ld b, a
  ld a, (start_prev)
  cp b
  jr z, hc_b1
  ld a, b
  ld (start_prev), a
  or a
  call z, toggle_nmi

hc_b1:
  ; Built-in button 1 is active low at port $DC bit 4.
  in a, ($DC)
  and $10
  ld b, a
  ld a, (b1_prev)
  cp b
  ret z
  ld a, b
  ld (b1_prev), a
  or a
  ret nz
  xor a
  ld (edge6), a
  ld (edge6+1), a
  ld (edge7), a
  ld (edge7+1), a
  ld (edge9), a
  ld (edge9+1), a
  ld (nmi_count), a
  ld (nmi_count+1), a
  ret

toggle_nmi:
  ld a, (nmi_armed)
  xor 1
  ld (nmi_armed), a
  or a
  ld a, $FF                  ; all inputs, PC6 NMI disabled
  jr z, tn_write
  ld a, $7F                  ; all inputs, PC6 falling-edge NMI armed
tn_write:
  out ($02), a
  ret

; -------------------------------------------------------------
; Dynamic screen fields
draw_dynamic:
  xor a
  ld (text_attr), a

  ld b, 3
  ld c, 10
  call set_text_at
  ld a, (raw_pins)
  call print_hex8

  ld a, (raw_pins)
  bit 4, a
  ld b, 5
  call draw_level
  ld a, (raw_pins)
  bit 6, a
  ld b, 6
  call draw_level
  ld a, (raw_pins)
  bit 5, a
  ld b, 7
  call draw_level

  xor a
  ld (text_attr), a
  ld b, 9
  ld c, 8
  call set_text_at
  ld hl, (edge6)
  call print_hex16
  ld b, 10
  ld c, 8
  call set_text_at
  ld hl, (edge7)
  call print_hex16
  ld b, 11
  ld c, 8
  call set_text_at
  ld hl, (edge9)
  call print_hex16

  ld hl, str_off
  ld a, (nmi_armed)
  or a
  jr z, dd_nmi_mode
  ld hl, str_arm
  ld a, $08
  ld (text_attr), a
dd_nmi_mode:
  ld b, 13
  ld c, 6
  call print_at
  xor a
  ld (text_attr), a
  ld b, 13
  ld c, 15
  call set_text_at
  ld hl, (nmi_count)
  call print_hex16
  ret

; B = logical row; flags from BIT select HIGH (NZ) or LOW (Z).
draw_level:
  ld hl, str_high
  ld a, 0
  jr nz, dl_ready
  ld hl, str_low
  ld a, $08                  ; inverse video makes a low line conspicuous
dl_ready:
  ld (text_attr), a
  ld c, 10
  call print_at
  ret

; -------------------------------------------------------------
; Static screen
draw_static:
  xor a
  ld (text_attr), a
  ld b, 0
  ld c, 1
  ld hl, str_title
  call print_at
  ld b, 1
  ld c, 1
  ld hl, str_mode
  call print_at
  ld b, 3
  ld c, 0
  ld hl, str_raw
  call print_at
  ld b, 5
  ld c, 0
  ld hl, str_pin6
  call print_at
  ld b, 6
  ld c, 0
  ld hl, str_pin7
  call print_at
  ld b, 7
  ld c, 0
  ld hl, str_pin9
  call print_at
  ld b, 9
  ld c, 0
  ld hl, str_edge6
  call print_at
  ld b, 10
  ld c, 0
  ld hl, str_edge7
  call print_at
  ld b, 11
  ld c, 0
  ld hl, str_edge9
  call print_at
  ld b, 13
  ld c, 0
  ld hl, str_nmi
  call print_at
  ld b, 13
  ld c, 11
  ld hl, str_count
  call print_at
  ld b, 15
  ld c, 1
  ld hl, str_start
  call print_at
  ld b, 16
  ld c, 1
  ld hl, str_reset
  call print_at
  ld b, 17
  ld c, 0
  ld hl, str_probe
  call print_at
  ret

; -------------------------------------------------------------
; Text helpers.  Logical (0,0) is the top-left Game Gear LCD tile;
; the LCD window starts at virtual name-table tile (6,3).
set_text_at:
  ld a, b
  add a, 3
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl                  ; physical row * 64 bytes
  ld a, c
  add a, 6
  add a, a
  ld e, a
  ld d, 0
  add hl, de
  ld de, NT_WRITE
  add hl, de
  jp vdp_set_addr

print_at:
  push hl
  call set_text_at
  pop hl
pa_loop:
  ld a, (hl)
  or a
  ret z
  call print_char
  inc hl
  jr pa_loop

print_char:
  sub $20
  out (VDP_DATA), a
  nop
  nop
  ld a, (text_attr)
  out (VDP_DATA), a
  ret

print_hex16:
  ld a, h
  call print_hex8
  ld a, l
  jp print_hex8

print_hex8:
  push af
  rrca
  rrca
  rrca
  rrca
  and $0F
  call print_nibble
  pop af
  and $0F
print_nibble:
  cp 10
  jr c, pn_digit
  add a, 7
pn_digit:
  add a, '0'
  jp print_char

; -------------------------------------------------------------
; VDP setup
vdp_init:
  ld hl, vdp_regs
  ld b, vdp_regs_end-vdp_regs
  ld c, VDP_CTRL
  otir
  ret
vdp_regs:
  .db $06, $80               ; R0: Mode 4
  .db $80, $81               ; R1: display off, interrupts off
  .db $FF, $82               ; R2: name table $3800
  .db $FF, $83
  .db $FF, $84
  .db $FF, $85
  .db $FB, $86
  .db $00, $87               ; black border
  .db $00, $88
  .db $00, $89
  .db $FF, $8A
vdp_regs_end:

display_on:
  ld a, $C0                  ; display on, interrupts remain off
  out (VDP_CTRL), a
  ld a, $81
  out (VDP_CTRL), a
  ret

vdp_set_addr:
  ld a, l
  out (VDP_CTRL), a
  ld a, h
  out (VDP_CTRL), a
  ret

vdp_clear:
  ld hl, $4000
  call vdp_set_addr
  ld bc, $4000
vc_loop:
  xor a
  out (VDP_DATA), a
  dec bc
  ld a, b
  or c
  jr nz, vc_loop
  ret

font_load:
  ld hl, $4000
  call vdp_set_addr
  ld hl, font_data
  ld bc, font_data_end-font_data
fl_loop:
  ld a, (hl)
  out (VDP_DATA), a
  inc hl
  dec bc
  ld a, b
  or c
  jr nz, fl_loop
  ret

palette_load:
  ld hl, $C000
  call vdp_set_addr
  ; Palette 0: white text on black.
  xor a
  out (VDP_DATA), a
  out (VDP_DATA), a
  ld a, $FF
  out (VDP_DATA), a
  ld a, $0F
  out (VDP_DATA), a
  xor a
  ld b, 28
pl_p0:
  out (VDP_DATA), a
  djnz pl_p0
  ; Palette 1: black text on white for LOW/ARM warnings.
  ld a, $FF
  out (VDP_DATA), a
  ld a, $0F
  out (VDP_DATA), a
  xor a
  out (VDP_DATA), a
  out (VDP_DATA), a
  ld b, 28
pl_p1:
  out (VDP_DATA), a
  djnz pl_p1
  ret

str_title: .db "GG LINK INPUT TEST", 0
str_mode:  .db "GPIO SAMPLE 60 HZ", 0
str_raw:   .db "RAW $01: $", 0
str_pin6:  .db "PIN6 PC4:", 0
str_pin7:  .db "PIN7 PC6:", 0
str_pin9:  .db "PIN9 PC5:", 0
str_edge6: .db "EDGES6: ", 0
str_edge7: .db "EDGES7: ", 0
str_edge9: .db "EDGES9: ", 0
str_nmi:   .db "NMI7: ", 0
str_count: .db "CNT:", 0
str_start: .db "START TOGGLE NMI7", 0
str_reset: .db "B1 RESET COUNTERS", 0
str_probe: .db "USE 4K7 TO PIN8 GND", 0
str_high:  .db "HIGH", 0
str_low:   .db "LOW ", 0
str_off:   .db "OFF ", 0
str_arm:   .db "ARM ", 0
.ENDS

.BANK 1 SLOT 1
.SECTION "GG link test font" FREE
font_data:
  .INCBIN "font.bin"
font_data_end:
.ENDS
