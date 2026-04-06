# Running Claude Code with a Self-Hosted LLM (Advanced: llama.cpp)

A practical guide to setting up Claude Code backed by Qwen 3.5-35B using llama.cpp on
any NVIDIA GPU server. llama.cpp gives you full control over quantization, context length,
caching, and inference flags.

> **Looking for the simpler setup?** The Quick Start in the README uses Ollama and takes
> about 10 minutes. This guide covers llama.cpp for users who want lower-level tuning.

The examples below use Ubuntu, but the steps work on any Linux distribution.

---

## What This Achieves

Claude Code (the CLI) normally calls Anthropic's API or Amazon Bedrock. This setup replaces
that backend with a self-hosted open-weight model (Qwen 3.5-35B) running on a GPU server
you control. The end result: full Claude Code agentic workflows — file edits, bash commands,
multi-step reasoning — powered by a model that never leaves your infrastructure.

```
Your Laptop or Desktop
  │ SSH tunnel (localhost:8131 → server:8131)
  ▼
GPU Server (any cloud or on-premise)
  llama-server + Qwen 3.5-35B
  NVIDIA GPU, 24GB+ VRAM
```

---

## Hardware Requirements

| Component | Minimum | Recommended |
|---|---|---|
| GPU | 24GB VRAM (7B–13B models) | 45GB VRAM (35B models) |
| Disk | 50 GB | 100 GB SSD |
| RAM | 16 GB | 32 GB |
| OS | Ubuntu 20.04+ | Ubuntu 22.04 LTS |

**Your local machine** just needs Claude Code and SSH — no GPU required.

### GPU options by size

| Provider | Instance | GPU | VRAM | Approx. Cost |
|---|---|---|---|---|
| AWS | g6e.xlarge | L40S | 45 GB | ~$1.86/hr |
| AWS | g5.xlarge | A10G | 24 GB | ~$1.01/hr |
| RunPod | A40 | A40 | 48 GB | ~$0.44/hr |
| Lambda Labs | 1x A100 | A100 | 40 GB | ~$1.10/hr |
| Local | Any | Any 24GB+ | — | Hardware cost |

---

## Step 1 — Get a GPU Server with NVIDIA Drivers

Most cloud images (AWS Deep Learning AMIs, RunPod, Lambda Labs) come with drivers
pre-installed. Verify:

```bash
nvidia-smi
# Should show GPU name and driver version
```

If not installed, follow the [NVIDIA CUDA installation guide](https://developer.nvidia.com/cuda-downloads).

---

## Step 2 — Build llama.cpp with CUDA

SSH into the GPU server and run:

```bash
sudo apt-get update -qq && sudo apt-get install -y cmake ninja-build git

git clone https://github.com/ggml-org/llama.cpp ~/llama.cpp
cd ~/llama.cpp
cmake -B build -G Ninja -DGGML_CUDA=ON
cmake --build build --config Release -j $(nproc)
```

> This takes ~15 minutes on a 4-core machine — CUDA kernel compilation is the bottleneck.

Verify:

```bash
~/llama.cpp/build/bin/llama-server --version
# Should mention CUDA support
```

---

## Step 3 — Start the Model Server

Downloads Qwen 3.5-35B (~22GB) on first run from HuggingFace, then starts serving:

```bash
nohup ~/llama.cpp/build/bin/llama-server \
  -hf unsloth/Qwen3.5-35B-A3B-GGUF:Q4_K_M \
  --host 127.0.0.1 \
  --port 8131 \
  -ngl 999 \
  -t 2 \
  -c 131072 \
  -b 512 \
  -ub 1024 \
  --parallel 1 \
  -fa on \
  --jinja \
  --keep 1024 \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --swa-full \
  --no-context-shift \
  --reasoning off \
  --mlock \
  --no-mmap \
  > /tmp/llama-server.log 2>&1 &
```

Verify it's running:

```bash
curl http://localhost:8131/v1/models
```

**Key flags explained:**

| Flag | Why |
|---|---|
| `-ngl 999` | Offload all layers to GPU. Without this, inference runs on CPU — ~10x slower. |
| `--swa-full` | Enables prompt caching for Qwen's sliding window attention. ~10x faster on follow-up turns. |
| `--no-context-shift` | Required when using `--swa-full`. |
| `--reasoning off` | Disables Qwen's internal chain-of-thought — Claude Code manages its own reasoning. |
| `--mlock` | Locks model weights in RAM, prevents OS from swapping them out. |
| `--host 127.0.0.1` | Binds to localhost only — access via SSH tunnel, never expose directly. |

**Performance observed on L40S (45GB VRAM):**
- Prompt processing: ~58 tokens/sec
- Generation: ~117 tokens/sec
- VRAM used: ~24GB of 45GB

> **Note:** This setup uses port **8131** (llama.cpp default). The `tunnel.sh` and
> `claude-local.sh` scripts default to port **11434** (Ollama). If using llama.cpp,
> update `LOCAL_PORT=8131` in `tunnel.sh` and the port in `claude-local.sh`.

---

## Step 4 — Open SSH Tunnel from Your Machine

Run this on your local machine:

```bash
export G6E_IP=<your-gpu-server-public-ip>
export G6E_KEY=~/.ssh/<your-key>

# If using llama.cpp (port 8131), edit LOCAL_PORT in tunnel.sh first, then:
./scripts/tunnel.sh start

# Or manually:
ssh -N -f -L 8131:localhost:8131 -i "$G6E_KEY" ubuntu@"$G6E_IP"
```

Verify from your machine:

```bash
curl http://localhost:8131/v1/models
```

---

## Step 5 — Run Claude Code

```bash
# Set env to point at local model and launch
ANTHROPIC_BASE_URL=http://127.0.0.1:8131 \
ANTHROPIC_AUTH_TOKEN=local \
claude
```

Or use `claude-local.sh` after updating the port from 11434 to 8131 inside the script.

Confirm it's using Qwen:

```bash
claude -p "What model are you?"
# Hello! I'm Qwen3.5-35B...
```

---

## Monitoring GPU Utilization

On the GPU server while running prompts:

```bash
nvidia-smi --query-gpu=utilization.gpu,utilization.memory,memory.used,temperature.gpu \
  --format=csv --loop=1
```

Expected: 0% at idle, spikes to ~80–100% during active generation.

---

## Lessons Learned

### 1. `settings.json` overrides shell environment variables

If your machine has `CLAUDE_CODE_USE_BEDROCK=1` or `ANTHROPIC_API_KEY` set in
`~/.claude/settings.json`, passing env vars on the command line will not override them.
The `env` block in `settings.json` wins.

**Fix:** Use `claude-local.sh` which swaps `settings.json` for the duration of the session
and restores it on exit.

### 2. llama.cpp CUDA build takes time

Expect ~15 minutes on a 4-core machine. Use `-j $(nproc)` to parallelize.

### 3. Model downloads to HuggingFace cache

The `-hf` flag uses HuggingFace Hub. The 22GB GGUF lands in `~/.cache/huggingface/hub/`.
First startup is slow; subsequent starts load from cache instantly.

### 4. `--reasoning off` replaces the old thinking flag

The previously documented `--chat-template-kwargs '{"enable_thinking": false}'` is
deprecated. Use `--reasoning off` for Qwen 3.5.

### 5. Always bind to `127.0.0.1`, not `0.0.0.0`

The SSH tunnel handles external access. Binding to `0.0.0.0` exposes the model port
to any network interface — unnecessary and risky.
