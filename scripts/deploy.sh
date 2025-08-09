#!/usr/bin/env bash
set -euo pipefail

# New one-click deploy script (independent)
# - Clone/update repo, install system deps, create venv, install Python deps
# - Write .env from flags/env, run self-check, install systemd service/timer (optional)
# - Support update/uninstall/dry-run, rollback on failed update
# - Designed for Ubuntu/Debian; has basic pkg-manager detection fallbacks

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
ROLLBACK_ON_FAIL=1
DRY_RUN=0
VERBOSE=0

# Config values (.env)
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

# Colors
c_info="\033[1;34m"; c_warn="\033[1;33m"; c_err="\033[1;31m"; c_ok="\033[1;32m"; c_end="\033[0m"
info(){ echo -e "${c_info}[INFO]${c_end} $*"; }
warn(){ echo -e "${c_warn}[WARN]${c_end} $*"; }
err(){ echo -e "${c_err}[ERR ]${c_end} $*"; }
ok(){ echo -e "${c_ok}[ OK ]${c_end} $*"; }

usage(){ cat <<USAGE
Usage: $0 [options]

General:
  -r URL           Repo URL (default: $REPO_URL)
  -d DIR           Install dir (default: $DEST_DIR)
  -n NAME          Service name (default: $SERVICE_NAME)
  -u USER          Service user (default: current user)
  -R               Run after install (background if no -s)
  -s               Install systemd service
  -U               Install auto-update timer
  -I INTERVAL      Timer interval (default: 1h)
  -y               Non-interactive; use flags/env only
  -C               Disable self-check
  -N               Disable rollback on failure
  -v               Verbose
  --dry-run        Print actions without executing

Actions (mutually exclusive, default: install/update):
  --install        Install or update in place (default)
  --update         Update code and deps, then self-check
  --uninstall      Stop/disable service & timer, remove dir

Env (.env values):
  -t TOKEN         TELEGRAM_BOT_TOKEN
  -A IDS           ADMIN_IDS (comma)
  -L IDS           ADMIN_LOG_CHAT_IDS (comma)
  -o LANGS         OCR_LANGUAGES (default: chi_sim+eng)
  -D ACTION        DEFAULT_ACTION
  -M MODE          AI_MODE (off|openrouter)
  -K KEY           OPENROUTER_API_KEY
  -B BASE          OPENROUTER_API_BASE
  -m MODEL         OPENROUTER_MODEL
  -E on|off        AI_EXCLUSIVE
  -T THRES         AI_CLASSIFY_THRESHOLD (0..1)

Examples:
  sudo $0 -t 123:ABC -A 111,222 -s -U -I 1h -R -y
  sudo $0 --uninstall -n $SERVICE_NAME -d $DEST_DIR
USAGE
}

ACTION="install"

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
    -y) NON_INTERACTIVE=1; shift;;
    -C) SELF_CHECK=0; shift;;
    -N) ROLLBACK_ON_FAIL=0; shift;;
    -v) VERBOSE=1; shift;;
    --dry-run) DRY_RUN=1; shift;;
    --install) ACTION="install"; shift;;
    --update) ACTION="update"; shift;;
    --uninstall) ACTION="uninstall"; shift;;
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

[ "$VERBOSE" -eq 1 ] && set -x || true

run(){ if [ "$DRY_RUN" -eq 1 ]; then echo "+ $*"; else eval "$*"; fi }

ensure_root(){ if [ "$(id -u)" -ne 0 ]; then err "Please run as root or with sudo"; exit 1; fi }

pkg_install(){
  if command -v apt-get >/dev/null 2>&1; then
    run "apt-get update -y"
    run "apt-get install -y git python3 python3-venv tesseract-ocr tesseract-ocr-chi-sim tesseract-ocr-chi-tra ffmpeg"
  elif command -v dnf >/dev/null 2>&1; then
    run "dnf install -y git python3 python3-venv tesseract ffmpeg"
  elif command -v yum >/dev/null 2>&1; then
    run "yum install -y git python3 python3-venv tesseract ffmpeg"
  elif command -v pacman >/dev/null 2>&1; then
    run "pacman -Sy --noconfirm git python python-virtualenv tesseract ffmpeg"
  else
    warn "Unknown package manager; please install git/python3/venv/tesseract/ffmpeg manually"
  fi
}

clone_or_update(){
  if [ -d "$DEST_DIR/.git" ]; then
    info "Syncing repo in $DEST_DIR ..."
    run "git -C '$DEST_DIR' fetch origin --depth=1"
    run "git -C '$DEST_DIR' checkout -B main origin/main"
    run "git -C '$DEST_DIR' reset --hard origin/main"
  else
    info "Cloning $REPO_URL to $DEST_DIR ..."
    run "mkdir -p '$DEST_DIR'"
    run "git clone --depth 1 '$REPO_URL' '$DEST_DIR'"
  fi
}

create_venv_and_deps(){
  run "python3 -m venv '$DEST_DIR/.venv' 2>/dev/null || true"
  run "bash -c 'source \"$DEST_DIR/.venv/bin/activate\" && python -m pip install -U pip setuptools wheel'"
  run "bash -c 'source \"$DEST_DIR/.venv/bin/activate\" && pip install -r \"$DEST_DIR/requirements.txt\"'"
}

write_env(){
  local env_file="$DEST_DIR/.env"
  run "touch '$env_file'"
  set_kv(){ key="$1"; val="$2"; if [ -n "$val" ]; then
    run "grep -q ^${key}= '$env_file' && sed -i 's|^${key}=.*$|${key}=${val}|' '$env_file' || echo ${key}=${val} >>'$env_file'"
  fi }
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
  ok ".env written at $env_file"
}

self_check(){
  [ "$SELF_CHECK" -eq 1 ] || { warn "Self-check disabled"; return 0; }
  info "Self-check ..."
  if ! command -v tesseract >/dev/null 2>&1; then warn "tesseract not found"; fi
  if ! command -v ffmpeg >/dev/null 2>&1; then warn "ffmpeg not found"; fi
  local out
  out=$(bash -c "source '$DEST_DIR/.venv/bin/activate' && python - <<'PY'
import compileall, importlib, sys
ok = compileall.compile_dir('app', quiet=1)
try:
    importlib.import_module('app.bot')
    print('IMPORT_OK=True')
except Exception as e:
    print('IMPORT_OK=False', e)
print('COMPILE_OK='+str(bool(ok)))
PY
") || true
  echo "$out" | grep -q 'COMPILE_OK=True' || { err "compile failed"; return 1; }
  echo "$out" | grep -q 'IMPORT_OK=True' || { err "import app.bot failed"; return 1; }
  ok "Self-check passed"
}

install_service(){
  [ "$INSTALL_SERVICE" -eq 1 ] || return 0
  if ! command -v systemctl >/dev/null 2>&1; then warn "systemctl not found; skipping service"; return 0; fi
  local svc="/etc/systemd/system/${SERVICE_NAME}.service"
  info "Installing service $svc (User=$SERVICE_USER)"
  run "bash -c 'cat > \"$svc\"'" <<SERVICE
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
  run "systemctl daemon-reload"
  run "systemctl enable '$SERVICE_NAME'"
  run "systemctl restart '$SERVICE_NAME' || systemctl start '$SERVICE_NAME'"
}

install_timer(){
  [ "$AUTO_TIMER" -eq 1 ] || return 0
  if ! command -v systemctl >/dev/null 2>&1; then warn "systemctl not found; skipping timer"; return 0; fi
  local usvc="/etc/systemd/system/${SERVICE_NAME}-update.service"
  local utmr="/etc/systemd/system/${SERVICE_NAME}-update.timer"
  info "Installing auto-update timer ($TIMER_INTERVAL)"
  run "bash -c 'cat > \"$usvc\"'" <<UPSVC
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
  run "bash -c 'cat > \"$utmr\"'" <<UPTMR
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
  run "systemctl daemon-reload"
  run "systemctl enable '${SERVICE_NAME}-update.timer'"
  run "systemctl restart '${SERVICE_NAME}-update.timer' || systemctl start '${SERVICE_NAME}-update.timer'"
}

run_background(){
  [ "$RUN_AFTER" -eq 1 ] || return 0
  [ "$INSTALL_SERVICE" -eq 1 ] && return 0
  info "Starting bot in background ..."
  run "bash -c 'nohup \"$DEST_DIR/.venv/bin/python\" -m app.bot >\"$DEST_DIR/bot.log\" 2>&1 & echo $! >\"$DEST_DIR/bot.pid\"'"
  ok "Started (PID $(cat "$DEST_DIR/bot.pid" 2>/dev/null || echo '?'))"
}

uninstall_all(){
  ensure_root
  if command -v systemctl >/dev/null 2>&1; then
    run "systemctl disable --now '${SERVICE_NAME}-update.timer' 2>/dev/null || true"
    run "systemctl disable --now '$SERVICE_NAME' 2>/dev/null || true"
    run "rm -f '/etc/systemd/system/${SERVICE_NAME}.service' '/etc/systemd/system/${SERVICE_NAME}-update.service' '/etc/systemd/system/${SERVICE_NAME}-update.timer'"
    run "systemctl daemon-reload || true"
  fi
  run "rm -rf '$DEST_DIR'"
  ok "Uninstalled"
}

main_install(){
  ensure_root
  pkg_install
  local prev_commit=""
  if [ -d "$DEST_DIR/.git" ]; then prev_commit=$(git -C "$DEST_DIR" rev-parse HEAD 2>/dev/null || true); fi
  clone_or_update
  create_venv_and_deps
  write_env
  if ! self_check; then
    warn "Self-check failed"
    if [ "$ROLLBACK_ON_FAIL" -eq 1 ] && [ -n "$prev_commit" ]; then
      warn "Rolling back to $prev_commit"
      run "git -C '$DEST_DIR' reset --hard '$prev_commit'"
      create_venv_and_deps || true
    else
      err "Install failed"; exit 1
    fi
  fi
  install_service
  install_timer
  run_background
  ok "Done. Path: $DEST_DIR"
}

main_update(){ ACTION="install"; main_install; }

case "$ACTION" in
  uninstall) uninstall_all ;;
  install|update) main_install ;;
  *) usage; exit 2 ;;
 esac