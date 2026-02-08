#!/bin/bash
# Ollama 主机切换脚本（优化版，可迁移）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

CONFIG_FILE="$OPENCLAW_HOME/openclaw.json"
ENV_FILE="$SCRIPT_DIR/.env"

show_help() {
    cat << EOF
用法: $0 [选项] [新地址]

选项:
  -c, --current    显示当前配置
  -t, --test       测试连接
  -l, --local      切换到本地 (127.0.0.1:11434)
  -f, --force      强制切换
  -h, --help       显示帮助

地址格式: IP:端口 或 域名:端口
示例: 192.168.1.100:11434

EOF
}

get_current_host() {
    if [ -f "$CONFIG_FILE" ]; then
        grep -o '"baseUrl": "http://[^"]*"' "$CONFIG_FILE" 2>/dev/null | \
            head -1 | sed 's/.*"http:\/\/\([^"]*\)".*/\1/' | sed 's|/v1||'
    fi
}

test_connection() {
    host="${1:-$(get_current_host)}"
    banner "测试连接"
    info "目标: http://$host"
    
    if curl -s --connect-timeout 5 "http://$host/api/tags" > /dev/null 2>&1; then
        log "连接成功"
        models=$(curl -s "http://$host/api/tags" 2>/dev/null | \
            grep -o '"name":"[^"]*"' | cut -d'"' -f4 | head -5)
        info "可用模型:"
        echo "$models" | sed 's/^/  - /'
        return 0
    else
        err "连接失败"
        info "请检查："
        info "  1. Ollama 服务是否运行"
        info "  2. 防火墙是否放行端口"
        return 1
    fi
}

update_all_configs() {
    new_host=$1
    
    # 1. 更新 openclaw.json
    if [ -f "$CONFIG_FILE" ]; then
        backup_file "$CONFIG_FILE"
        safe_sed "s|\"baseUrl\": \"http://[^\"]*\"|\"baseUrl\": \"http://$new_host/v1\"|" "$CONFIG_FILE"
        log "已更新 $CONFIG_FILE"
    fi
    
    # 2. 更新 .env 文件
    if [ -f "$ENV_FILE" ]; then
        safe_sed "s|OLLAMA_HOST=.*|OLLAMA_HOST=http://$new_host|" "$ENV_FILE"
        log "已更新 $ENV_FILE"
    fi
    
    # 3. 更新其他脚本中的硬编码（向后兼容）
    for script in switch-model.sh start-openclaw.sh; do
        script_path="$SCRIPT_DIR/$script"
        if [ -f "$script_path" ]; then
            # 注释掉或更新硬编码的 OLLAMA_HOST
            if grep -q "OLLAMA_HOST=" "$script_path"; then
                safe_sed "s|OLLAMA_HOST=\"http://[^\"]*\"|# OLLAMA_HOST (使用 .env)|" "$script_path" 2>/dev/null || true
            fi
        fi
    done
}

switch_host() {
    new_host=$1
    force=${2:-false}
    
    # 验证格式
    if ! echo "$new_host" | grep -qE '^[0-9a-zA-Z._-]+:[0-9]+$'; then
        err "地址格式不正确: $new_host"
        info "正确格式: IP:端口 或 域名:端口"
        exit 1
    fi
    
    banner "切换 Ollama 主机"
    info "当前: $(get_current_host)"
    info "目标: $new_host"
    echo ""
    
    # 测试连接
    if [ "$force" != "true" ]; then
        if ! test_connection "$new_host"; then
            if ! confirm "连接测试失败，强制切换?"; then
                info "已取消"
                exit 0
            fi
        fi
    fi
    
    # 更新所有配置
    update_all_configs "$new_host"
    
    log "配置更新完成"
    
    # 询问重启
    echo ""
    if confirm "立即重启 OpenClaw?"; then
        "$SCRIPT_DIR/stop-all.sh" > /dev/null 2>&1
        sleep 2
        "$SCRIPT_DIR/start-openclaw.sh"
    fi
}

# 主程序
case "${1:-}" in
    -c|--current)
        current=$(get_current_host)
        if [ -n "$current" ]; then
            info "当前 Ollama: $current"
        else
            warn "未找到配置"
        fi
        exit 0
        ;;
    -t|--test)
        test_connection
        exit $?
        ;;
    -l|--local)
        switch_host "127.0.0.1:11434"
        ;;
    -h|--help)
        show_help
        exit 0
        ;;
    -f|--force)
        [ -z "${2:-}" ] && { err "需要指定地址"; exit 1; }
        switch_host "$2" "true"
        ;;
    "")
        err "请指定地址或使用选项"
        show_help
        exit 1
        ;;
    *)
        switch_host "$1"
        ;;
esac
