#!/bin/bash
# One Health Global — Generate Channel Artifacts
set -e
source "$(dirname "$0")/env.sh"

log_info "============================================="
log_info " One Health Global — Channel Artifact Generation"
log_info "============================================="

export FABRIC_CFG_PATH="${PROJECT_ROOT}/configtx"
ARTIFACTS="${PROJECT_ROOT}/channel-artifacts"
mkdir -p "${ARTIFACTS}"

# ============================================================
# Generate Genesis Block (for osnadmin channel join)
# ============================================================
log_info "Generating genesis block for orderer..."
configtxgen -profile OHGOrdererGenesis \
    -outputBlock "${ARTIFACTS}/genesis.block" \
    -channelID healthchannel

log_success "Genesis block created: ${ARTIFACTS}/genesis.block"

log_info "Channel artifacts generation complete."
log_info "Artifacts directory:"
ls -la "${ARTIFACTS}/"
