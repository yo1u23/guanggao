import json
import sqlite3
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

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
  first_message_strict INTEGER NOT NULL,
  domain_whitelist TEXT NOT NULL DEFAULT '[]',
  domain_blacklist TEXT NOT NULL DEFAULT '[]'
);

CREATE TABLE IF NOT EXISTS user_state (
  chat_id INTEGER NOT NULL,
  user_id INTEGER NOT NULL,
  joined_at INTEGER NOT NULL,
  messages_sent INTEGER NOT NULL,
  captcha_required INTEGER NOT NULL,
  captcha_passed INTEGER NOT NULL,
  captcha_expected_answer TEXT,
  captcha_message_id INTEGER,
  PRIMARY KEY(chat_id, user_id)
);

CREATE TABLE IF NOT EXISTS ocr_cache (
  key TEXT PRIMARY KEY,          -- file_unique_id or perceptual hash
  text TEXT NOT NULL,
  created_at INTEGER NOT NULL
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
        _migrate_rules_add_columns(conn)


def _migrate_rules_add_columns(conn: sqlite3.Connection) -> None:
    cur = conn.execute("PRAGMA table_info(rules)")
    cols = {row[1] for row in cur.fetchall()}
    to_add: Dict[str, str] = {}
    if "domain_whitelist" not in cols:
        to_add["domain_whitelist"] = "TEXT NOT NULL DEFAULT '[]'"
    if "domain_blacklist" not in cols:
        to_add["domain_blacklist"] = "TEXT NOT NULL DEFAULT '[]'"
    for col, decl in to_add.items():
        conn.execute(f"ALTER TABLE rules ADD COLUMN {col} {decl}")


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
        "captcha_enabled", "captcha_timeout_seconds", "first_message_strict",
        "domain_whitelist", "domain_blacklist",
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
              captcha_timeout_seconds, first_message_strict,
              domain_whitelist, domain_blacklist
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(chat_id) DO UPDATE SET
              keywords=excluded.keywords,
              regexes=excluded.regexes,
              action=excluded.action,
              mute_seconds=excluded.mute_seconds,
              newcomer_buffer_seconds=excluded.newcomer_buffer_seconds,
              newcomer_buffer_mode=excluded.newcomer_buffer_mode,
              captcha_enabled=excluded.captcha_enabled,
              captcha_timeout_seconds=excluded.captcha_timeout_seconds,
              first_message_strict=excluded.first_message_strict,
              domain_whitelist=excluded.domain_whitelist,
              domain_blacklist=excluded.domain_blacklist
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
                "domain_whitelist": json.dumps(data.get("domain_whitelist", []), ensure_ascii=False),
                "domain_blacklist": json.dumps(data.get("domain_blacklist", []), ensure_ascii=False),
            }
            upsert_rules_row(chat_id, row)
        except Exception:
            continue


# --- User state CRUD ---

def get_user_state_row(chat_id: int, user_id: int) -> Optional[Dict[str, Any]]:
    with _connect() as conn:
        conn.row_factory = sqlite3.Row
        cur = conn.execute(
            "SELECT * FROM user_state WHERE chat_id = ? AND user_id = ?",
            (int(chat_id), int(user_id)),
        )
        row = cur.fetchone()
        return {k: row[k] for k in row.keys()} if row else None


essential_state_fields = (
    "joined_at", "messages_sent", "captcha_required", "captcha_passed",
    "captcha_expected_answer", "captcha_message_id",
)


def upsert_user_state(chat_id: int, user_id: int, data: Dict[str, Any]) -> None:
    vals = {k: data.get(k) for k in essential_state_fields}
    with _connect() as conn:
        conn.execute(
            """
            INSERT INTO user_state (
              chat_id, user_id, joined_at, messages_sent,
              captcha_required, captcha_passed, captcha_expected_answer, captcha_message_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(chat_id, user_id) DO UPDATE SET
              joined_at=excluded.joined_at,
              messages_sent=excluded.messages_sent,
              captcha_required=excluded.captcha_required,
              captcha_passed=excluded.captcha_passed,
              captcha_expected_answer=excluded.captcha_expected_answer,
              captcha_message_id=excluded.captcha_message_id
            """,
            (
                int(chat_id), int(user_id),
                int(vals["joined_at"]), int(vals["messages_sent"]),
                int(vals["captcha_required"]), int(vals["captcha_passed"]),
                vals.get("captcha_expected_answer"), vals.get("captcha_message_id"),
            ),
        )


def update_user_state_fields(chat_id: int, user_id: int, fields: Dict[str, Any]) -> None:
    if not fields:
        return
    sets = []
    args: Tuple[Any, ...] = tuple()
    for k, v in fields.items():
        sets.append(f"{k} = ?")
        args += (v,)
    args += (int(chat_id), int(user_id))
    with _connect() as conn:
        conn.execute(f"UPDATE user_state SET {', '.join(sets)} WHERE chat_id = ? AND user_id = ?", args)


def delete_user_state(chat_id: int, user_id: int) -> None:
    with _connect() as conn:
        conn.execute("DELETE FROM user_state WHERE chat_id = ? AND user_id = ?", (int(chat_id), int(user_id)))


def get_ocr_cache(key: str) -> Optional[str]:
    with _connect() as conn:
        conn.row_factory = sqlite3.Row
        cur = conn.execute("SELECT text FROM ocr_cache WHERE key = ?", (key,))
        row = cur.fetchone()
        return row["text"] if row else None


def set_ocr_cache(key: str, text: str) -> None:
    import time
    with _connect() as conn:
        conn.execute(
            "INSERT INTO ocr_cache(key, text, created_at) VALUES (?, ?, ?) ON CONFLICT(key) DO UPDATE SET text=excluded.text, created_at=excluded.created_at",
            (key, text, int(time.time())),
        )