#!/usr/bin/env bash

# 🧪 Telegram 广告管理机器人 - 安装测试脚本
# 版本: v1.0.0
# 用法: bash test_install.sh [安装目录]

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
readonly DEFAULT_INSTALL_DIR="/opt/telegram-ad-guard-bot"
readonly SERVICE_NAME="telegram-ad-guard-bot"

# 全局变量
INSTALL_DIR="${1:-$DEFAULT_INSTALL_DIR}"
TEST_RESULTS=()
TOTAL_TESTS=0
PASSED_TESTS=0

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
    local test_description="${3:-}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo -e "\n${WHITE}🧪 测试: $test_name${NC}"
    if [[ -n "$test_description" ]]; then
        echo -e "${YELLOW}描述: $test_description${NC}"
    fi
    
    if eval "$test_command" 2>/dev/null; then
        log_success "✅ 通过: $test_name"
        TEST_RESULTS+=("PASS: $test_name")
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        log_error "❌ 失败: $test_name"
        TEST_RESULTS+=("FAIL: $test_name")
        return 1
    fi
}

# 检查安装目录
test_install_directory() {
    run_test "安装目录检查" \
        "[[ -d '$INSTALL_DIR' ]]" \
        "检查安装目录是否存在"
}

# 检查必要文件
test_required_files() {
    local required_files=(
        ".env"
        "requirements.txt"
        "README.md"
        "app/bot.py"
    )
    
    for file in "${required_files[@]}"; do
        run_test "文件检查: $file" \
            "[[ -f '$INSTALL_DIR/$file' ]]" \
            "检查必要文件 $file 是否存在"
    done
}

# 检查 Python 虚拟环境
test_python_environment() {
    run_test "Python 虚拟环境检查" \
        "[[ -d '$INSTALL_DIR/.venv' ]]" \
        "检查 Python 虚拟环境是否存在"
    
    run_test "Python 可执行文件检查" \
        "[[ -f '$INSTALL_DIR/.venv/bin/python' ]]" \
        "检查虚拟环境中的 Python 可执行文件"
    
    run_test "pip 可执行文件检查" \
        "[[ -f '$INSTALL_DIR/.venv/bin/pip' ]]" \
        "检查虚拟环境中的 pip 可执行文件"
}

# 检查 Python 依赖
test_python_dependencies() {
    cd "$INSTALL_DIR"
    source .venv/bin/activate
    
    local required_packages=(
        "python-telegram-bot"
        "pytesseract"
        "Pillow"
        "python-dotenv"
        "imagehash"
        "numpy"
    )
    
    for package in "${required_packages[@]}"; do
        run_test "Python 包检查: $package" \
            "python -c 'import ${package//-/_}'" \
            "检查 Python 包 $package 是否可以导入"
    done
}

# 检查应用模块
test_application_modules() {
    cd "$INSTALL_DIR"
    source .venv/bin/activate
    
    run_test "应用模块导入测试" \
        "python -c 'import app.bot'" \
        "测试应用主模块是否可以导入"
}

# 检查配置文件
test_configuration() {
    cd "$INSTALL_DIR"
    
    # 检查 .env 文件内容
    if [[ -f ".env" ]]; then
        run_test "Bot Token 配置检查" \
            "grep -q '^TELEGRAM_BOT_TOKEN=' .env" \
            "检查 Bot Token 是否已配置"
        
        run_test "OCR 语言配置检查" \
            "grep -q '^OCR_LANGUAGES=' .env" \
            "检查 OCR 语言配置"
        
        run_test "默认动作配置检查" \
            "grep -q '^DEFAULT_ACTION=' .env" \
            "检查默认动作配置"
    else
        log_error "❌ .env 配置文件不存在"
        TEST_RESULTS+=("FAIL: .env 配置文件不存在")
        return 1
    fi
}

# 检查系统服务
test_system_service() {
    if command -v systemctl &> /dev/null; then
        run_test "系统服务文件检查" \
            "[[ -f '/etc/systemd/system/$SERVICE_NAME.service' ]]" \
            "检查 systemd 服务文件是否存在"
        
        run_test "系统服务状态检查" \
            "systemctl is-enabled $SERVICE_NAME >/dev/null 2>&1" \
            "检查系统服务是否已启用"
        
        run_test "系统服务运行状态检查" \
            "systemctl is-active $SERVICE_NAME >/dev/null 2>&1" \
            "检查系统服务是否正在运行"
    else
        log_warning "⚠️  systemctl 不可用，跳过系统服务测试"
    fi
}

# 检查系统依赖
test_system_dependencies() {
    local system_deps=(
        "git"
        "python3"
        "tesseract"
        "ffmpeg"
    )
    
    for dep in "${system_deps[@]}"; do
        run_test "系统依赖检查: $dep" \
            "command -v $dep >/dev/null 2>&1" \
            "检查系统依赖 $dep 是否已安装"
    done
}

# 检查权限
test_permissions() {
    local current_user=$(id -un)
    
    run_test "安装目录权限检查" \
        "[[ -r '$INSTALL_DIR' && -w '$INSTALL_DIR' ]]" \
        "检查当前用户对安装目录的读写权限"
    
    if [[ -f "$INSTALL_DIR/.env" ]]; then
        run_test "配置文件权限检查" \
            "[[ -r '$INSTALL_DIR/.env' ]]" \
            "检查配置文件的读取权限"
    fi
}

# 检查网络连接
test_network_connectivity() {
    run_test "GitHub 连接测试" \
        "ping -c 1 github.com >/dev/null 2>&1" \
        "测试与 GitHub 的网络连接"
}

# 显示测试结果摘要
show_test_summary() {
    log_header "🧪 测试结果摘要"
    
    echo -e "${WHITE}总测试数: $TOTAL_TESTS${NC}"
    echo -e "${GREEN}通过测试: $PASSED_TESTS${NC}"
    echo -e "${RED}失败测试: $((TOTAL_TESTS - PASSED_TESTS))${NC}"
    
    local pass_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    echo -e "${WHITE}通过率: ${pass_rate}%${NC}"
    
    echo -e "\n${WHITE}详细结果:${NC}"
    for result in "${TEST_RESULTS[@]}"; do
        if [[ "$result" == PASS:* ]]; then
            echo -e "${GREEN}✅ $result${NC}"
        else
            echo -e "${RED}❌ $result${NC}"
        fi
    done
    
    echo -e "\n${CYAN}==================================================${NC}"
    
    if [[ $PASSED_TESTS -eq $TOTAL_TESTS ]]; then
        echo -e "${GREEN}🎉 所有测试通过！安装成功！${NC}"
        return 0
    else
        echo -e "${RED}⚠️  部分测试失败，请检查安装${NC}"
        return 1
    fi
}

# 显示使用建议
show_usage_suggestions() {
    log_header "💡 使用建议"
    
    echo -e "${WHITE}如果所有测试通过，您可以：${NC}"
    echo -e "1. 将机器人添加到 Telegram 群组"
    echo -e "2. 赋予机器人管理员权限"
    echo -e "3. 使用 /help 命令查看可用命令"
    
    echo -e "\n${WHITE}如果部分测试失败，请：${NC}"
    echo -e "1. 检查错误日志"
    echo -e "2. 确认系统依赖是否完整"
    echo -e "3. 检查配置文件是否正确"
    echo -e "4. 重新运行安装脚本"
    
    echo -e "\n${WHITE}常用命令：${NC}"
    if command -v systemctl &> /dev/null; then
        echo -e "• 查看服务状态: ${CYAN}systemctl status $SERVICE_NAME${NC}"
        echo -e "• 查看服务日志: ${CYAN}journalctl -u $SERVICE_NAME -f${NC}"
        echo -e "• 重启服务: ${CYAN}systemctl restart $SERVICE_NAME${NC}"
    fi
    echo -e "• 查看应用日志: ${CYAN}tail -f $INSTALL_DIR/bot.log${NC}"
    echo -e "• 手动运行: ${CYAN}cd $INSTALL_DIR && source .venv/bin/activate && python -m app.bot${NC}"
}

# 主函数
main() {
    log_header "开始测试 Telegram 广告管理机器人安装"
    
    echo -e "${WHITE}安装目录: $INSTALL_DIR${NC}"
    echo -e "${WHITE}开始时间: $(date)${NC}"
    
    # 运行所有测试
    test_install_directory
    test_required_files
    test_python_environment
    test_python_dependencies
    test_application_modules
    test_configuration
    test_system_service
    test_system_dependencies
    test_permissions
    test_network_connectivity
    
    # 显示结果
    show_test_summary
    show_usage_suggestions
    
    # 返回适当的退出码
    if [[ $PASSED_TESTS -eq $TOTAL_TESTS ]]; then
        exit 0
    else
        exit 1
    fi
}

# 运行主函数
main "$@"