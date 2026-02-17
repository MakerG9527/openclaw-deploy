#!/bin/bash
# OpenClaw 交互式配置脚本
# 用于新服务器一键部署

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_USER=$(whoami)

echo "========================================"
echo "  OpenClaw 交互式配置"
echo "========================================"
echo ""
echo "当前用户: $INSTALL_USER"
echo "安装目录: $SCRIPT_DIR"
echo ""

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${BLUE}[ℹ]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err() { echo -e "${RED}[✗]${NC} $*" >&2; }

# 检查命令是否存在
check_cmd() {
    command -v "$1" &> /dev/null
}

# 询问函数
ask() {
    local prompt="$1"
    local default="${2:-}"
    local result
    
    if [ -n "$default" ]; then
        read -p "$prompt [$default]: " result
        result="${result:-$default}"
    else
        read -p "$prompt: " result
    fi
    
    echo "$result"
}

# 询问 yes/no
ask_yesno() {
    local prompt="$1"
    local default="${2:-y}"
    local result
    
    read -p "$prompt [Y/n]: " result
    result="${result:-$default}"
    
    [[ "$result" =~ ^[Yy]$ ]]
}

# 检测系统架构
detect_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l) echo "armv7" ;;
        *) echo "$arch" ;;
    esac
}

# 第一步：系统检测和信息展示
echo "[1/6] 系统检测"
echo "----------------------------------------"
info "操作系统: $(uname -s)"
info "架构: $(detect_arch)"
info "主机名: $(hostname)"
echo ""

# 检查必要的命令
MISSING_DEPS=()

if ! check_cmd curl; then
    MISSING_DEPS+=("curl")
fi

if ! check_cmd python3; then
    MISSING_DEPS+=("python3")
fi

if ! check_cmd node; then
    MISSING_DEPS+=("nodejs")
fi

if ! check_cmd npm; then
    MISSING_DEPS+=("npm")
fi

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    warn "检测到以下依赖未安装:"
    printf '  - %s\n' "${MISSING_DEPS[@]}"
    
    if ask_yesno "是否尝试自动安装依赖?"; then
        info "正在安装依赖..."
        if check_cmd apt; then
            sudo apt update
            sudo apt install -y curl python3 nodejs npm
        elif check_cmd yum; then
            sudo yum install -y curl python3 nodejs npm
        elif check_cmd pacman; then
            sudo pacman -Sy --noconfirm curl python3 nodejs npm
        else
            err "无法自动安装，请手动安装: ${MISSING_DEPS[*]}"
            exit 1
        fi
    else
        err "请先安装依赖后再运行此脚本"
        exit 1
    fi
fi

echo ""

# 第二步：选择 AI 模型来源
echo "[2/6] 选择 AI 模型来源"
echo "----------------------------------------"
echo "请选择要使用的 AI 模型来源："
echo ""
echo "  1) 使用 Ollama（本地或远程部署的模型）"
echo "  2) 使用 vLLM（高性能推理服务）"
echo "  3) 跳过本地模型，只使用 API（如 Moonshot/Kimi）"
echo ""

read -p "选择 [1/2/3] (默认: 1): " MODEL_SOURCE
MODEL_SOURCE="${MODEL_SOURCE:-1}"

USE_OLLAMA=false
USE_VLLM=false
OLLAMA_HOST="127.0.0.1:11434"
VLLM_HOST="127.0.0.1:8000"
DEFAULT_MODEL="moonshot/kimi-k2.5"

if [ "$MODEL_SOURCE" = "1" ]; then
    # ========== Ollama 配置 ==========
    USE_OLLAMA=true
    echo ""
    echo "配置 Ollama 服务器:"
    echo "  可以部署在本地 (127.0.0.1:11434) 或远程服务器"
    echo ""
    
    OLLAMA_HOST=$(ask "Ollama 服务器地址" "127.0.0.1:11434")
    
    # 测试连接
    info "测试 Ollama 连接..."
    if curl -s --connect-timeout 5 "http://$OLLAMA_HOST/api/tags" > /dev/null 2>&1; then
        log "Ollama 连接成功"
        MODELS=$(curl -s "http://$OLLAMA_HOST/api/tags" 2>/dev/null | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | head -5)
        if [ -n "$MODELS" ]; then
            info "可用模型:"
            echo "$MODELS" | sed 's/^/  - /'
            DEFAULT_MODEL=$(echo "$MODELS" | head -1)
        fi
    else
        warn "无法连接到 Ollama ($OLLAMA_HOST)"
        warn "请确保 Ollama 已安装并运行"
        if ! ask_yesno "是否继续配置?"; then
            exit 1
        fi
    fi

elif [ "$MODEL_SOURCE" = "2" ]; then
    # ========== vLLM 配置 ==========
    USE_VLLM=true
    echo ""
    echo "配置 vLLM 服务器:"
    echo "  vLLM 是一个高性能的大模型推理和服务框架"
    echo "  可以部署在本地 (127.0.0.1:8000) 或远程服务器"
    echo ""
    
    VLLM_HOST=$(ask "vLLM 服务器地址" "127.0.0.1:8000")
    
    # 测试连接
    info "测试 vLLM 连接..."
    if curl -s --connect-timeout 5 "http://$VLLM_HOST/v1/models" > /dev/null 2>&1; then
        log "vLLM 连接成功"
        MODELS=$(curl -s "http://$VLLM_HOST/v1/models" 2>/dev/null | grep -o '"id":"[^"]*"' | cut -d'"' -f4 | head -5)
        if [ -n "$MODELS" ]; then
            info "可用模型:"
            echo "$MODELS" | sed 's/^/  - /'
            DEFAULT_MODEL=$(echo "$MODELS" | head -1)
        else
            DEFAULT_MODEL=$(ask "默认模型名称" "vllm/Qwen2.5-7B-Instruct")
        fi
    else
        warn "无法连接到 vLLM ($VLLM_HOST)"
        warn "请确保 vLLM 服务已启动: python -m vllm.entrypoints.openai.api_server"
        if ! ask_yesno "是否继续配置?"; then
            exit 1
        fi
        DEFAULT_MODEL=$(ask "默认模型名称" "vllm/Qwen2.5-7B-Instruct")
    fi
    
    # 询问 API 密钥（可选）
    echo ""
    info "vLLM API 密钥（如果配置了认证）"
    VLLM_API_KEY=$(ask "API 密钥（留空表示无认证）" "")

else
    # ========== API 模式 ==========
    echo ""
    log "跳过本地模型配置"
    info "将使用 API 方式访问 AI 模型（如 Moonshot/Kimi）"
    OLLAMA_HOST=""
    VLLM_HOST=""
fi

echo ""

# 第三步：配置 Mihomo 代理
echo "[3/6] 配置 Mihomo 代理端口"
echo "----------------------------------------"
echo "Mihomo 是代理服务，用于翻墙访问 Telegram 和 AI 服务"
echo ""

MIHOMO_PORT=$(ask "HTTP 代理端口" "7890")
MIHOMO_SOCKS=$(ask "SOCKS 代理端口" "7891")
MIHOMO_CTRL=$(ask "控制器端口" "9090")

echo ""

# 第四步：配置模型
echo "[4/6] 配置默认模型"
echo "----------------------------------------"

if [ "$USE_OLLAMA" = true ]; then
    echo "请从上面列出的可用模型中选择一个作为默认模型"
    echo ""
    DEFAULT_MODEL=$(ask "默认模型名称" "$DEFAULT_MODEL")
elif [ "$USE_VLLM" = true ]; then
    echo "请配置要使用的 vLLM 模型:"
    echo "  格式: vllm/model-name"
    echo "  示例: vllm/Qwen2.5-7B-Instruct, vllm/llama-3-8b"
    echo ""
    DEFAULT_MODEL=$(ask "默认模型" "$DEFAULT_MODEL")
else
    echo "请配置要使用的 API 模型:"
    echo "  格式: provider/model-name"
    echo "  示例: moonshot/kimi-k2.5, openai/gpt-4"
    echo ""
    DEFAULT_MODEL=$(ask "默认模型" "moonshot/kimi-k2.5")
fi

echo ""

# 第五步：生成配置文件
echo "[5/6] 生成配置文件"
echo "----------------------------------------"

# 创建必要的目录
mkdir -p "$HOME/.config/mihomo"
mkdir -p "$HOME/.openclaw"
mkdir -p "$HOME/.local/log"

# 生成 .env 文件
info "生成环境变量配置..."

# 根据选择生成不同内容
cat > "$SCRIPT_DIR/.env" << EOF
# OpenClaw + Mihomo 环境变量配置
# 生成时间: $(date)
# 使用 Ollama: $USE_OLLAMA
# 使用 vLLM: $USE_VLLM

# ============================================
# Ollama 配置
# ============================================
EOF

if [ "$USE_OLLAMA" = true ]; then
    cat >> "$SCRIPT_DIR/.env" << EOF
OLLAMA_HOST=http://$OLLAMA_HOST
EOF
else
    cat >> "$SCRIPT_DIR/.env" << EOF
# OLLAMA_HOST=  # 未使用 Ollama
EOF
fi

cat >> "$SCRIPT_DIR/.env" << EOF

# ============================================
# vLLM 配置
# ============================================
EOF

if [ "$USE_VLLM" = true ]; then
    cat >> "$SCRIPT_DIR/.env" << EOF
VLLM_HOST=http://$VLLM_HOST
VLLM_API_KEY=${VLLM_API_KEY:-}
EOF
else
    cat >> "$SCRIPT_DIR/.env" << EOF
# VLLM_HOST=  # 未使用 vLLM
# VLLM_API_KEY=
EOF
fi

cat >> "$SCRIPT_DIR/.env" << EOF

# ============================================
# Mihomo 代理配置
# ============================================
MIHOMO_HTTP_PORT=$MIHOMO_PORT
MIHOMO_SOCKS_PORT=$MIHOMO_SOCKS
MIHOMO_CONTROLLER=127.0.0.1:$MIHOMO_CTRL
HTTP_PROXY=http://127.0.0.1:$MIHOMO_PORT
HTTPS_PROXY=http://127.0.0.1:$MIHOMO_PORT
http_proxy=http://127.0.0.1:$MIHOMO_PORT
https_proxy=http://127.0.0.1:$MIHOMO_PORT
NO_PROXY=localhost,127.0.0.1

# ============================================
# 路径配置
# ============================================
OPENCLAW_HOME=\$HOME/.openclaw
MIHOMO_HOME=\$HOME/.config/mihomo
LOG_DIR=\$HOME/.local/log

# OpenClaw 二进制路径（自动检测）
# OPENCLAW_BIN=/usr/local/bin/openclaw

# ============================================
# 其他配置
# ============================================
NODE_TLS_REJECT_UNAUTHORIZED=0
DEFAULT_MODEL=$DEFAULT_MODEL
EOF

log "已生成 $SCRIPT_DIR/.env"

# 创建基础 Mihomo 配置（如果没有）
if [ ! -f "$HOME/.config/mihomo/config.yaml" ]; then
    cat > "$HOME/.config/mihomo/config.yaml" << 'EOFM'
# Mihomo 基础配置
# 请运行 ./mihomo-sub.sh 添加你的订阅链接

mixed-port: 7890
allow-lan: true
mode: Rule
log-level: info
external-controller: 127.0.0.1:9090

# 默认规则
rules:
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
EOFM
    log "已创建基础 Mihomo 配置"
fi

echo ""

# 第六步：添加到 .bashrc
echo "[6/6] 配置 Shell 快捷方式"
echo "----------------------------------------"

if ask_yesno "是否添加快捷命令到 ~/.bashrc?"; then
    # 检查是否已存在
    if grep -q "# OpenClaw 快捷命令" "$HOME/.bashrc" 2>/dev/null; then
        warn "检测到已存在的配置，将更新..."
        # 删除旧配置
        sed -i '/# OpenClaw 快捷命令/,/^# 结束 OpenClaw/d' "$HOME/.bashrc"
    fi
    
    cat >> "$HOME/.bashrc" << 'EOFBRC'

# ============================================
# OpenClaw 快捷命令
# ============================================

# 主控制
alias claw-up='$HOME/openclaw/start-all.sh'
alias claw-down='$HOME/openclaw/stop-all.sh'
alias claw-restart='claw-down && sleep 2 && claw-up'
alias claw-ps='$HOME/openclaw/status-claw.sh'
alias claw-check='$HOME/openclaw/health-check.sh'

# 日志查看
alias claw-log='tail -f $HOME/.local/log/openclaw.log'
alias mih-log='tail -f $HOME/.local/log/mihomo.log'
alias claw-logs='echo "OpenClaw:" && tail -5 $HOME/.local/log/openclaw.log && echo "" && echo "Mihomo:" && tail -5 $HOME/.local/log/mihomo.log'

# 模型管理
alias claw-model='$HOME/openclaw/switch-model.sh'
alias claw-models='$HOME/openclaw/switch-model.sh -l'
alias claw-host='$HOME/openclaw/switch-ollama-host.sh'

# vLLM 控制（如果配置了）
alias vllm-up='echo "请手动启动: python -m vllm.entrypoints.openai.api_server --model <模型名>"'
alias test-vllm='curl -s $VLLM_HOST/v1/models 2>/dev/null | grep -o '"'"'"id":"[^"]*"'"'"' | head -3'

# Mihomo 代理控制
alias mih-up='$HOME/openclaw/start-mihomo.sh'
alias mih-down='pkill mihomo 2>/dev/null || true'
alias mih-restart='pkill mihomo 2>/dev/null; sleep 1; $HOME/openclaw/start-mihomo.sh'
alias mih-sub='$HOME/openclaw/mihomo-sub.sh'
alias mih-config='${EDITOR:-nano} $HOME/.config/mihomo/config.yaml'

# 快速测试
alias test-proxy='curl --proxy http://127.0.0.1:7890 -s https://www.google.com -o /dev/null -w "HTTP %{http_code}\n"'
alias test-ollama='curl -s ${OLLAMA_HOST:-http://127.0.0.1:11434}/api/tags 2>/dev/null | grep -o '"'"'"name":"[^"]*"'"'"' | head -3'
alias test-vllm='curl -s ${VLLM_HOST:-http://127.0.0.1:8000}/v1/models 2>/dev/null | grep -o '"'"'"id":"[^"]*"'"'"' | head -3'

# 编辑配置
alias claw-env='${EDITOR:-nano} $HOME/openclaw/.env'
alias claw-config='${EDITOR:-nano} $HOME/.openclaw/openclaw.json'

# 结束 OpenClaw
EOFBRC

    log "快捷命令已添加到 ~/.bashrc"
    info "请运行 'source ~/.bashrc' 或重新登录以生效"
fi

echo ""
echo "========================================"
echo "  配置完成!"
echo "========================================"
echo ""
echo "配置文件:"
echo "  - 环境变量: $SCRIPT_DIR/.env"
echo "  - Mihomo配置: $HOME/.config/mihomo/config.yaml"
echo ""

if [ "$USE_VLLM" = true ]; then
    echo "vLLM 配置:"
    echo "  - 服务器: http://$VLLM_HOST"
    echo "  - 默认模型: $DEFAULT_MODEL"
    if [ -n "$VLLM_API_KEY" ]; then
        echo "  - API 密钥: 已配置"
    fi
    echo ""
    echo "启动 vLLM 示例:"
    echo "  python -m vllm.entrypoints.openai.api_server --model <模型路径> --port 8000"
    echo ""
fi

echo "下一步:"
echo ""
if ! command -v mihomo &> /dev/null; then
    echo "  1. 安装 Mihomo:"
    echo "     ./install-mihomo.sh"
    echo ""
    echo "  2. 添加代理订阅:"
    echo "     ./mihomo-sub.sh"
    echo ""
    echo "  3. 启动服务:"
    echo "     ./start-all.sh"
    echo ""
else
    log "检测到 Mihomo 已安装"
    echo ""
    echo "  1. 添加代理订阅:"
    echo "     ./mihomo-sub.sh"
    echo ""
    echo "  2. 启动服务:"
    echo "     ./start-all.sh"
    echo ""
fi

echo "  快捷命令（需先 source ~/.bashrc）:"
echo "     claw-up      - 启动服务"
echo "     claw-ps      - 查看状态"
echo "     claw-check   - 健康检查"
echo "     mih-sub      - 管理订阅"

if [ "$USE_VLLM" = true ]; then
    echo "     test-vllm    - 测试 vLLM 连接"
fi

echo ""
