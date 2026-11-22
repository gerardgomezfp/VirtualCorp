# Actividad: Despliegue de DHCP Centralizado (Kea DHCPv4) y DHCP Relays en RouterOS — Delegación 8

Este documento recoge de manera exhaustiva el diseño, la arquitectura de Infraestructura como Código (IaC), la automatización con Ansible, las decisiones técnicas de direccionamiento y las pruebas de validación ejecutadas para el despliegue del servicio DHCP centralizado y los relays DHCP de la **Delegación 8** de **VirtualCorp**. Siguiendo los principios de IaC, el aprovisionamiento del contenedor `dhcp01` en Proxmox se gestiona con Terraform (`bpg/proxmox`), mientras que la configuración del servidor Kea DHCPv4 y de los relays en RouterOS se automatiza de forma modular, reproducible e idempotente mediante Ansible y se orquesta con `make deploy_dhcp`.

## Índice

1. [Arquitectura y Diseño de Red (Delegación 8)](#1-arquitectura-y-diseño-de-red-delegación-8)
   - [1.1. Adaptación a la Delegación 8 y Justificación de `.137` / `.138`](#11-adaptación-a-la-delegación-8-y-justificación-de-137--138)
   - [1.2. Subredes, Gateways, Relays y Exclusiones](#12-subredes-gateways-relays-y-exclusiones)
2. [Estructura del Proyecto, Terraform y Seguridad](#2-estructura-del-proyecto-terraform-y-seguridad)
   - [2.1. Árbol de Directorios y Ficheros Clave](#21-árbol-de-directorios-y-ficheros-clave)
   - [2.2. Instalación de Terraform, Acceso a Proxmox y Contenedor `dhcp01`](#22-instalación-de-terraform-acceso-a-proxmox-y-contenedor-dhcp01)
   - [2.3. Protección de Credenciales, Estado y Secretos en Git](#23-protección-de-credenciales-estado-y-secretos-en-git)
3. [Automatización de Kea DHCPv4 con Ansible (`kea_dhcp`)](#3-automatización-de-kea-dhcpv4-con-ansible-kea_dhcp)
   - [3.1. Ámbitos, Pools Dinámicos y Opciones DHCP](#31-ámbitos-pools-dinámicos-y-opciones-dhcp)
   - [3.2. Reservas Estáticas por MAC (Servidores e Impresoras)](#32-reservas-estáticas-por-mac-servidores-e-impresoras)
   - [3.3. Validación de Configuración e Idempotencia](#33-validación-de-configuración-e-idempotencia)
4. [Automatización de DHCP Relay en RouterOS (`dhcp_relay`)](#4-automatización-de-dhcp-relay-en-routeros-dhcp_relay)
   - [4.1. Funcionamiento del Relay (`giaddr`) y Topología por Router](#41-funcionamiento-del-relay-giaddr-y-topología-por-router)
   - [4.2. Comprobación Manual, Rol `dhcp_relay` y Playbook](#42-comprobación-manual-rol-dhcp_relay-y-playbook)
5. [Pruebas, Validación, `Makefile` y Criterios de Finalización](#5-pruebas-validación-makefile-y-criterios-de-finalización)
   - [5.1. Validación de Kea, Relays y Pruebas Controladas por LAN](#51-validación-de-kea-relays-y-pruebas-controladas-por-lan)
   - [5.2. Reejecución Idempotente, Target `deploy_dhcp` y Entrega Git](#52-reejecución-idempotente-target-deploy_dhcp-y-entrega-git)
   - [5.3. Checklist de Criterios de Finalización](#53-checklist-de-criterios-de-finalización)

---

## 1. Arquitectura y Diseño de Red (Delegación 8)

La solución centraliza la asignación dinámica de direcciones IPv4 y las reservas por dirección MAC para la **Delegación 8** (`10.8.0.0/16`) mediante un servidor **Kea DHCPv4** ejecutándose en el contenedor LXC `dhcp01`, combinado con agentes **DHCP relay** en las interfaces de los routers MikroTik conectadas a segmentos con clientes.

### 1.1. Adaptación a la Delegación 8 y Justificación de `.137` / `.138`

Mientras que el enunciado base toma como referencia la delegación central (`10.1.0.0/16`, con servidor DHCP en `10.1.0.136` y anuncio DNS en `10.1.0.137`), todo el despliegue se ha adaptado al espacio de direccionamiento de la **Delegación 8** (`10.8.0.0/16`) y al plan de direccionamiento aprobado (`configs/address-plan.tsv`):

| Parámetro | Valor / Configuración | Descripción Técnica |
| :--- | :--- | :--- |
| **Espacio de Delegación** | `10.8.0.0/16` | Red corporativa asignada a la Delegación 8 de VirtualCorp. |
| **Contenedor DHCP (`dhcp01`)** | `10.8.0.137/26` | Contenedor LXC Debian 13 sin privilegios en la red `privada` (`10.8.0.128/26`), gateway `10.8.0.129`. |
| **Servidor DNS Anunciado** | `10.8.0.138` | Opción DNS entregada por DHCP a los clientes de la delegación. |
| **Dominio Corporativo** | `virtualcorp.local` | Nombre de dominio anunciado mediante las opciones DHCP de Kea. |
| **Acceso de Gestión** | Túnel WireGuard + SSH | Acceso desde el nodo de control Debian 13 a Proxmox (`pve01`), `dhcp01` y routers MikroTik. |

> **Justificación técnica de la asignación `.137` (DHCP) y `.138` (DNS):** En la subred `privada` (`10.8.0.128/26`), la dirección `10.8.0.136` ya estaba ocupada por un servidor existente de la delegación (`intrasrv`). Para evitar cualquier solapamiento o conflicto de IP en el segmento, se asignó `10.8.0.137` al contenedor `dhcp01` y `10.8.0.138` al servidor DNS, garantizando una separación limpia sin colisiones.

### 1.2. Subredes, Gateways, Relays y Exclusiones

La Delegación 8 organiza sus segmentos internos de forma que cada LAN de clientes/servidores cuente con su ámbito DHCP en Kea y, cuando está separada del servidor DHCP por un router, con su correspondiente relay:

1. **Planta Baja (`pl0`):** `10.8.0.0/25` — Gateway `10.8.0.1` (`vcorp-planta00`).
2. **Red Privada (`privada`):** `10.8.0.128/26` — Gateway `10.8.0.129` (`vcorp-privada`), donde reside `dhcp01` (`10.8.0.137`).
3. **Zona Desmilitarizada (`dmz`):** `10.8.0.192/27` — Gateway `10.8.0.193` (`vcorp-dmz`).
4. **Enlace Troncal `R0-R1`:** `10.8.0.224/30` — Enlace punto a punto entre routers sin clientes finales; **excluido** de pools DHCP y de relays DHCP.
5. **Planta 1 (`pl1`):** `10.8.1.0/24` — Gateway `10.8.1.1` (`vcorp-planta01`), con relay hacia `10.8.0.137`.
6. **Planta 2 (`pl2`):** `10.8.2.0/24` — Gateway `10.8.2.1` (`vcorp-planta02`), con relay hacia `10.8.0.137`.
7. **Planta 3 (`pl3`):** `10.8.3.0/25` — Gateway `10.8.3.1` (`vcorp-planta03`), con relay hacia `10.8.0.137`.
8. **Dirección (`pl3_direccio`):** `10.8.3.128/25` — Gateway `10.8.3.129` (`vcorp-direccio`), con relay hacia `10.8.0.137`.

Quedan excluidos de la configuración de relays los enlaces punto a punto entre routers, el túnel WireGuard y cualquier interfaz sin clientes finales.

---

## 2. Estructura del Proyecto, Terraform y Seguridad

### 2.1. Árbol de Directorios y Ficheros Clave

La definición de infraestructura en Proxmox, la automatización con Ansible, el `Makefile` y la documentación se mantienen organizados en el repositorio `VirtualCorp-student`:

```text
VirtualCorp-student/
├── Makefile
├── configs/
│   └── address-plan.tsv
├── docs/
│   └── dhcp.md
├── infrastructure/
│   └── terraform/
│       └── proxmox/
│           ├── main.tf
│           ├── variables.tf
│           ├── README.md
│           ├── .terraform.lock.hcl      # Versionado en Git
│           ├── .terraform/              # Ignorado en Git
│           ├── terraform.tfstate        # Ignorado en Git
│           └── terraform.local.tfvars   # Local e ignorado en Git (chmod 600)
└── automation/
    └── ansible/
        ├── requirements.yml
        ├── inventories/
        │   └── lab.yml
        ├── playbooks/
        │   ├── dhcp.yml
        │   └── dhcp_relay.yml
        └── roles/
            ├── kea_dhcp/
            │   ├── defaults/main.yml
            │   ├── tasks/main.yml
            │   └── templates/
            │       └── kea-dhcp4.conf.j2
            └── dhcp_relay/
                ├── defaults/main.yml
                └── tasks/main.yml
```

### 2.2. Instalación de Terraform, Acceso a Proxmox y Contenedor `dhcp01`

1. **Instalación en el nodo de control:** Terraform (versión `>= 1.6`) se instaló en el equipo de control (Debian/Ubuntu) mediante el repositorio oficial de HashiCorp, verificándose con `terraform -version`. No se requiere instalar Terraform dentro de Proxmox ni dentro de `dhcp01`.
2. **Proveedor y plantilla:** Se utiliza el proveedor `bpg/proxmox` (serie `0.112.x`) a través del túnel WireGuard hacia el nodo Proxmox (`pve01`) y una plantilla LXC oficial de **Debian 13** (`debian-13-standard`) en un almacenamiento con contenido `VZTemplate` habilitado, autenticando mediante un usuario de servicio y token API con permisos acotados.
3. **Contenedor `dhcp01`:** Declarado exclusivamente como recurso `proxmox_virtual_environment_container` en `infrastructure/terraform/proxmox/main.tf` (y parametrizado en `variables.tf`):
   - Contenedor LXC **sin privilegios**, con hostname `dhcp01` y modo compatible con Debian y `systemd`.
   - Recursos iniciales: **1 vCPU**, **512 MB de RAM** y **6 GB de disco**.
   - Interfaz de red conectada al bridge de Proxmox correspondiente a la red `privada`, con IP estática de bootstrap `10.8.0.137/26`, gateway `10.8.0.129` y DNS inicial antes de desplegar el servicio.
   - Arranque automático al iniciar el nodo Proxmox y claves públicas SSH autorizadas para `vcorp_auditor` y `sysadmin`.
4. **Ciclo de trabajo:** `terraform init`, `terraform fmt -recursive`, `terraform validate`, `terraform plan` y `terraform apply`. Una nueva ejecución de `terraform plan` sin cambios en la configuración reporta `0 added, 0 changed, 0 destroyed` (idempotencia).

### 2.3. Protección de Credenciales, Estado y Secretos en Git

* Nunca se escriben tokens API, contraseñas ni claves privadas dentro de ficheros `.tf`, playbooks o plantillas versionadas.
* Las variables sensibles se pasan mediante variables `TF_VAR_...` o a través de `terraform.local.tfvars` con permisos restrictivos (`chmod 600`), excluido del control de versiones.
* `.terraform/`, `terraform.tfstate` y ficheros locales sensibles permanecen fuera de Git, mientras que `.terraform.lock.hcl` sí se versiona para fijar las sumas y versiones del proveedor.

---

## 3. Automatización de Kea DHCPv4 con Ansible (`kea_dhcp`)

El rol `automation/ansible/roles/kea_dhcp/` separa los datos de direccionamiento (`defaults/main.yml`), las tareas (`tasks/main.yml`) y la plantilla de configuración (`templates/kea-dhcp4.conf.j2`), aplicándose desde el playbook de DHCP (`automation/ansible/playbooks/dhcp.yml`).

### 3.1. Ámbitos, Pools Dinámicos y Opciones DHCP

* Instala los paquetes del servidor **Kea DHCPv4** desde los repositorios de la distribución.
* Define explícitamente la interfaz de red en la que escucha Kea en `dhcp01`.
* Declara los ámbitos (`subnet4`) para las redes con asignación DHCP de la Delegación 8 (`dmz`, `privada`, `planta00`, `planta01`, `planta02`, `planta03` y `direccio`), excluyendo enlaces punto a punto entre routers y segmentos sin clientes.
* Configura para cada subred la máscara, la puerta de enlace (`routers`), el rango dinámico (`pool`), el dominio `virtualcorp.local` y el servidor DNS `10.8.0.138`.

### 3.2. Reservas Estáticas por MAC (Servidores e Impresoras)

* Las reservas estáticas se generan a partir de las direcciones MAC observadas en VirtualBox/Proxmox y del plan `configs/address-plan.tsv`.
* Cada servidor e impresora documentado recibe su IP reservada asociada a su MAC, verificando que las direcciones reservadas no colisionen con los rangos dinámicos (`pool`).
* Los equipos de usuario sin reserva obtienen una dirección dinámica dentro del pool de su LAN correspondiente.

### 3.3. Validación de Configuración e Idempotencia

* Antes de reiniciar el servicio, el rol valida la sintaxis del fichero de configuración de Kea, habilita el servicio en el arranque (`enabled: true`) y comprueba su estado activo.
* En ejecuciones posteriores sin cambios en las variables o plantillas, no se reescribe el fichero ni se reinicia Kea innecesariamente (`changed=0`).

---

## 4. Automatización de DHCP Relay en RouterOS (`dhcp_relay`)

### 4.1. Funcionamiento del Relay (`giaddr`) y Topología por Router

Las tramas iniciales de descubrimiento DHCP (`DHCPDISCOVER`) se envían como broadcast en la LAN local y no son reenviadas como broadcast IP normal por los routers. El agente **DHCP relay** en RouterOS intercepta la petición en la interfaz de la LAN, la reenvía en *unicast* hacia el servidor Kea (`10.8.0.137`) y rellena el campo `giaddr` (gateway IP address) con la dirección IP del router en esa subred. Kea utiliza `giaddr` para identificar la LAN de origen y seleccionar la subred y el pool adecuados.

La asignación de relays por router de la topología responde a las interfaces con clientes:

| Router | Nombre Relay | Interfaz | `local-address` | Servidor DHCP |
| :--- | :--- | :--- | :--- | :--- |
| `mikrotik0` | `vcorp-dmz` | `ether3` | `10.8.0.193` | `10.8.0.137` |
| `mikrotik0` | `vcorp-privada` | `ether4` | `10.8.0.129` | `10.8.0.137` |
| `mikrotik1` | `vcorp-planta00` | `ether4` | `10.8.0.1` | `10.8.0.137` |
| `mikrotik2` | `vcorp-planta01` | `ether4` | `10.8.1.1` | `10.8.0.137` |
| `mikrotik2` | `vcorp-planta02` | `ether5` | `10.8.2.1` | `10.8.0.137` |
| `mikrotik3` | `vcorp-planta03` | `ether3` | `10.8.3.1` | `10.8.0.137` |
| `mikrotik3` | `vcorp-direccio` | `ether4` | `10.8.3.129` | `10.8.0.137` |

Las rutas de retorno en la delegación permiten que `dhcp01` (`10.8.0.137`) responda a las peticiones reenviadas por cada relay.

### 4.2. Comprobación Manual, Rol `dhcp_relay` y Playbook

* Antes de automatizar, se verificó la sintaxis y el comportamiento en RouterOS mediante `/ip dhcp-relay add ... disabled=no` y `/ip dhcp-relay print detail`.
* El rol `automation/ansible/roles/dhcp_relay/` está separado de otros roles de RouterOS y emplea `community.routeros.command` para:
  1. Consultar las entradas existentes en `/ip dhcp-relay` antes de escribir.
  2. Crear la entrada si no existe (`add`), actualizarla si difiere en parámetros (`set`), habilitarla si estaba desactivada (`disabled=no`) y no tocarla si ya está activa y correcta, evitando duplicados en ejecuciones repetidas.
* El playbook `automation/ansible/playbooks/dhcp_relay.yml` aplica el rol `dhcp_relay` sobre el inventario (`automation/ansible/inventories/lab.yml`), previa instalación de colecciones desde `automation/ansible/requirements.yml` y validación con `ansible-inventory --graph` y `ansible-playbook --syntax-check`.

---

## 5. Pruebas, Validación, `Makefile` y Criterios de Finalización

### 5.1. Validación de Kea, Relays y Pruebas Controladas por LAN

* **Servicio Kea:** Se verificó que el servicio Kea DHCPv4 está activo, escucha en la interfaz esperada de `dhcp01` y no presenta errores en sus logs.
* **Relays en RouterOS:** Se comprobó con `/ip dhcp-relay print detail` que las entradas existen, están habilitadas (`disabled=no`), apuntan a `10.8.0.137` y usan la interfaz y `local-address` correspondientes a cada LAN.
* **Pruebas secuenciales sin arrancar todas las VMs a la vez:** Las máquinas de prueba se arrancaron, validaron y apagaron de forma controlada (una por segmento) para evitar saturación y colisiones de prueba:
  - **`printer1` (`pl1`, MAC `08:00:27:c1:f7:02`):** obtuvo el lease esperado (`10.8.1.65/24`) a través del relay de `R2` (`10.8.1.1`), con puerta de enlace `10.8.1.1`, dominio `virtualcorp.local` y DNS `10.8.0.138`.
  - **`printer2` (`pl2`, MAC `08:00:27:ef:2d:5f`):** validada igualmente mediante solicitud/renovación de lease (`10.8.2.65/24`) a través del relay (`10.8.2.1`), apagándose tras la comprobación.
* **Reservas y leases:** Se confirmó que las reservas por MAC coinciden con la documentación y se mantienen al renovar la concesión.

### 5.2. Reejecución Idempotente, Target `deploy_dhcp` y Entrega Git

* El target `deploy_dhcp` del `Makefile` coordina la ejecución de Terraform para `dhcp01` y los playbooks de Ansible para Kea DHCPv4 y los relays de RouterOS.
* En la reejecución completa tras el despliegue inicial, tanto el plan/aplicación de Terraform como los playbooks de Ansible resultaron idempotentes (`0` cambios en recursos ya convergidos).
* Para la entrega en el repositorio Git:
  1. Se revisó el árbol de trabajo para garantizar la ausencia de tokens API, contraseñas, claves privadas o ficheros de estado/variables locales sensibles.
  2. Se registraron los cambios en la rama `adaptacion-delegacion8` y se etiquetó la entrega con el tag `DHCP` (`git tag DHCP` y `git push` de rama y etiqueta).