<!--
SPDX-FileCopyrightText: Copyright (c) 2026 KubeTEE AI LTD
SPDX-License-Identifier: Apache-2.0
-->

# NemoClaw Helm chart (KubeTEE)

[KubeTEE AI LTD](https://kubetee.ai) — deploy the NemoClaw **sandbox container image** (OpenClaw + Nemotron) on **KubeTEE RKE2** clusters.

**Defaults** match Traefik from the monorepo [`rke2-traefik-additional-manifest.yaml`](../../../../rke2-traefik-additional-manifest.yaml) (Gateway `traefik-gateway` in `kube-system`, HTTPS listener `websecure`, default IngressClass). Adjust only what differs on your cluster.

**Documentation:** [KUBETEE.md](./KUBETEE.md)

## Build the image

From the NemoClaw repo root, target **linux/amd64** (required for KubeTEE nodes and when building on Apple Silicon).
When you cut a versioned image, tag it with the plain version number such as `2026.3.22`, and also push `latest` from the same image:

```bash
docker build --platform linux/amd64 \
  -f Dockerfile.kubetee \
  -t YOUR_REGISTRY/nemoclaw:2026.3.22 \
  -t YOUR_REGISTRY/nemoclaw:latest .
docker push YOUR_REGISTRY/nemoclaw:2026.3.22
docker push YOUR_REGISTRY/nemoclaw:latest
```

## Install

Set the image repository and NVIDIA API key; the chart defaults to **`image.tag=latest`**. Set the public hostname (first entry drives both the **HTTPRoute** and **`CHAT_UI_URL`**, which is set in the Deployment to `https://<hostname>` when `httpRoute.enabled` is true):

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

If you pass `nvidiaApiKey`, the chart creates a Secret named `<release>-nvidia`, stores the NVIDIA key under `nvidia-api-key` by default, and also creates a stable `openclaw-gateway-token` used for token-mode gateway auth:

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

If your existing Secret also contains `openclaw-gateway-token`, the chart maps it to `OPENCLAW_GATEWAY_TOKEN` so the gateway token stays stable across pod restarts and upgrades.

The init-time config patcher also sees the same namespace-specific secret-backed env vars, which lets the chart derive OpenClaw config from runtime inputs such as `TELEGRAM_BOT_TOKEN`, `SLACK_BOT_TOKEN`, and `SLACK_APP_TOKEN` without baking tenant-specific settings into the image. The main container uses the same pattern for `opencode`, so you can point coding-agent traffic at an in-cluster NIM endpoint with either `NVIDIA_API_KEY` or a separate env such as `OPENCODE_NIM_API_KEY`.

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
| `image.repository`, `image.tag` | Image built for **linux/amd64** from `Dockerfile.kubetee`; the chart defaults `image.tag` to `latest`, while versioned pushes should use plain tags like `2026.3.22` |
| `nvidiaApiKey` or `existingSecret` | NVIDIA API key ([build.nvidia.com](https://build.nvidia.com)) |
| `codingAgent.*` | Enables delegated coding support and configures `opencode` to use an OpenAI-compatible backend such as in-cluster NVIDIA NIM |
| `gateway.controlUi.*` | Controls the risky OpenClaw Control UI auth/device behavior; `dangerouslyDisableDeviceAuth` defaults to `false` and `allowInsecureAuth` remains configurable for this deployment |
| `httpRoute.*` | HTTPRoute → Traefik Gateway (`traefik-gateway` / `websecure` by default) |
| `service.externalDns` | Enabled by default; adds ExternalDNS **hostname + target** on the Service and auto-targets Traefik |
| `httpRoute.tls.certManager` | Optional cert-manager `Certificate` support (disabled by default on KubeTEE) |
| `args` | Optional extra container args (default empty; `command` is fixed in the Deployment template) |
| `channels.telegram.*`, `channels.slack.*` | Optional Telegram/Slack auto-config policy for namespace-specific employee or enterprise deployments |
| `configPatch.extraEnv` | Extra init-container env vars for namespace-specific config generation |
| `persistence.workspace.*` | Optional PVC for the writable OpenClaw runtime state at `/sandbox/.openclaw-data` (enabled by default; key name retained for backward compatibility) |
| `networkPolicy.enabled` | Optional egress policy |

See `values.yaml` for the full list.

## Coding agent with in-cluster NIM

The KubeTEE image now installs `opencode`, and the chart can generate a global `opencode` config at runtime for the bundled OpenClaw `coding-agent` skill.

Set these values when your in-cluster NIM Service and model are ready:

```yaml
codingAgent:
  enabled: true
  runtime: opencode
  toolsProfile: full
  opencode:
    baseUrl: "http://nim-llm.nemo.svc.cluster.local:8000/v1"
    model: "meta/llama-3.1-70b-instruct"
    modelName: "NIM Llama 3.1 70B"
    apiKeyEnv: "OPENCODE_NIM_API_KEY" # or NVIDIA_API_KEY
```

If you use a separate key for the coding model, add it to your Secret with a name such as `opencode-nim-api-key`. The chart normalizes that to `OPENCODE_NIM_API_KEY` automatically for the main container.

## License

The chart is licensed under [Apache License 2.0](LICENSE). Copyright and attribution: see [NOTICE](NOTICE).
