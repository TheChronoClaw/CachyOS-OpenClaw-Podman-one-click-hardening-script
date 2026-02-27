#!/bin/bash
# ==============================================================================
# Podman + GPU Acceleration One-Click Setup (Fixed Version)
# For: CachyOS / Arch Linux
# Version: 1.0.1-Fixed
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
    echo -e "${RED}ERROR: Could not determine the target user. Please run with sudo.${NC}"
    exit 1
fi

echo -e "\n${GREEN}=====================================================${NC}"
echo -e "${GREEN}    Podman + GPU Acceleration Setup Script            ${NC}"
echo -e "${GREEN}    Target User: $USER_NAME                           ${NC}"
echo -e "${GREEN}=====================================================${NC}\n"

# --------------------------------------------------------------------------
# Step 1: Install dependencies
# --------------------------------------------------------------------------
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
if lspci | grep -i -q "nvidia"; then
    HAS_NVIDIA=true
    echo -e "${YELLOW}NVIDIA GPU detected.${NC}"
    pacman -S --needed --noconfirm \
        nvidia-container-toolkit \
        nvidia-utils \
        lib32-nvidia-utils
fi

HAS_AMD=false
if lspci | grep -i -q "amd" | grep -iE "vga|3d"; then
    HAS_AMD=true
    echo -e "${YELLOW}AMD GPU detected.${NC}"
fi

HAS_INTEL=false
if lspci | grep -iE "intel.*(vga|3d)"; then
    HAS_INTEL=true
    echo -e "${YELLOW}Intel GPU detected.${NC}"
fi

# --------------------------------------------------------------------------
# Step 2: Configure user namespaces
# --------------------------------------------------------------------------
echo -e "${BLUE}[2/5] Configuring user namespace mappings for $USER_NAME...${NC}"

touch /etc/subuid /etc/subgid
USER_UID=$(id -u "$USER_NAME")

sed -i "/^$USER_NAME:/d" /etc/subuid
sed -i "/^$USER_NAME:/d" /etc/subgid

echo "$USER_NAME:100000:65536" >> /etc/subuid
echo "$USER_NAME:100000:65536" >> /etc/subgid

echo "✅ Subuid/Subgid configured."

# --------------------------------------------------------------------------
# Step 3: Persistent GPU Permissions via UDEV
# --------------------------------------------------------------------------
echo -e "${BLUE}[3/5] Setting persistent GPU permissions via udev rules...${NC}"

UDEV_RULE="/etc/udev/rules.d/99-podman-gpu.rules"
cat > "$UDEV_RULE" << 'EOF'
# Allow users in 'render' and 'video' groups to access GPU devices
KERNEL=="renderD*", GROUP="render", MODE="0660"
KERNEL=="card*", GROUP="video", MODE="0660"
# NVIDIA specific
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

echo "✅ Udev rules created and triggered. User added to groups."

# --------------------------------------------------------------------------
# Step 4: Configure Podman for GPU
# --------------------------------------------------------------------------
echo -e "${BLUE}[4/5] Configuring Podman engine...${NC}"

mkdir -p /etc/containers
CONF_FILE="/etc/containers/containers.conf"
BACKUP_FILE="$CONF_FILE.bak.$(date +%s)"

[ -f "$CONF_FILE" ] && cp "$CONF_FILE" "$BACKUP_FILE"
touch "$CONF_FILE"

if ! grep -q "^\[engine\]" "$CONF_FILE"; then
    echo -e "\n[engine]" >> "$CONF_FILE"
fi

if ! grep -q "^default_runtime =" "$CONF_FILE"; then
    echo 'default_runtime = "crun"' >> "$CONF_FILE"
else
    sed -i 's|^default_runtime = .*|default_runtime = "crun"|' "$CONF_FILE"
fi

if [ "$HAS_NVIDIA" = true ]; then
    if ! grep -q "^\[engine.runtimes\]" "$CONF_FILE"; then
        echo -e "\n[engine.runtimes]" >> "$CONF_FILE"
    fi
    if ! grep -q "^nvidia =" "$CONF_FILE"; then
        echo 'nvidia = ["/usr/bin/nvidia-container-runtime", "/usr/bin/crun", "/usr/bin/runc"]' >> "$CONF_FILE"
    else
        sed -i 's|^nvidia = .*|nvidia = ["/usr/bin/nvidia-container-runtime", "/usr/bin/crun", "/usr/bin/runc"]|' "$CONF_FILE"
    fi

    if command -v nvidia-ctk &>/dev/null; then
        echo "Configuring NVIDIA Container Toolkit for Podman..."
        nvidia-ctk runtime configure --runtime=podman --config=/etc/containers/containers.conf || true
    elif command -v nvidia-container-toolkit &>/dev/null; then
        echo "Legacy NVIDIA toolkit detected, using automatic hooks."
    fi
fi

echo "✅ Podman configuration updated."

# --------------------------------------------------------------------------
# Step 5: Enable Services
# --------------------------------------------------------------------------
echo -e "${BLUE}[5/5] Enabling services...${NC}"

systemctl daemon-reload
systemctl enable --now podman.socket

echo -e "${YELLOW}Enabling linger for $USER_NAME...${NC}"
loginctl enable-linger "$USER_NAME"

sudo -u "$USER_NAME" systemctl --user daemon-reload
sudo -u "$USER_NAME" systemctl --user enable --now podman.socket

echo -e "\n${GREEN}=====================================================${NC}"
echo -e "${GREEN}✅ Podman + GPU Acceleration Setup Completed!${NC}"
echo -e " Test:  podman run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi${NC}"
echo -e "${GREEN}=====================================================${NC}\n"
