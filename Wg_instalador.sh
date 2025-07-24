#!/bin/bash

# Configuración
PUERTO=443
DOMINIO=$(curl -s ifconfig.me)  # Puedes reemplazar con IP fija si lo deseas
ARCHIVO="/etc/wireguard/usuarios.txt"

# Colores
GREEN="\\e[32m"; RESET="\\e[0m"

# Pedir cuántos usuarios
read -p "¿Cuántos usuarios quieres generar?: " CANTIDAD

# Crear archivo si no existe
touch "$ARCHIVO"

# Generar usuarios
echo -e "${GREEN}Generando accesos...${RESET}"
for i in $(seq 1 $CANTIDAD); do
  USUARIO="mx$(shuf -i 1000-9999 -n 1)"
  PASS="$(shuf -i 10000-99999 -n 1)"
  LINEA="${DOMINIO}:${PUERTO}@${USUARIO}:${PASS}"
  echo "$LINEA" | tee -a "$ARCHIVO"
done

echo -e "${GREEN}✅ Usuarios guardados en: $ARCHIVO${RESET}"
