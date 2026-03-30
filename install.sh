#!/bin/bash

# Colores para la terminal
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Iniciando Instalación de CARIS Agent...${NC}"

# 1. Verificar ROOT
if [ "$EUID" -ne 0 ]; then 
  echo "Por favor, corre este script como sudo."
  exit 1
fi

# 2. Pedir el Token al usuario
read -p "🔑 Ingresa tu Token de CARIS: " USER_TOKEN

if [ -z "$USER_TOKEN" ]; then
    echo "Error: El token es obligatorio."
    exit 1
fi

# 3. Actualizar sistema e instalar dependencias de red
echo -e "${GREEN}📦 Instalando dependencias de sistema (BIND9, DHCP, Python)...${NC}"
apt-get update
apt-get install -y python3-pip python3-venv isc-dhcp-server bind9 bind9utils ufw

# 4. Configurar Firewall
echo -e "${GREEN}🛡️ Configurando Firewall (Puerto 50052)...${NC}"
ufw allow 50052/tcp

#4.1 Crear entorno virtual
echo -e  "${GREEN}Creando entorno virtual (Python)"
python3 -m venv caris
source caris/bin/activate

# 5. Instalar librerías de Python
echo -e "${GREEN}🐍 Instalando librerías gRPC y Psutil...${NC}"
pip3 install grpcio grpcio-tools psutil --break-system-packages

# 6. Crear el servicio de Systemd para que inicie siempre
echo -e "${GREEN}⚙️ Configurando servicio persistente (systemd)...${NC}"
cat <<EOF > /etc/systemd/system/caris-agent.service
[Unit]
Description=CARIS Network Orchestrator Agent
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$(pwd)
ExecStart=/usr/bin/python3 $(pwd)/agent.py --token $USER_TOKEN
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 7. Recargar y activar
systemctl daemon-reload
systemctl enable caris-agent
systemctl start caris-agent

echo -e "${GREEN}✅ ¡INSTALACIÓN COMPLETADA!${NC}"
echo "El agente está corriendo en segundo plano y escuchando órdenes."
