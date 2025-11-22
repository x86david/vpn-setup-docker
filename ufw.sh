#!/bin/bash
set -e

# --- Variables ---
VPN_SUBNET_V4="10.9.0.0/24"
VPN_SUBNET_V6="fd42:42:42:42::/64"
VPN_PORT="1194"
VPN_PROTO="udp"
VPN_IFACE="tun0"

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

echo "[*] Enabling IPv4/IPv6 forwarding..."
sed -i 's/^#net\/ipv4\/ip_forward=1/net.ipv4.ip_forward=1/' /etc/ufw/sysctl.conf
sed -i 's/^#net\/ipv6\/conf\/default\/forwarding=1/net.ipv6.conf.default.forwarding=1/' /etc/ufw/sysctl.conf
sed -i 's/^#net\/ipv6\/conf\/all\/forwarding=1/net.ipv6.conf.all.forwarding=1/' /etc/ufw/sysctl.conf

sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1

echo "[*] Setting UFW forward policy to DROP (restrictive)..."
sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="DROP"/' /etc/default/ufw

echo "[*] Configuring NAT masquerade rules..."
if ! grep -q "$VPN_SUBNET_V4" $UFW_BEFORE; then
  sed -i "1i *nat\n:POSTROUTING ACCEPT [0:0]\n-A POSTROUTING -s $VPN_SUBNET_V4 -o $WAN_IFACE -j MASQUERADE\nCOMMIT\n" $UFW_BEFORE
fi

if ! grep -q "$VPN_SUBNET_V6" $UFW_BEFORE6; then
  sed -i "1i *nat\n:POSTROUTING ACCEPT [0:0]\n-A POSTROUTING -s $VPN_SUBNET_V6 -o $WAN_IFACE -j MASQUERADE\nCOMMIT\n" $UFW_BEFORE6
fi

echo "[*] Configuring UFW rules..."
ufw default deny incoming
ufw default allow outgoing

# Allow VPN port and SSH
ufw allow $VPN_PORT/$VPN_PROTO
ufw allow ssh

# Restrictive forwarding: only allow routed traffic from tun0 -> WAN_IFACE
ufw route allow in on $VPN_IFACE out on $WAN_IFACE

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

echo "[✓] VPN + UFW restrictive setup complete."
