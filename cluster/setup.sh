#!/usr/bin/env bash
#
# One-command local bring-up for the GitOps demo.
#
#   ./cluster/setup.sh
#
# It is idempotent: installs Docker, kind and kubectl if missing, creates a
# local Kubernetes (kind) cluster, installs Argo CD, wires GHCR pull access, and
# applies the Argo CD Application so the cluster continuously reconciles to Git.
#
# Requires: a Linux host (or WSL2) with sudo, and the GitHub CLI (`gh`) logged in
# so the cluster can pull the image published to GHCR by CI.
set -euo pipefail

CLUSTER=gitops-demo
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GH_USER="${GH_USER:-saisushaman}"
IMAGE="ghcr.io/${GH_USER}/gitops-cicd-pipeline"

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# 1. Prerequisites
# ---------------------------------------------------------------------------
install_docker() {
  have docker && return
  log "Installing Docker (docker.io)…"
  sudo apt-get update -y
  sudo apt-get install -y docker.io
  sudo systemctl enable --now docker || sudo service docker start || true
  sudo usermod -aG docker "$USER" || true
  log "Added $USER to the 'docker' group. If docker commands still need sudo,"
  log "open a new shell (or run: newgrp docker) and re-run this script."
}

install_kind() {
  have kind && return
  log "Installing kind…"
  curl -fsSLo /tmp/kind "https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64"
  chmod +x /tmp/kind && sudo mv /tmp/kind /usr/local/bin/kind
}

install_kubectl() {
  have kubectl && return
  log "Installing kubectl…"
  local v; v="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${v}/bin/linux/amd64/kubectl"
  chmod +x /tmp/kubectl && sudo mv /tmp/kubectl /usr/local/bin/kubectl
}

install_docker
install_kind
install_kubectl

# Fail early with a clear message if docker isn't usable by this user yet.
if ! docker info >/dev/null 2>&1; then
  echo "ERROR: cannot talk to the Docker daemon as '$USER'." >&2
  echo "       Start it (sudo systemctl start docker) and ensure group membership" >&2
  echo "       is active (newgrp docker), then re-run this script." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. kind cluster
# ---------------------------------------------------------------------------
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  log "kind cluster '$CLUSTER' already exists."
else
  log "Creating kind cluster '$CLUSTER'…"
  kind create cluster --config "$REPO_ROOT/cluster/kind-config.yaml"
fi
kubectl cluster-info --context "kind-${CLUSTER}" >/dev/null

# ---------------------------------------------------------------------------
# 3. GHCR pull access for the app namespace
#    The image published by CI is private by default; give the cluster a
#    pull secret built from the local `gh` token so it can pull it.
# ---------------------------------------------------------------------------
log "Configuring GHCR pull access in namespace 'demo'…"
kubectl create namespace demo --dry-run=client -o yaml | kubectl apply -f -
if have gh && gh auth token >/dev/null 2>&1; then
  TOKEN="$(gh auth token)"
  kubectl -n demo create secret docker-registry ghcr-creds \
    --docker-server=ghcr.io \
    --docker-username="$GH_USER" \
    --docker-password="$TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n demo patch serviceaccount default \
    -p '{"imagePullSecrets":[{"name":"ghcr-creds"}]}'
else
  log "WARNING: 'gh' not logged in. If the GHCR package is private, pods will"
  log "         fail to pull. Either 'gh auth login' and re-run, or make the"
  log "         package public at github.com/users/${GH_USER}/packages."
fi

# ---------------------------------------------------------------------------
# 4. Argo CD
# ---------------------------------------------------------------------------
log "Installing Argo CD…"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
log "Waiting for Argo CD to become ready…"
kubectl -n argocd rollout status deploy/argocd-server --timeout=180s

# ---------------------------------------------------------------------------
# 5. Register the Application (GitOps reconciliation begins)
# ---------------------------------------------------------------------------
log "Applying the Argo CD Application…"
kubectl apply -f "$REPO_ROOT/deploy/argocd/application.yaml"

log "Waiting for the app to roll out (Argo CD is syncing from Git)…"
kubectl -n demo rollout status deploy/gitops-demo --timeout=180s || {
  echo "The deployment did not become ready. Check image-pull status with:" >&2
  echo "  kubectl -n demo get pods" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# 6. Done — how to reach it
# ---------------------------------------------------------------------------
ARGO_PW="$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo '(already changed)')"

cat <<EOF

$(log "GitOps demo is up.")
App:
  kubectl -n demo port-forward svc/gitops-demo 8080:80
  curl localhost:8080/healthz    # -> {"status":"ok"}
  curl localhost:8080/api/info   # -> version + git sha of the deployed image

Argo CD UI:
  kubectl -n argocd port-forward svc/argocd-server 8443:443
  open https://localhost:8443   (user: admin, password: ${ARGO_PW})

Tear down:
  ./cluster/teardown.sh
EOF
