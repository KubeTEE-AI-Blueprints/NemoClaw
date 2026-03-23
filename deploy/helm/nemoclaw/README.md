<!--
SPDX-FileCopyrightText: Copyright (c) 2026 KubeTEE AI LTD
SPDX-License-Identifier: Apache-2.0
-->

# NemoClaw Helm chart (KubeTEE)

[KubeTEE AI LTD](https://kubetee.ai) — deploy the NemoClaw **sandbox container image** (OpenClaw + Nemotron) on **KubeTEE RKE2** clusters.

**Defaults** match Traefik from the monorepo [`rke2-traefik-additional-manifest.yaml`](../../../../rke2-traefik-additional-manifest.yaml) (Gateway `traefik-gateway` in `kube-system`, HTTPS listener `websecure`, default IngressClass). Adjust only what differs on your cluster.

**Documentation:** [KUBETEE.md](./KUBETEE.md)

## Build the image

From the NemoClaw repo root, target **linux/amd64** (required for KubeTEE nodes and when building on Apple Silicon):

```bash
docker build --platform linux/amd64 -t YOUR_REGISTRY/nemoclaw:TAG .
docker push YOUR_REGISTRY/nemoclaw:TAG
```

## Install

Set the image and NVIDIA API key; set the public hostname (first entry drives both the **HTTPRoute** and **`CHAT_UI_URL`**, which is set in the Deployment to `https://<hostname>` when `httpRoute.enabled` is true):

```bash
helm upgrade --install nemoclaw . -n nemoclaw --create-namespace \
  --set image.repository=YOUR_REGISTRY/nemoclaw \
  --set nvidiaApiKey="$NVIDIA_API_KEY" \
  --set 'httpRoute.hostnames[0]=nemoclaw-staging.kubetee.ai'
```

Minimal install (uses placeholder `nemoclaw.example.com` in `values.yaml` — change before production):

```bash
helm upgrade --install nemoclaw . -n nemoclaw --create-namespace \
  --set image.repository=YOUR_REGISTRY/nemoclaw \
  --set nvidiaApiKey="$NVIDIA_API_KEY"
```

With **`httpRoute.enabled=false`**, there is no HTTPRoute; **`CHAT_UI_URL`** is set to **`http://127.0.0.1:<service.port>`** (port-forward / local UI).

## Secrets

### Let the chart create the NVIDIA secret

If you pass `nvidiaApiKey`, the chart creates a Secret named `<release>-nvidia` and stores the key under `nvidia-api-key` by default:

```bash
helm upgrade --install nemoclaw . -n nemoclaw --create-namespace \
  --set image.repository=YOUR_REGISTRY/nemoclaw \
  --set nvidiaApiKey="$NVIDIA_API_KEY"
```

If you also want the chart-managed Secret to contain more keys, put them under `secret.extraStringData`. The chart will create them in the same Secret and automatically expose them to the main container as normalized environment variables:

```yaml
secret:
  extraStringData:
    github-token: "ghp_xxx"
    openai-api-key: "sk-xxx"
```

### Use an existing Secret

If you want to manage the Secret yourself, create it first and point the chart at it with `existingSecret`. By default the chart reads the NVIDIA key from `nvidia-api-key`, so you only need `existingSecretKey` when your Secret uses a different key name:

```bash
kubectl create secret generic nemoclaw-secrets -n nemoclaw \
  --from-literal=nvidia-api-key="$NVIDIA_API_KEY"

helm upgrade --install nemoclaw . -n nemoclaw --create-namespace \
  --set image.repository=YOUR_REGISTRY/nemoclaw \
  --set existingSecret=nemoclaw-secrets \
  --set 'httpRoute.hostnames[0]=nemoclaw-staging.kubetee.ai'
```

### Put multiple keys in the same Secret

You can also create one Secret manifest file that contains the NVIDIA key plus any other secrets you want to keep together:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: nemoclaw-secrets
  namespace: nemoclaw
type: Opaque
stringData:
  nvidia-api-key: "${NVIDIA_API_KEY}"
  github-token: "${GITHUB_TOKEN}"
  openai-api-key: "${OPENAI_API_KEY}"
```

Apply that file, then install the chart with `existingSecret=nemoclaw-secrets`:

```bash
kubectl apply -f nemoclaw-secrets.yaml

helm upgrade --install nemoclaw . -n nemoclaw --create-namespace \
  --set image.repository=YOUR_REGISTRY/nemoclaw \
  --set existingSecret=nemoclaw-secrets
```

The chart always reads the key configured by `existingSecretKey` for `NVIDIA_API_KEY`. It now also auto-exposes every other key it finds in that Secret to the main container as environment variables after normalizing the names:

- `github-token` -> `GITHUB_TOKEN`
- `openai-api-key` -> `OPENAI_API_KEY`
- `SLACK_BOT_TOKEN` -> `SLACK_BOT_TOKEN`

For `existingSecret`, this automatic expansion uses Helm `lookup`, so the Secret must already exist in the namespace before `helm upgrade --install` runs.

You can still use `extraEnv` for explicit overrides or for environment variables that should not come from the shared Secret, for example:

```yaml
extraEnv:
  - name: GITHUB_TOKEN
    valueFrom:
      secretKeyRef:
        name: nemoclaw-secrets
        key: github-token
  - name: OPENAI_API_KEY
    valueFrom:
      secretKeyRef:
        name: nemoclaw-secrets
        key: openai-api-key
```

## Values (high level)

| Key | Description |
| --- | --- |
| `image.repository`, `image.tag` | Image built for **linux/amd64** from the NemoClaw `Dockerfile` (required) |
| `nvidiaApiKey` or `existingSecret` | NVIDIA API key ([build.nvidia.com](https://build.nvidia.com)) |
| `httpRoute.*` | HTTPRoute → Traefik Gateway (`traefik-gateway` / `websecure` by default) |
| `service.externalDns` | Enabled by default; adds ExternalDNS **hostname + target** on the Service and auto-targets Traefik |
| `httpRoute.tls.certManager` | Optional cert-manager `Certificate` support (disabled by default on KubeTEE) |
| `args` | Optional extra container args (default empty; `command` is fixed in the Deployment template) |
| `persistence.workspace.*` | Optional PVC for `/sandbox/.openclaw-data/workspace` (enabled by default) |
| `networkPolicy.enabled` | Optional egress policy |

See `values.yaml` for the full list.

## License

The chart is licensed under [Apache License 2.0](LICENSE). Copyright and attribution: see [NOTICE](NOTICE).
