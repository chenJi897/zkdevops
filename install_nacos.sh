#!/bin/bash

# 简化版Nacos安装脚本（包含Java环境检查）
# 作者：chenJi897
# 日期：2025-04-15

# 设置变量
NACOS_VERSION="2.5.1"
NACOS_FILE="nacos-server-${NACOS_VERSION}.zip"
CURRENT_DIR=$(pwd)                            # 当前目录
INSTALL_DIR="/usr/local"                      # Nacos安装目录
NACOS_HOME="${INSTALL_DIR}/nacos"             # Nacos主目录
SERVICE_NAME="nacos"                          # Systemd服务名称
MIN_JAVA_VERSION="1.8.0"                      # 最低Java版本要求

# 输出彩色文本的函数
green() {
    echo -e "\033[32m$1\033[0m"
}

red() {
    echo -e "\033[31m$1\033[0m"
}

yellow() {
    echo -e "\033[33m$1\033[0m"
}

# 检查是否以root用户运行
if [ "$EUID" -ne 0 ]; then
  red "请以root用户运行此脚本"
  exit 1
fi

green "====== 开始安装 Nacos ${NACOS_VERSION} ======"

# 检查Java环境
yellow "正在检查Java环境..."
if ! command -v java &> /dev/null; then
    red "错误: 未检测到Java环境，Nacos需要Java 8或更高版本"
    red "请先安装JDK，可以使用之前的JDK安装脚本"
    exit 1
else
    # 检查Java版本
    JAVA_VERSION=$(java -version 2>&1 | head -n 1 | awk -F '"' '{print $2}')
    green "检测到Java版本: $JAVA_VERSION"
    
    # 简单版本比较，确保是Java 8或更高版本
    if [[ "$(echo -e "$MIN_JAVA_VERSION\n$JAVA_VERSION" | sort -V | head -n1)" != "$MIN_JAVA_VERSION" ]]; then
        red "错误: Java版本过低，Nacos需要Java 8或更高版本"
        red "当前版本: $JAVA_VERSION，最低要求: $MIN_JAVA_VERSION"
        exit 1
    fi
fi

# 检查当前目录下是否存在Nacos文件
if [ ! -f "${CURRENT_DIR}/${NACOS_FILE}" ]; then
    red "错误: Nacos 文件 ${CURRENT_DIR}/${NACOS_FILE} 不存在，请确保压缩包在当前目录"
    exit 1
fi

# 检查是否已安装unzip
if ! command -v unzip &> /dev/null; then
    yellow "未找到unzip命令，正在安装..."
    if command -v yum &> /dev/null; then
        yum install -y unzip
    elif command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y unzip
    else
        red "无法安装unzip，请手动安装后重试"
        exit 1
    fi
fi

# 解压Nacos文件
green "正在解压Nacos文件到 ${INSTALL_DIR}..."
mkdir -p ${INSTALL_DIR}
unzip -q "${CURRENT_DIR}/${NACOS_FILE}" -d "${INSTALL_DIR}"

# 确保目录名称正确
if [ ! -d "${NACOS_HOME}" ]; then
    # 如果解压后的目录名称不是nacos，可能需要重命名
    EXTRACTED_DIR=$(find ${INSTALL_DIR} -maxdepth 1 -name "nacos*" -type d | head -n 1)
    if [ -n "${EXTRACTED_DIR}" ]; then
        mv "${EXTRACTED_DIR}" "${NACOS_HOME}"
        green "已将 ${EXTRACTED_DIR} 重命名为 ${NACOS_HOME}"
    else
        red "找不到解压后的Nacos目录，请检查解压结果"
        exit 1
    fi
fi

# 给启动脚本添加执行权限
chmod +x ${NACOS_HOME}/bin/*.sh

# 创建systemd服务文件
green "正在创建systemd服务..."
cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Nacos Service
After=network.target

[Service]
Type=forking
ExecStart=${NACOS_HOME}/bin/startup.sh -m standalone
ExecStop=${NACOS_HOME}/bin/shutdown.sh
Restart=on-failure
RestartSec=30
LimitNOFILE=65535
WorkingDirectory=${NACOS_HOME}

[Install]
WantedBy=multi-user.target
EOF

# 重新加载systemd配置
green "正在重载systemd配置..."
systemctl daemon-reload

# 启动Nacos服务
green "正在启动Nacos服务..."
systemctl enable "${SERVICE_NAME}.service"
systemctl start "${SERVICE_NAME}.service"

# 检查服务状态
sleep 10
if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    green "Nacos服务已成功启动!"
    green "服务访问地址: http://$(hostname -I | awk '{print $1}'):8848/nacos"
    green "默认用户名/密码: nacos/nacos"
else
    red "Nacos服务启动失败，请检查日志:"
    red "journalctl -u ${SERVICE_NAME}.service"
    red "或查看 ${NACOS_HOME}/logs/ 目录下的日志文件"
    
    yellow "提示: 如果启动失败，可能是因为端口冲突或JVM内存设置不当"
    yellow "请检查 ${NACOS_HOME}/logs/ 目录下的日志获取详细错误信息"
    yellow "也可以尝试手动启动查看输出: ${NACOS_HOME}/bin/startup.sh -m standalone"
fi

# 打印使用说明
green "====== Nacos ${NACOS_VERSION} 安装完成 ======"
yellow "Nacos 管理命令:"
echo "启动: systemctl start ${SERVICE_NAME}"
echo "停止: systemctl stop ${SERVICE_NAME}"
echo "重启: systemctl restart ${SERVICE_NAME}"
echo "查看状态: systemctl status ${SERVICE_NAME}"
echo "查看日志: journalctl -u ${SERVICE_NAME} -f"
echo "或: tail -f ${NACOS_HOME}/logs/start.out"