# 2026-11-07 16:02:05 by RouterOS 7.21.4
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
/routing rip instance
add name=rip1 redistribute=connected,rip
/ip address
add address=10.8.0.225/30 comment="Enlace R0-R1" interface=ether2 network=\
    10.8.0.224
add address=10.8.0.193/27 comment=DMZ interface=ether3 network=10.8.0.192
add address=10.8.0.129/26 comment="Xarxa privada" interface=ether4 network=\
    10.8.0.128
add address=10.8.0.1/25 comment="Planta baixa" interface=ether5 network=\
    10.8.0.0
/ip dhcp-client
add interface=ether1
/routing rip interface-template
add disabled=no instance=rip1 interfaces=ether2
