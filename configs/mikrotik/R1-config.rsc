# 2026-10-22 20:06:06 by RouterOS 7.21.4
# system id = jsgjU4NZRjG
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
add address=10.8.0.226/30 comment="Enlace R0-R1" interface=ether2 network=\
    10.8.0.224
add address=10.8.0.229/30 comment="Enlace R1-R2" interface=ether3 network=\
    10.8.0.228
/ip dhcp-client
add interface=ether1
/ip route
add dst-address=10.8.0.232/30 gateway=10.8.0.230
add dst-address=10.1.3.0/25 gateway=10.8.0.230
add dst-address=10.1.3.128/25 gateway=10.8.0.230
