# Claude Code with a Self-Hosted Open-Source Model

Run Claude Code — Anthropic's AI coding assistant — backed by an open-source model on
any GPU server. Works on AWS, GCP, Azure, RunPod, Lambda Labs, or a local workstation.
No API keys. No per-token costs. Your code never leaves your machine.

```text
Your Laptop or Desktop
  │
  │  SSH tunnel (encrypted, no open ports needed)
  │
  ▼
Any GPU Server (cloud or on-premise)
  Open-source model (Qwen 3.5-35B) via llama.cpp
  NVIDIA GPU — runs fully offline
```

## Why Self-Host?

| | Cloud API (Anthropic / Bedrock / OpenAI) | Self-Hosted (this guide) |
| --- | --- | --- |
| Pricing | Pay per token | Fixed cost — server only |
| Your code stays private | No — sent to external API | Yes — never leaves your server |
| Works offline | No | Yes |
| Choose your model | No | Any open-source model |
| Rate limits | Yes | None |

Heavy coding sessions with many file reads and edits burn through API credits fast.
Once a GPU server is running, the cost is the same whether you make one request or a thousand.

## Where to Get a GPU Server

Any NVIDIA GPU with 24GB+ VRAM works. Some options:

| Provider | Option | Approx. Cost |
| --- | --- | --- |
| AWS | g6e.xlarge (L40S, 45GB) | ~$1.86/hr |
| AWS | g5.xlarge (A10G, 24GB) | ~$1.01/hr |
| RunPod | A40 (48GB) | ~$0.44/hr |
| Lambda Labs | A100 (40GB) | ~$1.10/hr |
| Local | Any 24GB+ NVIDIA GPU | Hardware cost only |

## What Is This?

Claude Code routes every request to Anthropic's API or Amazon Bedrock by default.
This guide shows you how to redirect those requests to a local model server running on
any NVIDIA GPU. The model used here is
[Qwen 3.5-35B](https://huggingface.co/unsloth/Qwen3.5-35B-A3B-GGUF) — a capable
open-source coding model that fits in ~24GB of GPU memory.

You can swap in any model supported by llama.cpp.

## What's Inside

| File | What it does |
| --- | --- |
| [SETUP-GUIDE.md](SETUP-GUIDE.md) | Full walkthrough with every flag explained and troubleshooting tips |
| [scripts/tunnel.sh](scripts/tunnel.sh) | Opens and closes the secure connection to your GPU server |
| [scripts/claude-local.sh](scripts/claude-local.sh) | Launches Claude Code against local model, restores original config on exit |
| [scripts/bench.sh](scripts/bench.sh) | Runs coding tasks against both local model and cloud API for comparison |
| [config/settings.template.json](config/settings.template.json) | Claude Code configuration template |

## Quick Start

### Step 1 — Get a GPU server with NVIDIA drivers and CUDA installed

On Ubuntu, install CUDA if not already present:

```bash
# Check first — many cloud images have it pre-installed
nvidia-smi
nvcc --version
```

If not installed, follow the [CUDA installation guide](https://developer.nvidia.com/cuda-downloads).

### Step 2 — Build the model server

```bash
sudo apt-get update -qq && sudo apt-get install -y cmake ninja-build git

git clone https://github.com/ggml-org/llama.cpp ~/llama.cpp
cd ~/llama.cpp
cmake -B build -G Ninja -DGGML_CUDA=ON
cmake --build build --config Release -j $(nproc)
```

Start the model (~22GB downloads on first run):

```bash
nohup ~/llama.cpp/build/bin/llama-server \
  -hf unsloth/Qwen3.5-35B-A3B-GGUF:Q4_K_M \
  --host 127.0.0.1 --port 8131 \
  -ngl 999 -c 131072 --reasoning off --swa-full --no-context-shift \
  > /tmp/llama-server.log 2>&1 &
```

The server is ready when you see `listening on 127.0.0.1:8131`.

### Step 3 — Connect from your local machine

```bash
export G6E_IP=<your-server-ip>
export G6E_KEY=~/.ssh/<your-key>
./scripts/tunnel.sh start
```

### Step 4 — Run Claude Code

```bash
./scripts/claude-local.sh
```

Or run `/install` inside Claude Code for a guided setup experience.

Confirm it is working:

```bash
claude -p "What model are you?"
# Hello! I'm Qwen3.5-35B-A3B...
```

See [SETUP-GUIDE.md](SETUP-GUIDE.md) for the full walkthrough with all configuration
options and troubleshooting tips.

## Performance

Measured on NVIDIA L40S (45GB VRAM):

- Input processing: ~58 tokens/sec
- Output generation: ~117 tokens/sec
- Memory used: ~24GB of 45GB
- Context window: up to 131,072 tokens

## Benchmark

Compare quality and speed against the cloud API:

```bash
./scripts/bench.sh both
```

Runs real coding tasks from simple lookups to writing full test suites, and prints a
side-by-side timing comparison.

## Common Pitfalls

Full details in [SETUP-GUIDE.md](SETUP-GUIDE.md#lessons-learned):

- If you use Amazon Bedrock with Claude Code, `settings.json` overrides env vars — use `claude-local.sh`
- llama.cpp CUDA build takes ~15 min on 4-core machines — this is normal
- Always bind the model server to `127.0.0.1`, not `0.0.0.0` — use the SSH tunnel
- Use `--reasoning off` for Qwen 3.5 (the older `enable_thinking` flag is deprecated)

## AWS-Specific Version

If you are running on Amazon EC2 and want AWS-specific guidance (instance selection,
CloudWatch monitoring, spot instances, IAM), see the companion repository:
[claude-code-on-amazon-ec2](https://github.com/shekharprateek/claude-code-on-amazon-ec2).
