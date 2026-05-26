# bash completion for pars                                 -*- shell-script -*-

_pars_store_entries() {
    local store_dir

    # Check if -R or --repo was specified on the command line
    local i
    for ((i = 1; i < cword; i++)); do
        if [[ "${words[i]}" == "-R" || "${words[i]}" == "--repo" ]]; then
            if [[ $((i + 1)) -lt cword ]]; then
                store_dir="${words[i + 1]}"
            fi
            break
        elif [[ "${words[i]}" == --repo=* ]]; then
            store_dir="${words[i]#--repo=}"
            break
        elif [[ "${words[i]}" == -R=* ]]; then
            store_dir="${words[i]#-R=}"
            break
        fi
    done

    # Fall back to environment variable or default
    if [[ -z "$store_dir" ]]; then
        store_dir="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
    fi

    # Return if the store directory doesn't exist
    [[ -d "$store_dir" ]] || return

    # List .gpg files, stripping the prefix and .gpg extension
    local entry
    while IFS= read -r entry; do
        entry="${entry#"$store_dir"/}"
        entry="${entry%.gpg}"
        COMPREPLY+=("$entry")
    done < <(find "$store_dir" -type f -name '*.gpg' 2>/dev/null | sort)

    # Also list subdirectories (strip trailing slash and prefix)
    while IFS= read -r entry; do
        entry="${entry#"$store_dir"/}"
        COMPREPLY+=("$entry/")
    done < <(find "$store_dir" -type d -not -name '.*' -not -path "$store_dir" 2>/dev/null | sort)

    # Filter results by current word
    if [[ -n "$cur" ]]; then
        local filtered=()
        for entry in "${COMPREPLY[@]}"; do
            if [[ "$entry" == "$cur"* ]]; then
                filtered+=("$entry")
            fi
        done
        COMPREPLY=("${filtered[@]}")
    fi
}

_pars() {
    local cur prev words cword
    _init_completion || return

    local subcommands="init grep find search ls list show insert add edit generate rm remove delete mv rename move cp copy git"
    local global_opts="-R --repo -h --help -V --version"

    # Find the subcommand
    local subcmd=""
    local subcmd_idx=0
    local i
    for ((i = 1; i < cword; i++)); do
        # Skip -R/--repo and its argument
        if [[ "${words[i]}" == "-R" || "${words[i]}" == "--repo" ]]; then
            ((i++))
            continue
        elif [[ "${words[i]}" == --repo=* || "${words[i]}" == -R=* ]]; then
            continue
        fi
        # Skip other global options
        if [[ "${words[i]}" == -* ]]; then
            continue
        fi
        # First non-option word is the subcommand
        subcmd="${words[i]}"
        subcmd_idx=$i
        break
    done

    # Resolve aliases to canonical subcommand names
    case "$subcmd" in
        search) subcmd="find" ;;
        list) subcmd="ls" ;;
        add) subcmd="insert" ;;
        remove|delete) subcmd="rm" ;;
        rename|move) subcmd="mv" ;;
        copy) subcmd="cp" ;;
    esac

    # If completing the value for -R/--repo, offer directory completion
    if [[ "$prev" == "-R" || "$prev" == "--repo" ]]; then
        _filedir -d
        return
    fi

    # If no subcommand yet, complete subcommands and global options
    if [[ -z "$subcmd" ]]; then
        if [[ "$cur" == -* ]]; then
            COMPREPLY=($(compgen -W "$global_opts" -- "$cur"))
        else
            COMPREPLY=($(compgen -W "$subcommands" -- "$cur"))
        fi
        return
    fi

    # Per-subcommand completion
    case "$subcmd" in
        init)
            local opts="-p --path -h --help"
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "$opts" -- "$cur"))
            fi
            ;;
        grep)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "-h --help" -- "$cur"))
            fi
            ;;
        find)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "-h --help" -- "$cur"))
            fi
            ;;
        ls)
            local opts="-c --clip -q --qrcode -h --help"
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "$opts" -- "$cur"))
            else
                _pars_store_entries
            fi
            ;;
        show)
            local opts="-c --clip -q --qrcode -h --help"
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "$opts" -- "$cur"))
            else
                _pars_store_entries
            fi
            ;;
        insert)
            local opts="-e --echo -m --multiline -f --force -h --help"
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "$opts" -- "$cur"))
            fi
            ;;
        edit)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "-h --help" -- "$cur"))
            else
                _pars_store_entries
            fi
            ;;
        generate)
            local opts="-n --no-symbols -c --clip -i --in-place -f --force -h --help"
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "$opts" -- "$cur"))
            else
                _pars_store_entries
            fi
            ;;
        rm)
            local opts="-r --recursive -f --force -h --help"
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "$opts" -- "$cur"))
            else
                _pars_store_entries
            fi
            ;;
        mv)
            local opts="-f --force -h --help"
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "$opts" -- "$cur"))
            else
                _pars_store_entries
            fi
            ;;
        cp)
            local opts="-f --force -h --help"
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "$opts" -- "$cur"))
            else
                _pars_store_entries
            fi
            ;;
        git)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "-h --help" -- "$cur"))
            fi
            ;;
    esac
}

complete -o filenames -F _pars pars
