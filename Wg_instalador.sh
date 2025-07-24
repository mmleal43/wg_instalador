#!/bin/bash
# WG HYDRA - Instalador completo con gestión de usuarios y redirección SSL para HTTP Custom

RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; RESET="\e[0m"
WG_DIR="/etc/wireguard"
WG_IF="wg0"
WG_PORT=51820
WG_SUBNET="10.10.10"
WG_SERVER_IP="$WG_SUBNET.1"
WG_CLIENT_IP="$WG_SUBNET.2"
HA_BACKEND_PORT=8443
PUB_IP=$(curl -s ifconfig.me)
ETH_IF=$(ip route get 1.1.1.1 | grep -oP 'dev \K[^ ]+')
USERS_FILE="/etc/wireguard/usuarios.txt"

clear
echo -e "${RED}"
echo "██╗    ██╗██╗ ██████╗ ██████╗ ██████╗ "
echo "██║    ██║██║██╔════╝ ██╔══██╗██╔══██╗"
echo "██║ █╗ ██║██║██║  ███╗██████╔╝███████║"
echo "██║███╗██║██║██║   ██║██╔═══╝ ██╔══██║"
echo "╚███╔███╔╝██║╚██████╔╝██║     ██║  ██║"
echo " ╚══╝╚══╝ ╚═╝ ╚═════╝ ╚═╝     ╚═╝  ╚═╝"
echo -e "${RESET}"
echo -e "${YELLOW}🔧 HYDRA: WireGuard + SNI + SSH Redirect para HTTP Custom${RESET}"
echo ""

instalar_todo() {
  echo -e "${BLUE}➡ Instalando dependencias...${RESET}"
  apt update && apt install -y wireguard haproxy qrencode curl net-tools libpam0g-dev

  echo -e "${BLUE}➡ Configurando claves y red...${RESET}"
  mkdir -p $WG_DIR
  cd $WG_DIR
  umask 077
  wg genkey | tee server.key | wg pubkey > server.pub
  wg genkey | tee client.key | wg pubkey > client.pub

  cat > $WG_DIR/${WG_IF}.conf <<EOF
[Interface]
PrivateKey = $(cat server.key)
Address = ${WG_SERVER_IP}/24
ListenPort = ${WG_PORT}
SaveConfig = true
PostUp = sysctl -w net.ipv4.ip_forward=1; iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${ETH_IF} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${ETH_IF} -j MASQUERADE

[Peer]
PublicKey = $(cat client.pub)
AllowedIPs = ${WG_CLIENT_IP}/32
EOF

  systemctl enable wg-quick@${WG_IF}
  systemctl start wg-quick@${WG_IF}

  echo -e "${BLUE}➡ Configurando HAProxy con SNI passthrough...${RESET}"
  mv /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.bak 2>/dev/null

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

    use_backend stream_bypass if { req.ssl_sni -i disneyplus.com }
    default_backend ssh_via_wg

backend stream_bypass
    server bypass_srv ${WG_CLIENT_IP}:8443 check

backend ssh_via_wg
    server ssh_srv 127.0.0.1:22 check
EOF

  systemctl enable haproxy
  systemctl restart haproxy
}

crear_usuario_ssh() {
  read -p "¿Cuántos usuarios deseas generar?: " CANT
  read -p "¿Cuántos días de vigencia?: " DIAS
  read -p "¿Cuántas conexiones simultáneas (por usuario)?: " MAX_CONN

  touch $USERS_FILE
  for i in $(seq 1 $CANT); do
    USER="mx$(shuf -i 1000-9999 -n 1)"
    PASS="$(shuf -i 10000-99999 -n 1)"
    EXPIRA=$(date -d "+$DIAS days" +%Y-%m-%d)

    useradd -e "$EXPIRA" -M -s /bin/false "$USER"
    echo "$USER:$PASS" | chpasswd

    echo "$USER hard maxlogins $MAX_CONN" >> /etc/security/limits.conf

    echo "${PUB_IP}:443@${USER}:${PASS} (expira: ${EXPIRA}, conexiones: ${MAX_CONN})" | tee -a "$USERS_FILE"
  done
  echo -e "${GREEN}✅ Usuarios creados. Archivo: $USERS_FILE${RESET}"
}

echo "1) Instalar WireGuard + HAProxy + Redirección"
echo "2) Crear usuarios SSH con vigencia y límite"
echo "3) Ver accesos generados"
echo "4) Salir"
read -p "Selecciona una opción: " OPC

case $OPC in
  1) instalar_todo ;;
  2) crear_usuario_ssh ;;
  3) cat $USERS_FILE ;;
  *) exit 0 ;;
esac
