# 2026-11-19 08:24:55 by RouterOS 7.21.4
# system id = G+ec/NUdUPO
#
/interface ethernet
set [ find default-name=ether1 ] disable-running-check=no
set [ find default-name=ether2 ] disable-running-check=no
set [ find default-name=ether3 ] disable-running-check=no
set [ find default-name=ether4 ] disable-running-check=no
set [ find default-name=ether5 ] disable-running-check=no
set [ find default-name=ether6 ] disable-running-check=no
set [ find default-name=ether7 ] disable-running-check=no
set [ find default-name=ether8 ] disable-running-check=no
/interface wireguard
add listen-port=51820 mtu=1420 name=wg-vcorp
/routing rip instance
add name=rip1 redistribute=connected,rip
/interface wireguard peers
add allowed-address=10.8.10.2/32 comment=debian-client interface=wg-vcorp \
    name=peer1 public-key="HvtSX8q7rjUmuMtibQJitGRUKbCe4PK2LV1XIF3Ru04="
/ip address
add address=10.8.0.225/30 comment="Enlace R0-R1" interface=ether2 network=\
    10.8.0.224
add address=10.8.0.193/27 comment=DMZ interface=ether3 network=10.8.0.192
add address=10.8.0.129/26 comment="Xarxa privada" interface=ether4 network=\
    10.8.0.128
add address=10.8.0.1/25 comment="Planta baixa" interface=ether5 network=\
    10.8.0.0
add address=10.8.10.1/24 comment="WireGuard VirtualCorp" interface=wg-vcorp \
    network=10.8.10.0
/ip dhcp-client
add interface=ether1
/ip dhcp-relay
add dhcp-server=10.8.0.137 disabled=no interface=ether3 local-address=\
    10.8.0.193 name=vcorp-dmz
add dhcp-server=10.8.0.137 disabled=no interface=ether5 local-address=\
    10.8.0.1 name=vcorp-planta00
/ip firewall filter
add action=accept chain=input comment="WireGuard VPN input" dst-port=51820 \
    in-interface=ether1 protocol=udp
add action=accept chain=forward comment="WireGuard established" \
    connection-state=established,related
add action=accept chain=forward comment="WireGuard LAN planta baja" \
    dst-address=10.8.0.0/25 in-interface=wg-vcorp src-address=10.8.10.2
add action=accept chain=forward comment="WireGuard LAN red privada" \
    dst-address=10.8.0.128/26 in-interface=wg-vcorp src-address=10.8.10.2
add action=accept chain=forward comment="WireGuard LAN DMZ" dst-address=\
    10.8.0.192/27 in-interface=wg-vcorp src-address=10.8.10.2
add action=accept chain=forward comment="WireGuard LAN enlace R0-R1" \
    dst-address=10.8.0.224/30 in-interface=wg-vcorp src-address=10.8.10.2
add action=accept chain=forward comment="WireGuard LAN planta 1" dst-address=\
    10.8.1.0/24 in-interface=wg-vcorp src-address=10.8.10.2
add action=accept chain=forward comment="WireGuard LAN planta 2" dst-address=\
    10.8.2.0/24 in-interface=wg-vcorp src-address=10.8.10.2
add action=accept chain=forward comment="WireGuard LAN planta 3" dst-address=\
    10.8.3.0/25 in-interface=wg-vcorp src-address=10.8.10.2
add action=accept chain=forward comment="WireGuard LAN direccion" \
    dst-address=10.8.3.128/25 in-interface=wg-vcorp src-address=10.8.10.2
add action=drop chain=forward comment="WireGuard VPN deny other" \
    in-interface=wg-vcorp src-address=10.8.10.2
/ip firewall nat
add action=masquerade chain=srcnat out-interface=ether1
/routing rip interface-template
add disabled=no instance=rip1 interfaces=ether2
/tool sniffer
set filter-interface=ether5 memory-limit=1000KiB
