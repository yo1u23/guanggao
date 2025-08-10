# Telegram 广告管理机器人 - 安装脚本

本目录包含了多种安装脚本，满足不同的安装需求。

## 🚀 推荐安装方式

### 1. 一键安装脚本 (推荐)

最简单的一键安装方式，支持交互式配置：

```bash
# 通过 curl 直接运行
curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/oneclick_install.sh | sudo bash

# 或者下载后运行
wget https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/oneclick_install.sh
chmod +x oneclick_install.sh
sudo ./oneclick_install.sh
```

**特点：**
- 🎨 美观的彩色界面
- 🔧 自动检测系统环境
- 📦 自动安装系统依赖
- 🐍 自动配置 Python 环境
- 🚀 自动注册系统服务
- 📝 详细的安装日志

### 2. 高级安装脚本

功能更全面的安装脚本，支持更多选项：

```bash
# 交互式安装
sudo bash scripts/install.sh

# 非交互式安装
sudo bash scripts/install.sh -t YOUR_BOT_TOKEN -a 123,456 -s -r

# 查看帮助
bash scripts/install.sh -h
```

**选项说明：**
- `-t TOKEN`: Telegram Bot Token (必需)
- `-a IDS`: 管理员用户ID，逗号分隔
- `-d DIR`: 安装目录
- `-s`: 安装为系统服务
- `-r`: 安装后立即运行
- `-y`: 非交互模式
- `-c`: 跳过系统检查

## 📋 系统要求

- **操作系统**: Linux (Ubuntu/Debian/CentOS/RHEL/Fedora/Arch Linux)
- **Python**: 3.8 或更高版本
- **内存**: 至少 512MB
- **磁盘空间**: 至少 2GB
- **网络**: 可访问 GitHub

## 🔧 安装前准备

1. **获取 Bot Token**
   - 在 Telegram 中搜索 @BotFather
   - 发送 `/newbot` 创建新机器人
   - 保存获得的 Token

2. **获取用户ID**
   - 在 Telegram 中搜索 @userinfobot
   - 发送任意消息获取您的用户ID

3. **确保系统权限**
   - 使用 `sudo` 运行安装脚本
   - 确保有足够的磁盘空间

## 📦 自动安装的依赖

### 系统依赖
- `git`: 代码版本控制
- `python3`: Python 解释器
- `python3-pip`: Python 包管理器
- `python3-venv`: Python 虚拟环境
- `tesseract-ocr`: OCR 文字识别
- `ffmpeg`: 音视频处理
- 编译工具和开发库

### Python 依赖
- `python-telegram-bot`: Telegram Bot API
- `pytesseract`: OCR 接口
- `Pillow`: 图像处理
- `python-dotenv`: 环境变量管理
- `imagehash`: 图像哈希
- `numpy`: 数值计算

## 🚀 安装后配置

### 1. 机器人权限设置
将机器人添加到群组后，需要赋予以下权限：
- ✅ 删除消息
- ✅ 限制成员
- ✅ 封禁用户
- ✅ 管理语音聊天

### 2. 基本命令配置
```
/add_keyword 广告
/add_regex 推广.*链接
/set_action delete_and_mute_and_notify
/set_mute_seconds 3600
```

### 3. 新人治理设置
```
/set_newcomer_buffer 300 mute
/set_captcha on 60
/set_first_message_strict on
```

## 📊 服务管理

### 查看服务状态
```bash
sudo systemctl status telegram-ad-guard-bot
```

### 查看实时日志
```bash
sudo journalctl -u telegram-ad-guard-bot -f
```

### 重启服务
```bash
sudo systemctl restart telegram-ad-guard-bot
```

### 停止服务
```bash
sudo systemctl stop telegram-ad-guard-bot
```

## 🔍 故障排除

### 常见问题

1. **Python 版本过低**
   ```bash
   # Ubuntu/Debian
   sudo apt-get install python3.8 python3.8-venv
   
   # CentOS/RHEL
   sudo yum install python38 python38-pip
   ```

2. **OCR 识别失败**
   ```bash
   # 检查 tesseract 安装
   tesseract --version
   
   # 检查语言包
   tesseract --list-langs
   ```

3. **权限不足**
   ```bash
   # 检查机器人权限
   # 确保机器人在群组中有管理员权限
   ```

4. **网络连接问题**
   ```bash
   # 测试网络连接
   ping github.com
   curl -I https://api.telegram.org
   ```

### 日志查看

- **安装日志**: `/tmp/telegram-bot-install.log`
- **服务日志**: `sudo journalctl -u telegram-ad-guard-bot`
- **应用日志**: `/opt/telegram-ad-guard-bot/bot.log`

## 🔄 更新机器人

### 自动更新
```bash
# 进入安装目录
cd /opt/telegram-ad-guard-bot

# 拉取最新代码
git pull origin main

# 重启服务
sudo systemctl restart telegram-ad-guard-bot
```

### 手动更新
```bash
# 停止服务
sudo systemctl stop telegram-ad-guard-bot

# 备份配置
cp .env .env.backup

# 拉取代码
git pull origin main

# 更新依赖
source .venv/bin/activate
pip install -r requirements.txt

# 启动服务
sudo systemctl start telegram-ad-guard-bot
```

## 📞 技术支持

如果遇到问题，请：

1. 查看安装日志和错误日志
2. 检查系统要求和依赖
3. 确认机器人权限设置
4. 查看 GitHub Issues

## 📄 许可证

本项目采用 MIT 许可证，详见 [LICENSE](../LICENSE) 文件。

---

**注意**: 安装脚本会自动检测系统环境并安装相应依赖，建议在干净的系统中运行以获得最佳体验。