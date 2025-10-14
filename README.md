# 🚀 quickvulkanv1 --- Vulkan + GLES C++ 20 Dev Container


A self-contained development environment with a full C++ 20 toolchain,
Vulkan & GLES libraries, Android NDK/SDK, PostgreSQL client, and common
debugging/profiling tools.

Designed to be **vendor-neutral** (NVIDIA/Intel/AMD), while defaulting
to LunarG's official SDK for predictable behavior across devices.

**Author:** [Linggawasistha Djohari](https://github.com/lwdjohari)\
**Base Image:** Ubuntu 24.04\
**Default GPU Stack:** LunarG Vulkan SDK 1.3.296.0 (compatible with
Vulkan 1.1)\
**Purpose:** Cross-platform engine development for PC 🖥️ / Android 📱 /
iOS ( MoltenVK )



## 🧱 Contents / Toolchain Matrix


**Category Tools / Packages**


**C++ Toolchain** clang / clang++ / lld / lldb / gcc / g++ /
 cmake / ninja / make / pkg-config / ccache /
 binutils

**Debug & Profile** gdb / lldb / valgrind / strace / ltrace /
 pahole (dwarves) / addr2line /
 llvm-symbolizer

**Vulkan & GLES Stack** vulkaninfo / glslangValidator / glslc /
 spirv-as / spirv-val / spirv-opt /
 spirv-cross / apitrace / gfxreconstruct /
 es2_info / glxinfo

**Android SDK & NDK** sdkmanager / adb / aapt / aapt2 / ndk-build
 / platform-tools / NDK r26c / API 34
 (build-tools 34.0.0)

**DB & Networking** PostgreSQL client v17 / sqlite3 / openssl /
 curl / wget / rsync / ssh / netcat /
 traceroute

**Compression & System** gzip / bzip2 / xz / brotli / zip / unzip /
 tar

**Editors & CLI Utils** git / git-lfs / nano / vim / less / htop /
 tree / ripgrep (rg) / fd (fd-find) / file

**Extras** openssh-server (for remote attach), gnupg /
 pinentry, PostgreSQL PGDG repo support



## 🧩 Container Structure

```
/workspace             →  your mounted project
/root/.ssh             →  root’s SSH keys (mapped volume)
/home/<USER>/.ssh      →  user SSH keys
/opt/vulkan-sdk        →  LunarG Vulkan SDK (x86_64)
/opt/android-sdk       →  Android SDK (cmdline-tools, build-tools, platforms)
/opt/android-ndk       →  Android NDK (r26c)
/opt/cache/ccache      →  shared ccache directory
```

---

## ⚙️ Build and Run

### 1️⃣ Build container

```bash
docker compose build quickvulkanv1
```

You can override versions **without editing any file**:

```bash
export VULKAN_SDK_VERSION=1.3.300.0
export ANDROID_PLATFORM=android-35
export ANDROID_BUILD_TOOLS=35.0.0
docker compose build --no-cache quickvulkanv1
```

### 2️⃣ Start container

```bash
docker compose up -d
```

### 3️⃣ Connect via SSH

```bash
ssh -p 7000 YOUR_USER@localhost
```

Default behavior (matches your template): - `root` SSH enabled (22 →
7000 on host) - User auto-created with sudo NOPASSWD - Workspace
ownership auto-taken by USER


## 🖥️ Host Preparation ( Ubuntu 22.04 / 24.04 )

### 🔧 Common for All GPUs

```bash
# allow performance tools (valgrind/perf)
sudo sysctl -w kernel.perf_event_paranoid=1
sudo sysctl -w kernel.kptr_restrict=0

# allow containerized X11 apps (optional)
xhost +si:localuser:$(whoami)
```


### 💠 NVIDIA (RTX Series / GTX / Quadro)

1. Install latest NVIDIA driver for your GPU.
2. Install **nvidia-container-toolkit** so Docker can pass the GPU:

```bash
sudo apt install -y nvidia-container-toolkit
sudo systemctl restart docker
```

3. Enable GPU support in `docker-compose.yml`:

```yaml
services:
  quickvulkanv1:
    gpus: all
```

4. No driver installation inside container --- host handles it.
5. Optional: use Nsight Systems or RenderDoc on host for capture.

---

### 🟢 Intel (Arc / Iris Xe / UHD)

1. Ensure Mesa drivers are installed:

```bash
sudo apt install -y mesa-vulkan-drivers mesa-utils
```

2. Expose DRI device to container:

```yaml
devices:
  - /dev/dri:/dev/dri
```

3. To test:

```bash
vulkaninfo | grep "driverName"
```


### 🔴 AMD (RDNA / Vega / Radeon)

1. Install Mesa RADV drivers:

```bash
sudo apt install -y mesa-vulkan-drivers mesa-utils
```

2. Expose DRI device (similar to Intel).\
3. Confirm GPU detected with `vulkaninfo`.


## 🪜 Typical Workflow

```bash
# 1. attach via ssh
ssh -p 7000 YOUR_USER@localhost

# 2. check environment
devinfo

# 3. build project
cmake -S . -B build -G Ninja
cmake --build build

# 4. run Vulkan sample
./build/bin/app_demo

# 5. run Android build
ndk-build
```


## 📦 Default Ports & Volumes


**Purpose Host → Container Description**


SSH 7000 → 22 root + user login

App Ports 7001 -- 7010 testing/game servers

Workspace `/mnt/data/dev-volumes/quickvulkanv1/workspace` project files

CCache `/mnt/data/dev-volumes/quickvulkanv1/ccache` compiler cache
 (shared)



## 🧰 Quick Commands

**Action Command**


Show toolchain `devinfo` \
 Rebuild image `docker compose build --no-cache quickvulkanv1` \
 Stop container `docker compose down` \
 Follow logs `docker logs -f quickvulkanv1` \
 Re-enter `docker exec -it quickvulkanv1 bash` \


## 🔄 Version Overrides

**Variable Default Example Override**


`VULKAN_SDK_VERSION` 1.3.296.0 1.3.300.0 \
 `USE_DISTRO_VULKAN` false true \
 `ANDROID_SDK_VERSION` 11076708_latest 11076709_latest \
 `ANDROID_PLATFORM` android-34 android-35 \
 `ANDROID_BUILD_TOOLS` 34.0.0 35.0.0 \
 `ANDROID_NDK_VERSION` r26c r27b \


## 🩺 Troubleshooting


**Symptom Cause / Fix**



`vulkaninfo` fails check `/dev/dri` mount or `--gpus all`
 enabled

Cannot run GUI tools missing `xhost +` or Wayland socket
 (RenderDoc) mount

Android build fails confirm SDK/NDK versions in `devinfo`

SSH denied for user verify `CREATE_USER=true` and password
 set

Vulkan validation not working ensure LunarG SDK path in `VULKAN_SDK`


## 🧠 Tips for Developers

- Use `ccache` shared volume to speed up rebuilds.
- For GPU tracing: `apitrace trace ./app_demo` then
  `apitrace retrace`.
- `gfxreconstruct` is installed for low-level replay captures.
- `valgrind --tool=memcheck` works out of the box.
- Use `lldb` or `gdb` remote attach from VS Code / CLion via SSH.


## 🧭 License & Credits

- [LunarG Vulkan SDK](https://vulkan.lunarg.com/sdk/home)
- [Android NDK / SDK Tools](https://developer.android.com/ndk)
- Ubuntu 24.04 Base Image --- Canonical


