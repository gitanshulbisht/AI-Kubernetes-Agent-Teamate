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
[ -f "$KUBE_PATH" ] || warn "kubeconfig not found at $KUBE_PATH. Be sure to set KUBECONFIG_HOST_PATH in .env before starting the stack."
if [ -f "$KUBE_PATH" ]; then
  info "kubeconfig found: $KUBE_PATH ✓"
fi

# Build
info "Building custom n8n image with kubectl..."
docker compose build --no-cache n8n
info "n8n image built ✓"

# Start Ollama
info "Starting Ollama..."
docker compose up -d ollama
info "Waiting for Ollama to be healthy..."
until docker compose exec ollama ollama list >/dev/null 2>&1; do
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
until docker compose exec n8n wget -qO- http://localhost:5678/healthz >/dev/null 2>&1; do
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
