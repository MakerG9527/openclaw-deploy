#!/bin/bash
# Mihomo 订阅管理脚本（优化版，可迁移）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# 配置路径
CONFIG_FILE="$MIHOMO_HOME/config.yaml"
SUB_FILE="$MIHOMO_HOME/subscription.url"
BACKUP_DIR="$MIHOMO_HOME/backups"

# 订阅转换 API
CONVERT_API="https://sub.xeton.dev/sub?target=clash&url="

url_encode() {
    python3 -c "import urllib.parse; print(urllib.parse.quote('''$1''', safe=''))" 2>/dev/null || echo "$1"
}

download_and_convert() {
    url="$1"
    temp_file="/tmp/mihomo_config_$(date +%s).yaml"
    
    info "下载订阅..."
    for i in 1 2 3; do
        if curl -sL --connect-timeout 10 --max-time 30 "$url" -o "$temp_file" 2>/dev/null; then
            break
        fi
        warn "第 $i 次下载失败，重试..."
        sleep 2
    done
    
    if [ ! -s "$temp_file" ]; then
        err "下载失败"
        rm -f "$temp_file"
        return 1
    fi
    
    # 检测格式
    if grep -q "^proxies:" "$temp_file" 2>/dev/null; then
        log "检测到 Clash 格式，无需转换"
    else
        info "尝试转换格式..."
        
        # 尝试 base64 解码（先解码，再检测）
        if base64 -d "$temp_file" > "${temp_file}.dec" 2>/dev/null; then
            mv "${temp_file}.dec" "$temp_file"
            log "Base64 解码成功"
        else
            rm -f "${temp_file}.dec"
        fi
        
        # 解码后再检测是否是 Clash 格式
        if ! grep -q "^proxies:" "$temp_file" 2>/dev/null; then
            info "使用在线服务转换为 Clash 格式..."
            
            # URL 编码
            enc_url=$(url_encode "$url")
            
            # 构建完整 URL（使用 insert=false 避免插入问题）
            convert_url="${CONVERT_API}${enc_url}&insert=false&config="
            
            info "转换 URL: ${convert_url:0:80}..."
            
            if ! curl -sL --connect-timeout 15 --max-time 60 "$convert_url" -o "$temp_file" 2>/dev/null; then
                err "转换 API 请求失败"
                rm -f "$temp_file"
                return 1
            fi
            
            # 检查转换结果
            if ! grep -q "^proxies:" "$temp_file" 2>/dev/null; then
                err "转换后的文件格式不正确"
                err "响应内容: $(head -1 "$temp_file")"
                rm -f "$temp_file"
                return 1
            fi
            
            log "转换成功"
        fi
    fi
    
    # 检查并确保配置完整性
    info "检查配置完整性..."
    
    # 1. 确保有端口配置
    port=${MIHOMO_HTTP_PORT:-7890}
    if ! grep -qE "^(port:|mixed-port:)" "$temp_file"; then
        info "添加混合端口配置: $port"
        echo "" >> "$temp_file"
        echo "mixed-port: $port" >> "$temp_file"
    fi
    
    # 2. 确保有 socks 端口（如果配置了）
    socks_port=${MIHOMO_SOCKS_PORT:-7891}
    if ! grep -qE "^(socks-port:)" "$temp_file"; then
        if [ -n "$socks_port" ]; then
            echo "socks-port: $socks_port" >> "$temp_file"
        fi
    fi
    
    # 3. 其他基本配置
    grep -q "^allow-lan:" "$temp_file" || echo "allow-lan: true" >> "$temp_file"
    grep -q "^mode:" "$temp_file" || echo "mode: Rule" >> "$temp_file"
    grep -q "^log-level:" "$temp_file" || echo "log-level: info" >> "$temp_file"
    grep -q "^external-controller:" "$temp_file" || \
        echo "external-controller: ${MIHOMO_CONTROLLER:-127.0.0.1:9090}" >> "$temp_file"
    
    # 4. 处理 GEOIP 问题（如果之前有禁用 GEOIP 的需求）
    # 检查是否有 GEOIP 规则但缺少 geoip-url 配置可能导致问题
    if grep -q "GEOIP" "$temp_file" 2>/dev/null; then
        # 检查是否已配置 geo-url
        if ! grep -q "geo-url:" "$temp_file"; then
            info "检测到 GEOIP 规则，添加 GeoIP 数据库配置..."
            # 在文件开头添加 geo 配置
            echo "geo-url: \"https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat\"" > "${temp_file}.tmp"
            cat "$temp_file" >> "${temp_file}.tmp"
            mv "${temp_file}.tmp" "$temp_file"
        fi
    fi
    
    # 5. 确保有规则部分
    if ! grep -q "^rules:" "$temp_file"; then
        warn "配置缺少规则部分，添加默认规则..."
        echo "" >> "$temp_file"
        echo "rules:" >> "$temp_file"
        echo "  - MATCH,PROXY" >> "$temp_file"
    fi
    
    # 6. 询问是否禁用 GEOIP（默认禁用）
    if grep -q "GEOIP" "$temp_file" 2>/dev/null; then
        echo ""
        info "检测到 GEOIP 规则"
        if ask_yesno "是否禁用 GEOIP 规则? (可能导致配置验证警告)" "y"; then
            info "禁用 GEOIP 规则..."
            # 删除所有包含 GEOIP 的行
            sed -i '/GEOIP/d' "$temp_file"
            log "已禁用 GEOIP 规则"
        fi
    fi
    
    # 验证配置
    if check_cmd mihomo; then
        info "验证配置..."
        if ! mihomo -t -f "$temp_file" > /dev/null 2>&1; then
            warn "配置验证有警告，显示详细信息..."
            mihomo -t -f "$temp_file" 2>&1 | head -10
            
            if ! ask_yesno "配置验证有警告，是否继续应用"; then
                rm -f "$temp_file"
                return 1
            fi
        else
            log "配置验证通过"
        fi
    fi
    
    # 备份并应用
    backup_file "$CONFIG_FILE" "$BACKUP_DIR"
    mv "$temp_file" "$CONFIG_FILE"
    echo "$url" > "$SUB_FILE"
    
    log "配置已应用到: $CONFIG_FILE"
    info "文件大小: $(ls -lh "$CONFIG_FILE" | awk '{print $5}')"
    info "代理节点数: $(grep -c "^  - {" "$CONFIG_FILE" 2>/dev/null || echo "未知")"
    
    return 0
}

list_backups() {
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        warn "没有可用的备份"
        return 1
    fi
    
    banner "可用备份"
    local i=1
    for f in $(ls -t "$BACKUP_DIR"/*.yaml 2>/dev/null); do
        [ -f "$f" ] || continue
        local size=$(ls -lh "$f" | awk '{print $5}')
        local mtime=$(stat -c %y "$f" 2>/dev/null | cut -d'.' -f1)
        echo "  $i. $(basename "$f") [$size] $mtime"
        ((i++))
    done
}

restore_backup() {
    list_backups || return 1
    
    echo ""
    read -p "选择要恢复的备份 [1-$((i-1))，0取消]: " choice
    
    [ "$choice" = "0" ] && return 0
    
    local selected=$(ls -t "$BACKUP_DIR"/*.yaml 2>/dev/null | sed -n "${choice}p")
    if [ -f "$selected" ]; then
        backup_file "$CONFIG_FILE" "$BACKUP_DIR"
        cp "$selected" "$CONFIG_FILE"
        log "已恢复: $(basename "$selected")"
        
        if confirm "立即重启 Mihomo?"; then
            if is_running "mihomo"; then
                killall mihomo 2>/dev/null || true
                sleep 1
            fi
            "$SCRIPT_DIR/start-mihomo.sh"
        fi
    else
        err "无效选择"
    fi
}

menu() {
    while true; do
        banner "Mihomo 订阅管理"
        echo "1. 更换订阅链接"
        echo "2. 更新当前订阅"
        echo "3. 重启 Mihomo"
        echo "4. 恢复备份配置"
        echo "5. 查看当前订阅"
        echo "0. 退出"
        echo ""
        read -p "选择: " c
        
        case $c in
            1)
                read -p "订阅链接: " url
                if [ -n "$url" ]; then
                    download_and_convert "$url" && {
                        if confirm "立即重启 Mihomo?"; then
                            is_running "mihomo" && killall mihomo 2>/dev/null
                            sleep 1
                            "$SCRIPT_DIR/start-mihomo.sh"
                        fi
                    }
                fi
                ;;
            2)
                if [ -f "$SUB_FILE" ]; then
                    url=$(cat "$SUB_FILE")
                    info "更新订阅: $url"
                    download_and_convert "$url" && {
                        if is_running "mihomo"; then
                            killall mihomo 2>/dev/null
                            sleep 1
                            "$SCRIPT_DIR/start-mihomo.sh"
                        fi
                    }
                else
                    err "无订阅文件，请先添加订阅"
                fi
                ;;
            3)
                info "重启 Mihomo..."
                is_running "mihomo" && killall mihomo 2>/dev/null
                sleep 1
                "$SCRIPT_DIR/start-mihomo.sh"
                ;;
            4) restore_backup ;;
            5)
                if [ -f "$SUB_FILE" ]; then
                    info "当前订阅: $(cat "$SUB_FILE")"
                else
                    warn "无订阅文件"
                fi
                ;;
            0) exit 0 ;;
            *) err "无效选择" ;;
        esac
        echo ""
        read -p "按回车继续..."
    done
}

# 直接运行菜单
menu
