#!/usr/bin/env bash

set -uo pipefail

NAMESPACE="${NAMESPACE:-default}"
ROUTE="${ROUTE:-llm-d-kv-events-istio}"
POOL="${POOL:-gaie}"
GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-istio-system}"
GATEWAY="${GATEWAY:-llm-d-infra-istio-inference-gateway}"
GATEWAY_URL="${GATEWAY_URL:-http://127.0.0.1:8000}"

section() {
  printf '\n== %s ==\n' "$*"
}

run() {
  printf '+ %s\n' "$*"
  "$@"
}

jsonpath() {
  kubectl "$@" 2>/dev/null || true
}

section "Inputs"
cat <<EOF
NAMESPACE=$NAMESPACE
ROUTE=$ROUTE
POOL=$POOL
GATEWAY_NAMESPACE=$GATEWAY_NAMESPACE
GATEWAY=$GATEWAY
GATEWAY_URL=$GATEWAY_URL
EOF

section "Namespace Injection"
run kubectl get namespace "$NAMESPACE" --show-labels

section "HTTPRoute Status"
run kubectl get httproute "$ROUTE" -n "$NAMESPACE" \
  -o jsonpath='parent={.status.parents[0].parentRef.namespace}/{.status.parents[0].parentRef.name}{"\n"}controller={.status.parents[0].controllerName}{"\n"}types={.status.parents[0].conditions[*].type}{"\n"}statuses={.status.parents[0].conditions[*].status}{"\n"}messages={.status.parents[0].conditions[*].message}{"\n"}'
printf '\n'
run kubectl get httproute "$ROUTE" -n "$NAMESPACE" \
  -o jsonpath='backendRefs={range .spec.rules[*].backendRefs[*]}{.group}/{.kind}/{.name}:port={.port}{" "}{end}{"\n"}'

section "InferencePool Status"
run kubectl get inferencepool "$POOL" -n "$NAMESPACE" \
  -o jsonpath='failureMode={.spec.endpointPickerRef.failureMode}{"\n"}epp={.spec.endpointPickerRef.name}:port={.spec.endpointPickerRef.port.number}{"\n"}targetPorts={.spec.targetPorts[*].number}{"\n"}selector={.spec.selector.matchLabels}{"\n"}conditions={.status.parents[0].conditions[*].type} {.status.parents[0].conditions[*].status}{"\n"}messages={.status.parents[0].conditions[*].message}{"\n"}'

section "Pods"
run kubectl get pods -n "$NAMESPACE" -o wide --show-labels

section "Model Pods Matched By InferencePool"
APP_SELECTOR="$(jsonpath get inferencepool "$POOL" -n "$NAMESPACE" -o go-template='{{range $k,$v := .spec.selector.matchLabels}}{{printf "%s=%s," $k $v}}{{end}}')"
APP_SELECTOR="${APP_SELECTOR%,}"
if [[ -n "$APP_SELECTOR" ]]; then
  run kubectl get pods -n "$NAMESPACE" -l "$APP_SELECTOR" -o wide --show-labels
else
  echo "No selector found on InferencePool/$POOL"
fi

section "Generated InferencePool Service And Endpoints"
IP_SERVICE="$(jsonpath get svc -n "$NAMESPACE" -l "istio.io/inferencepool-name=$POOL" -o jsonpath='{.items[0].metadata.name}')"
if [[ -n "$IP_SERVICE" ]]; then
  echo "InferencePool service: $IP_SERVICE"
  run kubectl get svc "$IP_SERVICE" -n "$NAMESPACE" -o yaml
  run kubectl get endpointslice -n "$NAMESPACE" -l "kubernetes.io/service-name=$IP_SERVICE" \
    -o jsonpath='{range .items[*].endpoints[*]}endpoint={.targetRef.name} ip={.addresses[*]} ready={.conditions.ready} serving={.conditions.serving} terminating={.conditions.terminating}{"\n"}{end}{range .items[*].ports[*]}port={.port} name={.name} protocol={.protocol}{"\n"}{end}'
else
  echo "No generated InferencePool service found for $POOL"
fi

section "EPP Service And Endpoints"
EPP_SERVICE="$(jsonpath get inferencepool "$POOL" -n "$NAMESPACE" -o jsonpath='{.spec.endpointPickerRef.name}')"
if [[ -n "$EPP_SERVICE" ]]; then
  run kubectl get svc "$EPP_SERVICE" -n "$NAMESPACE" -o yaml
  run kubectl get endpointslice -n "$NAMESPACE" -l "kubernetes.io/service-name=$EPP_SERVICE" \
    -o jsonpath='{range .items[*].endpoints[*]}endpoint={.targetRef.name} ip={.addresses[*]} ready={.conditions.ready} serving={.conditions.serving}{"\n"}{end}{range .items[*].ports[*]}port={.port} name={.name} protocol={.protocol}{"\n"}{end}'
else
  echo "No EPP service found on InferencePool/$POOL"
fi

section "Gateway"
run kubectl get gateway "$GATEWAY" -n "$GATEWAY_NAMESPACE" \
  -o jsonpath='programmed={.status.conditions[?(@.type=="Programmed")].status}{"\n"}address={.status.addresses[*].value}{"\n"}attachedRoutes={.status.listeners[*].attachedRoutes}{"\n"}'
run kubectl get pods -n "$GATEWAY_NAMESPACE" \
  -l "gateway.networking.k8s.io/gateway-name=$GATEWAY" -o wide

section "Curl Through Gateway"
run curl -i --max-time 10 "$GATEWAY_URL/health"
printf '\n'
run sh -c "curl -sS --max-time 20 '$GATEWAY_URL/v1/models' | head -c 1200; printf '\n'"

section "Recent Gateway ext_proc Warnings"
GW_POD="$(jsonpath get pod -n "$GATEWAY_NAMESPACE" -l "gateway.networking.k8s.io/gateway-name=$GATEWAY" -o jsonpath='{.items[0].metadata.name}')"
if [[ -n "$GW_POD" ]]; then
  run kubectl logs "$GW_POD" -n "$GATEWAY_NAMESPACE" --since=5m --tail=200
else
  echo "No gateway pod found"
fi

section "EPP Logs"
if [[ -n "$EPP_SERVICE" ]]; then
  run kubectl logs -n "$NAMESPACE" -l "inferencepool=$EPP_SERVICE" --tail=120
fi

section "Summary Hints"
cat <<'EOF'
Healthy minimum:
- HTTPRoute: Accepted=True and ResolvedRefs=True
- InferencePool: Accepted=True and ResolvedRefs=True
- InferencePool EndpointSlice: endpoint ready=true serving=true
- InferencePool target port should match the serving entrypoint. In this setup it is 8000 because routing-proxy listens on 8000 and forwards to vLLM on 8200.
- Gateway curl /health should return HTTP/1.1 200 OK

If Gateway returns 500 while direct pod/service endpoints are ready:
- Check ext_proc warnings.
- If failureMode=FailClose, EPP/ext_proc errors fail the request.
- If failureMode=FailOpen, those warnings are still worth investigating, but they should not block model traffic.
EOF
