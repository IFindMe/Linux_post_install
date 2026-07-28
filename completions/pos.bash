#!/usr/bin/env bash
# Bash completion for pos — dynamically discovers pos-* subcommands
# Install: source this file in ~/.bashrc or place in /etc/bash_completion.d/

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
    local -A cat_cmds
    for cmd in "${all_cmds[@]}"; do
        local cat="${cmd%%-*}"
        local sub="${cmd#*-}"
        if [ "$cat" != "$cmd" ]; then
            cat_cmds["$cat"]+="${sub} "
        fi
    done

    # ── Helpers ────────────────────────────────────────────────
    _pos_complete_categories() {
        COMPREPLY=($(compgen -W "${!cat_cmds[*]}" -- "$cur"))
    }

    _pos_complete_subcats() {
        local cat="${words[1]}"
        COMPREPLY=($(compgen -W "${cat_cmds[$cat]:-}" -- "$cur"))
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

    _pos_complete_vbox_cmds() {
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
            _pos_complete_subcats
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
                vbox-*)
                    _pos_complete_vbox_cmds
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
                vbox-create|vbox-enter|vbox-stop|vbox-start|vbox-rm)
                    _pos_complete_docker_vbox_names
                    ;;
            esac
            ;;
    esac
}

complete -F _pos pos
