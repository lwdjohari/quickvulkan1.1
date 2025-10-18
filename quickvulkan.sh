#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# Quick Vulkan Dev Container Launcher
# - Manual GPU mode (NVIDIA / Mesa / None) with auto-detect hint
# - Optional GUI mode (Wayland/X11 sockets) via docker-compose.gui.yml
# - Sudo prompt if Docker needs elevation
# - Actions: up, rebuild, down, logs
# - command + env preview
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
  echo "${cyan}${bold}------------------------------------------------------${reset}"
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

# Detect if Docker needs sudo
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
# GPU detection & manual choice
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
  *)
    echo "Invalid choice; using Auto."
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
# GUI (Wayland/X11) toggle
# -------------------------------------------------------------------
enable_gui="no"
if ask_yes_no "Enable GUI (Wayland/X11) for VkSurface / GUI tools?" n; then
  enable_gui="yes"
fi

if [ "$enable_gui" = "yes" ]; then
  if command -v xhost >/dev/null 2>&1; then
    echo "${cyan}Granting local X access: xhost +local:docker${reset}"
    xhost +local:docker >/dev/null 2>&1 || true
  fi
fi

# -------------------------------------------------------------------
# Compose stack setup
# -------------------------------------------------------------------
BASE_YML="docker-compose.yml"
NVIDIA_YML="docker-compose.nvidia.yml"
MESA_YML="docker-compose.mesa.yml"
GUI_YML="docker-compose.gui.yml"

[ -f "$BASE_YML" ] || { echo "${red}❌ Missing ${BASE_YML} in current directory.${reset}"; exit 1; }

CMD="$COMPOSE -f $BASE_YML"
STACK_DESC="$BASE_YML"

case "$gpu_mode" in
  nvidia)
    [ -f "$NVIDIA_YML" ] || { echo "${red}❌ Missing ${NVIDIA_YML}.${reset}"; exit 1; }
    CMD="$CMD -f $NVIDIA_YML"
    STACK_DESC="$STACK_DESC + $NVIDIA_YML"
    ;;
  mesa)
    [ -f "$MESA_YML" ] || { echo "${red}❌ Missing ${MESA_YML}.${reset}"; exit 1; }
    CMD="$CMD -f $MESA_YML"
    STACK_DESC="$STACK_DESC + $MESA_YML"
    ;;
esac

if [ "$enable_gui" = "yes" ]; then
  [ -f "$GUI_YML" ] || { echo "${red}❌ Missing ${GUI_YML}.${reset}"; exit 1; }
  export HOST_UID="$(id -u)"
  CMD="$CMD -f $GUI_YML"
  STACK_DESC="$STACK_DESC + $GUI_YML"
fi

# -------------------------------------------------------------------
# Env preview helper
# -------------------------------------------------------------------
print_env_preview() {
  echo "${bold}Env passed (host → container):${reset}"

  if [ "$enable_gui" = "yes" ]; then
    # Values used by docker-compose.gui.yml
    local disp="${DISPLAY:-<unset>}"
    local wdisp="${WAYLAND_DISPLAY:-wayland-0}"
    local huid="${HOST_UID:-$(id -u)}"
    local xdg="/run/user/${huid}"

    printf "  DISPLAY=%s\n" "$disp"
    printf "  WAYLAND_DISPLAY=%s\n" "$wdisp"
    printf "  XDG_RUNTIME_DIR=%s\n" "$xdg"
    printf "  HOST_UID=%s\n" "$huid"
  else
    echo "  (GUI disabled)"
  fi

  if [ "$gpu_mode" = "nvidia" ]; then
    echo "  NVIDIA_VISIBLE_DEVICES=all"
    echo "  NVIDIA_DRIVER_CAPABILITIES=graphics,utility,compute"
  fi

  # Mention .env pass-through (if present)
  if [ -f ".env" ]; then
    echo "  + plus variables from .env (if referenced in compose files)"
  fi
}

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

# -------------------------------------------------------------------
# Print stack, env preview, and final command
# -------------------------------------------------------------------
echo ""
echo "${bold}Compose files:${reset} $STACK_DESC"
print_env_preview
echo ""
echo "${bold}------------------------------------------------------${reset}"
echo "Final command to be executed:"
echo "${yellow}${USE_SUDO:+$USE_SUDO }$CMD${reset}"
echo "${bold}------------------------------------------------------${reset}"
echo ""

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
