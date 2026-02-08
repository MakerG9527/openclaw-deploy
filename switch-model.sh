#!/bin/bash
# 模型切换脚本（优化版，可迁移）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

CONFIG_FILE="$OPENCLAW_HOME/openclaw.json"

show_help() {
    cat << EOF
用法: $0 <模型名称> [选项]

选项:
  -l, --list     列出可用模型
  -f, --force    强制切换（不检查模型是否存在）
  -h, --help     显示帮助

示例:
  $0 -l                    # 列出模型
  $0 qwen3-vl:8b           # 切换到指定模型
  $0 -f my-model           # 强制切换
EOF
}

list_models() {
    banner "可用模型"
    
    if ! curl -s --connect-timeout 5 "$OLLAMA_HOST/api/tags" > /dev/null 2>&1; then
        err "无法连接到 Ollama ($OLLAMA_HOST)"
        info "请检查："
        info "  1. Ollama 服务是否运行"
        info "  2. 防火墙是否放行 11434 端口"
        info "  3. 网络连接是否正常"
        exit 1
    fi
    
    models=$(curl -s "$OLLAMA_HOST/api/tags" 2>/dev/null | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
    
    if [ -z "$models" ]; then
        warn "未获取到模型列表"
        return 1
    fi
    
    echo "$models" | while read -r model; do
        [ -n "$model" ] && echo "  • $model"
    done
    
    echo ""
    info "当前配置:"
    if [ -f "$CONFIG_FILE" ]; then
        grep '"primary"' "$CONFIG_FILE" 2>/dev/null | head -1 | sed 's/.*"primary": "\(.*\)".*/  模型: \1/'
    fi
}

check_model() {
    model=$1
    curl -s "$OLLAMA_HOST/api/tags" 2>/dev/null | grep -q "\"name\":\"$model\""
}

switch_model() {
    new_model=$1
    force=$2
    
    if [ ! -f "$CONFIG_FILE" ]; then
        err "配置文件不存在: $CONFIG_FILE"
        exit 1
    fi
    
    # 备份
    backup_file "$CONFIG_FILE"
    
    # 检查模型（如果不是强制模式）
    if [ "$force" != "true" ]; then
        if ! check_model "$new_model"; then
            warn "模型 '$new_model' 未在 Ollama 中找到"
            if ! confirm "强制切换?"; then
                info "已取消"
                exit 0
            fi
        fi
    fi
    
    banner "切换模型"
    info "目标模型: $new_model"
    
    # 获取当前模型
    old_model=$(grep '"primary"' "$CONFIG_FILE" 2>/dev/null | head -1 | sed 's/.*"primary": "\(.*\)".*/\1/')
    info "当前模型: ${old_model:-未知}"
    
    # 修改配置（使用更安全的方式）
    temp_file=$(mktemp)
    
    # 尝试使用 jq（如果安装了）
    if check_cmd jq; then
        jq --arg model "ollama/$new_model" '
            .ollama.primary = $model |
            .ollama.agents[0].id = ($model | split("/")[-1]) |
            .ollama.agents[0].name = ($model | split("/")[-1])
        ' "$CONFIG_FILE" > "$temp_file" 2>/dev/null
    else
        # 使用 sed（兼容性更好）
        cp "$CONFIG_FILE" "$temp_file"
        safe_sed "s|\"primary\": \"[^\"]*\"|\"primary\": \"ollama/$new_model\"|" "$temp_file"
        safe_sed "s|\"id\": \"[^\"]*\",|\"id\": \"$new_model\",|" "$temp_file"
    fi
    
    # 验证修改
    if grep -q "\"primary\": \"ollama/$new_model\"" "$temp_file"; then
        mv "$temp_file" "$CONFIG_FILE"
        log "配置已更新"
    else
        rm -f "$temp_file"
        err "修改失败，配置未更改"
        exit 1
    fi
    
    # 重启
    echo ""
    if confirm "是否立即重启 OpenClaw?"; then
        "$SCRIPT_DIR/stop-all.sh" > /dev/null 2>&1
        sleep 2
        "$SCRIPT_DIR/start-openclaw.sh"
    fi
}

# 主程序
case "${1:-}" in
    -h|--help) show_help; exit 0 ;;
    -l|--list) list_models; exit 0 ;;
    -f|--force) 
        [ -z "${2:-}" ] && { err "需要指定模型"; exit 1; }
        switch_model "$2" "true"
        ;;
    "") err "请指定模型名称"; show_help; exit 1 ;;
    *) switch_model "$1" "false" ;;
esac
