#!/usr/bin/env bash

# 🧪 Telegram 广告管理机器人 - 安装测试脚本
# 版本: v1.0.0
# 功能: 验证安装是否成功，检查各项功能

set -euo pipefail

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# 配置常量
readonly INSTALL_DIR="/opt/telegram-ad-guard-bot"
readonly SERVICE_NAME="telegram-ad-guard-bot"

# 测试结果
TESTS_PASSED=0
TESTS_TOTAL=0

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_header() { echo -e "\n${CYAN}==================================================${NC}\n${WHITE}$*${NC}\n${CYAN}==================================================${NC}\n"; }

# 测试函数
run_test() {
    local test_name="$1"
    local test_command="$2"
    local test_description="$3"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    echo -e "\n${WHITE}测试 $TESTS_TOTAL: $test_name${NC}"
    echo -e "${CYAN}描述:${NC} $test_description"
    
    if eval "$test_command" >/dev/null 2>&1; then
        log_success "✅ 测试通过: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "❌ 测试失败: $test_name"
        return 1
    fi
}

# 显示测试结果
show_test_results() {
    log_header "测试结果汇总"
    
    echo -e "${WHITE}测试完成: $TESTS_PASSED/$TESTS_TOTAL 通过${NC}"
    
    if [[ $TESTS_PASSED -eq $TESTS_TOTAL ]]; then
        echo -e "\n${GREEN}🎉 所有测试通过！安装成功！${NC}"
        echo -e "${CYAN}您的 Telegram 广告管理机器人已准备就绪。${NC}"
    else
        echo -e "\n${YELLOW}⚠️  部分测试失败，请检查安装。${NC}"
        echo -e "${CYAN}建议查看日志文件或重新运行安装脚本。${NC}"
    fi
    
    echo -e "\n${WHITE}下一步操作:${NC}"
    echo -e "1. 将机器人添加到 Telegram 群组"
    echo -e "2. 赋予机器人管理员权限"
    echo -e "3. 使用 /help 命令查看可用命令"
    echo -e "4. 配置群组规则"
}

# 主测试函数
main() {
    log_header "开始安装测试"
    
    echo -e "${WHITE}本脚本将测试以下项目:${NC}"
    echo -e "• 安装目录检查"
    echo -e "• 配置文件验证"
    echo -e "• Python 环境测试"
    echo -e "• 依赖包检查"
    echo -e "• 系统服务状态"
    echo -e "• 网络连接测试"
    echo
    
    # 测试 1: 检查安装目录
    run_test \
        "安装目录检查" \
        "[[ -d '$INSTALL_DIR' ]]" \
        "验证安装目录是否存在"
    
    # 测试 2: 检查配置文件
    run_test \
        "配置文件检查" \
        "[[ -f '$INSTALL_DIR/.env' ]]" \
        "验证 .env 配置文件是否存在"
    
    # 测试 3: 检查虚拟环境
    run_test \
        "虚拟环境检查" \
        "[[ -d '$INSTALL_DIR/.venv' ]]" \
        "验证 Python 虚拟环境是否存在"
    
    # 测试 4: 检查 Python 可执行文件
    run_test \
        "Python 可执行文件检查" \
        "[[ -f '$INSTALL_DIR/.venv/bin/python' ]]" \
        "验证虚拟环境中的 Python 是否存在"
    
    # 测试 5: 检查 requirements.txt
    run_test \
        "依赖文件检查" \
        "[[ -f '$INSTALL_DIR/requirements.txt' ]]" \
        "验证 requirements.txt 文件是否存在"
    
    # 测试 6: 检查 app 目录
    run_test \
        "应用代码检查" \
        "[[ -d '$INSTALL_DIR/app' ]]" \
        "验证应用代码目录是否存在"
    
    # 测试 7: 检查系统服务
    run_test \
        "系统服务检查" \
        "systemctl list-unit-files | grep -q '$SERVICE_NAME'" \
        "验证系统服务是否已注册"
    
    # 测试 8: 检查服务状态
    if systemctl list-unit-files | grep -q "$SERVICE_NAME"; then
        run_test \
            "服务状态检查" \
            "systemctl is-active --quiet '$SERVICE_NAME'" \
            "验证系统服务是否正在运行"
    else
        log_warning "跳过服务状态检查（服务未注册）"
    fi
    
    # 测试 9: 检查 Python 依赖
    if [[ -f "$INSTALL_DIR/.venv/bin/python" ]]; then
        run_test \
            "Python 依赖检查" \
            "$INSTALL_DIR/.venv/bin/python -c 'import telegram, pytesseract, PIL, dotenv, imagehash, numpy'" \
            "验证主要 Python 依赖包是否可导入"
    else
        log_warning "跳过 Python 依赖检查（虚拟环境不存在）"
    fi
    
    # 测试 10: 检查系统依赖
    run_test \
        "Tesseract OCR 检查" \
        "command -v tesseract >/dev/null" \
        "验证 Tesseract OCR 是否已安装"
    
    run_test \
        "FFmpeg 检查" \
        "command -v ffmpeg >/dev/null" \
        "验证 FFmpeg 是否已安装"
    
    # 测试 11: 检查网络连接
    run_test \
        "Telegram API 连接测试" \
        "curl -s --connect-timeout 10 https://api.telegram.org >/dev/null" \
        "验证是否可以连接到 Telegram API"
    
    # 测试 12: 检查配置文件内容
    if [[ -f "$INSTALL_DIR/.env" ]]; then
        run_test \
            "Bot Token 配置检查" \
            "grep -q '^TELEGRAM_BOT_TOKEN=' '$INSTALL_DIR/.env'" \
            "验证 Bot Token 是否已配置"
    else
        log_warning "跳过配置文件内容检查（.env 文件不存在）"
    fi
    
    # 测试 13: 检查日志文件
    if systemctl list-unit-files | grep -q "$SERVICE_NAME" && systemctl is-active --quiet "$SERVICE_NAME"; then
        run_test \
            "服务日志检查" \
            "journalctl -u '$SERVICE_NAME' --no-pager -n 1 >/dev/null" \
            "验证是否可以读取服务日志"
    else
        log_warning "跳过服务日志检查（服务未运行）"
    fi
    
    # 测试 14: 检查文件权限
    run_test \
        "文件权限检查" \
        "[[ -r '$INSTALL_DIR/.env' && -r '$INSTALL_DIR/app' ]]" \
        "验证关键文件和目录的读取权限"
    
    # 测试 15: 检查磁盘空间
    run_test \
        "磁盘空间检查" \
        "[[ \$(df -BG '$INSTALL_DIR' | awk 'NR==2{print \$4}' | sed 's/G//') -gt 1 ]]" \
        "验证安装目录有足够的磁盘空间（>1GB）"
    
    # 显示测试结果
    show_test_results
    
    # 显示详细信息
    if [[ -d "$INSTALL_DIR" ]]; then
        echo -e "\n${WHITE}安装详情:${NC}"
        echo -e "安装目录: ${CYAN}$INSTALL_DIR${NC}"
        echo -e "配置文件: ${CYAN}$INSTALL_DIR/.env${NC}"
        
        if systemctl list-unit-files | grep -q "$SERVICE_NAME"; then
            echo -e "服务名称: ${CYAN}$SERVICE_NAME${NC}"
            echo -e "服务状态: ${CYAN}$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || echo "inactive")${NC}"
        fi
        
        if [[ -f "$INSTALL_DIR/.env" ]]; then
            echo -e "\n${WHITE}配置信息:${NC}"
            grep -E '^(TELEGRAM_BOT_TOKEN|ADMIN_IDS|OCR_LANGUAGES|DEFAULT_ACTION)=' "$INSTALL_DIR/.env" | while read -r line; do
                echo -e "  ${CYAN}$line${NC}"
            done
        fi
    fi
    
    # 显示常用命令
    echo -e "\n${WHITE}常用管理命令:${NC}"
    echo -e "查看服务状态: ${CYAN}sudo systemctl status $SERVICE_NAME${NC}"
    echo -e "查看实时日志: ${CYAN}sudo journalctl -u $SERVICE_NAME -f${NC}"
    echo -e "重启服务: ${CYAN}sudo systemctl restart $SERVICE_NAME${NC}"
    echo -e "停止服务: ${CYAN}sudo systemctl stop $SERVICE_NAME${NC}"
    
    if [[ $TESTS_PASSED -eq $TESTS_TOTAL ]]; then
        exit 0
    else
        exit 1
    fi
}

# 运行主函数
main "$@"