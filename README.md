# llm-d PCA Local Dependencies

This directory vendors the exact CRD content used by:

- `/home/etty/llm-d/guides/prereq/gateway-provider/install-gateway-provider-dependencies.sh`

Vendored versions:

- `Gateway API CRDs`: `v1.5.1`
- `Gateway API Inference Extension CRDs`: `v1.4.0`

What the original script installs:

- `Gateway API` CRDs from `https://github.com/kubernetes-sigs/gateway-api/config/crd/?ref=v1.5.1`
- `Gateway API Inference Extension` CRDs from `https://github.com/kubernetes-sigs/gateway-api-inference-extension/config/crd/?ref=v1.4.0`

Local installation:

```bash
cd /home/etty/llm-d-pca
chmod +x ./install-gateway-provider-dependencies-local.sh
./install-gateway-provider-dependencies-local.sh
```

Local removal:

```bash
cd /home/etty/llm-d-pca
./install-gateway-provider-dependencies-local.sh delete
```

Useful verification:

```bash
kubectl api-resources --api-group=gateway.networking.k8s.io
kubectl api-resources --api-group=inference.networking.k8s.io
kubectl api-resources --api-group=inference.networking.x-k8s.io
```

Install local Istio control plane with Helm:

```bash
cd /home/etty/llm-d-pca
chmod +x ./install-istio-local.sh
./install-istio-local.sh
```

Equivalent manual Helm commands:

```bash
kubectl create namespace istio-system --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install istio-base /home/etty/llm-d-pca/charts/base \
  -n istio-system \
  --wait

helm upgrade --install istiod /home/etty/llm-d-pca/charts/istiod \
  -n istio-system \
  -f /home/etty/llm-d-pca/istio/istiod-values-llmd.yaml \
  --wait
```

Install the precise-prefix-cache-aware stack with Helm:

```bash
export NAMESPACE=llm-d-precise
export RELEASE_NAME_POSTFIX=kv-events

cd /home/etty/llm-d-pca
chmod +x ./install-precise-prefix-cache-aware.sh
./install-precise-prefix-cache-aware.sh
```

The local values files live directly under each chart:

- `/home/etty/llm-d-pca/charts/llm-d-infra/values-snd.yaml`
- `/home/etty/llm-d-pca/charts/inferencepool/values-snd.yaml`
- `/home/etty/llm-d-pca/charts/llm-d-modelservice/values-snd.yaml`

Install monitoring from this repo-local copy:

```bash
cd /home/etty/llm-d-pca
chmod +x ./install-monitoring-local.sh
./install-monitoring-local.sh
```

If you only want the Prometheus Operator CRDs required for `ServiceMonitor` / `PodMonitor`:

```bash
cd /home/etty/llm-d-pca
./install-monitoring-local.sh -c
```
