#!/usr/bin/env bash
# OpenRouter provider adapter for pos-ai
# Provider-specific: API call, auth, response parsing, models list
# Part of the R8 provider-agnostic architecture (lib/ai-providers/).

provider_name() { printf 'OpenRouter'; }
provider_default_model() { printf 'openrouter/auto'; }

# $1=model  $2=messages JSON ({"messages":[{role,content}]})  $3=optional system prompt
provider_generate() {
    local model="$1" messages="$2" system="${3:-}" body resp code body_out errmsg
    if [ -n "$system" ]; then
        body="$(printf '%s' "$messages" | jq -c --arg s "$system" \
            '[{role:"system",content:$s}] + .messages')"
    else
        body="$(printf '%s' "$messages" | jq -c '.messages')"
    fi
    body="$(printf '%s' "$body" | jq -nc --arg m "$model" --argjson msgs "$body" \
        '{model:$m, messages:$msgs}')"
    resp="$(curl -sS -m 60 -X POST "https://openrouter.ai/api/v1/chat/completions" \
        -H "Authorization: Bearer ${AI_API_KEY}" \
        -H "Content-Type: application/json" \
        -H "HTTP-Referer: https://github.com/admin/Linux_post_install" \
        --write-out $'\n%{http_code}' \
        --data "$body")" || { echo "request failed (curl exit $?)" >&2; return 1; }
    code="${resp##*$'\n'}"
    body_out="${resp%$'\n'*}"
    if [ "$code" != "200" ]; then
        errmsg="$(printf '%s' "$body_out" | jq -r '.error.message // empty' 2>/dev/null || true)"
        echo "API error $code${errmsg:+: $errmsg}" >&2
        return 1
    fi
    printf '%s' "$body_out" | jq -r '.choices[0].message.content // ""'
}

# $1=current default model  → stdout=formatted model list
provider_models_list() {
    local model="$1" resp code body m
    resp="$(curl -sS -m 30 "https://openrouter.ai/api/v1/models" \
        -H "Authorization: Bearer ${AI_API_KEY}" \
        --write-out $'\n%{http_code}')" || err "request failed (curl exit $?)"
    code="${resp##*$'\n'}"
    body="${resp%$'\n'*}"
    [ "$code" = "200" ] || err "API error $code: $(printf '%s' "$body" | jq -r '.error.message // empty')"
    local list
    list="$(printf '%s' "$body" | jq -r '.data[]?.id' | sort)"
    echo "OpenRouter models:"
    while IFS= read -r m; do
        [ -n "$m" ] || continue
        if [ "$m" = "$model" ]; then
            printf '  %-48s <- default\n' "$m"
        else
            printf '  %-48s\n' "$m"
        fi
    done <<< "$list"
    if ! grep -qxF "$model" <<< "$list" 2>/dev/null; then
        warn "configured default '$model' is not in the list — set AI_MODEL or OPENROUTER_MODEL"
    fi
}
