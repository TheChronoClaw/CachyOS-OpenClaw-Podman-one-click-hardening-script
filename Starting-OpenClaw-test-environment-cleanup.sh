#!/bin/bash
echo "🗑️ Starting OpenClaw test environment cleanup..."

# 1. Stop and remove services
if id openclaw &>/dev/null; then
  USER_UID=$(id -u openclaw)
  sudo -u openclaw XDG_RUNTIME_DIR=/run/user/${USER_UID} systemctl --user stop openclaw.service 2>/dev/null || true
  sudo -u openclaw XDG_RUNTIME_DIR=/run/user/${USER_UID} systemctl --user disable openclaw.service 2>/dev/null || true
  sudo loginctl disable-linger openclaw
fi

# 2. Delete the user and their home directory
sudo userdel -r openclaw 2>/dev/null || true

# 3. Delete BTRFS subvolume (if it exists)
if mount | grep -q " /home .*btrfs"; then
  sudo btrfs subvolume delete /home/openclaw/.openclaw 2>/dev/null || true
  # Note: If the user has already been deleted, the path may not exist; ignore errors
fi

# 4. Delete snapshot directories
sudo rm -rf /snapshots/openclaw-* 2>/dev/null || true

# 5. Remove Cron jobs
sudo rm -f /etc/cron.d/openclaw-btrfs

# 6. Remove scripts
rm -f ~/openclaw-cachyos-secure-podman.sh
rm -f ~/openclaw_install.log

echo "✅ Cleanup complete. The system has been restored to its original state."
