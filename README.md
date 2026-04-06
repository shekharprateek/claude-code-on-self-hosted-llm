# Claude Code with a Self-Hosted Open-Source Model

Use Claude Code — Anthropic's AI coding assistant — powered by an open-source model running
on your own GPU server, instead of a cloud API. You get full agentic workflows (file edits,
terminal commands, multi-step reasoning) at a predictable hourly cost, with your code never
leaving your own infrastructure.

```text
Your Laptop or Desktop
  │
  │  SSH tunnel (encrypted, no open ports needed)
  │
  ▼
GPU Server (cloud or on-premise)
  Open-source model (Qwen 3.5-35B)
  NVIDIA GPU, runs fully offline
```

## Why Run Your Own Model?

| | Cloud API (Anthropic / AWS Bedrock) | Self-Hosted (this guide) |
| --- | --- | --- |
| Pricing | Pay per token — adds up fast | Fixed hourly rate (~$1.86/hr on AWS) |
| Your code stays private | No — sent to external API | Yes — never leaves your server |
| Choose your model | No | Yes — swap any open-source model |
| Works offline | No | Yes |
| Setup time | Under 5 minutes | ~30 minutes (one time) |

Heavy coding sessions with lots of file reads and edits can burn through API credits quickly.
Once you have a GPU server running, the cost is the same whether you send one request or a thousand.

## What Is This?

Claude Code normally routes every request to Anthropic's API or Amazon Bedrock. This guide
shows you how to redirect those requests to a local model server running on any NVIDIA GPU —
cloud instance, workstation, or on-premise server. The model used here is
[Qwen 3.5-35B](https://huggingface.co/unsloth/Qwen3.5-35B-A3B-GGUF), a capable open-source
coding model that fits in ~24GB of GPU memory.

## What's Inside

| File | What it does |
| --- | --- |
| [SETUP-GUIDE.md](SETUP-GUIDE.md) | Full walkthrough with every flag explained and troubleshooting tips |
| [scripts/tunnel.sh](scripts/tunnel.sh) | Opens and closes the secure connection between your machine and the GPU server |
| [scripts/claude-local.sh](scripts/claude-local.sh) | Launches Claude Code pointed at your local model, restores original settings on exit |
| [scripts/bench.sh](scripts/bench.sh) | Runs the same coding tasks against both the local model and the cloud API for comparison |
| [config/settings.template.json](config/settings.template.json) | Claude Code configuration template for local model use |

## Quick Start

### Step 1 — Get a GPU server

This guide uses an AWS `g6e.xlarge` instance with an NVIDIA L40S GPU (45GB VRAM).
Any NVIDIA GPU with 24GB+ VRAM will work — cloud or local.

Launch on AWS with the **Deep Learning Base AMI (Ubuntu 22.04)** — it comes with GPU drivers
pre-installed so you skip manual CUDA setup.

### Step 2 — Install the model server on the GPU machine

SSH into your GPU server and run:

```bash
# Download and build llama.cpp (the model server) — takes ~15 min first time
git clone https://github.com/ggml-org/llama.cpp ~/llama.cpp
cd ~/llama.cpp
cmake -B build -G Ninja -DGGML_CUDA=ON
cmake --build build --config Release -j $(nproc)

# Start the model — downloads ~22GB from HuggingFace on first run
~/llama.cpp/build/bin/llama-server \
  -hf unsloth/Qwen3.5-35B-A3B-GGUF:Q4_K_M \
  --host 127.0.0.1 --port 8131 \
  -ngl 999 -c 131072 --reasoning off --swa-full --no-context-shift
```

The server is ready when you see `listening on 127.0.0.1:8131`.

### Step 3 — Connect your machine to the GPU server

Run this on your local machine (not the GPU server):

```bash
export G6E_IP=<your-gpu-server-ip>
./scripts/tunnel.sh start
```

This opens an encrypted SSH tunnel so Claude Code on your machine can reach the model
server without exposing any ports to the internet.

### Step 4 — Start coding with your local model

```bash
./scripts/claude-local.sh
```

This script temporarily points Claude Code at your local model, then restores your
original settings when you exit. Your existing Claude Code setup is not permanently changed.

Confirm it's working:

```bash
claude -p "What model are you?"
# Hello! I'm Qwen3.5-35B-A3B...
```

For the full walkthrough with all configuration options and troubleshooting, see [SETUP-GUIDE.md](SETUP-GUIDE.md).

## Performance

Measured on AWS `g6e.xlarge` (NVIDIA L40S, 45GB VRAM):

- Input processing: ~58 tokens/sec
- Output generation: ~117 tokens/sec
- Memory used: ~24GB of 45GB available
- Context window: up to 131,072 tokens

## Benchmark

Want to compare quality and speed against the cloud API? Run the included benchmark:

```bash
./scripts/bench.sh both
```

It runs a set of real coding tasks — from simple lookups to writing full test suites — against
both your local model and Amazon Bedrock, and prints a side-by-side timing comparison.

## Common Pitfalls

Full details in [SETUP-GUIDE.md](SETUP-GUIDE.md#lessons-learned), but here are the big ones:

- If you already use Amazon Bedrock with Claude Code, the `settings.json` config overrides
  environment variables — use `claude-local.sh` which handles the swap automatically
- The model server build takes ~15 minutes due to GPU compiler overhead — this is normal
- Always bind the model server to `127.0.0.1`, never `0.0.0.0` — use the SSH tunnel for remote access
- Use `--reasoning off` for Qwen 3.5 (the older `enable_thinking` flag is deprecated)

## Cost

| What | Cost |
| --- | --- |
| GPU server (AWS g6e.xlarge) | ~$1.86/hr on-demand |
| Model weights | Free download from HuggingFace (~22GB, one time) |

Stop the GPU server when you are not using it — the model stays on disk and reloads in seconds.
