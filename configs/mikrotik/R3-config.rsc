# 2026-10-26 13:25:29 by RouterOS 7.21.4
# system id = vD043zh4h+E
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
add address=10.1.3.1/25 interface=ether3 network=10.1.3.0
add address=10.1.3.129/25 interface=ether4 network=10.1.3.128
add address=10.8.0.234/30 comment="Enlace R2-R3" interface=ether2 network=\
    10.8.0.232
/ip dhcp-client
add interface=ether1
/ip route
add dst-address=10.8.0.224/30 gateway=10.8.0.233
add dst-address=10.8.0.228/30 gateway=10.8.0.233
/routing rip interface-template
add instance=rip1 interfaces=ether2
add instance=rip1 interfaces=ether3
add instance=rip1 interfaces=ether4
/system identity
set name=mikrotik3
