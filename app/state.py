from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Dict, Tuple, Optional


@dataclass
class UserState:
    joined_at: datetime
    messages_sent: int
    captcha_required: bool
    captcha_passed: bool


# Key: (chat_id, user_id)
_user_state: Dict[Tuple[int, int], UserState] = {}


def on_user_join(chat_id: int, user_id: int, require_captcha: bool) -> UserState:
    state = UserState(
        joined_at=datetime.now(timezone.utc),
        messages_sent=0,
        captcha_required=require_captcha,
        captcha_passed=not require_captcha,
    )
    _user_state[(chat_id, user_id)] = state
    return state


def get_user_state(chat_id: int, user_id: int) -> Optional[UserState]:
    return _user_state.get((chat_id, user_id))


def mark_captcha_passed(chat_id: int, user_id: int) -> None:
    state = _user_state.get((chat_id, user_id))
    if state:
        state.captcha_passed = True
        state.captcha_required = False


def increment_message_count(chat_id: int, user_id: int) -> int:
    state = _user_state.get((chat_id, user_id))
    if not state:
        state = on_user_join(chat_id, user_id, require_captcha=False)
    state.messages_sent += 1
    return state.messages_sent


def is_within_buffer(chat_id: int, user_id: int, buffer_seconds: int) -> bool:
    if buffer_seconds <= 0:
        return False
    state = _user_state.get((chat_id, user_id))
    if not state:
        return False
    delta = datetime.now(timezone.utc) - state.joined_at
    return delta.total_seconds() < buffer_seconds


def reset_user_state(chat_id: int, user_id: int) -> None:
    _user_state.pop((chat_id, user_id), None)