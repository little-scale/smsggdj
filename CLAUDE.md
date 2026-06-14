# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

SMSGGDJ — an LSDJ-inspired music tracker for the Sega Master System and Game Gear (one tree, two ROM flavors: SMSDJ and GGDJ), written in pure Z80 assembly (WLA-DX). Sound is the SN76489 PSG only, including 4-bit PCM and wavetable synthesis via the tone-period-1 DC-DAC trick on channel T3.

**DESIGN.md is the contract.** It records hardware constraints, the data model, and decisions that were already debated (PAL default, CH3-steal policy, control scheme, 24 PPQN sync default). Read the relevant section before making design decisions; don't re-litigate settled ones. SAVEFORMAT.md documents the save/SRAM format and must be kept in sync with any RAM-layout change.

## Build and run

```sh
make          # both flavors: build/smsdj.sms + build/smsdj.gg
make run      # launch the SMS ROM in Emulicious (bundled in tools/emulicious/)
make clean
```

Build flags (passed to `wla-z80` via the Makefile): `DEMO_MODE` makes a
self-playing build (auto-plays the demo song from boot). Normal builds load
the same demo song but wait for play (a blank song is still available via
PROJECT → NEW). `make demo` / `make run-demo[-gg]` produce separate
`-demo.sms`/`-demo.gg` outputs. The boot splash lives in a bank-1 `"Splash"`
section (bank 0/slot 0 is full).

Two ROM flavors from one tree: `TARGET_GG` (assembled as `main-gg.o`) is the
native Game Gear build — 20×18-tile window layout via a UI origin in
`nt_addr_hl` plus per-flavor defines (`GRID_ROW`, `NAME_ROW`, `STATE_*`),
START instead of PAUSE, 12-bit CRAM, NTSC-only, paged WAVE screen. Layout
literals must respect the GG window: columns ≥20 and grid rows beyond 15
don't exist there (DESIGN.md §15).

- Toolchain: `wla-z80` + `wlalink` (Homebrew). `make run` needs `/opt/homebrew/opt/openjdk/bin/java`.
- Emulicious must have `AudioSync=true` in `tools/emulicious/Emulicious.ini`, or it free-runs at turbo speed.
- There is no test suite; verification = build clean and run in Emulicious. Emulicious's PSG-DAC emulation is decent; the timing-critical sample/wave feed is now **confirmed on real hardware** (PAL SMS1 via flashcart) — still worth checking NTSC and Game Gear hardware.
- Build-generated includes (made automatically by `make` from the Python tools): `build/font.bin` (makefont.py), `build/notes.inc` (maketables.py — PAL+NTSC note-period tables), `build/demo.bin` (makedemo.py), `build/logo.bin`/`logo.inc` (makelogo.py from `art/`), and the sample pool (see below).
- **Demo song:** if `songs/demo.smdj` exists (a committed save export), the build strips its 16-byte header and bakes the 5376-byte block as `build/demo.bin`, with its echo settings (the SMDJ3 reserved bytes) in `build/demo_echo.bin`; both ride into `song_init`. Otherwise `makedemo.py` composes one. Delete `songs/demo.smdj` for the procedural demo.
- **Sample pool:** if `samples/pool.bin` exists (a 96 KB pool image, the production bank — committed, tuned in `tools/patcher.html`), the build bakes it in verbatim via `smsdj_sample.py --pool-in`. Otherwise it converts `samples/*.wav` with `smsdj_sample.py`. Delete `samples/pool.bin` to go back to the WAV pipeline. The pool region is byte-identical in both flavors, so one pool serves `.sms` and `.gg`.
- `tools/savetool.py build/smsdj.sav list|export|import` manipulates emulator/Everdrive save images (see SAVEFORMAT.md).

## Architecture

Single translation unit: the Makefile assembles only `src/main.asm`, which `.INCLUDE`s every other source file plus the generated includes. There is no per-file linking — adding a file means adding an `.INCLUDE` in main.asm *and* a prerequisite in the Makefile. 128 KB ROM, 8×16 KB banks (standard Sega mapper, `.SMSTAG` header): code/tables/demo in banks 0–1, the self-describing sample pool in banks 2–7 (contract in DESIGN.md §10.3 — ROM file offset $8000). SRAM maps over the pool banks in slot 2, so anything enabling SRAM must `smp_abort` first.

- `src/main.asm` — memory map, hardware port defines, boot, VBlank IRQ dispatch, main loop.
- `src/vdp.asm` — Mode 4 text UI helpers; register init table (line interrupt every 2 scanlines for the sample feed).
- `src/input.asm` — pad read with edge detection and LSDJ-style DAS key repeat.
- `src/psg.asm` — shadow registers in RAM; `psg_flush` writes only what changed. Volumes are stored as *attenuation* (0 = loud, $F = silent).
- `src/engine.asm` — per-tick sequencer pipeline (groove → row advance → trigger/commands → envelope → kill → PSG shadows → mute gate). Channel state = 4 × 32-byte structs walked with IX; layout documented in the file header. Full command set (A/B/C/D/E/F/G/H/I/K/L/M/N/O/P/R/S/T/V/W; `cmd_chars`/`cmd_order` map ids↔letters↔alphabetical rank) runs through one executor shared by phrase and table columns. `B` (wave-bank select) and D/L/I are peeked *before* the trigger; tempo (T)/groove (G)/hop (H)/wait (W) are handled inline. A once-per-tick `echo_pass` post-pass (bank-1 `Echo` section) reads a 64-tick ring of T1 and replays delayed/transposed copies onto T2/T3.
- `src/sample.asm` — PCM and wavetable feed through the T3 DAC: line IRQ during active display, cycle-counted feeder across VBlank.
- `src/editor.asm` — all screens and UI (the largest file). Screen map is 2D: OPTIONS/PROJECT above SONG/CHAIN, WAVE above INSTR; navigated with 2-held + d-pad. Bank 0 (slot 0) is full, so overflow code lives in bank-1 (`"Clone"`, `"CmdTab"`, `"TempoCalc"`, and the ECHO form) sections forced into slot 1 (always mapped) — new editor code that overflows bank 0 goes there too. The ECHO screen sits below INSTR; TMPO (PROJECT) is a live readout derived from the active groove (tempo *is* the groove — see DESIGN §9).

Song data lives as one contiguous RAM block (wave_ram ×8 waves, phrase_pool, chains, song, instruments, tables, grooves — offsets in SAVEFORMAT.md, format SMDJ3) so save/load is a straight copy to cart SRAM slots.

## Hard invariants

- **The Z80 shadow register set (`EXX` / `EX AF,AF'`) belongs to the sample/wave feed IRQ.** Main-thread and engine code must never touch it.
- **VDP control-port byte pairs must be DI/EI-guarded** (or otherwise IRQ-safe): a line interrupt between the two bytes corrupts the address latch.
- No mul/div on hot paths — lookup tables in ROM (note tables, curves, BPM math).
- Timing/tuning constants are per-region (PAL default, NTSC pair in ROM, selected at boot).

## Control-scheme model

Any new gesture must fit this frame (user's settled design, DESIGN.md §3): button **2** = project-level modifier (screen nav, transport: 2-held + 1 = play/stop), button **1** = item-level modifier (insert/edit/audition; 1-held + 2 = cut, double-tap 1 = paste). Never introduce simultaneous-press timing windows; the button already held when the other arrives selects the action.

## Workflow

Work proceeds in the milestones of DESIGN.md §14; commit at each milestone boundary. Milestones 1–9 plus wavetables, block ops, native sync (replaced MIDI), live mode and the 128 KB mapper are done; clone modes, K-cuts-samples, the wave-bank (`B`) command, the tempo-synced echo, and the `I` iteration play-mask are also done. **Hardware-verified on a PAL SMS1** (flashcart). Remaining: config persistence, polish, NTSC / Game-Gear hardware checks.

Releases are versioned — `str_version` in `src/main.asm` is the splash string (currently `V0.22`, dev), with a per-version `CHANGELOG.md`. Add user-facing bullets to the current version's section as you make changes, and keep `str_version` in sync on a release.
