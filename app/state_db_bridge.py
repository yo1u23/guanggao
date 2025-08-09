from datetime import datetime, timezone
from typing import Optional

from .db import get_user_state_row, upsert_user_state, update_user_state_fields, delete_user_state
from .state import UserState


def load_user_state(chat_id: int, user_id: int) -> Optional[UserState]:
    row = get_user_state_row(chat_id, user_id)
    if not row:
        return None
    return UserState(
        joined_at=datetime.fromtimestamp(int(row["joined_at"]), tz=timezone.utc),
        messages_sent=int(row["messages_sent"]),
        captcha_required=bool(int(row["captcha_required"])),
        captcha_passed=bool(int(row["captcha_passed"])),
        captcha_expected_answer=row.get("captcha_expected_answer"),
        captcha_message_id=row.get("captcha_message_id"),
    )


def save_user_state(chat_id: int, user_id: int, state: UserState) -> None:
    upsert_user_state(
        chat_id,
        user_id,
        {
            "joined_at": int(state.joined_at.timestamp()),
            "messages_sent": int(state.messages_sent),
            "captcha_required": 1 if state.captcha_required else 0,
            "captcha_passed": 1 if state.captcha_passed else 0,
            "captcha_expected_answer": state.captcha_expected_answer,
            "captcha_message_id": state.captcha_message_id,
        },
    )


def update_state_fields(chat_id: int, user_id: int, **fields):
    if "joined_at" in fields and hasattr(fields["joined_at"], "timestamp"):
        fields["joined_at"] = int(fields["joined_at"].timestamp())
    update_user_state_fields(chat_id, user_id, fields)


def delete_state(chat_id: int, user_id: int) -> None:
    delete_user_state(chat_id, user_id)