#!/usr/bin/env bash
set -euo pipefail

# Defaults
WORKDIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$WORKDIR/.env"
RUN_AFTER_SETUP=0
TOKEN="${TELEGRAM_BOT_TOKEN-}"
ADMIN_IDS="${ADMIN_IDS-}"
ADMIN_LOG_CHAT_IDS="${ADMIN_LOG_CHAT_IDS-}"
OCR_LANGUAGES="${OCR_LANGUAGES-chi_sim+eng}"
DEFAULT_ACTION="${DEFAULT_ACTION-delete_and_mute_and_notify}"
AUTO_Y=0
# AI defaults from env
AI_MODE="${AI_MODE-off}"
OPENROUTER_API_BASE="${OPENROUTER_API_BASE-https://openrouter.ai/api/v1}"
OPENROUTER_API_KEY="${OPENROUTER_API_KEY-}"
OPENROUTER_MODEL="${OPENROUTER_MODEL-gpt-4o-mini}"
AI_EXCLUSIVE="${AI_EXCLUSIVE-false}"
AI_CLASSIFY_THRESHOLD="${AI_CLASSIFY_THRESHOLD-0.7}"

usage() {
  cat <<USAGE
One-click setup for Telegram Ad Guard Bot

Options (all optional; if omitted, an interactive wizard will prompt):
  -t TOKEN                 Telegram bot token (from @BotFather) [or env TELEGRAM_BOT_TOKEN]
  -a ADMIN_IDS             Comma-separated admin user IDs (optional)
  -l ADMIN_LOG_CHAT_IDS    Comma-separated admin log chat IDs (optional)
  -o OCR_LANGUAGES         Tesseract languages (default: chi_sim+eng)
  -d DEFAULT_ACTION        Action on hit (default: delete_and_mute_and_notify)
  -r                       Run bot after setup
  -y                       Fully non-interactive; use env/defaults; implies -r if RUN_AFTER=1

AI (OpenRouter) options:
  -M AI_MODE               off|openrouter (default from env AI_MODE)
  -K OPENROUTER_API_KEY    OpenRouter API key
  -B OPENROUTER_API_BASE   API base (default: https://openrouter.ai/api/v1)
  -m OPENROUTER_MODEL      Model (e.g., gpt-4o-mini)
  -E AI_EXCLUSIVE          on|off (image/video via AI only)
  -T AI_THRESHOLD          0..1 (classification threshold, default 0.7)

Environment variables honored: TELEGRAM_BOT_TOKEN, ADMIN_IDS, ADMIN_LOG_CHAT_IDS,
OCR_LANGUAGES, DEFAULT_ACTION, RUN_AFTER, AI_MODE, OPENROUTER_API_BASE, OPENROUTER_API_KEY,
OPENROUTER_MODEL, AI_EXCLUSIVE, AI_CLASSIFY_THRESHOLD

Examples:
  ./scripts/setup.sh -t 123:ABC -a 111,222 -l -1001234567890 -r \
    -M openrouter -K sk-... -m gpt-4o-mini -E on -T 0.7
  TELEGRAM_BOT_TOKEN=123:ABC RUN_AFTER=1 AI_MODE=openrouter OPENROUTER_API_KEY=sk-... ./scripts/setup.sh -y
USAGE
}

# Parse args
if [ "$#" -gt 0 ]; then
  while getopts ":t:a:l:o:d:ryM:K:B:m:E:T:h" opt; do
    case $opt in
      t) TOKEN="$OPTARG" ;;
      a) ADMIN_IDS="$OPTARG" ;;
      l) ADMIN_LOG_CHAT_IDS="$OPTARG" ;;
      o) OCR_LANGUAGES="$OPTARG" ;;
      d) DEFAULT_ACTION="$OPTARG" ;;
      r) RUN_AFTER_SETUP=1 ;;
      y) AUTO_Y=1 ;;
      M) AI_MODE="$OPTARG" ;;
      K) OPENROUTER_API_KEY="$OPTARG" ;;
      B) OPENROUTER_API_BASE="$OPTARG" ;;
      m) OPENROUTER_MODEL="$OPTARG" ;;
      E) AI_EXCLUSIVE="$OPTARG" ;;
      T) AI_CLASSIFY_THRESHOLD="$OPTARG" ;;
      h) usage; exit 0 ;;
      :) echo "Option -$OPTARG requires an argument"; usage; exit 2 ;;
      \?) echo "Unknown option -$OPTARG"; usage; exit 2 ;;
    esac
  done
fi

# Honor RUN_AFTER env in -y mode
if [ "${RUN_AFTER-}" = "1" ] || [ "$AUTO_Y" -eq 1 ] && [ "${RUN_AFTER-}" = "1" ]; then
  RUN_AFTER_SETUP=1
fi

prompt() {
  label="$1"; shift
  varname="$1"; shift
  def="${1-}"; shift || true
  value=""
  if [ -n "$def" ]; then
    read -r -p "$label [$def]: " value || true
    value="${value:-$def}"
  else
    read -r -p "$label: " value || true
  fi
  printf -v "$varname" '%s' "$value"
}

# Interactive wizard only when TOKEN missing and not AUTO_Y
if [ -z "$TOKEN" ] && [ "$AUTO_Y" -ne 1 ]; then
  echo "=== Telegram Ad Guard Bot - Interactive Setup ==="
  echo "按回车接受默认值，必填项将反复询问。"
  while [ -z "$TOKEN" ]; do
    prompt "请输入 Telegram 机器人 Token (必填)" TOKEN ""
    if [ -z "$TOKEN" ]; then
      echo "Token 不能为空。"
    fi
  done
  prompt "全局管理员用户ID（逗号分隔，可留空）" ADMIN_IDS "${ADMIN_IDS-}"
  prompt "管理员通知 Chat ID（逗号分隔，可留空）" ADMIN_LOG_CHAT_IDS "${ADMIN_LOG_CHAT_IDS-}"
  prompt "OCR 语言" OCR_LANGUAGES "$OCR_LANGUAGES"
  prompt "默认动作 (delete|notify|delete_and_notify|mute|mute_and_notify|delete_and_mute|delete_and_mute_and_notify)" DEFAULT_ACTION "$DEFAULT_ACTION"
  # AI quick setup
  prompt "AI 模式 (off|openrouter)" AI_MODE "$AI_MODE"
  if [ "$AI_MODE" = "openrouter" ]; then
    prompt "OpenRouter API Key" OPENROUTER_API_KEY "$OPENROUTER_API_KEY"
    prompt "OpenRouter API Base" OPENROUTER_API_BASE "$OPENROUTER_API_BASE"
    prompt "OpenRouter 模型" OPENROUTER_MODEL "$OPENROUTER_MODEL"
    prompt "AI 独占 (on/off)" AI_EXCLUSIVE "$AI_EXCLUSIVE"
    prompt "AI 阈值 (0..1)" AI_CLASSIFY_THRESHOLD "$AI_CLASSIFY_THRESHOLD"
  fi
  local_run="${RUN_AFTER_SETUP}"; [ -z "$local_run" ] && local_run=0
  read -r -p "搭建完成后立即运行机器人？(y/N): " yn || true
  case "${yn:-N}" in y|Y) RUN_AFTER_SETUP=1 ;; *) ;; esac
fi

cd "$WORKDIR"

info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }

# Install system deps
if command -v apt-get >/dev/null 2>&1; then
  info "Updating apt and installing system dependencies..."
  sudo apt-get update -y
  sudo apt-get install -y python3-venv tesseract-ocr tesseract-ocr-chi-sim tesseract-ocr-chi-tra ffmpeg || true
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
  key="$1"; shift
  value="$1"; shift || true
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

# AI envs
[ -n "$AI_MODE" ] && set_env AI_MODE "$AI_MODE"
[ -n "$OPENROUTER_API_BASE" ] && set_env OPENROUTER_API_BASE "$OPENROUTER_API_BASE"
[ -n "$OPENROUTER_API_KEY" ] && set_env OPENROUTER_API_KEY "$OPENROUTER_API_KEY"
[ -n "$OPENROUTER_MODEL" ] && set_env OPENROUTER_MODEL "$OPENROUTER_MODEL"
[ -n "$AI_EXCLUSIVE" ] && set_env AI_EXCLUSIVE "$AI_EXCLUSIVE"
[ -n "$AI_CLASSIFY_THRESHOLD" ] && set_env AI_CLASSIFY_THRESHOLD "$AI_CLASSIFY_THRESHOLD"

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