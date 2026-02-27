#!/bin/bash
# ==============================================================================
# Podman + GPU Acceleration One-Click Setup (Final Fixed Version)
# For: CachyOS / Arch Linux
# Version: 1.0.3-Final
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

check_root() {
    if [ "$UID" -ne 0 ]; then
        echo -e "${RED}ERROR: Please run as root (sudo $0)${NC}"
        exit 1
    fi
}

check_root

if [ -n "${SUDO_USER:-}" ]; then
    USER_NAME="$SUDO_USER"
else
    echo -e "${RED}ERROR: Could not determine target user. Please run with sudo.${NC}"
    exit 1
fi

echo -e "\n${GREEN}=====================================================${NC}"
echo -e "${GREEN}    Podman + GPU Acceleration Setup Script            ${NC}"
echo -e "${GREEN}    Target User: $USER_NAME                           ${NC}"
echo -e "${GREEN}=====================================================${NC}\n"

# Install dependencies
echo -e "${BLUE}[1/5] Installing required packages...${NC}"

pacman -Syu --needed --noconfirm \
    podman \
    crun \
    btrfs-progs \
    udev \
    pciutils \
    mesa \
    libva-mesa-driver \
    vulkan-icd-loader \
    vulkan-radeon \
    vulkan-intel \
    egl-wayland \
    libglvnd \
    inotify-tools

HAS_NVIDIA=false
HAS_AMD=false
HAS_INTEL=false

# Detect NVIDIA GPU
if lspci | grep -iq "nvidia"; then
    HAS_NVIDIA=true
    echo -e "${YELLOW}NVIDIA GPU detected.${NC}"
    pacman -S --needed --noconfirm \
        nvidia-container-toolkit \
        nvidia-utils \
        lib32-nvidia-utils
fi

# Detect AMD GPU
if lspci | grep -iE "VGA compatible controller|3D controller" | grep -iq "amd\|advanced micro devices"; then
    HAS_AMD=true
    echo -e "${YELLOW}AMD GPU detected.${NC}"
fi

# Detect Intel GPU
if lspci | grep -iE "VGA compatible controller|3D controller" | grep -iq "intel"; then
    HAS_INTEL=true
    echo -e "${YELLOW}Intel GPU detected.${NC}"
fi

# Configure user namespaces for rootless
echo -e "${BLUE}[2/5] Configuring user namespace mappings for $USER_NAME...${NC}"

touch /etc/subuid /etc/subgid
sed -i "/^$USER_NAME:/d" /etc/subuid
sed -i "/^$USER_NAME:/d" /etc/subgid

echo "$USER_NAME:100000:65536" >> /etc/subuid
echo "$USER_NAME:100000:65536" >> /etc/subgid

echo "✅ Subuid/Subgid configured."

# Set persistent GPU permissions
echo -e "${BLUE}[3/5] Setting persistent GPU permissions via udev rules...${NC}"

UDEV_RULE="/etc/udev/rules.d/99-podman-gpu.rules"
cat > "$UDEV_RULE" << 'EOF'
KERNEL=="renderD*", GROUP="render", MODE="0660"
KERNEL=="card*", GROUP="video", MODE="0660"
KERNEL=="nvidia*", GROUP="video", MODE="0660"
KERNEL=="nvidiactl", GROUP="video", MODE="0660"
KERNEL=="nvidia-uvm*", GROUP="video", MODE="0660"
EOF

udevadm control --reload-rules
udevadm trigger

GROUPS=("video" "render" "input")
for grp in "${GROUPS[@]}"; do
    if getent group "$grp" > /dev/null; then
        usermod -aG "$grp" "$USER_NAME"
    fi
done

echo "✅ Udev rules applied."

# Configure Podman
echo -e "${BLUE}[4/5] Configuring Podman engine...${NC}"

mkdir -p /etc/containers
CONF_FILE="/etc/containers/containers.conf"
BACKUP_FILE="$CONF_FILE.bak.$(date +%s)"

[ -f "$CONF_FILE" ] && cp "$CONF_FILE" "$BACKUP_FILE"

if ! grep -q "^\[engine\]" "$CONF_FILE" 2>/dev/null; then
    echo -e "\n[engine]" >> "$CONF_FILE"
fi

if ! grep -q "^default_runtime" "$CONF_FILE"; then
    echo 'default_runtime = "crun"' >> "$CONF_FILE"
else
    sed -i 's|^default_runtime = .*|default_runtime = "crun"|' "$CONF_FILE"
fi

# NVIDIA runtime configuration
if [ "$HAS_NVIDIA" = true ]; then
    if command -v nvidia-ctk &>/dev/null; then
        echo "Configuring NVIDIA Container Toolkit..."
        nvidia-ctk runtime configure --runtime=podman --config="$CONF_FILE" --cgroup-manager=systemd || true

        if grep -q "nvidia-container-runtime" "$CONF_FILE"; then
            echo "✅ NVIDIA runtime configured."
        else
            echo -e "${YELLOW}Warning: NVIDIA runtime verification failed.${NC}"
        fi
    else
        echo -e "${YELLOW}Warning: nvidia-ctk not found.${NC}"
    fi
fi

echo "✅ Podman configuration updated."

# Enable services
echo -e "${BLUE}[5/5] Enabling services...${NC}"

systemctl daemon-reload
systemctl enable --now podman.socket

echo -e "${YELLOW}Enabling linger for $USER_NAME...${NC}"
loginctl enable-linger "$USER_NAME"

if machinectl shell "$USER_NAME"@.host "/usr/bin/systemctl --user daemon-reload" &>/dev/null; then
    machinectl shell "$USER_NAME"@.host "/usr/bin/systemctl --user enable --now podman.socket" &>/dev/null || true
    echo "✅ User podman socket started."
else
    echo -e "${YELLOW}Note: User service will start on next login.${NC}"
fi

echo -e "\n${GREEN}=====================================================${NC}"
echo -e "${GREEN}✅ Podman + GPU Acceleration Setup Completed!${NC}"
if [ "$HAS_NVIDIA" = true ]; then
    echo -e " Test NVIDIA: podman run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi"
elif [ "$HAS_AMD" = true ]; then
    echo -e " Test AMD:    podman run --rm --device /dev/kfd --device /dev/dri rocm/dev-centos-7 rocm-smi"
elif [ "$HAS_INTEL" = true ]; then
    echo -e " Test Intel:  podman run --rm --device /dev/dri intel/intel-opencl-cluster:latest clinfo"
fi
echo -e "${GREEN}=====================================================${NC}\n"
