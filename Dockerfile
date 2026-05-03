# syntax=docker/dockerfile:1.4

# ========================================
# Stage 1: Frontend Application Build
# ========================================
FROM node:23-slim AS frontend-compiler

# Production build configuration
ENV NODE_ENV=production
ENV VITE_BUILD_MEMORY_LIMIT=4096
ENV NODE_OPTIONS="--max-old-space-size=4096"

WORKDIR /app/ui

# Install build essentials
RUN apt-get update && apt-get install -y \
    ca-certificates \
    tzdata \
    gcc \
    g++ \
    make \
    git

# GraphQL schema for code generation
COPY ./backend/pkg/graph/schema.graphqls ../backend/pkg/graph/

# Application source code
COPY frontend/ .

# Install dependencies with package manager detection for SBOM
RUN --mount=type=cache,target=/root/.npm \
    npm ci --include=dev

# Generate license report for frontend dependencies
RUN npm install -g license-checker && \
    mkdir -p /licenses/frontend && \
    license-checker --production --json > /licenses/frontend/licenses.json && \
    license-checker --production --csv > /licenses/frontend/licenses.csv

# Build frontend with optimizations and parallel processing
RUN npm run build -- \
    --mode production \
    --minify esbuild \
    --outDir dist \
    --emptyOutDir \
    --sourcemap false \
    --target es2020

# ========================================
# Stage 2: Backend Services Compilation
# ========================================
FROM golang:1.24-bookworm AS api-builder

# Version injection arguments
ARG PACKAGE_VER=develop
ARG PACKAGE_REV=

# Static binary compilation settings
ENV CGO_ENABLED=0
ENV GO111MODULE=on

# Install compilation toolchain and dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    tzdata \
    gcc \
    g++ \
    make \
    git \
    musl-dev

WORKDIR /app/backend

COPY backend/ .

# Fetch Go module dependencies (cached for faster rebuilds)
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download && go mod verify

# Install go-licenses tool for license extraction
RUN --mount=type=cache,target=/go/pkg/mod \
    go install github.com/google/go-licenses@latest

# Generate license reports for backend dependencies
RUN mkdir -p /licenses/backend && \
    go list -m all > /licenses/backend/dependencies.txt && \
    GOROOT=$(go env GOROOT) GOTOOLCHAIN=auto go-licenses csv ./cmd/pennull > /licenses/backend/licenses.csv 2>/dev/null || true

# Compile main application binary with embedded version metadata
RUN go build -trimpath \
    -ldflags "\
        -X pennull/pkg/version.PackageName=pennull \
        -X pennull/pkg/version.PackageVer=${PACKAGE_VER} \
        -X pennull/pkg/version.PackageRev=${PACKAGE_REV}" \
    -o /pennull ./cmd/pennull

# Build ctester utility
RUN go build -trimpath \
    -ldflags "\
        -X pennull/pkg/version.PackageName=ctester \
        -X pennull/pkg/version.PackageVer=${PACKAGE_VER} \
        -X pennull/pkg/version.PackageRev=${PACKAGE_REV}" \
    -o /ctester ./cmd/ctester

# Build ftester utility
RUN go build -trimpath \
    -ldflags "\
        -X pennull/pkg/version.PackageName=ftester \
        -X pennull/pkg/version.PackageVer=${PACKAGE_VER} \
        -X pennull/pkg/version.PackageRev=${PACKAGE_REV}" \
    -o /ftester ./cmd/ftester

# Build etester utility
RUN go build -trimpath \
    -ldflags "\
        -X pennull/pkg/version.PackageName=etester \
        -X pennull/pkg/version.PackageVer=${PACKAGE_VER} \
        -X pennull/pkg/version.PackageRev=${PACKAGE_REV}" \
    -o /etester ./cmd/etester

# ========================================
# Stage 3: Production Runtime Environment
# ========================================
FROM alpine:3.23.3

# Establish non-privileged execution context with docker socket access
RUN addgroup -g 998 docker && \
    addgroup -S pennull && \
    adduser -S pennull -G pennull && \
    addgroup pennull docker

# Install required packages
RUN apk --no-cache add ca-certificates openssl openssh-keygen shadow

ADD scripts/entrypoint.sh /opt/pennull/bin/

RUN sed -i 's/\r//' /opt/pennull/bin/entrypoint.sh && \
    chmod +x /opt/pennull/bin/entrypoint.sh

RUN mkdir -p \
    /root/.ollama \
    /opt/pennull/bin \
    /opt/pennull/ssl \
    /opt/pennull/fe \
    /opt/pennull/logs \
    /opt/pennull/data \
    /opt/pennull/conf && \
    chmod 777 /root/.ollama

COPY --from=api-builder /pennull /opt/pennull/bin/pennull
COPY --from=api-builder /ctester /opt/pennull/bin/ctester
COPY --from=api-builder /ftester /opt/pennull/bin/ftester
COPY --from=api-builder /etester /opt/pennull/bin/etester
COPY --from=frontend-compiler /app/ui/dist /opt/pennull/fe
COPY --from=api-builder /licenses/backend /opt/pennull/licenses/backend
COPY --from=frontend-compiler /licenses/frontend /opt/pennull/licenses/frontend

# Copy provider configuration files
COPY examples/configs/custom-openai.provider.yml /opt/pennull/conf/
COPY examples/configs/deepinfra.provider.yml /opt/pennull/conf/
COPY examples/configs/deepseek.provider.yml /opt/pennull/conf/
COPY examples/configs/moonshot.provider.yml /opt/pennull/conf/
COPY examples/configs/ollama-cloud.provider.yml /opt/pennull/conf/
COPY examples/configs/ollama-llama318b-instruct.provider.yml /opt/pennull/conf/
COPY examples/configs/ollama-llama318b.provider.yml /opt/pennull/conf/
COPY examples/configs/ollama-qwen332b-fp16-tc.provider.yml /opt/pennull/conf/
COPY examples/configs/ollama-qwq32b-fp16-tc.provider.yml /opt/pennull/conf/
COPY examples/configs/openrouter.provider.yml /opt/pennull/conf/
COPY examples/configs/novita.provider.yml /opt/pennull/conf/
COPY examples/configs/vllm-qwen3.5-27b-fp8.provider.yml /opt/pennull/conf/
COPY examples/configs/vllm-qwen3.5-27b-fp8-no-think.provider.yml /opt/pennull/conf/
COPY examples/configs/vllm-qwen332b-fp16.provider.yml /opt/pennull/conf/

COPY LICENSE /opt/pennull/LICENSE
COPY NOTICE /opt/pennull/NOTICE
COPY EULA.md /opt/pennull/EULA
COPY EULA.md /opt/pennull/fe/EULA.md

RUN chown -R pennull:pennull /opt/pennull

WORKDIR /opt/pennull

USER pennull

ENTRYPOINT ["/opt/pennull/bin/entrypoint.sh", "/opt/pennull/bin/pennull"]

# Image Metadata
LABEL org.opencontainers.image.source="https://github.com/nullailab/pennull"
LABEL org.opencontainers.image.description="Fully autonomous AI Agents system capable of performing complex penetration testing tasks"
LABEL org.opencontainers.image.authors="penNULL Development Team"
LABEL org.opencontainers.image.licenses="MIT License"
