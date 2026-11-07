# 2026-11-07 16:02:54 by RouterOS 7.21.4
# system id = vD043zh4h+E
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
add address=10.8.3.1/25 interface=ether3 network=10.8.3.0
add address=10.8.3.129/25 interface=ether4 network=10.8.3.128
add address=10.8.0.234/30 comment="Enlace R2-R3" interface=ether2 network=\
    10.8.0.232
/ip dhcp-client
# Interface not active
add interface=*2
/ip route
add dst-address=0.0.0.0/0 gateway=10.8.0.233
/routing rip interface-template
add instance=rip1 interfaces=ether2
/system identity
set name=mikrotik3
