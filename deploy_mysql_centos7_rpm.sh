#!/bin/bash
#!/bin/sh
# 脚本版本
G_modify_date="2025/04/02"
echo "======>>>>>> 脚本版本号：$G_modify_date"

#########  启动命令  ###########
###    一定要使用 bash命令执行，否则识别进程会有问题
###    bash ./deploy_mysql_centos7_offline.sh data_dir=/var/lib/mysql port=3306 password=123456 rpm_dir=/path/to/rpm
###
##################################

# 使用无冲突参数名
declare -A defaults=(
    [env_check]=true
    [os_parameter]=true
    [port]=3306
    [password]=T3mp@Apr2025
    [data_dir]=/var/lib/mysql
    [rpm_dir]=/tmp/mysql_rpm
)

for param in "$@"; do
    if [[ "$param" == *=* ]]; then
        key="${param%%=*}"
        value="${param#*=}"

        # 兼容性键值存在校验
        if [[ ${defaults[$key]+isset} ]]; then
            defaults[$key]="$value"
        else
            printf "未知参数: %s，有效参数为: %s\n" "$key" "${!defaults[*]}" >&2
            exit 1
        fi
    else
        echo "参数格式错误: $param，应使用 key=value 格式" >&2
        exit 1
    fi
done

################################################################ 脚本变量 >> 开始
# 是否进行环境检查
G_is_environment_check=${defaults[env_check]}
# 是否修改服务器环境参数
G_is_adjust_parameter=${defaults[os_parameter]}

# mysql 端口号
G_mysql_port=${defaults[port]}
# mysql 密码
G_mysql_pwd=${defaults[password]}

## 数据目录
G_data_dir=${defaults[data_dir]}
## RPM包目录
G_rpm_dir=${defaults[rpm_dir]}

echo "配置参数："
echo "环境检查 = $G_is_environment_check"
echo "修改服务器参数 = $G_is_adjust_parameter"
echo "mysql端口号 = $G_mysql_port"
echo "mysql密码 = $G_mysql_pwd"
echo "安装目录 = /usr"
echo "数据目录 = $G_data_dir"
echo "RPM包目录 = $G_rpm_dir"

################################################################ 脚本变量 >> 结束

################################################################ 基础方法 >> 开始
## 脚本 提示信息
F_scriptTips(){
  echo "如果正常脚本执行后，应用无法访问或一键安装脚本无法进行"
  echo "1、检查脚本执行服务器操作系统是否匹配"
  echo "2、请检查rpm包是否完整并上传到正确的目录"
  echo "3、服务端口冲突，相同的服务已在运行，处理后才能重新安装"
  return 0
}
## 创建目录
F_createFold(){
    if [[ ! -d $1 ]];then
        echo "======>>>>>> 创建目录：command:mkdir -p $1"
        mkdir -p "$1"
    fi
}
## 验证文件是否存在
F_verifySoft(){
    if [[ -f $1 ]];then
        return 0
    else
        return 1
    fi
}
################################################################ 基础方法 >> 结束

################################################################ Linux环境检查 >> 开始
## 环境检查
function F_environmentCheck(){
    echo "======>>>>>> Linux环境检查：开始.........."
    #### 检查rpm
    which rpm>/dev/null
    rpmRes=$?
    if [[ $rpmRes -ne 0 ]];then
      echo ""
      echo ""
      echo ""
        echo "======>>>>>> ！！！ 环境检查失败，rpm 命令不存在，请检查rpm是否安装。"
        echo ""
      echo ""
      echo ""
        F_scriptTips
        exit 1
    fi


    #### 检查命令 verify command,netstat
    which netstat>/dev/null
    netstatRes=$?
    if [[ $netstatRes -ne 0 ]];then
      echo ""
      echo ""
      echo ""
        echo "======>>>>>> ！！！安装检查失败,netstat 命令不存在,请先安装，缺少相关netstat等相关命令。"
        echo ""
      echo ""
      echo ""
        F_scriptTips
        exit 1
    fi
    #### 检查操作系统
    osname=$(uname)
    if [[ $osname == "Linux" ]];then
      echo "======>>>>>> 操作系统正常"
    else
      echo "======>>>>>> 请使用Limux系统安装，当前系统为 $osname,目前支持 redhat 7.9|6.0CentOS 7.9 或 8.0,其他系统暂不支持"
      echo "======>>>>>> 支持 redhat 7.9,6.0"
      echo "======>>>>>> 支持 centos 7.9,6.0"
      echo "======>>>>>> other os not support!"
      F_scriptTips
      exit 1
    fi

    # 检查CentOS版本
    if [ -f /etc/centos-release ]; then
        version=$(cat /etc/centos-release | tr -dc '0-9.' | cut -d \. -f1)
        if [[ "$version" != "7" ]]; then
            echo "======>>>>>> 当前脚本仅支持CentOS 7，当前系统版本为 $version"
            F_scriptTips
            exit 1
        fi
    else
        echo "======>>>>>> 未找到CentOS版本信息，请确保使用CentOS 7系统"
        F_scriptTips
        exit 1
    fi

    #### 检查内存
    echo "======>>>>>> 开始检查内存"
    # 内存要求（M）
    support_memory=1500

    total_mem=$(free -m|grep Mem|awk '{print $2}')
    if [[ $total_mem -lt $support_memory ]];then
      echo "======>>>>>> ！！！当前系统内存:${total_mem}m,要求：${support_memory}m 或更高，内存太低了"
      F_scriptTips
      exit 1
    fi

    # 检查RPM包目录
    if [[ ! -d "$G_rpm_dir" ]]; then
        echo "======>>>>>> ！！！RPM包目录 $G_rpm_dir 不存在，请确保目录已创建并上传了MySQL RPM包"
        F_scriptTips
        exit 1
    fi

    # 检查RPM包文件
    rpm_count=$(find "$G_rpm_dir" -name "*.rpm" | wc -l)
    if [[ $rpm_count -eq 0 ]]; then
        echo "======>>>>>> ！！！未在 $G_rpm_dir 目录下找到任何RPM包，请确保已上传MySQL RPM包"
        F_scriptTips
        exit 1
    fi

    # 检查是否安装了MariaDB
    if rpm -qa | grep -i mariadb >/dev/null; then
        echo "======>>>>>> 检测到系统已安装MariaDB，安装MySQL前需要卸载MariaDB"
        echo "======>>>>>> 请运行以下命令卸载MariaDB后再次运行本脚本:"
        echo "systemctl stop mariadb"
        echo "rpm -e --nodeps \$(rpm -qa | grep -i mariadb)"
        echo "rm -rf /var/lib/mysql"
        echo "rm -rf /etc/my.cnf /etc/my.cnf.d"
	yum remove mariadb-libs.x86_64 -y
    fi

    echo "======>>>>>> Linux环境检查：结束!"
}
# 联网情况下 进行环境检查
if [[ "$G_is_environment_check" == "true" ]];then
    F_environmentCheck
fi
################################################################ Linux环境检查 >> 结束

################################################################ 设置服务器参数 >> 开始

## 设置系统参数
function F_adjustParameter(){
  echo "======>>>>>> 设置服务器参数：开始............"
  #redis
  echo "vm.overcommit_memory = 1 to sysctl.conf"
  sed -i '/vm.overcommit_memory/d' /etc/sysctl.conf
  echo "vm.overcommit_memory = 1">>/etc/sysctl.conf
  echo "net.core.somaxconn = 1024 to sysctl.conf"
  sed -i '/net.core.somaxconn/d' /etc/sysctl.conf
  echo "net.core.somaxconn = 1024">>/etc/sysctl.conf
  #comon
  echo "fs.aio-max-nr = 1048576 to sysctl.conf "
  sed -i '/fs.aio-max-nr/d' /etc/sysctl.conf
  echo "fs.aio-max-nr = 1048576">>/etc/sysctl.conf
  echo "fs.file-max = 6815744 to sysctl.conf"
  sed -i '/fs.file-max/d' /etc/sysctl.conf
  echo "fs.file-max = 6815744">>/etc/sysctl.conf
  echo "vm.swappiness to sysctl.conf"
  sed -i '/vm.swappiness/d' /etc/sysctl.conf
  echo "vm.swappiness = 5">>/etc/sysctl.conf
  sysctl -p
  #selinux
  echo "to close selinux"
  echo "SELINUX=disabled to /etc/selinux/config"
  sed -i '/SELINUX=/d' /etc/selinux/config
  echo "SELINUX=disabled">>/etc/selinux/config
  setenforce 0
  #limits.conf
  sed -i '/nofile/d' /etc/security/limits.conf
  echo "* soft nofile 65535">>/etc/security/limits.conf
  echo "* hard nofile 65535">>/etc/security/limits.conf
  sed -i '/nproc/d' /etc/security/limits.conf
  echo "* soft nproc 16384">>/etc/security/limits.conf
  echo "* hard nproc 16384">>/etc/security/limits.conf

  echo "======>>>>>> 设置服务器参数：结束!"
  return 0
}

# 设置系统参数
if [[ "$G_is_adjust_parameter" == "true" ]];then
    F_adjustParameter
fi

################################################################ 设置服务器参数 >> 结束


################################################################ Mysql 安装脚本 >> 开始
# 部署 mysql
F_deploy_mysql(){
  # mysql配置文件 my.cnf
  L_MYSQL_CNF=/etc/my.cnf

  ## 提示：删除mysql
  function F_mysql_clearTips(){
    echo "======>>>>>> 提示：检测到mysql已存在，如需重装请删除mysql"
    echo ">> 如果想重新安装mysql，请执行以下命令"
    echo ">> systemctl stop mysqld"
    echo ">> rpm -e --nodeps \$(rpm -qa | grep -i mysql)"
    echo ">> rm -rf $L_MYSQL_HOME"
    echo ">> rm -rf /var/lib/mysql"
    echo ">> rm -rf /etc/my.cnf*"
  }
  
  ## mysql 命令提示
  function F_mysql_cmdTips(){
    echo "======>>>>>> ===========###  MYSQL 操作命令  ###========="
    echo "======>>>>>> 启   动：systemctl start mysqld"
    echo "======>>>>>> 停   止：systemctl stop mysqld"
    echo "======>>>>>> 查看状态：systemctl status mysqld"
    echo "======>>>>>> ==========================================="
  }

  ## 安装Mysql
  function F_mysql_install(){
    echo "======>>>>>> 开始安装 mysql.........."

    # 检查是否已安装MySQL
    if rpm -qa | grep -i mysql >/dev/null; then
      echo "======>>>>>> MySQL已经安装，请先卸载后重新安装"
      F_mysql_clearTips
      exit 1
    fi


 # 如果使用默认目录，不需要创建；如果自定义目录，需要判断权限
if [[ "$G_data_dir" != "/var/lib/mysql" ]]; then
  if [[ -d "$G_data_dir" ]]; then
    echo "======>>>>>> 自定义数据目录 [$G_data_dir] 已存在，请确认是否已使用过，建议删除后再重试"
    F_mysql_clearTips
    exit 1
  else
    echo "======>>>>>> 创建自定义数据目录 $G_data_dir"
    mkdir -p "$G_data_dir"
    chown -R mysql:mysql "$G_data_dir"
    echo "======>>>>>> 自定义数据目录权限设置完成"
  fi
else
  echo "======>>>>>> 使用默认数据目录 [$G_data_dir]，不创建，由系统初始化"
fi


    # 检查配置文件是否存在
    if [[ -f "$L_MYSQL_CNF" ]]; then
      d=$(date "+%Y_%m_%d_%H_%M_%S")
      mv ${L_MYSQL_CNF} ${L_MYSQL_CNF}."$d"
      echo "======>>>>>> 已备份原有MySQL配置文件到 ${L_MYSQL_CNF}.$d"
    fi

    # 安装MySQL依赖包
    echo "======>>>>>> 安装MySQL依赖包..."
    yum -y install libaio numactl-libs

    # 安装所有RPM包
    echo "======>>>>>> 开始安装MySQL RPM包..."
    rpm -ivh ${G_rpm_dir}/*.rpm
    if [ $? -ne 0 ]; then
      echo "======>>>>>> MySQL RPM包安装失败，请检查RPM包是否完整或有依赖问题"
      F_mysql_clearTips
      exit 1
    fi
    echo "======>>>>>> MySQL RPM包安装成功"

    # 创建配置文件
    echo "======>>>>>> 配置MySQL..."

    # 缓冲池的大小计算
    innodb_buffer_pool_size=1024;
    total_mem=$(free -m|grep Mem|awk '{print $2}')
    innodb_buffer_pool_size_pre=$(echo "$total_mem"|awk '{printf "%d",$1*0.5*0.75}')
    #<2048
    if [[ $total_mem -lt 2048 ]];then
      innodb_buffer_pool_size=512
    fi
    #2048<=v<4096
    if [[ $total_mem -ge 2048 && $total_mem -lt 4096 ]];then
      innodb_buffer_pool_size=1024
    fi
    #4096<=v<8192
    if [[ $total_mem -ge 4096 && $total_mem -lt 8192 ]];then
      innodb_buffer_pool_size=2048
    fi
    #8192<=v<16384
    if [[ $total_mem -ge 8192 && $total_mem -lt 16384 ]];then
      innodb_buffer_pool_size=$innodb_buffer_pool_size_pre
    fi
    #v>16384
    if [[ $total_mem -ge 16384 ]];then
      innodb_buffer_pool_size=8192
    fi
    echo "======>>>>>> 设置缓冲池大小：${innodb_buffer_pool_size}m"

    # 创建my.cnf配置文件
    cat > $L_MYSQL_CNF <<EOF
###########################################################################
##客户端参数配置
###########################################################################
[client]
port=$G_mysql_port
socket=/var/lib/mysql/mysql.sock
default-character-set=utf8mb4

[mysql]
default-character-set=utf8mb4

###########################################################################
##服务端参数配置
###########################################################################
[mysqld]
port=$G_mysql_port
# 套接字文件
socket=/var/lib/mysql/mysql.sock
# Mysql安装的绝对路径
basedir=/usr
# Mysql数据存放的绝对路径
datadir=$G_data_dir
# 错误日志
log-error=/var/log/mysqld.log
pid-file=/var/run/mysqld/mysqld.pid

#只能用IP地址检查客户端的登录，不用主机名
#skip_name_resolve = 1

#时区设置
default_time_zone = "+8:00"

#数据库默认字符集, 主流字符集支持一些特殊表情符号（特殊表情符占用4个字节）
character-set-server = utf8mb4

#数据库字符集对应一些排序等规则，注意要和character-set-server对应
collation-server = utf8mb4_general_ci

#设置client连接mysql时的字符集,防止乱码
init_connect='SET NAMES utf8mb4'

#是否对sql语句大小写敏感，1表示不敏感
lower_case_table_names = 1

# 执行sql的模式，规定了sql的安全等级,
sql_mode="STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION"

#事务隔离级别，默认为可重复读，mysql默认可重复读级别（此级别下可能参数很多间隙锁，影响性能）
#transaction_isolation = READ-COMMITTED

#TIMESTAMP如果没有显示声明NOT NULL，允许NULL值
#explicit_defaults_for_timestamp = true

#它控制着mysqld进程能使用的最大文件描述(FD)符数量。
#需要注意的是这个变量的值并不一定是你设定的值，mysqld会在系统允许的情况下尽量获取更多的FD数量
#open_files_limit=65535

#最大连接数，默认为151
max_connections = 10000

#最大错误连接数
max_connect_errors = 2000

#在MySQL暂时停止响应新请求之前的短时间内多少个请求可以被存在堆栈中
#官方建议 back_log = 50 + (max_connections / 5),封顶数为65535,默认值= max_connections
#back_log = 110

# The number of open tables for all threads
# For example, for 200 concurrent running connections, specify a table cache size of at least 200 * N,
# where N is the maximum number of tables per join in any of the queries which you execute.
#table_open_cache = 600

# The number of table definitions that can be stored in the definition cache
# MIN(400 + table_open_cache / 2, 2000)
#table_definition_cache = 700

# 为了减少会话之间的争用，可以将opentables缓存划分为table_open_cache/table_open_cache_instances个小缓存
#table_open_cache_instances = 64

# 每个线程的堆栈大小 如果线程堆栈太小，则会限制执行复杂SQL语句
#thread_stack = 512K

# 禁止外部系统锁
#external-locking = FALSE

#SQL数据包发送的大小，如果有BLOB对象建议修改成1G
#max_allowed_packet = 1G

#order by 或group by 时用到
#建议先调整为4M，后期观察调整
#sort_buffer_size = 4M

#inner left right join时用到
#建议先调整为4M，后期观察调整
#join_buffer_size = 4M

# How many threads the server should cache for reuse.
# 如果您的服务器每秒达到数百个连接，则通常应将thread_cache_size设置得足够高，以便大多数新连接使用缓存线程
# default value = 8 + ( max_connections / 100) 上限为100
#thread_cache_size = 20

#MySQL连接闲置超过一定时间后(单位：秒)将会被强行关闭
#MySQL默认的wait_timeout  值为8个小时, interactive_timeout参数需要同时配置才能生效
interactive_timeout = 1800
wait_timeout = 1800

#Metadata Lock最大时长（秒）， 一般用于控制 alter操作的最大时长sine mysql5.6
#执行 DML操作时除了增加innodb事务锁外还增加Metadata Lock，其他alter（DDL）session将阻塞
lock_wait_timeout = 3600

#内部内存临时表的最大值。
#比如大数据量的group by ,order by时可能用到临时表，
#超过了这个值将写入磁盘，系统IO压力增大
tmp_table_size = 64M
max_heap_table_size = 64M

######################## 慢SQL日志记录 开始 ########################

#是否启用慢查询日志，1为启用，0为禁用
slow_query_log = 1

#记录系统时区
log_timestamps = SYSTEM

#指定慢查询日志文件的路径和名字
slow_query_log_file = /var/log/mysql-slow.log

#慢查询执行的秒数，必须达到此值可被记录
long_query_time = 5

#将没有使用索引的语句记录到慢查询日志
log_queries_not_using_indexes = 0

#设定每分钟记录到日志的未使用索引的语句数目，超过这个数目后只记录语句数量和花费的总时间
log_throttle_queries_not_using_indexes = 60

#对于查询扫描行数小于此参数的SQL，将不会记录到慢查询日志中
min_examined_row_limit = 5000

#记录执行缓慢的管理SQL，如alter table,analyze table, check table, create index, drop index, optimize table, repair table等。
log_slow_admin_statements = 0

#作为从库时生效, 从库复制中如何有慢sql也将被记录
log_slow_replica_statements = 1

######################## 慢SQL日志记录 结束 ########################


######################## MyISAM性能设置 开始 ########################

#对MyISAM表起作用，但是内部的临时磁盘表是MyISAM表，也要使用该值。
#可以使用检查状态值 created_tmp_disk_tables 得知详情
key_buffer_size = 15M

#对MyISAM表起作用，但是内部的临时磁盘表是MyISAM表，也要使用该值，
#例如大表order by、缓存嵌套查询、大容量插入分区。
read_buffer_size = 8M

#对MyISAM表起作用 读取优化
read_rnd_buffer_size = 4M

#对MyISAM表起作用 插入优化
bulk_insert_buffer_size = 64M
######################## MyISAM性能设置 结束 ########################

######################## Innodb性能设置 开始 ########################
# Defines the maximum number of threads permitted inside of InnoDB.
# A value of 0 (the default) is interpreted as infinite concurrency (no limit)
#innodb_thread_concurrency = 0

#一般设置物理存储的 60% ~ 70%
innodb_buffer_pool_size = ${innodb_buffer_pool_size}M

#当缓冲池大小大于1GB时，将innodb_buffer_pool_instances设置为大于1的值，可以提高繁忙服务器的可伸缩性
innodb_buffer_pool_instances = 4

#默认启用。指定在MySQL服务器启动时，InnoDB缓冲池通过加载之前保存的相同页面自动预热。 通常与innodb_buffer_pool_dump_at_shutdown结合使用
innodb_buffer_pool_load_at_startup = 1

#默认启用。指定在MySQL服务器关闭时是否记录在InnoDB缓冲池中缓存的页面，以便在下次重新启动时缩短预热过程
innodb_buffer_pool_dump_at_shutdown = 1

# Defines the name, size, and attributes of InnoDB system tablespace data files
#innodb_data_file_path = ibdata1:1G:autoextend

#InnoDB用于写入磁盘日志文件的缓冲区大小（以字节为单位）。默认值为16MB
innodb_log_buffer_size = 32M

#Innodb redo log容量
innodb_redo_log_capacity=1221225472

#是否开启在线回收（收缩）undo log日志文件，支持动态设置，默认开启
innodb_undo_log_truncate = 1

#当超过这个阀值（默认是1G），会触发truncate回收（收缩）动作，truncate后空间缩小到10M
innodb_max_undo_log_size = 1G

#提高刷新脏页数量和合并插入数量，改善磁盘I/O处理能力
#根据您的服务器IOPS能力适当调整
#一般配普通SSD盘的话，可以调整到 10000 - 20000
#配置高端PCIe SSD卡的话，则可以调整的更高，比如 50000 - 80000
innodb_io_capacity = 4000
innodb_io_capacity_max = 8000

#如果打开参数innodb_flush_sync, checkpoint时，flush操作将由page cleaner线程来完成，此时page cleaner会忽略io capacity的限制，进入激烈刷脏
innodb_flush_sync = 0
innodb_flush_neighbors = 0

#CPU多核处理能力设置，假设CPU是4颗8核的，设置如下
#读多，写少可以设成 2:6的比例
innodb_write_io_threads = 8
innodb_read_io_threads = 8
innodb_purge_threads = 4
innodb_page_cleaners = 4
innodb_open_files = 65535
innodb_max_dirty_pages_pct = 50

#该参数针对unix、linux，window上直接注释该参数.默认值为 NULL
#O_DIRECT减少操作系统级别VFS的缓存和Innodb本身的buffer缓存之间的冲突
innodb_flush_method = O_DIRECT

innodb_lru_scan_depth = 4000
innodb_checksum_algorithm = crc32

#为了获取被锁定的资源最大等待时间，默认50秒，超过该时间会报如下错误:
# ERROR 1205 (HY000): Lock wait timeout exceeded; try restarting transaction
innodb_lock_wait_timeout = 20

#默认OFF，如果事务因为加锁超时，会回滚上一条语句执行的操作。如果设置ON，则整个事务都会回滚
innodb_rollback_on_timeout = 1

#强所有发生的死锁错误信息记录到 error.log中，之前通过命令行只能查看最近一次死锁信息
innodb_print_all_deadlocks = 1

#在创建InnoDB索引时用于指定对数据排序的排序缓冲区的大小
innodb_sort_buffer_size = 67108864

#控制着在向有auto_increment 列的表插入数据时，相关锁的行为，默认为2
#0：traditonal （每次都会产生表锁）
#1：consecutive （mysql的默认模式，会产生一个轻量锁，simple insert会获得批量的锁，保证连续插入）
#2：interleaved （不会锁表，来一个处理一个，并发最高）
innodb_autoinc_lock_mode = 1

#表示每个表都有自已独立的表空间
innodb_file_per_table = 1

#指定Online DDL执行期间产生临时日志文件的最大大小，单位字节，默认大小为128MB。
#日志文件记录的是表在DDL期间的数据插入、更新和删除信息(DML操作)，一旦日志文件超过该参数指定值时，
#DDL执行就会失败并回滚所有未提交的当前DML操作，所以，当执行DDL期间有大量DML操作时可以提高该参数值，
#但同时也会增加DDL执行完成时应用日志时锁定表的时间
innodb_online_alter_log_max_size = 1G

######################## Innodb性能设置 结束 ########################

[mysqldump]
quick
max_allowed_packet = 128M
EOF

    # 启动MySQL服务
    echo "======>>>>>> 启动MySQL服务..."
    systemctl enable mysqld
    systemctl start mysqld
    sleep 10

    # 获取临时密码
    echo "======>>>>>> 获取MySQL临时密码..."
    TEMP_PASSWORD=$(grep 'temporary password' /var/log/mysqld.log | awk '{print $NF}')
    if [ -z "$TEMP_PASSWORD" ]; then
      echo "======>>>>>> 无法获取MySQL临时密码，请检查日志文件"
      grep -i "password" /var/log/mysqld.log
      F_mysql_clearTips
      exit 1
    fi
    echo "======>>>>>> MySQL初始化完成，临时密码为: $TEMP_PASSWORD"

    # 修改默认密码
    echo "======>>>>>> 修改MySQL密码..."
    mysql --connect-expired-password -uroot -p"${TEMP_PASSWORD}" <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '$G_mysql_pwd';
EOF

    # 设置允许远程访问
    echo "======>>>>>> 设置MySQL允许远程访问..."
    mysql -uroot -p"$G_mysql_pwd" <<EOF
use mysql;
update user set host = '%' where user ='root';
FLUSH PRIVILEGES;
EOF

    # 检查MySQL是否安装成功
    echo "======>>>>>> 检查MySQL是否启动成功..."
    sleep 5
    if systemctl status mysqld >/dev/null; then
      echo "======>>>>>> MySQL安装并启动成功"
    else
      echo "======>>>>>> MySQL安装或启动失败"
      systemctl status mysqld
      F_mysql_clearTips
      exit 1
    fi

    # 检查MySQL端口
    db_port_cnt=$(netstat -ant|grep LISTEN|grep -c ":$G_mysql_port")
    if [[ $db_port_cnt -eq 0 ]]; then
      echo "======>>>>>> MySQL端口 $G_mysql_port 未监听，服务可能未正常启动"
      F_mysql_clearTips
      exit 1
    else
      echo "======>>>>>> MySQL端口 $G_mysql_port 已成功监听"
      echo "======>>>>>> MySQL安装完成，密码: $G_mysql_pwd"
    fi

    # 命令提示
    F_mysql_cmdTips
  }

  ## 开始安装Mysql
  function F_mysql_start(){
    echo "======>>>>>> MySQL 安装开始！"

    # 检查MySQL进程是否已存在
    if systemctl status mysqld >/dev/null 2>&1; then
      echo "======>>>>>> MySQL 已经在运行！"
      F_mysql_clearTips
      return
    fi


    # 检查RPM包是否存在
    echo "======>>>>>> 检查MySQL RPM包..."
    rpm_count=$(find "$G_rpm_dir" -name "*.rpm" | wc -l)
    if [[ $rpm_count -eq 0 ]]; then
      echo "======>>>>>> 未找到MySQL RPM包，请确保已上传RPM包到 $G_rpm_dir 目录"
      exit 1
    fi
    echo "======>>>>>> 找到 $rpm_count 个RPM包，准备安装"

    # 继续安装MySQL
    F_mysql_install

    echo "======>>>>>> MySQL 安装完成！"
  }

  # 开始安装mysql
  F_mysql_start
}
# 部署mysql
F_deploy_mysql
################################################################ Mysql 安装脚本 >> 结束
