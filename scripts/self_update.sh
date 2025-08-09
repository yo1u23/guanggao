#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVICE_NAME="telegram-ad-guard-bot"

cd "$WORKDIR"

info(){ echo "[INFO] $*"; }
warn(){ echo "[WARN] $*"; }

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
info "Current branch: $CURRENT_BRANCH"

git fetch origin "$CURRENT_BRANCH"
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse "origin/$CURRENT_BRANCH")

if [ "$LOCAL" = "$REMOTE" ]; then
  info "Already up to date."
  exit 0
fi

info "Pulling latest..."
# Keep local changes (e.g., .env) out of the way
stash_needed=0
if ! git diff --quiet || ! git diff --cached --quiet; then
  stash_needed=1
  git stash push -u -m "self_update_$(date +%s)" || true
fi

git pull --rebase --autostash origin "$CURRENT_BRANCH"

if [ $stash_needed -eq 1 ]; then
  git stash pop || true
fi

# Reinstall dependencies if requirements changed
if git diff --name-only HEAD@{1} HEAD | grep -q '^requirements\.txt$'; then
  info "requirements.txt changed, reinstalling deps..."
  if [ -d .venv ]; then
    # shellcheck disable=SC1091
    source .venv/bin/activate
    pip install -r requirements.txt
  else
    warn ".venv not found; skipping deps reinstall"
  fi
fi

# Restart service if present
if systemctl list-units --type=service | grep -q "${SERVICE_NAME}\.service"; then
  info "Restarting systemd service: $SERVICE_NAME"
  sudo systemctl restart "$SERVICE_NAME" || warn "restart failed"
fi

info "Update done."