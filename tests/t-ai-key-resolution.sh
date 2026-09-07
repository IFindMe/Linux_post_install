#!/usr/bin/env bash
set -euo pipefail
# t-ai-key-resolution.sh — `pos ai` API-key resolution contract:
#   provider-specific key (AI_GEMINI_API_KEY / OPENROUTER_API_KEY)
#   > legacy shared AI_API_KEY fallback > error; llamacpp needs no key.
#
# Regression for the 7ae2e77 "per-provider keys" migration: AI_API_KEY must be
# honored ONLY when the active provider's own key is empty (backward-compat for
# howto-taught single-key configs) and must NEVER override a provider key
# (cross-provider leakage guard). Also pins env-wins (exported env beats
# ai.env) and `pos ai providers` agreeing with resolve_key().
#
# Seam: `pos ai models` with a curl stub on PATH that records -H headers to a
# log and returns deterministic per-provider JSON (no sessions are written by
# `models`, unlike ask/chat).

run_test() {
    require_cmd jq "pos ai key resolution" || return 0

    local sandbox cfg home stubs curl_log
    sandbox="$(mksandbox ai-key-resolution)"
    cfg="$sandbox/cfg"
    home="$sandbox/home"
    stubs="$sandbox/stubs"
    mkdir -p "$cfg" "$home" "$stubs"
    curl_log="$sandbox/curl.log"
    : > "$curl_log"
    : > "$cfg/ai.env"

    # curl stub: log every -H <header> pair; reply with provider-shaped JSON +
    # the trailing \n%{http_code} line the adapters' --write-out expects.
    cat > "$stubs/curl" <<STUB
#!/usr/bin/env bash
all="\$*"
while [ \$# -gt 0 ]; do
    case "\$1" in
        -H) printf 'HDR %s\n' "\$2" >> "$curl_log"; shift 2 ;;
        *) shift ;;
    esac
done
case "\$all" in
    *generativelanguage.googleapis.com*)
        printf '%s\n200' '{"models":[{"name":"models/gemini-2.5-flash","supportedGenerationMethods":["generateContent"]}]}' ;;
    *openrouter.ai*)
        printf '%s\n200' '{"data":[{"id":"openrouter/auto"}]}' ;;
    *)
        printf '%s\n200' '{"data":[{"id":"loaded-model"}]}' ;;
esac
STUB
    chmod +x "$stubs/curl"

    local posai="$ROOT/bin/pos-ai"
    # Hermetic env: `env -i` drops every inherited variable (incl. any ambient
    # AI_*), so each case exercises exactly the values declared below.
    local path_env=(-i PATH="$stubs:/usr/bin:/bin" CONFIG_FILE="$cfg/ai.env" HOME="$home")

    # ── Case 1: gemini via provider key only ──
    printf 'AI_GEMINI_API_KEY=GEMFILEKEY\n' > "$cfg/ai.env"
    test_run_env "${path_env[@]}" -- "$posai" models
    check_rc "C1 gemini via AI_GEMINI_API_KEY works" 0 "$TR_RC"
    check_contains "C1 gemini header carries provider key" "x-goog-api-key: GEMFILEKEY" "$(cat "$curl_log")"

    # ── Case 2: gemini via legacy AI_API_KEY only (core regression) ──
    : > "$curl_log"
    printf 'AI_API_KEY=AIKEYONLY\n' > "$cfg/ai.env"
    test_run_env "${path_env[@]}" -- "$posai" models
    check_rc "C2 gemini via legacy AI_API_KEY works" 0 "$TR_RC"
    check_contains "C2 gemini header carries legacy key" "x-goog-api-key: AIKEYONLY" "$(cat "$curl_log")"

    # ── Case 3: gemini with both → provider key wins (leakage guard) ──
    : > "$curl_log"
    printf 'AI_GEMINI_API_KEY=GEMWIN\nAI_API_KEY=AIKEYLOSE\n' > "$cfg/ai.env"
    test_run_env "${path_env[@]}" -- "$posai" models
    check_rc "C3 both set still works" 0 "$TR_RC"
    check_contains "C3 provider key wins" "x-goog-api-key: GEMWIN" "$(cat "$curl_log")"
    check_not_contains "C3 shared key not leaked" "AIKEYLOSE" "$(cat "$curl_log")"

    # ── Case 4: openrouter via provider key only ──
    : > "$curl_log"
    printf 'OPENROUTER_API_KEY=ORFILEKEY\n' > "$cfg/ai.env"
    test_run_env "${path_env[@]}" -- "$posai" --provider openrouter models
    check_rc "C4 openrouter via OPENROUTER_API_KEY works" 0 "$TR_RC"
    check_contains "C4 openrouter auth carries provider key" "Authorization: Bearer ORFILEKEY" "$(cat "$curl_log")"

    # ── Case 5: openrouter via legacy AI_API_KEY only ──
    : > "$curl_log"
    printf 'AI_API_KEY=AIKEYONLY\n' > "$cfg/ai.env"
    test_run_env "${path_env[@]}" -- "$posai" --provider openrouter models
    check_rc "C5 openrouter via legacy AI_API_KEY works" 0 "$TR_RC"
    check_contains "C5 openrouter auth carries legacy key" "Authorization: Bearer AIKEYONLY" "$(cat "$curl_log")"

    # ── Case 6: openrouter with both → provider key wins ──
    : > "$curl_log"
    printf 'OPENROUTER_API_KEY=ORWIN\nAI_API_KEY=AIKEYLOSE\n' > "$cfg/ai.env"
    test_run_env "${path_env[@]}" -- "$posai" --provider openrouter models
    check_rc "C6 both set still works" 0 "$TR_RC"
    check_contains "C6 openrouter provider key wins" "Authorization: Bearer ORWIN" "$(cat "$curl_log")"
    check_not_contains "C6 shared key not leaked" "AIKEYLOSE" "$(cat "$curl_log")"

    # ── Case 7: env-wins — exported provider key beats ai.env file value ──
    : > "$curl_log"
    printf 'AI_GEMINI_API_KEY=FILEVALUE\n' > "$cfg/ai.env"
    test_run_env "${path_env[@]}" AI_GEMINI_API_KEY=ENVVALUE -- "$posai" models
    check_rc "C7 env-wins run works" 0 "$TR_RC"
    check_contains "C7 exported env key used" "x-goog-api-key: ENVVALUE" "$(cat "$curl_log")"
    check_not_contains "C7 file value suppressed by env" "FILEVALUE" "$(cat "$curl_log")"

    # ── Case 8: llamacpp needs no key ──
    : > "$curl_log"
    : > "$cfg/ai.env"
    test_run_env "${path_env[@]}" -- "$posai" --provider llamacpp models
    check_rc "C8 llamacpp works with no key" 0 "$TR_RC"
    check_contains "C8 llamacpp lists models" "Local llama.cpp models:" "$TR_OUT"

    # ── Case 9: missing key → rc 1 + byte-stable message ──
    test_run_env "${path_env[@]}" -- "$posai" models
    check_rc "C9 missing key exits nonzero" 1 "$TR_RC"
    check_contains "C9 stable error message" "No Gemini API key — run 'pos config ai' and set AI_GEMINI_API_KEY" "$TR_OUT"

    # ── Case 10: providers status agrees with resolve_key (AI_API_KEY only) ──
    local prov
    printf 'AI_API_KEY=SHAREDKEY\n' > "$cfg/ai.env"
    test_run_env "${path_env[@]}" -- "$posai" providers
    prov="$(printf '%s\n' "$TR_OUT" | grep configured || true)"
    check_contains "C10 gemini row shows configured" "gemini" "$prov"
    check_contains "C10 openrouter row shows configured" "openrouter" "$prov"
    check_not_contains "C10 no 'not configured' row" "not configured" "$TR_OUT"
}