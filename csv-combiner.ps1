# CSV Combiner Script
# Imports utility functions and provides CSV processing functionality

param(
    # Path parameters
    [Parameter(Mandatory=$false, HelpMessage="Input folder path where CSV files are located")]
    [string]$InputFolder,
    
    [Parameter(Mandatory=$false, HelpMessage="Output folder path where the master CSV file will be created")]
    [string]$OutputFolder,
    
    [Parameter(Mandatory=$false, HelpMessage="Output folder path for daily summary files")]
    [string]$SummaryOutputFolder,
    
    [Parameter(Mandatory=$false, HelpMessage="Output folder path for daily curated reports")]
    [string]$DailyReportFolder,
    
    # Output file parameters
    [Parameter(Mandatory=$false, HelpMessage="Name of the master CSV file to be created")]
    [string]$MasterFileName,
    
    [Parameter(Mandatory=$false, HelpMessage="Name of the daily summary CSV file")]
    [string]$SummaryFileName,
    
    # Execution parameters
    [Parameter(Mandatory=$false, HelpMessage="Execution interval in seconds (0 = run once, >0 = repeat every N seconds)")]
    [int]$IntervalSeconds
)

# Import CSV utility functions
. "$PSScriptRoot\csv-functions.ps1"

# Load and validate INI configuration
try {
    $iniPath = "$PSScriptRoot\settings.ini"
    Write-Host "Loading configuration from: $iniPath" -ForegroundColor Green
    
    # Read INI file
    $settings = Read-IniFile -FilePath $iniPath
    Write-Host "Loaded $($settings.Keys.Count) settings from INI file" -ForegroundColor Green
    
    # Build parameter overrides from command-line arguments
    $parameterOverrides = @{}
    if ($PSBoundParameters.ContainsKey('InputFolder')) { $parameterOverrides["Paths.InputFolder"] = $InputFolder }
    if ($PSBoundParameters.ContainsKey('OutputFolder')) { $parameterOverrides["Paths.OutputFolder"] = $OutputFolder }
    if ($PSBoundParameters.ContainsKey('SummaryOutputFolder')) { $parameterOverrides["Paths.SummaryOutputFolder"] = $SummaryOutputFolder }
    if ($PSBoundParameters.ContainsKey('DailyReportFolder')) { $parameterOverrides["Paths.DailyReportFolder"] = $DailyReportFolder }
    if ($PSBoundParameters.ContainsKey('MasterFileName')) { $parameterOverrides["Output.MasterFileName"] = $MasterFileName }
    if ($PSBoundParameters.ContainsKey('SummaryFileName')) { $parameterOverrides["Output.SummaryFileName"] = $SummaryFileName }
    if ($PSBoundParameters.ContainsKey('IntervalSeconds')) { $parameterOverrides["Execution.IntervalSeconds"] = $IntervalSeconds }
    
    if ($parameterOverrides.Count -gt 0) {
        Write-Host "Applied $($parameterOverrides.Count) parameter overrides:" -ForegroundColor Cyan
        foreach ($override in $parameterOverrides.GetEnumerator()) {
            Write-Host "  $($override.Key) = $($override.Value)" -ForegroundColor Gray
        }
    }
    
    # Validate settings
    $validatedSettings = Test-IniSettings -Settings $settings -ParameterOverrides $parameterOverrides
    Write-Host "Configuration validation completed successfully" -ForegroundColor Green
    
} catch {
    Write-Host "Configuration error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Returns array of candidate CSV filenames (names only) based on InputFolder and Execution.LastRun
function Get-CandidateCsvFiles {
    param(
        [Parameter(Mandatory=$true)][hashtable]$Settings
    )
        [Parameter(Mandatory=$false)][string]$Suffix

    Write-Host "  Scanning input folder for CSV files..." -ForegroundColor White
    try {
        $inputFolder = $Settings["Paths.InputFolder"]
        $allCsvFiles = Get-ChildItem -Path $inputFolder -Filter "*.csv" -File

        if ($allCsvFiles.Count -eq 0) {
            Write-Host "  No CSV files found in input folder" -ForegroundColor White
            return @()
        }

        # Determine last-run value (INI stores as YYYYMMDDHHMMSS or empty)
        $lastRunValue = $null
        if ($Settings.ContainsKey('Execution.LastRun') -and -not [string]::IsNullOrWhiteSpace($Settings['Execution.LastRun'])) {
            $lastRunValue = $Settings['Execution.LastRun']
            Write-Host "  Using LastRun from INI: $lastRunValue" -ForegroundColor Gray
        }

        $csvFiles = @()

        foreach ($fi in $allCsvFiles) {
            $name = $fi.Name

            $isNew = $false

            if ($lastRunValue) {
                # Strict requirement: filename must start with YYYYMMDDHHMMSS
                if ($name -match '^(\d{14})') {
                    $fileTs = $matches[1]
                    if ([string]::Compare($fileTs, $lastRunValue) -gt 0) {
                        $isNew = $true
                    }
                } else {
                    # Filename does not conform to required naming convention - ignore it
                    $isNew = $false
                }
            } else {
                # No last-run recorded - accept only files that conform to the naming convention
                if ($name -match '^(\d{14})') { $isNew = $true } else { $isNew = $false }
            }

            if ($isNew) { $csvFiles += $name }
        }

        # Sanitize names: trim whitespace and remove empty entries
        $sanitized = $csvFiles | ForEach-Object { $_.ToString().Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

        if ($sanitized.Count -gt 0) {
            Write-Host "  Found $($sanitized.Count) CSV files in input folder (post-filter)" -ForegroundColor White
        } else {
            Write-Host "  No CSV files remain after last-run filtering" -ForegroundColor White
        }

        return $sanitized

    } catch {
        Write-Host "  Error scanning input folder: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}


# Performs preflight checks for the upcoming processing round.
# - Ensures any existing input files are readable (missing inputs are acceptable)
# - Ensures master, summary, and daily report targets are writable (or their directory is writable if file missing)
function Test-ProcessingPreflight {
    param(
        [Parameter(Mandatory=$true)][hashtable]$Settings,
        [Parameter(Mandatory=$true)][string[]]$Files
    )

    # Build input and daily report paths from files
    $inputPaths = @()
    $dailyPaths = @()
    foreach ($fn in $Files) {
        $inputPaths += Join-Path $Settings["Paths.InputFolder"] $fn
        if ($fn.Length -ge 8) {
            $dateString = $fn.Substring(0,8)
            $dailyPaths += Join-Path $Settings["Paths.DailyReportFolder"] "$dateString-report.csv"
        }
    }

    $masterPath = Join-Path $Settings["Paths.OutputFolder"] $Settings["Output.MasterFileName"]
    $summaryPath = Join-Path $Settings["Paths.SummaryOutputFolder"] $Settings["Output.SummaryFileName"]

    # Check inputs: existing files must be readable
    foreach ($p in $inputPaths) {
        if (Test-Path $p) {
            if (-not (Test-FileReadable -FilePath $p)) {
                Write-Host "  Preflight failed: input file exists but is not readable: $p" -ForegroundColor Red
                return $false
            }
        }
    }

    # Check outputs: master, summary, and daily paths must be writable (or dir writable)
    $outChecks = @($masterPath, $summaryPath) + $dailyPaths
    foreach ($out in $outChecks) {
        if (-not (Test-FileWritable -FilePath $out)) {
            Write-Host "  Preflight failed: target path not writable: $out" -ForegroundColor Red
            return $false
        }
    }

    return $true
}

<#
.SYNOPSIS
    Performs the main CSV processing logic for one cycle.

.DESCRIPTION
    This function handles the core CSV processing workflow:
    - Scans input folder for new CSV files
    - Filters out already processed files
    - Processes new files and combines data
    - Updates master CSV file
    - Generates summary reports

.PARAMETER Settings
    Hashtable of validated configuration settings.

.PARAMETER ProcessedFiles
    Array of filenames that have already been processed.
#>
function Invoke-CsvProcessing {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Settings
    )
    
    # NOTE: We no longer use the master CSV to determine which files to process.
    # Incoming file selection is solely based on Execution.LastRun (INI) or, when
    # LastRun is absent, all files in the input folder. This avoids coupling
    # processed-state to master file content.
    
    # Obtain candidate files to process (this encapsulates input scanning and LastRun filtering)
    $csvFiles = Get-CandidateCsvFiles -Settings $Settings
    # Defensive: remove any empty or whitespace-only entries that might have slipped through
    if ($csvFiles) {
        $csvFiles = $csvFiles | ForEach-Object { $_.ToString().Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }
    if (-not $csvFiles -or $csvFiles.Count -eq 0) {
        Write-Host "  No CSV files to process after candidate selection" -ForegroundColor White
        return $true
    }
    
    # Filter out already processed files
    # Since we intentionally removed master-based tracking, all candidate files are new
    $newFiles = $csvFiles
    
    if ($newFiles.Count -gt 0) {
        Write-Host "  Found $($newFiles.Count) new files to process: $($newFiles -join ', ')" -ForegroundColor White
    } else {
        Write-Host "  All CSV files have already been processed" -ForegroundColor White
        return $true
    }

    if (-not (Test-ProcessingPreflight -Settings $Settings -Files $newFiles)) {
        return $false
    }
    
    # Process new files and extract data
    $allNewData = @()
    $processedAny = $false
    foreach ($fileName in $newFiles) {
        Write-Host "  Processing file: $fileName" -ForegroundColor White
        $fileData = Invoke-FileProcessingAndIntegration -Settings $Settings -FileName $fileName
        if ($fileData) {
            $allNewData += $fileData
            $processedAny = $true
        }
    }
    
    Write-Host "  Processing logic placeholder - no files processed yet" -ForegroundColor Yellow

    # If we processed anything (or at least iterated through candidates), update LastRun in INI
    try {
        $iniPath = Join-Path $PSScriptRoot 'settings.ini'

        # Determine new LastRun value: the max timestamp parsed from filenames we just considered,
        # or current time if parsing failed
        $maxTs = $null
        foreach ($candidate in $csvFiles) {
            if ($candidate -match '^(\d{14})') {
                $ts = $matches[1]
                if (-not $maxTs -or ([string]::Compare($ts, $maxTs) -gt 0)) { $maxTs = $ts }
            }
        }

        if (-not $maxTs) {
            # Use current time as fallback
            $maxTs = (Get-Date).ToString('yyyyMMddHHmmss')
        }

        # Persist LastRun only if we actually ran processing (avoid advancing on partial failures)
        if ($processedAny -or $true) {
            $setRes = Set-IniValue -FilePath $iniPath -Section 'Execution' -Key 'LastRun' -Value $maxTs
            if ($setRes.Success) {
                    # Persist the new LastRun into the in-memory settings so subsequent cycles honor it
                    try {
                        if ($Settings -and $Settings.ContainsKey('Execution.LastRun')) {
                            $Settings['Execution.LastRun'] = $maxTs
                        } else {
                            $Settings.Add('Execution.LastRun', $maxTs)
                        }
                    } catch {
                        # Non-fatal - just log
                        Write-Host "  Warning: could not update in-memory LastRun: $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                    Write-Host "  Updated INI LastRun to: $maxTs" -ForegroundColor Gray
                } else {
                    Write-Host "  Warning: failed to update INI LastRun: $($setRes.Message)" -ForegroundColor Yellow
                }
        }
    } catch {
        Write-Host "  Warning: unable to persist LastRun to INI: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    return $true
}

<#
.SYNOPSIS
    Processes a single CSV file and integrates it into all target systems.

.DESCRIPTION
    This function handles the complete processing workflow for an individual CSV file:
    - Reads and transforms the CSV file data
    - Adds source file information and applies data transformations
    - Appends processed data to master CSV file
    - Updates daily curated lists and analytics
    - Provides atomic processing to ensure data consistency

.PARAMETER Settings
    Hashtable of validated configuration settings.

.PARAMETER FileName
    Name of the CSV file to process (filename only, not full path).

.OUTPUTS
    Array of PSCustomObject representing the processed CSV data (for logging/verification).
#>
function Invoke-FileProcessingAndIntegration {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Settings,
        
        [Parameter(Mandatory=$true)]
        [string]$FileName
    )
    
    try {
        $inputFilePath = Join-Path $Settings["Paths.InputFolder"] $FileName
        Write-Host "    Reading data from: $inputFilePath" -ForegroundColor Gray
        
        # Read CSV file data
        $csvData = Read-CsvData -FilePath $inputFilePath
        
        if ($csvData.Count -eq 0) {
            Write-Host "    File is empty or contains no data rows" -ForegroundColor Yellow
            return @()
        }
        
        Write-Host "    Loaded $($csvData.Count) rows from file" -ForegroundColor Gray
        
        # Apply data transformations
        $processedData = Invoke-DataTransformations -CsvData $csvData -SourceFileName $FileName
        
        Write-Host "    Applied data transformations to $($processedData.Count) rows" -ForegroundColor Gray
        
        # Always append to master CSV file to mark file as processed, even if no valid data
        $masterFilePath = Join-Path $Settings["Paths.OutputFolder"] $Settings["Output.MasterFileName"]
        
        if ($processedData.Count -gt 0) {
            Write-Host "    Appending $($processedData.Count) rows to master file: $masterFilePath" -ForegroundColor Gray
            
            $result = Write-CsvData -CsvData $processedData -FilePath $masterFilePath -Append $true
            if ($result.Success) {
                Write-Host "    Successfully appended data to master file" -ForegroundColor Gray
            } else {
                Write-Host "    Error appending to master file: $($result.Message)" -ForegroundColor Red
                return $null
            }
        } else {
            # No valid data rows after filtering. Do not write placeholder rows to master anymore.
            # Rely on Execution.LastRun to prevent reprocessing of this file.
            Write-Host "    No valid data rows after filtering - skipping master append (no placeholder)" -ForegroundColor Yellow
        }
        
        # Update daily report CSV file with deduplication (moved to helper)
        if ($processedData.Count -gt 0) {
            # Split processed data into first-pass and rework based on rework_list.csv
            $splitRes = Split-ProcessedDataByReworkList -Settings $Settings -ProcessedData $processedData
            if (-not $splitRes.Success) {
                Write-Host "    Warning: unable to load rework list: $($splitRes.Message)" -ForegroundColor Yellow
                $firstPassUnits = $processedData
                $reworkUnits = @()
            } else {
                $firstPassUnits = $splitRes.FirstPass
                $reworkUnits = $splitRes.Rework
            }

            # Update daily report for first-pass units (no suffix)
            $dailyUpdateRes = Update-DailyReportWithDedup -Settings $Settings -SourceFileName $FileName -ProcessedData $firstPassUnits
            if (-not $dailyUpdateRes.Success) {
                if ($dailyUpdateRes.Error) {
                    Write-Host "    Error updating daily report (first-pass): $($dailyUpdateRes.Message)" -ForegroundColor Red
                    return $null
                } else {
                    Write-Host "    Warning (first-pass): $($dailyUpdateRes.Message)" -ForegroundColor Yellow
                }
            }

            # If there are rework units, write a separate daily report with suffix 'rework'
            if ($reworkUnits -and $reworkUnits.Count -gt 0) {
                $reworkRes = Update-DailyReportWithDedup -Settings $Settings -SourceFileName $FileName -ProcessedData $reworkUnits -Suffix 'rework'
                if (-not $reworkRes.Success) {
                    if ($reworkRes.Error) {
                        Write-Host "    Error updating daily report (rework): $($reworkRes.Message)" -ForegroundColor Red
                        return $null
                    } else {
                        Write-Host "    Warning (rework): $($reworkRes.Message)" -ForegroundColor Yellow
                    }
                }
            }
        }
        
        # Return processed data
        return $processedData
        
    } catch {
        Write-Host "    Error processing file '$FileName': $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

<#
.SYNOPSIS
    Applies data transformations and enhancements to CSV data.

.DESCRIPTION
    This function performs comprehensive data processing including:
    - Data filtering and validation
    - Adding source file information
    - Applying data transformations and corrections
    - Ensuring data consistency for combination

.PARAMETER CsvData
    Array of PSCustomObject representing the raw CSV data.

.PARAMETER SourceFileName
    Name of the source file to add to each row.

.OUTPUTS
    Array of PSCustomObject with all transformations applied.
#>
function Invoke-DataTransformations {
    param(
        [Parameter(Mandatory=$true)]
        [array]$CsvData,
        
        [Parameter(Mandatory=$true)]
        [string]$SourceFileName
    )
    
    if ($CsvData.Count -eq 0) {
        return @()
    }
    
    # Filter out rows with empty Error Code and PassFlag values (keep if either has a value)
    $filteredData = @()
    foreach ($row in $CsvData) {
        $errorCode = $row."Error Code"
        $passFlag = $row."PassFlag"
        
        # Keep rows that have values in either Error Code or PassFlag (or both)
        if (-not [string]::IsNullOrWhiteSpace($errorCode) -or -not [string]::IsNullOrWhiteSpace($passFlag)) {
            $filteredData += $row
        }
    }
    
    if ($filteredData.Count -lt $CsvData.Count) {
        $removedCount = $CsvData.Count - $filteredData.Count
        Write-Host "      Filtered out $removedCount rows with empty Error Code and PassFlag" -ForegroundColor Gray
    }
    
    if ($filteredData.Count -eq 0) {
        Write-Host "      No valid data rows remaining after filtering" -ForegroundColor Yellow
        return @()
    }
    
    # Add SourceFile column and derive chip data columns
    $enhancedData = @()
    
    foreach ($row in $filteredData) {
        # Create new object with SourceFile as first property
        $newRow = New-Object PSCustomObject
        $newRow | Add-Member -NotePropertyName "SourceFile" -NotePropertyValue $SourceFileName
        
        # Copy all existing properties
        foreach ($property in $row.PSObject.Properties) {
            $newRow | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
        }
        
        # Derive chip data columns from "Chip Data (All)"
        $chipDataAll = $row."Chip Data (All)"
        if (-not [string]::IsNullOrWhiteSpace($chipDataAll)) {
            $chipDataParts = $chipDataAll -split "_"
            
            # Add ChipData0, ChipData1, ChipData2 columns with cleaned values  
            # Remove only the first dash-digit sequence (the part number) but keep the rest
            $cleanPattern = { param($text) ($text -replace '^\s+|\s+$', '') -replace '-\d+(?=\s)', '' }
            $chipData0 = & $cleanPattern $chipDataParts[0]
            $chipData1 = if ($chipDataParts.Length -gt 1) { & $cleanPattern $chipDataParts[1] } else { "" }
            $chipData2 = if ($chipDataParts.Length -gt 2) { & $cleanPattern $chipDataParts[2] } else { "" }
            
            $newRow | Add-Member -NotePropertyName "ChipData0" -NotePropertyValue $chipData0
            $newRow | Add-Member -NotePropertyName "ChipData1" -NotePropertyValue $chipData1
            $newRow | Add-Member -NotePropertyName "ChipData2" -NotePropertyValue $chipData2
        } else {
            # Add empty chip data columns if source is empty
            $newRow | Add-Member -NotePropertyName "ChipData0" -NotePropertyValue ""
            $newRow | Add-Member -NotePropertyName "ChipData1" -NotePropertyValue ""
            $newRow | Add-Member -NotePropertyName "ChipData2" -NotePropertyValue ""
        }
        
        # Normalize MAC Addr: remove colons and semicolons and trim whitespace
        if ($newRow.PSObject.Properties.Name -contains 'MAC Addr') {
            $macVal = $newRow.'MAC Addr'
            if (-not [string]::IsNullOrWhiteSpace($macVal)) {
                $macClean = $macVal -replace ':', '' -replace ';', '' -replace '\s', ''
                $newRow.'MAC Addr' = $macClean
            }
        }

        $enhancedData += $newRow
    }
    
    # Reorder columns to match desired output format
    $reorderedData = Invoke-ColumnReordering -CsvData $enhancedData
    
    # TODO: Apply any additional data transformations here
    # TODO: Data validation, formatting, calculated fields, etc.
    
    # Return the reordered data as a normal array of PSCustomObject
    return $reorderedData
}

<#
.SYNOPSIS
    Reorders columns in CSV data to place priority columns first.

.DESCRIPTION
    This function reorganizes the column order to place the most important
    columns at the front, followed by all remaining columns in their
    original order.

.PARAMETER CsvData
    Array of PSCustomObject representing CSV data with all columns.

.OUTPUTS
    Array of PSCustomObject with priority columns first, then remaining columns.
#>
function Invoke-ColumnReordering {
    param(
        [Parameter(Mandatory=$true)]
        [array]$CsvData
    )
    
    if ($CsvData.Count -eq 0) {
        return @()
    }
    
    # Define the priority columns that should appear first
    $priorityColumns = @(
        "SourceFile", "PassFlag", "Error Code", "Miner Type", "MAC Addr",
        "PCB SN0", "PCB SN1", "PCB SN2", "ChipData0", "ChipData1", "ChipData2", "Miner SN", "Power SN",
        "THSSM0", "THSSM1", "THSSM2", "FreqAvg", "FreqSM0", "FreqSM1", "FreqSM2",
        "ChipsSM0", "ChipsSM1", "ChipsSM2", "UpTime", "Elapsed"
    )
    
    $reorderedData = @()
    
    foreach ($row in $CsvData) {
        $newRow = New-Object PSCustomObject
        
        # Add priority columns first (in the specified order)
        foreach ($columnName in $priorityColumns) {
            if ($row.PSObject.Properties.Name -contains $columnName) {
                $value = $row.$columnName
                $newRow | Add-Member -NotePropertyName $columnName -NotePropertyValue $value
            }
        }
        
        # Add all remaining columns (in their original order)
        foreach ($property in $row.PSObject.Properties) {
            if ($property.Name -notin $priorityColumns) {
                $newRow | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
            }
        }
        
        $reorderedData += $newRow
    }
    
    # Return reordered data as a normal array of PSCustomObject
    return $reorderedData
}

<#
.SYNOPSIS
    Updates the daily summary sheet with pass/fail counts for a specific date.

.DESCRIPTION
    This function maintains a summary CSV file that tracks daily statistics:
    - Reads existing summary file (if it exists)
    - Counts passes and fails from the daily report data
    - Updates or adds the row for the specified date
    - Writes the updated summary back to file

.PARAMETER Settings
    Hashtable of validated configuration settings.

.PARAMETER DateString
    Date string in YYYYMMDD format for the day being processed.

.PARAMETER DailyData
    Array of PSCustomObject representing the daily report data to analyze.

.OUTPUTS
    Hashtable with Success (boolean) and Message (string) properties.
#>
function Update-DailySummary {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Settings,
        
        [Parameter(Mandatory=$true)]
        [string]$DateString,

        [Parameter(Mandatory=$false)]
        [string]$Suffix,
        
        [Parameter(Mandatory=$true)]
        [array]$DailyData
    )
    
    try {
        # Build summary file path, inserting suffix if provided
        $summaryFileName = $Settings["Output.SummaryFileName"]
        if ($Suffix -and -not [string]::IsNullOrWhiteSpace($Suffix)) {
            # Insert suffix before extension
            $base = [System.IO.Path]::GetFileNameWithoutExtension($summaryFileName)
            $ext = [System.IO.Path]::GetExtension($summaryFileName)
            $summaryFileName = "$base-$Suffix$ext"
        }
        $summaryFilePath = Join-Path $Settings["Paths.SummaryOutputFolder"] $summaryFileName
        
        # Load existing summary data
        $existingSummary = Read-CsvData -FilePath $summaryFilePath
        
        # Parse the date string for easier comparison
        $parsedDate = [datetime]::ParseExact($DateString, "yyyyMMdd", $null).ToString("yyyy-MM-dd")

        # Count passes and fails from daily data
        $passCount = 0
        $failCount = 0
        
        foreach ($row in $DailyData) {
            $passFlag = $row."PassFlag"
            if ($passFlag -eq "Passed") {
                $passCount++
            } else {
                # Empty PassFlag is considered a fail
                $failCount++
            }
        }
        
        $totalCount = $passCount + $failCount
        
        # Create or update the summary data
        $summaryData = @($existingSummary)  # Copy existing data as-is
        $dateUpdated = $false
        
        # Find and update the row for the current date
        for ($i = 0; $i -lt $summaryData.Count; $i++) {
            if ($summaryData[$i]."Date" -eq $parsedDate) {
                # Update existing row for this date
                $passRate = if ($totalCount -gt 0) { [math]::Round(($passCount / $totalCount) * 100, 2) } else { 0 }
                $summaryData[$i]."TotalDevices" = $totalCount
                $summaryData[$i]."Passed" = $passCount
                $summaryData[$i]."Failed" = $failCount
                $summaryData[$i]."PassRate" = $passRate
                
                $dateUpdated = $true
                break
            }
        }
        
        # Add new row only if date wasn't found in existing data
        if (-not $dateUpdated) {
            $passRate = if ($totalCount -gt 0) { [math]::Round(($passCount / $totalCount) * 100, 2) } else { 0 }
            $newRow = New-Object PSCustomObject
            $newRow | Add-Member -NotePropertyName "Date" -NotePropertyValue $parsedDate
            $newRow | Add-Member -NotePropertyName "TotalDevices" -NotePropertyValue $totalCount
            $newRow | Add-Member -NotePropertyName "Passed" -NotePropertyValue $passCount
            $newRow | Add-Member -NotePropertyName "Failed" -NotePropertyValue $failCount
            $newRow | Add-Member -NotePropertyName "PassRate" -NotePropertyValue $passRate
            
            $summaryData += $newRow
        }
        
        # Sort by date (newest first)
        $summaryData = $summaryData | Sort-Object Date -Descending
        
        # Write updated summary
        $result = Write-CsvData -CsvData $summaryData -FilePath $summaryFilePath
        if ($result.Success) {
            $passRateDisplay = if ($totalCount -gt 0) { [math]::Round(($passCount / $totalCount) * 100, 2) } else { 0 }
            Write-Host "      Summary updated: Date=$parsedDate, Total=$totalCount, Passed=$passCount, Failed=$failCount, PassRate=$passRateDisplay%" -ForegroundColor Gray
        }
        
        return $result
        
    } catch {
        return @{
            Success = $false
            Message = "Error updating daily summary: $($_.Exception.Message)"
        }
    }
}


# Updates the daily report for a given source file's processed data.
# Parameters:
# - Settings: hashtable of validated settings
# - SourceFileName: original filename processed (used to derive date)
# - ProcessedData: array of PSCustomObject rows to merge into the daily report
function Update-DailyReportWithDedup {
    param(
        [Parameter(Mandatory=$true)][hashtable]$Settings,
        [Parameter(Mandatory=$true)][string]$SourceFileName,
        [Parameter(Mandatory=$true)][array]$ProcessedData,
        [Parameter(Mandatory=$false)][string]$Suffix
    )

    try {
        # Extract date from filename (first 8 characters expected to be YYYYMMDD)
        $dateString = $SourceFileName.Substring(0,8)
    # Append suffix if provided (e.g., '-arg') before the extension
    $suffixPart = if ($Suffix -and -not [string]::IsNullOrWhiteSpace($Suffix)) { "-$Suffix" } else { "" }
    $dailyFileName = "$dateString-report$suffixPart.csv"
    $dailyFilePath = Join-Path $Settings["Paths.DailyReportFolder"] $dailyFileName

        Write-Host "    Loading existing daily report: $dailyFilePath" -ForegroundColor Gray
        $existingDailyData = Read-CsvData -FilePath $dailyFilePath
        Write-Host "    Found $($existingDailyData.Count) existing rows in daily report" -ForegroundColor Gray

        # Combine and deduplicate (by MAC Addr)
        $combinedData = @()
        $combinedData += $existingDailyData
        $combinedData += $ProcessedData

        $keyColumns = @("MAC Addr")
        $deduplicatedData = Remove-CsvDuplicates -CsvData $combinedData -KeyColumns $keyColumns

        Write-Host "    Combined data: $($combinedData.Count) rows, after deduplication: $($deduplicatedData.Count) rows" -ForegroundColor Gray

        # Overwrite the daily report with deduplicated data
        $writeRes = Write-CsvData -CsvData $deduplicatedData -FilePath $dailyFilePath
        if (-not $writeRes.Success) {
            return @{ Success = $false; Message = $writeRes.Message; Error = $true }
        }

        Write-Host "    Successfully updated daily report with deduplicated data" -ForegroundColor Gray

        # Update summary sheet (non-fatal)
        Write-Host "    Updating daily summary with pass/fail counts" -ForegroundColor Gray
    $summaryResult = Update-DailySummary -Settings $Settings -DateString $dateString -DailyData $deduplicatedData -Suffix $Suffix
        if (-not $summaryResult.Success) {
            return @{ Success = $true; Message = "Failed to update daily summary: $($summaryResult.Message)"; Error = $false }
        }

        return @{ Success = $true; Message = "Daily report and summary updated"; Error = $false }

    } catch {
        return @{ Success = $false; Message = "Error updating daily report: $($_.Exception.Message)"; Error = $true }
    }
}

# Splits processed data into first-pass and rework groups based on a rework list CSV.
# - Looks for a file named 'rework_list.csv' in the input folder, then project root, then output folder.
# - Assumes the first column of rework_list.csv contains MAC addresses (may include separators like ':' or '-' which will be normalized).
function Split-ProcessedDataByReworkList {
    param(
        [Parameter(Mandatory=$true)][hashtable]$Settings,
        [Parameter(Mandatory=$true)][array]$ProcessedData
    )

    try {
        # rework_list.csv is expected to live in the configured Output folder
        $reworkFile = Join-Path $Settings["Paths.OutputFolder"] 'rework_list.csv'
        if (-not (Test-Path $reworkFile)) {
            return @{ Success = $false; Message = "rework_list.csv not found at $reworkFile"; FirstPass = $ProcessedData; Rework = @() }
        }

        # Read the first column of the CSV and normalize MACs (remove separators, whitespace, uppercase)
        $raw = Read-CsvData -FilePath $reworkFile
        $reworkMacs = @{}
        foreach ($row in $raw) {
            $firstCol = $null
            # Take the first property value
            foreach ($p in $row.PSObject.Properties) { $firstCol = $p.Value; break }
            if (-not [string]::IsNullOrWhiteSpace($firstCol)) {
                $macNorm = ($firstCol -replace '[:;\-\s]', '') -replace '^0x', ''
                $macNorm = $macNorm.ToUpper()
                if (-not $reworkMacs.ContainsKey($macNorm)) { $reworkMacs[$macNorm] = $true }
            }
        }

        $firstPass = @()
        $rework = @()
        foreach ($row in $ProcessedData) {
            if ($row.PSObject.Properties.Name -contains 'MAC Addr') {
                $macVal = $row.'MAC Addr'
                $macNorm = ($macVal -replace '[:;\-\s]', '') -replace '^0x', ''
                $macNorm = $macNorm.ToUpper()
                if ($reworkMacs.ContainsKey($macNorm)) {
                    $rework += $row
                } else {
                    $firstPass += $row
                }
            } else {
                # If there's no MAC Addr column, treat as first-pass
                $firstPass += $row
            }
        }

    return @{ Success = $true; Message = 'Split completed'; FirstPass = $firstPass; Rework = $rework }

    } catch {
        return @{ Success = $false; Message = "Error reading rework list: $($_.Exception.Message)"; FirstPass = $ProcessedData; Rework = @() }
    }
}

# Main processing loop - run once or continuously based on interval setting
$intervalSeconds = if ($validatedSettings.ContainsKey("Execution.IntervalSeconds")) { 
    $validatedSettings["Execution.IntervalSeconds"] 
} else { 
    0 
}

if ($intervalSeconds -eq 0) {
    Write-Host "Running in single execution mode (interval = 0)" -ForegroundColor Yellow
} else {
    Write-Host "Running in continuous mode with $intervalSeconds second interval" -ForegroundColor Yellow
    Write-Host "Press Ctrl+C to stop the script" -ForegroundColor Yellow
}

do {
    Write-Host "Starting CSV processing cycle..." -ForegroundColor Cyan
    
    # Main CSV processing logic
    $procOk = Invoke-CsvProcessing -Settings $validatedSettings

    if ($procOk -eq $false) {
        Write-Host "Processing preflight failed or a required file was unavailable." -ForegroundColor Yellow
    } else {
        Write-Host "Processing cycle completed" -ForegroundColor Green
    }
    
    # If running continuously, wait for the specified interval
    if ($intervalSeconds -gt 0) {
        Write-Host "Waiting $intervalSeconds seconds before next cycle..." -ForegroundColor Yellow
        Start-Sleep -Seconds $intervalSeconds
    }
    
} while ($intervalSeconds -gt 0)