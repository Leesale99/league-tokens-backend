#!/usr/bin/env bash
# Shared provider configuration for oc-sdk-go custom provider.
# Writes ~/.pi/agent/models.json with all available models.
# Individual workflows select the model at runtime via the `model` input.
set -euo pipefail

mkdir -p ~/.pi/agent
cat > ~/.pi/agent/models.json << 'MODELS_EOF'
{
  "providers": {
    "oc-sdk-go": {
      "baseUrl": "https://opencode.ai/zen/go/v1",
      "api": "openai-completions",
      "models": [
        {
          "id": "deepseek-v4-pro",
          "name": "DeepSeek V4 Pro",
          "reasoning": true,
          "input": ["text"],
          "cost": {"input": 0.435, "output": 0.87, "cacheRead": 0.003625, "cacheWrite": 0},
          "contextWindow": 1000000,
          "maxTokens": 384000
        },
        {
          "id": "deepseek-v4-flash",
          "name": "DeepSeek V4 Flash",
          "reasoning": true,
          "input": ["text"],
          "cost": {"input": 0.14, "output": 0.28, "cacheRead": 0.0028, "cacheWrite": 0},
          "contextWindow": 1000000,
          "maxTokens": 384000
        }
      ]
    }
  }
}
MODELS_EOF
