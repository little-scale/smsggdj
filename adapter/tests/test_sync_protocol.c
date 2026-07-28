#include <assert.h>

#include "../src/output_logic.h"
#include "../src/sync_protocol.h"

int main(void)
{
    smsggdj_sync_t sync;

    for (uint8_t counter = 0; counter < 4; ++counter) {
        assert(smsggdj_counter_bit(counter, 0) == (counter & 1u));
        assert(smsggdj_counter_bit(counter, 1) == ((counter >> 1) & 1u));
        assert(smsggdj_npn_gate(counter, 0)
               == (uint8_t)(smsggdj_counter_bit(counter, 0) ^ 1u));
        assert(smsggdj_npn_gate(counter, 1)
               == (uint8_t)(smsggdj_counter_bit(counter, 1) ^ 1u));
    }

    smsggdj_sync_init(&sync);
    assert(sync.counter == 0);
    assert(!sync.running);

    /* Clock is ignored until Start or Continue. */
    assert(!smsggdj_sync_midi_status(&sync, 0xF8));
    assert(sync.counter == 0);

    assert(!smsggdj_sync_midi_status(&sync, 0xFA));
    assert(sync.running);
    assert(smsggdj_sync_midi_status(&sync, 0xF8));
    assert(sync.counter == 1);
    assert(smsggdj_sync_midi_status(&sync, 0xF8));
    assert(smsggdj_sync_midi_status(&sync, 0xF8));
    assert(smsggdj_sync_midi_status(&sync, 0xF8));
    assert(sync.counter == 0);

    assert(smsggdj_sync_midi_status(&sync, 0xF8));
    assert(sync.counter == 1);
    assert(!smsggdj_sync_midi_status(&sync, 0xFC));
    assert(!sync.running);
    assert(!smsggdj_sync_midi_status(&sync, 0xF8));
    assert(sync.counter == 1);

    assert(!smsggdj_sync_midi_status(&sync, 0xFB));
    assert(sync.running);
    assert(smsggdj_sync_midi_status(&sync, 0xF8));
    assert(sync.counter == 2);

    /* Start returns to zero; Reset also stops transport. */
    assert(smsggdj_sync_midi_status(&sync, 0xFA));
    assert(sync.counter == 0);
    assert(sync.running);
    assert(!smsggdj_sync_midi_status(&sync, 0xFF));
    assert(!sync.running);

    return 0;
}
