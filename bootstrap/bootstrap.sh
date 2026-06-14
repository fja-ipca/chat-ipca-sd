#!/usr/bin/env bash

# Forçar que o script corra como root
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, corre este script como root!"
  exit 1
fi

echo "Iniciando a verificação de estado do servidor..."

# Variáveis de Configuração
USER_NAME="chat-admin"
GIT_NAME="Filipe Almeida"
GIT_EMAIL="fja.ipca@gmail.com"
INTERFACE="enp0s3"

# ==========================================
# 1. CONFIGURAÇÃO DE REDE (SYSTEMD-NETWORKD)
# ==========================================
echo "[1/5] Verificando configuração de rede..."

if [ -f "/etc/systemd/network/20-${INTERFACE}.network" ] && systemctl is-active --quiet systemd-networkd; then
    echo "   Rede (systemd-networkd) já está configurada e ativa."
else
    echo "   Aplicando configuração de rede..."
    # Desativar o sistema antigo
    systemctl disable --now networking.service --force 2>/dev/null
    if [ -f /etc/network/interfaces ] && [ ! -f /etc/network/interfaces.old ]; then
        mv /etc/network/interfaces /etc/network/interfaces.old
    fi

    # Criar o ficheiro moderno de rede
    mkdir -p /etc/systemd/network
    cat <<EOF > /etc/systemd/network/20-${INTERFACE}.network
[Match]
Name=${INTERFACE}

[Network]
DHCP=yes
EOF
    systemctl enable systemd-networkd systemd-resolved
    systemctl restart systemd-networkd
    systemctl restart systemd-resolved
fi

# Verificar o link do DNS (systemd-resolved)
if [ "$(readlink /etc/resolv.conf)" = "/run/systemd/resolve/stub-resolv.conf" ]; then
    echo "   Link simbólico do DNS (/etc/resolv.conf) já está correto."
else
    echo "   Ajustando link simbólico do DNS..."
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
fi

# ==========================================
# 2. INSTALAÇÃO DE PACOTES ESSENCIAIS
# ==========================================
echo "[2/5] Verificando ferramentas essenciais..."

if command -v nala &>/dev/null; then
    echo "   Nala já está instalado."
else
    echo "   Instalando o gerenciador Nala..."
    apt-get update && apt-get install -y nala
fi

# Instalação idempotente (o nala/apt ignora se já existirem)
echo "   Validando pacotes utilitários..."
nala install -y sudo curl ca-certificates gnupg btop neovim git htop

# ==========================================
# 3. CRIAÇÃO E CONFIGURAÇÃO DO UTILIZADOR
# ==========================================
echo "👤 [3/5] Verificando o utilizador $USER_NAME..."

if id "$USER_NAME" &>/dev/null; then
    echo "   Utilizador '$USER_NAME' já existe."
else
    echo "   Criando o utilizador '$USER_NAME'..."
    useradd -m -s /bin/bash "$USER_NAME"
    echo "-> Define a password para o novo utilizador:"
    passwd "$USER_NAME"
fi

# Verificar grupo sudo
if groups "$USER_NAME" | grep -q "\bsudo\b"; then
    echo "   O utilizador já tem permissões de Sudo."
else
    echo "   Adicionando $USER_NAME ao grupo sudo..."
    usermod -aG sudo "$USER_NAME"
fi

# ==========================================
# 4. INSTALAÇÃO DO DOCKER (FONTE OFICIAL)
# ==========================================
echo "[4/5] Verificando instalação do Docker..."

if [ -f /etc/apt/sources.list.d/docker.sources ] && command -v docker &>/dev/null; then
    echo "   Repositório e binários do Docker já estão instalados."
else
    echo "   Configurando repositório oficial do Docker..."
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc 2>/dev/null
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
fi

# Verificar se o utilizador já está no grupo docker
if groups "$USER_NAME" | grep -q "\bdocker\b"; then
    echo "   O utilizador já pertence ao grupo Docker."
else
    echo "   Adicionando $USER_NAME ao grupo docker (requer nova sessão para aplicar)..."
    usermod -aG docker "$USER_NAME"
fi

# ==========================================
# 5. CONFIGURAÇÃO DO GIT E CHAVE SSH
# ==========================================
echo "[5/5] Verificando chaves SSH e Git do utilizador..."

# Validar Git Config local do user
CURRENT_GIT_USER=$(sudo -u "$USER_NAME" git config --global user.name)
if [ "$CURRENT_GIT_USER" = "$GIT_NAME" ]; then
    echo "   Configurações globais do Git já estão corretas."
else
    echo "   Configurando a identidade do Git para o utilizador..."
    sudo -u "$USER_NAME" git config --global user.name "$GIT_NAME"
    sudo -u "$USER_NAME" git config --global user.email "$GIT_EMAIL"
fi

# Validar Chave SSH
if [ -f "/home/$USER_NAME/.ssh/id_ed25519" ]; then
    echo "   Chave SSH do utilizador detetada e pronta."
else
    if [ -f /root/.ssh/id_ed25519 ]; then
        echo "   Migrando chave SSH existente do root para o $USER_NAME..."
        mkdir -p /home/$USER_NAME/.ssh
        cp /root/.ssh/id_ed25519* /home/$USER_NAME/.ssh/
        chown -R $USER_NAME:$USER_NAME /home/$USER_NAME/.ssh
        chmod 700 /home/$USER_NAME/.ssh
        chmod 600 /home/$USER_NAME/.ssh/id_ed25519
        chmod 644 /home/$USER_NAME/.ssh/id_ed25519.pub
    else
        echo "   Nenhuma chave encontrada. Gerando nova chave SSH para o $USER_NAME..."
        mkdir -p /home/$USER_NAME/.ssh
        chown $USER_NAME:$USER_NAME /home/$USER_NAME/.ssh
        chmod 700 /home/$USER_NAME/.ssh
        sudo -u "$USER_NAME" ssh-keygen -t ed25519 -C "$GIT_EMAIL" -N "" -f /home/$USER_NAME/.ssh/id_ed25519
        echo "  Lembra-te de adicionar esta nova chave ao teu GitHub:"
        cat /home/$USER_NAME/.ssh/id_ed25519.pub
    fi
fi

# Limpar o ficheiro indesejado do root, caso exista
[ -f /root/.gitconfig ] && rm -f /root/.gitconfig

echo "[FIM] Validação concluída! O teu servidor está estável e atualizado."