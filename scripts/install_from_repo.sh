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

usage() {
  cat <<USAGE
Bootstrap installer: clone repo, setup, and run as service (optional)

This installer ALWAYS deploys the latest commit of the repository's default branch (remote HEAD).

Options:
  -r REPO_URL            Repository URL (default: https://github.com/yo1u23/guanggao)
  -d DEST_DIR            Destination directory (default: /opt/telegram-ad-guard-bot)
  -R                     Run bot after setup
  -s                     Install and enable systemd service
  -n SERVICE_NAME        Systemd service name (default: telegram-ad-guard-bot)
  -u SERVICE_USER        User to run service as (default: current user)
  -U                     Enable auto-update timer (systemd timer)
  -I INTERVAL            Auto-update interval (default: 15m; e.g., 1h, 6h, 1d)
  -Y                     Fully non-interactive (pass -y to setup.sh); use env vars for token etc.

Pass-through setup options (optional; if omitted, interactive wizard will prompt):
  -t TOKEN               Bot token
  -a ADMIN_IDS           Comma-separated admin user IDs
  -l ADMIN_LOG_CHAT_IDS  Comma-separated admin log chat IDs
  -o OCR_LANGUAGES       Tesseract languages (default: chi_sim+eng)
  -D DEFAULT_ACTION      Action on hit (default: delete_and_mute_and_notify)

Examples:
  sudo bash scripts/install_from_repo.sh -r https://github.com/yo1u23/guanggao -R -s -U -I 1h -Y \
    -t 123456:ABC -a 111,222 -l -1001234567890 -o chi_sim+eng -D delete_and_mute_and_notify

  # Minimal: interactive prompts
  sudo bash scripts/install_from_repo.sh
USAGE
}

while getopts ":r:d:RsUn:u:I:YT:a:l:o:D:h" opt; do
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
    T) SETUP_ARGS+=( -t "$OPTARG" ); SETUP_INTERACTIVE=0 ;;
    a) SETUP_ARGS+=( -a "$OPTARG" ); SETUP_INTERACTIVE=0 ;;
    l) SETUP_ARGS+=( -l "$OPTARG" ); SETUP_INTERACTIVE=0 ;;
    o) SETUP_ARGS+=( -o "$OPTARG" ); SETUP_INTERACTIVE=0 ;;
    D) SETUP_ARGS+=( -d "$OPTARG" ); SETUP_INTERACTIVE=0 ;;
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

# Ensure apt-get, git, python3, venv
if command -v apt-get >/dev/null 2>&1; then
  info "Installing system deps (git, python3, venv, tesseract)..."
  sudo apt-get update -y
  sudo apt-get install -y git python3 python3-venv tesseract-ocr tesseract-ocr-chi-sim tesseract-ocr-chi-tra || true
else
  warn "apt-get not found. Please install git/python3/venv/tesseract manually."
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
  sudo mkdir -p "$DEST_DIR"
  sudo chown -R "$(id -un)":"$(id -gn)" "$DEST_DIR"
  git clone --branch "$DEFAULT_BRANCH" --depth 1 "$REPO_URL" "$DEST_DIR"
fi

cd "$DEST_DIR"

# Run setup
if [ $RUN_AFTER -eq 1 ]; then
  SETUP_ARGS+=( -r )
fi
if [ $SETUP_AUTO_Y -eq 1 ]; then
  SETUP_ARGS+=( -y )
fi
if [ $SETUP_INTERACTIVE -eq 1 ] && [ $SETUP_AUTO_Y -eq 0 ]; then
  info "Running interactive setup..."
  bash scripts/setup.sh "${SETUP_ARGS[@]}"
else
  info "Running setup (non-interactive or pre-specified arguments)..."
  bash scripts/setup.sh "${SETUP_ARGS[@]}"
fi

# Install systemd service (optional)
if [ $INSTALL_SERVICE -eq 1 ]; then
  SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
  info "Installing systemd service: $SERVICE_FILE (User=$SERVICE_USER)"
  sudo bash -c "cat > '$SERVICE_FILE'" <<SERVICE
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
  sudo systemctl daemon-reload
  sudo systemctl enable "$SERVICE_NAME"
  sudo systemctl restart "$SERVICE_NAME" || sudo systemctl start "$SERVICE_NAME"
  info "Service '$SERVICE_NAME' started. Use: systemctl status $SERVICE_NAME"
fi

# Install auto-update timer (optional)
if [ $INSTALL_AUTO_UPDATE -eq 1 ]; then
  UPDATE_SVC="/etc/systemd/system/${SERVICE_NAME}-update.service"
  UPDATE_TMR="/etc/systemd/system/${SERVICE_NAME}-update.timer"
  info "Installing auto-update timer: every $UPDATE_INTERVAL"
  sudo bash -c "cat > '$UPDATE_SVC'" <<UPSVC
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

  sudo bash -c "cat > '$UPDATE_TMR'" <<UPTMR
[Unit]
Description=Run ${SERVICE_NAME}-update.service every $UPDATE_INTERVAL

[Timer]
OnUnitActiveSec=$UPDATE_INTERVAL
AccuracySec=1s
Unit=${SERVICE_NAME}-update.service

[Install]
WantedBy=timers.target
UPTMR
  sudo systemctl daemon-reload
  sudo systemctl enable "${SERVICE_NAME}-update.timer"
  sudo systemctl restart "${SERVICE_NAME}-update.timer" || sudo systemctl start "${SERVICE_NAME}-update.timer"
  info "Auto-update timer enabled. Use: systemctl list-timers | grep ${SERVICE_NAME}-update"
fi

info "Done. Repo: $REPO_URL, Branch: $DEFAULT_BRANCH, Path: $DEST_DIR"