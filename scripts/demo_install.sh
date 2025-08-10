#!/usr/bin/env bash

# 🎬 Telegram 广告管理机器人 - 安装演示脚本
# 版本: v1.0.0
# 功能: 演示如何使用一键安装脚本

set -euo pipefail

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# 显示演示信息
show_demo() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                Telegram 广告管理机器人                        ║"
    echo "║                    安装演示脚本                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo -e "${WHITE}本脚本将演示如何安装 Telegram 广告管理机器人${NC}"
    echo
}

# 显示安装方式
show_installation_methods() {
    echo -e "${YELLOW}📋 安装方式选择:${NC}"
    echo
    echo -e "${WHITE}1. 🚀 一键安装 (推荐)${NC}"
    echo -e "   curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/oneclick_install.sh | sudo bash"
    echo
    echo -e "${WHITE}2. 🔧 高级安装${NC}"
    echo -e "   sudo bash scripts/install.sh"
    echo
    echo -e "${WHITE}3. 🧪 测试安装${NC}"
    echo -e "   sudo bash scripts/test_installation.sh"
    echo
}

# 显示安装步骤
show_installation_steps() {
    echo -e "${YELLOW}📝 安装步骤:${NC}"
    echo
    echo -e "${WHITE}步骤 1: 获取 Bot Token${NC}"
    echo -e "   • 在 Telegram 中搜索 @BotFather"
    echo -e "   • 发送 /newbot 创建新机器人"
    echo -e "   • 保存获得的 Token"
    echo
    echo -e "${WHITE}步骤 2: 获取用户ID${NC}"
    echo -e "   • 在 Telegram 中搜索 @userinfobot"
    echo -e "   • 发送任意消息获取您的用户ID"
    echo
    echo -e "${WHITE}步骤 3: 运行安装脚本${NC}"
    echo -e "   • 选择上述任一安装方式"
    echo -e "   • 按提示输入配置信息"
    echo -e "   • 等待安装完成"
    echo
    echo -e "${WHITE}步骤 4: 配置机器人${NC}"
    echo -e "   • 将机器人添加到群组"
    echo -e "   • 赋予管理员权限"
    echo -e "   • 使用 /help 查看命令"
    echo
}

# 显示系统要求
show_system_requirements() {
    echo -e "${YELLOW}💻 系统要求:${NC}"
    echo
    echo -e "${WHITE}• 操作系统:${NC} Linux (Ubuntu/Debian/CentOS/RHEL/Fedora/Arch Linux)"
    echo -e "${WHITE}• Python:${NC} 3.8 或更高版本"
    echo -e "${WHITE}• 内存:${NC} 至少 512MB"
    echo -e "${WHITE}• 磁盘空间:${NC} 至少 2GB"
    echo -e "${WHITE}• 网络:${NC} 可访问 GitHub"
    echo
}

# 显示功能特性
show_features() {
    echo -e "${YELLOW}✨ 功能特性:${NC}"
    echo
    echo -e "${WHITE}• 文本与图片（OCR）双通道检测${NC}"
    echo -e "${WHITE}• 视频首帧 OCR + pHash 去重${NC}"
    echo -e "${WHITE}• AI 识别支持（OpenRouter）${NC}"
    echo -e "${WHITE}• 按群独立规则配置${NC}"
    echo -e "${WHITE}• 新人治理功能${NC}"
    echo -e "${WHITE}• 自动删除广告和垃圾消息${NC}"
    echo -e "${WHITE}• 支持关键词和正则表达式${NC}"
    echo -e "${WHITE}• 灵活的禁言和通知策略${NC}"
    echo
}

# 显示常用命令
show_common_commands() {
    echo -e "${YELLOW}🔧 常用管理命令:${NC}"
    echo
    echo -e "${WHITE}关键词管理:${NC}"
    echo -e "  /add_keyword 广告"
    echo -e "  /remove_keyword 广告"
    echo -e "  /list_keywords"
    echo
    echo -e "${WHITE}正则表达式:${NC}"
    echo -e "  /add_regex 推广.*链接"
    echo -e "  /remove_regex 推广.*链接"
    echo -e "  /list_regex"
    echo
    echo -e "${WHITE}动作设置:${NC}"
    echo -e "  /set_action delete_and_mute_and_notify"
    echo -e "  /set_mute_seconds 3600"
    echo
    echo -e "${WHITE}新人治理:${NC}"
    echo -e "  /set_newcomer_buffer 300 mute"
    echo -e "  /set_captcha on 60"
    echo -e "  /set_first_message_strict on"
    echo
    echo -e "${WHITE}AI 配置:${NC}"
    echo -e "  /set_ai openrouter"
    echo -e "  /set_ai_key YOUR_API_KEY"
    echo -e "  /ai_stats"
    echo
}

# 显示服务管理
show_service_management() {
    echo -e "${YELLOW}📊 服务管理:${NC}"
    echo
    echo -e "${WHITE}查看服务状态:${NC}"
    echo -e "  sudo systemctl status telegram-ad-guard-bot"
    echo
    echo -e "${WHITE}查看实时日志:${NC}"
    echo -e "  sudo journalctl -u telegram-ad-guard-bot -f"
    echo
    echo -e "${WHITE}重启服务:${NC}"
    echo -e "  sudo systemctl restart telegram-ad-guard-bot"
    echo
    echo -e "${WHITE}停止服务:${NC}"
    echo -e "  sudo systemctl stop telegram-ad-guard-bot"
    echo
}

# 显示故障排除
show_troubleshooting() {
    echo -e "${YELLOW}🔍 故障排除:${NC}"
    echo
    echo -e "${WHITE}常见问题:${NC}"
    echo -e "• Python 版本过低: 安装 Python 3.8+"
    echo -e "• OCR 识别失败: 检查 tesseract 安装"
    echo -e "• 权限不足: 确保机器人有管理员权限"
    echo -e "• 网络连接问题: 检查防火墙和网络设置"
    echo
    echo -e "${WHITE}日志文件:${NC}"
    echo -e "• 安装日志: /tmp/telegram-bot-install.log"
    echo -e "• 服务日志: sudo journalctl -u telegram-ad-guard-bot"
    echo -e "• 应用日志: /opt/telegram-ad-guard-bot/bot.log"
    echo
}

# 显示下一步操作
show_next_steps() {
    echo -e "${YELLOW}🚀 下一步操作:${NC}"
    echo
    echo -e "${WHITE}1. 准备安装环境${NC}"
    echo -e "   • 确保系统满足要求"
    echo -e "   • 获取 Bot Token 和用户ID"
    echo
    echo -e "${WHITE}2. 选择安装方式${NC}"
    echo -e "   • 推荐使用一键安装脚本"
    echo -e "   • 或使用高级安装脚本"
    echo
    echo -e "${WHITE}3. 配置机器人${NC}"
    echo -e "   • 添加到群组并设置权限"
    echo -e "   • 配置关键词和规则"
    echo -e "   • 测试各项功能"
    echo
    echo -e "${WHITE}4. 运行测试${NC}"
    echo -e "   • 使用测试脚本验证安装"
    echo -e "   • 检查服务状态和日志"
    echo
}

# 主函数
main() {
    show_demo
    
    while true; do
        echo -e "${CYAN}请选择要查看的内容:${NC}"
        echo
        echo -e "${WHITE}1.${NC} 安装方式选择"
        echo -e "${WHITE}2.${NC} 安装步骤"
        echo -e "${WHITE}3.${NC} 系统要求"
        echo -e "${WHITE}4.${NC} 功能特性"
        echo -e "${WHITE}5.${NC} 常用命令"
        echo -e "${WHITE}6.${NC} 服务管理"
        echo -e "${WHITE}7.${NC} 故障排除"
        echo -e "${WHITE}8.${NC} 下一步操作"
        echo -e "${WHITE}9.${NC} 开始安装"
        echo -e "${WHITE}0.${NC} 退出"
        echo
        
        read -p "请输入选项 [0-9]: " choice
        
        case $choice in
            1) show_installation_methods ;;
            2) show_installation_steps ;;
            3) show_system_requirements ;;
            4) show_features ;;
            5) show_common_commands ;;
            6) show_service_management ;;
            7) show_troubleshooting ;;
            8) show_next_steps ;;
            9)
                echo -e "\n${GREEN}🚀 开始安装...${NC}"
                echo -e "${CYAN}运行以下命令开始安装:${NC}"
                echo -e "${WHITE}curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/oneclick_install.sh | sudo bash${NC}"
                echo
                read -p "按 Enter 键继续..."
                ;;
            0)
                echo -e "\n${GREEN}感谢使用！如有问题请查看文档或联系技术支持。${NC}"
                exit 0
                ;;
            *)
                echo -e "\n${RED}无效选项，请重新选择。${NC}"
                ;;
        esac
        
        echo
        read -p "按 Enter 键返回主菜单..."
        clear
        show_demo
    done
}

# 运行主函数
main "$@"