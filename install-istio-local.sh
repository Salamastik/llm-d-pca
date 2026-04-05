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
NAMESPACE="${NAMESPACE:-istio-system}"

kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${NAMESPACE}"

helm upgrade --install istio-base "${SCRIPT_DIR}/charts/base" \
  --namespace "${NAMESPACE}" \
  --wait

helm upgrade --install istiod "${SCRIPT_DIR}/charts/istiod" \
  --namespace "${NAMESPACE}" \
  --values "${SCRIPT_DIR}/istio/istiod-values-llmd.yaml" \
  --wait

