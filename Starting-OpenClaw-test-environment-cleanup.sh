#!/bin/bash
# ==============================================================================
# OpenClaw Test Environment Cleanup Script
# Version:      1.0.0
# Author:       TheChronoClaw
# GitHub:       https://github.com/TheChronoClaw
# Description:  Safely stop & remove OpenClaw containers, images, and configs
# Compatibility:CachyOS + Podman rootless
# ==============================================================================

set -euo pipefail

# Display header
echo -e "\n============================================================="
echo " OpenClaw Test Environment Cleanup Script"
echo " Version: 1.0.0 | Author: TheChronoClaw"
echo -e "=============================================================\n"

# Step 1: Stop OpenClaw container if running
echo "[1/5] Stopping OpenClaw container..."
podman stop openclaw >/dev/null 2>&1 || true

# Step 2: Remove OpenClaw container
echo "[2/5] Removing OpenClaw container..."
podman rm -f openclaw >/dev/null 2>&1 || true

# Step 3: Remove all OpenClaw images
echo "[3/5] Removing OpenClaw images..."
podman images | grep -i openclaw | awk '{print $3}' | xargs -r podman rmi -f >/dev/null 2>&1 || true

# Step 4: Safely delete config directories
echo "[4/5] Cleaning up config directories..."
[ -d ~/.config/openclaw ] && rm -rf ~/.config/openclaw
[ -d ./config ]         && rm -rf ./config
[ -d ./openclaw ]       && rm -rf ./openclaw

# Step 5: Prune unused Podman data
echo "[5/5] Pruning unused Podman data..."
podman system prune -f >/dev/null 2>&1 || true

# Done
echo -e "\n✅ Cleanup completed successfully!"
echo "All OpenClaw test environment resources have been removed.\n"
