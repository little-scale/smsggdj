# SMSDJ / GGDJ hardware notes

Companion to DESIGN.md §11 (sync wiring) and §15 (GGDJ). Working notes for
the physical bits — connectors, cables, and the EXT paddle PCB.

## Game Gear EXT connector

A 10-pin proprietary port: a centre **tongue** inside a keyed shroud, contacts
on both faces; the cable plug is the receptacle. Numbering (looking at the
console's EXT port, per the GG board silkscreen):

```
top row:     5  4  3  2  1
bottom row: 10  9  8  7  6
```

| pin | signal | controller-port meaning           |
|-----|--------|-----------------------------------|
| 1   | PC0    | Left                              |
| 2   | PC1    | Right                             |
| 3   | PC2    | Up                                |
| 4   | PC3    | Down                              |
| 5   | +5V    | power (one end only in G2G cable) |
| 6   | PC4    | TL / button 1 — serial **TX**     |
| 7   | PC6    | TH — serial-mode NMI line         |
| 8   | GND    | ground                            |
| 9   | PC5    | TR / button 2 — serial **RX**     |
| 10  | NC     | —                                 |

(D-pad order per the elefasgr EXT→DB9 adapter article; SMS Power's
Gear-to-Gear page documents the cable and serial mode.)

**Everything sync needs is on the bottom row**: serial = 6/8/9 (TX/GND/RX);
the SMS counter protocol = 7/8/9 (TH/GND/TR). +5V is on the *top* row —
unreachable by a bottom-side-only contact.

**Cable crossovers** (stock Gear-to-Gear cable): 1↔3, 2↔4, **6↔9** (TX↔RX),
7↔7, 8↔8. SMSDJ's SYNC IN reads counter bit 0 as TR AND TL, so straight and
crossed cables both work (DESIGN.md §11).

Measured so far (from macro photo, **verify with calipers before fab**):
contact field outer span 12.75 mm, inner 11.7 mm, contact width 1.4 mm →
pitch ≈ (11.7 − 1.4) / 4 ≈ **2.575 mm, i.e. probably standard 2.54 mm**.
Still needed: **pitch (confirm), tongue contact depth, bottom-gap height**.

## EXT paddle PCB (planned)

A bare PCB that slides into the **bottom gap** of the EXT port, gold fingers
up against the tongue's bottom-row contacts, terminating in a 5-pin 2.54 mm
through-hole header row.

Design decisions (settled 2026-06-12):

- **Single-sided fingers, deliberately**: copper on one face only. Flipped
  insertion (into the top gap, where +5V lives) presents bare board — no
  contact, inherently safe. This replaces keying for the bare-board version.
- **T-shaped outline**: tongue narrower than the body; the shoulders are the
  insertion depth stop. Tongue length = measured contact depth − ~0.5 mm.
- **Fingers**: all 5 positions (pin 10 NC kept for mechanical evenness),
  ~1.2 mm wide on the measured pitch, bevelled edge (20–30°), hard gold for
  a frequently-cycled tool (ENIG acceptable for a bench one-off).
- **Thickness vs. gap sets contact pressure**: order 0.8 mm and 1.0 mm
  variants; Kapton on the bare face shims a loose fit.
- **Header**: `TL6 TH7 GND8 TR9 NC10`, silkscreened on both faces. GND is
  the **middle finger** — a mirrored build swaps TL/TR but keeps GND on GND.
  First-connect ritual: power off, continuity from the GND pin to console
  ground before trusting anything.
- Two mounting holes in the body for the phase-2 printed shell (which adds
  alignment, grip, and replicates the plug's keyed profile).
- KiCad files to be generated once the three caliper numbers exist.

## Sourcing (state of the market, June 2026)

No modern reproduction Gear-to-Gear cables found. Leads:

- **Press-StartGames (NL)** — G2G cable listed *new* (NOS), ~€19:
  <https://www.press-startgames.com/a-41890321/game-gear-accessoires/game-gear-gear-to-gear-link-cable-new/>
- **eStarland (US)** — catalog page exists, stock unverified:
  <https://www.estarland.com/product-description/SegaGameGear/Game-Gear-Gear-to-Gear-Cable/33149>
- **Amazon** — *aftermarket* Master Link-style adapter (EXT→DE-9), proof the
  EXT plug exists in aftermarket tooling, and a donor-plug source:
  <https://www.amazon.com/Master-System-Controller-Adapter-Cable-Converters/dp/B071NV61MC>
- eBay "Game Gear replacement parts" lists desoldered **EXT ports** (the
  console-side socket) — useful for test jigs. Search ebay.com.au:
  "gear to gear cable", "game gear link cable".

Strategy: one genuine/NOS cable as reference + validation; the paddle PCB as
the reproducible part (and the basis of any future sync dongle product).

## SMS-side recap

Console-to-console SMS sync: straight 3-wire DE-9 — pins 9 (TR), 7 (TH),
8 (GND). SMS↔GG: male-male DE-9 + Master Link Cable (straight mapping).
Export consoles only for the SMS master (port $3F level drive). The known
hardware-verification items for the flashcart pass live in the project
memory: `print_at`'s ~24-cycle VRAM write spacing, real-DAC sample/wave
quality, and the sync electrical checks above.
