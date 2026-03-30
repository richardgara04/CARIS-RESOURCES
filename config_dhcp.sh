#!/bin/bash
#CARIS 26 DE MARZO
# PRIVILEGIOS DE ROOT
if [ "$EUID" -ne 0 ]; then
  echo "Error: Este script debe ejecutarse como root"
  exit 1
fi

TARGET_NETWORK=$1
TARGET_MASK=$2
GATEWAY=$3
IP_START=$4
IP_END=$5
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
IP_CIDR=$(ip -o -f inet addr show "$INTERFACE" | awk '{print $4}')
#CALCULAR LA RED Y MÁSCARA DEL SERVIDOR
NET_INFO=$(python3 -c "import ipaddress; net=ipaddress.IPv4Interface('$IP_CIDR').network; print(f'{net.network_address} {net.netmask}')")
SERVER_NETWORK=$(echo "$NET_INFO" | awk '{print $1}')
SERVER_NETMASK=$(echo "$NET_INFO" | awk '{print $2}')
echo "🛠️ [CARIS] Interfaz: $INTERFACE | Red Local: $SERVER_NETWORK | Máscara Local: $SERVER_NETMASK"
#CONFIGURAR INTERFAZ DE ESCUCHA EN EL SERVICIO
sed -i "s/INTERFACESv4=\".*\"/INTERFACESv4=\"$INTERFACE\"/" /etc/default/isc-dhcp-server
#GENERAR ARCHIVO DHCPD.CONF LIMPIO
cat <<EOF > /etc/dhcp/dhcpd.conf
# --- CARIS GLOBAL CONFIG ---
option domain-name "caris.local";
option domain-name-servers 8.8.8.8, 8.8.4.4;
default-lease-time 600;
max-lease-time 7200;
log-facility local7;
EOF

#INYECTAR LOS BLOQUES SUBNET
if [ "$SERVER_NETWORK" == "$TARGET_NETWORK" ]; then
  #ESCENARIO A: La IA pidió crear el pool en la misma red local del servidor
  cat <<EOF >> /etc/dhcp/dhcpd.conf

# --- POOL SOLICITADO (En la red local del servidor) ---
subnet $TARGET_NETWORK netmask $TARGET_MASK {
  range $IP_START $IP_END;
  option routers $GATEWAY;
  option subnet-mask $TARGET_MASK;
  option broadcast-address ${TARGET_NETWORK%.*}.255;
}
EOF

else
  #ESCENARIO B: La IA pidió crear el pool para una red distint
  cat <<EOF >> /etc/dhcp/dhcpd.conf

# --- 1. SUBRED DEL SERVIDOR (Pool vacío obligatorio) ---
subnet $SERVER_NETWORK netmask $SERVER_NETMASK {
}

# --- 2. POOL SOLICITADO POR EL ORQUESTADOR ---
subnet $TARGET_NETWORK netmask $TARGET_MASK {
  range $IP_START $IP_END;
  option routers $GATEWAY;
  option subnet-mask $TARGET_MASK;
  option broadcast-address ${TARGET_NETWORK%.*}.255;
}
EOF
fi

#REINICIAR Y VALIDAR
echo "🔄 [CARIS] Reiniciando isc-dhcp-server..."
systemctl restart isc-dhcp-server

if systemctl is-active --quiet isc-dhcp-server; then
  echo "✅ [CARIS] DHCP desplegado con éxito en la interfaz $INTERFACE."
  exit 0
else
  #Si falla veremos el error real del sistema para que viaje hasta el frontend
  ERROR_LOG=$(journalctl -u isc-dhcp-server -n 5 --no-pager | grep dhcpd | tail -n 1)
  echo "❌ Error del servicio: $ERROR_LOG"
  exit 1
fi
