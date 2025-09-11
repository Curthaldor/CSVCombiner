# CSV Utility Functions
# Collection of reusable functions for CSV file operations

<#
.SYNOPSIS
    Reads a CSV file and returns its data as an array of objects.

.DESCRIPTION
    This function reads a CSV file and returns the data as an array of custom objects.
    The first row is always treated as column headers and used as property names for the returned objects.

.PARAMETER FilePath
    The full path to the CSV file to read.

.OUTPUTS
    Array of PSCustomObject with properties named after header columns

.EXAMPLE
    # Read CSV with headers
    $data = Read-CsvData -FilePath "C:\data\sample.csv"
    foreach ($row in $data) {
        Write-Host "Name: $($row.Name), Age: $($row.Age)"
    }

.EXAMPLE
    # Access specific data
    $data = Read-CsvData -FilePath "C:\data\sample.csv"
    $firstRow = $data[0]
    Write-Host "First person's name: $($firstRow.Name)"
#>
function Read-CsvData {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    
    # Return empty array if file doesn't exist
    if (-not (Test-Path $FilePath)) {
        return @()
    }
    
    try {
        $reader = [System.IO.StreamReader]::new($FilePath)
        $result = @()
        $headers = @()
        $isFirstLine = $true
        
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            
            # Skip empty lines
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            
            # Split the line into columns
            $columns = $line -split ','
            
            # Handle header row (first non-empty line)
            if ($isFirstLine) {
                # Store headers for creating objects, handling duplicates
                $headers = @()
                $headerCounts = @{}
                
                foreach ($column in $columns) {
                    $cleanHeader = $column.Trim()
                    
                    # Handle duplicate column names by adding a suffix
                    if ($headerCounts.ContainsKey($cleanHeader)) {
                        $headerCounts[$cleanHeader]++
                        $uniqueHeader = "$cleanHeader$($headerCounts[$cleanHeader])"
                    } else {
                        $headerCounts[$cleanHeader] = 0
                        $uniqueHeader = $cleanHeader
                    }
                    
                    $headers += $uniqueHeader
                }
                
                $isFirstLine = $false
                continue
            }
            
            # Process data rows - create custom object with properties named after headers
            $rowObject = New-Object PSCustomObject
            
            for ($i = 0; $i -lt $headers.Length; $i++) {
                $value = if ($i -lt $columns.Length) { $columns[$i].Trim() } else { "" }
                $rowObject | Add-Member -NotePropertyName $headers[$i] -NotePropertyValue $value
            }
            
            $result += $rowObject
        }
        
        $reader.Close()
        return $result
    }
    catch {
        if ($reader) { 
            $reader.Close() 
        }
        throw "Error reading CSV file: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Filters CSV data to return rows that match a regex pattern in a specified column.

.DESCRIPTION
    This function takes an array of CSV objects (as returned by Read-CsvData) and filters
    them to return only rows where the specified column matches the provided regex pattern.

.PARAMETER CsvData
    Array of PSCustomObject representing CSV data (typically from Read-CsvData function).

.PARAMETER ColumnName
    The name of the column to search in. Must match a property name from the CSV headers.

.PARAMETER Pattern
    The regex pattern to match against the specified column.

.OUTPUTS
    Array of PSCustomObject containing only the rows that match the regex pattern.

.EXAMPLE
    # Get all rows with a specific filename in SourceFile column (exact match)
    $data = Read-CsvData -FilePath "C:\data\master.csv"
    $filtered = Get-CsvRowsByColumn -CsvData $data -ColumnName "SourceFile" -Pattern "^20240915123045\.csv$"

.EXAMPLE
    # Get all rows from September 15, 2024 (any time)
    $data = Read-CsvData -FilePath "C:\data\master.csv"
    $filtered = Get-CsvRowsByColumn -CsvData $data -ColumnName "SourceFile" -Pattern "^20240915\d{6}\.csv$"

.EXAMPLE
    # Get all rows where Name contains "John" (case-insensitive)
    $data = Read-CsvData -FilePath "C:\data\people.csv"
    $filtered = Get-CsvRowsByColumn -CsvData $data -ColumnName "Name" -Pattern "(?i)john"

.EXAMPLE
    # Get all rows with Pass or Fail in PassFlag column
    $data = Read-CsvData -FilePath "C:\data\results.csv"
    $results = Get-CsvRowsByColumn -CsvData $data -ColumnName "PassFlag" -Pattern "^(Pass|Fail)$"
#>
function Get-CsvRowsByColumn {
    param(
        [Parameter(Mandatory=$true)]
        [array]$CsvData,
        
        [Parameter(Mandatory=$true)]
        [string]$ColumnName,
        
        [Parameter(Mandatory=$true)]
        [string]$Pattern
    )
    
    # Validate inputs
    if ($CsvData.Count -eq 0) {
        return @()
    }
    
    # Check if the column exists in the data
    $firstRow = $CsvData[0]
    if (-not ($firstRow.PSObject.Properties.Name -contains $ColumnName)) {
        throw "Column '$ColumnName' not found in CSV data. Available columns: $($firstRow.PSObject.Properties.Name -join ', ')"
    }
    
    # Filter the data
    $result = @()
    
    foreach ($row in $CsvData) {
        $columnValue = $row.$ColumnName
        
        # Handle null/empty values
        if ([string]::IsNullOrEmpty($columnValue)) {
            # Only match if pattern matches empty string
            if ("" -match $Pattern) {
                $result += $row
            }
            continue
        }
        
        # Perform regex match
        if ($columnValue -match $Pattern) {
            $result += $row
        }
    }
    
    return $result
}

<#
.SYNOPSIS
    Removes duplicate rows from CSV data, keeping the last occurrence of each duplicate.

.DESCRIPTION
    This function removes duplicate rows based on specified columns, keeping the row that appears
    latest in the dataset (lower index). This is useful when newer data should override older data.
    You can specify one or more columns to use for duplicate detection.

.PARAMETER CsvData
    Array of PSCustomObject representing CSV data (typically from Read-CsvData function).

.PARAMETER KeyColumns
    Array of column names to use for duplicate detection. Rows with identical values
    in ALL specified columns are considered duplicates.

.OUTPUTS
    Array of PSCustomObject with duplicates removed, keeping the last occurrence of each duplicate.

.EXAMPLE
    # Remove duplicates based on single column, keeping latest
    $data = Read-CsvData -FilePath "C:\data\results.csv"
    $unique = Remove-CsvDuplicates -CsvData $data -KeyColumns @("TestID")

.EXAMPLE
    # Remove duplicates based on multiple columns
    $data = Read-CsvData -FilePath "C:\data\results.csv"
    $unique = Remove-CsvDuplicates -CsvData $data -KeyColumns @("TestID", "TestCase")

.EXAMPLE
    # Remove duplicates based on filename and test name (keep latest results)
    $data = Read-CsvData -FilePath "C:\data\master.csv"
    $unique = Remove-CsvDuplicates -CsvData $data -KeyColumns @("SourceFile", "TestName")
#>
function Remove-CsvDuplicates {
    param(
        [Parameter(Mandatory=$true)]
        [array]$CsvData,
        
        [Parameter(Mandatory=$true)]
        [string[]]$KeyColumns
    )
    
    # Validate inputs
    if ($CsvData.Count -eq 0) {
        return @()
    }
    
    # Check if all specified columns exist in the data
    $firstRow = $CsvData[0]
    $availableColumns = $firstRow.PSObject.Properties.Name
    
    foreach ($column in $KeyColumns) {
        if ($column -notin $availableColumns) {
            throw "Column '$column' not found in CSV data. Available columns: $($availableColumns -join ', ')"
        }
    }
    
    # Use a hashtable to track seen combinations (key = combined values, value = row index)
    $seenKeys = @{}
    $result = @()
    
    # Process rows from last to first (reverse order) to prioritize later occurrences
    for ($i = $CsvData.Count - 1; $i -ge 0; $i--) {
        $row = $CsvData[$i]
        
        # Create a composite key from the specified columns
        $keyParts = @()
        foreach ($column in $KeyColumns) {
            $value = $row.$column
            # Handle null/empty values in key
            $keyParts += if ([string]::IsNullOrEmpty($value)) { "NULL" } else { $value }
        }
        $compositeKey = $keyParts -join "|"
        
        # If we haven't seen this combination before, keep it
        if (-not $seenKeys.ContainsKey($compositeKey)) {
            $seenKeys[$compositeKey] = $i
            # Add to front of result array to maintain relative order
            $result = @($row) + $result
        }
        # If we have seen it before, the current row is earlier, so skip it
    }
    
    return $result
}

<#
.SYNOPSIS
    Writes CSV data objects to a file.

.DESCRIPTION
    This function takes an array of CSV objects (PSCustomObjects) and writes them to a CSV file.
    The column headers are derived from the property names of the first object.
    The file can be created new or appended to existing files.

.PARAMETER CsvData
    Array of PSCustomObject representing CSV data (typically from Read-CsvData function).

.PARAMETER FilePath
    The full path where the CSV file should be written.

.PARAMETER Append
    If true, appends to existing file. If false (default), overwrites existing file.

.OUTPUTS
    Returns hashtable with Success (boolean) and Message (string) properties.
    Success = $true if file written successfully, $false if failed.
    Message contains error details if Success = $false.

.EXAMPLE
    # Write CSV data to new file
    $data = Read-CsvData -FilePath "input.csv"
    $result = Write-CsvData -CsvData $data -FilePath "output.csv"
    if (-not $result.Success) {
        Write-Host "Failed to write file: $($result.Message)" -ForegroundColor Red
    }

.EXAMPLE
    # Append CSV data to existing file
    $newData = Read-CsvData -FilePath "new.csv"
    $result = Write-CsvData -CsvData $newData -FilePath "master.csv" -Append $true
    if ($result.Success) {
        Write-Host "Data appended successfully" -ForegroundColor Green
    }

.EXAMPLE
    # Filter and write with error handling
    $data = Read-CsvData -FilePath "input.csv"
    $filtered = Get-CsvRowsByColumn -CsvData $data -ColumnName "Status" -Pattern "^Pass$"
    $result = Write-CsvData -CsvData $filtered -FilePath "passed_only.csv"
    Write-Host $result.Message
#>
function Write-CsvData {
    param(
        [Parameter(Mandatory=$true)]
        [array]$CsvData,
        
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        
        [Parameter(Mandatory=$false)]
        [bool]$Append = $false
    )
    
    # Validate inputs
    if ($CsvData.Count -eq 0) {
        return @{
            Success = $false
            Message = "No data provided to write"
        }
    }
    
    # Ensure output directory exists
    $outputDir = [System.IO.Path]::GetDirectoryName($FilePath)
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    
    try {
        # Determine if we need to write headers
        $fileExists = Test-Path $FilePath
        $writeHeaders = -not ($Append -and $fileExists)
        
        # Create StreamWriter (append mode if specified and file exists)
        if ($Append -and $fileExists) {
            $writer = [System.IO.StreamWriter]::new($FilePath, $true, [System.Text.Encoding]::UTF8)
        } else {
            $writer = [System.IO.StreamWriter]::new($FilePath, $false, [System.Text.Encoding]::UTF8)
        }
        
        # Get column names from first object
        $firstRow = $CsvData[0]
        $columnNames = $firstRow.PSObject.Properties.Name
        
        # Write headers if needed
        if ($writeHeaders) {
            $headerLine = $columnNames -join ','
            $writer.WriteLine($headerLine)
        }
        
        # Write data rows
        foreach ($row in $CsvData) {
            $values = @()
            foreach ($column in $columnNames) {
                $value = $row.$column
                # Handle null/empty values and escape commas if needed
                if ([string]::IsNullOrEmpty($value)) {
                    $values += ""
                } elseif ($value.ToString().Contains(',') -or $value.ToString().Contains('"')) {
                    # Escape quotes and wrap in quotes if contains comma or quote
                    $escapedValue = $value.ToString() -replace '"', '""'
                    $values += "`"$escapedValue`""
                } else {
                    $values += $value.ToString()
                }
            }
            
            $dataLine = $values -join ','
            $writer.WriteLine($dataLine)
        }
        
        $writer.Close()
        $writer.Dispose()
        
        return @{
            Success = $true
            Message = "CSV file written successfully: $FilePath"
        }
    }
    catch {
        if ($writer) {
            $writer.Close()
            $writer.Dispose()
        }
        
        # Provide user-friendly error messages
        $errorMessage = $_.Exception.Message
        if ($errorMessage -match "being used by another process" -or $errorMessage -match "Access.*denied") {
            return @{
                Success = $false
                Message = "Cannot write to file '$FilePath'. The file may be open in another application (like Excel) or you may not have write permissions. Error: $errorMessage"
            }
        } else {
            return @{
                Success = $false
                Message = "Error writing CSV file '$FilePath': $errorMessage"
            }
        }
    }
}

<#
.SYNOPSIS
    Reads settings from an INI configuration file.

.DESCRIPTION
    This function reads an INI file and returns the settings as a hashtable with section.key format.
    Supports sections, key=value pairs, comments (lines starting with #), and empty lines.

.PARAMETER FilePath
    The full path to the INI file to read.

.OUTPUTS
    Hashtable with keys in "Section.Key" format and their corresponding values.

.EXAMPLE
    # Read INI file
    $settings = Read-IniFile -FilePath "C:\config\settings.ini"
    $inputFolder = $settings["Paths.InputFolder"]
    $outputFolder = $settings["Paths.OutputFolder"]

.EXAMPLE
    # Read with error handling
    try {
        $config = Read-IniFile -FilePath "settings.ini"
        Write-Host "Loaded $($config.Keys.Count) settings"
    } catch {
        Write-Host "Could not read INI file: $($_.Exception.Message)" -ForegroundColor Red
    }
#>
function Read-IniFile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    
    if (-not (Test-Path $FilePath)) {
        throw "INI file not found: $FilePath"
    }
    
    $settings = @{}
    $currentSection = ""
    
    try {
        Get-Content $FilePath | ForEach-Object {
            $line = $_.Trim()
            
            # Skip empty lines and comments
            if ($line -eq "" -or $line.StartsWith("#")) {
                return
            }
            
            # Check for section headers [SectionName]
            if ($line -match '^\[(.+)\]$') {
                $currentSection = $matches[1]
                return
            }
            
            # Parse key=value pairs
            if ($line -match '^(.+?)=(.*)$') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                
                if ($currentSection -ne "") {
                    $fullKey = "$currentSection.$key"
                } else {
                    $fullKey = $key
                }
                
                $settings[$fullKey] = $value
            }
        }
        
        return $settings
    }
    catch {
        throw "Error reading INI file: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Validates INI settings by checking actual file/folder existence and data types.

.DESCRIPTION
    This function validates INI settings by verifying that paths exist, filenames are valid,
    and data types are correct. Command-line parameters override INI values.
    Throws errors for invalid configurations rather than providing defaults.

.PARAMETER Settings
    Hashtable of settings from Read-IniFile function.

.PARAMETER ParameterOverrides
    Hashtable of parameter overrides (e.g., command line parameters that override INI values).

.OUTPUTS
    Hashtable containing the final validated settings with overrides applied.

.EXAMPLE
    # Basic validation
    $settings = Read-IniFile -FilePath "settings.ini"
    $overrides = @{
        "Paths.InputFolder" = $InputFolderParam
        "Output.MasterFileName" = $MasterFileNameParam
    }
    $validatedSettings = Test-IniSettings -Settings $settings -ParameterOverrides $overrides

.EXAMPLE
    # Simple validation without overrides
    $settings = Read-IniFile -FilePath "settings.ini"
    $validatedSettings = Test-IniSettings -Settings $settings
#>
function Test-IniSettings {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Settings,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$ParameterOverrides = @{}
    )
    
    # Create result hashtable with original settings
    $result = @{}
    foreach ($key in $Settings.Keys) {
        $result[$key] = $Settings[$key]
    }
    
    # Apply parameter overrides (command-line args override INI)
    foreach ($override in $ParameterOverrides.GetEnumerator()) {
        if (-not [string]::IsNullOrEmpty($override.Value)) {
            $result[$override.Key] = $override.Value
        }
    }
    
    # Validate paths exist
    $pathSettings = @("Paths.InputFolder", "Paths.OutputFolder", "Paths.SummaryOutputFolder", "Paths.DailyReportFolder")
    foreach ($pathSetting in $pathSettings) {
        if ($result.ContainsKey($pathSetting) -and -not [string]::IsNullOrEmpty($result[$pathSetting])) {
            if (-not (Test-Path $result[$pathSetting])) {
                throw "Path does not exist: $($result[$pathSetting]) (setting: $pathSetting)"
            }
        }
    }
    
    # Validate filenames are valid (not empty and contain valid characters)
    $fileSettings = @("Output.MasterFileName", "Output.SummaryFileName")
    foreach ($fileSetting in $fileSettings) {
        if ($result.ContainsKey($fileSetting) -and -not [string]::IsNullOrEmpty($result[$fileSetting])) {
            $filename = $result[$fileSetting]
            # Check for invalid filename characters
            $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
            foreach ($char in $invalidChars) {
                if ($filename.Contains($char)) {
                    throw "Invalid filename character '$char' in: $filename (setting: $fileSetting)"
                }
            }
        }
    }
    
    # Validate interval is a valid integer
    if ($result.ContainsKey("Execution.IntervalSeconds") -and -not [string]::IsNullOrEmpty($result["Execution.IntervalSeconds"])) {
        $intervalValue = $result["Execution.IntervalSeconds"]
        $intervalInt = 0
        if (-not [int]::TryParse($intervalValue, [ref]$intervalInt)) {
            throw "IntervalSeconds must be a valid integer, got: $intervalValue"
        }
        if ($intervalInt -lt 0) {
            throw "IntervalSeconds must be non-negative, got: $intervalInt"
        }
        # Store as integer for convenience
        $result["Execution.IntervalSeconds"] = $intervalInt
    }
    
    # Validate required settings are present and not empty
    $requiredSettings = @(
        "Paths.InputFolder",
        "Paths.OutputFolder", 
        "Output.MasterFileName"
    )
    
    foreach ($requiredSetting in $requiredSettings) {
        if (-not $result.ContainsKey($requiredSetting) -or [string]::IsNullOrEmpty($result[$requiredSetting])) {
            throw "Required setting '$requiredSetting' is missing or empty. Please check your INI file or provide a command-line override."
        }
    }
    
    return $result
}

<#
.SYNOPSIS
    Efficiently extracts unique values from the first column of a CSV file.

.DESCRIPTION
    This function reads a CSV file and returns only the unique values from the first column.
    It's optimized for scenarios where you only need to know what files have been processed,
    without loading the entire dataset into memory as objects.

.PARAMETER FilePath
    The full path to the CSV file to read.

.OUTPUTS
    Array of strings containing unique values from the first column.

.EXAMPLE
    # Get list of already processed files
    $processedFiles = Get-CsvFirstColumnUnique -FilePath "C:\output\master.csv"
    foreach ($file in $processedFiles) {
        Write-Host "Already processed: $file"
    }

.EXAMPLE
    # Check if specific file was already processed
    $processedFiles = Get-CsvFirstColumnUnique -FilePath "master.csv"
    if ($processedFiles -contains "20240915123045.csv") {
        Write-Host "File already processed, skipping..."
    }
#>
function Get-CsvFirstColumnUnique {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    
    # Return empty array if file doesn't exist (no files processed yet)
    if (-not (Test-Path $FilePath)) {
        return @()
    }
    
    try {
        $reader = [System.IO.StreamReader]::new($FilePath)
        $uniqueValues = [System.Collections.Generic.HashSet[string]]::new()
        $isFirstLine = $true
        
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            
            # Skip empty lines
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            
            # Skip header row (first non-empty line)
            if ($isFirstLine) {
                $isFirstLine = $false
                continue
            }
            
            # Extract first column value
            $firstColumnValue = ""
            if ($line.StartsWith('"')) {
                # Handle quoted values that might contain commas
                $quoteEnd = $line.IndexOf('"', 1)
                if ($quoteEnd -gt 0) {
                    $firstColumnValue = $line.Substring(1, $quoteEnd - 1)
                    # Handle escaped quotes
                    $firstColumnValue = $firstColumnValue -replace '""', '"'
                }
            } else {
                # Simple case - extract up to first comma
                $commaIndex = $line.IndexOf(',')
                if ($commaIndex -gt 0) {
                    $firstColumnValue = $line.Substring(0, $commaIndex).Trim()
                } else {
                    # Single column case
                    $firstColumnValue = $line.Trim()
                }
            }
            
            # Add to HashSet (automatically handles uniqueness)
            if (-not [string]::IsNullOrEmpty($firstColumnValue)) {
                $uniqueValues.Add($firstColumnValue) | Out-Null
            }
        }
        
        $reader.Close()
        
        # Convert HashSet to array for return
        return [string[]]$uniqueValues
    }
    catch {
        if ($reader) { 
            $reader.Close() 
        }
        throw "Error reading CSV file for first column extraction: $($_.Exception.Message)"
    }
}

