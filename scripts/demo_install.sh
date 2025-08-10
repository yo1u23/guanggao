#!/usr/bin/env bash

# 🎬 Telegram 广告管理机器人 - 安装演示脚本
# 版本: v1.0.0
# 用法: bash demo_install.sh

set -euo pipefail

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# 配置
readonly SCRIPT_VERSION="v1.0.0"
readonly APP_NAME="Telegram Ad Guard Bot"

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_header() { echo -e "\n${CYAN}==================================================${NC}\n${WHITE}$*${NC}\n${CYAN}==================================================${NC}\n"; }

# 显示欢迎信息
show_welcome() {
    clear
    log_header "欢迎使用 $APP_NAME 安装演示"
    echo -e "${WHITE}此脚本将演示如何安装 Telegram 广告管理机器人${NC}"
    echo -e ""
    echo -e "${YELLOW}演示内容：${NC}"
    echo -e "  • 安装方式选择"
    echo -e "  • 配置参数说明"
    echo -e "  • 安装流程展示"
    echo -e "  • 测试验证方法"
    echo -e ""
    echo -e "${WHITE}注意：此脚本仅用于演示，不会实际安装${NC}"
    echo -e ""
}

# 显示安装方式选择
show_installation_methods() {
    log_header "🚀 安装方式选择"
    
    echo -e "${WHITE}我们提供了多种安装方式，满足不同需求：${NC}"
    echo -e ""
    
    echo -e "${GREEN}1. 🎯 一键安装 (推荐新手)${NC}"
    echo -e "   最简单的安装方式，完全自动化"
    echo -e "   命令：${CYAN}curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/oneclick_install.sh | sudo bash${NC}"
    echo -e ""
    
    echo -e "${GREEN}2. ⚙️  高级安装 (推荐高级用户)${NC}"
    echo -e "   支持自定义配置和命令行参数"
    echo -e "   命令：${CYAN}sudo ./install.sh [选项]${NC}"
    echo -e ""
    
    echo -e "${GREEN}3. 🔧 手动安装 (推荐开发者)${NC}"
    echo -e "   完全手动控制，适合定制化需求"
    echo -e "   参考：${CYAN}docs/SETUP.zh-CN.md${NC}"
    echo -e ""
}

# 显示配置参数说明
show_configuration_options() {
    log_header "⚙️  配置参数说明"
    
    echo -e "${WHITE}安装时需要配置以下参数：${NC}"
    echo -e ""
    
    echo -e "${YELLOW}必需参数：${NC}"
    echo -e "  • ${CYAN}TELEGRAM_BOT_TOKEN${NC}: 从 @BotFather 获取的机器人 Token"
    echo -e "    格式：123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
    echo -e ""
    
    echo -e "${YELLOW}可选参数：${NC}"
    echo -e "  • ${CYAN}ADMIN_IDS${NC}: 管理员用户ID，逗号分隔"
    echo -e "    示例：123456789,987654321"
    echo -e "    留空则所有人可用管理命令"
    echo -e ""
    echo -e "  • ${CYAN}INSTALL_DIR${NC}: 安装目录"
    echo -e "    默认：/opt/telegram-ad-guard-bot"
    echo -e ""
    echo -e "  • ${CYAN}INSTALL_SERVICE${NC}: 是否安装为系统服务"
    echo -e "    推荐：是（自动启动、开机自启）"
    echo -e ""
}

# 显示安装流程
show_installation_process() {
    log_header "📋 安装流程展示"
    
    echo -e "${WHITE}完整的安装流程包括以下步骤：${NC}"
    echo -e ""
    
    echo -e "${GREEN}1. 🔍 系统检查${NC}"
    echo -e "   • 检查操作系统兼容性"
    echo -e "   • 检查 Python 版本 (需要 3.8+)"
    echo -e "   • 检查网络连接"
    echo -e "   • 检查磁盘空间"
    echo -e ""
    
    echo -e "${GREEN}2. 📦 依赖安装${NC}"
    echo -e "   • 自动检测包管理器 (apt/yum/dnf/pacman/zypper)"
    echo -e "   • 安装系统依赖 (git, python3, tesseract, ffmpeg)"
    echo -e "   • 安装 Python 依赖 (python-telegram-bot, pytesseract 等)"
    echo -e ""
    
    echo -e "${GREEN}3. 📥 代码下载${NC}"
    echo -e "   • 从 GitHub 克隆最新代码"
    echo -e "   • 创建 Python 虚拟环境"
    echo -e "   • 安装 Python 包"
    echo -e ""
    
    echo -e "${GREEN}4. ⚙️  配置设置${NC}"
    echo -e "   • 创建 .env 配置文件"
    echo -e "   • 设置 Bot Token 和管理员ID"
    echo -e "   • 配置 OCR 语言和默认动作"
    echo -e ""
    
    echo -e "${GREEN}5. 🚀 服务部署${NC}"
    echo -e "   • 创建 systemd 服务文件"
    echo -e "   • 启用并启动服务"
    echo -e "   • 设置开机自启"
    echo -e ""
    
    echo -e "${GREEN}6. 🧪 安装验证${NC}"
    echo -e "   • 测试 Python 模块导入"
    echo -e "   • 验证配置文件"
    echo -e "   • 检查服务状态"
    echo -e ""
}

# 显示测试验证方法
show_testing_methods() {
    log_header "🧪 测试验证方法"
    
    echo -e "${WHITE}安装完成后，可以使用以下方法验证：${NC}"
    echo -e ""
    
    echo -e "${GREEN}1. 🔍 使用测试脚本${NC}"
    echo -e "   运行内置的测试脚本："
    echo -e "   ${CYAN}bash scripts/test_install.sh${NC}"
    echo -e "   或指定安装目录："
    echo -e "   ${CYAN}bash scripts/test_install.sh /opt/telegram-ad-guard-bot${NC}"
    echo -e ""
    
    echo -e "${GREEN}2. 📊 检查服务状态${NC}"
    echo -e "   如果安装为系统服务："
    echo -e "   ${CYAN}systemctl status telegram-ad-guard-bot${NC}"
    echo -e "   查看服务日志："
    echo -e "   ${CYAN}journalctl -u telegram-ad-guard-bot -f${NC}"
    echo -e ""
    
    echo -e "${GREEN}3. 📝 检查应用日志${NC}"
    echo -e "   查看应用运行日志："
    echo -e "   ${CYAN}tail -f /opt/telegram-ad-guard-bot/bot.log${NC}"
    echo -e ""
    
    echo -e "${GREEN}4. 🧪 手动测试运行${NC}"
    echo -e "   手动启动机器人："
    echo -e "   ${CYAN}cd /opt/telegram-ad-guard-bot${NC}"
    echo -e "   ${CYAN}source .venv/bin/activate${NC}"
    echo -e "   ${CYAN}python -m app.bot${NC}"
    echo -e ""
}

# 显示使用建议
show_usage_suggestions() {
    log_header "💡 使用建议"
    
    echo -e "${WHITE}安装成功后，建议按以下步骤操作：${NC}"
    echo -e ""
    
    echo -e "${GREEN}1. 🤖 机器人设置${NC}"
    echo -e "   • 将机器人添加到 Telegram 群组"
    echo -e "   • 赋予机器人管理员权限（删除消息、限制成员）"
    echo -e "   • 测试机器人是否响应"
    echo -e ""
    
    echo -e "${GREEN}2. ⚙️  基础配置${NC}"
    echo -e "   • 使用 /help 查看可用命令"
    echo -e "   • 设置关键词过滤规则"
    echo -e "   • 配置正则表达式过滤"
    echo -e "   • 设置默认动作和禁言时长"
    echo -e ""
    
    echo -e "${GREEN}3. 🆕 新人治理${NC}"
    echo -e "   • 启用新人缓冲功能"
    echo -e "   • 设置入群验证码"
    echo -e "   • 配置首条消息加严"
    echo -e ""
    
    echo -e "${GREEN}4. 🤖 AI 功能 (可选)${NC}"
    echo -e "   • 配置 OpenRouter API 密钥"
    echo -e "   • 启用 AI 识别功能"
    echo -e "   • 设置 AI 独占模式"
    echo -e ""
}

# 显示故障排除
show_troubleshooting() {
    log_header "🚨 故障排除"
    
    echo -e "${WHITE}如果遇到问题，可以尝试以下解决方法：${NC}"
    echo -e ""
    
    echo -e "${YELLOW}常见问题：${NC}"
    echo -e "1. 权限不足：${CYAN}sudo chown -R \$USER:\$USER /opt/telegram-ad-guard-bot${NC}"
    echo -e "2. 模块导入失败：重新安装 Python 依赖"
    echo -e "3. 服务启动失败：检查日志文件"
    echo -e "4. 配置文件问题：检查 .env 文件内容"
    echo -e ""
    
    echo -e "${YELLOW}重新安装：${NC}"
    echo -e "如果问题无法解决，可以重新安装："
    echo -e "1. 停止并禁用服务"
    echo -e "2. 删除安装目录"
    echo -e "3. 重新运行安装脚本"
    echo -e ""
    
    echo -e "${YELLOW}获取帮助：${NC}"
    echo -e "• 查看项目文档：${CYAN}docs/USAGE.zh-CN.md${NC}"
    echo -e "• 提交 Issue：${CYAN}https://github.com/yo1u23/guanggao/issues${NC}"
    echo -e "• 查看安装日志：${CYAN}/tmp/telegram-bot-install.log${NC}"
    echo -e ""
}

# 显示演示总结
show_demo_summary() {
    log_header "🎯 演示总结"
    
    echo -e "${WHITE}现在您已经了解了安装的完整流程：${NC}"
    echo -e ""
    echo -e "${GREEN}✅ 安装方式选择${NC}"
    echo -e "${GREEN}✅ 配置参数说明${NC}"
    echo -e "${GREEN}✅ 安装流程展示${NC}"
    echo -e "${GREEN}✅ 测试验证方法${NC}"
    echo -e "${GREEN}✅ 使用建议${NC}"
    echo -e "${GREEN}✅ 故障排除${NC}"
    echo -e ""
    
    echo -e "${WHITE}下一步操作：${NC}"
    echo -e "1. 获取 Telegram Bot Token"
    echo -e "2. 选择安装方式"
    echo -e "3. 运行安装脚本"
    echo -e "4. 测试验证安装"
    echo -e "5. 配置和使用机器人"
    echo -e ""
    
    echo -e "${GREEN}🎉 演示完成！祝您安装顺利！${NC}"
}

# 主函数
main() {
    # 显示欢迎信息
    show_welcome
    
    # 等待用户确认
    echo -e "${WHITE}按 Enter 键继续...${NC}"
    read -r
    
    # 显示安装方式选择
    show_installation_methods
    
    echo -e "${WHITE}按 Enter 键继续...${NC}"
    read -r
    
    # 显示配置参数说明
    show_configuration_options
    
    echo -e "${WHITE}按 Enter 键继续...${NC}"
    read -r
    
    # 显示安装流程
    show_installation_process
    
    echo -e "${WHITE}按 Enter 键继续...${NC}"
    read -r
    
    # 显示测试验证方法
    show_testing_methods
    
    echo -e "${WHITE}按 Enter 键继续...${NC}"
    read -r
    
    # 显示使用建议
    show_usage_suggestions
    
    echo -e "${WHITE}按 Enter 键继续...${NC}"
    read -r
    
    # 显示故障排除
    show_troubleshooting
    
    echo -e "${WHITE}按 Enter 键继续...${NC}"
    read -r
    
    # 显示演示总结
    show_demo_summary
}

# 运行主函数
main "$@"