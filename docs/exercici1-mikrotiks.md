
# Documento técnico del despliegue de la infraestructura de VCORP

**Alumno:** Gerard Gómez  
**Curso:** ASIX2 26-27

## Índice

1. [Revisión del diseño de red](#1-revisión-del-diseño-de-red)
2. [Copia y publicación del repositorio](#2-copia-y-publicación-del-repositorio)
   1. [Subida del repositorio a GitHub](#21-subida-del-repositorio-a-github)
3. [Configuración del entorno de VCORP](#3-configuración-del-entorno-de-vcorp)
4. [Conexión de los cuatro routers MikroTik y pruebas](#4-conexión-de-los-cuatro-routers-mikrotik-y-pruebas)
   1. [Conexión inicial por SSH](#41-conexión-inicial-por-ssh)
   2. [Enlace entre R0 y R1](#42-enlace-entre-r0-y-r1)
   3. [Enlace entre R1 y R2](#43-enlace-entre-r1-y-r2)
   4. [Enlace entre R2 y R3](#44-enlace-entre-r2-y-r3)
   5. [Enrutamiento estático de extremo a extremo](#45-enrutamiento-estático-de-extremo-a-extremo)
   6. [Exportación de configuraciones](#46-exportación-de-configuraciones)
   7. [Persistencia de la configuración](#47-persistencia-de-la-configuración)

---

## 1. Revisión del diseño de red

La red que se utilizará en el proyecto VCORP corresponde a mi delegación, **10.8.0.0/16**. Los routers y el resto de dispositivos se adaptarán a esta red.

### 1.1. Direcciones IP y máscaras de las delegaciones

La red asignada para este ejercicio es `10.8.0.0/16`.

#### Enlaces entre routers

| Enlace | Red |
|---|---|
| Router 0 -- Router 1 | `10.8.0.224/30` |
| Router 1 -- Router 2 | `10.8.0.228/30` |
| Router 2 -- Router 3 | `10.8.0.232/30` |

#### Redes de las plantas

| Planta | Red | Uso |
|---|---|---|
| Planta baja | `10.8.0.0/24` | CPD, DMZ, conserjería y expositores |
| Planta 1 | `10.8.1.0/24` | Equipos de desarrollo y proyectos |
| Planta 2 | `10.8.2.0/24` | Equipos de desarrollo y proyectos |
| Planta 3 | `10.8.3.0/24` | Departamentos corporativos y dirección |

#### Segmentación de la planta baja

| Zona | Red | Uso |
|---|---|---|
| Zona general de planta baja | `10.8.0.0/25` | Conserjería, expositores y otros equipos |
| Zona privada | `10.8.0.128/26` | Servicios internos y equipos protegidos |
| DMZ | `10.8.0.192/27` | Servicios expuestos a Internet |

#### Direcciones de servidores

| Hostname | Descripción | Dirección IP |
|---|---|---|
| `pve01` | Nodo principal de la infraestructura Proxmox | `10.8.0.133` |
| `dbsrv` | Servidor de bases de datos | `10.8.0.134` |
| `infosrv` | Servidor documental y de archivos corporativos | `10.8.0.135` |
| `websrv` | Servidor web público | `10.8.0.197` |

#### Expositores de la planta baja

| Dispositivo | Dirección IP |
|---|---|
| `expo1` | `10.8.0.33` |
| `expo2` | `10.8.0.34` |
| `expo3` | `10.8.0.35` |
| `expo4` | `10.8.0.36` |

## 2. Copia y publicación del repositorio

Después de crear el par de claves SSH y añadir la clave pública a GitHub, hice una prueba de conexión.

### 2.1. Subida del repositorio a GitHub

Subí el proyecto a mi repositorio personal con los siguientes comandos:

```bash
git remote rename origin upstream
git remote add origin git@github.com:gerardgomezfp/VirtualCorp.git
git push -u origin main
```

Con estos comandos, el repositorio quedó publicado en GitHub.

## 3. Configuración del entorno de VCORP

Después de leer la documentación, copié el archivo de ejemplo `.env.example` al archivo `.env` y lo edité con `vim`:

```bash
cp .env.example .env
sudo vim .env
```

A continuación, ejecuté el objetivo `make ssh-keys`:

```bash
make ssh-keys
```

La salida mostró que el script detectó que no había secretos en el repositorio, pero después informó de un error al copiar la clave pública porque el origen y el destino eran el mismo archivo:

```text
[INFO] Comprovant que no hi ha claus privades al repositori...
[ OK ] No s'han detectat secrets al repositori.
[INFO] Generant clau 'vcorp_auditor'...
cp: '/home/gerard/.ssh/vcorp_auditor.pub' y '/home/gerard/.ssh/vcorp_auditor.pub' son el mismo fichero
make: *** [Makefile:39: ssh-keys] Error 1
```

Después ejecuté el despliegue de los routers:

```bash
make deploy-routers
```

El script indicó que `mikrotik0`, `mikrotik1` y `mikrotik2` ya existían, por lo que omitió su despliegue. A continuación, creó y configuró `mikrotik3`.

Resumen de la salida:

```text
[WARN] El router 'mikrotik0' ja existeix. S'omet el desplegament.
[WARN] El router 'mikrotik1' ja existeix. S'omet el desplegament.
[WARN] El router 'mikrotik2' ja existeix. S'omet el desplegament.
[INFO] ==========================================
[INFO] Desplegant router: mikrotik3
[INFO] ==========================================
[INFO] Creant VM 'mikrotik3'
Virtual machine 'mikrotik3' is created and registered.
[INFO] Configurant 8 interfícies de xarxa
[INFO] Configurant NAT temporal per SSH: localhost:2203 → RouterOS:22
[INFO] Arrencant 'mikrotik3' per fer el bootstrap
[INFO] Esperant SSH de RouterOS a 127.0.0.1:2203
[INFO] SSH disponible a 127.0.0.1:2203!
[INFO] Configurant usuari sysadmin
[INFO] Injectant clau SSH de sysadmin
[ OK ] Bootstrap de 'mikrotik3' completat
[INFO] Generant configuració RouterOS mikrotik3
[INFO] Pujant configuració RSC a 'mikrotik3'
Script file loaded and executed successfully
[ OK ] Configuració RouterOS aplicada
[INFO] Apagant 'mikrotik3'
[INFO] Esperant que 'mikrotik3' s'apagui...
[INFO] NIC1 → xarxa interna definitiva 'r2-r3'
[ OK ] Router 'mikrotik3' creat i configurat correctament.
[INFO] ==========================================
[INFO] [+] Routers desplegats correctament.
[INFO] ==========================================
```

Además, en los archivos de configuración del proyecto adapté las direcciones IP a las de mi delegación (`10.8.0.0/16`) y añadí al proceso de despliegue la importación de la clave pública del auditor `configs/ssh/vcorp_auditor.pub`. De esta forma, el despliegue incorpora la clave pública del profesor en los routers junto con la clave de `sysadmin`.

También añadí la clave del profesor manualmente en cada MikroTik con el siguiente comando RouterOS:

```routeros
/user/ssh-keys/add user=sysadmin key="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK313FBREF929KceJ7V98F8Hwywf+dgXuXtiCkuCMMSe vcorp_auditor@virtualcorp"
```

La clave se asocia al usuario `sysadmin` y permite al profesor acceder con su clave pública de auditoría.

Con esto, los cuatro routers MikroTik quedaron instalados en Debian/VirtualBox.

### Modificaciones realizadas en `router-base.sh`

Se ha ampliado el archivo `router-base.sh` para incorporar un proceso automatizado de instalación de las claves públicas SSH.

Este proceso se ejecuta durante la configuración de cada router y consta de dos fases principales: la copia de los archivos de clave pública y su posterior importación en RouterOS.

#### 1. Copia de las claves públicas

En primer lugar, el script muestra un mensaje informativo para indicar que comienza la instalación de las claves:

```bash
log_info "Injectant clau SSH de sysadmin"
```

A continuación, utiliza `scp` para transferir las dos claves públicas al router.

La clave del administrador se copia desde la ruta definida por la variable `$SSH_PUBLIC_KEY_DIR` y se guarda en el router con el nombre `sysadmin.pub`:

```bash
scp \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -P "$ssh_port" \
    "$SSH_PUBLIC_KEY_DIR/vcorp_sysadmin.pub" \
    admin@127.0.0.1:sysadmin.pub \
    || return 1
```

Posteriormente, se copia la clave pública del profesor, utilizando la ruta definida por la variable `$AUDIT_PUB_KEY_FILE`. El archivo se guarda en el router con el nombre `vcorp_auditor.pub`:

```bash
scp \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -P "$ssh_port" \
    "$AUDIT_PUB_KEY_FILE" \
    admin@127.0.0.1:vcorp_auditor.pub \
    || return 1
```

La conexión se realiza a través de `127.0.0.1`, utilizando el puerto SSH indicado por la variable `$ssh_port` y el usuario `admin` para efectuar la transferencia inicial.

Las opciones `StrictHostKeyChecking=no` y `UserKnownHostsFile=/dev/null` desactivan la comprobación habitual de la clave del servidor y evitan que esta se almacene en el archivo de hosts conocidos. El puerto se define mediante `$ssh_port`, lo que permite adaptar la conexión al puerto correspondiente a cada router.


## 4. Conexión de los cuatro routers MikroTik y pruebas

Primero comprobé que los cuatro routers MikroTik aparecieran en VirtualBox. Después comencé a configurar los enlaces entre ellos y a probar la conectividad.

### 4.1. Conexión inicial por SSH

Me conecté a los dos primeros routers por SSH desde la terminal, sin necesidad de abrir la consola de VirtualBox:

```bash
ssh -p 2200 -o IdentitiesOnly=yes -i ~/.ssh/vcorp_sysadmin sysadmin@localhost

ssh -p 2201 -o IdentitiesOnly=yes -i ~/.ssh/vcorp_sysadmin sysadmin@localhost

```

Al consultar las direcciones IP en ambos routers con `/ip address print`, los dos mostraban inicialmente una dirección dinámica `10.0.2.15/24` en `ether1`:

```text
Flags: D - DYNAMIC
Columns: ADDRESS, NETWORK, INTERFACE, VRF
#   ADDRESS       NETWORK   INTERFACE  VRF
0 D 10.0.2.15/24  10.0.2.0  ether1     main
```

Por tanto, ambos mostraban inicialmente la misma dirección en la interfaz `ether1`. Para configurar los enlaces internos, asigné direcciones de la red `10.8.0.0/16` según el diseño.

### 4.2. Enlace entre R0 y R1

Para configurar el enlace entre el router 0 y el router 1, utilicé la red `10.8.0.224/30`.

En `mikrotik0`:

```routeros
/ip address add address=10.8.0.225/30 interface=ether2 comment="Enlace R0-R1"
```

En `mikrotik1`:

```routeros
/ip address add address=10.8.0.226/30 interface=ether2 comment="Enlace R0-R1"
```

Si se añade una dirección por error, se puede consultar la lista y eliminar la entrada correspondiente. En mi ejemplo utilicé:

```routeros
/ip address remove 1
/ip address print
```

La salida de `mikrotik1` mostraba la dirección `10.8.0.226/30` en `ether2`, dentro de la red `10.8.0.224/30`.

#### Prueba de conectividad de R0 a R1

Desde `mikrotik0` ejecuté:

```routeros
/ping 10.8.0.226 count=4
```

Resultado:

```text
sent=4 received=4 packet-loss=0%
min-rtt=452us avg-rtt=849us max-rtt=1ms346us
```

También hice la prueba en sentido contrario, desde R1 hacia R0:

```routeros
/ping 10.8.0.225 count=4
```

Resultado:

```text
sent=4 received=4 packet-loss=0%
min-rtt=688us avg-rtt=737us max-rtt=822us
```

Las pruebas tuvieron un 0 % de pérdida de paquetes en ambos sentidos, por lo que el enlace entre R0 y R1 respondía correctamente.

### 4.3. Enlace entre R1 y R2

Una vez comprobado el enlace entre R0 y R1, configuré el enlace entre R1 y R2 utilizando la red `10.8.0.228/30`.

En `mikrotik1`:

```routeros
/ip address add address=10.8.0.229/30 interface=ether3 comment="Enlace R1-R2"
/ip address print
```

En `mikrotik2`:

```routeros
/ip address add address=10.8.0.230/30 interface=ether2 comment="Enlace R1-R2"
/ip address print
```

La interfaz del enlace en R1 es `ether3`, mientras que en R2 es `ether2`. Las direcciones asignadas fueron `10.8.0.229/30` y `10.8.0.230/30`, respectivamente.

#### Prueba de conectividad de R1 a R2

Desde R1:

```routeros
/ping 10.8.0.230 count=4
```

Resultado:

```text
sent=4 received=4 packet-loss=0%
min-rtt=449us avg-rtt=613us max-rtt=1ms86us
```

Desde R2 hacia R1:

```routeros
/ping 10.8.0.229 count=4
```

Resultado:

```text
sent=4 received=4 packet-loss=0%
min-rtt=428us avg-rtt=583us max-rtt=803us
```

Ambas pruebas tuvieron un 0 % de pérdida de paquetes.

### 4.4. Enlace entre R2 y R3

Al configurar el enlace entre R2 y R3, encontré un problema con las redes internas de R3: aparecían dos redes asociadas a `R2-R3` cuando solo debía haber una. Como no había reenvío de puertos disponible para la conexión SSH que necesitaba, configuré manualmente NAT para poder conectarme.

En una consulta inicial de R3 con `/ip address print` aparecían estas direcciones:

```text
0   10.1.0.234/30  10.1.0.232  ether2  main
1   10.1.3.1/25    10.1.3.0    ether3  main
2   10.1.3.129/25  10.1.3.128  ether4  main
3 D 10.0.2.15/24   10.0.2.0    ether1  main
```

Para acceder por SSH a R3 utilicé el puerto `2203` y especifiqué la clave privada correspondiente:

```bash
ssh -p 2203 -o IdentitiesOnly=yes -i ~/.ssh/vcorp_sysadmin sysadmin@localhost
```

Utilicé ese puerto para evitar solapamientos con los puertos de los otros routers.

En `mikrotik2` configuré la dirección del enlace en `ether3`:

```routeros
/ip address add address=10.8.0.233/30 interface=ether3 comment="Enlace R2-R3"
/ip address print
```

En `mikrotik3` configuré la dirección del enlace en `ether2`:

```routeros
/ip address add address=10.8.0.234/30 interface=ether2 comment="Enlace R2-R3"
/ip address print
```

La dirección final añadida para R3 fue `10.8.0.234/30`, dentro de la red `10.8.0.232/30`.

#### Prueba de conectividad de R2 a R3

Desde R2:

```routeros
/ping 10.8.0.234 count=4
```

Resultado:

```text
sent=4 received=4 packet-loss=0%
min-rtt=469us avg-rtt=586us max-rtt=834us
```

Desde R3 hacia R2:

```routeros
/ping 10.8.0.233 count=4
```

Resultado:

```text
sent=4 received=4 packet-loss=0%
min-rtt=461us avg-rtt=597us max-rtt=886us
```

Ambas pruebas tuvieron un 0 % de pérdida de paquetes, por lo que el enlace directo entre R2 y R3 respondía correctamente.



### 4.5. Enrutamiento estático de extremo a extremo

Para permitir la comunicación entre redes que no están conectadas directamente a cada router, se configuraron rutas estáticas mediante el comando `/ip route add` de RouterOS.

Cada ruta especifica la red de destino (`dst-address`) y la dirección IP del siguiente salto (`gateway`). La configuración se verificó mediante `/ip route print` en los cuatro routers.

#### R0 — Router 0

R0 utiliza R1 (`10.8.0.226`) como siguiente salto para alcanzar las redes remotas.

**Rutas estáticas configuradas:**

```routeros
/ip route add dst-address=10.8.0.228/30 gateway=10.8.0.226
/ip route add dst-address=10.8.0.232/30 gateway=10.8.0.226
/ip route add dst-address=10.1.3.0/25 gateway=10.8.0.226
/ip route add dst-address=10.1.3.128/25 gateway=10.8.0.226
```

Las cuatro rutas aparecen activas (`As`) en la tabla de enrutamiento.

| Red de destino | Siguiente salto |
|---|---|
| `10.8.0.228/30` | `10.8.0.226` |
| `10.8.0.232/30` | `10.8.0.226` |
| `10.1.3.0/25` | `10.8.0.226` |
| `10.1.3.128/25` | `10.8.0.226` |

La red `10.8.0.224/30` aparece como conectada directamente a través de `ether2`.

#### R1 — Router 1

R1 utiliza R2 (`10.8.0.230`) como siguiente salto para alcanzar el enlace R2–R3 y las dos redes conectadas a R3.

**Rutas estáticas configuradas:**

```routeros
/ip route add dst-address=10.8.0.232/30 gateway=10.8.0.230
/ip route add dst-address=10.1.3.0/25 gateway=10.8.0.230
/ip route add dst-address=10.1.3.128/25 gateway=10.8.0.230
```

Las tres rutas aparecen activas (`As`).

| Red de destino | Siguiente salto |
|---|---|
| `10.8.0.232/30` | `10.8.0.230` |
| `10.1.3.0/25` | `10.8.0.230` |
| `10.1.3.128/25` | `10.8.0.230` |

Los enlaces `10.8.0.224/30` y `10.8.0.228/30` aparecen como conectados directamente mediante `ether2` y `ether3`, respectivamente.

#### R2 — Router 2

R2 utiliza R1 (`10.8.0.229`) para alcanzar la red del enlace R0–R1 y R3 (`10.8.0.234`) para alcanzar las dos redes conectadas a este último.

**Rutas estáticas configuradas:**

```routeros
/ip route add dst-address=10.8.0.224/30 gateway=10.8.0.229
/ip route add dst-address=10.1.3.0/25 gateway=10.8.0.234
/ip route add dst-address=10.1.3.128/25 gateway=10.8.0.234
```

Las tres rutas aparecen activas (`As`).

| Red de destino | Siguiente salto |
|---|---|
| `10.8.0.224/30` | `10.8.0.229` |
| `10.1.3.0/25` | `10.8.0.234` |
| `10.1.3.128/25` | `10.8.0.234` |

Los enlaces `10.8.0.228/30` y `10.8.0.232/30` aparecen como conectados directamente mediante `ether2` y `ether3`, respectivamente.

#### R3 — Router 3

R3 utiliza R2 (`10.8.0.233`) como siguiente salto para alcanzar los enlaces R0–R1 y R1–R2.

**Rutas estáticas configuradas:**

```routeros
/ip route add dst-address=10.8.0.224/30 gateway=10.8.0.233
/ip route add dst-address=10.8.0.228/30 gateway=10.8.0.233
```

Las dos rutas aparecen activas (`As`).

| Red de destino | Siguiente salto |
|---|---|
| `10.8.0.224/30` | `10.8.0.233` |
| `10.8.0.228/30` | `10.8.0.233` |

Las redes `10.1.3.0/25` y `10.1.3.128/25` están conectadas directamente a R3 mediante `ether3` y `ether4`. Por este motivo, no necesitan rutas estáticas adicionales en R3. El enlace `10.8.0.232/30` también aparece como conectado directamente a través de `ether2`.

#### 4.5.1. Resumen global de rutas estáticas

| Router | Red de destino | Siguiente salto |
|---|---|---|
| R0 | `10.8.0.228/30` | `10.8.0.226` |
| R0 | `10.8.0.232/30` | `10.8.0.226` |
| R0 | `10.1.3.0/25` | `10.8.0.226` |
| R0 | `10.1.3.128/25` | `10.8.0.226` |
| R1 | `10.8.0.232/30` | `10.8.0.230` |
| R1 | `10.1.3.0/25` | `10.8.0.230` |
| R1 | `10.1.3.128/25` | `10.8.0.230` |
| R2 | `10.8.0.224/30` | `10.8.0.229` |
| R2 | `10.1.3.0/25` | `10.8.0.234` |
| R2 | `10.1.3.128/25` | `10.8.0.234` |
| R3 | `10.8.0.224/30` | `10.8.0.233` |
| R3 | `10.8.0.228/30` | `10.8.0.233` |

#### 4.5.2. Ruta por defecto y redes conectadas

En los cuatro routers se observa la siguiente ruta por defecto:

- **Destino:** `0.0.0.0/0`
- **Siguiente salto:** `10.0.2.2`
- **Origen:** DHCP
- **Estado:** dinámica y activa (`DAd`)

También aparece la red `10.0.2.0/24`, conectada directamente mediante `ether1` (`DAc`). Esta interfaz dispone de la dirección dinámica `10.0.2.15/24` en los cuatro routers.

La ruta por defecto permite enviar tráfico hacia destinos que no coinciden con rutas más específicas. Su funcionamiento se comprobó mediante las pruebas de conectividad exterior descritas a continuación.

### 4.6. Pruebas de conectividad y acceso a Internet

Para verificar la conectividad exterior de los cuatro routers MikroTik, se realizaron pruebas de ping a dos direcciones IP públicas (`8.8.8.8` y `1.1.1.1`) y a un nombre de dominio (`google.com`).

Cada prueba se ejecutó con cuatro paquetes mediante el comando `/ping`.

#### 4.6.1. Resultados de las pruebas

| Router | Destino | Paquetes recibidos | Pérdida de paquetes | RTT medio |
|---|---|---:|---:|---:|
| R0 | `8.8.8.8` | 4/4 | 0 % | 18,651 ms |
| R0 | `1.1.1.1` | 4/4 | 0 % | 36,317 ms |
| R0 | `google.com` | 4/4 | 0 % | 88,963 ms |
| R1 | `8.8.8.8` | 4/4 | 0 % | 17,577 ms |
| R1 | `1.1.1.1` | 4/4 | 0 % | 15,724 ms |
| R1 | `google.com` | 4/4 | 0 % | 17,773 ms |
| R2 | `8.8.8.8` | 4/4 | 0 % | 19,457 ms |
| R2 | `1.1.1.1` | 4/4 | 0 % | 17,189 ms |
| R2 | `google.com` | 4/4 | 0 % | 24,533 ms |
| R3 | `8.8.8.8` | 4/4 | 0 % | 18,214 ms |
| R3 | `1.1.1.1` | 4/4 | 0 % | 19,177 ms |
| R3 | `google.com` | 4/4 | 0 % | 19,093 ms |

Los tiempos corresponden al RTT medio (`avg-rtt`) mostrado por RouterOS. Pueden variar según el destino y las condiciones de la red durante cada prueba.

#### 4.6.2. Comprobación de conectividad IP

Desde cada router se enviaron cuatro paquetes ICMP a las direcciones públicas `8.8.8.8` y `1.1.1.1`.

En todos los casos se recibieron los cuatro paquetes enviados, con un resultado del 0 % de pérdida.

Estos resultados confirman que los cuatro routers podían alcanzar ambas direcciones IP públicas durante las pruebas.

#### 4.6.3. Comprobación de DNS

También se ejecutó el comando `/ping google.com count=4` desde cada router.

En las cuatro pruebas se resolvió el nombre de dominio a una dirección IP y se recibieron los cuatro paquetes enviados.

| Router | Dirección IP resuelta para `google.com` | Resultado |
|---|---|---|
| R0 | `108.177.15.139` | 4/4 recibidos |
| R1 | `172.217.20.238` | 4/4 recibidos |
| R2 | `172.217.20.238` | 4/4 recibidos |
| R3 | `216.58.206.14` | 4/4 recibidos |

Las direcciones resueltas pueden variar según la infraestructura de Google y la selección de servidores. Las pruebas confirman que la resolución de nombres funcionó en el momento de la comprobación.

#### 4.6.4. Conclusión de las pruebas

Los resultados obtenidos permiten concluir que, durante las pruebas realizadas:

- Los cuatro routers tenían conectividad hacia las dos direcciones IP públicas comprobadas.
- Los cuatro routers podían resolver el nombre de dominio `google.com`.
- No se observó pérdida de paquetes en ninguna de las doce pruebas.
- La ruta por defecto hacia `10.0.2.2` aparecía activa en los cuatro routers.

Por tanto, las pruebas de conectividad exterior y resolución DNS finalizaron satisfactoriamente en R0, R1, R2 y R3.


### 4.7. Persistencia de la configuración

Para comprobar que la configuración se mantenía tras reiniciar cada router, primero consulté las direcciones IP y las interfaces:

```routeros
/ip address print
/interface print
```

Después reinicié el router:

```routeros
/system reboot
```

Una vez que volvió a arrancar, comprobé de nuevo la configuración. Entre las consultas realizadas estaban las direcciones IP, las rutas y las claves SSH:

```routeros
/ip address print
/ip route print
/user ssh-keys print
```

La comprobación posterior al reinicio permitió verificar que se conservaban las direcciones configuradas, las rutas estáticas y las claves SSH instaladas. Repetí el procedimiento para cada uno de los cuatro routers.

---

## Conclusión

En este ejercicio revisé el diseño de direccionamiento de la delegación VCORP, publiqué el repositorio en GitHub, preparé el entorno de trabajo y desplegué los cuatro routers MikroTik. Después configuré los enlaces directos R0--R1, R1--R2 y R2--R3 y comprobé su conectividad mediante `ping`, obteniendo un 0 % de pérdida de paquetes en las pruebas documentadas.

La configuración incluyó las claves SSH de administración y auditoría, las rutas estáticas para alcanzar redes remotas y las comprobaciones de persistencia después de reiniciar los cuatro routers. Para dejar el informe aún más completo, se pueden adjuntar las salidas o capturas de las pruebas `ping` de extremo a extremo y de las tablas de rutas después del reinicio.
