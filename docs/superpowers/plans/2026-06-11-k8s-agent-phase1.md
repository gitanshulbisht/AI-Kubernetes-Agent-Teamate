# AI Kubernetes Agent Teammate — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a self-hosted AI Kubernetes agent using n8n + OpenRouter (Llama 3 70B+) that runs in Docker Compose and gives expert kubectl-powered answers via n8n's built-in chat interface.

**Architecture:** n8n runs in a custom Docker image with kubectl baked in. n8n's AI Agent node uses 14 kubectl tool sub-workflows to read/write the cluster. The kubeconfig is mounted read-only into n8n's container from the host.

**Tech Stack:** Docker Compose, n8n (v1.123.55 custom image), OpenRouter, kubectl v1.30, Bash setup script.

---

## File Map

```
AI-Kubernetes-Agent-Teamate/
├── Dockerfile.n8n                        # Custom n8n image with kubectl
├── docker-compose.yml                    # Stack: n8n
├── .env.example                          # Template for all env vars
├── .env                                  # Local config (gitignored)
├── internal-kubeconfig.yaml              # Modified kubeconfig for Docker
├── .gitignore
├── PROJECT_JOURNEY.md                    # Record of architectural pivots
├── workflows/
│   ├── k8s-agent-workflow.json           # Main AI agent workflow
│   └── tools/                            # 14 kubectl tool sub-workflows
└── README.md
```

---

## Task 1: Repository Foundation

**Files:**
- Create: `.gitignore`
- Create: `.env.example`
- Create: `.env` (gitignored)

- [ ] **Step 1: Create `.gitignore`**
- [ ] **Step 2: Create `.env.example`**
- [ ] **Step 3: Create `.env` from example**
- [ ] **Step 4: Commit**

---

## Task 2: Custom n8n Dockerfile with kubectl

**Files:**
- Create: `Dockerfile.n8n`

- [ ] **Step 1: Create `Dockerfile.n8n`**
Use `FROM n8nio/n8n:1.123.55` to avoid Langchain URL bugs in v2.x.
- [ ] **Step 2: Verify Dockerfile builds**
- [ ] **Step 3: Commit**

---

## Task 3: Docker Compose Stack

**Files:**
- Create: `docker-compose.yml`

- [ ] **Step 1: Create `docker-compose.yml`**
Mount `KUBECONFIG_HOST_PATH` (pointing to `internal-kubeconfig.yaml`) to `/home/node/.kube/config` as read-only.
- [ ] **Step 2: Validate compose file**
- [ ] **Step 3: Commit**

---

## Task 4: n8n Workflow JSON Files

**Files:**
- Create: `workflows/k8s-agent-workflow.json` (Using OpenRouter node)
- Create: `workflows/tools/get-pods-tool.json`
- Create: `workflows/tools/get-nodes-tool.json`
- Create: `workflows/tools/describe-pod-tool.json` (Requires Extra Workflow Inputs mappings)
- Create: `workflows/tools/get-logs-tool.json` (Requires Extra Workflow Inputs mappings)
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
- [ ] **Step 2: Create main agent workflow**
- [ ] **Step 3: Create all 14 tool workflow files**
- [ ] **Step 4: Commit**

---

## Task 5: Docker Mac Loopback Fix (`internal-kubeconfig.yaml`)

**Files:**
- Create script to generate `internal-kubeconfig.yaml`

- [ ] **Step 1: Copy ~/.kube/config**
- [ ] **Step 2: Modify server IP**
Change `https://127.0.0.1:xxx` to `https://host.docker.internal:xxx`.
- [ ] **Step 3: Disable TLS verification**
Run `kubectl config set-cluster kind-kubernetes-demo-cluster --insecure-skip-tls-verify=true --kubeconfig=internal-kubeconfig.yaml`.
- [ ] **Step 4: Update `.env`**
Set `KUBECONFIG_HOST_PATH` to point to the newly generated `internal-kubeconfig.yaml`.

---

## Task 6: UI Configuration

- [ ] **Step 1: Map Sub-Workflows**
In n8n, change the Workflow ID for each of the 14 tool nodes.
- [ ] **Step 2: Map Tool Arguments**
For tools taking parameters, use the ✨ button (or type `={{ $fromAI('parameter_name') }}`) in Extra Workflow Inputs.
