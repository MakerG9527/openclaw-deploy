#!/bin/bash
# 停止所有服务脚本（优化版）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

banner "停止所有服务"

# 1. 停止 OpenClaw（优雅方式）
info "停止 OpenClaw..."
if check_cmd openclaw; then
    openclaw gateway stop 2>/dev/null && log "OpenClaw 已停止" || warn "OpenClaw 停止命令失败"
else
    warn "openclaw 命令不可用"
fi

sleep 1

# 2. 强制清理残留
info "清理残留进程..."
for proc in "openclaw" "mihomo"; do
    if is_running "$proc"; then
        pid=$(get_pid "$proc")
        info "停止 $proc (PID: $pid)"
        
        # 先尝试正常终止
        kill -TERM "$pid" 2>/dev/null || true
        sleep 1
        
        # 强制终止如果还在
        if is_running "$proc"; then
            kill -9 "$pid" 2>/dev/null || true
            sleep 1
        fi
    fi
done

# 3. 清理锁文件
rm -f /tmp/openclaw-gateway.pid /tmp/openclaw/*.lock 2>/dev/null || true

# 4. 最终确认
banner "最终确认"
any_running=false

for proc in "openclaw" "mihomo"; do
    if is_running "$proc"; then
        err "$proc 仍在运行 (PID: $(get_pid $proc))"
        any_running=true
    else
        log "$proc 已停止"
    fi
done

if [ "$any_running" = true ]; then
    exit 1
else
    log "所有服务已停止"
fi
