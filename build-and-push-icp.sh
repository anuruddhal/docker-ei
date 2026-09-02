#!/usr/bin/env bash
set -euo pipefail

# Build and push WSO2 Integration Control Plane 2.0.0 multi-arch Docker images
# to hub.docker.com/r/wso2/wso2-integration-control-plane
#
# Prerequisites:
#   - Docker Desktop running with buildx support
#   - docker login (with push access to the wso2 Docker Hub org)
#
# Usage:
#   ./build-and-push-icp.sh

DIST_URL="https://github.com/wso2/integration-control-plane/releases/download/v2.0.0/wso2-integration-control-plane-2.0.0.zip"
REPO="wso2/wso2-integration-control-plane"
VERSION="2.0.0"
PLATFORMS="linux/amd64,linux/arm64"
BUILDER="icp-multiarch-builder"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKERFILES_DIR="${SCRIPT_DIR}/dockerfiles"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "[$(date '+%H:%M:%S')] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
docker info > /dev/null 2>&1 || die "Docker daemon is not running. Start Docker Desktop and retry."
docker buildx version > /dev/null 2>&1 || die "docker buildx is not available."

# Docker Hub login isn't reliably checkable across credential-store backends
# (osxkeychain, desktop, pass, wincred, ...). If not logged in, run `docker
# login` first — otherwise `docker buildx build --push` below will fail with
# a clear authentication error.

# ---------------------------------------------------------------------------
# Create (or reuse) a multi-arch builder
# ---------------------------------------------------------------------------
if ! docker buildx inspect "${BUILDER}" > /dev/null 2>&1; then
    log "Creating multi-arch builder '${BUILDER}' ..."
    docker buildx create --name "${BUILDER}" --driver docker-container --bootstrap
else
    existing_driver="$(docker buildx inspect "${BUILDER}" 2>/dev/null | awk -F': *' '/^Driver:/{print $2}')"
    if [[ "${existing_driver}" != "docker-container" ]]; then
        log "Existing builder '${BUILDER}' uses driver '${existing_driver}' (needs docker-container for multi-platform + push); recreating ..."
        docker buildx rm "${BUILDER}" > /dev/null 2>&1
        docker buildx create --name "${BUILDER}" --driver docker-container --bootstrap
    else
        log "Reusing existing builder '${BUILDER}'"
        docker buildx inspect "${BUILDER}" --bootstrap > /dev/null
    fi
fi

build_and_push() {
    local flavor="$1"   # ubuntu | alpine | rocky
    local tags="$2"     # space-separated list of full image:tag values
    local dockerfile_dir="${DOCKERFILES_DIR}/${flavor}/integration-control-plane"

    [[ -f "${dockerfile_dir}/Dockerfile" ]] || die "Dockerfile not found at ${dockerfile_dir}"

    local tag_args=()
    for tag in ${tags}; do
        tag_args+=("-t" "${tag}")
    done

    log "Building ${flavor} image → tags: ${tags}"
    docker buildx build \
        --builder "${BUILDER}" \
        --platform "${PLATFORMS}" \
        --build-arg "WSO2_SERVER_DIST_URL=${DIST_URL}" \
        "${tag_args[@]}" \
        --push \
        "${dockerfile_dir}"
    log "Pushed ${flavor} image successfully."
}

# ---------------------------------------------------------------------------
# Build each OS variant
# ---------------------------------------------------------------------------
log "=== Starting ICP ${VERSION} multi-arch build and push ==="

# Ubuntu: primary tag + latest
build_and_push "ubuntu" "${REPO}:${VERSION} ${REPO}:latest"

# Alpine
build_and_push "alpine" "${REPO}:${VERSION}-alpine"

# Rocky Linux
build_and_push "rocky" "${REPO}:${VERSION}-rocky"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log "=== All images pushed successfully ==="
echo ""
echo "Published tags:"
echo "  ${REPO}:${VERSION}        (Ubuntu, linux/amd64 + linux/arm64)"
echo "  ${REPO}:latest            (Ubuntu, linux/amd64 + linux/arm64)"
echo "  ${REPO}:${VERSION}-alpine (Alpine, linux/amd64 + linux/arm64)"
echo "  ${REPO}:${VERSION}-rocky  (Rocky Linux, linux/amd64 + linux/arm64)"
