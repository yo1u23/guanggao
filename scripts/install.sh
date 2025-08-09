#!/usr/bin/env bash
set -euo pipefail

# Canonical one-click installer (minimal, non-interactive by default)
# Usage (recommended):
#   sudo bash -lc "curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/install.sh | sudo bash -s -- \
#     --token <YOUR_BOT_TOKEN> --admins 111,222 --service --run"
# Flags can also be provided via env: TELEGRAM_BOT_TOKEN, ADMIN_IDS, etc.

REPO_URL="https://github.com/yo1u23/guanggao"
DEST_DIR="/opt/telegram-ad-guard-bot"
SERVICE_NAME="telegram-ad-guard-bot"
SERVICE_USER="$(id -un)"
INSTALL_SERVICE=0
RUN_AFTER=0

# .env values (read from flags or env)
TOKEN="${TELEGRAM_BOT_TOKEN-}"
ADMIN_IDS="${ADMIN_IDS-}"
ADMIN_LOG_CHAT_IDS="${ADMIN_LOG_CHAT_IDS-}"
OCR_LANGUAGES="${OCR_LANGUAGES-chi_sim+eng}"
DEFAULT_ACTION="${DEFAULT_ACTION-delete_and_mute_and_notify}"
AI_MODE="${AI_MODE-off}"
OPENROUTER_API_BASE="${OPENROUTER_API_BASE-https://openrouter.ai/api/v1}"
OPENROUTER_API_KEY="${OPENROUTER_API_KEY-}"
OPENROUTER_MODEL="${OPENROUTER_MODEL-gpt-4o-mini}"
AI_EXCLUSIVE="${AI_EXCLUSIVE-off}"
AI_CLASSIFY_THRESHOLD="${AI_CLASSIFY_THRESHOLD-0.7}"

info(){ echo "[INFO] $*"; }
warn(){ echo "[WARN] $*"; }
err(){ echo "[ERR ] $*"; }

usage(){ cat <<USAGE
Minimal installer (non-interactive)

Flags:
  --repo URL           (default: $REPO_URL)
  --dir PATH           (default: $DEST_DIR)
  --service            install systemd service
  --run                run after install (background if no --service)
  --user USER          run service as this user (default: $SERVICE_USER)

  --token TOKEN        TELEGRAM_BOT_TOKEN (required)
  --admins IDS         ADMIN_IDS (comma)
  --log-chats IDS      ADMIN_LOG_CHAT_IDS (comma)
  --ocr LANGS          OCR_LANGUAGES (default: chi_sim+eng)
  --action ACTION      DEFAULT_ACTION (default: delete_and_mute_and_notify)
  --ai-mode MODE       AI_MODE (off|openrouter)
  --ai-key KEY         OPENROUTER_API_KEY
  --ai-base URL        OPENROUTER_API_BASE
  --ai-model MODEL     OPENROUTER_MODEL
  --ai-exclusive on|off
  --ai-threshold 0..1

Example:
  sudo bash -lc "curl -fsSL $REPO_URL/raw/main/scripts/install.sh | sudo bash -s -- \
    --token 123:ABC --admins 111,222 --service --run"
USAGE
}

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_URL="$2"; shift 2;;
    --dir) DEST_DIR="$2"; shift 2;;
    --service) INSTALL_SERVICE=1; shift;;
    --run) RUN_AFTER=1; shift;;
    --user) SERVICE_USER="$2"; shift 2;;
    --token) TOKEN="$2"; shift 2;;
    --admins) ADMIN_IDS="$2"; shift 2;;
    --log-chats) ADMIN_LOG_CHAT_IDS="$2"; shift 2;;
    --ocr) OCR_LANGUAGES="$2"; shift 2;;
    --action) DEFAULT_ACTION="$2"; shift 2;;
    --ai-mode) AI_MODE="$2"; shift 2;;
    --ai-key) OPENROUTER_API_KEY="$2"; shift 2;;
    --ai-base) OPENROUTER_API_BASE="$2"; shift 2;;
    --ai-model) OPENROUTER_MODEL="$2"; shift 2;;
    --ai-exclusive) AI_EXCLUSIVE="$2"; shift 2;;
    --ai-threshold) AI_CLASSIFY_THRESHOLD="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) warn "Unknown flag: $1"; usage; exit 2;;
  esac
done

# Root check
if [[ $(id -u) -ne 0 ]]; then err "Run as root/sudo"; exit 1; fi

# Require token
if [[ -z "$TOKEN" ]]; then
  err "Missing token. Provide --token or env TELEGRAM_BOT_TOKEN."
  usage; exit 2
fi

# Install deps (apt only for simplicity)
if command -v apt-get >/dev/null 2>&1; then
  info "Installing system dependencies (apt) ..."
  apt-get update -y
  apt-get install -y git python3 python3-venv tesseract-ocr tesseract-ocr-chi-sim tesseract-ocr-chi-tra ffmpeg
else
  warn "Non-apt system detected. Please ensure git/python3/venv/tesseract/ffmpeg are installed."
fi

# Clone/update
if [[ -d "$DEST_DIR/.git" ]]; then
  info "Sync repo in $DEST_DIR ..."
  git -C "$DEST_DIR" fetch origin --depth=1
  git -C "$DEST_DIR" checkout -B main origin/main
  git -C "$DEST_DIR" reset --hard origin/main
else
  info "Clone repo to $DEST_DIR ..."
  mkdir -p "$DEST_DIR"
  git clone --depth 1 "$REPO_URL" "$DEST_DIR"
fi

# Python deps
python3 -m venv "$DEST_DIR/.venv" 2>/dev/null || true
source "$DEST_DIR/.venv/bin/activate"
python -m pip install -U pip setuptools wheel
pip install -r "$DEST_DIR/requirements.txt"

# Write .env
ENVF="$DEST_DIR/.env"
: >"$ENVF"
kv(){
  local k="$1"; local v="$2"; [[ -z "$v" ]] && return 0
  if grep -q "^${k}=" "$ENVF" 2>/dev/null; then
    sed -i "s|^${k}=.*$|${k}=${v}|" "$ENVF"
  else
    echo "${k}=${v}" >>"$ENVF"
  fi
}
kv TELEGRAM_BOT_TOKEN "$TOKEN"
kv ADMIN_IDS "$ADMIN_IDS"
kv ADMIN_LOG_CHAT_IDS "$ADMIN_LOG_CHAT_IDS"
kv OCR_LANGUAGES "$OCR_LANGUAGES"
kv DEFAULT_ACTION "$DEFAULT_ACTION"
kv AI_MODE "$AI_MODE"
kv OPENROUTER_API_BASE "$OPENROUTER_API_BASE"
kv OPENROUTER_API_KEY "$OPENROUTER_API_KEY"
kv OPENROUTER_MODEL "$OPENROUTER_MODEL"
kv AI_EXCLUSIVE "$AI_EXCLUSIVE"
kv AI_CLASSIFY_THRESHOLD "$AI_CLASSIFY_THRESHOLD"
info ".env written: $ENVF"

# Self-check
out=$(python - <<'PY'
import compileall, importlib
ok = compileall.compile_dir('app', quiet=1)
try:
    importlib.import_module('app.bot')
    print('IMPORT_OK=True')
except Exception as e:
    print('IMPORT_OK=False', e)
print('COMPILE_OK='+str(bool(ok)))
PY
) || true
printf '%s\n' "$out"
if ! echo "$out" | grep -q 'COMPILE_OK=True'; then err "Compile failed"; exit 1; fi
if ! echo "$out" | grep -q 'IMPORT_OK=True'; then err "Import failed"; exit 1; fi
info "Self-check passed"

# systemd service
if [[ $INSTALL_SERVICE -eq 1 ]]; then
  if ! command -v systemctl >/dev/null 2>&1; then warn "systemctl not found; skip service"; else
    svc="/etc/systemd/system/${SERVICE_NAME}.service"
    cat >"$svc" <<SERVICE
[Unit]
Description=Telegram Ad Guard Bot
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$DEST_DIR
ExecStart=$DEST_DIR/.venv/bin/python -m app.bot
Restart=always
RestartSec=3
User=$SERVICE_USER

[Install]
WantedBy=multi-user.target
SERVICE
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl restart "$SERVICE_NAME" || systemctl start "$SERVICE_NAME"
    info "Service installed: $SERVICE_NAME"
  fi
fi

# Run background if requested and no service
if [[ $RUN_AFTER -eq 1 && $INSTALL_SERVICE -eq 0 ]]; then
  nohup "$DEST_DIR/.venv/bin/python" -m app.bot >"$DEST_DIR/bot.log" 2>&1 &
  echo $! >"$DEST_DIR/bot.pid"
  info "Started in background (PID $(cat "$DEST_DIR/bot.pid" 2>/dev/null || echo '?')). Logs: $DEST_DIR/bot.log"
fi

info "Done. Path: $DEST_DIR"