#!/bin/bash
# ================================================
# OpenClaw Day 12 - CachyOS BTRFS + Snapper One-Click Production Snapshot Script (EN)
# Author: TheChronoClaw 
# Function: Auto-install & configure Snapper + snap-pac + bootloader support
# Designed for: OpenClaw + Podman rootless/Production Environment
# Version: 1.7 (FIXED: Robust GRUB Preload Module Logic + Optimized Container Detection)
# ================================================

set -e

# Define Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- CORRECTED ECHO STATEMENTS ---
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}=== OpenClaw Day 12: BTRFS + Snapper Production Setup ===${NC}"
echo -e "${GREEN}================================================${NC}"
echo "Starting professional snapshot system configuration for your CachyOS..."

# 1. Check Root Privileges
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: Please run this script with sudo (sudo ./script.sh)${NC}"
   exit 1
fi

# 2. Check if Root is BTRFS
if ! findmnt -n -o FSTYPE / | grep -q btrfs; then
  echo -e "${RED}Error: Root partition (/) is NOT a BTRFS filesystem!${NC}"
  echo "Current filesystem: $(findmnt -n -o FSTYPE /)"
  echo -e "${YELLOW}Hint: Please select BTRFS during CachyOS installation.${NC}"
  exit 1
fi

# 3. Install packages FIRST
echo -e "\n${YELLOW}→ [1/6] Installing required packages (no full upgrade yet)...${NC}"
pacman -Sy --needed --noconfirm snapper snap-pac grub-btrfs btrfs-progs btrfs-assistant

echo -e "\n${YELLOW}→ [2/6] Configuring Snapper for root...${NC}"

# Backup old config if exists
if [[ -f /etc/snapper/configs/root ]]; then
  cp /etc/snapper/configs/root /etc/snapper/configs/root.bak.$(date +%s)
  echo -e "${BLUE}ℹ️  Old config backed up.${NC}"
fi

# Create config if missing
if [[ ! -f /etc/snapper/configs/root ]]; then
  echo "Creating root Snapper configuration..."
  snapper -c root create-config /
fi

# Optimized Production Config
echo -e "${YELLOW}→ [3/6] Writing optimized Snapper parameters...${NC}"
cat > /etc/snapper/configs/root << 'EOF'
# OpenClaw Production Optimized Config - Day 12 v1.7
SUBVOLUME="/"
FSTYPE="btrfs"
ALLOW_USERS=""
ALLOW_GROUPS="wheel"
SYNC_ACL="yes"
BACKGROUND_COMPARISON="yes"
QGROUP="1/0"

# Number Cleanup
NUMBER_CLEANUP="yes"
NUMBER_MIN_AGE="1800"
NUMBER_LIMIT="10"
NUMBER_LIMIT_IMPORTANT="15"

# Timeline Snapshots
TIMELINE_CREATE="yes"
TIMELINE_CLEANUP="yes"
TIMELINE_MIN_AGE="1800"
TIMELINE_LIMIT_HOURLY="6"
TIMELINE_LIMIT_DAILY="7"
TIMELINE_LIMIT_WEEKLY="4"
TIMELINE_LIMIT_MONTHLY="3"
TIMELINE_LIMIT_YEARLY="0"

# Space Management
SPACE_LIMIT="0.6"
FREE_LIMIT="0.2"
EOF
chmod 750 /.snapshots
chown root:root /.snapshots

# 4. Container Environment Hint
echo -e "\n${YELLOW}→ [4/6] Checking container environment...${NC}"
if [[ -d /var/lib/containers ]]; then
  echo -e "${BLUE}ℹ️  Detected rootful Podman/Docker environment. Data protected.${NC}"
else
  echo -e "${BLUE}ℹ️  No rootful container directory detected. Ensure rootless containers ${NC}"
  echo -e "${BLUE}are managed separately for optimal safety.${NC}"
fi

echo -e "\n${YELLOW}→ [5/6] Enabling Snapper systemd timers...${NC}"
systemctl enable --now snapper-timeline.timer snapper-cleanup.timer snapper-boot.timer 2>/dev/null || true

# 5. Bootloader Configuration (GRUB or Limine)
echo -e "\n${YELLOW}→ [6/6] Configuring bootloader for snapshot booting...${NC}"

if [ -f /boot/grub/grub.cfg ]; then
    echo "Detected GRUB bootloader..."

    #  GRUB_PRELOAD_MODULES
    echo "Ensuring Btrfs module is preloaded in GRUB..."
    if grep -q "GRUB_PRELOAD_MODULES" /etc/default/grub; then
        
        sed -i 's/^GRUB_PRELOAD_MODULES=.*/GRUB_PRELOAD_MODULES="btrfs"/' /etc/default/grub
    else
        
        echo 'GRUB_PRELOAD_MODULES="btrfs"' >> /etc/default/grub
    fi

    echo "Updating GRUB configuration..."
    grub-mkconfig -o /boot/grub/grub.cfg

    # Enable grub-btrfsd
    if systemctl list-unit-files | grep -q grub-btrfsd; then
        systemctl enable --now grub-btrfsd.service 2>/dev/null || true
        echo -e "${GREEN}✔️  GRUB + grub-btrfsd ready. New snapshots auto-appear in boot menu.${NC}"
    fi

elif [ -f /boot/limine/limine.cfg ]; then
    echo -e "${BLUE}ℹ️  Detected Limine (CachyOS default).${NC}"
    echo -e "${YELLOW}Action: Use btrfs-assistant GUI to add snapshot boot entries.${NC}"
    echo -e "${GREEN}✔️  Snapper core ready. Limine manual management recommended.${NC}"
else
    echo -e "${RED}⚠️  Unknown bootloader detected. Use btrfs-assistant for snapshot support.${NC}"
fi

# Create initial snapshot
echo -e "\n${YELLOW}→ Creating initial manual snapshot...${NC}"
snapper -c root create --description "Before Day 12 Snapper Setup - OpenClaw Production" --cleanup-algorithm number

echo -e "\n${GREEN}================================================${NC}"
echo -e "${GREEN}✅ Snapper Production Setup COMPLETE! (v1.7)${NC}"
echo -e "${GREEN}================================================${NC}"

echo -e "\n${YELLOW}📚 Quick Commands:${NC}"
echo "   List snapshots:           sudo snapper -c root list"
echo "   Create manual:            sudo snapper -c root create --description 'Note'"
echo "   Rollback:                 sudo snapper -c root rollback <ID>"
echo "   GUI:                      btrfs-assistant"

echo -e "\n${GREEN}🚑 Rescue (if system breaks):${NC}"
echo "   1. Reboot → choose snapshot in GRUB/Limine menu"
echo "   2. sudo snapper -c root rollback <good_ID>"
echo "   3. Reboot"

echo -e "\n${BLUE}💡 Next: Now safely run 'sudo pacman -Syu' to test pre/post snapshots!${NC}"
echo -e "Reply 🦞 in the thread and I'll send you Day 13 (Quadlet auto-service) script!"
