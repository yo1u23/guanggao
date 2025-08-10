#!/usr/bin/env bash
# ==============================================================================
# Telegram Ad Guard Bot - 现代化一键安装脚本
# ==============================================================================
# 
# 功能特点：
# ✅ 智能系统检测（OS、包管理器、Python版本）
# ✅ 彩色输出和进度显示
# ✅ 交互式和非交互式安装
# ✅ 自动依赖安装（tesseract-ocr、ffmpeg、python3）
# ✅ 虚拟环境管理
# ✅ 系统服务集成（systemd）
# ✅ 自动更新定时器
# ✅ 完整的错误处理和回滚机制
# ✅ 安装后自检验证
# ✅ 多种运行模式（服务/后台/手动）
#
# 使用方法：
# 1. 交互式安装：
#    sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/modern_install.sh)"
#
# 2. 非交互式安装：
#    TELEGRAM_BOT_TOKEN=123:ABC ADMIN_IDS=111,222 \
#    sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/modern_install.sh)" -- -y -s -R
#
# 3. 完整配置（包含AI）：
#    sudo bash scripts/modern_install.sh -t YOUR_TOKEN -A 111,222 -M openrouter -K sk-xxx -s -U -R -y
#
# ==============================================================================

set -euo pipefail

# ==============================================================================
# 全局配置
# ==============================================================================

# 脚本信息
readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_NAME="Modern Telegram Ad Guard Bot Installer"
readonly GITHUB_REPO="https://github.com/yo1u23/guanggao"

# 默认配置
readonly DEFAULT_DEST_DIR="/opt/telegram-ad-guard-bot"
readonly DEFAULT_SERVICE_NAME="telegram-ad-guard-bot"
readonly DEFAULT_BRANCH="main"

# 运行时配置
REPO_URL="$GITHUB_REPO"
DEST_DIR="$DEFAULT_DEST_DIR"
SERVICE_NAME="$DEFAULT_SERVICE_NAME"
SERVICE_USER="$(id -un 2>/dev/null || echo "root")"
BRANCH="$DEFAULT_BRANCH"

# 安装选项
NON_INTERACTIVE=0
INSTALL_SERVICE=0
RUN_AFTER=0
AUTO_TIMER=0
TIMER_INTERVAL="1h"
ENABLE_SELF_CHECK=1
ENABLE_ROLLBACK=1
FORCE_REINSTALL=0
VERBOSE=0

# Bot配置（支持环境变量预设）
TOKEN="${TELEGRAM_BOT_TOKEN:-}"
ADMIN_IDS="${ADMIN_IDS:-}"
ADMIN_LOG_CHAT_IDS="${ADMIN_LOG_CHAT_IDS:-}"
OCR_LANGUAGES="${OCR_LANGUAGES:-chi_sim+eng}"
DEFAULT_ACTION="${DEFAULT_ACTION:-delete_and_mute_and_notify}"
AI_MODE="${AI_MODE:-off}"
OPENROUTER_API_BASE="${OPENROUTER_API_BASE:-https://openrouter.ai/api/v1}"
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"
OPENROUTER_MODEL="${OPENROUTER_MODEL:-gpt-4o-mini}"
AI_EXCLUSIVE="${AI_EXCLUSIVE:-off}"
AI_CLASSIFY_THRESHOLD="${AI_CLASSIFY_THRESHOLD:-0.7}"

# 系统信息
OS_NAME=""
PKG_MANAGER=""
PYTHON_CMD=""
SYSTEMCTL_AVAILABLE=0

# 状态跟踪
INSTALL_LOG=""
BACKUP_DIR=""
PREV_COMMIT=""
CLEANUP_NEEDED=0

# ==============================================================================
# 颜色和输出函数
# ==============================================================================

# ANSI颜色代码
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    readonly RED="$(tput setaf 1)"
    readonly GREEN="$(tput setaf 2)"
    readonly YELLOW="$(tput setaf 3)"
    readonly BLUE="$(tput setaf 4)"
    readonly MAGENTA="$(tput setaf 5)"
    readonly CYAN="$(tput setaf 6)"
    readonly WHITE="$(tput setaf 7)"
    readonly BOLD="$(tput bold)"
    readonly RESET="$(tput sgr0)"
else
    readonly RED=""
    readonly GREEN=""
    readonly YELLOW=""
    readonly BLUE=""
    readonly MAGENTA=""
    readonly CYAN=""
    readonly WHITE=""
    readonly BOLD=""
    readonly RESET=""
fi

# 日志函数
log_info() {
    echo -e "${BLUE}${BOLD}[INFO]${RESET} $*" >&2
    [[ -n "$INSTALL_LOG" ]] && echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*" >> "$INSTALL_LOG"
}

log_success() {
    echo -e "${GREEN}${BOLD}[SUCCESS]${RESET} $*" >&2
    [[ -n "$INSTALL_LOG" ]] && echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $*" >> "$INSTALL_LOG"
}

log_warn() {
    echo -e "${YELLOW}${BOLD}[WARNING]${RESET} $*" >&2
    [[ -n "$INSTALL_LOG" ]] && echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARNING] $*" >> "$INSTALL_LOG"
}

log_error() {
    echo -e "${RED}${BOLD}[ERROR]${RESET} $*" >&2
    [[ -n "$INSTALL_LOG" ]] && echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >> "$INSTALL_LOG"
}

log_debug() {
    [[ $VERBOSE -eq 1 ]] && echo -e "${MAGENTA}[DEBUG]${RESET} $*" >&2
    [[ -n "$INSTALL_LOG" ]] && echo "[$(date +'%Y-%m-%d %H:%M:%S')] [DEBUG] $*" >> "$INSTALL_LOG"
}

# 进度显示
show_progress() {
    local current=$1
    local total=$2
    local desc="$3"
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))
    
    printf "\r${CYAN}[%3d%%]${RESET} [" "$percent"
    printf "%*s" $filled | tr ' ' '█'
    printf "%*s" $empty | tr ' ' '░'
    printf "] %s" "$desc"
    
    if [[ $current -eq $total ]]; then
        echo
    fi
}

# 用户确认
confirm() {
    local message="$1"
    local default="${2:-n}"
    
    if [[ $NON_INTERACTIVE -eq 1 ]]; then
        [[ "$default" == "y" ]] && return 0 || return 1
    fi
    
    local prompt
    if [[ "$default" == "y" ]]; then
        prompt="${message} [Y/n]: "
    else
        prompt="${message} [y/N]: "
    fi
    
    while true; do
        read -r -p "$prompt" response
        response=${response,,} # 转小写
        
        if [[ -z "$response" ]]; then
            [[ "$default" == "y" ]] && return 0 || return 1
        elif [[ "$response" =~ ^(y|yes)$ ]]; then
            return 0
        elif [[ "$response" =~ ^(n|no)$ ]]; then
            return 1
        else
            echo "请输入 y/yes 或 n/no"
        fi
    done
}

# ==============================================================================
# 错误处理和清理
# ==============================================================================

# 错误处理函数
handle_error() {
    local line_no=$1
    local exit_code=$2
    log_error "脚本在第 $line_no 行出错，退出码: $exit_code"
    
    if [[ $CLEANUP_NEEDED -eq 1 ]]; then
        cleanup_on_failure
    fi
    
    echo
    log_error "安装失败！请检查上述错误信息。"
    log_info "如需帮助，请访问: $GITHUB_REPO/issues"
    exit $exit_code
}

# 设置错误陷阱
trap 'handle_error $LINENO $?' ERR

# 清理函数
cleanup_on_failure() {
    log_warn "检测到安装失败，开始清理..."
    
    # 停止可能运行的服务
    if [[ $SYSTEMCTL_AVAILABLE -eq 1 ]] && systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        log_info "停止服务: $SERVICE_NAME"
        systemctl stop "$SERVICE_NAME" || true
    fi
    
    # 回滚到之前的版本
    if [[ $ENABLE_ROLLBACK -eq 1 && -n "$PREV_COMMIT" && -d "$DEST_DIR/.git" ]]; then
        log_info "回滚到之前的提交: $PREV_COMMIT"
        if git -C "$DEST_DIR" checkout "$PREV_COMMIT" 2>/dev/null; then
            log_success "成功回滚到之前版本"
            # 尝试重新安装依赖
            if [[ -f "$DEST_DIR/.venv/bin/python" && -f "$DEST_DIR/requirements.txt" ]]; then
                log_info "重新安装Python依赖..."
                "$DEST_DIR/.venv/bin/pip" install -r "$DEST_DIR/requirements.txt" || true
            fi
        else
            log_error "回滚失败，可能需要手动修复"
        fi
    fi
    
    # 恢复备份的配置文件
    if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
        log_info "恢复配置文件备份..."
        if [[ -f "$BACKUP_DIR/.env" ]]; then
            cp "$BACKUP_DIR/.env" "$DEST_DIR/.env" || true
        fi
    fi
    
    log_warn "清理完成。如果问题持续，请查看安装日志: $INSTALL_LOG"
}

# 退出时清理
cleanup_on_exit() {
    # 清理临时文件
    if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
        rm -rf "$BACKUP_DIR" 2>/dev/null || true
    fi
}
trap cleanup_on_exit EXIT

# ==============================================================================
# 系统检测和验证
# ==============================================================================

# 检查运行权限
check_privileges() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        log_info "请使用: sudo $0 $*"
        exit 1
    fi
}

# 检测操作系统
detect_os() {
    log_debug "检测操作系统..."
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_NAME="$ID"
        log_debug "检测到系统: $PRETTY_NAME"
    elif [[ -f /etc/redhat-release ]]; then
        OS_NAME="rhel"
        log_debug "检测到系统: RHEL系"
    elif [[ -f /etc/debian_version ]]; then
        OS_NAME="debian"
        log_debug "检测到系统: Debian系"
    else
        log_warn "无法检测操作系统类型，将尝试通用安装方法"
        OS_NAME="unknown"
    fi
}

# 检测包管理器
detect_package_manager() {
    log_debug "检测包管理器..."
    
    if command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt"
        log_debug "检测到包管理器: apt"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
        log_debug "检测到包管理器: yum"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
        log_debug "检测到包管理器: dnf"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER="pacman"
        log_debug "检测到包管理器: pacman"
    else
        log_error "未检测到支持的包管理器"
        log_info "请手动安装以下依赖: git python3 python3-venv tesseract-ocr ffmpeg"
        exit 1
    fi
}

# 检测Python
detect_python() {
    log_debug "检测Python..."
    
    for cmd in python3 python3.9 python3.8 python3.7 python; do
        if command -v "$cmd" >/dev/null 2>&1; then
            local version
            version=$("$cmd" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
            local major minor
            major=$(echo "$version" | cut -d. -f1)
            minor=$(echo "$version" | cut -d. -f2)
            
            if [[ $major -eq 3 && $minor -ge 7 ]]; then
                PYTHON_CMD="$cmd"
                log_debug "找到合适的Python: $cmd (版本 $version)"
                return 0
            fi
        fi
    done
    
    log_error "未找到Python 3.7+版本"
    log_info "请安装Python 3.7或更高版本"
    exit 1
}

# 检测systemd
detect_systemd() {
    if command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1; then
        SYSTEMCTL_AVAILABLE=1
        log_debug "检测到systemd支持"
    else
        SYSTEMCTL_AVAILABLE=0
        log_debug "未检测到systemd支持"
        if [[ $INSTALL_SERVICE -eq 1 ]]; then
            log_warn "未检测到systemd，将无法安装系统服务"
            INSTALL_SERVICE=0
        fi
    fi
}

# 系统需求检查
check_system_requirements() {
    log_info "检查系统需求..."
    
    # 检查内存（至少256MB）
    local mem_kb
    mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}' 2>/dev/null || echo "0")
    local mem_mb=$((mem_kb / 1024))
    
    if [[ $mem_mb -lt 256 ]]; then
        log_warn "系统内存不足 ($mem_mb MB)，建议至少256MB"
    else
        log_debug "内存检查通过: ${mem_mb}MB"
    fi
    
    # 检查磁盘空间（至少1GB）
    local disk_free
    disk_free=$(df /tmp | tail -1 | awk '{print $4}' 2>/dev/null || echo "0")
    local disk_gb=$((disk_free / 1024 / 1024))
    
    if [[ $disk_gb -lt 1 ]]; then
        log_warn "磁盘空间可能不足 (${disk_gb}GB)，建议至少1GB"
    else
        log_debug "磁盘空间检查通过: ${disk_gb}GB"
    fi
    
    # 检查网络连接
    if ! ping -c 1 -W 5 github.com >/dev/null 2>&1; then
        log_warn "无法连接到github.com，可能影响代码下载"
    else
        log_debug "网络连接检查通过"
    fi
}

# ==============================================================================
# 系统依赖安装
# ==============================================================================

# 更新包索引
update_package_index() {
    log_info "更新包索引..."
    
    case "$PKG_MANAGER" in
        apt)
            apt-get update -qq || {
                log_error "更新apt包索引失败"
                exit 1
            }
            ;;
        yum|dnf)
            "$PKG_MANAGER" makecache -q || {
                log_warn "更新${PKG_MANAGER}缓存失败，继续安装"
            }
            ;;
        pacman)
            pacman -Sy --noconfirm || {
                log_warn "更新pacman数据库失败，继续安装"
            }
            ;;
    esac
}

# 安装系统依赖
install_system_dependencies() {
    log_info "安装系统依赖包..."
    
    local packages=()
    
    case "$PKG_MANAGER" in
        apt)
            packages=(
                "git"
                "python3"
                "python3-venv"
                "python3-pip"
                "tesseract-ocr"
                "tesseract-ocr-chi-sim"
                "tesseract-ocr-chi-tra"
                "ffmpeg"
                "curl"
                "wget"
            )
            
            # 检查是否需要添加额外的包
            if ! command -v python3-distutils >/dev/null 2>&1; then
                packages+=("python3-distutils")
            fi
            
            log_debug "安装包: ${packages[*]}"
            
            # 设置非交互模式
            export DEBIAN_FRONTEND=noninteractive
            
            if ! apt-get install -y "${packages[@]}"; then
                log_error "使用apt安装依赖包失败"
                exit 1
            fi
            ;;
            
        yum)
            packages=(
                "git"
                "python3"
                "python3-pip"
                "python3-devel"
                "tesseract"
                "tesseract-langpack-chi_sim"
                "ffmpeg"
                "curl"
                "wget"
            )
            
            log_debug "安装包: ${packages[*]}"
            
            # 启用EPEL仓库（如果需要）
            if ! yum list installed epel-release >/dev/null 2>&1; then
                log_info "启用EPEL仓库..."
                yum install -y epel-release || log_warn "无法安装EPEL仓库"
            fi
            
            if ! yum install -y "${packages[@]}"; then
                log_error "使用yum安装依赖包失败"
                exit 1
            fi
            ;;
            
        dnf)
            packages=(
                "git"
                "python3"
                "python3-pip"
                "python3-devel"
                "tesseract"
                "tesseract-langpack-chi_sim"
                "ffmpeg"
                "curl"
                "wget"
            )
            
            log_debug "安装包: ${packages[*]}"
            
            if ! dnf install -y "${packages[@]}"; then
                log_error "使用dnf安装依赖包失败"
                exit 1
            fi
            ;;
            
        pacman)
            packages=(
                "git"
                "python"
                "python-pip"
                "tesseract"
                "tesseract-data-chi_sim"
                "ffmpeg"
                "curl"
                "wget"
            )
            
            log_debug "安装包: ${packages[*]}"
            
            if ! pacman -S --noconfirm "${packages[@]}"; then
                log_error "使用pacman安装依赖包失败"
                exit 1
            fi
            ;;
            
        *)
            log_error "不支持的包管理器: $PKG_MANAGER"
            log_info "请手动安装以下依赖: git python3 python3-venv tesseract-ocr ffmpeg"
            exit 1
            ;;
    esac
    
    log_success "系统依赖安装完成"
}

# 验证依赖安装
verify_dependencies() {
    log_info "验证依赖安装..."
    
    local missing=()
    local commands=("git" "$PYTHON_CMD" "tesseract" "ffmpeg")
    
    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        else
            log_debug "✓ $cmd 已安装"
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "以下依赖未正确安装: ${missing[*]}"
        exit 1
    fi
    
    # 验证tesseract中文支持
    if ! tesseract --list-langs 2>/dev/null | grep -q "chi_sim"; then
        log_warn "tesseract中文简体语言包可能未安装"
        log_info "OCR功能可能无法正常工作"
    fi
    
    # 验证Python虚拟环境支持
    if ! "$PYTHON_CMD" -m venv --help >/dev/null 2>&1; then
        log_error "Python虚拟环境模块未安装"
        log_info "请安装python3-venv包"
        exit 1
    fi
    
    log_success "依赖验证通过"
}

# ==============================================================================
# 代码部署
# ==============================================================================

# 备份现有安装
backup_existing_installation() {
    if [[ ! -d "$DEST_DIR" ]]; then
        log_debug "目标目录不存在，无需备份"
        return 0
    fi
    
    log_info "备份现有安装..."
    
    # 创建备份目录
    BACKUP_DIR=$(mktemp -d)
    log_debug "备份目录: $BACKUP_DIR"
    
    # 备份配置文件
    if [[ -f "$DEST_DIR/.env" ]]; then
        cp "$DEST_DIR/.env" "$BACKUP_DIR/.env"
        log_debug "已备份 .env 文件"
    fi
    
    # 记录当前Git提交
    if [[ -d "$DEST_DIR/.git" ]]; then
        PREV_COMMIT=$(git -C "$DEST_DIR" rev-parse HEAD 2>/dev/null || echo "")
        if [[ -n "$PREV_COMMIT" ]]; then
            echo "$PREV_COMMIT" > "$BACKUP_DIR/prev_commit"
            log_debug "记录当前提交: $PREV_COMMIT"
        fi
    fi
    
    log_success "备份完成"
}

# 克隆或更新代码
clone_or_update_repo() {
    log_info "获取最新代码..."
    
    if [[ -d "$DEST_DIR/.git" ]]; then
        log_info "更新现有仓库..."
        
        # 保存当前状态
        local current_branch
        current_branch=$(git -C "$DEST_DIR" branch --show-current 2>/dev/null || echo "")
        
        # 获取远程更新
        if ! git -C "$DEST_DIR" fetch origin --depth=1; then
            log_error "获取远程更新失败"
            exit 1
        fi
        
        # 切换到目标分支
        if ! git -C "$DEST_DIR" checkout -B "$BRANCH" "origin/$BRANCH"; then
            log_error "切换到分支 $BRANCH 失败"
            exit 1
        fi
        
        # 重置到最新提交
        if ! git -C "$DEST_DIR" reset --hard "origin/$BRANCH"; then
            log_error "重置到最新提交失败"
            exit 1
        fi
        
        log_success "代码更新完成"
    else
        log_info "克隆新仓库..."
        
        # 创建目标目录
        mkdir -p "$DEST_DIR"
        
        # 克隆仓库
        if ! git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$DEST_DIR"; then
            log_error "克隆仓库失败"
            exit 1
        fi
        
        log_success "代码克隆完成"
    fi
    
    # 显示当前版本信息
    local current_commit
    current_commit=$(git -C "$DEST_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
    log_info "当前版本: $current_commit"
}

# ==============================================================================
# Python环境设置
# ==============================================================================

# 创建虚拟环境
create_virtual_environment() {
    log_info "设置Python虚拟环境..."
    
    local venv_dir="$DEST_DIR/.venv"
    
    # 如果虚拟环境已存在且不是强制重装，尝试重用
    if [[ -d "$venv_dir" && $FORCE_REINSTALL -eq 0 ]]; then
        log_info "检查现有虚拟环境..."
        
        if [[ -f "$venv_dir/bin/python" && -f "$venv_dir/bin/pip" ]]; then
            # 验证Python版本
            local venv_python_version
            venv_python_version=$("$venv_dir/bin/python" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
            local system_python_version
            system_python_version=$("$PYTHON_CMD" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
            
            if [[ "$venv_python_version" == "$system_python_version" ]]; then
                log_info "重用现有虚拟环境 (Python $venv_python_version)"
                return 0
            else
                log_warn "虚拟环境Python版本不匹配，重新创建"
            fi
        fi
    fi
    
    # 删除旧的虚拟环境
    if [[ -d "$venv_dir" ]]; then
        log_debug "删除旧的虚拟环境..."
        rm -rf "$venv_dir"
    fi
    
    # 创建新的虚拟环境
    log_debug "创建虚拟环境..."
    if ! "$PYTHON_CMD" -m venv "$venv_dir"; then
        log_error "创建Python虚拟环境失败"
        exit 1
    fi
    
    # 激活虚拟环境并升级pip
    log_debug "升级pip..."
    if ! "$venv_dir/bin/python" -m pip install --upgrade pip setuptools wheel; then
        log_error "升级pip失败"
        exit 1
    fi
    
    log_success "虚拟环境设置完成"
}

# 安装Python依赖
install_python_dependencies() {
    log_info "安装Python依赖..."
    
    local venv_python="$DEST_DIR/.venv/bin/python"
    local venv_pip="$DEST_DIR/.venv/bin/pip"
    local requirements_file="$DEST_DIR/requirements.txt"
    
    if [[ ! -f "$requirements_file" ]]; then
        log_error "requirements.txt 文件不存在"
        exit 1
    fi
    
    # 安装依赖
    log_debug "安装依赖包..."
    if ! "$venv_pip" install -r "$requirements_file"; then
        log_error "安装Python依赖失败"
        
        # 尝试使用国内镜像源重试
        log_info "尝试使用国内镜像源..."
        if "$venv_pip" install -r "$requirements_file" -i https://pypi.douban.com/simple/; then
            log_success "使用国内镜像源安装成功"
        else
            log_error "安装Python依赖失败"
            exit 1
        fi
    else
        log_success "Python依赖安装完成"
    fi
    
    # 验证关键模块
    log_debug "验证关键模块..."
    local modules=("telegram" "PIL" "pytesseract" "numpy")
    
    for module in "${modules[@]}"; do
        if ! "$venv_python" -c "import $module" 2>/dev/null; then
            log_warn "模块 $module 可能未正确安装"
        else
            log_debug "✓ $module 模块正常"
        fi
    done
}

# ==============================================================================
# 配置管理
# ==============================================================================

# 交互式配置收集
collect_configuration_interactive() {
    log_info "配置机器人参数..."
    echo
    
    # Telegram Bot Token
    while [[ -z "$TOKEN" ]]; do
        echo -e "${CYAN}请输入Telegram Bot Token:${RESET}"
        echo -e "${YELLOW}  (从 @BotFather 获取，格式如: 123456789:ABCdefGHIjklMNOpqrSTUvwxyz)${RESET}"
        read -r -p "Token: " TOKEN
        
        if [[ ! "$TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
            log_warn "Token格式不正确，请重新输入"
            TOKEN=""
        fi
    done
    
    echo
    
    # 管理员ID
    echo -e "${CYAN}请输入管理员用户ID (可选):${RESET}"
    echo -e "${YELLOW}  (多个ID用逗号分隔，如: 123456789,987654321)${RESET}"
    echo -e "${YELLOW}  (留空表示所有用户都可以使用管理命令)${RESET}"
    read -r -p "管理员ID: " ADMIN_IDS
    
    echo
    
    # 通知聊天ID
    echo -e "${CYAN}请输入管理通知聊天ID (可选):${RESET}"
    echo -e "${YELLOW}  (接收管理通知的聊天ID，通常是管理员私聊或管理群)${RESET}"
    read -r -p "通知聊天ID: " ADMIN_LOG_CHAT_IDS
    
    echo
    
    # AI配置
    if confirm "是否启用AI识别功能？" "n"; then
        AI_MODE="openrouter"
        
        echo -e "${CYAN}请输入OpenRouter API Key:${RESET}"
        echo -e "${YELLOW}  (从 https://openrouter.ai 获取)${RESET}"
        read -r -p "API Key: " OPENROUTER_API_KEY
        
        echo -e "${CYAN}选择AI模型 (默认: gpt-4o-mini):${RESET}"
        echo -e "${YELLOW}  1) gpt-4o-mini (推荐)${RESET}"
        echo -e "${YELLOW}  2) gpt-3.5-turbo${RESET}"
        echo -e "${YELLOW}  3) claude-3-haiku${RESET}"
        echo -e "${YELLOW}  4) 自定义${RESET}"
        read -r -p "选择 [1]: " model_choice
        
        case "${model_choice:-1}" in
            1) OPENROUTER_MODEL="gpt-4o-mini" ;;
            2) OPENROUTER_MODEL="gpt-3.5-turbo" ;;
            3) OPENROUTER_MODEL="anthropic/claude-3-haiku" ;;
            4) 
                read -r -p "请输入模型名称: " OPENROUTER_MODEL
                ;;
            *) OPENROUTER_MODEL="gpt-4o-mini" ;;
        esac
        
        if confirm "启用AI独占模式？(图片/视频只使用AI识别)" "n"; then
            AI_EXCLUSIVE="on"
        fi
    fi
    
    echo
    log_success "配置收集完成"
}

# 写入配置文件
write_configuration() {
    log_info "生成配置文件..."
    
    local env_file="$DEST_DIR/.env"
    
    # 备份现有配置
    if [[ -f "$env_file" ]]; then
        cp "$env_file" "$env_file.backup.$(date +%s)"
        log_debug "已备份现有配置文件"
    fi
    
    # 写入新配置
    cat > "$env_file" << EOF
# Telegram Bot Configuration
TELEGRAM_BOT_TOKEN=$TOKEN
ADMIN_IDS=$ADMIN_IDS
ADMIN_LOG_CHAT_IDS=$ADMIN_LOG_CHAT_IDS

# OCR Configuration
OCR_LANGUAGES=$OCR_LANGUAGES

# Detection Configuration
DEFAULT_ACTION=$DEFAULT_ACTION

# AI Configuration
AI_MODE=$AI_MODE
OPENROUTER_API_BASE=$OPENROUTER_API_BASE
OPENROUTER_API_KEY=$OPENROUTER_API_KEY
OPENROUTER_MODEL=$OPENROUTER_MODEL
AI_EXCLUSIVE=$AI_EXCLUSIVE
AI_CLASSIFY_THRESHOLD=$AI_CLASSIFY_THRESHOLD

# Generated by modern_install.sh v$SCRIPT_VERSION
# $(date)
EOF
    
    # 设置适当的权限
    chmod 600 "$env_file"
    chown "$SERVICE_USER:$(id -gn "$SERVICE_USER" 2>/dev/null || echo "root")" "$env_file" 2>/dev/null || true
    
    log_success "配置文件已生成: $env_file"
}

# ==============================================================================
# 安装后验证
# ==============================================================================

# 自检功能
run_self_check() {
    [[ $ENABLE_SELF_CHECK -eq 0 ]] && return 0
    
    log_info "运行安装后自检..."
    
    local venv_python="$DEST_DIR/.venv/bin/python"
    local checks_passed=0
    local total_checks=4
    
    # 检查1: Python虚拟环境
    show_progress 1 $total_checks "检查Python虚拟环境"
    if [[ -f "$venv_python" ]] && "$venv_python" --version >/dev/null 2>&1; then
        log_debug "✓ Python虚拟环境正常"
        ((checks_passed++))
    else
        log_error "✗ Python虚拟环境异常"
    fi
    
    # 检查2: 配置文件
    show_progress 2 $total_checks "检查配置文件"
    if [[ -f "$DEST_DIR/.env" ]] && grep -q "TELEGRAM_BOT_TOKEN=" "$DEST_DIR/.env"; then
        log_debug "✓ 配置文件正常"
        ((checks_passed++))
    else
        log_error "✗ 配置文件异常"
    fi
    
    # 检查3: 代码编译
    show_progress 3 $total_checks "检查代码编译"
    if cd "$DEST_DIR" && "$venv_python" -m compileall app/ >/dev/null 2>&1; then
        log_debug "✓ 代码编译正常"
        ((checks_passed++))
    else
        log_error "✗ 代码编译异常"
    fi
    
    # 检查4: 模块导入
    show_progress 4 $total_checks "检查模块导入"
    if cd "$DEST_DIR" && "$venv_python" -c "import app.bot" >/dev/null 2>&1; then
        log_debug "✓ 模块导入正常"
        ((checks_passed++))
    else
        log_error "✗ 模块导入异常"
    fi
    
    echo
    
    if [[ $checks_passed -eq $total_checks ]]; then
        log_success "自检通过 ($checks_passed/$total_checks)"
        return 0
    else
        log_error "自检失败 ($checks_passed/$total_checks)"
        
        if [[ $ENABLE_ROLLBACK -eq 1 ]]; then
            log_warn "自检失败，触发回滚机制"
            CLEANUP_NEEDED=1
            return 1
        else
            log_warn "自检失败，但回滚已禁用"
            if confirm "是否继续安装？" "n"; then
                return 0
            else
                exit 1
            fi
        fi
    fi
}

# ==============================================================================
# 系统服务管理
# ==============================================================================

# 安装systemd服务
install_systemd_service() {
    [[ $INSTALL_SERVICE -eq 0 || $SYSTEMCTL_AVAILABLE -eq 0 ]] && return 0
    
    log_info "安装systemd服务..."
    
    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"
    
    # 创建服务文件
    cat > "$service_file" << EOF
[Unit]
Description=Telegram Ad Guard Bot
Documentation=$GITHUB_REPO
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$(id -gn "$SERVICE_USER" 2>/dev/null || echo "root")
WorkingDirectory=$DEST_DIR
ExecStart=$DEST_DIR/.venv/bin/python -m app.bot
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

# 安全设置
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$DEST_DIR

# 环境变量
Environment=PYTHONPATH=$DEST_DIR
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF
    
    # 重新加载systemd
    systemctl daemon-reload
    
    # 启用服务
    if systemctl enable "$SERVICE_NAME"; then
        log_success "服务已启用: $SERVICE_NAME"
    else
        log_error "启用服务失败"
        return 1
    fi
    
    # 启动服务
    if systemctl start "$SERVICE_NAME"; then
        log_success "服务已启动: $SERVICE_NAME"
        
        # 等待一段时间后检查状态
        sleep 3
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            log_success "服务运行正常"
        else
            log_warn "服务可能未正常启动，请检查: systemctl status $SERVICE_NAME"
        fi
    else
        log_error "启动服务失败"
        log_info "请检查服务状态: systemctl status $SERVICE_NAME"
        return 1
    fi
}

# 安装自动更新定时器
install_update_timer() {
    [[ $AUTO_TIMER -eq 0 || $SYSTEMCTL_AVAILABLE -eq 0 ]] && return 0
    
    log_info "安装自动更新定时器..."
    
    local update_service="/etc/systemd/system/${SERVICE_NAME}-update.service"
    local update_timer="/etc/systemd/system/${SERVICE_NAME}-update.timer"
    
    # 创建更新服务
    cat > "$update_service" << EOF
[Unit]
Description=Auto update for Telegram Ad Guard Bot
Documentation=$GITHUB_REPO
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=$SERVICE_USER
WorkingDirectory=$DEST_DIR
ExecStart=/bin/bash $DEST_DIR/scripts/self_update.sh
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}-update
EOF
    
    # 创建定时器
    cat > "$update_timer" << EOF
[Unit]
Description=Run ${SERVICE_NAME}-update.service every $TIMER_INTERVAL
Requires=${SERVICE_NAME}-update.service

[Timer]
OnUnitActiveSec=$TIMER_INTERVAL
AccuracySec=1s
Persistent=true
Unit=${SERVICE_NAME}-update.service

[Install]
WantedBy=timers.target
EOF
    
    # 重新加载systemd
    systemctl daemon-reload
    
    # 启用并启动定时器
    if systemctl enable "${SERVICE_NAME}-update.timer" && \
       systemctl start "${SERVICE_NAME}-update.timer"; then
        log_success "自动更新定时器已启用 (间隔: $TIMER_INTERVAL)"
    else
        log_error "安装自动更新定时器失败"
        return 1
    fi
}

# ==============================================================================
# 后台运行管理
# ==============================================================================

# 后台运行
run_in_background() {
    [[ $RUN_AFTER -eq 0 || $INSTALL_SERVICE -eq 1 ]] && return 0
    
    log_info "在后台启动机器人..."
    
    local venv_python="$DEST_DIR/.venv/bin/python"
    local log_file="$DEST_DIR/bot.log"
    local pid_file="$DEST_DIR/bot.pid"
    
    # 停止可能存在的进程
    if [[ -f "$pid_file" ]]; then
        local old_pid
        old_pid=$(cat "$pid_file" 2>/dev/null || echo "")
        if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
            log_info "停止现有进程 (PID: $old_pid)"
            kill "$old_pid" 2>/dev/null || true
            sleep 2
        fi
        rm -f "$pid_file"
    fi
    
    # 启动新进程
    cd "$DEST_DIR"
    nohup "$venv_python" -m app.bot > "$log_file" 2>&1 &
    local new_pid=$!
    
    # 保存PID
    echo "$new_pid" > "$pid_file"
    
    # 验证进程是否启动
    sleep 2
    if kill -0 "$new_pid" 2>/dev/null; then
        log_success "机器人已在后台启动 (PID: $new_pid)"
        log_info "日志文件: $log_file"
        log_info "停止命令: kill $new_pid"
    else
        log_error "后台启动失败"
        if [[ -f "$log_file" ]]; then
            log_info "错误日志:"
            tail -10 "$log_file" | while read -r line; do
                log_error "  $line"
            done
        fi
        return 1
    fi
}

# ==============================================================================
# 用户界面和帮助
# ==============================================================================

# 显示帮助信息
show_usage() {
    cat << USAGE
${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${RESET}

${CYAN}用法:${RESET}
  $0 [选项]

${CYAN}安装选项:${RESET}
  -r URL          仓库URL (默认: $GITHUB_REPO)
  -d DIR          安装目录 (默认: $DEFAULT_DEST_DIR)
  -b BRANCH       Git分支 (默认: $DEFAULT_BRANCH)
  -u USER         服务用户 (默认: 当前用户)

${CYAN}运行选项:${RESET}
  -s              安装为systemd服务
  -R              安装后立即运行 (如未指定-s则后台运行)
  -U              启用自动更新定时器
  -I INTERVAL     定时器间隔 (默认: 1h)

${CYAN}配置选项:${RESET}
  -t TOKEN        Telegram Bot Token
  -A IDS          管理员ID (逗号分隔)
  -L IDS          通知聊天ID (逗号分隔)
  -o LANGS        OCR语言 (默认: chi_sim+eng)
  -D ACTION       默认动作 (默认: delete_and_mute_and_notify)

${CYAN}AI选项:${RESET}
  -M MODE         AI模式 (off|openrouter)
  -K KEY          OpenRouter API密钥
  -B BASE         OpenRouter API基础URL
  -m MODEL        AI模型 (默认: gpt-4o-mini)
  -E on|off       AI独占模式
  -T THRESHOLD    AI分类阈值 (默认: 0.7)

${CYAN}行为选项:${RESET}
  -y              非交互模式 (使用环境变量或默认值)
  -f              强制重新安装 (重建虚拟环境)
  -C              禁用安装后自检
  -N              禁用失败回滚
  -v              详细输出
  -h              显示此帮助信息

${CYAN}示例:${RESET}
  ${YELLOW}# 交互式安装${RESET}
  sudo $0

  ${YELLOW}# 非交互式安装并启动服务${RESET}
  sudo $0 -t "123456:ABC" -A "111,222" -s -R -y

  ${YELLOW}# 启用AI功能的完整安装${RESET}
  sudo $0 -t "123456:ABC" -A "111" -M openrouter -K "sk-xxx" -s -U -R -y

  ${YELLOW}# 通过环境变量配置${RESET}
  TELEGRAM_BOT_TOKEN="123:ABC" ADMIN_IDS="111,222" sudo $0 -s -R -y

${CYAN}更多信息:${RESET}
  项目主页: $GITHUB_REPO
  文档: $GITHUB_REPO/blob/main/README.md

USAGE
}

# 显示安装总结
show_installation_summary() {
    echo
    echo -e "${GREEN}${BOLD}┌─────────────────────────────────────────────┐${RESET}"
    echo -e "${GREEN}${BOLD}│           安装完成！                        │${RESET}"
    echo -e "${GREEN}${BOLD}└─────────────────────────────────────────────┘${RESET}"
    echo
    
    echo -e "${CYAN}安装信息:${RESET}"
    echo -e "  📁 安装目录: ${WHITE}$DEST_DIR${RESET}"
    echo -e "  🐍 Python: ${WHITE}$(cd "$DEST_DIR" && .venv/bin/python --version)${RESET}"
    echo -e "  📦 版本: ${WHITE}$(git -C "$DEST_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")${RESET}"
    
    if [[ $INSTALL_SERVICE -eq 1 && $SYSTEMCTL_AVAILABLE -eq 1 ]]; then
        echo -e "  🔧 服务: ${WHITE}$SERVICE_NAME${RESET}"
        echo
        echo -e "${CYAN}服务管理:${RESET}"
        echo -e "  查看状态: ${WHITE}systemctl status $SERVICE_NAME${RESET}"
        echo -e "  查看日志: ${WHITE}journalctl -u $SERVICE_NAME -f${RESET}"
        echo -e "  重启服务: ${WHITE}systemctl restart $SERVICE_NAME${RESET}"
        echo -e "  停止服务: ${WHITE}systemctl stop $SERVICE_NAME${RESET}"
        
        if [[ $AUTO_TIMER -eq 1 ]]; then
            echo -e "  更新定时器: ${WHITE}systemctl status ${SERVICE_NAME}-update.timer${RESET}"
        fi
    elif [[ $RUN_AFTER -eq 1 ]]; then
        echo -e "  🚀 运行模式: ${WHITE}后台进程${RESET}"
        echo
        echo -e "${CYAN}进程管理:${RESET}"
        echo -e "  查看日志: ${WHITE}tail -f $DEST_DIR/bot.log${RESET}"
        echo -e "  停止进程: ${WHITE}kill \$(cat $DEST_DIR/bot.pid)${RESET}"
    else
        echo
        echo -e "${CYAN}手动启动:${RESET}"
        echo -e "  ${WHITE}cd $DEST_DIR && .venv/bin/python -m app.bot${RESET}"
    fi
    
    echo
    echo -e "${CYAN}配置文件:${RESET}"
    echo -e "  📄 位置: ${WHITE}$DEST_DIR/.env${RESET}"
    echo -e "  ✏️  编辑: ${WHITE}nano $DEST_DIR/.env${RESET}"
    
    echo
    echo -e "${CYAN}使用说明:${RESET}"
    echo -e "  1. 将机器人添加到Telegram群组"
    echo -e "  2. 给予机器人删除消息和禁言用户的管理员权限"
    echo -e "  3. 发送 ${WHITE}/help${RESET} 查看可用命令"
    
    echo
    echo -e "${CYAN}更多信息:${RESET}"
    echo -e "  📚 文档: ${WHITE}$GITHUB_REPO${RESET}"
    echo -e "  🐛 问题反馈: ${WHITE}$GITHUB_REPO/issues${RESET}"
    
    if [[ -f "$INSTALL_LOG" ]]; then
        echo -e "  📋 安装日志: ${WHITE}$INSTALL_LOG${RESET}"
    fi
    
    echo
    echo -e "${GREEN}感谢使用 Telegram Ad Guard Bot! 🎉${RESET}"
}

# ==============================================================================
# 参数解析
# ==============================================================================

# 解析命令行参数
parse_arguments() {
    while getopts "r:d:b:u:n:sRUI:t:A:L:o:D:M:K:B:m:E:T:yfCNvh" opt; do
        case $opt in
            r) REPO_URL="$OPTARG" ;;
            d) DEST_DIR="$OPTARG" ;;
            b) BRANCH="$OPTARG" ;;
            u) SERVICE_USER="$OPTARG" ;;
            n) SERVICE_NAME="$OPTARG" ;;
            s) INSTALL_SERVICE=1 ;;
            R) RUN_AFTER=1 ;;
            U) AUTO_TIMER=1 ;;
            I) TIMER_INTERVAL="$OPTARG" ;;
            t) TOKEN="$OPTARG" ;;
            A) ADMIN_IDS="$OPTARG" ;;
            L) ADMIN_LOG_CHAT_IDS="$OPTARG" ;;
            o) OCR_LANGUAGES="$OPTARG" ;;
            D) DEFAULT_ACTION="$OPTARG" ;;
            M) AI_MODE="$OPTARG" ;;
            K) OPENROUTER_API_KEY="$OPTARG" ;;
            B) OPENROUTER_API_BASE="$OPTARG" ;;
            m) OPENROUTER_MODEL="$OPTARG" ;;
            E) AI_EXCLUSIVE="$OPTARG" ;;
            T) AI_CLASSIFY_THRESHOLD="$OPTARG" ;;
            y) NON_INTERACTIVE=1 ;;
            f) FORCE_REINSTALL=1 ;;
            C) ENABLE_SELF_CHECK=0 ;;
            N) ENABLE_ROLLBACK=0 ;;
            v) VERBOSE=1 ;;
            h) show_usage; exit 0 ;;
            \?) log_error "无效选项: -$OPTARG"; show_usage; exit 1 ;;
            :) log_error "选项 -$OPTARG 需要参数"; exit 1 ;;
        esac
    done
    
    # 如果启用自动更新定时器，自动启用服务安装
    if [[ $AUTO_TIMER -eq 1 ]]; then
        INSTALL_SERVICE=1
    fi
    
    # 参数验证
    if [[ -n "$TIMER_INTERVAL" ]] && ! [[ "$TIMER_INTERVAL" =~ ^[0-9]+(s|m|h|d)$ ]]; then
        log_error "无效的定时器间隔格式: $TIMER_INTERVAL"
        log_info "支持的格式: 数字+单位 (s=秒, m=分钟, h=小时, d=天)"
        exit 1
    fi
    
    if [[ -n "$AI_MODE" ]] && [[ "$AI_MODE" != "off" && "$AI_MODE" != "openrouter" ]]; then
        log_error "无效的AI模式: $AI_MODE (支持: off, openrouter)"
        exit 1
    fi
    
    if [[ -n "$AI_EXCLUSIVE" ]] && [[ "$AI_EXCLUSIVE" != "on" && "$AI_EXCLUSIVE" != "off" ]]; then
        log_error "无效的AI独占设置: $AI_EXCLUSIVE (支持: on, off)"
        exit 1
    fi
}

# ==============================================================================
# 主函数
# ==============================================================================

main() {
    # 显示标题
    echo -e "${BOLD}${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║        Telegram Ad Guard Bot - 现代化一键安装脚本           ║"
    echo "║                        v$SCRIPT_VERSION                                ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    
    # 解析参数
    parse_arguments "$@"
    
    # 创建安装日志
    INSTALL_LOG=$(mktemp)
    log_info "安装日志: $INSTALL_LOG"
    CLEANUP_NEEDED=1
    
    # 检查权限
    check_privileges "$@"
    
    # 系统检测
    log_info "检测系统环境..."
    detect_os
    detect_package_manager
    detect_python
    detect_systemd
    check_system_requirements
    
    # 如果是交互模式且缺少必要配置，收集配置
    if [[ $NON_INTERACTIVE -eq 0 && -z "$TOKEN" ]]; then
        collect_configuration_interactive
    elif [[ $NON_INTERACTIVE -eq 1 && -z "$TOKEN" ]]; then
        log_error "非交互模式下必须提供 TELEGRAM_BOT_TOKEN"
        log_info "使用 -t 参数或设置环境变量 TELEGRAM_BOT_TOKEN"
        exit 1
    fi
    
    # 开始安装
    log_info "开始安装过程..."
    
    # 第一阶段：系统准备
    show_progress 1 8 "更新包索引"
    update_package_index
    
    show_progress 2 8 "安装系统依赖"
    install_system_dependencies
    
    show_progress 3 8 "验证依赖"
    verify_dependencies
    
    # 第二阶段：代码部署
    show_progress 4 8 "备份现有安装"
    backup_existing_installation
    
    show_progress 5 8 "获取最新代码"
    clone_or_update_repo
    
    # 第三阶段：Python环境
    show_progress 6 8 "设置Python环境"
    create_virtual_environment
    install_python_dependencies
    
    # 第四阶段：配置和验证
    show_progress 7 8 "生成配置文件"
    write_configuration
    
    show_progress 8 8 "运行自检"
    if ! run_self_check; then
        log_error "自检失败，安装中止"
        exit 1
    fi
    
    # 第五阶段：服务安装
    if [[ $INSTALL_SERVICE -eq 1 ]]; then
        log_info "配置系统服务..."
        install_systemd_service
        if [[ $AUTO_TIMER -eq 1 ]]; then
            install_update_timer
        fi
    fi
    
    # 第六阶段：启动运行
    if [[ $RUN_AFTER -eq 1 ]]; then
        run_in_background
    fi
    
    # 安装完成
    CLEANUP_NEEDED=0
    show_installation_summary
    
    log_success "安装成功完成！"
}

# 运行主函数
main "$@"