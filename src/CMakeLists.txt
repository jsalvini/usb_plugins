# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(usb_plugins_library VERSION 0.0.1 LANGUAGES C)

add_library(usb_plugins SHARED
  "usb_plugins.c"
)

set_target_properties(usb_plugins PROPERTIES
  PUBLIC_HEADER libusb.h
  OUTPUT_NAME "usb_plugins"
)

set_target_properties(usb_plugins PROPERTIES LINKER_LANGUAGE C)


if (WIN32)
set_target_properties(usb_plugins PROPERTIES
  WINDOWS_EXPORT_ALL_SYMBOLS ON
)
endif (WIN32)

target_compile_definitions(usb_plugins PUBLIC DART_SHARED_LIB)

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(usb_plugins PRIVATE "-Wl,-z,max-page-size=16384")
endif()
