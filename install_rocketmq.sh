#!/bin/bash

# RocketMQ 4.9.7 离线安装脚本
# 用法: 将此脚本与rocketmq_0308.tar.gz放在同一目录下执行

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

# 配置变量
INSTALL_DIR="/opt"
ROCKETMQ_USER="rocketmq"
ROCKETMQ_GROUP="rocketmq"
ROCKETMQ_HOME="/opt/rocketmq"
NAMESRV_PORT=9876
BROKER_PORT=10911
CONSOLE_PORT=8080
SYSTEM_MEMORY=$(free -g | grep Mem | awk '{print $2}')

# 查找RocketMQ压缩包
ROCKETMQ_TARBALL=$(ls rocketmq_0308.tar.gz 2>/dev/null | head -n 1)
if [ -z "$ROCKETMQ_TARBALL" ]; then
    log_error "未找到RocketMQ压缩包，请确保将rocketmq_0308.tar.gz放在当前目录"
fi

log_info "找到RocketMQ安装包: $ROCKETMQ_TARBALL"

# 检查JDK环境
log_info "检查Java环境..."
if ! command -v java &> /dev/null; then
    log_error "未检测到Java环境，请先安装JDK 8+"
fi

java_version=$(java -version 2>&1 | head -n 1)
log_info "检测到Java: $java_version"

# 解压RocketMQ
log_info "解压RocketMQ..."
mkdir -p "$INSTALL_DIR/temp_extract"
tar -xzf "$ROCKETMQ_TARBALL" -C "$INSTALL_DIR/temp_extract"

# 查找解压后的RocketMQ目录
EXTRACT_DIR=$(find "$INSTALL_DIR/temp_extract" -name "rocketmq-all-4.9.7-bin-release" -type d | head -n 1)
if [ -z "$EXTRACT_DIR" ]; then
    log_error "解压失败，未找到rocketmq-all-4.9.7-bin-release目录"
fi

# 移动到正确位置
log_info "移动RocketMQ到安装目录..."
if [ -d "$ROCKETMQ_HOME" ]; then
    rm -rf "$ROCKETMQ_HOME"
fi
mv "$EXTRACT_DIR" "$ROCKETMQ_HOME"
rm -rf "$INSTALL_DIR/temp_extract"

# 创建必要的目录
log_info "创建日志和存储目录..."
mkdir -p "$ROCKETMQ_HOME/logs"
mkdir -p "$ROCKETMQ_HOME/store"
mkdir -p "$ROCKETMQ_HOME/store/commitlog"
mkdir -p "$ROCKETMQ_HOME/store/consumequeue"
mkdir -p "$ROCKETMQ_HOME/store/index"


# 配置JVM内存参数（根据系统内存自动调整）
log_info "根据系统内存配置JVM参数..."

# 配置NameServer JVM内存
if [ -f "$ROCKETMQ_HOME/bin/runserver.sh" ]; then
    if [ "$SYSTEM_MEMORY" -ge 16 ]; then
        NAMESRV_MEMORY="-Xms2g -Xmx2g -Xmn1g"
    elif [ "$SYSTEM_MEMORY" -ge 8 ]; then
        NAMESRV_MEMORY="-Xms1g -Xmx1g -Xmn512m"
    else
        NAMESRV_MEMORY="-Xms512m -Xmx512m -Xmn256m"
    fi
    
    log_info "设置NameServer内存为$NAMESRV_MEMORY"
    sed -i "s/-Xms[0-9]\+[gmk] -Xmx[0-9]\+[gmk]/$NAMESRV_MEMORY/g" "$ROCKETMQ_HOME/bin/runserver.sh"
fi

# 配置Broker JVM内存
if [ -f "$ROCKETMQ_HOME/bin/runbroker.sh" ]; then
    if [ "$SYSTEM_MEMORY" -ge 16 ]; then
        BROKER_MEMORY="-Xms4g -Xmx4g -Xmn2g"
    elif [ "$SYSTEM_MEMORY" -ge 8 ]; then
        BROKER_MEMORY="-Xms2g -Xmx2g -Xmn1g"
    else
        BROKER_MEMORY="-Xms1g -Xmx1g -Xmn512m"
    fi
    
    log_info "设置Broker内存为$BROKER_MEMORY"
    sed -i "s/-Xms[0-9]\+[gmk] -Xmx[0-9]\+[gmk]/$BROKER_MEMORY/g" "$ROCKETMQ_HOME/bin/runbroker.sh"
fi

# 配置Broker
log_info "配置Broker..."
if [ -f "$ROCKETMQ_HOME/conf/broker.conf" ]; then
    cp "$ROCKETMQ_HOME/conf/broker.conf" "$ROCKETMQ_HOME/conf/broker.conf.bak"
else
    touch "$ROCKETMQ_HOME/conf/broker.conf"
fi

# 获取主机IP
HOST_IP=$(hostname -I | awk '{print $1}')

# 写入基本Broker配置
cat > "$ROCKETMQ_HOME/conf/broker.conf" << EOF
# broker基本配置
brokerClusterName = DefaultCluster
brokerName = broker-a
brokerId = 0
deleteWhen = 04
fileReservedTime = 48
brokerRole = ASYNC_MASTER
flushDiskType = ASYNC_FLUSH
namesrvAddr = localhost:9876
listenPort = $BROKER_PORT
brokerIP1 = $HOST_IP
brokerIP2 = $HOST_IP

# 存储路径配置
storePathRootDir = $ROCKETMQ_HOME/store
storePathCommitLog = $ROCKETMQ_HOME/store/commitlog
storePathConsumeQueue = $ROCKETMQ_HOME/store/consumequeue
storePathIndex = $ROCKETMQ_HOME/store/index
storeCheckpoint = $ROCKETMQ_HOME/store/checkpoint
abortFile = $ROCKETMQ_HOME/store/abort
EOF

# 创建NameServer启动脚本
log_info "创建NameServer启动脚本..."
cat > "$ROCKETMQ_HOME/bin/start-namesrv.sh" << EOF
#!/bin/bash
export JAVA_HOME=$JAVA_HOME
cd \$(dirname \$0)
nohup sh mqnamesrv  > ../logs/namesrv.log 2>&1 &
echo \$! > ../logs/namesrv.pid
EOF
chmod +x "$ROCKETMQ_HOME/bin/start-namesrv.sh"

# 创建Broker启动脚本
log_info "创建Broker启动脚本..."
cat > "$ROCKETMQ_HOME/bin/start-broker.sh" << EOF
#!/bin/bash
export JAVA_HOME=$JAVA_HOME
cd \$(dirname \$0)
nohup sh mqbroker -c ../conf/broker.conf > ../logs/broker.log 2>&1 &
echo \$! > ../logs/broker.pid
EOF
chmod +x "$ROCKETMQ_HOME/bin/start-broker.sh"

# 创建停止脚本
log_info "创建停止脚本..."
cat > "$ROCKETMQ_HOME/bin/stop-all.sh" << EOF
#!/bin/bash
cd \$(dirname \$0)

# 停止Broker
if [ -f "../logs/broker.pid" ]; then
    BROKER_PID=\$(cat ../logs/broker.pid)
    if ps -p \$BROKER_PID > /dev/null; then
        kill \$BROKER_PID
        echo "Broker已停止 (PID: \$BROKER_PID)"
    else
        echo "Broker未运行"
    fi
    rm -f ../logs/broker.pid
fi

# 停止NameServer
if [ -f "../logs/namesrv.pid" ]; then
    NAMESRV_PID=\$(cat ../logs/namesrv.pid)
    if ps -p \$NAMESRV_PID > /dev/null; then
        kill \$NAMESRV_PID
        echo "NameServer已停止 (PID: \$NAMESRV_PID)"
    else
        echo "NameServer未运行"
    fi
    rm -f ../logs/namesrv.pid
fi
EOF
chmod +x "$ROCKETMQ_HOME/bin/stop-all.sh"

# 创建命令别名
log_info "创建命令别名..."
cat > /etc/profile.d/rocketmq.sh << EOF
# RocketMQ环境变量
export ROCKETMQ_HOME=$ROCKETMQ_HOME
export PATH=\$PATH:\$ROCKETMQ_HOME/bin
EOF
source /etc/profile.d/rocketmq.sh

# 创建systemd服务文件 - NameServer
log_info "创建NameServer系统服务..."
cat > /etc/systemd/system/rocketmq-namesrv.service << EOF
[Unit]
Description=RocketMQ NameServer Service
After=network.target

[Service]
Type=forking
User=root
Group=root
ExecStart=$ROCKETMQ_HOME/bin/start-namesrv.sh
ExecStop=$ROCKETMQ_HOME/bin/mqshutdown namesrv
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# 创建systemd服务文件 - Broker
log_info "创建Broker系统服务..."
cat > /etc/systemd/system/rocketmq-broker.service << EOF
[Unit]
Description=RocketMQ Broker Service
After=network.target rocketmq-namesrv.service
Requires=rocketmq-namesrv.service

[Service]
Type=forking
User=root
Group=root
ExecStart=$ROCKETMQ_HOME/bin/start-broker.sh
ExecStop=$ROCKETMQ_HOME/bin/mqshutdown broker
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# 设置系统参数
log_info "设置系统参数..."
cat > /etc/sysctl.d/99-rocketmq.conf << EOF
# 为RocketMQ优化的内核参数
vm.max_map_count=655360
vm.swappiness=10
EOF
sysctl -p /etc/sysctl.d/99-rocketmq.conf


# 重新加载systemd
systemctl daemon-reload

# 启动RocketMQ服务
log_info "启动RocketMQ NameServer..."
systemctl enable rocketmq-namesrv
systemctl start rocketmq-namesrv
sleep 5

# 检查NameServer服务状态
if systemctl is-active --quiet rocketmq-namesrv; then
    log_info "RocketMQ NameServer服务已成功启动"
    
    log_info "启动RocketMQ Broker..."
    systemctl enable rocketmq-broker
    systemctl start rocketmq-broker
    sleep 5
    
    # 检查Broker服务状态
    if systemctl is-active --quiet rocketmq-broker; then
        log_info "RocketMQ Broker服务已成功启动"
    else
        log_warn "RocketMQ Broker服务未能正常启动，请检查日志"
        log_info "查看日志: tail -f $ROCKETMQ_HOME/logs/broker.log"
    fi
else
    log_warn "RocketMQ NameServer服务未能正常启动，请检查日志"
    log_info "查看日志: tail -f $ROCKETMQ_HOME/logs/namesrv.log"
fi

# 打印连接信息
log_info "RocketMQ安装信息:"
log_info "  NameServer地址: $HOST_IP:$NAMESRV_PORT"
log_info "  Broker地址: $HOST_IP:$BROKER_PORT"
log_info "  安装目录: $ROCKETMQ_HOME"
log_info ""
log_info "RocketMQ管理命令:"
log_info "  查看服务状态: systemctl status rocketmq-namesrv rocketmq-broker"
log_info "  启动服务: systemctl start rocketmq-namesrv rocketmq-broker"
log_info "  停止服务: systemctl stop rocketmq-broker rocketmq-namesrv"
log_info "  重启服务: systemctl restart rocketmq-namesrv rocketmq-broker"
log_info ""
log_info "测试命令:"
log_info "  发送测试消息: ${ROCKETMQ_HOME}/bin/tools.sh org.apache.rocketmq.example.quickstart.Producer"
log_info "  接收测试消息: ${ROCKETMQ_HOME}/bin/tools.sh org.apache.rocketmq.example.quickstart.Consumer"
log_info ""
log_info "RocketMQ安装完成!"
