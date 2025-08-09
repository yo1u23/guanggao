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


def _rules_file_for_chat(chat_id: Optional[int]) -> Path:
    if chat_id is None:
        return DATA_DIR / "rules_global.json"
    return DATA_DIR / f"rules_chat_{chat_id}.json"


def _default_rules() -> Rules:
    return Rules(keywords=[], regexes=[], action=DEFAULT_ACTION, mute_seconds=3600)


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
        if action not in ALLOWED_ACTIONS:
            action = DEFAULT_ACTION
        if mute_seconds < 0:
            mute_seconds = 0
        return Rules(
            keywords=list(dict.fromkeys(map(str, keywords))),
            regexes=list(dict.fromkeys(map(str, regexes))),
            action=action,
            mute_seconds=mute_seconds,
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