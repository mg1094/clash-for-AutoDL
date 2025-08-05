#!/bin/bash

# 设置代理环境变量
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
export HTTP_PROXY=http://127.0.0.1:7890
export HTTPS_PROXY=http://127.0.0.1:7890
export ftp_proxy=http://127.0.0.1:7890
export FTP_PROXY=http://127.0.0.1:7890
export all_proxy=http://127.0.0.1:7890
export ALL_PROXY=http://127.0.0.1:7890

# 设置不走代理的地址
export no_proxy="localhost,127.0.0.1,::1,*.local"
export NO_PROXY="localhost,127.0.0.1,::1,*.local"

echo "✅ 代理已开启"
echo "HTTP/HTTPS 代理: http://127.0.0.1:7890"
echo ""
echo "测试代理是否生效："
echo "curl -I --connect-timeout 10 https://www.google.com"
echo ""
echo "关闭代理请运行: source proxy_off.sh"