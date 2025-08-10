# 安装脚本说明

本目录包含了 Telegram 广告管理机器人的各种安装和管理脚本。

## 📁 脚本文件

### 🚀 主要安装脚本

| 脚本名称 | 用途 | 推荐用户 |
|----------|------|----------|
| `oneclick_install.sh` | 一键安装脚本 | 新手用户 |
| `install.sh` | 高级安装脚本 | 高级用户 |
| `demo_install.sh` | 安装演示脚本 | 所有用户 |

### 🧪 测试和验证脚本

| 脚本名称 | 用途 | 使用场景 |
|----------|------|----------|
| `test_install.sh` | 安装验证测试 | 安装后验证 |
| `quick_setup.sh` | 快速设置脚本 | 开发环境 |

## 🎯 快速开始

### 1. 一键安装（推荐新手）

```bash
# 直接运行（需要 sudo 权限）
curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/oneclick_install.sh | sudo bash
```

**特点：**
- 🎨 彩色界面和友好提示
- 🔧 自动检测系统环境
- 📦 自动安装所有依赖
- 🚀 自动配置和启动服务

### 2. 高级安装（推荐高级用户）

```bash
# 下载脚本
wget https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/install.sh
chmod +x install.sh

# 交互式安装
sudo ./install.sh

# 非交互式安装
TELEGRAM_BOT_TOKEN=your_token ADMIN_IDS=123,456 sudo ./install.sh -y -s
```

**特点：**
- ⚙️ 支持命令行参数
- 🔧 可自定义安装目录
- 📝 详细的日志记录
- 🧪 安装后测试验证

### 3. 安装演示（了解流程）

```bash
# 运行演示脚本
bash scripts/demo_install.sh
```

**特点：**
- 📋 展示完整安装流程
- ⚙️ 说明配置参数
- 🧪 介绍测试方法
- 💡 提供使用建议

## 🔧 安装后管理

### 验证安装

```bash
# 运行测试脚本
bash scripts/test_install.sh

# 或指定安装目录
bash scripts/test_install.sh /opt/telegram-ad-guard-bot
```

### 服务管理

```bash
# 查看服务状态
sudo systemctl status telegram-ad-guard-bot

# 启动服务
sudo systemctl start telegram-ad-guard-bot

# 停止服务
sudo systemctl stop telegram-ad-guard-bot

# 重启服务
sudo systemctl restart telegram-ad-guard-bot

# 查看日志
sudo journalctl -u telegram-ad-guard-bot -f
```

## 📋 安装前准备

### 必需信息

1. **Telegram Bot Token**
   - 从 [@BotFather](https://t.me/BotFather) 获取
   - 格式：`123456789:ABCdefGHIjklMNOpqrsTUVwxyz`

2. **管理员用户ID**
   - 从 [@userinfobot](https://t.me/userinfobot) 获取
   - 纯数字格式

### 系统要求

- **操作系统**: Linux (Ubuntu, CentOS, Debian, Arch Linux 等)
- **Python**: 3.8 或更高版本
- **内存**: 至少 512MB
- **磁盘空间**: 至少 2GB
- **网络**: 可访问 GitHub

## 🚨 故障排除

### 常见问题

1. **权限不足**
   ```bash
   sudo chown -R $USER:$USER /opt/telegram-ad-guard-bot
   ```

2. **Python 模块导入失败**
   ```bash
   cd /opt/telegram-ad-guard-bot
   source .venv/bin/activate
   pip install -r requirements.txt
   ```

3. **服务启动失败**
   ```bash
   sudo journalctl -u telegram-ad-guard-bot -n 50
   ```

### 重新安装

```bash
# 停止服务
sudo systemctl stop telegram-ad-guard-bot
sudo systemctl disable telegram-ad-guard-bot

# 删除服务文件
sudo rm /etc/systemd/system/telegram-ad-guard-bot.service
sudo systemctl daemon-reload

# 删除安装目录
sudo rm -rf /opt/telegram-ad-guard-bot

# 重新运行安装脚本
curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/oneclick_install.sh | sudo bash
```

## 📚 更多信息

- **项目主页**: https://github.com/yo1u23/guanggao
- **使用说明**: [docs/USAGE.zh-CN.md](../docs/USAGE.zh-CN.md)
- **搭建教程**: [docs/SETUP.zh-CN.md](../docs/SETUP.zh-CN.md)

## 🤝 贡献

如果您发现脚本中的问题或有改进建议，欢迎提交 Issue 或 Pull Request。

---

**注意**: 安装脚本需要 sudo 权限来安装系统依赖和配置服务。请确保您了解脚本的执行内容。