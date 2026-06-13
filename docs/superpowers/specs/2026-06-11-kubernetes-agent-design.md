# AI Kubernetes Agent Teammate — Design Spec

**Date:** 2026-06-11  
**Status:** Approved  
**Phase:** 1 of 3 (n8n built-in chat)

---

## Overview

A self-hosted AI Kubernetes agent that acts as a principal-level SRE/Platform engineer teammate. Users interact with the agent through chat to ask questions about their cluster, get troubleshooting guidance, and issue operational commands. The agent can connect to a live Kubernetes cluster with both read and write capabilities.

---

## Phased Delivery

| Phase | Interface | Scope |
|---|---|---|
| **1 (Now)** | n8n built-in chat UI | Core agent + kubectl tools |
| **2 (Next)** | Custom web frontend (React/HTML) | Beautiful UI, chat history |
| **3 (Later)** | Slack / Teams / Discord bot | Team-wide notifications + commands |

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Docker Compose Host                    │
│                                                         │
│  ┌──────────────────┐    ┌──────────────────────────┐  │
│  │      n8n          │    │      OpenRouter /        │  │
│  │  (port 5678)     │◄──►│      NVIDIA NIM          │  │
│  │  v1.123.55       │    │  Model: Llama 3 70B+     │  │
│  │  ┌────────────┐  │    └──────────────────────────┘  │
│  │  │ AI Agent   │  │                                   │
│  │  │   Node     │  │    ┌──────────────────────────┐  │
│  │  └─────┬──────┘  │    │   internal-kubeconfig    │  │
│  │        │ Tools   │    │   (mounted into n8n)     │  │
│  │  ┌─────▼──────┐  │    └──────────────────────────┘  │
│  │  │ kubectl    │  │                                   │
│  │  │ Tool Nodes │  │                                   │
│  │  └────────────┘  │                                   │
│  └──────────────────┘                                   │
└─────────────────────────────────────────────────────────┘
          │
          ▼
  Kubernetes Cluster (remote or local via host.docker.internal)
```

### Key Design Decisions

- **n8n runs outside the cluster** (Docker Compose on Linux/Mac host) — separation of concerns, multi-cluster capable.
- **n8n Version pinned to v1.123.55** — prevents Langchain URL validation bugs found in n8n v2.x.
- **Cloud LLM (OpenRouter)** — local Ollama (Llama 3 8B) struggled with Langchain's complex JSON tool schemas. We offloaded to a powerful 70B+ model.
- **kubectl binary installed inside n8n's container** via custom Dockerfile.
- **kubeconfig mounted read-only** into n8n container for security.

---

## Components

### 1. Docker Compose Stack

**Services:**
- `n8n` — custom image extending `n8nio/n8n:1.123.55` with `kubectl` binary added.

**Volumes:**
- `n8n_data` — persistent n8n data (workflows, credentials, executions)

**Networking:**
- n8n exposed on `0.0.0.0:5678`
- Modified `kubeconfig` uses `host.docker.internal` (for macOS/Windows users) to route `kubectl` commands from inside the container back to the host's local cluster (e.g., kind, Docker Desktop).

### 2. Custom n8n Dockerfile

Extends `n8nio/n8n:1.123.55` with:
- `kubectl` binary (pinned to a specific version)
- `curl` for health checks
- Non-root user preserved

### 3. n8n Agent Workflow

The core workflow (exported as JSON for easy import) includes:

**Trigger:** Chat Message Received  
**Agent:** AI Agent Node with OpenRouter Chat Model  
**Memory:** Window Buffer Memory (last 20 messages for context)  
**System Prompt:** Full Kubernetes expert system prompt (see below)

**kubectl Tool Nodes (14 tools):**

| Tool Name | Command | Type |
|---|---|---|
| `get_pods` | `kubectl get pods -A -o wide` | Read |
| `get_nodes` | `kubectl get nodes -o wide` | Read |
| `describe_pod` | `kubectl describe pod {name} -n {namespace}` | Read |
| `get_logs` | `kubectl logs {pod} -n {namespace} --tail=100` | Read |
| `get_deployments` | `kubectl get deployments -A -o wide` | Read |
| `get_services` | `kubectl get services -A -o wide` | Read |
| `get_namespaces` | `kubectl get namespaces` | Read |
| `get_events` | `kubectl get events -A --sort-by=.metadata.creationTimestamp` | Read |
| `top_nodes` | `kubectl top nodes` | Read |
| `top_pods` | `kubectl top pods -A` | Read |
| `scale_deployment` | `kubectl scale deployment {name} --replicas={n} -n {ns}` | **Write** |
| `restart_deployment` | `kubectl rollout restart deployment/{name} -n {ns}` | **Write** |
| `apply_manifest` | `kubectl apply -f -` (stdin) | **Write** |
| `exec_command` | `kubectl exec {pod} -n {ns} -- {cmd}` | Read/Write |

### 4. System Prompt

The world-leading Kubernetes architect system prompt covers:
- Kubernetes architecture expertise
- Chain-of-thought troubleshooting framework
- YAML generation rules
- Output format requirements (Executive Summary, Root Cause, Steps, YAML, Trade-offs)

---

## Data Flow

1. User types question in n8n chat
2. AI Agent receives message with full expert system prompt
3. OpenRouter (Llama 3 70B+) generates plan and decides which tools to invoke
4. Tool nodes execute `kubectl` commands via `Execute Command` node
5. Results returned to OpenRouter as tool call outputs
6. OpenRouter synthesizes production-grade response
7. Response displayed in n8n chat

---

## Error Handling

| Scenario | Behavior |
|---|---|
| Cluster unreachable | Agent reports kubectl error, suggests `kubectl cluster-info` and connectivity checks |
| Permission denied (RBAC) | Agent explains RBAC issue and suggests remediation |
| Write operations | Agent shows exact command, asks "Confirm? (yes/no)" before executing |
| Delete/drain operations | Explicit double-confirmation required |
| Mac Docker Loopback | `internal-kubeconfig.yaml` points to `host.docker.internal` instead of `127.0.0.1` with `insecure-skip-tls-verify: true` |

---

## Security Model

- kubeconfig mounted **read-only** (`ro` flag in Docker Compose)
- Write operations require chat confirmation before execution
- All executed commands appear in n8n execution log (audit trail)
- n8n protected by basic auth (username/password set via env vars)

---

## Future Phases

### Phase 2: Custom Web Frontend
- React/HTML chat UI with WebSocket connection to n8n webhook
- Syntax highlighting for YAML/JSON responses
- Command history and search
- Multi-cluster selector dropdown

### Phase 3: Slack / Teams / Discord Bot
- n8n Slack node receiving @mentions
- n8n sends structured Slack messages with code blocks
- Alert subscription: "notify me when any pod is CrashLooping"
