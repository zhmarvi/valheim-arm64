#!/usr/bin/env bash
set -Eeuo pipefail

readonly pid_file="/run/valheim/valheim.pid"

[[ -s "${pid_file}" ]] || exit 1
read -r server_pid < "${pid_file}"
[[ "${server_pid}" =~ ^[0-9]+$ ]] || exit 1
kill -0 "${server_pid}" 2>/dev/null
