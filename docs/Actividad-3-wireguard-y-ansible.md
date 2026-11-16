# Memoria Técnica y Documentación de Automatización VPN - Delegación 8 (VirtualCorp)

**Alumno:** Gerard Gómez  
**Curso:** ASIX2 26-27  
**Actividad:** Activitat 3 — Automatització amb Ansible i Desplegament de VPN WireGuard  

Este documento recoge de manera exhaustiva el diseño, la arquitectura de automatización, las políticas de seguridad y las pruebas de validación ejecutadas para el despliegue integral de la **VPN Corporativa WireGuard** de la **Delegación 8 de VirtualCorp**. Siguiendo los principios de Infraestructura como Código (IaC), todo el aprovisionamiento del servidor perimetral (`mikrotik0`) y del nodo cliente/control (Debian 13) se ha implementado de forma modular, reproducible y estrictamente idempotente mediante **Ansible**.

---

## Índice

- [1. Arquitectura y Diseño de la Red VPN](#1-arquitectura-y-diseño-de-la-red-vpn)
- [2. Estructura Modular de Ansible y Gestión de Artefactos](#2-estructura-modular-de-ansible-y-gestión-de-artefactos)
- [3. Despliegue Automatizado del Servidor (`wireguard_server` en `mikrotik0`)](#3-despliegue-automatizado-del-servidor-wireguard_server-en-mikrotik0)
- [4. Despliegue Automatizado del Cliente (`wireguard_client` en Debian 13)](#4-despliegue-automatizado-del-cliente-wireguard_client-en-debian-13)
- [5. Seguridad, Criptografía y Split Tunneling](#5-seguridad-criptografía-y-split-tunneling)
- [6. Comprobaciones Técnicas, Idempotencia y Validación](#6-comprobaciones-técnicas-idempotencia-y-validación)

---

## 1. Arquitectura y Diseño de la Red VPN

La solución proporciona un canal de comunicaciones cifrado de extremo a extremo entre la estación de administración local (Debian 13) y el router de frontera de la Delegación 8 (`mikrotik0`), permitiendo la gestión segura de las infraestructuras internas sin exponer los servicios corporativos a redes externas.

### 1.1. Plan de Direccionamiento del Túnel y Endpoint

| Parámetro | Valor / Configuración | Descripción Técnica |
| :--- | :--- | :--- |
| **Protocolo VPN** | WireGuard (UDP) | Criptografía moderna de alto rendimiento en espacio de kernel. |
| **Interfaz Servidor** | `wg-vcorp` | Interfaz virtual creada en RouterOS (`mikrotik0`). |
| **Puerto de Escucha** | `51820/UDP` | Puerto estándar WireGuard habilitado en la interfaz WAN (`ether1`). |
| **Red del Túnel** | `10.8.10.0/24` | Subred dedicada exclusivamente al direccionamiento punto a punto del túnel. |
| **IP Servidor VPN** | `10.8.10.1/24` | Dirección asignada a `mikrotik0` dentro de la red privada virtual. |
| **IP Cliente VPN** | `10.8.10.2/32` | Dirección asignada al nodo de control Debian 13 (`vcorp-client`). |
| **Endpoint de Conexión** | `127.0.0.1:51820` | Acceso a través del reenvío de puertos (*Port Forwarding*) UDP en VirtualBox hacia `ether1`. |

### 1.2. Subredes Corporativas Autorizadas (Delegación 8)

El enrutamiento a través del túnel está estrictamente limitado a las 8 subredes internas de la delegación, además de la propia red de tránsito del túnel:

1. **Planta Baja (`pl0`)**: `10.8.0.0/25`
2. **Red Privada (`privada`)**: `10.8.0.128/26`
3. **Zona Desmilitarizada (`dmz`)**: `10.8.0.192/27`
4. **Enlace Troncal R0-R1**: `10.8.0.224/30`
5. **Planta 1 (`pl1`)**: `10.8.1.0/24`
6. **Planta 2 (`pl2`)**: `10.8.2.0/24`
7. **Planta 3 (`pl3`)**: `10.8.3.0/25`
8. **Dirección (`pl3_direccio`)**: `10.8.3.128/25`

---

## 2. Estructura Modular de Ansible y Gestión de Artefactos

Toda la automatización reside en el directorio `automation/ansible/`, estructurada mediante un playbook unificado (`playbooks/wireguard.yml`) que orquesta dos roles independientes y reutilizables.

### 2.1. Árbol de Directorios del Proyecto

```text
VirtualCorp-student/
├── artifacts/
│   └── vpn/                          # Excluido de Git (.gitignore) - Permisos 0700
│       ├── vcorp_client_private.key  # Clave privada del cliente (Permisos 0600)
│       ├── vcorp_client_public.key   # Clave pública del cliente (Permisos 0600)
│       └── vcorp-client.conf         # Configuración generada mediante plantilla Jinja2 (0600)
└── automation/
    └── ansible/
        ├── inventory/                # Definición de hosts (mikrotik0 y localhost)
        ├── playbooks/
        │   └── wireguard.yml         # Playbook principal unificado
        └── roles/
            ├── wireguard_server/     # Automatización de RouterOS en mikrotik0
            │   ├── defaults/main.yml
            │   └── tasks/main.yml
            └── wireguard_client/     # Automatización local en Debian 13
                ├── defaults/main.yml
                ├── tasks/main.yml
                └── templates/
                    └── vcorp-client.conf.j2
```

### 2.2. Patrón de Idempotencia Implementado

Para garantizar que el playbook pueda ejecutarse múltiples veces sin provocar errores de duplicidad ni alterar configuraciones operativas, ambos roles siguen un patrón explícito de **Comprobación (`register`) $\rightarrow$ Evaluación Condicional (`when`)**:
* En `mikrotik0`, se utilizan consultas `print count-only` mediante el módulo `community.routeros.command` antes de crear interfaces, IPs, *peers* o reglas de firewall.
* En `localhost` (Debian), se emplea el módulo nativo `ansible.builtin.stat` para comprobar la existencia previa de directorios, claves criptográficas y ficheros de configuración.

---

## 3. Despliegue Automatizado del Servidor (`wireguard_server` en `mikrotik0`)

El primer *play* de `wireguard.yml` actúa sobre el router perimetral `mikrotik0` ejecutando secuencialmente las siguientes tareas:

1. **Creación de la Interfaz WireGuard**: Verifica si existe `wg-vcorp` y, en caso negativo, la crea escuchando en el puerto UDP `51820`.
2. **Asignación de Direccionamiento IP**: Comprueba y asigna la dirección `10.8.10.1/24` sobre la interfaz `wg-vcorp`.
3. **Registro del Peer Cliente**: Configura el *peer* correspondiente al nodo Debian (`debian-client`), asociando su clave pública y restringiendo su origen permitido a `10.8.10.2/32`.
4. **Políticas de Firewall (`input`)**: Añade una regla en la cadena `input` para aceptar tráfico UDP entrante por `ether1` con destino al puerto `51820`.
5. **Políticas de Firewall (`forward`) y Aislamiento**:
   * Permite el tráfico `established` y `related` para garantizar el retorno de paquetes.
   * Mediante un bucle (`loop`), genera dinámicamente 8 reglas individuales en la cadena `forward` que autorizan el tráfico procedente de `wg-vcorp` únicamente hacia cada una de las 8 subredes corporativas listadas en el inventario.
   * Incorpora una regla final de bloqueo (`action=drop`) para cualquier otro tráfico iniciado desde la interfaz `wg-vcorp` hacia destinos no autorizados.

---

## 4. Despliegue Automatizado del Cliente (`wireguard_client` en Debian 13)

El segundo *play* se ejecuta localmente (`delegate_to: localhost`) sobre la estación de trabajo Debian 13 para aprovisionar el entorno cliente sin intervención manual:

1. **Gestión del Directorio de Artefactos**: Comprueba y crea la ruta `~/VirtualCorp-student/artifacts/vpn` con permisos estrictos de propietario (`mode: '0700'`).
2. **Generación de Par de Claves Criptográficas**:
   * Si no existe, genera la clave privada mediante `wg genkey` y aplica inmediatamente permisos `600`.
   * A partir de la clave privada, deriva la clave pública mediante `wg pubkey` con permisos `600`.
3. **Lectura Segura en Memoria**: Utiliza el módulo `ansible.builtin.slurp` con la directiva `no_log: true` para leer y decodificar en Base64 la clave privada sin exponer material sensible en los registros de ejecución de Ansible.
4. **Renderizado de Configuración vía Jinja2 (`vcorp-client.conf.j2`)**: Inyecta dinámicamente las variables en la plantilla para generar el fichero final `vcorp-client.conf` con permisos `0600`:

```ini
[Interface]
PrivateKey = {{ client_private_key_content }}
Address = {{ wireguard_client_address }}

[Peer]
PublicKey = {{ wireguard_server_public_key }}
Endpoint = {{ wireguard_server_endpoint }}
AllowedIPs = {{ (wireguard_allowed_networks + [wireguard_tunnel_network]) | join(', ') }}
PersistentKeepalive = {{ wireguard_persistent_keepalive }}
```

---

## 5. Seguridad, Criptografía y Split Tunneling

El diseño cumple rigurosamente con los requisitos de confidencialidad y segmentación de tráfico:

* **Protección de Credenciales y Control de Versiones**: Ninguna clave privada ni archivo de configuración con secretos forma parte del repositorio Git. El directorio `artifacts/` está explícitamente excluido mediante `.gitignore` y protegido a nivel de sistema de archivos mediante permisos `0700` (directorio) y `0600` (ficheros).
* **Implementación Estricta de Split Tunneling**: A través de la directiva `AllowedIPs` en el cliente, WireGuard inyecta rutas específicas en la tabla de enrutamiento de Linux únicamente para `10.8.10.0/24` y las 8 subredes internas de VirtualCorp. De este modo:
  * El tráfico administrativo hacia la Delegación 8 viaja cifrado a través del túnel.
  * El tráfico general hacia Internet continúa saliendo directamente por la interfaz física del equipo anfitrión sin latencia añadida ni pérdida de conectividad exterior.
* **Mantenimiento de Sesión (`PersistentKeepalive = 25`)**: Envía paquetes de mantenimiento cada 25 segundos para preservar la tabla de traducción de direcciones (NAT) en VirtualBox y evitar cortes por inactividad.

---

## 6. Comprobaciones Técnicas, Idempotencia y Validación

Se han llevado a cabo todas las pruebas de verificación funcionales y de seguridad exigidas:

### 6.1. Validación de Idempotencia de Ansible

Tras una primera ejecución donde se aprovisionó el fichero de configuración del cliente (`changed=1`), se lanzó una segunda ejecución consecutiva del playbook (`ansible-playbook playbooks/wireguard.yml`), obteniendo un resultado de **0 cambios en ambos nodos**:

```text
PLAY RECAP *********************************************************************
localhost                  : ok=6    changed=0    unreachable=0    failed=0    skipped=4
mikrotik0                  : ok=7    changed=0    unreachable=0    failed=0    skipped=7
```

### 6.2. Levantamiento del Túnel y Verificación de Rutas

Al activar la interfaz con `sudo wg-quick up ~/VirtualCorp-student/artifacts/vpn/vcorp-client.conf`, el sistema operativo configura automáticamente la interfaz `vcorp-client` (`10.8.10.2/32`) e inyecta exclusivamente las 9 rutas autorizadas en el kernel:

```text
[#] ip link add vcorp-client type wireguard
[#] ip -4 address add 10.8.10.2/32 dev vcorp-client
[#] ip -4 route add 10.8.0.0/25 dev vcorp-client
[#] ip -4 route add 10.8.0.128/26 dev vcorp-client
[#] ip -4 route add 10.8.0.192/27 dev vcorp-client
[#] ip -4 route add 10.8.0.224/30 dev vcorp-client
[#] ip -4 route add 10.8.1.0/24 dev vcorp-client
[#] ip -4 route add 10.8.2.0/24 dev vcorp-client
[#] ip -4 route add 10.8.3.0/25 dev vcorp-client
[#] ip -4 route add 10.8.3.128/25 dev vcorp-client
[#] ip -4 route add 10.8.10.0/24 dev vcorp-client
```

### 6.3. Confirmación del Handshake Criptográfico en RouterOS

Mediante consulta directa al router `mikrotik0` (`/interface wireguard peers print detail`), se verificó el establecimiento activo del túnel, el intercambio correcto de paquetes (`rx`/`tx`) y la actualización de la marca de tiempo `last-handshake`:

```text
 0    ;;; debian-client
      interface=wg-vcorp name="peer1" 
      public-key="HvtSX8q7rjUmuMtibQJitGRUKbCe4PK2LV1XIF3Ru04=" 
      current-endpoint-address=10.0.2.2 current-endpoint-port=44727 
      allowed-address=10.8.10.2/32 rx=308 tx=92 last-handshake=1m49s
```

### 6.4. Conectividad Extremo a Extremo y Split Tunneling

1. **Conectividad al extremo del túnel**: Respuesta ICMP exitosa (`0% packet loss`) hacia la IP interna del servidor VPN (`ping -c 3 10.8.10.1`).
2. **Conectividad a subredes corporativas**: Acceso verificado hacia las pasarelas y equipos internos de las distintas plantas de la Delegación 8 gracias al enrutamiento dinámico RIP y a las reglas `forward` de `mikrotik0`.
3. **Verificación de navegación externa**: Comprobación de que la salida general a Internet se mantiene intacta por la puerta de enlace local sin atravesar el túnel VPN.