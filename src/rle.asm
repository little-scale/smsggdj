; ============================================================
; src/rle.asm -- RLE save codec (see COMPRESSION.md).
;
; 4-byte unit (one phrase/table row). PackBits stream:
;   control byte c:
;     bit7 = 0 -> literal run : copy next (c & $7F)+1 units   (1..128)
;     bit7 = 1 -> repeat run  : next 1 unit, output (c&$7F)+2  (2..129)
; Matches tools/rletest.py / tools/rle.js (the canonical decoder)
; byte-for-byte. Runs only during save/load (not real-time), so it
; favours clarity over speed (RAM-var pointers, LDIR helpers) and
; parks in a bank-1 section.
;
; STATUS (M1): build-clean; logic verified against the Python/JS
; reference via tools/rle_z80mirror.py. The real on-console round
; trip is exercised when M2 wires this into song_save/song_load.
; Not yet called from anywhere.
; ============================================================

.RAMSECTION "RLEvars" BANK 0 SLOT 3
  rle_sp   dw           ; stream pointer  (read on unpack / write on pack)
  rle_bp   dw           ; block  pointer  (write on unpack / read on pack)
  rle_rem  dw           ; units remaining
  rle_cnt  dw           ; current run / literal length (low byte used)
  rle_unit dsb 4        ; scratch unit, for expanding a repeat run
.IFDEF RLE_SELFTEST
  rle_test_pk  dsb 80   ; codec self-test (make selftest): packed buffer
  rle_test_un  dsb 60   ; codec self-test: unpacked buffer (15 units)
.ENDIF
.ENDS

.BANK 1 SLOT 1
.SECTION "RLEcodec" FREE

; ------------------------------------------------------------
; rle_unpack: HL = stream src, DE = block dst, BC = unit count.
; Writes BC units (BC*4 bytes) to DE.
; ------------------------------------------------------------
rle_unpack:
  ld (rle_sp), hl
  ld (rle_bp), de
  ld (rle_rem), bc
ruk_loop:
  ld hl, (rle_rem)
  ld a, h
  or l
  ret z                       ; all units produced
  ld hl, (rle_sp)             ; read control byte
  ld a, (hl)
  inc hl
  ld (rle_sp), hl
  bit 7, a
  jr nz, ruk_rep
  ; literal: n = a+1 units (bit7 clear -> a in 0..127)
  inc a
  ld (rle_cnt), a
ruk_lit:
  call rle_copy_unit          ; (rle_sp) -> (rle_bp), advance both
  call rle_dec_rem
  ld a, (rle_cnt)
  dec a
  ld (rle_cnt), a
  jr nz, ruk_lit
  jr ruk_loop
ruk_rep:
  and $7F
  add a, 2                    ; count (2..129)
  ld (rle_cnt), a
  call rle_read_unit          ; (rle_sp) -> rle_unit, advance rle_sp
ruk_rw:
  call rle_write_unit         ; rle_unit -> (rle_bp), advance rle_bp
  call rle_dec_rem
  ld a, (rle_cnt)
  dec a
  ld (rle_cnt), a
  jr nz, ruk_rw
  jr ruk_loop

; ------------------------------------------------------------
; rle_pack: HL = block src, DE = stream dst, BC = unit count.
; Returns DE = end of stream (length = DE - original dst).
; ------------------------------------------------------------
rle_pack:
  ld (rle_bp), hl             ; bp = source block read ptr (i)
  ld (rle_sp), de             ; sp = dst stream write ptr
  ld (rle_rem), bc
rp_loop:
  ld hl, (rle_rem)
  ld a, h
  or l
  jr z, rp_done
  call rle_count_run          ; rle_cnt = run (1..129)
  ld a, (rle_cnt)
  cp 2
  jr c, rp_literal
  ; --- repeat run: ctrl = $80 | (run-2), then 1 unit ---
  sub 2
  or $80
  call rle_emit_byte
  ld hl, (rle_bp)             ; copy the unit at bp to the stream
  ld de, (rle_sp)
  ld bc, 4
  ldir
  ld (rle_sp), de
  call rle_advance_run        ; bp += run units, rem -= run
  jr rp_loop
rp_literal:
  call rle_count_literal      ; rle_cnt = literal length (1..128)
  ld a, (rle_cnt)
  dec a
  call rle_emit_byte          ; ctrl = len-1
rp_lit_copy:
  ld hl, (rle_bp)             ; copy one literal unit bp -> stream
  ld de, (rle_sp)
  ld bc, 4
  ldir
  ld (rle_bp), hl
  ld (rle_sp), de
  call rle_dec_rem
  ld a, (rle_cnt)
  dec a
  ld (rle_cnt), a
  jr nz, rp_lit_copy
  jr rp_loop
rp_done:
  ld de, (rle_sp)
  ret

; ---- run length at bp: consecutive units == unit[bp], cap min(rem,129) ----
rle_count_run:
  ld bc, 1                    ; BC = run
crun_loop:
  ld a, c
  cp 129
  jr z, crun_done             ; cap
  ld hl, (rle_rem)
  ld a, h
  or a
  jr nz, crun_inrange         ; rem >= 256 > run -> in range
  ld a, c                     ; rem < 256: compare run vs rem(low = L)
  cp l
  jr nc, crun_done            ; run >= rem -> stop
crun_inrange:
  ld a, c                     ; scan = bp + run*4
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl
  ld de, (rle_bp)
  add hl, de                  ; HL = scan unit
  ld de, (rle_bp)             ; DE = ref unit
  ld a, (de)
  cp (hl)
  jr nz, crun_done
  inc hl
  inc de
  ld a, (de)
  cp (hl)
  jr nz, crun_done
  inc hl
  inc de
  ld a, (de)
  cp (hl)
  jr nz, crun_done
  inc hl
  inc de
  ld a, (de)
  cp (hl)
  jr nz, crun_done
  inc bc                      ; equal -> run++
  jr crun_loop
crun_done:
  ld (rle_cnt), bc
  ret

; ---- literal length at bp: units until a repeat begins, cap 128 ----
rle_count_literal:
  ld bc, 0                    ; BC = L
clit_loop:
  ld a, c
  cp 128
  jr z, clit_done             ; cap
  ld hl, (rle_rem)            ; L < rem ?
  ld a, h
  or a
  jr nz, clit_inrange
  ld a, c
  cp l
  jr nc, clit_done            ; L >= rem -> stop
clit_inrange:
  ld hl, (rle_rem)            ; does U[p+1] exist? need L+1 < rem
  ld a, h
  or a
  jr nz, clit_havenext        ; rem >= 256 > L+1
  ld a, c
  inc a
  cp l
  jr nc, clit_incl            ; L+1 >= rem -> no p+1 -> include U[p]
clit_havenext:
  ld a, c                     ; p = bp + L*4
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl
  ld de, (rle_bp)
  add hl, de                  ; HL = p
  ld d, h                     ; DE = p+1 unit (p + 4)
  ld e, l
  inc de
  inc de
  inc de
  inc de
  ld a, (de)                  ; compare U[p] vs U[p+1]
  cp (hl)
  jr nz, clit_incl            ; differ -> include U[p]
  inc hl
  inc de
  ld a, (de)
  cp (hl)
  jr nz, clit_incl
  inc hl
  inc de
  ld a, (de)
  cp (hl)
  jr nz, clit_incl
  inc hl
  inc de
  ld a, (de)
  cp (hl)
  jr nz, clit_incl
  jr clit_done                ; all equal -> repeat starts at p -> stop
clit_incl:
  inc bc                      ; L++
  jr clit_loop
clit_done:
  ld a, c                     ; safety: never emit a zero-length literal
  or a
  jr nz, clit_store
  ld c, 1
clit_store:
  ld (rle_cnt), bc
  ret

; ---- small shared helpers ----
rle_copy_unit:                ; (rle_sp) -> (rle_bp), advance both by 4
  ld hl, (rle_sp)
  ld de, (rle_bp)
  ld bc, 4
  ldir
  ld (rle_sp), hl
  ld (rle_bp), de
  ret

rle_read_unit:                ; (rle_sp) -> rle_unit, advance rle_sp by 4
  ld hl, (rle_sp)
  ld de, rle_unit
  ld bc, 4
  ldir
  ld (rle_sp), hl
  ret

rle_write_unit:               ; rle_unit -> (rle_bp), advance rle_bp by 4
  ld hl, rle_unit
  ld de, (rle_bp)
  ld bc, 4
  ldir
  ld (rle_bp), de
  ret

rle_dec_rem:                  ; rem -= 1
  ld hl, (rle_rem)
  dec hl
  ld (rle_rem), hl
  ret

rle_emit_byte:                ; write A to (rle_sp), advance rle_sp
  ld hl, (rle_sp)
  ld (hl), a
  inc hl
  ld (rle_sp), hl
  ret

rle_advance_run:              ; bp += rle_cnt units, rem -= rle_cnt
  ld a, (rle_cnt)
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl                  ; HL = cnt*4
  ex de, hl
  ld hl, (rle_bp)
  add hl, de
  ld (rle_bp), hl
  ld a, (rle_cnt)
  ld e, a
  ld d, 0
  ld hl, (rle_rem)
  or a
  sbc hl, de
  ld (rle_rem), hl
  ret

; ============================================================
; M2 DRAFT (UNVERIFIED, opt-in, NOT yet called from anywhere).
; SMDJ4 directory/heap LOAD. Read-only on SRAM -> cannot corrupt
; saves even if buggy, so safe to carry build-clean. SAVE (which
; writes SRAM) is spec'd in COMPRESSION.md, not coded blind.
; Wire into PROJECT load + verify live (after `make selftest`
; passes) before trusting. No-straddle: a blob lives in one bank.
; ============================================================
.DEFINE SD4_SUPER   32
.DEFINE SD4_DIRENT  8
.DEFINE SD4_DIRN    32
.DEFINE SD4_HEAP    288              ; SD4_SUPER + SD4_DIRENT*SD4_DIRN
.DEFINE SD4_UNITS   SAVE_SIZE/4
.DEFINE SRAM_WIN    $8000
.DEFINE SRAM_BANK0  $08
.DEFINE SRAM_BANK1  $0C

; map a logical SRAM offset HL -> set $FFFC to its 16 KB bank and
; return HL = $8000 + (off & $3FFF). No-straddle => map once per blob.
rle_sram_map:
  ld a, h
  cp $40
  jr c, rsm_b0
  ld a, SRAM_BANK1
  ld ($FFFC), a
  ld a, h
  and $3F
  or $80
  ld h, a
  ret
rsm_b0:
  ld a, SRAM_BANK0
  ld ($FFFC), a
  ld a, h
  or $80
  ld h, a
  ret

; rle_song_load: A = slot (0..SD4_DIRN-1). Decompresses into wave_ram.
; Returns Z = loaded & checksum-ok, NZ = empty slot / bad checksum.
rle_song_load:
  ld l, a                              ; entry = SRAM_WIN + SD4_SUPER + slot*8
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  ld de, SRAM_WIN + SD4_SUPER
  add hl, de
  ld a, SRAM_BANK0
  ld ($FFFC), a                        ; directory is in bank 0
  ld a, (hl)
  cp $A5
  jr nz, rsl_bad                       ; not a valid entry
  inc hl
  ld a, (hl)                           ; +1 raw flag
  ld (rle_cnt), a                      ; stash (low byte)
  inc hl
  ld e, (hl)
  inc hl
  ld d, (hl)                           ; DE = heap_off
  inc hl
  ld c, (hl)
  inc hl
  ld b, (hl)                           ; BC = blob_len
  inc hl
  ld a, (hl)                           ; +6 checksum lo -> stash
  ld (rle_unit+0), a
  inc hl
  ld a, (hl)                           ; +7 checksum hi -> stash
  ld (rle_unit+1), a
  push bc                              ; blob_len (for raw copy)
  ld hl, SD4_HEAP
  add hl, de                           ; HL = logical blob offset
  call rle_sram_map                    ; set bank, HL = physical src
  pop bc                               ; blob_len
  ld a, (rle_cnt)
  or a
  jr z, rsl_rle
  ld de, wave_ram                      ; raw: straight copy
  ldir
  jr rsl_check
rsl_rle:
  ld de, wave_ram
  ld bc, SD4_UNITS
  call rle_unpack                      ; stream(SRAM) -> wave_ram(RAM)
rsl_check:
  ld hl, wave_ram                      ; wave_ram is RAM (always mapped)
  call sram_sum                        ; DE = computed 16-bit sum
  ld a, (rle_unit+0)                   ; compare to the stashed entry checksum
  cp e
  jr nz, rsl_bad
  ld a, (rle_unit+1)
  cp d
  jr nz, rsl_bad
  xor a                                ; Z = loaded ok
  ret
rsl_bad:
  or 1                                 ; NZ
  ret

.IFDEF RLE_SELFTEST
; Power-on codec self-test (built via `make selftest`). Round-trips an
; embedded 15-unit vector (repeat runs of 5 and 2, literal runs, a single
; unit) through rle_pack -> rle_unpack and prints the result on the splash,
; then freezes so it stays readable. RAM/ROM cost only in this build.
.DEFINE RLE_TEST_UNITS 15

rle_selftest_show:
  call rle_selftest          ; Z = round-trip byte-identical
  ld hl, str_rle_ok
  jr z, rss_go
  ld hl, str_rle_err
rss_go:
  ld b, 16
  ld c, 12
  call print_at
rss_freeze:
  jr rss_freeze              ; stay on the splash with the result

rle_selftest:
  ld hl, rle_test_vec        ; pack the vector
  ld de, rle_test_pk
  ld bc, RLE_TEST_UNITS
  call rle_pack
  ld hl, rle_test_pk         ; unpack it back
  ld de, rle_test_un
  ld bc, RLE_TEST_UNITS
  call rle_unpack
  ld hl, rle_test_vec        ; compare to the original
  ld de, rle_test_un
  ld bc, RLE_TEST_UNITS*4
rst_cmp:
  ld a, (de)
  cp (hl)
  ret nz                     ; NZ = mismatch (fail)
  inc hl
  inc de
  dec bc
  ld a, b
  or c
  jr nz, rst_cmp
  xor a                      ; Z = pass
  ret

rle_test_vec:
  .db $AA,$AA,$AA,$AA, $AA,$AA,$AA,$AA, $AA,$AA,$AA,$AA, $AA,$AA,$AA,$AA, $AA,$AA,$AA,$AA
  .db $01,$02,$03,$04, $05,$06,$07,$08, $09,$0A,$0B,$0C
  .db $BB,$BB,$BB,$BB, $BB,$BB,$BB,$BB
  .db $10,$11,$12,$13, $14,$15,$16,$17, $18,$19,$1A,$1B, $1C,$1D,$1E,$1F
  .db $F0,$F1,$F2,$F3
str_rle_ok:  .db "RLE OK ", 0
str_rle_err: .db "RLE ERR", 0
.ENDIF

.ENDS
