#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

chart_dir="charts/valheim-arm64"

bash -n scripts/*.sh

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck scripts/*.sh
else
  printf 'warning: shellcheck is not installed; skipping shell lint\n' >&2
fi

if command -v kubectl >/dev/null 2>&1; then
  kubectl kustomize k8s/base >/dev/null
else
  printf 'warning: kubectl is not installed; skipping Kustomize render\n' >&2
fi

if command -v helm >/dev/null 2>&1; then
  helm lint "${chart_dir}" --set-string server.password=validation-only
  helm template validation "${chart_dir}" \
    --namespace valheim \
    --set-string server.password=validation-only >/dev/null
  helm template validation-existing "${chart_dir}" \
    --namespace valheim \
    --set server.existingSecret.name=valheim-secret \
    --set persistence.server.existingClaim=valheim-server \
    --set persistence.config.enabled=false \
    --set service.type=NodePort >/dev/null
else
  printf 'warning: Helm is not installed; skipping chart validation\n' >&2
fi

if command -v yamllint >/dev/null 2>&1; then
  yamllint \
    .github \
    k8s \
    compose.yaml \
    "${chart_dir}/Chart.yaml" \
    "${chart_dir}/values.yaml"
else
  printf 'warning: yamllint is not installed; skipping YAML lint\n' >&2
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  SERVER_PASSWORD=validation-only docker compose config --quiet
else
  printf 'warning: Docker Compose is not installed; skipping Compose validation\n' >&2
fi

printf 'validation complete\n'
