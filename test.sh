#!/bin/bash

# 配置需要检查的目录路径，支持多个
DIRS=(
 "/home/template/log"
)
DISK_THRESHOLD=75  # 磁盘使用率阈值
DAYS_TO_KEEP=2     # 日志文件保留天数

# 获取目录所在磁盘的使用率
get_disk_usage() {
  df -h "$1" | awk 'NR==2 {print $5}' | sed 's/%//'
}

# 清理日志文件
clean_logs() {
  local dir=$1
  echo "清理目录：$dir"

  # 按时间排序日志文件列表
  logs=$(find "$dir" -type f  -printf "%T@ %p\n" | sort -n | awk '{print $2}')

  for log in $logs; do
    # 判断日志文件是否超过保留天数
    if [[ $(find "$log" -type f -mtime -$DAYS_TO_KEEP) ]]; then
      echo "触发告警：日志文件 $log 在 $DAYS_TO_KEEP 天内"
      # 通知逻辑 (示例仅为输出)
      #echo "通知相关人员处理 $log"
    else
      echo "清理日志文件：$log"
    fi

    # 清理后检查磁盘使用率
    usage=$(get_disk_usage "$dir")
    if [[ $usage -le $DISK_THRESHOLD ]]; then
      echo "磁盘使用率降至 $DISK_THRESHOLD% 以下，停止清理"
      break
    fi
  done
}

# 主流程
main() {
  echo "开始磁盘清理脚本"

  for dir in "${DIRS[@]}"; do
    echo "检查目录：$dir"
    if [[ ! -d "$dir" ]]; then
      echo "目录 $dir 不存在，跳过"
      continue
    fi

    # 获取当前目录磁盘使用率
    usage=$(get_disk_usage "$dir")
    echo "目录 $dir 的磁盘使用率：$usage%"

    if [[ $usage -ge $DISK_THRESHOLD ]]; then
      echo "标记目录 $dir 为需要清理"
      clean_logs "$dir"
    else
      echo "目录 $dir 的磁盘使用率未超过 $DISK_THRESHOLD%，跳过"
    fi
  done

  echo "磁盘清理脚本完成"
}

# 执行主流程
main

