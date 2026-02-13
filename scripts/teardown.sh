#!/bin/bash
# One Health Global — Network Teardown
set -e
source "$(dirname "$0")/env.sh"

log_info "============================================="
log_info " One Health Global — Network Teardown"
log_info "============================================="

log_warn "This will destroy all containers, volumes, and crypto material."
read -p "Are you sure? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Teardown cancelled."
    exit 0
fi

# Stop and remove all containers
log_info "Stopping Explorer..."
docker compose -f "${PROJECT_ROOT}/docker/explorer/docker-compose-explorer.yaml" down -v 2>/dev/null || true

log_info "Stopping Vault..."
docker compose -f "${PROJECT_ROOT}/docker/vault/docker-compose-vault.yaml" down -v 2>/dev/null || true

log_info "Stopping Org2 (Clinic)..."
docker compose -f "${PROJECT_ROOT}/docker/org2/docker-compose-org2.yaml" down -v 2>/dev/null || true

log_info "Stopping Org1 (Hospital)..."
docker compose -f "${PROJECT_ROOT}/docker/org1/docker-compose-org1.yaml" down -v 2>/dev/null || true

log_info "Stopping Orderer..."
docker compose -f "${PROJECT_ROOT}/docker/orderer/docker-compose-orderer.yaml" down -v 2>/dev/null || true

log_info "Stopping CAs..."
docker compose -f "${PROJECT_ROOT}/docker/ca/docker-compose-ca.yaml" down -v 2>/dev/null || true

# Remove chaincode containers
log_info "Removing chaincode containers..."
docker rm -f $(docker ps -aq --filter "name=dev-peer*healthcare*") 2>/dev/null || true

# Remove chaincode images
log_info "Removing chaincode images..."
docker rmi -f $(docker images -q "dev-peer*healthcare*") 2>/dev/null || true

# Remove network
log_info "Removing Docker network..."
docker network rm ohg-network 2>/dev/null || true

# Clean generated artifacts
log_info "Cleaning crypto material and artifacts..."
rm -rf "${CRYPTO_PATH}"
rm -rf "${PROJECT_ROOT}/channel-artifacts"/*.block
rm -rf "${PROJECT_ROOT}/channel-artifacts"/*.tx
rm -rf "${PROJECT_ROOT}/channel-artifacts"/*.pb
rm -rf "${PROJECT_ROOT}/channel-artifacts"/*.json
rm -rf "${PROJECT_ROOT}/channel-artifacts"/*.tar.gz
rm -rf "${PROJECT_ROOT}/channel-artifacts/cert-rotation"

log_success "============================================="
log_success " One Health Global Network Torn Down"
log_success " All containers, volumes, and artifacts removed."
log_success "============================================="
