# Game Gear EXT sync-port paddle

This is the hardware-verified PCB paddle and printable housing used to connect
the Game Gear EXT port to SMSGGDJ sync hardware. The PCB exposes the four useful
bottom-row EXT contacts on a 2.54 mm, 1x4 through-hole header.

The design is **hardware v1.0** and was verified on a real Game Gear with the
universal XIAO RP2040/Pico USB-MIDI adapter and SMSGGDJ `SYNC: IN24`.

## Verified configurations

- **DAW MIDI clock → Game Gear:** Ableton Live (or another DAW sending MIDI
  clock) → Chipbridge → Sega 9-pin-to-TRS adapter → Master Link Cable → Game
  Gear running SMSGGDJ in `SYNC: IN24`.
- **Direct Game Gear-to-Game Gear:** one EXT paddle on each console, connected
  by a TRS cable. The master runs `SYNC: OUT`; the follower runs `SYNC: IN`.
- **Game Gear clock out to TRS:** one EXT paddle through the external-sync /
  Chipbridge adapter with its selector in **position A**, with SMSGGDJ set to
  `SYNC: OUT`.

All three paths have been tested on real hardware.

## Contents

```text
kicad/
  GG_sync_port.kicad_pro   KiCad project
  GG_sync_port.kicad_sch   schematic
  GG_sync_port.kicad_pcb   PCB layout

enclosure/
  gg-sync-port-housing.stl print-ready binary STL in millimetres

manufacturing/
  v1.0/README.md           fabrication-export destination and release notes
```

The authoritative source files were saved by **KiCad 10.0**. The imported
project intentionally excludes KiCad backups, lock files, local preferences,
and the editor's private `.history` repository.

## PCB

- Board outline: approximately **11.900 × 12.406 mm**
- Board thickness in the source: **1.6 mm**
- Layers: 2
- Connector: vertical 1x4, 2.54 mm pitch, 1 mm drill
- EXT contact order across the paddle: pin 10 (NC), 9, 8, 7, 6
- The pin-10 contact is intentionally not routed to the header.

Use the same board thickness as the verified sample. The EXT fingers are
exposed contacts, so choose a durable contact finish appropriate for repeated
insertion; ENIG is a sensible fabrication default.

### Header J1

| J1 pin | Game Gear EXT | Signal | SMSGGDJ use |
|---:|---:|---|---|
| 1 | 9 | PC5 / serial RX | counter bit 0 |
| 2 | 8 | GND | shared ground |
| 3 | 7 | PC6 | counter bit 1 |
| 4 | 6 | PC4 / serial TX | optional redundant bit 0 |

For a direct RP2040 bridge, EXT pin 6 may remain unconnected. SMSGGDJ reads
counter bit 0 as PC4 AND PC5, and the unused PC4 input is pulled high.

## Housing

`enclosure/gg-sync-port-housing.stl` is a 100-triangle binary STL normalized to
millimetres. Its bounding dimensions are:

```text
16.000 × 10.906 × 6.200 mm
```

Import it into the slicer at **100% scale in millimetres**. Confirm dimensions
before printing; STL itself has no standard unit metadata. The editable/native
housing CAD should be added alongside the STL if it becomes available.

## RP2040 wiring

The universal UF2 presents both output polarities simultaneously:

| Counter | Non-inverted | NPN-compensated | GG EXT |
|---|---|---|---:|
| bit 0 | GP0 / XIAO D6 | GP6 / XIAO D4 | pin 9 |
| bit 1 | GP1 / XIAO D7 | GP7 / XIAO D5 | pin 7 |
| ground | GND | GND | pin 8 |

Use exactly one of the 5 V-safe interfaces documented in
[the RP2040 adapter guide](../../adapter/README.md). **Never connect an RP2040
GPIO directly to the Game Gear's 5 V EXT port.** Power the RP2040 by USB and
share ground through EXT pin 8.

The complete register, protocol, and connector notes are in
[GGSYNC.md](../../GGSYNC.md) and [HARDWARE.md](../../HARDWARE.md).

## Manufacturing releases

The editable KiCad files are the source of truth. For a frozen fabrication
revision, export Gerbers and drill files from the tagged source and attach a
clearly versioned ZIP, such as `gg-sync-port-v1.0-gerbers.zip`, to the
corresponding GitHub release. The KiCad project is configured to place these
exports in `manufacturing/v1.0/`.

Unless stated otherwise, these files are distributed under the repository's
[MIT licence](../../LICENSE).
