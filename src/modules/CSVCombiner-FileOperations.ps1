# ==============================================================================
# CSV Combiner File Operations Module v2.4
# ==============================================================================
# Purpose: File system operations, monitoring, and validation functions
# ==============================================================================

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
    
    $changes = [PSCustomObject]@{
        NewFiles = @()
        ModifiedFiles = @()
        DeletedFiles = @()
        Details = @()
        HasChanges = $false
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
    
    # Set HasChanges flag if any changes were detected
    $changes.HasChanges = ($changes.NewFiles.Count -gt 0 -or $changes.ModifiedFiles.Count -gt 0 -or $changes.DeletedFiles.Count -gt 0)
    
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
