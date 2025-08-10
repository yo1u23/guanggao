#!/usr/bin/env bash

# 🚀 Telegram 广告管理机器人 - 简化安装脚本
# 版本: v1.0.0
# 专门解决交互式输入问题

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# 配置
REPO_URL="https://github.com/yo1u23/guanggao"
INSTALL_DIR="/opt/telegram-ad-guard-bot"
SERVICE_NAME="telegram-ad-guard-bot"
SERVICE_USER="$(id -un)"

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# 显示欢迎信息
show_welcome() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    Telegram 广告管理机器人                    ║"
    echo "║                        简化安装脚本                          ║"
    echo "║                        版本: v1.0.0                        ║"
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
    echo -e "\n${CYAN}==================================================${NC}"
    echo -e "${WHITE}检查系统要求${NC}"
    echo -e "${CYAN}==================================================${NC}\n"
    
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

# 获取用户输入
get_user_input() {
    echo -e "\n${CYAN}==================================================${NC}"
    echo -e "${WHITE}配置信息${NC}"
    echo -e "${CYAN}==================================================${NC}\n"
    
    # 获取 Telegram Bot Token
    local token=""
    while [[ -z "$token" ]]; do
        echo -e "${YELLOW}请输入 Telegram Bot Token:${NC}"
        echo -e "${CYAN}提示: 在 @BotFather 处获取${NC}"
        echo -e "${CYAN}格式: 123456789:ABCdefGHIjklMNOpqrsTUVwxyz${NC}"
        echo -n "Token: "
        read -r token
        echo
        
        if [[ -z "$token" ]]; then
            log_warning "Token 不能为空，请重新输入"
        elif [[ ! "$token" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
            log_warning "Token 格式不正确，请检查后重新输入"
            token=""
        fi
    done
    
    # 获取管理员ID
    echo -e "${YELLOW}请输入管理员用户ID (逗号分隔，可选):${NC}"
    echo -e "${CYAN}提示: 在 @userinfobot 处获取您的ID${NC}"
    echo -e "${CYAN}格式: 123456789 或 123456789,987654321${NC}"
    echo -n "管理员ID: "
    read -r admin_ids
    echo
    
    # 保存到环境变量
    export TELEGRAM_BOT_TOKEN="$token"
    export ADMIN_IDS="$admin_ids"
    
    # 确认安装
    echo
    echo -e "${WHITE}安装配置:${NC}"
    echo -e "• 安装目录: ${CYAN}$INSTALL_DIR${NC}"
    echo -e "• 服务名称: ${CYAN}$SERVICE_NAME${NC}"
    echo -e "• 运行用户: ${CYAN}$SERVICE_USER${NC}"
    echo -e "• Bot Token: ${CYAN}${token:0:10}...${NC}"
    echo -e "• 管理员ID: ${CYAN}${admin_ids:-未设置}${NC}"
    echo
    echo -n "确认开始安装? [Y/n]: "
    read -r -n 1 confirm
    echo
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        log_info "安装已取消"
        exit 0
    fi
}

# 安装系统依赖
install_system_dependencies() {
    echo -e "\n${CYAN}==================================================${NC}"
    echo -e "${WHITE}安装系统依赖${NC}"
    echo -e "${CYAN}==================================================${NC}\n"
    
    # 检测包管理器
    local pkg_manager=""
    if command -v apt &> /dev/null; then
        pkg_manager="apt"
    elif command -v yum &> /dev/null; then
        pkg_manager="yum"
    elif command -v dnf &> /dev/null; then
        pkg_manager="dnf"
    elif command -v pacman &> /dev/null; then
        pkg_manager="pacman"
    elif command -v zypper &> /dev/null; then
        pkg_manager="zypper"
    else
        log_error "未检测到支持的包管理器"
        exit 1
    fi
    
    log_info "检测到包管理器: $pkg_manager"
    
    # 安装依赖
    case "$pkg_manager" in
        apt)
            log_info "使用 apt 安装依赖..."
            sudo apt update
            sudo apt install -y git python3 python3-pip python3-venv tesseract-ocr ffmpeg
            ;;
        yum|dnf)
            log_info "使用 $pkg_manager 安装依赖..."
            sudo $pkg_manager install -y git python3 python3-pip python3-venv tesseract ffmpeg
            ;;
        pacman)
            log_info "使用 pacman 安装依赖..."
            sudo pacman -Sy --noconfirm git python python-pip python-virtualenv tesseract ffmpeg
            ;;
        zypper)
            log_info "使用 zypper 安装依赖..."
            sudo zypper install -y git python3 python3-pip python3-venv tesseract ffmpeg
            ;;
    esac
    
    log_success "系统依赖安装完成"
}

# 克隆代码仓库
clone_repository() {
    echo -e "\n${CYAN}==================================================${NC}"
    echo -e "${WHITE}克隆代码仓库${NC}"
    echo -e "${CYAN}==================================================${NC}\n"
    
    if [[ -d "$INSTALL_DIR" ]]; then
        log_warning "目标目录已存在: $INSTALL_DIR"
        echo -n "是否删除现有目录? [y/N]: "
        read -r -n 1 reply
        echo
        if [[ "$reply" =~ ^[Yy]$ ]]; then
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
    echo -e "\n${CYAN}==================================================${NC}"
    echo -e "${WHITE}设置 Python 虚拟环境${NC}"
    echo -e "${CYAN}==================================================${NC}\n"
    
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
    echo -e "\n${CYAN}==================================================${NC}"
    echo -e "${WHITE}创建配置文件${NC}"
    echo -e "${CYAN}==================================================${NC}\n"
    
    cd "$INSTALL_DIR"
    
    # 创建 .env 文件
    cat > .env <<EOF
# Telegram Bot 配置
TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN
ADMIN_IDS=$ADMIN_IDS

# OCR 配置
OCR_LANGUAGES=chi_sim+eng

# 默认动作
DEFAULT_ACTION=delete_and_mute_and_notify

# AI 配置
AI_MODE=off
OPENROUTER_API_BASE=https://openrouter.ai/api/v1
OPENROUTER_API_KEY=
OPENROUTER_MODEL=gpt-4o-mini
AI_EXCLUSIVE=off
AI_CLASSIFY_THRESHOLD=0.7
EOF
    
    log_success "配置文件创建完成"
}

# 安装系统服务
install_system_service() {
    echo -e "\n${CYAN}==================================================${NC}"
    echo -e "${WHITE}安装系统服务${NC}"
    echo -e "${CYAN}==================================================${NC}\n"
    
    cd "$INSTALL_DIR"
    
    # 创建 systemd 服务文件
    sudo tee /etc/systemd/system/"$SERVICE_NAME".service > /dev/null <<EOF
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
    
    log_success "系统服务安装完成"
}

# 启动服务
start_service() {
    echo -e "\n${CYAN}==================================================${NC}"
    echo -e "${WHITE}启动系统服务${NC}"
    echo -e "${CYAN}==================================================${NC}\n"
    
    sudo systemctl start "$SERVICE_NAME"
    sudo systemctl status "$SERVICE_NAME" --no-pager
    log_success "系统服务已启动"
}

# 显示安装完成信息
show_completion_info() {
    echo -e "\n${CYAN}==================================================${NC}"
    echo -e "${WHITE}🎉 安装完成${NC}"
    echo -e "${CYAN}==================================================${NC}\n"
    
    log_success "Telegram 广告管理机器人已成功安装到: $INSTALL_DIR"
    
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
    echo -e "${GREEN}🎯 安装完成！机器人已自动启动并运行。${NC}"
    echo -e "${CYAN}如有问题请查看日志文件或联系技术支持。${NC}"
}

# 主函数
main() {
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
    
    # 启动服务
    start_service
    
    # 显示完成信息
    show_completion_info
}

# 运行主函数
main "$@"