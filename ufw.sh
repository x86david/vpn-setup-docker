#!/bin/bash
set -euo pipefail

VPN_SUBNET_V4="10.9.0.0/24"
VPN_SUBNET_V6="fd42:42:42:42::/64"
VPN_PORT="1194"
VPN_PROTO="udp"
DOCKER_SUBNET_V4="172.17.0.0/16"
WAN_IFACE=$(ip route | grep '^default' | awk '{print $5}')

echo "[*] Detected WAN interface: $WAN_IFACE"

echo "🛑 Resetting UFW..."
apt-get purge -y ufw iptables-persistent netfilter-persistent
apt-get install -y ufw

echo "🔧 Enabling IP forwarding..."
sed -i '/^#net.ipv4.ip_forward=1/c\net.ipv4.ip_forward=1' /etc/ufw/sysctl.conf
sed -i '/^#net.ipv6.conf.all.forwarding=1/c\net.ipv6.conf.all.forwarding=1' /etc/ufw/sysctl.conf

echo "🌐 Writing NAT rules into /etc/ufw/before.rules..."
cat <<EOF > /etc/ufw/before.rules
# /etc/ufw/before.rules
# NAT table rules
*nat
:POSTROUTING ACCEPT [0:0]

# NAT for VPN subnet
-A POSTROUTING -s $VPN_SUBNET_V4 -o $WAN_IFACE -j MASQUERADE

# NAT for Docker subnet
-A POSTROUTING -s $DOCKER_SUBNET_V4 -o $WAN_IFACE -j MASQUERADE

COMMIT

# End of NAT rules

*filter
# UFW default filter rules will follow
EOF

echo "🌐 Writing