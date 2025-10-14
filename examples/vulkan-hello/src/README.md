# quickvulkanv1.1 Hello World (Sanity Check)

Minimal C++20 project using CMake to sanity-check Vulkan 1.1 inside the dev container.

## Build

```bash
# from inside the container
cd example/vulkan-hello
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build
