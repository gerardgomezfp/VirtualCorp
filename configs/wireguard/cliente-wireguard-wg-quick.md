# Conexión directa de cliente WireGuard (`wg-quick`)

Este documento es una alternativa/complemento rápido para levantar el túnel hacia **VirtualCorp** desde un equipo cliente que solo tiene instalado WireGuard (`wg` y `wg-quick`), sin depender de Ansible.

---

## 1. Qué necesitas antes de empezar

* Un equipo cliente con **WireGuard** (`wireguard-tools` / `wg-quick`) instalado.
* Un par de claves propio del cliente (**clave privada** y **clave pública**).
* La **clave pública** del servidor/router WireGuard (`mikrotik0`) registrada en la configuración del cliente.
* Que el servidor tenga dada de alta la **clave pública** de este cliente y su IP asignada dentro del rango de la VPN (por ejemplo `10.8.10.2/32`).

---

## 2. Generar las claves en el cliente (si aún no las tienes)

En el equipo cliente, genera su clave privada y deriva su clave pública:

```bash
wg genkey | tee client_private.key | wg pubkey > client_public.key
```

---

## 3. Preparar el archivo de configuración (`vcorp-client.conf`)

A partir del archivo y sustituye `<CLAVE_PRIVADA_DEL_CLIENTE>` por el contenido de `client_private.key`:

```ini
[Interface]
PrivateKey = <CLAVE_PRIVADA_DEL_CLIENTE>
Address = 10.8.10.2/32

[Peer]
PublicKey = AVPx3R28tZbC9Q+ftFePOMSbQ4fpLLOgwsw+RVFcpwY=
Endpoint = 127.0.0.1:51820
AllowedIPs = 10.8.0.0/25, 10.8.0.128/26, 10.8.0.192/27, 10.8.0.224/30, 10.8.1.0/24, 10.8.2.0/24, 10.8.3.0/25, 10.8.3.128/25, 10.8.10.0/24
PersistentKeepalive = 25
```

Aplica permisos restrictivos (`600`) para que solo el propietario pueda leer el archivo:

```bash
chmod 600 /ruta/a/vcorp-client.conf
```
---

## 4. Levantar y comprobar el túnel

Para abrir el túnel:

```bash
sudo wg-quick up /ruta/a/vcorp-client.conf
```

Comprueba que la interfaz está activa y hay *handshake*:

```bash
sudo wg show
```

Haz una prueba rápida de conectividad hacia una IP dentro del rango de la VPN (por ejemplo `10.8.10.1`):

```bash
ping -c 2 10.8.10.1
```

Para cerrar el túnel cuando termines:

```bash
sudo wg-quick down /ruta/a/vcorp-client.conf
```

---
