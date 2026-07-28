cmake_minimum_required(VERSION 3.13)

list(APPEND PICO_BOARD_HEADER_DIRS "${CMAKE_CURRENT_LIST_DIR}/boards")
include(pico_sdk_import.cmake)

project(smsggdj_sync_rp2040 C CXX ASM)
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

pico_sdk_init()

add_executable(smsggdj_sync_rp2040
    src/main.c
    src/sync_protocol.c
    src/usb_descriptors.c
)

target_include_directories(smsggdj_sync_rp2040 PRIVATE src)

target_link_libraries(smsggdj_sync_rp2040 PRIVATE
    pico_stdlib
    pico_unique_id
    tinyusb_device
    tinyusb_board
)

pico_enable_stdio_usb(smsggdj_sync_rp2040 0)
pico_enable_stdio_uart(smsggdj_sync_rp2040 0)
pico_add_extra_outputs(smsggdj_sync_rp2040)
