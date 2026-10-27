# 2026-10-26 13:23:10 by RouterOS 7.21.4
# system id = IIH09h/lJpC
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
/ip address
add address=10.8.0.230/30 comment="Enlace R1-R2" interface=ether2 network=\
    10.8.0.228
add address=10.8.0.233/30 comment="Enlace R2-R3" interface=ether3 network=\
    10.8.0.232
/ip dhcp-client
add interface=ether1
/ip route
add dst-address=10.8.0.224/30 gateway=10.8.0.229
add dst-address=10.8.3.0/25 gateway=10.8.0.234
add dst-address=10.8.3.128/25 gateway=10.8.0.234
