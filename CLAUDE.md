# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

SMSDJ — an LSDJ-inspired music tracker ROM for the Sega Master System, written in pure Z80 assembly (WLA-DX). Sound is the SN76489 PSG only, including 4-bit PCM and wavetable synthesis via the tone-period-1 DC-DAC trick on channel T3.

**DESIGN.md is the contract.** It records hardware constraints, the data model, and decisions that were already debated (PAL default, CH3-steal policy, control scheme, 24 PPQN sync default). Read the relevant section before making design decisions; don't re-litigate settled ones. SAVEFORMAT.md documents the save/SRAM format and must be kept in sync with any RAM-layout change.

## Build and run

```sh
make          # assemble + link -> build/smsdj.sms
make run      # launch the ROM in Emulicious (bundled in tools/emulicious/)
make clean
```

- Toolchain: `wla-z80` + `wlalink` (Homebrew). `make run` needs `/opt/homebrew/opt/openjdk/bin/java`.
- Emulicious must have `AudioSync=true` in `tools/emulicious/Emulicious.ini`, or it free-runs at turbo speed.
- There is no test suite; verification = build clean and run in Emulicious. Emulicious's PSG-DAC emulation is decent but sample/wave behavior ultimately needs hardware verification.
- Build-generated includes (made automatically by `make` from the Python tools): `build/font.bin` (makefont.py), `build/notes.inc` (maketables.py — PAL+NTSC note-period tables), `build/pool.bin`/`pool.inc` (smsdj_sample.py from `samples/*.wav`).
- `tools/savetool.py build/smsdj.sav list|export|import` manipulates emulator/Everdrive save images (see SAVEFORMAT.md).

## Architecture

Single translation unit: the Makefile assembles only `src/main.asm`, which `.INCLUDE`s every other source file plus the generated includes. There is no per-file linking — adding a file means adding an `.INCLUDE` in main.asm *and* a prerequisite in the Makefile. 128 KB ROM, 8×16 KB banks (standard Sega mapper, `.SMSTAG` header): code/tables/demo in banks 0–1, the self-describing sample pool in banks 2–7 (contract in DESIGN.md §10.3 — ROM file offset $8000). SRAM maps over the pool banks in slot 2, so anything enabling SRAM must `smp_abort` first.

- `src/main.asm` — memory map, hardware port defines, boot, VBlank IRQ dispatch, main loop.
- `src/vdp.asm` — Mode 4 text UI helpers; register init table (line interrupt every 2 scanlines for the sample feed).
- `src/input.asm` — pad read with edge detection and LSDJ-style DAS key repeat.
- `src/psg.asm` — shadow registers in RAM; `psg_flush` writes only what changed. Volumes are stored as *attenuation* (0 = loud, $F = silent).
- `src/engine.asm` — per-tick sequencer pipeline (groove → row advance → trigger/commands → envelope → kill → PSG shadows → mute gate). Channel state = 4 × 32-byte structs walked with IX; layout documented in the file header. Full command set K/H/A/C/E/F/G/N/P/T/V/W/M/D/L/R runs through one executor shared by phrase and table columns.
- `src/sample.asm` — PCM and wavetable feed through the T3 DAC: line IRQ during active display, cycle-counted feeder across VBlank.
- `src/editor.asm` — all screens and UI (the largest file). Screen map is 2D: PROJECT above SONG, WAVE above INSTR; navigated with 2-held + d-pad.

Song data lives as one contiguous RAM block (wave_ram, phrase_pool, chains, song, instruments, tables, grooves — offsets in SAVEFORMAT.md) so save/load is a straight copy to cart SRAM slots.

## Hard invariants

- **The Z80 shadow register set (`EXX` / `EX AF,AF'`) belongs to the sample/wave feed IRQ.** Main-thread and engine code must never touch it.
- **VDP control-port byte pairs must be DI/EI-guarded** (or otherwise IRQ-safe): a line interrupt between the two bytes corrupts the address latch.
- No mul/div on hot paths — lookup tables in ROM (note tables, curves, BPM math).
- Timing/tuning constants are per-region (PAL default, NTSC pair in ROM, selected at boot).

## Control-scheme model

Any new gesture must fit this frame (user's settled design, DESIGN.md §3): button **2** = project-level modifier (screen nav, transport: 2-held + 1 = play/stop), button **1** = item-level modifier (insert/edit/audition; 1-held + 2 = cut, double-tap 1 = paste). Never introduce simultaneous-press timing windows; the button already held when the other arrives selects the action.

## Workflow

Work proceeds in the milestones of DESIGN.md §14; commit at each milestone boundary. Milestones 1–9 plus wavetables, block ops, native sync (replaced MIDI), live mode and the 128 KB mapper are done; remaining: the browser sample patcher, clone modes, config persistence, K-cuts-samples, polish, hardware verification.
