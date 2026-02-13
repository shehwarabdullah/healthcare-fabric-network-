package main

import (
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/hyperledger/fabric-chaincode-go/shim"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// HealthcareContract implements the healthcare record smart contract
type HealthcareContract struct {
	contractapi.Contract
}

// PatientRecord represents a healthcare patient record on the ledger
type PatientRecord struct {
	DocType       string `json:"docType"`
	RecordID      string `json:"recordID"`
	PatientName   string `json:"patientName"`
	DateOfBirth   string `json:"dateOfBirth"`
	Gender        string `json:"gender"`
	BloodType     string `json:"bloodType"`
	Diagnosis     string `json:"diagnosis"`
	Treatment     string `json:"treatment"`
	Allergies     string `json:"allergies"`
	Medications   string `json:"medications"`
	CreatedBy     string `json:"createdBy"`
	CreatedAt     string `json:"createdAt"`
	LastUpdatedBy string `json:"lastUpdatedBy"`
	LastUpdatedAt string `json:"lastUpdatedAt"`
	Status        string `json:"status"` // active, discharged, transferred
}

// InitLedger seeds the ledger with sample patient records
func (hc *HealthcareContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
	records := []PatientRecord{
		{
			DocType:     "patientRecord",
			RecordID:    "PAT-001",
			PatientName: "Ahmad Khan",
			DateOfBirth: "1985-03-15",
			Gender:      "Male",
			BloodType:   "O+",
			Diagnosis:   "Type 2 Diabetes",
			Treatment:   "Metformin 500mg, lifestyle counseling",
			Allergies:   "Penicillin",
			Medications: "Metformin",
			CreatedBy:   "OHGHospitalOrg",
			CreatedAt:   time.Now().UTC().Format(time.RFC3339),
			Status:      "active",
		},
		{
			DocType:     "patientRecord",
			RecordID:    "PAT-002",
			PatientName: "Fatima Ali",
			DateOfBirth: "1990-07-22",
			Gender:      "Female",
			BloodType:   "A+",
			Diagnosis:   "Hypertension Stage 1",
			Treatment:   "Amlodipine 5mg, dietary changes",
			Allergies:   "None",
			Medications: "Amlodipine",
			CreatedBy:   "OHGClinicOrg",
			CreatedAt:   time.Now().UTC().Format(time.RFC3339),
			Status:      "active",
		},
	}

	for _, record := range records {
		record.LastUpdatedBy = record.CreatedBy
		record.LastUpdatedAt = record.CreatedAt
		recordJSON, err := json.Marshal(record)
		if err != nil {
			return fmt.Errorf("failed to marshal record %s: %v", record.RecordID, err)
		}
		err = ctx.GetStub().PutState(record.RecordID, recordJSON)
		if err != nil {
			return fmt.Errorf("failed to put record %s: %v", record.RecordID, err)
		}
	}

	return nil
}

// CreateRecord creates a new patient health record
func (hc *HealthcareContract) CreateRecord(
	ctx contractapi.TransactionContextInterface,
	recordID string,
	patientName string,
	dateOfBirth string,
	gender string,
	bloodType string,
	diagnosis string,
	treatment string,
	allergies string,
	medications string,
) error {
	// Check if record already exists
	existing, err := ctx.GetStub().GetState(recordID)
	if err != nil {
		return fmt.Errorf("failed to read from world state: %v", err)
	}
	if existing != nil {
		return fmt.Errorf("patient record %s already exists", recordID)
	}

	// Get the invoking org's MSP ID
	clientMSPID, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil {
		return fmt.Errorf("failed to get client MSPID: %v", err)
	}

	now := time.Now().UTC().Format(time.RFC3339)
	record := PatientRecord{
		DocType:       "patientRecord",
		RecordID:      recordID,
		PatientName:   patientName,
		DateOfBirth:   dateOfBirth,
		Gender:        gender,
		BloodType:     bloodType,
		Diagnosis:     diagnosis,
		Treatment:     treatment,
		Allergies:     allergies,
		Medications:   medications,
		CreatedBy:     clientMSPID,
		CreatedAt:     now,
		LastUpdatedBy: clientMSPID,
		LastUpdatedAt: now,
		Status:        "active",
	}

	recordJSON, err := json.Marshal(record)
	if err != nil {
		return fmt.Errorf("failed to marshal record: %v", err)
	}

	return ctx.GetStub().PutState(recordID, recordJSON)
}

// ReadRecord retrieves a patient record by ID
func (hc *HealthcareContract) ReadRecord(
	ctx contractapi.TransactionContextInterface,
	recordID string,
) (*PatientRecord, error) {
	recordJSON, err := ctx.GetStub().GetState(recordID)
	if err != nil {
		return nil, fmt.Errorf("failed to read from world state: %v", err)
	}
	if recordJSON == nil {
		return nil, fmt.Errorf("patient record %s does not exist", recordID)
	}

	var record PatientRecord
	err = json.Unmarshal(recordJSON, &record)
	if err != nil {
		return nil, fmt.Errorf("failed to unmarshal record: %v", err)
	}

	return &record, nil
}

// UpdateRecord updates an existing patient health record
func (hc *HealthcareContract) UpdateRecord(
	ctx contractapi.TransactionContextInterface,
	recordID string,
	diagnosis string,
	treatment string,
	medications string,
	status string,
) error {
	recordJSON, err := ctx.GetStub().GetState(recordID)
	if err != nil {
		return fmt.Errorf("failed to read from world state: %v", err)
	}
	if recordJSON == nil {
		return fmt.Errorf("patient record %s does not exist", recordID)
	}

	var record PatientRecord
	err = json.Unmarshal(recordJSON, &record)
	if err != nil {
		return fmt.Errorf("failed to unmarshal record: %v", err)
	}

	// Get invoking org
	clientMSPID, err := ctx.GetClientIdentity().GetMSPID()
	if err != nil {
		return fmt.Errorf("failed to get client MSPID: %v", err)
	}

	// Update fields
	if diagnosis != "" {
		record.Diagnosis = diagnosis
	}
	if treatment != "" {
		record.Treatment = treatment
	}
	if medications != "" {
		record.Medications = medications
	}
	if status != "" {
		record.Status = status
	}
	record.LastUpdatedBy = clientMSPID
	record.LastUpdatedAt = time.Now().UTC().Format(time.RFC3339)

	updatedJSON, err := json.Marshal(record)
	if err != nil {
		return fmt.Errorf("failed to marshal updated record: %v", err)
	}

	return ctx.GetStub().PutState(recordID, updatedJSON)
}

// GetAllRecords returns all patient records in the world state
func (hc *HealthcareContract) GetAllRecords(
	ctx contractapi.TransactionContextInterface,
) ([]*PatientRecord, error) {
	resultsIterator, err := ctx.GetStub().GetStateByRange("", "")
	if err != nil {
		return nil, fmt.Errorf("failed to get state by range: %v", err)
	}
	defer resultsIterator.Close()

	var records []*PatientRecord
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return nil, fmt.Errorf("failed to iterate: %v", err)
		}
		var record PatientRecord
		err = json.Unmarshal(queryResponse.Value, &record)
		if err != nil {
			return nil, fmt.Errorf("failed to unmarshal: %v", err)
		}
		records = append(records, &record)
	}

	return records, nil
}

// QueryRecordsByDiagnosis uses CouchDB rich query to find records by diagnosis
func (hc *HealthcareContract) QueryRecordsByDiagnosis(
	ctx contractapi.TransactionContextInterface,
	diagnosis string,
) ([]*PatientRecord, error) {
	queryString := fmt.Sprintf(`{"selector":{"docType":"patientRecord","diagnosis":"%s"}}`, diagnosis)

	resultsIterator, err := ctx.GetStub().GetQueryResult(queryString)
	if err != nil {
		return nil, fmt.Errorf("failed to execute rich query: %v", err)
	}
	defer resultsIterator.Close()

	var records []*PatientRecord
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return nil, fmt.Errorf("failed to iterate: %v", err)
		}
		var record PatientRecord
		err = json.Unmarshal(queryResponse.Value, &record)
		if err != nil {
			return nil, fmt.Errorf("failed to unmarshal: %v", err)
		}
		records = append(records, &record)
	}

	return records, nil
}

// GetRecordHistory returns the full modification history for a patient record
func (hc *HealthcareContract) GetRecordHistory(
	ctx contractapi.TransactionContextInterface,
	recordID string,
) (string, error) {
	historyIterator, err := ctx.GetStub().GetHistoryForKey(recordID)
	if err != nil {
		return "", fmt.Errorf("failed to get history for %s: %v", recordID, err)
	}
	defer historyIterator.Close()

	type HistoryEntry struct {
		TxID      string         `json:"txId"`
		Timestamp string         `json:"timestamp"`
		IsDelete  bool           `json:"isDelete"`
		Record    *PatientRecord `json:"record,omitempty"`
	}

	var history []HistoryEntry
	for historyIterator.HasNext() {
		modification, err := historyIterator.Next()
		if err != nil {
			return "", fmt.Errorf("failed to iterate history: %v", err)
		}

		entry := HistoryEntry{
			TxID:      modification.TxId,
			Timestamp: time.Unix(modification.Timestamp.Seconds, int64(modification.Timestamp.Nanos)).UTC().Format(time.RFC3339),
			IsDelete:  modification.IsDelete,
		}

		if !modification.IsDelete {
			var record PatientRecord
			if err := json.Unmarshal(modification.Value, &record); err == nil {
				entry.Record = &record
			}
		}
		history = append(history, entry)
	}

	historyJSON, err := json.Marshal(history)
	if err != nil {
		return "", fmt.Errorf("failed to marshal history: %v", err)
	}

	return string(historyJSON), nil
}

func main() {
	chaincode, err := contractapi.NewChaincode(&HealthcareContract{})
	if err != nil {
		fmt.Printf("Error creating One Health Global healthcare chaincode: %v\n", err)
		return
	}

	// Check if running in CCaaS (Chaincode-as-a-Service) mode
	ccAddr := os.Getenv("CHAINCODE_SERVER_ADDRESS")
	ccID := os.Getenv("CHAINCODE_ID")
	if ccAddr != "" {
		// Run as external chaincode server (CCaaS mode)
		server := &shim.ChaincodeServer{
			CCID:    ccID,
			Address: ccAddr,
			CC:      chaincode,
			TLSProps: shim.TLSProperties{
				Disabled: true,
			},
		}
		fmt.Printf("Starting chaincode server at %s with CCID=%s\n", ccAddr, ccID)
		if err := server.Start(); err != nil {
			fmt.Printf("Error starting chaincode server: %v\n", err)
		}
	} else {
		// Run in traditional mode (peer manages lifecycle)
		if err := chaincode.Start(); err != nil {
			fmt.Printf("Error starting One Health Global healthcare chaincode: %v\n", err)
		}
	}
}