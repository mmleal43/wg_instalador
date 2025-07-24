#!/bin/bash

# ✅ Verificar permisos de root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ejecuta como root"
  exit 1
fi

echo "🔧 Instalando WireGuard + HAProxy para túnel SSL con SNI passthrough..."

# ✅ Actualizar sistema e instalar dependencias
apt update && apt install -y wireguard haproxy qrencode

# ✅ Variables
WG_DIR="/etc/wireguard"
WG_IF="wg0"
WG_PORT=51820
WG_SUBNET="10.10.10"
WG_SERVER_IP="$WG_SUBNET.1"
WG_CLIENT_IP="$WG_SUBNET.2"
HA_BACKEND_PORT=8443

# ✅ Generar claves WireGuard
mkdir -p $WG_DIR
cd $WG_DIR
umask 077
wg genkey | tee server.key | wg pubkey > server.pub
wg genkey | tee client.key | wg pubkey > client.pub

# ✅ Configuración del servidor WireGuard
cat > $WG_DIR/${WG_IF}.conf <<EOF
[Interface]
PrivateKey = $(cat server.key)
Address = ${WG_SERVER_IP}/24
ListenPort = ${WG_PORT}
SaveConfig = true
PostUp = sysctl -w net.ipv4.ip_forward=1; iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = $(cat client.pub)
AllowedIPs = ${WG_CLIENT_IP}/32
EOF

# ✅ Habilitar y levantar el túnel WireGuard
systemctl enable wg-quick@$WG_IF
systemctl start wg-quick@$WG_IF

# ✅ Configurar HAProxy
mv /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.bak

cat > /etc/haproxy/haproxy.cfg <<EOF
global
    log /dev/log local0
    maxconn 2048
    daemon

defaults
    log     global
    mode    tcp
    timeout connect 10s
    timeout client 1m
    timeout server 1m

frontend https_in
    bind *:443
    tcp-request inspect-delay 5s
    tcp-request content accept if { req.ssl_hello_type 1 }

    use_backend dominio1 if { req.ssl_sni -i dominio1.com }
    use_backend dominio2 if { req.ssl_sni -i dominio2.com }
    default_backend default_srv

backend dominio1
    server s1 ${WG_CLIENT_IP}:${HA_BACKEND_PORT} check

backend dominio2
    server s2 ${WG_CLIENT_IP}:${HA_BACKEND_PORT} check

backend default_srv
    server def ${WG_CLIENT_IP}:${HA_BACKEND_PORT} check
EOF

# ✅ Reiniciar HAProxy
systemctl enable haproxy
systemctl restart haproxy

# ✅ Mostrar QR para cliente WireGuard (por si deseas escanear en Android)
qrencode -t ansiutf8 <<EOF
[Interface]
PrivateKey = $(cat client.key)
Address = ${WG_CLIENT_IP}/24
DNS = 1.1.1.1

[Peer]
PublicKey = $(cat server.pub)
Endpoint = $(curl -s ifconfig.me):${WG_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

echo ""
echo "✅ Instalación completada"
echo "📌 WireGuard IP: $WG_SERVER_IP"
echo "📌 Puerto: $WG_PORT"
echo "📌 Puedes redirigir dominios SNI personalizados en /etc/haproxy/haproxy.cfg"
