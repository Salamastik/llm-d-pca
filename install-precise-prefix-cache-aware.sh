#!/usr/bin/env bash

set -euo pipefail

if [ -z "$(command -v helm)" ]; then
  echo "This script depends on \`helm\`. Please install it."
  exit 1
fi

if [ -z "$(command -v kubectl)" ]; then
  echo "This script depends on \`kubectl\`. Please install it."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-llm-d-precise}"
RELEASE_NAME_POSTFIX="${RELEASE_NAME_POSTFIX:-kv-events}"

kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${NAMESPACE}"

helm upgrade --install "infra-${RELEASE_NAME_POSTFIX}" "${SCRIPT_DIR}/charts/llm-d-infra" \
  --namespace "${NAMESPACE}" \
  --values "${SCRIPT_DIR}/charts/llm-d-infra/values-snd.yaml" \
  --wait

helm upgrade --install "gaie-${RELEASE_NAME_POSTFIX}" "${SCRIPT_DIR}/charts/inferencepool" \
  --namespace "${NAMESPACE}" \
  --values "${SCRIPT_DIR}/charts/inferencepool/values-snd.yaml" \
  --set-string "provider.istio.destinationRule.host=gaie-${RELEASE_NAME_POSTFIX}-epp.${NAMESPACE}.svc.cluster.local" \
  --wait

helm upgrade --install "ms-${RELEASE_NAME_POSTFIX}" "${SCRIPT_DIR}/charts/llm-d-modelservice" \
  --namespace "${NAMESPACE}" \
  --values "${SCRIPT_DIR}/charts/llm-d-modelservice/values-snd.yaml" \
  --set-string "decode.containers[0].env[0].value=${RELEASE_NAME_POSTFIX}" \
  --wait
