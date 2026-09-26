#!/usr/bin/env bash
set -Eeuo pipefail

readonly SERVER_BINARY="${VALHEIM_SERVER_DIR}/valheim_server.x86_64"
readonly PID_FILE="/run/valheim/valheim.pid"
child_pid=""

log() {
  printf '[%s] %s\n' "$(date --utc '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

is_true() {
  case "${1,,}" in
    1 | true | yes | on) return 0 ;;
    *) return 1 ;;
  esac
}

fail() {
  log "ERROR: $*"
  exit 1
}

validate_configuration() {
  [[ "$(uname -m)" == "aarch64" ]] || fail "This image requires an ARM64 (aarch64) host."
  [[ -n "${SERVER_PASSWORD:-}" ]] || fail "SERVER_PASSWORD is required."
  (( ${#SERVER_PASSWORD} >= 5 )) || fail "SERVER_PASSWORD must contain at least five characters."
  [[ "${SERVER_PORT}" =~ ^[0-9]+$ ]] || fail "SERVER_PORT must be numeric."
  (( SERVER_PORT >= 1024 && SERVER_PORT <= 65533 )) || fail "SERVER_PORT must be between 1024 and 65533."
  [[ "${SERVER_PUBLIC}" == "0" || "${SERVER_PUBLIC}" == "1" ]] || fail "SERVER_PUBLIC must be 0 or 1."
  [[ "${SAVE_INTERVAL}" =~ ^[0-9]+$ ]] || fail "SAVE_INTERVAL must be numeric."
  [[ "${BACKUPS}" =~ ^[0-9]+$ ]] || fail "BACKUPS must be numeric."
  [[ "${BACKUP_SHORT}" =~ ^[0-9]+$ ]] || fail "BACKUP_SHORT must be numeric."
  [[ "${BACKUP_LONG}" =~ ^[0-9]+$ ]] || fail "BACKUP_LONG must be numeric."
}

update_server() {
  log "Installing or validating Valheim Dedicated Server app 896660."
  "${DEPOTDOWNLOADER_DIR}/DepotDownloader" \
    -app 896660 \
    -os linux \
    -osarch 64 \
    -dir "${VALHEIM_SERVER_DIR}" \
    -validate
}

prepare_steam_runtime() {
  local steamclient_source=""

  mkdir -p "${HOME}/.steam/sdk64" /run/valheim
  if [[ -f "${VALHEIM_SERVER_DIR}/linux64/steamclient.so" ]]; then
    steamclient_source="${VALHEIM_SERVER_DIR}/linux64/steamclient.so"
  elif [[ -f "${VALHEIM_SERVER_DIR}/steamclient.so" ]]; then
    steamclient_source="${VALHEIM_SERVER_DIR}/steamclient.so"
  else
    fail "steamclient.so was not found after the server download."
  fi

  ln -sfn "${steamclient_source}" "${HOME}/.steam/sdk64/steamclient.so"
  chmod u+x "${SERVER_BINARY}"
}

# shellcheck disable=SC2317,SC2329  # Invoked indirectly by the signal trap.
forward_shutdown() {
  if [[ -n "${child_pid}" ]] && kill -0 "${child_pid}" 2>/dev/null; then
    log "Requesting a clean Valheim shutdown."
    kill -INT "${child_pid}"
  fi
}

validate_configuration
mkdir -p "${VALHEIM_SERVER_DIR}" "${VALHEIM_CONFIG_DIR}"

if is_true "${UPDATE_ON_START}" || [[ ! -x "${SERVER_BINARY}" ]]; then
  update_server
else
  log "Skipping server update because UPDATE_ON_START=${UPDATE_ON_START}."
fi

[[ -f "${SERVER_BINARY}" ]] || fail "Valheim server binary is missing: ${SERVER_BINARY}"
prepare_steam_runtime

declare -a server_args=(
  -nographics
  -batchmode
  -name "${SERVER_NAME}"
  -port "${SERVER_PORT}"
  -world "${WORLD_NAME}"
  -password "${SERVER_PASSWORD}"
  -public "${SERVER_PUBLIC}"
  -savedir "${VALHEIM_CONFIG_DIR}"
  -saveinterval "${SAVE_INTERVAL}"
  -backups "${BACKUPS}"
  -backupshort "${BACKUP_SHORT}"
  -backuplong "${BACKUP_LONG}"
)

if is_true "${SERVER_CROSSPLAY}"; then
  log "Crossplay requested. Review the documented Box64/PlayFab compatibility warning."
  server_args+=(-crossplay)
fi

export SteamAppId=892970
export SteamGameId=892970
export BOX64_LD_LIBRARY_PATH="${VALHEIM_SERVER_DIR}:${VALHEIM_SERVER_DIR}/linux64${BOX64_LD_LIBRARY_PATH:+:${BOX64_LD_LIBRARY_PATH}}"

trap forward_shutdown TERM INT

log "Starting '${SERVER_NAME}' on UDP ${SERVER_PORT}-$((SERVER_PORT + 2)); world '${WORLD_NAME}'."
box64 "${SERVER_BINARY}" "${server_args[@]}" &
child_pid=$!
printf '%s\n' "${child_pid}" > "${PID_FILE}"

exit_code=0
while kill -0 "${child_pid}" 2>/dev/null; do
  if wait "${child_pid}"; then
    exit_code=0
  else
    exit_code=$?
  fi
done
wait "${child_pid}" 2>/dev/null || true
rm -f "${PID_FILE}"

log "Valheim server exited with status ${exit_code}."
exit "${exit_code}"
