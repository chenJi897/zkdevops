#!/bin/bash
# Redis安装脚本 - 支持单实例或哨兵模式安装

# 默认变量
install_mode=""
master=""
nodes=""
redis_rpm="redis-7.0.14-1.el7.remi.x86_64.rpm"
redis_conf="/etc/redis/redis.conf"
sentinel_conf="/etc/redis/sentinel.conf"
redis_port=6379
sentinel_port=26379
redis_password="Wiseco#2024"

# 解析参数
for arg in "$@"; do
  case "$arg" in
    --mode=* )
      install_mode="${arg#*=}"
      shift
      ;;
    --master=* )
      master="${arg#*=}"
      shift
      ;;
    --nodes=* )
      nodes="${arg#*=}"
      shift
      ;;
    *)
      echo "未知选项: $arg"
      exit 1
      ;;
  esac
done

# 检查RPM文件是否存在
if [[ ! -f "$redis_rpm" ]]; then
    echo "错误: 未找到Redis RPM安装包: $redis_rpm"
    exit 1
fi

# 验证输入参数
if [[ "$install_mode" != "single" && "$install_mode" != "sentinel" ]]; then
    echo "错误: 未指定安装模式或安装模式无效"
    echo "用法: $0 --mode=<single|sentinel> [--master=<master_ip> --nodes=<node1_ip>,<node2_ip>]"
    echo "  单实例模式: $0 --mode=single"
    echo "  哨兵模式: $0 --mode=sentinel --master=<master_ip> --nodes=<node1_ip>,<node2_ip>"
    exit 1
fi

if [[ "$install_mode" == "sentinel" && (  -z "$master" || -z "$nodes" ) ]]; then
    echo "错误: 哨兵模式必须同时指定master和nodes参数"
    echo "用法: $0 --mode=sentinel --master=<master_ip> --nodes=<node1_ip>,<node2_ip>"
    exit 1
fi

# 将节点字符串转换为数组（如果是哨兵模式）
if [[ "$install_mode" == "sentinel" ]]; then
    IFS=',' read -r -a nodes_array <<< "$nodes"
fi

# 使用RPM安装Redis
install_redis() {
    echo "正在使用RPM包安装Redis..."
    sudo rpm -i "$redis_rpm" || { echo "安装Redis RPM失败"; exit 1; }
    echo "Redis安装成功!"
}

# 配置单实例Redis
configure_single() {
    echo "正在配置Redis单实例模式..."
    
    # 备份原始配置
    sudo cp "$redis_conf" "${redis_conf}.orig"
    
    # 写入新配置
    sudo tee "$redis_conf" > /dev/null << EOF
bind 0.0.0.0
port $redis_port
dir /var/lib/redis
requirepass $redis_password
daemonize yes
maxmemory 3221225472
appendonly yes
appendfilename "appendonly.aof"
protected-mode no
EOF
    
    # 启用并启动Redis服务
    sudo systemctl enable redis
    sudo systemctl restart redis
    
    # 检查服务状态
    echo "Redis状态:"
    sudo systemctl status redis
}

# 配置Redis主节点
configure_master() {
    echo "正在配置Redis为主节点..."
    
    # 备份原始配置
    sudo cp "$redis_conf" "${redis_conf}.orig"
    
    # 写入主节点配置
    sudo tee "$redis_conf" > /dev/null << EOF
bind 0.0.0.0
port $redis_port
dir /var/lib/redis
requirepass $redis_password
masterauth $redis_password
slave-serve-stale-data no
repl-disable-tcp-nodelay no
daemonize yes
maxmemory 3221225472
appendonly yes
appendfilename "appendonly.aof"
protected-mode no
EOF
    
    # 启用并启动Redis服务
    sudo systemctl enable redis
    sudo systemctl restart redis
    
    echo "Redis主节点配置并启动完成"
}

# 配置Redis从节点
configure_slave() {
    echo "正在配置Redis为从节点..."
    
    # 备份原始配置
    sudo cp "$redis_conf" "${redis_conf}.orig"
    
    # 写入从节点配置
    sudo tee "$redis_conf" > /dev/null << EOF
bind 0.0.0.0
port $redis_port
dir /var/lib/redis
requirepass $redis_password
slaveof $master $redis_port
masterauth $redis_password
slave-serve-stale-data no
repl-disable-tcp-nodelay no
daemonize yes
maxmemory 3221225472
appendonly yes
appendfilename "appendonly.aof"
protected-mode no
EOF
    
    # 启用并启动Redis服务
    sudo systemctl enable redis
    sudo systemctl restart redis
    
    echo "Redis从节点配置并启动完成"
}

# 配置Redis哨兵
configure_sentinel() {
    echo "正在配置Redis哨兵..."
    
    # 写入哨兵配置
    sudo tee "$sentinel_conf" > /dev/null << EOF
bind 0.0.0.0
port $sentinel_port
daemonize yes
sentinel monitor mymaster $master $redis_port 2
sentinel auth-pass mymaster $redis_password
sentinel down-after-milliseconds mymaster 10000
sentinel parallel-syncs mymaster 2
sentinel failover-timeout mymaster 180000
EOF
    
    # 创建哨兵服务文件(如果尚不存在)
    if [[ ! -f "/usr/lib/systemd/system/redis-sentinel.service" ]]; then
        sudo tee "/usr/lib/systemd/system/redis-sentinel.service" > /dev/null << EOF
[Unit]
Description=Redis Sentinel
After=network.target

[Service]
ExecStart=/usr/bin/redis-sentinel $sentinel_conf
ExecStop=/usr/bin/redis-cli -p $sentinel_port shutdown
User=redis
Group=redis
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    fi
    
    # 启用并启动哨兵服务
    sudo systemctl daemon-reload
    sudo systemctl enable redis-sentinel
    sudo systemctl restart redis-sentinel
    
    echo "Redis哨兵配置并启动完成"
}

# 主执行流程
echo "开始Redis安装..."

# 安装Redis RPM
install_redis

# 根据模式配置Redis
if [[ "$install_mode" == "single" ]]; then
    configure_single
    echo "Redis单实例安装成功完成"
elif [[ "$install_mode" == "sentinel" ]]; then
    # 获取当前服务器IP
    current_ip_list=$(hostname -I)
    
    # 检查当前服务器是主节点还是从节点
    is_master=$(echo "$current_ip_list" | tr ' ' '\n' | grep -Fxf - <(echo "$master" | tr ' ' '\n'))
    is_slave=$(echo "$current_ip_list" | tr ' ' '\n' | grep -Fxf - <(echo "${nodes_array[@]}" | tr ' ' '\n'))
    
    if [[ -n $is_master ]]; then
        echo "当前服务器是主节点, IP: $is_master"
        configure_master
        configure_sentinel
    elif [[ -n $is_slave ]]; then
        echo "当前服务器是从节点, IP: $is_slave"
        configure_slave
        configure_sentinel
    else
        echo "错误: 当前服务器IP与指定的节点不匹配"
        exit 1
    fi
    
    echo "Redis哨兵模式安装成功完成"
fi

# 显示Redis进程
echo "正在运行的Redis进程:"
ps -ef | grep redis | grep -v grep

# 检查Redis服务状态
echo "Redis服务状态:"
sudo systemctl status redis

# 如果是哨兵模式，检查哨兵服务状态
if [[ "$install_mode" == "sentinel" ]]; then
    echo "哨兵服务状态:"
    sudo systemctl status redis-sentinel
fi

echo "安装完成!"