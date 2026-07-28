#include <stdbool.h>
#include <stdint.h>

#include "bsp/board_api.h"
#include "pico/binary_info.h"
#include "pico/stdlib.h"
#include "tusb.h"

#include "output_logic.h"
#include "sync_protocol.h"

/*
 * These RP2040 GPIO numbers are broken out by both supported boards:
 *
 *   Non-inverted: XIAO D6/D7 = GP0/GP1; Pico physical pins 1/2
 *   NPN/inverted: XIAO D4/D5 = GP6/GP7; Pico physical pins 9/10
 *
 * Both pairs carry the same counter simultaneously. GP6/GP7 compensate for the
 * documented NPN stages; GP0/GP1 are ordinary active-high logic for a
 * non-inverting level translator.
 */
enum {
    PIN_NONINVERTED_BIT0 = 0,
    PIN_NONINVERTED_BIT1 = 1,
    PIN_NPN_BIT0 = 6,
    PIN_NPN_BIT1 = 7,
};

bi_decl(bi_4pins_with_names(
    PIN_NONINVERTED_BIT0, "counter bit 0 (non-inverted)",
    PIN_NONINVERTED_BIT1, "counter bit 1 (non-inverted)",
    PIN_NPN_BIT0, "counter bit 0 (NPN/inverted)",
    PIN_NPN_BIT1, "counter bit 1 (NPN/inverted)"));

static smsggdj_sync_t sync_state;

static void present_counter(uint8_t counter)
{
    gpio_put(PIN_NONINVERTED_BIT0, smsggdj_counter_bit(counter, 0));
    gpio_put(PIN_NONINVERTED_BIT1, smsggdj_counter_bit(counter, 1));
    gpio_put(PIN_NPN_BIT0, smsggdj_npn_gate(counter, 0));
    gpio_put(PIN_NPN_BIT1, smsggdj_npn_gate(counter, 1));
}

static void sync_gpio_init(void)
{
    /* Preload all latches before enabling outputs. At counter 0 the active-high
     * pair is low and the NPN bases are high, making both console lines low. */
    gpio_init(PIN_NONINVERTED_BIT0);
    gpio_init(PIN_NONINVERTED_BIT1);
    gpio_init(PIN_NPN_BIT0);
    gpio_init(PIN_NPN_BIT1);
    gpio_put(PIN_NONINVERTED_BIT0, 0);
    gpio_put(PIN_NONINVERTED_BIT1, 0);
    gpio_put(PIN_NPN_BIT0, 1);
    gpio_put(PIN_NPN_BIT1, 1);
    gpio_set_dir(PIN_NONINVERTED_BIT0, GPIO_OUT);
    gpio_set_dir(PIN_NONINVERTED_BIT1, GPIO_OUT);
    gpio_set_dir(PIN_NPN_BIT0, GPIO_OUT);
    gpio_set_dir(PIN_NPN_BIT1, GPIO_OUT);
    present_counter(sync_state.counter);
}

static void usb_midi_task(void)
{
    while (tud_midi_available()) {
        uint8_t packet[4];
        bool changed = false;

        if (!tud_midi_packet_read(packet))
            break;

        /*
         * Real-time bytes normally arrive as a one-byte USB-MIDI packet (CIN
         * 0xF). Scan all payload slots defensively because hosts may interleave
         * real-time bytes with other MIDI traffic.
         */
        for (unsigned i = 1; i < 4; ++i) {
            if (packet[i] >= 0xF8)
                changed |= smsggdj_sync_midi_status(&sync_state, packet[i]);
        }

        if (changed)
            present_counter(sync_state.counter);
    }
}

void tud_umount_cb(void)
{
    smsggdj_sync_stop(&sync_state);
}

int main(void)
{
    const tusb_rhport_init_t usb = {
        .role = TUSB_ROLE_DEVICE,
        .speed = TUSB_SPEED_FULL,
    };

    board_init();
    smsggdj_sync_init(&sync_state);
    sync_gpio_init();

    TU_ASSERT(tud_rhport_init(BOARD_TUD_RHPORT, &usb));
    board_init_after_tusb();

    while (true) {
        tud_task();
        usb_midi_task();
    }
}
