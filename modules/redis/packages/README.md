# Redis RPM包目录

这个目录用于存放Redis的RPM安装包。

## 使用说明

1. 将Redis的RPM包文件放在此目录中
2. 支持的包格式：`*.rpm`
3. 如果此目录为空，部署脚本会尝试使用系统包管理器（yum）安装Redis

## 推荐的Redis版本

- Redis 7.0.x (推荐)
- Redis 6.2.x (稳定版)

## 下载地址

- 官方下载：https://redis.io/download
- REMI源：https://rpms.remirepo.net/