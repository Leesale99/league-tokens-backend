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
          "id": "deepseek-v4-flash",
          "name": "DeepSeek V4 Flash",
          "reasoning": true,
          "input": ["text"],
          "cost": {"input": 0.14, "output": 0.28, "cacheRead": 0, "cacheWrite": 0},
          "compat": {
            "supportsStore": false,
            "supportsDeveloperRole": false,
            "maxTokensField": "max_tokens",
            "requiresReasoningContentOnAssistantMessages": true,
            "thinkingFormat": "deepseek"
          },
          "contextWindow": 1000000,
          "maxTokens": 384000,
          "thinkingLevelMap": {
            "minimal": null,
            "low": null,
            "medium": null,
            "high": "high",
            "xhigh": null,
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
# thinking_level: high). Set PI_FAIL_FAST=1 for jobs that want GitHub Actions
# to be the retry boundary. The provider timeout matches review.yml's shell
# deadline; the shell timeout remains the final enforcement point if a provider
# ignores its own setting.
SETTINGS_PATH=~/.pi/agent/settings.json
if [ "${PI_FAIL_FAST:-0}" = "1" ]; then
  SETTINGS_FILTER='
    .defaultThinkingLevel = "high" |
    .retry.enabled = false |
    .retry.maxRetries = 0 |
    .retry.provider.maxRetries = 0 |
    .retry.provider.timeoutMs = 540000
  '
  DEFAULT_SETTINGS='{
  "defaultThinkingLevel": "high",
  "retry": {
    "enabled": false,
    "maxRetries": 0,
    "provider": {
      "maxRetries": 0,
      "timeoutMs": 540000
    }
  }
}'
else
  SETTINGS_FILTER='.defaultThinkingLevel = "high"'
  DEFAULT_SETTINGS='{"defaultThinkingLevel": "high"}'
fi

if [ -f "$SETTINGS_PATH" ]; then
  # Fail loudly on a corrupt existing settings file: without the explicit
  # check, jq would leave a stale .tmp and the old settings in place.
  if ! jq "$SETTINGS_FILTER" "$SETTINGS_PATH" > "${SETTINGS_PATH}.tmp"; then
    rm -f "${SETTINGS_PATH}.tmp"
    echo "::error::cannot parse $SETTINGS_PATH"
    exit 1
  fi
  mv "${SETTINGS_PATH}.tmp" "$SETTINGS_PATH"
else
  printf '%s\n' "$DEFAULT_SETTINGS" > "$SETTINGS_PATH"
fi
