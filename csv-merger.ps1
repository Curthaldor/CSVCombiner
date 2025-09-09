# CSV File Merger Script
# Reads CSV files from input folder and appends them to a master file in output folder
# Memory-efficient processing using streaming approach
# Supports single execution or repeated execution based on IntervalSeconds setting

param(
    [string]$SettingsFile = ".\settings.ini",
    [string]$MasterFileName = ""
)

# Function to read settings from INI file
function Get-IniSettings {
    param([string]$FilePath)
    
    if (-not (Test-Path $FilePath)) {
        Write-Host "Error: Settings file not found: $FilePath" -ForegroundColor Red
        Write-Host "Please create the settings.ini file with InputFolder and OutputFolder paths." -ForegroundColor Yellow
        exit 1
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
            
            # Check for section headers
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
        Write-Host "Error reading settings file: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Function to validate INI settings and provide defaults
function Test-IniSettings {
    param([hashtable]$Settings, [string]$MasterFileNameParam)
    
    $result = @{
        InputFolder = $Settings["Paths.InputFolder"]
        OutputFolder = $Settings["Paths.OutputFolder"]
        MasterFileName = ""
        IntervalSeconds = 0
        IsValid = $true
        ErrorMessages = @()
    }
    
    # Validate required paths
    if (-not $result.InputFolder) {
        $result.ErrorMessages += "InputFolder not found in settings file under [Paths] section"
        $result.IsValid = $false
    }
    
    if (-not $result.OutputFolder) {
        $result.ErrorMessages += "OutputFolder not found in settings file under [Paths] section"
        $result.IsValid = $false
    }
    
    # Handle master file name (parameter overrides INI setting)
    if ($MasterFileNameParam -ne "") {
        $result.MasterFileName = $MasterFileNameParam
    } else {
        $result.MasterFileName = $Settings["Output.MasterFileName"]
    }
    
    if (-not $result.MasterFileName) {
        $result.ErrorMessages += "MasterFileName not found in settings file under [Output] section and not provided as parameter"
        $result.IsValid = $false
    }
    
    # Handle execution interval with default
    if ($Settings["Execution.IntervalSeconds"]) {
        $result.IntervalSeconds = [int]$Settings["Execution.IntervalSeconds"]
    } else {
        Write-Host "Warning: IntervalSeconds not found in settings file, defaulting to 0 (run once)" -ForegroundColor Yellow
        $result.IntervalSeconds = 0
    }
    
    return $result
}

# Read settings from INI file
$settings = Get-IniSettings -FilePath $SettingsFile

# Validate settings and get processed values
$config = Test-IniSettings -Settings $settings -MasterFileNameParam $MasterFileName

# Check if validation passed
if (-not $config.IsValid) {
    foreach ($error in $config.ErrorMessages) {
        Write-Host "Error: $error" -ForegroundColor Red
    }
    exit 1
}

# Extract validated settings
$InputFolder = $config.InputFolder
$OutputFolder = $config.OutputFolder
$MasterFileName = $config.MasterFileName
$intervalSeconds = $config.IntervalSeconds

# Function to check if folder exists
function Test-FolderExists {
    param([string]$Path, [string]$FolderType)
    if (-not (Test-Path $Path)) {
        Write-Host "Error: $FolderType folder does not exist: $Path" -ForegroundColor Red
        Write-Host "Please create the folder before running the script." -ForegroundColor Yellow
        exit 1
    }
}

# Function to process a single CSV file
function Merge-CsvFile {
    param(
        [string]$FilePath,
        [System.IO.StreamWriter]$Writer,
        [bool]$IsFirstFile
    )
    
    $fileName = [System.IO.Path]::GetFileName($FilePath)
    Write-Host "Processing: $fileName" -ForegroundColor Cyan
    
    try {
        # Open input file for reading
        $reader = [System.IO.StreamReader]::new($FilePath)
        $lineCount = 0
        $headerLine = $null
        
        # Read first line (header)
        if (-not $reader.EndOfStream) {
            $headerLine = $reader.ReadLine()
            $lineCount++
            
            # Always write header (from first file only for proper CSV format)
            if ($IsFirstFile) {
                # Add SourceFile as the first column
                $modifiedHeader = "SourceFile,$headerLine"
                $Writer.WriteLine($modifiedHeader)
            }
        }
        
        # Process remaining lines (data)
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                # Add source file name as the first column
                $modifiedLine = "$fileName,$line"
                $Writer.WriteLine($modifiedLine)
                $lineCount++
            }
        }
        
        $reader.Close()
        $dataLines = $lineCount - 1  # Subtract header line
        Write-Host "  Added $dataLines data rows" -ForegroundColor Gray
        
        return $dataLines
    }
    catch {
        Write-Host "  Error processing file: $($_.Exception.Message)" -ForegroundColor Red
        if ($reader) { $reader.Close() }
        return 0
    }
}

# Function to get list of already processed files from output file
function Get-ProcessedFiles {
    param(
        [string]$OutputPath
    )
    
    $processedFiles = @()
    
    if (-not (Test-Path $OutputPath)) {
        Write-Host "No existing output file found - will process all input files" -ForegroundColor Yellow
        return $processedFiles
    }
    
    try {
        Write-Host "Checking existing output file for previously processed files..." -ForegroundColor Cyan
        $reader = [System.IO.StreamReader]::new($OutputPath)
        
        # Skip header line
        if (-not $reader.EndOfStream) {
            $reader.ReadLine() | Out-Null
        }
        
        # Read through file and collect unique source files
        $uniqueFiles = @{}
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                # Extract first column (source file name)
                $firstCommaIndex = $line.IndexOf(',')
                if ($firstCommaIndex -gt 0) {
                    $sourceFile = $line.Substring(0, $firstCommaIndex)
                    $uniqueFiles[$sourceFile] = $true
                }
            }
        }
        
        $reader.Close()
        $processedFiles = $uniqueFiles.Keys
        
        if ($processedFiles.Count -gt 0) {
            if ($processedFiles.Count -le 5) {
                Write-Host "Found $($processedFiles.Count) previously processed file(s):" -ForegroundColor Gray
                foreach ($file in $processedFiles | Sort-Object) {
                    Write-Host "  - $file" -ForegroundColor Gray
                }
            } else {
                Write-Host "Found $($processedFiles.Count) previously processed files" -ForegroundColor Gray
            }
        } else {
            Write-Host "Output file exists but contains no data rows" -ForegroundColor Yellow
        }
        
        return $processedFiles
    }
    catch {
        Write-Host "Warning: Could not read existing output file: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Will process all input files" -ForegroundColor Yellow
        if ($reader) { $reader.Close() }
        return @()
    }
}

# Function to perform the CSV merge operation
function Invoke-CsvMerge {
    param(
        [string]$InputFolder,
        [string]$OutputFolder,
        [string]$MasterFileName
    )
    
    # Check that required folders exist
    Test-FolderExists -Path $InputFolder -FolderType "Input"
    Test-FolderExists -Path $OutputFolder -FolderType "Output"

    # Get all CSV files from input folder
    $csvFiles = Get-ChildItem -Path $InputFolder -Filter "*.csv" | Sort-Object Name

    if ($csvFiles.Count -eq 0) {
        Write-Host "No CSV files found in input folder: $InputFolder" -ForegroundColor Red
        return $false
    }

    Write-Host "Found $($csvFiles.Count) CSV file(s) in input folder" -ForegroundColor Green
    
    # Prepare output file path
    $outputPath = Join-Path $OutputFolder $MasterFileName
    
    # Check for previously processed files
    $processedFiles = Get-ProcessedFiles -OutputPath $outputPath
    
    # Filter out already processed files
    $newFiles = @()
    foreach ($file in $csvFiles) {
        if ($file.Name -notin $processedFiles) {
            $newFiles += $file
        }
    }
    
    if ($newFiles.Count -eq 0) {
        Write-Host "No new files to process - all input files have already been merged" -ForegroundColor Yellow
        return $true
    }
    
    if ($newFiles.Count -le 5) {
        Write-Host "Found $($newFiles.Count) new file(s) to process:" -ForegroundColor Green
        foreach ($file in $newFiles) {
            Write-Host "  - $($file.Name)" -ForegroundColor Green
        }
    } else {
        Write-Host "Found $($newFiles.Count) new files to process" -ForegroundColor Green
    }

    # Determine if we need to write header (only if output file doesn't exist)
    $outputExists = Test-Path $outputPath
    $writeHeader = -not $outputExists
    
    # Open output file for writing (append mode if file exists, create if not)
    try {
        $writer = [System.IO.StreamWriter]::new($outputPath, $outputExists, [System.Text.Encoding]::UTF8)
        if ($outputExists) {
            Write-Host "Appending to existing master file: $outputPath" -ForegroundColor Yellow
        } else {
            Write-Host "Creating new master file: $outputPath" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "Error: Cannot create/open output file: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "This may be because the file is open in another application." -ForegroundColor Yellow
        return $false
    }

    # Process each new CSV file
    $totalRows = 0
    $fileCount = 0

    try {
        foreach ($file in $newFiles) {
            $fileCount++
            $isFirstFile = $writeHeader -and ($fileCount -eq 1)
            
            Write-Host "`nProcessing file $fileCount of $($newFiles.Count):" -ForegroundColor Blue
            
            $rowsAdded = Merge-CsvFile -FilePath $file.FullName -Writer $writer -IsFirstFile $isFirstFile
            $totalRows += $rowsAdded
        }
    }
    finally {
        # Always close the writer
        if ($writer) {
            $writer.Close()
            $writer.Dispose()
        }
    }

    # Summary
    Write-Host "`n--- Processing Complete ---" -ForegroundColor Green
    Write-Host "New files processed: $fileCount" -ForegroundColor White
    Write-Host "Total data rows added: $totalRows" -ForegroundColor White
    Write-Host "Master file: $outputPath" -ForegroundColor White

    # Display master file info
    if (Test-Path $outputPath) {
        $fileSize = [math]::Round((Get-Item $outputPath).Length / 1KB, 2)
        Write-Host "Master file size: $fileSize KB" -ForegroundColor Gray
        
        # Show total processed files count
        $allProcessedFiles = Get-ProcessedFiles -OutputPath $outputPath
        Write-Host "Total files in master file: $($allProcessedFiles.Count)" -ForegroundColor Gray
    }
    
    return $true
}

# Main execution
Write-Host "CSV File Merger Starting..." -ForegroundColor Green
Write-Host "Settings File: $SettingsFile" -ForegroundColor Yellow
Write-Host "Input Folder: $InputFolder" -ForegroundColor Yellow
Write-Host "Output Folder: $OutputFolder" -ForegroundColor Yellow
Write-Host "Master File: $MasterFileName" -ForegroundColor Yellow
Write-Host "Execution Interval: $intervalSeconds seconds" -ForegroundColor Yellow

if ($intervalSeconds -eq 0) {
    Write-Host "`nRunning CSV merge once..." -ForegroundColor Green
    $success = Invoke-CsvMerge -InputFolder $InputFolder -OutputFolder $OutputFolder -MasterFileName $MasterFileName
    if ($success) {
        Write-Host "`nSingle execution completed successfully." -ForegroundColor Green
    } else {
        Write-Host "`nExecution failed." -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "`nStarting continuous execution mode (every $intervalSeconds seconds)" -ForegroundColor Green
    Write-Host "Press Ctrl+C to stop..." -ForegroundColor Yellow
    
    try {
        $counter = 1
        while ($true) {
            Write-Host "`n=== Execution #$counter at $(Get-Date) ===" -ForegroundColor Blue
            
            $success = Invoke-CsvMerge -InputFolder $InputFolder -OutputFolder $OutputFolder -MasterFileName $MasterFileName
            
            if ($success) {
                Write-Host "Execution #$counter completed successfully." -ForegroundColor Green
            } else {
                Write-Host "Execution #$counter failed, will retry after interval..." -ForegroundColor Red
            }
            
            Write-Host "`nWaiting $intervalSeconds seconds before next execution..." -ForegroundColor Gray
            Start-Sleep -Seconds $intervalSeconds
            $counter++
        }
    }
    catch {
        Write-Host "`n`nContinuous execution stopped." -ForegroundColor Yellow
    }
}
