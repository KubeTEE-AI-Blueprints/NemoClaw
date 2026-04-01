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

## Project Overview

NVIDIA NemoClaw is an open-source reference stack for running [OpenClaw](https://openclaw.ai) always-on assistants inside [NVIDIA OpenShell](https://github.com/NVIDIA/OpenShell) sandboxes with NVIDIA inference (Nemotron). It provides CLI tooling, a blueprint for sandbox orchestration, and security hardening.

**Status:** Alpha (March 2026+). Interfaces may change without notice.

## Architecture

| Path | Language | Purpose |
|------|----------|---------|
| `bin/` | JavaScript (CJS) | CLI entry point (`nemoclaw.js`) and library modules |
| `bin/lib/` | JavaScript (CJS) | Core CLI logic: onboard, credentials, inference, policies, preflight, runner |
| `nemoclaw/` | TypeScript | Plugin project (Commander CLI extension for OpenClaw) |
| `nemoclaw/src/blueprint/` | TypeScript | Runner, snapshot, SSRF validation, state management |
| `nemoclaw/src/commands/` | TypeScript | Slash commands, migration state |
| `nemoclaw/src/onboard/` | TypeScript | Onboarding config |
| `nemoclaw-blueprint/` | YAML | Blueprint definition and network policies |
| `scripts/` | Bash/JS/TS | Install helpers, setup, automation, E2E tooling |
| `test/` | JavaScript (ESM) | Root-level integration tests (Vitest) |
| `test/e2e/` | Bash/JS | End-to-end tests (Brev cloud instances) |
| `docs/` | Markdown (MyST) | User-facing docs (Sphinx) |
| `k8s/` | YAML | Kubernetes deployment manifests |

## Development Commands

```bash
# Install dependencies
npm install                              # root deps (OpenClaw + CLI)
cd nemoclaw && npm install && npm run build && cd ..  # TypeScript plugin
cd nemoclaw-blueprint && uv sync && cd ..             # Python deps

# Build
cd nemoclaw && npm run build      # compile TypeScript plugin
cd nemoclaw && npm run dev        # watch mode

# Test
npm test                          # root-level tests (Vitest)
cd nemoclaw && npm test           # plugin unit tests (Vitest)

# Lint / check
make check                        # all linters via prek (pre-commit hooks)
npx prek run --all-files          # same as make check
npm run typecheck:cli             # type-check CLI (bin/, scripts/)

# Format
make format                       # auto-format TypeScript

# Docs
make docs                         # build docs (Sphinx/MyST)
make docs-live                    # serve locally with auto-rebuild
```

## Test Structure

- **Root tests** (`test/*.test.js`): Integration tests run via Vitest (ESM)
- **Plugin tests** (`nemoclaw/src/**/*.test.ts`): Unit tests co-located with source
- **E2E tests** (`test/e2e/`): Cloud-based E2E on Brev instances, triggered only when `BREV_API_TOKEN` is set

Vitest config (`vitest.config.ts`) defines three projects: `cli`, `plugin`, and `e2e-brev`.

## Code Style and Conventions

### Commit Messages

Conventional Commits required. Enforced by commitlint via prek `commit-msg` hook.

```text
<type>(<scope>): <description>
```

Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`, `perf`, `merge`

### SPDX Headers

Every source file must include an SPDX license header. The pre-commit hook auto-inserts them:

```javascript
// SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
```

For shell scripts use `#` comments. For Markdown use HTML comments.

### JavaScript

- `bin/` and `scripts/`: **CommonJS** (`require`/`module.exports`), Node.js 22.16+
- `test/`: **ESM** (`import`/`export`)
- ESLint config in `eslint.config.mjs`
- Cyclomatic complexity limit: 20 (ratcheting down to 15)
- Unused vars pattern: prefix with `_`

### TypeScript

- Plugin code in `nemoclaw/src/` with its own ESLint config
- CLI type-checking via `tsconfig.cli.json`
- Plugin type-checking via `nemoclaw/tsconfig.json`

### Shell Scripts

- ShellCheck enforced (`.shellcheckrc` at root)
- `shfmt` for formatting
- All scripts must have shebangs and be executable

### No External Project Links

Do not add links to third-party code repositories, community collections, or unofficial resources. Links to official tool documentation (Node.js, Python, uv) are acceptable.

## Git Hooks (prek)

All hooks managed by [prek](https://prek.j178.dev/) (installed via `npm install`):

| Hook | What runs |
|------|-----------|
| **pre-commit** | File fixers, formatters, linters, Vitest (plugin) |
| **commit-msg** | commitlint (Conventional Commits) |
| **pre-push** | TypeScript type check (tsc --noEmit for plugin, JS, CLI) |

## Documentation

- Source of truth: `docs/` directory
- `.agents/skills/docs/` is **autogenerated** — never edit directly
- After changing docs, regenerate skills:

  ```bash
  python scripts/docs-to-skills.py docs/ .agents/skills/docs/ --prefix nemoclaw
  ```

- Follow style guide in `docs/CONTRIBUTING.md`

## PR Requirements

- Create feature branch from `main`
- Run `make check` and `npm test` before submitting
- Follow PR template (`.github/PULL_REQUEST_TEMPLATE.md`)
- Update docs for any user-facing behavior changes
- No secrets, API keys, or credentials committed
- Limit open PRs to fewer than 10
