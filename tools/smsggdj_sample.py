#!/usr/bin/env python3
"""SMSGGDJ sample converter (design doc 10.5).

Converts WAV files into the SMSGGDJ 4-bit PCM pool. The SN76489's
volume register is a LOGARITHMIC DAC (2 dB per step, datasheet):
level n outputs amplitude 10^(-n/10), level 15 is 0. Linear PCM is
mapped to the nearest log level with 1-D error-diffusion dithering —
the correction step almost no commercial SMS game bothered with.

usage:
  smsggdj_sample.py in1.wav [in2.wav ...] -o pool.bin [options]
    --asm pool.inc    WLA-DX include with the pool index
    --rate HZ         target rate (default 7813 = PAL line/2 cadence)
    --gate N          silence-gate threshold, levels (default 1)
    --gain X          post-normalize gain with hard clipping
                      (2-4 = louder/denser, 99 ~= 1-bit loudness)
    --no-dither       plain nearest-level quantization
    --no-norm         skip per-file normalization
    --no-trim         keep trailing silence (default: trim it)
    --trim-db DB      trailing-silence floor in dBFS (default -48);
                      strips the silent tail/pad to reclaim pool space.
                      The feeder hard-mutes on end, so the cut is clickless.
    --preview         write NAME.preview.wav rendered through the
                      exact level table (what the console will play)
    --pool-in POOL.bin  skip conversion: bake a pre-built 96 KB
                      pool image straight in (e.g. exported from
                      tools/patcher.html); emits the same pool.inc
"""
import math
import os
import struct
import sys
import wave

# unipolar DAC levels: attenuation 0..14 = 10^(-n/10), 15 = off
LEVELS = [10 ** (-n / 10.0) for n in range(15)] + [0.0]


def load_wav(path):
    w = wave.open(path, "rb")
    ch, width, rate, n = (w.getnchannels(), w.getsampwidth(),
                          w.getframerate(), w.getnframes())
    raw = w.readframes(n)
    w.close()
    if width == 2:
        data = struct.unpack("<%dh" % (n * ch), raw)
        scale = 32768.0
    elif width == 1:
        data = [b - 128 for b in raw]
        scale = 128.0
    else:
        sys.exit("%s: only 8/16-bit WAV supported" % path)
    # mix to mono
    mono = [sum(data[i * ch:(i + 1) * ch]) / (ch * scale)
            for i in range(n)]
    return mono, rate


def resample(samples, src, dst):
    if src == dst or not samples:
        return samples
    out, step = [], src / float(dst)
    pos, last = 0.0, len(samples) - 1
    while pos < last:
        i = int(pos)
        f = pos - i
        out.append(samples[i] * (1 - f) + samples[i + 1] * f)
        pos += step
    return out


def convert(samples, dither=True, gate=1):
    """signed [-1,1] -> 4-bit attenuation codes, log-mapped."""
    out, err = [], 0.0
    for s in samples:
        u = (s + 1.0) / 2.0          # unipolar DC range
        if dither:
            u += err
        best = min(range(16), key=lambda n: abs(LEVELS[n] - u))
        if dither:
            err = u - LEVELS[best]
            err = max(-0.5, min(0.5, err))
        out.append(best)
    if gate:
        # mute sub-noise-floor passages (mid-level wobble)
        mid = 7
        for i, v in enumerate(out):
            if abs(LEVELS[v] - 0.5) < (LEVELS[mid] - LEVELS[mid + gate]):
                out[i] = mid
    return out


def trim_tail(samples, thresh):
    """Drop the trailing run below `thresh` (the digital-silence pad / decayed
    tail), keeping the attack and body. Leading silence is left intact so the
    note's onset timing is unchanged (cf. genmddj makesamples.py). The feeder's
    sf_end hard-mutes T3 ($DF) the instant the data ends, so no rest terminator
    is needed for a clickless stop."""
    i = len(samples)
    while i > 0 and abs(samples[i - 1]) < thresh:
        i -= 1
    return samples[:i] if i else samples[:1]


def main():
    args = sys.argv[1:]
    if not args or "-o" not in args:
        sys.exit(__doc__)

    def opt(flag, default=None, has_val=True):
        if flag in args:
            i = args.index(flag)
            args.pop(i)
            return args.pop(i) if has_val else True
        return default

    out_bin = opt("-o")
    out_asm = opt("--asm")
    rate = int(opt("--rate", 7813))
    gain = float(opt("--gain", 1.0))
    gate = int(opt("--gate", 1))
    dither = not opt("--no-dither", False, has_val=False)
    norm = not opt("--no-norm", False, has_val=False)
    trim = not opt("--no-trim", False, has_val=False)
    trim_db = float(opt("--trim-db", -48.0))   # trailing-silence floor
    trim_th = 10.0 ** (trim_db / 20.0)
    preview = opt("--preview", False, has_val=False)
    pool_in = opt("--pool-in")
    kits_dir = opt("--kits")   # build 4 kits x 8 from a folder of subfolders

    if pool_in:
        BANK, POOL_BANKS = 16384, 6
        data = open(pool_in, "rb").read()
        if len(data) != POOL_BANKS * BANK:
            sys.exit("%s: pool must be %d bytes" % (pool_in, POOL_BANKS * BANK))
        if data[:4] != b"SMPL":
            sys.exit(pool_in + ": missing SMPL header")
        open(out_bin, "wb").write(data)
        print("pool passthrough: %s -> %s (%d samples)"
              % (pool_in, out_bin, data[5]))
        if out_asm:
            lines = ["; generated by tools/smsggdj_sample.py - do not edit",
                     ".DEFINE SAMPLE_RATE %d" % (data[6] | data[7] << 8)]
            for b in range(POOL_BANKS):
                lines += [".BANK %d SLOT 2" % (2 + b), ".ORGA $8000",
                          '.SECTION "PoolBank%d" FORCE' % (2 + b),
                          '  .INCBIN "pool.bin" SKIP %d READ %d'
                          % (b * BANK, BANK), ".ENDS"]
            open(out_asm, "w").write("\n".join(lines) + "\n")
            print("index -> " + out_asm)
        return

    # ---- the pool contract (ROM banks 2-7, slot 2 at $8000) ----
    # bank 2, $8000: "SMPL", version, count, rate lo/hi, then
    # MAX_SAMPLES dir entries x 10: bank, offset lo/hi ($8000-
    # based), length lo/hi, name[5]. Samples never cross a bank.
    # The browser patcher rewrites this region in place.
    MAX_SAMPLES = 64
    POOL_BANKS = 6             # banks 2-7 = 96 KB
    BANK = 16384
    DIR_END = 8 + MAX_SAMPLES * 10

    # --kits: lay the pool out as KITS x PER_KIT fixed slots so the engine can
    # index sample = kit*PER_KIT + (note mod PER_KIT). Each kit owns its block
    # even if short (missing slots stay empty -> silence). Kits and the WAVs
    # inside them are taken in alphanumeric order from the folder tree.
    KITS, PER_KIT = 8, 8
    if kits_dir:
        subdirs = sorted(d for d in os.listdir(kits_dir)
                         if not d.startswith(".")
                         and os.path.isdir(os.path.join(kits_dir, d)))
        slot_paths = []                    # KITS*PER_KIT entries: path or None
        for ki in range(KITS):
            wavs = []
            if ki < len(subdirs):
                kd = os.path.join(kits_dir, subdirs[ki])
                wavs = sorted(os.path.join(kd, f) for f in os.listdir(kd)
                              if f.lower().endswith(".wav")
                              and not f.startswith(".")
                              and not f.lower().endswith(".preview.wav"))
            print("kit %d: %s (%d sample%s)"
                  % (ki, subdirs[ki] if ki < len(subdirs) else "(none)",
                     len(wavs), "" if len(wavs) == 1 else "s"))
            for si in range(PER_KIT):
                slot_paths.append(wavs[si] if si < len(wavs) else None)
    else:
        slot_paths = [p for p in args if not p.endswith(".preview.wav")]

    slots = []                             # (name, packed) or None per slot
    for path in slot_paths:
        if path is None:
            slots.append(None)
            continue
        mono, src = load_wav(path)
        mono = resample(mono, src, rate)
        if norm and mono:
            peak = max(0.0001, max(abs(s) for s in mono))
            mono = [s / peak for s in mono]
        full = len(mono)
        if trim and mono:
            mono = trim_tail(mono, trim_th)   # on the clean (pre-gain) signal
        cut = full - len(mono)
        if gain != 1.0:
            mono = [max(-1.0, min(1.0, s * gain)) for s in mono]
        codes = convert(mono, dither, gate)
        if len(codes) & 1:
            codes.append(15)
        packed = bytes((codes[i] << 4) | codes[i + 1]
                       for i in range(0, len(codes), 2))
        if len(packed) > BANK - DIR_END:
            sys.exit("%s: %d bytes - samples may not exceed one "
                     "bank (%d)" % (path, len(packed), BANK - DIR_END))
        base = path.rsplit("/", 1)[-1].rsplit(".", 1)[0]
        name = base.split(" ", 1)[1] if (base[:1].isdigit() and " " in base) else base
        slots.append((name, packed))
        secs = len(codes) / float(rate)
        tag = "  -%d trimmed" % cut if cut else ""
        print("  %-12s %6d bytes  %.2fs%s" % (name, len(packed), secs, tag))
        if preview:
            pv = wave.open(name + ".preview.wav", "wb")
            pv.setnchannels(1)
            pv.setsampwidth(1)
            pv.setframerate(rate)
            pv.writeframes(bytes(
                int(LEVELS[c] * 255) for c in codes))
            pv.close()

    if len(slots) > MAX_SAMPLES:
        sys.exit("too many sample slots (max %d)" % MAX_SAMPLES)

    # first-fit placement, no bank crossing; empty slots get a length-0 entry
    pool = bytearray([0xFF]) * (POOL_BANKS * BANK)
    free = [DIR_END] + [0] * (POOL_BANKS - 1)   # next free per bank
    index = []
    for slot in slots:
        if slot is None:
            index.append(("", 0, 0, 0))         # empty slot
            continue
        name, packed = slot
        for b in range(POOL_BANKS):
            if free[b] + len(packed) <= BANK:
                index.append((name, 2 + b, 0x8000 + free[b],
                              len(packed)))
                pool[b * BANK + free[b]:
                     b * BANK + free[b] + len(packed)] = packed
                free[b] += len(packed)
                break
        else:
            sys.exit("pool full placing %s" % name)

    hdr = b"SMPL" + bytes([1, len(index)]) + struct.pack("<H", rate)
    for name, bank, off, ln in index:
        nm = name[:5].upper().ljust(5).encode("ascii", "replace")
        hdr += bytes([bank]) + struct.pack("<HH", off, ln) + nm
    hdr += bytes(10) * (MAX_SAMPLES - len(index))
    pool[:len(hdr)] = hdr

    open(out_bin, "wb").write(pool)
    used = sum(free) - DIR_END
    nreal = sum(1 for s in slots if s is not None)
    print("pool: %d samples in %d slots, %d bytes used of %d (%.1f%%) -> %s" %
          (nreal, len(index), used, POOL_BANKS * BANK - DIR_END,
           100.0 * used / (POOL_BANKS * BANK - DIR_END), out_bin))

    if out_asm:
        lines = ["; generated by tools/smsggdj_sample.py - do not edit",
                 ".DEFINE SAMPLE_RATE %d" % rate]
        for b in range(POOL_BANKS):
            lines += [".BANK %d SLOT 2" % (2 + b),
                      ".ORGA $8000",
                      '.SECTION "PoolBank%d" FORCE' % (2 + b),
                      '  .INCBIN "pool.bin" SKIP %d READ %d'
                      % (b * BANK, BANK),
                      ".ENDS"]
        open(out_asm, "w").write("\n".join(lines) + "\n")
        print("index -> " + out_asm)


if __name__ == "__main__":
    main()
