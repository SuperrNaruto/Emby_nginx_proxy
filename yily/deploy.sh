#!/bin/bash

set -e

# 显示帮助信息
show_help() {
    cat << EOF
用法: $(basename "$0") [选项]

选项:
  -y, --you-domain <域名>        你的域名或IP (例如: example.com)
  -r, --r-domain <域名>          反代 Emby 的域名 (例如: backend.com)
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
r_domain=""
you_frontend_port="443"
r_frontend_port=""
r_http_backend="no"
r_http_frontend="no"
no_tls="no"
stream_servers=()

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
        -r|--r-domain) r_domain="$2"; shift 2 ;;
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
if [[ -z "$you_domain" || -z "$r_domain" ]]; then
    echo -e "\n--- 交互模式: 配置反向代理 ---"
    echo "请按提示输入参数，或直接按 Enter 使用默认值"
    read -p "你的域名或者 IP [默认: you.example.com]: " input_you_domain
    read -p "反代Emby的域名 [默认: r.example.com]: " input_r_domain

    # 询问用户推流服务器的数量
    read -p "请输入推流服务器的数量 (默认: 0): " input_stream_server_count
    stream_server_count="${input_stream_server_count:-0}"

    # 如果推流服务器数量大于0，询问每个推流服务器的域名
    if [[ "$stream_server_count" -gt 0 ]]; then
        for ((i=1; i<=stream_server_count; i++)); do
            read -p "请输入第 $i 个推流服务器的域名: " stream_server_domain
            stream_servers+=("$stream_server_domain")
        done
    fi

    read -p "你的前端访问端口 [默认: 443]: " input_you_frontend_port
    read -p "反代Emby前端端口 [默认: 空]: " input_r_frontend_port
    read -p "是否使用HTTP连接反代Emby后端? (yes/no) [默认: no]: " input_r_http_backend
    read -p "是否使用HTTP连接反代Emby前端? (yes/no) [默认: no]: " input_r_http_frontend
    read -p "是否禁用TLS? (yes/no) [默认: no]: " input_no_tls

    # 赋值默认值
    you_domain="${input_you_domain:-you.example.com}"
    r_domain="${input_r_domain:-r.example.com}"
    you_frontend_port="${input_you_frontend_port:-443}"
    r_frontend_port="${input_r_frontend_port}"
    r_http_backend="${input_r_http_backend:-no}"
    r_http_frontend="${input_r_http_frontend:-no}"
    no_tls="${input_no_tls:-no}"
fi

# 美化输出配置信息
protocol=$( [[ "$no_tls" == "yes" ]] && echo "http" || echo "https" )
url="${protocol}://${you_domain}:${you_frontend_port}"

echo -e "\n------ 配置信息 ------"
echo "🌍 访问地址: ${url}"
echo "📌 你的域名: ${you_domain}"
echo "🖥️  你的前端访问端口: ${you_frontend_port}"
echo "🔄 反代 Emby 的域名: ${r_domain}"
echo "🎯 反代 Emby 前端端口: ${r_frontend_port:-未指定}"
echo "🔗 使用 HTTP 连接反代 Emby 后端: $( [[ "$r_http_backend" == "yes" ]] && echo "✅ 是" || echo "❌ 否" )"
echo "🛠️  使用 HTTP 连接反代 Emby 前端: $( [[ "$r_http_frontend" == "yes" ]] && echo "✅ 是" || echo "❌ 否" )"
echo "🔒 禁用 TLS: $( [[ "$no_tls" == "yes" ]] && echo "✅ 是" || echo "❌ 否" )"
echo "📡 推流服务器数量: ${stream_server_count}"
for ((i=0; i<stream_server_count; i++)); do
    echo "  🖥️  推流服务器 $((i+1)): ${stream_servers[$i]}"
done
echo "----------------------"

# 检查依赖项并安装 Nginx
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
    # 安装 Nginx 的代码保持不变
    # ...
else
    echo "Nginx 已安装，跳过安装步骤。"
fi

# 下载并复制 nginx.conf
echo "下载并复制 nginx 配置文件..."
curl -o /etc/nginx/nginx.conf https://raw.githubusercontent.com/xinyily/nginx-reverse-emby/main/yily/nginx.conf

you_domain_config="$you_domain"
download_domain_config="p.example.com"

# 如果 $no_tls 选择使用 HTTP，则选择下载对应的模板
if [[ "$no_tls" == "yes" ]]; then
    you_domain_config="$you_domain.$you_frontend_port"
    download_domain_config="p.example.com.no_tls"
fi

# 下载并复制 p.example.com.conf 并修改
echo "下载并创建 $you_domain_config 配置文件..."
curl -o "$you_domain_config.conf" "https://raw.githubusercontent.com/xinyily/Emby_nginx_proxy/main/yily/conf.d/$download_domain_config.conf"

# 如果 you_frontend_port 不为空， 则替换端口
if [[ -n "$you_frontend_port" ]]; then
    sed -i "s/443/$you_frontend_port/g" "$you_domain_config.conf"
fi

# 如果 r_http_frontend 选择使用 HTTP，先替换 https://emby.example.com
if [[ "$r_http_frontend" == "yes" ]]; then
    sed -i "s/https:\/\/emby.example.com/http:\/\/emby.example.com/g" "$you_domain_config.conf"
fi

# 如果 r_frontend_port 不为空，修改 emby.example.com 加上端口
if [[ -n "$r_frontend_port" ]]; then
    sed -i "s/emby.example.com/emby.example.com:$r_frontend_port/g" "$you_domain_config.conf"
fi

# 替换域名信息
sed -i "s/p.example.com/$you_domain/g" "$you_domain_config.conf"
sed -i "s/emby.example.com/$r_domain/g" "$you_domain_config.conf"

# 如果 r_http_backend 选择使用 HTTP，替换 https://$website
if [[ "$r_http_backend" == "yes" ]]; then
    sed -i "s/https:\/\/\$website/http:\/\/\$website/g" "$you_domain_config.conf"
fi

# 移动配置文件到 /etc/nginx/conf.d/
echo "移动 $you_domain_config.conf 到 /etc/nginx/conf.d/"
if [[ "$OS_NAME" == "ubuntu" ]]; then
  rsync -av "$you_domain_config.conf" /etc/nginx/conf.d/
else
  mv -f "$you_domain_config.conf" /etc/nginx/conf.d/
fi

# 如果有推流服务器，生成对应的配置文件
if [[ "$stream_server_count" -gt 0 ]]; then
    for stream_server in "${stream_servers[@]}"; do
        stream_config="${stream_server}.conf"
        echo "生成推流服务器配置文件: $stream_config"
        cp "$you_domain_config.conf" "$stream_config"
        sed -i "s/$r_domain/$stream_server/g" "$stream_config"
        mv -f "$stream_config" /etc/nginx/conf.d/
    done
fi

if [[ "$no_tls" != "yes" ]]; then
    ACME_SH="$HOME/.acme.sh/acme.sh"

    # 检查并安装 acme.sh
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

    # 申请并安装 ECC 证书
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

    # 安装证书
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
