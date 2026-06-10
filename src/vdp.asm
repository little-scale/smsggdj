; =============================================================
; SMSDJ - VDP helpers (Mode 4 text UI)
; =============================================================

.SECTION "VDP" FREE

; write VDP registers from init table
vdp_init:
  ld hl, vdp_reg_data
  ld b, vdp_reg_data_end - vdp_reg_data
  ld c, VDP_CTRL
  otir
  ret

vdp_reg_data:
  .db $06, $80                 ; R0: mode 4, M2
  .db $A0, $81                 ; R1: display off, frame int on
  .db $FF, $82                 ; R2: name table $3800
  .db $FF, $83                 ; R3: (legacy, all 1s)
  .db $FF, $84                 ; R4: (legacy, all 1s)
  .db $FF, $85                 ; R5: sprite attribute table $3F00
  .db $FB, $86                 ; R6: sprite patterns
  .db $0F, $87                 ; R7: border = sprite palette idx 15
  .db $00, $88                 ; R8: hscroll 0
  .db $00, $89                 ; R9: vscroll 0
  .db $FF, $8A                 ; R10: line interrupt off
vdp_reg_data_end:

display_on:
  ld a, $E0                    ; display on, frame int on
  out (VDP_CTRL), a
  ld a, $81
  out (VDP_CTRL), a
  ret

; set VRAM/CRAM address: HL = address (caller pre-ORs $4000 for
; VRAM write, $C000 for CRAM)
vdp_set_addr:
  ld a, l
  out (VDP_CTRL), a
  ld a, h
  out (VDP_CTRL), a
  ret

vdp_clear_vram:
  ld hl, $4000
  call vdp_set_addr
  ld bc, $4000
vcv_loop:
  xor a
  out (VDP_DATA), a
  dec bc
  ld a, b
  or c
  jr nz, vcv_loop
  ret

; font tiles -> VRAM tile 0 onward
load_font:
  ld hl, $4000                 ; tile 0 | write
  call vdp_set_addr
  ld hl, font_data
  ld bc, font_data_end - font_data
lf_loop:
  ld a, (hl)
  out (VDP_DATA), a
  inc hl
  dec bc
  ld a, b
  or c
  jr nz, lf_loop
  ret

; two palettes: 0 = white on black, 1 (sprite pal) = black on
; white for inverse video via the tilemap palette bit.
; Border colour comes from sprite palette index 15 (R7 = $0F).
load_palette:
  ld hl, $C000
  call vdp_set_addr
  ld hl, pal_data
  ld b, 32
lp_loop:
  ld a, (hl)
  out (VDP_DATA), a
  inc hl
  djnz lp_loop
  ret

pal_data:
  .db $00 $3F $00 $00 $00 $00 $00 $00 $00 $00 $00 $00 $00 $00 $00 $00
  .db $3F $00 $00 $00 $00 $00 $00 $00 $00 $00 $00 $00 $00 $00 $00 $00

; B = row, C = col -> HL = name table write address
nt_addr_hl:
  ld h, 0
  ld l, b
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl                   ; row * 64
  ld a, c
  add a, a
  ld e, a
  ld d, 0
  add hl, de                   ; + col * 2
  ld de, NT_WADDR
  add hl, de
  ret

; print zero-terminated string: B = row, C = col, HL = string.
; Attribute byte comes from text_attr ($00 normal / $08 inverted).
print_at:
  push hl
  call nt_addr_hl
  call vdp_set_addr
  pop hl
pa_loop:
  ld a, (hl)
  or a
  ret z
  sub $20                      ; font starts at space
  out (VDP_DATA), a
  ld a, (text_attr)
  out (VDP_DATA), a
  inc hl
  jr pa_loop

; print B chars from HL at current VRAM address (no terminator)
print_raw:
  ld a, (hl)
  sub $20
  out (VDP_DATA), a
  ld a, (text_attr)
  out (VDP_DATA), a
  inc hl
  djnz print_raw
  ret

; print A as two hex digits at current VRAM address
print_hex_a:
  push af
  rrca
  rrca
  rrca
  rrca
  call print_hex_nib
  pop af
  ; fall through
print_hex_nib:
  and $0F
  cp 10
  jr c, phn_digit
  add a, 7                     ; A-F
phn_digit:
  add a, $10                   ; tile index of '0'
  out (VDP_DATA), a
  push af
  ld a, (text_attr)
  out (VDP_DATA), a
  pop af
  ret

; write attribute byte only: B = row, C = col, A = attr
set_attr:
  push af
  call nt_addr_hl
  inc hl
  call vdp_set_addr
  pop af
  out (VDP_DATA), a
  ret

.ENDS
