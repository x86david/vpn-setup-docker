#!/bin/bash
set -e

echo "🚀 Instalando dependencias en el servidor..."

# Actualizar paquetes base
apt update -y
apt upgrade -y
apt install -y ca-certificates curl gnupg git openssh-client build-essential tar wget

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

# --- Firewall setup with UFW ---
echo "🛡️ Configurando firewall con UFW..."
bash ./ufw.sh

# --- SSH key setup for GitHub ---
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
echo "🐳 Levantando OpenVPN y reverse proxy con Docker Compose..."
docker compose up -d

echo "✅ OpenVPN desplegado en el servidor"
echo "👉 Usa ./clients/create-client.sh <usuario> para generar perfiles .ovpn"
echo "👉 Edita nginx.conf y reinicia el contenedor proxy para añadir servicios internos"

# --- Run No-IP setup script at the end ---
echo "🌐 Ejecutando script de instalación de No-IP..."
bash ./noip.sh

echo "✅ Configuración completa del servidor con No-IP"
