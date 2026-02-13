package main

import (
	"encoding/json"
	"testing"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// Basic struct test — full integration tests require mock stubs
func TestPatientRecordSerialization(t *testing.T) {
	record := PatientRecord{
		DocType:     "patientRecord",
		RecordID:    "PAT-TEST-001",
		PatientName: "Test Patient",
		DateOfBirth: "2000-01-01",
		Gender:      "Male",
		BloodType:   "B+",
		Diagnosis:   "Common Cold",
		Treatment:   "Rest and fluids",
		Allergies:   "None",
		Medications: "Paracetamol",
		CreatedBy:   "OHGHospitalOrgMSP",
		CreatedAt:   "2025-01-01T00:00:00Z",
		Status:      "active",
	}

	// Test serialization
	data, err := json.Marshal(record)
	if err != nil {
		t.Fatalf("Failed to marshal PatientRecord: %v", err)
	}

	// Test deserialization
	var decoded PatientRecord
	err = json.Unmarshal(data, &decoded)
	if err != nil {
		t.Fatalf("Failed to unmarshal PatientRecord: %v", err)
	}

	if decoded.RecordID != "PAT-TEST-001" {
		t.Errorf("Expected RecordID PAT-TEST-001, got %s", decoded.RecordID)
	}
	if decoded.PatientName != "Test Patient" {
		t.Errorf("Expected PatientName Test Patient, got %s", decoded.PatientName)
	}
	if decoded.Status != "active" {
		t.Errorf("Expected Status active, got %s", decoded.Status)
	}
	if decoded.DocType != "patientRecord" {
		t.Errorf("Expected DocType patientRecord, got %s", decoded.DocType)
	}
}

func TestHealthcareContractImplementsInterface(t *testing.T) {
	// Verify the contract satisfies the contractapi interface
	var _ contractapi.ContractInterface = &HealthcareContract{}
}
