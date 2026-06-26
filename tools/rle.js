// rle.js -- SMSGGDJ RLE codec (the canonical decoder, shared by savetool.html,
// the migration tool, and matched by the Z80 cart codec). See COMPRESSION.md.
//
// 4-byte unit (one phrase/table row). PackBits-style stream:
//   control byte c:
//     bit7 = 0  -> literal run : copy next (c & 0x7F)+1 units verbatim  (1..128)
//     bit7 = 1  -> repeat run  : next 1 unit, output (c & 0x7F)+2 times  (2..129)
// Pair with a store-raw fallback so stored size is always min(rle, raw).
//
// Usable in the browser (window.RLE) or node (module.exports). Pure Uint8Array.

(function (root) {
  "use strict";
  const UNIT = 4;

  function unitsEqual(a, i, j) {
    return a[i] === a[j] && a[i+1] === a[j+1] &&
           a[i+2] === a[j+2] && a[i+3] === a[j+3];
  }

  // data: Uint8Array, length a multiple of UNIT. -> Uint8Array stream.
  function compress(data) {
    const n = (data.length / UNIT) | 0;
    const out = [];
    let i = 0;
    while (i < n) {
      let run = 1;
      while (i + run < n && run < 129 && unitsEqual(data, (i+run)*UNIT, i*UNIT)) run++;
      if (run >= 2) {                         // repeat run
        out.push(0x80 | (run - 2));
        const b = i * UNIT;
        out.push(data[b], data[b+1], data[b+2], data[b+3]);
        i += run;
        continue;
      }
      let j = i;                              // literal run up to the next 2+ run
      while (j < n && (j - i) < 128 &&
             !(j + 1 < n && unitsEqual(data, (j+1)*UNIT, j*UNIT))) j++;
      if (j === i) j = i + 1;
      out.push((j - i) - 1);
      for (let k = i; k < j; k++) {
        const b = k * UNIT;
        out.push(data[b], data[b+1], data[b+2], data[b+3]);
      }
      i = j;
    }
    return Uint8Array.from(out);
  }

  // stream: Uint8Array. -> Uint8Array of decoded units.
  function decompress(stream) {
    const out = [];
    let i = 0;
    while (i < stream.length) {
      const c = stream[i++];
      if (c & 0x80) {
        const cnt = (c & 0x7F) + 2;
        const u = stream.slice(i, i + UNIT); i += UNIT;
        for (let r = 0; r < cnt; r++) out.push(u[0], u[1], u[2], u[3]);
      } else {
        const cnt = ((c & 0x7F) + 1) * UNIT;
        for (let k = 0; k < cnt; k++) out.push(stream[i++]);
      }
    }
    return Uint8Array.from(out);
  }

  // Convenience: pack with store-raw fallback. -> {raw:bool, bytes:Uint8Array}.
  function pack(block) {
    const rle = compress(block);
    if (rle.length >= block.length) return { raw: true, bytes: block };
    return { raw: false, bytes: rle };
  }

  const api = { UNIT, compress, decompress, pack };
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.RLE = api;
})(typeof self !== "undefined" ? self : this);
