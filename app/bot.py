import asyncio
import logging
import re
import secrets
import string
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import List, Optional, Tuple
import subprocess

from telegram import (
    Update,
    Message,
    ChatPermissions,
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    ChatMember,
    ChatMemberUpdated,
)
from telegram.constants import ParseMode
from telegram.ext import (
    ApplicationBuilder,
    CommandHandler,
    ContextTypes,
    MessageHandler,
    CallbackQueryHandler,
    ChatMemberHandler,
    filters,
)

from .config import TELEGRAM_BOT_TOKEN, ADMIN_IDS, OCR_LANGUAGES, ADMIN_LOG_CHAT_IDS, ALLOWED_ACTIONS
from .ocr import extract_text_from_image, OCRError
from .text import normalize_text, contains_link
from .cache import ocr_text_cache
from .storage import (
    load_rules,
    add_keyword,
    remove_keyword,
    add_regex,
    remove_regex,
    set_action,
    set_mute_seconds,
    set_newcomer_buffer,
    set_captcha,
    set_first_message_strict,
)
from .state import (
    on_user_join,
    get_user_state,
    increment_message_count,
    is_within_buffer,
    mark_captcha_passed,
    reset_user_state,
)
from .db import init_db, migrate_from_json_if_needed

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
)
logger = logging.getLogger("ad_guard_bot")


def ensure_admin(user_id: int, chat_admin_ids: Optional[List[int]] = None) -> bool:
    if ADMIN_IDS and user_id in ADMIN_IDS:
        return True
    if chat_admin_ids and user_id in chat_admin_ids:
        return True
    if not ADMIN_IDS and not chat_admin_ids:
        return True
    return False


async def _get_chat_admin_ids(context: ContextTypes.DEFAULT_TYPE, chat_id: Optional[int]) -> List[int]:
    if not chat_id:
        return []
    try:
        admins = await context.bot.get_chat_administrators(chat_id)
        return [m.user.id for m in admins]
    except Exception as exc:
        logger.debug("获取群管理员失败: %s", exc)
        return []


async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(
        "你好！我是广告管理机器人。\n"
        "- 识别文本与图片中的关键词/正则\n"
        "- 群管理员或全局管理员可通过命令维护规则，/help 查看",
    )


async def cmd_help(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    help_text = (
        "管理员命令：\n"
        "/add_keyword 词语 — 添加关键词\n"
        "/remove_keyword 词语 — 删除关键词\n"
        "/list_keywords — 列出所有关键词\n"
        "/add_regex 正则 — 添加正则\n"
        "/remove_regex 正则 — 删除正则\n"
        "/list_regex — 列出所有正则\n"
        "/set_action [delete|notify|delete_and_notify|mute|mute_and_notify|delete_and_mute|delete_and_mute_and_notify] — 设置命中处理动作\n"
        "/set_mute_seconds 秒数 — 设置禁言时长（秒），0 表示不禁言\n"
        "\n普通使用：把我拉进群并给管理员权限（删除/禁言）。"
    )
    await update.message.reply_text(help_text)


async def cmd_add_keyword(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    chat_id = update.effective_chat.id if update.effective_chat else None
    chat_admin_ids = await _get_chat_admin_ids(context, chat_id)
    if not ensure_admin(user_id, chat_admin_ids):
        await update.message.reply_text("无权限。仅限群管理员或全局管理员。")
        return
    if not context.args:
        await update.message.reply_text("请提供关键词，例如：/add_keyword 低价代充")
        return
    keyword = " ".join(context.args)
    rules = add_keyword(keyword, chat_id)
    await update.message.reply_text(f"已添加关键词：{keyword}\n当前群当前共 {len(rules.keywords)} 个关键词。")


async def cmd_remove_keyword(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    chat_id = update.effective_chat.id if update.effective_chat else None
    chat_admin_ids = await _get_chat_admin_ids(context, chat_id)
    if not ensure_admin(user_id, chat_admin_ids):
        await update.message.reply_text("无权限。仅限群管理员或全局管理员。")
        return
    if not context.args:
        await update.message.reply_text("请提供要删除的关键词。")
        return
    keyword = " ".join(context.args)
    rules = remove_keyword(keyword, chat_id)
    await update.message.reply_text(f"已删除关键词：{keyword}\n当前群当前共 {len(rules.keywords)} 个关键词。")


async def cmd_list_keywords(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    chat_id = update.effective_chat.id if update.effective_chat else None
    rules = load_rules(chat_id)
    if not rules.keywords:
        await update.message.reply_text("暂无关键词。")
        return
    await update.message.reply_text("关键词列表：\n" + "\n".join(f"- {k}" for k in rules.keywords))


async def cmd_add_regex(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    chat_id = update.effective_chat.id if update.effective_chat else None
    chat_admin_ids = await _get_chat_admin_ids(context, chat_id)
    if not ensure_admin(user_id, chat_admin_ids):
        await update.message.reply_text("无权限。仅限群管理员或全局管理员。")
        return
    if not context.args:
        await update.message.reply_text("请提供正则表达式，例如：/add_regex (?i)\\b代\\s*充\\b")
        return
    pattern = " ".join(context.args)
    try:
        re.compile(pattern)
    except re.error as exc:
        await update.message.reply_text(f"正则无效：{exc}")
        return
    rules = add_regex(pattern, chat_id)
    await update.message.reply_text(f"已添加正则：{pattern}\n当前群当前共 {len(rules.regexes)} 个正则。")


async def cmd_remove_regex(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    chat_id = update.effective_chat.id if update.effective_chat else None
    chat_admin_ids = await _get_chat_admin_ids(context, chat_id)
    if not ensure_admin(user_id, chat_admin_ids):
        await update.message.reply_text("无权限。仅限群管理员或全局管理员。")
        return
    if not context.args:
        await update.message.reply_text("请提供要删除的正则表达式。")
        return
    pattern = " ".join(context.args)
    rules = remove_regex(pattern, chat_id)
    await update.message.reply_text(f"已删除正则：{pattern}\n当前群当前共 {len(rules.regexes)} 个正则。")


async def cmd_list_regex(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    chat_id = update.effective_chat.id if update.effective_chat else None
    rules = load_rules(chat_id)
    if not rules.regexes:
        await update.message.reply_text("暂无正则。")
        return
    await update.message.reply_text("正则列表：\n" + "\n".join(f"- {p}" for p in rules.regexes))


async def cmd_set_action(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    chat_id = update.effective_chat.id if update.effective_chat else None
    chat_admin_ids = await _get_chat_admin_ids(context, chat_id)
    if not ensure_admin(user_id, chat_admin_ids):
        await update.message.reply_text("无权限。仅限群管理员或全局管理员。")
        return
    if not context.args:
        await update.message.reply_text("请提供动作：" + " | ".join(sorted(ALLOWED_ACTIONS)))
        return
    action = context.args[0].strip()
    try:
        rules = set_action(action, chat_id)
        await update.message.reply_text(f"已设置动作：{rules.action}")
    except ValueError:
        await update.message.reply_text("无效动作：请用 " + " | ".join(sorted(ALLOWED_ACTIONS)))


async def cmd_set_mute_seconds(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    chat_id = update.effective_chat.id if update.effective_chat else None
    chat_admin_ids = await _get_chat_admin_ids(context, chat_id)
    if not ensure_admin(user_id, chat_admin_ids):
        await update.message.reply_text("无权限。仅限群管理员或全局管理员。")
        return
    if not context.args:
        await update.message.reply_text("请提供禁言时长（秒），例如：/set_mute_seconds 3600")
        return
    try:
        seconds = int(context.args[0])
    except ValueError:
        await update.message.reply_text("请输入合法的整数秒数。")
        return
    rules = set_mute_seconds(seconds, chat_id)
    await update.message.reply_text(f"已设置禁言时长：{rules.mute_seconds} 秒")


async def cmd_set_newcomer_buffer(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    chat_id = update.effective_chat.id if update.effective_chat else None
    chat_admin_ids = await _get_chat_admin_ids(context, chat_id)
    if not ensure_admin(user_id, chat_admin_ids):
        await update.message.reply_text("无权限。仅限群管理员或全局管理员。")
        return
    if len(context.args) < 2:
        await update.message.reply_text("用法：/set_newcomer_buffer <秒> <none|mute|restrict_media|restrict_links>")
        return
    try:
        seconds = int(context.args[0])
        mode = context.args[1]
        rules = set_newcomer_buffer(seconds, mode, chat_id)
        await update.message.reply_text(f"已设置新人缓冲：{rules.newcomer_buffer_seconds}s，模式：{rules.newcomer_buffer_mode}")
    except ValueError as exc:
        await update.message.reply_text(f"参数错误：{exc}")


async def cmd_set_captcha(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    chat_id = update.effective_chat.id if update.effective_chat else None
    chat_admin_ids = await _get_chat_admin_ids(context, chat_id)
    if not ensure_admin(user_id, chat_admin_ids):
        await update.message.reply_text("无权限。仅限群管理员或全局管理员。")
        return
    if not context.args:
        await update.message.reply_text("用法：/set_captcha <on|off> [timeout_seconds>=10]")
        return
    onoff = context.args[0].lower()
    enabled = onoff in {"on", "true", "1", "enable", "enabled"}
    timeout = None
    if len(context.args) >= 2:
        try:
            timeout = int(context.args[1])
        except ValueError:
            await update.message.reply_text("timeout_seconds 必须为整数")
            return
    try:
        rules = set_captcha(enabled, timeout, chat_id)
        await update.message.reply_text(
            f"验证码：{'开启' if rules.captcha_enabled else '关闭'}，超时：{rules.captcha_timeout_seconds}s")
    except ValueError as exc:
        await update.message.reply_text(f"参数错误：{exc}")


async def cmd_set_first_message_strict(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    chat_id = update.effective_chat.id if update.effective_chat else None
    chat_admin_ids = await _get_chat_admin_ids(context, chat_id)
    if not ensure_admin(user_id, chat_admin_ids):
        await update.message.reply_text("无权限。仅限群管理员或全局管理员。")
        return
    if not context.args:
        await update.message.reply_text("用法：/set_first_message_strict <on|off>")
        return
    onoff = context.args[0].lower()
    enabled = onoff in {"on", "true", "1", "enable", "enabled"}
    rules = set_first_message_strict(enabled, chat_id)
    await update.message.reply_text(f"首条消息加严：{'开启' if rules.first_message_strict else '关闭'}")


async def cmd_update(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    # Only global admins can trigger self-update
    if ADMIN_IDS and user_id not in ADMIN_IDS:
        await update.message.reply_text("无权限。仅限全局管理员。")
        return
    await update.message.reply_text("开始更新，请稍候…")
    try:
        proc = await asyncio.create_subprocess_exec(
            "bash", "scripts/self_update.sh",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )
        stdout, _ = await proc.communicate()
        output = stdout.decode("utf-8", errors="ignore")
        if proc.returncode == 0:
            await update.message.reply_text("更新完成\n" + output[-3500:])
        else:
            await update.message.reply_text("更新失败\n" + output[-3500:])
    except Exception as exc:
        await update.message.reply_text(f"更新执行出错：{exc}")


# --- Detection helpers ---

def _gather_message_text(message: Message) -> str:
    parts: List[str] = []
    if message.text:
        parts.append(message.text)
    if message.caption:
        parts.append(message.caption)
    return "\n".join(parts).strip()


def _match_rules(text: str, chat_id: Optional[int]) -> Tuple[bool, List[str], List[str]]:
    rules = load_rules(chat_id)
    hit_keywords: List[str] = []
    hit_regexes: List[str] = []
    text_norm = normalize_text(text)
    for k in rules.keywords:
        if not k:
            continue
        if normalize_text(k) in text_norm:
            hit_keywords.append(k)
    for p in rules.regexes:
        try:
            if re.search(p, text, flags=re.IGNORECASE) or re.search(p, text_norm, flags=re.IGNORECASE):
                hit_regexes.append(p)
        except re.error:
            continue
    return (bool(hit_keywords or hit_regexes), hit_keywords, hit_regexes)


def _admin_action_keyboard(chat_id: int, user_id: int, message_id: int) -> InlineKeyboardMarkup:
    # Callback data format: a|<code>|<chat>|<user>|<msg>|[secs]
    row1 = [
        InlineKeyboardButton(text="删除", callback_data=f"a|d|{chat_id}|{user_id}|{message_id}"),
        InlineKeyboardButton(text="禁言10m", callback_data=f"a|m|{chat_id}|{user_id}|{message_id}|600"),
        InlineKeyboardButton(text="禁言1h", callback_data=f"a|m|{chat_id}|{user_id}|{message_id}|3600"),
        InlineKeyboardButton(text="禁言1d", callback_data=f"a|m|{chat_id}|{user_id}|{message_id}|86400"),
    ]
    row2 = [
        InlineKeyboardButton(text="解除禁言", callback_data=f"a|u|{chat_id}|{user_id}|{message_id}"),
        InlineKeyboardButton(text="踢出", callback_data=f"a|k|{chat_id}|{user_id}|{message_id}"),
        InlineKeyboardButton(text="封禁", callback_data=f"a|b|{chat_id}|{user_id}|{message_id}"),
    ]
    return InlineKeyboardMarkup([row1, row2])


async def _notify_admins(context: ContextTypes.DEFAULT_TYPE, source_message: Message, text_snippet: str, hit_keywords: List[str], hit_regexes: List[str]) -> None:
    chat = source_message.chat
    user = source_message.from_user
    header = (
        f"检测到疑似广告：\n"
        f"群组：{chat.title or chat.id}\n"
        f"用户：{user.mention_html()} (id={user.id})\n"
        f"消息ID：{source_message.id}\n"
    )
    hits = []
    if hit_keywords:
        hits.append("关键词：" + ", ".join(hit_keywords))
    if hit_regexes:
        hits.append("正则：" + ", ".join(hit_regexes))
    body = header + ("\n".join(hits) + "\n" if hits else "") + "内容预览：\n" + (
        text_snippet[:500] + ("…" if len(text_snippet) > 500 else "")
    )

    targets = list(ADMIN_LOG_CHAT_IDS) or list(ADMIN_IDS)
    keyboard = _admin_action_keyboard(chat.id, user.id, source_message.id)
    for target in targets:
        try:
            await context.bot.send_message(
                chat_id=target,
                text=body,
                parse_mode=ParseMode.HTML,
                disable_web_page_preview=True,
                reply_markup=keyboard,
            )
        except Exception as exc:
            logger.warning("通知管理员失败: %s", exc)


async def _mute_user(context: ContextTypes.DEFAULT_TYPE, chat_id: int, user_id: int, seconds: int) -> None:
    if seconds <= 0:
        return
    until = datetime.now(timezone.utc) + timedelta(seconds=seconds)
    perms = ChatPermissions(can_send_messages=False, can_send_audios=False, can_send_documents=False,
                            can_send_photos=False, can_send_videos=False, can_send_video_notes=False,
                            can_send_voice_notes=False, can_send_polls=False, can_send_other_messages=False,
                            can_add_web_page_previews=False, can_change_info=False, can_invite_users=True,
                            can_pin_messages=False)
    try:
        await context.bot.restrict_chat_member(chat_id=chat_id, user_id=user_id, permissions=perms, until_date=until)
    except Exception as exc:
        logger.warning("禁言失败，可能缺少权限: %s", exc)


async def _unmute_user(context: ContextTypes.DEFAULT_TYPE, chat_id: int, user_id: int) -> None:
    try:
        perms = ChatPermissions(
            can_send_messages=True,
            can_send_audios=True,
            can_send_documents=True,
            can_send_photos=True,
            can_send_videos=True,
            can_send_video_notes=True,
            can_send_voice_notes=True,
            can_send_polls=True,
            can_send_other_messages=True,
            can_add_web_page_previews=True,
            can_change_info=False,
            can_invite_users=True,
            can_pin_messages=False,
        )
        await context.bot.restrict_chat_member(chat_id=chat_id, user_id=user_id, permissions=perms)
    except Exception as exc:
        logger.warning("解除禁言失败: %s", exc)


async def _handle_action(update: Update, context: ContextTypes.DEFAULT_TYPE, matched_text: str, hit_keywords: List[str], hit_regexes: List[str]) -> None:
    chat_id = update.effective_chat.id if update.effective_chat else None
    rules = load_rules(chat_id)
    action = rules.action
    message = update.effective_message
    user_id = update.effective_user.id if update.effective_user else None

    if action in {"delete", "delete_and_notify", "delete_and_mute", "delete_and_mute_and_notify"}:
        try:
            await message.delete()
        except Exception as exc:
            logger.warning("删除消息失败，可能缺少权限: %s", exc)

    if action in {"mute", "mute_and_notify", "delete_and_mute", "delete_and_mute_and_notify"} and chat_id and user_id:
        await _mute_user(context, chat_id, user_id, rules.mute_seconds)

    if action in {"notify", "delete_and_notify", "mute_and_notify", "delete_and_mute_and_notify"}:
        await _notify_admins(context, message, matched_text, hit_keywords, hit_regexes)


# --- Newcomer and captcha flows ---

def _generate_captcha() -> Tuple[str, str]:
    # Simple math captcha: a+b
    a = secrets.randbelow(9) + 1
    b = secrets.randbelow(9) + 1
    question = f"请在 {a}+{b} 中选择正确结果以通过验证"
    answer = str(a + b)
    return question, answer


def _captcha_keyboard(chat_id: int, user_id: int, correct: str) -> InlineKeyboardMarkup:
    # Provide 4 options including correct answer
    options = {correct}
    while len(options) < 4:
        options.add(str(secrets.randbelow(17) + 2))
    buttons = []
    for opt in sorted(options):
        buttons.append(
            InlineKeyboardButton(text=opt, callback_data=f"c|v|{chat_id}|{user_id}|{opt}")
        )
    # Arrange in two rows
    rows = [buttons[:2], buttons[2:]]
    return InlineKeyboardMarkup(rows)


async def _send_captcha(context: ContextTypes.DEFAULT_TYPE, chat_id: int, user_id: int, timeout_seconds: int) -> None:
    question, answer = _generate_captcha()
    kb = _captcha_keyboard(chat_id, user_id, answer)
    try:
        msg = await context.bot.send_message(chat_id=chat_id, text=f"<a href=\"tg://user?id={user_id}\">用户</a> 验证码：{question}", parse_mode=ParseMode.HTML, reply_markup=kb)
        from .state import set_captcha_expected
        set_captcha_expected(chat_id, user_id, answer, msg.id)
    except Exception as exc:
        logger.warning("发送验证码失败: %s", exc)

    async def timeout_task():
        await asyncio.sleep(timeout_seconds)
        st = get_user_state(chat_id, user_id)
        if st and st.captcha_required and not st.captcha_passed:
            try:
                await context.bot.ban_chat_member(chat_id=chat_id, user_id=user_id)
                await context.bot.unban_chat_member(chat_id=chat_id, user_id=user_id, only_if_banned=True)
                # edit captcha message to expired
                if st.captcha_message_id:
                    try:
                        await context.bot.edit_message_text(chat_id=chat_id, message_id=st.captcha_message_id, text="验证码超时 ⛔️")
                    except Exception:
                        pass
            except Exception as exc2:
                logger.warning("验证码超时踢出失败: %s", exc2)

    asyncio.create_task(timeout_task())


async def on_chat_member(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    cm: ChatMemberUpdated = update.chat_member  # type: ignore[assignment]
    if not cm:
        return
    chat_id = cm.chat.id
    member: ChatMember = cm.new_chat_member
    if member.status == ChatMember.MEMBER:
        rules = load_rules(chat_id)
        require_captcha = rules.captcha_enabled
        state = on_user_join(chat_id, member.user.id, require_captcha)
        # Apply newcomer buffer restrictions
        if rules.newcomer_buffer_seconds > 0 and rules.newcomer_buffer_mode != "none":
            try:
                if rules.newcomer_buffer_mode == "mute":
                    await _mute_user(context, chat_id, member.user.id, rules.newcomer_buffer_seconds)
                else:
                    # Restrict media/links by using minimal permissions
                    perms = ChatPermissions(
                        can_send_messages=True,
                        can_send_audios=False,
                        can_send_documents=False,
                        can_send_photos=False,
                        can_send_videos=False,
                        can_send_video_notes=False,
                        can_send_voice_notes=False,
                        can_send_polls=False,
                        can_send_other_messages=False,
                        can_add_web_page_previews=(rules.newcomer_buffer_mode != "restrict_links"),
                    )
                    until = datetime.now(timezone.utc) + timedelta(seconds=rules.newcomer_buffer_seconds)
                    await context.bot.restrict_chat_member(chat_id=chat_id, user_id=member.user.id, permissions=perms, until_date=until)
            except Exception as exc:
                logger.warning("应用新人缓冲限制失败: %s", exc)
        # Send captcha
        if require_captcha:
            await _send_captcha(context, chat_id, member.user.id, rules.captcha_timeout_seconds)


async def on_captcha_click(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    cq = update.callback_query
    if not cq or not cq.data:
        return
    try:
        tag, typ, chat_id_s, user_id_s, opt = cq.data.split("|", 4)
        if tag != "c" or typ != "v":
            return
        chat_id = int(chat_id_s)
        user_id = int(user_id_s)
    except Exception:
        await cq.answer("无效验证", show_alert=True)
        return

    # Only the target user can click
    if cq.from_user.id != user_id:
        await cq.answer("只能本人完成验证", show_alert=True)
        return

    # Strict validate against expected answer
    expected = get_captcha_expected(chat_id, user_id)
    if expected is None:
        await cq.answer("验证已失效或未准备", show_alert=True)
        return
    if opt != expected:
        await cq.answer("答案错误，请重试", show_alert=False)
        return
    mark_captcha_passed(chat_id, user_id)
    await cq.answer("验证通过")
    try:
        await cq.message.edit_text("验证通过 ✅")
    except Exception:
        pass


async def on_text_or_caption(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    message = update.effective_message
    chat_id = update.effective_chat.id if update.effective_chat else None
    user_id = update.effective_user.id if update.effective_user else None

    # Newcomer first-message strictness
    rules = load_rules(chat_id)
    if user_id:
        msg_count = increment_message_count(chat_id, user_id)
        within_buffer = is_within_buffer(chat_id, user_id, rules.newcomer_buffer_seconds)
        # Link blocking during buffer
        if within_buffer and rules.newcomer_buffer_mode == "restrict_links":
            text_tmp = _gather_message_text(message)
            if contains_link(text_tmp):
                try:
                    await message.delete()
                except Exception as exc:
                    logger.warning("缓冲期链接删除失败: %s", exc)
                await _notify_admins(context, message, text_tmp, ["新人期链接"], [])
                return
        if rules.first_message_strict and msg_count == 1:
            # Apply stricter handling: if matched, prefer delete+mute+notify regardless of action
            pass

    text = _gather_message_text(message)
    if not text:
        return
    matched, hit_keywords, hit_regexes = _match_rules(text, chat_id)
    if matched:
        if user_id and rules.first_message_strict and msg_count == 1:
            # Temporarily override action
            original_action = rules.action
            rules.action = "delete_and_mute_and_notify"
            try:
                await _handle_action(update, context, text, hit_keywords, hit_regexes)
            finally:
                rules.action = original_action
            return
        await _handle_action(update, context, text, hit_keywords, hit_regexes)


async def on_photo(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    message = update.effective_message
    chat_id = update.effective_chat.id if update.effective_chat else None
    text_parts: List[str] = []
    if message.caption:
        text_parts.append(message.caption)

    try:
        photo = message.photo[-1]
        file = await photo.get_file()
        cached = ocr_text_cache.get(file.file_unique_id)
        if cached is not None:
            text_parts.append(cached)
        else:
            with tempfile.TemporaryDirectory() as tmpdir:
                tmp_path = Path(tmpdir) / f"photo_{file.file_unique_id}.jpg"
                await file.download_to_drive(custom_path=str(tmp_path))
                try:
                    ocr_text = extract_text_from_image(tmp_path, OCR_LANGUAGES)
                    if ocr_text:
                        text_parts.append(ocr_text)
                        ocr_text_cache.set(file.file_unique_id, ocr_text)
                except OCRError as e:
                    logger.error("OCR 不可用：%s", e)
    except Exception as exc:
        logger.warning("下载或处理图片失败: %s", exc)

    combined_text = "\n".join([t for t in text_parts if t]).strip()
    if not combined_text:
        return

    matched, hit_keywords, hit_regexes = _match_rules(combined_text, chat_id)
    if matched:
        await _handle_action(update, context, combined_text, hit_keywords, hit_regexes)


def _parse_cb(data: str) -> Optional[dict]:
    # a|<code>|<chat>|<user>|<msg>|[secs]
    try:
        parts = data.split("|")
        if len(parts) < 5 or parts[0] != "a":
            return None
        code = parts[1]
        chat_id = int(parts[2])
        user_id = int(parts[3])
        message_id = int(parts[4])
        secs = int(parts[5]) if len(parts) >= 6 else None
        return {"code": code, "chat_id": chat_id, "user_id": user_id, "message_id": message_id, "secs": secs}
    except Exception:
        return None


async def on_admin_action(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    cq = update.callback_query
    if not cq or not cq.data:
        return
    payload = _parse_cb(cq.data)
    if not payload:
        await cq.answer("无效操作", show_alert=True)
        return

    chat_id = payload["chat_id"]
    user_id = payload["user_id"]
    message_id = payload["message_id"]
    secs = payload.get("secs") or 0

    # Permission check: only chat admins or global admins
    chat_admin_ids = await _get_chat_admin_ids(context, chat_id)
    if not ensure_admin(cq.from_user.id, chat_admin_ids):
        await cq.answer("无权限", show_alert=True)
        return

    code = payload["code"]
    try:
        action_desc = None
        if code == "d":
            await context.bot.delete_message(chat_id=chat_id, message_id=message_id)
            action_desc = "删除"
            await cq.answer("已删除")
        elif code == "m":
            await _mute_user(context, chat_id, user_id, secs)
            action_desc = f"禁言{secs}秒"
            await cq.answer(f"已禁言 {secs} 秒")
        elif code == "u":
            await _unmute_user(context, chat_id, user_id)
            action_desc = "解除禁言"
            await cq.answer("已解除禁言")
        elif code == "k":
            await context.bot.ban_chat_member(chat_id=chat_id, user_id=user_id)
            await context.bot.unban_chat_member(chat_id=chat_id, user_id=user_id, only_if_banned=True)
            action_desc = "踢出"
            await cq.answer("已踢出")
        elif code == "b":
            await context.bot.ban_chat_member(chat_id=chat_id, user_id=user_id)
            action_desc = "封禁"
            await cq.answer("已封禁")
        else:
            await cq.answer("未知操作", show_alert=True)
            return
    except Exception as exc:
        logger.warning("按钮操作失败: %s", exc)
        await cq.answer("操作失败，可能权限不足", show_alert=True)
        return

    # Disable buttons after action and mark processed
    try:
        if action_desc:
            new_text = (cq.message.text or "") + f"\n\n（已处理：{action_desc}）"
            await cq.message.edit_text(new_text)
    except Exception:
        pass


async def main() -> None:
    token = TELEGRAM_BOT_TOKEN
    if not token:
        raise RuntimeError("请在环境变量 TELEGRAM_BOT_TOKEN 中提供机器人 Token。")

    # Initialize DB and migrate from JSON once
    init_db()
    migrate_from_json_if_needed()

    app = (
        ApplicationBuilder()
        .token(token)
        .concurrent_updates(True)
        .build()
    )

    app.add_handler(CommandHandler("start", cmd_start))
    app.add_handler(CommandHandler("help", cmd_help))
    app.add_handler(CommandHandler("add_keyword", cmd_add_keyword))
    app.add_handler(CommandHandler("remove_keyword", cmd_remove_keyword))
    app.add_handler(CommandHandler("list_keywords", cmd_list_keywords))
    app.add_handler(CommandHandler("add_regex", cmd_add_regex))
    app.add_handler(CommandHandler("remove_regex", cmd_remove_regex))
    app.add_handler(CommandHandler("list_regex", cmd_list_regex))
    app.add_handler(CommandHandler("set_action", cmd_set_action))
    app.add_handler(CommandHandler("set_mute_seconds", cmd_set_mute_seconds))
    app.add_handler(CommandHandler("set_newcomer_buffer", cmd_set_newcomer_buffer))
    app.add_handler(CommandHandler("set_captcha", cmd_set_captcha))
    app.add_handler(CommandHandler("set_first_message_strict", cmd_set_first_message_strict))
    app.add_handler(CommandHandler("update", cmd_update))

    app.add_handler(MessageHandler(filters.TEXT | filters.CAPTION, on_text_or_caption))
    app.add_handler(MessageHandler(filters.PHOTO, on_photo))
    app.add_handler(CallbackQueryHandler(on_admin_action, pattern=r"^a\|"))
    app.add_handler(CallbackQueryHandler(on_captcha_click, pattern=r"^c\|"))
    app.add_handler(ChatMemberHandler(on_chat_member, ChatMemberHandler.CHAT_MEMBER))

    logger.info("机器人已启动。按 Ctrl+C 结束。")
    await app.run_polling(close_loop=False)


if __name__ == "__main__":
    asyncio.run(main())