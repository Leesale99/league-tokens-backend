#!/usr/bin/env bash
# Shared provider configuration for opencode-go custom provider.
# Writes ~/.pi/agent/models.json with all available models.
# Individual workflows select the model at runtime via the `model` input.
set -euo pipefail

mkdir -p ~/.pi/agent
cat > ~/.pi/agent/models.json << 'MODELS_EOF'
{
  "providers": {
    "opencode-go": {
      "baseUrl": "https://opencode.ai/zen/go/v1",
      "api": "openai-completions",
      "models": [
        {
          "id": "gpt-5.6-luna",
          "name": "GPT-5.6 Luna",
          "reasoning": true,
          "input": ["text"],
          "cost": {"input": 0.20, "output": 1.20, "cacheRead": 0.02, "cacheWrite": 0},
          "compat": {
            "supportsStore": false,
            "supportsDeveloperRole": true,
            "supportsReasoningEffort": true,
            "maxTokensField": "max_tokens"
          },
          "contextWindow": 1000000,
          "maxTokens": 384000,
          "thinkingLevelMap": {
            "minimal": null,
            "low": null,
            "medium": null,
            "high": "high",
            "xhigh": "high",
            "max": "max"
          }
        }
      ]
    }
  }
}
MODELS_EOF

# Default thinking level for all pi invocations unless a job overrides it
# explicitly (review.yml passes --thinking high; the code-agent action passes
# thinking_level: high). Kept merge-safe so we never clobber a runner's
# existing global settings.
if [ -f ~/.pi/agent/settings.json ]; then
  jq '.defaultThinkingLevel = "high"' ~/.pi/agent/settings.json > ~/.pi/agent/settings.json.tmp && \
    mv ~/.pi/agent/settings.json.tmp ~/.pi/agent/settings.json
else
  echo '{"defaultThinkingLevel": "high"}' > ~/.pi/agent/settings.json
fi
