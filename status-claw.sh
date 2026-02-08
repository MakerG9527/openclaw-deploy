#!/bin/bash
# 服务状态查看脚本（优化版）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

banner "服务状态"

# Mihomo 状态
echo "📡 Mihomo 代理:"
if is_running "mihomo"; then
    log "运行中 (PID: $(get_pid mihomo))"
    info "HTTP代理: $HTTP_PROXY"
    info "Socks代理: http://127.0.0.1:${MIHOMO_SOCKS_PORT:-7891}"
    info "控制器: http://${MIHOMO_CONTROLLER:-127.0.0.1:9090}"
    
    # 测试连通性
    code=$(test_proxy)
    if [ "$code" = "200" ] || [ "$code" = "302" ]; then
        log "代理正常 (HTTP $code)"
    else
        warn "代理异常 (HTTP $code)"
    fi
else
    err "未运行"
fi

echo ""

# OpenClaw 状态
echo "🤖 OpenClaw:"
if is_running "openclaw"; then
    log "运行中"
    
    if check_cmd openclaw || [ -x "$OPENCLAW_BIN" ]; then
        cmd="${OPENCLAW_BIN:-$(command -v openclaw)}"
        "$cmd" health 2>/dev/null | grep -E "Telegram|Agents|model" | sed 's/^/  /' || warn "健康检查失败"
    fi
else
    err "未运行"
fi

echo ""

# 日志信息
echo "📝 日志位置:"
info "Mihomo:   $LOG_DIR/mihomo.log"
info "OpenClaw: $LOG_DIR/openclaw.log"

# 快速查看最后错误
echo ""
if [ -f "$LOG_DIR/openclaw.log" ]; then
    last_error=$(grep -i "error\|失败\|failed" "$LOG_DIR/openclaw.log" 2>/dev/null | tail -1)
    if [ -n "$last_error" ]; then
        warn "最近错误:"
        echo "  $last_error"
    fi
fi
