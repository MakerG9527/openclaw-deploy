#!/bin/bash
# OpenClaw 公共函数库
# 所有脚本都可以 source 这个文件

# 严格错误处理
set -euo pipefail 2>/dev/null || true

# 颜色定义
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export NC='\033[0m'

# 日志函数
log() { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${BLUE}[ℹ]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err() { echo -e "${RED}[✗]${NC} $*" >&2; }

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载环境变量
if [ -f "$SCRIPT_DIR/.env" ]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/.env"
else
    warn "未找到 .env 文件，使用默认配置"
fi

# 路径配置（可从环境变量覆盖）
export OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
export MIHOMO_HOME="${MIHOMO_HOME:-$HOME/.config/mihomo}"
export LOG_DIR="${LOG_DIR:-$HOME/.local/log}"
export OPENCLAW_BIN="${OPENCLAW_BIN:-$(command -v openclaw 2>/dev/null || echo "$HOME/.npm-global/bin/openclaw")}"

# 备份函数
backup_file() {
    file="$1"
    backup_dir="${2:-$(dirname "$file")/backups}"
    
    if [ -f "$file" ]; then
        mkdir -p "$backup_dir"
        backup_file="$backup_dir/$(basename "$file").$(date +%Y%m%d-%H%M%S).bak"
        cp "$file" "$backup_file"
        info "已备份: $backup_file"
        echo "$backup_file"
    fi
}

# 检查命令是否存在
check_cmd() {
    command -v "$1" &> /dev/null
}

# 检查进程是否运行
is_running() {
    pgrep -x "$1" &> /dev/null
}

# 获取进程PID
get_pid() {
    pgrep -x "$1" 2>/dev/null || echo ""
}

# 测试代理连通性
test_proxy() {
    proxy_url="${1:-http://127.0.0.1:7890}"
    test_url="${2:-https://www.google.com}"
    
    # 确保返回有效的 HTTP 状态码
    local result
    result=$(curl -s --proxy "$proxy_url" -o /dev/null --connect-timeout 5 -w "%{http_code}" "$test_url" 2>/dev/null)
    
    if [ -z "$result" ] || ! [[ "$result" =~ ^[0-9]+$ ]]; then
        echo "000"
    else
        echo "$result"
    fi
}

# 等待服务就绪
wait_for_service() {
    name="$1"
    check_cmd="$2"
    max_wait="${3:-30}"
    
    info "等待 $name 就绪..."
    for i in $(seq 1 "$max_wait"); do
        if eval "$check_cmd" &> /dev/null; then
            log "$name 已就绪"
            return 0
        fi
        echo -n "."
        sleep 1
    done
    err "$name 启动超时"
    return 1
}

# 安全sed替换（跨平台兼容）
safe_sed() {
    pattern="$1"
    file="$2"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "$pattern" "$file"
    else
        # Linux
        sed -i "$pattern" "$file"
    fi
}

# 确认提示
confirm() {
    msg="${1:-确认执行?}"
    read -p "$msg [Y/n]: " response
    [[ "$response" =~ ^[Yy]$ ]] || [ -z "$response" ]
}

# 询问 yes/no（带默认值）
ask_yesno() {
    prompt="${1:-确认?}"
    default="${2:-y}"
    
    read -p "$prompt [Y/n]: " response
    response="${response:-$default}"
    
    [[ "$response" =~ ^[Yy]$ ]]
}

# 显示 banner
banner() {
    echo ""
    echo "========================================"
    echo "  $*"
    echo "========================================"
    echo ""
}
