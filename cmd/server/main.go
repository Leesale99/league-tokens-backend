package main

import (
	"log/slog"

	"github.com/Leesale99/league-tokens-backend/internal/infra/config"
)

func main() {
	config.MustLoad()
	slog.Info("starting with valid config")
}
