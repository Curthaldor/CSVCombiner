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
    
    # Get current list of already processed files from the master output file
    try {
        $masterFilePath = Join-Path $Settings["Paths.OutputFolder"] $Settings["Output.MasterFileName"]
        Write-Host "  Checking for already processed files in: $masterFilePath" -ForegroundColor White
        
        $processedFiles = Get-CsvFirstColumnUnique -FilePath $masterFilePath
        
        if ($processedFiles.Count -gt 0) {
            Write-Host "  Found $($processedFiles.Count) already processed files" -ForegroundColor White
        } else {
            Write-Host "  No previously processed files found (starting fresh)" -ForegroundColor White
        }
        
    } catch {
        Write-Host "  Error checking processed files: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
    
    # Scan input folder for new CSV files
    Write-Host "  Scanning input folder for CSV files..." -ForegroundColor White
    try {
        $inputFolder = $Settings["Paths.InputFolder"]
        $csvFiles = Get-ChildItem -Path $inputFolder -Filter "*.csv" -File | Select-Object -ExpandProperty Name
        
        if ($csvFiles.Count -gt 0) {
            Write-Host "  Found $($csvFiles.Count) CSV files in input folder" -ForegroundColor White
        } else {
            Write-Host "  No CSV files found in input folder" -ForegroundColor White
            return
        }
        
    } catch {
        Write-Host "  Error scanning input folder: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
    
    # Filter out already processed files
    $newFiles = @()
    foreach ($file in $csvFiles) {
        if ($processedFiles -notcontains $file) {
            $newFiles += $file
        }
    }
    
    if ($newFiles.Count -gt 0) {
        Write-Host "  Found $($newFiles.Count) new files to process: $($newFiles -join ', ')" -ForegroundColor White
    } else {
        Write-Host "  All CSV files have already been processed" -ForegroundColor White
        return
    }
    
    # Process new files and extract data
    $allNewData = @()
    foreach ($fileName in $newFiles) {
        Write-Host "  Processing file: $fileName" -ForegroundColor White
        $fileData = Invoke-FileProcessingAndIntegration -Settings $Settings -FileName $fileName
        if ($fileData) {
            $allNewData += $fileData
        }
    }
    
    Write-Host "  Processing logic placeholder - no files processed yet" -ForegroundColor Yellow
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
            # Create a placeholder record to mark this file as processed
            Write-Host "    No valid data rows after filtering - adding placeholder record to mark file as processed" -ForegroundColor Yellow
            $placeholderData = @()
            $placeholderRecord = New-Object PSCustomObject
            $placeholderRecord | Add-Member -NotePropertyName "SourceFile" -NotePropertyValue $FileName
            $placeholderRecord | Add-Member -NotePropertyName "ProcessedAt" -NotePropertyValue (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            $placeholderRecord | Add-Member -NotePropertyName "Status" -NotePropertyValue "NoValidData"
            $placeholderRecord | Add-Member -NotePropertyName "IP" -NotePropertyValue ""
            $placeholderData += $placeholderRecord
            
            $result = Write-CsvData -CsvData $placeholderData -FilePath $masterFilePath -Append $true
            if ($result.Success) {
                Write-Host "    Successfully added placeholder record to mark file as processed" -ForegroundColor Gray
            } else {
                Write-Host "    Error adding placeholder to master file: $($result.Message)" -ForegroundColor Red
                return $null
            }
        }
        
        # Update daily report CSV file with deduplication
        if ($processedData.Count -gt 0) {
            try {
                # Extract date from filename (assuming format like "20250523200303.csv")
                $dateString = $FileName.Substring(0, 8)  # First 8 characters: YYYYMMDD
                $dailyFileName = "$dateString-report.csv"
                $dailyFilePath = Join-Path $Settings["Paths.DailyReportFolder"] $dailyFileName
                
                # Load existing daily report data (returns empty array if file doesn't exist)
                Write-Host "    Loading existing daily report: $dailyFilePath" -ForegroundColor Gray
                $existingDailyData = Read-CsvData -FilePath $dailyFilePath
                Write-Host "    Found $($existingDailyData.Count) existing rows in daily report" -ForegroundColor Gray
                
                # Combine existing and new data
                $combinedData = @()
                $combinedData += $existingDailyData
                $combinedData += $processedData
                
                # Remove duplicates based on MAC Addr only (keeping newer entries)
                # Simplified matching as requested: duplicates are defined solely by the `MAC Addr` value.
                $keyColumns = @("MAC Addr")
                $deduplicatedData = Remove-CsvDuplicates -CsvData $combinedData -KeyColumns $keyColumns
                
                Write-Host "    Combined data: $($combinedData.Count) rows, after deduplication: $($deduplicatedData.Count) rows" -ForegroundColor Gray
                
                # Overwrite the daily report with deduplicated data
                $result = Write-CsvData -CsvData $deduplicatedData -FilePath $dailyFilePath
                if ($result.Success) {
                    Write-Host "    Successfully updated daily report with deduplicated data" -ForegroundColor Gray
                } else {
                    Write-Host "    Error updating daily report: $($result.Message)" -ForegroundColor Red
                    return $null
                }
                
                # Update summary sheet with pass/fail counts for this date
                Write-Host "    Updating daily summary with pass/fail counts" -ForegroundColor Gray
                $summaryResult = Update-DailySummary -Settings $Settings -DateString $dateString -DailyData $deduplicatedData
                if (-not $summaryResult.Success) {
                    Write-Host "    Warning: Failed to update daily summary: $($summaryResult.Message)" -ForegroundColor Yellow
                    # Don't return null here - summary update failure shouldn't stop processing
                }
                
            } catch {
                Write-Host "    Error updating daily report: $($_.Exception.Message)" -ForegroundColor Red
                return $null
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
    
    # Force return as array to prevent PowerShell from unwrapping single-item arrays
    return , $reorderedData
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
    
    # Force return as array to prevent PowerShell from unwrapping single-item arrays
    return , $reorderedData
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
        
        [Parameter(Mandatory=$true)]
        [array]$DailyData
    )
    
    try {
        # Build summary file path
        $summaryFilePath = Join-Path $Settings["Paths.SummaryOutputFolder"] $Settings["Output.SummaryFileName"]
        
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
    Invoke-CsvProcessing -Settings $validatedSettings
    
    Write-Host "Processing cycle completed" -ForegroundColor Green
    
    # If running continuously, wait for the specified interval
    if ($intervalSeconds -gt 0) {
        Write-Host "Waiting $intervalSeconds seconds before next cycle..." -ForegroundColor Yellow
        Start-Sleep -Seconds $intervalSeconds
    }
    
} while ($intervalSeconds -gt 0)