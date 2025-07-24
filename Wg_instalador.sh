#!/bin/bash

DOMAIN="hydra.hydramx.mx"
read -p "☁️ Ingresa el Host para Cloudflare (ej. cdn.cloudflare.net): " CF_HOST

UUID=$(uuidgen)
WS_PATH="/$(tr -dc A-Za-z0-9 </dev/urandom | head -c8)"
SNI="www.disneyplus.com"

# Validar si el dominio resuelve
if ! getent hosts "$DOMAIN" > /dev/null; then
  echo "❌ El dominio '$DOMAIN' no resuelve a ninguna IP. Verifica en Cloudflare y espera unos minutos."
  exit 1
fi

# Instalar V2Ray
apt update && apt install -y curl unzip wget
bash <(curl -L -s https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)

# Habilitar puertos si ufw está instalado
if command -v ufw >/dev/null 2>&1; then
  ufw allow 443
  ufw allow 80
  ufw reload
fi

# Configurar V2Ray
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

systemctl restart v2ray

# Guardar archivo con datos de conexión
cat > /root/datos_vless.txt <<EOT
🌐 Dominio: $DOMAIN
🔐 UUID: $UUID
🛣 Path: $WS_PATH
📦 SNI: $SNI
☁️ Host Header: $CF_HOST
🔗 Link VLESS:
vless://$UUID@$DOMAIN:443?encryption=none&security=tls&sni=$SNI&type=ws&host=$CF_HOST&path=$WS_PATH#HYDRA-VLESS
EOT

echo ""
echo "✅ V2Ray instalado con éxito"
echo "📄 Archivo con configuración: /root/datos_vless.txt"
cat /root/datos_vless.txt
