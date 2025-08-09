#!/usr/bin/env bash
set -euo pipefail

# Defaults
REPO_URL=""
BRANCH="main"
DEST_DIR="/opt/telegram-ad-guard-bot"
RUN_AFTER=0
SETUP_ARGS=()
SETUP_INTERACTIVE=1
INSTALL_SERVICE=0
SERVICE_NAME="telegram-ad-guard-bot"
SERVICE_USER="$(id -un)"

usage() {
  cat <<USAGE
Bootstrap installer: clone repo, setup, and run as service (optional)

Options:
  -r REPO_URL            Repository URL (default: https://github.com/yo1u23/guanggao)
  -b BRANCH              Branch to checkout (default: main)
  -d DEST_DIR            Destination directory (default: /opt/telegram-ad-guard-bot)
  -R                     Run bot after setup
  -s                     Install and enable systemd service
  -n SERVICE_NAME        Systemd service name (default: telegram-ad-guard-bot)
  -u SERVICE_USER        User to run service as (default: current user)

Pass-through setup options (optional; if omitted, interactive wizard will prompt):
  -t TOKEN               Bot token
  -a ADMIN_IDS           Comma-separated admin user IDs
  -l ADMIN_LOG_CHAT_IDS  Comma-separated admin log chat IDs
  -o OCR_LANGUAGES       Tesseract languages (default: chi_sim+eng)
  -D DEFAULT_ACTION      Action on hit (default: delete_and_mute_and_notify)

Examples:
  sudo bash scripts/install_from_repo.sh -r https://github.com/yo1u23/guanggao -R -s \
    -t 123456:ABC -a 111,222 -l -1001234567890 -o chi_sim+eng -D delete_and_mute_and_notify

  # Minimal: interactive prompts
  sudo bash scripts/install_from_repo.sh
USAGE
}

while getopts ":r:b:d:Rs n:u:t:a:l:o:D:h" opt; do
  case $opt in
    r) REPO_URL="$OPTARG" ;;
    b) BRANCH="$OPTARG" ;;
    d) DEST_DIR="$OPTARG" ;;
    R) RUN_AFTER=1 ;;
    s) INSTALL_SERVICE=1 ;;
    n) SERVICE_NAME="$OPTARG" ;;
    u) SERVICE_USER="$OPTARG" ;;
    t) SETUP_ARGS+=( -t "$OPTARG" ); SETUP_INTERACTIVE=0 ;;
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

# Ensure apt-get, git, python3, venv
if command -v apt-get >/dev/null 2>&1; then
  info "Installing system deps (git, python3, venv, tesseract)..."
  sudo apt-get update -y
  sudo apt-get install -y git python3 python3-venv tesseract-ocr tesseract-ocr-chi-sim tesseract-ocr-chi-tra || true
else
  warn "apt-get not found. Please install git/python3/venv/tesseract manually."
fi

# Clone or update
if [ -d "$DEST_DIR/.git" ]; then
  info "Repo exists in $DEST_DIR, pulling..."
  git -C "$DEST_DIR" fetch --all
  git -C "$DEST_DIR" checkout "$BRANCH"
  git -C "$DEST_DIR" pull --rebase --autostash origin "$BRANCH"
else
  info "Cloning $REPO_URL to $DEST_DIR ..."
  sudo mkdir -p "$DEST_DIR"
  sudo chown -R "$(id -un)":"$(id -gn)" "$DEST_DIR"
  git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$DEST_DIR"
fi

cd "$DEST_DIR"

# Run setup
if [ $RUN_AFTER -eq 1 ]; then
  SETUP_ARGS+=( -r )
fi
if [ $SETUP_INTERACTIVE -eq 1 ]; then
  info "Running interactive setup..."
  bash scripts/setup.sh "${SETUP_ARGS[@]}"
else
  info "Running setup with provided arguments..."
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

info "Done. Repo: $REPO_URL, Branch: $BRANCH, Path: $DEST_DIR"