#!/bin/bash

# 大运维平台自动部署脚本 - 第一版
# 日期: 2025-04-28
# 作者: chenJi897

# 检查是否使用bash运行
if [ -z "$BASH_VERSION" ]; then
    echo "错误: 此脚本必须使用bash运行" >&2
    exit 1
fi

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 导入共享库
source "${SCRIPT_DIR}/lib/log.sh"
source "${SCRIPT_DIR}/lib/utils.sh"

# 脚本版本
VERSION="1.0.0"

# 默认配置
PLATFORM="centos"       # 目前只支持centos
APP_VERSION="1.0"       # 默认版本
ARCHITECTURE="standalone" # 默认架构
CONFIG_FILE=""          # 自定义配置文件
MODULES=""              # 要部署的模块
LOG_FILE="/tmp/deploy_$(date +%Y%m%d%H%M%S).log" # 日志文件
MODULES_TO_DEPLOY=()    # 要部署的模块数组
DEBUG=false             # 调试模式

# 错误标志
INVALID_ARGS=false

# 保存命令行参数值，避免被配置文件覆盖
CMDLINE_MYSQL_PORT=""
CMDLINE_MYSQL_PASSWORD=""
CMDLINE_MYSQL_DATA_DIR=""
CMDLINE_REDIS_PORT=""
CMDLINE_REDIS_PASSWORD=""
CMDLINE_REDIS_DATA_DIR=""

# 显示帮助信息
show_help() {
    cat << EOF
大运维平台自动部署脚本 v${VERSION}

使用方法:
    $0 [选项]

选项:
    --version=VERSION     指定部署版本 (默认: 1.0)
    --arch=TYPE           指定架构类型 (standalone|ha) (默认: standalone)
    --modules=LIST        指定要安装的模块，逗号分隔 (如: mysql,redis,nacos)
    --config=FILE         指定配置文件
    --log=FILE            指定日志文件
    --list-modules        列出可用模块
    --help                显示此帮助信息
    
    # MySQL特定参数
    --mysql-port=NUM      指定MySQL端口
    --mysql-password=PASS 指定MySQL密码
    --mysql-data-dir=PATH 指定MySQL数据目录
    
    # Redis特定参数
    --redis-port=NUM      指定Redis端口
    --redis-password=PASS 指定Redis密码
    --redis-data-dir=PATH 指定Redis数据目录
    
    # 调试选项
    --debug               启用调试模式

示例:
    $0 --arch=ha --modules=mysql,redis
    $0 --version=2.0 --modules=all
    $0 --modules=mysql --mysql-port=3308 --mysql-password="NewPwd2025"
EOF
}

# 默认主配置文件路径
MAIN_CONFIG_FILE="$SCRIPT_DIR/deploy.conf"

# 加载配置函数
load_config() {
    # 首先加载主配置文件（如果存在）
    if [[ -f "$MAIN_CONFIG_FILE" ]]; then
        log_info "加载主配置文件: $MAIN_CONFIG_FILE"
        source "$MAIN_CONFIG_FILE"
    fi
    
    # 加载版本配置（如果存在）
    if [[ -f "${SCRIPT_DIR}/config/versions/${APP_VERSION}.conf" ]]; then
        log_info "加载版本配置: $APP_VERSION"
        source "${SCRIPT_DIR}/config/versions/${APP_VERSION}.conf"
    fi
    
    # 加载架构配置（如果存在）
    if [[ -f "${SCRIPT_DIR}/config/architectures/${ARCHITECTURE}.conf" ]]; then
        log_info "加载架构配置: $ARCHITECTURE"
        source "${SCRIPT_DIR}/config/architectures/${ARCHITECTURE}.conf"
    fi
    
    # 加载用户指定的自定义配置（如果指定）
    if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
        log_info "加载自定义配置: $CONFIG_FILE"
        source "$CONFIG_FILE"
    fi
    
    # 恢复命令行参数值，使命令行参数优先级高于配置文件
    [[ -n "$CMDLINE_MYSQL_PORT" ]] && MYSQL_PORT="$CMDLINE_MYSQL_PORT"
    [[ -n "$CMDLINE_MYSQL_PASSWORD" ]] && MYSQL_PASSWORD="$CMDLINE_MYSQL_PASSWORD"
    [[ -n "$CMDLINE_MYSQL_DATA_DIR" ]] && MYSQL_DATA_DIR="$CMDLINE_MYSQL_DATA_DIR"
    [[ -n "$CMDLINE_REDIS_PORT" ]] && REDIS_PORT="$CMDLINE_REDIS_PORT"
    [[ -n "$CMDLINE_REDIS_PASSWORD" ]] && REDIS_PASSWORD="$CMDLINE_REDIS_PASSWORD"
    [[ -n "$CMDLINE_REDIS_DATA_DIR" ]] && REDIS_DATA_DIR="$CMDLINE_REDIS_DATA_DIR"
    
    # 输出调试信息
    if [[ "$DEBUG" == "true" ]]; then
        log_info "配置加载后的值:"
        log_info "- MYSQL_PORT = $MYSQL_PORT"
        log_info "- MYSQL_PASSWORD = $MYSQL_PASSWORD"
        log_info "- MYSQL_DATA_DIR = $MYSQL_DATA_DIR"
        log_info "- REDIS_PORT = $REDIS_PORT"
        log_info "- REDIS_PASSWORD = $REDIS_PASSWORD"
    fi
    
    # 导出关键配置变量，使它们对子进程可见
    export MYSQL_PORT
    export MYSQL_PASSWORD
    export MYSQL_DATA_DIR
    export MYSQL_MAX_CONNECTIONS
    export MYSQL_BUFFER_POOL_SIZE_PERCENT
    
    export REDIS_PORT
    export REDIS_PASSWORD
    export REDIS_DATA_DIR
    export REDIS_MAX_MEMORY
    
    export ROCKETMQ_NAMESRV_PORT
    export ROCKETMQ_BROKER_PORT
    export ROCKETMQ_DATA_DIR
    export ROCKETMQ_NAMESRV_MEMORY
    export ROCKETMQ_BROKER_MEMORY
    
    export NACOS_PORT
    export NACOS_HOME
    export NACOS_DB_TYPE
    export NACOS_JVM_XMS
    export NACOS_JVM_XMX
    
    export ES_PORT
    export ES_DATA_DIR
    export ES_JVM_SIZE
    
    export DEPLOY_VERSION
    export DEPLOY_ARCH
    export ARCHITECTURE
}

# 列出可用模块
list_modules() {
    echo "可用模块列表:"
    local found_modules=false
    
    for module_dir in "${SCRIPT_DIR}/modules"/*; do
        if [[ -d "$module_dir" && -f "$module_dir/deploy.sh" ]]; then
            found_modules=true
            local module_name=$(basename "$module_dir")
            local description=""
            
            # 尝试读取模块描述
            if [[ -f "$module_dir/info.txt" ]]; then
                description=$(head -n 1 "$module_dir/info.txt")
            fi
            
            echo "  - $module_name: ${description:-无描述}"
        fi
    done
    
    if [[ "$found_modules" == "false" ]]; then
        echo "  当前没有可用模块。请确保模块目录中包含有效的部署脚本。"
    fi
}

# 解析命令行参数
parse_args() {
    for arg in "$@"; do
        case $arg in
            --version=*)
                APP_VERSION="${arg#*=}"
                ;;
            --arch=*)
                ARCHITECTURE="${arg#*=}"
                ;;
            --modules=*)
                MODULES="${arg#*=}"
                ;;
            --config=*)
                CONFIG_FILE="${arg#*=}"
                ;;
            --log=*)
                LOG_FILE="${arg#*=}"
                ;;
            --list-modules)
                list_modules
                exit 0
                ;;
            --help)
                show_help
                exit 0
                ;;
            --debug)
                DEBUG=true
                export DEBUG
                ;;
            # MySQL特定参数 - 保存到专门的命令行参数变量
            --mysql-port=*)
                CMDLINE_MYSQL_PORT="${arg#*=}"
                MYSQL_PORT="$CMDLINE_MYSQL_PORT"  # 也设置常规变量，确保优先生效
                ;;
            --mysql-password=*)
                CMDLINE_MYSQL_PASSWORD="${arg#*=}"
                MYSQL_PASSWORD="$CMDLINE_MYSQL_PASSWORD"
                ;;
            --mysql-data-dir=*)
                CMDLINE_MYSQL_DATA_DIR="${arg#*=}"
                MYSQL_DATA_DIR="$CMDLINE_MYSQL_DATA_DIR"
                ;;
            # Redis特定参数
            --redis-port=*)
                CMDLINE_REDIS_PORT="${arg#*=}"
                REDIS_PORT="$CMDLINE_REDIS_PORT"
                ;;
            --redis-password=*)
                CMDLINE_REDIS_PASSWORD="${arg#*=}"
                REDIS_PASSWORD="$CMDLINE_REDIS_PASSWORD"
                ;;
            --redis-data-dir=*)
                CMDLINE_REDIS_DATA_DIR="${arg#*=}"
                REDIS_DATA_DIR="$CMDLINE_REDIS_DATA_DIR"
                ;;
            *)
                echo "错误: 无效的参数 '$arg'"
                echo "使用 --help 查看帮助信息"
                INVALID_ARGS=true
                ;;
        esac
    done
    
    # 初始化日志
    log_init "$LOG_FILE"
    
    # 如果有无效参数，显示帮助信息并退出
    if [[ "$INVALID_ARGS" == "true" ]]; then
        echo ""
        echo "存在无效参数，部署终止。请检查参数后重试。"
        echo ""
        show_help
        exit 1
    fi
    
    # 调试信息
    if [[ "$DEBUG" == "true" ]]; then
        log_info "命令行解析的参数:"
        [[ -n "$CMDLINE_MYSQL_PORT" ]] && log_info "- CMDLINE_MYSQL_PORT = $CMDLINE_MYSQL_PORT"
        [[ -n "$CMDLINE_MYSQL_PASSWORD" ]] && log_info "- CMDLINE_MYSQL_PASSWORD = $CMDLINE_MYSQL_PASSWORD"
        [[ -n "$CMDLINE_REDIS_PORT" ]] && log_info "- CMDLINE_REDIS_PORT = $CMDLINE_REDIS_PORT"
    fi
    
    log_info "部署配置:"
    log_info "- 平台: $PLATFORM"
    log_info "- 版本: $APP_VERSION"
    log_info "- 架构: $ARCHITECTURE" 
    log_info "- 模块: ${MODULES:-全部}"
    log_info "- 日志文件: $LOG_FILE"
    [[ "$DEBUG" == "true" ]] && log_info "- 调试模式: 已启用"
}

# 获取要部署的模块列表
get_modules_to_deploy() {
    local modules_array=()
    
    if [[ -z "$MODULES" || "$MODULES" == "all" ]]; then
        # 获取所有可用模块
        for module_dir in "${SCRIPT_DIR}/modules"/*; do
            if [[ -d "$module_dir" && -f "$module_dir/deploy.sh" ]]; then
                local module_name=$(basename "$module_dir")
                modules_array+=("$module_name")
            fi
        done
    else
        # 解析指定的模块
        IFS=',' read -ra modules_array <<< "$MODULES"
    fi
    
    MODULES_TO_DEPLOY=("${modules_array[@]}")
    
    if [[ ${#MODULES_TO_DEPLOY[@]} -eq 0 ]]; then
        log_info "没有找到可部署的模块"
    else
        log_info "将部署以下模块: ${MODULES_TO_DEPLOY[*]}"
    fi
}

# 检查环境
check_environment() {
    log_section "环境检查"
    
    # 检查是否以root运行
    check_root || {
        log_error "请以root用户运行此脚本"
        return 1
    }
    
    # 检查操作系统
    if [[ "$PLATFORM" == "centos" ]]; then
        if ! grep -qi "centos" /etc/redhat-release 2>/dev/null; then
            log_error "当前系统不是CentOS！"
            return 1
        fi
        
        # 检查CentOS版本
        local version=$(cat /etc/redhat-release 2>/dev/null | tr -dc '0-9.' | cut -d \. -f1)
        if [[ "$version" != "7" ]]; then
            log_warn "当前脚本主要支持CentOS 7，当前系统版本为 $version，可能会有兼容性问题"
        fi
    else
        log_error "不支持的平台: $PLATFORM"
        return 1
    fi
    
    # 检查必要命令
    for cmd in rpm yum systemctl tar; do
        if ! command -v $cmd &>/dev/null; then
            log_error "命令不存在: $cmd"
            return 1
        fi
    done
    
    log_success "环境检查通过"
    return 0
}

# 部署模块
deploy_module() {
    local module=$1
    local module_dir="${SCRIPT_DIR}/modules/$module"
    
    if [[ ! -d "$module_dir" ]]; then
        log_error "模块不存在: $module"
        return 1
    fi
    
    if [[ ! -f "$module_dir/deploy.sh" ]]; then
        log_error "模块部署脚本不存在: $module/deploy.sh"
        return 1
    fi
    
    log_section "部署模块: $module"
    
    # 构建部署参数
    local deploy_args=""
    
    # 通用参数
    deploy_args+=" --arch=$ARCHITECTURE"
    [[ "$DEBUG" == "true" ]] && deploy_args+=" --debug"
    
    # 模块特定参数 - 使用Case语句根据模块类型添加特定参数
    case $module in
        mysql)
            # 直接使用port而非mysql-port，因为模块脚本接受的是--port参数
            [[ -n "$MYSQL_PORT" ]] && deploy_args+=" --port=$MYSQL_PORT"
            [[ -n "$MYSQL_PASSWORD" ]] && deploy_args+=" --password=$MYSQL_PASSWORD"
            [[ -n "$MYSQL_DATA_DIR" ]] && deploy_args+=" --data-dir=$MYSQL_DATA_DIR"
            ;;
        redis)
            [[ -n "$REDIS_PORT" ]] && deploy_args+=" --port=$REDIS_PORT"
            [[ -n "$REDIS_PASSWORD" ]] && deploy_args+=" --password=$REDIS_PASSWORD"
            [[ -n "$REDIS_DATA_DIR" ]] && deploy_args+=" --data-dir=$REDIS_DATA_DIR"
            ;;
        nacos)
            [[ -n "$NACOS_PORT" ]] && deploy_args+=" --port=$NACOS_PORT"
            [[ -n "$NACOS_DB_TYPE" ]] && deploy_args+=" --db-type=$NACOS_DB_TYPE"
            ;;
        # 其他模块参数可以根据需要添加
    esac
    
    # 打印执行命令(调试模式)
    if [[ "$DEBUG" == "true" ]]; then
        log_info "执行命令: bash \"$module_dir/deploy.sh\"$deploy_args"
    fi
    
    # 执行部署脚本 - 修正命令格式，确保在脚本路径和参数之间有空格
    bash "$module_dir/deploy.sh" $deploy_args
    
    local status=$?
    if [[ $status -eq 0 ]]; then
        log_success "模块 $module 部署成功"
        return 0
    else
        log_error "模块 $module 部署失败 (错误码: $status)"
        return $status
    fi
}

# 部署所有指定模块
deploy_modules() {
    log_section "开始部署模块"
    
    if [[ ${#MODULES_TO_DEPLOY[@]} -eq 0 ]]; then
        log_warn "没有可部署的模块，部署过程已跳过"
        return 0
    fi
    
    local success_modules=()
    local failed_modules=()
    
    for module in "${MODULES_TO_DEPLOY[@]}"; do
        deploy_module "$module"
        
        if [[ $? -eq 0 ]]; then
            success_modules+=("$module")
        else
            failed_modules+=("$module")
        fi
    done
    
    # 显示部署结果
    log_section "部署结果"
    
    if [[ ${#success_modules[@]} -gt 0 ]]; then
        log_success "成功部署的模块: ${success_modules[*]}"
    fi
    
    if [[ ${#failed_modules[@]} -gt 0 ]]; then
        log_error "部署失败的模块: ${failed_modules[*]}"
        return 1
    fi
    
    return 0
}

# 主函数
main() {
    log_section "大运维平台部署开始 (v$VERSION)"
    
    # 解析参数
    parse_args "$@"
    
    # 加载配置
    load_config
    
    # 检查环境
    check_environment || {
        log_error "环境检查失败，终止部署"
        return 1
    }
    
    # 获取要部署的模块
    get_modules_to_deploy
    
    # 部署模块
    deploy_modules
    local deploy_status=$?
    
    if [[ $deploy_status -eq 0 ]]; then
        log_section "部署完成"
        log_success "部署成功！"
    else
        log_section "部署完成"
        log_error "部署过程中出现错误，请检查日志"
    fi
    
    log_info "部署摘要:"
    log_info "- 平台: $PLATFORM"
    log_info "- 版本: $APP_VERSION"
    log_info "- 架构: $ARCHITECTURE"
    log_info "- 日志文件: $LOG_FILE"
    
    return $deploy_status
}

# 执行主函数
main "$@"