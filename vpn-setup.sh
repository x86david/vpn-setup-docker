#!/bin/bash
set -e

echo "🚀 Instalando dependencias en el servidor..."

# Actualizar paquetes base
apt update -y
apt upgrade -y
apt install -y ca-certificates curl gnupg git openssh-client

# Resetear repositorio oficial de Docker
echo "🔑 Configurando repositorio oficial de Docker..."
rm -f /etc/apt/sources.list.d/docker.list   # eliminar archivo roto si existe
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod 0644 /etc/apt/keyrings/docker.gpg

# Detectar distribución y codename
. /etc/os-release
if [ "$ID" = "ubuntu" ]; then
  CODENAME=${VERSION_CODENAME:-jammy}
else
  # Debian 12 = bookworm, Debian 13 = trixie
  CODENAME=${VERSION_CODENAME:-bookworm}
fi

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${ID} ${CODENAME} stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update -y

# Instalar Docker y Compose plugin desde repositorio oficial
echo "🐳 Instalando Docker y Docker Compose..."
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Habilitar y arrancar Docker
systemctl enable --now docker

# Instalar iptables-persistent para guardar reglas
echo "🛡️ Instalando iptables-persistent..."
DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent netfilter-persistent

# Configurar sysctl para forwarding
echo "🔧 Configurando sysctl para forwarding..."
cat <<EOF >> /etc/sysctl.conf
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
sysctl -p

# Detectar interfaz externa
EXT_IF=$(ip route | grep default | awk '{print $5}')

# Configurar NAT IPv4
echo "🌐 Configurando NAT IPv4..."
iptables -t nat -C POSTROUTING -s 10.9.0.0/24 -o "$EXT_IF" -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -s 10.9.0.0/24 -o "$EXT_IF" -j MASQUERADE

# Configurar NAT IPv6
echo "🌐 Configurando NAT IPv6..."
ip6tables -t nat -C POSTROUTING -s fd42:42:42:42::/64 -o "$EXT_IF" -j MASQUERADE 2>/dev/null || \
ip6tables -t nat -A POSTROUTING -s fd42:42:42:42::/64 -o "$EXT_IF" -j MASQUERADE

# Guardar reglas persistentes
netfilter-persistent save

# Generar clave SSH directamente en ~/.ssh si no existe
SSH_DIR="/root/.ssh"
KEY_FILE="$SSH_DIR/id_ed25519"

if [ ! -f "$KEY_FILE" ]; then
  echo "🔑 Generando clave SSH en $SSH_DIR..."
  mkdir -p $SSH_DIR
  chmod 700 $SSH_DIR
  ssh-keygen -t ed25519 -C "github-key" -f $KEY_FILE -N ""
  echo "✅ Clave SSH generada"
  echo "🔐 Copia esta clave pública en GitHub (Settings → SSH and GPG keys → New SSH key):"
  cat $KEY_FILE.pub
  echo ""
  read -p "⏸️ Pulsa ENTER cuando hayas añadido la clave en GitHub..."
else
  echo "📂 Ya existe una clave SSH en $KEY_FILE, no se genera otra"
fi

# Probar conexión SSH con GitHub (no detiene el script si falla)
echo "🔍 Probando conexión SSH con GitHub..."
ssh -T git@github.com || true

# Clonar tu repositorio con SSH
REPO_URL="git@github.com:x86david/openvpn-docker.git"
TARGET_DIR="/opt/openvpn-docker"

if [ -d "$TARGET_DIR" ]; then
  echo "📂 El directorio $TARGET_DIR ya existe, saltando clon..."
else
  git clone "$REPO_URL" "$TARGET_DIR"
fi

cd "$TARGET_DIR"

# Dar permisos de ejecución a los scripts del repo
echo "⚙️ Ajustando permisos de ejecución a los scripts..."
find ./ -type f -name "*.sh" -exec chmod +x {} \;

# Generar llaves antes de levantar el contenedor
echo "🔑 Generando llaves con EasyRSA..."
./scripts/gen-keys-local.sh

# Levantar el servicio con Docker Compose
echo "🐳 Levantando OpenVPN con Docker Compose..."
docker compose up -d

echo "✅ OpenVPN desplegado en el servidor"
echo "👉 Usa ./clients/create-client.sh <usuario> para generar perfiles .ovpn"
