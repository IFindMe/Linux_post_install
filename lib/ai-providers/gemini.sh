#!/usr/bin/env bash
# Gemini provider adapter for pos-ai
# Provider-specific: API call, auth, response parsing, models list
# Part of the R8 provider-agnostic architecture (lib/ai-providers/).

# Provider-specific config variables (auto-discovered by pos config ai):
# PROVIDER_CONFIG: AI_GEMINI_API_KEY=secret:Gemini API key from aistudio.google.com
# PROVIDER_CONFIG: AI_GEMINI_MODEL=:Gemini model id (default: gemini-2.5-flash)

provider_name() { printf 'Google Gemini'; }
provider_default_model() { printf 'gemini-2.5-flash'; }

# $1=model  $2=messages JSON ({"messages":[{role,content}]})  $3=optional system prompt
provider_generate() {
    local model="$1" messages="$2" system="${3:-}" body resp code body_out errmsg
    # Convert OpenAI messages format to Gemini contents format
    body="$(printf '%s' "$messages" | jq -c '{
        contents: [.messages[]? | {role: (.role | gsub("assistant";"model")), parts: [{text: .content}]}]
    }')"
    if [ -n "$system" ]; then
        body="$(printf '%s' "$body" | jq -c --arg s "$system" \
            '. + {systemInstruction:{role:"system",parts:[{text:$s}]}}')"
    fi
    resp="$(curl -sS -m 60 -X POST "https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent" \
        -H "x-goog-api-key: ${AI_API_KEY}" \
        -H "Content-Type: application/json" \
        --write-out $'\n%{http_code}' \
        --data "$body")" || { echo "request failed (curl exit $?)" >&2; return 1; }
    code="${resp##*$'\n'}"
    body_out="${resp%$'\n'*}"
    if [ "$code" != "200" ]; then
        errmsg="$(printf '%s' "$body_out" | jq -r '.error.message // empty' 2>/dev/null || true)"
        echo "API error $code${errmsg:+: $errmsg}" >&2
        return 1
    fi
    printf '%s' "$body_out" | jq -r '[.candidates[0].content.parts[]?.text] | join("")'
}

# $1=current default model  → stdout=formatted model list
provider_models_list() {
    local model="$1" resp code body m
    resp="$(curl -sS -m 30 -G "https://generativelanguage.googleapis.com/v1beta/models" \
        -H "x-goog-api-key: ${AI_API_KEY}" \
        --data-urlencode "pageSize=1000" \
        --write-out $'\n%{http_code}')" || err "request failed (curl exit $?)"
    code="${resp##*$'\n'}"
    body="${resp%$'\n'*}"
    [ "$code" = "200" ] || err "API error $code: $(printf '%s' "$body" | jq -r '.error.message // empty')"
    local list
    list="$(printf '%s' "$body" | jq -r '.models[]? | select((.supportedGenerationMethods // []) | index("generateContent")) | .name' | sed 's#^models/##' | sort)"
    echo "Gemini models (generateContent-capable):"
    while IFS= read -r m; do
        [ -n "$m" ] || continue
        if [ "$m" = "$model" ]; then
            printf '  %-32s <- default\n' "$m"
        else
            printf '  %-32s\n' "$m"
        fi
    done <<< "$list"
    if ! grep -qxF "$model" <<< "$list" 2>/dev/null; then
        warn "configured default '$model' is not in the list — set AI_MODEL or AI_GEMINI_MODEL"
    fi
}
