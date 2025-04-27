#!/bin/bash

# MySQL模块部署脚本

# 获取脚本所在目录
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 导入共享库
source "$ROOT_DIR/lib/log.sh"
source "$ROOT_DIR/lib/utils.sh"

# 默认配置
MYSQL_VERSION="8.0"
MYSQL_RPM_DIR="$MODULE_DIR/packages"
MYSQL_CONF_FILE="/etc/my.cnf"

MYSQL_PORT=${MYSQL_PORT:-3306}
MYSQL_PASSWORD=${MYSQL_PASSWORD:-"T3mp@Apr2025"}
MYSQL_DATA_DIR=${MYSQL_DATA_DIR:-"/var/lib/mysql"}


# 帮助信息
show_usage() {
    cat << EOF
MySQL 部署脚本使用方法:
    $0 [选项]

选项:
    --port=NUM           MySQL端口号 (默认: 3306)
    --password=PASS      MySQL密码 (默认: T3mp@Apr2025)
    --data-dir=PATH      数据目录 (默认: /var/lib/mysql)
    --rpm-dir=PATH       RPM包目录 (默认: ./packages)
    --arch=TYPE          架构类型 (standalone|ha) (默认: standalone)
    --help               显示此帮助信息
EOF
}

# 解析命令行参数
parse_args() {
    for i in "$@"; do
        case $i in
            --port=*)
                MYSQL_PORT="${i#*=}"
                ;;
            --password=*)
                MYSQL_PASSWORD="${i#*=}"
                ;;
            --data-dir=*)
                MYSQL_DATA_DIR="${i#*=}"
                ;;
            --rpm-dir=*)
                MYSQL_RPM_DIR="${i#*=}"
                ;;
            --arch=*)
                ARCHITECTURE="${i#*=}"
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
    log_info "MySQL部署配置:"
    log_info "- 端口: $MYSQL_PORT"
    log_info "- 数据目录: $MYSQL_DATA_DIR"
    log_info "- RPM包目录: $MYSQL_RPM_DIR"
    log_info "- 架构: $ARCHITECTURE"
}

# 检查环境
check_env() {
    log_section "环境检查"
    
    # 检查是否以root运行
    check_root || return 1
    
    # 检查系统资源
    check_resources 1500 10 || log_warn "系统资源可能不足"
    
    # 检查端口是否被占用
    check_port $MYSQL_PORT || return 1
    
    # 检查MySQL是否已安装
    if systemctl status mysqld &>/dev/null; then
        log_warn "MySQL服务已运行"
        read -p "是否继续安装？(y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "取消安装"
            return 1
        fi
    fi
    
    # 检查RPM包
    if [[ ! -d "$MYSQL_RPM_DIR" ]]; then
        log_error "RPM包目录不存在: $MYSQL_RPM_DIR"
        return 1
    fi
    
    rpm_count=$(find "$MYSQL_RPM_DIR" -name "*.rpm" | wc -l)
    if [[ $rpm_count -eq 0 ]]; then
        log_error "未在 $MYSQL_RPM_DIR 目录中找到RPM包"
        return 1
    fi
    
    log_info "找到 $rpm_count 个RPM包"
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
    
    # 设置系统参数
    backup_file /etc/sysctl.conf
    {
        echo "vm.overcommit_memory = 1"
        echo "net.core.somaxconn = 1024"
    } >> /etc/sysctl.conf
    
    sysctl -p &>/dev/null || log_warn "应用系统参数失败"
    
    log_success "系统参数调整完成"
    return 0
}

# 安装MySQL
install_mysql() {
    log_section "安装MySQL"
    
    # 安装RPM包
    log_info "安装MySQL RPM包..."
    rpm -ivh $MYSQL_RPM_DIR/*.rpm --nodeps || {
        log_error "安装MySQL RPM包失败"
        return 1
    }
    
    # 创建数据目录
    ensure_dir "$MYSQL_DATA_DIR" || return 1
    
    # 配置MySQL
    configure_mysql || return 1
    
    # 启动MySQL服务
    log_info "启动MySQL服务..."
    systemctl enable mysqld
    systemctl start mysqld
    
    # 设置MySQL密码
    log_info "设置MySQL密码..."
    sleep 5  # 等待MySQL完全启动
    
    # 获取初始密码
    local init_password=$(grep "temporary password" /var/log/mysqld.log | awk '{print $NF}')
    
    if [[ -n "$init_password" ]]; then
        mysql --connect-expired-password -uroot -p"$init_password" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD';" || {
            log_error "设置MySQL密码失败"
            return 1
        }
        
        # 允许远程访问
        mysql -uroot -p"$MYSQL_PASSWORD" -e "CREATE USER 'root'@'%' IDENTIFIED BY '$MYSQL_PASSWORD';" || true
        mysql -uroot -p"$MYSQL_PASSWORD" -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%';" || true
        mysql -uroot -p"$MYSQL_PASSWORD" -e "FLUSH PRIVILEGES;" || true
        
        log_success "MySQL密码设置成功: $MYSQL_PASSWORD"
    else
        log_error "无法获取MySQL初始密码"
        return 1
    fi
    
    log_success "MySQL安装完成"
    return 0
}

# 根据架构配置MySQL
configure_mysql() {
    log_info "配置MySQL($ARCHITECTURE架构)..."
    
    # 备份原配置（如果存在）
    backup_file "$MYSQL_CONF_FILE"
    
    # 根据系统资源计算合适的参数
    local mem_mb=$(free -m | grep Mem | awk '{print $2}')
    local cpu_cores=$(grep -c processor /proc/cpuinfo)
    
    # 计算缓冲池大小 (50% of RAM)
    local buffer_pool_size=$(( mem_mb / 2 ))
    
    # 根据架构配置MySQL
    if [[ "$ARCHITECTURE" == "ha" ]]; then
        log_info "生成高可用架构配置..."
        cat > "$MYSQL_CONF_FILE" << EOF
[mysqld]
# 基本配置
datadir=$MYSQL_DATA_DIR
socket=/var/lib/mysql/mysql.sock
port=$MYSQL_PORT
log-error=/var/log/mysqld.log
pid-file=/var/run/mysqld/mysqld.pid
character_set_server=utf8mb4
collation_server=utf8mb4_unicode_ci

# 连接配置
max_connections=2000
wait_timeout=1800
interactive_timeout=1800

# InnoDB配置
innodb_buffer_pool_size=${buffer_pool_size}M
innodb_buffer_pool_instances=$(( cpu_cores > 8 ? 8 : cpu_cores ))
innodb_log_buffer_size=32M
innodb_write_io_threads=$cpu_cores
innodb_read_io_threads=$cpu_cores
innodb_flush_method=O_DIRECT
innodb_flush_neighbors=0
innodb_io_capacity=4000
innodb_io_capacity_max=8000

# 高可用特有配置
server_id=1
log-bin=mysql-bin
binlog_format=ROW
sync_binlog=1
innodb_flush_log_at_trx_commit=1
gtid_mode=ON
enforce_gtid_consistency=ON
log_slave_updates=ON
EOF
    else
        log_info "生成单节点架构配置..."
        cat > "$MYSQL_CONF_FILE" << EOF
[mysqld]
# 基本配置
datadir=$MYSQL_DATA_DIR
socket=/var/lib/mysql/mysql.sock
port=$MYSQL_PORT
log-error=/var/log/mysqld.log
pid-file=/var/run/mysqld/mysqld.pid
character_set_server=utf8mb4
collation_server=utf8mb4_unicode_ci

# 连接配置
max_connections=1000
wait_timeout=1800
interactive_timeout=1800

# InnoDB配置
innodb_buffer_pool_size=${buffer_pool_size}M
innodb_buffer_pool_instances=$(( cpu_cores > 4 ? 4 : cpu_cores ))
innodb_log_buffer_size=32M
innodb_write_io_threads=$(( cpu_cores / 2 > 4 ? cpu_cores / 2 : 4 ))
innodb_read_io_threads=$(( cpu_cores / 2 > 4 ? cpu_cores / 2 : 4 ))
innodb_flush_method=O_DIRECT
innodb_flush_neighbors=0
innodb_io_capacity=2000
innodb_io_capacity_max=4000
EOF
    fi
    
    log_success "MySQL配置文件生成完成"
    return 0
}

# 验证安装
verify_install() {
    log_section "验证安装"
    
    # 检查MySQL服务状态
    if ! systemctl is-active --quiet mysqld; then
        log_error "MySQL服务未运行"
        return 1
    fi
    
    # 检查MySQL连接
    if ! mysql -uroot -p"$MYSQL_PASSWORD" -e "SELECT VERSION();" &>/dev/null; then
        log_error "无法连接到MySQL"
        return 1
    fi
    
    log_info "MySQL版本: $(mysql -uroot -p"$MYSQL_PASSWORD" -e "SELECT VERSION();" -s)"
    log_info "MySQL状态: $(systemctl status mysqld | grep "Active:" | awk '{print $2, $3}')"
    log_success "MySQL安装验证通过"
    
    log_info "MySQL部署成功！"
    log_info "- 端口: $MYSQL_PORT"
    log_info "- 用户: root"
    log_info "- 密码: $MYSQL_PASSWORD"
    log_info "- 数据目录: $MYSQL_DATA_DIR"
    log_info "- 配置文件: $MYSQL_CONF_FILE"
    
    return 0
}

# 主函数
main() {
    log_section "MySQL部署开始"
    
    # 初始化日志
    log_init "/tmp/mysql_deploy_$(date +%Y%m%d%H%M%S).log"
    
    # 解析参数
    parse_args "$@"
    
    # 环境检查
    check_env || {
        log_error "环境检查失败，终止安装"
        return 1
    }
    
    # 调整系统参数
    adjust_system
    
    # 安装MySQL
    install_mysql || {
        log_error "MySQL安装失败"
        return 1
    }
    
    # 验证安装
    verify_install
    
    log_section "MySQL部署结束"
    return 0
}

# 执行主函数
main "$@"
