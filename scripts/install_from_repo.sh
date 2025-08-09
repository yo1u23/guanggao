#!/usr/bin/env bash
set -euo pipefail

# Defaults
REPO_URL=""
DEST_DIR="/opt/telegram-ad-guard-bot"
RUN_AFTER=0
SETUP_ARGS=()
SETUP_INTERACTIVE=1
SETUP_AUTO_Y=0
INSTALL_SERVICE=0
SERVICE_NAME="telegram-ad-guard-bot"
SERVICE_USER="$(id -un)"
# Auto update
INSTALL_AUTO_UPDATE=0
UPDATE_INTERVAL="15m"  # supports systemd time: e.g. 15m, 1h, 1d
# Self-check & rollback
SELF_CHECK=1
ROLLBACK_ON_FAIL=1

# Optional env controls for dry-run/testing
SUDO_CMD="sudo"
if [ -n "${NO_SUDO-}" ]; then SUDO_CMD=""; fi

usage() {
  cat <<USAGE
Bootstrap installer: clone repo, setup, and run as service (optional)

This installer ALWAYS deploys the latest commit of the repository's default branch (remote HEAD).

Options:
  -r REPO_URL            Repository URL (default: https://github.com/yo1u23/guanggao)
  -d DEST_DIR            Destination directory (default: /opt/telegram-ad-guard-bot)
  -R                     Run bot after setup (if no -s, runs in background after self-check)
  -s                     Install and enable systemd service
  -n SERVICE_NAME        Systemd service name (default: telegram-ad-guard-bot)
  -u SERVICE_USER        User to run service as (default: current user)
  -U                     Enable auto-update timer (systemd timer)
  -I INTERVAL            Auto-update interval (default: 15m; e.g., 1h, 6h, 1d)
  -Y                     Fully non-interactive (pass -y to setup.sh); use env vars for token etc.
  -C                     Disable post-install self-check
  -N                     Disable rollback on self-check failure

Pass-through setup options (optional; if omitted, interactive wizard will prompt):
  -t TOKEN               Bot token
  -a ADMIN_IDS           Comma-separated admin user IDs
  -l ADMIN_LOG_CHAT_IDS  Comma-separated admin log chat IDs
  -o OCR_LANGUAGES       Tesseract languages (default: chi_sim+eng)
  -D DEFAULT_ACTION      Action on hit (default: delete_and_mute_and_notify)

AI (OpenRouter) pass-through options:
  -M AI_MODE             off|openrouter
  -K OPENROUTER_API_KEY  API key
  -B OPENROUTER_API_BASE API base (default: https://openrouter.ai/api/v1)
  -m OPENROUTER_MODEL    Model name (e.g., gpt-4o-mini)
  -E AI_EXCLUSIVE        on|off
  -T AI_THRESHOLD        0..1

Examples:
  sudo bash scripts/install_from_repo.sh -r https://github.com/yo1u23/guanggao -R -s -U -I 1h -Y \
    -t 123456:ABC -a 111,222 -l -1001234567890 -o chi_sim+eng -D delete_and_mute_and_notify -M openrouter -K sk-... -m gpt-4o-mini -E on -T 0.7

  # Minimal: interactive prompts
  sudo bash scripts/install_from_repo.sh
USAGE
}

while getopts ":r:d:RsUn:u:I:Yt:a:l:o:D:M:K:B:m:E:T:CNh" opt; do
  case $opt in
    r) REPO_URL="$OPTARG" ;;
    d) DEST_DIR="$OPTARG" ;;
    R) RUN_AFTER=1 ;;
    s) INSTALL_SERVICE=1 ;;
    U) INSTALL_AUTO_UPDATE=1 ;;
    n) SERVICE_NAME="$OPTARG" ;;
    u) SERVICE_USER="$OPTARG" ;;
    I) UPDATE_INTERVAL="$OPTARG" ;;
    Y) SETUP_AUTO_Y=1 ;;
    t) SETUP_ARGS+=( -t "$OPTARG" ); SETUP_INTERACTIVE=0 ;;
    a) SETUP_ARGS+=( -a "$OPTARG" ); SETUP_INTERACTIVE=0 ;;
    l) SETUP_ARGS+=( -l "$OPTARG" ); SETUP_INTERACTIVE=0 ;;
    o) SETUP_ARGS+=( -o "$OPTARG" ); SETUP_INTERACTIVE=0 ;;
    D) SETUP_ARGS+=( -d "$OPTARG" ); SETUP_INTERACTIVE=0 ;;
    M) SETUP_ARGS+=( -M "$OPTARG" ); SETUP_INTERACTIVE=0 ;;
    K) SETUP_ARGS+=( -K "$OPTARG" ); SETUP_INTERACTIVE=0 ;;
    B) SETUP_ARGS+=( -B "$OPTARG" ); SETUP_INTERACTIVE=0 ;;
    m) SETUP_ARGS+=( -m "$OPTARG" ); SETUP_INTERACTIVE=0 ;;
    E) SETUP_ARGS+=( -E "$OPTARG" ); SETUP_INTERACTIVE=0 ;;
    T) SETUP_ARGS+=( -T "$OPTARG" ); SETUP_INTERACTIVE=0 ;;
    C) SELF_CHECK=0 ;;
    N) ROLLBACK_ON_FAIL=0 ;;
    h) usage; exit 0 ;;
    \?) echo "Unknown option -$OPTARG"; usage; exit 2 ;;
    :) echo "Option -$OPTARG requires an argument"; usage; exit 2 ;;
  esac
done

[ -z "$REPO_URL" ] && REPO_URL="https://github.com/yo1u23/guanggao"

info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }

# Determine default branch of remote HEAD
get_default_branch() {
  local url="$1"
  local ref
  ref=$(git ls-remote --symref "$url" HEAD 2>/dev/null | awk '/^ref:/ {print $2}' | sed 's#refs/heads/##') || true
  if [ -z "$ref" ]; then
    echo "main"
  else
    echo "$ref"
  fi
}

DEFAULT_BRANCH=$(get_default_branch "$REPO_URL")
info "Remote default branch: $DEFAULT_BRANCH"

# Snapshot previous state (for rollback)
PRE_EXISTING=0
PREV_COMMIT=""
if [ -d "$DEST_DIR/.git" ]; then
  PRE_EXISTING=1
  PREV_COMMIT=$(git -C "$DEST_DIR" rev-parse HEAD 2>/dev/null || true)
  info "Previous commit: ${PREV_COMMIT:-<none>}"
fi

# Ensure apt-get, git, python3, venv
if [ -n "${SKIP_APT-}" ]; then
  info "Skipping system deps installation due to SKIP_APT=1"
else
  if command -v apt-get >/dev/null 2>&1; then
    info "Installing system deps (git, python3, venv, tesseract, ffmpeg)..."
    $SUDO_CMD apt-get update -y || true
    $SUDO_CMD apt-get install -y git python3 python3-venv tesseract-ocr tesseract-ocr-chi-sim tesseract-ocr-chi-tra ffmpeg || true
  else
    warn "apt-get not found. Please install git/python3/venv/tesseract/ffmpeg manually."
  fi
fi

# Clone or update latest default branch
if [ -d "$DEST_DIR/.git" ]; then
  info "Repo exists in $DEST_DIR, syncing to latest $DEFAULT_BRANCH ..."
  git -C "$DEST_DIR" remote set-url origin "$REPO_URL" || true
  git -C "$DEST_DIR" fetch origin "$DEFAULT_BRANCH" --depth=1
  git -C "$DEST_DIR" checkout -B "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH"
  git -C "$DEST_DIR" reset --hard "origin/$DEFAULT_BRANCH"
else
  info "Cloning $REPO_URL ($DEFAULT_BRANCH) to $DEST_DIR ..."
  $SUDO_CMD mkdir -p "$DEST_DIR"
  if [ -n "$SUDO_CMD" ]; then $SUDO_CMD chown -R "$(id -un)":"$(id -gn)" "$DEST_DIR" || true; fi
  git clone --branch "$DEFAULT_BRANCH" --depth 1 "$REPO_URL" "$DEST_DIR"
fi

cd "$DEST_DIR"

# Build setup args
if [ $SETUP_AUTO_Y -eq 1 ]; then
  SETUP_ARGS+=( -y )
fi

# Run setup (without immediate run; we'll self-check first)
if [ $SETUP_INTERACTIVE -eq 1 ] && [ $SETUP_AUTO_Y -eq 0 ]; then
  info "Running interactive setup..."
  bash scripts/setup.sh "${SETUP_ARGS[@]}"
else
  info "Running setup (non-interactive or pre-specified arguments)..."
  bash scripts/setup.sh "${SETUP_ARGS[@]}"
fi

# Post-install self-check
self_check() {
  local ok=1
  if [ ! -x "$DEST_DIR/.venv/bin/python" ]; then
    warn "Venv python missing: $DEST_DIR/.venv/bin/python"
    return 1
  fi
  if ! grep -q '^TELEGRAM_BOT_TOKEN=' "$DEST_DIR/.env" 2>/dev/null; then
    warn ".env missing TELEGRAM_BOT_TOKEN"
    ok=0
  fi
  local out
  out=$("$DEST_DIR/.venv/bin/python" - <<'PY'
import compileall
ok = compileall.compile_dir('app', quiet=1)
print('COMPILE_OK='+str(bool(ok)))
PY
) || true
  echo "$out" | grep -q 'COMPILE_OK=True' || ok=0
  out=$("$DEST_DIR/.venv/bin/python" - <<'PY'
import importlib, sys
try:
    importlib.import_module('app.bot')
    print('IMPORT_OK=True')
except Exception as e:
    print('IMPORT_OK=False', e)
    sys.exit(1)
PY
) || true
  echo "$out" | grep -q 'IMPORT_OK=True' || ok=0
  if ! command -v tesseract >/dev/null 2>&1; then
    warn "tesseract not found (OCR features may be limited)"
  fi
  if ! command -v ffmpeg >/dev/null 2>&1; then
    warn "ffmpeg not found (video OCR features may be limited)"
  fi
  return $ok
}

rollback() {
  if [ $ROLLBACK_ON_FAIL -ne 1 ]; then
    warn "Rollback disabled; leaving current state."
    return 1
  fi
  if [ $PRE_EXISTING -eq 1 ] && [ -n "${PREV_COMMIT}" ]; then
    warn "Rolling back to previous commit ${PREV_COMMIT} ..."
    git -C "$DEST_DIR" reset --hard "$PREV_COMMIT" || true
    if [ -x "$DEST_DIR/.venv/bin/pip" ]; then
      info "Reinstalling dependencies after rollback..."
      "$DEST_DIR/.venv/bin/pip" install -r "$DEST_DIR/requirements.txt" || true
    fi
    if [ $INSTALL_SERVICE -eq 1 ] && command -v systemctl >/dev/null 2>&1; then
      warn "Restarting service after rollback..."
      $SUDO_CMD systemctl restart "$SERVICE_NAME" || true
    fi
    info "Rollback completed."
  else
    warn "Fresh install failed; removing $DEST_DIR ..."
    cd /
    $SUDO_CMD rm -rf "$DEST_DIR"
    info "Cleaned $DEST_DIR"
  fi
}

if [ $SELF_CHECK -eq 1 ]; then
  info "Running post-install self-check..."
  if ! self_check; then
    warn "Self-check failed."
    rollback || true
    exit 1
  fi
  info "Self-check passed."
fi

# Install systemd service (optional)
if [ $INSTALL_SERVICE -eq 1 ]; then
  if ! command -v systemctl >/dev/null 2>&1; then
    warn "systemctl not found; skipping service installation."
  else
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
    info "Installing systemd service: $SERVICE_FILE (User=$SERVICE_USER)"
    $SUDO_CMD bash -c "cat > '$SERVICE_FILE'" <<SERVICE
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
    $SUDO_CMD systemctl daemon-reload
    $SUDO_CMD systemctl enable "$SERVICE_NAME"
    $SUDO_CMD systemctl restart "$SERVICE_NAME" || $SUDO_CMD systemctl start "$SERVICE_NAME"
    info "Service '$SERVICE_NAME' started. Use: systemctl status $SERVICE_NAME"
  fi
fi

# Install auto-update timer (optional)
if [ $INSTALL_AUTO_UPDATE -eq 1 ]; then
  if ! command -v systemctl >/dev/null 2>&1; then
    warn "systemctl not found; skipping auto-update timer installation."
  else
    UPDATE_SVC="/etc/systemd/system/${SERVICE_NAME}-update.service"
    UPDATE_TMR="/etc/systemd/system/${SERVICE_NAME}-update.timer"
    info "Installing auto-update timer: every $UPDATE_INTERVAL"
    $SUDO_CMD bash -c "cat > '$UPDATE_SVC'" <<UPSVC
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

    $SUDO_CMD bash -c "cat > '$UPDATE_TMR'" <<UPTMR
[Unit]
Description=Run ${SERVICE_NAME}-update.service every $UPDATE_INTERVAL

[Timer]
OnUnitActiveSec=$UPDATE_INTERVAL
AccuracySec=1s
Persistent=true
Unit=${SERVICE_NAME}-update.service

[Install]
WantedBy=timers.target
UPTMR
    $SUDO_CMD systemctl daemon-reload
    $SUDO_CMD systemctl enable "${SERVICE_NAME}-update.timer"
    $SUDO_CMD systemctl restart "${SERVICE_NAME}-update.timer" || $SUDO_CMD systemctl start "${SERVICE_NAME}-update.timer"
    info "Auto-update timer enabled. Use: systemctl list-timers | grep ${SERVICE_NAME}-update"
  fi
fi

# Run after setup (only if not using systemd)
if [ $RUN_AFTER -eq 1 ] && [ $INSTALL_SERVICE -eq 0 ]; then
  info "Starting bot in background..."
  nohup "$DEST_DIR/.venv/bin/python" -m app.bot >"$DEST_DIR/bot.log" 2>&1 &
  info "Bot started (PID $!). Logs: $DEST_DIR/bot.log"
fi

info "Done. Repo: $REPO_URL, Branch: $DEFAULT_BRANCH, Path: $DEST_DIR"