# Claude Code with a Self-Hosted Open-Source Model

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Ollama](https://img.shields.io/badge/Ollama-compatible-blue)](https://ollama.com)
[![Model: Qwen 3.5](https://img.shields.io/badge/Model-Qwen%203.5--35B-orange)](https://ollama.com/library/qwen3.5)
[![AWS EC2 companion](https://img.shields.io/badge/AWS%20EC2-companion%20repo-orange?logo=amazon-aws)](https://github.com/shekharprateek/claude-code-on-amazon-ec2)

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
  Open-source model (Qwen 3.5-35B) via Ollama
  NVIDIA GPU — runs fully offline
```

> **Running on Amazon EC2?** See the AWS-specific companion repo with instance selection,
> IAM setup, CloudWatch monitoring, and spot instance guidance:
> **[claude-code-on-amazon-ec2](https://github.com/shekharprateek/claude-code-on-amazon-ec2)**

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

Claude Code routes every request to a cloud API by default. This guide shows you how to
redirect those requests to a local model server running on any NVIDIA GPU via
[Ollama](https://ollama.com). The model used here is
[Qwen 3.5-35B](https://ollama.com/library/qwen3.5) — a capable open-source coding model
that fits in ~24GB of GPU memory.

You can swap in any model supported by Ollama.

## What's Inside

| File | What it does |
| --- | --- |
| [scripts/server-setup.sh](scripts/server-setup.sh) | One-shot GPU server setup: installs Ollama, pulls model, verifies GPU |
| [scripts/tunnel.sh](scripts/tunnel.sh) | Opens and closes the secure SSH tunnel between your machine and the server |
| [scripts/claude-local.sh](scripts/claude-local.sh) | Launches Claude Code against local model, restores original config on exit |
| [scripts/bench.sh](scripts/bench.sh) | Benchmarks local model vs cloud API side by side |
| [config/settings.template.json](config/settings.template.json) | Claude Code configuration template |
| [SETUP-GUIDE.md](SETUP-GUIDE.md) | Advanced walkthrough using llama.cpp for fine-grained tuning |

## Quick Start

### Step 1 — Get a GPU server with NVIDIA drivers and CUDA installed

On Ubuntu, install CUDA if not already present:

```bash
# Check first — many cloud images have it pre-installed
nvidia-smi
nvcc --version
```

If not installed, follow the [CUDA installation guide](https://developer.nvidia.com/cuda-downloads).

### Step 2 — Set up the model server on the GPU server

SSH into the GPU server and run:

```bash
curl -fsSL https://raw.githubusercontent.com/shekharprateek/claude-code-on-self-hosted-llm/main/scripts/server-setup.sh | bash
```

Or clone and run:

```bash
git clone https://github.com/shekharprateek/claude-code-on-self-hosted-llm
bash claude-code-on-self-hosted-llm/scripts/server-setup.sh
```

This installs Ollama, pulls Qwen 3.5-35B (~22GB on first run), and verifies the model is running on GPU.
For a smaller GPU: `MODEL=qwen3.5:7b bash server-setup.sh`

### Step 3 — Connect from your local machine

```bash
export GPU_SERVER_IP=<your-server-ip>
export SSH_KEY=~/.ssh/<your-key>   # omit if using default ~/.ssh/id_rsa
export SSH_USER=ubuntu             # default; use root for RunPod, etc.
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
# Hello! I'm qwen3.5:35b (or whichever model Ollama is serving)...
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

- If you use Amazon Bedrock or another cloud API with Claude Code, `settings.json` overrides env vars — use `claude-local.sh`
- Ollama binds to `127.0.0.1` by default — good. Never expose it on `0.0.0.0` without a firewall.
- After `ollama pull`, the model loads on first request — expect a few seconds delay

## AWS-Specific Version

Running on Amazon EC2? The companion repo adds AWS-specific guidance: instance selection,
Deep Learning AMI setup, IAM roles, CloudWatch monitoring, and spot instance teardown.

**[claude-code-on-amazon-ec2](https://github.com/shekharprateek/claude-code-on-amazon-ec2)**

## License

[MIT](LICENSE)
