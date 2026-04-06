# Running Claude Code with a Self-Hosted LLM on AWS

A practical guide to setting up Claude Code backed by Qwen 3.5-35B running on an AWS g6e instance,
with lessons learned from doing it the first time.

---

## What This Achieves

Claude Code (the CLI) normally calls Anthropic's API or Amazon Bedrock. This setup replaces
that backend with a self-hosted open-weight model (Qwen 3.5-35B) running on an AWS GPU instance.
The end result: full Claude Code agentic workflows — file edits, bash commands, multi-step
reasoning — powered by a model you control, at a fixed hourly cost.

```
Your Machine
  │ SSH
  ▼
EC2 Client (t3.medium)          ── SSH tunnel ──▶   EC2 GPU Server (g6e.xlarge)
  Claude Code CLI                                    llama-server + Qwen 3.5-35B
  No cloud API keys needed                           NVIDIA L40S, 45GB VRAM
```

---

## Hardware Requirements

### GPU Server
| Component | Minimum | Used in this guide |
|---|---|---|
| Instance | Any GPU instance | g6e.xlarge |
| GPU | NVIDIA GPU | L40S (48GB VRAM) |
| Disk | 50 GB | 100 GB gp3 |
| AMI | Deep Learning Base OSS Nvidia (Ubuntu 22.04) | ami-014135eb43056a305 |

> The Deep Learning AMI comes with NVIDIA drivers and CUDA pre-installed — no manual driver setup needed.

### Client Machine
Any Linux machine with Node.js 18+ works. A t3.medium (~$0.04/hr) is sufficient.

---

## Step 1 — Launch the GPU Server

```bash
aws ec2 run-instances \
  --region us-east-1 \
  --image-id ami-014135eb43056a305 \
  --instance-type g6e.xlarge \
  --key-name <your-key> \
  --security-group-ids <your-sg> \
  --subnet-id <your-subnet> \
  --associate-public-ip-address \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":100,"VolumeType":"gp3"}}]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=llm-gpu-server}]'
```

**Security group rules needed:**
- Port 22 inbound from your IP (SSH access)
- Port 22 inbound from client EC2 private IP (for SSH tunnel)

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

> This takes ~15 minutes on a g6e.xlarge (4 vCPUs). The CUDA kernel compilation is the bottleneck.

Verify:
```bash
~/llama.cpp/build/bin/llama-server --version
# Should show: CUDA device detected — NVIDIA L40S
```

---

## Step 3 — Start the Model Server

This downloads Qwen 3.5-35B (~22GB) on first run from HuggingFace, then starts serving:

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
| `--reasoning off` | Disables Qwen's internal chain-of-thought. Claude Code manages its own reasoning — no need to waste tokens here. |
| `--mlock` | Locks model weights in RAM, prevents OS from swapping them out. |
| `--host 127.0.0.1` | Binds to localhost only. Access via SSH tunnel — never expose this port directly. |

**Performance observed on g6e.xlarge (L40S):**
- Prompt processing: ~58 tokens/sec
- Generation: ~117 tokens/sec
- VRAM used: 24GB of 45GB available

---

## Step 4 — Set Up the Client EC2

Launch a t3.medium with Ubuntu 22.04, then:

```bash
# Install Node.js 22
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install Claude Code
sudo npm install -g @anthropic-ai/claude-code
```

Configure Claude Code to use the local model — create `~/.claude/settings.json`:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:8131",
    "ANTHROPIC_AUTH_TOKEN": "local",
    "ANTHROPIC_MODEL": "unsloth/qwen3.5-35b-a3b",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "unsloth/qwen3.5-35b-a3b",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "unsloth/qwen3.5-35b-a3b",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "unsloth/qwen3.5-35b-a3b",
    "CLAUDE_CODE_SUBAGENT_MODEL": "unsloth/qwen3.5-35b-a3b",
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "128000",
    "DISABLE_PROMPT_CACHING": "1",
    "DISABLE_AUTOUPDATER": "1",
    "DISABLE_TELEMETRY": "1",
    "DISABLE_NON_ESSENTIAL_MODEL_CALLS": "1"
  }
}
```

---

## Step 5 — Open SSH Tunnel from Client to GPU Server

Run this on the client EC2 (copy your key there first):

```bash
scp -i ~/.ssh/<key>.pem ~/.ssh/<key>.pem ubuntu@<client-ip>:~/.ssh/<key>.pem
ssh ubuntu@<client-ip> "chmod 600 ~/.ssh/<key>.pem"

# Open the tunnel
ssh -o StrictHostKeyChecking=no \
    -o ServerAliveInterval=60 \
    -N -f \
    -L 8131:localhost:8131 \
    -i ~/.ssh/<key>.pem \
    ubuntu@<gpu-server-private-ip>
```

Verify from the client:
```bash
curl http://localhost:8131/v1/models
```

---

## Step 6 — Run Claude Code

```bash
cd ~/your-repo
claude
```

Confirm it's using Qwen:
```bash
claude -p "What model are you?"
# Hello! I'm Qwen3.5-35B-A3B (unsloth-optimized variant)...
```

---

## Monitoring GPU Utilization

Run this on the GPU server while sending prompts to see the GPU spike:

```bash
nvidia-smi --query-gpu=utilization.gpu,utilization.memory,memory.used,temperature.gpu,clocks.current.graphics \
  --format=csv --loop=1
```

Expected: 0% at idle, spikes to ~80-100% during active inference.

---

## Lessons Learned

### 1. Cloud provider settings override shell environment variables
If your machine uses Amazon Bedrock (`CLAUDE_CODE_USE_BEDROCK=1` in `settings.json`),
passing env var overrides on the command line will not work. The `env` block in
`settings.json` is applied after shell env vars and wins.

**Fix:** Use a clean machine with no existing Claude Code config, or swap `settings.json`
entirely before launching Claude.

### 2. llama.cpp CUDA build is slow on small instances
Expect ~15 minutes on a 4-core instance. The CUDA compiler (`nvcc`) is the bottleneck.
Consider using `-j $(nproc)` and pre-built binaries for repeated deployments.

### 3. Model downloads to HuggingFace cache, not llama.cpp cache
The `-hf` flag uses HuggingFace Hub. The 22GB GGUF lands in `~/.cache/huggingface/hub/`.
Plan disk accordingly. First startup is slow; subsequent starts are instant from cache.

### 4. `--reasoning off` replaces the old thinking flag
The previously documented `--chat-template-kwargs '{"enable_thinking": false}'` is deprecated.
Use `--reasoning off` for Qwen 3.5.

### 5. Same-VPC instances still need explicit security group rules
Two EC2s in the same VPC cannot reach each other unless the security group has an
explicit inbound rule for the source private IP. Don't assume VPC locality implies open access.

### 6. SSH tunnel is the right network pattern
Binding the model server to `0.0.0.0` would work but widens the attack surface unnecessarily.
An SSH tunnel keeps the model port on localhost and leverages your existing key-based auth.

---

## Cost Reference

| Resource | Rate | Notes |
|---|---|---|
| g6e.xlarge on-demand | ~$1.86/hr | 1x NVIDIA L40S, 48GB VRAM |
| t3.medium (client) | ~$0.04/hr | Can use any small instance |
| Model download | one-time | ~22GB, free from HuggingFace |

---

## Tear Down

```bash
aws ec2 terminate-instances --region us-east-1 \
  --instance-ids <gpu-instance-id> <client-instance-id>

aws ec2 delete-security-group --region us-east-1 --group-id <sg-id>
```
