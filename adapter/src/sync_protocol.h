#ifndef SMSGGDJ_SYNC_PROTOCOL_H
#define SMSGGDJ_SYNC_PROTOCOL_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    uint8_t counter;
    bool running;
} smsggdj_sync_t;

void smsggdj_sync_init(smsggdj_sync_t *sync);

/*
 * Consume one MIDI System Real-Time status byte.
 *
 * Returns true when the 2-bit output counter changed and therefore needs to be
 * presented on the GPIO lines. Unsupported statuses are ignored.
 */
bool smsggdj_sync_midi_status(smsggdj_sync_t *sync, uint8_t status);

void smsggdj_sync_stop(smsggdj_sync_t *sync);

#endif
