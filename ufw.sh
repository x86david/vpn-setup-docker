#!/bin/bash
set -euo pipefail

# --- Variables ---
VPN_SUBNET_V4="10.9.0.0/24"
VPN_SUBNET_V6="fd42:42:42:42::/64"
VPN_PORT="1194"
VPN_PROTO="udp"
VPN_IFACE="tun0"

# Docker default bridge subnet (adjust if you use custom networks)
DOCKER_SUBNET_V4="172.17.0.0/16"

UFW_BEFORE="/etc/ufw/before.rules"
UFW_BEFORE6="/etc/ufw/before6.rules"

# Detect external interface dynamically
WAN_IFACE=$(ip route | grep '^default' | awk '{print $5}')
echo "[*] Detected WAN interface: $WAN_IFACE"

echo "[*] Installing UFW..."
apt-get update -y
apt-get install -y ufw

echo "[*] Resetting UFW to defaults..."
ufw --force reset

# Clear previous NAT rules
echo "" > $UFW_BEFORE
echo "" > $UFW_BEFORE6
iptables -t nat -F
iptables -t nat -X

echo "[*] Enabling IPv4/IPv6 forwarding..."
sed -i 's/^#net\/ipv4\/ip_forward=1/net.ipv4.ip_forward=1/' /etc/ufw/sysctl.conf
sed -i 's/^#net\/ipv6\/conf\/default\/forwarding=1/net.ipv6.conf.default.forwarding=1/' /etc/ufw/sysctl.conf
sed -i 's/^#net\/ipv6\/conf\/all\/forwarding=1/net.ipv6.conf.all.forwarding=1/' /etc/ufw/sysctl.conf

sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1

echo "[*] Setting restrictive defaults..."
ufw default deny incoming
ufw default allow outgoing

# --- NAT masquerade rules (VPN + Docker -> Internet) ---
cat <<EOF > $UFW_BEFORE
*nat
:POSTROUTING ACCEPT [0:0]
# VPN subnet
-A POSTROUTING -s $VPN_SUBNET_V4 -o $WAN_IFACE -j MASQUERADE
# Docker subnet
-A POSTROUTING -s $DOCKER_SUBNET_V4 -o $WAN_IFACE -j MASQUERADE
COMMIT
EOF

cat <<EOF > $UFW_BEFORE6
*nat
:POSTROUTING ACCEPT [0:0]
# VPN IPv6 subnet
-A POSTROUTING -s $VPN_SUBNET_V6 -o $WAN_IFACE -j MASQUERADE
COMMIT
EOF

# --- Allow VPN port and SSH ---
ufw allow $VPN_PORT/$VPN_PROTO
ufw allow ssh

# --- Allow intra-VPN traffic (clients can talk to each other) ---
ufw allow in on $VPN_IFACE
ufw allow out on $VPN_IFACE

echo "[*] Enabling UFW..."
ufw --force enable
ufw reload

# --- Sanity checks ---
echo "[*] UFW status:"
ufw status verbose

echo "[*] NAT table:"
iptables -t nat -L -n -v

if command -v docker-compose >/dev/null 2>&1; then
  echo "[*] Restarting Docker Compose..."
  docker-compose restart
fi

echo "[✓] VPN + Docker + UFW restrictive setup complete."
