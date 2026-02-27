cat > ~/openclaw-cachyos-secure-podman.sh << 'EOF'
#!/bin/bash
set -euo pipefail

echo "🦞 CachyOS Dedicated OpenClaw Podman Hardening Script v3.2 (Fixed)"
echo "=================================================="

# 1. Verify CachyOS
if ! grep -q "ID=cachyos" /etc/os-release; then
  echo "❌ This script is designed exclusively for CachyOS! Please run on CachyOS."
  exit 1
fi

echo "✅ CachyOS detected. Enabling Arch + BTRFS optimizations."

# 2. Update system & install dependencies
# Note: cachyos-kernel-headers is kept but uses --needed (only install if missing)
sudo pacman -Syu --needed --noconfirm podman slirp4netns fuse3 btrfs-progs git
echo "📦 Base packages installed."

# 3. Create dedicated 'openclaw' user (Zero Trust)
if ! id openclaw &>/dev/null; then
  sudo useradd -m -s /usr/bin/nologin -c "OpenClaw Zero-Trust User" openclaw
  sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 openclaw
  echo "🔒 User 'openclaw' created."
fi

# Get dynamic UID/GID (safety measure)
USER_UID=$(id -u openclaw)
USER_GID=$(id -g openclaw)

# 4. Clone repository (if not exists)
if [ ! -d /home/openclaw/openclaw ]; then
  sudo -u openclaw git clone https://github.com/openclaw/openclaw.git /home/openclaw/openclaw
fi

# 5. Prepare directory structure & BTRFS Subvolumes
echo "📂 Preparing directories..."
sudo -u openclaw mkdir -p /home/openclaw/.config/containers
sudo -u openclaw mkdir -p /home/openclaw/.openclaw/workspace
sudo -u openclaw mkdir -p /home/openclaw/projects
sudo mkdir -p /snapshots
sudo chown openclaw:openclaw /snapshots 2>/dev/null || true

# Configure storage.conf
cat > /home/openclaw/.config/containers/storage.conf << CONF
[storage]
driver = "btrfs"
runroot = "/run/user/${USER_UID}/containers"
graphroot = "/home/openclaw/.local/share/containers/storage"

[storage.options]
mount_program = "/usr/bin/fuse-overlayfs"
CONF

# Create BTRFS subvolumes (FIXED: Created as root, then chowned)
if mount | grep -q " /home .*btrfs"; then
  echo "🌲 BTRFS detected on /home, creating subvolumes as root..."
  # Root creates the subvolume
  sudo btrfs subvolume create /home/openclaw/.openclaw 2>/dev/null || true
  sudo btrfs subvolume create /home/openclaw/.openclaw/workspace 2>/dev/null || true
  # Immediate permission fix
  sudo chown -R openclaw:openclaw /home/openclaw/.openclaw
  sudo chmod 700 /home/openclaw/.openclaw
  sudo chmod 700 /home/openclaw/.openclaw/workspace
  echo "✅ BTRFS subvolumes ready."
else
  echo "⚠️  /home is not on BTRFS. Subvolumes skipped."
fi

# 6. Pre-create all security configuration files (Before running setup)

# 6.1 Seccomp Profile
cat > /home/openclaw/.openclaw/seccomp-openclaw.json << 'SEC'
{"defaultAction":"SCMP_ACT_ALLOW","architectures":["SCMP_ARCH_X86_64"],"syscalls":[{"names":["ptrace","process_vm_readv","process_vm_writev","kexec_load","bpf","perf_event_open","fanotify_init","mount","umount2","reboot","setuid","setgid","chroot","pivot_root"],"action":"SCMP_ACT_ERRNO"}]}
SEC

# 6.2 OpenClaw Main Configuration
cat > /home/openclaw/.openclaw/openclaw.json << 'JSON'
{
  "gateway": {"bind": "127.0.0.1", "port": 18789, "auth": {"mode": "token"}},
  "agents": {"defaults": {"sandbox": {"mode": "all", "scope": "agent", "workspaceAccess": "rw", "docker": {"network": "none", "readOnlyRoot": true, "memory": "4096M", "cpus": 4}}}},
  "tools": {"fs": {"workspaceOnly": true}, "exec": {"host": "sandbox", "security": "ask", "ask": "always"}, "profile": "light"},
  "fileSystem": {"allowedPaths": ["/home/openclaw/.openclaw/workspace", "/home/openclaw/projects"], "blockedPaths": ["/etc", "/root", "/sys", "/proc"]}
}
JSON

# 6.3 Generate random Token and write to .env (Fix: Missing .env file)
TOKEN=$(openssl rand -hex 32)
cat > /home/openclaw/.openclaw/.env << ENVFILE
OPENCLAW_TOKEN=${TOKEN}
OPENCLAW_LOG_LEVEL=info
ENVFILE

# 6.4 Set Permissions (Must be done after all files are created)
sudo chown -R openclaw:openclaw /home/openclaw/.openclaw
sudo chown -R openclaw:openclaw /home/openclaw/.config
sudo chmod 700 /home/openclaw/.openclaw
sudo chmod 600 /home/openclaw/.openclaw/seccomp-openclaw.json
sudo chmod 600 /home/openclaw/.openclaw/openclaw.json
sudo chmod 600 /home/openclaw/.openclaw/.env

# 7. Execute official installation (Environment is now fully prepared)
cd /home/openclaw/openclaw
export OPENCLAW_PODMAN_QUADLET=1
# Run setup as the openclaw user
sudo -u openclaw ./setup-podman.sh --quadlet --image-tag local

# 8. Apply Advanced Quadlet Hardening (Overwrite default generated file)
QUADLET_DIR="/home/openclaw/.config/containers/systemd"
mkdir -p "$QUADLET_DIR"

cat > "$QUADLET_DIR/openclaw.container" << EOL
[Unit]
Description=OpenClaw Gateway - CachyOS Zero Trust
After=network-online.target
Wants=network-online.target

[Container]
Image=openclaw:local
ContainerName=openclaw-gateway
User=${USER_UID}:${USER_GID}
SecurityOpts=no-new-privileges:true
SecurityOpts=seccomp=/home/openclaw/.openclaw/seccomp-openclaw.json
ReadOnly=true
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=true
PrivateDevices=true
NoNewPrivileges=true
MaskPaths=/etc/shadow,/etc/passwd,/etc/sudoers,/root,/sys,/proc/sys,/dev/mem
Tmpfs=/tmp:size=128M,noexec,nosuid,nodev
# Simplified Pasta config for better compatibility
Network=pasta
PastaOptions=--no-tcp,--outbound-addr=host
CapDrop=ALL
PidsLimit=256
Memory=4096M
MemorySwap=0
CPUQuota=90%
EnvironmentFile=/home/openclaw/.openclaw/.env
Volume=/home/openclaw/.openclaw:/home/node/.openclaw:rw
Volume=/home/openclaw/.openclaw/workspace:/home/node/.openclaw/workspace:rw
Volume=/home/openclaw/projects:/home/node/projects:ro
SecurityLabelDisable=true

[Service]
Restart=always
RestartSec=3
LimitNOFILE=8192

[Install]
WantedBy=default.target
EOL

sudo chown openclaw:openclaw "$QUADLET_DIR/openclaw.container"

# 9. Reload and Start Service (Fix: Correct Systemd invocation)
echo "🚀 Starting services..."

# Enable linger (allows user services to run without active login)
sudo loginctl enable-linger openclaw

# Correct way to invoke user-level systemctl from root
sudo -u openclaw XDG_RUNTIME_DIR=/run/user/${USER_UID} systemctl --user daemon-reload
sudo -u openclaw XDG_RUNTIME_DIR=/run/user/${USER_UID} systemctl --user enable --now openclaw.service

# 10. Setup Automatic BTRFS Snapshots (Fix: Cron syntax)
# Use 'bash -c' to ensure 'date' executes correctly and escape '%' signs
CRON_CMD='if [ -d /snapshots ]; then btrfs subvolume snapshot -r /home/openclaw/.openclaw/workspace /snapshots/openclaw-workspace-$(date +\%F-\%H\%M); fi'
echo "0 4 * * 0 root bash -c \"$CRON_CMD\"" | sudo tee /etc/cron.d/openclaw-btrfs > /dev/null
sudo chmod 644 /etc/cron.d/openclaw-btrfs

echo "=================================================="
echo "🎉 CachyOS Dedicated Deployment Complete!"
echo "📍 Dashboard: http://127.0.0.1:18789"
echo "🔑 Token: $TOKEN"
echo "💡 Tip: To restart service, run: sudo -u openclaw XDG_RUNTIME_DIR=/run/user/${USER_UID} systemctl --user restart openclaw.service"
EOF

chmod +x ~/openclaw-cachyos-secure-podman.sh
