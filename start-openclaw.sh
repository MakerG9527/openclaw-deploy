#!/bin/bash
# OpenClaw 启动脚本（已修复代理支持 - ES 模块版）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

banner "启动 OpenClaw"

# 清理残留进程
if is_running "openclaw"; then
    info "发现残留进程，正在清理..."
    pkill -9 -f "openclaw gateway" 2>/dev/null || true
    pkill -9 -f "openclaw" 2>/dev/null || true
    rm -f /tmp/openclaw-gateway.pid 2>/dev/null || true
    sleep 2
fi

# 检查 Mihomo
if ! is_running "mihomo"; then
    err "Mihomo 代理未运行"
    info "请先执行: $SCRIPT_DIR/start-mihomo.sh"
    exit 1
fi

# 检查 openclaw 命令
if ! check_cmd openclaw && [ ! -x "$OPENCLAW_BIN" ]; then
    err "未找到 openclaw 命令"
    info "请安装: npm install -g openclaw"
    exit 1
fi

OPENCLAW_CMD="${OPENCLAW_BIN:-$(command -v openclaw)}"

# 设置代理环境变量（用于 curl 等传统工具）
export HTTP_PROXY="http://127.0.0.1:7890"
export HTTPS_PROXY="http://127.0.0.1:7890"
export http_proxy="http://127.0.0.1:7890"
export https_proxy="http://127.0.0.1:7890"

# 设置 Node.js ES 模块代理 bootstrap
export NODE_PATH="/usr/lib/node_modules/openclaw/node_modules"
export NODE_OPTIONS="--import=/root/openclaw/proxy-bootstrap.mjs"

info "环境变量已设置"
info "HTTP_PROXY: $HTTP_PROXY"
info "NODE_OPTIONS: $NODE_OPTIONS"

# OLLAMA_HOST 可选
if [ -n "${OLLAMA_HOST:-}" ]; then
    export OLLAMA_HOST
    info "OLLAMA_HOST: $OLLAMA_HOST"
else
    info "OLLAMA_HOST: 未配置（使用 API 模式）"
fi

info "等待代理就绪..."
sleep 2

# 创建日志目录
mkdir -p "$LOG_DIR"

# 备份旧日志
if [ -f "$LOG_DIR/openclaw.log" ]; then
    mv "$LOG_DIR/openclaw.log" "$LOG_DIR/openclaw.log.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
fi

# 测试 Telegram API
info "测试 Telegram API..."
if curl -s --proxy "$HTTP_PROXY" --connect-timeout 5 \
    "https://api.telegram.org" > /dev/null 2>&1; then
    log "Telegram API 可访问"
else
    warn "Telegram API 测试失败，继续启动..."
fi

# 启动 OpenClaw（带代理配置）
info "启动 OpenClaw..."
env HTTP_PROXY="http://127.0.0.1:7890" \
    HTTPS_PROXY="http://127.0.0.1:7890" \
    NODE_PATH="/usr/lib/node_modules/openclaw/node_modules" \
    NODE_OPTIONS="--import=/root/openclaw/proxy-bootstrap.mjs" \
    nohup "$OPENCLAW_CMD" gateway > "$LOG_DIR/openclaw.log" 2>&1 &

# 等待就绪
info "等待初始化..."
for i in $(seq 1 30); do
    sleep 1
    if "$OPENCLAW_CMD" health 2>/dev/null | grep -q "Telegram:"; then
        log "OpenClaw 启动成功"
        info "日志: $LOG_DIR/openclaw.log"
        echo ""
        info "当前状态："
        "$OPENCLAW_CMD" health 2>/dev/null | grep -E "Telegram|Agents|model" | sed 's/^/  /'
        exit 0
    fi
    echo -n "."
done

# 超时处理
if is_running "openclaw"; then
    warn "启动时间较长，请稍后手动检查"
    info "查看日志: tail -f $LOG_DIR/openclaw.log"
else
    err "OpenClaw 启动失败"
    info "查看错误: tail -n 30 $LOG_DIR/openclaw.log"
    exit 1
fi
