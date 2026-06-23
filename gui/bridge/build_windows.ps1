$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path "$PSScriptRoot\..\.."
Set-Location $RepoRoot

$targets = $env:PARS_WINDOWS_TARGETS
if ([string]::IsNullOrWhiteSpace($targets)) {
    $targets = "x86_64-pc-windows-msvc"
}

foreach ($target in $targets.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)) {
    cargo build -p pars-bridge --release --target $target
}
