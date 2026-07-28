#include <stddef.h>
#include <string.h>

#include "pico/unique_id.h"
#include "tusb.h"

static const tusb_desc_device_t device_descriptor = {
    .bLength = sizeof(tusb_desc_device_t),
    .bDescriptorType = TUSB_DESC_DEVICE,
    .bcdUSB = 0x0200,
    .bDeviceClass = 0,
    .bDeviceSubClass = 0,
    .bDeviceProtocol = 0,
    .bMaxPacketSize0 = CFG_TUD_ENDPOINT0_SIZE,
    .idVendor = 0xCAFE,             /* TinyUSB prototype VID */
    .idProduct = 0x4010,
    .bcdDevice = 0x0100,
    .iManufacturer = 1,
    .iProduct = 2,
    .iSerialNumber = 3,
    .bNumConfigurations = 1,
};

const uint8_t *tud_descriptor_device_cb(void)
{
    return (const uint8_t *)&device_descriptor;
}

enum {
    ITF_MIDI_CONTROL,
    ITF_MIDI_STREAMING,
    ITF_COUNT,
};

#define CONFIG_LENGTH (TUD_CONFIG_DESC_LEN + TUD_MIDI_DESC_LEN)

static const uint8_t configuration_descriptor[] = {
    TUD_CONFIG_DESCRIPTOR(1, ITF_COUNT, 0, CONFIG_LENGTH, 0, 100),
    TUD_MIDI_DESCRIPTOR(ITF_MIDI_CONTROL, 0, 0x01, 0x81, 64),
};

const uint8_t *tud_descriptor_configuration_cb(uint8_t index)
{
    (void)index;
    return configuration_descriptor;
}

static const char *const strings[] = {
    NULL,
    "little-scale",
    "SMSGGDJ Sync",
};
static uint16_t string_descriptor[33];

const uint16_t *tud_descriptor_string_cb(uint8_t index, uint16_t language)
{
    char serial[PICO_UNIQUE_BOARD_ID_SIZE_BYTES * 2 + 1];
    const char *text;
    size_t count;
    size_t i;

    (void)language;
    if (index == 0) {
        string_descriptor[0] = (uint16_t)((TUSB_DESC_STRING << 8) | 4);
        string_descriptor[1] = 0x0409;
        return string_descriptor;
    }

    if (index == 3) {
        pico_get_unique_board_id_string(serial, sizeof(serial));
        text = serial;
    } else {
        if (index >= sizeof(strings) / sizeof(strings[0]))
            return NULL;
        text = strings[index];
    }

    count = strlen(text);
    if (count > 32)
        count = 32;
    for (i = 0; i < count; ++i)
        string_descriptor[i + 1] = (uint8_t)text[i];
    string_descriptor[0] = (uint16_t)((TUSB_DESC_STRING << 8)
                                      | (2 * count + 2));
    return string_descriptor;
}
