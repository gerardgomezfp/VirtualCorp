# Memoria Técnica: Despliegue de `dns01` y Servicio DNS (BIND9) en la Delegación 8

> **Contexto del entorno:** Documentación técnica en castellano elaborada a partir del trabajo realizado en el repositorio (`VirtualCorp-student`) sobre el direccionamiento de la **Delegación 8** (`10.8.0.0/16`), manteniendo la coherencia con las variables, plantillas y tareas de Terraform y Ansible (`bind_dns` y `kea_dhcp`), donde `dhcp01` corresponde a `.137` y `dns01` corresponde a `.138`.

## 2. Añadir un contenedor LXC a Terraform

Para desplegar `dns01` se reutiliza el proyecto Terraform existente en `infrastructure/terraform/proxmox`, compartiendo proveedor (`bpg/proxmox`), variables y estado (`terraform.tfstate`), sin duplicar directorios ni proveedores para el mismo entorno.

* **Configuración del contenedor LXC (`dns01`):**
  * ID de contenedor único en Proxmox y `hostname` establecido como `dns01`.
  * Plantilla base **Debian 13**, clave SSH de administración y recursos asignados de forma proporcionada al rol de servidor DNS.
  * Arranque automático (`onboot` / inicio automático) habilitado y conexión a la red privada (`privada`).
  * Configuración IPv4 por **DHCP**, sin IP estática ni *gateway* estático definidos directamente en el recurso.

* **Dirección MAC local, fija y conversión hexadecimal:**
  * Se asigna una MAC administrada localmente y fija en la interfaz (`02:00:00:00:00:89`, donde el bit *locally administered* está activo en `02`).
  * Conversión del último octeto: `137` en decimal equivale a `0x89` en hexadecimal (`137 = 8 * 16 + 9`).
  * Se verifica que la MAC elegida no colisiona con ninguna MAC real de las máquinas o interfaces del laboratorio.

* **Flujo de trabajo y control del plan:**
  ```bash
  cd infrastructure/terraform/proxmox
  terraform fmt -recursive
  terraform validate
  terraform plan
  terraform apply
  ```
  * Antes de aplicar se revisa `terraform plan` para confirmar que únicamente se crea `dns01` y que no se destruye ni recrea `dhcp01`.
  * Los contenedores gestionados por Terraform no se clonan manualmente en Proxmox ni se retiran del estado para corregir desviaciones de configuración.

## 2.1. Generar el inventario Ansible desde Terraform

Terraform genera de forma automatizada el inventario de servicios en `automation/ansible/inventories/proxmox_lxc.yml` a partir de los atributos de los recursos Proxmox (como `network_interface[0].mac_address`), evitando copiar MACs manualmente o editar el archivo a mano.

* **Proveedores y estructura `local.ansible_inventory`:**
  * Se utilizan los proveedores necesarios para gestionar los recursos en Proxmox y escribir el archivo local (`hashicorp/local` con `local_file`).
  * Se construye un bloque `locals` con el grupo `terraform_services` (bajo `proxmox_lxc.children`) y los grupos hijos correspondientes (`kea_dhcp`, `bind_dns`, etc.) para que los *playbooks* seleccionen los hosts sin cambios frágiles.
  * Para cada host se incluye su `hostname`, `vcorp_mac_address` (obtenida dinámicamente desde `network_interface[0].mac_address`) y `vcorp_network`.
  * `vcorp_ipv4_cidr` y `ansible_host` solo se incluyen cuando Terraform asigna una IP estática; para `dns01` no se fija IP en el recurso ni se inventa una dirección en el inventario generado, ya que su dirección se entrega vía reserva DHCP.

* **Asignación de IP para servicios DHCP (`terraform_service_ip_assignments`):**
  * En las variables de Ansible se define la lista `terraform_service_ip_assignments` asociando el `hostname` correspondiente con la IP prevista de la reserva DHCP (recordando que `dhcp01` es `.137` y `dns01` es `.138` en el despliegue de la Delegación 8, partiendo del esquema de referencia del enunciado con `10.1.0.137`).
  * El host de control Ansible puede resolver la IP de administración a partir de esta misma estructura sin poner IP estática en el LXC.

* **Verificación y control de versión:**
  * Tras cada `terraform plan` y `terraform apply`, se comprueba el inventario resultante con:
    ```bash
    ansible-inventory --graph
    ansible-inventory --host dns01
    ```
  * `automation/ansible/inventories/proxmox_lxc.yml` se trata como artefacto generado (ignorado en Git y nunca usado como respaldo del estado de Terraform).

## 2.2. Actualizar el rol DHCP de la actividad anterior

El rol `kea_dhcp` se adapta para consumir el inventario generado por Terraform en lugar de mantener las reservas de los contenedores LXC a mano:

* **Resolución de datos por host en `terraform_services`:**
  * Se leen los hosts de `terraform_services` y se obtienen `vcorp_mac_address` y `vcorp_network`.
  * Si el host define `vcorp_ipv4_cidr`, se extrae la dirección IP de ese CIDR; si no lo define (como ocurre en `dns01`), se busca su IP correspondiente en `terraform_service_ip_assignments`.

* **Validaciones y reserva en Kea:**
  * Se valida que cada servicio gestionado por Terraform tenga MAC, red y una única IP resuelta antes de renderizar la configuración.
  * Se generan las reservas en Kea para los servicios de Terraform (incluyendo `dhcp01` en `.137` y `dns01` en `.138`) dentro de su subred correspondiente y **fuera del rango dinámico (*pool*)**, manteniendo intactas las reservas estáticas existentes de servidores, impresoras y equipos de laboratorio.

* **Idempotencia y secuencia de arranque:**
  * La generación de reservas es idempotente: una segunda ejecución sin cambios no duplica entradas ni reinicia Kea innecesariamente.
  * Se verifica que la MAC fija de `dns01` recibe la IP reservada (`10.8.0.138`) y la conserva al renovar el *lease*, mientras `dhcp01` mantiene `10.8.0.137`.
  * La configuración de BIND9 sobre `dns01` se ejecuta una vez que el contenedor dispone de su *lease* DHCP activo y conectividad de red.

##  3. Investigar el diseño de BIND9

Siguiendo las recomendaciones del *BIND 9 Administrator Reference Manual* y la organización de paquetes en Debian, la configuración de BIND9 se estructura separando responsabilidades:

* **Separación de configuraciones y datos:**
  * **Opciones globales (`named.conf.options`):** escucha en interfaces (`127.0.0.1` y `10.8.0.138`), reenviadores (`forwarders`), políticas de recursión (`recursion`, `allow-query`, `allow-recursion`) y restricción de transferencias de zona.
  * **Declaración de zonas (`named.conf.local`):** registra las zonas autoritativas directas e inversas y enlaza cada una a su archivo de zona (`file`).
  * **Archivos de zona (`/etc/bind/zones/db.*`):** contienen los registros `SOA`, `NS`, `A` y `PTR` de cada zona.

* **Rol Ansible `bind_dns`:**
  * Instala los paquetes necesarios (`bind9`, `bind9-utils`, `bind9-dnsutils`).
  * Gestiona variables en `defaults/main.yml`, plantillas en `templates/`, tareas en `tasks/main.yml` y *handlers* (como recargar `named`).
  * Valida configuración y zonas antes de aplicar/recargar y asegura que el servicio `named` esté habilitado y activo sin impactar otros servicios.

##  4. Requisits de nombres y zones

BIND9 actúa como servidor autoritativo para las zonas de la **Delegación 8** manteniendo alineados el plan de direccionamiento, las reservas DHCP y los registros DNS:

* **`delegacion8.com`:** zona orientada a servicios publicados en la DMZ, incluyendo el registro de `websrv.delegacion8.com` (`10.8.0.197`).
* **`delegacion8.lan`:** zona interna principal con registros de los servidores de infraestructura y servicios de VirtualCorp (`dhcp01` en `10.8.0.137`, `dns01` en `10.8.0.138`, `dbsrv`, `infosrv`, `intrasrv`, `websrv`, `coresrv`, `streamingsrv`, etc.).
* **Subzonas por planta:**
  * `planta00.delegacion8.lan` (planta 00, incluyendo exposición, conserjería e impresora `printer.planta00.delegacion8.lan` / `printer0`).
  * `planta01.delegacion8.lan` (planta 01, con servicios web/datos, desarrollo e impresora `printer.planta01.delegacion8.lan` / `printer1`).
  * `planta02.delegacion8.lan` (planta 02, con servicios web/datos, desarrollo e impresora `printer.planta02.delegacion8.lan` / `printer2`).
  * `planta03.delegacion8.lan` (planta 03, incluyendo la red de **Dirección** —con equipos documentados como `directiu1`, `directiu2`, `directiu3`—, portátiles e impresora `printer.planta03.delegacion8.lan` / `printer3`).

* **Coherencia con DHCP y servicios fijos:** los servicios de infraestructura previos a DHCP mantienen sus direcciones asignadas y documentadas, mientras que `dns01` obtiene su IP asignada mediante la reserva Kea (`10.8.0.138`, con `dhcp01` en `10.8.0.137`) y cualquier cambio de reserva se refleja en los registros DNS correspondientes.

##  5. Seguridad y resolución externa

* **Transporte y alcance de consultas:**
  * BIND9 atiende consultas en el puerto `53` tanto por **UDP** como por **TCP** para los clientes internos de la Delegación 8.
  * Las consultas sobre dominios locales se responden de forma autoritativa desde las zonas configuradas en BIND9.

* **Reenvío externo y control de recursión:**
  * Las consultas de dominios externos se reenvían a `8.8.8.8` (`forwarders`).
  * La recursión se restringe exclusivamente a las redes internas de confianza (`bind_allowed_clients` / `allow-recursion`), evitando exponer un resolvedor abierto a Internet.

* **Hardening, validación y recarga:**
  * Se revisan reglas de cortafuegos, permisos de los archivos de zona (`root:bind`, `0644`), registros del sistema (`journalctl -u named`) y bloqueo de transferencias de zona no autorizadas (`allow-transfer { none; };`).
  * Se ajustan los parámetros `TTL` y `SOA` (`serial`, `refresh`, `retry`, `expire`, `negative TTL`) y se valida siempre la configuración y las zonas antes de recargar `named`.

##  6. Integración con DHCP y pruebas

* **Anuncio de DNS por DHCP:** Kea anuncia la dirección del servidor DNS (`dns01`, `10.8.0.138`) como servidor DNS a los clientes para que consulten a BIND9 en lugar de ir directamente a `8.8.8.8`; BIND9 es quien reenvía las consultas externas.

* **Validación y pruebas de resolución:**
  * Comprobación de sintaxis y zonas con las utilidades de BIND9 (`named-checkconf` y `named-checkzone`) antes de reiniciar o recargar el servicio.
  * Consultas con `dig` verificando registros `SOA`, `NS` y `A` en las zonas configuradas.
  * Pruebas desde segmentos/clientes resolviendo un servidor interno, la impresora de la planta correspondiente y el servidor web de la DMZ (`websrv`).
  * Prueba de resolución externa (por ejemplo `example.com`) confirmando la respuesta vía reenviador.

* **Reinicio y reejecución idempotente:**
  * Tras reiniciar el contenedor `dns01`, se comprueba que `named` arranca automáticamente y sigue respondiendo.
  * Al reejecutar Terraform y Ansible, se verifica qué cambios se detectan (o ausencia de cambios innecesarios cuando la configuración declarada ya coincide con el estado actual).

##  7. Ampliación añadida: DNS reverso (`PTR` / `in-addr.arpa`)

Como ampliación voluntaria sobre el requisito base, se añadió resolución inversa en `bind_dns` para traducir direcciones IPv4 de la Delegación 8 a su nombre canónico (`FQDN`):

* **Variables y zonas inversas (`bind_reverse_zones`):**
  * Se definieron las zonas inversas `0.8.10.in-addr.arpa`, `1.8.10.in-addr.arpa`, `2.8.10.in-addr.arpa` y `3.8.10.in-addr.arpa` con sus respectivos archivos de zona (`/etc/bind/zones/db.*.in-addr.arpa`) y registros `{ ptr, fqdn }` terminados en punto (`.`), incluyendo el mapeo de `10.8.0.137` (`dhcp01.delegacion8.lan.`) y `10.8.0.138` (`dns01.delegacion8.lan.`).

* **Plantilla unificada (`db.zone.j2`) y declaración de zonas:**
  * Se actualizó la plantilla de zonas de BIND9 para generar registros `IN PTR` y su registro `NS` en las zonas inversas (manteniendo la rama de registros `A` para las zonas directas), evitando duplicar la estructura de la plantilla y corrigiendo el error inicial de mezclar bloques con atributos distintos (`ptr`/`fqdn` frente a `name`/`type`/`value`).
  * Se añadieron las zonas inversas en la declaración de zonas de BIND9 y las tareas en `roles/bind_dns/tasks/main.yml` para desplegar los archivos y validarlos con `named-checkzone` (con comentarios explicativos en catalán en la plantilla y en las tareas).

* **Comprobación inversa:**
  * Se verificó la resolución inversa con `dig @10.8.0.138 -x <IP>` comprobando que devuelve el `FQDN` esperado.

##  8. Incidencia encontrada: desfase horario de 1 hora al hacer `make deploy_dns`

Durante las pruebas de `make deploy_dns` se detectó un **desfase horario de 1 hora** en el entorno/contenedor respecto a la hora local esperada:

* **Impacto observado:** las marcas de tiempo en registros/logs o comprobaciones de sincronización aparecían adelantadas o atrasadas 1 hora, lo que puede generar confusión al correlacionar eventos de despliegue, *leases* DHCP, consultas DNS o fechas de modificación de archivos de zona (`serial` / logs).

* **Causa habitual y revisión:** en contenedores LXC y máquinas del laboratorio, el desfase de 1 hora suele deberse a la zona horaria configurada (por ejemplo `UTC` frente a `Europe/Madrid` / `CET` / horario de invierno o verano) o a la sincronización horaria del host/contenedor.

* **Comprobación y resolución:**
  * Verificar la zona horaria y la hora del sistema tanto en el host de control como en `dns01` (`timedatectl` / `/etc/timezone` y `date`).
  * Ajustar la zona horaria correcta y asegurar la sincronización NTP/crony del sistema para que los *logs* de `named`, los *leases* de Kea y los despliegues de Ansible queden alineados en el tiempo.
