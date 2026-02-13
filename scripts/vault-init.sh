#!/bin/bash
# One Health Global — HashiCorp Vault Initialization
# Stores Fabric private keys in Vault KV secrets engine
set -e
source "$(dirname "$0")/env.sh"

log_info "============================================="
log_info " One Health Global — Vault Key Management"
log_info "============================================="

# Check if Vault is running
if ! curl -s "${VAULT_ADDR}/v1/sys/health" > /dev/null 2>&1; then
    log_error "Vault is not running. Start it first:"
    log_error "  docker compose -f docker/vault/docker-compose-vault.yaml up -d"
    exit 1
fi

export VAULT_ADDR="${VAULT_ADDR}"
export VAULT_TOKEN="${VAULT_TOKEN}"

# ============================================================
# STEP 1: Enable KV secrets engine
# ============================================================
log_info "Enabling KV v2 secrets engine..."
vault secrets enable -path=ohg-fabric kv-v2 2>/dev/null || log_warn "KV engine may already be enabled."

# ============================================================
# STEP 2: Store private keys
# ============================================================
log_info "Storing organization private keys in Vault..."

# Helper to store a private key
store_key_in_vault() {
    local VAULT_PATH="$1"
    local KEY_FILE="$2"
    local DESCRIPTION="$3"

    if [ -f "${KEY_FILE}" ]; then
        # Read the key content
        KEY_CONTENT=$(cat "${KEY_FILE}" | base64 -w 0)
        vault kv put "ohg-fabric/${VAULT_PATH}" \
            private_key="${KEY_CONTENT}" \
            description="${DESCRIPTION}" \
            stored_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        log_success "  Stored: ${VAULT_PATH}"
    else
        log_warn "  Key not found: ${KEY_FILE}"
    fi
}

# Orderer admin key
ORDERER_KEY=$(ls "${CRYPTO_PATH}/ordererOrganizations/${DOMAIN}/orderers/orderer.${DOMAIN}/msp/keystore/"* 2>/dev/null | head -1)
store_key_in_vault "orderer/admin/private-key" "${ORDERER_KEY}" "Orderer node signing key"

# Orderer TLS key
store_key_in_vault "orderer/tls/private-key" \
    "${CRYPTO_PATH}/ordererOrganizations/${DOMAIN}/orderers/orderer.${DOMAIN}/tls/server.key" \
    "Orderer TLS private key"

# Hospital peer key
HOSPITAL_PEER_KEY=$(ls "${CRYPTO_PATH}/peerOrganizations/${ORG1_DOMAIN}/peers/peer0.${ORG1_DOMAIN}/msp/keystore/"* 2>/dev/null | head -1)
store_key_in_vault "hospital/peer0/private-key" "${HOSPITAL_PEER_KEY}" "Hospital peer0 signing key"

# Hospital admin key
HOSPITAL_ADMIN_KEY=$(ls "${CRYPTO_PATH}/peerOrganizations/${ORG1_DOMAIN}/users/Admin@${ORG1_DOMAIN}/msp/keystore/"* 2>/dev/null | head -1)
store_key_in_vault "hospital/admin/private-key" "${HOSPITAL_ADMIN_KEY}" "Hospital admin signing key"

# Hospital TLS key
store_key_in_vault "hospital/peer0/tls-key" \
    "${CRYPTO_PATH}/peerOrganizations/${ORG1_DOMAIN}/peers/peer0.${ORG1_DOMAIN}/tls/server.key" \
    "Hospital peer0 TLS private key"

# Clinic peer key
CLINIC_PEER_KEY=$(ls "${CRYPTO_PATH}/peerOrganizations/${ORG2_DOMAIN}/peers/peer0.${ORG2_DOMAIN}/msp/keystore/"* 2>/dev/null | head -1)
store_key_in_vault "clinic/peer0/private-key" "${CLINIC_PEER_KEY}" "Clinic peer0 signing key"

# Clinic admin key
CLINIC_ADMIN_KEY=$(ls "${CRYPTO_PATH}/peerOrganizations/${ORG2_DOMAIN}/users/Admin@${ORG2_DOMAIN}/msp/keystore/"* 2>/dev/null | head -1)
store_key_in_vault "clinic/admin/private-key" "${CLINIC_ADMIN_KEY}" "Clinic admin signing key"

# Clinic TLS key
store_key_in_vault "clinic/peer0/tls-key" \
    "${CRYPTO_PATH}/peerOrganizations/${ORG2_DOMAIN}/peers/peer0.${ORG2_DOMAIN}/tls/server.key" \
    "Clinic peer0 TLS private key"

# ============================================================
# STEP 3: Create access policies
# ============================================================
log_info "Creating Vault access policies..."

# Hospital org policy
vault policy write ohg-hospital-policy - <<EOF
path "ohg-fabric/data/hospital/*" {
  capabilities = ["read", "list"]
}
path "ohg-fabric/metadata/hospital/*" {
  capabilities = ["read", "list"]
}
EOF

# Clinic org policy
vault policy write ohg-clinic-policy - <<EOF
path "ohg-fabric/data/clinic/*" {
  capabilities = ["read", "list"]
}
path "ohg-fabric/metadata/clinic/*" {
  capabilities = ["read", "list"]
}
EOF

# Orderer policy
vault policy write ohg-orderer-policy - <<EOF
path "ohg-fabric/data/orderer/*" {
  capabilities = ["read", "list"]
}
path "ohg-fabric/metadata/orderer/*" {
  capabilities = ["read", "list"]
}
EOF

log_success "Vault policies created."

# ============================================================
# STEP 4: Verify
# ============================================================
log_info "Verifying stored keys..."
vault kv list ohg-fabric/hospital/ 2>/dev/null || true
vault kv list ohg-fabric/clinic/ 2>/dev/null || true
vault kv list ohg-fabric/orderer/ 2>/dev/null || true

# ============================================================
# STEP 5: (Optional) Remove local private keys
# ============================================================
log_info ""
log_info "IMPORTANT: In production, after verifying Vault storage,"
log_info "remove local private keys from the filesystem:"
log_info ""
log_info "  # Remove all local private keys"
log_info "  find ${CRYPTO_PATH} -name '*_sk' -delete"
log_info "  find ${CRYPTO_PATH} -path '*/keystore/*' -delete"
log_info ""
log_info "  # Configure Fabric nodes to use Vault via BCCSP plugin"
log_info "  # or use a sidecar to mount keys from Vault at runtime"

log_success "============================================="
log_success " Vault Key Management Initialized!"
log_success " Vault UI: ${VAULT_ADDR}/ui"
log_success " Token: ${VAULT_TOKEN} (dev mode only)"
log_success "============================================="
