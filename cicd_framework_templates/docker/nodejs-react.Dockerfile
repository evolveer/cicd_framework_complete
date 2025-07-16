# Multi-stage Dockerfile for React Applications with Node.js Backend
# Optimized for production deployment with NGINX

# Build stage for React frontend
FROM node:18-alpine AS frontend-builder

# Set working directory
WORKDIR /app/frontend

# Copy package files
COPY frontend/package*.json ./

# Install dependencies
RUN npm ci --only=production && npm cache clean --force

# Copy frontend source
COPY frontend/ ./

# Build React application
RUN npm run build

# Build stage for Node.js backend
FROM node:18-alpine AS backend-builder

# Set working directory
WORKDIR /app/backend

# Copy package files
COPY backend/package*.json ./

# Install dependencies including dev dependencies for build
RUN npm ci

# Copy backend source
COPY backend/ ./

# Build backend (if using TypeScript)
RUN npm run build

# Production dependencies only
RUN npm ci --only=production && npm cache clean --force

# Production stage
FROM nginx:1.25-alpine AS production

# Install Node.js for backend
RUN apk add --no-cache nodejs npm

# Create non-root user
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

# Install security updates
RUN apk update && \
    apk upgrade && \
    apk add --no-cache \
        curl \
        dumb-init \
        supervisor && \
    rm -rf /var/cache/apk/*

# Copy custom NGINX configuration
COPY docker/nginx.conf /etc/nginx/nginx.conf
COPY docker/default.conf /etc/nginx/conf.d/default.conf

# Copy built React application
COPY --from=frontend-builder /app/frontend/build /usr/share/nginx/html

# Copy Node.js backend
COPY --from=backend-builder --chown=appuser:appgroup /app/backend/dist /app/backend
COPY --from=backend-builder --chown=appuser:appgroup /app/backend/node_modules /app/node_modules
COPY --from=backend-builder --chown=appuser:appgroup /app/backend/package.json /app/

# Create necessary directories
RUN mkdir -p /app/logs /var/log/supervisor && \
    chown -R appuser:appgroup /app/logs && \
    chown -R appuser:appgroup /var/log/supervisor

# Copy supervisor configuration
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Create startup script
COPY docker/start.sh /start.sh
RUN chmod +x /start.sh

# Expose ports
EXPOSE 80 3001

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:80/health || exit 1

# Environment variables
ENV NODE_ENV=production
ENV PORT=3001
ENV NGINX_WORKER_PROCESSES=auto
ENV NGINX_WORKER_CONNECTIONS=1024

# Use dumb-init to handle signals
ENTRYPOINT ["dumb-init", "--"]

# Start services with supervisor
CMD ["/start.sh"]

# Labels
LABEL maintainer="DevOps Team <devops@company.com>"
LABEL version="1.0"
LABEL description="React Application with Node.js Backend"
LABEL org.opencontainers.image.source="https://github.com/company/react-app"

