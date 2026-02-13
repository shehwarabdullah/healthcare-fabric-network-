#!/bin/bash
# One Health Global — Deploy Healthcare Chaincode using CCaaS
# Uses Chaincode-as-a-Service so the peer doesn't need Docker socket access
# This is the recommended approach for Fabric 2.5+ and works on WSL2
set -e
source "$(dirname "$0")/env.sh"

log_info "============================================="
log_info " One Health Global — Chaincode Deployment (CCaaS)"
log_info " Chaincode: ${CHAINCODE_NAME} v${CHAINCODE_VERSION}"
log_info " Endorsement: AND(OHGHospitalOrgMSP, OHGClinicOrgMSP)"
log_info "============================================="

CC_LABEL="${CHAINCODE_NAME}_${CHAINCODE_VERSION}"
BUILD_DIR=$(mktemp -d)

# ============================================================
# STEP 1: Build the chaincode binary
# ============================================================
log_info "Building chaincode binary..."
pushd "${CHAINCODE_PATH}" > /dev/null
GO111MODULE=on go mod vendor 2>/dev/null || true
GO111MODULE=on CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -mod=vendor -o "${BUILD_DIR}/chaincode" .
popd > /dev/null
log_success "Chaincode binary built."

# ============================================================
# STEP 2: Create CCaaS chaincode package
# ============================================================
log_info "Creating CCaaS chaincode package..."

# The chaincode will listen on these addresses
CC_ORG1_ADDRESS="healthcare-cc-org1:9999"
CC_ORG2_ADDRESS="healthcare-cc-org2:9999"

# Create connection.json for Org1
mkdir -p "${BUILD_DIR}/org1-pkg" "${BUILD_DIR}/org2-pkg"

cat > "${BUILD_DIR}/org1-pkg/connection.json" <<EOF
{
  "address": "${CC_ORG1_ADDRESS}",
  "dial_timeout": "10s",
  "tls_required": false
}
EOF

cat > "${BUILD_DIR}/org2-pkg/connection.json" <<EOF
{
  "address": "${CC_ORG2_ADDRESS}",
  "dial_timeout": "10s",
  "tls_required": false
}
EOF

# Create metadata.json (same for both)
for DIR in org1-pkg org2-pkg; do
    cat > "${BUILD_DIR}/${DIR}/metadata.json" <<EOF
{
  "type": "ccaas",
  "label": "${CC_LABEL}"
}
EOF
done

# Package as tar.gz (Fabric CCaaS format)
CC_PKG_ORG1="${PROJECT_ROOT}/channel-artifacts/${CHAINCODE_NAME}-org1.tgz"
CC_PKG_ORG2="${PROJECT_ROOT}/channel-artifacts/${CHAINCODE_NAME}-org2.tgz"

# Create code.tar.gz containing connection.json
cd "${BUILD_DIR}/org1-pkg"
tar czf code.tar.gz connection.json
tar czf "${CC_PKG_ORG1}" code.tar.gz metadata.json

cd "${BUILD_DIR}/org2-pkg"
tar czf code.tar.gz connection.json
tar czf "${CC_PKG_ORG2}" code.tar.gz metadata.json

cd "${PROJECT_ROOT}/scripts"
log_success "CCaaS packages created."

# ============================================================
# STEP 3: Build Docker image for the chaincode server
# ============================================================
log_info "Building chaincode Docker image..."

cat > "${BUILD_DIR}/Dockerfile" <<'DOCKERFILE'
FROM alpine:3.18
RUN apk add --no-cache libc6-compat
COPY chaincode /usr/local/bin/chaincode
RUN chmod +x /usr/local/bin/chaincode
EXPOSE 9999
CMD ["chaincode"]
DOCKERFILE

docker build -t healthcare-cc:latest "${BUILD_DIR}" -q 2>&1 | tail -2
log_success "Chaincode Docker image built."

rm -rf "${BUILD_DIR}"

# ============================================================
# STEP 4: Start chaincode containers
# ============================================================
log_info "Starting chaincode containers..."

# Remove old ones if any
docker rm -f healthcare-cc-org1 healthcare-cc-org2 2>/dev/null || true

# Start chaincode container for Org1
docker run -d --name healthcare-cc-org1 \
    --network ohg-network \
    -e CHAINCODE_SERVER_ADDRESS=0.0.0.0:9999 \
    -e CHAINCODE_ID="" \
    healthcare-cc:latest

# Start chaincode container for Org2
docker run -d --name healthcare-cc-org2 \
    --network ohg-network \
    -e CHAINCODE_SERVER_ADDRESS=0.0.0.0:9999 \
    -e CHAINCODE_ID="" \
    healthcare-cc:latest

sleep 3

# ============================================================
# STEP 5: Install on Org1 (Hospital)
# ============================================================
log_info "Installing chaincode on Hospital peer..."
set_org1_env
peer lifecycle chaincode install "${CC_PKG_ORG1}"

ORG1_PKGID=$(peer lifecycle chaincode queryinstalled --output json | jq -r '.installed_chaincodes[0].package_id')
log_success "Installed on Hospital. Package ID: ${ORG1_PKGID}"

# ============================================================
# STEP 6: Install on Org2 (Clinic)
# ============================================================
log_info "Installing chaincode on Clinic peer..."
set_org2_env
peer lifecycle chaincode install "${CC_PKG_ORG2}"

ORG2_PKGID=$(peer lifecycle chaincode queryinstalled --output json | jq -r '.installed_chaincodes[0].package_id')
log_success "Installed on Clinic. Package ID: ${ORG2_PKGID}"

# ============================================================
# STEP 7: Update chaincode containers with package IDs
# ============================================================
log_info "Restarting chaincode containers with package IDs..."

docker rm -f healthcare-cc-org1 healthcare-cc-org2 2>/dev/null || true

docker run -d --name healthcare-cc-org1 \
    --network ohg-network \
    -e CHAINCODE_SERVER_ADDRESS=0.0.0.0:9999 \
    -e CHAINCODE_ID="${ORG1_PKGID}" \
    healthcare-cc:latest

docker run -d --name healthcare-cc-org2 \
    --network ohg-network \
    -e CHAINCODE_SERVER_ADDRESS=0.0.0.0:9999 \
    -e CHAINCODE_ID="${ORG2_PKGID}" \
    healthcare-cc:latest

sleep 3
log_success "Chaincode containers running with correct package IDs."

# ============================================================
# STEP 8: Approve for Org1 (Hospital)
# ============================================================
log_info "Approving chaincode for Hospital org..."
set_org1_env
peer lifecycle chaincode approveformyorg \
    -o "${ORDERER_ADDRESS}" \
    --ordererTLSHostnameOverride "orderer.${DOMAIN}" \
    --tls --cafile "${ORDERER_CA}" \
    --channelID "${CHANNEL_NAME}" \
    --name "${CHAINCODE_NAME}" \
    --version "${CHAINCODE_VERSION}" \
    --package-id "${ORG1_PKGID}" \
    --sequence ${CHAINCODE_SEQUENCE} \
    --signature-policy "AND('OHGHospitalOrgMSP.peer','OHGClinicOrgMSP.peer')" \
    --init-required

log_success "Approved by Hospital org."

# ============================================================
# STEP 9: Approve for Org2 (Clinic)
# ============================================================
log_info "Approving chaincode for Clinic org..."
set_org2_env
peer lifecycle chaincode approveformyorg \
    -o "${ORDERER_ADDRESS}" \
    --ordererTLSHostnameOverride "orderer.${DOMAIN}" \
    --tls --cafile "${ORDERER_CA}" \
    --channelID "${CHANNEL_NAME}" \
    --name "${CHAINCODE_NAME}" \
    --version "${CHAINCODE_VERSION}" \
    --package-id "${ORG2_PKGID}" \
    --sequence ${CHAINCODE_SEQUENCE} \
    --signature-policy "AND('OHGHospitalOrgMSP.peer','OHGClinicOrgMSP.peer')" \
    --init-required

log_success "Approved by Clinic org."

# ============================================================
# STEP 10: Check Commit Readiness
# ============================================================
log_info "Checking commit readiness..."
peer lifecycle chaincode checkcommitreadiness \
    --channelID "${CHANNEL_NAME}" \
    --name "${CHAINCODE_NAME}" \
    --version "${CHAINCODE_VERSION}" \
    --sequence ${CHAINCODE_SEQUENCE} \
    --signature-policy "AND('OHGHospitalOrgMSP.peer','OHGClinicOrgMSP.peer')" \
    --init-required \
    --output json | jq .

# ============================================================
# STEP 11: Commit Chaincode
# ============================================================
log_info "Committing chaincode definition..."
set_org1_env

ORG1_TLS_ROOT="${CRYPTO_PATH}/peerOrganizations/${ORG1_DOMAIN}/peers/peer0.${ORG1_DOMAIN}/tls/ca.crt"
ORG2_TLS_ROOT="${CRYPTO_PATH}/peerOrganizations/${ORG2_DOMAIN}/peers/peer0.${ORG2_DOMAIN}/tls/ca.crt"

peer lifecycle chaincode commit \
    -o "${ORDERER_ADDRESS}" \
    --ordererTLSHostnameOverride "orderer.${DOMAIN}" \
    --tls --cafile "${ORDERER_CA}" \
    --channelID "${CHANNEL_NAME}" \
    --name "${CHAINCODE_NAME}" \
    --version "${CHAINCODE_VERSION}" \
    --sequence ${CHAINCODE_SEQUENCE} \
    --signature-policy "AND('OHGHospitalOrgMSP.peer','OHGClinicOrgMSP.peer')" \
    --init-required \
    --peerAddresses "${ORG1_PEER}" --tlsRootCertFiles "${ORG1_TLS_ROOT}" \
    --peerAddresses "${ORG2_PEER}" --tlsRootCertFiles "${ORG2_TLS_ROOT}"

log_success "Chaincode committed."

# ============================================================
# STEP 12: Initialize Chaincode
# ============================================================
log_info "Initializing chaincode (InitLedger)..."
sleep 3

peer chaincode invoke \
    -o "${ORDERER_ADDRESS}" \
    --ordererTLSHostnameOverride "orderer.${DOMAIN}" \
    --tls --cafile "${ORDERER_CA}" \
    -C "${CHANNEL_NAME}" \
    -n "${CHAINCODE_NAME}" \
    --peerAddresses "${ORG1_PEER}" --tlsRootCertFiles "${ORG1_TLS_ROOT}" \
    --peerAddresses "${ORG2_PEER}" --tlsRootCertFiles "${ORG2_TLS_ROOT}" \
    --isInit -c '{"function":"InitLedger","Args":[]}'

log_success "Chaincode initialized with seed patient records."

# ============================================================
# STEP 13: Verify
# ============================================================
log_info "Querying committed chaincodes..."
peer lifecycle chaincode querycommitted --channelID "${CHANNEL_NAME}" --name "${CHAINCODE_NAME}" --output json | jq .

log_success "============================================="
log_success " Healthcare chaincode deployed successfully!"
log_success " Name: ${CHAINCODE_NAME}"
log_success " Version: ${CHAINCODE_VERSION}"
log_success " Channel: ${CHANNEL_NAME}"
log_success " Policy: AND(Hospital, Clinic)"
log_success " Mode: Chaincode-as-a-Service (CCaaS)"
log_success "============================================="