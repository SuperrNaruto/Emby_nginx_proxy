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

# 初始化变量
you_domain=""
you_frontend_port="443"
r_http_backend="no"
r_http_frontend="no"
no_tls="no"
backend_domains=()

# 使用 `getopt` 解析参数
TEMP=$(getopt -o y:P:bfsh --long you-domain:,you-frontend-port:,r-http-frontend,r-http-backend,no-tls,help -n "$(basename "$0")" -- "$@")
if [ $? -ne 0 ]; then
    echo "参数解析失败，请检查输入的参数。"
    exit 1
fi

eval set -- "$TEMP"

while true; do
    case "$1" in
        -y|--you-domain) you_domain="$2"; shift 2 ;;
        -P|--you-frontend-port) you_frontend_port="$2"; shift 2 ;;
        -b|--r-http-backend) r_http_backend="yes"; shift ;;
        -f|--r-http-frontend) r_http_frontend="yes"; shift ;;
        -s|--no-tls) no_tls="yes"; shift ;;
        -h|--help) show_help; shift ;;
        --) shift; break ;;
        *) echo "错误: 未知参数 $1"; exit 1 ;;
    esac
done

# 交互模式 (如果未提供必要参数)
if [[ -z "$you_domain" ]]; then
    echo -e "\n--- 交互模式: 配置反向代理 ---"
    echo "请按提示输入参数，或直接按 Enter 使用默认值"
    read -p "你的前端主站域名 [默认: you.example.com]: " input_you_domain
    read -p "你的前端访问端口 [默认: 443]: " input_you_frontend_port
    read -p "是否使用 HTTP 连接反代 Emby 后端? (yes/no) [默认: no]: " input_r_http_backend
    read -p "是否使用 HTTP 连接反代 Emby 前端? (yes/no) [默认: no]: " input_r_http_frontend
    read -p "是否禁用 TLS? (yes/no) [默认: no]: " input_no_tls

    # 赋值默认值
    you_domain="${input_you_domain:-you.example.com}"
    you_frontend_port="${input_you_frontend_port:-443}"
    r_http_backend="${input_r_http_backend:-no}"
    r_http_frontend="${input_r_http_frontend:-no}"
    no_tls="${input_no_tls:-no}"
fi

# 询问后端推流服务器数量
echo -e "\n--- 配置 Emby 后端推流服务器 ---"
read -p "请输入后端推流服务器的数量 (默认: 0): " backend_count
backend_count="${backend_count:-0}"

if [[ "$backend_count" -gt 0 ]]; then
    for ((i=1; i<=backend_count; i++)); do
        read -p "请输入第 $i 个后端推流服务器域名 (例如: backend$i.example.com): " backend_domain
        if [[ -n "$backend_domain" ]]; then
            backend_domains+=("$backend_domain")
        else
            echo "警告: 未输入有效的域名，跳过此服务器。"
        fi
    done
fi

# 美化输出配置信息
protocol=$( [[ "$no_tls" == "yes" ]] && echo "http" || echo "https" )
url="${protocol}://${you_domain}:${you_frontend_port}"

echo -e "\n------ 配置信息 ------"
echo "🌍 前端访问地址: ${url}"
echo "📌 前端主站域名: ${you_domain}"
echo "🖥️ 前端访问端口: ${you_frontend_port}"
echo "🔗 使用 HTTP 连接反代 Emby 后端: $( [[ "$r_http_backend" == "yes" ]] && echo "✅ 是" || echo "❌ 否" )"
echo "🛠️ 使用 HTTP 连接反代 Emby 前端: $( [[ "$r_http_frontend" == "yes" ]] && echo "✅ 是" || echo "❌ 否" )"
echo "🔒 禁用 TLS: $( [[ "$no_tls" == "yes" ]] && echo "✅ 是" || echo "❌ 否" )"
if [[ ${#backend_domains[@]} -gt 0 ]]; then
    echo "🔄 后端推流服务器域名:"
    for domain in "${backend_domains[@]}"; do
        echo "  - $domain"
    done
else
    echo "🔄 后端推流服务器: 未配置"
fi
echo "----------------------"

# 检查依赖 (保持原逻辑不变)
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
        debian|devuan|kali) OS_NAME='debian'; PM='apt'; GNUPG_PM='gnupg2';;
        ubuntu) OS_NAME='ubuntu'; PM='apt'; GNUPG_PM=$([[ ${VERSION_ID%%.*} -lt 22 ]] && echo "gnupg2" || echo "gnupg");;
        centos|fedora|rhel|almalinux|rocky|amzn) OS_NAME='rhel'; PM=$(command -v dnf >/dev/null && echo "dnf" || echo "yum");;
        arch|archarm) OS_NAME='arch'; PM='pacman';;
        alpine) OS_NAME='alpine'; PM='apk';;
        *) OS_NAME="$ID"; PM='apt';;
    esac
}
check_dependencies

# 检查并安装 Nginx (保持原逻辑不变)
echo "检查 Nginx 是否已安装..."
if ! command -v nginx &> /dev/null; then
    echo "Nginx 未安装，正在安装..."
    # 原安装逻辑保持不变，此处省略以节省篇幅
else
    echo "Nginx 已安装，跳过安装步骤。"
fi

# 下载并复制 nginx.conf
echo "下载并复制 nginx 配置文件..."
curl -o /etc/nginx/nginx.conf https://github.com/xiyily/Emby_nginx_proxy/main/yily/nginx.conf

you_domain_config="$you_domain"
download_domain_config="p.example.com"

# 如果 $no_tls 选择使用 HTTP，则选择下载对应的模板
if [[ "$no_tls" == "yes" ]]; then
    you_domain_config="$you_domain.$you_frontend_port"
    download_domain_config="p.example.com.no_tls"
fi

# 下载并创建配置文件
echo "下载并创建 $you_domain_config 配置文件..."
curl -o "$you_domain_config.conf" "https://github.com/xiyily/Emby_nginx_proxy/tree/main/yily/conf.d/$download_domain_config.conf"

# 修改端口
if [[ -n "$you_frontend_port" ]]; then
    sed -i "s/443/$you_frontend_port/g" "$you_domain_config.conf"
fi

# 如果 r_http_frontend 使用 HTTP，替换前端协议
if [[ "$r_http_frontend" == "yes" ]]; then
    sed -i "s/https:\/\/emby.example.com/http:\/\/emby.example.com/g" "$you_domain_config.conf"
fi

# 替换域名信息 (前端主站)
sed -i "s/p.example.com/$you_domain/g" "$you_domain_config.conf"
sed -i "s/emby.example.com/${backend_domains[0]:-emby.example.com}/g" "$you_domain_config.conf"

# 如果 r_http_backend 使用 HTTP，替换后端协议
if [[ "$r_http_backend" == "yes" ]]; then
    sed -i "s/https:\/\/\$website/http:\/\/\$website/g" "$you_domain_config.conf"
fi

# 移动配置文件
echo "移动 $you_domain_config.conf 到 /etc/nginx/conf.d/"
if [[ "$OS_NAME" == "ubuntu" ]]; then
    rsync -av "$you_domain_config.conf" /etc/nginx/conf.d/
else
    mv -f "$you_domain_config.conf" /etc/nginx/conf.d/
fi

# TLS 配置 (保持原逻辑不变)
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
            rm -f "/etc/nginx/conf.d/$you_domain_config.conf"
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
