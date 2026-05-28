#!/usr/bin/env bash
set -euo pipefail

# Backward-compatible wrapper — renders all manifests to build.yaml
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HELMFILE_ENV="${HELMFILE_ENV:-testing}" \
COMMON_TAG="${COMMON_TAG:-v2.9.2-4a60f20}" \
HELMFILE_COMMAND=template \
"${ROOT_DIR}/deploy.sh" > "${ROOT_DIR}/build.yaml"

echo "Rendered manifests to ${ROOT_DIR}/build.yaml"
