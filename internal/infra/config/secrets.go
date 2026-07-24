package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

var secretsDir = "/run/secrets"

func ReadSecret(name string) (string, error) {
	if filepath.Base(name) != name {
		return "", fmt.Errorf("invalid secret name: %q", name)
	}
	data, err := os.ReadFile(filepath.Join(secretsDir, name))
	if err != nil {
		return "", fmt.Errorf("read docker secret %s: %w", name, err)
	}
	return strings.TrimSpace(string(data)), nil
}
