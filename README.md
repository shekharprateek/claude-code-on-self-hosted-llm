# Claude Code on Self-Hosted LLM

Run Claude Code's full agentic workflows — file edits, bash commands, multi-step reasoning — backed by a self-hosted open-weight model on AWS, at a fixed hourly cost with no API keys.

```
Your Machine
  │ SSH
  ▼
EC2 Client (t3.medium)          ── SSH tunnel ──▶   EC2 GPU Server (g6e.xlarge)
  Claude Code CLI                                    llama-server + Qwen 3.5-35B
  No cloud API keys needed                           NVIDIA L40S, 45GB VRAM
```

## Why

| | Managed API (Bedrock/Anthropic) | Self-Hosted (this guide) |
|---|---|---|
| Cost model | Per token | Fixed hourly (~$1.86/hr) |
| Data leaves your infra | Yes | No |
| Model control | No | Full |
| Setup time | Minutes | ~30 minutes |

Heavy coding sessions with many tool calls add up fast on pay-per-token APIs. At ~117 tokens/sec generation on a g6e.xlarge, self-hosted becomes cost-effective for sustained use.

## What's Inside

| File | Purpose |
|---|---|
| [SETUP-GUIDE.md](SETUP-GUIDE.md) | Full step-by-step setup with all flags explained |
| [scripts/tunnel.sh](scripts/tunnel.sh) | Manage SSH tunnel to GPU server |
| [scripts/claude-local.sh](scripts/claude-local.sh) | Launch Claude Code against local model (auto-restores config on exit) |
| [scripts/bench.sh](scripts/bench.sh) | Benchmark local model vs Amazon Bedrock |
| [config/settings.template.json](config/settings.template.json) | Claude Code settings template |

## Quick Start

**1. Launch a g6e.xlarge with the Deep Learning Base AMI (Ubuntu 22.04)**

**2. Build llama.cpp with CUDA and start the model server**
```bash
# On the GPU server
git clone https://github.com/ggml-org/llama.cpp ~/llama.cpp
cd ~/llama.cpp && cmake -B build -G Ninja -DGGML_CUDA=ON && cmake --build build --config Release -j $(nproc)

~/llama.cpp/build/bin/llama-server \
  -hf unsloth/Qwen3.5-35B-A3B-GGUF:Q4_K_M \
  --host 127.0.0.1 --port 8131 \
  -ngl 999 -c 131072 --reasoning off --swa-full --no-context-shift
```

**3. Open SSH tunnel from your client**
```bash
export G6E_IP=<your-gpu-server-ip>
./scripts/tunnel.sh start
```

**4. Run Claude Code**
```bash
./scripts/claude-local.sh
```

See [SETUP-GUIDE.md](SETUP-GUIDE.md) for the complete walkthrough including all flags, troubleshooting, and cost reference.

## Hardware

Tested on:
- **GPU server**: g6e.xlarge — 1x NVIDIA L40S (45GB VRAM), 4 vCPUs
- **Client**: t3.medium — any small instance works
- **Model**: Qwen 3.5-35B Q4_K_M (~22GB, fits with 131K context window)

Performance on g6e.xlarge:
- Prompt processing: ~58 tokens/sec
- Generation: ~117 tokens/sec
- VRAM used: 24GB of 45GB

## Benchmark

Compare Claude Code quality and latency between self-hosted Qwen and Amazon Bedrock (Claude):

```bash
./scripts/bench.sh both
```

Tasks range from simple (single tool call) to complex (full agentic: 10+ tool calls, write tests from scratch).

## Lessons Learned

Key things that tripped us up — documented in [SETUP-GUIDE.md](SETUP-GUIDE.md#lessons-learned):

- `CLAUDE_CODE_USE_BEDROCK` in `settings.json` overrides shell env vars — use a clean machine or swap the file
- llama.cpp CUDA build takes ~15 min on 4-core instances — use `-j $(nproc)`
- Bind model server to `127.0.0.1`, not `0.0.0.0` — use SSH tunnel for access
- `--reasoning off` replaces the deprecated thinking flag for Qwen 3.5

## Cost Reference

| Resource | Rate |
|---|---|
| g6e.xlarge on-demand | ~$1.86/hr |
| t3.medium client | ~$0.04/hr |
| Model download | one-time, free from HuggingFace |
