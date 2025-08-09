"""In-memory newcomer and captcha state.

Bridges to SQLite via state_db_bridge when persistence is required.
"""
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
    captcha_expected_answer: Optional[str] = None
    captcha_message_id: Optional[int] = None


# Key: (chat_id, user_id)
_user_state: Dict[Tuple[int, int], UserState] = {}


def on_user_join(chat_id: int, user_id: int, require_captcha: bool) -> UserState:
    state = UserState(
        joined_at=datetime.now(timezone.utc),
        messages_sent=0,
        captcha_required=require_captcha,
        captcha_passed=not require_captcha,
        captcha_expected_answer=None,
        captcha_message_id=None,
    )
    _user_state[(chat_id, user_id)] = state
    return state


def get_user_state(chat_id: int, user_id: int) -> Optional[UserState]:
    return _user_state.get((chat_id, user_id))


def set_captcha_expected(chat_id: int, user_id: int, answer: str, message_id: int) -> None:
    state = _user_state.get((chat_id, user_id))
    if not state:
        state = on_user_join(chat_id, user_id, require_captcha=True)
    state.captcha_expected_answer = answer
    state.captcha_message_id = message_id
    state.captcha_required = True
    state.captcha_passed = False


def get_captcha_expected(chat_id: int, user_id: int) -> Optional[str]:
    st = _user_state.get((chat_id, user_id))
    return st.captcha_expected_answer if st else None


def clear_captcha(chat_id: int, user_id: int) -> None:
    st = _user_state.get((chat_id, user_id))
    if st:
        st.captcha_expected_answer = None
        st.captcha_message_id = None
        st.captcha_required = False
        st.captcha_passed = True


def mark_captcha_passed(chat_id: int, user_id: int) -> None:
    clear_captcha(chat_id, user_id)


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


# Per-user selected target chat (for private admin command routing)
_user_target_chat_by_user: Dict[int, int] = {}


def set_user_target_chat(user_id: int, chat_id: int) -> None:
    """Remember which group chat the user is currently managing via private commands."""
    _user_target_chat_by_user[int(user_id)] = int(chat_id)


def get_user_target_chat(user_id: int) -> Optional[int]:
    """Return the selected target chat id for a user, or None if not set."""
    return _user_target_chat_by_user.get(int(user_id))