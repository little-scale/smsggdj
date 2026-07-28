# Locate a Pico SDK supplied by the caller or checked out locally. Keeping the
# SDK outside this repository lets release builds pin it in CI without vendoring
# the SDK and its submodules here.
if (DEFINED ENV{PICO_SDK_PATH} AND (NOT PICO_SDK_PATH))
    set(PICO_SDK_PATH $ENV{PICO_SDK_PATH})
endif()

if (NOT PICO_SDK_PATH)
    set(PICO_SDK_PATH "${CMAKE_CURRENT_LIST_DIR}/lib/pico-sdk")
endif()

if (NOT EXISTS "${PICO_SDK_PATH}/external/pico_sdk_import.cmake")
    message(FATAL_ERROR
        "Pico SDK not found. Set PICO_SDK_PATH or clone pico-sdk (with "
        "submodules) to adapter/lib/pico-sdk.")
endif()

include("${PICO_SDK_PATH}/external/pico_sdk_import.cmake")
