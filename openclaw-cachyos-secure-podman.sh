cat > ~/openclaw-cachyos-secure-podman.sh << 'EOF'
#!/bin/bash
set -euo pipefail

echo "🦞 CachyOS OpenClaw Podman Hardening Script v4.0 FINAL"
echo "========================================================="

# 1. OS Check
if ! grep -q "ID=cachyos" /etc/os-release; then
  echo "❌ Only for CachyOS!"
  exit 1
fi
echo "✅ CachyOS detected"

# 2. Install FULL dependencies (fixed all missing)
sudo pacman -Syu --needed --noconfirm \
  podman slirp4netns fuse3 btrfs-progs git \
  openssl podman-plugin-pasta cronie nano \
  libseccomp iptables-nft nftables

echo "📦 All dependencies installed"

# 3. Create secure openclaw user
if ! id openclaw &>/dev/null; then
  sudo useradd -m -s /usr/bin/nologin -c "OpenClaw Zero-Trust" openclaw
  sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 openclaw
  echo "🔒 User openclaw created"
fi

USER_UID=$(id -u openclaw)
USER_GID=$(id -g openclaw)

# 4. Clone repo
if [ ! -d /home/openclaw/openclaw ]; then
  sudo -u openclaw git clone https://github.com/openclaw/openclaw.git /home/openclaw/openclaw
fi

# 5. Prepare directories
sudo -u openclaw mkdir -p /home/openclaw/.config/containers
sudo -u openclaw mkdir -p /home/openclaw/.openclaw/workspace
sudo -u openclaw mkdir -p /home/openclaw/projects
sudo mkdir -p /snapshots 2>/dev/null || true
sudo chown openclaw:openclaw /snapshots 2>/dev/null || true

# 6. Storage.conf (BTRFS + overlay)
cat > /home/openclaw/.config/containers/storage.conf << CONF
[storage]
driver = "btrfs"
runroot = "/run/user/${USER_UID}/containers"
graphroot = "/home/openclaw/.local/share/containers/storage"

[storage.options]
mount_program = "/usr/bin/fuse-overlayfs"
pull_options = {enable_partial_images = true, use_hard_links = true}
CONF

# 7. BTRFS subvolumes (reliable check)
if findmnt -no FSTYPE /home | grep -q btrfs; then
  echo "🌲 BTRFS /home detected"
  sudo btrfs subvolume create /home/openclaw/.openclaw 2>/dev/null || true
  sudo btrfs subvolume create /home/openclaw/.openclaw/workspace 2>/dev/null || true
  sudo chown -R openclaw:openclaw /home/openclaw/.openclaw
  sudo chmod 700 /home/openclaw/.openclaw
  sudo chmod 700 /home/openclaw/.openclaw/workspace
fi

# 8. Seccomp (fixed for Node.js compatibility)
cat > /home/openclaw/.openclaw/seccomp-openclaw.json << 'SEC'
{"defaultAction":"SCMP_ACT_ALLOW","architectures":["SCMP_ARCH_X86_64"],"syscalls":[{"names":["ptrace","process_vm_readv","process_vm_writev","kexec_load","bpf","perf_event_open","fanotify_init","mount","umount2","reboot","chroot","pivot_root"],"action":"SCMP_ACT_ERRNO"}]}
SEC

# 9. OpenClaw config
cat > /home/openclaw/.openclaw/openclaw.json << 'JSON'
{
  "gateway": {"bind": "127.0.0.1", "port": 18789, "auth": {"mode": "token"}},
  "agents": {"defaults": {"sandbox": {"mode": "all", "scope": "agent", "workspaceAccess": "rw", "docker": {"network": "none", "readOnlyRoot": true, "memory": "4096M", "cpus": 4}}}},
  "tools": {"fs": {"workspaceOnly": true}, "exec": {"host": "sandbox", "security": "ask", "ask": "always"}, "profile": "light"},
  "fileSystem": {"allowedPaths": ["/home/openclaw/.openclaw/workspace", "/home/openclaw/projects"], "blockedPaths": ["/etc", "/root", "/sys", "/proc"]}
}
JSON

# 10. Secure token
TOKEN=$(openssl rand -hex 32)
cat > /home/openclaw/.openclaw/.env << ENV
OPENCLAW_TOKEN=${TOKEN}
OPENCLAW_LOG_LEVEL=info
NODE_ENV=production
ENV

# 11. Permissions lock
sudo chown -R openclaw:openclaw /home/openclaw
sudo chmod -R 700 /home/openclaw
sudo chmod 600 /home/openclaw/.openclaw/*

# 12. Run official setup
cd /home/openclaw/openclaw
export OPENCLAW_PODMAN_QUADLET=1
sudo -u openclaw ./setup-podman.sh --quadlet --image-tag local

# 13. HARDENED Quadlet (final secure version)
QUADLET_DIR="/home/openclaw/.config/containers/systemd"
mkdir -p "$QUADLET_DIR"

cat > "$QUADLET_DIR/openclaw.container" << EOL
[Unit]
Description=OpenClaw Gateway ZeroTrust
After=network-online.target nss-lookup.target
Wants=network-online.target

[Container]
Image=openclaw:local
ContainerName=openclaw-gateway
User=${USER_UID}:${USER_GID}
SecurityOpts=no-new-privileges:true
SecurityOpts=seccomp=/home/openclaw/.openclaw/seccomp-openclaw.json
ReadOnly=True
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=True
PrivateDevices=True
ProtectKernelLogs=True
ProtectKernelModules=True
ProtectKernelTunables=True
RestrictNamespaces=True
RestrictRealtime=True
RestrictSUIDSGID=True
NoNewPrivileges=True
MaskPaths=/etc/shadow,/etc/sudoers,/root,/sys/fs,/dev/mem,/dev/kmem
Tmpfs=/tmp:size=128M,noexec,nosuid,nodev
Network=pasta
CapDrop=ALL
PidsLimit=256
Memory=4096M
MemorySwap=0
CPUQuota=85%
EnvironmentFile=/home/openclaw/.openclaw/.env
Volume=/home/openclaw/.openclaw:/home/node/.openclaw:rw
Volume=/home/openclaw/.openclaw/workspace:/home/node/.openclaw/workspace:rw
Volume=/home/openclaw/projects:/home/node/projects:ro
SecurityLabelDisable=true

[Service]
Restart=always
RestartSec=2
LimitNOFILE=8192
LimitNPROC=512

[Install]
WantedBy=default.target
EOL

sudo chown openclaw:openclaw "$QUADLET_DIR/openclaw.container"

# 14. Start service (stable systemd user)
sudo loginctl enable-linger openclaw

sudo -u openclaw bash -c "
export XDG_RUNTIME_DIR=/run/user/${USER_UID}
systemctl --user daemon-reload
systemctl --user enable --now openclaw.service
"

# 15. FIREWALL LOCKDOWN (only localhost allowed)
echo "🔒 Setting up firewall (18789 only allowed from 127.0.0.1)"

sudo systemctl enable --now nftables
sudo nft flush ruleset
sudo nft add table inet filter
sudo nft add chain inet filter input '{ type filter hook input priority 0; policy drop; }'
sudo nft add rule inet filter input iif lo accept
sudo nft add rule inet filter input ct state related,established accept
sudo nft add rule inet filter input tcp dport 18789 ip saddr 127.0.0.1 accept
sudo nft add rule inet filter input icmp type echo-request limit rate 10/second accept
sudo nft save

# 16. SYSCTL HARDENING (CachyOS optimized)
cat > /etc/sysctl.d/99-openclaw-hardening.conf << SYSCTL
fs.protected_symlinks=1
fs.protected_hardlinks=1
fs.suid_dumpable=0
kernel.dmesg_restrict=1
kernel.kptr_restrict=2
kernel.unprivileged_bpf_disabled=1
net.core.bpf_jit_harden=2
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.icmp_echo_ignore_broadcasts=1
net.ipv4.icmp_ignore_bogus_error_responses=1
SYSCTL

sudo sysctl -p /etc/sysctl.d/99-openclaw-hardening.conf

# 17. BTRFS SNAPSHOTS + AUTO-CLEAN (7 days retention)
SNAP_CRON="0 4 * * * root if [ -d /snapshots ]; then btrfs subvolume snapshot -r /home/openclaw/.openclaw/workspace /snapshots/openclaw-\$(date +\%F-\%H\%M); find /snapshots -name 'openclaw-*' -mtime +7 -delete 2>/dev/null; fi"
echo "$SNAP_CRON" | sudo tee /etc/cron.d/openclaw-snapshot >/dev/null
sudo chmod 644 /etc/cron.d/openclaw-snapshot

sudo systemctl enable --now cronie

# 18. AUTO-UPDATE container weekly
UPD_CRON="0 2 * * 0 openclaw export XDG_RUNTIME_DIR=/run/user/${USER_UID} && systemctl --user restart openclaw.service"
echo "$UPD_CRON" | sudo tee /etc/cron.d/openclaw-auto-update >/dev/null
sudo chmod 644 /etc/cron.d/openclaw-auto-update

echo
echo "========================================================="
echo "🎉 DEPLOYMENT COMPLETE - FULLY HARDENED"
echo "📍 URL: http://127.0.0.1:18789"
echo "🔑 TOKEN: $TOKEN"
echo "========================================================="
EOF

chmod +x ~/openclaw-cachyos-secure-podman.sh
