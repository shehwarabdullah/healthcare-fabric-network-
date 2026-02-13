#!/bin/bash
# One Health Global — Channel Config Update Demonstration
# Modifies batch timeout as a dummy config update
set -e
source "$(dirname "$0")/env.sh"

log_info "============================================="
log_info " One Health Global — Channel Config Update"
log_info " Demo: Modify BatchTimeout from 2s to 3s"
log_info "============================================="

ARTIFACTS="${PROJECT_ROOT}/channel-artifacts"

# ============================================================
# STEP 1: Fetch current config
# ============================================================
set_org1_env
log_info "Fetching current channel configuration..."

peer channel fetch config "${ARTIFACTS}/config_update_block.pb" \
    -o "${ORDERER_ADDRESS}" \
    --ordererTLSHostnameOverride "orderer.${DOMAIN}" \
    -c "${CHANNEL_NAME}" \
    --tls --cafile "${ORDERER_CA}"

configtxlator proto_decode --input "${ARTIFACTS}/config_update_block.pb" \
    --type common.Block --output "${ARTIFACTS}/config_update_block.json"

jq '.data.data[0].payload.data.config' "${ARTIFACTS}/config_update_block.json" \
    > "${ARTIFACTS}/current_config.json"

log_info "Current BatchTimeout: $(jq -r '.channel_group.groups.Orderer.values.BatchTimeout.value.timeout' ${ARTIFACTS}/current_config.json)"

# ============================================================
# STEP 2: Modify config (change BatchTimeout)
# ============================================================
log_info "Modifying BatchTimeout to 3s..."

jq '.channel_group.groups.Orderer.values.BatchTimeout.value.timeout = "3s"' \
    "${ARTIFACTS}/current_config.json" > "${ARTIFACTS}/modified_config.json"

# ============================================================
# STEP 3: Compute update delta
# ============================================================
log_info "Computing config update delta..."

configtxlator proto_encode --input "${ARTIFACTS}/current_config.json" \
    --type common.Config --output "${ARTIFACTS}/current_config.pb"

configtxlator proto_encode --input "${ARTIFACTS}/modified_config.json" \
    --type common.Config --output "${ARTIFACTS}/modified_config.pb"

configtxlator compute_update --channel_id "${CHANNEL_NAME}" \
    --original "${ARTIFACTS}/current_config.pb" \
    --updated "${ARTIFACTS}/modified_config.pb" \
    --output "${ARTIFACTS}/config_update.pb"

# ============================================================
# STEP 4: Wrap in envelope
# ============================================================
log_info "Wrapping update in envelope..."

configtxlator proto_decode --input "${ARTIFACTS}/config_update.pb" \
    --type common.ConfigUpdate --output "${ARTIFACTS}/config_update.json"

echo '{"payload":{"header":{"channel_header":{"channel_id":"'"${CHANNEL_NAME}"'","type":2}},"data":{"config_update":'$(cat ${ARTIFACTS}/config_update.json)'}}}' | \
    jq . > "${ARTIFACTS}/config_update_envelope.json"

configtxlator proto_encode --input "${ARTIFACTS}/config_update_envelope.json" \
    --type common.Envelope --output "${ARTIFACTS}/config_update_envelope.pb"

# ============================================================
# STEP 5: Sign with Org1 (Hospital)
# ============================================================
log_info "Signing config update with Hospital org..."
set_org1_env
peer channel signconfigtx -f "${ARTIFACTS}/config_update_envelope.pb"

# ============================================================
# STEP 6: Submit with Org2 (Clinic) — satisfies MAJORITY Admins
# ============================================================
log_info "Submitting config update from Clinic org..."
set_org2_env
peer channel update -f "${ARTIFACTS}/config_update_envelope.pb" \
    -c "${CHANNEL_NAME}" \
    -o "${ORDERER_ADDRESS}" \
    --ordererTLSHostnameOverride "orderer.${DOMAIN}" \
    --tls --cafile "${ORDERER_CA}"

# ============================================================
# STEP 7: Verify
# ============================================================
log_info "Verifying config update..."
sleep 2

peer channel fetch config "${ARTIFACTS}/updated_config_block.pb" \
    -o "${ORDERER_ADDRESS}" \
    --ordererTLSHostnameOverride "orderer.${DOMAIN}" \
    -c "${CHANNEL_NAME}" \
    --tls --cafile "${ORDERER_CA}"

configtxlator proto_decode --input "${ARTIFACTS}/updated_config_block.pb" \
    --type common.Block --output "${ARTIFACTS}/updated_config_block.json"

NEW_TIMEOUT=$(jq -r '.data.data[0].payload.data.config.channel_group.groups.Orderer.values.BatchTimeout.value.timeout' \
    "${ARTIFACTS}/updated_config_block.json")

log_success "============================================="
log_success " Channel Config Update Complete!"
log_success " BatchTimeout changed to: ${NEW_TIMEOUT}"
log_success " Signed by: OHGHospitalOrg + OHGClinicOrg"
log_success "============================================="
