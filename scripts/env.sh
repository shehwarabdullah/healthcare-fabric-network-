#!/bin/bash
# One Health Global — Shared Environment Variables

export PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export FABRIC_CFG_PATH="${PROJECT_ROOT}/config"
export FABRIC_CFG_PATH="${PROJECT_ROOT}/config"
export FABRIC_CFG_PATH="${PROJECT_ROOT}/config"
export CHANNEL_NAME="healthchannel"
export CHAINCODE_NAME="healthcare"
export CHAINCODE_VERSION="1.0"
export CHAINCODE_SEQUENCE=2
export CHAINCODE_PATH="${PROJECT_ROOT}/chaincode/healthcare/go"

# Organization MSP IDs
export ORG1_MSPID="OHGHospitalOrgMSP"
export ORG2_MSPID="OHGClinicOrgMSP"
export ORDERER_MSPID="OHGOrdererOrgMSP"

# Domain names
export DOMAIN="onehealthglobal.com"
export ORG1_DOMAIN="hospital.${DOMAIN}"
export ORG2_DOMAIN="clinic.${DOMAIN}"
export ORDERER_DOMAIN="${DOMAIN}"

# Crypto paths
export CRYPTO_PATH="${PROJECT_ROOT}/organizations"
export ORDERER_CA="${CRYPTO_PATH}/ordererOrganizations/${DOMAIN}/orderers/orderer.${DOMAIN}/tls/ca.crt"
export ORDERER_ADMIN_TLS_SIGN_CERT="${CRYPTO_PATH}/ordererOrganizations/${DOMAIN}/orderers/orderer.${DOMAIN}/tls/server.crt"
export ORDERER_ADMIN_TLS_PRIVATE_KEY="${CRYPTO_PATH}/ordererOrganizations/${DOMAIN}/orderers/orderer.${DOMAIN}/tls/server.key"

# Peer addresses
export ORG1_PEER="peer0.${ORG1_DOMAIN}:7051"
export ORG2_PEER="peer0.${ORG2_DOMAIN}:9051"
export ORDERER_ADDRESS="orderer.${DOMAIN}:7050"

# CA Addresses
export CA_HOSPITAL_PORT=7054
export CA_CLINIC_PORT=8054
export CA_ORDERER_PORT=9054

# Vault
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="ohg-vault-root-token"

# Colors for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[OHG-INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OHG-OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[OHG-WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[OHG-ERROR]${NC} $1"
}

# Set peer environment for Org1 (Hospital)
set_org1_env() {
    export CORE_PEER_TLS_ENABLED=true
    export CORE_PEER_LOCALMSPID="${ORG1_MSPID}"
    export CORE_PEER_TLS_ROOTCERT_FILE="${CRYPTO_PATH}/peerOrganizations/${ORG1_DOMAIN}/peers/peer0.${ORG1_DOMAIN}/tls/ca.crt"
    export CORE_PEER_MSPCONFIGPATH="${CRYPTO_PATH}/peerOrganizations/${ORG1_DOMAIN}/users/Admin@${ORG1_DOMAIN}/msp"
    export CORE_PEER_ADDRESS="${ORG1_PEER}"
}

# Set peer environment for Org2 (Clinic)
set_org2_env() {
    export CORE_PEER_TLS_ENABLED=true
    export CORE_PEER_LOCALMSPID="${ORG2_MSPID}"
    export CORE_PEER_TLS_ROOTCERT_FILE="${CRYPTO_PATH}/peerOrganizations/${ORG2_DOMAIN}/peers/peer0.${ORG2_DOMAIN}/tls/ca.crt"
    export CORE_PEER_MSPCONFIGPATH="${CRYPTO_PATH}/peerOrganizations/${ORG2_DOMAIN}/users/Admin@${ORG2_DOMAIN}/msp"
    export CORE_PEER_ADDRESS="${ORG2_PEER}"
}