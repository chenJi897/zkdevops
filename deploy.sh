#!/bin/bash

# 大运维平台自动部署脚本 - 第一版
# 日期: 2025-04-27
# 作者: chenJi897

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

示例:
    $0 --arch=ha --modules=mysql,redis
    $0 --version=2.0 --modules=all
EOF
}



# 默认主配置文件路径
MAIN_CONFIG_FILE="$SCRIPT_DIR/deploy.conf"

# 加载配置函数修改
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
    # 这个配置会覆盖主配置文件和架构配置
    if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
        log_info "加载自定义配置: $CONFIG_FILE"
        source "$CONFIG_FILE"
    fi
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
            *)
                echo "未知选项: $arg"
                ;;
        esac
    done
    
    # 初始化日志
    log_init "$LOG_FILE"
    
    log_info "部署配置:"
    log_info "- 平台: $PLATFORM"
    log_info "- 版本: $APP_VERSION"
    log_info "- 架构: $ARCHITECTURE" 
    log_info "- 模块: ${MODULES:-全部}"
    log_info "- 日志文件: $LOG_FILE"
}

# 加载配置
load_config() {
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
    
    # 加载自定义配置（如果指定）
    if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
        log_info "加载自定义配置: $CONFIG_FILE"
        source "$CONFIG_FILE"
    fi
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
    local deploy_args="--arch=$ARCHITECTURE"
    
    # 执行部署脚本
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

