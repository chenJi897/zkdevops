#!/bin/bash

# 配置需要检查的目录路径，支持多个
DIRS=(
 "/root/testlog1"
 "/root/testlog2"
)
DISK_THRESHOLD=80     # 磁盘使用率报警阈值
TARGET_USAGE=70       # 目标使用率，清理时会努力达到这个值
DAYS_TO_KEEP=2        # 日志文件保留天数
CHECK_INTERVAL=10     # 每清理多少个文件检查一次磁盘使用率

# 定义需要排除的文件列表
EXCLUDE_FILES=(
    "drtel-sms-operations.jar.log"
    "drtel-sms.jar.log"
    "drtel-sms-report.jar.log"
    "drtel-sms-mms.jar.log"
    "drtel-sms-numcode.jar.log"
    "drtel-sms-send-message.jar.log"
    "drtel-sms-chatbot.jar.log"
    "drtel-sms-cmm.jar.log"
    "drtel-sms-aim.jar.log"
    "drtel-sms-statistics.jar.log"
)

# 获取目录所在磁盘的使用率
get_disk_usage() {
  df -h "$1" | awk 'NR==2 {print $5}' | sed 's/%//'
}

# 获取目录所在的文件系统
get_filesystem() {
    df "$1" | awk 'NR==2 {print $1}'
}


# 检查文件是否在排除列表中
is_excluded() {
    local filename=$(basename "$1")
    for exclude in "${EXCLUDE_FILES[@]}"; do
        if [[ "$filename" == "$exclude" ]]; then
            return 0
        fi
    done
    return 1
}

# 检查磁盘使用率是否达到目标
check_disk_usage() {
    local dir=$1
    local usage=$(get_disk_usage "$dir")
    echo "当前磁盘使用率: $usage%"
    if [[ $usage -le $TARGET_USAGE ]]; then
        return 0  # 达到目标
    fi
    return 1     # 未达到目标
}

# 清理日志文件
clean_logs() {
  local dir=$1
  local cleaned_count=0
  local total_files=0
  echo "清理目录：$dir"

  # 获取需要处理的文件总数（不包括排除的文件）
  for file in "$dir"/*; do
    if [ -f "$file" ] && ! is_excluded "$file"; then
      ((total_files++))
    fi
  done

  echo "需要处理的文件总数: $total_files"

  # 创建临时文件存储排序后的文件列表
  local temp_file=$(mktemp)
  find "$dir" -type f -printf "%T@ %p\n" | sort -n | awk '{print $2}' > "$temp_file"

  # 读取排序后的文件列表并处理
  while read -r log; do
    # 检查文件是否在排除列表中
    if is_excluded "$log"; then
        echo "跳过排除文件：$log"
        continue
    fi

    # 判断日志文件是否超过保留天数
    if [ -f "$log" ] && [ -n "$(find "$log" -type f -mtime -$DAYS_TO_KEEP)" ]; then
      echo "触发告警：日志文件 $log 在 $DAYS_TO_KEEP 天内"
    else
      echo "清理日志文件：$log"
      rm -f "$log"
      ((cleaned_count++))
    fi

    # 在以下情况检查磁盘使用率：
    # 1. 已清理指定数量的文件
    # 2. 或者这是最后一个文件
    if [ $((cleaned_count % CHECK_INTERVAL)) -eq 0 ] || [ $cleaned_count -eq $total_files ]; then
      if check_disk_usage "$dir"; then
        echo "磁盘使用率已降至目标值 $TARGET_USAGE% 以下，停止清理"
        rm -f "$temp_file"  # 清理临时文件
        return 0
      fi
    fi
  done < "$temp_file"

  # 清理临时文件
  rm -f "$temp_file"

  # 清理完成后最后检查一次
  usage=$(get_disk_usage "$dir")
  echo "清理完成后磁盘使用率: $usage%"
  if [ $usage -ge $DISK_THRESHOLD ]; then
    echo "警告：清理完成后磁盘使用率仍然高于阈值($DISK_THRESHOLD%)，建议检查是否有其他大文件占用空间"
  fi
}
# 主流程
main() {
    echo "开始磁盘清理脚本"
    
    # 用来记录已处理过的文件系统
    declare -A processed_filesystems

    for dir in "${DIRS[@]}"; do
        echo "检查目录：$dir"
        if [ ! -d "$dir" ]; then
            echo "目录 $dir 不存在，跳过"
            continue
        fi

        # 获取当前目录所在的文件系统
        filesystem=$(get_filesystem "$dir")
        
        # 如果这个文件系统已经处理过且达标，则跳过
        if [ "${processed_filesystems[$filesystem]}" = "done" ]; then
            echo "目录 $dir 所在的文件系统 $filesystem 已经处理过且达到目标使用率，跳过"
            continue
        fi

        # 获取当前目录磁盘使用率
        usage=$(get_disk_usage "$dir")
        echo "目录 $dir 的磁盘使用率：$usage%"

        if [ $usage -ge $DISK_THRESHOLD ]; then
            echo "标记目录 $dir 为需要清理"
            clean_logs "$dir"
            
            # 再次检查使用率
            usage=$(get_disk_usage "$dir")
            if [ $usage -le $TARGET_USAGE ]; then
                echo "文件系统 $filesystem 已达到目标使用率，标记为已处理"
                processed_filesystems[$filesystem]="done"
            fi
        else
            echo "目录 $dir 的磁盘使用率未超过 $DISK_THRESHOLD%，跳过"
            # 如果使用率本来就低于阈值，也标记这个文件系统为已处理
            processed_filesystems[$filesystem]="done"
        fi
    done

    echo "磁盘清理脚本完成"
}

# 执行主流程
main
