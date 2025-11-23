#!/bin/bash
set -e

echo "🌐 Instalando cliente No-IP desde fuente..."

cd /usr/local/src
wget -q http://www.no-ip.com/client/linux/noip-duc-linux.tar.gz -O noip-duc-linux.tar.gz
tar xf noip-duc-linux.tar.gz
cd noip-2.1.9-1/binaries

ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
  cp noip2-x86_64 /usr/local/bin/noip2
else
  cp noip2-i686 /usr/local/bin/noip2
fi
chmod 755 /usr/local/bin/noip2

echo "⚙️ Creando servicio systemd para noip2..."
cat <<EOF >/etc/systemd/system/noip2.service
[Unit]
Description=No-IP Dynamic DNS Update Client
After=network.target

[Service]
ExecStart=/usr/local/bin/noip2 -c /usr/local/etc/no-ip2.conf
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# --- Crear configuración automática ---
cat <<EOF >/usr/local/etc/no-ip2.conf
# Configuración No-IP
# interface: enp0s3
# usuario: tu_email@noip.com
# contraseña: tu_password
# host: all.ddnskey.com
# intervalo: 30 minutos
EOF

systemctl daemon-reload
systemctl enable --now noip2

echo "✅ No-IP instalado, configurado y servicio systemd activo"
