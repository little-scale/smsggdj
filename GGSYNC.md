# Game Gear sync — EXT-port contract

Implementation and bring-up notes for `SYNC: IN`, `IN24`, `OUT`, and `MIDI` on
the native Game Gear ROM. The SMS path and the RP2040-driven GG `SYNC: IN24`
path are hardware-proven. GG-to-GG output still needs confirmation. See also
`HARDWARE.md`, `adapter/README.md`, and DESIGN.md §11.

## The important difference from SMS

The Master System reads its sync lines through controller-port register `$DD`.
The Game Gear has dedicated link I/O registers, so the GG build reads and
drives the EXT parallel port directly. Real-hardware testing confirms that the
GG's `$DD` controller view also mirrors the relevant EXT inputs, as documented,
but `$01` is used by the main code because its bits map directly to PC0-PC6.

The official Sega Game Gear Hardware Reference Manual defines:

| Port | Function |
|---|---|
| `$01` | PC0–PC6 parallel data |
| `$02` | bit 7 = PC6 falling-edge NMI disable; bits 6–0 = PC6–PC0 direction |
| `$03` | serial transmit data |
| `$04` | serial receive data |
| `$05` | serial status/control and baud selection |

For each `$02` direction bit, **0 means output** and **1 means input**. Bit 7 of
0 enables a falling edge on PC6 to generate NMI; bit 7 of 1 disables it.
SMSGGDJ keeps bit 7 set except when the standalone diagnostic ROM deliberately
tests NMI.

Authoritative reference:
[Sega Game Gear Hardware Reference Manual](https://manuals.plus/m/de6ad4ef2f625706764f4cb87455c2ab7a25ddaf1bcb68e7ae44a1a3ef626b60.pdf).

## Chosen mechanism: parallel 2-bit counter

The GG implementation uses PC5 and PC6 as ordinary GPIO. It deliberately avoids
the serial/NMI path:

- `sync_read` reads `$01`.
- counter bit 0 = PC4 AND PC5, allowing either a straight connection or the
  TX/RX crossover in a Gear-to-Gear cable.
- counter bit 1 = PC6.
- the slave calculates `(current - previous) & 3`, exactly like the SMS path.

This preserves up to three clocks between video-frame polls without adding an
asynchronous interrupt to the cycle-sensitive sample/wavetable feed.

The parallel data latch has an undefined power-on value. Native-GG startup
therefore sets `$02 = $FF` first, writes `$01 = $FF` while every pin is safely
an input, and writes `$02 = $FF` again. Releasing OUT or MIDI repeats the safe
input-then-latch sequence. When entering an output mode, the intended first
level is preloaded into `$01` before the relevant `$02` direction bits become
outputs, preventing a stale-level glitch.

### Safe `$02` masks

| Situation | `$02` | Meaning |
|---|---:|---|
| released / input | `$FF` | PC0–PC6 inputs, PC6 NMI disabled |
| sync OUT | `$8F` | PC4–PC6 outputs, PC0–PC3 inputs, NMI disabled |
| MIDI takeover | `$DF` | PC5 output; PC6 and the rest inputs; NMI disabled |

Earlier `$0F`/`$5F`/`$7F` values got the directions right but left bit 7 clear,
which could arm a PC6 falling-edge NMI. Those masks are no longer used by the
normal ROM. `gg_link_test.asm` still uses `$7F` intentionally in its explicit
NMI test and restores `$FF` afterward.

## Wiring

The relevant pins are the bottom row of the EXT socket:

| EXT pin | Signal | Parallel counter use |
|---:|---|---|
| 6 | PC4 / serial TX | optional redundant bit 0; otherwise leave open |
| 7 | PC6 | counter bit 1 |
| 8 | GND | shared ground |
| 9 | PC5 / serial RX | counter bit 0 |

For a direct bridge connection, pin 6 may remain unconnected. Its pull-up makes
`PC4 AND PC5` equal PC5. A GG-to-GG master drives bit 0 on both PC4 and PC5 so a
stock crossed Gear-to-Gear cable also works.

The Game Gear signals are 5 V logic. USB-power the RP2040 and never connect EXT
pin 5 directly to the board's power input. The universal UF2 provides both
polarities for a safe external interface:

- non-inverted GP0/GP1 → non-inverting 3.3 V/5 V translator → PC5/PC6
- NPN-compensated GP6/GP7 → two NPN stages → PC5/PC6
- board GND → EXT pin 8

Only a level translator's high-voltage reference may use EXT pin 5. The full
XIAO/Pico circuits are in `adapter/README.md`.

## Current status

- ✅ real GG hardware: pins 6/7/9 all respond through both `$01` and `$DD`.
- ✅ GG startup safely initialises the undefined parallel data latch.
- ✅ GG OUT drives PC4/PC5/PC6 through `$01` with safe `$02 = $8F`.
- ✅ stop/release restores `$02 = $FF`.
- ✅ MIDI takeover uses `$02 = $DF`; leaving it restores `$FF`.
- ✅ the register map, direction convention, and NMI-disable bit are checked
  against Sega's manual.
- ✅ a Gearsystem validation build has exercised the `.gg` EXT read/write path.
- ✅ USB-MIDI clock through the universal RP2040 UF2 and level interface drives
  `SYNC: IN24` correctly on a real Game Gear.
- ✅ the current Chipbridge PCB, populated with a Waveshare RP2040-Zero running
  `smsggdj-bridge-rp2040-zero.uf2`, drives both `SYNC: IN24` and MIDI takeover
  correctly on real Game Gear hardware (and the same two modes are confirmed on
  Master System).
- ⏳ GG-to-GG OUT still requires real-hardware confirmation.

The standalone `gg-link-test.gg` verifies both `$01` and `$DD`; all three pins
have passed that test on real hardware. The RP2040 `SYNC: IN24` path has also
passed. GG-to-GG `OUT` remains the final unverified EXT mode.
