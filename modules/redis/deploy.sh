#!/bin/bash

# Redis模块部署脚本

# 获取脚本所在目录
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 导入共享库
source "$ROOT_DIR/lib/log.sh"
source "$ROOT_DIR/lib/utils.sh"

# 默认配置
REDIS_VERSION="7.0"
REDIS_RPM_DIR="$MODULE_DIR/packages"
REDIS_CONF_FILE="/etc/redis/redis.conf"
SENTINEL_CONF_FILE="/etc/redis/sentinel.conf"

REDIS_PORT=${REDIS_PORT:-6379}
REDIS_PASSWORD=${REDIS_PASSWORD:-"T3mp@Redis2025"}
REDIS_DATA_DIR=${REDIS_DATA_DIR:-"/var/lib/redis"}
REDIS_MAX_MEMORY=${REDIS_MAX_MEMORY:-""}  # 如果不设置，自动计算
SENTINEL_PORT=${SENTINEL_PORT:-26379}

# 帮助信息
show_usage() {
    cat << EOF
Redis 部署脚本使用方法:
    $0 [选项]

选项:
    --port=NUM           Redis端口号 (默认: 6379)
    --password=PASS      Redis密码 (默认: T3mp@Redis2025)
    --data-dir=PATH      数据目录 (默认: /var/lib/redis)
    --rpm-dir=PATH       RPM包目录 (默认: ./packages)
    --max-memory=SIZE    最大内存限制 (默认: 自动计算)
    --arch=TYPE          架构类型 (standalone|ha) (默认: standalone)
    --help               显示此帮助信息
EOF
}

# 解析命令行参数
parse_args() {
    for i in "$@"; do
        case $i in
            --port=*)
                REDIS_PORT="${i#*=}"
                ;;
            --password=*)
                REDIS_PASSWORD="${i#*=}"
                ;;
            --data-dir=*)
                REDIS_DATA_DIR="${i#*=}"
                ;;
            --rpm-dir=*)
                REDIS_RPM_DIR="${i#*=}"
                ;;
            --max-memory=*)
                REDIS_MAX_MEMORY="${i#*=}"
                ;;
            --arch=*)
                ARCHITECTURE="${i#*=}"
                ;;
            --debug)
                DEBUG=true
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_warn "未知参数: $i"
                ;;
        esac
    done
    
    # 默认架构为standalone
    ARCHITECTURE=${ARCHITECTURE:-"standalone"}
    
    # 打印配置信息
    log_info "Redis部署配置:"
    log_info "- 端口: $REDIS_PORT"
    log_info "- 数据目录: $REDIS_DATA_DIR"
    log_info "- RPM包目录: $REDIS_RPM_DIR"
    log_info "- 架构: $ARCHITECTURE"
    log_info "- 最大内存: ${REDIS_MAX_MEMORY:-自动计算}"
}

# 检查环境
check_env() {
    log_section "环境检查"
    
    # 检查是否以root运行
    check_root || return 1
    
    # 检查系统资源
    check_resources 1000 5 || log_warn "系统资源可能不足"
    
    # 检查端口是否被占用
    check_port $REDIS_PORT || return 1
    
    # 如果是哨兵模式，检查哨兵端口
    if [[ "$ARCHITECTURE" == "ha" ]]; then
        check_port $SENTINEL_PORT || return 1
    fi
    
    # 检查Redis是否已安装
    if systemctl status redis &>/dev/null; then
        log_warn "Redis服务已运行"
        read -p "是否继续安装？(y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "取消安装"
            return 1
        fi
    fi
    
    # 检查是否有现成的Redis安装
    if command -v redis-server &>/dev/null; then
        log_info "检测到已安装的Redis: $(redis-server --version)"
    else
        # 检查RPM包
        if [[ ! -d "$REDIS_RPM_DIR" ]]; then
            log_warn "RPM包目录不存在: $REDIS_RPM_DIR，将尝试使用系统包管理器安装"
        else
            rpm_count=$(find "$REDIS_RPM_DIR" -name "*.rpm" | wc -l)
            if [[ $rpm_count -eq 0 ]]; then
                log_warn "未在 $REDIS_RPM_DIR 目录中找到RPM包，将尝试使用系统包管理器安装"
            else
                log_info "找到 $rpm_count 个RPM包"
            fi
        fi
    fi
    
    log_success "环境检查通过"
    return 0
}

# 调整系统参数
adjust_system() {
    log_section "调整系统参数"
    
    # 禁用SELinux
    if [ -f /etc/selinux/config ]; then
        backup_file /etc/selinux/config
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
        setenforce 0 2>/dev/null || true
    fi
    
    # 设置文件句柄数
    if ! grep -q "* soft nofile 65535" /etc/security/limits.conf; then
        backup_file /etc/security/limits.conf
        echo "* soft nofile 65535" >> /etc/security/limits.conf
        echo "* hard nofile 65535" >> /etc/security/limits.conf
    fi
    
    # 设置Redis相关的系统参数
    backup_file /etc/sysctl.conf
    {
        echo "vm.overcommit_memory = 1"
        echo "net.core.somaxconn = 65535"
        echo "vm.swappiness = 1"
        # 禁用透明大页
        echo "echo never > /sys/kernel/mm/transparent_hugepage/enabled"
    } >> /etc/sysctl.conf
    
    sysctl -p &>/dev/null || log_warn "应用系统参数失败"
    
    # 立即应用透明大页设置
    echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
    
    log_success "系统参数调整完成"
    return 0
}

# 安装Redis
install_redis() {
    log_section "安装Redis"
    
    # 检查是否已安装
    if command -v redis-server &>/dev/null; then
        log_info "Redis已安装，跳过安装步骤"
    else
        # 尝试RPM安装
        if [[ -d "$REDIS_RPM_DIR" ]] && [[ $(find "$REDIS_RPM_DIR" -name "*.rpm" | wc -l) -gt 0 ]]; then
            log_info "使用RPM包安装Redis..."
            rpm -ivh $REDIS_RPM_DIR/*.rpm --nodeps || {
                log_warn "RPM安装失败，尝试使用yum安装"
                yum install -y redis || {
                    log_error "安装Redis失败"
                    return 1
                }
            }
        else
            log_info "使用yum安装Redis..."
            yum install -y redis || {
                log_error "安装Redis失败"
                return 1
            }
        fi
    fi
    
    # 创建数据目录
    ensure_dir "$REDIS_DATA_DIR" || return 1
    chown redis:redis "$REDIS_DATA_DIR" 2>/dev/null || true
    
    # 根据架构配置Redis
    configure_redis || return 1
    
    # 启动Redis服务
    log_info "启动Redis服务..."
    systemctl enable redis
    systemctl restart redis
    
    # 如果是高可用模式，启动哨兵
    if [[ "$ARCHITECTURE" == "ha" ]]; then
        configure_sentinel || return 1
        systemctl enable redis-sentinel
        systemctl restart redis-sentinel
    fi
    
    log_success "Redis安装完成"
    return 0
}

# 配置Redis
configure_redis() {
    log_info "配置Redis($ARCHITECTURE架构)..."
    
    # 备份原配置（如果存在）
    backup_file "$REDIS_CONF_FILE"
    
    # 创建配置目录（如果不存在）
    ensure_dir "$(dirname "$REDIS_CONF_FILE")" || return 1
    
    # 计算最大内存（如果未指定）
    if [[ -z "$REDIS_MAX_MEMORY" ]]; then
        local mem_mb=$(free -m | grep Mem | awk '{print $2}')
        # 使用50%的系统内存
        REDIS_MAX_MEMORY="${mem_mb}mb"
    fi
    
    # 生成基础配置
    cat > "$REDIS_CONF_FILE" << EOF
# Redis配置文件 - 由部署脚本自动生成

# 网络配置
bind 0.0.0.0
port $REDIS_PORT
protected-mode no

# 通用配置
daemonize yes
pidfile /var/run/redis/redis.pid
loglevel notice
logfile /var/log/redis/redis.log

# 数据持久化
dir $REDIS_DATA_DIR
dbfilename dump.rdb
save 900 1
save 300 10
save 60 10000

# AOF配置
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec

# 内存配置
maxmemory $REDIS_MAX_MEMORY
maxmemory-policy allkeys-lru

# 安全配置
requirepass $REDIS_PASSWORD

# 客户端配置
timeout 300
tcp-keepalive 60
EOF

    # 根据架构添加特定配置
    if [[ "$ARCHITECTURE" == "ha" ]]; then
        log_info "添加高可用配置..."
        cat >> "$REDIS_CONF_FILE" << EOF

# 主从复制配置
masterauth $REDIS_PASSWORD
replica-serve-stale-data yes
replica-read-only yes
repl-diskless-sync no
repl-diskless-sync-delay 5
EOF
    fi
    
    log_success "Redis配置文件生成完成"
    return 0
}

# 配置Redis哨兵（仅用于高可用模式）
configure_sentinel() {
    log_info "配置Redis哨兵..."
    
    # 备份原配置（如果存在）
    backup_file "$SENTINEL_CONF_FILE"
    
    # 创建配置目录（如果不存在）
    ensure_dir "$(dirname "$SENTINEL_CONF_FILE")" || return 1
    
    # 生成哨兵配置
    cat > "$SENTINEL_CONF_FILE" << EOF
# Redis Sentinel配置文件 - 由部署脚本自动生成

# 网络配置
bind 0.0.0.0
port $SENTINEL_PORT

# 基本配置
daemonize yes
pidfile /var/run/redis/redis-sentinel.pid
logfile /var/log/redis/sentinel.log

# 主节点监控配置
sentinel monitor mymaster 127.0.0.1 $REDIS_PORT 2
sentinel auth-pass mymaster $REDIS_PASSWORD
sentinel down-after-milliseconds mymaster 10000
sentinel parallel-syncs mymaster 2
sentinel failover-timeout mymaster 180000

# 脚本配置
# sentinel notification-script mymaster /etc/redis/notify.sh
# sentinel client-reconfig-script mymaster /etc/redis/reconfig.sh
EOF
    
    # 创建哨兵服务文件（如果不存在）
    if [[ ! -f "/usr/lib/systemd/system/redis-sentinel.service" ]]; then
        cat > /usr/lib/systemd/system/redis-sentinel.service << EOF
[Unit]
Description=Redis Sentinel
After=network.target redis.service

[Service]
ExecStart=/usr/bin/redis-sentinel $SENTINEL_CONF_FILE
ExecStop=/usr/bin/redis-cli -p $SENTINEL_PORT shutdown
User=redis
Group=redis
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
    fi
    
    log_success "Redis哨兵配置完成"
    return 0
}

# 验证安装
verify_install() {
    log_section "验证安装"
    
    # 检查Redis服务状态
    if ! systemctl is-active --quiet redis; then
        log_error "Redis服务未运行"
        return 1
    fi
    
    # 检查Redis连接
    if ! redis-cli -p "$REDIS_PORT" -a "$REDIS_PASSWORD" ping | grep -q "PONG"; then
        log_error "无法连接到Redis"
        return 1
    fi
    
    # 获取Redis版本和状态信息
    local redis_version=$(redis-cli -p "$REDIS_PORT" -a "$REDIS_PASSWORD" INFO SERVER | grep "redis_version" | cut -d: -f2 | tr -d '\r')
    local redis_mode=$(redis-cli -p "$REDIS_PORT" -a "$REDIS_PASSWORD" INFO REPLICATION | grep "role" | cut -d: -f2 | tr -d '\r')
    
    log_info "Redis版本: $redis_version"
    log_info "Redis模式: $redis_mode"
    log_info "Redis状态: $(systemctl status redis | grep "Active:" | awk '{print $2, $3}')"
    
    # 如果是高可用模式，验证哨兵
    if [[ "$ARCHITECTURE" == "ha" ]]; then
        if systemctl is-active --quiet redis-sentinel; then
            log_info "Redis哨兵状态: 运行中"
        else
            log_warn "Redis哨兵未运行"
        fi
    fi
    
    log_success "Redis安装验证通过"
    
    log_info "Redis部署成功！"
    log_info "- 端口: $REDIS_PORT"
    log_info "- 密码: $REDIS_PASSWORD"
    log_info "- 数据目录: $REDIS_DATA_DIR"
    log_info "- 配置文件: $REDIS_CONF_FILE"
    if [[ "$ARCHITECTURE" == "ha" ]]; then
        log_info "- 哨兵端口: $SENTINEL_PORT"
        log_info "- 哨兵配置: $SENTINEL_CONF_FILE"
    fi
    
    return 0
}

# 主函数
main() {
    log_section "Redis部署开始"
    
    # 初始化日志
    log_init "/tmp/redis_deploy_$(date +%Y%m%d%H%M%S).log"
    
    # 解析参数
    parse_args "$@"
    
    # 环境检查
    check_env || {
        log_error "环境检查失败，终止安装"
        return 1
    }
    
    # 调整系统参数
    adjust_system
    
    # 安装Redis
    install_redis || {
        log_error "Redis安装失败"
        return 1
    }
    
    # 验证安装
    verify_install
    
    log_section "Redis部署结束"
    return 0
}

# 执行主函数
main "$@"