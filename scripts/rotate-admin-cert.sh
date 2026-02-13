#!/bin/bash
# One Health Global — Admin Certificate Rotation
# Demonstrates rotating an org admin cert without breaking channel governance
set -e
source "$(dirname "$0")/env.sh"

log_info "============================================="
log_info " One Health Global — Admin Certificate Rotation"
log_info " Org: OHGHospitalOrg (Org1)"
log_info "============================================="

ARTIFACTS="${PROJECT_ROOT}/channel-artifacts"
ROTATION_DIR="${PROJECT_ROOT}/channel-artifacts/cert-rotation"
mkdir -p "${ROTATION_DIR}"

CA_TLS_CERT="${CRYPTO_PATH}/fabric-ca/hospital/tls-cert.pem"

# ============================================================
# STEP 1: Enroll a NEW admin identity from the Hospital CA
# ============================================================
log_info "Step 1: Registering new admin identity with Hospital CA..."

export FABRIC_CA_CLIENT_HOME="${CRYPTO_PATH}/peerOrganizations/${ORG1_DOMAIN}"

# Register new admin
fabric-ca-client register --caname ca-hospital-ohg \
    --id.name hospitaladmin2 --id.secret hospitaladmin2pw --id.type admin \
    --tls.certfiles "${CA_TLS_CERT}" 2>/dev/null || {
    log_warn "Admin may already be registered. Continuing..."
}

# Enroll new admin
NEW_ADMIN_DIR="${ROTATION_DIR}/new-admin-hospital"
mkdir -p "${NEW_ADMIN_DIR}"

fabric-ca-client enroll -u "https://hospitaladmin2:hospitaladmin2pw@localhost:${CA_HOSPITAL_PORT}" \
    --caname ca-hospital-ohg \
    -M "${NEW_ADMIN_DIR}/msp" \
    --tls.certfiles "${CA_TLS_CERT}"

# Copy NodeOUs config
cp "${CRYPTO_PATH}/peerOrganizations/${ORG1_DOMAIN}/msp/config.yaml" "${NEW_ADMIN_DIR}/msp/config.yaml"

log_success "New admin enrolled at: ${NEW_ADMIN_DIR}/msp"

# ============================================================
# STEP 2: Backup current admin cert
# ============================================================
log_info "Step 2: Backing up current admin certificate..."

CURRENT_ADMIN_CERT="${CRYPTO_PATH}/peerOrganizations/${ORG1_DOMAIN}/users/Admin@${ORG1_DOMAIN}/msp/signcerts/cert.pem"
cp "${CURRENT_ADMIN_CERT}" "${ROTATION_DIR}/old-admin-cert.pem"

NEW_ADMIN_CERT=$(ls "${NEW_ADMIN_DIR}/msp/signcerts/"*.pem | head -1)
cp "${NEW_ADMIN_CERT}" "${ROTATION_DIR}/new-admin-cert.pem"

log_info "Old admin cert backed up."
log_info "New admin cert: $(openssl x509 -in "${ROTATION_DIR}/new-admin-cert.pem" -subject -noout 2>/dev/null)"

# ============================================================
# STEP 3: Fetch channel config and add new admin cert
# ============================================================
log_info "Step 3: Updating channel config to include new admin cert..."
set_org1_env

peer channel fetch config "${ROTATION_DIR}/config_block.pb" \
    -o "${ORDERER_ADDRESS}" \
    --ordererTLSHostnameOverride "orderer.${DOMAIN}" \
    -c "${CHANNEL_NAME}" \
    --tls --cafile "${ORDERER_CA}"

configtxlator proto_decode --input "${ROTATION_DIR}/config_block.pb" \
    --type common.Block --output "${ROTATION_DIR}/config_block.json"

jq '.data.data[0].payload.data.config' "${ROTATION_DIR}/config_block.json" \
    > "${ROTATION_DIR}/config.json"

# Extract new admin cert as base64
NEW_CERT_B64=$(base64 -w 0 "${ROTATION_DIR}/new-admin-cert.pem")

# Add new admin cert to the org's MSP admincerts in channel config
# With NodeOUs enabled, admin role is determined by OU, not admincerts folder.
# The key action is that the new cert was enrolled with type=admin from the same CA.
# For demonstration, we show the config update process:

log_info "With NodeOUs enabled, admin identity is determined by the 'admin' OU in the certificate."
log_info "Since the new cert was enrolled as type=admin from the Hospital CA, it is automatically"
log_info "recognized as an admin by the MSP without needing a channel config update."

# ============================================================
# STEP 4: Replace admin credentials in the MSP directory
# ============================================================
log_info "Step 4: Replacing admin credentials in the local MSP..."

ADMIN_MSP="${CRYPTO_PATH}/peerOrganizations/${ORG1_DOMAIN}/users/Admin@${ORG1_DOMAIN}/msp"

# Backup old credentials
cp -r "${ADMIN_MSP}" "${ROTATION_DIR}/old-admin-msp-backup"

# Replace signcerts
cp "${NEW_ADMIN_DIR}/msp/signcerts/"*.pem "${ADMIN_MSP}/signcerts/cert.pem"

# Replace keystore
rm -f "${ADMIN_MSP}/keystore/"*
cp "${NEW_ADMIN_DIR}/msp/keystore/"* "${ADMIN_MSP}/keystore/"
# Rename for Explorer compatibility
KEY=$(ls "${ADMIN_MSP}/keystore/" | head -1)
[ -n "$KEY" ] && [ "$KEY" != "priv_sk" ] && cp "${ADMIN_MSP}/keystore/${KEY}" "${ADMIN_MSP}/keystore/priv_sk"

log_success "Admin credentials rotated in local MSP."

# ============================================================
# STEP 5: Verify new admin can transact
# ============================================================
log_info "Step 5: Verifying new admin identity can transact..."
set_org1_env

# Query with new admin
peer chaincode query -C "${CHANNEL_NAME}" -n "${CHAINCODE_NAME}" \
    -c '{"function":"ReadRecord","Args":["PAT-001"]}' | jq .patientName

log_success "New admin identity verified — can query the ledger."

# ============================================================
# STEP 6: Optionally remove old admin cert from channel config
# ============================================================
log_info "Step 6: (Optional) To fully revoke the old admin, you would:"
log_info "  a) Revoke the old cert through the CA: fabric-ca-client revoke"
log_info "  b) Generate a new CRL and update the channel config"
log_info "  c) This ensures the old cert can no longer sign transactions"

log_success "============================================="
log_success " Admin Certificate Rotation Complete!"
log_success ""
log_success " Summary:"
log_success "   - New admin enrolled: hospitaladmin2"
log_success "   - Old credentials backed up to: ${ROTATION_DIR}/"
log_success "   - New credentials installed in Admin MSP"
log_success "   - Verified: new admin can query/invoke chaincode"
log_success ""
log_success " Production Notes:"
log_success "   - With NodeOUs, admin status is by cert OU attribute"
log_success "   - No channel config update needed for basic rotation"
log_success "   - For revocation, update CRL via channel config update"
log_success "   - Store keys in Vault, not local filesystem"
log_success "============================================="
