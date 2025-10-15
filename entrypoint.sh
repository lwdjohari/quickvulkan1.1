#!/usr/bin/env bash
set -eo pipefail

# load system profile for non-login shells too
# Source system profile safely (nounset off while sourcing)
if [ -f /etc/profile ]; then
  set +u
  . /etc/profile
  set -u 2>/dev/null || true
fi

log() { echo "[entrypoint] $*"; }
bool() { case "${1,,}" in true|1|yes|on) return 0 ;; *) return 1 ;; esac; }

# Helper: find a free UID in 1001..1999 (used only if you choose autopick)
next_free_uid() {
  for uid in $(seq 1001 1999); do
    if ! getent passwd "$uid" >/dev/null 2>&1; then
      echo "$uid"
      return 0
    fi
  done
  echo ""
  return 1
}

# ---------------- Root SSH controls ----------------
SSHD_ENABLED="${SSHD_ENABLED:-false}"
SSHD_PASSWORD_AUTH="${SSHD_PASSWORD_AUTH:-false}"
ROOT_PASSWORD="${ROOT_PASSWORD:-}"

# ---------------- Extra user controls ----------------
CREATE_USER="${CREATE_USER:-false}"     # true|false
USER_NAME="${USER_NAME:-dev}"
USER_UID="${USER_UID:-1000}"
USER_GID="${USER_GID:-1000}"
USER_PASSWORD="${USER_PASSWORD:-}"
USER_SUDO="${USER_SUDO:-true}"          # true -> NOPASSWD sudo
USER_SHELL="${USER_SHELL:-/bin/bash}"
TAKE_WORKSPACE="${TAKE_WORKSPACE:-true}"
USER_RENAME="${USER_RENAME:-true}"      # <--- default: allow rename of existing uid=USER_UID user
USER_STRATEGY="${USER_STRATEGY:-reuse}" # fallback strategy if USER_RENAME=false: reuse|fail|autopick

# cache dir
CCACHE_DIR="${CCACHE_DIR:-/opt/cache/ccache}"

log "SSHD_ENABLED=${SSHD_ENABLED} SSHD_PASSWORD_AUTH=${SSHD_PASSWORD_AUTH}"
log "CREATE_USER=${CREATE_USER} USER_NAME=${USER_NAME} USER_UID=${USER_UID} USER_GID=${USER_GID} USER_SUDO=${USER_SUDO} TAKE_WORKSPACE=${TAKE_WORKSPACE}"
log "CCACHE_DIR=${CCACHE_DIR}"

# Always ensure /workspace exists (bind mount may be empty)
install -d -m 0755 -o root -g root /workspace || true
install -d -m 0777 -o root -g root "${CCACHE_DIR}" || true

# ---------------- Configure root SSH (as per your template semantics) ----------------
if bool "${SSHD_ENABLED}"; then
  if bool "${SSHD_PASSWORD_AUTH}"; then
    if [[ -z "${ROOT_PASSWORD}" ]]; then
      ROOT_PASSWORD=$(tr -dc 'A-Za-z0-9!@#%^_+=' </dev/urandom | head -c 18)
      log "Generated ROOT_PASSWORD (dev only): ${ROOT_PASSWORD}"
    else
      log "Using provided ROOT_PASSWORD (masked)"
    fi
    echo "root:${ROOT_PASSWORD}" | chpasswd
    sed -ri 's/^#?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -ri 's/^#?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
  else
    sed -ri 's/^#?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -ri 's/^#?PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
  fi
  echo 'ClientAliveInterval 60' >>/etc/ssh/sshd_config
  echo 'ClientAliveCountMax  3'  >>/etc/ssh/sshd_config
else
  log "SSHD DISABLED (set SSHD_ENABLED=true to enable)"
fi

# ---------------- Create / ensure dev user (robust, keeps UID/GID=1000) ----------------
if bool "${CREATE_USER}"; then
  if [[ -z "${USER_PASSWORD}" ]]; then
    log "ERROR: CREATE_USER=true but USER_PASSWORD is empty. Refusing to start."
    exit 64
  fi

  # Who (if anyone) already owns the desired UID/GID?
  EXISTING_USER_BY_UID="$(getent passwd "${USER_UID}" | cut -d: -f1 || true)"
  EXISTING_GROUP_BY_GID="$(getent group  "${USER_GID}" | cut -d: -f1 || true)"

  # Case A: UID already taken by a different user name (e.g., ubuntu) and we want $USER_NAME
  if [[ -n "${EXISTING_USER_BY_UID}" && "${EXISTING_USER_BY_UID}" != "${USER_NAME}" ]]; then
    if bool "${USER_RENAME}"; then
      log "UID ${USER_UID} owned by '${EXISTING_USER_BY_UID}'. Renaming to '${USER_NAME}' (preserve UID/GID)."

      # If primary group name matches the old username and gid matches USER_GID, rename the group first.
      OLD_GID="$(getent passwd "${EXISTING_USER_BY_UID}" | cut -d: -f4)"
      OLD_GRP="$(getent group "${OLD_GID}" | cut -d: -f1 || true)"
      if [[ -n "${OLD_GRP}" && "${OLD_GRP}" == "${EXISTING_USER_BY_UID}" && "${OLD_GID}" == "${USER_GID}" ]]; then
        groupmod -n "${USER_NAME}" "${OLD_GRP}" || true
        log "Renamed group '${OLD_GRP}' -> '${USER_NAME}' (gid=${USER_GID})"
      fi

      # Rename the user, then move/rename home to match
      usermod -l "${USER_NAME}" "${EXISTING_USER_BY_UID}"
      usermod -d "/home/${USER_NAME}" -m "${USER_NAME}"
      chsh -s "${USER_SHELL}" "${USER_NAME}"
      log "User renamed. New home: /home/${USER_NAME}"

    else
      # USER_RENAME=false => follow USER_STRATEGY
      log "UID ${USER_UID} belongs to '${EXISTING_USER_BY_UID}', USER_RENAME=false. Strategy=${USER_STRATEGY}"
      case "${USER_STRATEGY}" in
        reuse)
          USER_NAME="${EXISTING_USER_BY_UID}"
          log "Reusing existing user '${USER_NAME}' (uid=${USER_UID})."
          ;;
        fail)
          log "ERROR: UID conflict and USER_STRATEGY=fail. Refusing to start."
          exit 65
          ;;
        autopick)
          NEW_UID="$(next_free_uid)"
          [[ -z "${NEW_UID}" ]] && { log "ERROR: No free UID in 1001..1999"; exit 66; }
          log "Auto-selecting free UID ${NEW_UID} for ${USER_NAME} (desired ${USER_UID} unavailable)."
          USER_UID="${NEW_UID}"
          ;;
        *)
          log "Unknown USER_STRATEGY='${USER_STRATEGY}', defaulting to 'reuse'."
          USER_NAME="${EXISTING_USER_BY_UID}"
          ;;
      esac
    fi
  fi

  # Ensure the group for desired GID exists (reuse if present; else create)
  if [[ -n "${EXISTING_GROUP_BY_GID}" ]]; then
    GROUP_NAME="${EXISTING_GROUP_BY_GID}"
    log "Reusing existing group gid=${USER_GID} name='${GROUP_NAME}'"
  else
    GROUP_NAME="${USER_NAME}"
    if ! getent group "${GROUP_NAME}" >/dev/null 2>&1; then
      groupadd -g "${USER_GID}" "${GROUP_NAME}"
      log "Created group name='${GROUP_NAME}' gid=${USER_GID}"
    else
      # Group name exists but with different gid; keep its gid to avoid conflict
      EXISTING_GID_FOR_NAME="$(getent group "${GROUP_NAME}" | cut -d: -f3)"
      log "WARNING: group '${GROUP_NAME}' exists with gid=${EXISTING_GID_FOR_NAME}; using that gid."
      USER_GID="${EXISTING_GID_FOR_NAME}"
    fi
  fi

  # Create user if it doesn't exist (after potential rename above)
  if ! id -u "${USER_NAME}" >/dev/null 2>&1; then
    useradd -m -u "${USER_UID}" -g "${USER_GID}" -s "${USER_SHELL}" "${USER_NAME}"
    log "Created user: ${USER_NAME} (uid=${USER_UID}, gid=${USER_GID}, shell=${USER_SHELL})"
  else
    ACT_UID="$(id -u "${USER_NAME}")"
    ACT_GID="$(id -g "${USER_NAME}")"
    log "User ${USER_NAME} exists (uid=${ACT_UID}, gid=${ACT_GID})"

    # Align primary group to USER_GID if safe
    if [[ "${ACT_GID}" != "${USER_GID}" ]]; then
      if getent group "${USER_GID}" >/dev/null 2>&1; then
        usermod -g "${USER_GID}" "${USER_NAME}"
        log "Updated GID for ${USER_NAME} -> ${USER_GID}"
      else
        log "Desired GID ${USER_GID} not found; keeping existing gid=${ACT_GID}"
        USER_GID="${ACT_GID}"
      fi
    fi

    # Align shell
    CUR_SHELL="$(getent passwd "${USER_NAME}" | cut -d: -f7)"
    if [[ "${CUR_SHELL}" != "${USER_SHELL}" ]]; then
      chsh -s "${USER_SHELL}" "${USER_NAME}" || usermod -s "${USER_SHELL}" "${USER_NAME}" || true
      log "Set shell for ${USER_NAME} -> ${USER_SHELL}"
    fi
  fi

  # Password & sudo
  echo "${USER_NAME}:${USER_PASSWORD}" | chpasswd
  log "Set password for ${USER_NAME} (masked)"

  if bool "${USER_SUDO}"; then
    echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/90-${USER_NAME}
    chmod 0440 /etc/sudoers.d/90-${USER_NAME}
    log "Granted sudo (NOPASSWD) to ${USER_NAME}"
  fi

  # Home & SSH
  USER_HOME="$(getent passwd "${USER_NAME}" | cut -d: -f6)"
  install -d -m 0755 -o "${USER_UID}" -g "${USER_GID}" "${USER_HOME}"
  install -d -m 0700 -o "${USER_UID}" -g "${USER_GID}" "${USER_HOME}/.ssh"
  touch "${USER_HOME}/.ssh/authorized_keys"
  chown "${USER_UID}:${USER_GID}" "${USER_HOME}/.ssh/authorized_keys"
  chmod 0600 "${USER_HOME}/.ssh/authorized_keys"
  log "Prepared home=${USER_HOME} (uid=${USER_UID}, gid=${USER_GID}) and SSH dir for ${USER_NAME}"

  # Workspace handover
  if bool "${TAKE_WORKSPACE}"; then
    if [[ -d /workspace ]]; then
      chown -R "${USER_UID}:${USER_GID}" /workspace || true
      log "Ownership of /workspace -> ${USER_UID}:${USER_GID}"
    else
      log "WARNING: /workspace not found to chown"
    fi
  fi

  # ccache ownership
  chown -R "${USER_UID}:${USER_GID}" "${CCACHE_DIR}" || true
fi

# ---------------- GPU/Display hints (informational) ----------------
if [ -d /dev/dri ]; then log "DRI present: /dev/dri mounted"; else log "DRI not present (OK on NVIDIA with --gpus all)"; fi
if [ -n "${DISPLAY:-}" ]; then log "X11 DISPLAY=${DISPLAY}"; fi
if [ -n "${WAYLAND_DISPLAY:-}" ]; then log "Wayland WAYLAND_DISPLAY=${WAYLAND_DISPLAY}"; fi
if [ -n "${VULKAN_SDK:-}" ]; then log "VULKAN_SDK=${VULKAN_SDK}"; fi

# ---------------- Start SSHD (if enabled) ----------------
if bool "${SSHD_ENABLED}"; then
  ssh-keygen -A >/dev/null 2>&1 || true
  /usr/sbin/sshd -E /var/log/sshd.log
  log "SSHD started on port 22"
  log "Login:"
  log " - root: ssh -p <port> root@<host>"
  if bool "${CREATE_USER}"; then
    log " - ${USER_NAME}: ssh -p <port> ${USER_NAME}@<host>"
  fi
fi

exec "$@"
