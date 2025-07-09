#!/bin/bash

# 定义颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置文件路径
CONF_DIR="$(dirname "$0")/conf"
CONFIG_FILE="$CONF_DIR/config.yaml"
RAW_CONFIG_FILE="$CONF_DIR/config_raw.yaml"
DECODED_CONFIG_FILE="$CONF_DIR/config_decoded.yaml"

# 代理计数器
PROXY_COUNT=0
DUPLICATE_COUNT=0

# 临时文件用于重复名称处理
TEMP_NAME_FILE="/tmp/clash_proxy_names.tmp"

# URL安全的base64解码函数
decode_base64_url() {
    local input="$1"
    # 替换URL安全字符
    input="${input//-/+}"
    input="${input//_/\/}"
    
    # 添加padding
    case $((${#input} % 4)) in
        2) input="${input}==" ;;
        3) input="${input}=" ;;
    esac
    
    # 优先使用python3进行解码
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import base64; print(base64.b64decode('$input').decode('utf-8', errors='ignore'))" 2>/dev/null && return 0
    fi
    
    # 备用方案使用base64命令
    echo "$input" | base64 -d 2>/dev/null || echo ""
}

# 解析SS链接
parse_ss() {
    local ss_url="$1"
    local ss_content=${ss_url#ss://}
    
    # 解码SS链接
    local decoded=$(decode_base64_url "$ss_content")
    
    if [ -z "$decoded" ]; then
        echo "# Failed to decode SS link"
        return 1
    fi
    
    # 解析格式: method:password@server:port
    local method=$(echo "$decoded" | cut -d: -f1)
    local rest=$(echo "$decoded" | cut -d: -f2-)
    local password=$(echo "$rest" | cut -d@ -f1)
    local server_port=$(echo "$rest" | cut -d@ -f2)
    local server=$(echo "$server_port" | cut -d: -f1)
    local port=$(echo "$server_port" | cut -d: -f2)
    
    # 生成代理名称
    local name="SS-${server}-${port}"
    
    # 检查重复名称
    if [ -f "$TEMP_NAME_FILE" ] && grep -q "^$name$" "$TEMP_NAME_FILE"; then
        DUPLICATE_COUNT=$((DUPLICATE_COUNT + 1))
        name="${name}-${DUPLICATE_COUNT}"
    fi
    echo "$name" >> "$TEMP_NAME_FILE"
    
    # 输出Clash格式配置
    cat << EOF
  - name: "$name"
    type: ss
    server: $server
    port: $port
    cipher: $method
    password: $password
EOF
    
    PROXY_COUNT=$((PROXY_COUNT + 1))
}

# 解析SSR链接
parse_ssr() {
    local ssr_url="$1"
    local ssr_content=${ssr_url#ssr://}
    
    # 解码SSR链接
    local decoded=$(decode_base64_url "$ssr_content")
    
    if [ -z "$decoded" ]; then
        echo "# Failed to decode SSR link"
        return 1
    fi
    
    # 解析格式: server:port:protocol:method:obfs:password_base64/?params
    local server=$(echo "$decoded" | cut -d: -f1)
    local port=$(echo "$decoded" | cut -d: -f2)
    local protocol=$(echo "$decoded" | cut -d: -f3)
    local method=$(echo "$decoded" | cut -d: -f4)
    local obfs=$(echo "$decoded" | cut -d: -f5)
    local password_and_params=$(echo "$decoded" | cut -d: -f6-)
    
    # 从password_and_params中提取password和参数
    local password_base64=$(echo "$password_and_params" | cut -d/ -f1)
    local params_part=$(echo "$password_and_params" | cut -d/ -f2- | cut -d? -f2-)
    
    # 解码密码
    local password=$(decode_base64_url "$password_base64")
    
    # 解析参数
    local obfsparam=""
    local protocolparam=""
    local remarks=""
    
    if [ -n "$params_part" ]; then
        # 使用正则表达式提取参数
        if [[ "$params_part" =~ obfsparam=([^&]*) ]]; then
            obfsparam=$(decode_base64_url "${BASH_REMATCH[1]}")
        fi
        if [[ "$params_part" =~ protocolparam=([^&]*) ]]; then
            protocolparam=$(decode_base64_url "${BASH_REMATCH[1]}")
        fi
        if [[ "$params_part" =~ remarks=([^&]*) ]]; then
            remarks=$(decode_base64_url "${BASH_REMATCH[1]}")
        fi
    fi
    
    # 生成代理名称
    local name="SSR-${server}-${port}"
    if [ -n "$remarks" ]; then
        name="$remarks"
    fi
    
    # 检查重复名称
    if [ -f "$TEMP_NAME_FILE" ] && grep -q "^$name$" "$TEMP_NAME_FILE"; then
        DUPLICATE_COUNT=$((DUPLICATE_COUNT + 1))
        name="${name}-${DUPLICATE_COUNT}"
    fi
    echo "$name" >> "$TEMP_NAME_FILE"
    
    # 输出Clash格式配置
    cat << EOF
  - name: "$name"
    type: ssr
    server: $server
    port: $port
    cipher: $method
    password: $password
    protocol: $protocol
    obfs: $obfs
EOF
    
    if [ -n "$protocolparam" ]; then
        echo "    protocol-param: $protocolparam"
    fi
    if [ -n "$obfsparam" ]; then
        echo "    obfs-param: $obfsparam"
    fi
    
    PROXY_COUNT=$((PROXY_COUNT + 1))
}

# 解析VLESS链接
parse_vless() {
    local vless_url="$1"
    
    # 移除vless://前缀
    local vless_content=${vless_url#vless://}
    
    # 解析格式: uuid@server:port?params#name
    local uuid=$(echo "$vless_content" | cut -d@ -f1)
    local server_port_params=$(echo "$vless_content" | cut -d@ -f2)
    local server=$(echo "$server_port_params" | cut -d: -f1)
    local port_params=$(echo "$server_port_params" | cut -d: -f2)
    local port=$(echo "$port_params" | cut -d? -f1)
    local params=$(echo "$port_params" | cut -d? -f2 | cut -d# -f1)
    local name=$(echo "$port_params" | cut -d# -f2 | sed 's/%20/ /g')
    
    # 默认参数
    local encryption="none"
    local network="tcp"
    local security=""
    local sni=""
    local alpn=""
    local path=""
    local host=""
    
    # 解析参数
    if [ -n "$params" ]; then
        IFS='&' read -ra PARAM_ARRAY <<< "$params"
        for param in "${PARAM_ARRAY[@]}"; do
            key=$(echo "$param" | cut -d= -f1)
            value=$(echo "$param" | cut -d= -f2)
            case "$key" in
                "encryption") encryption="$value" ;;
                "security") security="$value" ;;
                "sni") sni="$value" ;;
                "alpn") alpn="$value" ;;
                "path") path="$value" ;;
                "host") host="$value" ;;
                "type") network="$value" ;;
            esac
        done
    fi
    
    # 生成代理名称
    if [ -z "$name" ]; then
        name="VLESS-${server}-${port}"
    fi
    
    # 检查重复名称
    if [ -f "$TEMP_NAME_FILE" ] && grep -q "^$name$" "$TEMP_NAME_FILE"; then
        DUPLICATE_COUNT=$((DUPLICATE_COUNT + 1))
        name="${name}-${DUPLICATE_COUNT}"
    fi
    echo "$name" >> "$TEMP_NAME_FILE"
    
    # 输出Clash格式配置
    cat << EOF
  - name: "$name"
    type: vless
    server: $server
    port: $port
    uuid: $uuid
    cipher: auto
    network: $network
EOF
    
    if [ -n "$security" ] && [ "$security" != "none" ]; then
        echo "    tls: true"
        if [ -n "$sni" ]; then
            echo "    servername: $sni"
        fi
        if [ -n "$alpn" ]; then
            echo "    alpn: [$alpn]"
        fi
    fi
    
    if [ "$network" = "ws" ]; then
        echo "    ws-opts:"
        if [ -n "$path" ]; then
            echo "      path: $path"
        fi
        if [ -n "$host" ]; then
            echo "      headers:"
            echo "        Host: $host"
        fi
    fi
    
    PROXY_COUNT=$((PROXY_COUNT + 1))
}

# 解析VMESS链接
parse_vmess() {
    local vmess_url="$1"
    local vmess_content=${vmess_url#vmess://}
    
    # 解码VMESS链接
    local decoded=$(decode_base64_url "$vmess_content")
    
    if [ -z "$decoded" ]; then
        echo "# Failed to decode VMESS link"
        return 1
    fi
    
    # 使用python解析JSON（如果可用）
    if command -v python3 >/dev/null 2>&1; then
        local parsed=$(python3 -c "
import json
try:
    data = json.loads('$decoded')
    print(f\"{data.get('add', '')},{data.get('port', '')},{data.get('id', '')},{data.get('aid', '0')},{data.get('net', 'tcp')},{data.get('type', 'none')},{data.get('host', '')},{data.get('path', '')},{data.get('tls', '')},{data.get('ps', '')},{data.get('scy', 'auto')}\")
except:
    print('ERROR')
")
        
        if [ "$parsed" = "ERROR" ]; then
            echo "# Failed to parse VMESS JSON"
            return 1
        fi
        
        IFS=',' read -r server port uuid aid network type host path tls name cipher <<< "$parsed"
    else
        echo "# Python3 not available for VMESS parsing"
        return 1
    fi
    
    # 生成代理名称
    if [ -z "$name" ]; then
        name="VMESS-${server}-${port}"
    fi
    
    # 检查重复名称
    if [ -f "$TEMP_NAME_FILE" ] && grep -q "^$name$" "$TEMP_NAME_FILE"; then
        DUPLICATE_COUNT=$((DUPLICATE_COUNT + 1))
        name="${name}-${DUPLICATE_COUNT}"
    fi
    echo "$name" >> "$TEMP_NAME_FILE"
    
    # 输出Clash格式配置
    cat << EOF
  - name: "$name"
    type: vmess
    server: $server
    port: $port
    uuid: $uuid
    alterId: $aid
    cipher: $cipher
    network: $network
EOF
    
    if [ -n "$tls" ] && [ "$tls" != "none" ]; then
        echo "    tls: true"
    fi
    
    if [ "$network" = "ws" ]; then
        echo "    ws-opts:"
        if [ -n "$path" ]; then
            echo "      path: $path"
        fi
        if [ -n "$host" ]; then
            echo "      headers:"
            echo "        Host: $host"
        fi
    fi
    
    PROXY_COUNT=$((PROXY_COUNT + 1))
}

# 主转换函数
convert_subscription() {
    local input_file="$1"
    local output_file="$2"
    
    # 清理临时文件
    rm -f "$TEMP_NAME_FILE"
    touch "$TEMP_NAME_FILE"
    
    # 重置计数器
    PROXY_COUNT=0
    DUPLICATE_COUNT=0
    
    echo -e "${YELLOW}开始转换订阅链接...${NC}"
    
    # 读取原始配置文件
    if [ ! -f "$input_file" ]; then
        echo -e "${RED}错误：输入文件不存在 - $input_file${NC}"
        return 1
    fi
    
    # 备份原始文件
    cp "$input_file" "$RAW_CONFIG_FILE"
    
    # 开始生成Clash配置
    cat > "$output_file" << 'EOF'
port: 7890
socks-port: 7891
redir-port: 7892
mixed-port: 7893
allow-lan: true
mode: Rule
log-level: info
ipv6: false
external-controller: 0.0.0.0:6006
external-ui: dashboard
secret: ""

dns:
  enable: true
  ipv6: false
  default-nameserver:
    - 223.5.5.5
    - 8.8.8.8
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - https://doh.pub/dns-query
    - https://dns.alidns.com/dns-query

proxies:
EOF
    
    # 处理每一行
    while IFS= read -r line; do
        # 跳过空行和注释
        [ -z "$line" ] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        
        # 检测协议类型并解析
        if [[ "$line" =~ ^ss:// ]]; then
            parse_ss "$line" >> "$output_file"
        elif [[ "$line" =~ ^ssr:// ]]; then
            parse_ssr "$line" >> "$output_file"
        elif [[ "$line" =~ ^vless:// ]]; then
            parse_vless "$line" >> "$output_file"
        elif [[ "$line" =~ ^vmess:// ]]; then
            parse_vmess "$line" >> "$output_file"
        else
            echo "# 未识别的协议: $line" >> "$output_file"
        fi
    done < "$input_file"
    
    # 添加代理组和规则
    cat >> "$output_file" << 'EOF'

proxy-groups:
  - name: 🚀 手动切换
    type: select
    proxies:
      - 🎯 全球直连
      - ♻️ 自动选择
      - 🔯 故障转移
      - 🔮 负载均衡
      - 🇭🇰 香港节点
      - 🇯🇵 日本节点
      - 🇺🇸 美国节点
      - 🇸🇬 新加坡节点
      - 🇰🇷 韩国节点
      - 🇹🇼 台湾节点
  
  - name: ♻️ 自动选择
    type: url-test
    proxies:
      - 🎯 全球直连
    url: http://www.gstatic.com/generate_204
    interval: 300
    tolerance: 50
  
  - name: 🔯 故障转移
    type: fallback
    proxies:
      - 🎯 全球直连
    url: http://www.gstatic.com/generate_204
    interval: 300
  
  - name: 🔮 负载均衡
    type: load-balance
    proxies:
      - 🎯 全球直连
    url: http://www.gstatic.com/generate_204
    interval: 300
    strategy: consistent-hashing
  
  - name: 🇭🇰 香港节点
    type: select
    proxies:
      - 🎯 全球直连
  
  - name: 🇯🇵 日本节点
    type: select
    proxies:
      - 🎯 全球直连
  
  - name: 🇺🇸 美国节点
    type: select
    proxies:
      - 🎯 全球直连
  
  - name: 🇸🇬 新加坡节点
    type: select
    proxies:
      - 🎯 全球直连
  
  - name: 🇰🇷 韩国节点
    type: select
    proxies:
      - 🎯 全球直连
  
  - name: 🇹🇼 台湾节点
    type: select
    proxies:
      - 🎯 全球直连
  
  - name: 🎯 全球直连
    type: select
    proxies:
      - DIRECT

rules:
  - GEOIP,CN,🎯 全球直连
  - MATCH,🚀 手动切换
EOF
    
    # 更新代理组，添加实际的代理节点
    if [ $PROXY_COUNT -gt 0 ]; then
        # 提取所有代理名称
        local proxy_names=$(grep -o 'name: "[^"]*"' "$output_file" | sed 's/name: "\([^"]*\)"/\1/' | grep -v "全球直连\|手动切换\|自动选择\|故障转移\|负载均衡\|香港节点\|日本节点\|美国节点\|新加坡节点\|韩国节点\|台湾节点")
        
        # 生成临时文件用于更新代理组
        local temp_config="/tmp/updated_config.yaml"
        cp "$output_file" "$temp_config"
        
        # 更新各个代理组
        for group in "♻️ 自动选择" "🔯 故障转移" "🔮 负载均衡"; do
            # 在代理组中添加所有代理
            sed -i "/name: $group/,/url:/ { /proxies:/,/url:/ { /proxies:/a\\
$(echo "$proxy_names" | sed 's/^/      - /')
            }; }" "$temp_config"
        done
        
        # 按地区分组节点
        for region in "🇭🇰 香港节点" "🇯🇵 日本节点" "🇺🇸 美国节点" "🇸🇬 新加坡节点" "🇰🇷 韩国节点" "🇹🇼 台湾节点"; do
            local region_proxies=""
            case "$region" in
                "🇭🇰 香港节点") region_proxies=$(echo "$proxy_names" | grep -iE "(hk|hong|港)") ;;
                "🇯🇵 日本节点") region_proxies=$(echo "$proxy_names" | grep -iE "(jp|japan|日本)") ;;
                "🇺🇸 美国节点") region_proxies=$(echo "$proxy_names" | grep -iE "(us|america|美国)") ;;
                "🇸🇬 新加坡节点") region_proxies=$(echo "$proxy_names" | grep -iE "(sg|singapore|新加坡)") ;;
                "🇰🇷 韩国节点") region_proxies=$(echo "$proxy_names" | grep -iE "(kr|korea|韩国)") ;;
                "🇹🇼 台湾节点") region_proxies=$(echo "$proxy_names" | grep -iE "(tw|taiwan|台湾)") ;;
            esac
            
            if [ -n "$region_proxies" ]; then
                sed -i "/name: $region/,/^  -/ { /proxies:/a\\
$(echo "$region_proxies" | sed 's/^/      - /')
                }" "$temp_config"
            fi
        done
        
        mv "$temp_config" "$output_file"
    fi
    
    # 清理临时文件
    rm -f "$TEMP_NAME_FILE"
    
    echo -e "${GREEN}转换完成！${NC}"
    echo -e "${GREEN}共转换了 $PROXY_COUNT 个代理节点${NC}"
    
    # 保存解码后的配置文件
    cp "$output_file" "$DECODED_CONFIG_FILE"
    
    return 0
}

# 自动设置代理模式
set_proxy_mode() {
    local config_file="$1"
    local mode="${2:-rule}"  # 默认为rule模式
    
    # 检查mihomo是否运行
    if ! pgrep -f "mihomo" >/dev/null 2>&1; then
        echo -e "${YELLOW}Mihomo未运行，无法设置代理模式${NC}"
        return 1
    fi
    
    # 等待mihomo完全启动
    sleep 2
    
    # 设置代理模式
    if curl -s -X PUT "http://127.0.0.1:6006/configs" \
        -H "Content-Type: application/json" \
        -d "{\"mode\": \"$mode\"}" >/dev/null 2>&1; then
        echo -e "${GREEN}代理模式已设置为: $mode${NC}"
    else
        echo -e "${YELLOW}无法设置代理模式，请手动在面板中设置${NC}"
    fi
}

# 主函数
main() {
    local input_file="${1:-$RAW_CONFIG_FILE}"
    local output_file="${2:-$CONFIG_FILE}"
    
    echo -e "${YELLOW}启动自定义订阅转换器${NC}"
    
    # 检查输入文件
    if [ ! -f "$input_file" ]; then
        echo -e "${RED}错误：输入文件不存在 - $input_file${NC}"
        exit 1
    fi
    
    # 执行转换
    if convert_subscription "$input_file" "$output_file"; then
        echo -e "${GREEN}转换成功！输出文件: $output_file${NC}"
        
        # 设置代理模式
        set_proxy_mode "$output_file" "rule"
        
        exit 0
    else
        echo -e "${RED}转换失败！${NC}"
        exit 1
    fi
}

# 如果直接运行此脚本
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi