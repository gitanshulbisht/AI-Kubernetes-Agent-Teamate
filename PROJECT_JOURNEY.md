# The AI Kubernetes Agent Project Journey

This document captures the end-to-end journey of building a fully autonomous AI Kubernetes Agent using n8n, Langchain, and local cluster tools. It documents the architectural decisions, roadblocks, debugging processes, and final triumphant solutions.

## Phase 1: Conceptualization and Architecture

Our goal was to build a secure, locally-hosted AI agent capable of interrogating and managing a local Kubernetes cluster. The architecture required:
1. **n8n**: The core workflow and orchestration engine.
2. **Kubectl Integration**: A custom Dockerfile to install `kubectl` into the n8n container.
3. **LLM Engine**: Initially planned as a local Ollama instance, then shifted to cloud providers for better tool-calling capabilities.
4. **Tools Agent**: Utilizing n8n's Advanced AI nodes to parse LLM intent and trigger 14 custom-built sub-workflows executing specific `kubectl` commands.

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

We built a 14-tool, 550-billion parameter, fully autonomous Kubernetes SRE teammate!
