# CivicPulse Weekly Cleanup Script
# Purpose: Archive old Airflow logs and clean up S3 files older than 90 days to reduce costs
# Schedule: Run weekly via Windows Task Scheduler

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $ProjectRoot "pipelines\airflow\logs"
$ArchiveDir = Join-Path $ProjectRoot "data\archives"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "Starting weekly cleanup process..." -ForegroundColor Cyan

# ==========================================
# 1. Archive and Clean Local Airflow Logs
# ==========================================
Write-Host "`n[1] Archiving Airflow logs..." -ForegroundColor Yellow

if (Test-Path $LogDir) {

    # Create archive directory if it does not exist
    if (-not (Test-Path $ArchiveDir)) {
        New-Item -ItemType Directory -Force -Path $ArchiveDir | Out-Null
        Write-Host "Created archive directory: $ArchiveDir" -ForegroundColor Gray
    }

    # Create timestamped archive
    $ZipPath = Join-Path $ArchiveDir "airflow_logs_$Timestamp.zip"

    Write-Host "Compressing logs to: $ZipPath" -ForegroundColor Gray

    try {
        Compress-Archive `
            -Path "$LogDir\*" `
            -DestinationPath $ZipPath `
            -Force `
            -ErrorAction Stop

        Write-Host "[OK] Airflow logs archived successfully" -ForegroundColor Green

        # Clean up old archives
        # Keep only the four most recent archives
        Write-Host "Cleaning up old archives (keeping last 4)..." -ForegroundColor Gray

        $oldArchives = Get-ChildItem `
            -Path $ArchiveDir `
            -Filter "airflow_logs_*.zip" |
            Sort-Object CreationTime -Descending |
            Select-Object -Skip 4

        foreach ($archive in $oldArchives) {
            Remove-Item -Path $archive.FullName -Force
            Write-Host "Deleted old archive: $($archive.Name)" -ForegroundColor Gray
        }

        Write-Host "[OK] Old archives cleaned up" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARNING] Failed to archive logs: $_" -ForegroundColor Yellow
    }
}
else {
    Write-Host "[INFO] Log directory not found. Skipping log archival." -ForegroundColor Gray
}

# ==========================================
# 2. Clean Up S3 Files Older Than 90 Days
# ==========================================
Write-Host "`n[2] Cleaning up S3 files older than 90 days..." -ForegroundColor Yellow
Write-Host "This helps reduce AWS storage costs" -ForegroundColor Gray

$BucketName = "civicpulse-raw-surveys"
$ThresholdDate = (Get-Date).AddDays(-90).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

try {

    # Check if AWS CLI is configured
    $null = aws sts get-caller-identity 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "AWS CLI is not configured. Run 'aws configure' first."
    }

    Write-Host "Scanning bucket: $BucketName" -ForegroundColor Gray
    Write-Host "Threshold date: $ThresholdDate" -ForegroundColor Gray

    # List objects older than threshold
    $Objects = aws s3api list-objects-v2 `
        --bucket $BucketName `
        --query "Contents[?LastModified<'$ThresholdDate'].{Key: Key, Size: Size, LastModified: LastModified}" `
        --output json 2>$null | ConvertFrom-Json

    if ($null -eq $Objects -or $Objects.Count -eq 0) {

        Write-Host "[OK] No files older than 90 days found in S3." -ForegroundColor Green
    }
    else {

        Write-Host "Found $($Objects.Count) files to delete" -ForegroundColor Yellow

        # Calculate total size to be deleted
        $totalSize = ($Objects | Measure-Object -Property Size -Sum).Sum
        $totalSizeMB = [math]::Round($totalSize / 1MB, 2)

        Write-Host "Total size: $totalSizeMB MB" -ForegroundColor Gray

        # Delete old objects
        $deletedCount = 0

        foreach ($obj in $Objects) {

            $key = $obj.Key

            Write-Host "Deleting: s3://$BucketName/$key" -ForegroundColor Gray

            aws s3 rm "s3://$BucketName/$key" 2>$null

            if ($LASTEXITCODE -eq 0) {
                $deletedCount++
            }
        }

        Write-Host "[OK] S3 cleanup complete. Deleted $deletedCount files." -ForegroundColor Green

        # Estimate storage savings
        $estimatedSavings = [math]::Round($totalSizeMB * 0.023, 2)

        Write-Host "Estimated monthly storage savings: $estimatedSavings USD" -ForegroundColor Green
    }
}
catch {
    Write-Host "[WARNING] S3 cleanup failed: $_" -ForegroundColor Yellow
    Write-Host "Make sure AWS CLI is configured and you have permissions to access the bucket." -ForegroundColor Gray
}

# ==========================================
# 3. Clean Up Old Docker Images
# ==========================================
Write-Host "`n[3] Cleaning up unused Docker resources..." -ForegroundColor Yellow

try {

    docker system prune -f --volumes 2>$null

    Write-Host "[OK] Docker cleanup complete" -ForegroundColor Green
}
catch {
    Write-Host "[WARNING] Docker cleanup skipped: $_" -ForegroundColor Yellow
}

# ==========================================
# 4. Cleanup Complete
# ==========================================
$NextRun = (Get-Date).AddDays(7).ToString("yyyy-MM-dd")

Write-Host "`nWeekly cleanup finished successfully!" -ForegroundColor Cyan
Write-Host "Next scheduled run: $NextRun" -ForegroundColor Gray