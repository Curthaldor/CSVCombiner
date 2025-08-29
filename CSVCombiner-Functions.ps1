# ==============================================================================
# CSV Combiner Functions Module v2.4
# ==============================================================================
# Author: Curt Haldorson, GitHub Copilot Assistant
# Created: August 2025
# Purpose: Modular functions for CSV processing and file operations
# ==============================================================================

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

# Function to write log messages
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$LogFile = $null
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    
    if ($LogFile) {
        Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
    }
}

# Function to validate filename format
function Test-FilenameFormat {
    param(
        [string]$FileName,
        [bool]$ValidateFormat = $true
    )
    
    # If validation is disabled, accept any .csv file
    if (-not $ValidateFormat) {
        return $FileName.EndsWith(".csv", [System.StringComparison]::OrdinalIgnoreCase)
    }
    
    # Expected format: YYYYMMDDHHMMSS.csv (exactly 14 digits + .csv)
    $pattern = "^\d{14}\.csv$"
    return ($FileName -match $pattern)
}

# Function to get numbered output file path
function Get-NumberedOutputPath {
    param(
        [string]$OutputFolder,
        [string]$BaseName,
        [int]$Number = 1
    )
    
    return Join-Path $OutputFolder "${BaseName}_${Number}.csv"
}

# Function to get current output path with backup management
function Get-CurrentOutputPath {
    param(
        [string]$OutputFolder,
        [string]$BaseName,
        [int]$MaxBackups
    )
    
    try {
        # If MaxBackups is 1, always use suffix 1
        if ($MaxBackups -eq 1) {
            return Get-NumberedOutputPath -OutputFolder $OutputFolder -BaseName $BaseName -Number 1
        }
        
        # For MaxBackups > 1 or MaxBackups = 0 (infinite), shift existing files
        $currentPath = Get-NumberedOutputPath -OutputFolder $OutputFolder -BaseName $BaseName -Number 1
        
        # Find existing numbered files
        $pattern = "${BaseName}_*.csv"
        $existingFiles = Get-ChildItem -Path $OutputFolder -Filter $pattern -File -ErrorAction SilentlyContinue | 
                        Where-Object { $_.BaseName -match "^${BaseName}_(\d+)$" } |
                        Sort-Object { [int]($_.BaseName -replace "^${BaseName}_", "") } -Descending
        
        if ($existingFiles.Count -gt 0) {
            # Shift existing files up by one number
            foreach ($file in $existingFiles) {
                if ($file.BaseName -match "^${BaseName}_(\d+)$") {
                    $currentNum = [int]$matches[1]
                    $newNum = $currentNum + 1
                    $newPath = Get-NumberedOutputPath -OutputFolder $OutputFolder -BaseName $BaseName -Number $newNum
                    
                    # Only shift if we're keeping this backup (MaxBackups = 0 means infinite)
                    if ($MaxBackups -eq 0 -or $newNum -le $MaxBackups) {
                        Move-Item -Path $file.FullName -Destination $newPath -Force
                        Write-Log "Shifted backup: $($file.Name) -> $(Split-Path $newPath -Leaf)" "INFO"
                    }
                    else {
                        # Delete files that exceed MaxBackups
                        Remove-Item -Path $file.FullName -Force
                        Write-Log "Deleted old backup: $($file.Name) (exceeded MaxBackups=$MaxBackups)" "INFO"
                    }
                }
            }
        }
        
        return $currentPath
    }
    catch {
        Write-Log "Error managing numbered output files: $($_.Exception.Message)" "ERROR"
        # Fallback to basic path construction
        return Get-NumberedOutputPath -OutputFolder $OutputFolder -BaseName $BaseName -Number 1
    }
}

# Function to create a file snapshot for change detection
function Get-FileSnapshot {
    param(
        [string]$FolderPath,
        [bool]$UseFileHashing = $true,
        [bool]$ValidateFilenameFormat = $true
    )
    
    Write-Log "Creating file snapshot for: $FolderPath" "DEBUG"
    
    $snapshot = @{
        Files = @{}
        LastCheck = Get-Date
    }
    
    try {
        if (-not (Test-Path $FolderPath)) {
            Write-Log "Folder does not exist: $FolderPath" "ERROR"
            return $snapshot
        }
        
        $csvFiles = Get-ChildItem -Path $FolderPath -Filter "*.csv" -File
        Write-Log "Found $($csvFiles.Count) CSV files" "DEBUG"
        
        foreach ($file in $csvFiles) {
            Write-Log "Processing file: $($file.Name)" "DEBUG"
            
            # Skip files that don't match the expected format if validation is enabled
            if (-not (Test-FilenameFormat -FileName $file.Name -ValidateFormat $ValidateFilenameFormat)) {
                Write-Log "Skipping file with invalid format: $($file.Name)" "WARNING"
                continue
            }
            
            $fileHash = ""
            if ($UseFileHashing) {
                try {
                    $fileHash = (Get-FileHash -Path $file.FullName -Algorithm MD5).Hash
                } catch {
                    Write-Log "Could not calculate hash for $($file.Name): $($_.Exception.Message)" "WARNING"
                    $fileHash = ""
                }
            }
            
            $snapshot.Files[$file.Name] = @{
                LastWriteTime = $file.LastWriteTime
                Size = $file.Length
                Hash = $fileHash
                FullPath = $file.FullName
            }
        }
        
        Write-Log "Snapshot complete. Total files: $($snapshot.Files.Count)" "DEBUG"
        return $snapshot
    }
    catch {
        Write-Log "Exception in Get-FileSnapshot: $($_.Exception.Message)" "ERROR"
        return $snapshot
    }
}

# Function to compare two file snapshots
function Compare-FileSnapshots {
    param(
        $OldSnapshot,
        $NewSnapshot,
        [bool]$ValidateFilenameFormat = $true
    )
    
    Write-Log "Comparing file snapshots" "DEBUG"
    
    $changes = @{
        NewFiles = @()
        ModifiedFiles = @()
        DeletedFiles = @()
        Details = @()
    }
    
    # Check for new files
    foreach ($fileName in $NewSnapshot.Files.Keys) {
        if (-not $OldSnapshot.Files.ContainsKey($fileName)) {
            # Additional validation: check filename format
            if (Test-FilenameFormat -FileName $fileName -ValidateFormat $ValidateFilenameFormat) {
                $changes.NewFiles += $fileName
                $changes.Details += "NEW: $fileName"
            }
        }
    }
    
    # Check for modified or deleted files
    foreach ($fileName in $OldSnapshot.Files.Keys) {
        if ($NewSnapshot.Files.ContainsKey($fileName)) {
            $oldFile = $OldSnapshot.Files[$fileName]
            $newFile = $NewSnapshot.Files[$fileName]
            
            # Check if file was modified
            if ($oldFile.Size -ne $newFile.Size -or $oldFile.LastWriteTime -ne $newFile.LastWriteTime -or 
                ($oldFile.Hash -and $newFile.Hash -and $oldFile.Hash -ne $newFile.Hash)) {
                if (Test-FilenameFormat -FileName $fileName -ValidateFormat $ValidateFilenameFormat) {
                    $changes.ModifiedFiles += $fileName
                    $changes.Details += "MODIFIED: $fileName"
                }
            }
        } else {
            # File was deleted
            $changes.DeletedFiles += $fileName
            $changes.Details += "DELETED: $fileName"
        }
    }
    
    Write-Log "Changes detected - New: $($changes.NewFiles.Count), Modified: $($changes.ModifiedFiles.Count), Deleted: $($changes.DeletedFiles.Count)" "DEBUG"
    return $changes
}

# Function to wait for file stability
function Wait-ForFileStability {
    param(
        [System.IO.FileInfo[]]$CsvFiles,
        [int]$WaitTime = 2000,
        [int]$MaxRetries = 3,
        [bool]$ValidateFilenameFormat = $true
    )
    
    if ($WaitTime -le 0) { return $true }
    
    Write-Log "Waiting ${WaitTime}ms for files to stabilize..." "INFO"
    Start-Sleep -Milliseconds $WaitTime
    
    # Verify files are not locked
    foreach ($file in $CsvFiles) {
        # Skip files that don't match the expected format
        if (-not (Test-FilenameFormat -FileName $file.Name -ValidateFormat $ValidateFilenameFormat)) {
            Write-Log "Skipping stability check for invalid filename: $($file.Name)" "WARNING"
            continue
        }
        
        $retryCount = 0
        $isStable = $false
        
        while ($retryCount -lt $MaxRetries -and -not $isStable) {
            try {
                # Try to open file exclusively to check if it's being written
                $stream = [System.IO.File]::Open($file.FullName, 'Open', 'Read', 'None')
                $stream.Close()
                $isStable = $true
            } catch {
                $retryCount++
                Write-Log "File $($file.Name) appears to be in use, retry $retryCount/$MaxRetries" "WARNING"
                Start-Sleep -Milliseconds 500
            }
        }
        
        if (-not $isStable) {
            Write-Log "Warning: File $($file.Name) may still be in use after $MaxRetries retries" "WARNING"
        }
    }
    
    return $true
}

# Function to merge column schemas
function Merge-ColumnSchemas {
    param(
        [string[]]$ExistingColumns = @(),
        [string[]]$NewColumns = @(),
        [bool]$IncludeTimestamp = $true
    )
    
    $allColumns = [System.Collections.Generic.List[string]]::new()
    
    # Add timestamp column first if enabled
    if ($IncludeTimestamp) {
        $allColumns.Add("Timestamp")
    }
    
    # Add existing columns (excluding system properties)
    foreach ($columnName in $ExistingColumns) {
        if ($columnName -notmatch '^(PSObject|PSTypeNames|NullData)' -and 
            $columnName -ne "Timestamp" -and
            -not $allColumns.Contains($columnName)) {
            $allColumns.Add($columnName)
        }
    }
    
    # Add new columns
    foreach ($columnName in $NewColumns) {
        if ($columnName -notmatch '^(PSObject|PSTypeNames|NullData)' -and
            -not $allColumns.Contains($columnName)) {
            $allColumns.Add($columnName)
        }
    }
    
    return $allColumns.ToArray()
}

# Function to create a unified row with all columns
function New-UnifiedRow {
    param(
        [PSCustomObject]$SourceRow,
        [string[]]$UnifiedSchema,
        [string]$TimestampValue = $null
    )
    
    $unifiedRow = [ordered]@{}
    
    # Initialize all columns with empty values
    foreach ($column in $UnifiedSchema) {
        $unifiedRow[$column] = ""
    }
    
    # Fill in actual values from source row (exclude system properties)
    if ($SourceRow) {
        $SourceRow.PSObject.Properties | ForEach-Object {
            if ($_.Name -notmatch '^(PSObject|PSTypeNames|NullData)' -and 
                $UnifiedSchema -contains $_.Name) {
                $unifiedRow[$_.Name] = $_.Value
            }
        }
    }
    
    # Add timestamp if provided
    if ($TimestampValue -and $UnifiedSchema -contains "Timestamp") {
        $unifiedRow["Timestamp"] = $TimestampValue
    }
    
    return [PSCustomObject]$unifiedRow
}
