#!/usr/bin/env bash

set -euo pipefail

if [ -z "$(command -v kubectl)" ]; then
  echo "This script depends on \`kubectl\`. Please install it."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

COLOR_RESET=$'\e[0m'
COLOR_GREEN=$'\e[32m'
COLOR_RED=$'\e[31m'

log_success() {
  echo "${COLOR_GREEN}✅ $*${COLOR_RESET}"
}

log_error() {
  echo "${COLOR_RED}❌ $*${COLOR_RESET}" >&2
}

MODE=${1:-apply}
if [[ "$MODE" == "apply" ]]; then
  LOG_ACTION_NAME="Installing"
elif [[ "$MODE" == "delete" ]]; then
  LOG_ACTION_NAME="Deleting"
else
  log_error "Unrecognized Mode: ${MODE}, only supports \`apply\` or \`delete\`."
  exit 1
fi

GATEWAY_API_DIR="${SCRIPT_DIR}/vendor/gateway-api"
GAIE_DIR="${SCRIPT_DIR}/vendor/gateway-api-inference-extension"

if [[ ! -f "${GATEWAY_API_DIR}/kustomization.yaml" ]]; then
  log_error "Missing ${GATEWAY_API_DIR}/kustomization.yaml"
  exit 1
fi

if [[ ! -f "${GAIE_DIR}/kustomization.yaml" ]]; then
  log_error "Missing ${GAIE_DIR}/kustomization.yaml"
  exit 1
fi

log_success "📜 Base CRDs: ${LOG_ACTION_NAME} from ${GATEWAY_API_DIR}..."
kubectl "${MODE}" -k "${GATEWAY_API_DIR}" || true

log_success "🚪 GAIE CRDs: ${LOG_ACTION_NAME} from ${GAIE_DIR}..."
kubectl "${MODE}" -k "${GAIE_DIR}" || true

