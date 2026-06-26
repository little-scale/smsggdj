// smdj4.js -- SMDJ4 format library for SMSGGDJ (see COMPRESSION.md).
//
// SMDJ4 = larger pools (52 phrases / 40 chains, 6912-byte block) stored in an
// RLE directory+heap SRAM image, replacing SMDJ3's fixed 5376-byte slots.
// Shared by the migration tool and savetool v2. Pure Uint8Array; runs in the
// browser (window.SMDJ4) or node (module.exports / `node smdj4.js` self-test).
//
// PROPOSED on-cart format (the contract the M2 ROM codec must match):
//   The .sav is a LINEAR logical image; the ROM maps logical off -> physical
//   bank = off>>14, addr = $8000 + (off & $3FFF) via $FFFC. Layout:
//     [0]    superblock 32 B:  "SMDJ4"(5) ver(1) count(1)
//                              config(7: 'C''F' pal sync vid fm cksum) reserved
//     [32]   directory: 32 entries x 8 B:
//              valid(1,$A5) raw(1) heap_off(2,LE) blob_len(2,LE) cksum(2,LE)
//     [288]  heap: blobs (RLE or raw) packed contiguous to end of SRAM.
//   Song identity = directory index (slot N), preserving the slot UX.

(function (root) {
  "use strict";
  const RLE = (typeof require === "function") ? require("./rle.js") : root.RLE;

  // ---- block layouts (offset, length) ----
  const SMDJ3 = {
    LEN: 5376,
    pools: { wave:[0,256], phrases:[256,2048], chains:[2304,1024],
             song:[3328,512], instr:[3840,256], tables:[4096,1024], grooves:[5120,256] },
  };
  const SMDJ4 = {
    LEN: 6912,
    pools: { wave:[0,256], phrases:[256,3328], chains:[3584,1280],
             song:[4864,512], instr:[5376,256], tables:[5632,1024], grooves:[6656,256] },
    NUM_PHRASES: 52, NUM_CHAINS: 40, PHRASE_BYTES: 64, CHAIN_BYTES: 32,
  };

  // SMDJ4 .sav geometry. Entry (32 B): valid,raw,off2,len2,cksum2 +8 echo8 +16 name8 +24 rsvd8.
  const SUPER = 32, DIR_ENTRIES = 32, DIR_ENTRY = 32;
  const DIR_OFF = SUPER, HEAP_OFF = SUPER + DIR_ENTRIES * DIR_ENTRY; // 1056
  const MAGIC4 = [0x53,0x4D,0x44,0x4A,0x34];                         // "SMDJ4"
  const HDR = 16;                                                     // .smdj header

  // 16-bit little-endian sum over a block (matches the ROM's sram_sum)
  function checksum(block) {
    let s = 0;
    for (let i = 0; i < block.length; i++) s = (s + block[i]) & 0xFFFF;
    return s;
  }

  // ---- SMDJ3 block -> SMDJ4 block (pool re-layout + blank new entries) ----
  // New phrases get rows of 00 FF 00 00; new chains get $FF (per song_new).
  function expand(block3) {
    if (block3.length !== SMDJ3.LEN) throw new Error("expand: not a 5376-byte block");
    const b4 = new Uint8Array(SMDJ4.LEN);
    // copy each pool that exists in SMDJ3 to its SMDJ4 offset (clamped to old size)
    for (const k of Object.keys(SMDJ3.pools)) {
      const [so, sl] = SMDJ3.pools[k];
      const [doff]   = SMDJ4.pools[k];
      b4.set(block3.subarray(so, so + sl), doff);
    }
    // blank the new phrases (32..51): rows of 00 FF 00 00
    const [po, pl] = SMDJ4.pools.phrases;
    for (let off = po + SMDJ3.pools.phrases[1]; off < po + pl; off += 4) {
      b4[off] = 0x00; b4[off+1] = 0xFF; b4[off+2] = 0x00; b4[off+3] = 0x00;
    }
    // blank the new chains (32..39): $FF
    const [co, cl] = SMDJ4.pools.chains;
    b4.fill(0xFF, co + SMDJ3.pools.chains[1], co + cl);
    return b4;
  }

  // ---- .smdj single-song wrapper (header + block), SMDJ4 ----
  function wrapSmdj4(block4, echo8) {
    if (block4.length !== SMDJ4.LEN) throw new Error("wrap: not a 6912-byte block");
    const out = new Uint8Array(HDR + SMDJ4.LEN);
    out.set(MAGIC4, 0);
    const cs = checksum(block4);
    out[5] = cs & 0xFF; out[6] = (cs >> 8) & 0xFF;
    if (echo8) out.set(echo8.subarray(0, 8), 7);
    out.set(block4, HDR);
    return out;
  }

  // ---- directory/heap .sav assembly ----
  // songs: array of {block(6912), echo?(8)} | null. cartKB in {8,16,32}.
  function buildSav(songs, cartKB, config /*opt 7-byte*/) {
    const total = cartKB * 1024;
    const sav = new Uint8Array(total);            // $00-filled
    sav.set(MAGIC4, 0);
    sav[5] = 1;                                   // version
    sav[6] = DIR_ENTRIES;
    if (config) sav.set(config.subarray(0, 7), 7);
    let heapEnd = HEAP_OFF;
    for (let i = 0; i < DIR_ENTRIES; i++) {
      const s = songs[i];
      const e = DIR_OFF + i * DIR_ENTRY;
      if (!s) { sav[e] = 0; continue; }           // free entry
      const { raw, bytes } = RLE.pack(s.block);
      if (heapEnd + bytes.length > total)
        throw new Error(`SRAM FULL at slot ${i} (need ${bytes.length}, have ${total - heapEnd})`);
      const cs = checksum(s.block);
      sav[e]   = 0xA5;                            // valid
      sav[e+1] = raw ? 1 : 0;
      sav[e+2] = (heapEnd - HEAP_OFF) & 0xFF;
      sav[e+3] = ((heapEnd - HEAP_OFF) >> 8) & 0xFF;
      sav[e+4] = bytes.length & 0xFF;
      sav[e+5] = (bytes.length >> 8) & 0xFF;
      sav[e+6] = cs & 0xFF;
      sav[e+7] = (cs >> 8) & 0xFF;
      if (s.echo) sav.set(s.echo.subarray(0, 8), e + 8);   // +8..+15 echo
      if (s.name) sav.set(s.name.subarray(0, 8), e + 16);  // +16..+23 name
      sav.set(bytes, heapEnd);
      heapEnd += bytes.length;
    }
    return sav;
  }

  // -> array of {block(6912)|null, raw, checksumOK} indexed by slot.
  function readSav(sav) {
    if (![...MAGIC4].every((b, i) => sav[i] === b)) throw new Error("not an SMDJ4 image");
    const n = sav[6] || DIR_ENTRIES;
    const out = [];
    for (let i = 0; i < n; i++) {
      const e = DIR_OFF + i * DIR_ENTRY;
      if (sav[e] !== 0xA5) { out.push(null); continue; }
      const raw = sav[e+1] === 1;
      const off = HEAP_OFF + (sav[e+2] | (sav[e+3] << 8));
      const len = sav[e+4] | (sav[e+5] << 8);
      const cs  = sav[e+6] | (sav[e+7] << 8);
      const echo = sav.subarray(e + 8, e + 16).slice();
      const name = sav.subarray(e + 16, e + 24).slice();
      const blob = sav.subarray(off, off + len);
      const block = raw ? blob.slice() : RLE.decompress(blob);
      out.push({ block, echo, name, raw, checksumOK: checksum(block) === cs });
    }
    return out;
  }

  // ---- reading legacy SMDJ3 (fixed slots) for migration ----
  const SMDJ3_MAGIC = [0x53,0x4D,0x44,0x4A,0x33];   // "SMDJ3"
  const SMDJ3_STRIDE = 0x1520, SMDJ3_HDR = 16, BANK = 0x4000;
  function smdj3Slots(len) { return len <= 0x2000 ? 1 : len <= 0x4000 ? 3 : 6; }
  function smdj3SlotOff(n) { return Math.floor(n/3) * BANK + (n % 3) * SMDJ3_STRIDE; }
  function smdj3ConfigOff(len) { return len <= 0x2000 ? 0x1F60 : 0x3F60; }

  // -> array of {block(5376), echo(8), checksumOK} | null, by slot.
  function readSmdj3Sav(sav) {
    const out = [];
    for (let i = 0; i < smdj3Slots(sav.length); i++) {
      const b = smdj3SlotOff(i);
      if (!SMDJ3_MAGIC.every((m, k) => sav[b + k] === m)) { out.push(null); continue; }
      const block = sav.subarray(b + SMDJ3_HDR, b + SMDJ3_HDR + SMDJ3.LEN).slice();
      const cs = sav[b+5] | (sav[b+6] << 8);
      out.push({ block, echo: sav.subarray(b+7, b+15).slice(), checksumOK: checksum(block) === cs });
    }
    return out;
  }

  // accept an SMDJ3 .smdj (header+block) or a bare 5376-byte block -> block | null
  function unwrapSmdj3(bytes) {
    if (bytes.length >= SMDJ3_HDR + SMDJ3.LEN && SMDJ3_MAGIC.every((m, k) => bytes[k] === m))
      return bytes.subarray(SMDJ3_HDR, SMDJ3_HDR + SMDJ3.LEN).slice();
    if (bytes.length === SMDJ3.LEN) return bytes.slice();
    return null;
  }

  function readSmdj3Config(sav) {
    const o = smdj3ConfigOff(sav.length);
    if (sav[o] === 0x43 && sav[o+1] === 0x46) return sav.subarray(o, o + 7).slice(); // 'C''F'
    return null;
  }

  // SMDJ3 .sav -> migrated SMDJ4 .sav (expand every valid song).
  function migrateSav(smdj3sav, cartKB) {
    const src = readSmdj3Sav(smdj3sav);
    const songs = src.map(s => s ? { block: expand(s.block), echo: s.echo } : null);
    return buildSav(songs, cartKB || 32, readSmdj3Config(smdj3sav));
  }

  const api = { SMDJ3, SMDJ4, SUPER, DIR_ENTRIES, DIR_ENTRY, HEAP_OFF,
                checksum, expand, wrapSmdj4, buildSav, readSav,
                readSmdj3Sav, unwrapSmdj3, readSmdj3Config, migrateSav };
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.SMDJ4 = api;
})(typeof self !== "undefined" ? self : this);

// ---- node self-test: `node tools/smdj4.js` ----
if (typeof require === "function" && require.main === module) {
  const fs = require("fs");
  const S = module.exports;
  let ok = true, msg = [];
  function chk(c, m) { ok = ok && c; msg.push((c ? "Y " : "N ") + m); }

  // 1. expand the real demo block, check pool relocation + blank new entries
  const smdj = new Uint8Array(fs.readFileSync("songs/demo.smdj"));
  const blk3 = smdj.subarray(16, 16 + 5376);
  const blk4 = S.expand(blk3);
  chk(blk4.length === 6912, "expand -> 6912");
  // old phrases preserved at same offset, byte-identical
  chk(Buffer.compare(Buffer.from(blk4.subarray(256, 256+2048)),
                     Buffer.from(blk3.subarray(256, 256+2048))) === 0, "phrases 0-31 preserved");
  // tables moved from 4096 -> 5632 byte-identical
  chk(Buffer.compare(Buffer.from(blk4.subarray(5632, 5632+1024)),
                     Buffer.from(blk3.subarray(4096, 4096+1024))) === 0, "tables relocated");
  // new phrase 32 row 0 == 00 FF 00 00
  const np = 256 + 2048;
  chk(blk4[np]===0 && blk4[np+1]===0xFF && blk4[np+2]===0 && blk4[np+3]===0, "new phrase blank 00FF0000");
  // new chain 32 == FF
  const nc = 3584 + 1024;
  chk(blk4[nc]===0xFF && blk4[nc+1]===0xFF, "new chain blank FF");

  // 2. round-trip through the directory .sav (3 copies in a 32K image)
  const songs = [ {block: blk4}, null, {block: blk4}, {block: S.expand(blk3)} ];
  const sav = S.buildSav(songs, 32);
  const back = S.readSav(sav);
  chk(back[0] && Buffer.compare(Buffer.from(back[0].block), Buffer.from(blk4))===0 && back[0].checksumOK, "slot0 round-trip + cksum");
  chk(back[1] === null, "slot1 empty");
  chk(back[2] && Buffer.compare(Buffer.from(back[2].block), Buffer.from(blk4))===0, "slot2 round-trip");

  // 3. compression ratio of the expanded song
  const { raw, bytes } = require("./rle.js").pack(blk4);
  chk(!raw && bytes.length < 1200, `expanded song packs to ${bytes.length} B (raw=${raw})`);

  // 4. SRAM-full is refused
  let refused = false;
  try { S.buildSav(new Array(20).fill({block: blk4}), 8); } catch(e){ refused = /FULL/.test(e.message); }
  chk(refused, "SRAM-full refused on 8K");

  // 5. full migration: build an SMDJ3 .sav (demo in slot 0), migrate, read back
  const s3 = new Uint8Array(0x8000);
  s3.set([0x53,0x4D,0x44,0x4A,0x33], 0);                 // "SMDJ3" slot 0
  s3.set(blk3, 16);
  const cs3 = S.checksum(blk3); s3[5] = cs3 & 0xFF; s3[6] = (cs3 >> 8) & 0xFF;
  const migrated = S.migrateSav(s3, 32);
  const mback = S.readSav(migrated);
  chk(mback[0] && mback[0].checksumOK &&
      Buffer.compare(Buffer.from(mback[0].block), Buffer.from(S.expand(blk3))) === 0,
      "SMDJ3 .sav -> migrate -> SMDJ4 read matches expand()");
  chk(S.unwrapSmdj3(smdj) && Buffer.compare(Buffer.from(S.unwrapSmdj3(smdj)), Buffer.from(blk3))===0,
      "unwrapSmdj3 of a .smdj");

  console.log(msg.join("\n"));
  console.log(ok ? "\nALL PASS -- smdj4.js" : "\nFAIL");
  process.exit(ok ? 0 : 1);
}
