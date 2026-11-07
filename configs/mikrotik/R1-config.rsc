# 2026-11-07 16:02:30 by RouterOS 7.21.4
# system id = jsgjU4NZRjG
#
/interface ethernet
set [ find default-name=ether1 ] disable-running-check=no name=ether2
set [ find default-name=ether2 ] disable-running-check=no name=ether3
set [ find default-name=ether3 ] disable-running-check=no name=ether5
set [ find default-name=ether4 ] disable-running-check=no name=ether6
set [ find default-name=ether5 ] disable-running-check=no name=ether7
set [ find default-name=ether6 ] disable-running-check=no name=ether8
/routing rip instance
add name=rip1 redistribute=connected,rip
/ip address
add address=10.8.0.226/30 comment="Enlace R0-R1" interface=ether2 network=\
    10.8.0.224
add address=10.8.0.229/30 comment="Enlace R1-R2" interface=ether3 network=\
    10.8.0.228
/ip dhcp-client
# Interface not active
add interface=*2
/ip route
add dst-address=0.0.0.0/0 gateway=10.8.0.225
/routing rip interface-template
add instance=rip1 interfaces=ether2
add instance=rip1 interfaces=ether3
