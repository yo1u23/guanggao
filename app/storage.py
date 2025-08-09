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
    row = get_rules_row(chat_id)
    return _row_to_rules(row)


def _save_rules(rules: Rules, chat_id: Optional[int]) -> None:
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
    keyword = keyword.strip()
    rules = load_rules(chat_id)
    if keyword and keyword not in rules.keywords:
        rules.keywords.append(keyword)
        _save_rules(rules, chat_id)
    return rules


def remove_keyword(keyword: str, chat_id: Optional[int] = None) -> Rules:
    keyword = keyword.strip()
    rules = load_rules(chat_id)
    rules.keywords = [k for k in rules.keywords if k != keyword]
    _save_rules(rules, chat_id)
    return rules


def add_regex(pattern: str, chat_id: Optional[int] = None) -> Rules:
    pattern = pattern.strip()
    rules = load_rules(chat_id)
    if pattern and pattern not in rules.regexes:
        rules.regexes.append(pattern)
        _save_rules(rules, chat_id)
    return rules


def remove_regex(pattern: str, chat_id: Optional[int] = None) -> Rules:
    pattern = pattern.strip()
    rules = load_rules(chat_id)
    rules.regexes = [p for p in rules.regexes if p != pattern]
    _save_rules(rules, chat_id)
    return rules


def set_action(action: str, chat_id: Optional[int] = None) -> Rules:
    if action not in ALLOWED_ACTIONS:
        raise ValueError("Invalid action")
    rules = load_rules(chat_id)
    rules.action = action
    _save_rules(rules, chat_id)
    return rules


def set_mute_seconds(seconds: int, chat_id: Optional[int] = None) -> Rules:
    if seconds < 0:
        raise ValueError("seconds must be >= 0")
    rules = load_rules(chat_id)
    rules.mute_seconds = int(seconds)
    _save_rules(rules, chat_id)
    return rules


def set_newcomer_buffer(seconds: int, mode: str, chat_id: Optional[int] = None) -> Rules:
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
    rules = load_rules(chat_id)
    rules.captcha_enabled = bool(enabled)
    if timeout_seconds is not None:
        if int(timeout_seconds) < 10:
            raise ValueError("captcha timeout must be >= 10s")
        rules.captcha_timeout_seconds = int(timeout_seconds)
    _save_rules(rules, chat_id)
    return rules


def set_first_message_strict(enabled: bool, chat_id: Optional[int] = None) -> Rules:
    rules = load_rules(chat_id)
    rules.first_message_strict = bool(enabled)
    _save_rules(rules, chat_id)
    return rules