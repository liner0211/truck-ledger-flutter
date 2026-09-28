#!/usr/bin/env bash
# 宝塔/生产机：安装 Node（若缺失）→ npm 依赖 → 写入 Nginx /ws → 启动/托管 WebSocket。
# 用法：在站点根执行  bash ws/setup_baota_ws.sh
# 也可由 scripts/deploy_server_php.sh 远程调用。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE_NAME="${WS_SITE_NAME:-truck.liner0211.online}"
WS_PORT="${WS_PORT:-8765}"
NGINX_VHOST="${WS_NGINX_VHOST:-/www/server/panel/vhost/nginx/${SITE_NAME}.conf}"

log() { echo "==> $*"; }
warn() { echo "WARN: $*" >&2; }

ensure_node() {
  if command -v node >/dev/null 2>&1; then
    log "已有 node: $(command -v node) ($(node -v))"
    return 0
  fi
  local cand
  for cand in /www/server/nodejs/v*/bin/node /www/server/nodejs/node/bin/node; do
    if [[ -x "$cand" ]]; then
      export PATH="$(dirname "$cand"):$PATH"
      log "使用宝塔 Node: $cand ($(node -v))"
      return 0
    fi
  done

  log "安装 Node.js 20（官方二进制）…"
  local ver="v20.18.1"
  local arch
  arch="$(uname -m)"
  local node_arch="x64"
  case "$arch" in
    aarch64|arm64) node_arch="arm64" ;;
    x86_64|amd64) node_arch="x64" ;;
    *) warn "未知架构 $arch，尝试 x64" ;;
  esac
  local tmp="/tmp/node-${ver}-linux-${node_arch}.tar.xz"
  local url="https://nodejs.org/dist/${ver}/node-${ver}-linux-${node_arch}.tar.xz"
  if ! curl -fsSL --max-time 120 "$url" -o "$tmp"; then
    warn "官方源失败，尝试 npmmirror…"
    url="https://npmmirror.com/mirrors/node/${ver}/node-${ver}-linux-${node_arch}.tar.xz"
    curl -fsSL --max-time 120 "$url" -o "$tmp"
  fi
  mkdir -p /usr/local/lib/nodejs
  tar -xJf "$tmp" -C /usr/local/lib/nodejs
  ln -sfn "/usr/local/lib/nodejs/node-${ver}-linux-${node_arch}" /usr/local/lib/nodejs/current
  ln -sfn /usr/local/lib/nodejs/current/bin/node /usr/local/bin/node
  ln -sfn /usr/local/lib/nodejs/current/bin/npm /usr/local/bin/npm
  ln -sfn /usr/local/lib/nodejs/current/bin/npx /usr/local/bin/npx
  hash -r || true
  command -v node >/dev/null
  log "Node 已安装: $(node -v)"
}

ensure_nginx_ws() {
  if [[ ! -f "$NGINX_VHOST" ]]; then
    warn "未找到 Nginx 站点配置: $NGINX_VHOST（请手动加入 location /ws）"
    return 0
  fi
  if grep -qE 'location\s+\^~\s+/ws' "$NGINX_VHOST"; then
    log "Nginx 已有 /ws 反代"
    return 0
  fi
  log "向 Nginx 注入 /ws 反代…"
  local snippet
  snippet=$(cat <<SNIP

    # ★ WebSocket（truck-ledger ws/server.js）自动注入
    location ^~ /ws {
        proxy_pass http://127.0.0.1:${WS_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

SNIP
)
  if grep -q 'location ' "$NGINX_VHOST"; then
    local tmpf
    tmpf="$(mktemp)"
    awk -v snip="$snippet" '
      !done && $0 ~ /location[[:space:]]/ {
        print snip
        done=1
      }
      { print }
    ' "$NGINX_VHOST" >"$tmpf"
    cp -a "$NGINX_VHOST" "${NGINX_VHOST}.bak.ws.$(date +%s)"
    mv "$tmpf" "$NGINX_VHOST"
  else
    warn "无法自动插入 location，请手动编辑 $NGINX_VHOST"
    return 0
  fi
  if command -v nginx >/dev/null 2>&1; then
    nginx -t && (nginx -s reload || systemctl reload nginx || true)
    log "Nginx 已重载"
  elif [[ -x /www/server/nginx/sbin/nginx ]]; then
    /www/server/nginx/sbin/nginx -t && /www/server/nginx/sbin/nginx -s reload
    log "宝塔 Nginx 已重载"
  else
    warn "请在宝塔面板重载 Nginx"
  fi
}

install_systemd() {
  local unit=/etc/systemd/system/truck-ledger-ws.service
  cat >"$unit" <<UNIT
[Unit]
Description=Truck Ledger WebSocket Hub
After=network.target

[Service]
Type=simple
WorkingDirectory=${ROOT}/ws
ExecStart=/bin/bash ${ROOT}/ws/run_ws_fg.sh
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload 2>/dev/null || return 1
  systemctl enable truck-ledger-ws 2>/dev/null || true
  systemctl restart truck-ledger-ws 2>/dev/null || return 1
  if systemctl is-active --quiet truck-ledger-ws 2>/dev/null; then
    log "systemd 服务 truck-ledger-ws 已运行"
    return 0
  fi
  return 1
}

cd "$ROOT"
ensure_node
chmod +x "$ROOT/ws/"*.sh 2>/dev/null || true
bash "$ROOT/ws/export_env.sh"
# 读端口（export 后）
# shellcheck disable=SC1091
set -a
source "$ROOT/data/ws.env"
set +a
WS_PORT="${WS_PORT:-8765}"
ensure_nginx_ws

cd "$ROOT/ws"
if [[ ! -d node_modules/ws ]]; then
  log "npm install…"
  npm install --omit=dev
fi

if install_systemd; then
  sleep 0.5
  curl -fsS "http://127.0.0.1:${WS_PORT}/health" && echo
  log "完成（systemd）"
  exit 0
fi

log "systemd 不可用，回退 nohup start_ws.sh"
bash "$ROOT/ws/start_ws.sh"
log "完成（nohup）"
