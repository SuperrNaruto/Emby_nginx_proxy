#!/bin/bash

set -e

# 显示帮助信息
show_help() {
    cat << EOF
用法: $(basename "$0") [选项]

选项:
  -y, --you-domain <域名>        你的前端主站域名 (例如: example.com)
  -P, --you-frontend-port <端口>  你的前端访问端口 (默认: 443)
  -f, --r-http-frontend          反代 Emby 前端使用 HTTP (默认: 否)
  -b, --r-http-backend           反代 Emby 后端使用 HTTP (默认: 否)
  -s, --no-tls                   禁用 TLS (默认: 否)
  -h, --help                     显示帮助信息
EOF
    exit 0
}


