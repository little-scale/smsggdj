# Game Gear link-port input test ROM

Build the standalone diagnostic with:

```sh
make gg-link-test
```

Flash `build/gg-link-test.gg`. The ROM samples the EXT connector as parallel
GPIO about 60 times per second and displays:

- raw port `$01` bits;
- pin 6 / PC4 / bit 4;
- pin 7 / PC6 / bit 6;
- pin 9 / PC5 / bit 5;
- a sampled transition counter for each pin;
- the PC6 falling-edge NMI count.

`LOW` is shown in inverse video. Press **Button 1** to clear all counters.

The ROM normally writes `$FF` to port `$02`: every PC pin is an input and the
PC6/pin-7 NMI is disabled. Press **START** to deliberately arm that NMI using
`$7F`; press START again to return to safe polling mode. The serial UART remains
disabled throughout this test.

## Safe probe procedure

Power off before attaching the cable or probe. After the ROM is running, use a
4.7 kOhm resistor between a signal and pin 8/GND; do not inject +5 V. Locally:

| Probe | Expected display |
|---|---|
| pin 6 to pin 8 | pin 6 LOW; raw bit 4 clears |
| pin 7 to pin 8 | pin 7 LOW; raw bit 6 clears |
| pin 9 to pin 8 | pin 9 LOW; raw bit 5 clears |

Through a stock Gear-to-Gear cable, pins 6 and 9 cross and pin 7 is straight:

| Ground at far end | Expected at the test-ROM end |
|---|---|
| pin 9 | local pin 6 LOW |
| pin 7 | local pin 7 LOW |
| pin 6 | local pin 9 LOW |

Never configure both connected ends as outputs. This diagnostic keeps all
three tested lines as inputs, including while the pin-7 NMI is armed.
