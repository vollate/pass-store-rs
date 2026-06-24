param(
    [ValidateSet("debug", "release", "Debug", "Release", "Profile")]
    [string]$Profile = "debug",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..\..")
$profileDir = if ($Profile -eq "release" -or $Profile -eq "Release" -or $Profile -eq "Profile") { "release" } else { "debug" }

$cargoArgs = @("build", "-p", "pars-bridge")
if ($profileDir -eq "release") {
    $cargoArgs += "--release"
}

Push-Location $repoRoot
try {
    & cargo @cargoArgs
    if ($LASTEXITCODE -ne 0) {
        throw "cargo build failed with exit code $LASTEXITCODE"
    }

    if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        $OutputDir = Join-Path $repoRoot "gui\build\native\windows"
    }
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

    $sourceDll = Join-Path $repoRoot "target\$profileDir\pars_bridge.dll"
    if (-not (Test-Path $sourceDll)) {
        throw "pars_bridge.dll not found at $sourceDll"
    }
    Copy-Item $sourceDll (Join-Path $OutputDir "pars_bridge.dll") -Force

    $sourcePdb = Join-Path $repoRoot "target\$profileDir\pars_bridge.pdb"
    if (Test-Path $sourcePdb) {
        Copy-Item $sourcePdb (Join-Path $OutputDir "pars_bridge.pdb") -Force
    }
}
finally {
    Pop-Location
}
