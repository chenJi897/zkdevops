#!/bin/bash

# JDK 8u161 离线安装脚本
# 用法: 将此脚本与jdk-8u161-linux-x64.tar.gz放在同一目录下执行

# 设置颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # 重置颜色

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# 检查脚本是否以root用户运行
if [ "$EUID" -ne 0 ]; then
    log_error "请以root用户运行此脚本"
fi

# 定义JDK文件名和安装目录
JDK_ARCHIVE="jdk-8u421-linux-x64.tar.gz"
INSTALL_DIR="/usr/local"
JDK_HOME="$INSTALL_DIR/jdk1.8.0_421"
JAVA_HOME="/usr/local/java"

# 检查是否已存在JDK文件
if [ ! -f "$JDK_ARCHIVE" ]; then
    log_error "未找到 $JDK_ARCHIVE，请确保将JDK压缩包放在与脚本相同的目录"
fi

# 检查是否已经安装了JDK
if [ -d "$JDK_HOME" ]; then
    log_warn "检测到JDK已经安装在 $JDK_HOME"
    read -p "是否重新安装? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "取消安装"
        exit 0
    fi
fi

# 安装JDK
log_info "开始安装JDK 8u161..."

# 解压JDK
log_info "解压JDK到 $INSTALL_DIR..."
tar -xzf "$JDK_ARCHIVE" -C "$INSTALL_DIR"

if [ ! -d "$JDK_HOME" ]; then
    log_error "解压失败，未找到 $JDK_HOME 目录"
fi

# 创建符号链接
log_info "创建符号链接 $JAVA_HOME..."
if [ -L "$JAVA_HOME" ]; then
    rm -f "$JAVA_HOME"
fi
ln -s "$JDK_HOME" "$JAVA_HOME"

# 配置环境变量
log_info "配置环境变量..."

# 创建profile文件
cat > /etc/profile.d/jdk.sh << EOF
export JAVA_HOME=$JAVA_HOME
export JRE_HOME=\$JAVA_HOME/jre
export CLASSPATH=.:\$JAVA_HOME/lib:\$JRE_HOME/lib
export PATH=\$JAVA_HOME/bin:\$PATH
EOF

# 设置权限
chmod +x /etc/profile.d/jdk.sh

# 激活环境变量
source /etc/profile.d/jdk.sh

# 验证安装
log_info "验证JDK安装..."
java_version=$(java -version 2>&1 | head -n 1)

if [[ $java_version == *"1.8.0_421"* ]]; then
    log_info "JDK 8u161 安装成功!"
    log_info "Java版本信息: $java_version"
    log_info "JAVA_HOME: $JAVA_HOME"
else
    log_warn "JDK安装可能不完整，请检查Java版本"
    log_info "当前Java版本信息: $java_version"
fi

log_info "安装完成。"
log_info "请运行以下命令使环境变量生效:"
log_info "  source /etc/profile"
log_info "或者重新登录系统后再使用java命令。"
