function Get-PasswordStoreFiles {
    param(
        [string]$prefix = "",
        [string]$repoPath = ""
    )
    
    # Determine the password store path
    $storePath = if ($repoPath) { 
        $repoPath 
    } else { 
        if ($env:HOME) { "$env:HOME\.password-store" } else { "$env:USERPROFILE\.password-store" }
    }

    if (-not (Test-Path $storePath)) {
        return @()
    }

    $files = Get-ChildItem -Path $storePath -Recurse -File

    # Convert to relative paths
    $relativePaths = $files | ForEach-Object {
        $_.FullName.Substring($storePath.Length + 1) -replace '\\', '/' -replace '\.gpg$', ''
    }

    # If a prefix is provided, filter matching paths
    if ($prefix) {
        $relativePaths = $relativePaths | Where-Object { $_ -like "$prefix*" }
    }

    # Generate all subdirectory paths
    $allPaths = @()
    $processedDirs = @{ }
    
    foreach ($path in $relativePaths) {
        # Add full path
        $allPaths += $path
        
        # Add all levels of parent directory paths
        $parts = $path.Split('/')
        if ($parts.Length -gt 1) {
            $currentPath = ""
            for ($i = 0; $i -lt $parts.Length - 1; $i++) {
                if ($i -gt 0) {
                    $currentPath += "/"
                }
                $currentPath += $parts[$i]
                
                if (-not $processedDirs.ContainsKey($currentPath)) {
                    $allPaths += $currentPath
                    $processedDirs[$currentPath] = $true
                }
            }
        }
    }
    
    # Remove duplicates and sort the results
    $uniquePaths = $allPaths | Sort-Object -Unique
    
    return ,$uniquePaths
}

function ParsCompletion {
    param(
        [string]$wordToComplete,
        $commandAst,
        [int]$cursorPosition
    )

    $commandText = $commandAst.ToString()
    $commandElements = $commandText.Split()
    $commandCount = $commandElements.Count

    # Command definitions and descriptions
    $commandDefinitions = @{
        "init"     = "Initialize a new password store or reinitialize an existing one"
        "grep"     = "Search for a string in all files, regex is supported"
        "find"     = "Find a password by name"
        "ls"       = "List all passwords in the store or a sub-folder"
        "show"     = "Show a password, optionally clip or qrcode it"
        "insert"   = "Insert a new password"
        "edit"     = "Edit a password using specified editor"
        "generate" = "Generate a new password of specified length"
        "rm"       = "Remove a password or a sub-folder"
        "mv"       = "Move a password or a sub-folder from old-path to new-path"
        "cp"       = "Copy a password or a sub-folder from old-path to new-path"
        "git"      = "Run a git command with the password store as the working directory"
    }

    # Global option definitions and descriptions
    $optionDefinitions = @{
        "-R"        = "specify password store directory"
        "--repo"    = "specify password store directory"
        "-h"        = "print help message"
        "--help"    = "print help message"
        "-V"        = "print version info"
        "--version" = "print version info"
    }

    # Mapping of short and long global options
    $globalOptionMap = @{
        "-R" = "--repo"
        "-h" = "--help"
        "-V" = "--version"
    }

    # Subcommand option definitions and descriptions
    $subCommandOptionDefinitions = @{
        "generate" = @{
            "-c"           = "copy password to the clipboard"
            "--clip"       = "copy password to the clipboard"
            "-n"           = "don't include symbols in password"
            "--no-symbols" = "don't include symbols in password"
            "-f"           = "force overwrite"
            "--force"      = "force overwrite"
            "-i"           = "replace first line"
            "--in-place"   = "replace first line"
        }
        "show"     = @{
            "-c"       = "copy password to the clipboard"
            "--clip"   = "copy password to the clipboard"
            "-q"       = "display password as QR code"
            "--qrcode" = "display password as QR code"
        }
        "rm"       = @{
            "-r"          = "recursively remove directory"
            "--recursive" = "recursively remove directory"
        }
        "mv"       = @{
            "-f"      = "force move without confirmation"
            "--force" = "force move without confirmation"
        }
        "cp"       = @{
            "-f"      = "force copy without confirmation"
            "--force" = "force copy without confirmation"
        }
    }

    # Mapping of short and long subcommand options
    $shortToLongOptions = @{
        "generate" = @{
            "-c" = "--clip"
            "-n" = "--no-symbols"
            "-f" = "--force"
            "-i" = "--in-place"
        }
        "show" = @{
            "-c" = "--clip"
            "-q" = "--qrcode"
        }
        "rm" = @{
            "-r" = "--recursive"
        }
        "mv" = @{
            "-f" = "--force"
        }
        "cp" = @{
            "-f" = "--force"
        }
    }

    # Main command list
    $mainCommands = @("init", "grep", "find", "ls", "show", "insert", "edit", "generate", "rm", "mv", "cp", "git")
    
    # Alias mapping
    $commandAliases = @{
        "search" = "find"
        "list"   = "ls"
        "add"    = "insert"
        "remove" = "rm"
        "delete" = "rm"
        "move"   = "mv"
        "copy"   = "cp"
    }

    # Add descriptions for aliases
    $commandAliases.Keys | ForEach-Object {
        $aliasedCommand = $commandAliases[$_]
        if ($commandDefinitions.ContainsKey($aliasedCommand)) {
            $commandDefinitions[$_] = "[$aliasedCommand] " + $commandDefinitions[$aliasedCommand]
        }
    }
    
    # Add aliases to the main command list for completion
    $mainCommandsWithAliases = $mainCommands + $commandAliases.Keys
    
    $globalOptions = @("-R", "--repo", "-h", "--help", "-V", "--version")
    $Help_Args= @("-h", "--help")

    # Parse command-line arguments to find custom repository path
    $customRepoPath = ""
    for ($i = 0; $i -lt $commandElements.Count - 1; $i++) {
        if (($commandElements[$i] -eq "-R" -or $commandElements[$i] -eq "--repo") -and ($i + 1 -lt $commandElements.Count)) {
            $customRepoPath = $commandElements[$i + 1]
            break
        }
    }

    # Determine if completing a file path
    $isCompletingPath = $false
    $pathPrefix = ""
    $mainCommand = ""
    
    if ($commandCount -ge 2) {
        # Skip global options to find the main command
        $cmdIndex = 1
        while ($cmdIndex -lt $commandCount) {
            if ($commandElements[$cmdIndex] -in @("-R", "--repo")) {
                $cmdIndex += 2  # Skip option and its value
                continue
            }
            if ($commandElements[$cmdIndex] -in $globalOptions) {
                $cmdIndex++
                continue
            }
            
            $mainCommand = $commandElements[$cmdIndex]
            break
        }
        
        # If an alias is used, convert to the corresponding main command
        if ($commandAliases.ContainsKey($mainCommand)) {
            $mainCommand = $commandAliases[$mainCommand]
        }
        
        $commandsThatNeedPath = @("show", "rm", "mv", "cp", "ls", "edit", "generate")
        
        # Modify logic: only complete paths for the last argument if it's not an option
        if ($commandsThatNeedPath -contains $mainCommand) {
            $lastArg = $commandElements[-1]
            if (-not $lastArg.StartsWith('-')) {
                $isCompletingPath = $true
                if ($cursorPosition -eq $commandText.Length) {
                    $pathPrefix = $wordToComplete
                }
            }
        }
    }

    # Check if completing the value for -R/--repo
    $isCompletingRepo = $false
    if ($commandCount -ge 2 && $cursorPosition -eq $commandText.Length) {
        $prevArg = $commandElements[-2]
        if ($prevArg -eq "-R" -or $prevArg -eq "--repo") {
            $isCompletingRepo = $true
        }
    }

    $subCommandParams = @{
        "generate" = { 
            if ($isCompletingPath) {
                # Return parameter options first, then file paths
                @("-c", "-n", "-f", "-i", "--clip", "--no-symbols", "--force", "--in-place", "-h", "--help", "-R", "--repo", "-V", "--version") + 
                (Get-PasswordStoreFiles -prefix $pathPrefix -repoPath $customRepoPath)
            } else {
                @("-c", "-n", "-f", "-i", "--clip", "--no-symbols", "--force", "--in-place", "-h", "--help", "-R", "--repo", "-V", "--version") + 
                (Get-PasswordStoreFiles -repoPath $customRepoPath)
            }
        }
        "show"     = { 
            if ($isCompletingPath) {
                @("-c", "-q", "--clip", "--qrcode", "-h", "--help", "-R", "--repo", "-V", "--version") + 
                (Get-PasswordStoreFiles -prefix $pathPrefix -repoPath $customRepoPath)
            } else {
                @("-c", "-q", "--clip", "--qrcode", "-h", "--help", "-R", "--repo", "-V", "--version") + 
                (Get-PasswordStoreFiles -repoPath $customRepoPath)
            }
        }
        "rm"       = { 
            if ($isCompletingPath) {
                @("-r", "--recursive", "-h", "--help", "-R", "--repo", "-V", "--version") + 
                (Get-PasswordStoreFiles -prefix $pathPrefix -repoPath $customRepoPath)
            } else {
                @("-r", "--recursive", "-h", "--help", "-R", "--repo", "-V", "--version") + 
                (Get-PasswordStoreFiles -repoPath $customRepoPath)
            }
        }
        "mv"       = { 
            if ($isCompletingPath) {
                @("-f", "--force", "-h", "--help", "-R", "--repo", "-V", "--version") + 
                (Get-PasswordStoreFiles -prefix $pathPrefix -repoPath $customRepoPath)
            } else {
                @("-f", "--force", "-h", "--help", "-R", "--repo", "-V", "--version") + 
                (Get-PasswordStoreFiles -repoPath $customRepoPath)
            }
        }
        "cp"       = { 
            if ($isCompletingPath) {
                @("-f", "--force", "-h", "--help", "-R", "--repo", "-V", "--version") + 
                (Get-PasswordStoreFiles -prefix $pathPrefix -repoPath $customRepoPath)
            } else {
                @("-f", "--force", "-h", "--help", "-R", "--repo", "-V", "--version") + 
                (Get-PasswordStoreFiles -repoPath $customRepoPath)
            }
        }
        "ls"       = { 
            if ($isCompletingPath) {
                (Get-PasswordStoreFiles -prefix $pathPrefix -repoPath $customRepoPath) + 
                @("-h", "--help", "-R", "--repo", "-V", "--version")
            } else {
                (Get-PasswordStoreFiles -repoPath $customRepoPath) + 
                @("-h", "--help", "-R", "--repo", "-V", "--version")
            }
        }
        "edit"     = { 
            if ($isCompletingPath) {
                (Get-PasswordStoreFiles -prefix $pathPrefix -repoPath $customRepoPath) + 
                @("-h", "--help", "-R", "--repo", "-V", "--version")
            } else {
                (Get-PasswordStoreFiles -repoPath $customRepoPath) + 
                @("-h", "--help", "-R", "--repo", "-V", "--version")
            }
        }
        "find"     = { 
            @("-h", "--help", "-R", "--repo", "-V", "--version")
        }
    }

    $completions = @()
    
    # If completing repository path, provide directory completion
    if ($isCompletingRepo) {
        $dirToComplete = $wordToComplete
        if ([string]::IsNullOrEmpty($dirToComplete)) {
            $dirToComplete = "."
        }
        
        try {
            $directories = Get-ChildItem -Path $dirToComplete -Directory -ErrorAction SilentlyContinue
            $completions = $directories | ForEach-Object { $_.FullName }
        }
        catch {
            # If an error occurs, ignore and do not return completions
            $completions = @()
        }
    }
    # Handle case with only pars command
    elseif ($commandCount -eq 1) {
        $completions = $mainCommandsWithAliases + $globalOptions
    }
    # Handle partial main command input (e.g., "pars l")
    elseif ($commandCount -eq 2 -and $cursorPosition -eq $commandText.Length) {
        $partialCommand = $commandElements[1]
        $completions = $mainCommandsWithAliases + $globalOptions | Where-Object { $_ -like "$partialCommand*" }
    }
    # Full main command or alias is present
    elseif ($mainCommand) {
        # Provide subcommand parameter completions
        if ($subCommandParams.ContainsKey($mainCommand)) {
            $completions = & $subCommandParams[$mainCommand]
        }
    }

    # Ensure matches current prefix
    if ($wordToComplete -and -not $isCompletingRepo) {
        $completions = $completions | Where-Object { $_ -like "$wordToComplete*" }
    }

    # Get store path for directory check
    $storePath = if ($customRepoPath) { 
        $customRepoPath 
    } else { 
        if ($env:HOME) { "$env:HOME\.password-store" } else { "$env:USERPROFILE\.password-store" }
    }

    # Create completion results
    $results = @()
    foreach ($item in $completions) {
        $completionText = $item
        $listItemText = $item
        $resultType = 'ParameterValue'
        $tooltipText = $item

        # Handle command display format
        if ($mainCommandsWithAliases -contains $item) {
            # If it's a main command or alias
            $description = ""
            if ($commandDefinitions.ContainsKey($item)) {
                $description = " -- " + $commandDefinitions[$item]
                $tooltipText = $commandDefinitions[$item]
            }
            
            # Format display text, ensure alignment
            $paddingLength = [Math]::Max(1, 20 - $item.Length)
            $padding = " " * $paddingLength
            $listItemText = "$item$padding$description"
            $resultType = 'Command'
        }
        # Handle global option display format
        elseif ($globalOptions -contains $item) {
            $description = $optionDefinitions[$item]
            $tooltipText = $description
            
            # Find corresponding short or long option
            $optionPair = ""
            if ($item.StartsWith("--")) {
                # Long option, find short option
                $shortOption = $globalOptionMap.Keys | Where-Object { $globalOptionMap[$_] -eq $item } | Select-Object -First 1
                if ($shortOption) {
                    $optionPair = $shortOption
                }
            } else {
                # Short option, find long option
                if ($globalOptionMap.ContainsKey($item)) {
                    $optionPair = $globalOptionMap[$item]
                }
            }

            # Format display, ensure alignment
            if ($optionPair) {
                if ($item.StartsWith("--")) {
                    # Long option first, short option after
                    $paddedOption = $item.PadRight(12)
                    $listItemText = "$paddedOption $optionPair  -- $description"
                } else {
                    # Short option after, long option first
                    $paddedOption = $optionPair.PadRight(12)
                    $listItemText = "$paddedOption $item  -- $description"
                }
            } else {
                # No corresponding option pair
                $paddedOption = $item.PadRight(12)
                $listItemText = "$paddedOption     -- $description"
            }
            
            $resultType = 'ParameterName'
        }
        # Handle subcommand option display format
        elseif ($mainCommand -and $subCommandOptionDefinitions.ContainsKey($mainCommand) -and 
                $subCommandOptionDefinitions[$mainCommand].ContainsKey($item)) {
            $description = $subCommandOptionDefinitions[$mainCommand][$item]
            $tooltipText = $description
            
            # Find short or long option corresponding to the other form
            $optionPair = ""
            if ($item.StartsWith("--")) {
                # If long option, find short option
                $shortOption = $shortToLongOptions[$mainCommand].Keys | Where-Object { $shortToLongOptions[$mainCommand][$_] -eq $item } | Select-Object -First 1
                if ($shortOption) {
                    $optionPair = $shortOption
                }
            } else {
                # If short option, find long option
                if ($shortToLongOptions[$mainCommand].ContainsKey($item)) {
                    $optionPair = $shortToLongOptions[$mainCommand][$item]
                }
            }
            
            # Format display, ensure alignment
            if ($optionPair) {
                if ($item.StartsWith("--")) {
                    # Long option first, short option after
                    $paddedOption = $item.PadRight(12)
                    $listItemText = "$paddedOption $optionPair  -- $description"
                } else {
                    # Short option after, long option first
                    $paddedOption = $optionPair.PadRight(12)
                    $listItemText = "$paddedOption $item  -- $description"
                }
            } else {
                # No corresponding option pair
                $paddedOption = $item.PadRight(12)
                $listItemText = "$paddedOption     -- $description"
            }
            
            $resultType = 'ParameterName'
        }
        # Handle alias display
        elseif ($commandAliases.ContainsKey($item)) {
            $tooltipText = "Alias for: $($commandAliases[$item])"
        }
        # Handle file path display
        elseif ($isCompletingPath) {
            if (-not $item.Contains("/") -and (Test-Path "$storePath\$item") -and (Get-Item "$storePath\$item").PSIsContainer) {
                $listItemText = "$item/"
                $tooltipText = "[Directory] $item/"
            } else {
                $tooltipText = "[Password] $item"
            }
        }
        # Handle repository path completion
        elseif ($isCompletingRepo) {
            $listItemText = "$item\"
            $tooltipText = "[Directory] $item/"
        }

        $results += [System.Management.Automation.CompletionResult]::new(
            $completionText,  # Actual text to insert
            $listItemText,    # Formatted text to display in the list
            $resultType,      # Result type
            $tooltipText      # Tooltip
        )
    }

    return $results
}

Register-ArgumentCompleter -CommandName 'pars' -ScriptBlock $Function:ParsCompletion -Native
