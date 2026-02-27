#!/bin/bash
# ==============================================================================
# Podman + GPU Acceleration One-Click Setup
# For: CachyOS / Arch Linux
# Version: 1.0.0-Fixed
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;2;32m'
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

echo -e "\n${GREEN}=====================================================${NC}"
echo -e "${GREEN}    Podman + GPU Acceleration Setup Script            ${NC}"
echo -e "${GREEN}=====================================================${NC}\n"

# --------------------------------------------------------------------------
# Step 1: Install dependencies
# --------------------------------------------------------------------------
echo -e "${BLUE}[1/5] Installing required packages...${NC}"

pacman -Syu --needed --noconfirm \
    podman \
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

# Install NVIDIA stuff if NVIDIA GPU exists
if lspci | grep -i -q "nvidia"; then
    echo -e "${YELLOW}NVIDIA GPU detected, installing NVIDIA container toolkit...${NC}"
    pacman -S --needed --noconfirm \
        nvidia-container-toolkit \
        nvidia-container-runtime \
        lib32-nvidia-utils
fi

# --------------------------------------------------------------------------
# Step 2: Configure user namespaces
# --------------------------------------------------------------------------
echo -e "${BLUE}[2/5] Configuring user namespace mappings...${NC}"

# Ensure files exist
touch /etc/subuid /etc/subgid

USER_NAME="${SUDO_USER:-$USER}"
USER_UID=$(id -u "$USER_NAME")

if ! grep -q "^$USER_NAME:" /etc/subuid; then
    echo "$USER_NAME:$USER_UID:1" >> /etc/subuid
    echo "$USER_NAME:100000:65536" >> /etc/subuid
fi

if ! grep -q "^$USER_NAME:" /etc/subgid; then
    echo "$USER_NAME:$USER_UID:1" >> /etc/subgid
    echo "$USER_NAME:100000:65536" >> /etc/subgid
fi

# --------------------------------------------------------------------------
# Step 3: Fix GPU / DRI permissions
# --------------------------------------------------------------------------
echo -e "${BLUE}[3/5] Setting GPU permissions...${NC}"

usermod -aG video "$USER_NAME"
usermod -aG render "$USER_NAME"
usermod -aG input "$USER_NAME"

# Fix render group permissions safely
if [ -d /dev/dri ]; then
    chown -R root:render /dev/dri
    chmod -R 770 /dev/dri
fi

# --------------------------------------------------------------------------
# Step 4: Configure podman for GPU
# --------------------------------------------------------------------------
echo -e "${BLUE}[4/5] Configuring podman for GPU...${NC}"

mkdir -p /etc/containers
mkdir -p /etc/containers/registries.d

# Setup basic podman config if missing
if [ ! -f /etc/containers/containers.conf ]; then
    cat > /etc/containers/containers.conf << EOF
[containers]
default_capabilities = [
    "AUDIT_WRITE",
    "CHOWN",
    "DAC_OVERRIDE",
    "FOWNER",
    "FSETID",
    "KILL",
    "MKNOD",
    "NET_BIND_SERVICE",
    "NET_RAW",
    "SETFCAP",
    "SETGID",
    "SETPCAP",
    "SETUID",
    "SYS_CHROOT"
]
volumes = ["/etc/localtime:/etc/localtime:ro"]

[engine]
cgroup_manager = "systemd"
events_logger = "file"

[engine.runtimes]
runc = ["/usr/bin/runc"]
crun = ["/usr/bin/crun"]
EOF
fi

# NVIDIA config
if lspci | grep -i -q "nvidia"; then
    mkdir -p /etc/nvidia-container-runtime
    if [ ! -f /etc/nvidia-container-runtime/config.toml ]; then
        nvidia-container-toolkit configure
    fi
fi

# --------------------------------------------------------------------------
# Step 5: Start services
# --------------------------------------------------------------------------
echo -e "${BLUE}[5/5] Starting podman services...${NC}"

systemctl daemon-reload
systemctl enable --now podman.socket
systemctl enable --now podman-restart.service

echo -e "\n${GREEN}=====================================================${NC}"
echo -e "${GREEN}✅ Podman + GPU setup completed!${NC}"
echo -e "Test with: podman run --rm --gpus all <your-gpu-image>${NC}"
echo -e "${GREEN}=====================================================${NC}\n"
