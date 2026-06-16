# SMSGGDJ

An LSDJ-inspired music tracker for the **Sega Master System** and **Game
Gear**, written in pure Z80 assembly. Make music on real hardware (via
flashcart) or in an emulator, using just the D-pad and two buttons. Sound is
the SN76489 PSG only — three square channels and noise — plus 4-bit PCM
samples and drawn wavetables via the volume-register DAC trick, a built-in
tempo-synced echo, and Game Gear stereo.

One source tree builds two ROMs:

- **`smsggdj.sms`** — Master System (full screen).
- **`smsggdj.gg`** — Game Gear / *GGDJ* (handheld screen, real stereo).

**Prebuilt ROMs are on the [Releases](../../releases) page** — download
`smsggdj.sms` / `smsggdj.gg`, flash to a cart or open in an emulator, no toolchain
needed.

```
       L I T T L E - S C A L E
```

## Build & run

Needs [WLA-DX](https://github.com/vhelin/wla-dx) (`wla-z80` + `wlalink`) and
Python 3. `make run` launches the bundled Emulicious (needs Java).

```sh
make          # build both: build/smsggdj.sms and build/smsggdj.gg
make run      # build both, launch the SMS ROM
make run-gg   # build both, launch the Game Gear ROM
make clean
```

Both ROMs boot to a blank song, ready to make music. The bundled demo song is
loadable any time from the **PROJECT** screen (DEMO — a two-press confirm).

Drop a ROM on a flashcart (Master Everdrive etc.) or open it in an emulator,
and press play.

## For musicians

- **[MANUAL.md](MANUAL.md)** — the user guide: controls, screens, writing a
  song, instruments, commands, live mode, saving, sync.
- **[tools/patcher.html](tools/patcher.html)** — drop a built ROM + your own
  sounds in a browser, tune them (trim, gain, tanh, fades), audition the exact
  console sound, and download a ROM with your sample bank. No toolchain.
- **[tools/savetool.html](tools/savetool.html)** — unpack songs from a `.sav`,
  assemble a cart image (pick 8/16/32 KB), or click a slot to view a song's
  notes, commands and instruments — in the browser.
- **[tools/palette.html](tools/palette.html)** — drop a built ROM and recolour
  its 8 UI palettes (0–7): pick a background + foreground for each (the pickers
  snap to the 64 hardware colours), then download the patched ROM. No toolchain.
- **[tools/fmpatch.html](tools/fmpatch.html)** — drop a built `.sms` ROM and
  edit its 8 custom FM presets (the YM2413 user patches an FM instrument's
  **PRST** field selects): per-operator MUL/AR/DR/SL/RR/KSL/TL, feedback,
  waveforms and names, **audition** each with a built-in 2-op FM synth, then
  download the patched ROM. No toolchain.
- **[tools/als2smdj.html](tools/als2smdj.html)** — drop an Ableton Live Set
  (`.als`) and get a `.smdj` song: the first 3 MIDI tracks' Session clips become
  phrases/chains on a 16th-note grid (highest note wins, out-of-range folds in,
  note-offs ignored). Load the result with `savetool.html`. No toolchain.

## For developers

- **[CLAUDE.md](CLAUDE.md)** — build system, architecture, and the hard
  invariants (IRQ shadow registers, VDP write spacing, per-region tables).
- **[DESIGN.md](DESIGN.md)** — the design contract: hardware constraints, the
  song data model, the sound engine, the command set, the sample pool, sync,
  and the GGDJ build (§15). Read the relevant section before changing
  behaviour.
- **[SAVEFORMAT.md](SAVEFORMAT.md)** — the SRAM / `.sav` / `.smdj` save format.
- **[CHANGELOG.md](CHANGELOG.md)** — what changed, per version.
- **[HARDWARE.md](HARDWARE.md)** — controller-port and Game Gear EXT pinouts,
  sync cabling, and the EXT paddle-PCB notes.

### Companion projects

- **[smsggdj-link-esp32](https://github.com/little-scale/smsggdj-link-esp32)** —
  an ESP32 (Seeed XIAO ESP32-C3) **Ableton Link** bridge: joins a Link session
  over WiFi and drives SMSGGDJ's `SYNC: IN` so the tracker follows Ableton
  Live's tempo and transport on real hardware. Wiring in HARDWARE.md.

### Source layout

```
src/        Z80 assembly (main, vdp, input, psg, engine, sample, editor)
tools/      Python build tools + the browser apps:
              makefont / maketables / makedemo / makelogo  (build inputs)
              smsggdj_sample.py   WAV/pool -> sample bank
              savetool.py       song/.sav manager (CLI)
              patcher.html      browser sample patcher
              savetool.html     browser song/save manager
              palette.html      browser UI-palette recolourer
              fmpatch.html      browser FM custom-preset editor
samples/    sample sources; samples/pool.bin (if present) is the baked bank
art/        the logo art
```

## Sample bank

The committed `samples/pool.bin` is the production sample bank (tuned in the
patcher) and is baked into every build. To build from raw recordings instead,
delete `samples/pool.bin` and put WAVs in `samples/` — `make` converts them.
The pool is identical in both flavours, so one bank serves `.sms` and `.gg`.

## License

MIT — see [LICENSE](LICENSE). Use it, fork it, learn from it.

The bundled Emulicious emulator (`tools/emulicious/`, not in this repo) has its
own license.

---

Made by **little-scale**.
