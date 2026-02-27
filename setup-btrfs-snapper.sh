#!/bin/bash
# ==============================================================================
# Btrfs + Snapper One-Click Setup Script (Fixed Version)
# For: CachyOS / Arch Linux
# Version: 1.2.1-Fixed
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

echo -e "\n[2/6] Detecting root filesystem..."
ROOT_DEV=$(findmnt / -o SOURCE -n)
ROOT_FS=$(findmnt / -o FSTYPE -n)

if [ "$ROOT_FS" != "btrfs" ]; then
    echo -e "${RED}ERROR: Root filesystem is not Btrfs${NC}"
    exit 1
fi

ROOT_SUBVOL_ID=$(btrfs inspect-internal rootid /)
if [ "$ROOT_SUBVOL_ID" != "5" ]; then
    echo -e "${YELLOW}WARNING: Root '/' is not the top-level subvolume (ID: $ROOT_SUBVOL_ID).${NC}"
    echo -e "${YELLOW}This script expects a flat layout where '/' is subvolid 5.${NC}"
    echo -e "${YELLOW}If you are using a '@' subvolume layout, this script might create inconsistent snapshots.${NC}"
    read -p "Do you want to continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo -e "✅ Root device: ${GREEN}$ROOT_DEV${NC} (Subvol ID: $ROOT_SUBVOL_ID)"

echo -e "\n[3/6] Creating .snapshots subvolume..."
MOUNT_POINT_TMP="/mnt/btrfs-root-tmp"
mkdir -p "$MOUNT_POINT_TMP"

if mountpoint -q "$MOUNT_POINT_TMP"; then
    umount -f "$MOUNT_POINT_TMP" || true
fi

mount -o subvolid=5 "$ROOT_DEV" "$MOUNT_POINT_TMP"

if btrfs subvolume show "$MOUNT_POINT_TMP/.snapshots" &>/dev/null; then
    echo "⚠️  .snapshots already exists, skipping creation."
else
    btrfs subvolume create "$MOUNT_POINT_TMP/.snapshots"
    echo "✅ .snapshots subvolume created."
fi

umount -f "$MOUNT_POINT_TMP"
rmdir "$MOUNT_POINT_TMP"

echo -e "\n[4/6] Configuring /etc/fstab..."
TARGET_DIR="/.snapshots"
mkdir -p "$TARGET_DIR"
chmod 0750 "$TARGET_DIR"
chown root:root "$TARGET_DIR"

UUID=$(blkid -s UUID -o value "$ROOT_DEV")
FSTAB_BACKUP="/etc/fstab.bak.$(date +%s)"
cp /etc/fstab "$FSTAB_BACKUP"

sed -i '\|^.*'"$TARGET_DIR"'.*btrfs.*|d' /etc/fstab

echo "UUID=$UUID $TARGET_DIR btrfs rw,relatime,subvol=/.snapshots 0 0" >> /etc/fstab

if mountpoint -q "$TARGET_DIR"; then
    umount -f "$TARGET_DIR" || true
fi

if ! mount -o subvol=/.snapshots "$ROOT_DEV" "$TARGET_DIR"; then
    echo -e "${RED}ERROR: Failed to manually mount /.snapshots. Restoring fstab...${NC}"
    cp "$FSTAB_BACKUP" /etc/fstab
    exit 1
fi

echo "✅ /.snapshots mounted successfully."

echo -e "\n[5/6] Setting up Snapper..."
CONFIG_NAME="root"

if snapper -c "$CONFIG_NAME" list-config &>/dev/null; then
    echo "⚠️  Old config '$CONFIG_NAME' found, recreating..."
    snapper -c "$CONFIG_NAME" delete-config || true
fi

snapper -c "$CONFIG_NAME" create-config /

CONF_FILE="/etc/snapper/configs/$CONFIG_NAME"
if [ -f "$CONF_FILE" ]; then
    sed -i 's|^SUBVOLUME=.*|SUBVOLUME=/|' "$CONF_FILE"
    sed -i 's|^TIMELINE_LIMIT_HOURLY=.*|TIMELINE_LIMIT_HOURLY="24"|' "$CONF_FILE"
    sed -i 's|^TIMELINE_LIMIT_DAILY=.*|TIMELINE_LIMIT_DAILY="7"|' "$CONF_FILE"
    sed -i 's|^TIMELINE_LIMIT_WEEKLY=.*|TIMELINE_LIMIT_WEEKLY="4"|' "$CONF_FILE"
    sed -i 's|^TIMELINE_LIMIT_MONTHLY=.*|TIMELINE_LIMIT_MONTHLY="6"|' "$CONF_FILE"
    sed -i 's|^TIMELINE_LIMIT_YEARLY=.*|TIMELINE_LIMIT_YEARLY="2"|' "$CONF_FILE"
    echo "✅ Snapper config updated."
else
    echo -e "${RED}ERROR: Snapper config file not found after creation.${NC}"
    exit 1
fi

echo -e "\n[6/6] Enabling services..."
systemctl daemon-reload
systemctl enable --now snapperd.service
systemctl enable --now snapper-timeline.timer
systemctl enable --now snapper-cleanup.timer

echo -e "\n${YELLOW}IMPORTANT NEXT STEP:${NC}"
echo "To enable booting from snapshots, you need to configure GRUB."
echo "Install 'grub-btrfs' if not already installed:"
echo "  sudo pacman -S grub-btrfs"
echo "Then enable the path monitor:"
echo "  sudo systemctl enable --now grub-btrfs.path"

echo -e "\n${GREEN}=============================================${NC}"
echo -e "${GREEN}✅ Btrfs + Snapper setup completed!${NC}"
echo -e "Test command: snapper list"
echo -e "${GREEN}=============================================${NC}\n"
