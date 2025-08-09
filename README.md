## 电报广告管理机器人（OCR + 关键词/正则）

**版本（提交哈希）**: <!--VERSION_START-->2025-08-09+d0567e0<!--VERSION_END-->

功能：
- 文本与图片（OCR）双通道检测；视频首帧 OCR + pHash 去重
- AI 识别（OpenRouter）：文本本地未命中时走 AI；图片/视频可切换“AI 独占”跳过本地
- 按群独立规则：关键词、正则、动作、禁言时长
- 动作组合：delete / notify / delete_and_notify / mute / mute_and_notify / delete_and_mute / delete_and_mute_and_notify（默认）
- 管理通知内联按钮：一键 删除 / 禁言10m/1h/1d / 解除禁言 / 踢出 / 封禁
- 新人治理：
  - 新人缓冲（加入后 N 秒内禁言或限制发图/链接）
  - 入群验证码（按钮/算术，超时自动踢）
  - 首条消息加严（命中直接删+禁言+通知）

### 快速开始（Ubuntu 示例，推荐一键脚本）
```bash
# 基本：只需提供 Bot Token
bash scripts/setup.sh -t <YOUR_BOT_TOKEN>

# 进阶：含全局管理员、通知群组、OCR语言、默认动作为删+禁言+通知，并自动启动
bash scripts/setup.sh \
  -t 123456:ABC-DEF \
  -a 111111,222222 \
  -l -1001234567890 \
  -o chi_sim+eng \
  -d delete_and_mute_and_notify \
  -r
```

启用 AI（OpenRouter）
```bash
# 开启 OpenRouter + 设置 Key/模型 + 图片/视频走 AI 独占 + 阈值0.7
bash scripts/setup.sh \
  -M openrouter -K sk-... -m gpt-4o-mini -E on -T 0.7
```

### 拉库一键部署（Ubuntu）
```bash
# 全交互式（默认克隆到 /opt/telegram-ad-guard-bot）
sudo bash -lc "curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/install_from_repo.sh | sudo bash"

# 交互 + 注册服务 + 自动运行
yes | sudo bash -lc "curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/install_from_repo.sh | sudo bash -s -- -R -s"

# 非交互（环境变量）+ 注册服务 + 自动运行 + 启用 AI 独占
TELEGRAM_BOT_TOKEN=<YOUR_BOT_TOKEN> ADMIN_IDS=<111,222> AI_MODE=openrouter OPENROUTER_API_KEY=<sk-...> OPENROUTER_MODEL=gpt-4o-mini AI_EXCLUSIVE=on \
  sudo bash -lc "curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/install_from_repo.sh | sudo bash -s -- -R -s"
```

### 运行（手动方式）
```bash
python -m app.bot
```
将机器人拉进群并赋予删除/禁言权限。

### 管理命令（按群生效）
- 关键词/正则：
  - `/add_keyword 词语`、`/remove_keyword 词语`、`/list_keywords`
  - `/add_regex 正则`、`/remove_regex 正则`、`/list_regex`
- 动作与禁言：
  - `/set_action delete|notify|delete_and_notify|mute|mute_and_notify|delete_and_mute|delete_and_mute_and_notify`
  - `/set_mute_seconds 3600`
- 新人治理：
  - `/set_newcomer_buffer <秒> <none|mute|restrict_media|restrict_links>`
  - `/set_captcha <on|off> [timeout_seconds>=10]`
  - `/set_first_message_strict <on|off>`
- AI 识别：
  - `/set_ai off|openrouter`、`/set_ai_model gpt-4o-mini`、`/set_ai_key <API_KEY> [API_BASE]`
  - `/set_ai_exclusive on|off`（图片/视频只走 AI，文本仍本地命中优先、未命中再 AI）
  - `/ai_stats`（模式、模型、调用统计、阈值）
- 缓存与限流：
  - `/cache_stats`（OCR 持久化缓存条数、并发上限）
  - `/cache_clear`（清空 OCR 持久化缓存）
  - `/set_ocr_limit <n>`（设置 OCR 并发上限）
- 更新与版本：
  - `/update`（仅全局管理员）
  - `/version`（显示当前提交哈希）
- 帮助：`/help`

内联按钮（在管理员通知内）：删除、禁言10m/1h/1d、解除禁言、踢出、封禁。

### 截图
- 触发通知（占位）：`docs/images/notify-example.png`
- OCR 命中（占位）：`docs/images/ocr-hit-example.png`

### 文档
- 使用说明：`docs/USAGE.zh-CN.md`
- 搭建教程：`docs/SETUP.zh-CN.md`

说明：
- 默认 OCR 语言为 `chi_sim+eng`，可在 `.env` 的 `OCR_LANGUAGES` 调整。
- `ADMIN_IDS` 留空则默认所有人可用管理命令（便于初次设置），建议设置后再使用。
- 删除/禁言失败多半为权限不足，请确保机器人在群里有相应管理员权限。
