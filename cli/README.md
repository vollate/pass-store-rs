# pars-cli

`pars` is a cross-platform [zx2c4-pass](https://www.passwordstore.org/) compatible CLI tool for managing your password store.

## Dependencies

To use `pars-cli`, ensure your system has the following dependencies installed:

- `gpg2`: for encryption and decryption (any program that implements the PGP standard, such as GnuPG or OpenPGP)
- `git`: for version control

Refer to the [Installation](#installation) section for installation details.

## Installation

We are trying to package `pars-cli` to more package managers. If you want to help, feel free to open an issue or PR.

<!--### Package Manager-->

<!--#### Arch Linux-->

<!--You can install `pars` from the AUR using your favorite AUR helper. For example, with `yay`-->

<!--```shell-->
<!--yay -S pars-cli-->
<!--```-->

<!--or `paru`:-->

<!--```shell-->
<!--paru -S pars-cli-->
<!--```-->

<!--#### MacOS-->

<!--You can install `pars` from the [homebrew](https://brew.sh/) using the following command:-->

<!--```shell-->
<!--brew tap pars-->
<!--brew install pars-cli-->
<!--```-->
<!--[>todo<]-->

<!--#### Windows-->

<!--You can install `pars` from the [scoop](https://scoop.sh/) using the following command:-->

<!--```shell-->
<!--scoop add bucket xxxx-->
<!--scoop install pars-cli-->
<!--```-->
### Cargo

Install `pars-cli` using Cargo:

```shell
cargo install pars-cli
```

<!-- Additional package manager instructions (AUR, Homebrew, Scoop) to be added here -->

## Usage

> **Already familiar with `pass`? You can skip this section and go straight to the [Differences](#differences).**

`pars` is largely compatible with `pass`, supporting the same core commands:

```shell
# Initialize the password store
pars init <your-gpg-id>

# List all stored entries
pars ls

# Add a new password
pars insert <path/to/password>

# Generate a password
pars generate <path/to/password> <length>  # -c to copy to clipboard

# Show a password
pars show <path/to/password>               # -c to copy / -q to show QR code

# Edit a password
pars edit <path/to/password>
# Default editor is 'vim' on Unix and 'notepad' on Windows.
# You can configure this in the config file.

# Remove a password
pars rm <path/to/password>                 # -r to remove recursively from git

# Search passwords by name
pars find <name>

# Search passwords by content
pars grep <content>
```

## Differences

While `pars` aims for full compatibility with `pass`, a few key differences exist:

1. **Option Placement for `-c` and `-q`**

   If `-c` (clipboard) or `-q` (QR code) is used and followed directly by arguments (like a path), you must either:

```sh
pars show -c <path/to/password>        # ❌ Cause error
pars show -c -- <path/to/password>     # ✅ OK
pars show -c0 <path/to/password>       # ✅ Safe, the line 0 will be regarded as the frist line
pars show -c 0 <path/to/password>      # ✅ You can also separte them
pars show <path/to/password> -q        # ✅ OK
```

<details>
<summary>Why <code>pars</code> and <code>pass</code> differ in argument parsing</summary>
<div>
<p><code>pars</code> uses the <a href="https://docs.rs/clap">Rust Clap</a> library for parsing command-line arguments. Clap is a modern, strongly typed argument parser that conforms to POSIX standards. It enforces clear separation between options and positional arguments, especially when options accept optional values or multiple values.</p>

<p>In contrast, <code>pass</code> is written in Bash and parses arguments manually using shell constructs like <code>shift</code>, <code>case</code>, and <code>getopts</code>. This gives <code>pass</code> more lenient and flexible handling of ambiguous argument positions, but it also results in inconsistent behavior between versions or environments.</p>

<p>Because of these fundamental differences, some <code>pass</code>-style invocations must be adjusted slightly when used with <code>pars</code>.</p>
</div>
</details>

2. **Configuration via File**

   Unlike `pass`, `pars` does not rely on environment variables for configuration. All settings are managed through a dedicated config file. You can change the config file location by setting the `PARS_CONFIG_PATH` environment variable.

3. **No Plugin Support (Yet)**

   Plugin support is currently not available, but may be considered in future versions.

## Configuration

The configuration file's default location depends on your operating system:

- **Linux**: `~/.config/pars/config.toml`
- **macOS**: `~/Library/Application Support/pars/config.toml`
- **Windows**: `%APPDATA%/pars/config.toml`

If no config file is found or some options are not set, `pars` will use the default values to fill the missing parts.

You can copy and modify the following default config file to make your own:

```toml
[print_config]
dir_color = "cyan"
file_color = ""
symbol_color = "bright green"
tree_color = ""
grep_pass_color = "bright green"
grep_match_color = "bright red"

[path_config]
default_repo = "<Your Home>/.password-store"
repos = ["<Your Home>/.password-store"]

[executable_config]
pgp_executable = "gpg2"
editor_executable = "vim" # "notepad" on Windows
git_executable = "git"
```

## Command Line Completion

Currently, only `powershell` is supported for command line completion. We are working on adding support for `bash`, `zsh` and `fish` in the future.

### Windows Powershell

Run the following command to download the latest `ParsCompletion` module to your local machine:

```powershell
$documentsPath = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders').Personal
$documentsPath = [Environment]::ExpandEnvironmentVariables($documentsPath)

$modulePath = Join-Path $documentsPath "PowerShell\Modules\ParsCompletion"

# make sure the module path exists
if (-Not (Test-Path $modulePath)) {
    Write-Host "Creating module directory at $modulePath"
    New-Item -Path $modulePath -ItemType Directory -Force | Out-Null
}

$files = @(
    @{
        Url = "https://raw.githubusercontent.com/vollate/pass-store-rs/refs/heads/main/completion/pwsh/ParsCompletion.psm1"
        Path = Join-Path $modulePath "ParsCompletion.psm1"
    },
    @{
        Url = "https://raw.githubusercontent.com/vollate/pass-store-rs/refs/heads/main/completion/pwsh/ParsCompletion.psd1"
        Path = Join-Path $modulePath "ParsCompletion.psd1"
    }
)

# Download the files
foreach ($file in $files) {
    Write-Host "Downloading $($file.Url) ..."
    Invoke-WebRequest -Uri $file.Url -OutFile $file.Path -UseBasicParsing
    Write-Host "Saved to $($file.Path)"
}
```

Then, run `"Import-Module ParsCompletion" >> $PROFILE` to enable the module.

## Contributing

We welcome contributions of all kinds — from simple bug reports and typo fixes to major new features.

## Reporting Bugs

If you encounter any issues, please report them on our [GitHub Issues page](https://github.com/vollate/pass-store-rs/issues). When reporting a bug, please provide as much detail as possible to help us understand and reproduce the issue. This includes:

- OS and version (e.g., Ubuntu 22.04, macOS 14, Windows 11)
- pars version (pars --version)
- Steps to reproduce
- Relevant output or logs: set up the environment variable `PARS_LOG_LEVEL=Debug` to get more logs, **remember to remove any sensitive information before sharing!**
- Crash reports: if `pars` exits abnormally, set up the environment variable `PARS_LOG_LEVEL=Debug` and `RUST_BACKTRACE=1` to get the backtrace, and share it with us. **Remember to remove any sensitive information before sharing!**
  
