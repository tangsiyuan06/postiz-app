# ============================================================
# Postiz Build Image - Builds in ACR cloud
# 1. Copy source code
# 2. Install dependencies in ACR
# 3. Build artifacts
# 4. Package runtime image
# ============================================================

# ===== Stage 1: Build =====
FROM node:22.20-bookworm AS builder

WORKDIR /app

# Copy source files
COPY .npmrc package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.base.json ./
COPY apps ./apps
COPY libraries ./libraries

# Install dependencies
RUN npm install -g pnpm && \
    pnpm config set store-dir /pnpm-store && \
    pnpm install

# Build
ARG NODE_ENV=production
RUN NODE_OPTIONS="--max-old-space-size=4096" pnpm run build

# ===== Stage 2: Runtime =====
FROM node:22.20-bookworm-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx curl \
 && rm -rf /var/lib/apt/lists/*

RUN npm --no-update-notifier --no-fund --global install pm2

RUN addgroup --system www \
 && adduser --system --ingroup www --home /www --shell /usr/sbin/nologin www \
 && mkdir -p /www /uploads /app /var/log/nginx \
 && chown -R www:www /www /uploads /var/lib/nginx /var/log/nginx /app

WORKDIR /app

# Copy node_modules from builder
COPY --from=builder /app/node_modules ./node_modules

# Copy build artifacts
COPY --from=builder /app/apps/backend/dist ./apps/backend/dist
COPY --from=builder /app/apps/orchestrator/dist ./apps/orchestrator/dist
COPY --from=builder /app/apps/frontend/.next ./apps/frontend/.next
COPY --from=builder /app/apps/frontend/public ./apps/frontend/public
COPY --from=builder /app/package.json ./

# Copy nginx config
COPY var/docker/nginx.conf /etc/nginx/nginx.conf

# Copy PM2 config
COPY --chown=www:www var/docker/ecosystem.config.cjs ./ecosystem.config.cjs

# USER www  # Run as root for PVC write permissions

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
  CMD curl -f http://localhost:5000/api/health || exit 1

CMD ["sh", "-c", "nginx && pm2-runtime ecosystem.config.cjs"]
