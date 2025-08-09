import asyncio
import logging
import os
import re
import tempfile
from dataclasses import dataclass
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

from .config import TELEGRAM_BOT_TOKEN, ADMIN_IDS, OCR_LANGUAGES, ADMIN_LOG_CHAT_IDS
from .ocr import extract_text_from_image, OCRError
from .storage import (
    load_rules,
    add_keyword,
    remove_keyword,
    add_regex,
    remove_regex,
    set_action,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
)
logger = logging.getLogger("ad_guard_bot")


def ensure_admin(user_id: int) -> bool:
    return user_id in ADMIN_IDS if ADMIN_IDS else True


async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(
        "你好！我是广告管理机器人。\n"
        "- 识别文本与图片中的关键词/正则\n"
        "- 管理命令使用 /help 查看",
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
        "/set_action [delete|notify|delete_and_notify] — 设置命中处理动作\n"
        "\n普通使用：直接把我拉进群并给管理员权限。"
    )
    await update.message.reply_text(help_text)


async def cmd_add_keyword(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    if not ensure_admin(user_id):
        await update.message.reply_text("无权限。")
        return
    if not context.args:
        await update.message.reply_text("请提供关键词，例如：/add_keyword 低价代充")
        return
    keyword = " ".join(context.args)
    rules = add_keyword(keyword)
    await update.message.reply_text(f"已添加关键词：{keyword}\n当前共 {len(rules.keywords)} 个关键词。")


async def cmd_remove_keyword(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    if not ensure_admin(user_id):
        await update.message.reply_text("无权限。")
        return
    if not context.args:
        await update.message.reply_text("请提供要删除的关键词。")
        return
    keyword = " ".join(context.args)
    rules = remove_keyword(keyword)
    await update.message.reply_text(f"已删除关键词：{keyword}\n当前共 {len(rules.keywords)} 个关键词。")


async def cmd_list_keywords(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    rules = load_rules()
    if not rules.keywords:
        await update.message.reply_text("暂无关键词。")
        return
    await update.message.reply_text("关键词列表：\n" + "\n".join(f"- {k}" for k in rules.keywords))


async def cmd_add_regex(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    if not ensure_admin(user_id):
        await update.message.reply_text("无权限。")
        return
    if not context.args:
        await update.message.reply_text("请提供正则表达式，例如：/add_regex (?i)\b代\s*充\b")
        return
    pattern = " ".join(context.args)
    # simple compile check
    try:
        re.compile(pattern)
    except re.error as exc:
        await update.message.reply_text(f"正则无效：{exc}")
        return
    rules = add_regex(pattern)
    await update.message.reply_text(f"已添加正则：{pattern}\n当前共 {len(rules.regexes)} 个正则。")


async def cmd_remove_regex(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    if not ensure_admin(user_id):
        await update.message.reply_text("无权限。")
        return
    if not context.args:
        await update.message.reply_text("请提供要删除的正则表达式。")
        return
    pattern = " ".join(context.args)
    rules = remove_regex(pattern)
    await update.message.reply_text(f"已删除正则：{pattern}\n当前共 {len(rules.regexes)} 个正则。")


async def cmd_list_regex(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    rules = load_rules()
    if not rules.regexes:
        await update.message.reply_text("暂无正则。")
        return
    await update.message.reply_text("正则列表：\n" + "\n".join(f"- {p}" for p in rules.regexes))


async def cmd_set_action(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    if not ensure_admin(user_id):
        await update.message.reply_text("无权限。")
        return
    if not context.args:
        await update.message.reply_text("请提供动作：delete | notify | delete_and_notify")
        return
    action = context.args[0].strip()
    try:
        rules = set_action(action)
        await update.message.reply_text(f"已设置动作：{rules.action}")
    except ValueError:
        await update.message.reply_text("无效动作：请用 delete / notify / delete_and_notify")


# --- Detection helpers ---

def _gather_message_text(message: Message) -> str:
    parts: List[str] = []
    if message.text:
        parts.append(message.text)
    if message.caption:
        parts.append(message.caption)
    return "\n".join(parts).strip()


def _match_rules(text: str) -> Tuple[bool, List[str], List[str]]:
    text_lower = text.lower()
    rules = load_rules()
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


async def _handle_action(update: Update, context: ContextTypes.DEFAULT_TYPE, matched_text: str, hit_keywords: List[str], hit_regexes: List[str]) -> None:
    rules = load_rules()
    action = rules.action
    message = update.effective_message

    if action in {"delete", "delete_and_notify"}:
        try:
            await message.delete()
        except Exception as exc:
            logger.warning("删除消息失败，可能缺少权限: %s", exc)

    if action in {"notify", "delete_and_notify"}:
        await _notify_admins(context, message, matched_text, hit_keywords, hit_regexes)


async def on_text_or_caption(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    message = update.effective_message
    text = _gather_message_text(message)
    if not text:
        return
    matched, hit_keywords, hit_regexes = _match_rules(text)
    if matched:
        await _handle_action(update, context, text, hit_keywords, hit_regexes)


async def on_photo(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    message = update.effective_message
    text_parts: List[str] = []
    if message.caption:
        text_parts.append(message.caption)

    # Download the highest resolution photo
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

    matched, hit_keywords, hit_regexes = _match_rules(combined_text)
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

    # Commands
    app.add_handler(CommandHandler("start", cmd_start))
    app.add_handler(CommandHandler("help", cmd_help))
    app.add_handler(CommandHandler("add_keyword", cmd_add_keyword))
    app.add_handler(CommandHandler("remove_keyword", cmd_remove_keyword))
    app.add_handler(CommandHandler("list_keywords", cmd_list_keywords))
    app.add_handler(CommandHandler("add_regex", cmd_add_regex))
    app.add_handler(CommandHandler("remove_regex", cmd_remove_regex))
    app.add_handler(CommandHandler("list_regex", cmd_list_regex))
    app.add_handler(CommandHandler("set_action", cmd_set_action))

    # Messages
    app.add_handler(MessageHandler(filters.TEXT | filters.CAPTION, on_text_or_caption))
    app.add_handler(MessageHandler(filters.PHOTO, on_photo))

    logger.info("机器人已启动。按 Ctrl+C 结束。")
    await app.run_polling(close_loop=False)


if __name__ == "__main__":
    asyncio.run(main())