import json
import sqlite3
from pathlib import Path
from typing import Any, Dict, Optional

from .config import DATA_DIR

DB_PATH = DATA_DIR / "ad_guard.db"

_SCHEMA = """
CREATE TABLE IF NOT EXISTS rules (
  chat_id INTEGER PRIMARY KEY,
  keywords TEXT NOT NULL,
  regexes TEXT NOT NULL,
  action TEXT NOT NULL,
  mute_seconds INTEGER NOT NULL,
  newcomer_buffer_seconds INTEGER NOT NULL,
  newcomer_buffer_mode TEXT NOT NULL,
  captcha_enabled INTEGER NOT NULL,
  captcha_timeout_seconds INTEGER NOT NULL,
  first_message_strict INTEGER NOT NULL
);
"""


def _connect() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA synchronous=NORMAL;")
    return conn


def init_db() -> None:
    with _connect() as conn:
        conn.executescript(_SCHEMA)


def get_rules_row(chat_id: Optional[int]) -> Optional[Dict[str, Any]]:
    chat_id = int(chat_id or 0)
    with _connect() as conn:
        conn.row_factory = sqlite3.Row
        cur = conn.execute("SELECT * FROM rules WHERE chat_id = ?", (chat_id,))
        row = cur.fetchone()
        if not row:
            return None
        return {k: row[k] for k in row.keys()}


def upsert_rules_row(chat_id: Optional[int], data: Dict[str, Any]) -> None:
    chat_id = int(chat_id or 0)
    fields = (
        "keywords", "regexes", "action", "mute_seconds",
        "newcomer_buffer_seconds", "newcomer_buffer_mode",
        "captcha_enabled", "captcha_timeout_seconds", "first_message_strict"
    )
    values = tuple(
        data.get(name) for name in fields
    )
    with _connect() as conn:
        conn.execute(
            """
            INSERT INTO rules (
              chat_id, keywords, regexes, action, mute_seconds,
              newcomer_buffer_seconds, newcomer_buffer_mode, captcha_enabled,
              captcha_timeout_seconds, first_message_strict
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(chat_id) DO UPDATE SET
              keywords=excluded.keywords,
              regexes=excluded.regexes,
              action=excluded.action,
              mute_seconds=excluded.mute_seconds,
              newcomer_buffer_seconds=excluded.newcomer_buffer_seconds,
              newcomer_buffer_mode=excluded.newcomer_buffer_mode,
              captcha_enabled=excluded.captcha_enabled,
              captcha_timeout_seconds=excluded.captcha_timeout_seconds,
              first_message_strict=excluded.first_message_strict
            """,
            (chat_id, *values)
        )


def migrate_from_json_if_needed() -> None:
    # If DB already has any row, skip
    with _connect() as conn:
        cur = conn.execute("SELECT 1 FROM rules LIMIT 1")
        if cur.fetchone():
            return
    # Load global json and per-chat files
    json_files = list(DATA_DIR.glob("rules_chat_*.json"))
    global_file = DATA_DIR / "rules_global.json"
    if global_file.exists():
        json_files.append(global_file)
    for jf in json_files:
        try:
            data = json.loads(jf.read_text(encoding="utf-8"))
            if jf.name.startswith("rules_chat_"):
                chat_id_str = jf.name[len("rules_chat_"):-len(".json")]
                chat_id = int(chat_id_str)
            else:
                chat_id = 0
            row = {
                "keywords": json.dumps(data.get("keywords", []), ensure_ascii=False),
                "regexes": json.dumps(data.get("regexes", []), ensure_ascii=False),
                "action": data.get("action", "delete_and_mute_and_notify"),
                "mute_seconds": int(data.get("mute_seconds", 3600)),
                "newcomer_buffer_seconds": int(data.get("newcomer_buffer_seconds", 300)),
                "newcomer_buffer_mode": str(data.get("newcomer_buffer_mode", "restrict_media")),
                "captcha_enabled": 1 if data.get("captcha_enabled", False) else 0,
                "captcha_timeout_seconds": int(data.get("captcha_timeout_seconds", 120)),
                "first_message_strict": 1 if data.get("first_message_strict", True) else 0,
            }
            upsert_rules_row(chat_id, row)
        except Exception:
            continue