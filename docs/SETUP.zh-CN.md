# 搭建教程（Telegram 广告管理机器人）

## 前置条件
- Linux/Unix 环境（Windows 也可，但命令略有差异）
- Python 3.10+（项目当前运行于 Python 3.13）
- 可访问 Telegram API 的网络环境

## 系统依赖安装（以 Ubuntu 为例，OCR 必需）
建议 Ubuntu/Debian 系列执行：
```bash
bash scripts/install_tesseract_ocr.sh
```
若脚本不适用你的系统，请手动安装：
```bash
sudo apt-get update -y
sudo apt-get install -y tesseract-ocr tesseract-ocr-chi-sim tesseract-ocr-chi-tra ffmpeg
```

## Python 依赖
推荐使用虚拟环境：
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## 环境变量配置
复制模板并按需填写：
```bash
cp .env.example .env
```
- `TELEGRAM_BOT_TOKEN`：从 `@BotFather` 获取
- `ADMIN_IDS`：全局管理员用户 ID（可选，逗号分隔）
- `ADMIN_LOG_CHAT_IDS`：通知发送到的 Chat ID（可选，逗号分隔）
- `OCR_LANGUAGES`：Tesseract 语言（默认 `chi_sim+eng`）
- `DEFAULT_ACTION`：默认动作（建议 `delete_and_mute_and_notify`）
- AI（可选，OpenRouter）：`AI_MODE=openrouter`、`OPENROUTER_API_KEY`、`OPENROUTER_MODEL`

## 一键搭建脚本
推荐使用一键脚本完成安装、配置与运行：
```bash
# 基本（仅配置 Token）
./scripts/setup.sh -t <YOUR_BOT_TOKEN>

# 完整示例（含全局管理员、通知群组、OCR语言、默认动作，并自动运行）
./scripts/setup.sh \
  -t 123456:ABC-DEF \
  -a 111111,222222 \
  -l -1001234567890 \
  -o chi_sim+eng \
  -d delete_and_mute_and_notify \
  -r

# 启用 AI（OpenRouter）并设置独占模式与阈值
./scripts/setup.sh \
  -M openrouter -K sk-... -m gpt-4o-mini -E on -T 0.7
```
脚本支持参数：
- `-t`: 机器人 Token（必需）
- `-a`: 全局管理员用户ID，逗号分隔（可选）
- `-l`: 管理通知发送到的 Chat ID（可选）
- `-o`: OCR 语言（可选，默认 `chi_sim+eng`）
- `-d`: 默认动作（可选，默认 `delete_and_mute_and_notify`）
- `-r`: 搭建完成后立即运行机器人
- `-M/-K/-m/-E/-T`: AI 模式、Key、模型、独占、阈值（OpenRouter）

## 启动机器人
```bash
source .venv/bin/activate
python -m app.bot
```
将机器人拉入目标群，并授予管理员权限：
- 删除消息
- 禁言成员（限制成员）

## 基本验证
在群里执行：
- 添加关键词：`/add_keyword 低价代充`
- 发送文本或包含该词的图片，观察是否按设定动作触发

## 拉库一键部署
用于全新环境一键克隆仓库、搭建并可选注册为 systemd 服务：
```bash
# 交互式：
sudo bash -lc "curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/install_from_repo.sh | sudo bash"

# 交互 + 注册服务 + 自动运行
yes | sudo bash -lc "curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/install_from_repo.sh | sudo bash -s -- -R -s"

# 非交互（通过环境变量传递）+ 注册服务 + 自动运行 + 启用 AI 独占
TELEGRAM_BOT_TOKEN=<YOUR_BOT_TOKEN> ADMIN_IDS=<111,222> AI_MODE=openrouter OPENROUTER_API_KEY=<sk-...> OPENROUTER_MODEL=gpt-4o-mini AI_EXCLUSIVE=on \
  sudo bash -lc "curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/install_from_repo.sh | sudo bash -s -- -R -s"
```
- `-U` 启用自更新定时器，`-I` 指定间隔（如 15m/1h/6h/1d）。
- 自更新执行 `scripts/self_update.sh`，拉取最新代码、必要时重装依赖，并尝试重启服务。
- 查看定时器：`systemctl list-timers | grep telegram-ad-guard-bot-update`

## 安装后自检与回滚
- 默认开启自检：
  - 检查虚拟环境 Python 是否存在（`.venv/bin/python`）
  - `.env` 文件包含 `TELEGRAM_BOT_TOKEN`
  - 编译 `app` 目录与导入 `app.bot` 成功
  - 如缺失 `tesseract` 或 `ffmpeg`，将给出提示（不阻塞安装）
- 自检失败行为：
  - 目标目录原本存在：回滚到安装前的 commit，尝试重装依赖并重启服务
  - 全新安装：清理 `DEST_DIR`
- 可选参数：
  - `-C` 关闭自检（不建议）
  - `-N` 关闭失败回滚（用于排查问题时保留现场）
- 运行逻辑：
  - 不在 `setup.sh` 阶段直接运行；自检通过后
    - 指定 `-s` 则注册并启动 systemd 服务
    - 未指定 `-s` 但提供 `-R` 时后台运行，日志写入 `DEST_DIR/bot.log`

## 部署建议
- 使用 `systemd` 或 `pm2` 守护进程运行，崩溃自动重启
- 记录日志（可以使用 shell 重定向或日志系统）
- Docker 部署时确保镜像内安装 Tesseract 及语言包

## 升级与迁移
- 升级代码后，建议重新 `pip install -r requirements.txt`
- 数据使用 SQLite：`app/data/ad_guard.db`
- 更改配置后重启机器人生效