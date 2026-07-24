package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

var secretsDir = "/run/secrets"

func ReadSecret(name string) (string, error) {
	data, err := os.ReadFile(filepath.Join(secretsDir, name))
	if err != nil {
		return "", fmt.Errorf("read docker secret %s: %w", name, err)
	}
	return strings.TrimRight(string(data), "\n\r"), nil
}
