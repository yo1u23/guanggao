#!/usr/bin/env bash
set -euo pipefail

# Defaults
WORKDIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$WORKDIR/.env"
RUN_AFTER_SETUP=0
TOKEN=""
ADMIN_IDS=""
ADMIN_LOG_CHAT_IDS=""
OCR_LANGUAGES="chi_sim+eng"
DEFAULT_ACTION="delete_and_mute_and_notify"

usage() {
  cat <<USAGE
One-click setup for Telegram Ad Guard Bot

Options (all optional; if omitted, an interactive wizard will prompt):
  -t TOKEN                 Telegram bot token (from @BotFather)
  -a ADMIN_IDS             Comma-separated admin user IDs (optional)
  -l ADMIN_LOG_CHAT_IDS    Comma-separated admin log chat IDs (optional)
  -o OCR_LANGUAGES         Tesseract languages (default: chi_sim+eng)
  -d DEFAULT_ACTION        Action on hit (default: delete_and_mute_and_notify)
  -r                       Run bot after setup
  -h                       Show this help

Examples:
  ./scripts/setup.sh -t 123:ABC -a 111,222 -l -1001234567890 -r
  ./scripts/setup.sh   # interactive wizard
USAGE
}

# Parse args
if [ $# -gt 0 ]; then
  while getopts ":t:a:l:o:d:rh" opt; do
    case $opt in
      t) TOKEN="$OPTARG" ;;
      a) ADMIN_IDS="$OPTARG" ;;
      l) ADMIN_LOG_CHAT_IDS="$OPTARG" ;;
      o) OCR_LANGUAGES="$OPTARG" ;;
      d) DEFAULT_ACTION="$OPTARG" ;;
      r) RUN_AFTER_SETUP=1 ;;
      h) usage; exit 0 ;;
      :) echo "Option -$OPTARG requires an argument"; usage; exit 2 ;;
      \?) echo "Unknown option -$OPTARG"; usage; exit 2 ;;
    esac
  done
fi

prompt() {
  local label="$1"; shift
  local varname="$1"; shift
  local def="${1-}"; shift || true
  local secret="${1-}"; shift || true
  local value
  if [ -n "$def" ]; then
    if [ -n "$secret" ]; then
      read -r -p "$label [$def]: " value || true
    else
      read -r -p "$label [$def]: " value || true
    fi
    value="${value:-$def}"
  else
    if [ -n "$secret" ]; then
      read -r -p "$label: " value || true
    else
      read -r -p "$label: " value || true
    fi
  fi
  printf -v "$varname" '%s' "$value"
}

# Interactive wizard if TOKEN missing
if [ -z "$TOKEN" ]; then
  echo "=== Telegram Ad Guard Bot - Interactive Setup ==="
  echo "按回车接受默认值，必填项将反复询问。"
  while [ -z "$TOKEN" ]; do
    prompt "请输入 Telegram 机器人 Token (必填)" TOKEN "" secret
    if [ -z "$TOKEN" ]; then
      echo "Token 不能为空。"
    fi
  done
  prompt "全局管理员用户ID（逗号分隔，可留空）" ADMIN_IDS ""
  prompt "管理员通知 Chat ID（逗号分隔，可留空）" ADMIN_LOG_CHAT_IDS ""
  prompt "OCR 语言" OCR_LANGUAGES "$OCR_LANGUAGES"
  prompt "默认动作 (delete|notify|delete_and_notify|mute|mute_and_notify|delete_and_mute|delete_and_mute_and_notify)" DEFAULT_ACTION "$DEFAULT_ACTION"
  local_run="N"
  read -r -p "搭建完成后立即运行机器人？(y/N): " local_run || true
  case "${local_run:-N}" in
    y|Y) RUN_AFTER_SETUP=1 ;;
    *) RUN_AFTER_SETUP=0 ;;
  esac
fi

cd "$WORKDIR"

info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }

# Install system deps
if command -v apt-get >/dev/null 2>&1; then
  info "Updating apt and installing system dependencies..."
  sudo apt-get update -y
  sudo apt-get install -y python3-venv tesseract-ocr tesseract-ocr-chi-sim tesseract-ocr-chi-tra || true
else
  warn "apt-get not found. Please install Tesseract OCR and python3-venv manually for your OS."
fi

# Create venv
if [ ! -d .venv ]; then
  info "Creating Python virtual environment..."
  python3 -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate

info "Upgrading pip/setuptools/wheel..."
python -m pip install -U pip setuptools wheel

info "Installing Python dependencies..."
pip install -r requirements.txt

# Prepare .env
if [ ! -f "$ENV_FILE" ]; then
  if [ -f "$WORKDIR/.env.example" ]; then
    cp "$WORKDIR/.env.example" "$ENV_FILE"
  else
    touch "$ENV_FILE"
  fi
fi

set_env() {
  local key="$1"; shift
  local value="$1"; shift || true
  value="${value//\/\\}"
  value="${value//&/\&}"
  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*$|${key}=${value}|" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >>"$ENV_FILE"
  fi
}

[ -n "$TOKEN" ] && set_env TELEGRAM_BOT_TOKEN "$TOKEN"
[ -n "$ADMIN_IDS" ] && set_env ADMIN_IDS "$ADMIN_IDS"
[ -n "$ADMIN_LOG_CHAT_IDS" ] && set_env ADMIN_LOG_CHAT_IDS "$ADMIN_LOG_CHAT_IDS"
[ -n "$OCR_LANGUAGES" ] && set_env OCR_LANGUAGES "$OCR_LANGUAGES"
[ -n "$DEFAULT_ACTION" ] && set_env DEFAULT_ACTION "$DEFAULT_ACTION"

info ".env configured at $ENV_FILE"

# Final checks (OCR)
python - <<'PY'
from app.ocr import assert_tesseract_available
try:
    assert_tesseract_available()
    print('[INFO] OCR available')
except Exception as e:
    print('[WARN] OCR not available:', e)
PY

info "Setup finished. To run:"
echo "  source .venv/bin/activate && python -m app.bot"

if [ "$RUN_AFTER_SETUP" -eq 1 ]; then
  info "Starting bot... (Ctrl+C to stop)"
  exec python -m app.bot
fi