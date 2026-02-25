#!/bin/bash
# Filename: setup-podman-gpu.sh
# Description: Standalone script to add NVIDIA GPU support to Podman on CachyOS/Arch Linux.
# Usage: sudo ./setup-podman-gpu.sh

set -e # Exit immediately if a command exits with a non-zero status.

echo "========================================="
echo "  Starting Podman GPU Setup (NVIDIA)"
echo "  Target: CachyOS / Arch Linux"
echo "========================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
  echo "Error: Please run this script with sudo."
  exit 1
fi

# 1. Check if Podman is installed
if ! command -v podman &> /dev/null; then
    echo "Error: Podman not detected. Please install Podman first."
    exit 1
fi
echo "[OK] Podman found."

# 2. Enable 'multilib' repository (Required for NVIDIA drivers)
echo "[Checking multilib repository...]"
if ! grep -q "^$$multilib$$" /etc/pacman.conf; then
    echo "Enabling multilib repository..."
    echo "[multilib]" >> /etc/pacman.conf
    echo "Include = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf
    pacman -Sy --noconfirm
    echo "[OK] Multilib enabled and database updated."
else
    echo "[OK] Multilib repository already enabled."
fi

# 3. Install Kernel Headers (Required for DKMS)
echo "[Detecting kernel headers...]"
KERNEL_PKG=$(pacman -Q | grep "^linux " | awk '{print $1}' | head -n 1)
HEADERS_PKG=""

case "$KERNEL_PKG" in
    "linux") HEADERS_PKG="linux-headers" ;;
    "linux-lts") HEADERS_PKG="linux-lts-headers" ;;
    "linux-cachyos") HEADERS_PKG="linux-cachyos-headers" ;;
    "linux-cachyos-lts") HEADERS_PKG="linux-cachyos-lts-headers" ;;
    "linux-zen") HEADERS_PKG="linux-zen-headers" ;;
    *) 
        echo "Warning: Could not auto-detect kernel headers package."
        echo "Defaulting to 'linux-headers'. If this fails, install headers manually."
        HEADERS_PKG="linux-headers" 
        ;;
esac

echo "Installing kernel headers: $HEADERS_PKG"
pacman -S --noconfirm "$HEADERS_PKG" || {
    echo "Error: Failed to install kernel headers. Please install them manually matching your kernel."
    exit 1
}

# 4. Install NVIDIA Drivers
echo "[Installing NVIDIA Drivers (DKMS)...]"
pacman -S --noconfirm nvidia-dkms nvidia-utils nvidia-settings opencl-nvidia libva-nvidia-driver

# Load modules immediately (optional, reboot is safer)
echo "Loading NVIDIA kernel modules..."
modprobe nvidia || true
modprobe nvidia-uvm || true
modprobe nvidia-modeset || true
echo "[OK] Drivers installed."

# 5. Install NVIDIA Container Toolkit
echo "[Installing NVIDIA Container Toolkit...]"
# Check if available in official repos first
if pacman -Si nvidia-container-toolkit &> /dev/null; then
    pacman -S --noconfirm nvidia-container-toolkit
else
    echo "Package not found in official repos. Checking for AUR helpers..."
    if command -v yay &> /dev/null; then
        yay -S --noconfirm nvidia-container-toolkit
    elif command -v paru &> /dev/null; then
        paru -S --noconfirm nvidia-container-toolkit
    else
        echo "Error: 'nvidia-container-toolkit' not found in repos, and no AUR helper (yay/paru) detected."
        echo "Please install an AUR helper or install the toolkit manually."
        exit 1
    fi
fi
echo "[OK] Toolkit installed."

# 6. Configure Podman Runtime
echo "[Configuring Podman runtime...]"
nvidia-ctk runtime configure --runtime=podman

# 7. Restart Podman Services
echo "[Restarting Podman services...]"
systemctl restart podman.socket
systemctl restart podman.service
echo "[OK] Services restarted."

# 8. Verification Test
echo "========================================="
echo "Running verification test..."
echo "========================================="

# Pull a small CUDA image and run nvidia-smi
# Using a lightweight base image for speed
IMAGE_NAME="nvidia/cuda:12.0-base"

echo "Pulling test image: $IMAGE_NAME (this may take a moment)..."
if podman run --rm --gpus all "$IMAGE_NAME" nvidia-smi; then
    echo "========================================="
    echo "✅ SUCCESS! GPU is accessible in Podman."
    echo "========================================="
    echo "Usage Example:"
    echo "  podman run --gpus all <your-image> <command>"
    echo ""
    echo "Note: If you encounter permission errors later, ensure your user"
    echo "is added to the 'video' and 'render' groups and log out/in."
else
    echo "========================================="
    echo "❌ TEST FAILED."
    echo "========================================="
    echo "The container could not access the GPU."
    echo "Suggestions:"
    echo "1. Reboot your system to ensure kernel modules are loaded correctly."
    echo "2. Check 'dmesg | grep NVRM' for driver errors."
    echo "3. Ensure your GPU is supported by the installed driver version."
fi
