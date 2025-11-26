#!/bin/bash
set -euo pipefail

VPN_SUBNET_V4="10.9.0.0/24"
VPN_SUBNET_V6="fd42:42:42:42::/64"
VPN_PORT="1194"
VPN_PROTO="udp"
VPN_IFACE="tun0"
DOCKER_SUBNET_V4="172.17.0.0/16"
WAN_IFACE=$(ip route | grep '^default' | awk '{print $5}')

echo "[*] Detected WAN interface: $WAN_IFACE"

apt-get purge -y ufw
rm -rf /etc/ufw
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent netfilter-persistent

sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1
grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
grep -q "net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf || echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
sysctl -p

iptables -F; iptables -X; iptables -t nat -F; iptables -t nat -X
ip6tables -F; ip6tables -X; ip6tables -t nat -F; ip6tables -t nat -X

iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT ACCEPT

# NAT
iptables -t nat -A POSTROUTING -s $VPN_SUBNET_V4 -o $WAN_IFACE -j MASQUERADE
iptables -t nat -A POSTROUTING -s $DOCKER_SUBNET_V4 -o $WAN_IFACE -j MASQUERADE
ip6tables -t nat -A POSTROUTING -s $VPN_SUBNET_V6 -o $WAN_IFACE -j MASQUERADE

# VPN forwarding
iptables -A FORWARD -i $VPN_IFACE -o $WAN_IFACE -j ACCEPT
iptables -A FORWARD -i $WAN_IFACE -o $VPN_IFACE -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Inbound ports
iptables -A INPUT -i $WAN_IFACE -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -i $WAN_IFACE -p $VPN_PROTO --dport $VPN_PORT -j ACCEPT
iptables -A INPUT -i $WAN_IFACE -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -i $WAN_IFACE -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -i $WAN_IFACE -p tcp --dport 2222 -j ACCEPT

# DNAT for 2222 → 10.9.0.99:22
iptables -t nat -A PREROUTING -i $WAN_IFACE -p tcp --dport 2222 -j DNAT --to-destination 10.9.0.99:22
iptables -A FORWARD -p tcp -d 10.9.0.99 --dport 22 -j ACCEPT

# Established + localhost
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

netfilter-persistent save
echo "[✓] iptables firewall setup complete (VPN, Docker, nginx, host connectivity, 2222 DNAT)."
