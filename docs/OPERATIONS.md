# One Health Global — Operations Guide

## Table of Contents

1. [Network Startup](#1-network-startup)
2. [Channel Creation & Peer Joining](#2-channel-creation--peer-joining)
3. [Chaincode Deployment](#3-chaincode-deployment)
4. [Admin Certificate Rotation](#4-admin-certificate-rotation)
5. [Vault Key Management](#5-vault-key-management)
6. [Kubernetes Deployment](#6-kubernetes-deployment)
7. [Explorer Dashboard](#7-explorer-dashboard)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. Network Startup

### Prerequisites

Ensure the following are installed:

```bash
# Verify prerequisites
docker --version          # >= 20.10
docker compose version    # >= 2.0
go version                # >= 1.20
peer version              # Fabric 2.5.x
configtxgen -version      # Fabric 2.5.x
```

### Quick Start (All-in-One)

```bash
cd onehealthglobal-fabric/scripts
chmod +x *.sh
./start-network.sh
./create-channel.sh
./deploy-chaincode.sh
./test-transactions.sh
```

### Manual Step-by-Step

**Step 1: Generate Crypto Material**

The `generate-crypto.sh` script uses Fabric CAs (not cryptogen) to create a proper CA hierarchy:

- **Root CA** (`ca.root.onehealthglobal.com:7054`) — Trust anchor
- **Hospital Intermediate CA** (`ca.hospital.onehealthglobal.com:7055`) — Issues Hospital org identities
- **Clinic Intermediate CA** (`ca.clinic.onehealthglobal.com:8055`) — Issues Clinic org identities
- **Orderer CA** (`ca.orderer.onehealthglobal.com:9054`) — Issues orderer identities

```bash
./generate-crypto.sh
```

This script:
1. Starts all CA containers
2. Copies Root CA TLS cert to intermediate CAs
3. Enrolls each org's admin, peer, and user identities
4. Creates proper NodeOUs configuration for role-based access
5. Sets up TLS certificates for all nodes

**Step 2: Generate Channel Artifacts**

```bash
./generate-channel.sh
```

Creates the genesis block using `configtxgen` with the `OHGOrdererGenesis` profile.

**Step 3: Start Network Components**

```bash
./start-network.sh
```

Starts (in order):
1. Docker network `ohg-network`
2. Orderer node
3. Hospital peer + CouchDB
4. Clinic peer + CouchDB

---

## 2. Channel Creation & Peer Joining

```bash
./create-channel.sh
```

### What This Does

1. **Orderer joins channel** via `osnadmin channel join` (Fabric 2.5 channel participation API)
2. **Hospital peer joins** by fetching the genesis block and calling `peer channel join`
3. **Clinic peer joins** using the same genesis block
4. **Anchor peers set** for both organizations via channel config updates

### Verification

```bash
# Check from Hospital peer
export CORE_PEER_LOCALMSPID=OHGHospitalOrgMSP
# ... (set full env, see env.sh)
peer channel getinfo -c healthchannel

# Check from Clinic peer
export CORE_PEER_LOCALMSPID=OHGClinicOrgMSP
# ...
peer channel getinfo -c healthchannel
```

Both should show the same block height.

---

## 3. Chaincode Deployment

```bash
./deploy-chaincode.sh
```

### Lifecycle Steps (Fabric v2.x)

1. **Package**: `peer lifecycle chaincode package` — Creates `healthcare.tar.gz`
2. **Install on Hospital**: `peer lifecycle chaincode install` — Returns package ID
3. **Install on Clinic**: Same command, different peer context
4. **Approve for Hospital**: `peer lifecycle chaincode approveformyorg` with endorsement policy
5. **Approve for Clinic**: Same, satisfying MAJORITY approval
6. **Commit**: `peer lifecycle chaincode commit` — Both peers endorse
7. **Initialize**: `peer chaincode invoke --isInit` — Seeds ledger with sample records

### Endorsement Policy

```
AND('OHGHospitalOrgMSP.peer', 'OHGClinicOrgMSP.peer')
```

Every transaction requires signatures from peers of **both** organizations.

### Chaincode Functions

| Function | Description | Arguments |
|---|---|---|
| `InitLedger` | Seeds 2 sample patient records | None |
| `CreateRecord` | Creates a new patient record | recordID, patientName, dob, gender, bloodType, diagnosis, treatment, allergies, medications |
| `ReadRecord` | Retrieves a patient record | recordID |
| `UpdateRecord` | Updates diagnosis/treatment/status | recordID, diagnosis, treatment, medications, status |
| `GetAllRecords` | Lists all patient records | None |
| `QueryRecordsByDiagnosis` | CouchDB rich query by diagnosis | diagnosis string |
| `GetRecordHistory` | Full audit trail for a record | recordID |

### Sample Transaction

```bash
# Create record (requires both org endorsement)
peer chaincode invoke \
    -o orderer.onehealthglobal.com:7050 \
    --tls --cafile $ORDERER_CA \
    -C healthchannel -n healthcare \
    --peerAddresses peer0.hospital.onehealthglobal.com:7051 \
    --tlsRootCertFiles $ORG1_TLS \
    --peerAddresses peer0.clinic.onehealthglobal.com:9051 \
    --tlsRootCertFiles $ORG2_TLS \
    -c '{"function":"CreateRecord","Args":["PAT-100","Test Patient","2000-01-01","Male","A+","Flu","Rest","None","Paracetamol"]}'
```

---

## 4. Admin Certificate Rotation

### Overview

Rotating an organization's admin certificate without breaking channel governance. With NodeOUs enabled, admin status is determined by the `admin` OU attribute in the certificate, not by the `admincerts` folder.

### Procedure

```bash
./rotate-admin-cert.sh
```

### Detailed Steps

**Step 1: Register a new admin identity with the organization's CA**

```bash
fabric-ca-client register --caname ca-hospital-ohg \
    --id.name hospitaladmin2 --id.secret hospitaladmin2pw --id.type admin \
    --tls.certfiles $CA_TLS_CERT
```

The `--id.type admin` ensures the certificate will contain the `admin` OU.

**Step 2: Enroll the new admin**

```bash
fabric-ca-client enroll -u https://hospitaladmin2:hospitaladmin2pw@localhost:7055 \
    --caname ca-hospital-ohg -M /path/to/new-admin/msp \
    --tls.certfiles $CA_TLS_CERT
```

**Step 3: Backup current admin credentials**

```bash
cp -r /path/to/current/Admin@hospital.../msp /backup/old-admin-msp
```

**Step 4: Replace admin credentials in the local MSP**

```bash
# Replace signing certificate
cp new-admin/msp/signcerts/*.pem Admin@hospital.../msp/signcerts/cert.pem

# Replace private key
rm Admin@hospital.../msp/keystore/*
cp new-admin/msp/keystore/* Admin@hospital.../msp/keystore/
```

**Step 5: Verify new admin can transact**

```bash
peer chaincode query -C healthchannel -n healthcare \
    -c '{"function":"ReadRecord","Args":["PAT-001"]}'
```

**Step 6: (Optional) Revoke old admin**

```bash
# Revoke through CA
fabric-ca-client revoke --caname ca-hospital-ohg \
    -e hospitaladmin --reason keycompromise \
    --tls.certfiles $CA_TLS_CERT

# Generate CRL and update channel config
fabric-ca-client gencrl --caname ca-hospital-ohg \
    --tls.certfiles $CA_TLS_CERT
```

### Why This Works Without Channel Config Update

- **NodeOUs** are enabled (see `config.yaml` in each MSP)
- The `AdminOUIdentifier` maps the certificate's OU to admin role
- Any certificate issued by the org's CA with `type=admin` is automatically recognized
- No need to manually add certificates to `admincerts` folder or channel config

### When You DO Need a Channel Config Update

- Changing the CA root certificate
- Updating CRLs (Certificate Revocation Lists)
- Modifying MSP structure or policies
- Adding/removing intermediate CAs

---

## 5. Vault Key Management

### Starting Vault

```bash
docker compose -f docker/vault/docker-compose-vault.yaml up -d
./scripts/vault-init.sh
```

### How Keys Are Stored

```
ohg-fabric/
├── orderer/
│   ├── admin/private-key
│   └── tls/private-key
├── hospital/
│   ├── peer0/private-key
│   ├── peer0/tls-key
│   └── admin/private-key
└── clinic/
    ├── peer0/private-key
    ├── peer0/tls-key
    └── admin/private-key
```

### Access Policies

| Policy | Access |
|---|---|
| `ohg-hospital-policy` | Read-only access to `hospital/*` keys |
| `ohg-clinic-policy` | Read-only access to `clinic/*` keys |
| `ohg-orderer-policy` | Read-only access to `orderer/*` keys |

### Retrieving a Key

```bash
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=ohg-vault-root-token
vault kv get ohg-fabric/hospital/admin/private-key
```

### Production Notes

In production, configure Fabric nodes to use Vault via:

1. **Init container** that fetches keys from Vault and mounts them
2. **Vault Agent sidecar** for automatic key rotation
3. **BCCSP plugin** (if using custom HSM integration)

---

## 6. Kubernetes Deployment

### Apply Manifests

```bash
# 1. Create namespace and base config
kubectl apply -f kubernetes/base/namespace.yaml

# 2. Create secrets from crypto material
# (Script to create K8s secrets from generated crypto)
./scripts/k8s-create-secrets.sh

# 3. Deploy CAs
kubectl apply -f kubernetes/ca/ca-deployments.yaml

# 4. Deploy Vault
kubectl apply -f kubernetes/vault/vault-deployment.yaml

# 5. Deploy Orderer
kubectl apply -f kubernetes/orderer/orderer-deployment.yaml

# 6. Deploy Peers
kubectl apply -f kubernetes/org1/peer0-hospital-deployment.yaml
kubectl apply -f kubernetes/org2/peer0-clinic-deployment.yaml

# 7. Deploy Explorer
kubectl apply -f kubernetes/explorer/explorer-deployment.yaml
```

### Verify

```bash
kubectl get pods -n ohg-fabric
kubectl get svc -n ohg-fabric
```

---

## 7. Explorer Dashboard

### Starting Explorer

```bash
docker compose -f docker/explorer/docker-compose-explorer.yaml up -d
```

### Access

- **URL**: http://localhost:8080
- **Username**: admin
- **Password**: adminpw

### What You Should See

After running `test-transactions.sh`:

- **Dashboard**: Block count (8+), transaction count (6+), node count (2 peers)
- **Blocks**: Genesis block + config blocks + transaction blocks
- **Transactions**: All CreateRecord, UpdateRecord, InitLedger invocations
- **Chaincodes**: `healthcare` v1.0 on `healthchannel`
- **Peers**: `peer0.hospital.onehealthglobal.com`, `peer0.clinic.onehealthglobal.com`

---

## 8. Troubleshooting

### Common Issues

**Peer fails to start**
```bash
docker logs peer0.hospital.onehealthglobal.com
# Check MSP path, TLS certs, CouchDB connectivity
```

**Chaincode endorsement fails**
```bash
# Verify both peers have chaincode installed
peer lifecycle chaincode queryinstalled  # for each org
# Verify endorsement policy matches
peer lifecycle chaincode querycommitted --channelID healthchannel
```

**Explorer shows no data**
```bash
# Check connection profile paths
docker logs explorer.onehealthglobal.com
# Verify crypto paths in explorer/connection-profile.json
```

**Channel creation fails**
```bash
# Verify orderer is running and TLS certs are correct
osnadmin channel list -o localhost:7053 \
    --ca-file $ORDERER_CA \
    --client-cert $ORDERER_ADMIN_TLS_SIGN_CERT \
    --client-key $ORDERER_ADMIN_TLS_PRIVATE_KEY
```

### Useful Commands

```bash
# View all running containers
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# Check peer channel membership
peer channel list

# Check installed chaincodes
peer lifecycle chaincode queryinstalled

# View CouchDB (Hospital)
curl http://localhost:5984/_all_dbs -u couchdbadmin:couchdbadminpw

# View CouchDB (Clinic)
curl http://localhost:7984/_all_dbs -u couchdbadmin:couchdbadminpw
```
