#!/usr/bin/env bash
# Local llama.cpp provider adapter for pos-ai
# Provider-specific: API call via OpenAI-compatible /v1/chat/completions
# Part of the R8 provider-agnostic architecture (lib/ai-providers/).

# Provider-specific config variables (auto-discovered by pos config ai):
# PROVIDER_CONFIG: LLAMACPP_MODEL=:Default model path (GGUF file)

provider_name() { printf 'Local llama.cpp'; }

provider_default_model() {
    local port="${LLAMACPP_PORT:-8088}"
    local model
    model="$(curl -sf "http://127.0.0.1:$port/v1/models" 2>/dev/null | jq -r '.data[0].id // empty')"
    [ -n "$model" ] && printf '%s' "$model" || printf '(no model loaded)'
}

# $1=model  $2=messages JSON ({"messages":[{role,content}]})  $3=optional system prompt
provider_generate() {
    local model="$1" messages="$2" system="${3:-}" port="${LLAMACPP_PORT:-8088}"
    local body resp code body_out
    # Build messages array with optional system prompt
    if [ -n "$system" ]; then
        body="$(printf '%s' "$messages" | jq -c --arg s "$system" \
            '[{role:"system",content:$s}] + .messages')"
    else
        body="$(printf '%s' "$messages" | jq -c '.messages')"
    fi
    body="$(printf '%s' "$body" | jq -nc --arg m "$model" --argjson msgs "$body" \
        '{model:$m, messages:$msgs, stream:false}')"
    resp="$(curl -sS -m 120 -X POST "http://127.0.0.1:$port/v1/chat/completions" \
        -H "Content-Type: application/json" \
        --write-out $'\n%{http_code}' \
        --data "$body")" || { echo "request failed (curl exit $?)" >&2; return 1; }
    code="${resp##*$'\n'}"
    body_out="${resp%$'\n'*}"
    if [ "$code" != "200" ]; then
        echo "API error $code" >&2
        return 1
    fi
    printf '%s' "$body_out" | jq -r '.choices[0].message.content // ""'
}

# $1=current default model  → stdout=formatted model list
provider_models_list() {
    local model="$1" port="${LLAMACPP_PORT:-8088}" resp code body
    resp="$(curl -sf "http://127.0.0.1:$port/v1/models" \
        --write-out $'\n%{http_code}')" || { echo "server not running" >&2; return 1; }
    code="${resp##*$'\n'}"
    body="${resp%$'\n'*}"
    [ "$code" = "200" ] || { echo "API error $code" >&2; return 1; }
    echo "Local llama.cpp models:"
    printf '%s' "$body" | jq -r '.data[]? | .id' | while IFS= read -r m; do
        [ -n "$m" ] || continue
        if [ "$m" = "$model" ]; then
            printf '  %-48s <- loaded\n' "$m"
        else
            printf '  %-48s\n' "$m"
        fi
    done
}
