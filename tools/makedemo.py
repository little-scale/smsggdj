#!/usr/bin/env python3
"""Compose the SMSDJ demo song as a complete 5,248-byte song block
(the wave_ram..grooves layout from SAVEFORMAT.md). song_init copies
it wholesale, so this file IS the demo song - edit and rebuild.

The tune: C major, 125 BPM at PAL (groove 6,6), fourteen song
rows (~54 s loop) touring the engine: the original lead motif
with vibrato, sampled drums, table arps, a swing section (G +
W shuffle), slides and falls (L, P, D delays), pitched periodic
noise bass with N overrides, an echo-table melody (C chord, E
override, M tremolo), a wavetable organ pad alternating notes
across repeats (I), GG pan ping-pong on the hats (O), and retrig
fills (R) - with K cuts throughout.

Encodings (engine.asm):
  note byte   = note-table index + 1, 0 = rest; index 0 = A-2
  instrument  = type,vol,env,len,noise/wave,swp,vib,trm,tsp,tbl,tbs
  env         = direction nibble (0 off, 1 down, 2 up) | speed
  chain step  = phrase #, signed transpose
"""
import math
import struct
import sys

# ---- sizes (must match the RAMSECTION) ----
N_PHR, N_CHN, N_ROWS, N_INS, N_TBL, N_GRV = 32, 32, 128, 16, 16, 16

# ---- commands ----
K, H, A_, C_, E_, F_, G_, N_, P_, T_, V_, W_, M_, D_, L_, R_, O_, I_ = range(1, 19)

NAMES = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5,
         "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def n(name):
    """'A2' -> note byte (A-2 = lowest = 1)."""
    pitch, octave = name[:-1], int(name[-1])
    midi = 12 * (octave + 1) + NAMES[pitch]
    byte = midi - 44                       # index 0 = MIDI 45 (A-2)
    assert 1 <= byte <= 63, name
    return byte


REST = (0, 0xFF, 0, 0)


def ph(*steps):
    """Build one 16-step phrase. Each step: None, note-name string,
    (name, instr), or (name, instr, cmd, param). A bare string uses
    the phrase's default instrument set by the first tuple seen."""
    out, default_i = [], 0
    for s in steps:
        if s is None:
            out.append(REST)
        elif isinstance(s, str):
            out.append((n(s), default_i, 0, 0))
        else:
            name, ins = s[0], s[1]
            cmd, par = (s[2], s[3]) if len(s) > 2 else (0, 0)
            default_i = ins
            note = n(name) if name else 0
            out.append((note, ins if name else 0xFF, cmd, par))
    assert len(out) == 16, len(out)
    return out


# =====================================================================
# instruments
# =====================================================================
LEAD, PLUCK, BASS, HAT, SNARE, KICK, WBASS, STAB, OHAT, \
    PBASS, WPAD, ECHO = range(12)

INSTRUMENTS = [
    # type vol  env   len noise  swp vib  trm tsp  tbl   tbs
    (0, 0x0F, 0x14, 0,  0x00,  0, 0x33, 0,  0,  0xFF, 1),   # LEAD: vib
    (0, 0x0B, 0x13, 0,  0x00,  0, 0,    0,  0,  0x00, 2),   # PLUCK: arp tbl
    (0, 0x0F, 0x15, 0,  0x00,  0, 0,    0,  0,  0xFF, 1),   # BASS
    (1, 0x0A, 0x12, 2,  0x04,  0, 0,    0,  0,  0xFF, 1),   # HAT w/512
    (1, 0x0F, 0x14, 8,  0x05,  0, 0,    0,  0,  0xFF, 1),   # SNARE w/1024
    (2, 0x0F, 0x00, 0,  0x00,  0, 0,    0,  0,  0xFF, 1),   # KICK (sample 0)
    (3, 0x0F, 0x00, 0,  0x03,  0, 0,    0,  0,  0xFF, 1),   # WBASS (square)
    (0, 0x0C, 0x14, 0,  0x00,  0, 0,    0,  0,  0xFF, 1),   # STAB
    (1, 0x09, 0x13, 6,  0x04,  0, 0,    0,  0,  0xFF, 1),   # OHAT
    (1, 0x0F, 0x15, 0,  0x03,  0, 0,    0,  0,  0xFF, 1),   # PBASS: pitched
    (3, 0x0F, 0x00, 0,  0x06,  0, 0,    0,  0,  0xFF, 1),   # WPAD (organ)
    (0, 0x0D, 0x00, 0,  0x00,  0, 0,    0,  0,  0x01, 3),   # ECHO: tbl 1
]

# =====================================================================
# phrases
# =====================================================================
S0 = n("A2")  # sample 0 = kick lives on the lowest note

PHRASES = [
    # 0 bassA: octave-pump in C
    ph(("C3", BASS), None, "C4", None, "C3", None, "C4", None,
       "C3", None, "C4", None, "G3", None, "B3", None),
    # 1 bassB: turnaround home
    ph(("C3", BASS), None, "C4", None, "A3", None, "C4", None,
       "G3", None, "G3", None, "E3", None, "D3", None),
    # 2 leadA: the original demo motif
    ph(("A4", LEAD), None, "C5", "E5", "A5", None, "G5", "E5",
       None, "C5", "D5", None, "E5", None, "B4", ("", LEAD, K, 3)),
    # 3 leadB: bouncing answer
    ph(("C5", LEAD), None, "E5", None, "G5", None, "E5", None,
       "D5", None, "C5", None, "G4", None, None, ("", LEAD, K, 3)),
    # 4 leadC: long singing notes over the progression
    ph(("E5", LEAD, V_, 0x45), None, None, None, None, None, "D5", None,
       "C5", None, "D5", None, "E5", None, None, None),
    # 5 pluck: skipping broken chords
    ph(("C4", STAB), "E4", "G4", "C5", "G4", "E4", "C4", "E4",
       "G4", "C5", "G4", "E4", "C4", None, "D4", None),
    # 6 stabs: offbeat major-arp chords (PLUCK carries the table)
    ph(None, None, ("C4", PLUCK), None, None, None, "C4", None,
       None, None, "C4", None, None, "C4", None, None),
    # 7 hatsA: straight 8ths
    ph(("A4", HAT), None, "A4", None, "A4", None, "A4", None,
       "A4", None, "A4", None, "A4", None, "A4", None),
    # 8 drumsA: hats + backbeat snare, open hat at the end
    ph(("A4", HAT), None, "A4", None, ("A4", SNARE), None, ("A4", HAT), None,
       "A4", None, "A4", None, ("A4", SNARE), None, ("A4", HAT), ("A4", OHAT)),
    # 9 drumsB: bar-end snare fill
    ph(("A4", HAT), None, "A4", None, ("A4", SNARE), None, ("A4", HAT), None,
       "A4", None, "A4", None, ("A4", SNARE), ("A4", SNARE),
       ("A4", SNARE, R_, 0x02), ("A4", SNARE, R_, 0x01)),
    # 10 hatsB: sparse quarters
    ph(("A4", HAT), None, None, None, "A4", None, None, None,
       "A4", None, None, None, "A4", None, None, None),
    # 11 fill: rising retrigged snare build
    ph(("A4", HAT), None, "A4", None, ("A4", SNARE), None, ("A4", HAT), None,
       ("A4", SNARE), None, ("A4", SNARE), None,
       ("A4", SNARE, R_, 0x02), None, ("A4", SNARE, R_, 0x01), None),
    # 12 kickA: four-ish on the floor (sampled)
    ph(("A2", KICK), None, None, None, None, None, None, None,
       "A2", None, None, None, None, None, None, None),
    # 13 kickB: syncopated
    ph(("A2", KICK), None, None, None, None, None, None, None,
       "A2", None, None, None, None, None, "A2", None),
    # 14 wavA: square-wave bass, walking up
    ph(("C3", WBASS), None, None, None, "E3", None, None, None,
       "G3", None, None, None, "A3", None, "G3", None),
    # 15 wavB: and home again
    ph(("F3", WBASS), None, None, None, "E3", None, None, None,
       "D3", None, "C3", None, None, None, None, ("", WBASS, K, 4)),
    # 16 pluckHi: sparkling top line over the breakdown
    ph(("C5", STAB), "E5", "G5", "C6", "G5", "E5", "C5", "E5",
       "G5", "C6", "G5", "E5", "C5", None, None, None),
    # 17 slides: L portamento lines
    ph(("C5", LEAD), None, None, None, ("G5", LEAD, L_, 0x20), None,
       None, None, ("E5", LEAD, L_, 0x18), None, ("C5", LEAD, L_, 0x18),
       None, ("D5", LEAD), None, ("G4", LEAD, L_, 0x28), None),
    # 18 falls: D delays, an E envelope override, P pitch falls
    ph(("E5", LEAD, D_, 3), None, ("C5", LEAD, D_, 3), None,
       ("G4", LEAD, P_, 0x06), None, None, None,
       ("A4", LEAD, E_, 0xF2), None, ("E5", LEAD, D_, 2), None,
       ("G5", LEAD, P_, 0x10), None, None, ("", LEAD, K, 2)),
    # 19 swing: G flips to groove 1, W clips a row, G back at exit
    ph(("C4", STAB, G_, 0x01), ("E4", STAB), ("G4", STAB), ("C5", STAB),
       ("E5", STAB, W_, 3), None, ("C5", STAB), ("G4", STAB),
       ("E4", STAB), ("G4", STAB), ("C5", STAB), ("E5", STAB),
       ("G5", STAB), None, ("C5", STAB), ("", STAB, G_, 0x00)),
    # 20 noise bass: pitched periodic, N overrides mid-line
    ph(("A2", PBASS), None, ("A2", PBASS), None, ("C3", PBASS), None,
       ("A2", PBASS), None, ("E3", PBASS), None,
       ("D3", PBASS, N_, 0x04), None, ("A2", PBASS, N_, 0x03), None,
       ("E3", PBASS), None),
    # 21 echo melody: table-1 echoes, one C chord, M tremolo
    ph(("C5", ECHO), None, None, None, ("G4", ECHO), None, None, None,
       ("A4", ECHO, C_, 0x37), None, None, None,
       ("E5", ECHO, M_, 0x46), None, None, None),
    # 22 organ pad: I alternates the chord tone across repeats
    ph(("C3", WPAD, I_, 0x20), None, ("E3", WPAD, I_, 0x21), None,
       None, None, None, None, ("G3", WPAD), None, None, None,
       ("C3", WPAD, I_, 0x21), ("C4", WPAD, I_, 0x20), None, None),
    # 23 fill: extra snares only on even repeats (I), retrig tail
    ph(("A4", HAT), None, ("A4", HAT), None, ("A4", SNARE), None,
       ("A4", HAT), None, ("A4", HAT), ("A4", SNARE, I_, 0x21),
       ("A4", HAT), ("A4", SNARE, I_, 0x21), ("A4", SNARE),
       ("A4", SNARE, I_, 0x21), ("A4", SNARE, R_, 0x02),
       ("A4", SNARE, I_, 0x21)),
    # 24 pan hats: O ping-pong (audible on GG, harmless on SMS)
    ph(("A4", HAT, O_, 0x10), None, ("A4", HAT, O_, 0x01), None,
       ("A4", HAT, O_, 0x10), None, ("A4", HAT, O_, 0x01), None,
       ("A4", HAT, O_, 0x10), None, ("A4", HAT, O_, 0x01), None,
       ("A4", OHAT, O_, 0x11), None, ("A4", HAT), None),
]

# =====================================================================
# chains: lists of (phrase, transpose); C F G Am = 0 +5 +7 -3
# =====================================================================
CHAINS = [
    [(0, 0), (1, 0)],          # 0 bass main
    [(0, 0), (0, 5)],          # 1 bass C F
    [(0, 7), (1, 0)],          # 2 bass G C
    [(2, 0), (3, 0)],          # 3 lead main
    [(4, 0), (4, 5)],          # 4 lead C F
    [(4, 7), (3, 0)],          # 5 lead G C
    [(6, 0), (6, 5)],          # 6 stabs C F
    [(6, 7), (6, 0)],          # 7 stabs G C
    [(7, 0), (7, 0)],          # 8 hats intro
    [(8, 0), (9, 0)],          # 9 drums main
    [(8, 0), (11, 0)],         # 10 drums + build fill
    [(12, 0), (13, 0)],        # 11 kick main
    [(14, 0), (15, 0)],        # 12 wav breakdown
    [(10, 0), (10, 0)],        # 13 hats sparse
    [(16, 0), (16, 5)],        # 14 pluck high
    [(31, 0), (31, 0)],        # 15 rest (phrase 31 stays empty)
    [(17, 0), (18, 0)],        # 16 slides + falls
    [(19, 0), (19, 0)],        # 17 swing
    [(20, 0), (20, 0)],        # 18 pitched-noise bass
    [(21, 0), (21, 0)],        # 19 echo melody
    [(22, 0), (22, 0)],        # 20 organ pad (repeat for I)
    [(5, 0), (5, 0)],          # 21 pluck main
    [(24, 0), (24, 0)],        # 22 pan hats
]

# =====================================================================
# song rows: (T1, T2, T3, NO) chain numbers, None = empty
# =====================================================================
# every column spans rows 0-13 (15 = rest chain) so the four
# loops stay aligned; an empty cell would loop its column early
SONG = [
    (15,   0,    15,   22),    # intro: bass + pan-ping hats (O)
    (15,   0,    11,   9),     # kick and snare join
    (3,    0,    11,   9),     # the lead motif (vibrato)
    (3,    0,    11,   10),    # ... I-gated fill on the repeat
    (4,    1,    6,    9),     # C F (table-arp stabs answer)
    (5,    2,    7,    10),    # G C, build
    (16,   0,    11,   9),     # slides, delays and falls (L D P)
    (17,   0,    11,   9),     # swing section (G + W shuffle)
    (19,   18,   15,   13),    # echoes over pitched-noise bass
    (19,   18,   15,   9),     # ... drums join (T3 stays free)
    (21,   0,    20,   13),    # organ pad, I alternating tones
    (21,   0,    20,   9),     # ... pad repeat flips the I gate
    (3,    0,    11,   9),     # recap
    (4,    1,    6,    10),    # final turn, loops to the top
]

# =====================================================================
# emit the block
# =====================================================================
def waves():
    """8 boot waves = the 8 stamp presets, one per slot."""
    def pack(vals):
        return bytes(0xD0 | (15 - v) for v in vals)
    def tri(i):
        p = (i % 32) / 32.0
        if p < 0.25: return p * 4
        if p < 0.75: return 2 - p * 4
        return p * 4 - 4
    sine = [round((math.sin(2 * math.pi * i / 32) * .5 + .5) * 15)
            for i in range(32)]
    trit = [round(tri((i + 8) % 32) * 7.5 + 7.5) for i in range(32)]
    saw = [round(i * 15 / 31.0) for i in range(32)]
    sqr = [15] * 16 + [0] * 16
    p25 = [15] * 8 + [0] * 24
    p12 = [15] * 4 + [0] * 28
    org = []
    for i in range(32):
        th = 2 * math.pi * i / 32
        v = math.sin(th) + math.sin(3 * th) / 3 + math.sin(5 * th) / 5
        org.append(max(0, min(15, round((v / 1.4 * .5 + .5) * 15))))
    rseed, rnd = 0xACE1, []
    for i in range(32):
        rseed = (rseed * 0x6255 + 0x3217) & 0xFFFF
        rnd.append(rseed >> 12)
    return b"".join(pack(w) for w in
                    (sine, trit, saw, sqr, p25, p12, org, rnd))


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: makedemo.py OUT.BIN")
    blk = bytearray()
    blk += waves()                                       # 256

    for p in PHRASES:                                    # 2048
        for note, ins, cmd, par in p:
            blk += bytes([note, ins, cmd, par])
    blk += bytes([0, 0xFF, 0, 0]) * 16 * (N_PHR - len(PHRASES))

    for c in CHAINS:                                     # 1024
        for phr, tsp in c:
            blk += bytes([phr, tsp & 0xFF])
        blk += bytes([0xFF, 0]) * (16 - len(c))
    blk += bytes([0xFF, 0]) * 16 * (N_CHN - len(CHAINS))

    for row in SONG:                                     # 512
        blk += bytes(0xFF if c is None else c for c in row)
    blk += bytes([0xFF] * 4) * (N_ROWS - len(SONG))

    for ins in INSTRUMENTS:                              # 256
        blk += bytes(b & 0xFF for b in ins) + bytes(16 - len(ins))
    # unedited instruments: audible defaults (vol F, env off)
    blk += bytes([0, 0x0F, 0, 0, 0, 0, 0, 0, 0, 0xFF, 1] + [0] * 5) \
        * (N_INS - len(INSTRUMENTS))

    TABLES = {                                           # 1024
        0: [(0xFF, 0, 0, 0), (0xFF, 4, 0, 0), (0xFF, 7, H, 0)],
        1: [(0x0F, 0, 0, 0), (0x09, 0, 0, 0),            # echo
            (0x05, 0, 0, 0), (0x02, 0, H, 3)],
    }
    empty_row = (0xFF, 0, 0, 0)
    for ti in range(N_TBL):
        rows = TABLES.get(ti, [])
        for r in range(16):
            blk += bytes(rows[r] if r < len(rows) else empty_row)

    blk += bytes([6, 6] + [0] * 14)                      # 256
    blk += bytes(16) * (N_GRV - 1)

    assert len(blk) == 5376, len(blk)
    with open(sys.argv[1], "wb") as f:
        f.write(blk)
    print("demo song: %d phrases, %d chains, %d rows -> %s (%d bytes)"
          % (len(PHRASES), len(CHAINS), len(SONG), sys.argv[1], len(blk)))


if __name__ == "__main__":
    main()
