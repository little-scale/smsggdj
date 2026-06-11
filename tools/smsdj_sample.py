#!/usr/bin/env python3
"""SMSDJ sample converter (design doc 10.5).

Converts WAV files into the SMSDJ 4-bit PCM pool. The SN76489's
volume register is a LOGARITHMIC DAC (2 dB per step, datasheet):
level n outputs amplitude 10^(-n/10), level 15 is 0. Linear PCM is
mapped to the nearest log level with 1-D error-diffusion dithering —
the correction step almost no commercial SMS game bothered with.

usage:
  smsdj_sample.py in1.wav [in2.wav ...] -o pool.bin [options]
    --asm pool.inc    WLA-DX include with the pool index
    --rate HZ         target rate (default 7813 = PAL line/2 cadence)
    --gate N          silence-gate threshold, levels (default 1)
    --gain X          post-normalize gain with hard clipping
                      (2-4 = louder/denser, 99 ~= 1-bit loudness)
    --no-dither       plain nearest-level quantization
    --no-norm         skip per-file normalization
    --preview         write NAME.preview.wav rendered through the
                      exact level table (what the console will play)
"""
import math
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
    preview = opt("--preview", False, has_val=False)

    # ---- the pool contract (ROM banks 2-7, slot 2 at $8000) ----
    # bank 2, $8000: "SMPL", version, count, rate lo/hi, then
    # MAX_SAMPLES dir entries x 10: bank, offset lo/hi ($8000-
    # based), length lo/hi, name[5]. Samples never cross a bank.
    # The browser patcher rewrites this region in place.
    MAX_SAMPLES = 32
    POOL_BANKS = 6             # banks 2-7 = 96 KB
    BANK = 16384
    DIR_END = 8 + MAX_SAMPLES * 10

    converted = []
    for path in args:
        if path.endswith(".preview.wav"):
            continue           # our own audition renders
        mono, src = load_wav(path)
        mono = resample(mono, src, rate)
        if norm and mono:
            peak = max(0.0001, max(abs(s) for s in mono))
            mono = [s / peak for s in mono]
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
        name = path.rsplit("/", 1)[-1].rsplit(".", 1)[0]
        converted.append((name, packed))
        secs = len(codes) / float(rate)
        print("%-12s %6d bytes  %.2fs" % (name, len(packed), secs))
        if preview:
            pv = wave.open(name + ".preview.wav", "wb")
            pv.setnchannels(1)
            pv.setsampwidth(1)
            pv.setframerate(rate)
            pv.writeframes(bytes(
                int(LEVELS[c] * 255) for c in codes))
            pv.close()

    if len(converted) > MAX_SAMPLES:
        sys.exit("too many samples (max %d)" % MAX_SAMPLES)

    # first-fit placement, no bank crossing
    pool = bytearray([0xFF]) * (POOL_BANKS * BANK)
    free = [DIR_END] + [0] * (POOL_BANKS - 1)   # next free per bank
    index = []
    for name, packed in converted:
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
    print("pool: %d samples, %d bytes used of %d (%.1f%%) -> %s" %
          (len(index), used, POOL_BANKS * BANK - DIR_END,
           100.0 * used / (POOL_BANKS * BANK - DIR_END), out_bin))

    if out_asm:
        lines = ["; generated by tools/smsdj_sample.py - do not edit",
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
