package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestReadSecret(t *testing.T) {
	dir := t.TempDir()
	origDir := secretsDir
	secretsDir = dir
	defer func() { secretsDir = origDir }()

	tests := []struct {
		name    string
		content string
		want    string
		wantErr bool
	}{
		{
			name:    "valid secret",
			content: "my-secret-value",
			want:    "my-secret-value",
		},
		{
			name:    "trailing newline",
			content: "my-secret-value\n",
			want:    "my-secret-value",
		},
		{
			name:    "trailing whitespace",
			content: "my-secret-value  \n",
			want:    "my-secret-value",
		},
		{
			name:    "empty file",
			content: "",
			want:    "",
		},
		{
			name:    "whitespace only",
			content: "  \n\n",
			want:    "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if err := os.WriteFile(filepath.Join(dir, tt.name), []byte(tt.content), 0644); err != nil {
				t.Fatal(err)
			}
			got, err := ReadSecret(tt.name)
			if (err != nil) != tt.wantErr {
				t.Errorf("ReadSecret() error = %v, wantErr = %v", err, tt.wantErr)
				return
			}
			if got != tt.want {
				t.Errorf("ReadSecret() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestReadSecret_MissingFile(t *testing.T) {
	origDir := secretsDir
	secretsDir = t.TempDir()
	defer func() { secretsDir = origDir }()

	_, err := ReadSecret("nonexistent")
	if err == nil {
		t.Fatal("ReadSecret() expected error for missing file, got nil")
	}
}

func TestReadSecret_PathTraversal(t *testing.T) {
	origDir := secretsDir
	secretsDir = t.TempDir()
	defer func() { secretsDir = origDir }()

	_, err := ReadSecret("/etc/passwd")
	if err == nil {
		t.Fatal("ReadSecret() expected error for path traversal, got nil")
	}
}

func TestReadSecret_DotDot(t *testing.T) {
	origDir := secretsDir
	secretsDir = t.TempDir()
	defer func() { secretsDir = origDir }()

	_, err := ReadSecret("../../etc/passwd")
	if err == nil {
		t.Fatal("ReadSecret() expected error for .. traversal, got nil")
	}
}
