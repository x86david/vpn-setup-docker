#!/bin/bash
set -euo pipefail

# --- Variables ---
VPN_SUBNET_V4="10.9.0.0/24"
VPN_SUBNET_V6="fd42:42:42:42::/64"
VPN_PORT="1194"
VPN_PROTO="udp"
VPN_IFACE="tun0"

DOCKER_SUBNET_V4="172.17.0.0/16"

UFW_BEFORE="/etc/ufw/before.rules"
UFW_BEFORE6="/etc/ufw/before6.rules"

WAN_IFACE=$(ip route | grep '^default' | awk '{print $5}')
echo "[*] Detected WAN interface: $WAN_IFACE"

echo "[*] Installing UFW..."
apt-get update -y
apt-get install -y ufw

echo "[*] Resetting UFW..."
ufw --force reset

# Clear previous NAT rules
echo "" > $UFW_BEFORE
echo "" > $UFW_BEFORE6
iptables -t nat -F
iptables -t nat -X

echo "[*] Enable IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1

echo "[*] Set defaults..."
ufw default deny incoming
ufw default allow outgoing

# --- NAT masquerade rules ---
cat <<EOF > $UFW_BEFORE
*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s $VPN_SUBNET_V4 -o $WAN_IFACE -j MASQUERADE
-A POSTROUTING -s $DOCKER_SUBNET_V4 -o $WAN_IFACE -j MASQUERADE
COMMIT
EOF

cat <<EOF > $UFW_BEFORE6
*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s $VPN_SUBNET_V6 -o $WAN_IFACE -j MASQUERADE
COMMIT
EOF

# --- Allow VPN port + SSH ---
ufw allow $VPN_PORT/$VPN_PROTO
ufw allow ssh

# --- Allow intra-VPN traffic ---
ufw allow in on $VPN_IFACE
ufw allow out on $VPN_IFACE

echo "[*] Enable UFW..."
ufw --force enable
ufw reload

echo "[*] UFW status:"
ufw status verbose

echo "[*] NAT table:"
iptables -t nat -L -n -v

echo "[✓] Minimal VPN + Docker + UFW setup complete."
