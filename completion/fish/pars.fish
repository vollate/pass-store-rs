# Fish shell completions for pars (password store)

# Helper: returns true when no subcommand has been given yet
function __pars_needs_command
    set -l cmd (commandline -opc)
    set -l i 2
    while test $i -le (count $cmd)
        switch $cmd[$i]
            case '-R' '--repo'
                # Skip option and its argument
                set i (math $i + 2)
            case '-h' '--help' '-V' '--version'
                set i (math $i + 1)
            case '-*'
                set i (math $i + 1)
            case '*'
                return 1
        end
    end
    return 0
end

# Helper: returns true when the given subcommand is the active one
function __pars_using_command
    set -l subcmd $argv[1]
    set -l cmd (commandline -opc)
    set -l i 2
    while test $i -le (count $cmd)
        switch $cmd[$i]
            case '-R' '--repo'
                set i (math $i + 2)
            case '-h' '--help' '-V' '--version'
                set i (math $i + 1)
            case '-*'
                set i (math $i + 1)
            case '*'
                if test "$cmd[$i]" = "$subcmd"
                    return 0
                end
                return 1
        end
    end
    return 1
end

# Helper: returns true when any of the given subcommands is active
function __pars_using_any_command
    for subcmd in $argv
        if __pars_using_command $subcmd
            return 0
        end
    end
    return 1
end

# Dynamic: list password store entries
function __pars_store_entries
    # Determine store directory
    set -l store_dir
    if set -q PASSWORD_STORE_DIR; and test -n "$PASSWORD_STORE_DIR"
        set store_dir "$PASSWORD_STORE_DIR"
    else
        set store_dir "$HOME/.password-store"
    end

    # Check for -R/--repo override in the current commandline
    set -l cmd (commandline -opc)
    set -l i 2
    while test $i -le (count $cmd)
        switch $cmd[$i]
            case '-R' '--repo'
                set -l next (math $i + 1)
                if test $next -le (count $cmd)
                    set store_dir $cmd[$next]
                end
                set i (math $i + 2)
            case '*'
                set i (math $i + 1)
        end
    end

    # If store directory doesn't exist, return nothing
    if not test -d "$store_dir"
        return
    end

    # List .gpg files, stripping prefix and extension
    find "$store_dir" -name '*.gpg' -type f 2>/dev/null | while read -l file
        set -l entry (string replace -r "^$store_dir/?" "" -- "$file")
        set -l entry (string replace -r '\.gpg$' '' -- "$entry")
        # Skip .gpg-id files
        if not string match -q '*.gpg-id*' -- "$entry"
            echo $entry
        end
    end

    # List directories (subfolders), excluding hidden ones and .git
    find "$store_dir" -type d -not -name '.*' -not -path '*/.git/*' 2>/dev/null | while read -l dir
        if test "$dir" != "$store_dir"
            set -l entry (string replace -r "^$store_dir/?" "" -- "$dir")
            if test -n "$entry"
                echo "$entry/"
            end
        end
    end
end

# Disable file completions for pars
complete -c pars -f

# ============================================================
# Subcommand completions (shown when no subcommand given yet)
# ============================================================
complete -c pars -f -n '__pars_needs_command' -a 'init' -d 'Initialize new password store'
complete -c pars -f -n '__pars_needs_command' -a 'grep' -d 'Search for a string in all files'
complete -c pars -f -n '__pars_needs_command' -a 'find' -d 'Find a password by name'
complete -c pars -f -n '__pars_needs_command' -a 'search' -d 'Find a password by name (alias for find)'
complete -c pars -f -n '__pars_needs_command' -a 'ls' -d 'List passwords'
complete -c pars -f -n '__pars_needs_command' -a 'list' -d 'List passwords (alias for ls)'
complete -c pars -f -n '__pars_needs_command' -a 'show' -d 'Show a password'
complete -c pars -f -n '__pars_needs_command' -a 'insert' -d 'Insert a new password'
complete -c pars -f -n '__pars_needs_command' -a 'add' -d 'Insert a new password (alias for insert)'
complete -c pars -f -n '__pars_needs_command' -a 'edit' -d 'Edit a password'
complete -c pars -f -n '__pars_needs_command' -a 'generate' -d 'Generate a new password'
complete -c pars -f -n '__pars_needs_command' -a 'rm' -d 'Remove a password'
complete -c pars -f -n '__pars_needs_command' -a 'remove' -d 'Remove a password (alias for rm)'
complete -c pars -f -n '__pars_needs_command' -a 'delete' -d 'Remove a password (alias for rm)'
complete -c pars -f -n '__pars_needs_command' -a 'mv' -d 'Move/rename a password'
complete -c pars -f -n '__pars_needs_command' -a 'rename' -d 'Move/rename a password (alias for mv)'
complete -c pars -f -n '__pars_needs_command' -a 'move' -d 'Move/rename a password (alias for mv)'
complete -c pars -f -n '__pars_needs_command' -a 'cp' -d 'Copy a password'
complete -c pars -f -n '__pars_needs_command' -a 'copy' -d 'Copy a password (alias for cp)'
complete -c pars -f -n '__pars_needs_command' -a 'git' -d 'Run git command on the store'
complete -c pars -f -n '__pars_needs_command' -a 'completion' -d 'Generate shell completions'

# ============================================================
# Global options (available at any position)
# ============================================================
complete -c pars -f -n '__pars_needs_command' -s R -l repo -r -d 'Specify password store directory'
complete -c pars -f -n '__pars_needs_command' -s h -l help -d 'Print help'
complete -c pars -f -n '__pars_needs_command' -s V -l version -d 'Print version'

# ============================================================
# init options
# ============================================================
complete -c pars -f -n '__pars_using_any_command init' -s p -l path -r -d 'Initialize sub-folder'
complete -c pars -f -n '__pars_using_any_command init' -s h -l help -d 'Print help'

# ============================================================
# ls / list options
# ============================================================
complete -c pars -f -n '__pars_using_any_command ls list' -s c -l clip -d 'Copy to clipboard'
complete -c pars -f -n '__pars_using_any_command ls list' -s q -l qrcode -d 'Display as QR code'
complete -c pars -f -n '__pars_using_any_command ls list' -s h -l help -d 'Print help'
complete -c pars -f -n '__pars_using_any_command ls list' -a '(__pars_store_entries)'

# ============================================================
# show options
# ============================================================
complete -c pars -f -n '__pars_using_any_command show' -s c -l clip -d 'Copy to clipboard'
complete -c pars -f -n '__pars_using_any_command show' -s q -l qrcode -d 'Display as QR code'
complete -c pars -f -n '__pars_using_any_command show' -s h -l help -d 'Print help'
complete -c pars -f -n '__pars_using_any_command show' -a '(__pars_store_entries)'

# ============================================================
# insert / add options
# ============================================================
complete -c pars -f -n '__pars_using_any_command insert add' -s e -l echo -d 'Echo input'
complete -c pars -f -n '__pars_using_any_command insert add' -s m -l multiline -d 'Multiline input'
complete -c pars -f -n '__pars_using_any_command insert add' -s f -l force -d 'Force overwrite'
complete -c pars -f -n '__pars_using_any_command insert add' -s h -l help -d 'Print help'

# ============================================================
# edit options
# ============================================================
complete -c pars -f -n '__pars_using_any_command edit' -s h -l help -d 'Print help'
complete -c pars -f -n '__pars_using_any_command edit' -a '(__pars_store_entries)'

# ============================================================
# generate options
# ============================================================
complete -c pars -f -n '__pars_using_any_command generate' -s n -l no-symbols -d 'No symbols'
complete -c pars -f -n '__pars_using_any_command generate' -s c -l clip -d 'Copy to clipboard'
complete -c pars -f -n '__pars_using_any_command generate' -s i -l in-place -d 'Replace first line'
complete -c pars -f -n '__pars_using_any_command generate' -s f -l force -d 'Force overwrite'
complete -c pars -f -n '__pars_using_any_command generate' -s h -l help -d 'Print help'
complete -c pars -f -n '__pars_using_any_command generate' -a '(__pars_store_entries)'

# ============================================================
# rm / remove / delete options
# ============================================================
complete -c pars -f -n '__pars_using_any_command rm remove delete' -s r -l recursive -d 'Remove recursively'
complete -c pars -f -n '__pars_using_any_command rm remove delete' -s f -l force -d 'Force removal'
complete -c pars -f -n '__pars_using_any_command rm remove delete' -s h -l help -d 'Print help'
complete -c pars -f -n '__pars_using_any_command rm remove delete' -a '(__pars_store_entries)'

# ============================================================
# mv / rename / move options
# ============================================================
complete -c pars -f -n '__pars_using_any_command mv rename move' -s f -l force -d 'Force move'
complete -c pars -f -n '__pars_using_any_command mv rename move' -s h -l help -d 'Print help'
complete -c pars -f -n '__pars_using_any_command mv rename move' -a '(__pars_store_entries)'

# ============================================================
# cp / copy options
# ============================================================
complete -c pars -f -n '__pars_using_any_command cp copy' -s f -l force -d 'Force copy'
complete -c pars -f -n '__pars_using_any_command cp copy' -s h -l help -d 'Print help'
complete -c pars -f -n '__pars_using_any_command cp copy' -a '(__pars_store_entries)'

# ============================================================
# git options
# ============================================================
complete -c pars -f -n '__pars_using_any_command git' -s h -l help -d 'Print help'

# ============================================================
# grep options
# ============================================================
complete -c pars -f -n '__pars_using_any_command grep' -s h -l help -d 'Print help'

# ============================================================
# find / search options
# ============================================================
complete -c pars -f -n '__pars_using_any_command find search' -s h -l help -d 'Print help'

# ============================================================
# completion subcommand
# ============================================================
complete -c pars -f -n '__pars_using_any_command completion' -a 'install' -d 'Install shell completions'
complete -c pars -f -n '__pars_using_any_command completion' -a 'uninstall' -d 'Uninstall shell completions'
complete -c pars -f -n '__pars_using_any_command completion' -a 'generate' -d 'Generate shell completions'
complete -c pars -f -n '__pars_using_any_command completion' -s s -l shell -r -d 'Target shell'
complete -c pars -f -n '__pars_using_any_command completion' -s h -l help -d 'Print help'

# Shell values for completion --shell
complete -c pars -f -n '__pars_using_any_command completion; and __fish_seen_argument -s s -l shell' -a 'bash zsh fish powershell'
