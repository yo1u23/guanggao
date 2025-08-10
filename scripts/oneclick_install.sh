#!/usr/bin/env bash

# 🚀 Telegram 广告管理机器人 - 一键安装脚本
# 版本: v2.0.0
# 支持: Ubuntu/Debian/CentOS/RHEL/Fedora/Arch Linux
# 用法: curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/oneclick_install.sh | sudo bash

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
readonly SCRIPT_VERSION="v2.0.0"
readonly APP_NAME="Telegram Ad Guard Bot"
readonly REPO_URL="https://github.com/yo1u23/guanggao"
readonly INSTALL_DIR="/opt/telegram-ad-guard-bot"
readonly SERVICE_NAME="telegram-ad-guard-bot"
readonly SERVICE_USER="$(id -un)"

# 全局变量
TELEGRAM_TOKEN=""
ADMIN_IDS=""
NON_INTERACTIVE=false
INSTALL_SERVICE=true
LOG_FILE="/tmp/telegram-bot-install.log"

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"; }
log_header() { echo -e "\n${CYAN}==================================================${NC}\n${WHITE}$*${NC}\n${CYAN}==================================================${NC}\n" | tee -a "$LOG_FILE"; }

# 错误处理
cleanup_on_error() {
    log_error "安装过程中发生错误，正在清理..."
    if [[ -d "$INSTALL_DIR" ]]; then
        log_warning "清理安装目录: $INSTALL_DIR"
        rm -rf "$INSTALL_DIR" 2>/dev/null || true
    fi
    log_error "安装失败。请查看日志文件: $LOG_FILE"
    exit 1
}

trap cleanup_on_error ERR

# 显示欢迎信息
show_welcome() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    Telegram 广告管理机器人                    ║"
    echo "║                        一键安装脚本                          ║"
    echo "║                        版本: $SCRIPT_VERSION                        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${WHITE}功能特性:${NC}"
    echo -e "• 文本与图片（OCR）双通道检测"
    echo -e "• 视频首帧 OCR + pHash 去重"
    echo -e "• AI 识别支持（OpenRouter）"
    echo -e "• 按群独立规则配置"
    echo -e "• 新人治理功能"
    echo -e "• 自动删除广告和垃圾消息"
    echo
}

# 检查系统要求
check_system_requirements() {
    log_header "检查系统要求"
    
    # 检查操作系统
    if [[ "$(uname)" != "Linux" ]]; then
        log_error "此脚本仅支持 Linux 系统"
        exit 1
    fi
    
    # 检查是否为 root 用户
    if [[ $EUID -eq 0 ]]; then
        log_warning "检测到 root 用户，建议使用 sudo 运行"
    fi
    
    # 检查 Python 版本
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 未安装，请先安装 Python 3.8+"
        exit 1
    fi
    
    local python_version=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    if [[ "$(printf '%s\n' "3.8" "$python_version" | sort -V | head -n1)" != "3.8" ]]; then
        log_error "Python 版本过低，需要 3.8+，当前版本: $python_version"
        exit 1
    fi
    log_success "Python 版本检查通过: $python_version"
    
    # 检查网络连接
    if ! ping -c 1 github.com &> /dev/null; then
        log_error "无法连接到 GitHub，请检查网络连接"
        exit 1
    fi
    log_success "网络连接检查通过"
}

# 检测包管理器
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    elif command -v zypper &> /dev/null; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

# 安装系统依赖
install_system_dependencies() {
    log_header "安装系统依赖"
    
    local pkg_manager=$(detect_package_manager)
    log_info "检测到包管理器: $pkg_manager"
    
    case $pkg_manager in
        apt)
            log_info "更新包列表..."
            sudo apt-get update
            
            log_info "安装系统依赖..."
            sudo apt-get install -y \
                git \
                python3 \
                python3-pip \
                python3-venv \
                python3-dev \
                build-essential \
                tesseract-ocr \
                tesseract-ocr-chi-sim \
                tesseract-ocr-eng \
                ffmpeg \
                libffi-dev \
                libssl-dev
            ;;
        yum|dnf)
            log_info "安装系统依赖..."
            sudo $pkg_manager install -y \
                git \
                python3 \
                python3-pip \
                python3-devel \
                gcc \
                tesseract \
                tesseract-langpack-chi-sim \
                tesseract-langpack-eng \
                ffmpeg \
                libffi-devel \
                openssl-devel
            ;;
        pacman)
            log_info "安装系统依赖..."
            sudo pacman -S --noconfirm \
                git \
                python \
                python-pip \
                base-devel \
                tesseract \
                tesseract-data-chi-sim \
                tesseract-data-eng \
                ffmpeg \
                libffi \
                openssl
            ;;
        zypper)
            log_info "安装系统依赖..."
            sudo zypper install -y \
                git \
                python3 \
                python3-pip \
                python3-devel \
                gcc \
                tesseract \
                tesseract-langpack-chi-sim \
                tesseract-langpack-eng \
                ffmpeg \
                libffi-devel \
                libopenssl-devel
            ;;
        *)
            log_warning "未知的包管理器，请手动安装以下依赖:"
            log_warning "git, python3, python3-pip, python3-venv, tesseract-ocr, ffmpeg"
            ;;
    esac
    
    log_success "系统依赖安装完成"
}

# 获取用户输入
get_user_input() {
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        return
    fi
    
    log_header "配置信息"
    
    # 获取 Telegram Bot Token
    while [[ -z "$TELEGRAM_TOKEN" ]]; do
        echo -e "${YELLOW}请输入 Telegram Bot Token:${NC}"
        echo -e "${CYAN}提示: 在 @BotFather 处获取${NC}"
        read -p "Token: " TELEGRAM_TOKEN
        if [[ -z "$TELEGRAM_TOKEN" ]]; then
            log_warning "Token 不能为空"
        fi
    done
    
    # 获取管理员ID
    if [[ -z "$ADMIN_IDS" ]]; then
        echo -e "${YELLOW}请输入管理员用户ID (逗号分隔，可选):${NC}"
        echo -e "${CYAN}提示: 在 @userinfobot 处获取您的ID${NC}"
        read -p "管理员ID: " ADMIN_IDS
    fi
    
    # 确认安装
    echo
    echo -e "${WHITE}安装配置:${NC}"
    echo -e "• 安装目录: ${CYAN}$INSTALL_DIR${NC}"
    echo -e "• 服务名称: ${CYAN}$SERVICE_NAME${NC}"
    echo -e "• 运行用户: ${CYAN}$SERVICE_USER${NC}"
    echo
    read -p "确认开始安装? [Y/n]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_info "安装已取消"
        exit 0
    fi
}

# 克隆代码仓库
clone_repository() {
    log_header "克隆代码仓库"
    
    if [[ -d "$INSTALL_DIR" ]]; then
        log_warning "目标目录已存在: $INSTALL_DIR"
        read -p "是否删除现有目录? [y/N]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "删除现有目录..."
            sudo rm -rf "$INSTALL_DIR"
        else
            log_error "安装目录已存在，请选择其他目录或删除现有目录"
            exit 1
        fi
    fi
    
    log_info "克隆仓库到: $INSTALL_DIR"
    sudo git clone "$REPO_URL" "$INSTALL_DIR"
    sudo chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
    
    if [[ ! -d "$INSTALL_DIR" ]]; then
        log_error "仓库克隆失败"
        exit 1
    fi
    
    log_success "代码仓库克隆完成"
}

# 设置虚拟环境
setup_virtual_environment() {
    log_header "设置 Python 虚拟环境"
    
    cd "$INSTALL_DIR"
    
    log_info "创建虚拟环境..."
    python3 -m venv .venv
    
    log_info "激活虚拟环境..."
    source .venv/bin/activate
    
    log_info "升级 pip..."
    pip install --upgrade pip
    
    log_info "安装 Python 依赖..."
    pip install -r requirements.txt
    
    log_success "Python 虚拟环境设置完成"
}

# 创建配置文件
create_config_file() {
    log_header "创建配置文件"
    
    cd "$INSTALL_DIR"
    
    # 创建 .env 文件
    cat > .env << EOF
# Telegram Bot 配置
TELEGRAM_BOT_TOKEN=$TELEGRAM_TOKEN

# 管理员配置
ADMIN_IDS=$ADMIN_IDS

# OCR 配置
OCR_LANGUAGES=chi_sim+eng

# 默认动作
DEFAULT_ACTION=delete_and_mute_and_notify

# AI 配置 (可选)
AI_MODE=off
OPENROUTER_API_KEY=
OPENROUTER_MODEL=gpt-4o-mini
AI_EXCLUSIVE=off
AI_CLASSIFY_THRESHOLD=0.7

# 日志配置
LOG_LEVEL=INFO
LOG_FILE=bot.log
EOF
    
    log_success "配置文件创建完成"
}

# 安装系统服务
install_system_service() {
    log_header "安装系统服务"
    
    cd "$INSTALL_DIR"
    
    # 创建服务文件
    local service_file="/etc/systemd/system/$SERVICE_NAME.service"
    
    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=Telegram Ad Guard Bot
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
Environment=PATH=$INSTALL_DIR/.venv/bin
ExecStart=$INSTALL_DIR/.venv/bin/python -m app.bot
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # 重新加载 systemd
    sudo systemctl daemon-reload
    
    # 启用服务
    sudo systemctl enable "$SERVICE_NAME"
    
    log_success "系统服务安装完成: $SERVICE_NAME"
}

# 测试安装
test_installation() {
    log_header "测试安装"
    
    cd "$INSTALL_DIR"
    
    # 激活虚拟环境
    source .venv/bin/activate
    
    # 测试 Python 模块导入
    log_info "测试 Python 模块导入..."
    if python -c "import app.bot" 2>/dev/null; then
        log_success "Python 模块导入测试通过"
    else
        log_warning "Python 模块导入测试失败，但继续安装"
    fi
    
    # 测试配置文件
    if [[ -f ".env" ]]; then
        log_success "配置文件检查通过"
    else
        log_error "配置文件不存在"
        exit 1
    fi
    
    log_success "安装测试完成"
}

# 启动服务
start_service() {
    log_header "启动系统服务"
    sudo systemctl start "$SERVICE_NAME"
    sudo systemctl status "$SERVICE_NAME" --no-pager
    log_success "系统服务已启动"
}

# 显示安装完成信息
show_completion_info() {
    log_header "🎉 安装完成"
    
    log_success "$APP_NAME 已成功安装到: $INSTALL_DIR"
    
    echo -e "${GREEN}系统服务已安装并启动${NC}"
    echo -e "服务名称: ${CYAN}$SERVICE_NAME${NC}"
    echo
    echo -e "${YELLOW}常用命令:${NC}"
    echo -e "• 查看服务状态: ${CYAN}sudo systemctl status $SERVICE_NAME${NC}"
    echo -e "• 查看实时日志: ${CYAN}sudo journalctl -u $SERVICE_NAME -f${NC}"
    echo -e "• 重启服务: ${CYAN}sudo systemctl restart $SERVICE_NAME${NC}"
    echo -e "• 停止服务: ${CYAN}sudo systemctl stop $SERVICE_NAME${NC}"
    echo
    echo -e "${YELLOW}下一步操作:${NC}"
    echo -e "1. 将机器人添加到 Telegram 群组"
    echo -e "2. 赋予机器人管理员权限（删除消息、限制成员）"
    echo -e "3. 使用 /help 命令查看可用命令"
    echo -e "4. 配置群组规则（关键词、正则等）"
    echo
    echo -e "${YELLOW}配置文件位置:${NC}"
    echo -e "环境配置: ${CYAN}$INSTALL_DIR/.env${NC}"
    echo
    echo -e "${YELLOW}日志文件:${NC}"
    echo -e "系统日志: ${CYAN}sudo journalctl -u $SERVICE_NAME${NC}"
    echo
    echo -e "${GREEN}🎯 安装完成！机器人已自动启动并运行。${NC}"
    echo -e "${CYAN}如有问题请查看日志文件或联系技术支持。${NC}"
}

# 主函数
main() {
    # 初始化日志
    echo "Telegram Bot 一键安装日志 - $(date)" > "$LOG_FILE"
    
    # 显示欢迎信息
    show_welcome
    
    # 检查系统要求
    check_system_requirements
    
    # 获取用户输入
    get_user_input
    
    # 安装系统依赖
    install_system_dependencies
    
    # 克隆代码仓库
    clone_repository
    
    # 设置虚拟环境
    setup_virtual_environment
    
    # 创建配置文件
    create_config_file
    
    # 安装系统服务
    install_system_service
    
    # 测试安装
    test_installation
    
    # 启动服务
    start_service
    
    # 显示完成信息
    show_completion_info
}

# 运行主函数
main "$@"