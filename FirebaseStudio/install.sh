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
echo ">>> 初始化目录..."
mkdir -p "$APP_ROOT_DIR"/{argo,xray,nginx/html,idx-keepalive}


# =================================================================
# 3. Xray 核心安装与配置 (监听 8001)
# =================================================================
echo ">>> 3. 安装 Xray 核心并配置..."
cd "$APP_ROOT_DIR"/xray

# 3.1. 下载并解压 Xray
wget https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
unzip Xray-linux-64.zip
rm -f Xray-linux-64.zip

# 3.2. 下载并配置 config.json
wget -O config.json $REPO_BASE/xray/xray-config.json

# 替换变量：UUID, 内部端口, 代理路径
sed -i 's/$UUID/'$UUID'/g' config.json
sed -i 's/$PORT_XRAY_INTERNAL/'$PORT_XRAY_INTERNAL'/g' config.json
sed -i 's|$PROXY_PATH|'$PROXY_PATH'|g' config.json
cd -


# =================================================================
# 4. Nginx 伪装安装与配置 (监听 8388, 转发到 8001)
# =================================================================
echo ">>> 4. 配置 Nginx 伪装分流..."
cd "$APP_ROOT_DIR"/nginx

# 4.1. 下载 Nginx 二进制文件 (!!! 占位符 - 请替换为实际链接)
# wget -O nginx <实际的 Nginx 二进制链接>
# chmod +x nginx
touch nginx
chmod +x nginx

# 4.2. 下载静态网页
wget -O html/index.html $REPO_BASE/html/index.html

# 4.3. 下载并配置 nginx.conf
wget -O nginx.conf $REPO_BASE/nginx/nginx.conf

# 替换变量：Nginx 监听端口, Xray 内部端口, 代理路径
sed -i 's/$PORT_NGINX_LISTEN/'$PORT_NGINX_LISTEN'/g' nginx.conf
sed -i 's/$PORT_XRAY_INTERNAL/'$PORT_XRAY_INTERNAL'/g' nginx.conf
sed -i 's|$PROXY_PATH|'$PROXY_PATH'|g' nginx.conf
cd -


# =================================================================
# 5. Cloudflared (Argo) 安装与配置
# =================================================================
echo ">>> 5. 安装 Cloudflared..."
cd "$APP_ROOT_DIR"/argo
wget -O cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x cloudflared
# 5.2. 注意：这里不再下载 argo/startup.sh，启动逻辑在根目录的 startup.sh 中实现。
cd -


# =================================================================
# 6. Keepalive (Node.js) 安装与配置
# =================================================================
echo ">>> 6. 配置 Keepalive..."
cd "$APP_ROOT_DIR"/idx-keepalive
# 下载 Keepalive 脚本和依赖文件 (app.js 和 package.json 不需要 sed 替换)
wget -O app.js $REPO_BASE/keepalive/app.js
wget -O package.json $REPO_BASE/keepalive/package.json
# 安装 Node.js 依赖
npm install --no-progress
cd -


# =================================================================
# 7. 创建根目录启动脚本 (startup.sh)
# =================================================================
echo ">>> 7. 创建 startup.sh..."

# 7.1. 下载主启动脚本模板
wget -O startup.sh $REPO_BASE/startup-master-template.sh 

# 7.2. 替换启动脚本中的动态路径和变量
# 使用 # 作为 sed 分隔符
# 注意：所有变量都必须被替换为启动时可用的值
sed -i 's#\$APP_ROOT_DIR#'$APP_ROOT_DIR'#g' startup.sh
sed -i 's/\$PORT_NGINX_LISTEN/'$PORT_NGINX_LISTEN'/g' startup.sh
# 确保 ARGO_TOKEN 变量被正确传入 startup.sh (这里使用 sed 将环境变量名替换成其值)
sed -i 's/\$ARGO_TOKEN/'$ARGO_TOKEN'/g' startup.sh

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
