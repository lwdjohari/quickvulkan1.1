#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# Quick Vulkan Dev Container Launcher
# - Manual GPU mode (NVIDIA / Mesa / None) with auto-detect hint
# - Optional GUI mode (Wayland/X11 sockets) via docker-compose.gui.yml
# - Sudo prompt if Docker needs elevation
# - Actions: up, rebuild, down, logs
# Author: Linggawasistha Djohari (https://github.com/lwdjohari)
# -------------------------------------------------------------------

bold=$(tput bold 2>/dev/null || echo "")
reset=$(tput sgr0 2>/dev/null || echo "")
cyan=$(tput setaf 6 2>/dev/null || echo "")
green=$(tput setaf 2 2>/dev/null || echo "")
yellow=$(tput setaf 3 2>/dev/null || echo "")
red=$(tput setaf 1 2>/dev/null || echo "")

print_header() {
  echo ""
  echo "${cyan}${bold}Quickvulkan1.1${reset}"
  echo "${cyan}${bold}--------------------------------------${reset}"
  echo "Quickvulkan docker development container quick launcher."
  echo "Linggawasistha Djohari, 2025"
  echo ""

}

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "${red}❌ Missing command: $1${reset}"; exit 1; }
}

ask_yes_no() {
  local prompt="$1" default="${2:-y}" reply
  local hint="[y/n]"
  [ "$default" = "y" ] && hint="[Y/n]"
  [ "$default" = "n" ] && hint="[y/N]"
  while true; do
    read -rp "${prompt} ${hint}: " reply
    reply="${reply:-$default}"
    case "$reply" in
      [Yy]*) return 0 ;;
      [Nn]*) return 1 ;;
      *) echo "Please answer y or n." ;;
    esac
  done
}

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
  else
    echo ""
  fi
}

print_header
require docker
COMPOSE=$(compose_cmd)
if [ -z "$COMPOSE" ]; then
  echo "${red}❌ Neither 'docker compose' (v2) nor 'docker-compose' found.${reset}"
  exit 1
fi

# Determine if we need sudo for docker
USE_SUDO=""
if ! docker info >/dev/null 2>&1; then
  echo "${yellow}⚠️  Docker requires elevated privileges on this system.${reset}"
  if ask_yes_no "Run with sudo?" y; then
    USE_SUDO="sudo"
  else
    echo "${red}Aborted (docker not accessible without sudo).${reset}"
    exit 1
  fi
else
  if ask_yes_no "Run with sudo?" n; then
    USE_SUDO="sudo"
  fi
fi

# -------------------------------------------------------------------
# GPU: auto-detect (hint) + manual selection
# -------------------------------------------------------------------
detected="unknown"
if command -v lspci >/dev/null 2>&1; then
  if lspci | grep -qi nvidia; then
    detected="nvidia"
  elif lspci | grep -qiE 'amd|ati'; then
    detected="amd"
  elif lspci | grep -qi intel; then
    detected="intel"
  fi
fi

echo "🔍 Detected GPU vendor (hint): ${yellow}${detected}${reset}"
echo ""
echo "${bold}Select GPU backend:${reset}"
echo "  1) NVIDIA (nvidia-container-toolkit)"
echo "  2) Intel / AMD (Mesa via /dev/dri)"
echo "  3) CPU-only (no GPU passthrough)"
echo "  4) Auto (use hint: ${detected})"
read -rp "Enter choice [1-4, default 4]: " choice
choice="${choice:-4}"

gpu_mode="none"
case "$choice" in
  1) gpu_mode="nvidia" ;;
  2) gpu_mode="mesa" ;;
  3) gpu_mode="none" ;;
  4)
    case "$detected" in
      nvidia) gpu_mode="nvidia" ;;
      amd|ati|intel) gpu_mode="mesa" ;;
      *) gpu_mode="none" ;;
    esac
    ;;
  *) echo "Invalid choice; using Auto."
     case "$detected" in
       nvidia) gpu_mode="nvidia" ;;
       amd|ati|intel) gpu_mode="mesa" ;;
       *) gpu_mode="none" ;;
     esac
     ;;
esac
echo "👉 Using GPU mode: ${green}${gpu_mode}${reset}"
echo ""

# -------------------------------------------------------------------
# GUI mode (Wayland/X11) toggle
# -------------------------------------------------------------------
enable_gui="no"
if ask_yes_no "Enable GUI (Wayland/X11) for VkSurface / GUI tools?" n; then
  enable_gui="yes"
fi

# When GUI is enabled, we need host X/Wayland access
if [ "$enable_gui" = "yes" ]; then
  # Allow local docker to connect to your X server (X11/XWayland); harmless on Wayland
  if command -v xhost >/dev/null 2>&1; then
    if ! xhost | grep -q "LOCAL:"; then
      echo "${cyan}Granting local X access: xhost +local:docker${reset}"
      xhost +local:docker >/dev/null 2>&1 || true
    fi
  else
    echo "${yellow}⚠️ 'xhost' not found; if X11 is used, you may need to allow access manually.${reset}"
  fi
fi

# -------------------------------------------------------------------
# Compose file stack & sanity checks
# -------------------------------------------------------------------
BASE_YML="docker-compose.yml"
NVIDIA_YML="docker-compose.nvidia.yml"
MESA_YML="docker-compose.mesa.yml"
GUI_YML="docker-compose.gui.yml"

[ -f "$BASE_YML" ] || { echo "${red}❌ Missing ${BASE_YML} in current directory.${reset}"; exit 1; }

CMD="$COMPOSE -f $BASE_YML"

case "$gpu_mode" in
  nvidia)
    [ -f "$NVIDIA_YML" ] || { echo "${red}❌ Missing ${NVIDIA_YML}.${reset}"; exit 1; }
    CMD="$CMD -f $NVIDIA_YML"
    if ! command -v nvidia-ctk >/dev/null 2>&1 && ! command -v nvidia-container-toolkit >/dev/null 2>&1; then
      echo "${yellow}⚠️  'nvidia-container-toolkit' not found on host.${reset}"
      echo "    Install: sudo apt install -y nvidia-container-toolkit && sudo systemctl restart docker"
    fi
    ;;
  mesa)
    [ -f "$MESA_YML" ] || { echo "${red}❌ Missing ${MESA_YML}.${reset}"; exit 1; }
    CMD="$CMD -f $MESA_YML"
    ;;
  none) ;; # base only
esac

if [ "$enable_gui" = "yes" ]; then
  [ -f "$GUI_YML" ] || { echo "${red}❌ Missing ${GUI_YML}.${reset}"; exit 1; }
  # Export HOST_UID so the compose file can mount /run/user/$HOST_UID/wayland-0
  export HOST_UID="$(id -u)"
  CMD="$CMD -f $GUI_YML"
  echo "🖥  GUI enabled (HOST_UID=${HOST_UID})."
fi

# -------------------------------------------------------------------
# Action menu
# -------------------------------------------------------------------
echo "${bold}Select action:${reset}"
echo "  u) up -d (start in background)   [default]"
echo "  r) rebuild (no-cache) + up -d"
echo "  d) down (stop)"
echo "  l) logs -f"
read -rp "Enter choice [u/r/d/l, default u]: " action
action="${action:-u}"

case "$action" in
  u|U)
    echo "${cyan}>> Starting container...${reset}"
    exec ${USE_SUDO:+$USE_SUDO} $CMD up -d
    ;;
  r|R)
    echo "${cyan}>> Rebuilding image (no cache) and starting...${reset}"
    ${USE_SUDO:+$USE_SUDO} $CMD build --no-cache
    exec ${USE_SUDO:+$USE_SUDO} $CMD up -d
    ;;
  d|D)
    echo "${cyan}>> Stopping container...${reset}"
    exec ${USE_SUDO:+$USE_SUDO} $CMD down
    ;;
  l|L)
    echo "${cyan}>> Streaming logs... (Ctrl-C to exit)${reset}"
    exec ${USE_SUDO:+$USE_SUDO} $CMD logs -f
    ;;
  *)
    echo "${cyan}>> Starting container (default)...${reset}"
    exec ${USE_SUDO:+$USE_SUDO} $CMD up -d
    ;;
esac
