#!/bin/bash


# 获取当前脚本所在目录
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 导入日志库
source "$LIB_DIR/log.sh"


# 检查是否以root用户运行
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请以root用户运行此脚本"
        return 1
    fi
    return 0
}

# 检查文件是否存在
check_file() {
    local file=$1
    if [[ ! -f "$file" ]]; then
        log_error "文件不存在: $file"
        return 1
    fi
    return 0
}

# 检查目录是否存在，不存在则创建
ensure_dir() {
    local dir=$1
    if [[ ! -d "$dir" ]]; then
        log_info "创建目录: $dir"
        mkdir -p "$dir" || { 
            log_error "无法创建目录: $dir"; 
            return 1; 
        }
    fi
    return 0
}

# 检查命令是否存在
check_command() {
    local cmd=$1
    if ! command -v $cmd &> /dev/null; then
        log_error "命令不存在: $cmd"
        return 1
    fi
    return 0
}

# 检查端口是否被占用
check_port() {
    local port=$1
    if command -v ss &> /dev/null; then
        if ss -lnt | grep -q ":$port\s"; then
            log_warn "端口 $port 已被占用"
            return 1
        fi
    elif command -v netstat &> /dev/null; then
        if netstat -lnt | grep -q ":$port\s"; then
            log_warn "端口 $port 已被占用"
            return 1
        fi
    else
        log_warn "无法检查端口，ss和netstat命令均不可用"
        return 2
    fi
    return 0
}

# 检查系统资源
check_resources() {
    # 检查内存
    local min_memory=$1  # 单位MB
    local total_mem=$(free -m | grep Mem | awk '{print $2}')
    
    log_info "系统内存: ${total_mem}MB"
    if [[ $total_mem -lt $min_memory ]]; then
        log_warn "系统内存不足: 当前${total_mem}MB，建议${min_memory}MB或更高"
        return 1
    fi
    
    # 检查CPU核心数
    local cpu_cores=$(grep -c processor /proc/cpuinfo)
    log_info "CPU核心数: $cpu_cores"
    
    # 检查磁盘空间
    local min_disk=$2  # 单位GB
    local disk_space=$(df -BG / | tail -n 1 | awk '{print $4}' | tr -d 'G')
    
    log_info "根目录可用空间: ${disk_space}GB"
    if [[ $disk_space -lt $min_disk ]]; then
        log_warn "磁盘空间不足: 当前${disk_space}GB，建议${min_disk}GB或更高"
        return 1
    fi
    
    return 0
}

# 执行命令并检查结果
exec_cmd() {
    local cmd="$1"
    local error_msg="${2:-执行命令失败}"
    local silent=${3:-false}
    
    if [[ "$silent" == true ]]; then
        eval "$cmd" &>/dev/null
    else
        log_info "执行: $cmd"
        eval "$cmd"
    fi
    
    local status=$?
    if [[ $status -ne 0 ]]; then
        log_error "$error_msg (错误码: $status)"
        return $status
    fi
    return 0
}

# 备份文件
backup_file() {
    local file=$1
    if [[ -f "$file" ]]; then
        local backup="${file}.bak.$(date +%Y%m%d%H%M%S)"
        log_info "备份文件 $file 到 $backup"
        cp "$file" "$backup" || {
            log_error "备份文件失败: $file"
            return 1
        }
    fi
    return 0
}
