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
      ca-certificates apt-transport-https gnupg curl wget unzip zip rsync \
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
      clang lld lldb gdb \
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

# -------------------------------------------------------------------
# Vulkan stack
#   USE_DISTRO_VULKAN=false -> LunarG SDK (default, pinned)
#   USE_DISTRO_VULKAN=true  -> Ubuntu packages
# -------------------------------------------------------------------
ARG USE_DISTRO_VULKAN=${USE_DISTRO_VULKAN:-false}
ARG VULKAN_SDK_VERSION=${VULKAN_SDK_VERSION:-1.3.296.0}

ENV VULKAN_SDK=/opt/vulkan-sdk/x86_64
ENV PATH=/opt/vulkan-sdk/x86_64/bin:$PATH
ENV LD_LIBRARY_PATH=/opt/vulkan-sdk/x86_64/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

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
    mkdir -p /opt && cd /opt; \
    wget -q "https://sdk.lunarg.com/sdk/download/${VULKAN_SDK_VERSION}/linux/vulkan-sdk.tar.gz" -O /tmp/vksdk.tgz; \
    mkdir -p /opt/vulkan-sdk && tar -xzf /tmp/vksdk.tgz -C /opt/vulkan-sdk --strip-components=1; \
    rm -f /tmp/vksdk.tgz; \
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

WORKDIR /workspace
VOLUME ["/workspace", "/root/.ssh", "/opt/cache/ccache"]

EXPOSE 22
EXPOSE 7001-7010

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
