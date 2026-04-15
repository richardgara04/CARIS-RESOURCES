import time
import psutil
import grpc
import uuid
import argparse
import socket
import json
from datetime import datetime
from concurrent import futures
import threading
import subprocess
import telemetry_pb2
import telemetry_pb2_grpc


class CommandServiceServicer(telemetry_pb2_grpc.CommandServiceServicer):
    def ExecuteConfig(self, request, context):
        print(f"\n🔔 [NUEVA ORDEN RECIBIDA DE KOTLIN]")
        print(f"🎯 Acción: {request.action_type}")
        print(f"📦 JSON Técnico: {request.command_json}")
        try:
            command_data = json.loads(request.command_json)
            if request.action_type == "create_dhcp":
                network = command_data.get("network")
                mask = command_data.get("mask")
                gateway = command_data.get("gateway")
                ip_start = command_data.get("ip_start")
                ip_end = command_data.get("ip_end")
                
                print(f"🛠️ Ejecutando configuración REAL de DHCP para la red {network}...")
                try:
                    resultado = subprocess.run(
                        ['sudo', './config_dhcp.sh', network, mask, gateway, ip_start, ip_end],
                        capture_output=True, text=True, check=True
                    )
                    
                    msg = resultado.stdout.strip()
                    print(f"✅ Éxito en Linux: {msg}")
                    return telemetry_pb2.ConfigResponse(success=True, message=msg, error_details="")
                except subprocess.CalledProcessError as sub_e:
                    error_msg = sub_e.stderr.strip() if sub_e.stderr else sub_e.stdout.strip()
                    print(f"❌ Error en Linux: {error_msg}")
                    return telemetry_pb2.ConfigResponse(success=False, message="", error_details=error_msg)
            elif request.action_type == "create_dns":
                host = command_data.get("host")
                zone = command_data.get("zone")
                ip = command_data.get("ip")
                ttl = str(command_data.get("ttl", 86400)) 
                
                print(f"🛠️ Ejecutando configuración REAL de DNS para {host}.{zone} -> {ip}...")
                
                try:
                    resultado = subprocess.run(
                        ['sudo', './config_dns.sh', host, zone, ip, ttl],
                        capture_output=True, text=True, check=True
                    )
                    
                    msg = resultado.stdout.strip()
                    print(f"✅ Éxito en Linux: {msg}")
                    return telemetry_pb2.ConfigResponse(success=True, message=msg, error_details="")
                    
                except subprocess.CalledProcessError as sub_e:
                    error_msg = sub_e.stderr.strip() if sub_e.stderr else sub_e.stdout.strip()
                    print(f"❌ Error en Linux: {error_msg}")
                    return telemetry_pb2.ConfigResponse(success=False, message="", error_details=error_msg)




        except Exception as e:
            print(f"💥 Error al ejecutar la orden: {e}")
            return telemetry_pb2.ConfigResponse(success=False, message="", error_details=str(e))
def serve_commands():
    try:
        server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
        telemetry_pb2_grpc.add_CommandServiceServicer_to_server(CommandServiceServicer(), server)
        server.add_insecure_port('[::]:50052') 
        server.start()
        print("🎧 Agente de Comandos ESCUCHANDO en el puerto 50052...")
        server.wait_for_termination()
    except Exception as e:
        print(f"\n💀 FATAL: El servidor de comandos (Oído) colapsó al iniciar: {e}")
        
        
        
        
def get_mac_address():
    mac = uuid.UUID(int=uuid.getnode()).hex[-12:]
    return "-".join([mac[e:e+2] for e in range(0, 11, 2)]).upper()

def get_internal_ip():
    """Descubre la IP interna real abriendo un socket temporal."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

def get_temperature():
    """Lee el sensor térmico principal de la máquina (si está disponible)."""
    try:
        temps = psutil.sensors_temperatures()
        if not temps: return 0.0
        for name, entries in temps.items():
            if entries: return round(entries[0].current, 2)
        return 0.0
    except Exception:
        return 0.0

def get_processes_info():
    """Obtiene el total de procesos y el Top 5 en formato JSON."""
    processes = []
    now = time.time()
    
    for proc in psutil.process_iter(['name', 'create_time', 'cpu_percent']):
        try:
            info = proc.info
            uptime_hours = round((now - info['create_time']) / 3600, 1) if info['create_time'] else 0
            processes.append({
                'name': info['name'],
                'uptime': uptime_hours,
                'cpu': info['cpu_percent'] or 0
            })
        except Exception:
            pass
            
    total_active = len(processes)
    top_5 = sorted(processes, key=lambda p: p['cpu'], reverse=True)[:5]
    return total_active, json.dumps(top_5)

def generate_metrics(agent_token):
    mac_address = get_mac_address()
    internal_ip = get_internal_ip()
    net_old = psutil.net_io_counters()
    
    while True:
        try:
            # Paraemtros Basicos
            time.sleep(3)
            cpu = psutil.cpu_percent(interval=None)
            ram = psutil.virtual_memory().percent
            disk = psutil.disk_usage('/').percent
            temp = get_temperature()
            total_procs, top_procs_json = get_processes_info()
            current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            # Red
            net_new = psutil.net_io_counters()
            net_up = (net_new.bytes_sent - net_old.bytes_sent) / 1024 / 1024 / 3
            net_down = (net_new.bytes_recv - net_old.bytes_recv) / 1024 / 1024 / 3
            net_old = net_new
            metric = telemetry_pb2.SystemMetrics(
                server_id=mac_address,
                cpu_usage=round(cpu, 2),
                ram_usage=round(ram, 2),
                disk_usage=round(disk, 2),
                temperature=temp,
                active_processes=total_procs,
                timestamp=current_time,
                network_download=round(net_down, 2),
                network_upload=round(net_up, 2),
                top_processes=top_procs_json,
                agent_token=agent_token,
                internal_ip=internal_ip 
            )
            
            yield metric
            
        except Exception as e:
            print(f"\n🚨 ERROR INTERNO EN PYTHON: {e}")
            break

def run_agent(token):
    channel = grpc.insecure_channel('www.caris.website:50052') 
    stub = telemetry_pb2_grpc.AgentMetricsServiceStub(channel)
    
    print(f"Iniciando Agente CARIS. MAC: {get_mac_address()} | IP: {get_internal_ip()}")
    print(f"Token de Autenticación: {token}")
    
    try:
        response = stub.StreamMetrics(generate_metrics(token))
        print(f"Respuesta del servidor: {response.message}")
    except grpc.RpcError as e:
        print(f"Error de conexión gRPC: {e.code()} - {e.details()}")
    except KeyboardInterrupt:
        print("\nAgente detenido manualmente.")



if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description="CARIS Telemetry Agent")
    parser.add_argument('--token', type=str, required=True, help="Token seguro generado por CARIS")
    args = parser.parse_args()
    # Hilo Paralelo, El Oido
    command_thread = threading.Thread(target=serve_commands, daemon=True)
    command_thread.start()
    # Hilo Paralelo,  La Boca
    run_agent(args.token)
