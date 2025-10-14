cmake_minimum_required(VERSION 3.20)
project(vulkan-hello LANGUAGES CXX)

option(ENABLE_ASAN "Enable AddressSanitizer for Debug builds" ON)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Prefer Ninja if available
if(NOT CMAKE_GENERATOR)
  find_program(NINJA_EXE NAMES ninja ninja-build)
  if(NINJA_EXE)
    set(CMAKE_GENERATOR "Ninja" CACHE INTERNAL "" FORCE)
  endif()
endif()

find_package(Vulkan REQUIRED)

add_executable(vulkan-hello src/main.cc)
target_link_libraries(vulkan-hello PRIVATE Vulkan::Vulkan)

if (MSVC)
  target_compile_options(vulkan-hello PRIVATE /W4 /permissive-)
else()
  target_compile_options(vulkan-hello PRIVATE -Wall -Wextra -Wpedantic)
endif()

if (ENABLE_ASAN AND CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU" AND CMAKE_BUILD_TYPE STREQUAL "Debug")
  target_compile_options(vulkan-hello PRIVATE -fsanitize=address -fno-omit-frame-pointer)
  target_link_options(vulkan-hello PRIVATE -fsanitize=address)
endif()

set_target_properties(vulkan-hello PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)
