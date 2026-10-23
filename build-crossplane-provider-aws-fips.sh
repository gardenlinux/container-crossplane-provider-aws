#!/usr/bin/env bash
set -euo pipefail

# --- configuration -----------------------------------------------------------

REPO_URL="${REPO_URL:-https://github.com/crossplane-contrib/provider-aws}"
BASE_IMAGE="${BASE_IMAGE:-ghcr.io/gardenlinux/gardenlinux/fips:1877.22}"
WORKDIR="${WORKDIR:-./.build/crossplane-provider-aws-fips-build}"
IMAGE_NAME="${IMAGE_NAME:-gl-fips-crossplane-provider-aws}"
ARCH="${ARCH:-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')}"
VERSION="${VERSION:-0.59.0}"
UPSTREAM_GIT_SHA="${UPSTREAM_GIT_SHA:-5829880faaca3d4bcedd6554fd6a90ab4eb0928c}"
GO_IMAGE="${GO_IMAGE:-golang:1.23-bookworm}"

# --- prerequisites -----------------------------------------------------------

check_tool() { command -v "$1" &>/dev/null || { echo "error: $1 not found" >&2; exit 1; }; }
check_tool git
check_tool docker
docker buildx version &>/dev/null || { echo "error: docker buildx not available" >&2; exit 1; }

# --- clone / reuse source ----------------------------------------------------

CLONE_DIR=".build/fips-port-crossplane-provider-aws"
if [ ! -d "${CLONE_DIR}" ]; then
    git clone "${REPO_URL}" "${CLONE_DIR}"
fi
git -C "${CLONE_DIR}" checkout "v${VERSION}"

# --- buildx driver -----------------------------------------------------------

if ! docker buildx inspect fips-builder &>/dev/null; then
    docker buildx create --name fips-builder --driver docker-container
fi
docker buildx use fips-builder

# --- generate Dockerfile (Pattern D) ----------------------------------------

mkdir -p "${WORKDIR}"

cat > "${WORKDIR}/Dockerfile.fips" <<DOCKERFILE
ARG GO_IMAGE
FROM --platform=\$BUILDPLATFORM \${GO_IMAGE} AS builder
ARG ARCH
ARG VERSION
WORKDIR /src
COPY . .
RUN CGO_ENABLED=0 GOARCH=\${ARCH} go build \\
    -ldflags "-s -w -X github.com/crossplane-contrib/provider-aws/pkg/version.Version=\${VERSION}" \\
    -o /crossplane-aws-provider ./cmd/provider

FROM ${BASE_IMAGE}
ARG UPSTREAM_GIT_SHA
LABEL org.opencontainers.image.description="A FIPS-enabled crossplane-provider-aws image"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.revision="\${UPSTREAM_GIT_SHA}"
RUN groupadd -g 65532 nonroot \\
    && useradd -u 65532 -g 65532 -s /sbin/nologin -d /home/nonroot nonroot
COPY --from=builder /crossplane-aws-provider /usr/local/bin/crossplane-aws-provider
ENV GODEBUG=fips140=only
USER 65532
ENTRYPOINT ["/usr/local/bin/crossplane-aws-provider"]
DOCKERFILE

# --- build -------------------------------------------------------------------

docker buildx build \
    --platform "linux/${ARCH}" \
    --build-arg ARCH="${ARCH}" \
    --build-arg VERSION="${VERSION}" \
    --build-arg UPSTREAM_GIT_SHA="${UPSTREAM_GIT_SHA}" \
    --build-arg GO_IMAGE="${GO_IMAGE}" \
    --load \
    --tag "${IMAGE_NAME}:${VERSION}-${ARCH}" \
    -f "${WORKDIR}/Dockerfile.fips" \
    "${CLONE_DIR}"

# --- report ------------------------------------------------------------------

echo "Built: ${IMAGE_NAME}:${VERSION}-${ARCH}"
