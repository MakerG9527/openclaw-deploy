#!/bin/bash
# Mihomo 启动脚本（优化版，可迁移）

# 加载公共库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/common.sh"

banner "启动 Mihomo 代理"

# 检查是否已在运行
if is_running "mihomo"; then
    log "Mihomo 已在运行 (PID: $(get_pid mihomo))"
    exit 0
fi

# 检查配置文件
if [ ! -f "$MIHOMO_HOME/config.yaml" ]; then
    err "配置文件不存在: $MIHOMO_HOME/config.yaml"
    info "请先运行: $SCRIPT_DIR/mihomo-sub.sh 添加订阅"
    exit 1
fi

# 检查 mihomo 命令
if ! check_cmd mihomo; then
    err "未找到 mihomo 命令"
    info "请安装: https://github.com/MetaCubeX/mihomo"
    exit 1
fi

# 创建日志目录
mkdir -p "$LOG_DIR"

# 备份旧日志（可选）
if [ -f "$LOG_DIR/mihomo.log" ]; then
    mv "$LOG_DIR/mihomo.log" "$LOG_DIR/mihomo.log.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
fi

# 启动 Mihomo
info "启动 Mihomo..."
nohup mihomo -d "$MIHOMO_HOME" > "$LOG_DIR/mihomo.log" 2>&1 &
MIHOMO_PID=$!

# 等待启动
sleep 2

if is_running "mihomo"; then
    log "Mihomo 启动成功 (PID: $(get_pid mihomo))"
    info "HTTP 代理: $HTTP_PROXY"
    info "日志: $LOG_DIR/mihomo.log"
    
    # 测试代理
    info "测试代理连通性..."
    sleep 3
    HTTP_CODE=$(test_proxy "$HTTP_PROXY" "https://www.google.com")
    
    if [ -z "$HTTP_CODE" ] || [ "$HTTP_CODE" = "000" ]; then
        warn "代理测试失败 (无响应)，但服务已启动"
        info "5秒后再次测试..."
        sleep 5
        HTTP_CODE=$(test_proxy "$HTTP_PROXY" "https://www.google.com")
    fi
    
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
        log "代理测试通过 (HTTP $HTTP_CODE)"
    elif [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
        warn "代理测试返回 HTTP $HTTP_CODE"
    else
        warn "代理测试失败，但 Mihomo 已启动"
        info "请稍后手动测试: test-proxy"
    fi
else
    err "Mihomo 启动失败"
    info "查看日志: tail -n 20 $LOG_DIR/mihomo.log"
    exit 1
fi
