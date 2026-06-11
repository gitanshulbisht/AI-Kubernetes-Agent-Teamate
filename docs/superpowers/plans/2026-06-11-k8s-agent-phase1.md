# AI Kubernetes Agent Teammate — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a self-hosted AI Kubernetes agent using n8n + Ollama (Llama 3.1) that runs in Docker Compose and gives expert kubectl-powered answers via n8n's built-in chat interface.

**Architecture:** n8n runs in a custom Docker image with kubectl baked in. Ollama serves Llama 3.1 as the LLM. n8n's AI Agent node uses 14 kubectl tool sub-workflows to read/write the cluster. The kubeconfig is mounted read-only into n8n's container from the host.

**Tech Stack:** Docker Compose, n8n (custom image), Ollama (llama3.1:8b for low-RAM or llama3.1:70b for GPU hosts), kubectl v1.30, Bash setup script.

---

## File Map

```
AI-Kubernetes-Agent-Teamate/
├── Dockerfile.n8n                        # Custom n8n image with kubectl
├── docker-compose.yml                    # Stack: n8n + ollama
├── .env.example                          # Template for all env vars
├── .env                                  # Local config (gitignored)
├── .gitignore
├── scripts/
│   └── setup.sh                          # One-command bootstrap script
├── workflows/
│   ├── k8s-agent-workflow.json           # Main AI agent workflow
│   └── tools/                            # 14 kubectl tool sub-workflows
│       ├── get-pods-tool.json
│       ├── get-nodes-tool.json
│       ├── describe-pod-tool.json
│       ├── get-logs-tool.json
│       ├── get-deployments-tool.json
│       ├── get-services-tool.json
│       ├── get-namespaces-tool.json
│       ├── get-events-tool.json
│       ├── top-nodes-tool.json
│       ├── top-pods-tool.json
│       ├── scale-deployment-tool.json
│       ├── restart-deployment-tool.json
│       ├── apply-manifest-tool.json
│       └── exec-in-pod-tool.json
└── README.md
```

---

## Task 1: Repository Foundation

**Files:**
- Create: `.gitignore`
- Create: `.env.example`
- Create: `.env` (gitignored)

- [ ] **Step 1: Create `.gitignore`**

```
# Environment
.env

# n8n data
n8n_data/
ollama_data/

# OS
.DS_Store
*.swp

# kubeconfig copies
kubeconfig
*.kubeconfig
```

- [ ] **Step 2: Create `.env.example`**

```bash
# n8n Basic Auth (protect the web UI)
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=changeme123

# n8n host settings
N8N_HOST=localhost
N8N_PORT=5678
N8N_PROTOCOL=http
WEBHOOK_URL=http://localhost:5678/

# Timezone
GENERIC_TIMEZONE=UTC
TZ=UTC

# Ollama model (llama3.1:8b for CPU/low-RAM, llama3.1:70b for GPU)
OLLAMA_MODEL=llama3.1:8b

# Path to your kubeconfig on the HOST machine
KUBECONFIG_HOST_PATH=/Users/anshulbisht/.kube/config
```

- [ ] **Step 3: Create `.env` from example**

```bash
cp .env.example .env
# Edit .env: set N8N_BASIC_AUTH_PASSWORD and KUBECONFIG_HOST_PATH
```

- [ ] **Step 4: Commit**

```bash
git add .gitignore .env.example
git commit -m "feat: add gitignore and env template"
```

---

## Task 2: Custom n8n Dockerfile with kubectl

**Files:**
- Create: `Dockerfile.n8n`

- [ ] **Step 1: Create `Dockerfile.n8n`**

```dockerfile
# Dockerfile.n8n
# Extends the official n8n image with kubectl for Kubernetes operations

FROM n8nio/n8n:latest

USER root

# Install kubectl (pinned to v1.30.2)
ARG KUBECTL_VERSION=v1.30.2
RUN apk add --no-cache curl ca-certificates \
    && curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" \
    && echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/kubectl \
    && rm kubectl.sha256 \
    && kubectl version --client

# Switch back to non-root n8n user
USER node

# Verify kubectl accessible as node user
RUN kubectl version --client
```

- [ ] **Step 2: Verify Dockerfile builds**

```bash
docker build -f Dockerfile.n8n -t k8s-agent-n8n:test . 2>&1 | tail -20
```

Expected output ends with:
```
Successfully built <image-id>
Successfully tagged k8s-agent-n8n:test
```

- [ ] **Step 3: Commit**

```bash
git add Dockerfile.n8n
git commit -m "feat: custom n8n dockerfile with kubectl binary"
```

---

## Task 3: Docker Compose Stack

**Files:**
- Create: `docker-compose.yml`

- [ ] **Step 1: Create `docker-compose.yml`**

```yaml
# docker-compose.yml
# AI Kubernetes Agent Teammate Stack

version: '3.8'

networks:
  k8s-agent-net:
    driver: bridge

volumes:
  n8n_data:
    driver: local
  ollama_data:
    driver: local

services:
  # ─── Ollama: Local LLM Inference ─────────────────────────────────────────
  ollama:
    image: ollama/ollama:latest
    container_name: k8s-agent-ollama
    restart: unless-stopped
    networks:
      - k8s-agent-net
    volumes:
      - ollama_data:/root/.ollama
    # Uncomment for NVIDIA GPU support:
    # deploy:
    #   resources:
    #     reservations:
    #       devices:
    #         - driver: nvidia
    #           count: all
    #           capabilities: [gpu]
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/version"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  # ─── n8n: AI Agent + Workflow Engine ─────────────────────────────────────
  n8n:
    build:
      context: .
      dockerfile: Dockerfile.n8n
    image: k8s-agent-n8n:latest
    container_name: k8s-agent-n8n
    restart: unless-stopped
    networks:
      - k8s-agent-net
    ports:
      - "5678:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=${N8N_BASIC_AUTH_ACTIVE:-true}
      - N8N_BASIC_AUTH_USER=${N8N_BASIC_AUTH_USER:-admin}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD}
      - N8N_HOST=${N8N_HOST:-localhost}
      - N8N_PORT=${N8N_PORT:-5678}
      - N8N_PROTOCOL=${N8N_PROTOCOL:-http}
      - WEBHOOK_URL=${WEBHOOK_URL:-http://localhost:5678/}
      - GENERIC_TIMEZONE=${GENERIC_TIMEZONE:-UTC}
      - TZ=${TZ:-UTC}
      # Ollama endpoint (internal Docker network — not exposed externally)
      - OLLAMA_BASE_URL=http://ollama:11434
      - OLLAMA_MODEL=${OLLAMA_MODEL:-llama3.1:8b}
      # kubeconfig path inside container (fixed)
      - KUBECONFIG=/home/node/.kube/config
    volumes:
      - n8n_data:/home/node/.n8n
      # kubeconfig mounted read-only from host
      - ${KUBECONFIG_HOST_PATH:-~/.kube/config}:/home/node/.kube/config:ro
    depends_on:
      ollama:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s
```

- [ ] **Step 2: Validate compose file**

```bash
docker compose config
```

Expected: Full merged YAML printed with no errors.

- [ ] **Step 3: Commit**

```bash
git add docker-compose.yml
git commit -m "feat: docker compose stack for n8n + ollama"
```

---

## Task 4: n8n Workflow JSON Files

**Files:**
- Create: `workflows/k8s-agent-workflow.json`
- Create: `workflows/tools/get-pods-tool.json`
- Create: `workflows/tools/get-nodes-tool.json`
- Create: `workflows/tools/describe-pod-tool.json`
- Create: `workflows/tools/get-logs-tool.json`
- Create: `workflows/tools/get-deployments-tool.json`
- Create: `workflows/tools/get-services-tool.json`
- Create: `workflows/tools/get-namespaces-tool.json`
- Create: `workflows/tools/get-events-tool.json`
- Create: `workflows/tools/top-nodes-tool.json`
- Create: `workflows/tools/top-pods-tool.json`
- Create: `workflows/tools/scale-deployment-tool.json`
- Create: `workflows/tools/restart-deployment-tool.json`
- Create: `workflows/tools/apply-manifest-tool.json`
- Create: `workflows/tools/exec-in-pod-tool.json`

- [ ] **Step 1: Create directories**

```bash
mkdir -p workflows/tools
```

- [ ] **Step 2: Create main agent workflow**

Save as `workflows/k8s-agent-workflow.json`:

```json
{
  "name": "AI Kubernetes Agent",
  "nodes": [
    {
      "parameters": { "options": {} },
      "id": "chat-trigger",
      "name": "When chat message received",
      "type": "@n8n/n8n-nodes-langchain.chatTrigger",
      "typeVersion": 1.1,
      "position": [0, 300],
      "webhookId": "k8s-agent-chat"
    },
    {
      "parameters": {
        "options": {
          "systemMessage": "YOU ARE THE WORLD'S LEADING KUBERNETES ARCHITECT, PLATFORM ENGINEER, SITE RELIABILITY ENGINEER (SRE), AND CLOUD-NATIVE INFRASTRUCTURE EXPERT.\n\nYOUR KNOWLEDGE ENCOMPASSES:\n- Kubernetes Architecture: Control Plane, kubelet, kube-proxy, CNI, CSI, CRI\n- Workloads: Pods, Deployments, StatefulSets, DaemonSets, Jobs, CronJobs\n- Networking: Ingress, Gateway API, Service Mesh, DNS\n- Security: RBAC, OPA, Kyverno, Pod Security Standards\n- GitOps: ArgoCD, Flux, Terraform, Pulumi\n- Observability: Prometheus, Grafana, OpenTelemetry\n- Cloud: AWS EKS, Azure AKS, GCP GKE\n- Operations: Incident Response, Upgrades, Capacity Planning, Cost Optimization\n\nCORE BEHAVIOR:\n- THINK LIKE A PRINCIPAL KUBERNETES ENGINEER\n- IDENTIFY ROOT CAUSES, NOT SYMPTOMS\n- PROVIDE PRODUCTION-READY RECOMMENDATIONS\n- STATE ASSUMPTIONS EXPLICITLY\n- EVALUATE TRADE-OFFS\n- CONSIDER FAILURE MODES\n\nKUBECTL TOOLS AVAILABLE:\nAlways call relevant tools FIRST to gather live cluster data, then analyze.\n- get_pods: List all pods across all namespaces\n- get_nodes: List all nodes with status\n- describe_pod: Detailed pod info (params: pod_name, namespace)\n- get_logs: Pod logs last 100 lines (params: pod_name, namespace, optional: container_name)\n- get_deployments: List all deployments\n- get_services: List all services\n- get_namespaces: List all namespaces\n- get_events: Recent cluster events sorted by time\n- top_nodes: Node CPU/memory usage (needs metrics-server)\n- top_pods: Pod CPU/memory usage (needs metrics-server)\n- scale_deployment: Scale replicas (params: deployment_name, namespace, replicas) — WRITE: CONFIRM FIRST\n- restart_deployment: Rolling restart (params: deployment_name, namespace) — WRITE: CONFIRM FIRST\n- apply_manifest: Apply YAML manifest (params: manifest_yaml) — WRITE: CONFIRM FIRST\n- exec_in_pod: Run command in pod (params: pod_name, namespace, command)\n\nWRITE OPERATION SAFETY RULE:\nBEFORE executing scale_deployment, restart_deployment, apply_manifest:\n1. Show the EXACT command that will run\n2. Ask: 'Do you want me to proceed? (yes/no)'\n3. Only execute after explicit 'yes'\n\nOUTPUT FORMAT:\n### Executive Summary\n### Live Cluster Data\n### Root Cause Analysis\n### Recommended Solution\n### Implementation Steps\n### Example Configurations\n### Risks and Trade-Offs\n### Validation Checklist"
        }
      },
      "id": "ai-agent",
      "name": "AI Kubernetes Agent",
      "type": "@n8n/n8n-nodes-langchain.agent",
      "typeVersion": 1.7,
      "position": [300, 300]
    },
    {
      "parameters": {
        "model": "={{ $env.OLLAMA_MODEL || 'llama3.1:8b' }}",
        "options": {
          "baseURL": "={{ $env.OLLAMA_BASE_URL || 'http://ollama:11434' }}"
        }
      },
      "id": "ollama-model",
      "name": "Ollama Chat Model",
      "type": "@n8n/n8n-nodes-langchain.lmChatOllama",
      "typeVersion": 1,
      "position": [300, 500]
    },
    {
      "parameters": {
        "sessionIdType": "fromInput",
        "windowSize": 20
      },
      "id": "memory",
      "name": "Window Buffer Memory",
      "type": "@n8n/n8n-nodes-langchain.memoryBufferWindow",
      "typeVersion": 1.2,
      "position": [500, 500]
    },
    {
      "parameters": {
        "name": "get_pods",
        "description": "List all pods across all namespaces. Returns pod names, namespaces, status, restarts, and age. Use to get workload overview or find pods with issues.",
        "workflowId": { "__rl": true, "value": "REPLACE_WITH_GET_PODS_WORKFLOW_ID", "mode": "id" }
      },
      "id": "tool-get-pods",
      "name": "Tool: get_pods",
      "type": "@n8n/n8n-nodes-langchain.toolWorkflow",
      "typeVersion": 1.2,
      "position": [700, 500]
    },
    {
      "parameters": {
        "name": "get_nodes",
        "description": "List all Kubernetes nodes with status, roles, age, and version. Use to check node health and capacity.",
        "workflowId": { "__rl": true, "value": "REPLACE_WITH_GET_NODES_WORKFLOW_ID", "mode": "id" }
      },
      "id": "tool-get-nodes",
      "name": "Tool: get_nodes",
      "type": "@n8n/n8n-nodes-langchain.toolWorkflow",
      "typeVersion": 1.2,
      "position": [900, 500]
    },
    {
      "parameters": {
        "name": "describe_pod",
        "description": "Get detailed info about a specific pod including events, conditions, container states, resource requests/limits. Requires: pod_name (string), namespace (string).",
        "workflowId": { "__rl": true, "value": "REPLACE_WITH_DESCRIBE_POD_WORKFLOW_ID", "mode": "id" }
      },
      "id": "tool-describe-pod",
      "name": "Tool: describe_pod",
      "type": "@n8n/n8n-nodes-langchain.toolWorkflow",
      "typeVersion": 1.2,
      "position": [1100, 500]
    },
    {
      "parameters": {
        "name": "get_logs",
        "description": "Get last 100 lines of logs from a pod. Requires: pod_name (string), namespace (string). Optional: container_name (string).",
        "workflowId": { "__rl": true, "value": "REPLACE_WITH_GET_LOGS_WORKFLOW_ID", "mode": "id" }
      },
      "id": "tool-get-logs",
      "name": "Tool: get_logs",
      "type": "@n8n/n8n-nodes-langchain.toolWorkflow",
      "typeVersion": 1.2,
      "position": [700, 700]
    },
    {
      "parameters": {
        "name": "get_deployments",
        "description": "List all Deployments across all namespaces including desired/ready/available replicas, images, and age.",
        "workflowId": { "__rl": true, "value": "REPLACE_WITH_GET_DEPLOYMENTS_WORKFLOW_ID", "mode": "id" }
      },
      "id": "tool-get-deployments",
      "name": "Tool: get_deployments",
      "type": "@n8n/n8n-nodes-langchain.toolWorkflow",
      "typeVersion": 1.2,
      "position": [900, 700]
    },
    {
      "parameters": {
        "name": "get_services",
        "description": "List all Kubernetes Services including type, ports, and external IPs.",
        "workflowId": { "__rl": true, "value": "REPLACE_WITH_GET_SERVICES_WORKFLOW_ID", "mode": "id" }
      },
      "id": "tool-get-services",
      "name": "Tool: get_services",
      "type": "@n8n/n8n-nodes-langchain.toolWorkflow",
      "typeVersion": 1.2,
      "position": [1100, 700]
    },
    {
      "parameters": {
        "name": "get_namespaces",
        "description": "List all Kubernetes namespaces with status and age.",
        "workflowId": { "__rl": true, "value": "REPLACE_WITH_GET_NAMESPACES_WORKFLOW_ID", "mode": "id" }
      },
      "id": "tool-get-namespaces",
      "name": "Tool: get_namespaces",
      "type": "@n8n/n8n-nodes-langchain.toolWorkflow",
      "typeVersion": 1.2,
      "position": [700, 900]
    },
    {
      "parameters": {
        "name": "get_events",
        "description": "Get cluster events sorted by time (newest first). Shows Warnings, scheduling failures, OOMKills. Use to diagnose recent issues.",
        "workflowId": { "__rl": true, "value": "REPLACE_WITH_GET_EVENTS_WORKFLOW_ID", "mode": "id" }
      },
      "id": "tool-get-events",
      "name": "Tool: get_events",
      "type": "@n8n/n8n-nodes-langchain.toolWorkflow",
      "typeVersion": 1.2,
      "position": [900, 900]
    },
    {
      "parameters": {
        "name": "top_nodes",
        "description": "Show CPU and memory usage for all nodes. Requires metrics-server in the cluster.",
        "workflowId": { "__rl": true, "value": "REPLACE_WITH_TOP_NODES_WORKFLOW_ID", "mode": "id" }
      },
      "id": "tool-top-nodes",
      "name": "Tool: top_nodes",
      "type": "@n8n/n8n-nodes-langchain.toolWorkflow",
      "typeVersion": 1.2,
      "position": [1100, 900]
    },
    {
      "parameters": {
        "name": "top_pods",
        "description": "Show CPU and memory usage for all pods. Requires metrics-server. Use to find resource-hungry pods.",
        "workflowId": { "__rl": true, "value": "REPLACE_WITH_TOP_PODS_WORKFLOW_ID", "mode": "id" }
      },
      "id": "tool-top-pods",
      "name": "Tool: top_pods",
      "type": "@n8n/n8n-nodes-langchain.toolWorkflow",
      "typeVersion": 1.2,
      "position": [700, 1100]
    },
    {
      "parameters": {
        "name": "scale_deployment",
        "description": "WRITE OPERATION — always confirm with user first. Scale a Deployment to N replicas. Requires: deployment_name (string), namespace (string), replicas (number).",
        "workflowId": { "__rl": true, "value": "REPLACE_WITH_SCALE_DEPLOYMENT_WORKFLOW_ID", "mode": "id" }
      },
      "id": "tool-scale-deployment",
      "name": "Tool: scale_deployment",
      "type": "@n8n/n8n-nodes-langchain.toolWorkflow",
      "typeVersion": 1.2,
      "position": [900, 1100]
    },
    {
      "parameters": {
        "name": "restart_deployment",
        "description": "WRITE OPERATION — always confirm with user first. Rolling restart of a Deployment. Requires: deployment_name (string), namespace (string).",
        "workflowId": { "__rl": true, "value": "REPLACE_WITH_RESTART_DEPLOYMENT_WORKFLOW_ID", "mode": "id" }
      },
      "id": "tool-restart-deployment",
      "name": "Tool: restart_deployment",
      "type": "@n8n/n8n-nodes-langchain.toolWorkflow",
      "typeVersion": 1.2,
      "position": [1100, 1100]
    },
    {
      "parameters": {
        "name": "apply_manifest",
        "description": "WRITE OPERATION — show manifest to user and confirm before calling. Apply a Kubernetes YAML manifest. Requires: manifest_yaml (string, valid YAML).",
        "workflowId": { "__rl": true, "value": "REPLACE_WITH_APPLY_MANIFEST_WORKFLOW_ID", "mode": "id" }
      },
      "id": "tool-apply-manifest",
      "name": "Tool: apply_manifest",
      "type": "@n8n/n8n-nodes-langchain.toolWorkflow",
      "typeVersion": 1.2,
      "position": [700, 1300]
    },
    {
      "parameters": {
        "name": "exec_in_pod",
        "description": "Execute a shell command inside a running pod for diagnostics. Requires: pod_name (string), namespace (string), command (string e.g. 'cat /etc/resolv.conf').",
        "workflowId": { "__rl": true, "value": "REPLACE_WITH_EXEC_IN_POD_WORKFLOW_ID", "mode": "id" }
      },
      "id": "tool-exec-in-pod",
      "name": "Tool: exec_in_pod",
      "type": "@n8n/n8n-nodes-langchain.toolWorkflow",
      "typeVersion": 1.2,
      "position": [900, 1300]
    }
  ],
  "connections": {
    "When chat message received": {
      "main": [[{ "node": "AI Kubernetes Agent", "type": "main", "index": 0 }]]
    },
    "Ollama Chat Model": {
      "ai_languageModel": [[{ "node": "AI Kubernetes Agent", "type": "ai_languageModel", "index": 0 }]]
    },
    "Window Buffer Memory": {
      "ai_memory": [[{ "node": "AI Kubernetes Agent", "type": "ai_memory", "index": 0 }]]
    },
    "Tool: get_pods": { "ai_tool": [[{ "node": "AI Kubernetes Agent", "type": "ai_tool", "index": 0 }]] },
    "Tool: get_nodes": { "ai_tool": [[{ "node": "AI Kubernetes Agent", "type": "ai_tool", "index": 0 }]] },
    "Tool: describe_pod": { "ai_tool": [[{ "node": "AI Kubernetes Agent", "type": "ai_tool", "index": 0 }]] },
    "Tool: get_logs": { "ai_tool": [[{ "node": "AI Kubernetes Agent", "type": "ai_tool", "index": 0 }]] },
    "Tool: get_deployments": { "ai_tool": [[{ "node": "AI Kubernetes Agent", "type": "ai_tool", "index": 0 }]] },
    "Tool: get_services": { "ai_tool": [[{ "node": "AI Kubernetes Agent", "type": "ai_tool", "index": 0 }]] },
    "Tool: get_namespaces": { "ai_tool": [[{ "node": "AI Kubernetes Agent", "type": "ai_tool", "index": 0 }]] },
    "Tool: get_events": { "ai_tool": [[{ "node": "AI Kubernetes Agent", "type": "ai_tool", "index": 0 }]] },
    "Tool: top_nodes": { "ai_tool": [[{ "node": "AI Kubernetes Agent", "type": "ai_tool", "index": 0 }]] },
    "Tool: top_pods": { "ai_tool": [[{ "node": "AI Kubernetes Agent", "type": "ai_tool", "index": 0 }]] },
    "Tool: scale_deployment": { "ai_tool": [[{ "node": "AI Kubernetes Agent", "type": "ai_tool", "index": 0 }]] },
    "Tool: restart_deployment": { "ai_tool": [[{ "node": "AI Kubernetes Agent", "type": "ai_tool", "index": 0 }]] },
    "Tool: apply_manifest": { "ai_tool": [[{ "node": "AI Kubernetes Agent", "type": "ai_tool", "index": 0 }]] },
    "Tool: exec_in_pod": { "ai_tool": [[{ "node": "AI Kubernetes Agent", "type": "ai_tool", "index": 0 }]] }
  },
  "settings": { "executionOrder": "v1" },
  "staticData": null,
  "meta": { "templateCredsSetupCompleted": true },
  "pinData": {}
}
```

- [ ] **Step 3: Create `workflows/tools/get-pods-tool.json`**

```json
{
  "name": "K8s Tool: get_pods",
  "nodes": [
    {
      "parameters": { "workflowInputs": { "values": [] } },
      "id": "trigger",
      "name": "Execute Workflow Trigger",
      "type": "n8n-nodes-base.executeWorkflowTrigger",
      "typeVersion": 1,
      "position": [0, 300]
    },
    {
      "parameters": { "command": "kubectl get pods -A -o wide 2>&1" },
      "id": "kubectl-cmd",
      "name": "kubectl get pods",
      "type": "n8n-nodes-base.executeCommand",
      "typeVersion": 1,
      "position": [300, 300]
    },
    {
      "parameters": {
        "fields": { "values": [{ "name": "output", "stringValue": "={{ $json.stdout || $json.stderr }}" }] },
        "options": {}
      },
      "id": "format-output",
      "name": "Format Output",
      "type": "n8n-nodes-base.set",
      "typeVersion": 3,
      "position": [600, 300]
    }
  ],
  "connections": {
    "Execute Workflow Trigger": { "main": [[{ "node": "kubectl get pods", "type": "main", "index": 0 }]] },
    "kubectl get pods": { "main": [[{ "node": "Format Output", "type": "main", "index": 0 }]] }
  },
  "settings": { "executionOrder": "v1" }
}
```

- [ ] **Step 4: Create `workflows/tools/get-nodes-tool.json`**

```json
{
  "name": "K8s Tool: get_nodes",
  "nodes": [
    {
      "parameters": { "workflowInputs": { "values": [] } },
      "id": "trigger",
      "name": "Execute Workflow Trigger",
      "type": "n8n-nodes-base.executeWorkflowTrigger",
      "typeVersion": 1,
      "position": [0, 300]
    },
    {
      "parameters": { "command": "kubectl get nodes -o wide 2>&1" },
      "id": "kubectl-cmd",
      "name": "kubectl get nodes",
      "type": "n8n-nodes-base.executeCommand",
      "typeVersion": 1,
      "position": [300, 300]
    },
    {
      "parameters": {
        "fields": { "values": [{ "name": "output", "stringValue": "={{ $json.stdout || $json.stderr }}" }] },
        "options": {}
      },
      "id": "format-output",
      "name": "Format Output",
      "type": "n8n-nodes-base.set",
      "typeVersion": 3,
      "position": [600, 300]
    }
  ],
  "connections": {
    "Execute Workflow Trigger": { "main": [[{ "node": "kubectl get nodes", "type": "main", "index": 0 }]] },
    "kubectl get nodes": { "main": [[{ "node": "Format Output", "type": "main", "index": 0 }]] }
  },
  "settings": { "executionOrder": "v1" }
}
```

- [ ] **Step 5: Create `workflows/tools/describe-pod-tool.json`**

```json
{
  "name": "K8s Tool: describe_pod",
  "nodes": [
    {
      "parameters": {
        "workflowInputs": {
          "values": [{ "name": "pod_name" }, { "name": "namespace" }]
        }
      },
      "id": "trigger",
      "name": "Execute Workflow Trigger",
      "type": "n8n-nodes-base.executeWorkflowTrigger",
      "typeVersion": 1,
      "position": [0, 300]
    },
    {
      "parameters": {
        "command": "=kubectl describe pod {{ $json.pod_name }} -n {{ $json.namespace }} 2>&1"
      },
      "id": "kubectl-cmd",
      "name": "kubectl describe pod",
      "type": "n8n-nodes-base.executeCommand",
      "typeVersion": 1,
      "position": [300, 300]
    },
    {
      "parameters": {
        "fields": { "values": [{ "name": "output", "stringValue": "={{ $json.stdout || $json.stderr }}" }] },
        "options": {}
      },
      "id": "format-output",
      "name": "Format Output",
      "type": "n8n-nodes-base.set",
      "typeVersion": 3,
      "position": [600, 300]
    }
  ],
  "connections": {
    "Execute Workflow Trigger": { "main": [[{ "node": "kubectl describe pod", "type": "main", "index": 0 }]] },
    "kubectl describe pod": { "main": [[{ "node": "Format Output", "type": "main", "index": 0 }]] }
  },
  "settings": { "executionOrder": "v1" }
}
```

- [ ] **Step 6: Create `workflows/tools/get-logs-tool.json`**

```json
{
  "name": "K8s Tool: get_logs",
  "nodes": [
    {
      "parameters": {
        "workflowInputs": {
          "values": [{ "name": "pod_name" }, { "name": "namespace" }, { "name": "container_name" }]
        }
      },
      "id": "trigger",
      "name": "Execute Workflow Trigger",
      "type": "n8n-nodes-base.executeWorkflowTrigger",
      "typeVersion": 1,
      "position": [0, 300]
    },
    {
      "parameters": {
        "command": "=kubectl logs {{ $json.pod_name }} -n {{ $json.namespace }} {{ $json.container_name ? '-c ' + $json.container_name : '' }} --tail=100 2>&1"
      },
      "id": "kubectl-cmd",
      "name": "kubectl logs",
      "type": "n8n-nodes-base.executeCommand",
      "typeVersion": 1,
      "position": [300, 300]
    },
    {
      "parameters": {
        "fields": { "values": [{ "name": "output", "stringValue": "={{ $json.stdout || $json.stderr }}" }] },
        "options": {}
      },
      "id": "format-output",
      "name": "Format Output",
      "type": "n8n-nodes-base.set",
      "typeVersion": 3,
      "position": [600, 300]
    }
  ],
  "connections": {
    "Execute Workflow Trigger": { "main": [[{ "node": "kubectl logs", "type": "main", "index": 0 }]] },
    "kubectl logs": { "main": [[{ "node": "Format Output", "type": "main", "index": 0 }]] }
  },
  "settings": { "executionOrder": "v1" }
}
```

- [ ] **Step 7: Create remaining 10 tool workflow files**

Run this script to create `get-deployments`, `get-services`, `get-namespaces`, `get-events`, `top-nodes`, `top-pods`, `scale-deployment`, `restart-deployment`, `apply-manifest`, and `exec-in-pod` tools:

```bash
# get-deployments-tool.json
cat > workflows/tools/get-deployments-tool.json << 'EOF'
{
  "name": "K8s Tool: get_deployments",
  "nodes": [
    { "parameters": { "workflowInputs": { "values": [] } }, "id": "trigger", "name": "Execute Workflow Trigger", "type": "n8n-nodes-base.executeWorkflowTrigger", "typeVersion": 1, "position": [0, 300] },
    { "parameters": { "command": "kubectl get deployments -A -o wide 2>&1" }, "id": "kubectl-cmd", "name": "kubectl get deployments", "type": "n8n-nodes-base.executeCommand", "typeVersion": 1, "position": [300, 300] },
    { "parameters": { "fields": { "values": [{ "name": "output", "stringValue": "={{ $json.stdout || $json.stderr }}" }] }, "options": {} }, "id": "format-output", "name": "Format Output", "type": "n8n-nodes-base.set", "typeVersion": 3, "position": [600, 300] }
  ],
  "connections": { "Execute Workflow Trigger": { "main": [[{ "node": "kubectl get deployments", "type": "main", "index": 0 }]] }, "kubectl get deployments": { "main": [[{ "node": "Format Output", "type": "main", "index": 0 }]] } },
  "settings": { "executionOrder": "v1" }
}
EOF

# get-services-tool.json
cat > workflows/tools/get-services-tool.json << 'EOF'
{
  "name": "K8s Tool: get_services",
  "nodes": [
    { "parameters": { "workflowInputs": { "values": [] } }, "id": "trigger", "name": "Execute Workflow Trigger", "type": "n8n-nodes-base.executeWorkflowTrigger", "typeVersion": 1, "position": [0, 300] },
    { "parameters": { "command": "kubectl get services -A -o wide 2>&1" }, "id": "kubectl-cmd", "name": "kubectl get services", "type": "n8n-nodes-base.executeCommand", "typeVersion": 1, "position": [300, 300] },
    { "parameters": { "fields": { "values": [{ "name": "output", "stringValue": "={{ $json.stdout || $json.stderr }}" }] }, "options": {} }, "id": "format-output", "name": "Format Output", "type": "n8n-nodes-base.set", "typeVersion": 3, "position": [600, 300] }
  ],
  "connections": { "Execute Workflow Trigger": { "main": [[{ "node": "kubectl get services", "type": "main", "index": 0 }]] }, "kubectl get services": { "main": [[{ "node": "Format Output", "type": "main", "index": 0 }]] } },
  "settings": { "executionOrder": "v1" }
}
EOF

# get-namespaces-tool.json
cat > workflows/tools/get-namespaces-tool.json << 'EOF'
{
  "name": "K8s Tool: get_namespaces",
  "nodes": [
    { "parameters": { "workflowInputs": { "values": [] } }, "id": "trigger", "name": "Execute Workflow Trigger", "type": "n8n-nodes-base.executeWorkflowTrigger", "typeVersion": 1, "position": [0, 300] },
    { "parameters": { "command": "kubectl get namespaces 2>&1" }, "id": "kubectl-cmd", "name": "kubectl get namespaces", "type": "n8n-nodes-base.executeCommand", "typeVersion": 1, "position": [300, 300] },
    { "parameters": { "fields": { "values": [{ "name": "output", "stringValue": "={{ $json.stdout || $json.stderr }}" }] }, "options": {} }, "id": "format-output", "name": "Format Output", "type": "n8n-nodes-base.set", "typeVersion": 3, "position": [600, 300] }
  ],
  "connections": { "Execute Workflow Trigger": { "main": [[{ "node": "kubectl get namespaces", "type": "main", "index": 0 }]] }, "kubectl get namespaces": { "main": [[{ "node": "Format Output", "type": "main", "index": 0 }]] } },
  "settings": { "executionOrder": "v1" }
}
EOF

# get-events-tool.json
cat > workflows/tools/get-events-tool.json << 'EOF'
{
  "name": "K8s Tool: get_events",
  "nodes": [
    { "parameters": { "workflowInputs": { "values": [] } }, "id": "trigger", "name": "Execute Workflow Trigger", "type": "n8n-nodes-base.executeWorkflowTrigger", "typeVersion": 1, "position": [0, 300] },
    { "parameters": { "command": "kubectl get events -A --sort-by=.metadata.creationTimestamp 2>&1 | tail -50" }, "id": "kubectl-cmd", "name": "kubectl get events", "type": "n8n-nodes-base.executeCommand", "typeVersion": 1, "position": [300, 300] },
    { "parameters": { "fields": { "values": [{ "name": "output", "stringValue": "={{ $json.stdout || $json.stderr }}" }] }, "options": {} }, "id": "format-output", "name": "Format Output", "type": "n8n-nodes-base.set", "typeVersion": 3, "position": [600, 300] }
  ],
  "connections": { "Execute Workflow Trigger": { "main": [[{ "node": "kubectl get events", "type": "main", "index": 0 }]] }, "kubectl get events": { "main": [[{ "node": "Format Output", "type": "main", "index": 0 }]] } },
  "settings": { "executionOrder": "v1" }
}
EOF

# top-nodes-tool.json
cat > workflows/tools/top-nodes-tool.json << 'EOF'
{
  "name": "K8s Tool: top_nodes",
  "nodes": [
    { "parameters": { "workflowInputs": { "values": [] } }, "id": "trigger", "name": "Execute Workflow Trigger", "type": "n8n-nodes-base.executeWorkflowTrigger", "typeVersion": 1, "position": [0, 300] },
    { "parameters": { "command": "kubectl top nodes 2>&1" }, "id": "kubectl-cmd", "name": "kubectl top nodes", "type": "n8n-nodes-base.executeCommand", "typeVersion": 1, "position": [300, 300] },
    { "parameters": { "fields": { "values": [{ "name": "output", "stringValue": "={{ $json.stdout || $json.stderr }}" }] }, "options": {} }, "id": "format-output", "name": "Format Output", "type": "n8n-nodes-base.set", "typeVersion": 3, "position": [600, 300] }
  ],
  "connections": { "Execute Workflow Trigger": { "main": [[{ "node": "kubectl top nodes", "type": "main", "index": 0 }]] }, "kubectl top nodes": { "main": [[{ "node": "Format Output", "type": "main", "index": 0 }]] } },
  "settings": { "executionOrder": "v1" }
}
EOF

# top-pods-tool.json
cat > workflows/tools/top-pods-tool.json << 'EOF'
{
  "name": "K8s Tool: top_pods",
  "nodes": [
    { "parameters": { "workflowInputs": { "values": [] } }, "id": "trigger", "name": "Execute Workflow Trigger", "type": "n8n-nodes-base.executeWorkflowTrigger", "typeVersion": 1, "position": [0, 300] },
    { "parameters": { "command": "kubectl top pods -A 2>&1" }, "id": "kubectl-cmd", "name": "kubectl top pods", "type": "n8n-nodes-base.executeCommand", "typeVersion": 1, "position": [300, 300] },
    { "parameters": { "fields": { "values": [{ "name": "output", "stringValue": "={{ $json.stdout || $json.stderr }}" }] }, "options": {} }, "id": "format-output", "name": "Format Output", "type": "n8n-nodes-base.set", "typeVersion": 3, "position": [600, 300] }
  ],
  "connections": { "Execute Workflow Trigger": { "main": [[{ "node": "kubectl top pods", "type": "main", "index": 0 }]] }, "kubectl top pods": { "main": [[{ "node": "Format Output", "type": "main", "index": 0 }]] } },
  "settings": { "executionOrder": "v1" }
}
EOF

# scale-deployment-tool.json
cat > workflows/tools/scale-deployment-tool.json << 'EOF'
{
  "name": "K8s Tool: scale_deployment",
  "nodes": [
    {
      "parameters": { "workflowInputs": { "values": [{ "name": "deployment_name" }, { "name": "namespace" }, { "name": "replicas" }] } },
      "id": "trigger", "name": "Execute Workflow Trigger", "type": "n8n-nodes-base.executeWorkflowTrigger", "typeVersion": 1, "position": [0, 300]
    },
    {
      "parameters": { "command": "=kubectl scale deployment {{ $json.deployment_name }} --replicas={{ $json.replicas }} -n {{ $json.namespace }} 2>&1" },
      "id": "kubectl-cmd", "name": "kubectl scale", "type": "n8n-nodes-base.executeCommand", "typeVersion": 1, "position": [300, 300]
    },
    { "parameters": { "fields": { "values": [{ "name": "output", "stringValue": "={{ $json.stdout || $json.stderr }}" }] }, "options": {} }, "id": "format-output", "name": "Format Output", "type": "n8n-nodes-base.set", "typeVersion": 3, "position": [600, 300] }
  ],
  "connections": { "Execute Workflow Trigger": { "main": [[{ "node": "kubectl scale", "type": "main", "index": 0 }]] }, "kubectl scale": { "main": [[{ "node": "Format Output", "type": "main", "index": 0 }]] } },
  "settings": { "executionOrder": "v1" }
}
EOF

# restart-deployment-tool.json
cat > workflows/tools/restart-deployment-tool.json << 'EOF'
{
  "name": "K8s Tool: restart_deployment",
  "nodes": [
    {
      "parameters": { "workflowInputs": { "values": [{ "name": "deployment_name" }, { "name": "namespace" }] } },
      "id": "trigger", "name": "Execute Workflow Trigger", "type": "n8n-nodes-base.executeWorkflowTrigger", "typeVersion": 1, "position": [0, 300]
    },
    {
      "parameters": { "command": "=kubectl rollout restart deployment/{{ $json.deployment_name }} -n {{ $json.namespace }} 2>&1" },
      "id": "kubectl-cmd", "name": "kubectl rollout restart", "type": "n8n-nodes-base.executeCommand", "typeVersion": 1, "position": [300, 300]
    },
    { "parameters": { "fields": { "values": [{ "name": "output", "stringValue": "={{ $json.stdout || $json.stderr }}" }] }, "options": {} }, "id": "format-output", "name": "Format Output", "type": "n8n-nodes-base.set", "typeVersion": 3, "position": [600, 300] }
  ],
  "connections": { "Execute Workflow Trigger": { "main": [[{ "node": "kubectl rollout restart", "type": "main", "index": 0 }]] }, "kubectl rollout restart": { "main": [[{ "node": "Format Output", "type": "main", "index": 0 }]] } },
  "settings": { "executionOrder": "v1" }
}
EOF

# apply-manifest-tool.json
cat > workflows/tools/apply-manifest-tool.json << 'EOF'
{
  "name": "K8s Tool: apply_manifest",
  "nodes": [
    {
      "parameters": { "workflowInputs": { "values": [{ "name": "manifest_yaml" }] } },
      "id": "trigger", "name": "Execute Workflow Trigger", "type": "n8n-nodes-base.executeWorkflowTrigger", "typeVersion": 1, "position": [0, 300]
    },
    {
      "parameters": { "command": "=printf '%s' {{ JSON.stringify($json.manifest_yaml) }} | kubectl apply -f - 2>&1" },
      "id": "kubectl-cmd", "name": "kubectl apply", "type": "n8n-nodes-base.executeCommand", "typeVersion": 1, "position": [300, 300]
    },
    { "parameters": { "fields": { "values": [{ "name": "output", "stringValue": "={{ $json.stdout || $json.stderr }}" }] }, "options": {} }, "id": "format-output", "name": "Format Output", "type": "n8n-nodes-base.set", "typeVersion": 3, "position": [600, 300] }
  ],
  "connections": { "Execute Workflow Trigger": { "main": [[{ "node": "kubectl apply", "type": "main", "index": 0 }]] }, "kubectl apply": { "main": [[{ "node": "Format Output", "type": "main", "index": 0 }]] } },
  "settings": { "executionOrder": "v1" }
}
EOF

# exec-in-pod-tool.json
cat > workflows/tools/exec-in-pod-tool.json << 'EOF'
{
  "name": "K8s Tool: exec_in_pod",
  "nodes": [
    {
      "parameters": { "workflowInputs": { "values": [{ "name": "pod_name" }, { "name": "namespace" }, { "name": "command" }] } },
      "id": "trigger", "name": "Execute Workflow Trigger", "type": "n8n-nodes-base.executeWorkflowTrigger", "typeVersion": 1, "position": [0, 300]
    },
    {
      "parameters": { "command": "=kubectl exec {{ $json.pod_name }} -n {{ $json.namespace }} -- sh -c {{ JSON.stringify($json.command) }} 2>&1" },
      "id": "kubectl-cmd", "name": "kubectl exec", "type": "n8n-nodes-base.executeCommand", "typeVersion": 1, "position": [300, 300]
    },
    { "parameters": { "fields": { "values": [{ "name": "output", "stringValue": "={{ $json.stdout || $json.stderr }}" }] }, "options": {} }, "id": "format-output", "name": "Format Output", "type": "n8n-nodes-base.set", "typeVersion": 3, "position": [600, 300] }
  ],
  "connections": { "Execute Workflow Trigger": { "main": [[{ "node": "kubectl exec", "type": "main", "index": 0 }]] }, "kubectl exec": { "main": [[{ "node": "Format Output", "type": "main", "index": 0 }]] } },
  "settings": { "executionOrder": "v1" }
}
EOF
```

- [ ] **Step 8: Verify all 15 workflow files exist**

```bash
ls -1 workflows/k8s-agent-workflow.json workflows/tools/*.json | wc -l
```

Expected: `15`

- [ ] **Step 9: Commit all workflow files**

```bash
git add workflows/
git commit -m "feat: add n8n agent workflow and 14 kubectl tool sub-workflows"
```

---

## Task 5: Setup Script

**Files:**
- Create: `scripts/setup.sh`

- [ ] **Step 1: Create setup script**

```bash
mkdir -p scripts
```

Save as `scripts/setup.sh`:

```bash
#!/usr/bin/env bash
# scripts/setup.sh — One-command bootstrap for AI Kubernetes Agent Teammate
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║  AI Kubernetes Agent Teammate — Setup     ║"
echo "╚═══════════════════════════════════════════╝"
echo ""

# Prerequisites
info "Checking prerequisites..."
command -v docker >/dev/null 2>&1 || error "Docker not installed. https://docs.docker.com/get-docker/"
docker compose version >/dev/null 2>&1 || error "Docker Compose v2 not installed."
info "Docker: $(docker --version)"

# Environment
if [ ! -f ".env" ]; then
  warn ".env not found — copying from .env.example"
  cp .env.example .env
  echo ""
  warn "⚠️  Edit .env before continuing:"
  warn "   1. Set N8N_BASIC_AUTH_PASSWORD to a strong password"
  warn "   2. Set KUBECONFIG_HOST_PATH to your kubeconfig path (e.g. $HOME/.kube/config)"
  echo ""
  read -p "Press Enter after editing .env..."
fi

set -a; source .env; set +a

KUBE_PATH="${KUBECONFIG_HOST_PATH:-$HOME/.kube/config}"
[ -f "$KUBE_PATH" ] || error "kubeconfig not found at $KUBE_PATH. Set KUBECONFIG_HOST_PATH in .env."
info "kubeconfig found: $KUBE_PATH ✓"

# Build
info "Building custom n8n image with kubectl..."
docker compose build --no-cache n8n
info "n8n image built ✓"

# Start Ollama
info "Starting Ollama..."
docker compose up -d ollama
info "Waiting for Ollama to be healthy..."
until docker compose exec ollama curl -sf http://localhost:11434/api/version >/dev/null 2>&1; do
  sleep 5; echo -n "."
done
echo ""; info "Ollama ready ✓"

# Pull model
MODEL="${OLLAMA_MODEL:-llama3.1:8b}"
info "Pulling model: $MODEL (may take several minutes on first run)..."
docker compose exec ollama ollama pull "$MODEL"
info "Model $MODEL ready ✓"

# Start n8n
info "Starting n8n..."
docker compose up -d n8n
info "Waiting for n8n..."
until docker compose exec n8n curl -sf http://localhost:5678/healthz >/dev/null 2>&1; do
  sleep 5; echo -n "."
done
echo ""; info "n8n ready ✓"

# Verify
info "Verifying kubectl in n8n container..."
docker compose exec n8n kubectl version --client
info "kubectl accessible ✓"

info "Testing cluster connectivity..."
if docker compose exec n8n kubectl cluster-info --request-timeout=5s 2>&1; then
  info "Cluster reachable ✓"
else
  warn "Cannot reach cluster. Check KUBECONFIG_HOST_PATH and cluster accessibility."
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ✅ Setup complete! Next steps:                              ║"
echo "║                                                              ║"
echo "║  1. Open n8n: http://localhost:5678                          ║"
echo "║     Login with credentials from your .env file              ║"
echo "║                                                              ║"
echo "║  2. Import tool workflows (Workflows → Import from File):    ║"
echo "║     - Import all 14 files in: workflows/tools/              ║"
echo "║     - Activate each tool workflow                            ║"
echo "║     - Import: workflows/k8s-agent-workflow.json             ║"
echo "║     - Update Tool node Workflow IDs (see README)            ║"
echo "║                                                              ║"
echo "║  3. Activate the 'AI Kubernetes Agent' workflow              ║"
echo "║  4. Click the chat bubble icon and start chatting!          ║"
echo "║                                                              ║"
echo "║  📖 README.md has full details                               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
```

- [ ] **Step 2: Make script executable**

```bash
chmod +x scripts/setup.sh
```

- [ ] **Step 3: Commit**

```bash
git add scripts/setup.sh
git commit -m "feat: one-command setup script"
```

---

## Task 6: README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Create `README.md`**

```markdown
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
| ~8GB RAM | For llama3.1:8b model |

---

## Quick Start

```bash
./scripts/setup.sh
```

Then open http://localhost:5678 and import the workflows (see Import Guide below).

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

> This step is required after first setup and after any `docker compose down -v`.

1. Open http://localhost:5678 and log in
2. Go to **Workflows → ⊕ New → Import from File**
3. Import **all 14 files** from `workflows/tools/` one at a time
4. **Activate** each tool workflow (toggle in top-right of each workflow)
5. Import `workflows/k8s-agent-workflow.json`
6. Open the **AI Kubernetes Agent** workflow
7. For each Tool node, click it and update the **Workflow ID** to match the imported sub-workflow's ID (visible in each tool workflow's URL after import)
8. **Activate** the AI Kubernetes Agent workflow
9. Click the **chat bubble icon** (bottom-left) to open chat

---

## Configuration

| Variable | Default | Description |
|---|---|---|
| `N8N_BASIC_AUTH_USER` | `admin` | n8n web UI username |
| `N8N_BASIC_AUTH_PASSWORD` | *(required)* | n8n web UI password |
| `KUBECONFIG_HOST_PATH` | `~/.kube/config` | Path to kubeconfig on HOST machine |
| `OLLAMA_MODEL` | `llama3.1:8b` | Ollama model (use 70b for GPU hosts) |
| `GENERIC_TIMEZONE` | `UTC` | Timezone |

---

## Available kubectl Tools

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
| `scale_deployment` | **Write** ⚠️ | Scale replicas |
| `restart_deployment` | **Write** ⚠️ | Rolling restart |
| `apply_manifest` | **Write** ⚠️ | Apply YAML |
| `exec_in_pod` | Read/Write | Run command in pod |

⚠️ Write operations require explicit "yes" confirmation before executing.

---

## Example Prompts

```
"List all pods that are not Running"
"Why is my nginx pod in CrashLoopBackOff in the production namespace?"
"Show resource usage across all nodes"
"Get the last 100 log lines from pod api-server-xyz in namespace default"
"Scale the frontend deployment to 5 replicas in production"
"Design a high-availability ingress setup for a 3-node cluster"
"What cluster events happened in the last hour?"
"How do I implement network policies to isolate the payment service?"
```

---

## Troubleshooting

### n8n can't reach the cluster
```bash
docker compose exec n8n ls -la /home/node/.kube/config
docker compose exec n8n kubectl cluster-info
```

### Ollama not responding
```bash
docker compose logs ollama
docker compose exec ollama ollama list
docker compose exec ollama ollama pull llama3.1:8b
```

### Tool nodes showing errors
- Ensure all 14 sub-workflows are **imported and activated**
- Ensure Workflow IDs in Tool nodes match the imported sub-workflow IDs
- Check **Executions** tab in n8n for detailed error output

---

## Architecture

```
Docker Host
├── n8n :5678        ← Custom image (n8n + kubectl)
│   ├── AI Agent     ← Orchestrates LLM + tool calls
│   ├── Ollama LLM   ← Llama 3.1 (via Ollama container)
│   ├── Memory       ← 20-message conversation window
│   └── 14 Tools     ← Execute Command nodes (kubectl)
└── Ollama :11434    ← LLM inference (internal network only)

~/.kube/config → mounted read-only → kubectl → Kubernetes Cluster
```

---

## Roadmap

- [x] Phase 1: n8n built-in chat + kubectl tools
- [ ] Phase 2: Custom web frontend with syntax highlighting
- [ ] Phase 3: Slack / Teams / Discord bot
- [ ] Phase 4: CrashLoop / OOMKill alert subscriptions
- [ ] Phase 5: Multi-cluster support
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with setup and usage guide"
```

---

## Task 7: Start Stack and Validate

**No files — runtime validation.**

- [ ] **Step 1: Run setup script (or start manually)**

```bash
./scripts/setup.sh
```

Or manually:
```bash
docker compose up -d --build
docker compose exec ollama ollama pull llama3.1:8b
```

- [ ] **Step 2: Verify both containers healthy**

```bash
docker compose ps
```

Expected output:
```
NAME                  IMAGE                   STATUS
k8s-agent-n8n         k8s-agent-n8n:latest    Up (healthy)
k8s-agent-ollama      ollama/ollama:latest     Up (healthy)
```

- [ ] **Step 3: Verify kubectl inside n8n**

```bash
docker compose exec n8n kubectl version --client
```

Expected:
```
Client Version: v1.30.2
Kustomize Version: v5.x.x
```

- [ ] **Step 4: Verify cluster connectivity**

```bash
docker compose exec n8n kubectl get nodes
```

Expected: Your cluster's nodes listed with Ready status.

- [ ] **Step 5: Import all 15 workflows into n8n**

Open http://localhost:5678, log in, then:
1. Workflows → Import from File → import each of the 14 files in `workflows/tools/`
2. Activate each tool workflow
3. Import `workflows/k8s-agent-workflow.json`
4. For each Tool node in the agent workflow, update the Workflow ID field to match the ID shown in each imported tool's URL (`http://localhost:5678/workflow/<ID>`)
5. Activate the AI Kubernetes Agent workflow

- [ ] **Step 6: Test the agent with a read query**

In the n8n chat interface, send:
```
Hello! Can you list all the pods currently running in my cluster?
```

Expected: Agent calls `get_pods` tool, receives kubectl output, responds with formatted analysis.

- [ ] **Step 7: Test troubleshooting mode**

```
What cluster events have occurred recently? Are there any warnings I should know about?
```

Expected: Agent calls `get_events`, returns events table, provides analysis of any warnings.

- [ ] **Step 8: Test write operation safety prompt**

```
Scale the nginx deployment in the default namespace to 3 replicas
```

Expected: Agent shows the exact kubectl command it will run and asks for confirmation before executing.

- [ ] **Step 9: Final commit**

```bash
git add -A
git commit -m "chore: phase 1 implementation complete"
```

---

## Verification Checklist

- [ ] `docker compose ps` shows both containers as `(healthy)`
- [ ] `docker compose exec n8n kubectl get nodes` returns cluster nodes
- [ ] n8n accessible at http://localhost:5678 with basic auth
- [ ] Ollama model `llama3.1:8b` loaded and responding
- [ ] All 14 tool sub-workflows imported and active
- [ ] Agent workflow imported and active
- [ ] Chat responds to "list all pods" with live cluster data
- [ ] "Show recent events" returns cluster event data
- [ ] Scale command shows confirmation prompt before executing
- [ ] n8n Executions page shows kubectl commands that ran
