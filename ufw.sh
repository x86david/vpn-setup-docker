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

echo "🌐 Prepending NAT rules into /etc/ufw/before.rules..."
tmpfile=$(mktemp)
cat <<EOF > "$tmpfile"
# Custom NAT rules
*nat
:POSTROUTING ACCEPT [0:0]

# NAT for VPN subnet
-A POSTROUTING -s $VPN_SUBNET_V4 -o $WAN_IFACE -j MASQUERADE

# NAT for Docker subnet
-A POSTROUTING -s $DOCKER_SUBNET_V4 -o $WAN_IFACE -j MASQUERADE

COMMIT

# End of custom NAT rules
EOF
cat /etc/ufw/before.rules >> "$tmpfile"
mv "$tmpfile" /etc/ufw/before.rules

echo "🌐 Prepending NAT rules into /etc/ufw/before6.rules..."
tmpfile=$(mktemp)
cat <<EOF > "$tmpfile"
# Custom NAT rules (IPv6)
*nat
:POSTROUTING ACCEPT [0:0]

# NAT for VPN IPv6 subnet
-A POSTROUTING -s $VPN_SUBNET_V6 -o $WAN_IFACE -j MASQUERADE

COMMIT

# End of custom NAT rules
EOF
cat /etc/ufw/before6.rules >> "$tmpfile"
mv "$tmpfile" /etc/ufw/before6.rules

echo "🔓 Allowing inbound SSH (22/tcp) + proxy port (2222/tcp)..."
ufw allow 22/tcp
ufw allow 2222/tcp

echo "🔓 Allowing inbound VPN ($VPN_PORT/$VPN_PROTO)..."
ufw allow $VPN_PORT/$VPN_PROTO

echo "🔓 Allowing nginx/webserver ports (80/tcp and 443/tcp)..."
ufw allow 80/tcp
ufw allow 443/tcp

echo "🔓 Enabling UFW..."
ufw --force enable
ufw status verbose

echo "[✓] UFW firewall setup complete (VPN, SSH, nginx ports, proxy port for Nginx stream)."
