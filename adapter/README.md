# SMSGGDJ RP2040 USB-MIDI sync adapter

This firmware turns MIDI Start/Continue/Stop/Clock from a computer into the
2-bit, 24-PPQN counter understood by SMSGGDJ's `SYNC: IN24` mode.
The complete path is verified on a real Game Gear.

`smsggdj-sync-rp2040.uf2` is one universal build for:

- Seeed Studio XIAO RP2040 (2 MB)
- Raspberry Pi Pico / other regular-layout 2 MB RP2040 Pico boards

The binary does not detect the carrier board. Its custom board definition keeps
carrier-specific LED/power pins untouched and uses the XIAO-safe longer
oscillator startup allowance.

Two output pairs carry the same counter simultaneously:

| Output pair | Counter bit | XIAO RP2040 | Raspberry Pi Pico |
|---|---|---|---|
| **Non-inverted** | bit 0 | D6 / GP0 | GP0, physical pin 1 |
| **Non-inverted** | bit 1 | D7 / GP1 | GP1, physical pin 2 |
| **NPN/inverted** | bit 0 | D4 / GP6 | GP6, physical pin 9 |
| **NPN/inverted** | bit 1 | D5 / GP7 | GP7, physical pin 10 |
| either | ground | GND | any GND, e.g. physical pin 8 |

## Circuit

The Game Gear EXT port is 5 V logic and RP2040 pins are **not 5 V tolerant**.
Never connect either output pair directly to the console.

### Option A: two NPNs

Use the **inverted GP6/GP7 pair** with two NPN transistors. The firmware
compensates for their inversion, so the Game Gear receives the ordinary
counter:

```text
XIAO D4 / Pico GP6 -- 2.2 kΩ -- base Q1
                                     collector -- GG EXT pin 9 (PC5, bit 0)
board GND ---------------------- emitter

XIAO D5 / Pico GP7 -- 2.2 kΩ -- base Q2
                                     collector -- GG EXT pin 7 (PC6, bit 1)
board GND ---------------------- emitter

board GND ------------------------------------ GG EXT pin 8 (GND)
```

Q1 and Q2 may be 2N3904, PN2222A, BC547, or similar small-signal NPNs. Check
your transistor's lead order; it varies between parts. Optional 47–100 kΩ
resistors from each base to emitter keep the transistors off while the board is
unpowered. The console's existing input pull-ups provide the high level.

Do **not** connect Game Gear EXT pin 5 (+5 V) to the RP2040 board. Power the
board from USB and share only ground.

### Option B: non-inverting level translator

Use the **non-inverted GP0/GP1 pair** with a proper 3.3 V ↔ 5 V non-inverting
translator, for example a two-channel BSS138 level-shifter module:

| Level-shifter connection | Wire |
|---|---|
| LV | RP2040 3V3 |
| LV1 | GP0 (XIAO D6 / Pico physical pin 1) |
| LV2 | GP1 (XIAO D7 / Pico physical pin 2) |
| HV | Game Gear EXT pin 5 (+5 V), **level shifter only** |
| HV1 | Game Gear EXT pin 9 (PC5 / bit 0) |
| HV2 | Game Gear EXT pin 7 (PC6 / bit 1) |
| GND | RP2040 GND and Game Gear EXT pin 8 |

Do not use EXT pin 5 to power the RP2040 itself. If your translator has named
A/B sides instead of LV/HV, confirm that it supports 3.3 V inputs and 5 V
outputs and that it is non-inverting.

### Game Gear EXT bottom row

Looking into the socket with the console screen facing you, use the numbered
pinout in `GGSYNC.md`/`HARDWARE.md`; verify continuity before power-up:

| EXT pin | Use |
|---|---|
| 7 | PC6 / counter bit 1 |
| 8 | ground |
| 9 | PC5 / counter bit 0 |

Pin 6 may remain unconnected. SMSGGDJ reads counter bit 0 as PC4 AND PC5, and
the unconnected PC4 input is pulled high.

## Flash and use

1. Hold **B** while plugging in a XIAO RP2040, or hold **BOOTSEL** while
   plugging in a Pico.
2. Copy `smsggdj-sync-rp2040.uf2` to the `RPI-RP2` drive.
3. Reconnect normally. The board appears to the computer as **SMSGGDJ Sync**, a
   class-compliant USB-MIDI destination.
4. In the DAW, enable MIDI clock output and transport messages for
   **SMSGGDJ Sync**.
5. In the Game Gear ROM choose `SYNC: IN24`, press play so the display says
   `WAIT`, then start the DAW. Six MIDI clocks advance one tracker row.

MIDI Start resets the adapter counter, Stop freezes it, and Continue resumes it.
Channel notes and controller messages are ignored.

## Build

Install the Arm embedded compiler and the Raspberry Pi Pico SDK (including
submodules), then either export `PICO_SDK_PATH` or pass it to `make`:

```sh
make adapter PICO_SDK_PATH=/path/to/pico-sdk
```

The UF2 is copied to `build/smsggdj-sync-rp2040.uf2`.
