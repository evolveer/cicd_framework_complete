# Multi-stage Dockerfile for Django Applications
# Optimized for production with security best practices

# Build stage
FROM python:3.11-slim AS builder

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Install system dependencies for building
RUN apt-get update && apt-get install -y \
    build-essential \
    libpq-dev \
    libffi-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Poetry
RUN pip install poetry==1.6.1

# Set working directory
WORKDIR /app

# Copy dependency files
COPY pyproject.toml poetry.lock ./

# Configure Poetry and install dependencies
RUN poetry config virtualenvs.create false && \
    poetry install --only=main --no-dev

# Production stage
FROM python:3.11-slim AS production

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    DJANGO_SETTINGS_MODULE=config.settings.production

# Create non-root user
RUN groupadd -r django && useradd -r -g django django

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libpq5 \
    libffi8 \
    libssl3 \
    curl \
    dumb-init \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Copy Python packages from builder
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Set working directory
WORKDIR /app

# Copy application code
COPY --chown=django:django . .

# Create necessary directories
RUN mkdir -p /app/staticfiles /app/mediafiles /app/logs && \
    chown -R django:django /app/staticfiles /app/mediafiles /app/logs

# Collect static files
RUN python manage.py collectstatic --noinput --settings=config.settings.production

# Switch to non-root user
USER django

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8000/health/ || exit 1

# Create entrypoint script
COPY --chown=django:django docker/entrypoint.sh /entrypoint.sh
USER root
RUN chmod +x /entrypoint.sh
USER django

# Use dumb-init to handle signals
ENTRYPOINT ["dumb-init", "--"]

# Default command
CMD ["/entrypoint.sh"]

# Labels
LABEL maintainer="DevOps Team <devops@company.com>"
LABEL version="1.0"
LABEL description="Django Application"
LABEL org.opencontainers.image.source="https://github.com/company/django-app"
LABEL org.opencontainers.image.documentation="https://docs.company.com/django-app"
LABEL org.opencontainers.image.licenses="MIT"

