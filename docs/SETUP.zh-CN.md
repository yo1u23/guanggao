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
sudo apt-get install -y tesseract-ocr tesseract-ocr-chi-sim tesseract-ocr-chi-tra
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
```
脚本支持参数：
- `-t`: 机器人 Token（必需）
- `-a`: 全局管理员用户ID，逗号分隔（可选）
- `-l`: 管理通知发送到的 Chat ID（可选）
- `-o`: OCR 语言（可选，默认 `chi_sim+eng`）
- `-d`: 默认动作（可选，默认 `delete_and_mute_and_notify`）
- `-r`: 搭建完成后立即运行机器人

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
# 交互式最简（默认拉取 main 分支到 /opt/telegram-ad-guard-bot）
sudo bash scripts/install_from_repo.sh

# 带参数（自动运行并注册 systemd 服务 + 启用自更新定时器每小时一次）
sudo bash scripts/install_from_repo.sh \
  -r https://github.com/yo1u23/guanggao \
  -b main \
  -d /opt/telegram-ad-guard-bot \
  -R -s -U -I 1h -n telegram-ad-guard-bot -u ubuntu \
  -t 123456:ABC-DEF -a 111111,222222 -l -1001234567890 -o chi_sim+eng -D delete_and_mute_and_notify
```
- `-U` 启用自更新定时器，`-I` 指定间隔（如 15m/1h/6h/1d）。
- 自更新执行 `scripts/self_update.sh`，拉取最新代码、必要时重装依赖，并尝试重启服务。
- 查看定时器：`systemctl list-timers | grep telegram-ad-guard-bot-update`

## 部署建议
- 使用 `systemd` 或 `pm2` 守护进程运行，崩溃自动重启
- 记录日志（可以使用 shell 重定向或日志系统）
- Docker 部署时确保镜像内安装 Tesseract 及语言包

## 升级与迁移
- 升级代码后，建议重新 `pip install -r requirements.txt`
- `app/data/` 下每个群的规则 JSON 文件可保留直接复用
- 更改配置后重启机器人生效