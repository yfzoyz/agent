#!/bin/bash
set -e

# ==============================================================================
# 哪吒监控 Agent Bohrium 专用一键安装脚本 (CDN/EdgeOne 修复版)
# 仓库: https://github.com/yfzoyz/agent
# 包含 Terminal (网页终端) 与 File Manager (文件管理) 完整支持
# ==============================================================================

# 参数提取（支持环境变量与命令行参数）
NZ_SERVER="${NZ_SERVER:-nezha.loc.cc:443}"
NZ_CLIENT_SECRET="${NZ_CLIENT_SECRET:-}"
NZ_UUID="${NZ_UUID:-}"
NZ_TLS="${NZ_TLS:-true}"
NZ_REPORT_DELAY="${NZ_REPORT_DELAY:-3}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--server)
            NZ_SERVER="$2"
            shift 2
            ;;
        -p|--secret|--client-secret)
            NZ_CLIENT_SECRET="$2"
            shift 2
            ;;
        -u|--uuid)
            NZ_UUID="$2"
            shift 2
            ;;
        --tls)
            NZ_TLS="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

if [ -z "$NZ_CLIENT_SECRET" ]; then
    echo "❌ 错误: 未提供客户端密钥 (NZ_CLIENT_SECRET)！"
    echo "用法示例:"
    echo "  env NZ_SERVER=nezha.loc.cc:443 NZ_CLIENT_SECRET=xxx NZ_UUID=xxx bash install_bohrium_nezha.sh"
    echo "或者:"
    echo "  bash install_bohrium_nezha.sh -s nezha.loc.cc:443 -p xxx -u xxx"
    exit 1
fi

echo "=========================================="
echo "🚀 开始安装哪吒监控 Agent (Bohrium 专版)"
echo "📡 服务器: $NZ_SERVER"
echo "🔐 TLS: $NZ_TLS"
echo "=========================================="

# 1. 清理旧进程与冲突服务
echo "🛑 正在清理旧版本及冲突进程..."
killall -9 nezha-agent 2>/dev/null || true
pkill -9 -f "nezha_daemon.py" 2>/dev/null || true
pkill -9 -f "./nezha-agent" 2>/dev/null || true

# 2. 创建运行目录
INSTALL_DIR="/opt/nezha/agent"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# 2.1 优化 Cloudflare 节点网络路由 (纯原生 Hosts 绑定，无需代理软件)
echo "⚡ 正在配置原生 Cloudflare 稳定节点路由..."
python3 -c "
try:
    with open('/etc/hosts', 'r') as f:
        lines = [l for l in f.read().splitlines() if 'nezha.loc.cc' not in l]
    lines.append('162.159.153.1 nezha.loc.cc')
    with open('/etc/hosts', 'w') as f:
        f.write('\n'.join(lines) + '\n')
except Exception as e:
    pass
" 2>/dev/null || true

# 3. 下载修复版二进制 nezha-agent
echo "📥 正在下载针对 CDN 代理优化的 nezha-agent 二进制文件 (v2.4.5)..."
DOWNLOAD_URLS=(
    "https://ghfast.top/https://github.com/yfzoyz/agent/releases/download/v2.4.5/nezha-agent_linux_amd64.zip"
    "https://ghproxy.net/https://github.com/yfzoyz/agent/releases/download/v2.4.5/nezha-agent_linux_amd64.zip"
    "https://github.com/yfzoyz/agent/releases/download/v2.4.5/nezha-agent_linux_amd64.zip"
    "https://ghfast.top/https://github.com/yfzoyz/agent/releases/download/v2.4.4/nezha-agent_linux_amd64.zip"
    "https://ghproxy.net/https://github.com/yfzoyz/agent/releases/download/v2.4.4/nezha-agent_linux_amd64.zip"
    "https://github.com/yfzoyz/agent/releases/download/v2.4.4/nezha-agent_linux_amd64.zip"
    "https://ghfast.top/https://github.com/yfzoyz/agent/releases/download/v2.4.3/nezha-agent_linux_amd64.zip"
    "https://ghproxy.net/https://github.com/yfzoyz/agent/releases/download/v2.4.3/nezha-agent_linux_amd64.zip"
    "https://github.com/yfzoyz/agent/releases/download/v2.4.3/nezha-agent_linux_amd64.zip"
)

SUCCESS=0
for url in "${DOWNLOAD_URLS[@]}"; do
    echo "尝试从 $url 下载..."
    if [[ "$url" == *.zip ]]; then
        if curl --noproxy "*" -fSL -m 30 "$url" -o nezha-agent.zip; then
            if unzip -o nezha-agent.zip && chmod +x nezha-agent; then
                rm -f nezha-agent.zip
                SUCCESS=1
                echo "✅ 解压并配置成功！"
                break
            fi
        fi
    else
        if curl --noproxy "*" -fSL -m 30 "$url" -o nezha-agent.tmp; then
            mv nezha-agent.tmp nezha-agent
            chmod +x nezha-agent
            SUCCESS=1
            echo "✅ 下载成功！"
            break
        fi
    fi
    echo "⚠️ 下载失败，尝试下一个源..."
done

if [ "$SUCCESS" -ne 1 ]; then
    echo "❌ 所有下载节点均失败，请检查容器网络。"
    exit 1
fi

# 3. 写入配置文件 config.yml
echo "⚙️ 正在生成配置文件 $INSTALL_DIR/config.yml ..."
cat > "$INSTALL_DIR/config.yml" <<EOF
client_secret: ${NZ_CLIENT_SECRET}
debug: true
disable_auto_update: true
disable_command_execute: false
disable_force_update: true
disable_nat: false
disable_send_query: false
gpu: false
insecure_tls: false
ip_report_period: 1800
report_delay: ${NZ_REPORT_DELAY}
self_update_period: 0
server: ${NZ_SERVER}
skip_connection_count: false
skip_procs_count: false
temperature: false
tls: ${NZ_TLS}
use_atomgit_to_upgrade: false
use_gitee_to_upgrade: false
use_ipv6_country_code: false
uuid: "${NZ_UUID}"
EOF
chmod 600 "$INSTALL_DIR/config.yml"

# 4. 配置 Supervisor 进程守护
SUPERVISOR_CONF="/etc/supervisor/conf.d/nezha-agent.conf"
SUPERVISOR_CFG="/etc/supervisor/openclaw-supervisord.conf"

echo "🔧 配置 Supervisor 守护进程 ($SUPERVISOR_CONF)..."
mkdir -p /etc/supervisor/conf.d/
cat > "$SUPERVISOR_CONF" <<EOF
[program:nezha-agent]
command=/opt/nezha/agent/nezha-agent -c /opt/nezha/agent/config.yml
directory=/opt/nezha/agent
autostart=true
autorestart=true
environment=http_proxy="",https_proxy="",HTTP_PROXY="",HTTPS_PROXY=""
stderr_logfile=/var/log/nezha-agent.err.log
stdout_logfile=/var/log/nezha-agent.out.log
user=root
EOF

# 5. 重载并启动服务
echo "🔄 启动 Agent 服务..."
if [ -f "$SUPERVISOR_CFG" ]; then
    supervisorctl -c "$SUPERVISOR_CFG" update
    supervisorctl -c "$SUPERVISOR_CFG" restart nezha-agent || supervisorctl -c "$SUPERVISOR_CFG" start nezha-agent
    sleep 3
    supervisorctl -c "$SUPERVISOR_CFG" status nezha-agent
else
    echo "⚠️ 未发现 openclaw-supervisord.conf，使用普通 supervisorctl 或后台运行..."
    if command -v supervisorctl >/dev/null 2>&1; then
        supervisorctl update
        supervisorctl restart nezha-agent || supervisorctl start nezha-agent
    else
        killall nezha-agent 2>/dev/null || true
        env http_proxy="" https_proxy="" nohup /opt/nezha/agent/nezha-agent -c /opt/nezha/agent/config.yml > /var/log/nezha-agent.out.log 2>&1 &
    fi
fi

echo "=========================================="
echo "🎉 哪吒监控 Agent 安装配置完成！"
echo "🔍 检查日志命令: tail -f /var/log/nezha-agent.err.log"
echo "=========================================="
