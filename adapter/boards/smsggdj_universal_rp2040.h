/*
 * Board definition shared by the Seeed XIAO RP2040 and Raspberry Pi Pico.
 *
 * It intentionally declares no LED, SMPS-mode, VBUS-sense, UART, I2C, or SPI
 * pins: those carrier-board assignments differ. The firmware uses only GP0,
 * GP1, GP6, GP7, USB, and the common 2 MB flash geometry.
 */

#ifndef _BOARDS_SMSGGDJ_UNIVERSAL_RP2040_H
#define _BOARDS_SMSGGDJ_UNIVERSAL_RP2040_H

pico_board_cmake_set(PICO_PLATFORM, rp2040)

#define SMSGGDJ_UNIVERSAL_RP2040

/* Seeed specifies this longer delay for some XIAO RP2040 oscillator samples.
 * It is harmless on a Pico and makes one image reliable on both carriers. */
#ifndef PICO_XOSC_STARTUP_DELAY_MULTIPLIER
#define PICO_XOSC_STARTUP_DELAY_MULTIPLIER 64
#endif

#define PICO_BOOT_STAGE2_CHOOSE_W25Q080 1

#ifndef PICO_FLASH_SPI_CLKDIV
#define PICO_FLASH_SPI_CLKDIV 2
#endif

pico_board_cmake_set_default(PICO_FLASH_SIZE_BYTES, (2 * 1024 * 1024))
#ifndef PICO_FLASH_SIZE_BYTES
#define PICO_FLASH_SIZE_BYTES (2 * 1024 * 1024)
#endif

/* Keep compatibility with early RP2040 silicon found on some original Picos;
 * the XIAO uses B1, so enabling B0 support does not cost carrier compatibility. */
#ifndef PICO_RP2040_B0_SUPPORTED
#define PICO_RP2040_B0_SUPPORTED 1
#endif

#endif
