#!/usr/bin/env sh

ARGO_TOKEN="${ARGO_TOKEN:-}"

# 1. init directory
mkdir -p app/argo
cd app/argo

# 2. download cloudflared
if [ ! -f cloudflared ]; then
  wget -O cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
  chmod +x cloudflared
fi

# 3. create startup.sh
wget -O startup.sh https://raw.githubusercontent.com/justlagom/fsne-Kalive/refs/heads/main/FirebaseStudio/argo/startup.sh
sed -i 's#$PWD#'$PWD'#g' startup.sh
if [ -n "$ARGO_TOKEN" ]; then
  sed -i "s/ARGO_TOKEN=/ARGO_TOKEN=$ARGO_TOKEN/g" startup.sh
fi
chmod +x startup.sh

# 4. return main directory
cd -
