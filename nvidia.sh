#!/bin/bash

set -e

# Command line options
ONLY_CONFIG=false
EXPORT_PACKAGES=false
SKIP_NVIDIA=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --only-config)
            ONLY_CONFIG=true
            shift
            ;;
        --export-packages)
            EXPORT_PACKAGES=true
            shift
            ;;
        --skip-nvidia)
            SKIP_NVIDIA=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "  --only-config      Only copy config files (skip packages and external tools)"
            echo "  --export-packages  Export package lists for different distros and exit"
            echo "  --skip-nvidia      Skip NVIDIA drivers installation"
            echo "  --help            Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config/i3"
TEMP_DIR="/tmp/i3_$$"
LOG_FILE="$HOME/i3-install.log"

# Logging and cleanup
exec > >(tee -a "$LOG_FILE") 2>&1
trap "rm -rf $TEMP_DIR" EXIT

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

die() { echo -e "${RED}ERROR: $*${NC}" >&2; exit 1; }
msg() { echo -e "${CYAN}$*${NC}"; }

# Função de instalação para Arch Linux
progress_install() {
    local description="$1"
    shift
    local packages=("$@")
    local total_packages=${#packages[@]}
    local installed_count=0

    # Cabeçalho com emoji e descrição
    echo -e "\n${CYAN}📦 $description${NC}"
    echo -e "${GRAY}═${NC}"$(printf '%.0s═' $(seq 1 $((${#description} + 2))))

    # Verificar se há pacotes para instalar
    if [ $total_packages -eq 0 ]; then
        echo -e "${YELLOW}⚠️  Nenhum pacote especificado${NC}\n"
        return 1
    fi

    echo -e "${BLUE}📊 Total de pacotes: $total_packages${NC}"

    # Verificar pacotes já instalados
    local to_install=()
    for pkg in "${packages[@]}"; do
        if pacman -Qi "$pkg" &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $pkg ${GRAY}(já instalado)${NC}"
            ((installed_count++))
        else
            to_install+=("$pkg")
        fi
    done

    # Se todos já estiverem instalados
    if [ $installed_count -eq $total_packages ]; then
        echo -e "${GREEN}✅ Todos os pacotes já estão instalados${NC}\n"
        return 0
    fi

    # Mostrar o que será instalado
    if [ ${#to_install[@]} -gt 0 ]; then
        echo -e "${YELLOW}⬇️  Pacotes para instalar: ${#to_install[@]}${NC}"
        printf "  • %s\n" "${to_install[@]}"
    fi

    echo -e "${BLUE}⏳ Iniciando instalação...${NC}"

    # Instalação com progresso
    local start_time=$(date +%s)

    # Usar yay se disponível, senão pacman
    if command -v yay &> /dev/null; then
        echo -e "${BLUE}Usando yay para instalação AUR...${NC}"
        yay -S --needed --noconfirm "${to_install[@]}" || {
            echo -e "${YELLOW}Tentando com pacman...${NC}"
            sudo pacman -S --needed --noconfirm "${to_install[@]}"
        }
    else
        sudo pacman -S --needed --noconfirm "${to_install[@]}"
    fi

    local exit_code=$?
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Resultado
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}✅ $description concluído em ${duration}s${NC}"

        # Verificar instalação bem-sucedida
        local success_count=0
        for pkg in "${to_install[@]}"; do
            if pacman -Qi "$pkg" &>/dev/null; then
                ((success_count++))
            fi
        done

        echo -e "  ${GREEN}${success_count}/${#to_install[@]} pacotes instalados com sucesso${NC}"
    else
        echo -e "${RED}❌ Erro na instalação de $description${NC}"
        echo -e "${YELLOW}Código de erro: $exit_code${NC}"
    fi

    echo ""
    return $exit_code
}

# Função para instalar yay do AUR
install_yay() {
    msg "Instalando yay (AUR helper)..."

    # Verificar se yay já está instalado
    if command -v yay &> /dev/null; then
        echo -e "${GREEN}✓ yay já está instalado${NC}"
        return 0
    fi

    # Verificar dependências necessárias
    if ! pacman -Qi git base-devel &>/dev/null; then
        echo -e "${YELLOW}Instalando dependências para yay...${NC}"
        sudo pacman -S --needed --noconfirm git base-devel || {
            echo -e "${RED}❌ Falha ao instalar dependências${NC}"
            return 1
        }
    fi

    # Criar diretório temporário para build
    local temp_dir="/tmp/yay_install_$$"
    mkdir -p "$temp_dir"
    cd "$temp_dir"

    echo -e "${BLUE}Clonando repositório do yay...${NC}"
    git clone https://aur.archlinux.org/yay.git || {
        echo -e "${RED}❌ Falha ao clonar repositório${NC}"
        return 1
    }

    cd yay
    echo -e "${BLUE}Compilando e instalando yay...${NC}"

    # Construir e instalar
    makepkg -si --noconfirm || {
        echo -e "${RED}❌ Falha ao instalar yay${NC}"
        cd ~
        rm -rf "$temp_dir"
        return 1
    }

    # Limpar
    cd ~
    rm -rf "$temp_dir"

    echo -e "${GREEN}✅ yay instalado com sucesso!${NC}"
    return 0
}

# Função de diagnóstico NVIDIA
diagnose_nvidia_issue() {
    echo -e "\n${CYAN}=== Diagnóstico NVIDIA ===${NC}"
    
    echo -e "\n${BLUE}1. Hardware detectado:${NC}"
    lspci | grep -i nvidia || echo "Nenhuma placa NVIDIA detectada"
    
    echo -e "\n${BLUE}2. Módulos carregados:${NC}"
    lsmod | grep -i nvidia || echo "Nenhum módulo NVIDIA carregado"
    
    echo -e "\n${BLUE}3. Pacotes instalados:${NC}"
    pacman -Q | grep -i nvidia || echo "Nenhum pacote NVIDIA instalado"
    
    echo -e "\n${BLUE}4. Arquivos de configuração:${NC}"
    ls -la /etc/modprobe.d/*nvidia* /etc/X11/xorg.conf.d/*nvidia* 2>/dev/null || echo "Nenhum arquivo de configuração encontrado"
    
    echo -e "\n${BLUE}5. Logs do kernel (últimas 20 linhas):${NC}"
    dmesg | grep -i nvidia | tail -20 || echo "Nenhum log NVIDIA encontrado"
    
    echo -e "\n${BLUE}6. Status do mkinitcpio:${NC}"
    lsinitcpio /boot/initramfs-*.img 2>/dev/null | grep -i nvidia || echo "NVIDIA não encontrado no initramfs"
    
    echo -e "${CYAN}=== Fim do Diagnóstico ===${NC}\n"
}

# Função melhorada para instalação NVIDIA
install_nvidia_drivers() {
    if [ "$ONLY_CONFIG" = true ]; then
        echo -e "${YELLOW}⚠️  Modo --only-config ativo, pulando instalação NVIDIA${NC}"
        return 0
    fi
    
    if [ "$SKIP_NVIDIA" = true ]; then
        echo -e "${YELLOW}⚠️  Opção --skip-nvidia ativada, pulando instalação NVIDIA${NC}"
        return 0
    fi
    
    msg "Verificando hardware NVIDIA..."
    
    # Verificar se há placa NVIDIA
    if ! lspci | grep -i nvidia &>/dev/null; then
        echo -e "${YELLOW}⚠️  Nenhuma placa NVIDIA detectada, pulando instalação de drivers${NC}"
        return 0
    fi
    
    msg "Instalando drivers NVIDIA..."
    
    # Determinar qual pacote NVIDIA instalar baseado no kernel
    local nvidia_package="nvidia"
    local kernel_package=$(pacman -Q | grep -E "^linux[0-9-]* " | head -n1 | cut -d' ' -f1 2>/dev/null || echo "linux")

    case "$kernel_package" in
        linux-lts)
            nvidia_package="nvidia-lts"
            echo -e "${BLUE}Detectado kernel LTS, usando $nvidia_package${NC}"
            ;;
        linux-zen)
            nvidia_package="nvidia-dkms"
            echo -e "${BLUE}Detectado kernel Zen, usando $nvidia_package (DKMS)${NC}"
            ;;
        linux-hardened)
            nvidia_package="nvidia-dkms"
            echo -e "${BLUE}Detectado kernel Hardened, usando $nvidia_package (DKMS)${NC}"
            ;;
        *)
            echo -e "${BLUE}Usando driver padrão: $nvidia_package${NC}"
            ;;
    esac
    
    # Pacotes NVIDIA para instalar
    local nvidia_packages=(
        "$nvidia_package"
        nvidia-utils
        nvidia-settings
    )
    
    # Verificar se multilib está habilitado para suporte a 32-bit
    if grep -q "^\[multilib\]" /etc/pacman.conf; then
        nvidia_packages+=(lib32-nvidia-utils)
        echo -e "${BLUE}Multilib detectado, adicionando suporte a 32-bit${NC}"
    fi
    
    # Instalar drivers
    if ! progress_install "Installing NVIDIA drivers" "${nvidia_packages[@]}"; then
        echo -e "${YELLOW}Tentando método alternativo com nvidia-dkms...${NC}"
        local fallback_packages=("nvidia-dkms" "nvidia-utils" "nvidia-settings")
        if grep -q "^\[multilib\]" /etc/pacman.conf; then
            fallback_packages+=("lib32-nvidia-utils")
        fi
        
        sudo pacman -S --needed --noconfirm "${fallback_packages[@]}" || {
            echo -e "${RED}❌ Falha na instalação dos drivers NVIDIA${NC}"
            echo -e "${YELLOW}Você pode tentar instalar manualmente depois${NC}"
            return 1
        }
    fi
    
    # Configurar drivers
    configure_nvidia
    
    # Verificação final
    if command -v nvidia-smi &>/dev/null; then
        if nvidia-smi &>/dev/null; then
            echo -e "${GREEN}✅ Driver NVIDIA funcionando corretamente!${NC}"
        else
            echo -e "${YELLOW}⚠️  Driver NVIDIA instalado mas pode precisar de reinicialização${NC}"
        fi
    fi
    
    return 0
}

# Função de configuração NVIDIA melhorada
configure_nvidia() {
    msg "Configurando drivers NVIDIA..."
    
    # 1. Blacklist do driver nouveau
    echo -e "${BLUE}Configurando blacklist para nouveau...${NC}"
    sudo tee /etc/modprobe.d/nvidia.conf > /dev/null << 'EOF'
# Desabilitar nouveau
blacklist nouveau
options nouveau modeset=0

# Habilitar NVIDIA
options nvidia_drm modeset=1
EOF
    
    # 2. Configuração do mkinitcpio
    if command -v mkinitcpio &> /dev/null; then
        msg "Atualizando initramfs..."
        
        # Backup do mkinitcpio.conf original se não existir
        if [ ! -f /etc/mkinitcpio.conf.backup ]; then
            sudo cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.backup
        fi
        
        # Remover "nouveau" dos hooks se existir
        sudo sed -i 's/\b nouveau\b//g' /etc/mkinitcpio.conf
        
        # Adicionar módulos NVIDIA se não estiverem presentes
        if ! grep -q "MODULES=.*nvidia" /etc/mkinitcpio.conf; then
            sudo sed -i '/^MODULES=/ s/)/ nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
        fi
        
        # Regenerar initramfs
        sudo mkinitcpio -P || {
            echo -e "${YELLOW}⚠️  mkinitcpio encontrou problemas, tentando continuar...${NC}"
        }
    fi
    
    # 3. Configuração do Xorg
    if [ ! -f /etc/X11/xorg.conf.d/10-nvidia.conf ]; then
        msg "Criando configuração do Xorg para NVIDIA..."
        sudo mkdir -p /etc/X11/xorg.conf.d
        
        sudo tee /etc/X11/xorg.conf.d/10-nvidia.conf > /dev/null << 'EOF'
Section "OutputClass"
    Identifier "nvidia"
    MatchDriver "nvidia-drm"
    Driver "nvidia"
    Option "AllowEmptyInitialConfiguration"
    Option "PrimaryGPU" "yes"
    ModulePath "/usr/lib/nvidia/xorg"
    ModulePath "/usr/lib/xorg/modules"
EndSection
EOF
    fi
    
    # 4. Configurar Wayland (opcional)
    if [ -f /etc/gdm/custom.conf ] || [ -f /etc/lightdm/lightdm.conf ]; then
        echo -e "${BLUE}Configurando variáveis de ambiente para NVIDIA...${NC}"
        
        # Adicionar ao /etc/environment sem sobrescrever
        grep -q "LIBVA_DRIVER_NAME=nvidia" /etc/environment 2>/dev/null || \
            echo "LIBVA_DRIVER_NAME=nvidia" | sudo tee -a /etc/environment > /dev/null
        
        grep -q "GBM_BACKEND=nvidia-drm" /etc/environment 2>/dev/null || \
            echo "GBM_BACKEND=nvidia-drm" | sudo tee -a /etc/environment > /dev/null
        
        grep -q "__GLX_VENDOR_LIBRARY_NAME=nvidia" /etc/environment 2>/dev/null || \
            echo "__GLX_VENDOR_LIBRARY_NAME=nvidia" | sudo tee -a /etc/environment > /dev/null
    fi
    
    # 5. Verificar módulos carregados
    msg "Verificando se módulos NVIDIA estão carregados..."
    if ! lsmod | grep -q nvidia; then
        echo -e "${YELLOW}Módulos NVIDIA não estão carregados${NC}"
        echo -e "${BLUE}Tentando carregar módulos...${NC}"
        sudo modprobe nvidia nvidia_modeset nvidia_uvm nvidia_drm 2>/dev/null || {
            echo -e "${YELLOW}⚠️  Não foi possível carregar módulos agora${NC}"
            echo -e "${YELLOW}  Eles serão carregados na próxima reinicialização${NC}"
        }
    else
        echo -e "${GREEN}✓ Módulos NVIDIA carregados com sucesso${NC}"
    fi
    
    # 6. Verificar se o driver está funcionando
    msg "Verificando status do driver NVIDIA..."
    if command -v nvidia-smi &> /dev/null; then
        echo -e "\n${GREEN}=== NVIDIA-SMI Output ===${NC}"
        nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader || \
            echo "nvidia-smi não conseguiu executar (pode precisar de reinicialização)"
        echo -e "${GREEN}=========================${NC}"
    else
        echo -e "${YELLOW}nvidia-smi não está disponível${NC}"
    fi
    
    msg "✅ Configuração NVIDIA concluída"
    echo -e "${YELLOW}⚠️  REINICIE O SISTEMA para que as mudanças tenham efeito completo!${NC}"
}

export_packages() {
    echo "Exporting installed packages for Arch Linux..."
    pacman -Qqe > "$HOME/package_list_arch.txt" 2>/dev/null || echo "Não foi possível exportar pacotes"
    echo "Packages exported to ~/package_list_arch.txt"
}

# Check if we should export packages and exit
if [ "$EXPORT_PACKAGES" = true ]; then
    export_packages
    exit 0
fi

# Banner
clear
echo -e "${CYAN}"
echo " +-+-+-+-+-+-+-+-+-+-+-+-+-+ "
echo " |o|w|h|s|k|a| "
echo " +-+-+-+-+-+-+-+-+-+-+-+-+-+ "
echo "  |s|e|t|u|p|  "
echo " +-+-+-+-+-+-+-+-+-+-+-+-+-+ "
echo -e "${NC}\n"

read -p "Install i3? (y/n) " -n 1 -r
echo
[[ ! $REPLY =~ ^[Yy]$ ]] && exit 1

# Update system
if [ "$ONLY_CONFIG" = false ]; then
    msg "Updating system..."
    sudo pacman -Syu --noconfirm --needed || {
        echo -e "${YELLOW}⚠️  Falha na atualização do sistema, continuando...${NC}"
    }

    install_yay || {
        echo -e "${YELLOW}⚠️  Continuando sem yay, usando pacman para pacotes AUR${NC}"
    }
else
    msg "Skipping system update (--only-config mode)"
fi

# Package groups for Arch Linux
PACKAGES_CORE=(
    xorg xorg-xinit xorg-xbacklight xbindkeys xdotool xinput
    base-devel i3-wm i3status sxhkd
    libnotify
)

PACKAGES_UI=(
    i3status rofi dunst feh lxappearance network-manager-applet lxsession
    polkit-gnome
)

PACKAGES_FILE_MANAGER=(
    thunar thunar-archive-plugin thunar-volman
    gvfs gvfs-smb udisks2 mtools dialog cifs-utils fd unzip
)

PACKAGES_AUDIO=(
    pavucontrol pulsemixer pamixer pipewire pipewire-pulse wireplumber
)

PACKAGES_UTILITIES=(
    avahi acpi acpid xfce4-power-manager
    flameshot qimgv micro xdg-user-dirs  
)

PACKAGES_TERMINAL=(
    neovim emacs ripgrep fzf eza
)

PACKAGES_FONTS=(
    ttf-dejavu ttf-font-awesome ttf-terminus-nerd
    noto-fonts noto-fonts-emoji
)

PACKAGES_BUILD=(
    cmake meson ninja curl pkg-config
)

PACKAGES_ARCH_SPECIFIC=(
    lightdm lightdm-gtk-greeter
    picom
    kitty
    yazi
    st
    gnome-themes-extra papirus-icon-theme
    tmux
)

# Install packages by group
if [ "$ONLY_CONFIG" = false ]; then
    msg "Installing core packages..."
    progress_install "Installing core packages" "${PACKAGES_CORE[@]}" || echo -e "${YELLOW}Falha em alguns pacotes core, continuando...${NC}"

    # Instalar drivers NVIDIA se não for pulado
    install_nvidia_drivers

    msg "Installing UI components..."
    progress_install "Installing UI packages" "${PACKAGES_UI[@]}" || echo -e "${YELLOW}Falha em alguns pacotes UI, continuando...${NC}"

    msg "Installing file manager..."
    progress_install "Installing file manager packages" "${PACKAGES_FILE_MANAGER[@]}" || echo -e "${YELLOW}Falha em alguns pacotes de file manager, continuando...${NC}"

    msg "Installing audio support..."
    progress_install "Installing audio packages" "${PACKAGES_AUDIO[@]}" || echo -e "${YELLOW}Falha em alguns pacotes de audio, continuando...${NC}"

    msg "Installing system utilities..."
    progress_install "Installing system packages" "${PACKAGES_UTILITIES[@]}" || echo -e "${YELLOW}Falha em alguns pacotes utilitários, continuando...${NC}"

    # Instalar Firefox
    progress_install "Installing Firefox" firefox || echo -e "${YELLOW}Falha ao instalar Firefox, continuando...${NC}"

    msg "Installing terminal tools..."
    progress_install "Installing terminal packages" "${PACKAGES_TERMINAL[@]}" || echo -e "${YELLOW}Falha em alguns pacotes de terminal, continuando...${NC}"

    msg "Installing fonts..."
    progress_install "Installing fonts packages" "${PACKAGES_FONTS[@]}" || echo -e "${YELLOW}Falha em algumas fontes, continuando...${NC}"

    msg "Installing build dependencies..."
    progress_install "Installing build packages" "${PACKAGES_BUILD[@]}" || echo -e "${YELLOW}Falha em algumas dependências de build, continuando...${NC}"

    msg "Installing Arch-specific packages..."
    progress_install "Installing Arch-specific packages" "${PACKAGES_ARCH_SPECIFIC[@]}" || echo -e "${YELLOW}Falha em alguns pacotes Arch-specific, continuando...${NC}"

    # Enable services
    sudo systemctl enable avahi-daemon acpid lightdm 2>/dev/null || true
else
    msg "Skipping package installation (--only-config mode)"
fi

# Handle existing config
if [ -d "$CONFIG_DIR" ]; then
    clear
    read -p "Found existing i3 config. Backup? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        mv "$CONFIG_DIR" "$CONFIG_DIR.bak.$(date +%s)"
        msg "Backed up existing config"
    else
        clear
        read -p "Overwrite without backup? (y/n) " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]] || die "Installation cancelled"
        rm -rf "$CONFIG_DIR"
    fi
fi

# Copy configs
msg "Setting up configuration..."
mkdir -p "$CONFIG_DIR"

# Copy i3 config files
if [ -d "$SCRIPT_DIR/i3" ]; then
    cp -r "$SCRIPT_DIR"/i3/* "$CONFIG_DIR"/ 2>/dev/null || echo -e "${YELLOW}Warning: Failed to copy some i3 config files${NC}"
else
    echo -e "${YELLOW}Warning: i3 config directory not found in $SCRIPT_DIR${NC}"
fi

# Make scripts executable
find "$CONFIG_DIR"/scripts -type f -exec chmod +x {} \; 2>/dev/null || true

# Setup directories
xdg-user-dirs-update 2>/dev/null || true
mkdir -p ~/Screenshots

# Install essential components
if [ "$ONLY_CONFIG" = false ]; then
    mkdir -p "$TEMP_DIR" && cd "$TEMP_DIR"

    msg "Configurando Kitty com transparência..."
    mkdir -p ~/.config/kitty

    cat > ~/.config/kitty/kitty.conf << 'EOF'
# Kitty config with transparency
font_family FiraCode Nerd Font
font_size 13.0

# Transparency
background_opacity 0.6

window_padding_width 40

# Mouse
mouse_hide_wait 3.0
url_color #0087bd
url_style curly

# Performance
repaint_delay 10
sync_to_monitor yes

# Terminal bell
enable_audio_bell no
EOF

    msg "Setting up Neovim config..."
    if [ ! -d "$HOME/.config/nvim" ]; then
        git clone https://github.com/owhska/nvim "$HOME/.config/nvim" 2>/dev/null || \
            echo -e "${YELLOW}Falha ao clonar configuração do Neovim${NC}"
    fi

    msg "Setting up Tmux config..."
    if [ ! -d "$HOME/.config/tmux" ]; then
        git clone https://github.com/owhska/tmux "$HOME/.config/tmux" 2>/dev/null || \
            echo -e "${YELLOW}Falha ao clonar configuração do Tmux${NC}"
    fi

    # Copy Emacs config
    msg "Installing Emacs config..."
    if [ -f "$SCRIPT_DIR/emacs/.emacs" ]; then
        cp "$SCRIPT_DIR/emacs/.emacs" "$HOME/.emacs"
        msg "Emacs config installed!"
    else
        msg "Warning: .emacs file not found inside emacs directory!"
    fi

    # Instalar fonts Fira Code do AUR se necessário
    if ! pacman -Qi ttf-firacode-nerd &>/dev/null; then
        msg "Installing FiraCode Nerd Font..."
        if command -v yay &> /dev/null; then
            yay -S --noconfirm ttf-firacode-nerd 2>/dev/null || \
                echo -e "${YELLOW}Falha ao instalar FiraCode Nerd Font${NC}"
        else
            msg "Note: yay not installed. Please install ttf-firacode-nerd manually from AUR"
        fi
    fi

    msg "Setting up wallpapers..."
    mkdir -p "$CONFIG_DIR/i3/wallpaper"

    # Copia wallpapers do diretório do script
    if [ -d "$SCRIPT_DIR/wallpaper" ]; then
        cp -r "$SCRIPT_DIR/wallpaper"/* "$CONFIG_DIR/i3/wallpaper/" 2>/dev/null || true
        msg "Wallpapers copied from script directory"

        # Verifica se o wall.jpg existe e configura como padrão
        if [ -f "$CONFIG_DIR/i3/wallpaper/wall.jpg" ]; then
            msg "Your wallpaper 'wall.jpg' found and set as default"
        else
            msg "Note: wall.jpg not found in wallpapers directory"
        fi
    else
        msg "Note: wallpapers directory not found in script folder"
    fi

    # Configuração do i3status
    msg "Setting up i3status configuration..."
    
    # Cria configuração do i3status se não existir
    if [ ! -f "$CONFIG_DIR/i3status.conf" ]; then
        msg "Creating i3status configuration..."
        cat > "$CONFIG_DIR/i3status.conf" << 'EOF'
general {
    output_format = "i3bar"
    colors = true
    interval = 5          # Atualiza a cada 5 segundos
}

# Ordem dos módulos exibidos (da esquerda para a direita)
#order += "wireless _first_"
order += "disk /"
#order += "battery all"
order += "cpu_usage"
order += "memory"
order += "time"
order += "ethernet _first_"

# Indicador de Ethernet simplificado
ethernet _first_ {
    format_up = "🌐 Online"
    format_down = "🌐 Offline"
}

# Mostra status da rede Wi-Fi
wireless _first_ {
    format_up = "WiFi: %quality at %essid"
    format_down = "WiFi: down"
}

# Mostra uso de CPU
cpu_usage {
    format = "CPU: %usage"
}

# Mostra uso de memória RAM
memory {
    format = "RAM: %used / %total"
    threshold_degraded = "10%"
    format_degraded = "MEMORY: %free"
}


# Mostra data e hora (no padrão do i3)
time {
    format = "%Y-%m-%d %H:%M:%S"
}

battery all {
    format = "%status %percentage %remaining"
    path = "/sys/class/power_supply/BAT%d/uevent"
    low_threshold = 10
}

disk "/" {
    format = "%free"
}
EOF
    fi

    # Optional tools
    clear
    read -p "Install optional tools (browsers, editors, etc)? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        msg "Installing optional tools..."
        optional_packages=(
            vim
            fastfetch
            python
            nodejs
            npm
        )
        progress_install "Installing optional tools" "${optional_packages[@]}" || \
            echo -e "${YELLOW}Some optional tools failed to install${NC}"
        msg "Optional tools installation completed"
    fi
else
    msg "Skipping external tool installation (--only-config mode)"
fi

# =============================================================================
# ZSH + Oh My Zsh + Plugins (VERSÃO SEGURA)
# =============================================================================
if [ "$ONLY_CONFIG" = false ]; then
    clear
    read -p "Instalar e configurar zsh + oh-my-zsh como padrão? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        msg "Instalando zsh e dependências..."
        sudo pacman -S --needed --noconfirm zsh curl git || {
            echo -e "${YELLOW}Falha ao instalar zsh ou dependências${NC}"
            echo -e "${YELLOW}Continuando sem zsh...${NC}"
        }

        # Verifica se o zsh foi instalado corretamente
        if command -v zsh &> /dev/null; then
            # Configura zsh no /etc/shells primeiro
            ZSH_PATH=$(which zsh)
            if ! grep -q "$ZSH_PATH" /etc/shells; then
                echo "$ZSH_PATH" | sudo tee -a /etc/shells
            fi

            msg "Instalando Oh My Zsh..."
            # Faz backup do .zshrc atual se existir
            if [ -f "$HOME/.zshrc" ]; then
                cp "$HOME/.zshrc" "$HOME/.zshrc.backup.$(date +%s)"
                msg "Backup do .zshrc existente criado"
            fi

            # Instala Oh My Zsh em modo não-interativo
            RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended 2>/dev/null || {
                echo -e "${YELLOW}Falha ao instalar Oh My Zsh${NC}"
            }

            msg "Instalando plugins populares do zsh..."
            ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

            # Instala plugins apenas se o Oh My Zsh foi instalado
            if [ -d "$ZSH_CUSTOM" ]; then
                git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM}/plugins/zsh-autosuggestions 2>/dev/null || true
                git clone https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting 2>/dev/null || true
                git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM}/plugins/zsh-completions 2>/dev/null || true
            else
                msg "Aviso: Diretório do Oh My Zsh não encontrado, pulando plugins..."
            fi

            msg "Configurando .zshrc personalizado..."
            # Cria .zshrc personalizado
            cat > "$HOME/.zshrc" << 'EOF'
# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"

plugins=(
    git
    zsh-autosuggestions
    zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}

# Aliases úteis
alias ls='eza --icons --group-directories-first'
alias ll='eza -la --icons --group-directories-first'
alias cls='clear'
alias ..='cd ..'
alias ...='cd ../..'
alias v='nvim'
alias c='clear'
alias q='exit'
alias f='yazi'
alias ff="fastfetch"
alias sai="sudo pacman -S"
alias sup="sudo pacman -Syu"
alias t="tmux"

# Git aliases
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph'
EOF

            # AGORA muda o shell padrão - APENAS no final de tudo
            msg "Definindo zsh como shell padrão para sessões futuras..."
            sudo chsh -s $(which zsh) $USER 2>/dev/null && \
                msg "zsh definido como shell padrão!" || \
                echo -e "${YELLOW}Não foi possível alterar o shell padrão${NC}"

            msg "zsh + oh-my-zsh instalados com sucesso!"
            echo -e "${GREEN}Na próxima vez que você fizer login ou abrir um novo terminal, o zsh será ativado automaticamente!${NC}"

            # Apenas informa o usuário sem executar o zsh
            echo
            echo -e "${CYAN}Para ativar o zsh AGORA (opcional), execute:${NC}"
            echo -e "${CYAN}  exec zsh${NC}"
            echo -e "${CYAN}Ou simplesmente feche e reabra o terminal.${NC}"
        else
            echo -e "${YELLOW}zsh não foi instalado corretamente, continuando sem zsh${NC}"
        fi
    fi
else
    msg "Pulando instalação do zsh/oh-my-zsh (--only-config mode)"
fi

# Done
echo -e "\n${GREEN}✅ Installation complete!${NC}"
echo ""
echo "================================================"
echo "Próximos passos:"
echo "1. REINICIE O SISTEMA para aplicar todas as mudanças"
echo "2. Faça login e selecione 'i3' no gerenciador de display"
echo "3. Pressione Super+Z para ver os atalhos do teclado"
echo ""
echo "Para problemas com NVIDIA:"
echo "- Reinicie o sistema primeiro"
echo "- Se ainda tiver problemas: sudo nvidia-xconfig"
echo "- Verifique logs: journalctl -xe | grep -i nvidia"
echo "================================================"
echo ""
echo "Log completo da instalação: $LOG_FILE"
