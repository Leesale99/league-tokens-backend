package application

import "testing"

// The ledger context has no env-driven config yet; these tests lock the no-op
// contract so accidental breakage surfaces when fields are added later.
func TestParseConfig(t *testing.T) {
	cfg, err := ParseConfig()
	if err != nil {
		t.Fatalf("ParseConfig() error = %v", err)
	}
	if cfg == nil {
		t.Fatal("ParseConfig() returned nil")
	}
	if err := cfg.Validate(); err != nil {
		t.Errorf("Validate() error = %v, want nil", err)
	}
}
