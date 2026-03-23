<!--
SPDX-FileCopyrightText: Copyright (c) 2026 KubeTEE AI LTD
SPDX-License-Identifier: Apache-2.0
-->

# NemoClaw Helm chart — KubeTEE notes

**KubeTEE AI LTD** — [kubetee.ai](https://kubetee.ai)

This chart is **only for KubeTEE RKE2** clusters. Networking defaults assume **Traefik** is installed as in the monorepo **[`rke2-traefik-additional-manifest.yaml`](../../../../rke2-traefik-additional-manifest.yaml)** (`helm.cattle.io/v1` `HelmChart` in `kube-system`, Traefik chart ~39.x: `kubernetesGateway`, default `Gateway` **`traefik-gateway`**, HTTPS listener **`websecure`**, default IngressClass). If your management cluster differs, change `httpRoute.parentRefs` (confirm with `kubectl get gateway -A`).

## What upstream NemoClaw does

The [NemoClaw README](../../README.md) describes a **host** workflow: Docker, the **OpenShell** CLI, and a **sandbox** container built from this repo’s `Dockerfile`. The host runs `openshell gateway start`, registers inference providers, then `openshell sandbox create` to build and run the sandbox image. Inference from the agent is normally proxied through the gateway at `https://inference.local/v1`.

## What this Helm chart does

This chart runs the **same sandbox image** as a Kubernetes `Deployment`:

1. **Init container** copies `openclaw.json` from the image and rewrites the NVIDIA provider to call **`https://integrate.api.nvidia.com/v1`** directly with your API key. That avoids the OpenShell `inference.local` proxy, which is not available when OpenShell is not running on the node.
2. The main container runs **`/usr/local/bin/nemoclaw-start`**, which now also auto-syncs the same local onboarding artifacts that `nemoclaw onboard` would create for NVIDIA Endpoint usage: **`~/.nemoclaw/credentials.json`** (with `NVIDIA_API_KEY`) and **`~/.nemoclaw/config.json`** (endpoint, model, provider metadata). It then starts the OpenClaw gateway inside the pod on **`GATEWAY_PORT`** (Helm **`service.port`**, default **18789**) with **`openclaw gateway run --bind lan --port …`** so the process listens on **all interfaces**, not loopback. Optional auto-pairing: see `scripts/nemoclaw-start.sh`.
3. The chart can now provision a **workspace PVC** mounted at **`/sandbox/.openclaw-data/workspace`** so files under the OpenClaw workspace survive pod restarts. This follows the same persistence idea used by the upstream OpenClaw Kubernetes manifests, adapted to NemoClaw’s split writable-state layout.

### What you do *not* get vs full OpenShell

- OpenShell **gateway** (k3s-in-Docker), **Landlock/seccomp/netns** sandboxing, and **declarative egress** from the README are **not** reproduced by this chart alone.
- For similar isolation on Kubernetes you would use your cluster’s policies (NetworkPolicy, PodSecurity, confidential runtimes, etc.) — the optional `networkPolicy` in this chart only sketches HTTPS egress.
- Because of that, the chart does **not** run the full host-side `nemoclaw onboard` workflow inside the pod. Instead, it automates the onboarding state that the README expects while keeping inference pointed at the direct NVIDIA endpoint configured for Kubernetes.

## Build the image

From the **NemoClaw repository root** (where `Dockerfile.kubetee` lives). **Use `linux/amd64`** so the image runs on KubeTEE GPU nodes (including when you build on Apple Silicon):

```bash
docker build --platform linux/amd64 -f Dockerfile.kubetee -t <registry>/<project>/nemoclaw:<tag> . \
&& docker push <registry>/<project>/nemoclaw:<tag>
```

You can pass build args such as `NEMOCLAW_MODEL` and `CHAT_UI_URL` as documented in the `Dockerfile`.

## Install

```bash
helm upgrade --install nemoclaw ./deploy/helm/nemoclaw \
  -n <namespace> --create-namespace \
  --set image.repository=<registry>/<project>/nemoclaw \
  --set image.tag=<tag> \
  --set nvidiaApiKey=$NVIDIA_API_KEY
```

Or create a Secret yourself and reference it:

```bash
kubectl create secret generic nemoclaw-nvidia -n <namespace> \
  --from-literal=nvidia-api-key="$NVIDIA_API_KEY"
```

```bash
helm upgrade --install nemoclaw ./deploy/helm/nemoclaw -n <namespace> \
  --set image.repository=<registry>/<project>/nemoclaw \
  --set image.tag=<tag> \
  --set existingSecret=nemoclaw-nvidia
```

### Traefik Gateway API (HTTPRoute) and `CHAT_UI_URL`

The chart creates a Gateway API **`HTTPRoute`** (`gateway.networking.k8s.io/v1`), not `Ingress`. Default **`httpRoute.parentRefs`** target the Traefik **`Gateway`** created by [`rke2-traefik-additional-manifest.yaml`](../../../../rke2-traefik-additional-manifest.yaml): name **`traefik-gateway`**, namespace **`kube-system`**, **`sectionName: websecure`** for HTTPS. See [Traefik Kubernetes Gateway provider](https://doc.traefik.io/traefik/providers/kubernetes-gateway/).

**`CHAT_UI_URL`** is set only in **`templates/deployment.yaml`**: when **`httpRoute.enabled`** is true, it is **`https://`** plus the **first** hostname in **`httpRoute.hostnames`** (no path), so `nemoclaw-start` prints a correct “Remote UI” URL for the public HTTPS entrypoint. When **`httpRoute.enabled`** is false, it is **`http://127.0.0.1:<service.port>`** (port-forward / no Gateway exposure).

**Traefik → Service → Pod IP** does not use loopback. The gateway must listen on **all interfaces** (`openclaw gateway run --bind lan --port <service.port>`, **`gateway.bind: lan`** in config). The init **`patch-openclaw.py`** sets **`bind`**, **`port`** (from **`GATEWAY_PORT`**), appends **RFC1918** CIDRs to **`trustedProxies`**, and adds the **`CHAT_UI_URL`** origin to **`controlUi.allowedOrigins`**. Without **`lan`**, logs show **`listening on ws://127.0.0.1:18789`** only and the public URL will not load.

Upstream OpenClaw defaults to port **18789**, and this chart now follows that default so the Service/HTTPRoute target the actual gateway HTTP + WebSocket port. OpenClaw also allocates a separate **browser control** port at **gateway.port + 2**; it is not exposed on the Service unless you add it for automation.

If the HTTPRoute is in a different namespace than the Gateway, you may need a **ReferenceGrant** in the Gateway namespace (see Gateway API documentation).

### ExternalDNS (Cloudflare)

Fleet **external-dns** is configured with sources **`service`** and **`ingress`** only (older charts do not accept `gateway-httproute`). Per [ExternalDNS Gateway API docs](https://kubernetes-sigs.github.io/external-dns/latest/docs/sources/gateway-api/), **hostname / TTL / provider annotations belong on Routes**; the **Gateway** resource only accepts **`external-dns.alpha.kubernetes.io/target`** (where A/AAAA records point — usually the Traefik Service load balancer IP or hostname).

**Working pattern on KubeTEE:** **`service.externalDns`** is enabled by default on this chart. It sets on the **nemoclaw Service**:

- `external-dns.alpha.kubernetes.io/hostname` — from **`service.externalDns.hostname`** or, if empty, comma-joined **`httpRoute.hostnames`** (requires **`httpRoute.enabled`**)
- `external-dns.alpha.kubernetes.io/target` — auto-derived from the Traefik LoadBalancer Service (`kube-system/traefik`) unless you override `service.externalDns.target`

Example:

```yaml
service:
  externalDns:
    target: "203.0.113.1"   # optional override; otherwise derived from kube-system/traefik
```

Optional: add **`external-dns.alpha.kubernetes.io/target`** on the Traefik **`Gateway`** via [`rke2-traefik-additional-manifest.yaml`](../../../../rke2-traefik-additional-manifest.yaml) under **`gateway.annotations`** when you upgrade external-dns to a release that supports Gateway API route sources (then route-derived DNS can use that target).

Confirm sync: `kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns --tail=50 | grep -i desired`.

### TLS (Let’s Encrypt via cert-manager)

This is **disabled by default** on KubeTEE. The shared Traefik **Gateway** in `kube-system` already terminates HTTPS and references its own TLS Secret there, so a per-release `Certificate` from the NemoClaw namespace is not needed for the standard staging setup.

If you explicitly enable `httpRoute.tls.certManager.enabled: true`, ensure a **ClusterIssuer** exists (for example `letsencrypt-prod` from your Fleet cert-manager bundle). The chart creates a **cert-manager `Certificate`** for `httpRoute.hostnames` using that issuer; the TLS key/cert land in a Secret named `<release>-tls` unless you set `httpRoute.tls.certManager.secretName`.

HTTPS is still terminated on the **Gateway** listener. Either:

- Use **cert-manager’s Gateway integration** and set `httpRoute.tls.certManager.gatewayRef.enabled: true` only if your cert-manager version supports the `Certificate` `spec.gateway` field (this cluster currently does not); or  
- Reference the issued **Secret** from your Gateway’s TLS `certificateRefs` (possibly with a **ReferenceGrant** if the Secret and Gateway differ in namespace).

See [cert-manager Gateway API](https://cert-manager.io/docs/usage/gateway/) and [Traefik Gateway TLS](https://doc.traefik.io/traefik/routing/providers/kubernetes-gateway/).

### Workspace Persistence

The upstream OpenClaw manifests mount a PVC for the OpenClaw home directory. In this chart, the writable runtime state already lives under **`/sandbox/.openclaw-data`**, so the PVC is scoped to the workspace path only:

- **Mount path:** `/sandbox/.openclaw-data/workspace`
- **Default claim name:** `<release>-workspace`
- **Default size:** `10Gi`
- **Default access mode:** `ReadWriteOnce`
- **Default storage class:** `longhorn`

Use **`persistence.workspace.existingClaim`** if you want to bind the Deployment to an existing claim instead of creating one from the chart.

### Probes

The chart now follows the upstream OpenClaw manifest pattern and uses exec probes against local OpenClaw endpoints:

- **startupProbe** → `GET http://127.0.0.1:<port>/healthz`
- **readinessProbe** → `GET http://127.0.0.1:<port>/readyz`
- **livenessProbe** → `GET http://127.0.0.1:<port>/healthz`

These probe timings are intentionally hard-coded in the Deployment template to mirror the upstream OpenClaw Kubernetes manifest, rather than being exposed as chart values.

Because the workspace PVC is **`ReadWriteOnce`** by default and the chart runs a single replica, the Deployment strategy is also hard-coded to **`Recreate`** to avoid volume-attach races during rollouts.

## References

- [Inference profiles](https://docs.nvidia.com/nemoclaw/latest/reference/inference-profiles.html) — NVIDIA Endpoint and models
- [NemoClaw README](../../README.md) — prerequisites and CLI workflow
