#!/bin/bash

# 颜色定义
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
NC="\033[0m" # 无颜色

# 是否启用彩色输出
USE_COLOR=true

# 日志文件配置
LOG_FILE="/tmp/deploy_$(date +%Y%m%d%H%M%S).log"
LOG_ENABLED=false

# 初始化日志
log_init() {
    local log_file=${1:-""}
    
    if [[ -n "$log_file" ]]; then
        LOG_FILE="$log_file"
        LOG_ENABLED=true
        echo "=========== 部署日志 开始于: $(date) ===========" > "$LOG_FILE"
    fi
}

# 写入日志到文件
log_to_file() {
    local level="$1"
    local message="$2"
    
    if [[ "$LOG_ENABLED" == true ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] ${message}" >> "$LOG_FILE"
    fi
}

# 错误日志
log_error() {
    if [[ "$USE_COLOR" == true ]]; then
        echo -e "${RED}[错误]${NC} $*"
    else
        echo "[错误] $*"
    fi
    log_to_file "错误" "$*"
}

# 警告日志
log_warn() {
    if [[ "$USE_COLOR" == true ]]; then
        echo -e "${YELLOW}[警告]${NC} $*"
    else
        echo "[警告] $*"
    fi
    log_to_file "警告" "$*"
}

# 信息日志
log_info() {
    if [[ "$USE_COLOR" == true ]]; then
        echo -e "${BLUE}[信息]${NC} $*"
    else
        echo "[信息] $*"
    fi
    log_to_file "信息" "$*"
}

# 成功消息
log_success() {
    if [[ "$USE_COLOR" == true ]]; then
        echo -e "${GREEN}[成功]${NC} $*"
    else
        echo "[成功] $*" 
    fi
    log_to_file "成功" "$*"
}

# 分节标题
log_section() {
    echo ""
    if [[ "$USE_COLOR" == true ]]; then
        echo -e "${BLUE}========== $* ==========${NC}"
    else
        echo "========== $* =========="
    fi
    echo ""
    log_to_file "分节" "$*"
}