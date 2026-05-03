# Gateway Health Guide

Use this guide when you want to answer one question:

"If a request goes through the gateway to the model, where do I look to prove each hop is healthy?"

The components in this setup are:

1. `kgateway` controller in `kgateway-system`
2. `Gateway` object in `llm-d-infra`
3. `HTTPRoute` object in `llm-d-precise`
4. `InferencePool` object in `llm-d-precise`
5. `EPP` deployment `gaie-kv-events-epp`
6. Model deployment `ms-kv-events-llm-d-modelservice-decode`

Important note:

- `HTTPRoute` is a Kubernetes object, not a pod. It has no logs of its own.
- To debug `HTTPRoute`, check its `status` and the `kgateway` controller logs.

## 1. Quick Green Check

Run these first:

```bash
kubectl get pods -n kgateway-system
kubectl get pods -n llm-d-precise
kubectl get gateway -n llm-d-infra
kubectl get httproute -n llm-d-precise
kubectl get inferencepool -n llm-d-precise
```

Healthy in this environment looks like:

```bash
kgateway-system:
kgateway-df8f779d9-px9fz   1/1 Running

llm-d-precise:
gaie-kv-events-epp-...     2/2 Running
ms-kv-events-...decode...  1/1 Running
```

If one of these is not ready, continue with the relevant section below.

## 2. kgateway Controller

### Status

```bash
kubectl get pod kgateway-df8f779d9-px9fz -n kgateway-system -o wide
kubectl describe pod kgateway-df8f779d9-px9fz -n kgateway-system
```

Healthy signs:

- `READY` is `1/1`
- `STATUS` is `Running`
- readiness probe stops failing

### Logs

```bash
kubectl logs kgateway-df8f779d9-px9fz -n kgateway-system --tail=200
```

What to look for in healthy logs:

- `caches warm!`
- `successfully acquired lease`
- `Starting Controller`
- `reconciling gateway`
- `patched gateway status`
- no repeating sync loop errors

Good examples from this cluster:

- `caches warm!`
- `successfully acquired lease kgateway-system/kgateway`
- `reconciling gateway`
- `patched gateway status`

Bad signs:

- repeated `waiting for sync...`
- repeated `failed to list`
- repeated `the server could not find the requested resource`
- repeated health/readiness failures

In this cluster, the bad pattern we fixed was:

- `failed to list *v1alpha2.TLSRoute`

That meant `kgateway` expected a served `TLSRoute` API version that was not exposed by the CRD.

## 3. Gateway Object

### Status

```bash
kubectl get gateway llm-d-infra-inference-gateway -n llm-d-infra -o yaml
```

What to check:

- `status.conditions`
- `status.listeners`
- `status.addresses`

Healthy signs in this cluster:

- `Accepted=True`
- `Programmed=True`
- `status.addresses[0].value=10.106.48.36`
- `listeners[].attachedRoutes: 1`

You can extract just the useful parts:

```bash
kubectl get gateway llm-d-infra-inference-gateway -n llm-d-infra \
  -o jsonpath='{"conditions.type: "}{.status.conditions[*].type}{"\n"}{"conditions.status: "}{.status.conditions[*].status}{"\n"}{"listeners.attachedRoutes: "}{.status.listeners[*].attachedRoutes}{"\n"}{"addresses: "}{.status.addresses[*].value}{"\n"}'
```

Bad signs:

- `Accepted=False`
- `Programmed=False`
- no `status.addresses`
- `attachedRoutes: 0` when you expect traffic

## 4. HTTPRoute

### Status

```bash
kubectl get httproute llm-d-kv-events -n llm-d-precise -o yaml
```

Compact key/value view:

```bash
kubectl get httproute llm-d-kv-events -n llm-d-precise \
  -o jsonpath='{"parentRef.name: "}{.status.parents[0].parentRef.name}{"\n"}{"parentRef.namespace: "}{.status.parents[0].parentRef.namespace}{"\n"}{"controllerName: "}{.status.parents[0].controllerName}{"\n"}{"conditions.type: "}{.status.parents[0].conditions[*].type}{"\n"}{"conditions.status: "}{.status.parents[0].conditions[*].status}{"\n"}{"conditions.message: "}{.status.parents[0].conditions[*].message}{"\n"}'
```

Healthy signs:

- `status.parents` exists
- `controllerName: kgateway.dev/kgateway`
- `Accepted=True`
- `ResolvedRefs=True`

Good example from this cluster:

- `Successfully accepted Route`
- `Successfully resolved all references`

Bad signs:

- no `status.parents`
- `Accepted=False`
- `ResolvedRefs=False`
- wrong parent gateway name or namespace
- wrong backend `InferencePool` name

### Useful describe view

```bash
kubectl describe httproute llm-d-kv-events -n llm-d-precise
```

If the route is broken, usually you will see the reason here before you see it anywhere else.

## 5. InferencePool

### Status

```bash
kubectl get inferencepool gaie-kv-events -n llm-d-precise -o yaml
```

Compact key/value view:

```bash
kubectl get inferencepool gaie-kv-events -n llm-d-precise \
  -o jsonpath='{"parentRef.name: "}{.status.parents[0].parentRef.name}{"\n"}{"parentRef.namespace: "}{.status.parents[0].parentRef.namespace}{"\n"}{"conditions.type: "}{.status.parents[0].conditions[*].type}{"\n"}{"conditions.status: "}{.status.parents[0].conditions[*].status}{"\n"}{"conditions.message: "}{.status.parents[0].conditions[*].message}{"\n"}{"endpointPickerRef.name: "}{.spec.endpointPickerRef.name}{"\n"}{"targetPorts: "}{.spec.targetPorts[*].number}{"\n"}'
```

Healthy signs:

- `status.parents` exists
- `Accepted=True`
- `ResolvedRefs=True`

Good example from this cluster:

- `InferencePool has been accepted by controller kgateway.dev/kgateway`
- `All InferencePool references have been resolved`

Bad signs:

- no `status.parents`
- unresolved refs to the EPP service
- route exists but controller did not accept the pool

## 6. EPP Deployment

This is the scheduler / endpoint picker that sits behind the `InferencePool`.

### Status

```bash
kubectl get deploy gaie-kv-events-epp -n llm-d-precise -o yaml
kubectl get pods -n llm-d-precise -l inferencepool=gaie-kv-events-epp
```

Healthy signs:

- deployment has `Available=True`
- pod is `2/2 Running`
- readiness probe passes on gRPC health port `9003`

### Logs

The deployment has two containers:

1. `epp`
2. `tokenizer-uds`

Check both when debugging:

```bash
kubectl logs deploy/gaie-kv-events-epp -n llm-d-precise -c epp --tail=200
kubectl logs deploy/gaie-kv-events-epp -n llm-d-precise -c tokenizer-uds --tail=200
```

Healthy signs in `epp` logs:

- request flow logs
- chosen endpoint logs
- response generated logs

Good examples from this cluster:

- `EPP received request`
- `Request handled`
- `Response generated`
- `endpoint":"10.244.0.12:8000"`

Healthy signs in `tokenizer-uds` logs:

- `Server started`
- `Initializing tokenizer`
- `Successfully initialized tokenizer`

Good examples from this cluster:

- `gRPC server started on /tmp/tokenizer/tokenizer-uds.socket`
- `Successfully initialized tokenizer for model: Qwen/Qwen2.5-0.5B-Instruct`

Bad signs:

- missing `HF_TOKEN` secret
- endless cache/watch reconnect noise with no request handling
- no endpoint selected
- gRPC probe failures on `9003`

## 7. Model Deployment

This is the actual vLLM server.

### Status

```bash
kubectl get deploy ms-kv-events-llm-d-modelservice-decode -n llm-d-precise -o yaml
kubectl get pods -n llm-d-precise -l llm-d.ai/role=decode
```

Healthy signs:

- deployment has `Available=True`
- pod is `1/1 Running`
- startup/readiness probe passes on `/v1/models`

### Logs

```bash
kubectl logs deploy/ms-kv-events-llm-d-modelservice-decode -n llm-d-precise --tail=200
```

Healthy signs:

- model weights downloaded
- engine became ready
- API server started
- health checks continue to pass

Good examples from this cluster:

- `Time spent downloading weights for Qwen/Qwen2.5-0.5B-Instruct`
- `Loading weights took`
- `READY from local core engine process 0`
- `Starting vLLM API server 0 on http://0.0.0.0:8000`
- `Called check_health.`

Bad signs:

- stuck on image pull
- stuck on Hugging Face download
- stuck on compile/warmup forever
- repeated `connection refused` on `/v1/models`

Important local note:

- In this cluster we had to add `HF_HUB_DISABLE_XET=1`
- We also had to add `--enforce-eager`

Without those two, the model pod either stalled during Hugging Face fetch or during CPU compile/warmup.

## 8. End-to-End Through Gateway

### Check that the Gateway sees the model

```bash
curl -s http://10.106.48.36/v1/models
```

Healthy sign:

- returns `Qwen/Qwen2.5-0.5B-Instruct`

### Send a test request through the Gateway

```bash
curl -s http://10.106.48.36/v1/chat/completions \
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

- returns a normal OpenAI-compatible response with an assistant message

Good example from this cluster:

- `Pong! Via Gateway!`

## 9. Fast Triage Order

If a request through the gateway fails, check in this order:

1. `kubectl get pods -n kgateway-system`
2. `kubectl get pods -n llm-d-precise`
3. `kubectl get gateway llm-d-infra-inference-gateway -n llm-d-infra -o yaml`
4. `kubectl get httproute llm-d-kv-events -n llm-d-precise -o yaml`
5. `kubectl get inferencepool gaie-kv-events -n llm-d-precise -o yaml`
6. `kubectl logs deploy/gaie-kv-events-epp -n llm-d-precise -c epp --tail=200`
7. `kubectl logs deploy/ms-kv-events-llm-d-modelservice-decode -n llm-d-precise --tail=200`
8. `curl -s http://10.106.48.36/v1/models`
9. `curl -s http://10.106.48.36/v1/chat/completions ...`

## 10. One-Screen Command Set

If you want a single block to run during debugging:

```bash
kubectl get pods -n kgateway-system
kubectl get pods -n llm-d-precise
kubectl get gateway llm-d-infra-inference-gateway -n llm-d-infra -o yaml
kubectl get httproute llm-d-kv-events -n llm-d-precise -o yaml
kubectl get inferencepool gaie-kv-events -n llm-d-precise -o yaml
kubectl logs kgateway-df8f779d9-px9fz -n kgateway-system --tail=80
kubectl logs deploy/gaie-kv-events-epp -n llm-d-precise -c epp --tail=80
kubectl logs deploy/ms-kv-events-llm-d-modelservice-decode -n llm-d-precise --tail=80
curl -s http://10.106.48.36/v1/models
```

If all of that looks healthy, the path is usually fine end to end.
