# 安装脚本目录

本目录包含了多种安装脚本，适用于不同的使用场景。推荐使用 `modern_install.sh`，它提供了最佳的用户体验和功能。

## 🚀 推荐脚本

### `modern_install.sh` - 现代化一键安装脚本

**最新、最完善的安装脚本**，具有以下特点：

✅ **智能系统检测** - 自动检测操作系统、包管理器、Python版本  
✅ **美观界面** - 彩色输出、进度条、清晰的状态提示  
✅ **交互式配置** - 友好的配置向导，支持AI功能设置  
✅ **健壮性强** - 完整的错误处理和自动回滚机制  
✅ **多种运行模式** - 支持systemd服务、后台进程、手动运行  
✅ **自动更新** - 可选的定时自动更新功能  
✅ **安装验证** - 自动进行安装后自检  

#### 使用方法

```bash
# 1. 交互式安装（推荐新手）
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/modern_install.sh)"

# 2. 非交互式安装
TELEGRAM_BOT_TOKEN=123:ABC ADMIN_IDS=111,222 \
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/modern_install.sh)" -- -y -s -R

# 3. 完整配置（包含AI功能）
sudo scripts/modern_install.sh -t YOUR_TOKEN -A 111,222 -M openrouter -K sk-xxx -s -U -R -y
```

#### 主要参数

| 参数 | 说明 | 示例 |
|------|------|------|
| `-t TOKEN` | Telegram Bot Token | `-t "123456:ABC"` |
| `-A IDS` | 管理员ID（逗号分隔） | `-A "111,222"` |
| `-s` | 安装为systemd服务 | |
| `-R` | 安装后立即运行 | |
| `-U` | 启用自动更新定时器 | |
| `-y` | 非交互模式 | |
| `-M MODE` | AI模式 | `-M openrouter` |
| `-K KEY` | OpenRouter API密钥 | `-K "sk-xxx"` |

---

## 🔧 其他脚本

### `quick_setup.sh` - 快速安装脚本

特点：彩色输出、系统检测、回滚机制

```bash
sudo bash -lc "curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/quick_setup.sh | sudo bash"
```

### `deploy.sh` - 部署脚本

特点：专注部署、支持更新和卸载

```bash
sudo scripts/deploy.sh -t YOUR_TOKEN -A 111,222 -s -R -y
```

### `oneclick.sh` - 简单一键安装

特点：轻量级、快速安装

```bash
sudo bash -lc "curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/oneclick.sh | sudo bash"
```

### `install_from_repo.sh` - 从仓库安装

特点：克隆仓库后安装，适合开发环境

```bash
sudo bash -lc "curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/install_from_repo.sh | sudo bash"
```

---

## 📝 脚本选择建议

| 使用场景 | 推荐脚本 | 原因 |
|----------|----------|------|
| **首次安装** | `modern_install.sh` | 最佳用户体验，智能检测和配置 |
| **生产环境** | `modern_install.sh` + `-s -U` | 服务化部署，自动更新 |
| **快速测试** | `oneclick.sh` | 最简单快速 |
| **开发环境** | `install_from_repo.sh` | 完整克隆仓库 |
| **自定义需求** | `deploy.sh` | 更多自定义选项 |

---

## 🛠️ 工具脚本

- `install_tesseract_ocr.sh` - 单独安装OCR依赖
- `collect_diagnostics.sh` - 收集诊断信息
- `self_update.sh` - 自动更新脚本

---

## 🔍 故障排除

### 安装失败

1. **检查网络连接**
   ```bash
   ping -c 3 github.com
   ```

2. **检查系统权限**
   ```bash
   sudo -l
   ```

3. **查看详细日志**
   ```bash
   sudo scripts/modern_install.sh -v
   ```

4. **禁用自检（如果自检失败）**
   ```bash
   sudo scripts/modern_install.sh -C
   ```

### 服务问题

```bash
# 查看服务状态
systemctl status telegram-ad-guard-bot

# 查看服务日志
journalctl -u telegram-ad-guard-bot -f

# 重启服务
sudo systemctl restart telegram-ad-guard-bot
```

### 依赖问题

```bash
# 手动安装依赖
sudo apt-get update
sudo apt-get install git python3 python3-venv tesseract-ocr ffmpeg

# 或使用安装脚本
sudo scripts/install_tesseract_ocr.sh
```

---

## 💡 建议

1. **首次安装**：使用 `modern_install.sh` 的交互模式
2. **生产部署**：使用 `-s -U -R` 参数安装服务并启用自动更新
3. **批量部署**：使用环境变量配合 `-y` 参数
4. **开发调试**：使用 `-v` 参数查看详细输出

更多信息请参考项目主页：https://github.com/yo1u23/guanggao