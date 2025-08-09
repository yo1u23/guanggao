import asyncio
import logging
import re
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import List, Optional, Tuple

from telegram import Update, Message, ChatPermissions
from telegram.constants import ParseMode
from telegram.ext import (
    ApplicationBuilder,
    CommandHandler,
    ContextTypes,
    MessageHandler,
    filters,
)

from .config import TELEGRAM_BOT_TOKEN, ADMIN_IDS, OCR_LANGUAGES, ADMIN_LOG_CHAT_IDS, ALLOWED_ACTIONS
from .ocr import extract_text_from_image, OCRError
from .storage import (
    load_rules,
    add_keyword,
    remove_keyword,
    add_regex,
    remove_regex,
    set_action,
    set_mute_seconds,
)

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


# --- Detection helpers ---

def _gather_message_text(message: Message) -> str:
    parts: List[str] = []
    if message.text:
        parts.append(message.text)
    if message.caption:
        parts.append(message.caption)
    return "\n".join(parts).strip()


def _match_rules(text: str, chat_id: Optional[int]) -> Tuple[bool, List[str], List[str]]:
    text_lower = text.lower()
    rules = load_rules(chat_id)
    hit_keywords: List[str] = []
    hit_regexes: List[str] = []
    for k in rules.keywords:
        if not k:
            continue
        if k.lower() in text_lower:
            hit_keywords.append(k)
    for p in rules.regexes:
        try:
            if re.search(p, text, flags=re.IGNORECASE):
                hit_regexes.append(p)
        except re.error:
            continue
    return (bool(hit_keywords or hit_regexes), hit_keywords, hit_regexes)


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
    for target in targets:
        try:
            await context.bot.send_message(chat_id=target, text=body, parse_mode=ParseMode.HTML, disable_web_page_preview=True)
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


async def on_text_or_caption(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    message = update.effective_message
    chat_id = update.effective_chat.id if update.effective_chat else None
    text = _gather_message_text(message)
    if not text:
        return
    matched, hit_keywords, hit_regexes = _match_rules(text, chat_id)
    if matched:
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
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir) / f"photo_{file.file_unique_id}.jpg"
            await file.download_to_drive(custom_path=str(tmp_path))
            try:
                ocr_text = extract_text_from_image(tmp_path, OCR_LANGUAGES)
                if ocr_text:
                    text_parts.append(ocr_text)
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


async def main() -> None:
    token = TELEGRAM_BOT_TOKEN
    if not token:
        raise RuntimeError("请在环境变量 TELEGRAM_BOT_TOKEN 中提供机器人 Token。")

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

    app.add_handler(MessageHandler(filters.TEXT | filters.CAPTION, on_text_or_caption))
    app.add_handler(MessageHandler(filters.PHOTO, on_photo))

    logger.info("机器人已启动。按 Ctrl+C 结束。")
    await app.run_polling(close_loop=False)


if __name__ == "__main__":
    asyncio.run(main())