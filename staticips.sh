#!/bin/bash
set -e

CCD_DIR="/etc/openvpn/ccd"

echo "[*] Creating CCD directory at $CCD_DIR..."
mkdir -p $CCD_DIR

echo "[*] Assigning static IPs..."

# Webserver client (CN = webserver1)
cat > $CCD_DIR/webserver1 <<EOF
ifconfig-push 10.9.0.99 255.255.255.0
EOF

# SFTP client (CN = sftp)
cat > $CCD_DIR/sftp <<EOF
ifconfig-push 10.9.0.98 255.255.255.0
EOF

echo "[✓] Static IPs configured in $CCD_DIR"

# Helpful message for manual runs
echo ""
echo "ℹ️ After running this script:"
echo "   - Make sure 'client-config-dir $CCD_DIR' is present in your server.conf"
echo "   - Restart OpenVPN with: sudo systemctl restart openvpn@server"
echo "   - Verify clients get their static IPs by checking openvpn-status.log or running ifconfig on the client"
