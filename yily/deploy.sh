#!/bin/bash

set -e

# 显示帮助信息
show_help() {
    cat << EOF
用法: $(basename "$0") [选项]


选项:
  -y, --you-domain <域名>        你的域名或IP (例如: example.com)
  -r, --r-domain <域名>          反代 Emby 的域名 (多个域名用逗号分隔，例如: frontend.com)
  -P, --you-frontend-port <端口>  你的前端访问端口 (默认: 443)
  -p, --r-frontend-port <端口>    反代 Emby 前端端口 (默认: 空)
  -f, --r-http-frontend          反代 Emby 使用 HTTP 作为前端访问 (默认: 否)
  -b, --r-http-backend           反代 Emby 使用 HTTP 连接后端 (默认: 否)
  -s, --no-tls                   禁用 TLS (默认: 否)
  -h, --help                     显示帮助信息
EOF
    exit 0
}

# 初始化变量
you_domain=""
r_domains=""
backend_count=0
backend_domains=()
r_http_backend="no"
you_frontend_port="443"
r_frontend_port=""
r_http_frontend="no"
no_tls="no"

# 使用 `getopt` 解析参数
TEMP=$(getopt -o y:r:P:p:bfsh --long you-domain:,r-domain:,you-frontend-port:,r-frontend-port:,r-http-frontend,r-http-backend,no-tls,help -n "$(basename "$0")" -- "$@")

if [ $? -ne 0 ]; then
    echo "参数解析失败，请检查输入的参数。"
    exit 1
fi

eval set -- "$TEMP"

while true; do
    case "$1" in
        -y|--you-domain) you_domain="$2"; shift 2 ;;
        -r|--r-domain) r_domains="$2"; shift 2 ;;
        -P|--you-frontend-port) you_frontend_port="$2"; shift 2 ;;
        -p|--r-frontend-port) r_frontend_port="$2"; shift 2 ;;
        -b|--r-http-backend) r_http_backend="yes"; shift ;;
        -f|--r-http-frontend) r_http_frontend="yes"; shift ;;
        -s|--no-tls) no_tls="yes"; shift ;;
        -h|--help) show_help; shift ;;
        --) shift; break ;;
        *) echo "错误: 未知参数 $1"; exit 1 ;;
    esac
done

# 交互模式
if [[ -z "$you_domain" || -z "$r_domains" ]]; then
    echo -e "\n--- 交互模式: 配置反向代理 ---"
    echo "请按提示输入参数，或直接按 Enter 使用默认值"
    read -p "你的域名或者 IP [默认: you.example.com]: " input_you_domain
    read -p "反代Emby的域名 (前端，例如: frontend.com) [默认: r.example.com]: " input_r_domains
    read -p "推流数量 (Emby后端流式处理服务器数量，输入0或留空跳过) [默认: 0]: " input_backend_count

    you_domain="${input_you_domain:-you.example.com}"
    r_domains="${input_r_domains:-r.example.com}"
    backend_count="${input_backend_count:-0}"

    if [[ "$backend_count" -gt 0 ]]; then
        echo "请输入 $backend_count 个 Emby 后端流式处理服务器地址："
        for ((i=1; i<=backend_count; i++)); do
            read -p "后端服务器 $i 地址 (例如: backend$i.example.com): " backend_input
            if [[ -n "$backend_input" ]]; then
                backend_domains+=("$backend_input")
            else
                backend_domains+=("backend$i.${r_domains%%,*}")
            fi
        done
        read -p "是否使用HTTP反向代理Emby后端? (yes/no) [默认: no]: " input_r_http_backend
        r_http_backend="${input_r_http_backend:-no}"
    fi

    read -p "你的前端访问端口 [默认: 443]: " input_you_frontend_port
    read -p "反代Emby前端端口 [默认: 空]: " input_r_frontend_port
    read -p "是否使用HTTP连接反代Emby前端? (yes/no) [默认: no]: " input_r_http_frontend
    read -p "是否禁用TLS? (yes/no) [默认: no]: " input_no_tls

    you_frontend_port="${input_you_frontend_port:-443}"
    r_frontend_port="${input_r_frontend_port}"
    r_http_frontend="${input_r_http_frontend:-no}"
    no_tls="${input_no_tls:-no}"
fi

# Split r_domains into an array (frontend domains)
IFS=',' read -r -a r_domain_array <<< "$r_domains"

# Combine frontend and backend domains
all_domains=("${r_domain_array[@]}" "${backend_domains[@]}")

# 美化输出配置信息
protocol=$( [[ "$no_tls" == "yes" ]] && echo "http" || echo "https" )
url="${protocol}://${you_domain}:${you_frontend_port}"

echo -e "\n------ 配置信息 ------"
echo "🌍 访问地址: ${url}"
echo "📌 你的域名: ${you_domain}"
echo "🖥️  你的前端访问端口: ${you_frontend_port}"
echo "🔄 反代 Emby 的前端域名: ${r_domains}"
echo "🔄 推流数量 (Emby后端服务器): ${backend_count}"
if [[ "$backend_count" -gt 0 ]]; then
    echo "🔄 反代 Emby 的后端域名: ${backend_domains[*]}"
    echo "🔗 使用 HTTP 连接反代 Emby 后端: $( [[ "$r_http_backend" == "yes" ]] && echo "✅ 是" || echo "❌ 否" )"
fi
echo "🎯 反代 Emby 前端端口: ${r_frontend_port:-未指定}"
echo "🛠️  使用 HTTP 连接反代 Emby 前端: $( [[ "$r_http_frontend" == "yes" ]] && echo "✅ 是" || echo "❌ 否" )"
echo "🔒 禁用 TLS: $( [[ "$no_tls" == "yes" ]] && echo "✅ 是" || echo "❌ 否" )"
echo "----------------------"

# 检查依赖函数
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
  debian|devuan|kali) OS_NAME='debian'; PM='apt'; GNUPG_PM='gnupg2'; ;;
  ubuntu) OS_NAME='ubuntu'; PM='apt'; GNUPG_PM=$([[ ${VERSION_ID%%.*} -lt 22 ]] && echo "gnupg2" || echo "gnupg"); ;;
  centos|fedora|rhel|almalinux|rocky|amzn) OS_NAME='rhel'; PM=$(command -v dnf >/dev/null && echo "dnf" || echo "yum"); ;;
  arch|archarm) OS_NAME='arch'; PM='pacman'; ;;
  alpine) OS_NAME='alpine'; PM='apk'; ;;
  *) OS_NAME="$ID"; PM='apt'; ;;
  esac
}
check_dependencies

# 检查并安装 Nginx
echo "检查 Nginx 是否已安装..."
if ! command -v nginx &> /dev/null; then
    echo "Nginx 未安装，正在安装..."
    if [[ "$OS_NAME" == "debian" || "$OS_NAME" == "ubuntu" ]]; then
      $PM install -y "$GNUPG_PM" ca-certificates lsb-release "$OS_NAME-keyring" \
        && curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor > /usr/share/keyrings/nginx-archive-keyring.gpg \
        && echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/mainline/$OS_NAME `lsb_release -cs` nginx" > /etc/apt/sources.list.d/nginx.list \
        && echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" > /etc/apt/preferences.d/99nginx \
        && $PM update && $PM install -y nginx \
        && mkdir -p /etc/systemd/system/nginx.service.d \
        && echo -e "[Service]\nExecStartPost=/bin/sleep 0.1" > /etc/systemd/system/nginx.service.d/override.conf \
        && systemctl daemon-reload && rm -f /etc/nginx/conf.d/default.conf \
        && systemctl enable --now nginx
    elif [[ "$OS_NAME" == "rhel" ]]; then
      $PM install -y yum-utils \
          && echo -e "[nginx-mainline]\nname=NGINX Mainline Repository\nbaseurl=https://nginx.org/packages/mainline/centos/\$releasever/\$basearch/\ngpgcheck=1\nenabled=1\ngpgkey=https://nginx.org/keys/nginx_signing.key" > /etc/yum.repos.d/nginx.repo \
          && $PM install -y nginx \
          && mkdir -p /etc/systemd/system/nginx.service.d \
          && echo -e "[Service]\nExecStartPost=/bin/sleep 0.1" > /etc/systemd/system/nginx.service.d/override.conf \
          && systemctl daemon-reload && rm -f /etc/nginx/conf.d/default.conf \
          && systemctl enable --now nginx
    elif [[ "$OS_NAME" == "arch" ]]; then
      $PM -Sy --noconfirm nginx-mainline \
          && mkdir -p /etc/systemd/system/nginx.service.d \
          && echo -e "[Service]\nExecStartPost=/bin/sleep 0.1" > /etc/systemd/system/nginx.service.d/override.conf \
          && systemctl daemon-reload && rm -f /etc/nginx/conf.d/default.conf \
          && systemctl enable --now nginx
    elif [[ "$OS_NAME" == "alpine" ]]; then
      $PM update && $PM add --no-cache nginx-mainline \
          && rc-update add nginx default && rm -f /etc/nginx/conf.d/default.conf \
          && rc-service nginx start
    else
        echo "不支持的操作系统，请手动安装 Nginx" >&2
        exit 1
    fi
else
    echo "Nginx 已安装，跳过安装步骤。"
fi

# 下载并复制 nginx.conf
echo "下载并复制 nginx 配置文件..."
curl -o /etc/nginx/nginx.conf https://raw.githubusercontent.com/xiyily/Emby_nginx_proxy/refs/heads/main/xinyily/nginx.conf

# 为每个域名生成配置文件
for r_domain in "${all_domains[@]}"; do
    you_domain_config="$you_domain"
    download_domain_config="p.example.com"

    if [[ "$no_tls" == "yes" ]]; then
        you_domain_config="$you_domain.$you_frontend_port"
        download_domain_config="p.example.com.no_tls"
    else
        # Assume QUIC-enabled template for TLS case
        download_domain_config="p.example.com"
    fi

    # Generate a unique server_name for each domain (combine you_domain and r_domain)
    unique_server_name="${you_domain}_${r_domain//./_}"
    config_file="${unique_server_name}.conf"
    echo "下载并创建 $config_file 配置文件..."
    curl -o "$config_file" "https://raw.githubusercontent.com/xiyily/Emby_nginx_proxy/main/xinyily/conf.d/$download_domain_config.conf"

    # 替换端口
    if [[ -n "$you_frontend_port" ]]; then
        sed -i "s/443/$you_frontend_port/g" "$config_file"
    fi

    # 替换 server_name with unique value
    sed -i "s/p.example.com/$unique_server_name/g" "$config_file"

    # 前端 HTTP 设置
    if [[ "$r_http_frontend" == "yes" && " ${r_domain_array[*]} " =~ " $r_domain " ]]; then
        sed -i "s/https:\/\/emby.example.com/http:\/\/emby.example.com/g" "$config_file"
    fi

    # 前端端口设置
    if [[ -n "$r_frontend_port" && " ${r_domain_array[*]} " =~ " $r_domain " ]]; then
        sed -i "s/emby.example.com/emby.example.com:$r_frontend_port/g" "$config_file"
    fi

    # 替换域名
    sed -i "s/emby.example.com/$r_domain/g" "$config_file"

    # 后端 HTTP 设置
    if [[ "$r_http_backend" == "yes" && " ${backend_domains[*]} " =~ " $r_domain " ]]; then
        sed -i "s/https:\/\/\$website/http:\/\/\$website/g" "$config_file"
    fi

    # 如果使用 TLS，添加证书路径 (兼容 QUIC 配置)
    if [[ "$no_tls" != "yes" ]]; then
        # Ensure certificates are added within the server block
        sed -i "/^server {/,/}/ s|^server {|server {\n    ssl_certificate /etc/nginx/certs/$you_domain/cert;\n    ssl_certificate_key /etc/nginx/certs/$you_domain/key;|" "$config_file"
    fi

    # 移动配置文件
    echo "移动 $config_file 到 /etc/nginx/conf.d/"
    if [[ "$OS_NAME" == "ubuntu" ]]; then
        rsync -av "$config_file" /etc/nginx/conf.d/
    else
        mv -f "$config_file" /etc/nginx/conf.d/
    fi
done

# TLS 配置
if [[ "$no_tls" != "yes" ]]; then
    ACME_SH="$HOME/.acme.sh/acme.sh"

    echo "检查 acme.sh 是否已安装..."
    if [[ ! -f "$ACME_SH" ]]; then
        echo "acme.sh 未安装，正在安装..."
        apt install -y socat cron
        curl https://get.acme.sh | sh
        "$ACME_SH" --upgrade --auto-upgrade
        "$ACME_SH" --set-default-ca --server letsencrypt
    else
        echo "acme.sh 已安装，跳过安装步骤。"
    fi

    if ! "$ACME_SH" --info -d "$you_domain" | grep -q RealFullChainPath; then
        echo "ECC 证书未申请，正在申请..."
        mkdir -p "/etc/nginx/certs/$you_domain"
        "$ACME_SH" --issue -d "$you_domain" --standalone --keylength ec-256 || {
            echo "证书申请失败，请检查错误信息！"
                rm -f "/etc/nginx/conf.d/$you_domain.conf"
            done
            exit 1
        }
    else
        echo "ECC 证书已申请，跳过申请步骤。"
    fi

    echo "安装证书..."
    "$ACME_SH" --install-cert -d "$you_domain" --ecc \
        --fullchain-file "/etc/nginx/certs/$you_domain/cert" \
        --key-file "/etc/nginx/certs/$you_domain/key" \
        --reloadcmd "nginx -s reload" --force

    echo "证书安装完成！"
fi

echo "重新加载 Nginx..."
nginx -s reload

echo "反向代理设置完成！"
