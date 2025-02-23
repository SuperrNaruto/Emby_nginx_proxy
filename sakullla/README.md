# Nginx Nmby 反代指南

Github [@sakullla](https://github.com/sakullla) 

- 支持单个域名的反向代理。支持 301 302 307的重定向代理
- 支持 http1.1 \ http2 \ http3，ipv4 / ipv6 访问
- 支持代理多个Emby服，每次只要根据模板调整和申请证书即可
- 目前模板里默认重定向后的地址是 https ，如果是 http 需要自己调整模板。

# 一键部署脚本
```shell
curl -sSL https://raw.githubusercontent.com/sakullla/nginx-reverse-emby/main/deploy.sh | bash -s -- -y yourdomain.com -r backend.com
```
或者交互式
```shell
bash <(curl -sSL https://raw.githubusercontent.com/sakullla/nginx-reverse-emby/main/deploy.sh)
```


**首次使用请查看[full.md](full.md)**
# 快速使用

- 将 [p.example.com.conf](conf.d/p.example.com.conf) 拷贝成你的域名配置 比如 you.example.com.conf
```shell
cp p.example.com.conf you.example.com.conf
```

- 将you.example.com.conf里面的 p.example.com 替换为 拷贝成你的域名配置 比如 you.example.com
```shell
sed -i 's/p.example.com/you.example.com/g' you.example.com.conf
```

- 将you.example.com.conf里面的 emby.example.com 替换为要反代的域名 r.example.com
```shell
sed -i 's/emby.example.com/r.example.com/g' you.example.com.conf
```

- 将 you.example.com.conf 放到 /etc/nginx/conf.d 下面
```shell
mv you.example.com.conf /etc/nginx/conf.d/
```

- 使用 standalone 模式为你的域名 you.example.com 申请 ECC 证书，并放到指定位置

```shell
mkdir -p /etc/nginx/certs/you.example.com
acme.sh --issue -d you.example.com  --standalone --keylength ec-256
acme.sh --install-cert -d you.example.com --ecc --fullchain-file /etc/nginx/certs/you.example.com/cert --key-file /etc/nginx/certs/you.example.com/key --reloadcmd "nginx -s reload"
```





