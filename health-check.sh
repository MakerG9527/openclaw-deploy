#!/bin/bash
# 健康检查脚本 - 检查所有组件状态

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

banner "OpenClaw 健康检查"

# 检查结果汇总
ERRORS=0
WARNINGS=0

# 检查系统资源
check_system() {
    echo "📊 系统资源:"
    
    # 内存
    mem_info=$(free -h 2>/dev/null | grep Mem) || true
    if [ -n "$mem_info" ]; then
        mem_used=$(echo "$mem_info" | awk '{print $3}')
        mem_total=$(echo "$mem_info" | awk '{print $2}')
        info "内存: $mem_used / $mem_total"
    fi
    
    # 磁盘
    disk_usage=$(df -h / 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%') || true
    if [ -n "$disk_usage" ] && [ "$disk_usage" -eq "$disk_usage" ] 2>/dev/null; then
        if [ "$disk_usage" -gt 90 ]; then
            err "磁盘使用率过高: ${disk_usage}%"
            ERRORS=$((ERRORS + 1))
        elif [ "$disk_usage" -gt 80 ]; then
            warn "磁盘使用率较高: ${disk_usage}%"
            WARNINGS=$((WARNINGS + 1))
        else
            log "磁盘使用率: ${disk_usage}%"
        fi
    fi
    
    # CPU温度（树莓派）
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        temp=$(cat /sys/class/thermal/thermal_zone0/temp) || true
        if [ -n "$temp" ]; then
            temp_c=$((temp / 1000)) || true
            if [ "$temp_c" -gt 80 ]; then
                err "CPU温度过高: ${temp_c}°C"
                ERRORS=$((ERRORS + 1))
            elif [ "$temp_c" -gt 70 ]; then
                warn "CPU温度较高: ${temp_c}°C"
                WARNINGS=$((WARNINGS + 1))
            else
                log "CPU温度: ${temp_c}°C"
            fi
        fi
    fi
    
    echo ""
}

# 检查服务
check_services() {
    echo "🔧 服务状态:"
    
    # Mihomo
    if is_running "mihomo"; then
        log "Mihomo: 运行中"
        
        # 测试代理
        proxy_code=$(test_proxy "$HTTP_PROXY" "https://www.google.com")
        if [ "$proxy_code" = "200" ] || [ "$proxy_code" = "302" ]; then
            log "代理连接: 正常"
        else
            err "代理连接: 失败 (HTTP $proxy_code)"
            ERRORS=$((ERRORS + 1))
        fi
    else
        err "Mihomo: 未运行"
        ERRORS=$((ERRORS + 1))
    fi
    
    # OpenClaw
    if is_running "openclaw"; then
        log "OpenClaw: 运行中"
        
        # 健康检查
        cmd="${OPENCLAW_BIN:-$(command -v openclaw)}"
        if "$cmd" health 2>/dev/null | grep -q "Telegram:"; then
            log "OpenClaw API: 正常"
        else
            warn "OpenClaw API: 异常"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        err "OpenClaw: 未运行"
        ERRORS=$((ERRORS + 1))
    fi
    
    echo ""
}

# 检查配置
check_configs() {
    echo "📋 配置文件:"
    
    # Mihomo配置
    if [ -f "$MIHOMO_HOME/config.yaml" ]; then
        log "Mihomo配置: 存在"
        
        # 检查订阅是否过期（简单检查文件修改时间）
        config_age=$(( ($(date +%s) - $(stat -c %Y "$MIHOMO_HOME/config.yaml" 2>/dev/null || echo 0)) / 86400 ))
        if [ "$config_age" -gt 30 ]; then
            warn "配置已 ${config_age} 天未更新，建议检查订阅"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        err "Mihomo配置: 不存在"
        ERRORS=$((ERRORS + 1))
    fi
    
    # OpenClaw配置
    if [ -f "$OPENCLAW_HOME/openclaw.json" ]; then
        log "OpenClaw配置: 存在"
        
        # 检查 Ollama 连接
        if curl -s --connect-timeout 5 "$OLLAMA_HOST/api/tags" > /dev/null 2>&1; then
            log "Ollama连接: 正常 ($OLLAMA_HOST)"
        else
            err "Ollama连接: 失败 ($OLLAMA_HOST)"
            ERRORS=$((ERRORS + 1))
        fi
    else
        err "OpenClaw配置: 不存在"
        ERRORS=$((ERRORS + 1))
    fi
    
    # .env文件
    if [ -f "$SCRIPT_DIR/.env" ]; then
        log "环境变量: 已配置"
    else
        warn "环境变量: 未配置 (.env不存在)"
        WARNINGS=$((WARNINGS + 1))
    fi
    
    echo ""
}

# 检查日志
check_logs() {
    echo "📜 日志检查:"
    
    # 检查错误日志
    for log in "$LOG_DIR/openclaw.log" "$LOG_DIR/mihomo.log"; do
        if [ -f "$log" ]; then
            log_size=$(ls -lh "$log" 2>/dev/null | awk '{print $5}')
            info "$(basename "$log"): $log_size"
            
            # 检查最近是否有错误
            recent_errors=$(grep -i "error\|fatal\|panic" "$log" 2>/dev/null | tail -5)
            if [ -n "$recent_errors" ]; then
                warn "$(basename "$log") 中发现最近错误:"
                echo "$recent_errors" | sed 's/^/  /'
            fi
        else
            warn "$(basename "$log"): 不存在"
        fi
    done
    
    echo ""
}

# 自动修复（可选）
auto_fix() {
    if [ $ERRORS -gt 0 ] && confirm "是否尝试自动修复?"; then
        banner "自动修复"
        
        # 重启未运行的服务
        if ! is_running "mihomo"; then
            info "启动 Mihomo..."
            "$SCRIPT_DIR/start-mihomo.sh"
        fi
        
        if ! is_running "openclaw"; then
            info "启动 OpenClaw..."
            "$SCRIPT_DIR/start-openclaw.sh"
        fi
        
        log "修复完成，请重新运行健康检查"
    fi
}

# 主程序
case "${1:-}" in
    -f|--fix)
        check_system
        check_services
        check_configs
        check_logs
        auto_fix
        ;;
    -q|--quick)
        # 快速检查，只显示结果
        is_running "mihomo" && is_running "openclaw" && \
        [ "$(test_proxy)" = "200" ] && echo "OK" || echo "ERROR"
        ;;
    *)
        check_system
        check_services
        check_configs
        check_logs
        
        # 汇总
        banner "检查结果"
        if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
            log "所有检查通过 ✓"
        else
            [ $ERRORS -gt 0 ] && err "发现 $ERRORS 个错误"
            [ $WARNINGS -gt 0 ] && warn "发现 $WARNINGS 个警告"
            info "运行 '$0 --fix' 尝试自动修复"
        fi
        ;;
esac
