# Multi-stage Dockerfile for Java Spring Boot Applications
# Optimized for security, performance, and minimal image size

# Build stage
FROM maven:3.9.4-eclipse-temurin-17 AS builder

# Set working directory
WORKDIR /app

# Copy dependency files first for better caching
COPY pom.xml .
COPY .mvn .mvn
COPY mvnw .

# Download dependencies (cached layer)
RUN mvn dependency:go-offline -B

# Copy source code
COPY src ./src

# Build application
RUN mvn clean package -DskipTests -B

# Extract JAR layers for better caching
RUN java -Djarmode=layertools -jar target/*.jar extract

# Runtime stage
FROM eclipse-temurin:17-jre-alpine AS runtime

# Create non-root user for security
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

# Install security updates and required packages
RUN apk update && \
    apk upgrade && \
    apk add --no-cache \
        curl \
        dumb-init \
        tzdata && \
    rm -rf /var/cache/apk/*

# Set timezone
ENV TZ=UTC

# Create application directory
WORKDIR /app

# Copy application layers from builder stage
COPY --from=builder --chown=appuser:appgroup app/dependencies/ ./
COPY --from=builder --chown=appuser:appgroup app/spring-boot-loader/ ./
COPY --from=builder --chown=appuser:appgroup app/snapshot-dependencies/ ./
COPY --from=builder --chown=appuser:appgroup app/application/ ./

# Create logs directory
RUN mkdir -p /app/logs && chown appuser:appgroup /app/logs

# Switch to non-root user
USER appuser

# Expose application port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/actuator/health || exit 1

# JVM optimization for containers
ENV JAVA_OPTS="-XX:+UseContainerSupport \
               -XX:MaxRAMPercentage=75.0 \
               -XX:+UseG1GC \
               -XX:+UseStringDeduplication \
               -XX:+OptimizeStringConcat \
               -Djava.security.egd=file:/dev/./urandom \
               -Dspring.backgroundpreinitializer.ignore=true"

# Application configuration
ENV SPRING_PROFILES_ACTIVE=production
ENV LOGGING_LEVEL_ROOT=INFO
ENV MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE=health,info,metrics,prometheus

# Use dumb-init to handle signals properly
ENTRYPOINT ["dumb-init", "--"]

# Start application
CMD ["sh", "-c", "java $JAVA_OPTS org.springframework.boot.loader.JarLauncher"]

# Labels for metadata
LABEL maintainer="DevOps Team <devops@company.com>"
LABEL version="1.0"
LABEL description="Spring Boot Application"
LABEL org.opencontainers.image.source="https://github.com/company/spring-boot-app"
LABEL org.opencontainers.image.documentation="https://docs.company.com/spring-boot-app"
LABEL org.opencontainers.image.licenses="MIT"

