#!/usr/bin/env bash
# image_audit.sh --- Audit a Docker image for security and best practices.
#
# Usage:
#   ./image_audit.sh <image_name:tag>
#   ./image_audit.sh myapp:latest
#
# Checks:
#   - Image size
#   - Layer count
#   - Running as root
#   - Vulnerability scan (if trivy is installed)
#   - Exposed ports
#
# Exit codes:
#   0 — all checks pass
#   1 — issues found

set -euo pipefail

IMAGE="${1:?Usage: $0 <image:tag>}"

echo "=== Docker Image Audit: ${IMAGE} ==="
echo

# Image size
SIZE=$(docker image inspect "${IMAGE}" --format '{{.Size}}' 2>/dev/null)
if [ -z "${SIZE}" ]; then
    echo "ERROR: Image '${IMAGE}' not found locally."
    exit 1
fi
SIZE_MB=$((SIZE / 1024 / 1024))
echo "Image size: ${SIZE_MB} MB"
if [ "${SIZE_MB}" -gt 500 ]; then
    echo "  WARNING: Image exceeds 500 MB — consider multi-stage build or slimmer base"
fi

# Layer count
LAYERS=$(docker image inspect "${IMAGE}" --format '{{len .RootFS.Layers}}')
echo "Layer count: ${LAYERS}"
if [ "${LAYERS}" -gt 20 ]; then
    echo "  WARNING: High layer count — consider combining RUN instructions"
fi

# Check if running as root
USER=$(docker image inspect "${IMAGE}" --format '{{.Config.User}}')
echo "Default user: ${USER:-root}"
if [ -z "${USER}" ] || [ "${USER}" = "root" ] || [ "${USER}" = "0" ]; then
    echo "  WARNING: Image runs as root — add USER instruction with non-root user"
fi

# Health check
HEALTHCHECK=$(docker image inspect "${IMAGE}" --format '{{.Config.Healthcheck}}')
if [ "${HEALTHCHECK}" = "<nil>" ] || [ -z "${HEALTHCHECK}" ]; then
    echo "Health check: NOT CONFIGURED"
    echo "  WARNING: No HEALTHCHECK defined — add one for orchestrator integration"
else
    echo "Health check: configured"
fi

# Exposed ports
PORTS=$(docker image inspect "${IMAGE}" --format '{{json .Config.ExposedPorts}}')
echo "Exposed ports: ${PORTS}"

# Vulnerability scan with Trivy (if available)
echo
if command -v trivy &>/dev/null; then
    echo "Running Trivy vulnerability scan..."
    trivy image --severity HIGH,CRITICAL --no-progress "${IMAGE}"
else
    echo "Trivy not installed — skipping vulnerability scan"
    echo "Install: brew install trivy (macOS) or see https://aquasecurity.github.io/trivy/"
fi

echo
echo "=== Audit complete ==="
