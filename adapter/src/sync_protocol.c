#include "sync_protocol.h"

enum {
    MIDI_TIMING_CLOCK = 0xF8,
    MIDI_START = 0xFA,
    MIDI_CONTINUE = 0xFB,
    MIDI_STOP = 0xFC,
    MIDI_SYSTEM_RESET = 0xFF,
};

void smsggdj_sync_init(smsggdj_sync_t *sync)
{
    sync->counter = 0;
    sync->running = false;
}

bool smsggdj_sync_midi_status(smsggdj_sync_t *sync, uint8_t status)
{
    uint8_t previous = sync->counter;

    switch (status) {
    case MIDI_TIMING_CLOCK:
        if (sync->running)
            sync->counter = (uint8_t)((sync->counter + 1u) & 3u);
        break;
    case MIDI_START:
        sync->counter = 0;
        sync->running = true;
        break;
    case MIDI_CONTINUE:
        sync->running = true;
        break;
    case MIDI_STOP:
        sync->running = false;
        break;
    case MIDI_SYSTEM_RESET:
        sync->counter = 0;
        sync->running = false;
        break;
    default:
        break;
    }

    return previous != sync->counter;
}

void smsggdj_sync_stop(smsggdj_sync_t *sync)
{
    sync->running = false;
}
