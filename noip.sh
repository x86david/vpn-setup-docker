#!/bin/bash
set -e

echo "🌐 Instalando cliente No-IP desde fuente..."

cd /usr/local/src
wget -q http://www.no-ip.com/client/linux/noip-duc-linux.tar.gz -O noip-duc-linux.tar.gz
tar xf noip-duc-linux.tar.gz
cd noip-2.1.9-1/binaries

ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
  sudo cp noip2-x86_64 /usr/local/bin/noip2
else
  sudo cp noip2-i686 /usr/local/bin/noip2
fi
sudo chmod 755 /usr/local/bin/noip2

echo "⚙️ Creando servicio systemd para noip2..."
cat <<EOF | sudo tee /etc/systemd/system/noip2.service
[Unit]
Description=No-IP Dynamic DNS Update Client
After=network.target

[Service]
ExecStart=/usr/local/bin/noip2
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now noip2

echo "⚠️ Ejecuta 'sudo /usr/local/bin/noip2 -C' manualmente una vez para configurar tu cuenta y hostname de No-IP (elige la interfaz enp0s3)."
echo "✅ No-IP instalado y servicio systemd configurado"
