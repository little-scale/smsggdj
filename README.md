# SMSGGDJ

An LSDJ-inspired music tracker for the **Sega Master System** and **Game
Gear**, written in pure Z80 assembly. Make music on real hardware (via
flashcart) or in an emulator, using just the D-pad and two buttons. Sound is
the SN76489 PSG only — three square channels and noise — plus 4-bit PCM
samples and drawn wavetables via the volume-register DAC trick, and Game
Gear stereo.

One source tree builds two ROMs:

- **`smsdj.sms`** — Master System (full screen).
- **`smsdj.gg`** — Game Gear / *GGDJ* (handheld screen, real stereo).

```
       L I T T L E - S C A L E
```

## Build & run

Needs [WLA-DX](https://github.com/vhelin/wla-dx) (`wla-z80` + `wlalink`) and
Python 3. `make run` launches the bundled Emulicious (needs Java).

```sh
make          # build both: build/smsdj.sms and build/smsdj.gg
make run      # build both, launch the SMS ROM
make run-gg   # build both, launch the Game Gear ROM
make demo     # build the self-playing demo ROMs (-demo.sms / -demo.gg)
make run-demo / run-demo-gg   # build + launch a demo ROM
make clean
```

The normal ROMs boot to a blank song, ready to edit. The **demo** ROMs load
the demo song and auto-play it from boot — a self-running "attract" build.

Drop a ROM on a flashcart (Master Everdrive etc.) or open it in an emulator.
On boot it loads a demo song — press play and you're off.

## For musicians

- **[MANUAL.md](MANUAL.md)** — the user guide: controls, screens, writing a
  song, instruments, commands, live mode, saving, sync.
- **[tools/patcher.html](tools/patcher.html)** — drop a built ROM + your own
  sounds in a browser, tune them (trim, gain, tanh, fades), audition the exact
  console sound, and download a ROM with your sample bank. No toolchain.
- **[tools/savetool.html](tools/savetool.html)** — unpack songs from a `.sav`,
  or assemble a cart image from song files, in the browser.

## For developers

- **[CLAUDE.md](CLAUDE.md)** — build system, architecture, and the hard
  invariants (IRQ shadow registers, VDP write spacing, per-region tables).
- **[DESIGN.md](DESIGN.md)** — the design contract: hardware constraints, the
  song data model, the sound engine, the command set, the sample pool, sync,
  and the GGDJ build (§15). Read the relevant section before changing
  behaviour.
- **[SAVEFORMAT.md](SAVEFORMAT.md)** — the SRAM / `.sav` / `.smdj` save format.
- **[HARDWARE.md](HARDWARE.md)** — controller-port and Game Gear EXT pinouts,
  sync cabling, and the EXT paddle-PCB notes.

### Source layout

```
src/        Z80 assembly (main, vdp, input, psg, engine, sample, editor)
tools/      Python build tools + the browser apps:
              makefont / maketables / makedemo / makelogo  (build inputs)
              smsdj_sample.py   WAV/pool -> sample bank
              savetool.py       song/.sav manager (CLI)
              patcher.html      browser sample patcher
              savetool.html     browser song/save manager
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
