Install and configure the self-hosted LLM setup for Claude Code.

Detect whether you are running on the **GPU server** or the **local machine** and perform the appropriate setup steps.

## Step 1 — Detect environment

Run `nvidia-smi` to check if a GPU is present.

- If a GPU is detected: this is the **GPU server** — proceed with GPU Server Setup below.
- If no GPU is detected: this is the **local machine** — proceed with Local Machine Setup below.

## GPU Server Setup

### 1. Check prerequisites

Run the following and report what is found:

```bash
nvidia-smi
```

### 2. Install Ollama

Check if Ollama is already installed:

```bash
which ollama && ollama --version
```

If not installed:

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

### 3. Check if model is already pulled

```bash
ollama list
```

Report whether a Qwen model is already present. If not, ask the user:

"Pull Qwen 3.5-35B now? (~22GB download, requires 24GB+ VRAM). For smaller GPUs use qwen3.5:7b. (yes/no)"

If yes, pull the model:

```bash
ollama pull qwen3.5:35b
```

For smaller GPUs: `ollama pull qwen3.5:7b`

### 4. Verify the model is running on GPU

```bash
ollama run qwen3.5:35b "Reply with only: ready"
```

Then check GPU memory is being used:

```bash
nvidia-smi --query-gpu=memory.used,utilization.gpu --format=csv,noheader
```

Confirm memory shows ~24GB used for the 35B model — this confirms GPU inference is active.

### 5. Print connection instructions

Print the public IP of this server:

```bash
curl -s ifconfig.me
```

Tell the user:

"GPU server setup complete. Ollama is serving on port 11434. Now run `/install` on your local machine and provide this IP when prompted."

---

## Local Machine Setup

### 1. Check Claude Code is installed

```bash
claude --version
```

If not installed, instruct the user to install it:

```bash
npm install -g @anthropic-ai/claude-code
```

### 2. Check SSH key

Ask the user: "What is the path to your SSH key for the GPU server? (default: ~/.ssh/id_rsa — press enter to use default)"

If they provide a path, verify the key file exists. If they press enter, use `~/.ssh/id_rsa`.

### 3. Ask for SSH username

Ask the user: "What is the SSH username for your GPU server? (default: ubuntu — use root for RunPod, etc.)"

### 4. Ask for GPU server IP

Ask the user: "What is the public IP address of your GPU server?"

### 5. Test SSH connectivity

```bash
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i <key> <user>@<GPU_SERVER_IP> "ollama list"
```

If this fails, report the error and suggest checking:

- The server's firewall allows port 22 from the current IP
- The correct username (ubuntu for most cloud images, root for RunPod)
- The key file has correct permissions (`chmod 600 <key>`)

### 6. Open SSH tunnel

```bash
export GPU_SERVER_IP=<ip>
export SSH_KEY=<key>
export SSH_USER=<user>
./scripts/tunnel.sh start
```

Verify the tunnel is working:

```bash
curl -s http://localhost:11434/v1/models
```

Report the model name from the response.

### 7. Launch Claude Code with local model

Run a quick test to confirm the full chain is working:

```bash
./scripts/claude-local.sh -p "What model are you running?"
```

The response should name the open-source model (e.g. qwen3.5:35b), not Claude.

### 8. Print summary

Print a summary of what was configured:

- GPU server IP and SSH username
- SSH tunnel status (port 11434)
- Model responding at localhost:11434
- How to start a session: `./scripts/claude-local.sh`
- How to stop the tunnel: `./scripts/tunnel.sh stop`
