# CivicPulse Deployment Script
# Purpose: Build Docker infrastructure, initialize Airflow, and run dbt

$ErrorActionPreference = "Stop"

Write-Host "Deploying CivicPulse Infrastructure..." -ForegroundColor Cyan

# Ensure we're in the project root
Set-Location -Path $PSScriptRoot\..

# 1. Check Docker
Write-Host "`n[1] Checking Docker..." -ForegroundColor Yellow

try {
    $null = docker info 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "Docker is not running"
    }

    Write-Host "[OK] Docker is running" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Docker is not running. Please start Docker Desktop." -ForegroundColor Red
    exit 1
}

# 2. Build and Start Docker Containers
Write-Host "`n[2] Building and starting Docker containers..." -ForegroundColor Yellow
Write-Host "This may take 2-3 minutes on first run..." -ForegroundColor Gray

docker compose up -d --build

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Docker compose failed. Check the error messages above." -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Containers started successfully" -ForegroundColor Green

# 3. Wait for Airflow to Initialize
Write-Host "`n[3] Waiting for Airflow to initialize..." -ForegroundColor Yellow
Write-Host "This may take 20-30 seconds..." -ForegroundColor Gray

Start-Sleep -Seconds 25

# Verify Airflow is running
$retryCount = 0
$maxRetries = 10
$airflowReady = $false

while ($retryCount -lt $maxRetries -and -not $airflowReady) {
    try {
        $response = Invoke-WebRequest `
            -Uri "http://localhost:8080/health" `
            -Method Get `
            -UseBasicParsing `
            -ErrorAction SilentlyContinue

        if ($response.StatusCode -eq 200) {
            $airflowReady = $true
            Write-Host "[OK] Airflow webserver is healthy" -ForegroundColor Green
        }
    }
    catch {
        $retryCount++
        Write-Host "Waiting for Airflow... (attempt $retryCount/$maxRetries)" -ForegroundColor Gray
        Start-Sleep -Seconds 5
    }
}

if (-not $airflowReady) {
    Write-Host "[WARNING] Airflow may still be initializing." -ForegroundColor Yellow
    Write-Host "You can check manually at http://localhost:8080" -ForegroundColor Yellow
}

# 4. Initialize dbt
Write-Host "`n[4] Initializing dbt dependencies..." -ForegroundColor Yellow

Set-Location pipelines\dbt

try {
    dbt deps
    Write-Host "[OK] dbt dependencies installed" -ForegroundColor Green
}
catch {
    Write-Host "[WARNING] dbt deps failed. You may need to run this manually later." -ForegroundColor Yellow
}

Set-Location ..\..

# 5. Deployment Complete
Write-Host "`nDeployment complete!" -ForegroundColor Cyan
Write-Host "Access Airflow at: http://localhost:8080" -ForegroundColor White
Write-Host "Default credentials: admin / admin" -ForegroundColor White
Write-Host "Run '.\scripts\weekly_cleanup.ps1' to schedule weekly maintenance" -ForegroundColor White