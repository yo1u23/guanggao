import json
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import List, Dict, Any, Optional

from .config import DATA_DIR, DEFAULT_ACTION, ALLOWED_ACTIONS


@dataclass
class Rules:
    keywords: List[str]
    regexes: List[str]
    action: str
    mute_seconds: int
    # Newcomer governance
    newcomer_buffer_seconds: int
    newcomer_buffer_mode: str  # none|mute|restrict_media|restrict_links
    captcha_enabled: bool
    captcha_timeout_seconds: int
    first_message_strict: bool


_VALID_BUFFER_MODES = {"none", "mute", "restrict_media", "restrict_links"}


def _rules_file_for_chat(chat_id: Optional[int]) -> Path:
    if chat_id is None:
        return DATA_DIR / "rules_global.json"
    return DATA_DIR / f"rules_chat_{chat_id}.json"


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


def load_rules(chat_id: Optional[int] = None) -> Rules:
    path = _rules_file_for_chat(chat_id)
    if not path.exists():
        rules = _default_rules()
        save_rules(rules, chat_id)
        return rules
    try:
        data: Dict[str, Any] = json.loads(path.read_text(encoding="utf-8"))
        keywords = data.get("keywords", [])
        regexes = data.get("regexes", [])
        action = data.get("action", DEFAULT_ACTION)
        mute_seconds = int(data.get("mute_seconds", 3600))
        newcomer_buffer_seconds = int(data.get("newcomer_buffer_seconds", 300))
        newcomer_buffer_mode = str(data.get("newcomer_buffer_mode", "restrict_media"))
        captcha_enabled = bool(data.get("captcha_enabled", False))
        captcha_timeout_seconds = int(data.get("captcha_timeout_seconds", 120))
        first_message_strict = bool(data.get("first_message_strict", True))

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
    except Exception:
        rules = _default_rules()
        save_rules(rules, chat_id)
        return rules


def save_rules(rules: Rules, chat_id: Optional[int] = None) -> None:
    path = _rules_file_for_chat(chat_id)
    path.write_text(json.dumps(asdict(rules), ensure_ascii=False, indent=2), encoding="utf-8")


def add_keyword(keyword: str, chat_id: Optional[int] = None) -> Rules:
    keyword = keyword.strip()
    rules = load_rules(chat_id)
    if keyword and keyword not in rules.keywords:
        rules.keywords.append(keyword)
        save_rules(rules, chat_id)
    return rules


def remove_keyword(keyword: str, chat_id: Optional[int] = None) -> Rules:
    keyword = keyword.strip()
    rules = load_rules(chat_id)
    rules.keywords = [k for k in rules.keywords if k != keyword]
    save_rules(rules, chat_id)
    return rules


def add_regex(pattern: str, chat_id: Optional[int] = None) -> Rules:
    pattern = pattern.strip()
    rules = load_rules(chat_id)
    if pattern and pattern not in rules.regexes:
        rules.regexes.append(pattern)
        save_rules(rules, chat_id)
    return rules


def remove_regex(pattern: str, chat_id: Optional[int] = None) -> Rules:
    pattern = pattern.strip()
    rules = load_rules(chat_id)
    rules.regexes = [p for p in rules.regexes if p != pattern]
    save_rules(rules, chat_id)
    return rules


def set_action(action: str, chat_id: Optional[int] = None) -> Rules:
    if action not in ALLOWED_ACTIONS:
        raise ValueError("Invalid action")
    rules = load_rules(chat_id)
    rules.action = action
    save_rules(rules, chat_id)
    return rules


def set_mute_seconds(seconds: int, chat_id: Optional[int] = None) -> Rules:
    if seconds < 0:
        raise ValueError("seconds must be >= 0")
    rules = load_rules(chat_id)
    rules.mute_seconds = int(seconds)
    save_rules(rules, chat_id)
    return rules


def set_newcomer_buffer(seconds: int, mode: str, chat_id: Optional[int] = None) -> Rules:
    if seconds < 0:
        raise ValueError("seconds must be >= 0")
    if mode not in _VALID_BUFFER_MODES:
        raise ValueError("invalid buffer mode")
    rules = load_rules(chat_id)
    rules.newcomer_buffer_seconds = int(seconds)
    rules.newcomer_buffer_mode = mode
    save_rules(rules, chat_id)
    return rules


def set_captcha(enabled: bool, timeout_seconds: Optional[int] = None, chat_id: Optional[int] = None) -> Rules:
    rules = load_rules(chat_id)
    rules.captcha_enabled = bool(enabled)
    if timeout_seconds is not None:
        if int(timeout_seconds) < 10:
            raise ValueError("captcha timeout must be >= 10s")
        rules.captcha_timeout_seconds = int(timeout_seconds)
    save_rules(rules, chat_id)
    return rules


def set_first_message_strict(enabled: bool, chat_id: Optional[int] = None) -> Rules:
    rules = load_rules(chat_id)
    rules.first_message_strict = bool(enabled)
    save_rules(rules, chat_id)
    return rules