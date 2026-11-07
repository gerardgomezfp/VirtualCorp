# 2026-11-07 16:02:40 by RouterOS 7.21.4
# system id = IIH09h/lJpC
#
/interface ethernet
set [ find default-name=ether1 ] disable-running-check=no name=ether2
set [ find default-name=ether2 ] disable-running-check=no name=ether3
set [ find default-name=ether3 ] disable-running-check=no name=ether4
set [ find default-name=ether4 ] disable-running-check=no name=ether5
set [ find default-name=ether5 ] disable-running-check=no name=ether6
set [ find default-name=ether6 ] disable-running-check=no name=ether7
set [ find default-name=ether7 ] disable-running-check=no name=ether8
/routing rip instance
add name=rip1 redistribute=connected,rip
/ip address
add address=10.8.0.230/30 comment="Enlace R1-R2" interface=ether2 network=\
    10.8.0.228
add address=10.8.0.233/30 comment="Enlace R2-R3" interface=ether3 network=\
    10.8.0.232
add address=10.8.1.1/24 comment="Planta 1" interface=ether4 network=10.8.1.0
add address=10.8.2.1/24 comment="Planta 2" interface=ether5 network=10.8.2.0
/ip dhcp-client
# Interface not active
add interface=*2
/ip route
add dst-address=0.0.0.0/0 gateway=10.8.0.229
/routing rip interface-template
add instance=rip1 interfaces=ether2
add instance=rip1 interfaces=ether3
