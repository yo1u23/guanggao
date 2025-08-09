# 使用说明（Telegram 广告管理机器人）

## 功能概览
- 文本与图片广告检测：
  - 文本消息、图片说明（caption）均会匹配关键词与正则
  - 图片内容通过 OCR（默认中文简体+英文 chi_sim+eng）识别后匹配
- 处理动作可配置（按群生效）：
  - delete：删除命中消息
  - notify：仅通知管理员
  - delete_and_notify：删除并通知
  - mute：禁言发送者（按设置时长）
  - mute_and_notify：禁言并通知
  - delete_and_mute：删除并禁言
  - delete_and_mute_and_notify（默认）：删除并禁言并通知
- 群级规则独立：同一机器人在不同群组可使用不同关键词、正则、动作与禁言时长
- 管理权限：群管理员或 `.env` 中配置的全局管理员可使用管理命令

## 机器人所需权限
- 删除消息权限（执行 delete 类动作）
- 限制成员权限（执行 mute 类动作）

## 管理命令（群内执行，按群生效）
- 关键词
  - `/add_keyword 词语`：添加关键词
  - `/remove_keyword 词语`：删除关键词
  - `/list_keywords`：查看本群关键词列表
- 正则表达式
  - `/add_regex 正则`：添加正则（示例：`/add_regex (?i)\b代\s*充\b`）
  - `/remove_regex 正则`：删除正则
  - `/list_regex`：查看本群正则列表
- 动作与禁言
  - `/set_action delete|notify|delete_and_notify|mute|mute_and_notify|delete_and_mute|delete_and_mute_and_notify`
  - `/set_mute_seconds 秒数`：设置禁言时长（秒），`0` 表示不禁言
- 新人治理
  - `/set_newcomer_buffer <秒> <none|mute|restrict_media|restrict_links>`
  - `/set_captcha <on|off> [timeout_seconds>=10]`
  - `/set_first_message_strict <on|off>`
- AI 与缓存/限流
  - `/set_ai off|openrouter`、`/set_ai_model <model>`、`/set_ai_key <API_KEY> [API_BASE]`
  - `/set_ai_exclusive on|off`（图片/视频只走 AI，文本本地优先、未命中再 AI）
  - `/ai_stats`（模式、模型、调用统计与阈值）
  - `/cache_stats`（OCR 持久化缓存条数、并发上限）
  - `/cache_clear`（清空持久化缓存）
  - `/set_ocr_limit <n>`（设置 OCR 并发上限）
- 更新与版本
  - `/update`（仅全局管理员）
  - `/version`（显示当前提交哈希）
- 帮助
  - `/help`：显示命令帮助

## 规则命中逻辑
1. 聚合消息文本：消息正文 + 图片说明
2. 图片 OCR：下载分辨率最高的图片，使用 Tesseract 识别为文本
3. 关键词匹配：大小写不敏感地判定是否包含任一关键词
4. 正则匹配：对文本执行 `re.search(pattern, text, flags=re.IGNORECASE)`，任一命中即触发
5. AI 回退（文本）：若本地未命中且启用 AI，则调用 OpenRouter 文本分类判断
6. 触发处理动作：根据当前群组设置的动作执行删除、禁言、通知等

## AI 独占模式与回退逻辑
- 文本：默认“本地规则优先，未命中再 AI”。文本不受独占模式影响（保持低成本）。
- 图片/视频：
  - 独占模式关闭（默认）：优先本地 OCR（含缓存与 pHash 去重），未命中可选再走 AI。
  - 独占模式开启：直接送 AI 进行多模态识别，跳过本地 OCR 与规则匹配。
- 阈值：可在内部设置（`ai_provider.py`）配置，影响 AI 判定为广告的敏感度。

## 内联按钮权限与用法
- 触发通知时，管理员通知消息会附带按钮：删除、禁言（10m/1h/1d）、解除禁言、踢出、封禁。
- 按钮权限：仅群管理员或全局管理员可操作；权限不足会提示“无权限”。
- 操作后：按钮会被禁用并在消息末尾标注“（已处理：<动作>）”。

## 通知对象
- 通知默认发送给 `.env` 中的 `ADMIN_LOG_CHAT_IDS`（若配置多个则全部发送）
- 如未配置通知群组，则尝试私聊通知全局管理员（`ADMIN_IDS`）

## OCR 语言与效果
- 默认 `chi_sim+eng`（中文简体+英文）。可在 `.env` 中通过 `OCR_LANGUAGES` 自定义
- OCR 质量与图片清晰度、文字语言包有关。建议尽量提供清晰图片，并安装对应语言包

## 数据存储
- 使用 SQLite 持久化，数据库位于 `app/data/ad_guard.db`
- 表结构：`rules`（群规则）、`user_state`（新人/验证码状态）、`ocr_cache`（OCR 文本缓存）
- 首次运行会自动初始化并从历史 JSON（如存在）迁移至 SQLite

## 常见问题
- 无法删除/禁言：请确认机器人在该群具备对应的管理员权限
- OCR 不生效：检查服务器是否安装 tesseract 及中文语言包；容器部署需安装系统依赖
- 命令提示“无权限”：仅群管理员或全局管理员可执行管理命令