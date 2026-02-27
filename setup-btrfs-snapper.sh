#!/bin/bash
# ==============================================================================
# Btrfs + Snapper Auto Setup Script (Fixed Enhanced)
# For: CachyOS / Arch Linux
# Function: Auto-detect root partition, create subvolumes, configure Snapper, enable services
# Version: 1.2.0-Fix
# Author: TheChronoClaw (Modified & Fixed by Assistant)
# ==============================================================================

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# ------------------------------------------------------------------------------
# 1. Install dependencies
# ------------------------------------------------------------------------------
echo "[1/6] Checking and installing required tools..."
if ! command -v snapper &> /dev/null; then
    # Remove pacman lock if exists
    if [ -f /var/lib/pacman/db.lck ]; then
        echo -e "${YELLOW}WARNING: Pacman lock found, attempting to remove...${NC}"
        rm -f /var/lib/pacman/db.lck
    fi
    pacman -Syu --needed --noconfirm snapper btrfs-progs inotify-tools
else
    echo "✅ snapper is already installed, skipping."
fi

# ------------------------------------------------------------------------------
# 2. Check if root filesystem is Btrfs
# ------------------------------------------------------------------------------
echo -e "\n[2/6] Detecting root filesystem type..."
ROOT_DEV=$(findmnt / -o SOURCE -n)
ROOT_FS=$(findmnt / -o FSTYPE -n)

if [ "$ROOT_FS" != "btrfs" ]; then
  echo -e "${RED}ERROR: Root filesystem ($ROOT_FS) is not Btrfs, aborting.${NC}"
  exit 1
fi

echo -e "✅ Root device detected: ${GREEN}$ROOT_DEV${NC}"

# ------------------------------------------------------------------------------
# 3. Create standard .snapshots subvolume
# ------------------------------------------------------------------------------
echo -e "\n[3/6] Creating .snapshots subvolume..."
MOUNT_POINT_TMP="/mnt/btrfs-root-tmp"
mkdir -p "$MOUNT_POINT_TMP"

# Prevent duplicate mount
if mountpoint -q "$MOUNT_POINT_TMP"; then
    umount "$MOUNT_POINT_TMP"
fi

mount -o subvolid=5 "$ROOT_DEV" "$MOUNT_POINT_TMP"

# Check if subvolume already exists
if btrfs subvolume show "$MOUNT_POINT_TMP/.snapshots" &>/dev/null; then
    echo "⚠️  Subvolume .snapshots already exists, skipping."
else
    btrfs subvolume create "$MOUNT_POINT_TMP/.snapshots"
    echo "✅ Subvolume .snapshots created successfully."
fi

umount "$MOUNT_POINT_TMP"
rmdir "$MOUNT_POINT_TMP"

# ------------------------------------------------------------------------------
# 4. Configure /etc/fstab for /.snapshots
# ------------------------------------------------------------------------------
echo -e "\n[4/6] Configuring /etc/fstab for /.snapshots..."
TARGET_DIR="/.snapshots"

if [ ! -d "$TARGET_DIR" ]; then
    mkdir -p "$TARGET_DIR"
fi

chmod 0750 "$TARGET_DIR"
chown root:root "$TARGET_DIR"

UUID=$(blkid -s UUID -o value "$ROOT_DEV")

# Backup fstab
cp /etc/fstab /etc/fstab.bak.$(date +%s)

# Remove old entries
sed -i '/\/\.snapshots.*btrfs/d' /etc/fstab

# Add new mount entry
echo "UUID=$UUID $TARGET_DIR btrfs rw,relatime,subvol=/.snapshots 0 0" >> /etc/fstab

# Mount immediately
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

# ------------------------------------------------------------------------------
# 5. Configure Snapper
# ------------------------------------------------------------------------------
echo -e "\n[5/6] Initializing Snapper configuration..."
CONFIG_NAME="root"

# Remove existing config if present
if snapper -c "$CONFIG_NAME" list-config &>/dev/null; then
    echo "⚠️  Existing config '$CONFIG_NAME' found, recreating..."
    snapper -c "$CONFIG_NAME" delete-config || true
fi

# Create config for /
snapper -c "$CONFIG_NAME" create-config /

# Verify and fix config
CONF_FILE="/etc/snapper/configs/$CONFIG_NAME"
if [ -f "$CONF_FILE" ]; then
    sed -i 's|^SUBVOLUME=.*|SUBVOLUME=/|' "$CONF_FILE"
    echo "✅ Snapper configuration updated."
else
    echo -e "${RED}ERROR: Configuration file not generated${NC}"
    exit 1
fi

# ------------------------------------------------------------------------------
# 6. Enable and start services
# ------------------------------------------------------------------------------
echo -e "\n[6/6] Starting Snapper services..."

systemctl daemon-reload
systemctl enable --now snapperd.service
systemctl enable --now snapper-timeline.timer
systemctl enable --now snapper-cleanup.timer

echo -e "\n${GREEN}=============================================${NC}"
echo -e "${GREEN}✅ Btrfs + Snapper setup completed!${NC}"
echo -e "📌 Test: snapper list"
echo -e "📌 Create snapshot: snapper -c root create --description \"test\""
echo -e "${GREEN}=============================================${NC}\n"
