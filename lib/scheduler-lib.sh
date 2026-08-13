# lib/scheduler-lib.sh — shared library for `pos system schedule`.
# Sourced by bin/pos-system-schedule AFTER lib/common.sh.
#
# A job is a chmod-600 file in $SCHEDULE_DIR (<name>.env) with keys:
#
#     INTERVAL=hourly            (5m..59m | 1h..23h | hourly daily weekly | OnCalendar=…)
#     NOTIFY=onchange            (always | onchange | onerror | threshold | never)
#     MSG="NVMe health"          (optional label; threshold alert text when NOTIFY=threshold)
#     RULE="> 60c"               (threshold only: op + threshold, unit suffix fine)
#     COMMAND=…                  literal rest of the line — pipes/quotes/sudo fine
#     ENABLED=false              (written by `disable`; default enabled)
#
# NOTIFY policies (run <name> executes the command and acts on the result):
#   always     send the full output on every run
#   onchange   send only when output differs from the last run (first run sends)
#   onerror    send only when the command fails (non-zero exit or empty output)
#   threshold  compare the command's first numeric output with RULE; alert on
#              false→true plus one recovery message (the old event-trigger behavior)
#   never      run only — no notification (side-effect jobs)
#
# Default NOTIFY: threshold if RULE is present, else onchange.
#
# State lives in $SCHEDULE_STATE_DIR/<name>/ (firing flag, last output,
# last rc/timestamp) and per-job run logs in $SCHEDULE_LOG_DIR/<name>.log.

SCHEDULE_DIR="${SCHEDULE_DIR:-$HOME/.config/linux_post_install/schedule.d}"
SCHEDULE_STATE_DIR="${SCHEDULE_STATE_DIR:-$HOME/.local/share/linux_post_install/schedule/state}"
SCHEDULE_LOG_DIR="${SCHEDULE_LOG_DIR:-$HOME/.local/share/linux_post_install/schedule/logs}"
USER_SYSTEMD_DIR="${USER_SYSTEMD_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user}"
SCHED_PREFIX="pos-schedule"
SCHED_RUNNER="$(command -v pos-system-schedule 2>/dev/null || echo /usr/local/bin/pos-system-schedule)"
SCHED_DEFAULT_INTERVAL="5m"
# Legacy event-trigger leftovers (migrate reads the old rules file, sync
# removes the old single timer).
SCHED_LEGACY_ENV="${SCHED_LEGACY_ENV:-$HOME/.config/linux_post_install/event.env}"
SCHED_LEGACY_UNIT="pos-event-trigger"

# common.sh helpers (guarded so the lib is safe if common.sh wasn't loaded)
declare -F err  >/dev/null || err()  { echo "ERROR: $*" >&2; exit 1; }
declare -F warn >/dev/null || warn() { echo "[!] $*"; }
declare -F ok   >/dev/null || ok()   { echo "  OK $*"; }
declare -F log  >/dev/null || log()  { echo "[+] $*"; }

# Shared systemd **user** timer machinery (interval→OnCalendar mapping, unit
# pair writer, linger bootstrap) — the same lib the entertainment module uses,
# so the two unit templates never drift apart. Defines USER_SYSTEMD_DIR + ut_*.
source "$(dirname "${BASH_SOURCE[0]}")/../lib/user-timers-lib.sh" 2>/dev/null \
    || source "$(dirname "${BASH_SOURCE[0]}")/user-timers-lib.sh" 2>/dev/null \
    || source "$(dirname "$0")/../lib/user-timers-lib.sh" 2>/dev/null \
    || source "$(dirname "$0")/user-timers-lib.sh"

# ── Job discovery / naming ───────────────────────────────────────
sched_valid_name() {
    [[ "$1" =~ ^[a-z0-9][a-z0-9_-]*$ ]]
}

sched_job_file() {
    sched_valid_name "$1" || err "invalid job name '$1' (lowercase letters, digits, - and _)"
    printf '%s/%s.env\n' "$SCHEDULE_DIR" "$1"
}

sched_list_jobs() {
    local f n
    for f in "$SCHEDULE_DIR"/*.env; do
        [ -f "$f" ] || continue
        n="${f##*/}"
        printf '%s\n' "${n%.env}"
    done | sort
}

# ── Reading a job file ───────────────────────────────────────────
# sched_read_job <name> — fills JOB_NAME, JOB_INTERVAL, JOB_NOTIFY, JOB_MSG,
# JOB_RULE, JOB_RULE_OP, JOB_RULE_NUM, JOB_RULE_THRESH, JOB_COMMAND,
# JOB_ENABLED. Returns 1 for a missing/invalid job.
sched_read_job() {
    local name="$1" f="$SCHEDULE_DIR/$1.env" line k v
    [ -f "$f" ] || return 1
    JOB_NAME="$name"
    JOB_INTERVAL="" JOB_NOTIFY="" JOB_MSG="" JOB_RULE=""
    JOB_RULE_OP="" JOB_RULE_NUM="" JOB_RULE_THRESH=""
    JOB_COMMAND="" JOB_ENABLED=""
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ""|\#*) continue ;;
        esac
        k="${line%%=*}"
        v="${line#*=}"
        case "$k" in
            INTERVAL) JOB_INTERVAL="$(sched_strip_quotes "$v")" ;;
            NOTIFY)   JOB_NOTIFY="$(sched_strip_quotes "$v")" ;;
            MSG)      JOB_MSG="$(sched_strip_quotes "$v")" ;;
            RULE)     JOB_RULE="$(sched_strip_quotes "$v")" ;;
            COMMAND)  JOB_COMMAND="$v" ;;   # literal remainder — never quote-stripped
            ENABLED)  JOB_ENABLED="$(sched_strip_quotes "$v")" ;;
        esac
    done < "$f"
    JOB_INTERVAL="${JOB_INTERVAL:-$SCHED_DEFAULT_INTERVAL}"
    if [ -z "$JOB_NOTIFY" ]; then
        [ -n "$JOB_RULE" ] && JOB_NOTIFY="threshold" || JOB_NOTIFY="onchange"
    fi
    [ -n "$JOB_COMMAND" ] || return 1
    if [ "$JOB_NOTIFY" = "threshold" ]; then
        sched_parse_rule "$JOB_RULE" || return 1
    fi
    return 0
}

sched_write_job() {   # $1 = name — writes the JOB_* globals to schedule.d/<name>.env
    local f tmp
    f="$(sched_job_file "$1")"
    mkdir -p "$SCHEDULE_DIR"
    tmp="$(mktemp)"
    {
        printf '# pos system schedule job — %s\n' "$1"
        [ -z "$JOB_INTERVAL" ] || printf 'INTERVAL=%s\n' "$JOB_INTERVAL"
        printf 'NOTIFY=%s\n' "$JOB_NOTIFY"
        [ -z "$JOB_MSG" ] || printf 'MSG=%s\n' "$JOB_MSG"
        [ -z "$JOB_RULE" ] || printf 'RULE=%s\n' "$JOB_RULE"
        printf 'COMMAND=%s\n' "$JOB_COMMAND"
    } >"$tmp"
    mv "$tmp" "$f"
    chmod 600 "$f"
}

# ── Small helpers ────────────────────────────────────────────────
sched_strip_quotes() {
    local v="$1"
    v="${v#\"}"; v="${v%\"}"
    v="${v#\'}"; v="${v%\'}"
    printf '%s' "$v"
}

# First numeric prefix of a string (allows a unit suffix: 60c, 80%, 10g).
sched_numeric() {
    if [[ "$1" =~ ^[+-]?([0-9]+([.][0-9]+)?|[.][0-9]+) ]]; then
        printf '%s' "${BASH_REMATCH[0]}"
        return 0
    fi
    return 1
}

# Float-safe numeric comparison. Returns 0 if $1 $2 $3 is TRUE.
sched_compare() {
    awk -v a="$1" -v op="$2" -v b="$3" 'BEGIN{
        if (op==">")  exit (a>b)  ? 0 : 1
        if (op=="<")  exit (a<b)  ? 0 : 1
        if (op==">=") exit (a>=b) ? 0 : 1
        if (op=="<=") exit (a<=b) ? 0 : 1
        if (op=="==") exit (a==b) ? 0 : 1
        if (op=="!=") exit (a!=b) ? 0 : 1
        exit 1
    }'
}

# ── Threshold rule parsing (RULE key: "<op> <number>[unit]") ────
# Sets RULE_OP, RULE_THRESH, RULE_NUM. Returns 1 on unparseable input.
sched_parse_rule() {
    local -a t=()
    read -r -a t <<< "$1"
    local n=${#t[@]} i
    [ "$n" -ge 2 ] || return 1
    for ((i=n-2; i>=0; i--)); do
        case "${t[i]}" in
            ">="|"<="|"=="|"!="|">"|"<")
                if sched_numeric "${t[i+1]}" >/dev/null 2>&1; then
                    RULE_OP="${t[i]}"
                    RULE_THRESH="${t[i+1]}"
                    RULE_NUM="$(sched_numeric "${t[i+1]}")"
                    return 0
                fi ;;
        esac
    done
    return 1
}

# ── Running the job's command ────────────────────────────────────
# Sets JOB_OUT (stdout+stderr) and JOB_RC (the pipeline's exit code).
sched_run_command() {
    local out rc
    if out="$(bash -c "$JOB_COMMAND" 2>&1)"; then rc=0; else rc=$?; fi
    JOB_OUT="$out"
    JOB_RC="$rc"
}

# First numeric token of JOB_OUT's first line → VALUE_NUM + VALUE_DISPLAY.
sched_first_numeric() {
    local line tok
    line="$(printf '%s' "$JOB_OUT" | sed -n '1p')"
    read -r -a tokens <<< "$line"
    for tok in "${tokens[@]:-}"; do
        if sched_numeric "$tok" >/dev/null 2>&1; then
            VALUE_NUM="$(sched_numeric "$tok")"
            VALUE_DISPLAY="$tok"
            return 0
        fi
    done
    return 1
}

# Cap a message (telegram listener precedent: ~3800 chars).
sched_truncate() {
    local n="${1:-3800}" out
    out="$(cat)"
    if [ "${#out}" -gt "$n" ]; then
        out="${out:0:$n}"
        printf '%s\n…(truncated)' "$out"
    else
        printf '%s' "$out"
    fi
}

# DRY_RUN-aware notify (the only place scheduler messages leave).
sched_notify() {
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        log "(dry-run) would notify: $1"
    else
        notify_send "$1"
    fi
}

# ── Per-job state ────────────────────────────────────────────────
sched_state_firing() {   # $1 = job name
    [ -f "$SCHEDULE_STATE_DIR/$1/firing" ] && grep -q '^1' "$SCHEDULE_STATE_DIR/$1/firing"
}

sched_state_set_firing() {   # $1 = job name, $2 = 0|1
    mkdir -p "$SCHEDULE_STATE_DIR/$1"
    printf '%s\n' "$2" >"$SCHEDULE_STATE_DIR/$1/firing"
}

sched_save_run() {   # $1 = job name, $2 = output, $3 = rc
    local dir="$SCHEDULE_STATE_DIR/$1" logf="$SCHEDULE_LOG_DIR/$1.log"
    mkdir -p "$dir" "$SCHEDULE_LOG_DIR"
    printf '%s' "$2" >"$dir/out"
    printf 'rc=%s\nts=%s\n' "$3" "$(date +%s)" >"$dir/meta"
    {
        printf '\n== %s rc=%s ==\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$3"
        printf '%s\n' "$2"
    } >>"$logf"
    # Keep the run log bounded (last 500 lines).
    if [ "$(wc -l <"$logf" 2>/dev/null || echo 0)" -gt 500 ]; then
        tail -n 500 "$logf" >"$logf.tmp" && mv "$logf.tmp" "$logf"
    fi
}

sched_last_run_str() {   # $1 = job name → "rc=N <MM-DD HH:MM>"
    local f="$SCHEDULE_STATE_DIR/$1/meta" rc ts
    [ -f "$f" ] || { printf 'never'; return; }
    rc="$(sed -n 's/^rc=//p' "$f" | head -1)"
    ts="$(sed -n 's/^ts=//p' "$f" | head -1)"
    printf 'rc=%s %s' "$rc" "$(date -d "@$ts" '+%m-%d %H:%M' 2>/dev/null || printf '?')"
}

# ── Notify policies ──────────────────────────────────────────────
sched_msg_alert() {
    if [ -n "$JOB_MSG" ]; then
        printf '%s (now %s)' "$JOB_MSG" "$VALUE_DISPLAY"
    else
        printf '%s now %s is %s %s' "${JOB_COMMAND%% *}" "$VALUE_DISPLAY" "$RULE_OP" "$RULE_THRESH"
    fi
}

sched_msg_recover() {
    if [ -n "$JOB_MSG" ]; then
        printf '%s recovered (now %s)' "$JOB_MSG" "$VALUE_DISPLAY"
    else
        printf '%s OK (now %s)' "${JOB_COMMAND%% *}" "$VALUE_DISPLAY"
    fi
}

sched_report_msg() {   # $1 = label ("changed" | "run" | "failed (rc N)")
    {
        printf 'sched %s%s — %s\n' "$JOB_NAME" "${JOB_MSG:+ ($JOB_MSG)}" "$1"
        [ -z "$JOB_OUT" ] || printf '%s\n' "$JOB_OUT"
    } | sched_truncate
}

sched_policy_threshold() {
    if ! sched_first_numeric; then
        warn "job '$JOB_NAME' check produced no number — skipped"
        return 0
    fi
    local fired=0
    sched_compare "$VALUE_NUM" "$RULE_OP" "$RULE_NUM" && fired=1
    if [ "$fired" -eq 1 ] && ! sched_state_firing "$JOB_NAME"; then
        sched_notify "$(sched_msg_alert)"
        sched_state_set_firing "$JOB_NAME" 1
        log "alert: $JOB_NAME = $VALUE_DISPLAY (was below $RULE_OP $RULE_THRESH)"
    elif [ "$fired" -eq 0 ] && sched_state_firing "$JOB_NAME"; then
        sched_notify "$(sched_msg_recover)"
        sched_state_set_firing "$JOB_NAME" 0
        log "recovered: $JOB_NAME = $VALUE_DISPLAY"
    else
        log "ok: $JOB_NAME = $VALUE_DISPLAY (no change)"
    fi
}

sched_policy_onchange() {
    local dir="$SCHEDULE_STATE_DIR/$JOB_NAME" changed=0
    if [ ! -f "$dir/out" ]; then
        changed=1   # first run always notifies
    elif ! printf '%s' "$JOB_OUT" | cmp -s - "$dir/out"; then
        changed=1
    fi
    if [ "$changed" -eq 1 ]; then
        sched_notify "$(sched_report_msg 'changed')"
        log "change detected — notified"
    else
        log "no change — not notifying"
    fi
}

sched_policy_always() {
    sched_notify "$(sched_report_msg 'run')"
    log "notified (always)"
}

sched_policy_onerror() {
    if [ "$JOB_RC" -ne 0 ] || [ -z "$JOB_OUT" ]; then
        sched_notify "$(sched_report_msg "failed (rc $JOB_RC)")"
        log "error detected (rc $JOB_RC) — notified"
    else
        log "ok (rc 0) — not notifying"
    fi
}

sched_policy_never() {
    log "ran silently (rc $JOB_RC) — no notify"
}

# ── Run one job ──────────────────────────────────────────────────
sched_run_job() {   # $1 = job name
    if ! sched_read_job "$1"; then
        warn "job '$1' unparseable — skipping"
        return 1
    fi
    sched_run_command
    case "$JOB_NOTIFY" in
        threshold) sched_policy_threshold ;;
        onchange)  sched_policy_onchange ;;
        always)    sched_policy_always ;;
        onerror)   sched_policy_onerror ;;
        never)     sched_policy_never ;;
        *)
            warn "job '$1': unknown NOTIFY '$JOB_NOTIFY' (always|onchange|onerror|threshold|never) — ran silently"
            sched_policy_never ;;
    esac
    # dry-run previews without mutating state, logs, or the onchange baseline
    [ "${DRY_RUN:-0}" -ne 1 ] && sched_save_run "$1" "$JOB_OUT" "$JOB_RC"
    return 0
}
# ── systemd user timers (one pair per job) ──────────────────────
# Interval → OnCalendar mapping, unit naming, the unit pair writer and linger
# bootstrap come from lib/user-timers-lib.sh (ut_*).
sched_job_active() {   # $1 = job name — valid AND not disabled
    sched_read_job "$1" >/dev/null 2>&1 || return 1
    [ "$JOB_ENABLED" = "false" ] && return 1
    return 0
}

# Reconcile schedule.d with the per-job user timers.
sched_sync() {
    local -a jobs=() name oncal wrote=0 n=0
    mapfile -t jobs < <(sched_list_jobs)
    [ "${#jobs[@]}" -eq 0 ] && log "no jobs in $SCHEDULE_DIR — add one with 'pos system schedule config'"
    for name in "${jobs[@]}"; do
        if ! sched_read_job "$name" >/dev/null 2>&1; then
            warn "job '$name' unparseable — skipping"
            continue
        fi
        [ "$JOB_ENABLED" = "false" ] && continue   # disabled: orphan cleanup drops its timer
        if ! oncal="$(ut_interval_to_oncalendar "$JOB_INTERVAL")"; then
            warn "invalid interval '$JOB_INTERVAL' for '$name' — skipping"
            continue
        fi
        if [ "${DRY_RUN:-0}" -eq 1 ]; then
            log "(dry-run) write $(ut_unit_name "$SCHED_PREFIX" "$name").timer (OnCalendar=$oncal)"
        else
            ut_write_unit_pair \
                "$USER_SYSTEMD_DIR/$(ut_unit_name "$SCHED_PREFIX" "$name").service" \
                "$USER_SYSTEMD_DIR/$(ut_unit_name "$SCHED_PREFIX" "$name").timer" \
                "pos system schedule — run job $name" \
                "$SCHED_RUNNER run $name" \
                "$oncal"
        fi
        wrote=1; n=$((n + 1))
    done
    [ "${DRY_RUN:-0}" -eq 1 ] && return 0
    [ "$wrote" -eq 1 ] && systemctl --user daemon-reload >/dev/null 2>&1 || true
    [ "$n" -gt 0 ] && ut_ensure_linger
    for name in "${jobs[@]}"; do
        if ! sched_read_job "$name" >/dev/null 2>&1; then
            continue
        fi
        [ "$JOB_ENABLED" = "false" ] && continue
        ut_interval_to_oncalendar "$JOB_INTERVAL" >/dev/null 2>&1 || continue
        local t="$(ut_unit_name "$SCHED_PREFIX" "$name").timer"
        if systemctl --user is-enabled "$t" >/dev/null 2>&1; then
            systemctl --user restart "$t" >/dev/null 2>&1 || true
        else
            systemctl --user enable --now "$t" >/dev/null 2>&1 || \
                warn "could not enable timer '$t' (is the user systemd manager running?)"
        fi
    done
    sched_remove_orphans
    sched_cleanup_legacy
}

# Remove timers whose job no longer exists or was disabled.
sched_remove_orphans() {
    local f p removed=0
    for f in "$USER_SYSTEMD_DIR"/${SCHED_PREFIX}-*.timer; do
        [ -f "$f" ] || continue
        p="${f##*/}"; p="${p#${SCHED_PREFIX}-}"; p="${p%.timer}"
        if ! sched_job_active "$p"; then
            systemctl --user disable --now "$(ut_unit_name "$SCHED_PREFIX" "$p").timer" >/dev/null 2>&1 || true
            rm -f "$USER_SYSTEMD_DIR/$(ut_unit_name "$SCHED_PREFIX" "$p").timer" "$USER_SYSTEMD_DIR/$(ut_unit_name "$SCHED_PREFIX" "$p").service"
            log "removed timer for '$p'"
            removed=1
        fi
    done
    [ "$removed" -eq 1 ] && systemctl --user daemon-reload >/dev/null 2>&1 || true
}

# Remove the legacy single event-trigger timer if still present.
sched_cleanup_legacy() {
    if [ -f "$USER_SYSTEMD_DIR/${SCHED_LEGACY_UNIT}.timer" ]; then
        systemctl --user disable --now "$SCHED_LEGACY_UNIT.timer" >/dev/null 2>&1 || true
        rm -f "$USER_SYSTEMD_DIR/${SCHED_LEGACY_UNIT}.timer" "$USER_SYSTEMD_DIR/${SCHED_LEGACY_UNIT}.service"
        systemctl --user daemon-reload >/dev/null 2>&1 || true
        log "removed legacy $SCHED_LEGACY_UNIT timer (superseded by per-job timers)"
    fi
}

# Toggle a job's enabled flag (keeps the job file). $1 = name, $2 = true|false.
sched_set_enabled() {
    local f tmp
    f="$(sched_job_file "$1")"
    [ -f "$f" ] || err "no such job '$1' (see: pos system schedule list)"
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        log "(dry-run) set ENABLED=$2 in $f"
        return 0
    fi
    tmp="$(mktemp)"
    grep -v '^ENABLED=' "$f" >"$tmp" || true
    printf 'ENABLED=%s\n' "$2" >>"$tmp"
    mv "$tmp" "$f"
    chmod 600 "$f"
}

# ── Legacy migration (event.env rules → schedule.d jobs) ─────────
# Parses one old event.env rule line into MIG_MSG / MIG_CMD / MIG_RULE.
sched_parse_legacy_rule() {
    local line="$1" s="$1" cond="" msg="" parts="" m
    local -a tokens=()
    while [[ "$s" == *" if "* ]]; do
        m="${s%% if *}"
        s="${s#*" if "}"
        if [[ "$s" == *" if "* ]]; then parts+="${m} if "; else parts+="${m}"; fi
    done
    msg="$parts"
    cond="$s"
    [ -n "$cond" ] || return 1
    read -r -a tokens <<< "$cond"
    local n=${#tokens[@]} i
    [ "$n" -ge 2 ] || return 1
    for ((i=n-2; i>=0; i--)); do
        case "${tokens[i]}" in
            ">="|"<="|"=="|"!="|">"|"<")
                if sched_numeric "${tokens[i+1]}" >/dev/null 2>&1; then
                    if [ "$i" -eq 0 ]; then
                        MIG_CMD="${tokens[0]}"
                    else
                        MIG_CMD="$(printf '%s ' "${tokens[@]:0:i}")"
                        MIG_CMD="${MIG_CMD% }"
                    fi
                    MIG_MSG="$(sched_strip_quotes "$msg")"
                    MIG_RULE="${tokens[i]} ${tokens[i+1]}"
                    return 0
                fi ;;
        esac
    done
    return 1
}

sched_migrate() {
    local legacy="$SCHED_LEGACY_ENV"
    if [ ! -f "$legacy" ]; then
        log "no legacy rules file at $legacy — nothing to migrate"
        return 0
    fi
    local line name n=0 migrated=0 oncal=""
    if [ -f "$USER_SYSTEMD_DIR/${SCHED_LEGACY_UNIT}.timer" ]; then
        oncal="$(sed -n 's/^OnCalendar=//p' "$USER_SYSTEMD_DIR/${SCHED_LEGACY_UNIT}.timer" | head -1)"
    fi
    local interval="${oncal:+OnCalendar=$oncal}"
    interval="${interval:-$SCHED_DEFAULT_INTERVAL}"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ""|\#*) continue ;;
        esac
        if ! sched_parse_legacy_rule "$line"; then
            warn "skipping unparseable rule: $line"
            continue
        fi
        n=$((n + 1))
        name="rule-$n"
        if [ -f "$SCHEDULE_DIR/$name.env" ]; then
            log "job '$name' already exists — skipping (remove it to re-migrate)"
            migrated=1
            continue
        fi
        if [ "${DRY_RUN:-0}" -eq 1 ]; then
            log "(dry-run) would write job '$name' (NOTIFY=threshold, INTERVAL=$interval): $MIG_CMD"
        else
            JOB_INTERVAL="$interval" JOB_NOTIFY="threshold" JOB_MSG="$MIG_MSG" JOB_RULE="$MIG_RULE" JOB_COMMAND="$MIG_CMD"
            sched_write_job "$name"
            migrated=1
        fi
    done < "$legacy"
    if [ "$migrated" -eq 0 ]; then
        log "no rules found in $legacy"
        return 0
    fi
    log "migrated $n rule(s) → $SCHEDULE_DIR (NOTIFY=threshold, INTERVAL=$interval)"
    if [ "${DRY_RUN:-0}" -ne 1 ]; then
        sched_cleanup_legacy
        log "legacy timer removed — run 'pos system schedule enable' to start the migrated jobs"
    fi
}

# ── Subcommand implementations ───────────────────────────────────
sched_run() {   # $1 = job name | all
    local name
    if [ "$1" = "all" ]; then
        local -a jobs=() ran=0
        mapfile -t jobs < <(sched_list_jobs)
        if [ "${#jobs[@]}" -eq 0 ]; then
            warn "no jobs in $SCHEDULE_DIR — add one with 'pos system schedule config'"
            return 0
        fi
        for name in "${jobs[@]}"; do
            sched_run_job "$name" && ran=$((ran + 1))
        done
        log "ran $ran job(s)"
        return 0
    fi
    sched_valid_name "$1" || err "invalid job name '$1'"
    [ -f "$SCHEDULE_DIR/$1.env" ] || err "no such job '$1' (see: pos system schedule list)"
    sched_run_job "$1"
}

sched_list() {
    local -a jobs=() name
    mapfile -t jobs < <(sched_list_jobs)
    if [ "${#jobs[@]}" -eq 0 ]; then
        echo "(no jobs — run 'pos system schedule config' to add one)"
        return 0
    fi
    printf '%-18s %-9s %-9s %-8s %s\n' JOB NOTIFY INTERVAL STATE LAST
    for name in "${jobs[@]}"; do
        if ! sched_read_job "$name" >/dev/null 2>&1; then
            printf '%-18s %s\n' "$name" "INVALID job file"
            continue
        fi
        local st="enabled"
        [ "$JOB_ENABLED" = "false" ] && st="disabled"
        printf '%-18s %-9s %-9s %-8s %s\n' "$name" "$JOB_NOTIFY" "$JOB_INTERVAL" "$st" "$(sched_last_run_str "$name")"
    done
    echo
    log "run 'pos system schedule enable' to start the enabled jobs"
}

sched_enable() {   # $1 = job name | all
    local name
    if [ "$1" = "all" ]; then
        local -a jobs=()
        mapfile -t jobs < <(sched_list_jobs)
        for name in "${jobs[@]}"; do
            sched_set_enabled "$name" true
        done
        log "enabled all jobs"
    else
        sched_set_enabled "$1" true
        log "job '$1' enabled"
    fi
    sched_sync
}

sched_disable() {   # $1 = job name | all
    local name
    if [ "$1" = "all" ]; then
        local -a jobs=()
        mapfile -t jobs < <(sched_list_jobs)
        for name in "${jobs[@]}"; do
            sched_set_enabled "$name" false
        done
        log "disabled all jobs (job files kept)"
    else
        sched_set_enabled "$1" false
        log "job '$1' disabled (job file kept)"
    fi
    sched_sync
}

sched_status() {
    local -a jobs=() name
    mapfile -t jobs < <(sched_list_jobs)
    if [ "${#jobs[@]}" -eq 0 ]; then
        echo "no jobs defined in $SCHEDULE_DIR"
        echo "add one: pos system schedule config"
        return 0
    fi
    if ! systemctl --user show-environment >/dev/null 2>&1; then
        warn "no user systemd manager reachable — timers cannot run"
    fi
    echo "jobs: ${#jobs[@]} in $SCHEDULE_DIR"
    for name in "${jobs[@]}"; do
        if ! sched_read_job "$name" >/dev/null 2>&1; then
            printf '  %-18s INVALID job file\n' "$name"
            continue
        fi
        local st="enabled" oncal next=""
        [ "$JOB_ENABLED" = "false" ] && st="disabled"
        if [ "$st" = "enabled" ]; then
            if oncal="$(ut_interval_to_oncalendar "$JOB_INTERVAL")"; then
                next="$(systemctl --user list-timers "$(ut_unit_name "$SCHED_PREFIX" "$name").timer" --no-legend 2>/dev/null | awk '{print $1, $2}' | head -1)"
            else
                oncal="(invalid interval: $JOB_INTERVAL)"
            fi
            printf '  %-18s %-9s %-8s %s%s\n' "$name" "$JOB_NOTIFY" "$st" "$oncal${next:+ (next: $next)}"
        else
            printf '  %-18s %-9s %-8s\n' "$name" "$JOB_NOTIFY" "$st"
        fi
    done
}

# ── Interactive job editor (config) ─────────────────────────────
sched_config_editor() {
    local -a jobs=() name action n ok
    while true; do
        mapfile -t jobs < <(sched_list_jobs)
        echo "── jobs in $SCHEDULE_DIR ──" >&2
        if [ "${#jobs[@]}" -eq 0 ]; then
            echo "  (empty)" >&2
        else
            for i in "${!jobs[@]}"; do
                if sched_read_job "${jobs[i]}" >/dev/null 2>&1; then
                    printf '  %2d  %-18s %s, %s, %s\n' "$((i + 1))" "${jobs[i]}" "$JOB_NOTIFY" "$JOB_INTERVAL" \
                        "$([ "$JOB_ENABLED" = "false" ] && echo disabled || echo enabled)" >&2
                else
                    printf '  %2d  %-18s INVALID\n' "$((i + 1))" "${jobs[i]}" >&2
                fi
            done
        fi
        read -rp "action [add / edit <n> / remove <n> / enable <n> / disable <n> / quit]: " action
        case "$action" in
            quit|q) break ;;
            add) sched_editor_add ;;
            remove*) sched_editor_remove "${action#remove }" ;;
            edit*) sched_editor_edit "${action#edit }" ;;
            enable*) sched_editor_toggle enable "${action#enable }" ;;
            disable*) sched_editor_toggle disable "${action#disable }" ;;
            *) warn "unknown action (add | edit <n> | remove <n> | enable <n> | disable <n> | quit)" ;;
        esac
    done
}

sched_editor_add() {
    local name interval notify msg rule cmd
    read -rp "name [a-z0-9_-]: " name
    sched_valid_name "$name" || { warn "invalid name — lowercase letters, digits, - and _"; return; }
    [ -f "$SCHEDULE_DIR/$name.env" ] && { warn "job '$name' already exists — use edit"; return; }
    read -rp "interval [5m..59m | 1h..23h | hourly daily weekly | OnCalendar=…] (blank = $SCHED_DEFAULT_INTERVAL): " interval
    interval="${interval:-$SCHED_DEFAULT_INTERVAL}"
    ut_interval_to_oncalendar "$interval" >/dev/null 2>&1 || warn "interval '$interval' not recognized — saved anyway, 'enable' will skip it"
    read -rp "notify [always|onchange|onerror|threshold|never] (blank = onchange): " notify
    notify="${notify:-onchange}"
    case "$notify" in always|onchange|onerror|threshold|never) ;; *) warn "unknown policy '$notify' — job will run silently" ;; esac
    read -rp "message (optional, blank = none): " msg
    rule=""
    if [ "$notify" = "threshold" ]; then
        read -rp "rule (op + threshold, e.g. '> 60c'): " rule
        [ -n "$rule" ] || warn "threshold jobs need RULE — job will be skipped"
    fi
    read -rp "command: " cmd
    [ -n "$cmd" ] || { warn "empty command — not added"; return; }
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        log "(dry-run) would add job '$name'"
        return
    fi
    JOB_INTERVAL="$interval" JOB_NOTIFY="$notify" JOB_MSG="$msg" JOB_RULE="$rule" JOB_COMMAND="$cmd"
    sched_write_job "$name"
    ok "job '$name' added — apply with 'pos system schedule enable'"
}

sched_editor_edit() {
    local n="$1" name
    [[ "$n" =~ ^[0-9]+$ ]] || { warn "use: edit <number>"; return; }
    local -a jobs=()
    mapfile -t jobs < <(sched_list_jobs)
    [ "$n" -ge 1 ] && [ "$n" -le "${#jobs[@]}" ] || { warn "no job $n"; return; }
    name="${jobs[$((n - 1))]}"
    sched_read_job "$name" || { warn "job '$name' is invalid — remove and re-add it"; return; }
    local interval notify msg rule cmd
    read -rp "interval (blank keeps, current: $JOB_INTERVAL): " interval
    interval="${interval:-$JOB_INTERVAL}"
    ut_interval_to_oncalendar "$interval" >/dev/null 2>&1 || warn "interval '$interval' not recognized — saved anyway, 'enable' will skip it"
    read -rp "notify (blank keeps, current: $JOB_NOTIFY): " notify
    notify="${notify:-$JOB_NOTIFY}"
    read -rp "message (blank keeps, current: ${JOB_MSG:-<none>}): " msg
    [ -n "$msg" ] || msg="$JOB_MSG"
    rule=""
    if [ "$notify" = "threshold" ]; then
        read -rp "rule (blank keeps, current: $JOB_RULE): " rule
        [ -n "$rule" ] || rule="$JOB_RULE"
    fi
    read -rp "command (blank keeps, current: $JOB_COMMAND): " cmd
    [ -n "$cmd" ] || cmd="$JOB_COMMAND"
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        log "(dry-run) would update job '$name'"
        return
    fi
    JOB_INTERVAL="$interval" JOB_NOTIFY="$notify" JOB_MSG="$msg" JOB_RULE="$rule" JOB_COMMAND="$cmd"
    sched_write_job "$name"
    ok "job '$name' updated"
}

sched_editor_remove() {
    local n="$1" name ok
    [[ "$n" =~ ^[0-9]+$ ]] || { warn "use: remove <number>"; return; }
    local -a jobs=()
    mapfile -t jobs < <(sched_list_jobs)
    [ "$n" -ge 1 ] && [ "$n" -le "${#jobs[@]}" ] || { warn "no job $n"; return; }
    name="${jobs[$((n - 1))]}"
    read -rp "remove job '$name'? [y/N]: " ok
    [[ "$ok" =~ ^[Yy] ]] || return
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        log "(dry-run) would remove job '$name'"
        return
    fi
    rm -f "$SCHEDULE_DIR/$name.env"
    ok "job '$name' removed (apply with 'pos system schedule enable')"
}

sched_editor_toggle() {
    local mode="$1" n="$2" name
    [[ "$n" =~ ^[0-9]+$ ]] || { warn "use: $mode <number>"; return; }
    local -a jobs=()
    mapfile -t jobs < <(sched_list_jobs)
    [ "$n" -ge 1 ] && [ "$n" -le "${#jobs[@]}" ] || { warn "no job $n"; return; }
    name="${jobs[$((n - 1))]}"
    if [ "$mode" = "enable" ]; then
        sched_set_enabled "$name" true
        ok "job '$name' enabled (apply with 'pos system schedule enable')"
    else
        sched_set_enabled "$name" false
        ok "job '$name' disabled (apply with 'pos system schedule enable')"
    fi
}
