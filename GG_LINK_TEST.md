# Game Gear link-port input test ROM

Build the standalone diagnostic with:

```sh
make gg-link-test
```

Flash `build/gg-link-test.gg`. The ROM samples the EXT connector as parallel
GPIO about 60 times per second. It initialises the parallel data latch while
all pins are inputs, rather than relying on the Game Gear's undefined
power-on latch state.

The display shows the connector through both documented input paths:

- raw port `$01` and raw controller mirror `$DD`;
- pin 6 / PC4 (`$01` bit 4 and `$DD` bit 2);
- pin 7 / PC6 (`$01` bit 6 and `$DD` bit 7);
- pin 9 / PC5 (`$01` bit 5 and `$DD` bit 3);
- a sampled transition counter for each pin;
- the PC6 falling-edge NMI count.

The `01` and `DD` columns should agree. `LOW` is shown in inverse video.
An edge counter advances if either input view detects a transition. Press
**Button 1** to clear all counters.

The ROM normally writes `$FF` to port `$02`: every PC pin is an input and the
PC6/pin-7 NMI is disabled. Press **START** to deliberately arm that NMI using
`$7F`; press START again to return to safe polling mode. The serial UART remains
disabled throughout this test.

## Safe probe procedure

Power off before attaching the cable or probe. After the ROM is running, use a
4.7 kOhm resistor between a signal and pin 8/GND; do not inject +5 V. Locally:

| Probe | Expected display |
|---|---|
| pin 6 to pin 8 | pin 6 LOW in both columns; `$01.4` and `$DD.2` clear |
| pin 7 to pin 8 | pin 7 LOW in both columns; `$01.6` and `$DD.7` clear |
| pin 9 to pin 8 | pin 9 LOW in both columns; `$01.5` and `$DD.3` clear |

Through a stock Gear-to-Gear cable, pins 6 and 9 cross and pin 7 is straight:

| Ground at far end | Expected at the test-ROM end |
|---|---|
| pin 9 | local pin 6 LOW |
| pin 7 | local pin 7 LOW |
| pin 6 | local pin 9 LOW |

Never configure both connected ends as outputs. This diagnostic keeps all
three tested lines as inputs, including while the pin-7 NMI is armed.
