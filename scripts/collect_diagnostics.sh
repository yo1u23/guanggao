#!/usr/bin/env bash
set -euo pipefail

# Collect environment and runtime diagnostics to help reproduce issues.
# - Gathers OS info, Python/venv, pip packages, tesseract/ffmpeg versions
# - Captures .env (sensitive fields masked), git commit, requirements.txt
# - Collects systemd service status/journal (if available) and bot.log tail
# - Outputs either a tar.gz bundle (default) or a single text file (-T)
#
# Usage examples:
#   bash scripts/collect_diagnostics.sh -n telegram-ad-guard-bot -p /opt/telegram-ad-guard-bot
#   bash scripts/collect_diagnostics.sh -T -o ./diag.txt
#
# Options:
#   -n SERVICE_NAME   systemd service name (default: telegram-ad-guard-bot)
#   -p DEST_DIR       deployment directory (default: current repo root)
#   -o OUTPUT         output path (.tar.gz by default; .txt when -T)
#   -t TAIL_LINES     tail lines for logs (default: 300)
#   -T                text mode (emit a single .txt instead of tar.gz)

SERVICE_NAME="telegram-ad-guard-bot"
DEST_DIR=""
OUTPUT=""
TAIL_LINES=300
TEXT_MODE=0

while getopts ":n:p:o:t:Th" opt; do
  case $opt in
    n) SERVICE_NAME="$OPTARG" ;;
    p) DEST_DIR="$OPTARG" ;;
    o) OUTPUT="$OPTARG" ;;
    t) TAIL_LINES="$OPTARG" ;;
    T) TEXT_MODE=1 ;;
    h)
      cat <<USAGE
Collect diagnostics for Telegram Ad Guard Bot

-n SERVICE_NAME   systemd service name (default: telegram-ad-guard-bot)
-p DEST_DIR       deployment directory (default: current repo root)
-o OUTPUT         output path (.tar.gz default; .txt when -T)
-t TAIL_LINES     tail lines for logs (default: 300)
-T                text mode (single .txt)
USAGE
      exit 0
      ;;
    \?) echo "Unknown option -$OPTARG"; exit 2 ;;
    :) echo "Option -$OPTARG requires an argument"; exit 2 ;;
  esac
done

# Resolve DEST_DIR default to repository root (this script's parent/..)
if [ -z "$DEST_DIR" ]; then
  DEST_DIR="$(cd "$(dirname "$0")/.." && pwd)"
fi

# Resolve default OUTPUT
ts="$(date +%Y%m%d_%H%M%S)"
if [ -z "$OUTPUT" ]; then
  if [ $TEXT_MODE -eq 1 ]; then
    OUTPUT="$PWD/diagnostics_${ts}.txt"
  else
    OUTPUT="$PWD/diagnostics_${ts}.tar.gz"
  fi
fi

# Helpers
info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
exists() { command -v "$1" >/dev/null 2>&1; }

mask_env_file() {
  # Mask sensitive fields in .env-like file: TELEGRAM_BOT_TOKEN, OPENROUTER_API_KEY
  # Show only first 6 chars, replace the rest with *
  awk '
  BEGIN{FS=OFS="="}
  function mask(v){ if(length(v)<=6){return v} else {return substr(v,1,6)"***masked***"} }
  /^\s*#/ {print; next}
  /^[[:space:]]*$/ {print; next}
  {
    key=$1; $1=""; sub(/^=/,""); val=$0
    gsub(/^\s+|\s+$/,"",val)
    if (key=="TELEGRAM_BOT_TOKEN" || key=="OPENROUTER_API_KEY") { val=mask(val) }
    print key"="val
  }
  ' "$1"
}

collect_text() {
  local out="$1"
  {
    echo "=== BASIC ===";
    echo "DATE: $(date -Is)";
    echo "HOST: $(hostname)";
    echo "UNAME: $(uname -a)";
    [ -f /etc/os-release ] && { echo "-- /etc/os-release --"; cat /etc/os-release; } || true
    exists lsb_release && { echo "-- lsb_release -a --"; lsb_release -a || true; }

    echo; echo "=== REPO ===";
    if [ -d "$DEST_DIR/.git" ]; then
      (cd "$DEST_DIR" && echo "GIT_REMOTE: $(git remote get-url origin 2>/dev/null || echo n/a)"; \
        echo "GIT_BRANCH: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo n/a)"; \
        echo "GIT_COMMIT: $(git rev-parse --short HEAD 2>/dev/null || echo n/a)")
    else
      echo "No git repo at $DEST_DIR"
    fi

    echo; echo "=== PYTHON ===";
    echo "which python: $(which python3 || true)";
    echo "python3 --version: $(python3 --version 2>&1 || true)";
    if [ -x "$DEST_DIR/.venv/bin/python" ]; then
      echo "venv python: $DEST_DIR/.venv/bin/python";
      echo "venv version: $($DEST_DIR/.venv/bin/python --version 2>&1)";
      echo "pip freeze (top 50):";
      $DEST_DIR/.venv/bin/pip freeze 2>/dev/null | head -n 50 || true
    fi

    echo; echo "=== DEPENDENCIES ===";
    echo "tesseract: $(tesseract --version 2>&1 | head -n1 || echo missing)";
    echo "ffmpeg: $(ffmpeg -version 2>&1 | head -n1 || echo missing)";

    echo; echo "=== ENV (.env, sensitive masked) ===";
    if [ -f "$DEST_DIR/.env" ]; then
      mask_env_file "$DEST_DIR/.env"
    else
      echo ".env not found at $DEST_DIR/.env"
    fi

    echo; echo "=== REQUIREMENTS (snapshot) ===";
    [ -f "$DEST_DIR/requirements.txt" ] && head -n 200 "$DEST_DIR/requirements.txt" || echo "requirements.txt not found"

    echo; echo "=== IMPORT CHECK ===";
    if [ -x "$DEST_DIR/.venv/bin/python" ]; then
      "$DEST_DIR/.venv/bin/python" - <<'PY'
import importlib, sys
try:
    importlib.import_module('app.bot')
    print('IMPORT_OK=True')
except Exception as e:
    print('IMPORT_OK=False', e)
    sys.exit(0)
PY
    else
      echo "venv python not found; skip import check"
    fi

    echo; echo "=== SYSTEMD (if available) ===";
    if exists systemctl; then
      systemctl status "$SERVICE_NAME" --no-pager || true
      echo; echo "--- journalctl (tail $TAIL_LINES) ---";
      journalctl -u "$SERVICE_NAME" -n "$TAIL_LINES" --no-pager || true
    else
      echo "systemctl not found"
    fi

    echo; echo "=== BOT LOG (tail $TAIL_LINES) ===";
    if [ -f "$DEST_DIR/bot.log" ]; then
      tail -n "$TAIL_LINES" "$DEST_DIR/bot.log" || true
    else
      echo "bot.log not found at $DEST_DIR/bot.log"
    fi
  } > "$out"
}

main() {
  if [ $TEXT_MODE -eq 1 ]; then
    collect_text "$OUTPUT"
    info "Diagnostics written to $OUTPUT"
    return 0
  fi

  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  # Text summary
  collect_text "$tmp/summary.txt"

  # Raw files
  [ -f "$DEST_DIR/.env" ] && mask_env_file "$DEST_DIR/.env" >"$tmp/env.masked" || true
  [ -f "$DEST_DIR/requirements.txt" ] && cp "$DEST_DIR/requirements.txt" "$tmp/requirements.txt" || true
  [ -f "$DEST_DIR/README.md" ] && grep -n "VERSION_START" -n "$DEST_DIR/README.md" > "$tmp/readme_version.txt" || true

  # Package
  tar -C "$tmp" -czf "$OUTPUT" .
  info "Diagnostics bundle written to $OUTPUT"
}

main "$@"