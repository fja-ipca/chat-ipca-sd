#!/usr/bin/env bash

# Forçar que o script corra como root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Por favor, corre este script como root!"
  exit 1
fi

echo "🚀 Iniciando o provisionamento do servidor..."

# Variáveis de Configuração
USER_NAME="chat-admin"
GIT_NAME="Filipe Almeida"
GIT_EMAIL="fja.ipca@gmail.com"
INTERFACE="enp0s3"

# ==========================================
# 1. CONFIGURAÇÃO DE REDE (SYSTEMD-NETWORKD)
# ==========================================
echo "🌐 Configurando a rede ($INTERFACE) e DNS..."

# Desativar o sistema antigo do Debian para não haver conflitos
systemctl disable --now networking.service --force 2>/dev/null
if [ -f /etc/network/interfaces ]; then
    mv /etc/network/interfaces /etc/network/interfaces.old
fi

# Criar o ficheiro de rede para a interface do Hyper-V
mkdir -p /etc/systemd/network
cat <<EOF > /etc/systemd/network/20-${INTERFACE}.network
[Match]
Name=${INTERFACE}

[Network]
DHCP=yes
EOF

# Ativar e reiniciar os serviços de rede modernos
systemctl enable systemd-networkd systemd-resolved
systemctl restart systemd-networkd
systemctl restart systemd-resolved

# Criar o link simbólico correto para o DNS funcionar via systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# ==========================================
# 2. INSTALAÇÃO DE PACOTES ESSENCIAIS
# ==========================================
echo "📦 Atualizando o sistema e instalando ferramentas utilitárias..."
apt-get update && apt-get install -y nala
nala install -y sudo curl ca-certificates gnupg btop neovim git htop

# ==========================================
# 3. CRIAÇÃO E CONFIGURAÇÃO DO UTILIZADOR
# ==========================================
echo "👤 Configurando o utilizador: $USER_NAME..."

# Criar o utilizador se ele não existir
if ! id "$USER_NAME" &>/dev/null; then
    useradd -m -s /bin/bash "$USER_NAME"
    echo "-> Define a password para o utilizador $USER_NAME:"
    passwd "$USER_NAME"
fi

# Adicionar o utilizador ao grupo sudo para comandos administrativos
usermod -aG sudo "$USER_NAME"

# ==========================================
# 4. INSTALAÇÃO DO DOCKER (FONTE OFICIAL)
# ==========================================
echo "🐳 Configurando o repositório oficial do Docker..."
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

cat <<EOF > /etc/apt/sources.list.d/docker.sources
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

nala update
nala install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Colocar o chat-admin no grupo do docker (para poderes rodar docker sem 'sudo')
usermod -aG docker "$USER_NAME"

# ==========================================
# 5. MIGRAÇÃO DO GIT E CHAVE SSH PARA O USER
# ==========================================
echo "🔑 Migrando configurações do Git e chaves SSH para o $USER_NAME..."

# Configurar o Git do utilizador comum
sudo -u "$USER_NAME" git config --global user.name "$GIT_NAME"
sudo -u "$USER_NAME" git config --global user.email "$GIT_EMAIL"

# Se o root tiver chaves SSH prontas, migra para o utilizador (evita reconfigurar o GitHub)
if [ -f /root/.ssh/id_ed25519 ]; then
    mkdir -p /home/$USER_NAME/.ssh
    cp /root/.ssh/id_ed25519* /home/$USER_NAME/.ssh/
    chown -R $USER_NAME:$USER_NAME /home/$USER_NAME/.ssh
    chmod 700 /home/$USER_NAME/.ssh
    chmod 600 /home/$USER_NAME/.ssh/id_ed25519
    chmod 644 /home/$USER_NAME/.ssh/id_ed25519.pub
    echo "✅ Chave SSH migrada com sucesso para o $USER_NAME."
else
    # Se não existia chave, gera uma nova direto no utilizador
    sudo -u "$USER_NAME" ssh-keygen -t ed25519 -C "$GIT_EMAIL" -N "" -f /home/$USER_NAME/.ssh/id_ed25519
    echo "⚠️ Nova chave SSH gerada para o $USER_NAME. Lembra-te de a adicionar ao GitHub:"
    cat /home/$USER_NAME/.ssh/id_ed25519.pub
fi

# Limpar configurações indevidas do root para evitar confusões futuras
rm -f /root/.gitconfig

echo "🎉 Configuração concluída com sucesso! O teu servidor está limpo e pronto."
echo "👉 Executa 'su - $USER_NAME' para começares a trabalhar corretamente."