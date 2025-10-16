#!/usr/bin/env bash
set -euo pipefail

# check-vulkan-host.sh — Verify host is ready for Vulkan GUI in Docker (Wayland/X11)
# Usage:
#   ./check-vulkan-host.sh           # just check
#   ./check-vulkan-host.sh --fix     # also run safe fixes (xhost +local:docker)

bold=$(tput bold 2>/dev/null || echo "")
reset=$(tput sgr0 2>/dev/null || echo "")
cyan=$(tput setaf 6 2>/dev/null || echo "")
green=$(tput setaf 2 2>/dev/null || echo "")
yellow=$(tput setaf 3 2>/dev/null || echo "")
red=$(tput setaf 1 2>/dev/null || echo "")

print_header() {
  echo ""
  echo "${cyan}${bold}Quickvulkan1.1${reset}"
  echo "${cyan}${bold}------------------------------------------------------${reset}"
  echo "Quickvulkan check host prerequisites utility."
  echo "Linggawasistha Djohari, 2025"
  echo ""

}

ok()   { printf "\033[32m✔\033[0m %s\n" "$*"; }
warn() { printf "\033[33m⚠\033[0m %s\n" "$*"; }
err()  { printf "\033[31m✘\033[0m %s\n" "$*"; }

HAS_FIX=false
[[ "${1:-}" == "--fix" ]] && HAS_FIX=true

# ---------- Determine real desktop user (never root for xhost) ----------
REAL_USER="${SUDO_USER:-${USER}}"
REAL_UID="$(id -u "${REAL_USER}")"
REAL_RUNTIME_DIR="/run/user/${REAL_UID}"

# Run a command as the real (non-root) user, preserving DISPLAY/XDG_RUNTIME_DIR
as_real_user() {
  # shellcheck disable=SC2086
  sudo -u "${REAL_USER}" \
       DISPLAY="${DISPLAY:-:0}" \
       XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$REAL_RUNTIME_DIR}" \
       bash -lc "$*"
}

print_header

# ---------- Basic tools ----------
need=( bash id lspci grep awk sed xhost )
for c in "${need[@]}"; do
  command -v "$c" >/dev/null 2>&1 || { err "Missing tool: $c"; MISSING=true; }
done
[[ "${MISSING:-}" == "true" ]] && { err "Install missing tools and re-run."; exit 1; }

# ---------- Docker access (wrap with sudo only if required) ----------
if docker info >/dev/null 2>&1; then
  ok "Docker accessible without sudo"
  DOCKER="docker"
else
  warn "Docker requires sudo privileges"
  if sudo -n docker info >/dev/null 2>&1 || sudo docker info >/dev/null 2>&1; then
    ok "Docker usable with sudo"
    DOCKER="sudo docker"
  else
    err "Cannot access Docker even with sudo — fix group membership:"
    echo "   sudo usermod -aG docker \$USER && newgrp docker"
    exit 1
  fi
fi

# ---------- GPU detection ----------
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
  warn "vulkan-tools not installed (sudo apt install -y vulkan-tools libvulkan1)"
fi

# ---------- NVIDIA specific ----------
if [[ "$gpu" == "nvidia" ]]; then
  command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1 \
    && ok "nvidia-smi OK" || { err "nvidia-smi failed — driver missing/not loaded"; exit 1; }

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
XSOCK="/tmp/.X11-unix"
WAYLAND="${WAYLAND_DISPLAY:-wayland-0}"
WAYSOCK="${REAL_RUNTIME_DIR}/${WAYLAND}"

[[ -d "$XSOCK" ]] && ok "X11 socket dir present: $XSOCK" || warn "X11 socket dir missing (ok if using Wayland only)"
[[ -S "$WAYSOCK" ]] && ok "Wayland socket present: $WAYSOCK" || warn "Wayland socket not found: $WAYSOCK"

# ---------- Display permissions (NO sudo for xhost; run as real user) ----------
if as_real_user "command -v xhost >/dev/null"; then
  if as_real_user "xhost | grep -q 'LOCAL:'"; then
    ok "X access already granted to local users"
  else
    warn "X access for Docker not granted"
    if $HAS_FIX; then
      if as_real_user "xhost +local:docker >/dev/null 2>&1"; then
        ok "Granted X access (as ${REAL_USER}): xhost +local:docker"
      else
        warn "Failed to grant X access (is a desktop session active for ${REAL_USER}?)"
      fi
    fi
  fi
else
  warn "xhost not found in ${REAL_USER}'s session PATH"
fi

# ---------- /dev expectations ----------
if [[ "$gpu" == "nvidia" ]]; then
  ok "At runtime, container should expose /dev/nvidia* via gpus: all"
else
  [[ -e /dev/dri ]] && ok "/dev/dri present" || warn "/dev/dri missing — Mesa/DRM inactive?"
fi

# ---------- Summary ----------
echo
echo "Summary:"
echo "  GPU            : $gpu"
echo "  Real user      : ${REAL_USER} (uid ${REAL_UID})"
echo "  Wayland socket : $WAYSOCK $( [[ -S "$WAYSOCK" ]] && echo '(ok)' || echo '(missing)' )"
echo "  X11 socket dir : $XSOCK   $( [[ -d "$XSOCK" ]] && echo '(ok)' || echo '(missing)' )"
[[ "$gpu" == "nvidia" ]] && echo "  Toolkit        : $( (command -v nvidia-ctk >/dev/null || command -v nvidia-container-toolkit >/dev/null) && echo ok || echo missing )"


echo
ok "Host looks ready ${HAS_FIX:+(with fixes applied)}."
echo "Next: run ./quickvulkan.sh and enable GUI if you want VkSurface on host."
