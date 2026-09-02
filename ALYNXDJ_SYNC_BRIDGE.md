# Deferred design: SMSGGDJ to ALYNXDJ sync bridge

**Status: design note only — not implemented or hardware-tested.**

This records a possible future Chipbridge firmware mode for synchronising
ALYNXDJ on an Atari Lynx to an SMSGGDJ master running on a Master System or
Game Gear. Implementation should wait until both consoles and the complete
cable path are available for proper testing.

## Proposed signal path

```text
SMSGGDJ SYNC OUT counter bit 0
        |
        v
Chipbridge TRS MIDI input / optocoupler / RP2040 GP13
        |
        v
one transition -> one ALYNXDJ serial sync byte
        |
        v
Chipbridge CONSOLE_DATA ring / RP2040 GP1
        |
        v
Lynx ComLynx input -> ALYNXDJ SYNC IN
```

SMSGGDJ's two-bit counter advances once per tracker row. Counter bit 0
therefore alternates on every row (`0, 1, 0, 1...`), so the complete two-bit
value is not needed for this bridge. The RP2040 can detect both rising and
falling transitions and send one ALYNXDJ row event for each transition.

This is a row-clock conversion, not MIDI clock and not 24 PPQN. ALYNXDJ should
use its native `SYNC IN` mode rather than `IN24`.

## Proposed dedicated UF2

A separate, clearly named Chipbridge UF2 should be used so the existing
general-purpose firmware retains its current MIDI and SMSGGDJ behaviour.
The proposed build would:

- configure GP13 as a GPIO edge input rather than a 31,250-baud MIDI receiver;
- accept both edges because the optocoupler inverts the input;
- use the existing open-drain PIO transmitter on GP1 at 62,500 baud;
- send ALYNXDJ `ROW` (`0x01`) for each qualified row transition;
- optionally send `START` (`0x02`) for the first transition, noting that START
  is itself ALYNXDJ's first-row/downbeat event;
- optionally send `STOP` (`0x03`) after an inactivity timeout, with the
  limitations described below.

An initially simpler operating procedure is to put ALYNXDJ in `SYNC IN`, press
play so that it is waiting, and translate every qualified transition to `ROW`.
The first received ROW then starts ALYNXDJ at its selected row.

## Two protocol details that must be resolved

### First-row phase

SMSGGDJ currently releases the counter lines high while idle (`11`), resets
the counter to zero, and emits `01` on the first row. Bit 0 is high in both the
idle and first-row states, so a bridge observing only bit 0 sees no first-row
transition and would begin one row late.

The clean proposed correction is a small SMSGGDJ change applying only to
`SYNC: OUT`: initialise the counter phase so the first emitted value is `10`.
That creates a high-to-low bit-0 transition on the first row. Do not change the
shared counter initialisation indiscriminately because the counter is also
used by PULSE mode.

This change is intentionally **not implemented yet**.

### Stop/release ambiguity

When playback stops, SMSGGDJ releases the lines to their pulled-high idle
state. If bit 0 was low, that release produces a final rising edge that a
one-bit receiver cannot distinguish perfectly from another row.

Possible policies to test are:

- stop ALYNXDJ manually for the first prototype;
- reject a suspected final edge using measured row timing, then issue STOP
  after an inactivity timeout;
- later add an explicit transport indication if exact automatic stop is
  required.

An inactivity timeout is necessarily heuristic, especially across tempo or
groove changes, and must not be documented as exact transport detection.

## Proposed Chipbridge connections

The existing PCB appears suitable without a hardware revision:

- **Input:** the TRS MIDI input reaches the RP2040 through the 6N138
  optocoupler and is read on GP13.
- **Output:** the CONSOLE_DATA ring is GP1 and can carry the open-drain
  ComLynx serial output.
- **Ground:** use the required common/reference connections for the two cable
  paths as established by the PCB and console interfaces.

The SMSGGDJ-clock input cable is **not a MIDI cable**, even though it uses the
Chipbridge MIDI-input socket. It needs a deliberate polarity and added current
limiting for the optocoupler LED. The existing input includes 220 ohms; roughly
another 560 ohms is a reasonable 5 V prototype starting point, but the final
value and TRS polarity must be checked against the optocoupler datasheet,
schematic, and measured console output before connection.

For the Lynx cable, preserve the already established Chipbridge-to-ComLynx
wiring: Lynx ring to the PCB's 3.5 mm ring and sleeve to sleeve, with both tips
unconnected. An ordinary tip-to-tip audio cable must not be used because the
Lynx connector's tip carries +5 V.

Relevant SMSGGDJ source: `src/engine.asm`. The ALYNXDJ byte definitions and
existing RP2040 ComLynx transmitter live in the ALYNXDJ project and should be
rechecked against its then-current revision before implementation.

## Required validation before release

- Confirm the console bit-0 signal, optocoupler output, and GP13 edge stream
  with an oscilloscope or logic analyser.
- Verify the custom input cable's polarity and optocoupler current on both SMS
  and Game Gear hardware before connecting the RP2040.
- Verify one and only one ALYNXDJ row per SMSGGDJ row at slow and fast tempos,
  including uneven grooves and tempo changes.
- Verify first-row alignment after play, restart, and repeated stop/start.
- Characterise the release-to-idle edge and select a documented stop policy.
- Verify ComLynx voltage behaviour, 62,500-baud serial timing, and open-drain
  operation on a real Lynx running ALYNXDJ.
- Perform longer musical tests for accumulated drift, missing edges, duplicate
  rows, cable disturbance, and power cycling in either order.

Until these tests pass, this remains an experiment and should not be included
in normal release claims or the general Chipbridge UF2.
