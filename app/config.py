import os
from pathlib import Path
from typing import Set

from dotenv import load_dotenv

# Load environment variables from .env if present
load_dotenv()

# Base directories
WORKSPACE_DIR = Path(os.environ.get("WORKSPACE_DIR", "/workspace"))
APP_DIR = WORKSPACE_DIR / "app"
DATA_DIR = Path(os.environ.get("DATA_DIR", str(APP_DIR / "data")))
DATA_DIR.mkdir(parents=True, exist_ok=True)

# Telegram bot token
TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")

# Admin user IDs (comma separated integers)
_raw_admins = os.environ.get("ADMIN_IDS", "").strip()
ADMIN_IDS: Set[int] = set()
if _raw_admins:
    for part in _raw_admins.split(","):
        part = part.strip()
        if part:
            try:
                ADMIN_IDS.add(int(part))
            except ValueError:
                continue

# OCR languages (tesseract language codes)
OCR_LANGUAGES = os.environ.get("OCR_LANGUAGES", "chi_sim+eng")

# Default action when ad keyword is detected
# Options: "delete", "notify", "delete_and_notify"
DEFAULT_ACTION = os.environ.get("DEFAULT_ACTION", "delete_and_notify").strip()
if DEFAULT_ACTION not in {"delete", "notify", "delete_and_notify"}:
    DEFAULT_ACTION = "delete_and_notify"

# Admin log chat IDs (optional): when notifying, send to these chats; falls back to admin DMs
_raw_log_chats = os.environ.get("ADMIN_LOG_CHATS", "").strip()
ADMIN_LOG_CHAT_IDS: Set[int] = set()
if _raw_log_chats:
    for part in _raw_log_chats.split(","):
        part = part.strip()
        if part:
            try:
                ADMIN_LOG_CHAT_IDS.add(int(part))
            except ValueError:
                continue