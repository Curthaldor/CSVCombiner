# ==============================================================================
# CSV Combiner Script v2.0
# ==============================================================================
# Author: Curt Haldorson, GitHub Copilot Assistant
# Created: August 2025
# Purpose: Monitors a folder for CSV files and combines them into a master CSV
# 
# FEATURES:
# - Additive processing (preserves existing data when new files are added)
# - Unified schema merging (handles different column structures)
# - Configurable timestamp metadata column (extracted from filename)
# - Streaming append processing (no duplicate checking)
# - Polling-based file monitoring (reliable, no admin privileges required)
# - Automatic backup management with configurable retention
# - File stability checks to prevent processing incomplete files
# - Simple retry logic for file-in-use scenarios (waits for next iteration)
# - PID file management for reliable start/stop operations
#
# USAGE:
#   powershell -ExecutionPolicy Bypass -File CSVCombiner.ps1 -ConfigPath CSVCombiner.ini
#   
# DEPENDENCIES:
# - Windows PowerShell 5.1+ (built into Windows 10/11)
# - CSVCombiner.ini configuration file
# - Write access to input/output folders
#
# ==============================================================================

param(
    [Parameter(Mandatory=$false, HelpMessage="Path to the configuration INI file")]
    [string]$ConfigPath = ".\CSVCombiner.ini"
)

# Function to read INI file
function Read-IniFile {
    param([string]$FilePath)
    
    $ini = @{}
    if (Test-Path $FilePath) {
        $content = Get-Content $FilePath
        $currentSection = "General"
        $ini[$currentSection] = @{}
        
        foreach ($line in $content) {
            $line = $line.Trim()
            if ($line -eq "" -or $line.StartsWith("#") -or $line.StartsWith(";")) {
                continue
            }
            
            if ($line.StartsWith("[") -and $line.EndsWith("]")) {
                $currentSection = $line.Substring(1, $line.Length - 2)
                $ini[$currentSection] = @{}
            }
            elseif ($line.Contains("=")) {
                $key, $value = $line.Split("=", 2)
                $ini[$currentSection][$key.Trim()] = $value.Trim()
            }
        }
    }
    return $ini
}

# Function to load and validate configuration
function Initialize-Configuration {
    param([string]$ConfigPath)
    
    try {
        Write-Log "Loading configuration from: $ConfigPath"
        
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
                Write-Log "Created output directory: $outputDir"
            }
            catch {
                Write-Log "Cannot create output directory: $outputDir - $($_.Exception.Message)" "ERROR"
                return $false
            }
        }
        
        # All validation passed - update the global configuration
        $script:config = $newConfig
        
        Write-Log "Configuration loaded and validated successfully"
        return $true
    }
    catch {
        Write-Log "Error reading configuration file: $($_.Exception.Message)" "ERROR"
        Write-Log "Configuration load failed" "ERROR"
        return $false
    }
}

# Function to write log messages
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    
    # Also write to log file if specified in config
    if ($script:config.General.LogFile) {
        Add-Content -Path $script:config.General.LogFile -Value $logMessage -ErrorAction SilentlyContinue
    }
}

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
            Write-Log "Processing: $($csvFile.Name)"
            
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
        
        # Create ordered column list: metadata columns first, then data columns
        $allColumns = [System.Collections.Generic.List[string]]::new()
        
        # Add metadata column (if enabled)
        if ($script:config.General.IncludeTimestamp -eq "true") {
            $allColumns.Add("Timestamp")
        }
        
        # Add data columns from existing data (if any)
        if ($existingData.Count -gt 0) {
            $existingData[0].PSObject.Properties.Name | ForEach-Object {
                $columnName = $_
                # Skip metadata column and system properties
                if ($columnName -notmatch '^(PSObject|PSTypeNames|NullData)' -and 
                    $columnName -ne "Timestamp") {
                    if (-not $allColumns.Contains($columnName)) {
                        $allColumns.Add($columnName)
                    }
                }
            }
        }
        
        # Add new data columns
        foreach ($columnName in $dataColumns) {
            if (-not $allColumns.Contains($columnName)) {
                $allColumns.Add($columnName)
            }
        }
        
        Write-Log "Unified schema contains $($allColumns.Count) columns: $($allColumns -join ', ')"
        
        # Process new data from changed files
        $newData = @()
        foreach ($csvFile in $filesToProcess) {
            $csvContent = $fileDataMap[$csvFile.Name]
            
            foreach ($row in $csvContent) {
                $unifiedRow = [ordered]@{}
                
                # Initialize all columns with empty values
                foreach ($column in $allColumns) {
                    $unifiedRow[$column] = ""
                }
                
                # Fill in actual values from this row (exclude system properties)
                $row.PSObject.Properties | ForEach-Object {
                    # Only include properties that are actual data columns
                    if ($_.Name -notmatch '^(PSObject|PSTypeNames|NullData)' -and $allColumns.Contains($_.Name)) {
                        $unifiedRow[$_.Name] = $_.Value
                    }
                }
                
                # Add timestamp metadata if enabled (keep full filename including .csv)
                if ($script:config.General.IncludeTimestamp -eq "true") {
                    # Use the full filename (including .csv extension) to prevent Excel scientific notation
                    $unifiedRow["Timestamp"] = $csvFile.Name
                }
                
                $newData += [PSCustomObject]$unifiedRow
            }
        }
        
        # Ensure existing data has all columns (expand schema if needed)
        if ($existingData.Count -gt 0) {
            $expandedExistingData = @()
            foreach ($row in $existingData) {
                $expandedRow = [ordered]@{}
                
                # Initialize all columns
                foreach ($column in $allColumns) {
                    $expandedRow[$column] = ""
                }
                
                # Fill in existing values (exclude system properties)
                $row.PSObject.Properties | ForEach-Object {
                    if ($_.Name -notmatch '^(PSObject|PSTypeNames|NullData)' -and $allColumns.Contains($_.Name)) {
                        $expandedRow[$_.Name] = $_.Value
                    }
                }
                
                $expandedExistingData += [PSCustomObject]$expandedRow
            }
            $existingData = $expandedExistingData
        }
        
        # Combine existing and new data
        $combinedData = $existingData + $newData
        
        Write-Log "Final dataset: $($combinedData.Count) total rows ($($existingData.Count) existing + $($newData.Count) new)"
        
        if ($combinedData.Count -gt 0) {
            # Now get the actual output path (this will handle backup shifting)
            $actualOutputPath = Get-CurrentOutputPath
            
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

# Function to get the numbered output file path
function Get-NumberedOutputPath {
    param(
        [string]$BaseName,
        [string]$OutputDir,
        [int]$Number = 1
    )
    
    $extension = ".csv"
    $numberedName = "${BaseName}_${Number}${extension}"
    return Join-Path $OutputDir $numberedName
}

# Function to shift backup files and get current output path
function Get-CurrentOutputPath {
    try {
        $baseName = $script:config.General.OutputBaseName
        $outputDir = $script:config.General.OutputFolder
        $maxBackups = [int]$script:config.General.MaxBackups
        
        # If MaxBackups is 1, always use suffix 1
        if ($maxBackups -eq 1) {
            return Get-NumberedOutputPath -BaseName $baseName -OutputDir $outputDir -Number 1
        }
        
        # For MaxBackups > 1 or MaxBackups = 0 (infinite), shift existing files
        $currentPath = Get-NumberedOutputPath -BaseName $baseName -OutputDir $outputDir -Number 1
        
        # Find existing numbered files
        $pattern = "${baseName}_*.csv"
        $existingFiles = Get-ChildItem -Path $outputDir -Filter $pattern -File -ErrorAction SilentlyContinue | 
                        Where-Object { $_.BaseName -match "^${baseName}_(\d+)$" } |
                        Sort-Object { [int]($_.BaseName -replace "^${baseName}_", "") } -Descending
        
        if ($existingFiles.Count -gt 0) {
            # Shift existing files up by one number
            foreach ($file in $existingFiles) {
                if ($file.BaseName -match "^${baseName}_(\d+)$") {
                    $currentNum = [int]$matches[1]
                    $newNum = $currentNum + 1
                    $newPath = Get-NumberedOutputPath -BaseName $baseName -OutputDir $outputDir -Number $newNum
                    
                    # Only shift if we're keeping this backup (MaxBackups = 0 means infinite)
                    if ($maxBackups -eq 0 -or $newNum -le $maxBackups) {
                        Move-Item -Path $file.FullName -Destination $newPath -Force
                        Write-Log "Shifted backup: $($file.Name) -> $(Split-Path $newPath -Leaf)"
                    }
                    else {
                        # Delete files that exceed MaxBackups
                        Remove-Item -Path $file.FullName -Force
                        Write-Log "Deleted old backup: $($file.Name) (exceeded MaxBackups=$maxBackups)"
                    }
                }
            }
        }
        
        return $currentPath
    }
    catch {
        Write-Log "Error managing numbered output files: $($_.Exception.Message)" "ERROR"
        # Fallback to basic path construction
        return Join-Path $script:config.General.OutputFolder "$($script:config.General.OutputBaseName)_1.csv"
    }
}

# ===========================
# POLLING-BASED FILE MONITORING FUNCTIONS
# ===========================

# Creates a snapshot of all CSV files in a folder for change detection
# Returns hashtable with file information including names, sizes, dates, and optional hashes
function Get-FileSnapshot {
    param([string]$FolderPath)  # Path to folder to snapshot
    
    Write-Log "DEBUG: Get-FileSnapshot called for: $FolderPath"
    
    $snapshot = @{
        Files = @{}
        LastCheck = Get-Date
    }
    
    try {
        Write-Log "DEBUG: Checking if folder exists: $FolderPath"
        if (!(Test-Path $FolderPath)) {
            Write-Log "ERROR: Folder does not exist: $FolderPath" "ERROR"
            return $snapshot
        }
        
        Write-Log "DEBUG: Getting CSV files from: $FolderPath"
        $csvFiles = Get-ChildItem -Path $FolderPath -Filter "*.csv" -File -ErrorAction Stop
        Write-Log "DEBUG: Found $($csvFiles.Count) CSV files"
        
        foreach ($file in $csvFiles) {
            Write-Log "DEBUG: Processing file: $($file.Name)"
            $fileHash = ""
            if ($script:config.Advanced.UseFileHashing -eq $true) {
                Write-Log "DEBUG: Calculating hash for: $($file.Name)"
                try {
                    $fileHash = (Get-FileHash $file.FullName -Algorithm MD5).Hash
                    Write-Log "DEBUG: Hash calculated successfully for: $($file.Name)"
                } catch {
                    Write-Log "Warning: Could not calculate hash for $($file.Name): $_" "WARNING"
                    $fileHash = "HASH_ERROR"
                }
            }
            
            Write-Log "DEBUG: Adding file to snapshot: $($file.Name)"
            $snapshot.Files[$file.Name] = @{
                LastWriteTime = $file.LastWriteTime
                Size = $file.Length
                Hash = $fileHash
                FullPath = $file.FullName
            }
        }
        
        Write-Log "DEBUG: Snapshot complete. Total files in snapshot: $($snapshot.Files.Count)"
        return $snapshot
    }
    catch {
        Write-Log "ERROR: Exception in Get-FileSnapshot: $($_.Exception.Message)" "ERROR"
        Write-Log "DEBUG: Returning empty snapshot due to error"
        return $snapshot
    }
}

# Compares two file snapshots and returns detailed change information
# Detects added, removed, and modified files with descriptive change details
function Compare-Snapshots {
    param($OldSnapshot, $NewSnapshot)  # Snapshot objects to compare
    
    Write-Log "DEBUG: Compare-Snapshots called"
    Write-Log "DEBUG: Old snapshot has $($OldSnapshot.Files.Count) files"
    Write-Log "DEBUG: New snapshot has $($NewSnapshot.Files.Count) files"
    
    $changes = @{
        HasChanges = $false
        NewFiles = @()
        ModifiedFiles = @()
        DeletedFiles = @()
        Details = @()
    }
    
    Write-Log "DEBUG: Checking for new files..."
    # Check for new files
    foreach ($fileName in $NewSnapshot.Files.Keys) {
        if (-not $OldSnapshot.Files.ContainsKey($fileName)) {
            Write-Log "DEBUG: Found new file: $fileName"
            $changes.NewFiles += $fileName
            $changes.HasChanges = $true
            $changes.Details += "NEW: $fileName"
        }
    }
    
    # Check for modified or deleted files
    foreach ($fileName in $OldSnapshot.Files.Keys) {
        if ($NewSnapshot.Files.ContainsKey($fileName)) {
            $oldFile = $OldSnapshot.Files[$fileName]
            $newFile = $NewSnapshot.Files[$fileName]
            
            $isModified = $false
            
            # Check size and timestamp first (fast)
            if ($oldFile.Size -ne $newFile.Size -or $oldFile.LastWriteTime -ne $newFile.LastWriteTime) {
                $isModified = $true
            }
            # If hashing is enabled and basic checks passed, compare hashes (slower but accurate)
            elseif ($script:config.Advanced.UseFileHashing -eq $true -and $oldFile.Hash -ne "" -and $newFile.Hash -ne "" -and $oldFile.Hash -ne $newFile.Hash) {
                $isModified = $true
            }
            
            if ($isModified) {
                $changes.ModifiedFiles += $fileName
                $changes.HasChanges = $true
                $changes.Details += "MODIFIED: $fileName"
            }
        } else {
            # File was deleted
            Write-Log "DEBUG: Found deleted file: $fileName"
            $changes.DeletedFiles += $fileName
            $changes.HasChanges = $true
            $changes.Details += "DELETED: $fileName"
        }
    }
    
    Write-Log "DEBUG: Comparison complete - Changes: $($changes.HasChanges), New: $($changes.NewFiles.Count), Modified: $($changes.ModifiedFiles.Count), Deleted: $($changes.DeletedFiles.Count)"
    return $changes
}

# Waits for files to stabilize before processing to avoid reading incomplete files
# Checks if files are locked and retries until they're accessible
function Wait-ForFileStability {
    param([string]$FolderPath)  # Path to folder containing files to check
    
    $waitTime = [int]$script:config.Advanced.WaitForStableFile
    $maxRetries = [int]$script:config.Advanced.MaxPollingRetries
    
    if ($waitTime -le 0) { return $true }
    
    Write-Log "Waiting ${waitTime}ms for files to stabilize..."
    Start-Sleep -Milliseconds $waitTime
    
    # Verify files are not locked
    $csvFiles = Get-ChildItem -Path $FolderPath -Filter "*.csv" -File -ErrorAction SilentlyContinue
    
    foreach ($file in $csvFiles) {
        $retryCount = 0
        $isStable = $false
        
        while ($retryCount -lt $maxRetries -and -not $isStable) {
            try {
                # Try to open file exclusively to check if it's being written
                $stream = [System.IO.File]::Open($file.FullName, 'Open', 'Read', 'None')
                $stream.Close()
                $isStable = $true
            } catch {
                $retryCount++
                Write-Log "File $($file.Name) appears to be in use, retry $retryCount/$maxRetries" "WARNING"
                Start-Sleep -Milliseconds 500
            }
        }
        
        if (-not $isStable) {
            Write-Log "Warning: File $($file.Name) may still be in use after $maxRetries retries" "WARNING"
        }
    }
    
    return $true
}

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
$lastSnapshot = Get-FileSnapshot $inputFolder

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
            $currentSnapshot = Get-FileSnapshot $inputFolder
            $snapshotDuration = (Get-Date) - $snapshotStartTime
            Write-Log "DEBUG: Snapshot took $($snapshotDuration.TotalSeconds) seconds"
            
            Write-Log "DEBUG: Snapshot taken, comparing with previous snapshot..."
            $compareStartTime = Get-Date
            $changes = Compare-Snapshots $lastSnapshot $currentSnapshot
            $compareDuration = (Get-Date) - $compareStartTime
            Write-Log "DEBUG: Comparison took $($compareDuration.TotalSeconds) seconds"
            Write-Log "DEBUG: Comparison complete. HasChanges: $($changes.HasChanges)"
            
            if ($changes.HasChanges) {
                Write-Log "File changes detected!"
                foreach ($detail in $changes.Details) {
                    Write-Log "  $detail"
                }
                
                # Wait for files to stabilize
                $null = Wait-ForFileStability $inputFolder
                
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
                $lastSnapshot = Get-FileSnapshot $inputFolder
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
