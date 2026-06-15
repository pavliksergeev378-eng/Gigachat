# =============================================================================
# Fix incompatible wheels: replace scipy 1.17 -> 1.14.1, fsspec 2026 -> 2024.9
# Run on the HOME PC (with internet access).
# =============================================================================

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$wheelsDir = Join-Path $scriptDir "wheels"

if (-not (Test-Path $wheelsDir)) {
    Write-Host "[ERROR] wheels folder not found in $scriptDir" -ForegroundColor Red
    exit 1
}

Write-Host "==> Wheels folder: $wheelsDir"

# 1. Remove old scipy-1.17
$oldScipy = Get-ChildItem -Path $wheelsDir -Filter "scipy-1.17*" -File
if ($oldScipy) {
    Write-Host "  -> Removing old scipy: $($oldScipy.Name)"
    Remove-Item $oldScipy.FullName -Force
} else {
    Write-Host "  -> scipy-1.17 not found (already removed)"
}

# 2. Remove old fsspec 2026
$oldFsspec = Get-ChildItem -Path $wheelsDir -Filter "fsspec-2026*" -File
if ($oldFsspec) {
    Write-Host "  -> Removing old fsspec: $($oldFsspec.Name)"
    Remove-Item $oldFsspec.FullName -Force
} else {
    Write-Host "  -> fsspec-2026 not found"
}

Write-Host ""
Write-Host "==> Deletion done. Downloading new wheels..."

# 3. Download scipy 1.14.1 via python -m pip
Write-Host "  -> Downloading scipy-1.14.1..."
python -m pip download --only-binary=:all: --platform win_amd64 --python-version 3.12 --dest $wheelsDir scipy==1.14.1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Failed to download scipy-1.14.1" -ForegroundColor Red
    Write-Host "Check: python --version (needs 3.12), internet connection" -ForegroundColor Yellow
    exit 1
}
Write-Host "     OK" -ForegroundColor Green

# 4. Download fsspec 2024.9.0
Write-Host "  -> Downloading fsspec-2024.9.0..."
python -m pip download --only-binary=:all: --platform win_amd64 --python-version 3.12 --dest $wheelsDir fsspec==2024.9.0
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Failed to download fsspec-2024.9.0" -ForegroundColor Red
    Write-Host "Check: python --version (needs 3.12), internet connection" -ForegroundColor Yellow
    exit 1
}
Write-Host "     OK" -ForegroundColor Green

Write-Host ""
Write-Host "=============================================================" -ForegroundColor Green
Write-Host " DONE!" -ForegroundColor Green
Write-Host "============================================================="
Write-Host ""
Write-Host "Check scipy in wheels:"
$checkScipy = Get-ChildItem -Path $wheelsDir -Filter "scipy*" -File
foreach ($f in $checkScipy) { Write-Host "  $($f.Name)" }

Write-Host "Check fsspec in wheels:"
$checkFsspec = Get-ChildItem -Path $wheelsDir -Filter "fsspec*" -File
foreach ($f in $checkFsspec) { Write-Host "  $($f.Name)" }

Write-Host ""
Write-Host "Now copy the whole GigaChat-main folder to work and run install-offline.ps1" -ForegroundColor Cyan
