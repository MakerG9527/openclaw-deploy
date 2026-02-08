#!/bin/bash
# 一键启动所有服务（优化版）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

banner "OpenClaw + Mihomo 一键启动"

# 清理残留
info "清理残留进程..."
pkill -9 -f "openclaw gateway" 2>/dev/null || true
sleep 1

# 启动 Mihomo
if ! is_running "mihomo"; then
    info "[1/3] 启动 Mihomo..."
    "$SCRIPT_DIR/start-mihomo.sh" || {
        err "Mihomo 启动失败"
        exit 1
    }
    echo ""
else
    log "[1/3] Mihomo 已在运行"
fi

# 等待代理就绪
info "检测代理可用性..."
for i in $(seq 1 15); do
    if [ "$(test_proxy)" = "200" ] || [ "$(test_proxy)" = "302" ]; then
        log "代理已就绪"
        break
    fi
    echo -n "."
    sleep 1
done

# 启动 OpenClaw
info "[2/3] 启动 OpenClaw..."
"$SCRIPT_DIR/start-openclaw.sh" || {
    err "OpenClaw 启动失败"
    exit 1
}

echo ""
info "[3/3] 最终状态检查..."
sleep 3
echo "----------------------------------------"
"$SCRIPT_DIR/status-claw.sh"
echo "----------------------------------------"
