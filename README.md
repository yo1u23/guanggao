## 电报广告管理机器人（OCR + 关键词/正则）

功能：
- 文本与图片（OCR）双通道检测
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
更多脚本与“拉库一键部署”说明见 `docs/SETUP.zh-CN.md`。

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