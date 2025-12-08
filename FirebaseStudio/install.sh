#!/usr/bin/env sh

# =================================================================
# 1. 变量初始化与检查
# =================================================================
# 定义核心变量，并设置检查函数
check_var() {
    if [ -z "$1" ]; then
        echo "❌ 错误: 环境变量 $2 未设置。"
        echo "请使用 'export $2=\"<你的值>\"' 设置变量。"
        exit 1
    fi
}

# 检查所有必需的环境变量
check_var "$ARGO_TOKEN" "ARGO_TOKEN"
check_var "$UUID" "UUID"
check_var "$TUNNEL_DOMAIN" "TUNNEL_DOMAIN"
check_var "$PROXY_PATH" "PROXY_PATH"

# 固定内部端口和外部监听端口
PORT_XRAY_INTERNAL="8001"
PORT_NGINX_LISTEN="8388"

# 根目录路径定义
APP_ROOT_DIR=$(pwd)/app
# 远程仓库基础URL (用于下载模板和静态文件)
REPO_BASE="https://raw.githubusercontent.com/justlagom/fsne-Kalive/refs/heads/main/FirebaseStudio"


# =================================================================
# 2. 目录初始化
# =================================================================
echo ">>> 1/6. 初始化目录..."
mkdir -p "$APP_ROOT_DIR"/{argo,xray,nginx/html,idx-keepalive}


# =================================================================
# 3. Xray 核心安装与配置 (监听 8001)
# =================================================================
echo ">>> 2/6. 安装 Xray 核心并配置..."
cd "$APP_ROOT_DIR"/xray

# 3.1. 下载并解压 Xray
wget -q https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
unzip Xray-linux-64.zip
rm -f Xray-linux-64.zip

# 3.2. 下载并配置 config.json
wget -q -O config.json $REPO_BASE/xray/xray-config-template.json

# 替换变量：UUID, 内部端口, 隧道域名, 代理路径
sed -i 's/$UUID/'$UUID'/g' config.json
sed -i 's/$PORT_XRAY_INTERNAL/'$PORT_XRAY_INTERNAL'/g' config.json
sed -i 's/$TUNNEL_DOMAIN/'$TUNNEL_DOMAIN'/g' config.json
# 关键：使用 | 作为 sed 的分隔符来替换包含斜杠的 PROXY_PATH
sed -i 's|$PROXY_PATH|'$PROXY_PATH'|g' config.json
cd -


# =================================================================
# 4. Nginx 伪装安装与配置 (监听 8388, 转发到 8001)
# =================================================================
echo ">>> 3/6. 配置 Nginx 伪装分流..."
cd "$APP_ROOT_DIR"/nginx

# 4.1. 下载 Nginx 二进制文件 (!!! 占位符 - 需用户自行替换)
# wget -q -O nginx <实际的 Nginx 二进制链接>
# chmod +x nginx
touch nginx
chmod +x nginx

# 4.2. 下载静态网页
wget -q -O html/index.html $REPO_BASE/html/index.html

# 4.3. 下载并配置 nginx.conf
wget -q -O nginx.conf $REPO_BASE/nginx/nginx-config-template.conf

# 替换变量：Nginx 监听端口, Xray 内部端口, 代理路径
sed -i 's/$PORT_NGINX_LISTEN/'$PORT_NGINX_LISTEN'/g' nginx.conf
sed -i 's/$PORT_XRAY_INTERNAL/'$PORT_XRAY_INTERNAL'/g' nginx.conf
sed -i 's|$PROXY_PATH|'$PROXY_PATH'|g' nginx.conf
cd -


# =================================================================
# 5. Cloudflared (Argo) 安装
# =================================================================
echo ">>> 4/6. 安装 Cloudflared..."
cd "$APP_ROOT_DIR"/argo
wget -q -O cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x cloudflared
cd -


# =================================================================
# 6. Keepalive (Node.js) 安装与配置
# =================================================================
echo ">>> 5/6. 配置 Keepalive..."
cd "$APP_ROOT_DIR"/idx-keepalive
# 下载 Keepalive 脚本和依赖文件
wget -q -O app.js $REPO_BASE/keepalive/app.js
wget -q -O package.json $REPO_BASE/keepalive/package.json
# 安装 Node.js 依赖
npm install --no-progress
cd -


# =================================================================
# 7. 创建根目录启动脚本 (startup.sh)
# =================================================================
echo ">>> 6/6. 创建 startup.sh..."

# 7.1. 下载主启动脚本模板 (假设远程有一个通用的模板)
# 由于我们没有模板URL，这里使用 cat 直接创建最终脚本内容，方便变量替换
# 注意：在实际项目中，这里应该下载一个模板文件，然后用 sed 替换 $APP_ROOT_DIR 等变量
# 为了使脚本立即可用，我们直接创建，并避免使用 $ARGO_TOKEN 等敏感变量的替换，而是直接在 startup.sh 中引用环境变量
cat > startup.sh <<EOF
#!/usr/bin/env sh

# 检查 ARGO_TOKEN，因为 startup.sh 需要它
if [ -z "\$ARGO_TOKEN" ]; then
    echo "❌ 启动失败: ARGO_TOKEN 环境变量未设置。"
    exit 1
fi

# 确保 Nginx 和 Xray 的固定端口在 startup.sh 中可见
PORT_XRAY_INTERNAL="$PORT_XRAY_INTERNAL"
PORT_NGINX_LISTEN="$PORT_NGINX_LISTEN"
APP_ROOT_DIR="$(pwd)/app" 


# 1. 启动 Xray (后台运行)
echo ">>> 1/4. 启动 Xray 核心 (127.0.0.1:\$PORT_XRAY_INTERNAL)..."
"\$APP_ROOT_DIR"/xray/xray run -c "\$APP_ROOT_DIR"/xray/config.json &
XRAY_PID=\$!
sleep 2

# 2. 启动 Nginx (后台运行)
echo ">>> 2/4. 启动 Nginx 伪装服务器 (localhost:\$PORT_NGINX_LISTEN)..."
"\$APP_ROOT_DIR"/nginx/nginx -c "\$APP_ROOT_DIR"/nginx/nginx.conf &
NGINX_PID=\$!
sleep 2

# 3. 启动 Keepalive (后台运行，通过 nohup 持久化)
echo ">>> 3/4. 启动 Keepalive Node.js 服务..."
cd "\$APP_ROOT_DIR"/idx-keepalive
nohup npm run start 1>idx-keepalive.log 2>&1 &
KEEPALIVE_PID=\$!
cd -
sleep 2

# 4. 启动 Cloudflared Tunnel (主进程，连接到 Nginx 的 \$PORT_NGINX_LISTEN 端口)
echo ">>> 4/4. 启动 Cloudflare Argo Tunnel (主进程)..."
"\$APP_ROOT_DIR"/argo/cloudflared tunnel --url http://localhost:\$PORT_NGINX_LISTEN --token \$ARGO_TOKEN

# 脚本执行到这里意味着 Argo Tunnel 进程已终止
echo "---------------------------------------------------------------"
echo "!!! Cloudflare Argo Tunnel 已终止。正在清理后台进程..."
# 清理所有后台启动的进程
kill \$KEEPALIVE_PID \$NGINX_PID \$XRAY_PID 2>/dev/null
echo "---------------------------------------------------------------"
EOF

chmod +x startup.sh


# =================================================================
# 8. 完成信息
# =================================================================
echo "---------------------------------------------------------------"
echo "✅ 项目安装完成。"
echo "   Nginx 监听本地端口: $PORT_NGINX_LISTEN"
echo "   Xray 监听内部端口: $PORT_XRAY_INTERNAL"
echo "   代理路径 (PATH): $PROXY_PATH"
echo ""
echo "🔥 您的 Xray VLESS 节点 URI (客户端连接信息):"
echo "vless://$UUID@$TUNNEL_DOMAIN:443?encryption=none&security=tls&alpn=http%2F1.1&fp=chrome&type=ws&path=$PROXY_PATH&host=$TUNNEL_DOMAIN#idx-ws-proxy"
echo "---------------------------------------------------------------"
