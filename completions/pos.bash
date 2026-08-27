#!/usr/bin/env bash
# Bash completion for pos — dynamically discovers pos-* subcommands
# Install: source this file in ~/.bashrc or place in /etc/bash_completion.d/
# GEN:START posflags
declare -A _pos_flags
_pos_flags[communication-matrix-listener]="--enable --disable --status --run"
_pos_flags[communication-telegram-listener]="--enable --disable --status --sync-commands --run"
_pos_flags[communication-telegram-sender]="--type --caption --parse-mode --no-preview --token --chat-id --markdown"
_pos_flags[docker-stack]="-a --all"
_pos_flags[docker-vbox]="--dir --gpu --device --port --cpus --memory --network"
_pos_flags[entertainment-send]="--print --markdown"
_pos_flags[media-mp3]="--output --no-playlist --cookies --by-artist --dry-run"
_pos_flags[media-mp4]="--format --best --worst --output --no-playlist --cookies --dry-run"
_pos_flags[media-sync]="--mp3 --mp4 --source --dry-run"
_pos_flags[media-ytsync]="--dry-run"
_pos_flags[network-checkport]="--tcp --udp --ping --no-banner --versions --timeout"
_pos_flags[network-download]="--dir --out --split --seed --force --upload --gid --tmux"
_pos_flags[network-hotspot]="--foreground"
_pos_flags[share-usb-server]="--ls --ls-shared --share --unshare --auto-share --callback --close-callback --auto-connect --disconnect --nickname --timeout --port --info --version menu"
_pos_flags[system-backup]="--service --no-encrypt"
_pos_flags[system-schedule]="--dry-run"
_pos_flags[system-uninstall]="--yes --config --data"
_pos_flags[ai]="--provider --model --session --system --full --last --trust"
_pos_flags[tree]="--depth"
# GEN:END posflags
# GEN:START possubcmds
declare -A _pos_subcmds
_pos_subcmds[ai-alias]="create edit remove list show"
_pos_subcmds[ai-gemini]="ask chat models sessions capture"
_pos_subcmds[ai-openrouter]="ask chat sessions capture"
_pos_subcmds[communication-matrix-sender]="send test login"
_pos_subcmds[communication-scrcpy]="devices record tcpip connect push pull screenshot info"
_pos_subcmds[communication-telegram-listener]="prefix"
_pos_subcmds[communication-telegram-sender]="send test"
_pos_subcmds[docker-compose]="ls installed up down restart logs update config menu"
_pos_subcmds[docker-vbox]="create enter stop start rm ls menu"
_pos_subcmds[media-sync]="menu"
_pos_subcmds[media-ytsync]="add sync list remove"
_pos_subcmds[network-download]="start stop status add torrent metalink list info files peers pause resume remove purge move limit set watch restart retry replace menu"
_pos_subcmds[share-nfs-client]="mount unmount list persist unpersist menu"
_pos_subcmds[share-nfs-server]="status share unshare list reload enable disable menu"
_pos_subcmds[share-smb-client]="mount unmount list persist unpersist menu"
_pos_subcmds[share-smb-server]="status share unshare list adduser deluser reload enable disable menu"
_pos_subcmds[system-backup]="menu"
_pos_subcmds[system-schedule]="run list config enable disable status migrate menu"
_pos_subcmds[ai]="ask chat sessions capture models providers alias gemini openrouter"
# GEN:END possubcmds
# GEN:START posconfigscopes
declare -a _pos_config_scopes=(ai compose entertainment matrix notify scrcpy system telegram ytsync)
# GEN:END posconfigscopes

_pos() {
    local cur prev words cword

    # Manual init if bash-completion package is not loaded
    if declare -F _init_completion &>/dev/null; then
        _init_completion || return
    else
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        words=("${COMP_WORDS[@]}")
        cword=$COMP_CWORD
    fi

    local pos_bin="${COMP_WORDS[0]}"
    local pos_dir
    pos_dir="$(dirname "$(command -v "$pos_bin" 2>/dev/null || echo "$pos_bin")")"

    # ── Collect all pos-* subcommands ──────────────────────────
    local all_cmds=()
    local f
    for f in "$pos_dir"/pos-*; do
        [ -x "$f" ] || continue
        all_cmds+=("${f##*/pos-}")
    done

    # ── Build category→subcommand map ──────────────────────────
    # Nested sub-tools (pos-<cat>-<a>-<b> where pos-<cat>-<a> exists) are
    # offered under their parent tool, not at the category level.
    local -A cat_cmds
    local -A nested
    local cmd2 c2 cat2 sub2
    for cmd in "${all_cmds[@]}"; do
        local cat="${cmd%%-*}"
        local sub="${cmd#*-}"
        if [ "$cat" != "$cmd" ]; then
            for cmd2 in "${all_cmds[@]}"; do
                cat2="${cmd2%%-*}"
                sub2="${cmd2#*-}"
                if [ "$cat2" = "$cat" ] && [ "$sub2" != "$sub" ] && [[ "$sub" == "$sub2-"* ]]; then
                    nested["$cmd"]=1
                    break
                fi
            done
        fi
    done
    for cmd in "${all_cmds[@]}"; do
        local cat="${cmd%%-*}"
        local sub="${cmd#*-}"
        if [ "$cat" != "$cmd" ] && [ -z "${nested[$cmd]:-}" ]; then
            cat_cmds["$cat"]+="${sub} "
        fi
    done

    # ── Helpers ────────────────────────────────────────────────
    _pos_complete_categories() {
        COMPREPLY=($(compgen -W "${!cat_cmds[*]} config" -- "$cur"))
    }

    _pos_complete_subcats() {
        local cat="${words[1]}"
        COMPREPLY=($(compgen -W "${cat_cmds[$cat]:-} --help" -- "$cur"))
    }

    # Nested sub-tool group (pos-<key>-* with no direct tool) → suggest suffixes.
    _pos_complete_group() {
        local key="$1" out=() f
        for f in "$pos_dir"/pos-"$key"-*; do
            [ -x "$f" ] || continue
            out+=("${f##*/pos-$key-}")
        done
        COMPREPLY=($(compgen -W "${out[*]} --help" -- "$cur"))
    }

    # Complete subcommands + flags + --help for a tool chain, walking up to
    # the nearest tool that declares anything. A key that is a group of nested
    # sub-tools (no direct tool) completes to the group's suffixes.
    _pos_complete_tool() {
        local key="$1" k opts
        if [ -n "${_pos_subcmds[$key]:-}" ] || [ -n "${_pos_flags[$key]:-}" ]; then
            opts="${_pos_subcmds[$key]:-} ${_pos_flags[$key]:-} --help"
            COMPREPLY=($(compgen -W "$opts" -- "$cur"))
            return
        fi
        for f in "$pos_dir"/pos-"$key"-*; do
            if [ -x "$f" ]; then
                _pos_complete_group "$key"
                return
            fi
        done
        k="$key"
        while [ -n "$k" ]; do
            if [ -n "${_pos_subcmds[$k]:-}" ] || [ -n "${_pos_flags[$k]:-}" ]; then
                opts="${_pos_flags[$k]:-} --help"
                COMPREPLY=($(compgen -W "$opts" -- "$cur"))
                return
            fi
            [[ "$k" == *-* ]] || break
            k="${k%-*}"
        done
        COMPREPLY=($(compgen -W "--help" -- "$cur"))
    }

    _pos_complete_compose_services() {
        local scale_dir="/usr/local/share/linux_post_install/scale-tail/services"
        if [ -d "$scale_dir" ]; then
            local svcs=()
            for d in "$scale_dir"/*/; do
                [ -d "$d" ] && svcs+=("$(basename "$d")")
            done
            COMPREPLY=($(compgen -W "${svcs[*]}" -- "$cur"))
        fi
    }

    _pos_complete_compose_cmds() {
        COMPREPLY=($(compgen -W "ls installed up down restart logs update config" -- "$cur"))
    }

    _pos_complete_docker_vbox_cmds() {
        COMPREPLY=($(compgen -W "create enter stop start rm ls" -- "$cur"))
    }

    _pos_complete_docker_vbox_names() {
        local names
        names=$(docker ps -a --filter label=linux_post_install.vbox=true --format '{{.Names}}' 2>/dev/null)
        COMPREPLY=($(compgen -W "$names" -- "$cur"))
    }

    _pos_entertainment_plugins() {
        local d f name out=()
        for d in /usr/local/bin "$pos_dir/../entertainment"; do
            [ -d "$d" ] || continue
            for f in "$d"/*.sh; do
                [ -f "$f" ] || continue
                name="$(grep -m1 '^# POS_PLUGIN:' "$f" 2>/dev/null | sed 's/^# POS_PLUGIN:[[:space:]]*//;s/[[:space:]]*$//')"
                [ -n "$name" ] && out+=("$name")
            done
        done
        COMPREPLY=($(compgen -W "${out[*]}" -- "$cur"))
    }

    # Config scope completion for `pos config <TAB>` — cached at gen time from
    # the "# POS_CONFIG:" registry (scanning all tools per TAB is too heavy).
    # Falls back to a live scan only if the cache is missing.
    _pos_config_scopes() {
        local scopes=()
        if declare -p _pos_config_scopes &>/dev/null; then
            scopes=("${_pos_config_scopes[@]}")
        else
            local f line scope
            for f in "$pos_dir"/pos-*; do
                [ -x "$f" ] || continue
                while IFS= read -r line; do
                    line="${line#*POS_CONFIG:}"
                    scope="${line%%|*}"
                    scope="${scope// }"
                    [ -n "$scope" ] && scopes+=("$scope")
                done < <(grep '^# POS_CONFIG:' "$f" 2>/dev/null || true)
            done
            mapfile -t scopes < <(printf '%s\n' "${scopes[@]}" | sort -u)
        fi
        COMPREPLY=($(compgen -W "${scopes[*]} --help" -- "$cur"))
    }

    # ── Dispatch ───────────────────────────────────────────────
    case "${#words[@]}" in
        2)
            _pos_complete_categories
            ;;
        3)
            case "${words[1]}" in
                config) _pos_config_scopes ;;
                *) _pos_complete_subcats ;;
            esac
            ;;
        4)
            case "${words[1]}-${words[2]}" in
                docker-compose)
                    case "${words[3]}" in
                        up|down|restart|logs)
                            _pos_complete_compose_services
                            ;;
                        *)
                            _pos_complete_compose_cmds
                            ;;
                    esac
                    ;;
                docker-vbox)
                    _pos_complete_docker_vbox_cmds
                    ;;
                entertainment-enable|entertainment-disable)
                    _pos_entertainment_plugins
                    ;;
                entertainment-config)
                    COMPREPLY=($(compgen -W "set --help" -- "$cur"))
                    ;;
                *)
                    _pos_complete_tool "${words[1]}-${words[2]}"
                    ;;
            esac
            ;;
        5)
            case "${words[1]}-${words[2]}" in
                docker-compose)
                    case "${words[3]}" in
                        up|down|restart|logs)
                            _pos_complete_compose_services
                            ;;
                    esac
                    ;;
                docker-vbox)
                    case "${words[3]}" in
                        create|enter|stop|start|rm)
                            _pos_complete_docker_vbox_names
                            ;;
                    esac
                    ;;
                *)
                    _pos_complete_tool "${words[1]}-${words[2]}-${words[3]}"
                    ;;
            esac
            ;;
        6)
            case "${words[1]}-${words[2]}" in
                docker-compose)
                    case "${words[3]}" in
                        up|down|restart|logs)
                            _pos_complete_compose_services
                            ;;
                    esac
                    ;;
                docker-vbox)
                    case "${words[3]}" in
                        create|enter|stop|start|rm)
                            _pos_complete_docker_vbox_names
                            ;;
                    esac
                    ;;
                *)
                    _pos_complete_tool "${words[1]}-${words[2]}-${words[3]}-${words[4]}"
                    ;;
            esac
            ;;
        7)
            case "${words[1]}-${words[2]}" in
                communication-telegram)
                    case "${words[5]}" in
                        --type) COMPREPLY=($(compgen -W "message file link sticker photo video audio voice animation" -- "$cur")) ;;
                        --parse-mode) COMPREPLY=($(compgen -W "plain markdown html" -- "$cur")) ;;
                    esac
                    ;;
            esac
            ;;
    esac
}

complete -F _pos pos
