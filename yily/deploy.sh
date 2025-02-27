#!/bin/bash

set -e

# 显示帮助信息
show_help() {
    cat << EOF
用法: $(basename "$0") [选项]

选项:
  -y, --you-domain <域名>        你的域名或IP (例如: example.com)
  -r, --r-domain <域名>          反代 Emby 的域名 (例如: backend.com)
  -P, --frontend-port <端口>     你的前端访问端口 (默认: 443)
  -p, --backend-port <端口>      反代 Emby 前端端口 (默认: 空)
  -f, --backend-http-frontend    反代 Emby 使用 HTTP 作为前端访问 (默认: 否)
  -b, --backend-http-backend     反代 Emby 使用 HTTP 连接后端 (默认: 否)
  -t, --enable-streaming         启用 Emby 后端推流支持 (默认: 否)
  -s, --no-tls                   禁用 TLS (默认: 否)
  -h, --help                     显示帮助信息
EOF
    exit 0
}

# 初始化变量
you_domain=""
r_domain=""
frontend_port="443"
backend_port=""
backend_http_backend="no"
backend_http_frontend="no"
enable_streaming="no"
no_tls="no"

# 使用 `getopt` 解析参数
TEMP=$(getopt -o y:r:P:p:bfsth --long you-domain:,r-domain:,frontend-port:,backend-port:,backend-http-frontend,backend-http-backend,enable-streaming,no-tls,help -n "$(basename "$0")" -- "$@")

if [ $? -ne 0 ]; then
    echo "参数解析失败，请检查输入的参数。"
    exit 1
fi

eval set -- "$TEMP"

while true; do
    case "$1" in
        -y|--you-domain) you_domain="$2"; shift 2 ;;
        -r|--r-domain) r_domain="$2"; shift 2 ;;
        -P|--frontend-port) frontend_port="$2"; shift 2 ;;
        -p|--backend-port) backend_port="$2"; shift 2 ;;
        -b|--backend-http-backend) backend_http_backend="yes"; shift ;;
        -f|--backend-http-frontend) backend_http_frontend="yes"; shift ;;
        -t|--enable-streaming) enable_streaming="yes"; shift ;;
        -s|--no-tls) no_tls="yes"; shift ;;
        -h|--help) show_help; shift ;;
        --) shift; break ;;
        *) echo "错误: 未知参数 $1"; exit 1 ;;
    esac
done

# 交互模式 (如果未提供必要参数)
if [[ -z "$you_domain" || -z "$r_domain" ]]; then
    echo -e "\n--- 交互模式: 配置反向代理 ---"
    echo "请按提示输入参数，或直接按 Enter 使用默认值"
    read -p "你的域名或 IP [默认: you.example.com]: " input_you_domain
    read -p "反代 Emby 的域名 [默认: backend.example.com]: " input_r_domain
    read -p "是否启用 Emby 后端推流支持? (yes/no) [默认: no]: " input_enable_streaming
    read -p "前端访问端口 [默认: 443]: " input_frontend_port
    read -p "反代 Emby 前端端口 [默认: 空]: " input_backend_port
    read -p "是否使用 HTTP 连接反代 Emby 后端? (yes/no) [默认: no]: " input_backend_http_backend
    read -p "是否使用 HTTP 连接反代 Emby 前端? (yes/no) [默认: no]: " input_backend_http_frontend
    read -p "是否禁用 TLS? (yes/no) [默认: no]: " input_no_tls

    you_domain="${input_you_domain:-you.example.com}"
    r_domain="${input_r_domain:-backend.example.com}"
    enable_streaming="${input_enable_streaming:-no}"
    frontend_port="${input_frontend_port:-443}"
    backend_port="${input_backend_port}"
    backend_http_backend="${input_backend_http_backend:-no}"
    backend_http_frontend="${input_backend_http_frontend:-no}"
    no_tls="${input_no_tls:-no}"
fi

# 美化输出配置信息
protocol=$( [[ "$no_tls" == "yes" ]] && echo "http" || echo "https" )
url="${protocol}://${you_domain}:${frontend_port}"

echo -e "\n------ 配置信息 ------"
echo "🌍 访问地址: ${url}"
echo "📌 你的域名: ${you_domain}"
echo "🖥️ 前端访问端口: ${frontend_port}"
echo "🔄 反代 Emby 的域名: ${r_domain}"
echo "🎯 反代 Emby 前端端口: ${backend_port:-未指定}"
echo "📡 启用 Emby 后端推流支持: $( [[ "$enable_streaming" == "yes" ]] && echo "✅ 是" || echo "❌ 否" )"
echo "🔗 使用 HTTP 连接反代 Emby 后端: $( [[ "$backend_http_backend" == "yes" ]] && echo "✅ 是" || echo "❌ 否" )"
echo "🛠️ 使用 HTTP 连接反代 Emby 前端: $( [[ "$backend_http_frontend" == "yes" ]] && echo "✅ 是" || echo "❌ 否" )"
echo "🔒 禁用 TLS: $( [[ "$no_tls" == "yes" ]] && echo "✅ 是" || echo "❌ 否" )"
echo "----------------------"

# 检查依赖和安装 Nginx（保持不变）
check_dependencies() {
  if [[ ! -f '/etc/os-release' ]]; then
    echo "error: Don't use outdated Linux distributions."
    return 1
  fi
  source /etc/os-release
  if [ -z "$ID" ]; then
      echo -e "Unsupported Linux OS Type"
      exit 1
  fi

  case "$ID" in
  debian|devuan|kali)
      OS_NAME='debian'
      PM='apt'
      GNUPG_PM='gnupg2'
      ;;
  ubuntu)
      OS_NAME='ubuntu'
      PM='apt'
      GNUPG_PM=$([[ ${VERSION_ID%%.*} -lt 22 ]] && echo "gnupg2" || echo "gnupg")
      ;;
  centos|fedora|rhel|almalinux|rocky|amzn)
      OS_NAME='rhel'
      PM=$(command -v dnf >/dev/null && echo "dnf" || echo "yum")
      ;;
  arch|archarm)
      OS_NAME='arch'
      PM='pacman'
      ;;
  alpine)
      OS_NAME='alpine'
      PM='apk'
      ;;
  *)
      OS_NAME="$ID"
      PM='apt'
      ;;
  esac
}
check_dependencies

echo "检查 Nginx 是否已安装..."
if ! command -v nginx &> /dev/null; then
    echo "Nginx 未安装，正在安装..."
    # 安装逻辑保持不变（略）
else
    echo "Nginx 已安装，跳过安装步骤。"
fi

# 下载并复制 nginx.conf
echo "下载并复制 nginx 配置文件..."
curl -o /etc/nginx/nginx.conf https://raw.githubusercontent.com/xiyily/Emby_nginx_proxy/refs/heads/main/yily/nginx.conf

# 生成合并的配置文件
config_file="$you_domain.conf"
echo "生成合并配置文件 $config_file..."
cat > "$config_file" << EOF
server {
    listen $frontend_port quic;
    listen $frontend_port ssl;
    listen [::]:$frontend_port quic;
    listen [::]:$frontend_port ssl;
    http2 on;
    http3 on;
    quic_gso on;
    quic_retry on;

    server_name $you_domain;

    $( [[ "$no_tls" != "yes" ]] && echo "ssl_certificate /etc/nginx/certs/$you_domain/cert;
    ssl_certificate_key /etc/nginx/certs/$you_domain/key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers TLS13_AES_128_GCM_SHA256:TLS13_AES_256_GCM_SHA384:TLS13_CHACHA20_POLY1305_SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers on;" || echo "# TLS disabled")

    resolver 8.8.8.8 1.1.1.1 valid=60s;
    resolver_timeout 5s;

    client_header_timeout 1h;
    keepalive_timeout 30m;
    client_header_buffer_size 8k;

    # 前端：屏蔽 web 端访问
    location ~ ^/(?:$|web(?:/.*)?)$ {
        return 403;
    }

    # 前端：代理到后端 Emby 服务
    location / {
        proxy_pass $( [[ "$backend_http_frontend" == "yes" ]] && echo "http" || echo "https" )://$r_domain${backend_port:+:$backend_port};
        proxy_set_header Host \$proxy_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_http_version 1.1;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        # 重定向处理
        proxy_redirect ~^(https?)://([^:/]+(?::\d+)?)(/.+)$ \$scheme://\$server_name:\$server_port/backstream/\$2\$3;
        set \$redirect_scheme \$1;
        set \$redirect_host \$2;
        sub_filter \$proxy_host \$host;
        sub_filter '\$redirect_scheme://\$redirect_host' '\$scheme://\$server_name:\$server_port/backstream/\$redirect_host';
        sub_filter_once off;
        proxy_intercept_errors on;
        error_page 307 = @handle_redirect;
    }

    # 后端：处理 /backstream/ 请求
    location ~ ^/backstream/([^/]+) {
        set \$website \$1;
        rewrite ^/backstream/([^/]+)(/.+)$ \$2 break;
        proxy_pass $( [[ "$backend_http_backend" == "yes" ]] && echo "http" || echo "https" )://\$website;
        proxy_set_header Host \$proxy_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_http_version 1.1;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # 处理重定向
    location @handle_redirect {
        set \$saved_redirect_location '\$upstream_http_location';
        proxy_pass \$saved_redirect_location;
        proxy_set_header Host \$proxy_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_http_version 1.1;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    $( [[ "$enable_streaming" == "yes" ]] && cat << 'STREAMING' || echo "# Streaming disabled")
    # 后端：Emby 推流支持
    location ~ ^/emby/videos/(.*)/stream {
        proxy_pass $( [[ "$backend_http_backend" == "yes" ]] && echo "http" || echo "https" )://$r_domain${backend_port:+:$backend_port}/emby/videos/\$1/stream;
        proxy_set_header Host \$proxy_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_http_version 1.1;
        proxy_buffering off;  # 禁用缓冲以支持实时流
        proxy_cache off;      # 禁用缓存
        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;  # 增加超时时间以支持长连接
        proxy_read_timeout 300s;
    }
STREAMING
}
EOF

# 移动配置文件到 /etc/nginx/conf.d/
echo "移动配置文件到 /etc/nginx/conf.d/"
mv -f "$config_file" /etc/nginx/conf.d/

# 处理 TLS 证书
if [[ "$no_tls" != "yes" ]]; then
    ACME_SH="$HOME/.acme.sh/acme.sh"
    echo "检查 acme.sh 是否已安装..."
    if [[ ! -f "$ACME_SH" ]]; then
        echo "acme.sh 未安装，正在安装..."
        apt install -y socat cron
        curl https://get.acme.sh | sh
        "$ACME_SH" --upgrade --auto-upgrade
        "$ACME_SH" --set-default-ca --server letsencrypt
    fi

    if ! "$ACME_SH" --info -d "$you_domain" | grep -q RealFullChainPath; then
        echo "ECC 证书未申请，正在申请..."
        mkdir -p "/etc/nginx/certs/$you_domain"
        "$ACME_SH" --issue -d "$you_domain" --standalone --keylength ec-256 || {
            echo "证书申请失败，请检查错误信息！"
            rm -f "/etc/nginx/conf.d/$config_file"
            exit 1
        }
    fi

    echo "安装证书..."
    "$ACME_SH" --install-cert -d "$you_domain" --ecc \
        --fullchain-file "/etc/nginx/certs/$you_domain/cert" \
        --key-file "/etc/nginx/certs/$you_domain/key" \
        --reloadcmd "nginx -s reload" --force
fi

echo "重新加载 Nginx..."
nginx -s reload

echo "反向代理设置完成！"
