# CivicPulse Environment Setup Script
# Purpose: Automate environment provisioning, dependency installation, and AWS CLI configuration

$ErrorActionPreference = "Stop"

Write-Host "Starting CivicPulse Environment Setup..." -ForegroundColor Cyan

# 1. Check Python Installation
Write-Host "`n[1] Checking Python installation..." -ForegroundColor Yellow

try {
    $pythonVersion = python --version 2>&1
    Write-Host "[OK] Python found: $pythonVersion" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Python is not installed or not in PATH." -ForegroundColor Red
    Write-Host "Please install Python 3.8+ from https://www.python.org/downloads/" -ForegroundColor Yellow
    exit 1
}

# 2. Setup Virtual Environment
Write-Host "`n[2] Setting up virtual environment..." -ForegroundColor Yellow

$VenvDir = ".venv"

if (-not (Test-Path $VenvDir)) {
    Write-Host "Creating virtual environment..." -ForegroundColor Gray
    python -m venv $VenvDir
    Write-Host "[OK] Virtual environment created at $VenvDir" -ForegroundColor Green
}
else {
    Write-Host "[OK] Virtual environment already exists" -ForegroundColor Green
}

# 3. Activate Virtual Environment
Write-Host "`n[3] Activating virtual environment..." -ForegroundColor Yellow

& "$VenvDir\Scripts\Activate.ps1"

# 4. Install Dependencies
Write-Host "`n[4] Installing Python dependencies..." -ForegroundColor Yellow

if (Test-Path "requirements.txt") {
    pip install --upgrade pip
    pip install -r requirements.txt
    Write-Host "[OK] All dependencies installed successfully" -ForegroundColor Green
}
else {
    Write-Host "[WARNING] requirements.txt not found. Skipping pip install." -ForegroundColor Yellow
}

# 5. Check Docker
Write-Host "`n[5] Checking Docker..." -ForegroundColor Yellow

try {
    $null = docker info 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Docker is running" -ForegroundColor Green
    }
    else {
        Write-Host "[WARNING] Docker daemon is not running. Please start Docker Desktop." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "[WARNING] Docker is not installed or not in PATH." -ForegroundColor Yellow
    Write-Host "Please install Docker Desktop from https://www.docker.com/products/docker-desktop" -ForegroundColor Gray
}

# 6. Check AWS CLI
Write-Host "`n[6] Checking AWS CLI..." -ForegroundColor Yellow

try {
    $awsVersion = aws --version 2>&1
    Write-Host "[OK] AWS CLI found: $awsVersion" -ForegroundColor Green

    # Check if AWS is configured
    $awsConfig = aws configure list 2>&1

    if ($awsConfig -match "None" -or $awsConfig -match "<not set>") {
        Write-Host "[WARNING] AWS CLI is not configured." -ForegroundColor Yellow

        $configure = Read-Host "Do you want to run 'aws configure' now? (y/n)"

        if ($configure -eq "y" -or $configure -eq "Y") {
            aws configure
        }
    }
    else {
        Write-Host "[OK] AWS CLI is configured" -ForegroundColor Green
    }
}
catch {
    Write-Host "[WARNING] AWS CLI is not installed." -ForegroundColor Yellow
    Write-Host "Install from: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" -ForegroundColor Gray
}

# 7. Setup Complete
Write-Host "`nSetup complete! You are ready to build." -ForegroundColor Cyan
Write-Host "Next steps:" -ForegroundColor Gray
Write-Host "1. Run '.\scripts\deploy.ps1' to deploy the infrastructure" -ForegroundColor Gray
Write-Host "2. Access Airflow at http://localhost:8080" -ForegroundColor Gray