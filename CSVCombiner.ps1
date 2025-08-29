# ==============================================================================
# CSV Combiner Script v2.4 - Modular Architecture
# ==============================================================================
# Author: Curt Haldorson, GitHub Copilot Assistant
# Created: August 2025
# Updated: December 2024 - Modular architecture for improved testability
# Purpose: Monitors a folder for CSV files and combines them into a master CSV
# 
# FEATURES:
# - Additive processing (preserves existing data when new files are added)
# - Unified schema merging (handles different column structures)
# - Configurable timestamp metadata column (extracted from filename)
# - High-performance streaming processing for maximum throughput
# - Optional filename format validation (14-digit timestamp format)
# - Polling-based file monitoring (reliable, no admin privileges required)
# - Automatic backup management with configurable retention
# - File stability checks to prevent processing incomplete files
# - Simple retry logic for file-in-use scenarios (waits for next iteration)
# - PID file management for reliable start/stop operations
# - Modular architecture with extracted functions for better testability
#
# USAGE:
#   powershell -ExecutionPolicy Bypass -File CSVCombiner.ps1 -ConfigPath CSVCombiner.ini
#   
# DEPENDENCIES:
# - Windows PowerShell 5.1+ (built into Windows 10/11)
# - CSVCombiner.ini configuration file
# - CSVCombiner-Functions.ps1 module
# - Write access to input/output folders
#
# FILENAME REQUIREMENTS (when ValidateFilenameFormat=true):
# - Input CSV files must follow format: YYYYMMDDHHMMSS.csv
# - Example: 20250825160159.csv (exactly 14 digits + .csv)
# - Invalid examples: data.csv, report_2025.csv, 2025-08-25.csv
#
# ==============================================================================

param(
    [Parameter(Mandatory=$false, HelpMessage="Path to the configuration INI file")]
    [string]$ConfigPath = ".\CSVCombiner.ini"
)

# Import functions module
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$functionsPath = Join-Path $scriptDir "CSVCombiner-Functions.ps1"
if (Test-Path $functionsPath) {
    . $functionsPath
    Write-Verbose "Loaded functions from: $functionsPath"
} else {
    Write-Error "Required functions module not found: $functionsPath"
    exit 1
}

# Function to load and validate configuration
function Initialize-Configuration {
    param([string]$ConfigPath)
    
    try {
        Write-Log "Loading configuration from: $ConfigPath" "INFO"
        
        # Read the configuration file
        $newConfig = Read-IniFile -FilePath $ConfigPath
        
        # Validate required sections and settings
        if (!$newConfig.General) {
            Write-Log "Missing [General] section in configuration file: $ConfigPath" "ERROR"
            return $false
        }
        
        if (!$newConfig.General.InputFolder) {
            Write-Log "Missing or empty InputFolder setting in configuration file: $ConfigPath" "ERROR"
            return $false
        }
        
        if (!$newConfig.General.OutputFolder) {
            Write-Log "Missing or empty OutputFolder setting in configuration file: $ConfigPath" "ERROR"
            return $false
        }
        
        # OutputBaseName is required for the new naming system
        if (!$newConfig.General.OutputBaseName) {
            Write-Log "Missing or empty OutputBaseName setting in configuration file: $ConfigPath" "ERROR"
            return $false
        }
        
        # Validate that input folder exists
        if (!(Test-Path $newConfig.General.InputFolder)) {
            Write-Log "Input folder does not exist: $($newConfig.General.InputFolder)" "ERROR"
            return $false
        }
        
        # Validate that output directory exists or can be created
        $outputDir = $newConfig.General.OutputFolder
        if ($outputDir -and !(Test-Path $outputDir)) {
            try {
                New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
                Write-Log "Created output directory: $outputDir" "INFO"
            }
            catch {
                Write-Log "Cannot create output directory: $outputDir - $($_.Exception.Message)" "ERROR"
                return $false
            }
        }
        
        # All validation passed - update the global configuration
        $script:config = $newConfig
        
        Write-Log "Configuration loaded and validated successfully" "INFO"
        return $true
    }
    catch {
        Write-Log "Error reading configuration file: $($_.Exception.Message)" "ERROR"
        Write-Log "Configuration load failed" "ERROR"
        return $false
    }
}

# Function to validate filename format
# Function to write CSV file with simple retry logic
function Write-CSV {
    param(
        [array]$Data,
        [string]$OutputPath
    )
    
    try {
        # Try to write the file
        $Data | Export-Csv -Path $OutputPath -NoTypeInformation
        Write-Log "Combined CSV saved to: $OutputPath ($($Data.Count) records)"
        return $true
    }
    catch {
        # Check if this is a file-in-use error
        if ($_.Exception.Message -like "*being used by another process*" -or 
            $_.Exception.Message -like "*cannot access the file*") {
            
            Write-Log "File is currently in use, will retry on next iteration: $OutputPath" "WARNING"
            return $false
        }
        else {
            # Different error - log and fail
            Write-Log "Error writing CSV file: $($_.Exception.Message)" "ERROR"
            return $false
        }
    }
}

# Function to merge CSV files
# Main function that combines all CSV files in a folder using additive processing
# Preserves existing data when source files are deleted, maintains unified column schema
function Merge-CSVFiles {
    param(
        [string]$InputFolder,      # Path to folder containing CSV files to combine
        [bool]$IncludeHeaders = $true,  # Whether to include headers in output
        [object]$Changes = $null   # Optional change information for optimized processing
    )
    
    try {
        $csvFiles = Get-ChildItem -Path $InputFolder -Filter "*.csv" -File
        
        # Get output path without shifting backups yet
        $outputBaseName = $script:config.General.OutputBaseName
        $outputDir = $script:config.General.OutputFolder
        $outputPath = Join-Path $outputDir ($outputBaseName + "_1.csv")
        
        # Load existing master CSV if it exists
        $existingData = @()
        
        if (Test-Path $outputPath) {
            try {
                Write-Log "Loading existing master CSV: $outputPath"
                $existingData = Import-Csv -Path $outputPath
                
                if ($existingData.Count -gt 0) {
                    Write-Log "Existing master has $($existingData.Count) rows with $($existingData[0].PSObject.Properties.Count) columns"
                }
            }
            catch {
                Write-Log "Error loading existing master CSV: $($_.Exception.Message)" "WARNING"
                $existingData = @()
            }
        }
        
        # If this is the initial run or no changes specified, process all files
        if ($null -eq $Changes) {
            Write-Log "Initial run: Processing all $($csvFiles.Count) CSV files"
            $filesToProcess = $csvFiles
        }
        else {
            # Process only new and modified files for additive approach
            $filesToProcess = @()
            foreach ($fileName in ($Changes.NewFiles + $Changes.ModifiedFiles)) {
                $file = $csvFiles | Where-Object { $_.Name -eq $fileName }
                if ($file) {
                    $filesToProcess += $file
                }
            }
            Write-Log "Additive update: Processing $($filesToProcess.Count) changed files"
            
            # For modified files, remove their existing data first
            if ($Changes.ModifiedFiles.Count -gt 0 -and $existingData.Count -gt 0) {
                Write-Log "Removing data from $($Changes.ModifiedFiles.Count) modified files"
                $existingData = $existingData | Where-Object {
                    if ($script:config.General.IncludeTimestamp -eq "true" -and $_."Timestamp") {
                        # Timestamp now contains the full filename (including .csv)
                        $sourceFileName = $_."Timestamp"
                        $sourceFileName -notin $Changes.ModifiedFiles
                    } else {
                        # If no timestamp column, keep the row (safer approach)
                        $true
                    }
                }
                Write-Log "After removal: $($existingData.Count) rows remain"
            }
        }
        
        if ($filesToProcess.Count -eq 0) {
            Write-Log "No files to process"
            return $actualOutputPath
        }
        
        # Collect columns from new/modified files
        $dataColumns = [System.Collections.Generic.HashSet[string]]::new()
        $fileDataMap = @{}
        foreach ($csvFile in $filesToProcess) {
            Write-Log "Processing: $($csvFile.Name)" "INFO" $script:config.General.LogFile
            
            # Validate filename format if enabled
            $validateFormat = ($script:config.General.ValidateFilenameFormat -eq "true")
            if (!(Test-FilenameFormat -FileName $csvFile.Name -ValidateFormat $validateFormat)) {
                Write-Log "Skipping file with invalid format: $($csvFile.Name)" "WARNING" $script:config.General.LogFile
                $fileDataMap[$csvFile.Name] = @()
                continue
            }
            
            try {
                # Check if file is empty or has no content
                $fileContent = Get-Content -Path $csvFile.FullName -Raw
                if ([string]::IsNullOrWhiteSpace($fileContent)) {
                    Write-Log "Skipping empty file: $($csvFile.Name)" "WARNING"
                    $fileDataMap[$csvFile.Name] = @()
                    continue
                }
                
                # Check if file has at least a header line
                $lines = Get-Content -Path $csvFile.FullName
                if ($lines.Count -eq 0 -or [string]::IsNullOrWhiteSpace($lines[0])) {
                    Write-Log "Skipping file with no header: $($csvFile.Name)" "WARNING"
                    $fileDataMap[$csvFile.Name] = @()
                    continue
                }
                
                # Debug: Show first few lines of the CSV
                Write-Log "DEBUG: File has $($lines.Count) lines, first line: '$($lines[0])'"
                if ($lines.Count -gt 1) {
                    Write-Log "DEBUG: Second line: '$($lines[1])'"
                }
                
                # Fix duplicate column names before importing
                $headerLine = $lines[0]
                $columnNames = $headerLine -split ','
                $uniqueColumnNames = @()
                $columnCounts = @{}
                
                foreach ($columnName in $columnNames) {
                    $trimmedName = $columnName.Trim()
                    if ($columnCounts.ContainsKey($trimmedName)) {
                        $columnCounts[$trimmedName]++
                        $uniqueName = "${trimmedName}_$($columnCounts[$trimmedName])"
                    } else {
                        $columnCounts[$trimmedName] = 1
                        $uniqueName = $trimmedName
                    }
                    $uniqueColumnNames += $uniqueName
                }
                
                # Create a temporary CSV with unique headers
                $tempCsvContent = @()
                $tempCsvContent += $uniqueColumnNames -join ','
                
                # Add data rows (skip header)
                for ($i = 1; $i -lt $lines.Count; $i++) {
                    $tempCsvContent += $lines[$i]
                }
                
                # Write temporary CSV and import it
                $tempFile = [System.IO.Path]::GetTempFileName() + ".csv"
                try {
                    $tempCsvContent | Out-File -FilePath $tempFile -Encoding UTF8
                    $csvContent = Import-Csv -Path $tempFile
                    
                    Write-Log "DEBUG: Successfully imported CSV with $($csvContent.Count) rows and unique column names"
                } finally {
                    # Clean up temp file
                    if (Test-Path $tempFile) {
                        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
                    }
                }
                
                # Debug: Show what properties were imported
                if ($csvContent.Count -gt 0) {
                    $propertyNames = $csvContent[0].PSObject.Properties.Name
                    Write-Log "DEBUG: Imported properties: $($propertyNames -join ', ')"
                }
                
                # The CSV content is now ready to use (duplicate column names have been made unique)
                $fileDataMap[$csvFile.Name] = $csvContent
                
                if ($csvContent.Count -gt 0) {
                    # Collect all column names from this file (excluding metadata)
                    $firstRow = $csvContent[0]
                    $firstRow.PSObject.Properties.Name | ForEach-Object {
                        $dataColumns.Add($_) | Out-Null
                    }
                }
            }
            catch {
                Write-Log "Error processing $($csvFile.Name): $($_.Exception.Message)" "ERROR"
                $fileDataMap[$csvFile.Name] = @()
            }
        }
        
        # Create unified schema using modular function
        $existingColumns = @()
        if ($existingData.Count -gt 0) {
            $existingColumns = $existingData[0].PSObject.Properties.Name
        }
        $newColumns = $dataColumns.ToArray()
        $includeTimestamp = ($script:config.General.IncludeTimestamp -eq "true")
        $allColumns = Merge-ColumnSchemas -ExistingColumns $existingColumns -NewColumns $newColumns -IncludeTimestamp $includeTimestamp
        
        Write-Log "Unified schema contains $($allColumns.Count) columns: $($allColumns -join ', ')" "INFO" $script:config.General.LogFile
        
        # Process new data from changed files using modular function
        $newData = @()
        foreach ($csvFile in $filesToProcess) {
            $csvContent = $fileDataMap[$csvFile.Name]
            
            foreach ($row in $csvContent) {
                # Use modular function to create unified row
                $timestampValue = if ($includeTimestamp) { $csvFile.Name } else { $null }
                $unifiedRow = New-UnifiedRow -SourceRow $row -UnifiedSchema $allColumns -TimestampValue $timestampValue
                $newData += $unifiedRow
            }
        }
        
        # Ensure existing data has all columns (expand schema if needed) using modular function
        if ($existingData.Count -gt 0) {
            $expandedExistingData = @()
            foreach ($row in $existingData) {
                $expandedRow = New-UnifiedRow -SourceRow $row -UnifiedSchema $allColumns
                $expandedExistingData += $expandedRow
            }
            $existingData = $expandedExistingData
        }
        
        # Combine existing and new data
        $combinedData = $existingData + $newData
        
        Write-Log "Final dataset: $($combinedData.Count) total rows ($($existingData.Count) existing + $($newData.Count) new)"
        
        if ($combinedData.Count -gt 0) {
            # Now get the actual output path using modular function
            $actualOutputPath = Get-CurrentOutputPath -OutputFolder $script:config.General.OutputFolder -BaseName $script:config.General.OutputBaseName -MaxBackups ([int]$script:config.General.MaxBackups)
            
            # Create output directory if it doesn't exist
            $outputDir = Split-Path -Path $actualOutputPath -Parent
            if (!(Test-Path $outputDir)) {
                New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
            }
            
            # Use simple file writing with retry on next iteration
            $writeSuccess = Write-CSV -Data $combinedData -OutputPath $actualOutputPath
            
            if (!$writeSuccess) {
                Write-Log "CSV write skipped due to file access issue - will retry on next iteration" "WARNING"
                return $null
            }
            
            return $actualOutputPath
        }
        else {
            Write-Log "No data to write" "WARNING"
            return $null
        }
    }
    catch {
        Write-Log "Error in additive CSV combining: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# ===========================
# POLLING-BASED FILE MONITORING FUNCTIONS
# ===========================

# Main execution
Write-Log "=== CSV Combiner Started ==="
Write-Log "Config file: $ConfigPath"

# Store config path for event handlers to access
$script:ConfigPath = $ConfigPath

# Create PID file for process management
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$pidFile = Join-Path $scriptDir "csvcombiner.pid"
$PID | Out-File -FilePath $pidFile -Encoding ASCII
Write-Log "PID file created: $pidFile (PID: $PID)"

# Set up cleanup on exit
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    $scriptDir = Split-Path $using:MyInvocation.MyCommand.Path -Parent
    $pidFile = Join-Path $scriptDir "csvcombiner.pid"
    if (Test-Path $pidFile) {
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    }
}

# Load and validate configuration
if (!(Initialize-Configuration -ConfigPath $ConfigPath)) {
    Write-Log "Configuration validation failed. Please check your configuration file: $ConfigPath" "ERROR"
    exit 1
}

$inputFolder = $script:config.General.InputFolder

# Perform initial scan of existing files
Write-Log "Performing initial scan of existing files..."
$outputPath = Merge-CSVFiles -InputFolder $inputFolder

if ($outputPath) {
    Write-Log "Initial processing complete: $outputPath"
} else {
    Write-Log "No CSV files found during initial scan"
}

# Set up polling-based file monitoring
Write-Log "Setting up polling-based file monitoring..."

# Convert forward slashes to backslashes for Windows compatibility
$windowsPath = $inputFolder -replace "/", "\"
Write-Log "Monitoring folder: $windowsPath"

# Validate polling configuration
$pollingInterval = [int]$script:config.Advanced.PollingInterval
if ($pollingInterval -lt 1) { $pollingInterval = 10 }

Write-Log "Polling interval: ${pollingInterval} seconds"
Write-Log "File hashing enabled: $($script:config.Advanced.UseFileHashing)"
Write-Log "File stability wait time: $($script:config.Advanced.WaitForStableFile)ms"

# Take initial file snapshot
$useFileHashing = ($script:config.Advanced.UseFileHashing -eq "true")
$validateFormat = ($script:config.General.ValidateFilenameFormat -eq "true")
$lastSnapshot = Get-FileSnapshot -FolderPath $inputFolder -UseFileHashing $useFileHashing -ValidateFilenameFormat $validateFormat

Write-Log "CSV Combiner is now running in polling mode."
Write-Log "The script will check for changes every ${pollingInterval} seconds in: $inputFolder"
Write-Log "Press Ctrl+C to stop the script."

# Main polling loop
try {
    Write-Log "CSV Combiner is running in polling mode."
    Write-Log "Configuration loaded at startup will be used for the entire session."
    Write-Log "DEBUG: Entering main polling loop..."
    
    $loopCount = 0
    while ($true) {
        $loopCount++
        Write-Log "DEBUG: Starting polling cycle #$loopCount"
        
        # Wait for the polling interval
        Write-Log "DEBUG: Sleeping for $pollingInterval seconds..."
        Start-Sleep -Seconds $pollingInterval
        Write-Log "DEBUG: Sleep completed, taking file snapshot..."
        
        # Take new snapshot and compare
        try {
            Write-Log "DEBUG: Calling Get-FileSnapshot for: $inputFolder"
            $snapshotStartTime = Get-Date
            $currentSnapshot = Get-FileSnapshot -FolderPath $inputFolder -UseFileHashing $useFileHashing -ValidateFilenameFormat $validateFormat
            $snapshotDuration = (Get-Date) - $snapshotStartTime
            Write-Log "DEBUG: Snapshot took $($snapshotDuration.TotalSeconds) seconds"
            
            Write-Log "DEBUG: Snapshot taken, comparing with previous snapshot..."
            $compareStartTime = Get-Date
            $changes = Compare-FileSnapshots -OldSnapshot $lastSnapshot -NewSnapshot $currentSnapshot -ValidateFilenameFormat $validateFormat
            $compareDuration = (Get-Date) - $compareStartTime
            Write-Log "DEBUG: Comparison took $($compareDuration.TotalSeconds) seconds"
            Write-Log "DEBUG: Comparison complete. HasChanges: $($changes.HasChanges)"
            
            if ($changes.HasChanges) {
                Write-Log "File changes detected!"
                foreach ($detail in $changes.Details) {
                    Write-Log "  $detail"
                }
                
                # Wait for files to stabilize
                $csvFiles = Get-ChildItem -Path $inputFolder -Filter "*.csv" -File
                $waitTime = [int]$script:config.Advanced.WaitForStableFile
                $maxRetries = [int]$script:config.Advanced.MaxPollingRetries
                $null = Wait-ForFileStability -CsvFiles $csvFiles -WaitTime $waitTime -MaxRetries $maxRetries -ValidateFilenameFormat $validateFormat
                
                # Use additive processing with change information
                Write-Log "Performing additive update based on detected changes..."
                
                # Call the Merge-CSVFiles function with changes information
                $outputPath = Merge-CSVFiles -InputFolder $script:config.General.InputFolder -Changes $changes
                
                if ($outputPath) {
                    Write-Log "Additive update complete: $outputPath (triggered by polling detection)"
                } else {
                    Write-Log "No changes to process during additive update"
                }
                
                # Update snapshot after successful processing
                $lastSnapshot = Get-FileSnapshot -FolderPath $inputFolder -UseFileHashing $useFileHashing -ValidateFilenameFormat $validateFormat
            } else {
                Write-Log "DEBUG: No changes detected, continuing to next polling cycle..."
            }
        }
        catch {
            Write-Log "ERROR: Exception during polling cycle: $($_.Exception.Message)" "ERROR"
            Write-Log "DEBUG: Stack trace: $($_.ScriptStackTrace)" "ERROR"
            # Continue polling even if one cycle fails
        }
        
        Write-Log "DEBUG: Completed polling cycle #$loopCount, starting next cycle..."
    }
}
catch {
    Write-Log "FATAL: Unexpected error in main polling loop: $($_.Exception.Message)" "ERROR"
    Write-Log "DEBUG: Stack trace: $($_.ScriptStackTrace)" "ERROR"
}
finally {
    Write-Log "=== CSV Combiner Stopped ==="
    # Clean up PID file
    $scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
    $pidFile = Join-Path $scriptDir "csvcombiner.pid"
    if (Test-Path $pidFile) {
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
        Write-Log "PID file removed: $pidFile"
    }
}
