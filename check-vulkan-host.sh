#!/usr/bin/env bash
set -euo pipefail

# check-vulkan-host.sh — Verify host is ready for Vulkan GUI in Docker (Wayland/X11)
# Usage:
#   ./check-vulkan-host.sh           # just check
#   ./check-vulkan-host.sh --fix     # also run safe fixes (xhost +local:docker)

ok()   { printf "\033[32m✔\033[0m %s\n" "$*"; }
warn() { printf "\033[33m⚠\033[0m %s\n" "$*"; }
err()  { printf "\033[31m✘\033[0m %s\n" "$*"; }

HAS_FIX=false
[[ "${1:-}" == "--fix" ]] && HAS_FIX=true

# ---------- Basic tools ----------
need=( bash id lspci grep awk sed xhost )
for c in "${need[@]}"; do
  if ! command -v "$c" >/dev/null 2>&1; then
    err "Missing tool: $c"
    MISSING=true
  fi
done
[[ "${MISSING:-}" == "true" ]] && { err "Install missing tools and re-run."; exit 1; }

# ---------- Docker Access ----------
if docker info >/dev/null 2>&1; then
  ok "Docker accessible without sudo"
  DOCKER="docker"
else
  warn "Docker requires sudo privileges"
  if sudo -n docker info >/dev/null 2>&1; then
    ok "Docker usable with sudo (passwordless)"
    DOCKER="sudo docker"
  else
    warn "Prompting for sudo access to test Docker"
    if sudo docker info >/dev/null 2>&1; then
      ok "Docker usable with sudo"
      DOCKER="sudo docker"
    else
      err "Cannot access Docker even with sudo — fix group membership or permissions."
      echo "   → Run: sudo usermod -aG docker \$USER && newgrp docker"
      exit 1
    fi
  fi
fi

# ---------- GPU Detection ----------
gpu="unknown"
if lspci | grep -qi nvidia; then
  gpu="nvidia"
elif lspci | grep -qiE 'amd|ati'; then
  gpu="amd"
elif lspci | grep -qi intel; then
  gpu="intel"
fi
ok "Detected GPU: $gpu"

# ---------- Vulkan on host ----------
if command -v vulkaninfo >/dev/null 2>&1; then
  if vulkaninfo >/dev/null 2>&1; then
    ok "Host Vulkan works (vulkaninfo succeeded)"
  else
    err "Host Vulkan driver seems broken (vulkaninfo failed)"
    exit 1
  fi
else
  warn "vulkan-tools not installed (sudo apt install -y vulkan-tools libvulkan1)"
fi

# ---------- NVIDIA Specific ----------
if [[ "$gpu" == "nvidia" ]]; then
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    ok "nvidia-smi OK"
  else
    err "nvidia-smi failed — driver missing or not loaded"
    exit 1
  fi

  if command -v nvidia-ctk >/dev/null 2>&1 || command -v nvidia-container-toolkit >/dev/null 2>&1; then
    ok "NVIDIA container toolkit installed"
  else
    err "nvidia-container-toolkit not found"
    echo "→ Install: sudo apt install -y nvidia-container-toolkit && sudo systemctl restart docker"
    exit 1
  fi

  if ! $DOCKER info 2>/dev/null | grep -q 'Runtimes:.*nvidia'; then
    warn "Docker runtime may not list NVIDIA"
    echo "Try: sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker"
  else
    ok "Docker runtime lists NVIDIA"
  fi
fi

# ---------- Wayland/X11 sockets ----------
UIDNUM="$(id -u)"
XSOCK="/tmp/.X11-unix"
WAYLAND="${WAYLAND_DISPLAY:-wayland-0}"
WAYSOCK="/run/user/${UIDNUM}/${WAYLAND}"

[[ -d "$XSOCK" ]] && ok "X11 socket dir present: $XSOCK" || warn "X11 socket dir missing (ok if using Wayland only)"
[[ -S "$WAYSOCK" ]] && ok "Wayland socket present: $WAYSOCK" || warn "Wayland socket not found: $WAYSOCK"

# ---------- Display Permissions ----------
if xhost >/dev/null 2>&1; then
  if xhost | grep -q "LOCAL:"; then
    ok "X access already granted to local users"
  else
    warn "X access for Docker not granted"
    if $HAS_FIX; then
      if xhost +local:docker >/dev/null 2>&1; then
        ok "Granted X access: xhost +local:docker"
      else
        warn "Failed to run 'xhost +local:docker'"
      fi
    fi
  fi
fi

# ---------- /dev checks ----------
if [[ "$gpu" == "nvidia" ]]; then
  ok "Expecting /dev/nvidia* visible inside container (via gpus: all)"
else
  [[ -e /dev/dri ]] && ok "/dev/dri present" || warn "/dev/dri missing — Mesa/DRM inactive?"
fi

# ---------- Summary ----------
echo
echo "Summary:"
echo "  GPU: $gpu"
echo "  Wayland sock: $WAYSOCK $( [[ -S "$WAYSOCK" ]] && echo "(ok)" || echo "(missing)" )"
echo "  X11 sock dir: $XSOCK $( [[ -d "$XSOCK" ]] && echo "(ok)" || echo "(missing)" )"
if [[ "$gpu" == "nvidia" ]]; then
  echo "  Toolkit: $( (command -v nvidia-ctk >/dev/null || command -v nvidia-container-toolkit >/dev/null) && echo ok || echo missing )"
fi

echo
ok "Host looks ready ${HAS_FIX:+(with fixes applied)}."
echo "Next: run ./quickvulkan.sh and enable GUI if you want VkSurface on host."
