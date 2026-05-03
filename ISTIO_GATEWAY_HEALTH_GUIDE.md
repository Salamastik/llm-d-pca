# Istio Gateway Health Guide

Use this guide when you want to answer:

"Is the Istio-based gateway path healthy, and if not, where is it failing?"

This guide is for the Istio setup currently installed in:

- namespace: `istio-system`
- Istio control plane release: `istiod`
- llm-d infra release: `infra-istio`
- Gateway name: `infra-istio-inference-gateway`
- Gateway service: `infra-istio-inference-gateway-istio`

The main components are:

1. `istiod` control plane
2. Istio-managed `Gateway` object
3. Istio gateway data plane deployment
4. `HTTPRoute` attached to the Istio gateway
5. `InferencePool`
6. `EPP`
7. model server

Important notes:

- `Gateway` and `HTTPRoute` are Kubernetes objects, not pods.
- They do not have logs of their own.
- For them, you mainly inspect `status`, `describe`, and controller logs from `istiod`.

## 1. Quick Green Check

Run these first:

```bash
env HELM_NO_PLUGINS=1 helm list -n istio-system
kubectl get pods -n istio-system
kubectl get gateway -n istio-system
kubectl get svc -n istio-system
```

Healthy in this environment looks like:

```bash
istio-system:
istiod-...                                 1/1 Running
infra-istio-inference-gateway-istio-...    1/1 Running
```

The release should show:

- `infra-istio` with `STATUS: deployed`
- `istiod` with `STATUS: deployed`
- `istio-base` with `STATUS: deployed`

## 2. istiod Control Plane

### Status

```bash
kubectl get pods -n istio-system -o wide
kubectl describe deployment istiod -n istio-system
kubectl get endpoints istiod -n istio-system -o yaml
```

Healthy signs:

- `istiod` pod is `1/1 Running`
- deployment has `Available=True`
- service `istiod` exists
- endpoints exist and point to the running `istiod` pod

### Logs

```bash
kubectl logs deploy/istiod -n istio-system --tail=200
```

What to look for in healthy logs:

- `marking server ready`
- `starting secure gRPC discovery service`
- `starting webhook service`
- lots of `synced`

Good examples from this cluster:

- `All caches have been synced up ..., marking server ready`
- `starting secure gRPC discovery service at [::]:15012`
- `starting webhook service at [::]:15017`

Bad signs:

- repeated `failed to sync`
- repeated webhook errors that never recover
- repeated `not ready` without a later ready transition

Startup notes:

- Short-lived webhook retry messages during startup can be normal
- What matters is that `istiod` reaches ready state afterward

## 3. Istio Gateway Object

### Status

```bash
kubectl get gateway infra-istio-inference-gateway -n istio-system -o yaml
```

Compact key/value view:

```bash
kubectl get gateway infra-istio-inference-gateway -n istio-system \
  -o jsonpath='{"name: "}{.metadata.name}{"\n"}{"gatewayClassName: "}{.spec.gatewayClassName}{"\n"}{"conditions.type: "}{.status.conditions[*].type}{"\n"}{"conditions.status: "}{.status.conditions[*].status}{"\n"}{"listener.attachedRoutes: "}{.status.listeners[*].attachedRoutes}{"\n"}{"addresses: "}{.status.addresses[*].value}{"\n"}'
```

Healthy signs:

- `Accepted=True`
- `Programmed=True`
- `ResolvedRefs=True` on the listener
- `addresses` is not empty

Good example from this cluster:

- `Accepted=True`
- `Programmed=True`
- `addresses: infra-istio-inference-gateway-istio.istio-system.svc.cluster.local`

Important interpretation:

- `attachedRoutes: 0` is not automatically a problem
- It only means no `HTTPRoute` is currently attached

Bad signs:

- `Accepted=False`
- `Programmed=False`
- no address assigned
- route expected but `attachedRoutes` stays `0`

### Useful describe view

```bash
kubectl describe gateway infra-istio-inference-gateway -n istio-system
```

## 4. Istio Gateway Data Plane

This is the actual Istio-managed gateway pod behind the `Gateway` object.

### Status

```bash
kubectl get deploy infra-istio-inference-gateway-istio -n istio-system -o yaml
kubectl get pods -n istio-system -l gateway.networking.k8s.io/gateway-name=infra-istio-inference-gateway
kubectl get svc infra-istio-inference-gateway-istio -n istio-system -o yaml
```

Healthy signs:

- deployment has `Available=True`
- pod is `1/1 Running`
- readiness passes on `/healthz/ready` via port `15021`
- service exists and selects the gateway pod

Good example from this cluster:

- service `infra-istio-inference-gateway-istio`
- ports `15021` and `80`
- readiness probe on `15021/healthz/ready`

### Logs

```bash
kubectl logs deploy/infra-istio-inference-gateway-istio -n istio-system --tail=200
```

Healthy signs:

- connection to `istiod`
- SDS starts
- ADS connections appear
- workload certificate generated

Good examples from this cluster:

- `Initializing with upstream address "istiod.istio-system.svc:15012"`
- `Starting SDS grpc server`
- `connected to delta upstream XDS server`
- `ADS: new connection`
- `generated new workload certificate`

Bad signs:

- repeated disconnect/reconnect loops
- no connection to `istiod`
- cert generation failures
- readiness probe failures on `15021`

## 5. HTTPRoute for Istio Gateway

If you attach traffic to the Istio gateway via Gateway API, check the route like this:

```bash
kubectl get httproute <route-name> -n <route-namespace> -o yaml
```

Compact key/value view:

```bash
kubectl get httproute <route-name> -n <route-namespace> \
  -o jsonpath='{"parentRef.name: "}{.status.parents[0].parentRef.name}{"\n"}{"parentRef.namespace: "}{.status.parents[0].parentRef.namespace}{"\n"}{"controllerName: "}{.status.parents[0].controllerName}{"\n"}{"conditions.type: "}{.status.parents[0].conditions[*].type}{"\n"}{"conditions.status: "}{.status.parents[0].conditions[*].status}{"\n"}{"conditions.message: "}{.status.parents[0].conditions[*].message}{"\n"}'
```

Healthy signs:

- `status.parents` exists
- `controllerName` points to Istio
- `Accepted=True`
- `ResolvedRefs=True`

Bad signs:

- no `status.parents`
- `Accepted=False`
- `ResolvedRefs=False`
- wrong gateway name or namespace
- wrong backend object

### Useful describe view

```bash
kubectl describe httproute <route-name> -n <route-namespace>
```

## 6. InferencePool

This remains the same logical checkpoint even if the north-south gateway changes.

### Status

```bash
kubectl get inferencepool <pool-name> -n <pool-namespace> -o yaml
```

Compact key/value view:

```bash
kubectl get inferencepool <pool-name> -n <pool-namespace> \
  -o jsonpath='{"parentRef.name: "}{.status.parents[0].parentRef.name}{"\n"}{"parentRef.namespace: "}{.status.parents[0].parentRef.namespace}{"\n"}{"conditions.type: "}{.status.parents[0].conditions[*].type}{"\n"}{"conditions.status: "}{.status.parents[0].conditions[*].status}{"\n"}{"conditions.message: "}{.status.parents[0].conditions[*].message}{"\n"}{"endpointPickerRef.name: "}{.spec.endpointPickerRef.name}{"\n"}{"targetPorts: "}{.spec.targetPorts[*].number}{"\n"}'
```

Healthy signs:

- `Accepted=True`
- `ResolvedRefs=True`
- endpoint picker service exists

## 7. EPP

The EPP behavior is the same regardless of whether traffic reached it through `kgateway` or Istio.

### Status

```bash
kubectl get deploy gaie-kv-events-epp -n llm-d-precise -o yaml
kubectl get pods -n llm-d-precise -l inferencepool=gaie-kv-events-epp
```

Healthy signs:

- deployment `Available=True`
- pod `2/2 Running`

### Logs

```bash
kubectl logs deploy/gaie-kv-events-epp -n llm-d-precise -c epp --tail=200
kubectl logs deploy/gaie-kv-events-epp -n llm-d-precise -c tokenizer-uds --tail=200
```

Healthy signs in `epp` logs:

- `EPP received request`
- `Request handled`
- `Response generated`
- selected model endpoint

Healthy signs in `tokenizer-uds` logs:

- `Server started`
- `Successfully initialized tokenizer`

## 8. Model Server

### Status

```bash
kubectl get deploy ms-kv-events-llm-d-modelservice-decode -n llm-d-precise -o yaml
kubectl get pods -n llm-d-precise -l llm-d.ai/role=decode
```

Healthy signs:

- deployment `Available=True`
- pod `1/1 Running`
- `/v1/models` readiness passes

### Logs

```bash
kubectl logs deploy/ms-kv-events-llm-d-modelservice-decode -n llm-d-precise --tail=200
```

Healthy signs:

- weights downloaded
- engine ready
- API server started
- health checks continue

Good examples from this cluster:

- `READY from local core engine process 0`
- `Starting vLLM API server 0 on http://0.0.0.0:8000`
- `Called check_health.`

## 9. Service Reachability of the Istio Gateway

Right now, the Istio gateway service in this cluster is:

- `infra-istio-inference-gateway-istio.istio-system.svc.cluster.local`

Check the service:

```bash
kubectl get svc infra-istio-inference-gateway-istio -n istio-system -o yaml
```

Compact key/value view:

```bash
kubectl get svc infra-istio-inference-gateway-istio -n istio-system \
  -o jsonpath='{"name: "}{.metadata.name}{"\n"}{"type: "}{.spec.type}{"\n"}{"clusterIP: "}{.spec.clusterIP}{"\n"}{"ports: "}{range .spec.ports[*]}{.name}{":"}{.port}{" "}{end}{"\n"}{"selector.gateway-name: "}{.spec.selector.gateway\.networking\.k8s\.io/gateway-name}{"\n"}'
```

Healthy signs:

- service exists
- selector matches the gateway pod
- service exposes `80` and `15021`

## 10. End-to-End Through Istio Gateway

After you attach an `HTTPRoute`, test the gateway directly.

If you are inside the cluster network:

```bash
curl -s http://infra-istio-inference-gateway-istio.istio-system.svc.cluster.local/v1/models
```

Or using ClusterIP from your current host, if reachable:

```bash
kubectl get svc infra-istio-inference-gateway-istio -n istio-system
curl -s http://<cluster-ip>/v1/models
```

For chat completions:

```bash
curl -s http://infra-istio-inference-gateway-istio.istio-system.svc.cluster.local/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "Qwen/Qwen2.5-0.5B-Instruct",
    "messages": [
      {"role": "user", "content": "Reply with exactly: pong"}
    ],
    "temperature": 0,
    "max_tokens": 16
  }'
```

Healthy sign:

- you get a normal OpenAI-compatible JSON response

## 11. Fast Triage Order

If the Istio path fails, check in this order:

1. `env HELM_NO_PLUGINS=1 helm list -n istio-system`
2. `kubectl get pods -n istio-system`
3. `kubectl get gateway infra-istio-inference-gateway -n istio-system -o yaml`
4. `kubectl get svc infra-istio-inference-gateway-istio -n istio-system -o yaml`
5. `kubectl logs deploy/infra-istio-inference-gateway-istio -n istio-system --tail=200`
6. `kubectl logs deploy/istiod -n istio-system --tail=200`
7. `kubectl get httproute <route-name> -n <route-namespace> -o yaml`
8. `kubectl get inferencepool <pool-name> -n <pool-namespace> -o yaml`
9. `kubectl logs deploy/gaie-kv-events-epp -n llm-d-precise -c epp --tail=200`
10. `kubectl logs deploy/ms-kv-events-llm-d-modelservice-decode -n llm-d-precise --tail=200`

## 12. One-Screen Command Set

```bash
env HELM_NO_PLUGINS=1 helm list -n istio-system
kubectl get pods -n istio-system
kubectl get gateway infra-istio-inference-gateway -n istio-system -o yaml
kubectl get svc infra-istio-inference-gateway-istio -n istio-system -o yaml
kubectl logs deploy/infra-istio-inference-gateway-istio -n istio-system --tail=80
kubectl logs deploy/istiod -n istio-system --tail=80
```

If all of that looks healthy, the Istio gateway installation itself is in good shape. The next likely failure point is usually the missing or misconfigured `HTTPRoute`.
