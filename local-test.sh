#!/usr/bin/env bash
# Bootstrap script for local testing on kind.
# Run each step in order; re-run individual steps as needed.
set -euo pipefail

CLUSTER_NAME="digit-studio"
HELMFILE_ENV="testing"
COMMON_TAG="${COMMON_TAG:-v2.9.2-4a60f20}"
HELM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/deploy-as-code/helm" && pwd)"

step() { echo ""; echo "──────────────────────────────────────────"; echo "  $*"; echo "──────────────────────────────────────────"; }

usage() {
  cat <<'EOF'
Local kind testing for egov-digit-studio-one-click-deployment

Usage:
  ./local-test.sh <step>

Steps (run in order for a clean setup):
  install-kind      Install kind binary (if not present)
  cluster-up        Create kind cluster from kind-cluster.yaml
  cluster-down      Delete the kind cluster
  render            Render manifests to build.yaml (no cluster needed)
  deploy-backbone   Deploy cluster-configs + backbone only (start here)
  deploy-core       Deploy core-services on top of backbone
  deploy-studio     Deploy studio-services on top of core
  deploy-all        Deploy all layers at once
  diff              Show pending changes for all layers
  status            Show pod status across all namespaces
  logs <release>    Tail logs for a named release

Environment:
  COMMON_TAG        Image tag (default: v2.9.2-4a60f20)

Examples:
  ./local-test.sh install-kind
  ./local-test.sh cluster-up
  ./local-test.sh deploy-backbone
  COMMON_TAG=v2.9.3-abc ./local-test.sh deploy-studio
EOF
}

require() {
  for cmd in "$@"; do
    command -v "$cmd" &>/dev/null || { echo "ERROR: '$cmd' not found. Install it first."; exit 1; }
  done
}

helmfile_run() {
  local cmd="$1"; shift
  cd "${HELM_DIR}"
  HELMFILE_ENV="${HELMFILE_ENV}" \
  COMMON_TAG="${COMMON_TAG}" \
    helmfile -f digit-helmfile.yaml "${cmd}" --include-needs=true "$@"
}

helmfile_layer() {
  local cmd="$1"; local file="$2"; shift 2
  cd "${HELM_DIR}"
  HELMFILE_ENV="${HELMFILE_ENV}" \
  COMMON_TAG="${COMMON_TAG}" \
    helmfile -f "${file}" "${cmd}" --include-needs=true "$@"
}

case "${1:-}" in

  install-kind)
    step "Installing kind"
    require curl
    OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
    curl -Lo /tmp/kind "https://kind.sigs.k8s.io/dl/v0.23.0/kind-${OS}-${ARCH}"
    chmod +x /tmp/kind
    sudo mv /tmp/kind /usr/local/bin/kind
    kind version
    ;;

  cluster-up)
    step "Creating kind cluster '${CLUSTER_NAME}'"
    require kind kubectl
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
      echo "Cluster '${CLUSTER_NAME}' already exists — skipping creation."
    else
      kind create cluster --name "${CLUSTER_NAME}" --config kind-cluster.yaml
    fi
    kubectl cluster-info --context "kind-${CLUSTER_NAME}"
    echo ""
    echo "Context set to: kind-${CLUSTER_NAME}"
    ;;

  cluster-down)
    step "Deleting kind cluster '${CLUSTER_NAME}'"
    require kind
    kind delete cluster --name "${CLUSTER_NAME}"
    ;;

  render)
    step "Rendering manifests to build.yaml (no cluster needed)"
    require helm helmfile
    helmfile_run template > "$(dirname "${HELM_DIR}")/../../build.yaml"
    echo "Written to build.yaml"
    ;;

  deploy-backbone)
    step "Deploying cluster-configs + backbone-services"
    require kubectl helm helmfile
    helmfile_layer apply charts/cluster-configs/clusterconfigs-helmfile.yaml
    helmfile_layer apply charts/backbone-services/backboneservices-helmfile.yaml
    ;;

  deploy-core)
    step "Deploying core-services"
    require kubectl helm helmfile
    helmfile_layer apply charts/core-services/coreservices-helmfile.yaml
    ;;

  deploy-studio)
    step "Deploying studio-services"
    require kubectl helm helmfile
    helmfile_layer apply charts/studio-services/studioservices-helmfile.yaml
    ;;

  deploy-all)
    step "Deploying all layers"
    require kubectl helm helmfile
    helmfile_run apply
    ;;

  diff)
    step "Showing pending changes (all layers)"
    require kubectl helm helmfile
    helmfile_run diff
    ;;

  status)
    step "Pod status across all namespaces"
    require kubectl
    for ns in egov backbone-dev core-dev studio-dev monitoring; do
      echo ""
      echo "── namespace: ${ns} ──"
      kubectl get pods -n "${ns}" 2>/dev/null || echo "(namespace not found)"
    done
    ;;

  logs)
    RELEASE="${2:-}"
    [[ -z "${RELEASE}" ]] && { echo "Usage: $0 logs <release-name>"; exit 1; }
    step "Logs for release: ${RELEASE}"
    require kubectl
    # Try each namespace
    for ns in egov backbone-dev core-dev studio-dev monitoring; do
      pods=$(kubectl get pods -n "${ns}" -l "app=${RELEASE}" -o name 2>/dev/null) || continue
      [[ -z "${pods}" ]] && continue
      echo "Found in namespace: ${ns}"
      kubectl logs -n "${ns}" -l "app=${RELEASE}" --tail=100 -f
      break
    done
    ;;

  -h|--help|help|"")
    usage
    ;;

  *)
    echo "Unknown step: ${1}"
    usage
    exit 1
    ;;
esac
