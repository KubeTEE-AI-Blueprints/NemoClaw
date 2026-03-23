# CLAUDE.md

This file provides guidance for AI assistants working in `NemoClaw/`.

## KubeTEE Kubernetes Variant

This repository contains the upstream NemoClaw codebase plus KubeTEE-specific Kubernetes work.

The upstream OpenClaw repository is also vendored locally as a Git submodule at:

- `openclaw/`

When working on the KubeTEE deployment, treat the following files as the authoritative KubeTEE-maintained variants derived from the original upstream `main` branch:

- Helm chart: `deploy/helm/nemoclaw/`
- Kubernetes image definition: `Dockerfile.kubetee`
- Kubernetes startup script: `scripts/nemoclaw-start-kubetee.sh`

These files are our KubeTEE version for Kubernetes and should be preferred over the upstream/local-host workflow files when making cluster deployment changes.

## Upstream vs KubeTEE Files

The upstream/local-host flow is still represented by:

- `Dockerfile`
- `scripts/nemoclaw-start.sh`
- `openclaw/` (upstream OpenClaw source as submodule)

Do not assume changes made for the upstream host workflow automatically apply to the KubeTEE Kubernetes deployment. Review whether the same change must also be applied to:

- `Dockerfile.kubetee`
- `scripts/nemoclaw-start-kubetee.sh`
- `deploy/helm/nemoclaw/`

## Deployment Notes

- The KubeTEE Helm chart lives at `deploy/helm/nemoclaw/`.
- The KubeTEE image is built from `Dockerfile.kubetee`.
- The KubeTEE container entrypoint logic lives in `scripts/nemoclaw-start-kubetee.sh`.
- The upstream OpenClaw codebase is available locally at `openclaw/` for reference and comparison.
- KubeTEE deploys NemoClaw behind Traefik Gateway API rather than the upstream host-side OpenShell workflow.

## Practical Rule

If the task is about Kubernetes, Helm, RKE2, Traefik, ExternalDNS, cert-manager, pod startup, or the live `nemoclaw` deployment, start from the KubeTEE files first:

- `deploy/helm/nemoclaw/`
- `Dockerfile.kubetee`
- `scripts/nemoclaw-start-kubetee.sh`
