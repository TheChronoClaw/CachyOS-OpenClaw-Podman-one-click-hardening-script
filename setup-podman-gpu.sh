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

# 获取实际执行 sudo 的用户名
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

# Detect GPU and install specific tools
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
if lspci | grep -i -q "amd.*vga\|amd.*3d"; then
    HAS_AMD=true
    echo -e "${YELLOW}AMD GPU detected.${NC}"
fi

HAS_INTEL=false
if lspci | grep -i -q "intel.*vga\|intel.*3d"; then
    HAS_INTEL=true
    echo -e "${YELLOW}Intel GPU detected.${NC}"
fi

# --------------------------------------------------------------------------
# Step 2: Configure user namespaces (Rootless support)
# --------------------------------------------------------------------------
echo -e "${BLUE}[2/5] Configuring user namespace mappings for $USER_NAME...${NC}"

# Ensure files exist
touch /etc/subuid /etc/subgid

USER_UID=$(id -u "$USER_NAME")

# Remove existing entries for this user to avoid duplicates/conflicts before adding fresh ones
sed -i "/^$USER_NAME:/d" /etc/subuid
sed -i "/^$USER_NAME:/d" /etc/subgid

# Add standard mapping: user -> 100000 (count 65536)
# This is required for rootless containers to map internal root to non-root host users
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

# Trigger udev to apply rules immediately without reboot
udevadm control --reload-rules
udevadm trigger

# Add user to necessary groups
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

# Create/Update containers.conf
CONF_FILE="/etc/containers/containers.conf"
BACKUP_FILE="$CONF_FILE.bak.$(date +%s)"

if [ ! -f "$CONF_FILE" ]; then
    touch "$CONF_FILE"
else
    cp "$CONF_FILE" "$BACKUP_FILE"
fi

# We need to ensure the [engine] section has the correct runtime settings
# Using a temp file for safe editing
TEMP_CONF=$(mktemp)

# If file is empty or doesn't have [engine], append basic structure
if ! grep -q "$$engine$$" "$CONF_FILE"; then
    echo "[engine]" >> "$CONF_FILE"
fi

# Configure default runtime to crun (better for rootless)
if ! grep -q "^default_runtime =" "$CONF_FILE"; then
    echo 'default_runtime = "crun"' >> "$CONF_FILE"
else
    sed -i 's|^default_runtime = .*|default_runtime = "crun"|' "$CONF_FILE"
fi

# Configure Runtimes specifically for NVIDIA if needed
if [ "$HAS_NVIDIA" = true ]; then
    # Ensure nvidia runtime is defined
    if ! grep -q "$$engine.runtimes$$" "$CONF_FILE"; then
        echo "" >> "$CONF_FILE"
        echo "[engine.runtimes]" >> "$CONF_FILE"
    fi
    
    # Check if nvidia runtime entry exists, if not add it
    if ! grep -q "^nvidia =" "$CONF_FILE"; then
        echo 'nvidia = ["/usr/bin/nvidia-container-runtime", "/usr/bin/crun", "/usr/bin/runc"]' >> "$CONF_FILE"
    else
        # Update existing line to ensure path is correct
        sed -i 's|^nvidia = .*|nvidia = ["/usr/bin/nvidia-container-runtime", "/usr/bin/crun", "/usr/bin/runc"]|' "$CONF_FILE"
    fi
    
    # Configure the toolkit itself for Podman
    if command -v nvidia-ctk &> /dev/null; then
        echo "Configuring NVIDIA Container Toolkit for Podman..."
        nvidia-ctk runtime configure --runtime=podman --config=/etc/containers/containers.conf || true
    elif command -v nvidia-container-toolkit &> /dev/null;
        # Fallback for older versions, though nvidia-ctk is preferred now
        echo "Legacy toolkit detected, attempting generic config..."
        # The hook should be picked up automatically if installed correctly, 
        # but explicit config in containers.conf is safer.
    fi
fi

echo "✅ Podman configuration updated."

# --------------------------------------------------------------------------
# Step 5: Enable Services (Rootless focused)
# --------------------------------------------------------------------------
echo -e "${BLUE}[5/5] Enabling services...${NC}"

systemctl daemon-reload

# Enable system socket (for rootful usage if needed)
systemctl enable --now podman.socket

# IMPORTANT: Enable user-level socket for the target user for Rootless operation
# We use machinectl to run this as the user, or instruct the user to do it.
# Since we are root, we can't easily enable --user services for another user without logging in as them.
# Best practice: Tell the user to run the command, OR use loginctl enable-linger and run as that user.

echo -e "${YELLOW}NOTE: Rootless Podman socket requires user context.${NC}"
echo "Enabling linger for $USER_NAME to allow user services without login..."
loginctl enable-linger "$USER_NAME"

# Run the user-level enable command as the target user
su - "$USER_NAME" -c "systemctl --user daemon-reload"
su - "$USER_NAME" -c "systemctl --user enable --now podman.socket"

echo "✅
