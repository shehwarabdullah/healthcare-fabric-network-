#!/bin/bash
# One Health Global — Create Channel & Join Peers
set -e
source "$(dirname "$0")/env.sh"

log_info "============================================="
log_info " One Health Global — Channel Setup"
log_info " Channel: ${CHANNEL_NAME}"
log_info "============================================="

ARTIFACTS="${PROJECT_ROOT}/channel-artifacts"

# ============================================================
# STEP 1: Join orderer to channel via osnadmin
# ============================================================
log_info "Joining orderer to channel via osnadmin..."

osnadmin channel join \
    --channelID "${CHANNEL_NAME}" \
    --config-block "${ARTIFACTS}/genesis.block" \
    -o "localhost:7053" \
    --ca-file "${ORDERER_CA}" \
    --client-cert "${ORDERER_ADMIN_TLS_SIGN_CERT}" \
    --client-key "${ORDERER_ADMIN_TLS_PRIVATE_KEY}"

log_success "Orderer joined channel ${CHANNEL_NAME}."

# Verify orderer channel list
log_info "Verifying orderer channels..."
osnadmin channel list \
    -o "localhost:7053" \
    --ca-file "${ORDERER_CA}" \
    --client-cert "${ORDERER_ADMIN_TLS_SIGN_CERT}" \
    --client-key "${ORDERER_ADMIN_TLS_PRIVATE_KEY}"

sleep 3

# ============================================================
# STEP 2: Join Org1 (Hospital) peer to channel
# ============================================================
log_info "Joining Hospital peer to channel..."
set_org1_env

# Fetch genesis block from orderer
peer channel fetch 0 "${ARTIFACTS}/${CHANNEL_NAME}.block" \
    -o "${ORDERER_ADDRESS}" \
    --ordererTLSHostnameOverride "orderer.${DOMAIN}" \
    -c "${CHANNEL_NAME}" \
    --tls --cafile "${ORDERER_CA}"

# Join peer
peer channel join -b "${ARTIFACTS}/${CHANNEL_NAME}.block"
log_success "Hospital peer joined channel ${CHANNEL_NAME}."

# ============================================================
# STEP 3: Join Org2 (Clinic) peer to channel
# ============================================================
log_info "Joining Clinic peer to channel..."
set_org2_env

peer channel join -b "${ARTIFACTS}/${CHANNEL_NAME}.block"
log_success "Clinic peer joined channel ${CHANNEL_NAME}."

# ============================================================
# STEP 4: Set Anchor Peers
# ============================================================
log_info "Setting anchor peers..."

# Org1 anchor peer
set_org1_env
peer channel fetch config "${ARTIFACTS}/config_block.pb" \
    -o "${ORDERER_ADDRESS}" \
    --ordererTLSHostnameOverride "orderer.${DOMAIN}" \
    -c "${CHANNEL_NAME}" \
    --tls --cafile "${ORDERER_CA}"

configtxlator proto_decode --input "${ARTIFACTS}/config_block.pb" --type common.Block \
    --output "${ARTIFACTS}/config_block.json"

jq '.data.data[0].payload.data.config' "${ARTIFACTS}/config_block.json" > "${ARTIFACTS}/config.json"

# Add anchor peer for Org1
jq '.channel_group.groups.Application.groups.OHGHospitalOrgMSP.values += {
    "AnchorPeers": {
        "mod_policy": "Admins",
        "value": {
            "anchor_peers": [{"host": "peer0.hospital.onehealthglobal.com", "port": 7051}]
        },
        "version": "0"
    }
}' "${ARTIFACTS}/config.json" > "${ARTIFACTS}/modified_config_org1.json"

configtxlator proto_encode --input "${ARTIFACTS}/config.json" --type common.Config --output "${ARTIFACTS}/config.pb"
configtxlator proto_encode --input "${ARTIFACTS}/modified_config_org1.json" --type common.Config --output "${ARTIFACTS}/modified_config_org1.pb"
configtxlator compute_update --channel_id "${CHANNEL_NAME}" \
    --original "${ARTIFACTS}/config.pb" --updated "${ARTIFACTS}/modified_config_org1.pb" \
    --output "${ARTIFACTS}/anchor_update_org1.pb" 2>/dev/null || {
    log_warn "Anchor peer for Org1 may already be set. Skipping."
}

if [ -f "${ARTIFACTS}/anchor_update_org1.pb" ] && [ -s "${ARTIFACTS}/anchor_update_org1.pb" ]; then
    echo '{"payload":{"header":{"channel_header":{"channel_id":"'"${CHANNEL_NAME}"'","type":2}},"data":{"config_update":'$(configtxlator proto_decode --input "${ARTIFACTS}/anchor_update_org1.pb" --type common.ConfigUpdate)'}}}' | \
        jq . > "${ARTIFACTS}/anchor_update_org1_envelope.json"
    configtxlator proto_encode --input "${ARTIFACTS}/anchor_update_org1_envelope.json" --type common.Envelope --output "${ARTIFACTS}/anchor_update_org1_envelope.pb"
    peer channel update -f "${ARTIFACTS}/anchor_update_org1_envelope.pb" \
        -c "${CHANNEL_NAME}" -o "${ORDERER_ADDRESS}" \
        --ordererTLSHostnameOverride "orderer.${DOMAIN}" \
        --tls --cafile "${ORDERER_CA}"
    log_success "Anchor peer set for Hospital Org."
fi

# Org2 anchor peer (similar process)
set_org2_env
peer channel fetch config "${ARTIFACTS}/config_block2.pb" \
    -o "${ORDERER_ADDRESS}" \
    --ordererTLSHostnameOverride "orderer.${DOMAIN}" \
    -c "${CHANNEL_NAME}" \
    --tls --cafile "${ORDERER_CA}"

configtxlator proto_decode --input "${ARTIFACTS}/config_block2.pb" --type common.Block \
    --output "${ARTIFACTS}/config_block2.json"
jq '.data.data[0].payload.data.config' "${ARTIFACTS}/config_block2.json" > "${ARTIFACTS}/config2.json"

jq '.channel_group.groups.Application.groups.OHGClinicOrgMSP.values += {
    "AnchorPeers": {
        "mod_policy": "Admins",
        "value": {
            "anchor_peers": [{"host": "peer0.clinic.onehealthglobal.com", "port": 9051}]
        },
        "version": "0"
    }
}' "${ARTIFACTS}/config2.json" > "${ARTIFACTS}/modified_config_org2.json"

configtxlator proto_encode --input "${ARTIFACTS}/config2.json" --type common.Config --output "${ARTIFACTS}/config2.pb"
configtxlator proto_encode --input "${ARTIFACTS}/modified_config_org2.json" --type common.Config --output "${ARTIFACTS}/modified_config_org2.pb"
configtxlator compute_update --channel_id "${CHANNEL_NAME}" \
    --original "${ARTIFACTS}/config2.pb" --updated "${ARTIFACTS}/modified_config_org2.pb" \
    --output "${ARTIFACTS}/anchor_update_org2.pb" 2>/dev/null || {
    log_warn "Anchor peer for Org2 may already be set. Skipping."
}

if [ -f "${ARTIFACTS}/anchor_update_org2.pb" ] && [ -s "${ARTIFACTS}/anchor_update_org2.pb" ]; then
    echo '{"payload":{"header":{"channel_header":{"channel_id":"'"${CHANNEL_NAME}"'","type":2}},"data":{"config_update":'$(configtxlator proto_decode --input "${ARTIFACTS}/anchor_update_org2.pb" --type common.ConfigUpdate)'}}}' | \
        jq . > "${ARTIFACTS}/anchor_update_org2_envelope.json"
    configtxlator proto_encode --input "${ARTIFACTS}/anchor_update_org2_envelope.json" --type common.Envelope --output "${ARTIFACTS}/anchor_update_org2_envelope.pb"
    peer channel update -f "${ARTIFACTS}/anchor_update_org2_envelope.pb" \
        -c "${CHANNEL_NAME}" -o "${ORDERER_ADDRESS}" \
        --ordererTLSHostnameOverride "orderer.${DOMAIN}" \
        --tls --cafile "${ORDERER_CA}"
    log_success "Anchor peer set for Clinic Org."
fi

# ============================================================
# Verify
# ============================================================
log_info "Verifying channel membership..."
set_org1_env
peer channel getinfo -c "${CHANNEL_NAME}"
set_org2_env
peer channel getinfo -c "${CHANNEL_NAME}"

log_success "============================================="
log_success " Channel ${CHANNEL_NAME} ready!"
log_success " Both peers joined successfully."
log_success "============================================="
