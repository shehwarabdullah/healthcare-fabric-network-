#!/bin/bash
# One Health Global — Test Transactions
# Demonstrates 3+ transactions from EACH organization identity
set -e
source "$(dirname "$0")/env.sh"

log_info "============================================="
log_info " One Health Global — Transaction Demonstration"
log_info " 3+ transactions from each org identity"
log_info "============================================="

ORG1_TLS_ROOT="${CRYPTO_PATH}/peerOrganizations/${ORG1_DOMAIN}/peers/peer0.${ORG1_DOMAIN}/tls/ca.crt"
ORG2_TLS_ROOT="${CRYPTO_PATH}/peerOrganizations/${ORG2_DOMAIN}/peers/peer0.${ORG2_DOMAIN}/tls/ca.crt"

INVOKE_ARGS="-o ${ORDERER_ADDRESS} --ordererTLSHostnameOverride orderer.${DOMAIN} --tls --cafile ${ORDERER_CA} -C ${CHANNEL_NAME} -n ${CHAINCODE_NAME} --peerAddresses ${ORG1_PEER} --tlsRootCertFiles ${ORG1_TLS_ROOT} --peerAddresses ${ORG2_PEER} --tlsRootCertFiles ${ORG2_TLS_ROOT}"

TX_COUNT=0

# ============================================================
# HOSPITAL ORG (Org1) — 3 Transactions
# ============================================================
set_org1_env
log_info "--- Hospital Org Transactions ---"

# TX1: Create patient record
log_info "[Hospital TX-1] Creating patient PAT-H001..."
peer chaincode invoke ${INVOKE_ARGS} \
    -c '{"function":"CreateRecord","Args":["PAT-H001","Usman Malik","1978-11-03","Male","B+","Chronic Kidney Disease Stage 2","Losartan 50mg, low-sodium diet","Sulfa drugs","Losartan, Calcium Carbonate"]}'
TX_COUNT=$((TX_COUNT+1))
sleep 2

# TX2: Create another patient
log_info "[Hospital TX-2] Creating patient PAT-H002..."
peer chaincode invoke ${INVOKE_ARGS} \
    -c '{"function":"CreateRecord","Args":["PAT-H002","Ayesha Siddiqui","1992-04-18","Female","AB+","Gestational Diabetes","Insulin therapy, blood sugar monitoring","None known","Insulin Glargine"]}'
TX_COUNT=$((TX_COUNT+1))
sleep 2

# TX3: Update existing patient record
log_info "[Hospital TX-3] Updating patient PAT-001 diagnosis..."
peer chaincode invoke ${INVOKE_ARGS} \
    -c '{"function":"UpdateRecord","Args":["PAT-001","Type 2 Diabetes - Controlled","Metformin 500mg + Sitagliptin 100mg","Metformin, Sitagliptin","active"]}'
TX_COUNT=$((TX_COUNT+1))
sleep 2

# Query to verify
log_info "[Hospital QUERY] Reading patient PAT-H001..."
peer chaincode query -C "${CHANNEL_NAME}" -n "${CHAINCODE_NAME}" \
    -c '{"function":"ReadRecord","Args":["PAT-H001"]}' | jq .

log_success "Hospital completed ${TX_COUNT} transactions."

# ============================================================
# CLINIC ORG (Org2) — 3 Transactions
# ============================================================
set_org2_env
log_info "--- Clinic Org Transactions ---"

# TX4: Create patient record
log_info "[Clinic TX-1] Creating patient PAT-C001..."
peer chaincode invoke ${INVOKE_ARGS} \
    -c '{"function":"CreateRecord","Args":["PAT-C001","Bilal Ahmed","1965-08-20","Male","O-","Coronary Artery Disease","Atorvastatin 40mg, Aspirin 75mg, cardiac rehab","Iodine contrast","Atorvastatin, Aspirin, Metoprolol"]}'
TX_COUNT=$((TX_COUNT+1))
sleep 2

# TX5: Create another patient
log_info "[Clinic TX-2] Creating patient PAT-C002..."
peer chaincode invoke ${INVOKE_ARGS} \
    -c '{"function":"CreateRecord","Args":["PAT-C002","Nadia Hussain","1988-12-05","Female","A-","Asthma - Moderate Persistent","Fluticasone/Salmeterol inhaler, rescue inhaler","Aspirin, NSAIDs","Fluticasone, Salmeterol, Albuterol"]}'
TX_COUNT=$((TX_COUNT+1))
sleep 2

# TX6: Update patient from Hospital (cross-org update)
log_info "[Clinic TX-3] Updating patient PAT-H002 status..."
peer chaincode invoke ${INVOKE_ARGS} \
    -c '{"function":"UpdateRecord","Args":["PAT-H002","Gestational Diabetes - Post-delivery resolved","Monitoring only, no medication","None","discharged"]}'
TX_COUNT=$((TX_COUNT+1))
sleep 2

# Query to verify
log_info "[Clinic QUERY] Reading patient PAT-C001..."
peer chaincode query -C "${CHANNEL_NAME}" -n "${CHAINCODE_NAME}" \
    -c '{"function":"ReadRecord","Args":["PAT-C001"]}' | jq .

log_success "Clinic completed 3 transactions."

# ============================================================
# Cross-verification queries
# ============================================================
log_info "--- Cross-Verification ---"

log_info "Getting all records from Hospital peer..."
set_org1_env
peer chaincode query -C "${CHANNEL_NAME}" -n "${CHAINCODE_NAME}" \
    -c '{"function":"GetAllRecords","Args":[]}' | jq '.[] | {recordID, patientName, status, createdBy, lastUpdatedBy}'

log_info "Getting record history for PAT-001 (modified by Hospital)..."
peer chaincode query -C "${CHANNEL_NAME}" -n "${CHAINCODE_NAME}" \
    -c '{"function":"GetRecordHistory","Args":["PAT-001"]}' | jq .

log_info "Querying by diagnosis from Clinic peer..."
set_org2_env
peer chaincode query -C "${CHANNEL_NAME}" -n "${CHAINCODE_NAME}" \
    -c '{"function":"QueryRecordsByDiagnosis","Args":["Coronary Artery Disease"]}' | jq .

log_success "============================================="
log_success " Transaction Demonstration Complete!"
log_success " Total Transactions: ${TX_COUNT}"
log_success "   Hospital (Org1): 3 transactions"
log_success "   Clinic   (Org2): 3 transactions"
log_success " Records Created: PAT-H001, PAT-H002, PAT-C001, PAT-C002"
log_success " Records Updated: PAT-001, PAT-H002"
log_success "============================================="
