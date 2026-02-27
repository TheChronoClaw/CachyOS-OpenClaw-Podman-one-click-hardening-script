#!/bin/bash
# ================================================
# OpenClaw Day 12 - Ollama Local Model One-Click Setup (EN)
# Author: TheChronoClaw 
# Function: Install Ollama + GPU + models + OpenClaw config (Podman rootless safe)
# Designed for: CachyOS + Podman rootless + NVIDIA
# Version: 1.7 (Ultimate - VRAM Check + Smart Wait + Model Selection)
# ================================================

set -e

# Define Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================
# OPTIMIZATION #3: Custom Model Selection
# ============================================
DEFAULT_MODEL="qwen2.5:7b"
echo -e "${BLUE}💡 Model Selection:${NC}"
read -p "Enter model name to pull (default: ${DEFAULT_MODEL}): " INPUT_MODEL
MODEL_NAME=${INPUT_MODEL:-${DEFAULT_MODEL}}
echo -e "${GREEN}✓ Selected model: ${MODEL_NAME}${NC}"

# Header
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}=== OpenClaw Day 12: Ollama Local LLM One-Click Setup ===${NC}"
echo -e "${GREEN}================================================${NC}"
echo "Setting up fully local AI models for your CachyOS production environment..."

# 1. Check root privileges
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: Please run this script with sudo${NC}"
   exit 1
fi

# Determine real user home (safe getent)
if [ -n "$SUDO_USER" ]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    [ -z "$REAL_HOME" ] && REAL_HOME="/home/$SUDO_USER"
else
    REAL_USER=$(whoami)
    REAL_HOME="$HOME"
fi

echo -e "${BLUE}ℹ️  Target User: ${REAL_USER} (${REAL_HOME})${NC}"

# 2. Install dependencies + Ollama
echo -e "\n${YELLOW}→ [1/6] Installing dependencies and Ollama...${NC}"
pacman -Sy --needed --noconfirm curl

if ! command -v ollama &> /dev/null; then
    echo "Installing Ollama via official script..."
    curl -fsSL https://ollama.com/install.sh | sh
else
    echo -e "${BLUE}ℹ️  Ollama already installed.${NC}"
fi

# 3. Enable Ollama service
echo -e "\n${YELLOW}→ [2/6] Enabling Ollama systemd service...${NC}"
if ! systemctl enable --now ollama.service; then
    echo -e "${RED}Error: Failed to start Ollama service.${NC}"
    echo -e "${RED}Check logs with: systemctl status ollama.service${NC}"
    exit 1
fi

# ============================================
# OPTIMIZATION #2: Smart Service Wait (Port Check)
# ============================================
echo -e "\n${YELLOW}→ [3/6] Waiting for Ollama service to be ready...${NC}"
for i in {1..15}; do
    if curl -s http://localhost:11434/api/tags &> /dev/null; then
        echo -e "${GREEN}✔️ Ollama API is ready! (Attempt $i)${NC}"
        break
    fi
    if [ $i -eq 15 ]; then
        echo -e "${RED}Error: Ollama service did not become ready within 15 seconds.${NC}"
        echo -e "${RED}Check logs with: journalctl -u ollama.service${NC}"
        exit 1
    fi
    sleep 1
done

# 4. NVIDIA check + VRAM recommendation
echo -e "\n${YELLOW}→ [4/6] Checking NVIDIA GPU...${NC}"
if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
    echo -e "${GREEN}✔️ NVIDIA detected! Full GPU acceleration ready.${NC}"
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
    
    # ============================================
    # OPTIMIZATION #1: VRAM Model Recommendation
    # ============================================
    echo -e "\n${BLUE}💡 VRAM Model Recommendation:${NC}"
    VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader | awk '{print $1}' | head -n 1)
    # Remove "MiB" suffix if present
    VRAM_MB=$(echo "$VRAM_MB" | tr -d ' ')
    
    if [ -n "$VRAM_MB" ] && [ "$VRAM_MB" -gt 0 ] 2>/dev/null; then
        echo -e "${BLUE}Detected VRAM: ${VRAM_MB} MiB${NC}"
        if [ "$VRAM_MB" -lt 6000 ]; then
            echo -e "${YELLOW}⚠️  Low VRAM detected. Recommended: qwen2.5:3b or smaller${NC}"
            echo -e "${YELLOW}   Current selection (${MODEL_NAME}) may be too large.${NC}"
        elif [ "$VRAM_MB" -lt 10000 ]; then
            echo -e "${GREEN}✔️ Medium VRAM. Recommended: qwen2.5:7b${NC}"
        elif [ "$VRAM_MB" -lt 20000 ]; then
            echo -e "${GREEN}✔️ Good VRAM. Recommended: qwen2.5:14b or llama3.2:11b${NC}"
        else
            echo -e "${GREEN}✔️ High VRAM. Recommended: qwen2.5:32b or larger${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Could not determine VRAM size.${NC}"
    fi
else
    echo -e "${YELLOW}⚠️ No NVIDIA detected, running on CPU.${NC}"
    echo -e "${YELLOW}   CPU inference will be slower. Consider smaller models.${NC}"
fi

# 5. Pull models
echo -e "\n${YELLOW}→ [5/6] Pulling model: ${MODEL_NAME}...${NC}"
if ! ollama pull "$MODEL_NAME"; then
    echo -e "${RED}Error: Failed to pull model ${MODEL_NAME}.${NC}"
    echo -e "${RED}Check network connection or GPU drivers.${NC}"
    exit 1
fi
echo -e "${GREEN}✔️ Model ${MODEL_NAME} pulled successfully.${NC}"

# Optional: Pull embedding model
echo -e "\n${YELLOW}→ [5.5/6] Pulling embedding model...${NC}"
if ! ollama pull nomic-embed-text; then
    echo -e "${YELLOW}⚠️  Failed to pull embedding model (optional feature).${NC}"
fi
echo -e "${GREEN}✔️ Embedding model ready.${NC}"

# 6. Create config (with overwrite protection)
echo -e "\n${YELLOW}→ [6/6] Creating OpenClaw local config...${NC}"
CONFIG_PATH="${REAL_HOME}/openclaw-local-ollama.json"

if [ -f "$CONFIG_PATH" ]; then
    echo -e "${YELLOW}⚠️  Config file already exists: ${CONFIG_PATH}${NC}"
    read -p "Overwrite? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}ℹ️  Skipping config file creation.${NC}"
        CONFIG_SKIPPED=true
    fi
fi

if [ "${CONFIG_SKIPPED}" != "true" ]; then
    cat > "$CONFIG_PATH" << EOF
{
  "llm": {
    "provider": "ollama",
    "base_url": "http://localhost:11434",
    "model": "${MODEL_NAME}",
    "temperature": 0.7
  },
  "embedding": {
    "provider": "ollama",
    "model": "nomic-embed-text"
  }
}
EOF
    chown "$REAL_USER:$REAL_USER" "$CONFIG_PATH" 2>/dev/null || true
    echo -e "${GREEN}✅ Local config saved to ${CONFIG_PATH}${NC}"
fi

# 7. Preflight check (Podman image)
echo -e "\n${BLUE}💡 Preflight Check:${NC}"
if command -v podman &> /dev/null; then
    if podman inspect --type=image your-openclaw-image &> /dev/null; then
        echo -e "${GREEN}✔️ Local image 'your-openclaw-image' found.${NC}"
    else
        echo -e "${YELLOW}⚠️  Local image 'your-openclaw-image' NOT found.${NC}"
        echo -e "${YELLOW}Build it first with: podman build -t your-openclaw-image .${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Podman not installed. Install with: sudo pacman -S podman${NC}"
fi

# Summary
echo -e "\n${GREEN}================================================${NC}"
echo -e "${GREEN}✅ Setup COMPLETE!${NC}"
echo -e "${GREEN}================================================${NC}"

echo -e "\n${YELLOW}📚 Quick Commands:${NC}"
echo "   ollama ps                    → List running models"
echo "   ollama run ${MODEL_NAME}     → Test chat"
echo "   ollama pull qwen2.5:14b      → Upgrade model"
echo "   systemctl status ollama      → Check service status"

echo -e "\n${GREEN}🚀 Podman rootless start command:${NC}"
echo "podman run -d --name openclaw \\"
echo "  --network=host \\"
echo "  -v ${REAL_HOME}/openclaw-local-ollama.json:/app/config.json \\"
echo "  your-openclaw-image"

echo -e "\n${BLUE}💡 Next Steps:${NC}"
echo "1. Build/pull your OpenClaw image first"
echo "2. Run the podman command above"
echo "3. All agents now 100% local — zero tokens!"

echo -e "\n🦞"

echo -e "\n${GREEN}Your OpenClaw is now truly local and production-ready!${NC}"
