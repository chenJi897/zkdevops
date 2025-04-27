#!/bin/bash

# Elasticsearch与IK分词器离线安装脚本（使用RPM包）
# 用法: 将此脚本与Elasticsearch的RPM包和IK分词器zip包放在同一目录下执行

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

# 检查是否存在ES的RPM包
ES_RPM=$(ls elasticsearch-*.rpm 2>/dev/null | head -n 1)
if [ -z "$ES_RPM" ]; then
    log_error "未找到Elasticsearch的RPM包，请确保将RPM包放在与脚本相同的目录中"
fi

log_info "找到Elasticsearch安装包: $ES_RPM"

# 检查是否存在IK分词器插件包
IK_ZIP=$(ls elasticsearch-analysis-ik-*.zip 2>/dev/null | head -n 1)
if [ -z "$IK_ZIP" ]; then
    log_warn "未找到IK分词器插件包，将只安装Elasticsearch核心组件"
    INSTALL_IK=false
else
    log_info "找到IK分词器插件包: $IK_ZIP"
    INSTALL_IK=true
fi

# 检查系统要求
log_info "检查系统要求..."

# 检查最大文件描述符
max_file_descriptors=$(ulimit -n)
if [ "$max_file_descriptors" -lt 65535 ]; then
    log_warn "当前最大文件描述符数为 $max_file_descriptors，建议至少为65535"
    
    # 添加系统限制配置
    if [ ! -f /etc/security/limits.d/elasticsearch.conf ]; then
        log_info "创建elasticsearch文件描述符限制配置..."
        cat > /etc/security/limits.d/elasticsearch.conf << EOF
elasticsearch soft nofile 65535
elasticsearch hard nofile 65535
EOF
    fi
fi

# 检查最大虚拟内存区域
max_map_count=$(cat /proc/sys/vm/max_map_count)
if [ "$max_map_count" -lt 262144 ]; then
    log_warn "当前max_map_count为 $max_map_count，建议至少为262144"
    log_info "设置vm.max_map_count=262144..."
    
    sysctl -w vm.max_map_count=262144
    
    # 添加到/etc/sysctl.conf以使设置永久生效
    if ! grep -q "vm.max_map_count" /etc/sysctl.conf; then
        echo "vm.max_map_count=262144" >> /etc/sysctl.conf
    else
        sed -i 's/vm.max_map_count=.*/vm.max_map_count=262144/' /etc/sysctl.conf
    fi
fi

# 安装Elasticsearch
log_info "开始安装Elasticsearch..."
rpm -ivh "$ES_RPM" || log_error "Elasticsearch安装失败"

# 配置Elasticsearch
log_info "配置Elasticsearch..."
ES_CONFIG="/etc/elasticsearch/elasticsearch.yml"

# 备份原始配置
cp "$ES_CONFIG" "${ES_CONFIG}.bak"

# 基本配置
cat > "$ES_CONFIG" << EOF
# ======================== Elasticsearch Configuration =========================

# 集群名称
cluster.name: es-cluster

# 节点名称
node.name: node-1

# 数据和日志路径
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch

# 网络设置
network.host: 0.0.0.0
http.port: 9200

# 发现设置
discovery.type: single-node

# 禁用安全功能(生产环境不建议)
xpack.security.enabled: false

# JVM配置 - 根据系统内存调整
# 在/etc/elasticsearch/jvm.options中配置
EOF

# 根据系统内存配置JVM堆大小
TOTAL_MEM=$(free -g | grep Mem | awk '{print $2}')
if [ "$TOTAL_MEM" -ge 64 ]; then
    JVM_HEAP=31g
elif [ "$TOTAL_MEM" -ge 32 ]; then
    JVM_HEAP=16g
elif [ "$TOTAL_MEM" -ge 16 ]; then
    JVM_HEAP=8g
else
    JVM_HEAP="$((TOTAL_MEM / 2))g"
fi

log_info "系统内存为${TOTAL_MEM}G，设置ES堆内存为${JVM_HEAP}"

# 更新JVM配置
sed -i "s/-Xms[0-9]\+[gmk]/-Xms${JVM_HEAP}/" /etc/elasticsearch/jvm.options
sed -i "s/-Xmx[0-9]\+[gmk]/-Xmx${JVM_HEAP}/" /etc/elasticsearch/jvm.options

# 安装IK分词器插件
if [ "$INSTALL_IK" = true ]; then
    log_info "安装IK分词器插件..."
    
    # 创建插件安装自动应答文件
    echo "y" > /tmp/plugin_answer
    
    # 安装插件，自动应答yes以接受权限提示
    /usr/share/elasticsearch/bin/elasticsearch-plugin install --batch file:$(pwd)/$IK_ZIP < /tmp/plugin_answer
    
    if [ $? -eq 0 ]; then
        log_info "IK分词器插件安装成功"
    else
        log_error "IK分词器插件安装失败"
    fi
    
    # 清理临时文件
    rm -f /tmp/plugin_answer
fi

# 配置系统服务
log_info "配置和启动Elasticsearch服务..."
systemctl daemon-reload
systemctl enable elasticsearch.service
systemctl start elasticsearch.service

# 等待服务启动
log_info "等待Elasticsearch启动(最多60秒)..."
for i in {1..12}; do
    if curl -s "http://localhost:9200/" &> /dev/null; then
        break
    fi
    echo -n "."
    sleep 5
done
echo ""

# 检查服务状态
if systemctl is-active --quiet elasticsearch; then
    log_info "Elasticsearch服务已成功启动"
    ES_VERSION=$(curl -s "http://localhost:9200/" | grep number | cut -d '"' -f 4)
    log_info "Elasticsearch版本: $ES_VERSION"
    log_info "访问地址: http://$(hostname -I | awk '{print $1}'):9200/"
    
    # 验证IK分词器是否安装成功
    if [ "$INSTALL_IK" = true ]; then
        if curl -s "http://localhost:9200/_cat/plugins" | grep -q "analysis-ik"; then
            log_info "IK分词器插件安装验证成功，您可以使用以下分词器类型:"
            log_info "  - ik_smart: 最少切分"
            log_info "  - ik_max_word: 最细粒度切分"
            log_info "测试分词示例: curl -X GET \"http://localhost:9200/_analyze?pretty\" -H \"Content-Type: application/json\" -d'{\"analyzer\": \"ik_smart\",\"text\":\"中华人民共和国\"}'"
        else
            log_warn "未能验证到IK分词器插件，请检查插件日志"
        fi
    fi
else
    log_error "Elasticsearch服务未能成功启动，请检查日志: journalctl -u elasticsearch"
fi

log_info "安装完成! 请根据生产环境需求进一步配置安全设置和集群参数。"
