#!/bin/bash

# === Solicitar datos al usuario ===
read -p "🌐 Ingresa tu dominio con SSL (ej. mi.dominio.com): " DOMAIN
read -p "☁️ Ingresa el Host para Cloudflare (ej. cdn.cloudflare.net): " CF_HOST

UUID=$(uuidgen)
WS_PATH="/$(tr -dc A-Za-z0-9 </dev/urandom | head -c8)"
SNI="www.disneyplus.com"

# === Instalar V2Ray ===
apt update && apt install -y curl unzip wget
bash <(curl -L -s https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)

# === Configurar V2Ray ===
cat > /usr/local/etc/v2ray/config.json <<EOF
{
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 1080,
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true,
        "userLevel": 8
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      },
      "tag": "socks"
    },
    {
      "listen": "127.0.0.1",
      "port": 8080,
      "protocol": "http",
      "settings": {
        "userLevel": 8
      },
      "tag": "http"
    }
  ],
  "log": {
    "loglevel": "none"
  },
  "outbounds": [
    {
      "mux": {
        "enabled": true
      },
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$DOMAIN",
            "port": 443,
            "users": [
              {
                "id": "$UUID",
                "encryption": "none",
                "level": 8
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "allowInsecure": true,
          "serverName": "$SNI"
        },
        "wsSettings": {
          "path": "$WS_PATH",
          "headers": {
            "Host": "$CF_HOST"
          }
        }
      },
      "tag": "cf_vless"
    }
  ],
  "policy": {
    "levels": {
      "8": {
        "connIdle": 300,
        "downlinkOnly": 1,
        "handshake": 4,
        "uplinkOnly": 1
      }
    }
  }
}
EOF

# === Reiniciar V2Ray ===
systemctl restart v2ray

# === Mostrar datos ===
echo ""
echo "✅ V2Ray instalado con éxito"
echo "🌐 Dominio: $DOMAIN"
echo "🔐 UUID: $UUID"
echo "🛣 Path: $WS_PATH"
echo "📦 SNI: $SNI"
echo "☁️ Host Header: $CF_HOST"
