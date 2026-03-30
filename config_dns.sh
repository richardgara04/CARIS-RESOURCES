#!/bin/bash
#CARIS 26 DE MARZO DD 2026
# Privilegios de root
if [ "$EUID" -ne 0 ]; then
  echo "Error: Este script debe ejecutarse como root"
  exit 1
fi

HOST=$1
ZONE=$2
IP=$3
TTL=$4

# Rutas estándar de BIND9 en Debian/Ubuntu/Mint
OPTIONS_FILE="/etc/bind/named.conf.options"
LOCAL_FILE="/etc/bind/named.conf.local"
ZONE_FILE="/etc/bind/db.$ZONE"

#DETECTAR IP DEL SERVIDOR PARA EL REGISTRO 'NS'
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
SERVER_IP=$(ip -o -f inet addr show "$INTERFACE" | awk '{print $4}' | cut -d/ -f1)

echo "🛠️ [CARIS] Configurando DNS: $HOST.$ZONE -> $IP (Servidor NS: $SERVER_IP)"

#CONFIGURAR OPCIONES GLOBALES (/etc/bind/named.conf.options)
#Esto asegura que el DNS resuelva dominios externos y acepte peticiones de la red local
cat <<EOF > "$OPTIONS_FILE"
acl "trusted" {
    127.0.0.0/8;
    192.168.0.0/16;
    10.0.0.0/8;
    any; # Permitir todo temporalmente para evitar bloqueos en la red de pruebas
};

options {
    directory "/var/cache/bind";
    recursion yes;
    allow-query { trusted; };
    forwarders {
        8.8.8.8;
        8.8.4.4;
    };
    forward only;
    dnssec-validation auto;
    listen-on-v6 { any; };
};
EOF

#DECLARAR LA ZONA LOCAL (/etc/bind/named.conf.local)
# Si la zona no está declarada en el archivo, la agregamos
if ! grep -q "zone \"$ZONE\"" "$LOCAL_FILE"; then
    echo "⚙️ [CARIS] Registrando nueva zona $ZONE en $LOCAL_FILE..."
    cat <<EOF >> "$LOCAL_FILE"

zone "$ZONE" {
    type master;
    file "$ZONE_FILE";
};
EOF
fi

#CREAR O ACTUALIZAR EL ARCHIVO DE ZONA DIRECTA
#El Serial debe cambiar cada vez que se edita el archivo. Usamos el timestamp de Unix.
SERIAL=$(date +%s) 

if [ ! -f "$ZONE_FILE" ]; then
    echo "⚙️ [CARIS] Creando archivo de zona maestra $ZONE_FILE..."
    cat <<EOF > "$ZONE_FILE"
\$TTL    $TTL
@       IN      SOA     ns1.$ZONE. admin.$ZONE. (
                         $SERIAL        ; Serial automático
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns1.$ZONE.
ns1     IN      A       $SERVER_IP
EOF
else
    echo "⚙️ [CARIS] Actualizando zona existente $ZONE_FILE..."
    # Actualizamos el Serial de la zona existente usando sed
    sed -i -E "s/[0-9]+(\s+;\s*Serial automático)/$SERIAL\1/i" "$ZONE_FILE"
fi

#INYECTAR EL REGISTRO A SOLICITADO
#Borramos el registro si ya existía antes 
sed -i "/^$HOST\s/d" "$ZONE_FILE"

#Agregamos el nuevo host apuntando a la IP indicada
echo "$HOST    IN    A    $IP" >> "$ZONE_FILE"

#VALIDACIÓN SINTÁCTICA DE BIND9
echo "🔍 [CARIS] Verificando sintaxis de BIND9..."
if ! named-checkconf; then
    echo "❌ Error de sintaxis en named.conf"
    exit 1
fi

if ! named-checkzone "$ZONE" "$ZONE_FILE"; then
    echo "❌ Error de sintaxis en el archivo de zona $ZONE_FILE"
    exit 1
fi

#REINICIAR Y APLICAR CAMBIOS
echo "🔄 [CARIS] Reiniciando servicio bind9..."
systemctl restart bind9

if systemctl is-active --quiet bind9; then
  echo "✅ [CARIS] Registro DNS desplegado. $HOST.$ZONE apunta a $IP."
  exit 0
else
  ERROR_LOG=$(journalctl -u bind9 -n 5 --no-pager | grep named | tail -n 1)
  echo "❌ Error del servicio DNS: $ERROR_LOG"
  exit 1
fi
