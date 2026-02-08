#!/bin/bash
# Mihomo 安装脚本 - 支持自动下载和手动模式

set -e

ARCH=$(uname -m)
OS=$(uname -s)

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

echo "========================================"
echo "  Mihomo 安装脚本"
echo "========================================"
echo ""
echo "系统: $OS"
echo "架构: $ARCH"
echo ""

# 检测架构并返回下载文件名
get_arch_info() {
    case "$ARCH" in
        x86_64|amd64)
            echo "linux-amd64"
            ;;
        aarch64|arm64)
            echo "linux-arm64"
            ;;
        armv7l|armhf)
            echo "linux-armv7"
            ;;
        *)
            echo "unsupported"
            ;;
    esac
}

# 获取下载 URL
get_download_url() {
    local arch_suffix=$1
    local version=${2:-"v1.18.10"}
    echo "https://github.com/MetaCubeX/mihomo/releases/download/$version/mihomo-$arch_suffix-$version.gz"
}

# 获取最新版本
get_latest_version() {
    curl -sL --connect-timeout 10 \
        "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest" 2>/dev/null | \
        grep '"tag_name":' | head -1 | sed -E 's/.*"tag_name": "([^"]+)".*/\1/'
}

# 检查是否已安装
check_existing() {
    if command -v mihomo &> /dev/null; then
        info "检测到已安装的 Mihomo:"
        mihomo -v 2>&1 | head -1
        
        read -p "是否重新安装? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "取消安装"
            exit 0
        fi
    fi
}

# 自动下载模式
auto_download() {
    local arch_suffix=$1
    
    echo "[1/4] 获取版本信息..."
    VERSION=$(get_latest_version)
    if [ -z "$VERSION" ]; then
        VERSION="v1.18.10"
        warn "无法获取最新版本，使用默认版本: $VERSION"
    else
        info "最新版本: $VERSION"
    fi
    
    echo ""
    echo "[2/4] 下载 Mihomo..."
    
    # 尝试多个镜像源
    DOWNLOAD_URLS=(
        "$(get_download_url "$arch_suffix" "$VERSION")"
        "https://ghproxy.com/$(get_download_url "$arch_suffix" "$VERSION")"
        "https://mirror.ghproxy.com/$(get_download_url "$arch_suffix" "$VERSION")"
    )
    
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    DOWNLOAD_SUCCESS=false
    for url in "${DOWNLOAD_URLS[@]}"; do
        info "尝试下载: ${url:0:80}..."
        if curl -sL --connect-timeout 15 --max-time 60 "$url" -o mihomo.gz 2>/dev/null; then
            # 检查文件是否有效
            if file mihomo.gz | grep -q "gzip" && [ -s mihomo.gz ]; then
                log "下载成功"
                DOWNLOAD_SUCCESS=true
                break
            else
                warn "文件无效，尝试下一个源..."
                rm -f mihomo.gz
            fi
        else
            warn "下载失败，尝试下一个源..."
        fi
    done
    
    if [ "$DOWNLOAD_SUCCESS" = false ]; then
        return 1
    fi
    
    log "文件大小: $(ls -lh mihomo.gz | awk '{print $5}')"
    return 0
}

# 手动模式 - 用户指定文件
manual_install() {
    local arch_suffix=$1
    
    echo ""
    echo "========================================"
    echo "  手动安装模式"
    echo "========================================"
    echo ""
    warn "自动下载失败，请手动下载 Mihomo"
    echo ""
    echo "您的系统架构: $ARCH"
    echo "需要的文件: mihomo-${arch_suffix}-v*.gz"
    echo ""
    echo "下载地址:"
    echo "  https://github.com/MetaCubeX/mihomo/releases"
    echo ""
    echo "下载完成后，输入文件的完整路径"
    echo "例如: /home/user/Downloads/mihomo-linux-amd64-v1.18.10.gz"
    echo ""
    
    read -p "gz 文件路径 (或输入 'skip' 跳过): " file_path
    
    if [ "$file_path" = "skip" ] || [ -z "$file_path" ]; then
        err "用户取消安装"
        exit 1
    fi
    
    # 展开路径
    file_path="${file_path/#\~/$HOME}"
    
    if [ ! -f "$file_path" ]; then
        err "文件不存在: $file_path"
        exit 1
    fi
    
    # 检查文件类型
    if ! file "$file_path" | grep -q "gzip"; then
        err "文件不是有效的 gzip 压缩文件"
        exit 1
    fi
    
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    cp "$file_path" mihomo.gz
    log "已复制文件到临时目录"
    return 0
}

# 解压和安装
install_mihomo() {
    echo ""
    echo "[3/4] 解压 Mihomo..."
    
    if ! gunzip mihomo.gz; then
        err "解压失败"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    if [ ! -f "mihomo" ]; then
        err "解压后未找到 mihomo 文件"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    chmod +x mihomo
    log "解压成功"
    
    echo ""
    echo "[4/4] 安装 Mihomo..."
    
    if [ -w /usr/local/bin ]; then
        mv mihomo /usr/local/bin/
    else
        warn "需要 sudo 权限安装到 /usr/local/bin"
        sudo mv mihomo /usr/local/bin/
    fi
    
    log "安装完成"
    
    # 清理
    cd /
    rm -rf "$TEMP_DIR"
}

# 验证安装
verify_install() {
    echo ""
    echo "验证安装..."
    if command -v mihomo &> /dev/null; then
        log "Mihomo 安装成功"
        mihomo -v 2>&1 | head -1
    else
        err "安装失败，请检查"
        exit 1
    fi
}

# 配置代理选项
configure_proxy() {
    echo ""
    if ask_yesno "是否立即配置代理订阅?"; then
        if [ -f "./mihomo-sub.sh" ]; then
            ./mihomo-sub.sh
        else
            warn "未找到 mihomo-sub.sh，请手动运行"
            info "命令: ./mihomo-sub.sh"
        fi
    fi
}

# 询问函数
ask_yesno() {
    local prompt="$1"
    local default="${2:-y}"
    local result
    
    read -p "$prompt [Y/n]: " result
    result="${result:-$default}"
    
    [[ "$result" =~ ^[Yy]$ ]]
}

# ============ 主程序 ============

# 检查架构
ARCH_SUFFIX=$(get_arch_info)
if [ "$ARCH_SUFFIX" = "unsupported" ]; then
    err "不支持的架构: $ARCH"
    exit 1
fi

info "检测到的架构: $ARCH_SUFFIX"

# 检查现有安装
check_existing

# 尝试自动下载
TEMP_DIR=""
if auto_download "$ARCH_SUFFIX"; then
    log "自动下载成功"
else
    warn "自动下载失败，切换到手动模式"
    if ! manual_install "$ARCH_SUFFIX"; then
        exit 1
    fi
fi

# 安装
install_mihomo

# 验证
verify_install

# 创建配置目录
mkdir -p "$HOME/.config/mihomo"
mkdir -p "$HOME/.local/log"

# 可选：配置代理
echo ""
if [ -f "./mihomo-sub.sh" ]; then
    configure_proxy
fi

echo ""
echo "========================================"
echo "  Mihomo 安装完成!"
echo "========================================"
echo ""
echo "使用方法:"
echo "  mihomo -d ~/.config/mihomo  # 启动 Mihomo"
echo "  mihomo -v                   # 查看版本"
echo ""
echo "配置代理:"
echo "  ./mihomo-sub.sh             # 管理订阅"
echo ""
