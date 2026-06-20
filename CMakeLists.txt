cmake_minimum_required(VERSION 3.19)
project(lite-xl-web C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(LXL_WEB_BUILD_TESTS "Build native module load tests" ON)
if(LXL_WEB_BUILD_TESTS)
  enable_testing()
endif()

set(LITE_XL_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../lite-xl/resources/include"
    CACHE PATH "Lite XL plugin API include directory")
if(NOT EXISTS "${LITE_XL_INCLUDE_DIR}/lite_xl_plugin_api.h")
  message(FATAL_ERROR
    "lite_xl_plugin_api.h not found. Set -DLITE_XL_INCLUDE_DIR=/path/to/lite-xl/resources/include")
endif()

if(APPLE)
  enable_language(OBJC)
  set(WEB_LXL_SOURCES src/lxl_web_macos.m)
else()
  set(WEB_LXL_SOURCES src/lxl_web_stub.c)
endif()

add_library(web_lxl MODULE ${WEB_LXL_SOURCES})
set_target_properties(web_lxl PROPERTIES
  PREFIX ""
  OUTPUT_NAME "init"
)
if(APPLE)
  set_target_properties(web_lxl PROPERTIES SUFFIX ".lib")
  target_compile_options(web_lxl PRIVATE -fobjc-arc)
  target_link_libraries(web_lxl PRIVATE "-framework Cocoa" "-framework WebKit")
else()
  set_target_properties(web_lxl PROPERTIES SUFFIX ".so")
endif()

target_include_directories(web_lxl PRIVATE "${LITE_XL_INCLUDE_DIR}")

add_custom_command(TARGET web_lxl POST_BUILD
  COMMAND "${CMAKE_COMMAND}" -E make_directory
          "${CMAKE_CURRENT_SOURCE_DIR}/libraries/web_lxl"
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
          "$<TARGET_FILE:web_lxl>"
          "${CMAKE_CURRENT_SOURCE_DIR}/libraries/web_lxl/$<TARGET_FILE_NAME:web_lxl>")


if(LXL_WEB_BUILD_TESTS AND UNIX)
  add_executable(test_dlopen tests/test_dlopen.c)
  target_link_libraries(test_dlopen PRIVATE ${CMAKE_DL_LIBS})
  add_test(NAME native_module_load COMMAND test_dlopen "$<TARGET_FILE:web_lxl>")
endif()
