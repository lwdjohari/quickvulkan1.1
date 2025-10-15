# syntax=docker/dockerfile:1.7
FROM ubuntu:24.04

# -------------------------------------------------------------------
# quickvulkanv1 — Vulkan (LunarG default) + GLES C++20 Dev Container
# Default: LunarG Vulkan SDK 1.3.296.0 (cross-platform parity)
# Optional: use distro Vulkan via --build-arg USE_DISTRO_VULKAN=true
# Target API at runtime is Vulkan 1.1 (set by your app's VkApplicationInfo)
# -------------------------------------------------------------------

ENV DEBIAN_FRONTEND=noninteractive TZ=UTC

# Base prerequisites + apt hygiene
RUN apt-get update && apt-get install -y --no-install-recommends \
      sudo bash ca-certificates apt-transport-https gnupg curl wget unzip zip rsync \
      software-properties-common \
    && rm -rf /var/lib/apt/lists/*

# PostgreSQL 17 client (PGDG)
RUN set -eux; \
    . /etc/os-release; \
    echo "deb https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list; \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -; \
    apt-get update && apt-get install -y --no-install-recommends postgresql-client-17 \
    && rm -rf /var/lib/apt/lists/*

# -------------------------------------------------------------------
# Core toolchain, editors, compression, networking utils + Java 17
# -------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
      # compilers / build
      build-essential gcc g++ llvm clang lld lldb gdb \
      cmake ninja-build pkg-config make \
      # VCS / scripting
      git git-lfs gnupg python3 python3-pip \
      # caches / binutils / misc
      ccache binutils dwarves file \
      # editors / cli utils
      nano vim less htop tree ripgrep fd-find \
      # compression / archive
      gzip bzip2 xz-utils brotli tar unzip zip \
      # networking
      openssh-client curl wget rsync \
      netcat-traditional iputils-ping traceroute \
      # crypto / db libs
      libssl-dev zlib1g-dev \
      sqlite3 libsqlite3-dev \
      # Java 17 for Android/Gradle
      openjdk-17-jdk \
    && rm -rf /var/lib/apt/lists/*

# Set JAVA_HOME (Ubuntu path) and prepend to PATH
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH="$JAVA_HOME/bin:$PATH"

# -------------------------------------------------------------------
# GLES/EGL + X/Wayland dev libs (vendor-neutral) — Ubuntu 24.04 names
# -------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
      libgles2 libgles2-mesa-dev \
      libegl1 libegl1-mesa-dev \
      libgbm1 libgbm-dev \
      mesa-utils \
      libx11-dev libxrandr-dev libxi-dev libxinerama-dev libxcursor-dev \
      libwayland-client0 libwayland-dev \
    && rm -rf /var/lib/apt/lists/*


# ---------------- Vulkan stack ----------------
# USE_DISTRO_VULKAN=false -> LunarG SDK (default)
# USE_DISTRO_VULKAN=true  -> Ubuntu packages
# -----------------------------------------------
ARG USE_DISTRO_VULKAN=${USE_DISTRO_VULKAN:-false}
ARG VULKAN_SDK_VERSION=${VULKAN_SDK_VERSION:-1.3.296.0}

ENV VULKAN_SDK=/opt/vulkan-sdk/x86_64 \
    PATH=/opt/vulkan-sdk/x86_64/bin:$PATH \
    LD_LIBRARY_PATH=/opt/vulkan-sdk/x86_64/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

RUN set -eux; \
  if [ "${USE_DISTRO_VULKAN}" = "true" ]; then \
    echo ">>> Installing distro Vulkan packages"; \
    apt-get update && apt-get install -y --no-install-recommends \
      libvulkan1 vulkan-tools vulkan-validationlayers-dev \
      glslang-tools shaderc spirv-tools spirv-cross apitrace gfxreconstruct \
    && rm -rf /var/lib/apt/lists/*; \
    sed -i '/VULKAN_SDK/d' /etc/profile.d/*.sh 2>/dev/null || true; \
  else \
    echo ">>> Installing LunarG Vulkan SDK (${VULKAN_SDK_VERSION})"; \
    SDK_URL="https://sdk.lunarg.com/sdk/download/${VULKAN_SDK_VERSION}/linux/vulkansdk-linux-x86_64-${VULKAN_SDK_VERSION}.tar.xz"; \
    curl -fsSL -o /tmp/vksdk.tar.xz "$SDK_URL"; \
    # Sanity: ensure we really fetched an xz archive
    file /tmp/vksdk.tar.xz | grep -qi 'XZ compressed' || { \
      echo "Downloaded file is not an .xz archive. URL may have changed: $SDK_URL"; \
      exit 1; \
    }; \
    mkdir -p /opt/vulkan-sdk; \
    tar -xJf /tmp/vksdk.tar.xz -C /opt/vulkan-sdk --strip-components=1; \
    rm -f /tmp/vksdk.tar.xz; \
    printf 'export VULKAN_SDK=/opt/vulkan-sdk/x86_64\nexport PATH=$VULKAN_SDK/bin:$PATH\nexport LD_LIBRARY_PATH=$VULKAN_SDK/lib:$LD_LIBRARY_PATH\n' \
      > /etc/profile.d/10-vulkan-sdk.sh; \
  fi

# -------------------------------------------------------------------
# Debug/profiling tools
# -------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
      valgrind linux-tools-generic strace ltrace apitrace gfxreconstruct \
    && rm -rf /var/lib/apt/lists/*

# -------------------------------------------------------------------
# Android SDK / NDK (uses Java 17 set above)
# -------------------------------------------------------------------
ARG ANDROID_SDK_VERSION=${ANDROID_SDK_VERSION:-11076708_latest}  # cmdline-tools r12+
ARG ANDROID_PLATFORM=${ANDROID_PLATFORM:-android-34}
ARG ANDROID_BUILD_TOOLS=${ANDROID_BUILD_TOOLS:-34.0.0}
ARG ANDROID_NDK_VERSION=${ANDROID_NDK_VERSION:-r26c}

ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_NDK_ROOT=/opt/android-ndk
ENV PATH=/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:/opt/android-ndk:$PATH

RUN set -eux; \
    mkdir -p /opt/android-sdk/cmdline-tools; \
    cd /tmp; \
    wget -q "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_SDK_VERSION}.zip" -O cmdtools.zip; \
    unzip -q cmdtools.zip -d /opt/android-sdk/cmdline-tools; \
    mv /opt/android-sdk/cmdline-tools/cmdline-tools /opt/android-sdk/cmdline-tools/latest; \
    rm -f cmdtools.zip; \
    yes | sdkmanager --licenses >/dev/null || true; \
    sdkmanager --install "platform-tools" "build-tools;${ANDROID_BUILD_TOOLS}" "platforms;${ANDROID_PLATFORM}"; \
    cd /tmp; \
    wget -q "https://dl.google.com/android/repository/android-ndk-${ANDROID_NDK_VERSION}-linux.zip" -O ndk.zip; \
    unzip -q ndk.zip -d /opt; \
    rm -f ndk.zip; \
    ln -s /opt/android-ndk-${ANDROID_NDK_VERSION} /opt/android-ndk

    
# -------------------------------------------------------------------
# OpenSSH server (behavior per your template via entrypoint env)
# -------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /run/sshd \
 && sed -ri 's/^#?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config \
 && sed -ri 's/^#?PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config \
 && printf '%s\n' 'ClientAliveInterval 60' 'ClientAliveCountMax 3' >> /etc/ssh/sshd_config

# -------------------------------------------------------------------
# Workspace, ccache, sanity
# -------------------------------------------------------------------
ENV CCACHE_DIR=/opt/cache/ccache
RUN mkdir -p /workspace /opt/cache/ccache && chmod -R 0777 /opt/cache/ccache

RUN (command -v vulkaninfo >/dev/null 2>&1 && vulkaninfo --summary || true) \
 && (command -v glslangValidator >/dev/null 2>&1 && glslangValidator --version || true) \
 && (command -v spirv-val >/dev/null 2>&1 && spirv-val --version || true) \
 && (command -v es2_info >/dev/null 2>&1 && es2_info || true) \
 && cmake --version || true && ninja --version || true \
 && clang --version || true && gdb --version || true && psql --version || true \
 && java -version || true && javac -version || true

# -------------------------------------------------------------------
# Entrypoint + profiles (SSH/user behavior preserved)
# -------------------------------------------------------------------
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh && chmod +x /usr/local/bin/entrypoint.sh

COPY .bashrc.dev /etc/skel/.bashrc
COPY .bash_profile.dev /etc/skel/.bash_profile
COPY .bashrc.dev /root/.bashrc
COPY .bash_profile.dev /root/.bash_profile

# --- Android environment loader (SDK flat + NDK flat, dynamic build-tools) ---
RUN mkdir -p /etc/profile.d && \
  cat >/etc/profile.d/20-android-sdk.sh <<'EOF' && \
  chmod 0644 /etc/profile.d/20-android-sdk.sh

# 20-android-sdk.sh — unified Android env loader (SDK + flat NDK)
# Honors overrides from the environment/compose; otherwise uses sensible defaults.

# Roots (can be overridden via env)
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-/opt/android-sdk}"
export ANDROID_HOME="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-/opt/android-ndk}"   # flat NDK (ndk-build at root)

# Helper: prepend to PATH if the directory exists and isn't already present
_path_add() {
  [ -d "$1" ] || return 0
  case ":$PATH:" in *":$1:"*) ;; *) PATH="$1:$PATH";; esac
}

# --- JAVA_HOME (best effort; JDK 17 on Ubuntu) ---
if [ -z "${JAVA_HOME:-}" ]; then
  if [ -d /usr/lib/jvm/java-17-openjdk-amd64 ]; then
    export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
  elif command -v update-alternatives >/dev/null 2>&1; then
    jhome="$(update-alternatives --list java 2>/dev/null | sed 's:/bin/java::' | head -n1)"
    [ -n "$jhome" ] && export JAVA_HOME="$jhome"
  fi
fi

# --- cmdline-tools (prefer 'latest', else highest numeric) ---
if [ -d "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin" ]; then
  _path_add "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin"
else
  _ct="$(ls -1 "$ANDROID_SDK_ROOT/cmdline-tools" 2>/dev/null | grep -v '^latest$' | sort -V | tail -n1)"
  [ -n "$_ct" ] && _path_add "$ANDROID_SDK_ROOT/cmdline-tools/$_ct/bin"
fi

# --- platform-tools (adb/fastboot) ---
_path_add "$ANDROID_SDK_ROOT/platform-tools"

# --- build-tools (aapt/aapt2/zipalign/apksigner) ---
if [ -d "$ANDROID_SDK_ROOT/build-tools" ]; then
  if [ -n "${ANDROID_BUILD_TOOLS:-}" ] && [ -d "$ANDROID_SDK_ROOT/build-tools/$ANDROID_BUILD_TOOLS" ]; then
    _bt="$ANDROID_BUILD_TOOLS"
  else
    _bt="$(ls -1 "$ANDROID_SDK_ROOT/build-tools" 2>/dev/null | sort -V | tail -n1)"
  fi
  if [ -n "$_bt" ] && [ -d "$ANDROID_SDK_ROOT/build-tools/$_bt" ]; then
    export ANDROID_BUILD_TOOLS="$_bt"
    export ANDROID_BUILD_TOOLS_BIN="$ANDROID_SDK_ROOT/build-tools/$_bt"
    _path_add "$ANDROID_BUILD_TOOLS_BIN"
  fi
fi

# --- emulator tools ---
_path_add "$ANDROID_SDK_ROOT/emulator"

# --- NDK (flat layout) ---
# Add root (for ndk-build) and LLVM toolchains bin if present
if [ -d "$ANDROID_NDK_HOME" ]; then
  _path_add "$ANDROID_NDK_HOME"
  # Typical LLVM toolchains path on Linux:
  if [ -d "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin" ]; then
    _path_add "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
  fi
fi

export PATH
EOF


# --- ccache profile (so CCACHE_DIR shows up for all shells) ---
RUN printf '%s\n' \
'export CCACHE_DIR=${CCACHE_DIR:-/opt/cache/ccache}' \
'export PATH="/usr/lib/ccache:$PATH"' \
> /etc/profile.d/30-ccache.sh && chmod 0644 /etc/profile.d/30-ccache.sh

WORKDIR /workspace
VOLUME ["/workspace", "/root/.ssh", "/opt/cache/ccache"]

EXPOSE 22
EXPOSE 7001-7010

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
