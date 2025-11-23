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

echo "🛑 Removing UFW..."
apt-get purge -y ufw
rm -rf /etc/ufw

echo "🛡️ Installing iptables-persistent..."
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent netfilter-persistent

echo "🔧 Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1
grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
grep -q "net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf || echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
sysctl -p

echo "🌐 Flushing old rules..."
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
ip6tables -F
ip6tables -X
ip6tables -t nat -F
ip6tables -t nat -X

echo "🌐 Setting up NAT for VPN + Docker..."
iptables -t nat -A POSTROUTING -s $VPN_SUBNET_V4 -o $WAN_IFACE -j MASQUERADE
iptables -t nat -A POSTROUTING -s $DOCKER_SUBNET_V4 -o $WAN_IFACE -j MASQUERADE
ip6tables -t nat -A POSTROUTING -s $VPN_SUBNET_V6 -o $WAN_IFACE -j MASQUERADE

echo "🔓 Allowing inbound SSH + VPN..."
iptables -A INPUT -i $WAN_IFACE -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -i $WAN_IFACE -p $VPN_PROTO --dport $VPN_PORT -j ACCEPT

echo "🔓 Allowing established/related traffic..."
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

echo "🔓 Allowing localhost..."
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

echo "🔓 Allowing nginx/webserver on port 80 + 443..."
iptables -A INPUT -i $WAN_IFACE -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -i $WAN_IFACE -p tcp --dport 443 -j ACCEPT

echo "💾 Saving rules..."
netfilter-persistent save

echo "[✓] iptables firewall setup complete (VPN, Docker, nginx, host connectivity)."
