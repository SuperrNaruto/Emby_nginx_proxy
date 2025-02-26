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
r_domains=""  # For frontend domain(s)
backend_count=""  # Number of backend servers, empty by default
backend_domains=()  # Array for backend domains
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

# 交互模式 (如果未提供必要参数)
if [[ -z "$you_domain" || -z "$r_domains" ]]; then
    echo -e "\n--- 交互模式: 配置反向代理 ---"
    echo "请按提示输入参数，或直接按 Enter 使用默认值"
    read -p "你的域名或者 IP [默认: you.example.com]: " input_you_domain
    read -p "反代Emby的域名 (前端，例如: frontend.com) [默认: r.example.com]: " input_r_domains

    # 赋值前端域名
    you_domain="${input_you_domain:-you.example.com}"
    r_domains="${input_r_domains:-r.example.com}"

    # 提示输入推流数量
    read -p "推流数量 (Emby后端流式处理服务器数量，若不输入则跳过) [默认: 空]: " input_backend_count
    if [[ -n "$input_backend_count" ]]; then
        backend_count="$input_backend_count"
        # 根据推流数量提示用户输入后端域名
        for ((i=1; i<=backend_count; i++)); do
            read -p "请输入第 $i 个 Emby 后端流式处理服务器地址 (例如: backend$i.example.com): " backend_domain
            if [[ -n "$backend_domain" ]]; then
                backend_domains+=("$backend_domain")
            else
                backend_domains+=("backend$i.${r_domains%%,*}")  # Default to subdomain of first frontend domain
            fi
        done
        read -p "是否使用HTTP反向代理Emby后端? (yes/no) [默认: no]: " input_r_http_backend
        r_http_backend="${input_r_http_backend:-no}"
    fi

    # 继续其他参数
    read -p "你的前端访问端口 [默认: 443]: " input_you_frontend_port
    read -p "反代Emby前端端口 [默认: 空]: " input_r_frontend_port
    read -p "是否使用HTTP连接反代Emby前端? (yes/no) [默认: no]: " input_r_http_frontend
    read -p "是否禁用TLS? (yes/no) [默认: no]: " input_no_tls

    # 赋值默认值
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
if [[ ${#backend_domains[@]} -gt 0 ]]; then
    echo "🔄 推流数量 (Emby后端服务器): ${backend_count}"
    echo "🔄 反代 Emby 的后端域名: ${backend_domains[*]}"
    echo "🔗 使用 HTTP 连接反代 Emby 后端: $( [[ "$r_http_backend" == "yes" ]] && echo "✅ 是" || echo "❌ 否" )"
fi
echo "🎯 反代 Emby 前端端口: ${r_frontend_port:-未指定}"
echo "🛠️  使用 HTTP 连接反代 Emby 前端: $( [[ "$r_http_frontend" == "yes" ]] && echo "✅ 是" || echo "❌ 否" )"
echo "🔒 禁用 TLS: $( [[ "$no_tls" == "yes" ]] && echo "✅ 是" || echo "❌ 否" )"
echo "----------------------"

# 检查依赖函数保持不变
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
curl -o /etc/nginx/nginx.conf https://raw.githubusercontent.com/xiyily/Emby_nginx_proxy/refs/heads/main/sakullla/nginx.conf

# 在 for 循环中生成支持 HTTP 和 HTTPS 的配置文件
for r_domain in "${all_domains[@]}"; do
    you_domain_config="$you_domain"
    download_domain_config="p.example.com"

    # 如果 $no_tls 选择使用 HTTP，则只生成 HTTP 配置
    if [[ "$no_tls" == "yes" ]]; then
        you_domain_config="$you_domain.$you_frontend_port"
        download_domain_config="p.example.com.no_tls"
    else
        # 使用支持 HTTP 和 HTTPS 的模板
        download_domain_config="p.example.com.both"
    fi

    # 下载并创建配置文件，以域名命名文件
    config_file="${you_domain}_${r_domain//./_}.conf"
    echo "下载并创建 $config_file 配置文件..."
    curl -o "$config_file" "https://raw.githubusercontent.com/xiyily/Emby_nginx_proxy/main/sakullla/conf.d/$download_domain_config.conf"

    # 替换 server_name 为当前域名
    sed -i "s/p.example.com/$r_domain/g" "$config_file"

    # 替换 emby.example.com 为当前域名
    sed -i "s/emby.example.com/$r_domain/g" "$config_file"

    # 如果 you_frontend_port 不为空，则替换端口
    if [[ -n "$you_frontend_port" ]]; then
        sed -i "s/443/$you_frontend_port/g" "$config_file"
        sed -i "s/80/$you_frontend_port/g" "$config_file"  # 如果 HTTP 也使用自定义端口
    fi

    # 如果 r_http_frontend 选择使用 HTTP，前端域名应用
    if [[ "$r_http_frontend" == "yes" && " ${r_domain_array[*]} " =~ " $r_domain " ]]; then
        sed -i "s/https:\/\/frontend.com/http:\/\/frontend.com/g" "$config_file"
    fi

    # 如果 r_frontend_port 不为空，修改前端域名加上端口
    if [[ -n "$r_frontend_port" && " ${r_domain_array[*]} " =~ " $r_domain " ]]; then
        sed -i "s/frontend.com/frontend.com:$r_frontend_port/g" "$config_file"
    fi

    # 如果 r_http_backend 选择使用 HTTP，后端域名应用
    if [[ "$r_http_backend" == "yes" && " ${backend_domains[*]} " =~ " $r_domain " ]]; then
        sed -i "s/https:\/\/\$website/http:\/\/\$website/g" "$config_file"
    fi

    # 更新 SSL 证书路径（如果有多个域名，可能需要通配符证书或多个证书）
    if [[ "$no_tls" != "yes" ]]; then
        sed -i "s|/etc/nginx/certs/p.example.com/cert|/etc/nginx/certs/$r_domain/cert|g" "$config_file"
        sed -i "s|/etc/nginx/certs/p.example.com/key|/etc/nginx/certs/$r_domain/key|g" "$config_file"
    fi

    # 确保 .well-known/acme-challenge 路径在 HTTP 块中可用
    if [[ "$no_tls" != "yes" ]]; then
        sed -i "/listen 80;/a\        location /.well-known/acme-challenge/ {\n            root /var/www/html;\n            default_type text/plain;\n        }" "$config_file"
    fi

    # 移动配置文件到 /etc/nginx/conf.d/
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

    # 为所有域名申请证书
    domains=("$you_domain" "${r_domain_array[@]}" "${backend_domains[@]}")
    domain_list=$(printf " -d %s" "${domains[@]}")
    if ! "$ACME_SH" --info $domain_list | grep -q RealFullChainPath; then
        echo "ECC 证书未申请，正在申请..."
        mkdir -p "/var/www/html/.well-known/acme-challenge"  # Ensure challenge directory exists
        sudo chmod -R 755 /var/www/html
        "$ACME_SH" --issue $domain_list --standalone --keylength ec-256 || {
            echo "证书申请失败，请检查错误信息！"
            for r_domain in "${all_domains[@]}"; do
                rm -f "/etc/nginx/conf.d/${you_domain}_${r_domain//./_}.conf"
            done
            exit 1
        }
    else
        echo "ECC 证书已申请，跳过申请步骤。"
    fi

    # 安装证书（这里假设为第一个域名安装，如果需要为每个域名安装证书，需循环处理）
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
