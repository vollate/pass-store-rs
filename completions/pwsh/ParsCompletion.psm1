# ParsCompletion.psm1

function Get-PasswordStoreFiles {
    # 假设密码存储位于 ~/.password-store
    $storePath = "$env:HOME\.password-store"
    if (Test-Path $storePath) {
        Get-ChildItem -Path $storePath -Recurse -File | ForEach-Object {
            $_.FullName.Substring($storePath.Length + 1) -replace '\.gpg$', ''
        }
    } else {
        @()  # 如果目录不存在，返回空数组
    }
}

function ParsCompletion {
    param(
        [string]$wordToComplete,
        [string]$commandAst,
        [int]$cursorPosition
    )

    # 获取当前命令的上下文
    $commandElements = $commandAst.CommandElements
    $commandName = $commandElements[0].Value

    # 定义所有命令和选项
    $commands = @(
        "init", "grep", "find", "ls", "show", "insert", "edit", "generate",
        "rm", "mv", "cp", "git", "help"
    )

    $options = @(
        "-R", "--repo", "-h", "--help", "-V", "--version"
    )

    # 根据上下文提供补全建议
    if ($commandElements.Count -eq 2) {
        # 补全主命令
        $completions = $commands
    } elseif ($commandElements.Count -ge 3) {
        # 补全子命令或选项
        $currentCommand = $commandElements[1].Value

        switch ($currentCommand) {
            "init" {
                $completions = @()  # init 命令没有子命令
            }
            "grep" {
                $completions = @()  # grep 命令没有子命令
            }
            "find" {
                $completions = @()  # find 命令没有子命令
            }
            "ls" {
                $completions = Get-PasswordStoreFiles  # 动态生成 ls 命令的补全选项
            }
            "show" {
                $completions = @("--clip", "--qrcode")  # show 命令的选项
            }
            "insert" {
                $completions = @()  # insert 命令没有子命令
            }
            "edit" {
                $completions = @()  # edit 命令没有子命令
            }
            "generate" {
                $completions = @("--no-symbols", "--clip", "--force", "--replace")  # generate 命令的选项
            }
            "rm" {
                $completions = @("--recursive")  # rm 命令的选项
            }
            "mv" {
                $completions = @("--force")  # mv 命令的选项
            }
            "cp" {
                $completions = @("--force")  # cp 命令的选项
            }
            "git" {
                $completions = @("clone", "pull", "push", "commit", "status")  # git 子命令
            }
            "help" {
                $completions = $commands  # help 命令的子命令
            }
            default {
                $completions = $options  # 默认补全选项
            }
        }
    }

    # 过滤补全选项
    $completions | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

# 注册补全函数
Register-ArgumentCompleter -CommandName 'pars' -ScriptBlock $ParsCompletion -Native