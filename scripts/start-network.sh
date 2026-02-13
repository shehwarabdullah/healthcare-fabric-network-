#!/bin/bash
# One Health Global — Start Complete Network
set -e
source "$(dirname "$0")/env.sh"

log_info "============================================="
log_info " One Health Global — Starting Network"
log_info "============================================="

# ============================================================
# STEP 1: Generate crypto material (if not present)
# ============================================================
if [ ! -d "${CRYPTO_PATH}/peerOrganizations" ]; then
    log_info "Crypto material not found. Generating..."
    "${PROJECT_ROOT}/scripts/generate-crypto.sh"
else
    log_info "Crypto material found. Skipping generation."
fi

# ============================================================
# STEP 2: Generate channel artifacts (always regenerate to match crypto)
# ============================================================
log_info "Generating channel artifacts..."
"${PROJECT_ROOT}/scripts/generate-channel.sh"

# ============================================================
# STEP 3: Create Docker network (if not exists)
# ============================================================
docker network inspect ohg-network >/dev/null 2>&1 || {
    log_info "Creating Docker network: ohg-network"
    docker network create ohg-network
}

# ============================================================
# STEP 4: Start Orderer
# ============================================================
log_info "Starting Orderer..."
docker compose -f "${PROJECT_ROOT}/docker/orderer/docker-compose-orderer.yaml" up -d

# ============================================================
# STEP 5: Start Org1 (Hospital)
# ============================================================
log_info "Starting Hospital Org (Org1)..."
docker compose -f "${PROJECT_ROOT}/docker/org1/docker-compose-org1.yaml" up -d

# ============================================================
# STEP 6: Start Org2 (Clinic)
# ============================================================
log_info "Starting Clinic Org (Org2)..."
docker compose -f "${PROJECT_ROOT}/docker/org2/docker-compose-org2.yaml" up -d

# ============================================================
# STEP 7: Wait for services
# ============================================================
log_info "Waiting for services to be ready..."
sleep 10

# Verify containers
log_info "Verifying running containers..."
EXPECTED=("orderer.onehealthglobal.com" "peer0.hospital.onehealthglobal.com" "peer0.clinic.onehealthglobal.com" "couchdb.hospital.onehealthglobal.com" "couchdb.clinic.onehealthglobal.com")
ALL_UP=true
for CONTAINER in "${EXPECTED[@]}"; do
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
        log_success "  ${CONTAINER} is running"
    else
        log_error "  ${CONTAINER} is NOT running"
        ALL_UP=false
    fi
done

if $ALL_UP; then
    log_success "============================================="
    log_success " One Health Global Network is UP!"
    log_success "============================================="
    echo ""
    echo "Next steps:"
    echo "  1. Create channel:     ./scripts/create-channel.sh"
    echo "  2. Deploy chaincode:   ./scripts/deploy-chaincode.sh"
    echo "  3. Run transactions:   ./scripts/test-transactions.sh"
    echo "  4. Start Explorer:     docker compose -f docker/explorer/docker-compose-explorer.yaml up -d"
else
    log_error "Some containers failed to start. Check: docker ps -a"
    exit 1
fi