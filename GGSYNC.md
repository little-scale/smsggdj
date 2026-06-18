# Game Gear sync — how the EXT port really works

Working notes for getting **SYNC IN on the Game Gear** right. The SMS sync is
hardware-proven (PAL SMS1 + the ESP32 / ares Link bridges); the **GG path is not
yet verified on silicon**, and the GG accesses its link port *differently* from
the SMS. This file is the contract for that work — read it before touching the GG
sync read or fabbing a cable/paddle. See also HARDWARE.md (pinout, cabling, paddle
PCB) and DESIGN.md §11 (the sync protocol).

## The trap

The SMS reads the 2-bit sync counter from **controller port 2's TR + TH**
(`$DD` bits 3 and 7). It is tempting to assume the GG reads the same pins the same
way. **It does not.** The Game Gear has its *own* dedicated I/O registers for the
EXT/link port — the SMS controller-port read does **not** sample the EXT pins on a
GG. Any GG sync code that reuses the `$DC`/`$DD` path is reading the wrong
register.

## How the GG EXT port works

The GG EXT port supports **two modes**, both driven from GG-specific I/O ports
(distinct from the SMS controller ports):

### 1. Parallel (GPIO) mode
- A **data-direction register** sets each EXT bit's direction (`0 = output`,
  `1 = input`).
- A **data register** is read/written to sample or drive the pins.
- The seven parallel bits map to PC0–PC6; **PC4/PC5 double as the serial TX/RX**,
  the others are free parallel bits.
- ⟹ A GG ROM **can read the EXT pins as plain GPIO** — so SMSGGDJ's existing
  2-bit-counter protocol works on GG unchanged *except for which port the read
  targets* (the parallel data port, after setting those bits as inputs — not
  `$DC`/`$DD`).

### 2. Serial (UART) mode
- 5 V TTL UART: **TX on PC4 (EXT pin 6)**, **RX on PC5 (EXT pin 9)**.
- The hardware **raises an NMI whenever a byte is received** (or the connected
  console powers off). Inside the NMI you read the **status port** and act on it.
- **NMI is optional**: with NMI disabled you can **poll status-port bit 1**
  ("new data to read") each frame instead.

(So "the GG is serial with NMI to flag a new byte" is correct — that's the native
link mode — but parallel GPIO and serial-with-polling are equally available.)

## Three candidate implementations for SYNC IN

| | Mechanism | Pins used | Risk | Engine change |
|---|---|---|---|---|
| **A. Parallel 2-bit counter** ⭐ | direction reg → inputs; read data port. Bridge drives 2 level bits (Gray-coded counter); engine keeps `(read − last) & 3`. | 2 of TR/TH + GND | **Lowest** — no UART, no interrupt, reuses the proven SMS protocol & its jitter tolerance | just the read port (+ a one-time direction init) |
| **B. Serial + polled status** | bridge sends 1 byte/tick over UART; GG polls status bit 1 each frame, reads the RX byte, counts ticks. | RX(9) + GND | Low — no async interrupt; but the bridge must speak the GG UART (exact baud TBD) | new serial-poll read path |
| **C. Serial + NMI** | 1 byte/tick → NMI → minimal handler bumps a tick counter. (The "strobe NMI" idea.) | RX(9) + TH/NMI(7) + GND | **Higher** — NMI is non-maskable/async; it can land mid sample-feed IRQ or mid VDP control-pair write (the hard invariants). Handler must be tiny and never touch the feed's shadow register set. | NMI vector + handler |

**Recommendation: path A.** It reuses the exact counter protocol SMSGGDJ already
ships (TR + TH, `(read−last)&3`), adds no UART framing and no asynchronous
interrupt to fight the cycle-counted DAC feed. The only delta from the SMS path is
*which port the read hits*. Path B is the clean fallback if parallel reads
misbehave on hardware. Path C is the most "designed-for" GG mode but loads the
IRQ-safety burden onto the handler — weigh it against the sample/wave feed.

## Wiring

The 4-wire bottom-row set covers **all three** paths without a re-fab — keep it:

| EXT pin | Signal | A (parallel) | B (serial poll) | C (serial NMI) |
|---|---|---|---|---|
| 7 | PC6 / TH ("NMI") | counter bit 1 | — | NMI line |
| 9 | PC5 / TR ("RX") | counter bit 0 | RX in | RX in |
| 6 | PC4 / TL ("TX") | (spare / redundant bit 0) | — | — |
| 8 | GND | ground | ground | ground |

Everything sync needs is on the **bottom row** (HARDWARE.md). Do **not** tap +5V
(top row, pin 5) — USB-power the bridge and share only GND. The planned paddle's
`TL6 TH7 GND8 TR9` header already matches this.

## Open items (must close before trusting GG sync)

1. **Audit the current GG sync read.** Does `src/engine.asm` read sync from the
   SMS `$DC`/`$DD` controller path even in the `TARGET_GG` build? If so, it is
   sampling the wrong register on GG → switching it to the GG **parallel data
   port** (path A, with the direction-register init) is the likely one-spot fix.
2. **Verify the exact GG I/O register map** — which `$0x` port is the parallel
   data register, the direction register, the serial TX/RX buffers, and the
   status/control register; the NMI-enable bit; the "RX full" status bit; and (for
   paths B/C) the **baud-rate bits**. The search summaries establish the *model*
   above but not the verbatim port/bit numbers. Pull them from the manual:
   - Gear to Gear Cable — SMS Power!: <https://www.smspower.org/Development/GearToGearCable>
   - Peripheral Ports — SMS Power!: <https://www.smspower.org/Development/PeripheralPorts>
   - Sega Game Gear Hardware Reference Manual (PDF, authoritative register/bit map):
     <https://segaretro.org/images/1/16/Sega_Game_Gear_Hardware_Reference_Manual.pdf>
   - SEGA Official Serial Protocol notes (HINATA): <https://hinata.neri.moe/en/sega/serial>
   (Both smspower and segaretro 403 automated fetchers — open them in a browser.)
3. **Hardware test** on a real Game Gear once a candidate path is wired, the same
   way the SMS path was confirmed.
