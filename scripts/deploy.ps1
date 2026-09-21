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
Write-Host "This may take 60-90 seconds on first run..." -ForegroundColor Gray

# Initial longer wait for database migrations
Start-Sleep -Seconds 45

# Verify Airflow is running with more retries
$retryCount = 0
$maxRetries = 15
$airflowReady = $false

Write-Host "Polling Airflow health endpoint..." -ForegroundColor Gray

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
        $remaining = $maxRetries - $retryCount
        Write-Host "Waiting for Airflow... (attempt $retryCount/$maxRetries, $remaining retries left)" -ForegroundColor Gray
        Start-Sleep -Seconds 6
    }
}

if (-not $airflowReady) {
    Write-Host "[WARNING] Airflow health check timed out." -ForegroundColor Yellow
    Write-Host "Checking container status..." -ForegroundColor Gray
    
    # Show container status
    docker compose ps
    
    Write-Host "`nTo troubleshoot:" -ForegroundColor Yellow
    Write-Host "  1. Check container logs: docker compose logs airflow-webserver" -ForegroundColor Gray
    Write-Host "  2. Wait a bit longer and try: http://localhost:8080" -ForegroundColor Gray
    Write-Host "  3. Ensure port 8080 isn't blocked by firewall" -ForegroundColor Gray
}

# 4. Initialize dbt
Write-Host "`n[4] Initializing dbt dependencies and documentation..." -ForegroundColor Yellow

Set-Location pipelines\dbt

try {
    dbt deps
    Write-Host "[OK] dbt dependencies installed" -ForegroundColor Green
    
    # Generate dbt documentation for the Data Dictionary
    Write-Host "Generating dbt documentation..." -ForegroundColor Gray
    dbt docs generate
    Write-Host "[OK] dbt documentation generated" -ForegroundColor Green
}
catch {
    Write-Host "[WARNING] dbt initialization failed. You may need to run this manually later." -ForegroundColor Yellow
}

Set-Location ..\..

# 5. Deployment Complete
Write-Host "`nDeployment complete!" -ForegroundColor Cyan
Write-Host "Access Airflow at: http://localhost:8080" -ForegroundColor White
Write-Host "Default credentials: admin / admin" -ForegroundColor White
Write-Host "Run '.\scripts\weekly_cleanup.ps1' to schedule weekly maintenance" -ForegroundColor White

if (-not $airflowReady) {
    Write-Host "`n[INFO] Airflow might still be starting. Give it 1-2 more minutes." -ForegroundColor Yellow
}