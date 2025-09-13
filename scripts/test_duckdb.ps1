<#
Simple DuckDB test harness for Windows PowerShell
Creates a small DuckDB DB, imports a sample CSV, runs a simple query, and exports the result.

Usage:
  - Ensure `duckdb.exe` is installed and reachable (either in PATH or set the $duckdb variable below)
  - From repository root: `.
epos\CSVCombiner\scripts\test_duckdb.ps1`
#>

param(
    [string]$DuckDbExe = "C:\\Tools\\duckdb\\duckdb.exe",
    [string]$DbFile = "$PSScriptRoot\..\master.duckdb",
    [string]$InputCsv = "$PSScriptRoot\sample_input.csv",
    [string]$OutputCsv = "$PSScriptRoot\output_test.csv"
)

Write-Host "DuckDB test harness starting..." -ForegroundColor Cyan

# Check duckdb executable
if (-not (Test-Path $DuckDbExe)) {
    Write-Host "duckdb.exe not found at: $DuckDbExe" -ForegroundColor Red
    Write-Host "Please download duckdb.exe and place it at that path or pass -DuckDbExe to this script." -ForegroundColor Yellow
    exit 2
}

# Ensure scripts folder exists
New-Item -ItemType Directory -Path "$PSScriptRoot" -Force | Out-Null

# Create sample CSV if missing
if (-not (Test-Path $InputCsv)) {
    @"
activity_date,status,amount
2025-09-10 12:00:00,ok,10.5
2025-09-10 13:30:00,ok,7.25
2025-09-11 09:45:00,fail,0
"@ | Out-File -FilePath $InputCsv -Encoding UTF8
    Write-Host "Created sample CSV at $InputCsv" -ForegroundColor Green
} else {
    Write-Host "Sample CSV already exists: $InputCsv" -ForegroundColor Green
}

# Initialize DB and run test SQL
# Prepare duckdb path and database file path (work even when DB doesn't exist yet)
$duckdb = $DuckDbExe
# Get a full absolute path for the DB file even if it doesn't exist
$dbfile = [System.IO.Path]::GetFullPath($DbFile)

# Ensure the parent directory of the DB file exists
$dbDir = Split-Path -Path $dbfile -Parent
if (-not (Test-Path $dbDir)) {
    New-Item -ItemType Directory -Path $dbDir -Force | Out-Null
}

# Remove existing DB file for a clean test
if (Test-Path $dbfile) { Remove-Item $dbfile -Force }


# Build SQL commands as a single -c argument (avoids Windows .read path quoting issues)
$sql = @"
CREATE TABLE IF NOT EXISTS master (activity_date TIMESTAMP, status TEXT, amount DOUBLE);
INSERT INTO master SELECT * FROM read_csv_auto('$InputCsv');
COPY (
    SELECT CAST(activity_date AS DATE) AS day,
                 COUNT(*) AS actions,
                 SUM(amount) AS total_amount
    FROM master
    GROUP BY CAST(activity_date AS DATE)
    ORDER BY day
) TO '$OutputCsv' (HEADER, DELIMITER ',');
"@

Write-Host "Running DuckDB commands against: $dbfile" -ForegroundColor Cyan
& $duckdb $dbfile -c $sql
$exit = $LASTEXITCODE

if ($exit -ne 0) {
    Write-Host "DuckDB exited with code $exit" -ForegroundColor Red
    exit $exit
}

# Show output CSV
if (Test-Path $OutputCsv) {
    Write-Host "Test output written to: $OutputCsv" -ForegroundColor Green
    Get-Content $OutputCsv | ForEach-Object { Write-Host "  $_" }
    exit 0
} else {
    Write-Host "Expected output not found: $OutputCsv" -ForegroundColor Red
    exit 3
}
