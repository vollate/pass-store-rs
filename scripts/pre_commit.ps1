$TARGET_DIRS = @("core", "cli")

if (-not (Test-Path ".git")) {
    Write-Host "Not a git repository, please use at the root of a git repository"
    exit 1
}

Write-Host "Adding all changes to git..."
git add -A
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to add changes to git"
    exit 1
}

Write-Host "Fixing cargo issues..."
cargo fix --allow-staged -q
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to fix cargo issues"
    exit 1
}

Write-Host "Formatting code..."
cargo fmt
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to format code"
    exit 1
}

foreach ($dir in $TARGET_DIRS) {
    Write-Host "Changing directory to $dir..."
    Set-Location $dir
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to change directory to $dir"
        exit 1
    }
    Write-Host "============================== Testing $dir =============================="
    Write-Host "Running cargo clippy in $dir..."
    cargo clippy --fix --allow-dirty
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to run cargo clippy in $dir"
        cd ..
        exit 1
    }
    Write-Host "Running cargo test in $dir..."
    sudo cargo test -- --include-ignored
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to run cargo test in $dir"
        cd ..
        exit 1
    }
    Write-Host "Changing back to root directory..."
    Set-Location ..
}

Write-Host "Adding all changes to git again..."
git add -A
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to add changes to git again"
    exit 1
}
