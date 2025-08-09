#!/usr/bin/env bash

# 🚀 电报广告管理机器人 - 一键安装脚本（quick_setup）
# 参考风格：sgr/quick_setup.sh（彩色日志、交互向导、系统检测、回滚）
# 用法（交互式）：
#   sudo bash -lc "curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/quick_setup.sh | sudo bash"
# 用法（非交互）：
#   TELEGRAM_BOT_TOKEN=123:ABC ADMIN_IDS=111,222 sudo bash -lc "curl -fsSL https://raw.githubusercontent.com/yo1u23/guanggao/main/scripts/quick_setup.sh | sudo bash -s -- -y -s -R"

set -e

SCRIPT_VERSION="v1.0.0"
APP_NAME="Telegram Ad Guard Bot"
DEFAULT_REPO="https://github.com/yo1u23/guanggao"
DEST_DIR_DEFAULT="/opt/telegram-ad-guard-bot"
SERVICE_NAME_DEFAULT="telegram-ad-guard-bot"
REQUIRED_MEMORY_MB=256
REQUIRED_DISK_GB=1

# 颜色
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'

# 全局变量
REPO_URL="$DEFAULT_REPO"
DEST_DIR="$DEST_DIR_DEFAULT"
SERVICE_NAME="$SERVICE_NAME_DEFAULT"
SERVICE_USER="$(id -un)"
NON_INTERACTIVE=0
INSTALL_SERVICE=0
RUN_AFTER=0
AUTO_TIMER=0
TIMER_INTERVAL="1h"
PKG_MANAGER=""
INSTALL_LOG=""
ERROR_LOG=""
BACKUP_DIR=""
PREV_COMMIT=""

# .env 值（支持环境变量预置）
TOKEN="${TELEGRAM_BOT_TOKEN-}"
ADMIN_IDS="${ADMIN_IDS-}"
ADMIN_LOG_CHAT_IDS="${ADMIN_LOG_CHAT_IDS-}"
OCR_LANGUAGES="${OCR_LANGUAGES-chi_sim+eng}"
DEFAULT_ACTION="${DEFAULT_ACTION-delete_and_mute_and_notify}"
AI_MODE="${AI_MODE-off}"
OPENROUTER_API_BASE="${OPENROUTER_API_BASE-https://openrouter.ai/api/v1}"
OPENROUTER_API_KEY="${OPENROUTER_API_KEY-}"
OPENROUTER_MODEL="${OPENROUTER_MODEL-gpt-4o-mini}"
AI_EXCLUSIVE="${AI_EXCLUSIVE-off}"
AI_CLASSIFY_THRESHOLD="${AI_CLASSIFY_THRESHOLD-0.7}"

# 日志
log_info(){ echo -e "${BLUE}[INFO]${NC} $*"; [[ -n "$INSTALL_LOG" ]] && echo "[INFO] $(date '+%F %T') $*" >>"$INSTALL_LOG"; }
log_ok(){ echo -e "${GREEN}[ OK ]${NC} $*"; [[ -n "$INSTALL_LOG" ]] && echo "[OK] $(date '+%F %T') $*" >>"$INSTALL_LOG"; }
log_warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; [[ -n "$INSTALL_LOG" ]] && echo "[WARN] $(date '+%F %T') $*" >>"$INSTALL_LOG"; }
log_err(){ echo -e "${RED}[ERR ]${NC} $*"; [[ -n "$ERROR_LOG" ]] && echo "[ERR] $(date '+%F %T') $*" >>"$ERROR_LOG"; [[ -n "$INSTALL_LOG" ]] && echo "[ERR] $(date '+%F %T') $*" >>"$INSTALL_LOG"; }
log_hdr(){ echo -e "${CYAN}==================================================${NC}\n${WHITE}$*${NC}\n${CYAN}==================================================${NC}"; [[ -n "$INSTALL_LOG" ]] && echo "[HDR] $(date '+%F %T') $*" >>"$INSTALL_LOG"; }

usage(){ cat <<USAGE
$APP_NAME - 一键安装脚本 $SCRIPT_VERSION

参数：
  -r URL      仓库地址（默认：$DEFAULT_REPO）
  -d DIR      安装目录（默认：$DEST_DIR_DEFAULT）
  -n NAME     服务名（默认：$SERVICE_NAME_DEFAULT）
  -u USER     运行用户（默认：当前用户）
  -s          安装为 systemd 服务
  -U          安装自更新定时器
  -I INT      定时器间隔（默认：1h）
  -R          安装后运行（未启用 -s 时后台运行）
  -y          非交互（从环境变量/参数读取）

  -t TOKEN    TELEGRAM_BOT_TOKEN（必填）
  -A IDS      ADMIN_IDS（逗号分隔，可选）
  -L IDS      ADMIN_LOG_CHAT_IDS（逗号分隔，可选）
  -o LANGS    OCR_LANGUAGES（默认 chi_sim+eng）
  -D ACTION   默认动作（默认 delete_and_mute_and_notify）
  -M MODE     AI_MODE（off|openrouter）
  -K KEY      OPENROUTER_API_KEY
  -B BASE     OPENROUTER_API_BASE
  -m MODEL    OPENROUTER_MODEL
  -E on|off   AI_EXCLUSIVE
  -T THRESH   AI_CLASSIFY_THRESHOLD（0..1）
USAGE
}

cleanup_on_error(){
  log_err "安装过程中发生错误，正在清理..."
  # 尝试恢复 .env 备份
  if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
    [[ -f "$BACKUP_DIR/.env" ]] && cp -f "$BACKUP_DIR/.env" "$DEST_DIR/.env" 2>/dev/null || true
  fi
  # 回滚代码
  if [[ -n "$PREV_COMMIT" && -d "$DEST_DIR/.git" ]]; then
    log_warn "回滚到先前提交：$PREV_COMMIT"
    git -C "$DEST_DIR" reset --hard "$PREV_COMMIT" || true
  fi
  log_err "安装失败。日志：$INSTALL_LOG；错误：$ERROR_LOG"
  exit 1
}
trap cleanup_on_error ERR

ensure_root(){ if [[ $(id -u) -ne 0 ]]; then log_err "请以 root/sudo 运行"; exit 1; fi }

parse_args(){
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -r) REPO_URL="$2"; shift 2;;
      -d) DEST_DIR="$2"; shift 2;;
      -n) SERVICE_NAME="$2"; shift 2;;
      -u) SERVICE_USER="$2"; shift 2;;
      -s) INSTALL_SERVICE=1; shift;;
      -U) AUTO_TIMER=1; shift;;
      -I) TIMER_INTERVAL="$2"; shift 2;;
      -R) RUN_AFTER=1; shift;;
      -y) NON_INTERACTIVE=1; shift;;
      -t) TOKEN="$2"; shift 2;;
      -A) ADMIN_IDS="$2"; shift 2;;
      -L) ADMIN_LOG_CHAT_IDS="$2"; shift 2;;
      -o) OCR_LANGUAGES="$2"; shift 2;;
      -D) DEFAULT_ACTION="$2"; shift 2;;
      -M) AI_MODE="$2"; shift 2;;
      -K) OPENROUTER_API_KEY="$2"; shift 2;;
      -B) OPENROUTER_API_BASE="$2"; shift 2;;
      -m) OPENROUTER_MODEL="$2"; shift 2;;
      -E) AI_EXCLUSIVE="$2"; shift 2;;
      -T) AI_CLASSIFY_THRESHOLD="$2"; shift 2;;
      -h|--help) usage; exit 0;;
      *) args+=("$1"); shift;;
    esac
  done
  set -- "${args[@]}"
}

init_logs(){
  mkdir -p "$DEST_DIR" "$DEST_DIR/logs" 2>/dev/null || true
  INSTALL_LOG="$DEST_DIR/logs/install_$(date +%Y%m%d_%H%M%S).log"
  ERROR_LOG="$DEST_DIR/logs/error_$(date +%Y%m%d_%H%M%S).log"
  BACKUP_DIR="$DEST_DIR/.backup_$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$BACKUP_DIR" || true
}

system_detect(){
  log_hdr "🔍 系统检测"
  if command -v apt-get >/dev/null 2>&1; then PKG_MANAGER=apt; log_info "包管理器：apt";
  elif command -v dnf >/dev/null 2>&1; then PKG_MANAGER=dnf; log_info "包管理器：dnf";
  elif command -v yum >/dev/null 2>&1; then PKG_MANAGER=yum; log_info "包管理器：yum";
  elif command -v pacman >/dev/null 2>&1; then PKG_MANAGER=pacman; log_info "包管理器：pacman";
  else PKG_MANAGER=unknown; log_warn "无法识别包管理器"; fi

  # 资源检查
  if command -v free >/dev/null 2>&1; then
    local mem_kb=$(free | awk '/^Mem:/{print $2}')
    local mem_mb=$((mem_kb/1024))
    log_info "内存：${mem_mb}MB"
    if (( mem_mb < REQUIRED_MEMORY_MB )); then log_err "内存不足（至少 ${REQUIRED_MEMORY_MB}MB）"; exit 1; fi
  fi
  if command -v df >/dev/null 2>&1; then
    local disk_kb=$(df "$DEST_DIR" 2>/dev/null | awk 'NR==2{print $4}');
    [[ -z "$disk_kb" ]] && disk_kb=$(df . | awk 'NR==2{print $4}')
    local disk_gb=$((disk_kb/1024/1024))
    log_info "可用磁盘：${disk_gb}GB"
    if (( disk_gb < REQUIRED_DISK_GB )); then log_err "磁盘不足（至少 ${REQUIRED_DISK_GB}GB）"; exit 1; fi
  fi
}

install_deps(){
  log_hdr "📦 安装系统依赖"
  case "$PKG_MANAGER" in
    apt) apt-get update -y && apt-get install -y git python3 python3-venv tesseract-ocr tesseract-ocr-chi-sim tesseract-ocr-chi-tra ffmpeg;;
    dnf) dnf install -y git python3 python3-virtualenv tesseract ffmpeg;;
    yum) yum install -y git python3 python3-virtualenv tesseract ffmpeg;;
    pacman) pacman -Sy --noconfirm git python python-virtualenv tesseract ffmpeg;;
    *) log_warn "请自行安装 git/python3/venv/tesseract/ffmpeg";;
  esac
}

backup_existing(){
  log_hdr "🗂️ 备份现有配置"
  if [[ -f "$DEST_DIR/.env" ]]; then
    cp -f "$DEST_DIR/.env" "$BACKUP_DIR/.env" || true
    log_info "已备份 .env 到 $BACKUP_DIR/.env"
  fi
}

clone_or_update(){
  log_hdr "⬇️ 拉取/更新代码"
  if [[ -d "$DEST_DIR/.git" ]]; then
    PREV_COMMIT=$(git -C "$DEST_DIR" rev-parse HEAD 2>/dev/null || true)
    log_info "当前提交：${PREV_COMMIT:-unknown}"
    git -C "$DEST_DIR" fetch origin --depth=1
    git -C "$DEST_DIR" checkout -B main origin/main
    git -C "$DEST_DIR" reset --hard origin/main
  else
    git clone --depth 1 "$REPO_URL" "$DEST_DIR"
  fi
}

create_venv_install(){
  log_hdr "🐍 Python 依赖"
  python3 -m venv "$DEST_DIR/.venv" 2>/dev/null || true
  # shellcheck disable=SC1091
  source "$DEST_DIR/.venv/bin/activate"
  python -m pip install -U pip setuptools wheel
  pip install -r "$DEST_DIR/requirements.txt"
}

set_env_kv(){
  local file="$DEST_DIR/.env"; local key="$1"; local val="$2"
  [[ -z "$val" ]] && return 0
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed -i "s|^${key}=.*$|${key}=${val}|" "$file"
  else
    echo "${key}=${val}" >>"$file"
  fi
}

write_env(){
  log_hdr "⚙️ 配置环境变量"
  touch "$DEST_DIR/.env"
  if [[ $NON_INTERACTIVE -ne 1 ]]; then
    if [[ -z "$TOKEN" ]]; then
      if [[ -r /dev/tty ]]; then
        read -r -p "请输入 Telegram Bot Token: " TOKEN </dev/tty || true
      else
        log_err "检测到通过管道执行，无法交互。请改用 -y 并通过 --token 或 TELEGRAM_BOT_TOKEN 提供 Token。"
        exit 2
      fi
    fi
    if [[ -r /dev/tty ]]; then
      read -r -p "全局管理员（逗号分隔，可留空）: " ADMIN_IDS </dev/tty || true
      read -r -p "通知 Chat IDs（逗号分隔，可留空）: " ADMIN_LOG_CHAT_IDS </dev/tty || true
    fi
  fi
  set_env_kv TELEGRAM_BOT_TOKEN "$TOKEN"
  set_env_kv ADMIN_IDS "$ADMIN_IDS"
  set_env_kv ADMIN_LOG_CHAT_IDS "$ADMIN_LOG_CHAT_IDS"
  set_env_kv OCR_LANGUAGES "$OCR_LANGUAGES"
  set_env_kv DEFAULT_ACTION "$DEFAULT_ACTION"
  set_env_kv AI_MODE "$AI_MODE"
  set_env_kv OPENROUTER_API_BASE "$OPENROUTER_API_BASE"
  set_env_kv OPENROUTER_API_KEY "$OPENROUTER_API_KEY"
  set_env_kv OPENROUTER_MODEL "$OPENROUTER_MODEL"
  set_env_kv AI_EXCLUSIVE "$AI_EXCLUSIVE"
  set_env_kv AI_CLASSIFY_THRESHOLD "$AI_CLASSIFY_THRESHOLD"
  log_ok ".env 写入完成"
}

self_check(){
  log_hdr "🧪 安装后自检"
  # shellcheck disable=SC1091
  source "$DEST_DIR/.venv/bin/activate"
  local out
  out=$(python - <<'PY'
import compileall, importlib
ok = compileall.compile_dir('app', quiet=1)
try:
    importlib.import_module('app.bot')
    print('IMPORT_OK=True')
except Exception as e:
    print('IMPORT_OK=False', e)
print('COMPILE_OK='+str(bool(ok)))
PY
) || true
  echo "$out"
  echo "$out" | grep -q 'COMPILE_OK=True' || { log_err "编译失败"; return 1; }
  echo "$out" | grep -q 'IMPORT_OK=True' || { log_err "导入失败"; return 1; }
  log_ok "自检通过"
}

install_service(){
  [[ $INSTALL_SERVICE -ne 1 ]] && return 0
  if ! command -v systemctl >/dev/null 2>&1; then log_warn "systemctl 不存在，跳过服务"; return 0; fi
  log_hdr "🛠️ 安装 systemd 服务"
  local svc="/etc/systemd/system/${SERVICE_NAME}.service"
  cat >"$svc" <<SERVICE
[Unit]
Description=$APP_NAME
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$DEST_DIR
ExecStart=$DEST_DIR/.venv/bin/python -m app.bot
Restart=always
RestartSec=3
User=$SERVICE_USER

[Install]
WantedBy=multi-user.target
SERVICE
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME" || systemctl start "$SERVICE_NAME"
}

install_timer(){
  [[ $AUTO_TIMER -ne 1 ]] && return 0
  if ! command -v systemctl >/dev/null 2>&1; then log_warn "systemctl 不存在，跳过定时器"; return 0; fi
  log_hdr "⏱️ 安装自更新定时器 ($TIMER_INTERVAL)"
  local usvc="/etc/systemd/system/${SERVICE_NAME}-update.service"
  local utmr="/etc/systemd/system/${SERVICE_NAME}-update.timer"
  cat >"$usvc" <<UPSVC
[Unit]
Description=Auto update for $APP_NAME
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=$DEST_DIR
ExecStart=/bin/bash $DEST_DIR/scripts/self_update.sh
User=$SERVICE_USER
UPSVC
  cat >"$utmr" <<UPTMR
[Unit]
Description=Run ${SERVICE_NAME}-update.service every $TIMER_INTERVAL

[Timer]
OnUnitActiveSec=$TIMER_INTERVAL
AccuracySec=1s
Persistent=true
Unit=${SERVICE_NAME}-update.service

[Install]
WantedBy=timers.target
UPTMR
  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}-update.timer"
  systemctl restart "${SERVICE_NAME}-update.timer" || systemctl start "${SERVICE_NAME}-update.timer"
}

run_background(){
  [[ $RUN_AFTER -ne 1 ]] && return 0
  [[ $INSTALL_SERVICE -eq 1 ]] && return 0
  log_hdr "▶️ 后台运行"
  nohup "$DEST_DIR/.venv/bin/python" -m app.bot >"$DEST_DIR/bot.log" 2>&1 &
  echo $! >"$DEST_DIR/bot.pid"
  log_ok "已启动（PID $(cat "$DEST_DIR/bot.pid" 2>/dev/null || echo '?')） 日志：$DEST_DIR/bot.log"
}

main(){
  ensure_root
  parse_args "$@"
  init_logs
  log_hdr "$APP_NAME 安装开始（$SCRIPT_VERSION）"
  system_detect
  install_deps
  backup_existing
  clone_or_update
  create_venv_install
  write_env
  self_check
  install_service
  install_timer
  run_background
  log_ok "安装完成。目录：$DEST_DIR；服务：$SERVICE_NAME"
}

main "$@"