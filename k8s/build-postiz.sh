#!/bin/bash
# ============================================================
# Postiz Build & Deploy Script
# Phase 1: ACR cloud build (download deps + build)
#       OR push local image directly (--local [image])
# Phase 2: Deploy to K8s
# Usage:
#   ./build-postiz.sh [git_tag]                  # ACR cloud build
#   ./build-postiz.sh --local [image] [git_tag]  # push local image
# ============================================================
set -euo pipefail

POSTIZ_DIR="/Users/cyril/workspaces/postiz-app"
BUILD_DIR="$POSTIZ_DIR/k8s"

# ========================
# Configuration
# ========================
ACR_NAME="${BUILD_ACR:-FBRDevAcr}"
ACR_HOST="${BUILD_ACR_HOST:-fbrdevacr.azurecr.io}"
IMAGE_NAME="app/postiz"
NAMESPACE="dev-ai"
DEPLOYMENT_NAME="postiz"

# ========================
# Parse arguments
# ========================
LOCAL_MODE=false
LOCAL_IMAGE="docker-postiz:latest"
GIT_TAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local)
      LOCAL_MODE=true
      shift
      # Next arg is the local image name if it doesn't start with --
      if [[ $# -gt 0 && "$1" != --* && "$1" != "" ]] && docker image inspect "$1" &>/dev/null 2>&1; then
        LOCAL_IMAGE="$1"
        shift
      fi
      ;;
    *)
      GIT_TAG="$1"
      shift
      ;;
  esac
done

if [ -z "$GIT_TAG" ]; then
    GIT_TAG=$(cd "$POSTIZ_DIR" && git rev-parse --short=7 HEAD)
fi

ACR_IMAGE="${ACR_HOST}/${IMAGE_NAME}:${GIT_TAG}"

if $LOCAL_MODE; then
  echo "============================================"
  echo " Postiz Deploy (local image → ACR push)"
  echo "============================================"
  echo " Local image:  ${LOCAL_IMAGE}"
else
  echo "============================================"
  echo " Postiz Build & Deploy (ACR Cloud Build)"
  echo "============================================"
fi
echo " ACR:          ${ACR_NAME}"
echo " ACR Host:     ${ACR_HOST}"
echo " Image:        ${IMAGE_NAME}:${GIT_TAG}"
echo " Git Tag:      ${GIT_TAG}"
echo " Namespace:    ${NAMESPACE}"
echo "============================================"

if $LOCAL_MODE; then
  # ========================
  # Push local image to ACR
  # ========================
  echo ""
  echo "[1/2] Pushing local image to ACR..."

  az acr login --name "$ACR_NAME"

  docker tag "${LOCAL_IMAGE}" "${ACR_IMAGE}"
  docker tag "${LOCAL_IMAGE}" "${ACR_HOST}/${IMAGE_NAME}:latest"
  docker push "${ACR_IMAGE}"
  docker push "${ACR_HOST}/${IMAGE_NAME}:latest"

  echo "  Push complete."

else
  # ========================
  # Prepare build context
  # ========================
  echo ""
  echo "[1/3] Preparing build context..."

  cd "$BUILD_DIR"

  # Clean previous artifacts (keep Dockerfile, ecosystem.config.cjs, build script)
  rm -rf apps libraries package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.base.json 2>/dev/null || true

  # Copy source code for ACR build
  cp "$POSTIZ_DIR/.npmrc" .
  cp "$POSTIZ_DIR/package.json" .
  cp "$POSTIZ_DIR/pnpm-lock.yaml" .
  cp "$POSTIZ_DIR/pnpm-workspace.yaml" .
  cp "$POSTIZ_DIR/tsconfig.base.json" .

  # Copy apps source
  mkdir -p apps/backend apps/orchestrator apps/frontend

  cp -r "$POSTIZ_DIR/apps/backend/src" "$BUILD_DIR/apps/backend/" 2>/dev/null || true
  cp "$POSTIZ_DIR/apps/backend/package.json" "$BUILD_DIR/apps/backend/" 2>/dev/null || true
  cp "$POSTIZ_DIR/apps/backend/tsconfig.json" "$BUILD_DIR/apps/backend/" 2>/dev/null || true
  cp "$POSTIZ_DIR/apps/backend/tsconfig.build.json" "$BUILD_DIR/apps/backend/" 2>/dev/null || true
  cp "$POSTIZ_DIR/apps/backend/project.json" "$BUILD_DIR/apps/backend/" 2>/dev/null || true

  cp -r "$POSTIZ_DIR/apps/orchestrator/src" "$BUILD_DIR/apps/orchestrator/" 2>/dev/null || true
  cp "$POSTIZ_DIR/apps/orchestrator/package.json" "$BUILD_DIR/apps/orchestrator/" 2>/dev/null || true
  cp "$POSTIZ_DIR/apps/orchestrator/tsconfig.json" "$BUILD_DIR/apps/orchestrator/" 2>/dev/null || true
  cp "$POSTIZ_DIR/apps/orchestrator/tsconfig.build.json" "$BUILD_DIR/apps/orchestrator/" 2>/dev/null || true
  cp "$POSTIZ_DIR/apps/orchestrator/project.json" "$BUILD_DIR/apps/orchestrator/" 2>/dev/null || true

  cp -r "$POSTIZ_DIR/apps/frontend/src" "$BUILD_DIR/apps/frontend/" 2>/dev/null || true
  cp -r "$POSTIZ_DIR/apps/frontend/public" "$BUILD_DIR/apps/frontend/" 2>/dev/null || true
  cp -r "$POSTIZ_DIR/apps/frontend/package.json" "$BUILD_DIR/apps/frontend/" 2>/dev/null || true
  cp -r "$POSTIZ_DIR/apps/frontend/next.config.js" "$BUILD_DIR/apps/frontend/" 2>/dev/null || true
  cp -r "$POSTIZ_DIR/apps/frontend/tsconfig.json" "$BUILD_DIR/apps/frontend/" 2>/dev/null || true
  cp -r "$POSTIZ_DIR/apps/frontend/postcss.config.mjs" "$BUILD_DIR/apps/frontend/" 2>/dev/null || true
  cp -r "$POSTIZ_DIR/apps/frontend/tailwind.config.cjs" "$BUILD_DIR/apps/frontend/" 2>/dev/null || true

  mkdir -p libraries
  cp -r "$POSTIZ_DIR/libraries" .

  # Copy Docker support files
  cp "$POSTIZ_DIR/var/docker/nginx.conf" "$BUILD_DIR/var/docker/"
  cp "$POSTIZ_DIR/var/docker/ecosystem.config.cjs" "$BUILD_DIR/var/docker/"

  echo "  Build context prepared."

  # ========================
  # ACR Cloud Build
  # ========================
  echo ""
  echo "[2/3] Building Docker image in ACR (cloud build)..."

  az acr login --name "$ACR_NAME"

  az acr build \
      --registry "$ACR_NAME" \
      --image "${IMAGE_NAME}:${GIT_TAG}" \
      --image "${IMAGE_NAME}:latest" \
      --file "$BUILD_DIR/Dockerfile" \
      --build-arg NODE_ENV=production \
      --timeout 3600 \
      "$BUILD_DIR"

  echo "  ACR build complete."
fi

# ========================
# Update K8s deployment
# ========================
echo ""
echo "[$(if $LOCAL_MODE; then echo "2/2"; else echo "3/3"; fi)] Updating Kubernetes deployment..."

kubectl set image "deployment/${DEPLOYMENT_NAME}" \
    "${DEPLOYMENT_NAME}=${ACR_IMAGE}" \
    -n "${NAMESPACE}"

echo ""
echo "Waiting for rollout..."
kubectl rollout status "deployment/${DEPLOYMENT_NAME}" \
    -n "${NAMESPACE}" \
    --timeout=300s

echo ""
echo "============================================"
echo " Postiz deployed successfully!"
echo " Image: ${ACR_IMAGE}"
echo "============================================"
