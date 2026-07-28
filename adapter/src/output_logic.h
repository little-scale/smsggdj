#ifndef SMSGGDJ_OUTPUT_LOGIC_H
#define SMSGGDJ_OUTPUT_LOGIC_H

#include <stdint.h>

static inline uint8_t smsggdj_counter_bit(uint8_t counter, unsigned bit)
{
    return (uint8_t)((counter >> bit) & 1u);
}

static inline uint8_t smsggdj_npn_gate(uint8_t counter, unsigned bit)
{
    return (uint8_t)(smsggdj_counter_bit(counter, bit) ^ 1u);
}

#endif
