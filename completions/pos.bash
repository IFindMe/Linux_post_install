#!/usr/bin/env bash
# Bash completion for pos — dynamically discovers pos-* subcommands
# Install: source this file in ~/.bashrc or place in /etc/bash_completion.d/

# Command names are discovered dynamically below; these maps are optional
# per-tool flag/subcommand hints (empty = generic completion only).
declare -A _pos_flags=()
declare -A _pos_subcmds=()

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
        local solos=()
        for cmd in "${all_cmds[@]}"; do
            local cat_c="${cmd%%-*}"
            if [ "$cat_c" = "$cmd" ] && [ -z "${cat_cmds[$cmd]:-}" ]; then
                solos+=("$cmd")
            fi
        done
        COMPREPLY=($(compgen -W "${!cat_cmds[*]} ${solos[*]}" -- "$cur"))
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

    _pos_complete_docker_vbox_cmds() {
        COMPREPLY=($(compgen -W "create enter stop start rm ls" -- "$cur"))
    }

    _pos_complete_docker_vbox_names() {
        local names
        names=$(docker ps -a --filter label=linux_post_install.vbox=true --format '{{.Names}}' 2>/dev/null)
        COMPREPLY=($(compgen -W "$names" -- "$cur"))
    }

    # ── Dispatch ───────────────────────────────────────────────
    case "${#words[@]}" in
        2)
            _pos_complete_categories
            ;;
        3)
            if [[ "${words[1]}" == *-* ]]; then
                _pos_complete_subcats
            else
                _pos_complete_tool "${words[1]}"
            fi
            ;;
        4)
            case "${words[1]}-${words[2]}" in
                docker-vbox)
                    _pos_complete_docker_vbox_cmds
                    ;;
                *)
                    _pos_complete_tool "${words[1]}-${words[2]}"
                    ;;
            esac
            ;;
        5)
            case "${words[1]}-${words[2]}" in
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
    esac
}

complete -F _pos pos
