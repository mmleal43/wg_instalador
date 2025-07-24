#!/bin/bash
# WG HYDRA - Instalador completo con gestiÃ³n de usuarios y redirecciÃ³n SSL para HTTP Custom

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

# Mostrar banner
clear
echo -e "${RED}"
echo "â–ˆâ–ˆâ•—    â–ˆâ–ˆâ•—â–ˆâ–ˆâ•— â–ˆâ–ˆâ–ˆâ–ˆâ–ˆâ–ˆâ•— â–ˆâ–ˆâ–ˆâ–ˆâ–ˆâ–ˆâ•— â–ˆâ–ˆâ–ˆâ–ˆâ–ˆâ–ˆâ•— "
echo "â–ˆâ–ˆâ•‘    â–ˆâ–ˆâ•‘â–ˆâ–ˆâ•‘â–ˆâ–ˆâ•”â•â•â•â•â• â–ˆâ–ˆâ•”â•â•â–ˆâ–ˆâ•—â–ˆâ–ˆâ•”â•â•â–ˆâ–ˆâ•—"
echo "â–ˆâ–ˆâ•‘ â–ˆâ•— â–ˆâ–ˆâ•‘â–ˆâ–ˆâ•‘â–ˆâ–ˆâ•‘  â–ˆâ–ˆâ–ˆâ•—â–ˆâ–ˆâ–ˆâ–ˆâ–ˆâ–ˆâ•”â•â–ˆâ–ˆâ–ˆâ–ˆâ–ˆâ–ˆâ–ˆâ•‘"
echo "â–ˆâ–ˆâ•‘â–ˆâ–ˆâ–ˆâ•—â–ˆâ–ˆâ•‘â–ˆâ–ˆâ•‘â–ˆâ–ˆâ•‘   â–ˆâ–ˆâ•‘â–ˆâ–ˆâ•”â•â•â•â• â–ˆâ–ˆâ•”â•â•â–ˆâ–ˆâ•‘"
echo "â•šâ–ˆâ–ˆâ–ˆâ•”â–ˆâ–ˆâ–ˆâ•”â•â–ˆâ–ˆâ•‘â•šâ–ˆâ–ˆâ–ˆâ–ˆâ–ˆâ–ˆâ•”â•â–ˆâ–ˆâ•‘     â–ˆâ–ˆâ•‘  â–ˆâ–ˆâ•‘"
echo " â•šâ•â•â•â•šâ•â•â• â•šâ•â• â•šâ•â•â•â•â•â• â•šâ•â•     â•šâ•â•  â•šâ•â•"
echo -e "${RESET}"
echo -e "${YELLOW}ðŸ”§ HYDRA: WireGuard + SNI + SSH Redirect para HTTP Custom${RESET}"
echo ""

# FunciÃ³n para instalar y configurar WireGuard + HAProxy
instalar_todo() {
  echo -e "${BLUE}âž¡ Instalando dependencias...${RESET}"
  apt update && apt install -y wireguard haproxy qrencode curl net-tools libpam0g-dev

  echo -e "${BLUE}âž¡ Configurando claves y red...${RESET}"
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

  echo -e "${BLUE}âž¡ Configurando HAProxy con SNI passthrough...${RESET}"
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

# FunciÃ³n para crear usuarios SSH
crear_usuario_ssh() {
  read -p "Â¿CuÃ¡ntos usuarios deseas generar?: " CANT
  read -p "Â¿CuÃ¡ntos dÃ­as de vigencia?: " DIAS
  read -p "Â¿CuÃ¡ntas conexiones simultÃ¡neas (por usuario)?: " MAX_CONN

  touch $USERS_FILE
  for i in $(seq 1 $CANT); do
    USER="mx$(shuf -i 1000-9999 -n 1)"
    PASS="$(shuf -i 10000-99999 -n 1)"
    EXPIRA=$(date -d "+$DIAS days" +%Y-%m-%d)

    # Crear usuario con expiraciÃ³n
    useradd -e "$EXPIRA" -M -s /bin/false "$USER"
    echo "$USER:$PASS" | chpasswd

    # Limitar sesiones (por PAM si es requerido)
    echo "$USER hard maxlogins $MAX_CONN" >> /etc/security/limits.conf

    # Registrar
    echo "${PUB_IP}:443@${USER}:${PASS} (expira: ${EXPIRA}, conexiones: ${MAX_CONN})" | tee -a "$USERS_FILE"
  done
  echo -e "${GREEN}âœ… Usuarios creados. Archivo: $USERS_FILE${RESET}"
}

# MenÃº principal
echo "1) Instalar WireGuard + HAProxy + RedirecciÃ³n"
echo "2) Crear usuarios SSH con vigencia y lÃ­mite"
echo "3) Ver accesos generados"
echo "4) Salir"
read -p "Selecciona una opciÃ³n: " OPC

case $OPC in
  1) instalar_todo ;;
  2) crear_usuario_ssh ;;
  3) cat $USERS_FILE ;;
  *) exit 0 ;;
esac
