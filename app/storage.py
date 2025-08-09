"""Per-chat rule storage backed by SQLite via db helpers.

This module exposes a Rules dataclass and CRUD operations for per-chat
keywords, regexes, actions, and newcomer governance, mapping to the `rules`
table. It validates and normalizes inputs and hides persistence details.
"""
import json
from dataclasses import dataclass, asdict
from typing import List, Dict, Any, Optional

from .config import DEFAULT_ACTION, ALLOWED_ACTIONS
from .db import get_rules_row, upsert_rules_row


@dataclass
class Rules:
    keywords: List[str]
    regexes: List[str]
    action: str
    mute_seconds: int
    newcomer_buffer_seconds: int
    newcomer_buffer_mode: str
    captcha_enabled: bool
    captcha_timeout_seconds: int
    first_message_strict: bool


_VALID_BUFFER_MODES = {"none", "mute", "restrict_media", "restrict_links"}


def _default_rules() -> Rules:
    """Return default per-chat `Rules` with safe, sensible defaults.

    Returns:
        Rules: Fresh rules instance used when no row exists for a chat.
    """
    return Rules(
        keywords=[],
        regexes=[],
        action=DEFAULT_ACTION,
        mute_seconds=3600,
        newcomer_buffer_seconds=300,
        newcomer_buffer_mode="restrict_media",
        captcha_enabled=False,
        captcha_timeout_seconds=120,
        first_message_strict=True,
    )


def _row_to_rules(row: Optional[Dict[str, Any]]) -> Rules:
    """Convert a DB row dict into a `Rules` object with validation.

    Args:
        row: Row mapping from `db.get_rules_row` or None.

    Returns:
        Rules: Normalized rules instance.
    """
    if not row:
        return _default_rules()
    try:
        keywords = json.loads(row.get("keywords", "[]"))
    except Exception:
        keywords = []
    try:
        regexes = json.loads(row.get("regexes", "[]"))
    except Exception:
        regexes = []
    action = str(row.get("action", DEFAULT_ACTION))
    mute_seconds = int(row.get("mute_seconds", 3600))
    newcomer_buffer_seconds = int(row.get("newcomer_buffer_seconds", 300))
    newcomer_buffer_mode = str(row.get("newcomer_buffer_mode", "restrict_media"))
    captcha_enabled = bool(int(row.get("captcha_enabled", 0)))
    captcha_timeout_seconds = int(row.get("captcha_timeout_seconds", 120))
    first_message_strict = bool(int(row.get("first_message_strict", 1)))

    if action not in ALLOWED_ACTIONS:
        action = DEFAULT_ACTION
    if mute_seconds < 0:
        mute_seconds = 0
    if newcomer_buffer_seconds < 0:
        newcomer_buffer_seconds = 0
    if newcomer_buffer_mode not in _VALID_BUFFER_MODES:
        newcomer_buffer_mode = "none"
    if captcha_timeout_seconds < 10:
        captcha_timeout_seconds = 10

    return Rules(
        keywords=list(dict.fromkeys(map(str, keywords))),
        regexes=list(dict.fromkeys(map(str, regexes))),
        action=action,
        mute_seconds=mute_seconds,
        newcomer_buffer_seconds=newcomer_buffer_seconds,
        newcomer_buffer_mode=newcomer_buffer_mode,
        captcha_enabled=captcha_enabled,
        captcha_timeout_seconds=captcha_timeout_seconds,
        first_message_strict=first_message_strict,
    )


def load_rules(chat_id: Optional[int] = None) -> Rules:
    """Fetch rules for a chat (or global fallback chat_id=0).

    Args:
        chat_id: Telegram chat id. None/0 means global.

    Returns:
        Rules: Rules object for the chat, or defaults if missing.
    """
    row = get_rules_row(chat_id)
    return _row_to_rules(row)


def _save_rules(rules: Rules, chat_id: Optional[int]) -> None:
    """Persist a `Rules` object into the DB.

    Args:
        rules: Rules to be stored.
        chat_id: Target chat id (None treated as 0/global).
    """
    upsert_rules_row(
        chat_id,
        {
            "keywords": json.dumps(rules.keywords, ensure_ascii=False),
            "regexes": json.dumps(rules.regexes, ensure_ascii=False),
            "action": rules.action,
            "mute_seconds": int(rules.mute_seconds),
            "newcomer_buffer_seconds": int(rules.newcomer_buffer_seconds),
            "newcomer_buffer_mode": rules.newcomer_buffer_mode,
            "captcha_enabled": 1 if rules.captcha_enabled else 0,
            "captcha_timeout_seconds": int(rules.captcha_timeout_seconds),
            "first_message_strict": 1 if rules.first_message_strict else 0,
        },
    )


def add_keyword(keyword: str, chat_id: Optional[int] = None) -> Rules:
    """Append a keyword to the rules if not duplicated.

    Args:
        keyword: Keyword to add.
        chat_id: Target chat.

    Returns:
        Rules: Updated rules.
    """
    keyword = keyword.strip()
    rules = load_rules(chat_id)
    if keyword and keyword not in rules.keywords:
        rules.keywords.append(keyword)
        _save_rules(rules, chat_id)
    return rules


def remove_keyword(keyword: str, chat_id: Optional[int] = None) -> Rules:
    """Remove a keyword from the rules.

    Args:
        keyword: Keyword to remove.
        chat_id: Target chat.

    Returns:
        Rules: Updated rules.
    """
    keyword = keyword.strip()
    rules = load_rules(chat_id)
    rules.keywords = [k for k in rules.keywords if k != keyword]
    _save_rules(rules, chat_id)
    return rules


def add_regex(pattern: str, chat_id: Optional[int] = None) -> Rules:
    """Append a regex pattern to the rules if not duplicated.

    Args:
        pattern: Regex string.
        chat_id: Target chat.

    Returns:
        Rules: Updated rules.
    """
    pattern = pattern.strip()
    rules = load_rules(chat_id)
    if pattern and pattern not in rules.regexes:
        rules.regexes.append(pattern)
        _save_rules(rules, chat_id)
    return rules


def remove_regex(pattern: str, chat_id: Optional[int] = None) -> Rules:
    """Remove a regex pattern from the rules.

    Args:
        pattern: Regex string to remove.
        chat_id: Target chat.

    Returns:
        Rules: Updated rules.
    """
    pattern = pattern.strip()
    rules = load_rules(chat_id)
    rules.regexes = [p for p in rules.regexes if p != pattern]
    _save_rules(rules, chat_id)
    return rules


def set_action(action: str, chat_id: Optional[int] = None) -> Rules:
    """Set the default moderation action for this chat.

    Args:
        action: One of `ALLOWED_ACTIONS`.
        chat_id: Target chat.

    Raises:
        ValueError: If action is invalid.

    Returns:
        Rules: Updated rules.
    """
    if action not in ALLOWED_ACTIONS:
        raise ValueError("Invalid action")
    rules = load_rules(chat_id)
    rules.action = action
    _save_rules(rules, chat_id)
    return rules


def set_mute_seconds(seconds: int, chat_id: Optional[int] = None) -> Rules:
    """Set mute duration in seconds for mute-related actions.

    Args:
        seconds: Non-negative duration.
        chat_id: Target chat.

    Raises:
        ValueError: If `seconds` < 0.

    Returns:
        Rules: Updated rules.
    """
    if seconds < 0:
        raise ValueError("seconds must be >= 0")
    rules = load_rules(chat_id)
    rules.mute_seconds = int(seconds)
    _save_rules(rules, chat_id)
    return rules


def set_newcomer_buffer(seconds: int, mode: str, chat_id: Optional[int] = None) -> Rules:
    """Configure newcomer buffer window and mode.

    Args:
        seconds: Non-negative buffer duration.
        mode: One of `_VALID_BUFFER_MODES`.
        chat_id: Target chat.

    Raises:
        ValueError: If seconds < 0 or mode invalid.

    Returns:
        Rules: Updated rules.
    """
    if seconds < 0:
        raise ValueError("seconds must be >= 0")
    if mode not in _VALID_BUFFER_MODES:
        raise ValueError("invalid buffer mode")
    rules = load_rules(chat_id)
    rules.newcomer_buffer_seconds = int(seconds)
    rules.newcomer_buffer_mode = mode
    _save_rules(rules, chat_id)
    return rules


def set_captcha(enabled: bool, timeout_seconds: Optional[int] = None, chat_id: Optional[int] = None) -> Rules:
    """Enable/disable captcha and optionally set timeout.

    Args:
        enabled: Whether captcha is required for newcomers.
        timeout_seconds: Optional timeout (>=10 seconds).
        chat_id: Target chat.

    Raises:
        ValueError: If provided timeout_seconds < 10.

    Returns:
        Rules: Updated rules.
    """
    rules = load_rules(chat_id)
    rules.captcha_enabled = bool(enabled)
    if timeout_seconds is not None:
        if int(timeout_seconds) < 10:
            raise ValueError("captcha timeout must be >= 10s")
        rules.captcha_timeout_seconds = int(timeout_seconds)
    _save_rules(rules, chat_id)
    return rules


def set_first_message_strict(enabled: bool, chat_id: Optional[int] = None) -> Rules:
    """Toggle strict handling for a user's first message after joining.

    Args:
        enabled: If True, matched first message enforces delete+mute+notify.
        chat_id: Target chat.

    Returns:
        Rules: Updated rules.
    """
    rules = load_rules(chat_id)
    rules.first_message_strict = bool(enabled)
    _save_rules(rules, chat_id)
    return rules