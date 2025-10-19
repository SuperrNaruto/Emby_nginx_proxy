# Nginx Emby  一键反代指南

### 支持Emby前后端推流服务器 不同域名后缀 下的反向代理
> 注意：不支持http代理

### >> [单域名反向代理](https://github.com/sakullla/nginx-reverse-emby)<<

# 下载运行
1. 下载脚本
```bash
wget https://raw.githubusercontent.com/iuvu/Emby_nginx_proxy/main/Proxy_Louis.sh
```
> 注意：可能存在重复下载文件，需要手动删除文件

2. 运行脚本
```
bash Proxy_Louis.sh
```

# 若需要修改反代地址，参考以下步骤
```bash
nano /etc/nginx/proxy_louis.conf
```

此时修改内部的`EMBY_URL` `STREAM_COUNT`等配置即可
