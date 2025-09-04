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
    
    return @($allColumns)
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

# Function to read just the header from existing master CSV (memory efficient)
function Get-MasterFileSchema {
    param(
        [string]$MasterFilePath
    )
    
    if (-not (Test-Path $MasterFilePath)) {
        return @()
    }
    
    try {
        # Read only the first line (header) to minimize memory usage
        $headerLine = Get-Content -Path $MasterFilePath -First 1
        if ([string]::IsNullOrWhiteSpace($headerLine)) {
            return @()
        }
        
        # Parse CSV header
        $columnNames = $headerLine -split ',' | ForEach-Object { $_.Trim('"') }
        Write-Log "Master file schema detected: $($columnNames -join ', ')" "DEBUG"
        return $columnNames
    }
    catch {
        Write-Log "Error reading master file schema: $($_.Exception.Message)" "WARNING"
        return @()
    }
}

# Function to get row count from master file without loading it
function Get-MasterFileRowCount {
    param(
        [string]$MasterFilePath
    )
    
    if (-not (Test-Path $MasterFilePath)) {
        return 0
    }
    
    try {
        # Count lines efficiently without loading into memory
        $lineCount = (Get-Content -Path $MasterFilePath | Measure-Object -Line).Lines
        # Subtract 1 for header row
        $rowCount = [Math]::Max(0, $lineCount - 1)
        Write-Log "Master file contains $rowCount data rows" "DEBUG"
        return $rowCount
    }
    catch {
        Write-Log "Error counting master file rows: $($_.Exception.Message)" "WARNING"
        return 0
    }
}

# Function to append new data directly to master file (memory efficient)
function Append-ToMasterFile {
    param(
        [string]$MasterFilePath,
        [PSCustomObject[]]$NewData,
        [string[]]$UnifiedSchema,
        [bool]$CreateNewFile = $false
    )
    
    if ($NewData.Count -eq 0) {
        return $true
    }
    
    try {
        if ($CreateNewFile) {
            # Create new file with header
            $headerLine = $UnifiedSchema -join ','
            $headerLine | Out-File -FilePath $MasterFilePath -Encoding UTF8
            Write-Log "Created new master file with schema: $($UnifiedSchema -join ', ')" "INFO"
        }
        
        # Convert data to CSV lines and append
        $csvLines = @()
        foreach ($row in $NewData) {
            $values = @()
            foreach ($column in $UnifiedSchema) {
                $value = if ($row.$column) { $row.$column } else { "" }
                # Escape commas and quotes in CSV values
                if ($value -match '[",\r\n]') {
                    $value = '"' + $value.Replace('"', '""') + '"'
                }
                $values += $value
            }
            $csvLines += $values -join ','
        }
        
        # Append to file in one operation
        $csvLines | Add-Content -Path $MasterFilePath -Encoding UTF8
        Write-Log "Appended $($NewData.Count) rows to master file" "INFO"
        return $true
    }
    catch {
        Write-Log "Error appending to master file: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Function to remove rows from master file by timestamp (for modified files)
function Remove-RowsFromMasterFile {
    param(
        [string]$MasterFilePath,
        [string[]]$TimestampsToRemove,
        [string]$TempDirectory = $env:TEMP
    )
    
    if ($TimestampsToRemove.Count -eq 0) {
        return $true
    }
    
    if (-not (Test-Path $MasterFilePath)) {
        return $true
    }
    
    try {
        Write-Log "Removing rows for modified files: $($TimestampsToRemove -join ', ')" "INFO"
        
        # Create temporary file for filtered content
        $tempFile = Join-Path $TempDirectory "master_temp_$(Get-Random).csv"
        $removedCount = 0
        $keptCount = 0
        
        # Process file line by line (memory efficient)
        $headerWritten = $false
        Get-Content -Path $MasterFilePath | ForEach-Object {
            $line = $_
            
            if (-not $headerWritten) {
                # Always keep header
                $line | Add-Content -Path $tempFile -Encoding UTF8
                $headerWritten = $true
            }
            else {
                # Check if this row should be removed
                $shouldRemove = $false
                foreach ($timestamp in $TimestampsToRemove) {
                    if ($line -like "*$timestamp*") {
                        $shouldRemove = $true
                        $removedCount++
                        break
                    }
                }
                
                if (-not $shouldRemove) {
                    $line | Add-Content -Path $tempFile -Encoding UTF8
                    $keptCount++
                }
            }
        }
        
        # Replace original with filtered file
        Move-Item -Path $tempFile -Destination $MasterFilePath -Force
        Write-Log "Removed $removedCount rows, kept $keptCount rows from master file" "INFO"
        return $true
    }
    catch {
        Write-Log "Error removing rows from master file: $($_.Exception.Message)" "ERROR"
        # Clean up temp file if it exists
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
        return $false
    }
}

# Function to remove duplicate rows from data array (preserves first occurrence)
function Remove-DuplicateRows {
    param(
        [PSCustomObject[]]$Data,
        [string[]]$ExcludeColumns = @()
    )
    
    if (-not $Data -or $Data.Count -eq 0) {
        return @()
    }
    
    try {
        Write-Log "Removing duplicates from $($Data.Count) rows, excluding columns: $($ExcludeColumns -join ', ')" "DEBUG"
        
        # Use ArrayList for better performance than array growth
        $uniqueRows = [System.Collections.ArrayList]::new()
        $seenRows = [System.Collections.Generic.HashSet[string]]::new()
        
        foreach ($row in $Data) {
            # Create a signature for this row (excluding specified columns)
            $signature = ""
            $row.PSObject.Properties | Where-Object { 
                $_.Name -notin $ExcludeColumns -and 
                $_.Name -notmatch '^(PSObject|PSTypeNames|NullData)' 
            } | Sort-Object Name | ForEach-Object {
                $signature += "$($_.Name)=$($_.Value);"
            }
            
            # Only add if we haven't seen this signature before
            if ($seenRows.Add($signature)) {
                [void]$uniqueRows.Add($row)
            }
        }
        
        Write-Log "Removed $($Data.Count - $uniqueRows.Count) duplicate rows, $($uniqueRows.Count) unique rows remain" "DEBUG"
        return [array]$uniqueRows
    }
    catch {
        Write-Log "Error removing duplicate rows: $($_.Exception.Message)" "ERROR"
        return $Data  # Return original data if deduplication fails
    }
}

# Function to get processed filenames from master file
function Get-ProcessedFilenames {
    param(
        [string]$MasterFilePath
    )
    
    try {
        if (-not (Test-Path $MasterFilePath)) {
            Write-Log "Master file does not exist: $MasterFilePath" "DEBUG"
            return @()
        }
        
        # Use HashSet for O(1) lookup and add operations instead of O(n) array operations
        $processedFilesSet = [System.Collections.Generic.HashSet[string]]::new()
        $reader = [System.IO.StreamReader]::new($MasterFilePath)
        
        try {
            # Skip header line
            $header = $reader.ReadLine()
            if ($null -eq $header) {
                Write-Log "Master file is empty: $MasterFilePath" "DEBUG"
                return @()
            }
            
            # Check if Timestamp column exists (should be first column)
            $columns = $header -split ','
            if ($columns[0] -ne "Timestamp") {
                Write-Log "Master file does not have Timestamp as first column: $MasterFilePath" "WARNING"
                return @()
            }
            
            # Read each line and extract the filename from Timestamp column
            while ($null -ne ($line = $reader.ReadLine())) {
                if ($line.Trim() -ne "") {
                    $fields = $line -split ','
                    if ($fields.Count -gt 0 -and $fields[0].Trim() -ne "") {
                        $filename = $fields[0].Trim()
                        if ($filename -notlike "*.csv") {
                            $filename += ".csv"
                        }
                        # HashSet.Add() automatically handles duplicates efficiently
                        [void]$processedFilesSet.Add($filename)
                    }
                }
            }
        }
        finally {
            $reader.Close()
        }
        
        # Convert HashSet to array for return compatibility
        $processedFiles = [string[]]$processedFilesSet
        Write-Log "Found $($processedFiles.Count) unique processed files in master file" "DEBUG"
        return $processedFiles
    }
    catch {
        Write-Log "Error reading processed filenames from master file: $($_.Exception.Message)" "ERROR"
        return @()
    }
}
