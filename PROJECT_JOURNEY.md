# The AI Kubernetes Agent Project Journey

This document captures the end-to-end journey of building a fully autonomous AI Kubernetes Agent using n8n, Langchain, and local cluster tools. It documents the architectural decisions, roadblocks, debugging processes, and final triumphant solutions.

## Phase 1: Conceptualization and Architecture

Our goal was to build a secure, locally-hosted AI agent capable of interrogating and managing a local Kubernetes cluster. The architecture required:
1. **n8n**: The core workflow and orchestration engine.
2. **Kubectl Integration**: A custom Dockerfile to install `kubectl` into the n8n container.
3. **LLM Engine**: Initially planned as a local Ollama instance, then shifted to cloud providers for better tool-calling capabilities.
4. **Tools Agent**: Utilizing n8n's Advanced AI nodes to parse LLM intent and trigger 20 custom-built sub-workflows executing specific `kubectl` commands.

## Phase 2: The Initial Build and Docker Woes

We started by creating a `docker-compose.yml` to spin up n8n and Ollama. We created a custom `Dockerfile.n8n` to pull the `n8n:latest` image and layer `kubectl` on top.

**Roadblock 1: The Llama 3 API Crash**
Our initial local LLM strategy hit a snag: Ollama's Llama 3 8B model struggled to cleanly parse the complex JSON schemas required by Langchain for tool calling. To fix this, we decided to offload the LLM inference to a more powerful, cloud-hosted model.

## Phase 3: The API Routing Matrix

We attempted to use **Groq** and **NVIDIA NIM** (which provide blazing-fast, OpenAI-compatible APIs). 

**Roadblock 2: The n8n Version Bug**
We discovered a major bug in the newer versions of n8n (v2.x). The OpenAI Chat Model node hardcoded the base URL to `api.openai.com` in the backend code, completely ignoring the UI's `OPENAI_API_BASE` environment variables. 
- *Attempted Fix*: We tried creating a custom Litellm proxy.
- *Attempted Fix*: We tried using the "Expression" feature in the n8n credential fields. 
- *The Final Fix*: We realized n8n `v1.123.55` (the pinnacle of the v1 release cycle) natively exposed the Base URL parameter perfectly! We downgraded our container from the buggy v2.x to the highly stable v1.123.55.

**Roadblock 3: Langchain URL Appending**
Even after fixing the Base URL, Langchain threw `404 Page Not Found` errors. We diagnosed that Langchain automatically appends `/v1/chat/completions` to base URLs, meaning our URL `https://integrate.api.nvidia.com/v1` became a malformed `.../v1/v1/chat/completions`. We resolved this by removing the trailing `/v1`.

## Phase 4: The Network Isolation Barrier

With the LLM perfectly connected via OpenRouter (using the massive Nemotron 3 Ultra 550B model), the agent successfully recognized the user's intent and fired the `get_pods` tool! 

**Roadblock 4: The Docker loopback (127.0.0.1) Issue**
The `kubectl` command inside the n8n container failed with `connection refused`. We realized the user's kubeconfig pointed to `127.0.0.1:50078`. Inside a Docker container, `127.0.0.1` refers to the container itself, not the Mac host where the `kind` Kubernetes cluster was running!
- *The Fix*: We wrote a script to generate an `internal-kubeconfig.yaml` that replaced `127.0.0.1` with `host.docker.internal`.
- *The TLS Hurdle*: The new host URL triggered x509 certificate errors. We bypassed this by setting `insecure-skip-tls-verify: true` and removing the CA data from the internal kubeconfig.

## Phase 5: The Final Polish

With the networking solved, the tools executed flawlessly inside the container. 
Our final hurdle was n8n's UI quirks for passing LLM arguments (like `pod_name` and `namespace`) into the tools. We mapped the `={{ $fromAI('parameter') }}` expressions directly into the tool parameters.

## The Result
The agent sprang to life. It successfully analyzed the raw output of `kubectl get pods -A`, filtered out the noise, identified 3 failing pods in CrashLoopBackOff, and formatted a beautiful executive summary with recommended next steps.

## Phase 6: Telegram Mobile Integration & Cloudflare Tunnels
To make the agent truly act like a teammate, we integrated it with Telegram so the user could debug clusters directly from their phone.
1. **The Webhook Tunnel**: We set up a `cloudflared` Quick Tunnel to expose the local n8n instance to the internet securely.
2. **The Markdown Parsing Crash**: The agent generated highly detailed markdown (bolding, code blocks). However, because Telegram restricts messages to 4096 characters, long outputs were getting sliced right in the middle of markdown entities, completely crashing Telegram's strict parser (`Can't find end of the entity`).
3. **The Nuclear Sanitizer**: We built a custom Javascript node to dynamically split messages at 3900 characters and forcefully strip problematic markdown characters (`*`, `_`, `<none>`) while preserving the structure. This guaranteed 100% stable delivery to the mobile app.

## Phase 7: The Self-Healing Cluster Demonstration
With the Telegram integration complete, we put the agent to the ultimate test using a deliberately broken cluster.
1. **Tool Refactoring**: We discovered that the `apply_manifest` tool failed because piping JSON-stringified YAML into `kubectl` via `printf` caused newline formatting errors. We refactored it to use a bulletproof bash "Here-Doc" (`<< 'EOF'`).
2. **The Autonomous Fix**: The user challenged the agent with an `oom-killed-demo` pod. The agent intelligently read the raw python command `python -c "a = []; while True: a.append(' '*10**6)"` and realized it was a deliberate memory leak. It stated that simply increasing memory limits was a band-aid, rewrote the deployment YAML to use a safe `time.sleep()` loop, and utilized the `apply_manifest` tool to autonomously push the permanent fix to the cluster.

## Phase 8: Expanding the Arsenal
To make the agent truly invincible, we expanded its capabilities from 14 to 20 tools.
1. **The JSON Patch Challenge**: We built a `patch_resource` tool. Initially, we faced issues with complex JSON schemas. We resolved this by using a robust Bash Here-Doc (`<< 'EOF'`) to safely inject the JSON payload into a temporary file before applying the strategic merge patch.
2. **The Missing Namespace Bug**: When building the `describe_resource` and `get_ingresses` tools, we discovered that if the AI omitted the namespace, the bash command `kubectl describe -n 2>&1` would crash. We fixed this by adding ternary logic (`{{ $json.namespace ? '-n ' + $json.namespace : '' }}`) to gracefully fallback to all namespaces or the default namespace.
3. **The Rollout Undo Testing**: We implemented a `rollout_undo` tool. During testing, the AI intelligently refused to rollback a deployment because it noticed there was only 1 revision! We had to manually inject an environment variable using `kubectl set env` to force Kubernetes to create a Revision 2, proving the AI's contextual awareness and the flawless execution of the rollback.

We built a 20-tool, OpenRouter-powered (n2 pro), fully autonomous Kubernetes SRE teammate that lives on your phone!
