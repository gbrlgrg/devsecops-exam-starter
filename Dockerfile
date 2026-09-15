# ---- Stage 1: Build ----
# Use the official Node.js 18 Alpine image as the build stage.
FROM node:18-alpine AS builder

# Set the working directory inside the container
WORKDIR /app

# Copy only the package manifest files first.
# This leverages Docker's layer caching: dependencies are only reinstalled
# when package.json or package-lock.json actually change, not on every
# source-code edit to significantly speeding up rebuilds.
COPY package.json package-lock.json ./

# Install ALL dependencies (including devDependencies needed for testing).
# Using `npm ci` instead of `npm install` ensures a deterministic,
# reproducible build by installing exactly what's in the lockfile.
RUN npm ci

# Copy the rest of the application source code
COPY . .

# Run the test suite during the build so the image is only produced
# when all tests pass to serve as a quality gate baked into the container build.
RUN npm test

# ---- Stage 2: Production ----
# Start a fresh, clean image for the final production artifact.
FROM node:18-alpine AS production

# Add metadata labels following OCI conventions
LABEL org.opencontainers.image.title="Macky Merch API" \
      org.opencontainers.image.description="Containerized Express.js API for the LSCS DevSecOps Engineering Exam" \
      org.opencontainers.image.source="https://github.com/gbrlgrg/devsecops-exam-starter"

# Set the working directory
WORKDIR /app

# Copy only the package manifests for a production-only install
COPY package.json package-lock.json ./

# Install production dependencies only (no devDependencies like jest/supertest).
# --ignore-scripts prevents arbitrary post-install scripts from running,
# reducing the risk of supply-chain attacks.
RUN npm ci --only=production --ignore-scripts

# Copy the application source from the builder stage.
# We copy from builder (not from the local context) to ensure only the
# files that passed the test stage make it into production.
COPY --from=builder /app/server.js ./

# Security Best Practice: Non-Root User
# The official node:*-alpine images ship with a built-in `node` user (UID 1000).
# Switching to this user ensures the application never runs as root inside
# the container, limiting the blast radius if the process is ever compromised.
USER node

# Expose the application port (informational; does not publish the port)
EXPOSE 3000

# Define a health check so orchestrators (Docker, Compose, Kubernetes) can
# automatically detect when the application is ready to serve traffic.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# Start the application
CMD ["node", "server.js"]
