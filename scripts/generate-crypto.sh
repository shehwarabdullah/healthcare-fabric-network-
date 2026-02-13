#!/bin/bash
# One Health Global — Generate Crypto Material using Fabric CAs
# Each org has its own standalone CA
set -e
source "$(dirname "$0")/env.sh"

log_info "============================================="
log_info " One Health Global — Crypto Material Generation"
log_info "============================================="

# ============================================================
# STEP 0: Full cleanup (use sudo if needed for Docker-owned files)
# ============================================================
log_info "Cleaning previous crypto material..."
sudo rm -rf "${CRYPTO_PATH}" 2>/dev/null || rm -rf "${CRYPTO_PATH}" 2>/dev/null || true
mkdir -p "${CRYPTO_PATH}/fabric-ca/hospital"
mkdir -p "${CRYPTO_PATH}/fabric-ca/clinic"
mkdir -p "${CRYPTO_PATH}/fabric-ca/ordererOrg"

# Kill any leftover CA containers
docker rm -f ca.hospital.onehealthglobal.com ca.clinic.onehealthglobal.com ca.orderer.onehealthglobal.com 2>/dev/null || true

# ============================================================
# STEP 1: Start CAs
# ============================================================
log_info "Starting Certificate Authority services..."
docker compose -f "${PROJECT_ROOT}/docker/ca/docker-compose-ca.yaml" up -d

# Wait for ALL three CAs to produce their tls-cert.pem
log_info "Waiting for CAs to initialize..."
for CA_DIR in hospital clinic ordererOrg; do
    CERT_FILE="${CRYPTO_PATH}/fabric-ca/${CA_DIR}/tls-cert.pem"
    RETRIES=0
    while [ ! -f "${CERT_FILE}" ] && [ $RETRIES -lt 60 ]; do
        sleep 1
        RETRIES=$((RETRIES + 1))
        if [ $((RETRIES % 10)) -eq 0 ]; then
            echo "  Waiting for ${CA_DIR} CA... (${RETRIES}s)"
        fi
    done
    if [ ! -f "${CERT_FILE}" ]; then
        log_error "${CA_DIR} CA failed to start. Check: docker logs ca.${CA_DIR}.onehealthglobal.com"
        exit 1
    fi
    log_success "  ${CA_DIR} CA is ready."
done

log_success "All CAs are running."

# ============================================================
# Helper: Create NodeOUs config.yaml
# ============================================================
create_nodeou_config() {
    local MSP_DIR="$1"
    local CA_CERT_FILENAME="$2"
    cat > "${MSP_DIR}/config.yaml" <<NODEOU_EOF
NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: cacerts/${CA_CERT_FILENAME}
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: cacerts/${CA_CERT_FILENAME}
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: cacerts/${CA_CERT_FILENAME}
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: cacerts/${CA_CERT_FILENAME}
    OrganizationalUnitIdentifier: orderer
NODEOU_EOF
}

# ============================================================
# Helper: Normalize TLS directory
# ============================================================
fix_tls_dir() {
    local TLS_DIR="$1"
    cp "${TLS_DIR}/tlscacerts/"* "${TLS_DIR}/ca.crt" 2>/dev/null
    cp "${TLS_DIR}/signcerts/"* "${TLS_DIR}/server.crt" 2>/dev/null
    cp "${TLS_DIR}/keystore/"* "${TLS_DIR}/server.key" 2>/dev/null
}

# ============================================================
# Helper: Find the CA cert filename in cacerts/
# ============================================================
get_ca_cert_filename() {
    local MSP_DIR="$1"
    ls "${MSP_DIR}/cacerts/" 2>/dev/null | head -1
}

# ============================================================
# STEP 2: Enroll Orderer Org
# ============================================================
log_info "Enrolling Orderer organization..."

ORDERER_ORG_HOME="${CRYPTO_PATH}/ordererOrganizations/${DOMAIN}"
TLS_CERT="${CRYPTO_PATH}/fabric-ca/ordererOrg/tls-cert.pem"

export FABRIC_CA_CLIENT_HOME="${ORDERER_ORG_HOME}"
mkdir -p "${ORDERER_ORG_HOME}"

# Enroll CA admin
fabric-ca-client enroll \
    -u "https://admin:adminpw@localhost:${CA_ORDERER_PORT}" \
    --caname ca-orderer-ohg \
    --tls.certfiles "${TLS_CERT}" \
    -M "${ORDERER_ORG_HOME}/msp"

CA_CERT=$(get_ca_cert_filename "${ORDERER_ORG_HOME}/msp")
create_nodeou_config "${ORDERER_ORG_HOME}/msp" "${CA_CERT}"

# Register identities
fabric-ca-client register --caname ca-orderer-ohg \
    --id.name orderer --id.secret ordererpw --id.type orderer \
    --tls.certfiles "${TLS_CERT}"

fabric-ca-client register --caname ca-orderer-ohg \
    --id.name ordererAdmin --id.secret ordererAdminpw --id.type admin \
    --tls.certfiles "${TLS_CERT}"

# Enroll orderer node MSP
ORDERER_NODE="${ORDERER_ORG_HOME}/orderers/orderer.${DOMAIN}"
mkdir -p "${ORDERER_NODE}"

fabric-ca-client enroll \
    -u "https://orderer:ordererpw@localhost:${CA_ORDERER_PORT}" \
    --caname ca-orderer-ohg \
    -M "${ORDERER_NODE}/msp" \
    --tls.certfiles "${TLS_CERT}" \
    --csr.hosts "orderer.${DOMAIN},localhost"

create_nodeou_config "${ORDERER_NODE}/msp" "${CA_CERT}"

# Enroll orderer node TLS
fabric-ca-client enroll \
    -u "https://orderer:ordererpw@localhost:${CA_ORDERER_PORT}" \
    --caname ca-orderer-ohg \
    -M "${ORDERER_NODE}/tls" \
    --enrollment.profile tls \
    --tls.certfiles "${TLS_CERT}" \
    --csr.hosts "orderer.${DOMAIN},localhost"

fix_tls_dir "${ORDERER_NODE}/tls"

# Create tlscacerts in MSP (needed by configtx.yaml)
mkdir -p "${ORDERER_NODE}/msp/tlscacerts"
cp "${ORDERER_NODE}/tls/ca.crt" "${ORDERER_NODE}/msp/tlscacerts/tlsca.${DOMAIN}-cert.pem"

# Enroll orderer admin user
ORDERER_ADMIN="${ORDERER_ORG_HOME}/users/Admin@${DOMAIN}"
mkdir -p "${ORDERER_ADMIN}"

fabric-ca-client enroll \
    -u "https://ordererAdmin:ordererAdminpw@localhost:${CA_ORDERER_PORT}" \
    --caname ca-orderer-ohg \
    -M "${ORDERER_ADMIN}/msp" \
    --tls.certfiles "${TLS_CERT}"

create_nodeou_config "${ORDERER_ADMIN}/msp" "${CA_CERT}"

log_success "Orderer organization enrolled."

# ============================================================
# STEP 3+4: Enroll Peer Orgs (reusable function)
# ============================================================
enroll_peer_org() {
    local LABEL="$1"       # "Hospital" or "Clinic"
    local ORG_DOM="$2"     # hospital.onehealthglobal.com
    local CA_PORT="$3"     # 7054 or 8054
    local CA_NAME="$4"     # ca-hospital-ohg or ca-clinic-ohg
    local CA_DIR="$5"      # hospital or clinic

    log_info "Enrolling ${LABEL} organization (${ORG_DOM})..."

    local TLS_FILE="${CRYPTO_PATH}/fabric-ca/${CA_DIR}/tls-cert.pem"
    local ORG_DIR="${CRYPTO_PATH}/peerOrganizations/${ORG_DOM}"

    export FABRIC_CA_CLIENT_HOME="${ORG_DIR}"
    mkdir -p "${ORG_DIR}"

    # Enroll CA admin
    fabric-ca-client enroll \
        -u "https://admin:adminpw@localhost:${CA_PORT}" \
        --caname "${CA_NAME}" \
        --tls.certfiles "${TLS_FILE}" \
        -M "${ORG_DIR}/msp"

    local CA_CERT_FILE
    CA_CERT_FILE=$(get_ca_cert_filename "${ORG_DIR}/msp")
    create_nodeou_config "${ORG_DIR}/msp" "${CA_CERT_FILE}"

    # Register identities
    fabric-ca-client register --caname "${CA_NAME}" \
        --id.name peer0 --id.secret peer0pw --id.type peer \
        --tls.certfiles "${TLS_FILE}"

    fabric-ca-client register --caname "${CA_NAME}" \
        --id.name user1 --id.secret user1pw --id.type client \
        --tls.certfiles "${TLS_FILE}"

    fabric-ca-client register --caname "${CA_NAME}" \
        --id.name orgadmin --id.secret orgadminpw --id.type admin \
        --tls.certfiles "${TLS_FILE}"

    # ---- Enroll peer0 MSP ----
    local PEER="${ORG_DIR}/peers/peer0.${ORG_DOM}"
    mkdir -p "${PEER}"

    fabric-ca-client enroll \
        -u "https://peer0:peer0pw@localhost:${CA_PORT}" \
        --caname "${CA_NAME}" \
        -M "${PEER}/msp" \
        --tls.certfiles "${TLS_FILE}" \
        --csr.hosts "peer0.${ORG_DOM},localhost"

    create_nodeou_config "${PEER}/msp" "${CA_CERT_FILE}"

    # ---- Enroll peer0 TLS ----
    fabric-ca-client enroll \
        -u "https://peer0:peer0pw@localhost:${CA_PORT}" \
        --caname "${CA_NAME}" \
        -M "${PEER}/tls" \
        --enrollment.profile tls \
        --tls.certfiles "${TLS_FILE}" \
        --csr.hosts "peer0.${ORG_DOM},localhost"

    fix_tls_dir "${PEER}/tls"

    # ---- Enroll Admin user ----
    local ADMIN="${ORG_DIR}/users/Admin@${ORG_DOM}"
    mkdir -p "${ADMIN}"

    fabric-ca-client enroll \
        -u "https://orgadmin:orgadminpw@localhost:${CA_PORT}" \
        --caname "${CA_NAME}" \
        -M "${ADMIN}/msp" \
        --tls.certfiles "${TLS_FILE}"

    create_nodeou_config "${ADMIN}/msp" "${CA_CERT_FILE}"

    # Rename keystore key to priv_sk (Explorer compatibility)
    if [ -d "${ADMIN}/msp/keystore" ]; then
        local KEY
        KEY=$(ls "${ADMIN}/msp/keystore/" | head -1)
        if [ -n "${KEY}" ] && [ "${KEY}" != "priv_sk" ]; then
            cp "${ADMIN}/msp/keystore/${KEY}" "${ADMIN}/msp/keystore/priv_sk"
        fi
    fi

    # ---- Enroll User1 ----
    local USER="${ORG_DIR}/users/User1@${ORG_DOM}"
    mkdir -p "${USER}"

    fabric-ca-client enroll \
        -u "https://user1:user1pw@localhost:${CA_PORT}" \
        --caname "${CA_NAME}" \
        -M "${USER}/msp" \
        --tls.certfiles "${TLS_FILE}"

    create_nodeou_config "${USER}/msp" "${CA_CERT_FILE}"

    log_success "${LABEL} organization enrolled."
}

# Enroll Hospital Org
enroll_peer_org "Hospital" "${ORG1_DOMAIN}" "${CA_HOSPITAL_PORT}" "ca-hospital-ohg" "hospital"

# Enroll Clinic Org
enroll_peer_org "Clinic" "${ORG2_DOMAIN}" "${CA_CLINIC_PORT}" "ca-clinic-ohg" "clinic"

# ============================================================
# STEP 5: Verify all critical files exist
# ============================================================
log_info "Verifying crypto material..."
ERRORS=0
CRITICAL_FILES=(
    "${CRYPTO_PATH}/ordererOrganizations/${DOMAIN}/orderers/orderer.${DOMAIN}/tls/server.crt"
    "${CRYPTO_PATH}/ordererOrganizations/${DOMAIN}/orderers/orderer.${DOMAIN}/tls/server.key"
    "${CRYPTO_PATH}/ordererOrganizations/${DOMAIN}/orderers/orderer.${DOMAIN}/tls/ca.crt"
    "${CRYPTO_PATH}/ordererOrganizations/${DOMAIN}/orderers/orderer.${DOMAIN}/msp/signcerts/cert.pem"
    "${CRYPTO_PATH}/ordererOrganizations/${DOMAIN}/msp/config.yaml"
    "${CRYPTO_PATH}/peerOrganizations/${ORG1_DOMAIN}/peers/peer0.${ORG1_DOMAIN}/tls/server.crt"
    "${CRYPTO_PATH}/peerOrganizations/${ORG1_DOMAIN}/peers/peer0.${ORG1_DOMAIN}/tls/server.key"
    "${CRYPTO_PATH}/peerOrganizations/${ORG1_DOMAIN}/peers/peer0.${ORG1_DOMAIN}/tls/ca.crt"
    "${CRYPTO_PATH}/peerOrganizations/${ORG1_DOMAIN}/users/Admin@${ORG1_DOMAIN}/msp/keystore/priv_sk"
    "${CRYPTO_PATH}/peerOrganizations/${ORG1_DOMAIN}/msp/config.yaml"
    "${CRYPTO_PATH}/peerOrganizations/${ORG2_DOMAIN}/peers/peer0.${ORG2_DOMAIN}/tls/server.crt"
    "${CRYPTO_PATH}/peerOrganizations/${ORG2_DOMAIN}/peers/peer0.${ORG2_DOMAIN}/tls/server.key"
    "${CRYPTO_PATH}/peerOrganizations/${ORG2_DOMAIN}/peers/peer0.${ORG2_DOMAIN}/tls/ca.crt"
    "${CRYPTO_PATH}/peerOrganizations/${ORG2_DOMAIN}/users/Admin@${ORG2_DOMAIN}/msp/keystore/priv_sk"
    "${CRYPTO_PATH}/peerOrganizations/${ORG2_DOMAIN}/msp/config.yaml"
)

for F in "${CRITICAL_FILES[@]}"; do
    if [ ! -f "$F" ]; then
        log_error "MISSING: $F"
        ERRORS=$((ERRORS + 1))
    fi
done

if [ $ERRORS -eq 0 ]; then
    log_success "============================================="
    log_success " All crypto material generated successfully!"
    log_success "   Orderer: orderer.${DOMAIN}"
    log_success "   Hospital: peer0.${ORG1_DOMAIN}"
    log_success "   Clinic: peer0.${ORG2_DOMAIN}"
    log_success "============================================="
else
    log_error "${ERRORS} critical files missing!"
    exit 1
fi
