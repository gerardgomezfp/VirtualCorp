# Memoria Técnica y Documentación de Despliegue - Delegación 8 (VirtualCorp)

Alumno: Gerard Gómez
Curso: ASIX2 26-27

Este documento recoge de manera exhaustiva el diseño, la implementación, el flujo de automatización y los procedimientos técnicos utilizados para el despliegue integral de la **Delegación 8 de VirtualCorp**. El proyecto se ha diseñado bajo los principios de Infraestructura como Código (IaC), garantizando la reproducibilidad, la robustez mediante la idempotencia y el cumplimiento estricto de los requisitos de seguridad (acceso SSH automatizado y aislamiento de redes).

## Índice

* [1. Arquitectura y Flujo del Makefile](#1-arquitectura-y-flujo-del-makefile)

* [2. Creación de Plantillas Debian y Automatización Preseed](#2-creación-de-plantillas-debian-y-automatización-preseed)

* [3. Despliegue Masivo de los 29 Equipos (`deploy_equipment.sh`)](#3-despliegue-masivo-de-los-29-equipos-deploy_equipmentsh)

* [4. Instalación Desatendida de Proxmox VE (`pve01`)](#4-instalación-desatendida-de-proxmox-ve-pve01)

* [5. Comprobaciones Técnicas y Validación](#5-comprobaciones-técnicas-y-validación)

## 1. Arquitectura y Flujo del Makefile

El flujo de trabajo centralizado en el archivo `Makefile` permite gestionar el ciclo de vida del proyecto de manera modular, separando la generación de plantillas base de la instanciación y configuración de la infraestructura masiva.

### Objetivos Principales del Makefile:

* **`make create_templates`**: Ejecuta el script `infrastructure/bash/vcorp_create_templates.sh`, el cual se encarga de:

  1. Validar y descargar las imágenes ISO oficiales de Debian Netinst (`debian-13.7.0-amd64-netinst.iso`).

  2. Generar las plantillas base para servidores y estaciones de trabajo (`debian_server_template` y `debian_desktop_template`) utilizando instalaciones automatizadas mediante `preseed`.

  3. Crear un snapshot llamado `base` en cada plantilla, indispensable para realizar posteriores clonaciones enlazadas (*linked clones*).

* **`make deploy_equipment`**: Ejecuta de manera secuencial e idempotente:

  1. `deploy_equipment.sh`: Clonación de las 29 máquinas de la delegación y conexión a los segmentos de red internos de VirtualBox.

  2. `configure_equipment.sh --all`: Aplicación de parámetros de red y configuraciones específicas por equipo.

  3. `deploy_pve.sh`: Instalación desatendida del nodo Proxmox VE (`pve01`) con soporte de virtualización anidada.

## 2. Creación de Plantillas Debian y Automatización Preseed

La creación de las plantillas base se automatiza mediante scripts en el entorno de Bash, integrando directamente la respuesta desatendida (*preseed*) para evitar cualquier intervención manual durante la instalación del sistema operativo base.

### 2.1. Características Técnicas de las Plantillas

* **`debian_server_template`**:

  * **vCPU**: 1 | **RAM**: 1024 MB | **Disco**: 20 GB (VDI).

  * **Perfil**: Instalación mínima orientada a servidores (paquetes estándar y servidor SSH).

* **`debian_desktop_template`**:

  * **vCPU**: 2 | **RAM**: 2048 MB | **Disco**: 20 GB (VDI).

  * **Perfil**: Estación de trabajo ligera con entorno gráfico LXQt (`xserver-xorg`, `lxqt-core`, `lightdm`, `falkon`) y herramientas de desarrollo.

### 2.2. Mecanismo de Seguridad e Inyección vía `late_command`

Durante la instalación desatendida, se ejecuta un bloque `late_command` altamente robusto que prepara la plantilla para su uso en clonación masiva y establece las políticas de acceso obligatorias:

1. **Creación del usuario de administración**: Se crea automáticamente el usuario `sysadmin` con contraseña cifrada y privilegios de sudo sin contraseña (`NOPASSWD:ALL` en `/etc/sudoers.d/sysadmin`).

2. **Inyección de Claves SSH Públicas**: Se copian las claves autorizadas desde el medio de instalación hacia el directorio `/home/sysadmin/.ssh/authorized_keys`, garantizando tanto el acceso del alumno como del auditor (`configs/ssh/vcorp_auditor.pub`). Se configuran estrictamente los permisos (`700` para `.ssh` y `600` para `authorized_keys`).

3. **Hardening SSH**: Se aplica la directiva de seguridad mediante `/etc/ssh/sshd_config.d/99-vcorp-key-only.conf` desactivando el acceso por contraseña y permitiendo exclusivamente la autenticación por clave pública.

4. **Preparación para Clonación**: Se eliminan las claves de host existentes, se programa un servicio systemd para regenerarlas en el primer arranque y se vacía el archivo `/etc/machine-id` vinculado con D-Bus.

## 3. Despliegue Masivo de los 29 Equipos (`deploy_equipment.sh`)

El script `deploy_equipment.sh` lee un inventario predefinido y realiza un despliegue automatizado basado en **clonación enlazada** (*linked clones*), optimizando el espacio en disco y garantizando un rendimiento óptimo.

### 3.1. Lógica de Idempotencia y Verificación

Antes de iniciar cualquier operación, el script valida la existencia de la carpeta base, comprueba que las plantillas dispongan del snapshot `base`, verifica la presencia de todos los segmentos de red necesarios (`privada`, `dmz`, `pl0`, `pl1`, `pl2`, `pl3`, `pl3_direccio`) y utiliza la función `vm_exists` para evitar duplicados o modificaciones no deseadas en equipos ya creados.

### 3.2. Inventario Detallado y Plan de Direccionamiento de la Delegación 8

- 📄 **[Documentació de Topologia i Connexió (PDF)](./assets/Vcorp%20Connexi%C3%B3%20amb%20M0375%20ASIX.pdf)**


A continuación se detalla la correspondencia completa de cada máquina, su red asignada, dirección IP, máscara/prefijo y puerta de enlace (*gateway*):

| Máquina | Tipo | Red VirtualBox | Dirección IP | Prefijo | Gateway | 
| ----- | ----- | ----- | ----- | ----- | ----- | 
| `pve01` | proxmox | `privada` | `10.8.0.133` | `/26` | `10.8.0.129` | 
| `dbsrv` | server | `privada` | `10.8.0.134` | `/26` | `10.8.0.129` | 
| `infosrv` | server | `privada` | `10.8.0.135` | `/26` | `10.8.0.129` | 
| `intrasrv` | server | `privada` | `10.8.0.136` | `/26` | `10.8.0.129` | 
| `websrv` | server | `dmz` | `10.8.0.197` | `/27` | `10.8.0.193` | 
| `coresrv` | server | `dmz` | `10.8.0.198` | `/27` | `10.8.0.193` | 
| `streamingsrv` | server | `dmz` | `10.8.0.199` | `/27` | `10.8.0.193` | 
| `printer0` | server | `pl0` | `10.8.0.65` | `/25` | `10.8.1.1` | 
| `printer1` | server | `pl1` | `10.8.1.65` | `/24` | `10.8.2.1` | 
| `printer2` | server | `pl2` | `10.8.2.65` | `/24` | `10.8.3.1` | 
| `printer3` | server | `pl3` | `10.8.3.65` | `/25` | `10.8.4.1` | 
| `expo1` | desktop | `pl0` | `10.8.0.33` | `/26` | `10.8.0.129` | 
| `expo2` | desktop | `pl0` | `10.8.0.34` | `/26` | `10.8.0.129` | 
| `expo3` | desktop | `pl0` | `10.8.0.35` | `/26` | `10.8.0.129` | 
| `expo4` | desktop | `pl0` | `10.8.0.36` | `/26` | `10.8.0.129` | 
| `conserge1` | desktop | `pl0` | `10.8.0.37` | `/26` | `10.8.0.129` | 
| `conserge2` | desktop | `pl0` | `10.8.0.38` | `/26` | `10.8.0.129` | 
| `web-p1` | server | `pl1` | `10.8.1.10` | `/24` | `10.8.1.1` | 
| `data-p1` | server | `pl1` | `10.8.1.11` | `/24` | `10.8.1.1` | 
| `web-p2` | server | `pl1` | `10.8.1.12` | `/24` | `10.8.1.1` | 
| `data-p2` | server | `pl1` | `10.8.1.13` | `/24` | `10.8.1.1` | 
| `dev1` | desktop | `pl1` | `10.8.1.30` | `/24` | `10.8.1.1` | 
| `web-p3` | server | `pl2` | `10.8.2.10` | `/24` | `10.8.2.1` | 
| `data-p3` | server | `pl2` | `10.8.2.11` | `/24` | `10.8.2.1` | 
| `dev2` | desktop | `pl2` | `10.8.2.30` | `/24` | `10.8.2.1` | 
| `Laptop2` | desktop | `pl3` | `10.8.3.10` | `/24` | `10.8.3.1` | 
| `Laptop3` | desktop | `pl3` | `10.8.3.11` | `/24` | `10.8.3.1` | 
| `directiu1` | desktop | `pl3_direccio` | `10.8.3.130` | `/24` | `10.8.3.1` | 
| `directiu2` | desktop | `pl3_direccio` | `10.8.3.131` | `/24` | `10.8.3.1` | 
| `directiu3` | desktop | `pl3_direccio` | `10.8.3.132` | `/24` | `10.8.3.1` | 

## 4. Instalación Desatendida de Proxmox VE (`pve01`)

El despliegue del hipervisor Proxmox VE (`pve01`) se automatiza mediante la herramienta oficial `proxmox-auto-install-assistant` ejecutada localmente en espacio de usuario.

### 4.1. Configuración y Red de `pve01`

* **Recursos**: 4 vCPUs, 8192 MB de RAM (8 GB) y disco duro virtual de 64 GB en formato VDI.

* **Red**: Conectada a la red interna `privada` con IP estática `10.8.0.133/26`, gateway `10.8.0.129` y modo promiscuo (`allow-all`).

* **Virtualización Anidada**: Habilitada con `VBoxManage modifyvm "pve01" --nested-hw-virt on`.

* **Seguridad**: Inyección automática de las claves SSH del administrador y del auditor (`vcorp_auditor.pub`) en el archivo `/root/.ssh/authorized_keys` del nodo.

## 5. Comprobaciones Técnicas y Validación

1. **Verificación de Inyección SSH**: Se ha auditado el archivo de claves autorizadas en `pve01` y en los nodos Debian, comprobando el correcto funcionamiento de la automatización sin intervención manual.

2. **Conectividad de Red**: Se ha comprobado con éxito la conectividad desde el interior de `pve01` hacia las pasarelas locales (0% de pérdida de paquetes), quedando pendiente el tráfico externo por la futura configuración de los servicios de red y NAT perimetrales.
