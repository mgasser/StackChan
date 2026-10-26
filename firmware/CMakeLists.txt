# The following five lines of boilerplate have to be in your project's
# CMakeLists in this exact order for cmake to work correctly
cmake_minimum_required(VERSION 3.16)

set(PROJECT_VER "1.6.0")
# A build may carry its own version (build_duplex.sh: 1.6.0.<yymmdd>.<hhmm>), so the
# robot can tell a newer image apart in an OTA answer. Dot-separated numbers only.
if(DEFINED ENV{STACKCHAN_FW_VERSION} AND NOT "$ENV{STACKCHAN_FW_VERSION}" STREQUAL "")
    if(NOT "$ENV{STACKCHAN_FW_VERSION}" MATCHES "^[0-9]+(\\.[0-9]+)*$")
        message(FATAL_ERROR "STACKCHAN_FW_VERSION must be numbers and dots, got '$ENV{STACKCHAN_FW_VERSION}'")
    endif()
    set(PROJECT_VER "$ENV{STACKCHAN_FW_VERSION}")
endif()
add_definitions(-DFIRMWARE_VERSION=\"${PROJECT_VER}\")

# Add this line to disable the specific warning
add_compile_options(-Wno-missing-field-initializers)

# Overlays on top of sdkconfig.defaults:
#  - a build variant, STACKCHAN_VARIANT=<name> → sdkconfig.defaults.<name>
#    (build_duplex.sh: "duplex", the full-duplex test build for one robot);
#  - a local overlay (git-ignored) when present. Lets self-hosted / custom
#    deployments pin CONFIG_STACKCHAN_SERVER_URL, CONFIG_OTA_URL, etc. without
#    touching committed defaults.
# Manual equivalent: SDKCONFIG_DEFAULTS="sdkconfig.defaults;sdkconfig.defaults.local" idf.py build
set(_stackchan_defaults "${CMAKE_CURRENT_SOURCE_DIR}/sdkconfig.defaults")
if(DEFINED ENV{STACKCHAN_VARIANT} AND NOT "$ENV{STACKCHAN_VARIANT}" STREQUAL "")
    set(_stackchan_variant "${CMAKE_CURRENT_SOURCE_DIR}/sdkconfig.defaults.$ENV{STACKCHAN_VARIANT}")
    if(NOT EXISTS "${_stackchan_variant}")
        message(FATAL_ERROR "StackChan: no ${_stackchan_variant} for STACKCHAN_VARIANT=$ENV{STACKCHAN_VARIANT}")
    endif()
    list(APPEND _stackchan_defaults "${_stackchan_variant}")
    message(STATUS "StackChan: build variant $ENV{STACKCHAN_VARIANT}")
endif()
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/sdkconfig.defaults.local")
    list(APPEND _stackchan_defaults "${CMAKE_CURRENT_SOURCE_DIR}/sdkconfig.defaults.local")
    message(STATUS "StackChan: detected sdkconfig.defaults.local, applying overlay")
endif()
# Generated overlays (build_duplex.sh writes the OTA URL into one), ';'-separated paths.
if(DEFINED ENV{STACKCHAN_EXTRA_DEFAULTS} AND NOT "$ENV{STACKCHAN_EXTRA_DEFAULTS}" STREQUAL "")
    list(APPEND _stackchan_defaults $ENV{STACKCHAN_EXTRA_DEFAULTS})
endif()
list(LENGTH _stackchan_defaults _stackchan_defaults_count)
if(_stackchan_defaults_count GREATER 1)
    set(SDKCONFIG_DEFAULTS "${_stackchan_defaults}"
        CACHE STRING "ESP-IDF sdkconfig default files (base + variant + local overlay)" FORCE)
endif()

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(stack-chan)
