#!/bin/bash

echo "🔍 测试代理连接..."
echo ""

# 检查 Clash 服务状态
echo "1. 检查 Clash 服务状态："
if pgrep -f "mihomo-linux\|clash-linux" > /dev/null; then
    echo "   ✅ Clash 服务运行中"
    echo "   PID: $(pgrep -f 'mihomo-linux\|clash-linux')"
else
    echo "   ❌ Clash 服务未运行"
    echo "   请先运行: bash restart.sh"
    exit 1
fi

# 检查端口监听
echo ""
echo "2. 检查端口监听："
if command -v lsof >/dev/null 2>&1; then
    if lsof -i :7890 > /dev/null 2>&1; then
        echo "   ✅ 端口 7890 正在监听"
    else
        echo "   ❌ 端口 7890 未监听"
        exit 1
    fi
else
    echo "   ⚠️  lsof 命令不可用，跳过端口检查"
fi

# 检查环境变量
echo ""
echo "3. 检查代理环境变量："
if [ -n "$http_proxy" ] || [ -n "$HTTP_PROXY" ]; then
    echo "   ✅ 代理环境变量已设置"
    echo "   http_proxy: $http_proxy"
    echo "   https_proxy: $https_proxy"
else
    echo "   ❌ 代理环境变量未设置"
    echo "   请运行: source proxy_on.sh"
    exit 1
fi

# 测试代理连接
echo ""
echo "4. 测试代理连接："
echo "   测试 Google..."
if curl -I --connect-timeout 10 --max-time 15 https://www.google.com > /dev/null 2>&1; then
    echo "   ✅ Google 访问成功"
else
    echo "   ❌ Google 访问失败"
fi

echo ""
echo "   测试 Hugging Face..."
if curl -I --connect-timeout 10 --max-time 15 https://huggingface.co > /dev/null 2>&1; then
    echo "   ✅ Hugging Face 访问成功"
else
    echo "   ❌ Hugging Face 访问失败"
    echo "   建议检查代理节点或更换其他节点"
fi

echo ""
echo "测试完成！"