Param(
    [string]$ReportsDir = ".\output\daily_reports",
    [switch]$VerboseReport
)

if (-not (Test-Path $ReportsDir)) {
    Write-Error "Reports directory not found: $ReportsDir"
    exit 2
}

$csvFiles = Get-ChildItem -Path $ReportsDir -Filter *.csv | Sort-Object Name
if ($csvFiles.Count -eq 0) {
    Write-Output "No CSV files found in $ReportsDir"
    exit 0
}

foreach ($f in $csvFiles) {
    $path = $f.FullName
    Write-Output "Processing: $($f.Name)"
    try {
        $rows = Import-Csv -Path $path
    } catch {
        Write-Output "  Failed to import $($f.Name): $($_.Exception.Message)"
        continue
    }

    $originalCount = $rows.Count

    # Use existing Remove-CsvDuplicates function from csv-functions.ps1 - import if not loaded
    if (-not (Get-Command -Name Remove-CsvDuplicates -ErrorAction SilentlyContinue)) {
        . "$PSScriptRoot\..\csv-functions.ps1"
    }

    $deduped = Remove-CsvDuplicates -CsvData $rows -KeyColumns @('MAC Addr')
    $dedupCount = $deduped.Count

    if ($dedupCount -lt $originalCount) {
        $result = Write-CsvData -CsvData $deduped -FilePath $path
        if ($result.Success) {
            Write-Output "  Deduped $originalCount -> $dedupCount rows"
        } else {
            Write-Output "  Error writing deduped file: $($result.Message)"
        }
    } else {
        Write-Output "  No changes (rows = $originalCount)"
    }
}

Write-Output "Completed dedupe pass by MAC for daily reports."