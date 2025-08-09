## 电报广告管理机器人（OCR + 关键词/正则）

**版本（提交哈希）**: <!--VERSION_START-->2025-08-09+a3085c8<!--VERSION_END-->

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

### 一键安装（推荐，curl | bash）
```bash
# 交互式（会询问 Token/管理员等）
sudo bash -lc "curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/quick_setup.sh | sudo bash"

# 非交互 + 注册服务 + 自动运行（将 <TOKEN> 替换为你的 Bot Token）
TELEGRAM_BOT_TOKEN=<TOKEN> ADMIN_IDS=111,222 \
  sudo bash -lc "curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/quick_setup.sh | sudo bash -s -- -y -s -R"
```

### 推荐一键部署（新脚本 deploy.sh）
```bash
# 最简（提供 Token，后台运行）
sudo scripts/deploy.sh -t <YOUR_BOT_TOKEN> -R -y

# 服务化 + 定时自更新（每小时）
sudo scripts/deploy.sh -t <YOUR_BOT_TOKEN> -A 111,222 -s -U -I 1h -R -y

# 启用 OpenRouter AI（独占）
sudo scripts/deploy.sh -t <YOUR_BOT_TOKEN> -M openrouter -K <sk-...> -m gpt-4o-mini -E on -T 0.7 -s -R -y
```

如需“拉库即装”方式，可继续使用旧脚本（已兼容自动修复）：
```bash
# 交互式（默认克隆到 /opt/telegram-ad-guard-bot）
sudo bash -lc "curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/install_from_repo.sh | sudo bash -s -- -F"

# 非交互 + 注册服务 + 自动运行 + 启用 AI 独占
TELEGRAM_BOT_TOKEN=<YOUR_BOT_TOKEN> ADMIN_IDS=<111,222> AI_MODE=openrouter OPENROUTER_API_KEY=<sk-...> OPENROUTER_MODEL=gpt-4o-mini AI_EXCLUSIVE=on \
  sudo bash -lc "curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/install_from_repo.sh | sudo bash -s -- -R -s -Y -F"
```

### 安装后自检与回滚
- 默认开启自检：检查 `.venv/bin/python`、`.env` 里 `TELEGRAM_BOT_TOKEN`、编译与导入 `app.bot`
- 自检失败：
  - 若目标目录存在旧版本，自动回滚至安装前 commit，并尝试重装依赖与重启服务
  - 若为全新安装，自动清理 `DEST_DIR`
- 可选参数：
  - `-C` 关闭自检
  - `-N` 关闭失败回滚
- 运行逻辑：通过自检后，`-s` 注册服务，否则 `-R` 后台运行输出 `bot.log`

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

### 疑难排查
- 日志查看：
  - 使用 systemd：`systemctl status telegram-ad-guard-bot`，`journalctl -u telegram-ad-guard-bot -n 200 --no-pager`
  - 未使用 systemd：查看部署目录下 `bot.log`
- 自检失败：
  - 可临时使用 `-C` 关闭自检、`-N` 关闭回滚定位问题
  - 检查 `.env` 的 `TELEGRAM_BOT_TOKEN` 是否正确
  - 手动运行：`source .venv/bin/activate && python -m app.bot`
- 诊断收集：
  - 打包收集：`bash scripts/collect_diagnostics.sh -n telegram-ad-guard-bot -p /opt/telegram-ad-guard-bot`
  - 文本模式：`bash scripts/collect_diagnostics.sh -T -o ./diag.txt`
- OCR/视频：确认已安装 `tesseract-ocr`（含中文语言包）与 `ffmpeg`
- AI：若启用 OpenRouter，检查 `OPENROUTER_API_KEY`、`AI_MODE=openrouter` 与网络连通性
- 权限：确保机器人在群内具备删除与限制成员权限
