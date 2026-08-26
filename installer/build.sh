#!/bin/bash
# ============================================================================
# Lemonade Stand Assistant Installer — Build Script
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

REGISTRY="quay.io/rh-ai-quickstart"
IMAGE_NAME="lemonade-stand-assistant-installer"
VERSION="1.0.0"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${VERSION}"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}✓${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; exit 1; }

cd "$PROJECT_DIR"

info "Checking required files..."
REQUIRED_FILES=(
  "installer/entrypoint.sh"
  "installer/lib/install.sh"
  "installer/lib/uninstall.sh"
  "installer/lib/status.sh"
  "installer/lib/check_pre_reqs.sh"
  "installer/Dockerfile"
  "quickstart-manifest.yaml"
  "chart/Chart.yaml"
)

for file in "${REQUIRED_FILES[@]}"; do
  if [[ ! -e "$file" ]]; then
    error "Required file missing: $file"
  fi
done

info "Building installer image: ${FULL_IMAGE}"
podman build -t "${FULL_IMAGE}" -f installer/Dockerfile .

info "Tagging as latest: ${REGISTRY}/${IMAGE_NAME}:latest"
podman tag "${FULL_IMAGE}" "${REGISTRY}/${IMAGE_NAME}:latest"

info "Build complete!"
echo ""
echo "Image: ${FULL_IMAGE}"
echo "Also tagged: ${REGISTRY}/${IMAGE_NAME}:latest"

if [[ "${1:-}" == "push" ]]; then
  echo ""
  info "Pushing to registry..."
  podman push "${FULL_IMAGE}"
  podman push "${REGISTRY}/${IMAGE_NAME}:latest"
  info "Push complete!"
  echo ""
  echo "Image pushed to registry!"
  echo ""
  echo "Deploy to cluster:"
  echo "  ./installer/deploy.sh check_pre_reqs <namespace> - Validate prerequisites"
  echo "  ./installer/deploy.sh status <namespace>         - Check deployment status"
  echo "  ./installer/deploy.sh install <namespace>        - Deploy installation"
fi
