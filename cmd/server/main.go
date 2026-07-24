package main

import (
	"log"

	"github.com/Leesale99/league-tokens-backend/internal/infra/config"
)

func main() {
	cfg := config.MustLoad()
	_ = cfg
	log.Println("starting with valid config")
}
