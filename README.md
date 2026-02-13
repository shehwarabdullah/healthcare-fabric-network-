# One Health Global — Hyperledger Fabric Healthcare Blockchain Network

## Overview

Production-grade Hyperledger Fabric v2.5 test network for **One Health Global**, a healthcare records platform. This network implements a permissioned blockchain for secure, auditable patient health record management across two healthcare organizations.

### Network Architecture

| Component | Details |
|---|---|
| **Organizations** | `OHGHospitalOrg` (Org1), `OHGClinicOrg` (Org2) |
| **Ordering Service** | 1 Raft node (`orderer.onehealthglobal.com`) |
| **Peers** | 1 peer per org |
| **State Database** | CouchDB per peer |
| **TLS** | Enabled on all communications |
| **CA Hierarchy** | Root CA → Intermediate CA per org |
| **Key Management** | HashiCorp Vault integration |
| **Channel** | `healthchannel` |
| **Chaincode** | `healthcare` (Go) — Create/Read/Update patient records |
| **Explorer** | Hyperledger Explorer branded for One Health Global |

### Domain Structure

```
onehealthglobal.com
├── orderer.onehealthglobal.com
├── hospital.onehealthglobal.com       (OHGHospitalOrg / Org1)
│   ├── peer0.hospital.onehealthglobal.com
│   └── ca.hospital.onehealthglobal.com
├── clinic.onehealthglobal.com          (OHGClinicOrg / Org2)
│   ├── peer0.clinic.onehealthglobal.com
│   └── ca.clinic.onehealthglobal.com
└── explorer.onehealthglobal.com
```

---

## Prerequisites

- Docker Engine >= 20.10
- Docker Compose >= 2.0
- Go >= 1.20 (for chaincode development)
- `jq`, `curl`
- Hyperledger Fabric binaries v2.5.x (`peer`, `configtxgen`, `cryptogen`, `osnadmin`, `fabric-ca-client`)

```bash
# Download Fabric binaries
curl -sSLO https://raw.githubusercontent.com/hyperledger/fabric/main/scripts/install-fabric.sh
chmod +x install-fabric.sh
./install-fabric.sh binary
export PATH=$PWD/bin:$PATH
```

---

## Quick Start

```bash
# 1. Generate all crypto material and channel artifacts
cd scripts/
chmod +x *.sh
./start-network.sh       # Does everything: crypto, channel, chaincode, explorer

# --- OR step by step ---

# 1. Generate crypto material (CA-based)
./generate-crypto.sh

# 2. Generate channel artifacts
./generate-channel.sh

# 3. Start all containers
./start-network.sh

# 4. Create channel and join peers
./create-channel.sh

# 5. Deploy chaincode
./deploy-chaincode.sh

# 6. Run sample transactions (3+ from each org)
./test-transactions.sh

# 7. Start Explorer
docker compose -f ../docker/explorer/docker-compose-explorer.yaml up -d
# Open http://localhost:8080 (admin / adminpw)

# 8. Channel config update demo
./channel-config-update.sh

# 9. Admin cert rotation demo
./rotate-admin-cert.sh
```

---

## Tear Down

```bash
./scripts/teardown.sh
```

---

## Repository Structure

```
onehealthglobal-fabric/
├── README.md
├── configtx/
│   └── configtx.yaml
├── chaincode/
│   └── healthcare/go/
│       ├── go.mod
│       ├── go.sum
│       ├── healthcare.go
│       └── healthcare_test.go
├── docker/
│   ├── ca/docker-compose-ca.yaml
│   ├── orderer/docker-compose-orderer.yaml
│   ├── org1/docker-compose-org1.yaml
│   ├── org2/docker-compose-org2.yaml
│   ├── vault/docker-compose-vault.yaml
│   └── explorer/docker-compose-explorer.yaml
├── explorer/
│   ├── config.json
│   └── connection-profile.json
├── kubernetes/
│   ├── base/
│   ├── org1/
│   ├── org2/
│   ├── orderer/
│   ├── explorer/
│   ├── vault/
│   └── ca/
├── channel-artifacts/
├── scripts/
│   ├── env.sh
│   ├── generate-crypto.sh
│   ├── generate-channel.sh
│   ├── start-network.sh
│   ├── create-channel.sh
│   ├── deploy-chaincode.sh
│   ├── test-transactions.sh
│   ├── channel-config-update.sh
│   ├── rotate-admin-cert.sh
│   ├── vault-init.sh
│   └── teardown.sh
└── docs/
    └── OPERATIONS.md
```

## Endorsement Policy

All chaincode invocations require endorsement from **both** organizations:

```
AND('OHGHospitalOrgMSP.peer', 'OHGClinicOrgMSP.peer')
```

## License

Proprietary — One Health Global 2025
