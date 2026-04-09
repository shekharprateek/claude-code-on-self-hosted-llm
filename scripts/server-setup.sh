#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# server-setup.sh — One-shot GPU server setup: install Ollama, pull model, verify GPU
#
# Run this on the GPU server (Ubuntu). Works on AWS, GCP, Azure, RunPod,
# Lambda Labs, or any Ubuntu machine with an NVIDIA GPU.
#
# Usage:
#   bash server-setup.sh                  # pulls qwen3.5:35b (default)
#   MODEL=qwen3.5:7b bash server-setup.sh # smaller model for 16GB GPUs
#
# What it does:
#   1. Verifies NVIDIA GPU and CUDA are available
#   2. Installs Ollama (skips if already installed)
#   3. Pulls the model (~22GB for 35b, ~5GB for 7b)
#   4. Verifies the model runs on GPU
#   5. Prints the public IP and next steps
# ---------------------------------------------------------------------------

MODEL="${MODEL:-qwen3.5:35b}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

info()  { echo -e "${BLUE}[info]${RESET}  $1"; }
ok()    { echo -e "${GREEN}[ok]${RESET}    $1"; }
warn()  { echo -e "${YELLOW}[warn]${RESET}  $1"; }
die()   { echo -e "${RED}[error]${RESET} $1"; exit 1; }

echo -e "\n${BOLD}=== GPU Server Setup ===${RESET}"
info "Model: $MODEL"
echo ""

# ---------------------------------------------------------------------------
# Step 1 — Verify GPU
# ---------------------------------------------------------------------------
info "Checking GPU..."
if ! command -v nvidia-smi &>/dev/null; then
    die "nvidia-smi not found. Install NVIDIA drivers first: https://developer.nvidia.com/cuda-downloads"
fi

GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "unknown")
GPU_VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ' || echo "unknown")
ok "GPU: $GPU_NAME ($GPU_VRAM)"

# ---------------------------------------------------------------------------
# Step 2 — Install Ollama
# ---------------------------------------------------------------------------
if command -v ollama &>/dev/null; then
    OLLAMA_VER=$(ollama --version 2>/dev/null || echo "installed")
    ok "Ollama already installed ($OLLAMA_VER) — skipping install"
else
    info "Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
    ok "Ollama installed"
fi

# Ensure ollama service is running
if ! pgrep -x ollama &>/dev/null; then
    info "Starting Ollama service..."
    nohup ollama serve > /tmp/ollama.log 2>&1 &
    sleep 3
fi

# ---------------------------------------------------------------------------
# Step 3 — Pull model
# ---------------------------------------------------------------------------
if ollama list 2>/dev/null | grep -q "^${MODEL}"; then
    ok "Model $MODEL already present — skipping pull"
else
    info "Pulling $MODEL (this may take a while on first run)..."
    ollama pull "$MODEL"
    ok "Model pulled: $MODEL"
fi

# ---------------------------------------------------------------------------
# Step 4 — Verify GPU inference
# ---------------------------------------------------------------------------
info "Verifying model runs on GPU..."
RESPONSE=$(ollama run "$MODEL" "Reply with only the word: ready" 2>/dev/null || echo "")

if echo "$RESPONSE" | grep -qi "ready"; then
    ok "Model responded: $RESPONSE"
else
    warn "Unexpected response: '$RESPONSE' — server may still be initializing"
fi

VRAM_USED=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ' || echo "unknown")
ok "GPU VRAM in use: $VRAM_USED"

if [[ "$VRAM_USED" == "unknown" ]] || [[ "${VRAM_USED%%MiB}" -lt 1000 ]] 2>/dev/null; then
    warn "Low VRAM usage detected — model may be running on CPU. Check: ollama ps"
fi

# ---------------------------------------------------------------------------
# Step 5 — Print next steps
# ---------------------------------------------------------------------------
SERVER_IP=$(curl -sf --max-time 5 http://ifconfig.me 2>/dev/null \
    || curl -sf --max-time 5 http://icanhazip.com 2>/dev/null \
    || echo "<this-server-ip>")

echo ""
echo -e "${BOLD}=== Setup complete ===${RESET}"
echo ""
echo -e "  GPU:    $GPU_NAME ($GPU_VRAM VRAM)"
echo -e "  Model:  $MODEL"
echo -e "  Port:   11434 (localhost only — access via SSH tunnel)"
echo ""
echo -e "${BOLD}Next steps — run on your local machine:${RESET}"
echo ""
echo "  export GPU_SERVER_IP=$SERVER_IP"
echo "  export SSH_KEY=~/.ssh/<your-key>"
echo "  export SSH_USER=ubuntu            # adjust if needed (root for RunPod, etc.)"
echo "  ./scripts/tunnel.sh start"
echo "  ./scripts/claude-local.sh"
echo ""
echo -e "See README.md for full instructions."
