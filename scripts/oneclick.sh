#!/usr/bin/env bash
set -euo pipefail

# One-click installer (single command via curl | bash)
# Example (interactive):
#   sudo bash -lc "curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/oneclick.sh | sudo bash"
# Example (non-interactive):
#   TELEGRAM_BOT_TOKEN=123:ABC ADMIN_IDS=111,222 sudo bash -lc "curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/oneclick.sh | sudo bash -s -- -R -s -Y"

# Defaults
REPO_URL="https://github.com/yo1u23/guanggao"
DEST_DIR="/opt/telegram-ad-guard-bot"
SERVICE_NAME="telegram-ad-guard-bot"
SERVICE_USER="$(id -un)"
RUN_AFTER=0
INSTALL_SERVICE=0
AUTO_TIMER=0
TIMER_INTERVAL="1h"
NON_INTERACTIVE=0
SELF_CHECK=1

# .env values
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

usage(){ cat <<USAGE
Usage: oneclick.sh [options]
  -r URL    Repo URL (default: $REPO_URL)
  -d DIR    Install dir (default: $DEST_DIR)
  -n NAME   Service name (default: $SERVICE_NAME)
  -u USER   Service user (default: current user)
  -R        Run after install (background if no -s)
  -s        Install systemd service
  -U        Install auto-update timer
  -I INT    Timer interval (default: 1h)
  -Y        Non-interactive (use env/flags)
  -C        Disable self-check

  -t TOKEN  TELEGRAM_BOT_TOKEN
  -A IDS    ADMIN_IDS (comma)
  -L IDS    ADMIN_LOG_CHAT_IDS (comma)
  -o LANGS  OCR_LANGUAGES
  -D ACT    DEFAULT_ACTION
  -M MODE   AI_MODE (off|openrouter)
  -K KEY    OPENROUTER_API_KEY
  -B BASE   OPENROUTER_API_BASE
  -m MODEL  OPENROUTER_MODEL
  -E on|off AI_EXCLUSIVE
  -T THRES  AI_CLASSIFY_THRESHOLD
USAGE
}

# Parse args
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r) REPO_URL="$2"; shift 2;;
    -d) DEST_DIR="$2"; shift 2;;
    -n) SERVICE_NAME="$2"; shift 2;;
    -u) SERVICE_USER="$2"; shift 2;;
    -R) RUN_AFTER=1; shift;;
    -s) INSTALL_SERVICE=1; shift;;
    -U) AUTO_TIMER=1; shift;;
    -I) TIMER_INTERVAL="$2"; shift 2;;
    -Y) NON_INTERACTIVE=1; shift;;
    -C) SELF_CHECK=0; shift;;
    -t) TOKEN="$2"; shift 2;;
    -A) ADMIN_IDS="$2"; shift 2;;
    -L) ADMIN_LOG_CHAT_IDS="$2"; shift 2;;
    -o) OCR_LANGUAGES="$2"; shift 2;;
    -D) DEFAULT_ACTION="$2"; shift 2;;
    -M) AI_MODE="$2"; shift 2;;
    -K) OPENROUTER_API_KEY="$2"; shift 2;;
    -B) OPENROUTER_API_BASE="$2"; shift 2;;
    -m) OPENROUTER_MODEL="$2"; shift 2;;
    -E) AI_EXCLUSIVE="$2"; shift 2;;
    -T) AI_CLASSIFY_THRESHOLD="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) args+=("$1"); shift;;
  esac
done
set -- "${args[@]}"

ensure_root(){ if [ "$(id -u)" -ne 0 ]; then echo "[ERR ] run as root/sudo"; exit 1; fi }
log(){ echo "[INFO] $*"; }
warn(){ echo "[WARN] $*"; }

pkg_install(){
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y git python3 python3-venv tesseract-ocr tesseract-ocr-chi-sim tesseract-ocr-chi-tra ffmpeg
  else
    warn "apt-get not found; please install git/python3-venv/tesseract/ffmpeg manually"
  fi
}

clone_sync(){
  if [ -d "$DEST_DIR/.git" ]; then
    log "Sync repo in $DEST_DIR"
    git -C "$DEST_DIR" fetch origin --depth=1
    git -C "$DEST_DIR" checkout -B main origin/main
    git -C "$DEST_DIR" reset --hard origin/main
  else
    log "Clone $REPO_URL to $DEST_DIR"
    mkdir -p "$DEST_DIR"
    git clone --depth 1 "$REPO_URL" "$DEST_DIR"
  fi
}

mkvenv_install(){
  python3 -m venv "$DEST_DIR/.venv" 2>/dev/null || true
  . "$DEST_DIR/.venv/bin/activate"
  python -m pip install -U pip setuptools wheel
  pip install -r "$DEST_DIR/requirements.txt"
}

write_env(){
  envf="$DEST_DIR/.env"
  touch "$envf"
  set_kv(){ key="$1"; val="$2"; if [ -n "$val" ]; then
    if grep -q "^${key}=" "$envf"; then sed -i "s|^${key}=.*$|${key}=${val}|" "$envf"; else echo "${key}=${val}" >>"$envf"; fi
  fi }
  if [ "$NON_INTERACTIVE" -ne 1 ]; then
    if [ -z "$TOKEN" ]; then
      read -r -p "请输入 Telegram Bot Token: " TOKEN
    fi
    read -r -p "全局管理员（逗号分隔，可留空）: " ADMIN_IDS || true
    read -r -p "通知 Chat IDs（逗号分隔，可留空）: " ADMIN_LOG_CHAT_IDS || true
  fi
  set_kv TELEGRAM_BOT_TOKEN "$TOKEN"
  set_kv ADMIN_IDS "$ADMIN_IDS"
  set_kv ADMIN_LOG_CHAT_IDS "$ADMIN_LOG_CHAT_IDS"
  set_kv OCR_LANGUAGES "$OCR_LANGUAGES"
  set_kv DEFAULT_ACTION "$DEFAULT_ACTION"
  set_kv AI_MODE "$AI_MODE"
  set_kv OPENROUTER_API_BASE "$OPENROUTER_API_BASE"
  set_kv OPENROUTER_API_KEY "$OPENROUTER_API_KEY"
  set_kv OPENROUTER_MODEL "$OPENROUTER_MODEL"
  set_kv AI_EXCLUSIVE "$AI_EXCLUSIVE"
  set_kv AI_CLASSIFY_THRESHOLD "$AI_CLASSIFY_THRESHOLD"
  log ".env updated"
}

self_check(){
  [ "$SELF_CHECK" -eq 1 ] || return 0
  . "$DEST_DIR/.venv/bin/activate"
  python - <<'PY'
import compileall, importlib, sys
ok = compileall.compile_dir('app', quiet=1)
try:
    importlib.import_module('app.bot')
    print('IMPORT_OK=True')
except Exception as e:
    print('IMPORT_OK=False', e)
print('COMPILE_OK='+str(bool(ok)))
PY
}

install_service(){
  [ "$INSTALL_SERVICE" -eq 1 ] || return 0
  if ! command -v systemctl >/dev/null 2>&1; then warn "systemctl not found; skip"; return 0; fi
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
}

install_timer(){
  [ "$AUTO_TIMER" -eq 1 ] || return 0
  if ! command -v systemctl >/dev/null 2>&1; then warn "systemctl not found; skip timer"; return 0; fi
  usvc="/etc/systemd/system/${SERVICE_NAME}-update.service"
  utmr="/etc/systemd/system/${SERVICE_NAME}-update.timer"
  cat >"$usvc" <<UPSVC
[Unit]
Description=Auto update for Telegram Ad Guard Bot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=$DEST_DIR
ExecStart=/bin/bash $DEST_DIR/scripts/self_update.sh
User=$SERVICE_USER
UPSVC
  cat >"$utmr" <<UPTMR
[Unit]
Description=Run ${SERVICE_NAME}-update.service every $TIMER_INTERVAL

[Timer]
OnUnitActiveSec=$TIMER_INTERVAL
AccuracySec=1s
Persistent=true
Unit=${SERVICE_NAME}-update.service

[Install]
WantedBy=timers.target
UPTMR
  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}-update.timer"
  systemctl restart "${SERVICE_NAME}-update.timer" || systemctl start "${SERVICE_NAME}-update.timer"
}

run_background(){
  [ "$RUN_AFTER" -eq 1 ] || return 0
  [ "$INSTALL_SERVICE" -eq 1 ] && return 0
  nohup "$DEST_DIR/.venv/bin/python" -m app.bot >"$DEST_DIR/bot.log" 2>&1 &
  echo $! >"$DEST_DIR/bot.pid"
}

main(){
  ensure_root
  pkg_install
  clone_sync
  mkvenv_install
  write_env
  out=$(self_check || true)
  echo "$out"
  echo "$out" | grep -q 'COMPILE_OK=True' || { echo "[ERR ] compile failed"; exit 1; }
  echo "$out" | grep -q 'IMPORT_OK=True' || { echo "[ERR ] import failed"; exit 1; }
  install_service
  install_timer
  run_background
  echo "[OK ] Done. Path: $DEST_DIR"
}

main "$@"