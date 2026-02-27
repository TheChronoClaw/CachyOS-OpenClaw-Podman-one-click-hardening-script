#!/bin/bash
# ==============================================================================
# Btrfs + Snapper One-Click Setup Script
# For: CachyOS / Arch Linux
# Version: 1.2.0-Fix
# Author: TheChronoClaw
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_root() {
    if [ "$UID" -ne 0 ]; then
        echo -e "${RED}ERROR: Please run as root (sudo $0)${NC}"
        exit 1
    fi
}

check_root

echo -e "\n${GREEN}=============================================${NC}"
echo -e "${GREEN} Btrfs + Snapper Automatic Setup Script ${NC}"
echo -e "${GREEN}=============================================${NC}\n"

# Install dependencies
echo "[1/6] Checking and installing required tools..."
if ! command -v snapper &> /dev/null; then
    if [ -f /var/lib/pacman/db.lck ]; then
        echo -e "${YELLOW}WARNING: Pacman lock found, removing...${NC}"
        rm -f /var/lib/pacman/db.lck
    fi
    pacman -Syu --needed --noconfirm snapper btrfs-progs inotify-tools
else
    echo "✅ snapper already installed, skipping."
fi

# Check root filesystem
echo -e "\n[2/6] Detecting root filesystem..."
ROOT_DEV=$(findmnt / -o SOURCE -n)
ROOT_FS=$(findmnt / -o FSTYPE -n)

if [ "$ROOT_FS" != "btrfs" ]; then
    echo -e "${RED}ERROR: Root filesystem is not Btrfs${NC}"
    exit 1
fi

echo -e "✅ Root device: ${GREEN}$ROOT_DEV${NC}"

# Create .snapshots subvolume
echo -e "\n[3/6] Creating .snapshots subvolume..."
MOUNT_POINT_TMP="/mnt/btrfs-root-tmp"
mkdir -p "$MOUNT_POINT_TMP"

if mountpoint -q "$MOUNT_POINT_TMP"; then
    umount "$MOUNT_POINT_TMP"
fi

mount -o subvolid=5 "$ROOT_DEV" "$MOUNT_POINT_TMP"

if btrfs subvolume show "$MOUNT_POINT_TMP/.snapshots" &>/dev/null; then
    echo "⚠️  .snapshots already exists, skipping."
else
    btrfs subvolume create "$MOUNT_POINT_TMP/.snapshots"
    echo "✅ .snapshots subvolume created."
fi

umount "$MOUNT_POINT_TMP"
rmdir "$MOUNT_POINT_TMP"

# Configure fstab and mount
echo -e "\n[4/6] Configuring /etc/fstab..."
TARGET_DIR="/.snapshots"
mkdir -p "$TARGET_DIR"
chmod 0750 "$TARGET_DIR"
chown root:root "$TARGET_DIR"

UUID=$(blkid -s UUID -o value "$ROOT_DEV")
cp /etc/fstab /etc/fstab.bak.$(date +%s)
sed -i '/\/\.snapshots.*btrfs/d' /etc/fstab
echo "UUID=$UUID $TARGET_DIR btrfs rw,relatime,subvol=/.snapshots 0 0" >> /etc/fstab

if mountpoint -q "$TARGET_DIR"; then
    umount "$TARGET_DIR"
fi
mount "$TARGET_DIR"

if mountpoint -q "$TARGET_DIR"; then
    echo "✅ /.snapshots mounted successfully."
else
    echo -e "${RED}ERROR: Failed to mount /.snapshots${NC}"
    exit 1
fi

# Configure Snapper
echo -e "\n[5/6] Setting up Snapper..."
CONFIG_NAME="root"

if snapper -c "$CONFIG_NAME" list-config &>/dev/null; then
    echo "⚠️  Old config found, recreating..."
    snapper -c "$CONFIG_NAME" delete-config || true
fi

snapper -c "$CONFIG_NAME" create-config /

CONF_FILE="/etc/snapper/configs/$CONFIG_NAME"
sed -i 's|^SUBVOLUME=.*|SUBVOLUME=/|' "$CONF_FILE"

# Enable services
echo -e "\n[6/6] Enabling services..."
systemctl daemon-reload
systemctl enable --now snapperd.service
systemctl enable --now snapper-timeline.timer
systemctl enable --now snapper-cleanup.timer

echo -e "\n${GREEN}=============================================${NC}"
echo -e "${GREEN}✅ Btrfs + Snapper setup completed!${NC}"
echo -e "Test: snapper list"
echo -e "${GREEN}=============================================${NC}\n"
