import json
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import List, Dict, Any

from .config import DATA_DIR, DEFAULT_ACTION

_RULES_FILE = DATA_DIR / "rules.json"


@dataclass
class Rules:
    keywords: List[str]
    regexes: List[str]
    action: str


def _default_rules() -> Rules:
    return Rules(keywords=[], regexes=[], action=DEFAULT_ACTION)


def load_rules() -> Rules:
    if not _RULES_FILE.exists():
        rules = _default_rules()
        save_rules(rules)
        return rules
    try:
        data: Dict[str, Any] = json.loads(_RULES_FILE.read_text(encoding="utf-8"))
        keywords = data.get("keywords", [])
        regexes = data.get("regexes", [])
        action = data.get("action", DEFAULT_ACTION)
        if action not in {"delete", "notify", "delete_and_notify"}:
            action = DEFAULT_ACTION
        return Rules(keywords=list(dict.fromkeys(map(str, keywords))),
                     regexes=list(dict.fromkeys(map(str, regexes))),
                     action=action)
    except Exception:
        rules = _default_rules()
        save_rules(rules)
        return rules


def save_rules(rules: Rules) -> None:
    _RULES_FILE.write_text(json.dumps(asdict(rules), ensure_ascii=False, indent=2), encoding="utf-8")


def add_keyword(keyword: str) -> Rules:
    keyword = keyword.strip()
    rules = load_rules()
    if keyword and keyword not in rules.keywords:
        rules.keywords.append(keyword)
        save_rules(rules)
    return rules


def remove_keyword(keyword: str) -> Rules:
    keyword = keyword.strip()
    rules = load_rules()
    rules.keywords = [k for k in rules.keywords if k != keyword]
    save_rules(rules)
    return rules


def add_regex(pattern: str) -> Rules:
    pattern = pattern.strip()
    rules = load_rules()
    if pattern and pattern not in rules.regexes:
        rules.regexes.append(pattern)
        save_rules(rules)
    return rules


def remove_regex(pattern: str) -> Rules:
    pattern = pattern.strip()
    rules = load_rules()
    rules.regexes = [p for p in rules.regexes if p != pattern]
    save_rules(rules)
    return rules


def set_action(action: str) -> Rules:
    if action not in {"delete", "notify", "delete_and_notify"}:
        raise ValueError("Invalid action")
    rules = load_rules()
    rules.action = action
    save_rules(rules)
    return rules