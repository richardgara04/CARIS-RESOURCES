#!/bin/bash
#CARIS 30 DE MARZO DE 2026
REDBOLD='\033[1;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e   "${BLUE}               .                                                                                                                                                                  
                    .........                                                                                                                                                       
                        ................................                                                                                                                            
                                     ...........................                                                                                                                    
                          .......                    .............                                                                                                                  
                           .          .........             . ...                                                                                                                   
                              ..................     .....         .......                                                                                                          
                         .........................                .   ......                                                                                                        
                      ...        ................. ..          ...............                                                                                                      
                   .       .........                       ...................                                                                                                      
                      .........       ...      ..       ....               ...                                                                                                      
                  ........       .....     ...        .                     ..                                                                                                      
                  .....      ......    .....      .                                 %-%@@%             %@@@@@@@@@@@@@@@@@@@#        %%@@%       %%%@@@@@@@@@@@@@@@@%%               
                  ..     .......    ......      ..                                 %%%%@@%%            %@@@%%%%%%%%%%%%%%@@@@*      %@@@@     -@@@%%%%%%%@@%%%%%%%%%                
                      ........    ......   .   ...    .                           %@@* %%@@%           %@@@%             %%@@%+     %@@@%     %@@@@                                 
                    ........    ......   ..   ....   ...                         %%%%   %@%%#          %@@@%              %@@@@     @@@@@     %@@@%=                                
                  ........    .......   ..    ....   ...                        #%@%     %%@%%         %@@@%             %%@@%.     @%@@%      %%@@@%%%@%%%.                        
                   ......   ........   ...   .....   ....                      #%@@.     *@@%%*        %@@@@%@%@%@@@@%@%%@@@@.      @%@@%        %@@@@@@@@@@@%%%%%%                 
                    ...    ........   ....   .....   .....                    +%@%#       @@@@%#       %@@@@@@@@@@@@@@@@@%%         @%@@%               :%@@@@@@@@@%%               
                    ..    ........   .....   ......   .....                  :%%%%%%%@%@@@@@@@%%#      %@@@%       %%@@%%           @%@@@                       %@@@@#              
                        .........    .....   ......    ......               :%@%%%%@@@@%@%%@%%@@%*     %@@@%        .%%%@%%         %@@@@                       .@@@@%              
                         .......    ......   .......    .......            .@@@%:            %@@@@#    %@@@@          %%@@@%.       %%@@%      %%%%%@%@%@%@@%%@@@@@%%               
                            ....   .......    .......    ........          %@@%%              %%@@%+   %@@@@            %@@@@%      %@@@%     %@@@@@@@@@@@@@@@@@@%%#                
                                   ........   .........    ........                                                      ....       :..                                             
                                        ....     .......       . .....
${NC}"

# 1. VERIFICAR ROOT
if [ "$EUID" -ne 0 ]; then 
  echo -e "${REDBOLD}❌ Error: Por favor, ejecuta este script con sudo.${NC}"
  exit 1
fi

# 2. PREPARAR DIRECTORIO
INSTALL_DIR="/opt/caris-agent"
echo -e "${GREEN}📂 Creando directorio de instalación en $INSTALL_DIR...${NC}"
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# 3. DESCARGAR COMPONENTES (Asumiendo que están en la misma carpeta que el install.sh en GitHub)
REPO_URL="https://raw.githubusercontent.com/richardgara04/CARIS-RESOURCES/main"
wget -q $REPO_URL/agent.py -O agent.py
wget -q $REPO_URL/telemetry.proto -O telemetry.proto
wget -q $REPO_URL/config_dhcp.sh -O config_dhcp.sh
wget -q $REPO_URL/config_dns.sh -O config_dns.sh

# 4. SOLICITAR TOKEN
echo -e "${BLUE}🔑 Configuración de Identidad${NC}"
read -p "Ingresa tu Token de CARIS: " USER_TOKEN </dev/tty
if [ -z "$USER_TOKEN" ]; then
    echo -e "${REDBOLD}❌ Error: El token es obligatorio para la telemetría.${NC}"
    exit 1
fi
# CREAR ENTORNO PYTHON
python3 -m venv caris-agent
source caris-agent/bin/activate

# 5. INSTALAR DEPENDENCIAS DE SISTEMA
echo -e "${GREEN}📦 Instalando paquetes de red (BIND9, DHCP, Python)...${NC}"
apt-get update -y
apt-get install -y python3-pip python3-venv isc-dhcp-server bind9 bind9utils ufw wget

# 6. COMPILAR CONTRATO GRPC (Cero archivos basura en el repo)
echo -e "${GREEN}🐍 Configurando entorno de Python y compilar Proto...${NC}"
pip3 install grpcio grpcio-tools psutil --break-system-packages --quiet

if [ -f "telemetry.proto" ]; then
    python3 -m grpc_tools.protoc -I. --python_out=. --grpc_python_out=. telemetry.proto
    echo -e "${GREEN}✅ Contrato gRPC compilado localmente.${NC}"
else
    echo -e "${REDBOLD}⚠️ Advertencia: No se encontró telemetry.proto en la carpeta actual.${NC}"
fi

# 7. PERMISOS DE EJECUCIÓN PARA SCRIPTS BASH
echo -e "${GREEN}🔐 Ajustando permisos de seguridad...${NC}"
chmod +x config_dhcp.sh config_dns.sh
chmod 644 telemetry.proto

# 8. CREAR SERVICIO SYSTEMD (Ruta fija en /opt)
echo -e "${GREEN}⚙️ Creando servicio persistente caris-agent.service...${NC}"
cat <<EOF > /etc/systemd/system/caris-agent.service
[Unit]
Description=CARIS Network Orchestrator Agent
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $INSTALL_DIR/agent.py --token $USER_TOKEN
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 9. ACTIVAR SERVICIO Y FIREWALL
echo -e "${GREEN}🚀 Arrancando motores...${NC}"
systemctl daemon-reload
systemctl enable caris-agent
systemctl restart caris-agent
ufw allow 50052/tcp

echo -e "${BLUE}==========================================${NC}"
echo -e "${GREEN}✅ ¡CARIS AGENT INSTALADO Y ACTIVO!${NC}"
echo -e "Estado: $(systemctl is-active caris-agent)"
echo -e "Ruta: $INSTALL_DIR"
echo -e "${BLUE}==========================================${NC}"
