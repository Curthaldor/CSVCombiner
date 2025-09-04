# ==============================================================================
# CSV Combiner Script v2.4 - Modular Architecture with Main Function
# ==============================================================================
# Author: Curt Haldorson, GitHub Copilot Assistant
# Created: August 2025
# Updated: September 2025 - Added main function for improved structure
# Purpose: Monitors a folder for CSV files and combines them into a master CSV
# 
# FEATURES:
# - Additive processing (preserves existing data when new files are added)
# - Unified schema merging (handles different column structures)
# - Configurable timestamp metadata column (extracted from filename)
# - High-performance streaming processing for maximum throughput
# - Optional filename format validation (14-digit timestamp format)
# - Polling-based file monitoring (reliable, no admin privileges required)
# - File stability checks to prevent processing incomplete files
# - Simple retry logic for file-in-use scenarios (waits for next iteration)
# - PID file management for reliable start/stop operations
# - Modular architecture with extracted functions for better testability
# - Main function encapsulation for improved structure and testing
#
# USAGE:
#   Single-run mode (default - process once and exit):
#   powershell -ExecutionPolicy Bypass -File CSVCombiner.ps1 -ConfigPath CSVCombiner.ini
#   
#   Continuous monitoring mode:
#   powershell -ExecutionPolicy Bypass -File CSVCombiner.ps1 -ConfigPath CSVCombiner.ini -Monitor
#   
#   Or call the main function directly (useful for testing):
#   . .\CSVCombiner.ps1
#   Start-CSVCombiner -ConfigPath "CSVCombiner.ini" -Monitor
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
    [string]$ConfigPath = ".\CSVCombiner.ini",
    
    [Parameter(Mandatory=$false, HelpMessage="Enable continuous monitoring mode instead of single-run")]
    [switch]$Monitor
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

# Function to merge CSV files using memory-efficient streaming approach
# Optimized for small input files (≤30 rows) but large master output files
function Merge-CSVFiles {
    param(
        [string]$InputFolder,      # Path to folder containing CSV files to combine
        [bool]$IncludeHeaders = $true,  # Whether to include headers in output
        [object]$Changes = $null   # Optional change information for optimized processing
    )
    
    try {
        $csvFiles = Get-ChildItem -Path $InputFolder -Filter "*.csv" -File
        
        # Get output path
        $outputBaseName = $script:config.General.OutputBaseName
        $outputDir = $script:config.General.OutputFolder
        $outputPath = Join-Path $outputDir ($outputBaseName + ".csv")
        
        # Verify output file exists and validate content
        $outputFileExists = Test-Path $outputPath
        $existingSchema = @()
        $existingRowCount = 0
        $processedFiles = @()
        
        if ($outputFileExists) {
            Write-Log "Output file exists: $outputPath"
            
            # Get existing master file schema and content validation
            $existingSchema = Get-MasterFileSchema -MasterFilePath $outputPath
            $existingRowCount = Get-MasterFileRowCount -MasterFilePath $outputPath
            $processedFiles = Get-ProcessedFilenames -MasterFilePath $outputPath
            
            if ($existingRowCount -gt 0) {
                Write-Log "Existing master has $existingRowCount rows with $($existingSchema.Count) columns"
                Write-Log "Found $($processedFiles.Count) processed files in master: $($processedFiles -join ', ')"
            }
            else {
                Write-Log "Master file exists but is empty - will recreate" "WARNING"
                $outputFileExists = $false
            }
        }
        else {
            Write-Log "No output file found - will create new master file"
        }
        
        # Determine which files need processing
        if ($null -eq $Changes) {
            # Initial run or manual launch - validate content and process missing files
            if ($outputFileExists -and $processedFiles.Count -gt 0) {
                # Find files that are not yet processed
                $missingFiles = @()
                foreach ($file in $csvFiles) {
                    if ($processedFiles -notcontains $file.Name) {
                        $missingFiles += $file
                    }
                }
                
                if ($missingFiles.Count -gt 0) {
                    Write-Log "Content validation: Found $($missingFiles.Count) unprocessed files out of $($csvFiles.Count) total files"
                    Write-Log "Missing files: $($missingFiles.Name -join ', ')"
                    $filesToProcess = $missingFiles
                }
                else {
                    Write-Log "Content validation: All $($csvFiles.Count) input files are already processed"
                    $filesToProcess = @()
                }
            }
            else {
                # No master file or empty master file - process all files
                Write-Log "Initial processing: Processing all $($csvFiles.Count) CSV files"
                $filesToProcess = $csvFiles
            }
        }
        else {
            # File change monitoring mode - process only new and modified files
            $filesToProcess = @()
            foreach ($fileName in ($Changes.NewFiles + $Changes.ModifiedFiles)) {
                $file = $csvFiles | Where-Object { $_.Name -eq $fileName }
                if ($file) {
                    $filesToProcess += $file
                }
            }
            Write-Log "Additive update: Processing $($filesToProcess.Count) changed files"
            
            # For modified files, remove their existing data from master file (streaming operation)
            if ($Changes.ModifiedFiles.Count -gt 0 -and $existingRowCount -gt 0) {
                if ($script:config.General.IncludeTimestamp -eq "true") {
                    Write-Log "Removing data from $($Changes.ModifiedFiles.Count) modified files using streaming approach"
                    $removeSuccess = Remove-RowsFromMasterFile -MasterFilePath $outputPath -TimestampsToRemove $Changes.ModifiedFiles
                    if ($removeSuccess) {
                        $newRowCount = Get-MasterFileRowCount -MasterFilePath $outputPath
                        Write-Log "After removal: $newRowCount rows remain in master file"
                        $existingSchema = Get-MasterFileSchema -MasterFilePath $outputPath  # Refresh schema
                    }
                    else {
                        Write-Log "Failed to remove modified file data, proceeding with append" "WARNING"
                    }
                }
                else {
                    Write-Log "Cannot remove modified file data: timestamp tracking disabled" "WARNING"
                }
            }
        }
        
        if ($filesToProcess.Count -eq 0) {
            Write-Log "No files to process"
            return $outputPath
        }
        
        # Process input files (safe to load in memory due to small size ≤30 rows)
        $dataColumns = [System.Collections.Generic.HashSet[string]]::new()
        $newDataRows = @()
        
        foreach ($csvFile in $filesToProcess) {
            Write-Log "Processing: $($csvFile.Name)" "INFO" $script:config.General.LogFile
            
            # Validate filename format if enabled
            $validateFormat = ($script:config.General.ValidateFilenameFormat -eq "true")
            if (!(Test-FilenameFormat -FileName $csvFile.Name -ValidateFormat $validateFormat)) {
                Write-Log "Skipping file with invalid format: $($csvFile.Name)" "WARNING" $script:config.General.LogFile
                continue
            }
            
            try {
                # Check if file is empty or has no content
                $fileContent = Get-Content -Path $csvFile.FullName -Raw
                if ([string]::IsNullOrWhiteSpace($fileContent)) {
                    Write-Log "Skipping empty file: $($csvFile.Name)" "WARNING"
                    continue
                }
                
                # Check if file has at least a header line
                $lines = Get-Content -Path $csvFile.FullName
                if ($lines.Count -eq 0 -or [string]::IsNullOrWhiteSpace($lines[0])) {
                    Write-Log "Skipping file with no header: $($csvFile.Name)" "WARNING"
                    continue
                }
                
                Write-Log "DEBUG: Processing file with $($lines.Count) lines"
                
                # Fix duplicate column names before importing
                $headerLine = $lines[0]
                $columnNames = $headerLine -split ','
                Write-Log "DEBUG: Processing $($columnNames.Count) columns from header" "DEBUG"
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
                
                # Write temporary CSV and import it (small files, safe for memory)
                $tempFile = [System.IO.Path]::GetTempFileName() + ".csv"
                try {
                    $tempCsvContent | Out-File -FilePath $tempFile -Encoding UTF8
                    $csvContent = Import-Csv -Path $tempFile
                    
                    Write-Log "DEBUG: Successfully imported CSV with $($csvContent.Count) rows"
                } finally {
                    # Clean up temp file
                    if (Test-Path $tempFile) {
                        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
                    }
                }
                
                # Process rows from this small file
                if ($csvContent.Count -gt 0) {
                    # Collect column names from this file
                    $firstRow = $csvContent[0]
                    $firstRow.PSObject.Properties.Name | ForEach-Object {
                        $dataColumns.Add($_) | Out-Null
                    }
                    
                    # Convert rows to unified format and add to collection
                    foreach ($row in $csvContent) {
                        $timestampValue = if ($script:config.General.IncludeTimestamp -eq "true") { $csvFile.Name } else { $null }
                        $newDataRows += @{
                            Row = $row
                            Timestamp = $timestampValue
                        }
                    }
                }
            }
            catch {
                Write-Log "Error processing $($csvFile.Name): $($_.Exception.Message)" "ERROR"
            }
        }
        
        Write-Log "DEBUG: Finished processing files, collected $($newDataRows.Count) rows from $($dataColumns.Count) unique columns" "DEBUG"
        
        if ($newDataRows.Count -eq 0) {
            Write-Log "No new data to process"
            return $outputPath
        }

        Write-Log "Processing $($newDataRows.Count) new rows from $($dataColumns.Count) unique columns" "INFO"
        
        # Create unified schema
        $newColumns = [string[]]$dataColumns
        $includeTimestamp = ($script:config.General.IncludeTimestamp -eq "true")
        $allColumns = Merge-ColumnSchemas -ExistingColumns $existingSchema -NewColumns $newColumns -IncludeTimestamp $includeTimestamp
        Write-Log "DEBUG: Schema merge complete with $($allColumns.Count) total columns" "DEBUG"
        
        Write-Log "Unified schema contains $($allColumns.Count) columns: $($allColumns -join ', ')" "INFO" $script:config.General.LogFile
        
        # Convert new data to unified format (use ArrayList for better performance)
        $unifiedNewData = [System.Collections.ArrayList]::new()
        foreach ($dataItem in $newDataRows) {
            $unifiedRow = New-UnifiedRow -SourceRow $dataItem.Row -UnifiedSchema $allColumns -TimestampValue $dataItem.Timestamp
            [void]$unifiedNewData.Add($unifiedRow)
        }
        
        # Remove duplicates from new data (preserving first occurrence, excluding timestamp)
        $excludeColumns = if ($includeTimestamp) { @("Timestamp") } else { @() }
        $unifiedNewData = Remove-DuplicateRows -Data $unifiedNewData -ExcludeColumns $excludeColumns
        
        Write-Log "Processed $($unifiedNewData.Count) unique rows from $($filesToProcess.Count) files (removed $($newDataRows.Count - $unifiedNewData.Count) duplicates)"
        
        # Use the simple output path (no backup rotation)
        $actualOutputPath = Join-Path $script:config.General.OutputFolder ($script:config.General.OutputBaseName + ".csv")
        
        # Create output directory if it doesn't exist
        $outputDir = Split-Path -Path $actualOutputPath -Parent
        if (!(Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }
        
        # Determine if we need to create a new file or append to existing
        $createNewFile = (-not (Test-Path $actualOutputPath)) -or ($existingSchema.Count -eq 0)
        
        # Use memory-efficient append operation
        $appendSuccess = Append-ToMasterFile -MasterFilePath $actualOutputPath -NewData $unifiedNewData -UnifiedSchema $allColumns -CreateNewFile $createNewFile
        
        if ($appendSuccess) {
            $finalRowCount = Get-MasterFileRowCount -MasterFilePath $actualOutputPath
            Write-Log "Successfully updated master file: $actualOutputPath ($finalRowCount total rows)" "INFO"
            return $actualOutputPath
        }
        else {
            Write-Log "Failed to append data to master file" "ERROR"
            return $null
        }
    }
    catch {
        Write-Log "Error in memory-efficient CSV combining: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# ===========================
# MAIN FUNCTION
# ===========================

# Main function that encapsulates the entire CSV Combiner execution logic
function Start-CSVCombiner {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConfigPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$Monitor
    )
    
    try {
        Write-Log "=== CSV Combiner Started ==="
        Write-Log "Config file: $ConfigPath"

        # Store config path for event handlers to access
        $script:ConfigPath = $ConfigPath

        # Create PID file for process management
        $scriptDir = Split-Path $PSCommandPath -Parent
        $pidFile = Join-Path $scriptDir "csvcombiner.pid"
        $PID | Out-File -FilePath $pidFile -Encoding ASCII
        Write-Log "PID file created: $pidFile (PID: $PID)"

        # Set up cleanup on exit
        $null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
            $scriptDir = Split-Path $using:PSCommandPath -Parent
            $pidFile = Join-Path $scriptDir "csvcombiner.pid"
            if (Test-Path $pidFile) {
                Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
            }
        }

        # Load and validate configuration
        if (!(Initialize-Configuration -ConfigPath $ConfigPath)) {
            Write-Log "Configuration validation failed. Please check your configuration file: $ConfigPath" "ERROR"
            return $false
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

        # Check if we should run once and exit (default behavior)
        if (-not $Monitor) {
            Write-Log "Single-run mode: Exiting after initial processing (use -Monitor for continuous mode)"
            return $outputPath
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
        Write-Log "FATAL: Unexpected error in main execution: $($_.Exception.Message)" "ERROR"
        Write-Log "DEBUG: Stack trace: $($_.ScriptStackTrace)" "ERROR"
        return $false
    }
    finally {
        Write-Log "=== CSV Combiner Stopped ==="
        # Clean up PID file
        $scriptDir = Split-Path $PSCommandPath -Parent
        $pidFile = Join-Path $scriptDir "csvcombiner.pid"
        if (Test-Path $pidFile) {
            Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
            Write-Log "PID file removed: $pidFile"
        }
    }
    
    return $true
}

# ===========================
# SCRIPT EXECUTION
# ===========================

# Execute main function when script is run directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    $exitCode = if (Start-CSVCombiner -ConfigPath $ConfigPath -Monitor:$Monitor) { 0 } else { 1 }
    exit $exitCode
}
