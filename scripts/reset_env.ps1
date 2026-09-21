# CivicPulse Full Environment Reset Script
# WARNING: This will destroy all local containers, volumes, caches, and scheduled tasks!
# NOTE: MUST be run as Administrator to delete the Scheduled Task.

$ErrorActionPreference = "Stop"

Write-Host "WARNING: This will destroy your local CivicPulse environment!" -ForegroundColor Red
Write-Host "This includes:" -ForegroundColor Yellow
Write-Host "  - All Docker containers and volumes" -ForegroundColor Gray
Write-Host "  - Local dbt caches and packages" -ForegroundColor Gray
Write-Host "  - Python virtual environment" -ForegroundColor Gray
Write-Host "  - Windows Task Scheduler task (CivicPulse Weekly Cleanup)" -ForegroundColor Gray
Write-Host ""

# Auto-deactivate if currently inside a virtual environment
if ($env:VIRTUAL_ENV) {
    Write-Host "[INFO] Virtual environment detected. Deactivating..." -ForegroundColor Yellow
    deactivate
    Start-Sleep -Seconds 2
}

$confirm = Read-Host "Are you sure you want to continue? Type 'yes' to confirm"

if ($confirm -ne "yes") {
    Write-Host "Aborted." -ForegroundColor Yellow
    exit
}

# 1. Remove Windows Task Scheduler Task
Write-Host "`n[1] Removing Windows Task Scheduler task..." -ForegroundColor Yellow
$taskName = "CivicPulse Weekly Cleanup"
try {
    # Redirect to $null to satisfy linter, we only care if it succeeds or throws
    $null = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false | Out-Null
    Write-Host "   [OK] Scheduled task '$taskName' removed." -ForegroundColor Green
} catch {
    if ($_.Exception.Message -like "*Access is denied*") {
        Write-Host "   [ERROR] Access denied. Please run this script as Administrator." -ForegroundColor Red
    } else {
        Write-Host "   [INFO] Scheduled task '$taskName' not found. Skipping." -ForegroundColor Gray
    }
}

# 2. Tear Down Docker Environment
Write-Host "`n[2] Tearing down Docker environment and removing volumes..." -ForegroundColor Yellow
try {
    docker compose down -v
    Write-Host "   [OK] Docker containers and volumes removed." -ForegroundColor Green
} catch {
    Write-Host "   [WARNING] Docker compose down failed or no containers to remove." -ForegroundColor Yellow
}

# 3. Remove dbt Caches
Write-Host "`n[3] Removing local dbt caches..." -ForegroundColor Yellow
$dbtTargetPath = Join-Path $PSScriptRoot "..\pipelines\dbt\target"
$dbtPackagesPath = Join-Path $PSScriptRoot "..\pipelines\dbt\dbt_packages"

if (Test-Path $dbtTargetPath) {
    Remove-Item -Recurse -Force $dbtTargetPath -ErrorAction SilentlyContinue
    Write-Host "   [OK] Removed: target" -ForegroundColor Green
} else {
    Write-Host "   [INFO] target folder not found. Skipping." -ForegroundColor Gray
}

if (Test-Path $dbtPackagesPath) {
    Remove-Item -Recurse -Force $dbtPackagesPath -ErrorAction SilentlyContinue
    Write-Host "   [OK] Removed: dbt_packages" -ForegroundColor Green
} else {
    Write-Host "   [INFO] dbt_packages folder not found. Skipping." -ForegroundColor Gray
}

# 4. Remove Python Virtual Environment
Write-Host "`n[4] Removing Python virtual environment..." -ForegroundColor Yellow
$venvPath = Join-Path $PSScriptRoot "..\.venv"
if (Test-Path $venvPath) {
    # Use -ErrorAction SilentlyContinue to bypass minor Windows file lock hiccups
    Remove-Item -Recurse -Force $venvPath -ErrorAction SilentlyContinue
    
    # Double-check if it was actually deleted
    if (Test-Path $venvPath) {
        Write-Host "   [WARNING] .venv is locked by a background process." -ForegroundColor Yellow
        Write-Host "   Please close all terminals/VS Code and manually delete the .venv folder." -ForegroundColor Gray
    } else {
        Write-Host "   [OK] Removed: .venv" -ForegroundColor Green
    }
} else {
    Write-Host "   [INFO] .venv folder not found. Skipping." -ForegroundColor Gray
}

# 5. Summary
Write-Host "`n[OK] Environment completely reset!" -ForegroundColor Cyan
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Run '.\scripts\setup_env.ps1' to provision a fresh environment" -ForegroundColor Gray
Write-Host "  2. Run '.\scripts\deploy.ps1' to deploy infrastructure" -ForegroundColor Gray
Write-Host "  3. Run '.\scripts\schedule_cleanup.ps1' (as Admin) to reschedule weekly cleanup" -ForegroundColor Gray