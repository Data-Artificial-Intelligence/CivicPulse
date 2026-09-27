# CivicPulse Schedule Cleanup Task Script
# Purpose: Creates a Windows Scheduled Task to run weekly_cleanup.ps1 every Sunday at 2 AM
# Note: This script MUST be run as Administrator.

$ErrorActionPreference = "Stop"

# 1. Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "❌ Error: This script must be run as Administrator." -ForegroundColor Red
    Write-Host "   Please right-click PowerShell and select 'Run as Administrator', then try again." -ForegroundColor Yellow
    exit 1
}

# 2. Define Task Parameters
$taskName = "CivicPulse Weekly Cleanup"
$taskDescription = "Archive logs and clean up old S3 files to reduce costs"

# Dynamically get the absolute path to weekly_cleanup.ps1 based on this script's location
$scriptPath = Join-Path $PSScriptRoot "weekly_cleanup.ps1"

if (-not (Test-Path $scriptPath)) {
    Write-Host "❌ Error: Could not find weekly_cleanup.ps1 at $scriptPath" -ForegroundColor Red
    exit 1
}

# 3. Define Task Action, Trigger, and Principal
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 2am
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest

# 4. Check if task already exists and remove it to avoid conflicts on re-runs
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "⚠️  Task '$taskName' already exists. Unregistering it first..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# 5. Register the new Scheduled Task
Register-ScheduledTask -TaskName $taskName -Description $taskDescription -Action $action -Trigger $trigger -Principal $principal | Out-Null

Write-Host "✅ Scheduled task '$taskName' created successfully!" -ForegroundColor Green
Write-Host "   The script will run every Sunday at 2:00 AM." -ForegroundColor Gray
Write-Host "   You can view or modify it in the Windows Task Scheduler GUI." -ForegroundColor Gray