#!/usr/bin/env bash
set -Eeuo pipefail

# Applies Debian security updates for packages that Trivy flags with fixable
# HIGH/CRITICAL vulnerabilities in the final image. The base image tag follows
# patched Trixie rebuilds, but a cached layer or a lag between a published
# Debian Security Advisory and a base-image rebuild can still ship a vulnerable
# package version. Running the latest security updates for these packages at
# build time keeps the published image clean without waiting for a new base tag.
#
# Keep this list aligned with the CI Trivy policy
# (.github/workflows/container.yml, "Reject fixable high or critical
# vulnerabilities"). Each entry documents the CVE(s) that motivated it so the
# list can be pruned once a vulnerability ages out of the base image.
#
# Covered advisories at the time of writing:
#   - libpcre2-8-0            CVE-2026-103111 (pcre2 JIT out-of-bounds write)
#   - libssl3t64, openssl,    CVE-2026-75804  (OpenSSL QUIC flow-control DoS)
#     openssl-provider-legacy CVE-2026-84782  (OpenSSL DTLS info disclosure)

# Packages to force to the newest available (security) version. Only list
# packages already installed in the final image so an upgrade never pulls in
# unexpected new dependencies.
readonly security_packages=(
  libpcre2-8-0
  libssl3t64
  openssl
  openssl-provider-legacy
)

log() {
  printf '[security-updates] %s\n' "$1"
}

main() {
  export DEBIAN_FRONTEND=noninteractive

  log "Refreshing package indexes."
  apt-get update

  # Determine which of the requested packages are actually installed. Some
  # (for example openssl-provider-legacy) are pulled in transitively and may
  # not exist on every base-image revision; skip anything absent instead of
  # failing the build.
  local -a installed=()
  local pkg
  for pkg in "${security_packages[@]}"; do
    if dpkg-query --show --showformat='${Status}' "${pkg}" 2>/dev/null \
      | grep --quiet "install ok installed"; then
      installed+=("${pkg}")
    else
      log "Skipping ${pkg}; not installed in this image."
    fi
  done

  if (( ${#installed[@]} == 0 )); then
    log "No targeted packages are installed; nothing to upgrade."
    rm -rf /var/lib/apt/lists/*
    return 0
  fi

  log "Upgrading: ${installed[*]}"
  apt-get install -y --no-install-recommends --only-upgrade "${installed[@]}"

  log "Installed versions after upgrade:"
  dpkg-query --show --showformat='  ${Package} ${Version}\n' "${installed[@]}"

  log "Cleaning apt caches."
  apt-get clean
  rm -rf /var/lib/apt/lists/*

  log "Security updates applied."
}

main "$@"
