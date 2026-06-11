# AI Kubernetes Agent Teammate 🤖☸️

A self-hosted AI agent that acts as your principal-level Kubernetes SRE teammate.
Ask questions about your cluster, get expert troubleshooting guidance, and issue operational commands — all via chat.

**Stack:** n8n + Ollama (Llama 3.1) + kubectl | 100% self-hosted | Zero API costs

---

## Prerequisites

| Tool | Notes |
|---|---|
| Docker Desktop ≥ 4.x | https://docs.docker.com/get-docker/ |
| Docker Compose v2 | Bundled with Docker Desktop |
| Kubernetes cluster | Local (kind/minikube) or remote |
| ~8GB RAM | Minimum for llama3.1:8b model |

---

## Quick Start

```bash
# 1. Clone this repository
# 2. Run the automated setup script
./scripts/setup.sh
```

Then open http://localhost:5678 and follow the **Workflow Import Guide** below.

---

## Manual Setup

```bash
# 1. Configure environment
cp .env.example .env
# Edit .env: set N8N_BASIC_AUTH_PASSWORD and KUBECONFIG_HOST_PATH

# 2. Start the stack
docker compose up -d --build

# 3. Pull the Ollama model
docker compose exec ollama ollama pull llama3.1:8b
```

---

## Workflow Import Guide

> ⚠️ **This step is required after first setup or after tearing down volumes (`docker compose down -v`).**

1. Open http://localhost:5678 and log in (Credentials from `.env`)
2. Go to **Workflows → ⊕ Add Workflow → Import from File**
3. Import **all 14 files** from `workflows/tools/` one at a time
4. **Activate** each tool workflow (toggle switch in top-right of each workflow)
5. Import `workflows/k8s-agent-workflow.json` (the main agent)
6. Open the **AI Kubernetes Agent** workflow
7. For each of the 14 Tool nodes, click the node and update the **Workflow ID** field to match the imported sub-workflow's ID. *(You can find a workflow's ID in its URL: `http://localhost:5678/workflow/<ID>`)*
8. **Activate** the AI Kubernetes Agent workflow
9. Click the **chat bubble icon** (bottom-left) to open the chat interface!

---

## Configuration

These values are managed in your `.env` file:

| Variable | Default | Description |
|---|---|---|
| `N8N_BASIC_AUTH_USER` | `admin` | n8n web UI username |
| `N8N_BASIC_AUTH_PASSWORD` | *(required)* | n8n web UI password |
| `KUBECONFIG_HOST_PATH` | `~/.kube/config` | Absolute path to your kubeconfig on the HOST machine |
| `OLLAMA_MODEL` | `llama3.1:8b` | Ollama model. Change to `llama3.1:70b` if you have a powerful GPU host. |
| `GENERIC_TIMEZONE` | `UTC` | Timezone |

---

## Available kubectl Tools

The agent can autonomously call these tools to gather context before answering you.

| Tool | Type | Description |
|---|---|---|
| `get_pods` | Read | All pods across namespaces |
| `get_nodes` | Read | Nodes with status |
| `describe_pod` | Read | Detailed pod info + events |
| `get_logs` | Read | Last 100 log lines |
| `get_deployments` | Read | All deployments |
| `get_services` | Read | All services |
| `get_namespaces` | Read | All namespaces |
| `get_events` | Read | Cluster events (newest first) |
| `top_nodes` | Read | Node CPU/memory |
| `top_pods` | Read | Pod CPU/memory |
| `scale_deployment` | **Write** ⚠️ | Scale deployment replicas |
| `restart_deployment` | **Write** ⚠️ | Rolling restart a deployment |
| `apply_manifest` | **Write** ⚠️ | Apply a YAML manifest |
| `exec_in_pod` | Read/Write | Run diagnostic command in pod |

> ⚠️ **Safety mechanism:** For all Write operations, the agent is strictly instructed to show you the exact command it plans to run and ask for your explicit confirmation ("yes") before executing it.

---

## Example Prompts

```text
"List all pods that are not in a Running state."
"Why is my nginx pod in CrashLoopBackOff in the production namespace?"
"Show resource usage across all nodes."
"Get the last 100 log lines from pod api-server-xyz in namespace default."
"Scale the frontend deployment to 5 replicas in production."
"Design a high-availability ingress setup for a 3-node cluster."
"What cluster events happened in the last hour? Any warnings?"
"How do I implement network policies to isolate the payment service?"
```

---

## Troubleshooting

### n8n cannot reach the Kubernetes cluster
```bash
# Check if kubeconfig is mounted correctly
docker compose exec n8n ls -la /home/node/.kube/config

# Test cluster connectivity directly from n8n container
docker compose exec n8n kubectl cluster-info
```

### Ollama not responding or model errors
```bash
# Check Ollama logs
docker compose logs ollama

# Verify model was pulled successfully
docker compose exec ollama ollama list

# Re-pull model if needed
docker compose exec ollama ollama pull llama3.1:8b
```

### Tool nodes showing errors in n8n
- Ensure all 14 sub-workflows are **imported AND activated**.
- Ensure the **Workflow IDs** in the Tool nodes match the actual imported IDs.
- Check the **Executions** tab in n8n for detailed error stack traces.

---

## Architecture

```text
Docker Compose Host
├── n8n :5678                 ← Custom image (n8n + kubectl baked in)
│   ├── AI Agent              ← Orchestrates LLM + tool calls
│   ├── Ollama Chat Model     ← Connects to local Llama 3.1
│   ├── Memory                ← 20-message conversation window
│   └── 14 Tools              ← Execute Command nodes (runs kubectl)
└── Ollama :11434             ← LLM inference (internal network only)

~/.kube/config ── mounted read-only ──→ n8n ── kubectl ──→ Kubernetes Cluster
```

---

## License

MIT
