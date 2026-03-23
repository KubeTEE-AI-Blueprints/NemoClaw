#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# NemoClaw sandbox entrypoint. Configures OpenClaw and starts the dashboard
# gateway inside the sandbox so the forwarded host port has a live upstream.
#
# Optional env:
#   NVIDIA_API_KEY        API key for NVIDIA-hosted inference
#   NVIDIA_DIRECT_BASE_URL  Base URL for direct NVIDIA endpoint access
#   CHAT_UI_URL          Browser origin that will access the forwarded dashboard

set -euo pipefail

NEMOCLAW_CMD=("$@")
# Must match gateway.port / Service targetPort. Bind is loopback in URL only for "Local UI" hints.
GATEWAY_PORT="${GATEWAY_PORT:-18789}"
CHAT_UI_URL="${CHAT_UI_URL:-http://127.0.0.1:${GATEWAY_PORT}}"
PUBLIC_PORT="${GATEWAY_PORT}"
OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-/sandbox/.openclaw-data}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-/sandbox/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-/sandbox/.local/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-/sandbox/.local/state}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-/sandbox/.cache}"
OPENCODE_CONFIG="${OPENCODE_CONFIG:-${XDG_CONFIG_HOME}/opencode/opencode.json}"
export OPENCLAW_STATE_DIR XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME OPENCODE_CONFIG

ensure_runtime_state_layout() {
  mkdir -p \
    "${OPENCLAW_STATE_DIR}/agents/main/agent" \
    "${OPENCLAW_STATE_DIR}/extensions" \
    "${OPENCLAW_STATE_DIR}/workspace" \
    "${OPENCLAW_STATE_DIR}/workspace-main" \
    "${OPENCLAW_STATE_DIR}/skills" \
    "${OPENCLAW_STATE_DIR}/hooks" \
    "${OPENCLAW_STATE_DIR}/identity" \
    "${OPENCLAW_STATE_DIR}/devices" \
    "${OPENCLAW_STATE_DIR}/canvas" \
    "${OPENCLAW_STATE_DIR}/cron" \
    "${OPENCLAW_STATE_DIR}/opencode/config" \
    "${OPENCLAW_STATE_DIR}/opencode/data" \
    "${OPENCLAW_STATE_DIR}/opencode/cache" \
    "${OPENCLAW_STATE_DIR}/opencode/state"

  if [ ! -f "${OPENCLAW_STATE_DIR}/update-check.json" ]; then
    printf '{}\n' > "${OPENCLAW_STATE_DIR}/update-check.json"
  fi

  if [ ! -f "${OPENCLAW_STATE_DIR}/exec-approvals.json" ]; then
    printf '{}\n' > "${OPENCLAW_STATE_DIR}/exec-approvals.json"
  fi

  if [ ! -f "${OPENCLAW_STATE_DIR}/workspace/AGENTS.md" ]; then
    cat > "${OPENCLAW_STATE_DIR}/workspace/AGENTS.md" <<'EOF'
# OpenClaw Assistant

You are a helpful AI assistant running in Kubernetes.
EOF
  fi
}

sync_nemoclaw_plugin_bundle() {
  python3 - <<'PYSYNC'
import shutil
from pathlib import Path

source_root = Path("/opt/nemoclaw")
target_root = Path("/sandbox/.openclaw-data/extensions/nemoclaw")

target_root.mkdir(parents=True, exist_ok=True)

target_dist = target_root / "dist"
if target_dist.exists():
    shutil.rmtree(target_dist)
shutil.copytree(source_root / "dist", target_dist)

for filename in ("openclaw.plugin.json", "package.json"):
    shutil.copy2(source_root / filename, target_root / filename)
PYSYNC
}

write_opencode_config() {
  python3 - <<'PYOPENCODE'
import json
import os
from pathlib import Path


def truthy(value):
    return value.strip().lower() in {"1", "true", "yes", "on"} if isinstance(value, str) else bool(value)


def parse_headers(raw):
    if not raw:
        return {}
    try:
        data = json.loads(raw)
    except Exception:
        return {}
    if not isinstance(data, dict):
        return {}
    result = {}
    for key, value in data.items():
        key_text = str(key).strip()
        value_text = str(value).strip()
        if key_text and value_text:
            result[key_text] = value_text
    return result


def maybe_int(raw):
    raw = (raw or "").strip()
    if not raw:
        return None
    try:
        value = int(raw)
    except Exception:
        return None
    return value if value > 0 else None


enabled = truthy(os.environ.get("OPENCODE_ENABLED", "false"))
runtime = (os.environ.get("OPENCLAW_CODING_AGENT_RUNTIME", "") or "").strip()
base_url = (os.environ.get("OPENCODE_BASE_URL", "") or "").strip()
model_id = (os.environ.get("OPENCODE_MODEL", "") or "").strip()
provider_id = (os.environ.get("OPENCODE_PROVIDER_ID", "nim") or "nim").strip()
provider_name = (os.environ.get("OPENCODE_PROVIDER_NAME", "NVIDIA NIM") or "NVIDIA NIM").strip()
model_name = (os.environ.get("OPENCODE_MODEL_NAME", "") or "").strip() or model_id
api_key_env = (os.environ.get("OPENCODE_API_KEY_ENV", "") or "").strip()
headers = parse_headers(os.environ.get("OPENCODE_HEADERS_JSON", ""))
context_window = maybe_int(os.environ.get("OPENCODE_CONTEXT_WINDOW", ""))
max_output_tokens = maybe_int(os.environ.get("OPENCODE_MAX_OUTPUT_TOKENS", ""))

config_path = Path(os.environ.get("OPENCODE_CONFIG", str(Path.home() / ".config" / "opencode" / "opencode.json")))
config_path.parent.mkdir(parents=True, exist_ok=True)
(Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local" / "share"))) / "opencode").mkdir(parents=True, exist_ok=True)
(Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local" / "state"))) / "opencode").mkdir(parents=True, exist_ok=True)
(Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "opencode").mkdir(parents=True, exist_ok=True)

if not enabled or runtime != "opencode" or not base_url or not model_id:
    if config_path.exists():
        config_path.unlink()
    reason = "disabled"
    if enabled and runtime == "opencode":
        reason = "missing OPENCODE_BASE_URL or OPENCODE_MODEL"
    elif enabled:
        reason = f"runtime={runtime or 'unset'}"
    print(f"[opencode] skipped config generation ({reason})")
    raise SystemExit(0)

config = {
    "$schema": "https://opencode.ai/config.json",
    "model": f"{provider_id}/{model_id}",
    "provider": {
        provider_id: {
            "npm": "@ai-sdk/openai-compatible",
            "name": provider_name,
            "options": {
                "baseURL": base_url,
            },
            "models": {
                model_id: {
                    "name": model_name,
                }
            },
        }
    },
}

options = config["provider"][provider_id]["options"]
if api_key_env:
    options["apiKey"] = f"{{env:{api_key_env}}}"
if headers:
    options["headers"] = headers

limit = {}
if context_window is not None:
    limit["context"] = context_window
if max_output_tokens is not None:
    limit["output"] = max_output_tokens
if limit:
    config["provider"][provider_id]["models"][model_id]["limit"] = limit

with open(config_path, "w", encoding="utf-8") as fh:
    json.dump(config, fh, indent=2)
    fh.write("\n")
os.chmod(config_path, 0o600)
print(f"[opencode] wrote {config_path} for model {provider_id}/{model_id}")
PYOPENCODE
}

write_auth_profile() {
  if [ -z "${NVIDIA_API_KEY:-}" ]; then
    return
  fi

  python3 - <<'PYAUTH'
import json
import os
path = os.path.expanduser('~/.openclaw/agents/main/agent/auth-profiles.json')
os.makedirs(os.path.dirname(path), exist_ok=True)
json.dump({
    'nvidia:manual': {
        'type': 'api_key',
        'provider': 'nvidia',
        'keyRef': {'source': 'env', 'id': 'NVIDIA_API_KEY'},
        'profileId': 'nvidia:manual',
    }
}, open(path, 'w'))
os.chmod(path, 0o600)
PYAUTH
}

sync_onboard_state() {
  if [ -z "${NVIDIA_API_KEY:-}" ]; then
    return
  fi

  python3 - <<'PYONBOARD'
import json
import os
from datetime import datetime, timezone
from pathlib import Path

home = Path.home()
nemoclaw_dir = home / ".nemoclaw"
creds_path = nemoclaw_dir / "credentials.json"
config_path = nemoclaw_dir / "config.json"
openclaw_path = home / ".openclaw" / "openclaw.json"

nemoclaw_dir.mkdir(parents=True, exist_ok=True)
os.chmod(nemoclaw_dir, 0o700)

def load_json(path, default):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return default

def write_json(path, data, mode):
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
    os.chmod(path, mode)

openclaw_cfg = load_json(openclaw_path, {})
existing_config = load_json(config_path, {})
credentials = load_json(creds_path, {})

model = (
    openclaw_cfg.get("agents", {})
    .get("defaults", {})
    .get("model", {})
    .get("primary")
    or os.environ.get("NEMOCLAW_MODEL")
    or "nvidia/nemotron-3-super-120b-a12b"
)
if isinstance(model, str) and model.startswith("inference/"):
    model = model.split("/", 1)[1]

onboarded_at = existing_config.get("onboardedAt")
if not onboarded_at:
    onboarded_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

credentials["NVIDIA_API_KEY"] = os.environ["NVIDIA_API_KEY"]
write_json(creds_path, credentials, 0o600)

config = {
    "endpointType": "build",
    "endpointUrl": os.environ.get("NVIDIA_DIRECT_BASE_URL", "https://integrate.api.nvidia.com/v1"),
    "ncpPartner": None,
    "model": model,
    "profile": "build",
    "credentialEnv": "NVIDIA_API_KEY",
    "provider": "nvidia-nim",
    "providerLabel": "NVIDIA Endpoint API",
    "onboardedAt": onboarded_at,
}
write_json(config_path, config, 0o600)
print("[onboard] synced ~/.nemoclaw/credentials.json and ~/.nemoclaw/config.json")
PYONBOARD
}

print_dashboard_urls() {
  local token chat_ui_base local_url remote_url

  token="$(python3 - <<'PYTOKEN'
import json
import os
path = os.path.expanduser('~/.openclaw/openclaw.json')
try:
    cfg = json.load(open(path))
except Exception:
    print('')
else:
    print(cfg.get('gateway', {}).get('auth', {}).get('token', ''))
PYTOKEN
)"

  chat_ui_base="${CHAT_UI_URL%/}"
  local_url="http://127.0.0.1:${PUBLIC_PORT}/"
  remote_url="${chat_ui_base}/"
  if [ -n "$token" ]; then
    local_url="${local_url}#token=${token}"
    remote_url="${remote_url}#token=${token}"
  fi

  echo "[gateway] Local UI: ${local_url}"
  echo "[gateway] Remote UI: ${remote_url}"
}

start_auto_pair() {
  python3 - <<'PYAUTOPAIR' &
import json
import subprocess
import time

DEADLINE = time.time() + 600
QUIET_POLLS = 0
APPROVED = 0

def run(*args):
    proc = subprocess.run(args, capture_output=True, text=True)
    return proc.returncode, proc.stdout.strip(), proc.stderr.strip()

while time.time() < DEADLINE:
    rc, out, err = run('openclaw', 'devices', 'list', '--json')
    if rc != 0 or not out:
        time.sleep(1)
        continue
    try:
        data = json.loads(out)
    except Exception:
        time.sleep(1)
        continue

    pending = data.get('pending') or []
    paired = data.get('paired') or []
    has_browser = any((d.get('clientId') == 'openclaw-control-ui') or (d.get('clientMode') == 'webchat') for d in paired if isinstance(d, dict))

    if pending:
        QUIET_POLLS = 0
        for device in pending:
            request_id = (device or {}).get('requestId')
            if not request_id:
                continue
            arc, aout, aerr = run('openclaw', 'devices', 'approve', request_id, '--json')
            if arc == 0:
                APPROVED += 1
                print(f'[auto-pair] approved request={request_id}')
            elif aout or aerr:
                print(f'[auto-pair] approve failed request={request_id}: {(aerr or aout)[:400]}')
        time.sleep(1)
        continue

    if has_browser:
        QUIET_POLLS += 1
        if QUIET_POLLS >= 4:
            print(f'[auto-pair] browser pairing converged approvals={APPROVED}')
            break
    elif APPROVED > 0:
        QUIET_POLLS += 1
    else:
        QUIET_POLLS = 0

    time.sleep(1)
else:
    print(f'[auto-pair] watcher timed out approvals={APPROVED}')
PYAUTOPAIR
  echo "[gateway] auto-pair watcher launched (pid $!)"
}

echo 'Setting up NemoClaw...'
# openclaw doctor --fix and openclaw plugins install already ran at build time
# (Dockerfile Step 28). At runtime they fail with EPERM against the locked
# /sandbox/.openclaw directory and accomplish nothing.
ensure_runtime_state_layout
sync_nemoclaw_plugin_bundle
write_auth_profile
sync_onboard_state
write_opencode_config

if [ ${#NEMOCLAW_CMD[@]} -gt 0 ]; then
  exec "${NEMOCLAW_CMD[@]}"
fi

# Run the gateway in the **foreground** (`exec`). If we used `openclaw gateway run &` + `wait $!`,
# OpenClaw may daemonize: the background shell job exits quickly while the real server is another
# process — `wait` returns immediately, bash exits 0, and Kubernetes restarts the pod (CrashLoop).
# Auto-pair runs first in the background; it already retries until `openclaw devices` succeeds.
start_auto_pair
print_dashboard_urls
echo '[gateway] starting openclaw gateway (foreground; logs follow)'
# Behind Traefik/Service, traffic hits the pod IP — must listen on all interfaces, not loopback only.
exec openclaw gateway run --bind lan --port "${GATEWAY_PORT}"
