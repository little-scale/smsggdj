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
  rss_slot    db        ; M2 save: slot index
  rss_cksum   dw        ; M2 save: block checksum
  rss_dst     dw        ; M2 save: blob physical dst
  rss_bloblen dw        ; M2 save: blob length
  rss_raw     db        ; M2 save: store-raw flag
  rle_heapmax dw        ; M2 save: computed heap_end (logical)
.IFDEF RLE_SELFTEST
  rle_test_pk  dsb 80   ; codec self-test (make selftest): packed buffer
  rle_test_un  dsb 60   ; codec self-test: unpacked buffer (15 units)
  rdt_cksum    dw       ; directory self-test: original block checksum
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
.DEFINE SD4_DIRENT  16               ; valid,raw,off2,len2,cksum2, then 8 echo bytes
.DEFINE SD4_DIRN    32
.DEFINE SD4_HEAP    544              ; SD4_SUPER + SD4_DIRENT*SD4_DIRN
.DEFINE SD4_UNITS   SAVE_SIZE/4
.DEFINE SRAM_WIN    $8000
.DEFINE SRAM_BANK0  $08              ; $FFFC: SRAM enable + bank 0
.DEFINE SRAM_BANK1  $0C              ; SRAM enable + bank 1
.DEFINE SD4_CAP     $8000            ; capacity (TODO: derive from sram_detect; 32K here)

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
  ld l, a                              ; entry = SRAM_WIN + SD4_SUPER + slot*16
  ld h, 0
  add hl, hl
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
  ld (rss_raw), a
  inc hl
  ld e, (hl)
  inc hl
  ld d, (hl)                           ; +2/+3 heap_off
  ld (rle_heapmax), de
  inc hl
  ld e, (hl)
  inc hl
  ld d, (hl)                           ; +4/+5 blob_len
  ld (rss_bloblen), de
  inc hl
  ld e, (hl)
  inc hl
  ld d, (hl)                           ; +6/+7 checksum
  ld (rss_cksum), de
  inc hl                               ; +8: echo settings (8 bytes)
  ld de, echo_mode
  ld bc, 8
  ldir                                 ; restore echo (bank 0, entry mapped)
  ld hl, (rle_heapmax)                 ; logical blob offset = SD4_HEAP + heap_off
  ld de, SD4_HEAP
  add hl, de
  call rle_sram_map                    ; set bank, HL = physical src
  ld a, (rss_raw)
  or a
  jr z, rsl_rle
  ld bc, (rss_bloblen)                 ; raw: straight copy
  ld de, wave_ram
  ldir
  jr rsl_check
rsl_rle:
  ld de, wave_ram
  ld bc, SD4_UNITS
  call rle_unpack                      ; stream(SRAM) -> wave_ram(RAM)
rsl_check:
  ld hl, wave_ram
  call sram_sum                        ; DE = computed checksum
  ld hl, (rss_cksum)
  ld a, l
  cp e
  jr nz, rsl_bad
  ld a, h
  cp d
  jr nz, rsl_bad
  xor a                                ; Z = loaded ok
  ret
rsl_bad:
  or 1                                 ; NZ
  ret

; rle_dir_init: write the SMDJ4 superblock + clear all directory entries
; (fresh cart). Caller must smp_abort first (this enables SRAM).
rle_dir_init:
  ld a, SRAM_BANK0
  ld ($FFFC), a
  ld hl, SRAM_WIN
  ld (hl), 'S'
  inc hl
  ld (hl), 'M'
  inc hl
  ld (hl), 'D'
  inc hl
  ld (hl), 'J'
  inc hl
  ld (hl), '4'
  inc hl
  ld (hl), 1                           ; version
  inc hl
  ld (hl), SD4_DIRN                     ; entry count
  ld hl, SRAM_WIN + SD4_SUPER
  ld bc, SD4_DIRN * SD4_DIRENT
rdi_clr:
  ld (hl), 0
  inc hl
  dec bc
  ld a, b
  or c
  jr nz, rdi_clr
  ret

; rle_heap_end -> HL (= rle_heapmax) = max(SD4_HEAP + off + len) over valid
; entries, else SD4_HEAP. Reads the directory (bank 0).
rle_heap_end:
  ld a, SRAM_BANK0
  ld ($FFFC), a
  ld hl, SD4_HEAP
  ld (rle_heapmax), hl
  ld ix, SRAM_WIN + SD4_SUPER
  ld b, SD4_DIRN
rhe_loop:
  ld a, (ix+0)
  cp $A5
  jr nz, rhe_next
  ld e, (ix+2)
  ld d, (ix+3)                         ; DE = off
  ld l, (ix+4)
  ld h, (ix+5)                         ; HL = len
  add hl, de                           ; off + len
  ld de, SD4_HEAP
  add hl, de                           ; end = SD4_HEAP + off + len
  ld de, (rle_heapmax)
  ld a, e
  sub l
  ld a, d
  sbc a, h                             ; max - end ; carry if end > max
  jr nc, rhe_next
  ld (rle_heapmax), hl
rhe_next:
  ld de, SD4_DIRENT
  add ix, de
  djnz rhe_loop
  ld hl, (rle_heapmax)
  ret

; rle_song_save: A = slot. Packs wave_ram into the heap (no-straddle),
; writes the directory entry. Z = saved, NZ = SRAM full. Caller smp_abort's.
rle_song_save:
  ld (rss_slot), a
  ld hl, wave_ram
  call sram_sum                        ; DE = block checksum
  ld (rss_cksum), de
  call rle_heap_end                    ; rle_heapmax = heap_end
  ; no-straddle: if (heap_end & $3FFF) + SAVE_SIZE > $4000, bump to next bank
  ld a, h
  and $3F
  ld d, a
  ld e, l                              ; DE = heap_end within-bank offset
  ld hl, SAVE_SIZE
  add hl, de
  ld a, h
  cp $40
  jr c, rss_fits
  jr nz, rss_bump
  ld a, l
  or a
  jr z, rss_fits
rss_bump:
  ld hl, (rle_heapmax)
  ld a, h
  and $C0
  ld h, a
  ld l, 0                              ; heap_end & ~$3FFF (bank base)
  ld de, $4000
  add hl, de                           ; next bank boundary
  ld (rle_heapmax), hl
rss_fits:
  ld hl, (rle_heapmax)                 ; capacity: heap_end + SAVE_SIZE > CAP?
  ld de, SAVE_SIZE
  add hl, de
  ld de, SD4_CAP
  ld a, e
  sub l
  ld a, d
  sbc a, h                             ; CAP - (heap_end+SAVE_SIZE) ; carry if full
  jp c, rss_full
  ld hl, (rle_heapmax)
  call rle_sram_map                    ; set bank, HL = physical dst
  ld (rss_dst), hl
  ex de, hl                            ; DE = dst
  ld hl, wave_ram
  ld bc, SD4_UNITS
  call rle_pack                        ; DE = stream end
  ld hl, (rss_dst)
  ex de, hl                            ; HL = end, DE = dst
  or a
  sbc hl, de                           ; HL = blob_len
  ld (rss_bloblen), hl
  ld de, SAVE_SIZE                      ; store-raw if blob_len >= SAVE_SIZE
  ld a, h
  cp d
  jr c, rss_rle
  jr nz, rss_storeraw
  ld a, l
  cp e
  jr c, rss_rle
rss_storeraw:
  ld de, (rss_dst)                     ; raw: overwrite with a straight copy
  ld hl, wave_ram
  ld bc, SAVE_SIZE
  ldir
  ld hl, SAVE_SIZE
  ld (rss_bloblen), hl
  ld a, 1
  ld (rss_raw), a
  jr rss_entry
rss_rle:
  xor a
  ld (rss_raw), a
rss_entry:
  ld a, SRAM_BANK0                     ; the directory lives in bank 0
  ld ($FFFC), a
  ld a, (rss_slot)
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl                           ; slot*16
  ld de, SRAM_WIN + SD4_SUPER
  add hl, de                           ; HL = entry ptr
  ld (hl), $A5
  inc hl
  ld a, (rss_raw)
  ld (hl), a
  inc hl
  push hl
  ld hl, (rle_heapmax)                 ; heap_off = heap_end - SD4_HEAP
  ld bc, SD4_HEAP
  or a
  sbc hl, bc
  ex de, hl                            ; DE = heap_off
  pop hl
  ld (hl), e
  inc hl
  ld (hl), d
  inc hl
  ld de, (rss_bloblen)
  ld (hl), e
  inc hl
  ld (hl), d
  inc hl
  ld de, (rss_cksum)
  ld (hl), e
  inc hl
  ld (hl), d                           ; +7 checksum hi
  inc hl                               ; +8: echo settings (8 bytes)
  ld d, h
  ld e, l
  ld hl, echo_mode
  ld bc, 8
  ldir                                 ; echo_mode -> entry+8..+15
  xor a                                ; Z = saved
  ret
rss_full:
  or 1                                 ; NZ
  ret

.IFDEF RLE_SELFTEST
; Power-on codec self-test (built via `make selftest`). Round-trips an
; embedded 15-unit vector (repeat runs of 5 and 2, literal runs, a single
; unit) through rle_pack -> rle_unpack and prints the result on the splash,
; then freezes so it stays readable. RAM/ROM cost only in this build.
.DEFINE RLE_TEST_UNITS 15

rle_selftest_show:
  call rle_selftest          ; codec round-trip (RAM only)
  ld hl, str_rle_ok
  jr z, rss_c1
  ld hl, str_rle_err
rss_c1:
  ld b, 14
  ld c, 12
  call print_at
  call rle_dirtest           ; directory save->load round-trip (writes SRAM)
  ld hl, str_dir_ok
  jr z, rss_c2
  ld hl, str_dir_err
rss_c2:
  ld b, 16
  ld c, 12
  call print_at
  call display_on            ; splash left the display OFF + screen wiped
rss_freeze:
  jr rss_freeze              ; freeze on the result (interrupts already off)

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

; directory save->load round-trip on SRAM: checksum the live block, init a
; fresh directory, save to slot 0, corrupt RAM, load slot 0 back, confirm the
; block is byte-identical (load also self-checks against the stored checksum).
rle_dirtest:
  call smp_abort             ; SRAM is about to cover the sample pool
  ld a, $3C                  ; seed echo with a known pattern (uninit at boot)
  ld (echo_mode), a
  ld a, $5A
  ld (echo_mode+1), a
  ld hl, wave_ram
  call sram_sum
  ld (rdt_cksum), de
  call rle_dir_init
  xor a
  call rle_song_save
  ret nz                     ; SRAM full
  ld a, $99                  ; corrupt the block AND echo
  ld (wave_ram), a
  ld (echo_mode), a
  ld (echo_mode+1), a
  xor a
  call rle_song_load         ; verifies its own checksum + restores echo
  ret nz
  ld a, (echo_mode)          ; echo restored?
  cp $3C
  ret nz
  ld a, (echo_mode+1)
  cp $5A
  ret nz
  ld hl, wave_ram            ; belt-and-braces: re-checksum == original
  call sram_sum
  ld hl, (rdt_cksum)
  ld a, l
  cp e
  ret nz
  ld a, h
  cp d
  ret

rle_test_vec:
  .db $AA,$AA,$AA,$AA, $AA,$AA,$AA,$AA, $AA,$AA,$AA,$AA, $AA,$AA,$AA,$AA, $AA,$AA,$AA,$AA
  .db $01,$02,$03,$04, $05,$06,$07,$08, $09,$0A,$0B,$0C
  .db $BB,$BB,$BB,$BB, $BB,$BB,$BB,$BB
  .db $10,$11,$12,$13, $14,$15,$16,$17, $18,$19,$1A,$1B, $1C,$1D,$1E,$1F
  .db $F0,$F1,$F2,$F3
str_rle_ok:  .db "RLE OK ", 0
str_rle_err: .db "RLE ERR", 0
str_dir_ok:  .db "DIR OK ", 0
str_dir_err: .db "DIR ERR", 0
.ENDIF

.ENDS
