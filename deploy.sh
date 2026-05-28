#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_DIR="${ROOT_DIR}/deploy-as-code/helm"
HELMFILE="${HELM_DIR}/digit-helmfile.yaml"

: "${HELMFILE_ENV:=testing}"
: "${COMMON_TAG:=v2.9.2-4a60f20}"
: "${HELMFILE_COMMAND:=apply}"

# Optional per-service tag overrides (fall back to COMMON_TAG when unset)
: "${HEALTH_INDIVIDUAL_TAG:=${COMMON_TAG}}"
: "${HEALTH_SERVICE_REQUEST_TAG:=${COMMON_TAG}}"

usage() {
  cat <<'EOF'
Digit Studio one-click deployment (Helmfile)

Usage:
  ./deploy.sh [command]

Commands:
  apply     Deploy all enabled helmfile layers (default)
  sync      Sync releases to cluster state
  diff      Show pending changes
  template  Render manifests to stdout
  list      List all releases
  destroy   Remove all releases (use with caution)

Environment variables:
  HELMFILE_ENV              Environment values file prefix (default: unified-demo-studio)
  COMMON_TAG                Image tag for core/studio services (default: v2.9.2-4a60f20)
  HEALTH_INDIVIDUAL_TAG     Override image tag for health-individual (defaults to COMMON_TAG)
  HEALTH_SERVICE_REQUEST_TAG Override image tag for health-service-request (defaults to COMMON_TAG)
  HELMFILE_COMMAND          Override command when invoked without args

Helmfile layers (all in one deploy):
  cluster-configs   → backbone-services → core-services (+ egov-hrms)
                    → studio-services (+ health-individual, health-service-request)
                    → monitoring

Examples:
  HELMFILE_ENV=unified-demo-studio ./deploy.sh apply
  HELMFILE_ENV=unified-demo-staging ./deploy.sh diff
  ./deploy.sh template > build.yaml

Prerequisites:
  - kubectl context pointing at target cluster
  - helm, helmfile installed
  - SOPS-decrypted secrets in deploy-as-code/helm/environments/
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

COMMAND="${1:-${HELMFILE_COMMAND}}"

case "${COMMAND}" in
  apply|sync|diff|template|list|destroy) ;;
  *)
    echo "Unknown command: ${COMMAND}" >&2
    usage >&2
    exit 1
    ;;
esac

# Backbone secret vars used by backboneservices-helmfile.yaml inline set: blocks.
# For cloud/SOPS: export these from the decrypted secrets file before running.
: "${DOMAIN:=localhost}"
: "${DB_PASSWORD:=postgres}"
: "${ES_PASSWORD:=elastic_local}"
: "${KAFKA_CLUSTER_ID:=bXlsb2NhbGNsdXN0ZXJpZDAx}"

export HELMFILE_ENV COMMON_TAG HEALTH_INDIVIDUAL_TAG HEALTH_SERVICE_REQUEST_TAG \
       DOMAIN DB_PASSWORD ES_PASSWORD KAFKA_CLUSTER_ID

cd "${HELM_DIR}"

helmfile -f "${HELMFILE}" "${COMMAND}" --include-needs=true \
  --set digit-studio.image.tag="${COMMON_TAG}" \
  --set public-service.image.tag="${COMMON_TAG}" \
  --set public-service-init.image.tag="${COMMON_TAG}" \
  --set studio-individual.image.tag="${COMMON_TAG}" \
  --set studio-pdf.image.tag="${COMMON_TAG}" \
  --set studio-service-request.image.tag="${COMMON_TAG}" \
  --set health-individual.image.tag="${HEALTH_INDIVIDUAL_TAG}" \
  --set health-service-request.image.tag="${HEALTH_SERVICE_REQUEST_TAG}" \
  --set egov-hrms.image.tag="${COMMON_TAG}"
