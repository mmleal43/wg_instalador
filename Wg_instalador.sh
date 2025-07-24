#!/bin/bash

# Verifica permisos root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ejecuta como root"
  exit
fi

echo "🔧 Instalando WireGuard + Stunnel..."

# Instalar dependencias
apt update && apt install -y wireguard stunnel4 qrencode

# Rutas
WG_DIR="/etc/wireguard"
WG_IF="wg0"
WG_PORT=51820
STUNNEL_PORT=443

# Generar claves
mkdir -p $WG_DIR
cd $WG_DIR
umask 077
wg genkey | tee server.key | wg pubkey > server.pub
wg genkey | tee client.key | wg pubkey > client.pub

# IPs internas
SERVER_IP="10.10.10.1"
CLIENT_IP="10.10.10.2"

# Configurar WireGuard (servidor)
cat > $WG_DIR/${WG_IF}.conf <<EOF
[Interface]
PrivateKey = $(cat server.key)
Address = ${SERVER_IP}/24
ListenPort = ${WG_PORT}
SaveConfig = true

[Peer]
PublicKey = $(cat client.pub)
AllowedIPs = ${CLIENT_IP}/32
EOF

# Configuración del cliente (para HTTP Custom)
cat > $WG_DIR/cliente.conf <<EOF
[Interface]
PrivateKey = $(cat client.key)
Address = ${CLIENT_IP}/24
DNS = 1.1.1.1

[Peer]
PublicKey = $(cat server.pub)
Endpoint = $(curl -s ifconfig.me):${STUNNEL_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

# Activar reenvío de IP
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# Agregar NAT
IFACE=$(ip route get 1.1.1.1 | awk '{print $5}')
iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o $IFACE -j MASQUERADE

# Habilitar wg
systemctl enable wg-quick@${WG_IF}
systemctl start wg-quick@${WG_IF}

# Crear certificado SSL autofirmado
mkdir -p /etc/stunnel
openssl req -new -x509 -days 3650 -nodes -subj "/CN=localhost" \
  -out /etc/stunnel/stunnel.pem -keyout /etc/stunnel/stunnel.pem
chmod 600 /etc/stunnel/stunnel.pem

# Crear config STUNNEL
cat > /etc/stunnel/wireguard.conf <<EOF
[wgs]
accept = ${STUNNEL_PORT}
connect = 127.0.0.1:${WG_PORT}
cert = /etc/stunnel/stunnel.pem
key = /etc/stunnel/stunnel.pem
EOF

# Activar STUNNEL
echo "ENABLED=1" > /etc/default/stunnel4
systemctl restart stunnel4
systemctl enable stunnel4

# Abrir puerto 443
ufw allow 443

# Mostrar QR
echo -e "\n📱 Escanea este QR en la app WireGuard o copia en HTTP Custom:"
qrencode -t ansiutf8 < $WG_DIR/cliente.conf

echo -e "\n✅ Instalación completada."
echo "📂 Config cliente: $WG_DIR/cliente.conf"
