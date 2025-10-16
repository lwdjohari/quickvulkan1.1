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
need=(
  bash id lspci grep awk sed
  docker
  xhost
)
for c in "${need[@]}"; do
  if ! command -v "$c" >/dev/null 2>&1; then
    err "Missing tool: $c"
    MISSING=true
  fi
done
[[ "${MISSING:-}" == "true" ]] && { err "Install missing tools and re-run."; exit 1; }
ok "Core tools present"

# ---------- Docker access ----------
if docker info >/dev/null 2>&1; then
  ok "Docker is accessible without sudo"
else
  warn "Docker needs sudo on this system"
  if $HAS_FIX; then
    warn "Will try sudo for subsequent Docker checks"
    alias docker='sudo docker'
  fi
fi

# ---------- Detect GPU ----------
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
    err "Host Vulkan driver seems broken (vulkaninfo failed). Fix host before Docker."
    exit 1
  fi
else
  warn "vulkan-tools not installed (install: sudo apt install -y vulkan-tools libvulkan1)"
fi

# ---------- NVIDIA-specific checks ----------
if [[ "$gpu" == "nvidia" ]]; then
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    ok "nvidia-smi OK"
  else
    err "nvidia-smi failed. Install/enable NVIDIA driver (e.g., nvidia-driver-550) and reboot."
    exit 1
  fi
  if command -v nvidia-ctk >/dev/null 2>&1 || command -v nvidia-container-toolkit >/dev/null 2>&1; then
    ok "NVIDIA container toolkit installed"
  else
    err "nvidia-container-toolkit not found. Install: sudo apt install -y nvidia-container-toolkit && sudo systemctl restart docker"
    exit 1
  fi
  # Ensure Docker runtime configured (best effort check)
  if ! docker info 2>/dev/null | grep -q 'Runtimes:.*nvidia'; then
    warn "Docker runtime may not be configured for NVIDIA."
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

[[ -d "$XSOCK" ]] && ok "X11 socket dir present: $XSOCK" || warn "X11 socket dir missing (ok if only using Wayland): $XSOCK"
if [[ -S "$WAYSOCK" ]]; then
  ok "Wayland socket present: $WAYSOCK"
else
  warn "Wayland socket not found: $WAYSOCK"
  echo "   Ensure you are logged in to a Wayland session (echo \$WAYLAND_DISPLAY)."
fi

# ---------- Display permissions ----------
if command -v xhost >/dev/null 2>&1; then
  if xhost | grep -q "LOCAL:"; then
    ok "X access already granted to local users"
  else
    warn "X access for Docker not granted (xhost +local:docker recommended)"
    if $HAS_FIX; then
      if xhost +local:docker >/dev/null 2>&1; then
        ok "Granted X access: xhost +local:docker"
      else
        warn "Failed to run 'xhost +local:docker' (headless? no X server?)"
      fi
    fi
  fi
fi

# ---------- /dev access expectations ----------
if [[ "$gpu" == "nvidia" ]]; then
  ok "At runtime, container should expose /dev/nvidia* via 'gpus: all'"
else
  if [[ -e /dev/dri ]]; then
    ok "/dev/dri present (Mesa/DRI path looks good)"
  else
    warn "/dev/dri not present; for Intel/AMD, ensure kernel DRM is active."
  fi
fi

# ---------- Summary ----------
echo
echo "Summary:"
echo "  GPU           : $gpu"
echo "  Wayland sock  : $WAYSOCK $( [[ -S "$WAYSOCK" ]] && echo "(ok)" || echo "(missing)" )"
echo "  X11 sock dir  : $XSOCK   $( [[ -d "$XSOCK" ]] && echo "(ok)" || echo "(missing)" )"
if [[ "$gpu" == "nvidia" ]]; then
  echo "  Toolkit       : $( (command -v nvidia-ctk >/dev/null || command -v nvidia-container-toolkit >/dev/null) && echo ok || echo missing )"
fi

echo
ok "Host looks ready ${HAS_FIX:+(with fixes applied)}."
echo "Next: run ./quickvulkan.sh and enable GUI if you want on-screen VkSurface."
