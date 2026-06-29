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
  song_name   dsb 8     ; current song's 8-char name (metadata, not in the block)
  ; heap compaction (rle_compact): repack blobs in offset order to close holes
  rcp_dst   dw          ; running placement offset (logical)
  rcp_prev  dw          ; last processed source offset (offset-order scan)
  rcp_hi    dw          ; scan upper bound / sentinel
  rcp_off   dw          ; chosen blob's absolute offset (= scan best)
  rcp_len   dw          ; chosen blob's length
  rcp_ent   dw          ; chosen directory entry pointer
  rcp_found db          ; 1 = findmin found a blob
  rmv_src   dw          ; blob move: working source (logical)
  rmv_dst   dw          ; blob move: working dest (logical)
  rmv_n     db          ; blob move: current chunk size
  rcp_buf   dsb 64      ; blob move: cross-bank staging buffer
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
.DEFINE SD4_DIRENT  32               ; +0 valid,raw,off2,len2,cksum2  +8 echo8  +16 name8  +24 rsvd8
.DEFINE SD4_DIRN    32
.DEFINE SD4_HEAP    1056             ; SD4_SUPER + SD4_DIRENT*SD4_DIRN
.DEFINE SD4_UNITS   SAVE_SIZE/4
.DEFINE SRAM_WIN    $8000
.DEFINE SRAM_BANK0  $08              ; $FFFC: SRAM enable + bank 0
.DEFINE SRAM_BANK1  $0C              ; SRAM enable + bank 1
.DEFINE SD4_CAP     $8000            ; max capacity (32K). The live capacity is the
                                     ; runtime `sd4_cap` (set from sram_detect: 8K/
                                     ; 16K/32K); SD4_CAP is only the heap-scan sentinel.
; NOTE: the OPTIONS config block lives at CFG_ADDR $BF60 = logical heap offset
; $3F60 (16224) in bank 0, which sits inside this heap range. Compressed songs
; bump to bank 1 long before reaching it, but a pathological near-raw blob could
; in theory overwrite it. Fix someday: cap bank-0 heap below $3F60 (or relocate
; the config). Mirror any change in tools/smdj4.js buildSav + SAVEFORMAT.md.

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
  ld l, a                              ; entry = SRAM_WIN + SD4_SUPER + slot*32
  ld h, 0
  add hl, hl
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
  ld de, song_name                     ; +16: name (8 bytes)
  ld bc, 8
  ldir
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

; rle_dir_ensure: init the directory if the cart isn't already an SMDJ4 image.
rle_dir_ensure:
  ld a, SRAM_BANK0
  ld ($FFFC), a
  ld a, ($8000)
  cp 'S'
  jp nz, rle_dir_init
  ld a, ($8004)
  cp '4'
  ret z
  jp rle_dir_init

; rle_can_save -> Z + A=0 if there is room for one more SAVE_SIZE (worst-case)
; blob, leaving rle_heapmax at the no-straddle placement offset; NZ + A=1 if the
; SRAM is full. Reads the directory (bank 0). Shared by rle_song_save and the
; FILES UI (trailing-empty-slot gate).
rle_can_save:
  call rle_heap_end                    ; rle_heapmax = heap_end (HL too)
  ; single-bank carts (<= 16K) have no internal $4000 boundary -> no straddle bump
  ld a, (sd4_cap+1)
  cp $80
  jr c, rcs_fits                       ; cap < 32K -> skip the bump
  ; no-straddle: if (heap_end & $3FFF) + SAVE_SIZE > $4000, bump to next bank
  ld a, h
  and $3F
  ld d, a
  ld e, l                              ; DE = heap_end within-bank offset
  ld hl, SAVE_SIZE
  add hl, de
  ld a, h
  cp $40
  jr c, rcs_fits
  jr nz, rcs_bump
  ld a, l
  or a
  jr z, rcs_fits
rcs_bump:
  ld hl, (rle_heapmax)
  ld a, h
  and $C0
  ld h, a
  ld l, 0                              ; heap_end & ~$3FFF (bank base)
  ld de, $4000
  add hl, de                           ; next bank boundary
  ld (rle_heapmax), hl
rcs_fits:
  ld hl, (rle_heapmax)                 ; capacity: heap_end + SAVE_SIZE > CAP?
  ld de, SAVE_SIZE
  add hl, de
  ld de, (sd4_cap)
  ld a, e
  sub l
  ld a, d
  sbc a, h                             ; CAP - (heap_end+SAVE_SIZE) ; carry if full
  jr c, rcs_full
  xor a                                ; Z = room
  ret
rcs_full:
  ld a, 1                              ; NZ = full
  ret

; rle_dir_count -> A = number of valid ($A5) directory entries. bank 0.
rle_dir_count:
  ld a, SRAM_BANK0
  ld ($FFFC), a
  ld ix, SRAM_WIN + SD4_SUPER
  ld b, SD4_DIRN
  ld c, 0
rdc_loop:
  ld a, (ix+0)
  cp $A5
  jr nz, rdc_next
  inc c
rdc_next:
  ld de, SD4_DIRENT
  add ix, de
  djnz rdc_loop
  ld a, c
  ret

; rle_dir_pack: compact the directory so valid entries are contiguous at the
; front (heap blobs are untouched; each entry's heap_off stays valid). Idempotent;
; normalises any holes left by the old fixed-slot model. bank 0.
rle_dir_pack:
  ld a, SRAM_BANK0
  ld ($FFFC), a
  ld hl, SRAM_WIN + SD4_SUPER          ; src
  ld de, SRAM_WIN + SD4_SUPER          ; dst
  ld b, SD4_DIRN
rdp_loop:
  ld a, (hl)
  cp $A5
  jr z, rdp_copy
  push de                              ; invalid: skip src, dst unchanged
  ld de, SD4_DIRENT
  add hl, de
  pop de
  jr rdp_next
rdp_copy:
  push bc
  ld bc, SD4_DIRENT
  ldir                                 ; (HL)->(DE), both += 32
  pop bc
rdp_next:
  djnz rdp_loop
  ; clear the tail (DE .. end-of-directory)
  ld hl, SRAM_WIN + SD4_SUPER + SD4_DIRN*SD4_DIRENT
  or a
  sbc hl, de                           ; HL = tail byte count
  ld a, h
  or l
  ret z
  ld b, h
  ld c, l                              ; BC = tail bytes
  ex de, hl                            ; HL = dst (clear ptr)
rdp_clr:
  ld (hl), 0
  inc hl
  dec bc
  ld a, b
  or c
  jr nz, rdp_clr
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

; rss_free_old: if the target slot (rss_slot) already holds a valid blob,
; invalidate its entry and compact the heap so the upcoming save reuses that
; space. Without this, re-saving the same slot orphans the old blob every time
; and the heap (free space) only ever shrinks. New-file slots ($A5 absent) are
; left alone. bank 0; leaves bank 0 mapped (rle_compact does).
rss_free_old:
  ld a, SRAM_BANK0
  ld ($FFFC), a
  ld a, (rss_slot)
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl                           ; slot*32
  ld de, SRAM_WIN + SD4_SUPER
  add hl, de                           ; HL = entry(slot)
  ld a, (hl)
  cp $A5
  ret nz                               ; empty slot: nothing to reclaim
  ld (hl), 0                           ; invalidate -> old blob becomes a hole
  jp rle_compact                       ; slide later blobs down to close it

; rle_song_save: A = slot. Packs wave_ram into the heap (no-straddle),
; writes the directory entry. Z = saved, NZ = SRAM full. Caller smp_abort's.
rle_song_save:
  ld (rss_slot), a
  call rss_free_old                    ; reclaim this slot's previous blob first
  ld hl, wave_ram
  call sram_sum                        ; DE = block checksum
  ld (rss_cksum), de
  call rle_can_save                    ; rle_heapmax = no-straddle placement
  jp nz, rss_full
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
  add hl, hl
  add hl, hl                           ; slot*32
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
  ldir                                 ; echo_mode -> entry+8..+15 (DE -> +16)
  ld hl, song_name                     ; +16: name (8 bytes)
  ld bc, 8
  ldir                                 ; song_name -> entry+16..+23
  xor a                                ; Z = saved
  ret
rss_full:
  or 1                                 ; NZ
  ret

; rle_song_delete: A = slot. Removes the entry and shifts the following entries
; down to keep the directory packed, then calls rle_compact to close the heap
; hole the freed blob left. bank 0.
rle_song_delete:
  ld (rss_slot), a
  ld a, SRAM_BANK0
  ld ($FFFC), a
  ; bytes to shift = (SD4_DIRN-1 - slot) * 32  -> BC
  ld a, SD4_DIRN-1
  ld hl, rss_slot
  sub (hl)
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl                           ; (31-slot)*32
  ld b, h
  ld c, l                              ; BC = shift length
  ; dst = entry(slot) -> DE ; src = entry(slot+1) -> HL
  ld a, (rss_slot)
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl                           ; slot*32
  ld de, SRAM_WIN + SD4_SUPER
  add hl, de                           ; HL = entry(slot)
  ld d, h
  ld e, l                              ; DE = dst
  push bc
  ld bc, SD4_DIRENT
  add hl, bc                           ; HL = entry(slot+1) = src
  pop bc
  ld a, b
  or c
  jr z, rsd_clrlast                    ; slot is the last entry: nothing to shift
  ldir                                 ; shift down; DE -> entry(SD4_DIRN-1)
rsd_clrlast:
  ld b, SD4_DIRENT                     ; clear the now-stale last entry at DE
rsd_z:
  ld a, 0
  ld (de), a
  inc de
  djnz rsd_z
  jp rle_compact                       ; close the heap hole the delete left

; rle_compact: slide every valid blob down to close heap holes, processing in
; ascending offset order so an unmoved blob is never overwritten (all moves are
; "down"). Keeps the no-straddle invariant (bumps a blob to the next bank when
; it wouldn't fit), and updates each entry's heap_off. Leaves bank 0 mapped.
; Reads the directory in bank 0; the data move maps the blob's own bank.
rle_compact:
  ld hl, SD4_HEAP
  ld (rcp_dst), hl
  dec hl
  ld (rcp_prev), hl                    ; prev = SD4_HEAP - 1 (nothing placed yet)
  ld hl, SD4_CAP
  ld (rcp_hi), hl                      ; scan sentinel
rcp_loop:
  call rcp_findmin                     ; bank 0; Z = none left, NZ = found
  jr z, rcp_done
  ld a, (sd4_cap+1)                    ; single-bank cart -> no straddle bump
  cp $80
  jr c, rcp_nobump
  ; no-straddle: if (dst & $3FFF) + len > $4000, bump dst to the next bank
  ld hl, (rcp_dst)
  ld a, h
  and $3F
  ld d, a
  ld e, l                              ; DE = dst within-bank offset
  ld hl, (rcp_len)
  add hl, de
  ld a, h
  cp $40
  jr c, rcp_nobump
  jr nz, rcp_bump
  ld a, l
  or a
  jr z, rcp_nobump
rcp_bump:
  ld hl, (rcp_dst)
  ld a, h
  and $C0
  ld h, a
  ld l, 0                              ; dst & ~$3FFF (bank base)
  ld de, $4000
  add hl, de
  ld (rcp_dst), hl
rcp_nobump:
  ld hl, (rcp_dst)                     ; already in place? skip the move
  ld de, (rcp_off)
  ld a, l
  cp e
  jr nz, rcp_mv
  ld a, h
  cp d
  jr z, rcp_after
rcp_mv:
  call rcp_move                        ; maps the blob's bank(s) to copy down
  ld a, SRAM_BANK0
  ld ($FFFC), a                        ; back to the directory bank
  ld hl, (rcp_dst)                     ; entry heap_off = dst - SD4_HEAP
  ld de, SD4_HEAP
  or a
  sbc hl, de
  ld ix, (rcp_ent)
  ld (ix+2), l
  ld (ix+3), h
rcp_after:
  ld hl, (rcp_off)                     ; prev = this blob's source offset
  ld (rcp_prev), hl
  ld hl, (rcp_dst)                     ; dst += len
  ld de, (rcp_len)
  add hl, de
  ld (rcp_dst), hl
  jr rcp_loop
rcp_done:
  ld a, SRAM_BANK0
  ld ($FFFC), a
  ret

; rcp_findmin: scan the directory for the valid blob with the smallest absolute
; offset in (rcp_prev, rcp_hi). Maps bank 0. NZ + rcp_off/rcp_len/rcp_ent set if
; found; Z if none.
rcp_findmin:
  ld a, SRAM_BANK0
  ld ($FFFC), a
  xor a
  ld (rcp_found), a
  ld hl, (rcp_hi)
  ld (rcp_off), hl                     ; best = hi sentinel
  ld ix, SRAM_WIN + SD4_SUPER
  ld b, SD4_DIRN
rfm_loop:
  ld a, (ix+0)
  cp $A5
  jr nz, rfm_next
  ld l, (ix+2)
  ld h, (ix+3)
  ld de, SD4_HEAP
  add hl, de                           ; HL = abs offset
  ld de, (rcp_prev)                    ; abs > prev?  (carry if prev < abs)
  ld a, e
  sub l
  ld a, d
  sbc a, h
  jr nc, rfm_next
  ld de, (rcp_off)                     ; abs < best?  (carry if abs < best)
  ld a, l
  sub e
  ld a, h
  sbc a, d
  jr nc, rfm_next
  ld (rcp_off), hl                     ; new best
  ld l, (ix+4)
  ld h, (ix+5)
  ld (rcp_len), hl
  ld (rcp_ent), ix
  ld a, 1
  ld (rcp_found), a
rfm_next:
  ld de, SD4_DIRENT
  add ix, de
  djnz rfm_loop
  ld a, (rcp_found)
  or a                                 ; Z = none, NZ = found
  ret

; rcp_move: copy rcp_len bytes from logical rcp_off down to rcp_dst (dst <= src).
; Goes through a small RAM buffer in <=64-byte chunks, so it works whether the
; two ends share a bank or straddle it (one bank is mapped at a time). Forward
; chunk order is safe for a down-move. Preserves rcp_off / rcp_dst / rcp_len.
rcp_move:
  ld hl, (rcp_off)
  ld (rmv_src), hl
  ld hl, (rcp_dst)
  ld (rmv_dst), hl
  ld bc, (rcp_len)
rmv_loop:
  ld a, b
  or c
  ret z
  ld a, b                              ; n = min(BC, 64)
  or a
  jr nz, rmv_full
  ld a, c
  cp 64
  jr c, rmv_setn
rmv_full:
  ld a, 64
rmv_setn:
  ld (rmv_n), a
  push bc
  ld hl, (rmv_src)                     ; source bank -> buffer
  call rle_sram_map
  ld de, rcp_buf
  ld a, (rmv_n)
  ld c, a
  ld b, 0
  ldir
  ld hl, (rmv_dst)                     ; buffer -> dest bank
  call rle_sram_map
  ex de, hl
  ld hl, rcp_buf
  ld a, (rmv_n)
  ld c, a
  ld b, 0
  ldir
  pop bc
  ld a, (rmv_n)                        ; advance both ends, BC -= n
  ld e, a
  ld d, 0
  ld hl, (rmv_src)
  add hl, de
  ld (rmv_src), hl
  ld hl, (rmv_dst)
  add hl, de
  ld (rmv_dst), hl
  ld a, c
  sub e
  ld c, a
  ld a, b
  sbc a, d
  ld b, a
  jr rmv_loop

; rle_name_default: song_name = 8 spaces (for a fresh/loaded-demo song).
rle_name_default:
  ld hl, song_name
  ld a, $20
  ld b, 8
rnd_l:
  ld (hl), a
  inc hl
  djnz rnd_l
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
  call rle_compacttest       ; delete-with-compaction round-trip (writes SRAM)
  ld hl, str_cmp_ok
  jr z, rss_c3
  ld hl, str_cmp_err
rss_c3:
  ld b, 18
  ld c, 12
  call print_at
  call rle_captest           ; 16K capacity path (single-bank, no straddle bump)
  ld hl, str_cap_ok
  jr z, rss_c4
  ld hl, str_cap_err
rss_c4:
  ld b, 20
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
  ld hl, song_name           ; seed the name = "AAAAAAAA"
  ld a, $41
  ld b, 8
rdt_nseed:
  ld (hl), a
  inc hl
  djnz rdt_nseed
  ld hl, wave_ram
  call sram_sum
  ld (rdt_cksum), de
  call rle_dir_init
  xor a
  call rle_song_save
  ret nz                     ; SRAM full
  ld a, $99                  ; corrupt the block, echo AND name
  ld (wave_ram), a
  ld (echo_mode), a
  ld (echo_mode+1), a
  ld (song_name), a
  ld (song_name+7), a
  xor a
  call rle_song_load         ; verifies its checksum + restores echo & name
  ret nz
  ld a, (echo_mode)          ; echo restored?
  cp $3C
  ret nz
  ld a, (echo_mode+1)
  cp $5A
  ret nz
  ld a, (song_name)          ; name restored?
  cp $41
  ret nz
  ld a, (song_name+7)
  cp $41
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
; compaction round-trip: save three big (incompressible -> store-raw, so they
; span both SRAM banks) songs, delete the middle one (which compacts the heap,
; pulling the third blob down across the bank boundary), then load both
; survivors. rle_song_load verifies each blob's stored checksum, so a bad move
; fails here. Distinct per-song fills => a swapped/garbled blob can't pass.
rle_compacttest:
  call smp_abort
  call rle_dir_init
  ld a, $11                  ; song 0
  call rct_fill
  xor a
  call rle_song_save
  ret nz
  ld a, $22                  ; song 1 (the one we delete)
  call rct_fill
  ld a, 1
  call rle_song_save
  ret nz
  ld a, $33                  ; song 2 (gets pulled across the bank boundary)
  call rct_fill
  ld a, 2
  call rle_song_save
  ret nz
  ld a, 1                    ; delete the middle song -> dir shift + compaction
  call rle_song_delete
  xor a                      ; slot 0 still song 0 (checksum-verified on load)
  call rle_song_load
  ret nz
  ld a, 1                    ; slot 1 is now the moved song 2
  call rle_song_load
  ret nz
  xor a                      ; Z = pass
  ret

; fill the live block with an incompressible, seed-distinct pattern:
; wave_ram[i] = (i & $FF) XOR A. wave_ram is 256-aligned, so L = i & $FF.
rct_fill:
  ld c, a                    ; C = seed
  ld hl, wave_ram
  ld de, SAVE_SIZE
rcf_loop:
  ld a, l
  xor c
  ld (hl), a
  inc hl
  dec de
  ld a, d
  or e
  jr nz, rcf_loop
  ret

; 16K-cart capacity path: pretend the cart is 16K (sd4_cap = $4000), then check
; that single-bank saves pack contiguously with no straddle bump (two raw 6912 B
; songs fit, 1056..14880 < $4000) and that the third is correctly refused (no
; bank 1 to bump into). Then load the survivors checksum-clean.
rle_captest:
  call smp_abort
  ld hl, $4000               ; pretend 16K
  ld (sd4_cap), hl
  call rle_dir_init
  ld a, $44                  ; song 0 (incompressible -> raw 6912 B)
  call rct_fill
  xor a
  call rle_song_save
  ret nz                     ; must fit
  ld a, $55                  ; song 1
  call rct_fill
  ld a, 1
  call rle_song_save
  ret nz                     ; must fit (ends at 14880 < $4000)
  ld a, $66                  ; song 2 must be refused (would exceed 16K, no bump)
  call rct_fill
  ld a, 2
  call rle_song_save
  jr z, rct_capfail          ; Z = saved = wrong
  xor a                      ; survivors still load clean?
  call rle_song_load
  ret nz
  ld a, 1
  call rle_song_load
  ret nz
  xor a                      ; Z = pass
  ret
rct_capfail:
  or 1                       ; NZ = fail
  ret

str_rle_ok:  .db "RLE OK ", 0
str_rle_err: .db "RLE ERR", 0
str_dir_ok:  .db "DIR OK ", 0
str_dir_err: .db "DIR ERR", 0
str_cmp_ok:  .db "CMP OK ", 0
str_cmp_err: .db "CMP ERR", 0
str_cap_ok:  .db "CAP OK ", 0
str_cap_err: .db "CAP ERR", 0
.ENDIF

.ENDS
