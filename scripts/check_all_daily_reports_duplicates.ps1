Param(
    [string]$ReportsDir = ".\output\daily_reports"
)

if (-not (Test-Path $ReportsDir)) {
    Write-Host "Reports directory not found: $ReportsDir" -ForegroundColor Red
    exit 1
}

Get-ChildItem -Path $ReportsDir -Filter '*-report.csv' -File | ForEach-Object {
    $file = $_.FullName
    $rows = Import-Csv -Path $file -ErrorAction SilentlyContinue
    if (-not $rows) {
        Write-Host "$($_.Name): file empty or unreadable" -ForegroundColor Yellow
        return
    }

    $dups = $rows | Group-Object -Property 'MAC Addr' | Where-Object { $_.Count -gt 1 }
    if ($dups.Count -gt 0) {
        Write-Host "Duplicates in $($_.Name):" -ForegroundColor Red
        $dups | ForEach-Object {
            $mac = $_.Name
            Write-Host "  ${mac}: $($_.Count) occurrences"
            $rows | Where-Object { $_.'MAC Addr' -eq $mac } | Select-Object SourceFile,'MAC Addr' | ForEach-Object {
                Write-Host "    $($_.SourceFile)  $($_.'MAC Addr')"
            }
        }
    } else {
        Write-Host "$($_.Name): No duplicate MAC Addr values" -ForegroundColor Green
    }
}
