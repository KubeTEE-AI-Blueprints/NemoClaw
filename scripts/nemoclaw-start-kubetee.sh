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
write_auth_profile
sync_onboard_state
openclaw plugins install /opt/nemoclaw > /dev/null 2>&1 || true

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
