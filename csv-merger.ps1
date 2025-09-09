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

    Write-Host "Found $($csvFiles.Count) CSV file(s) to process" -ForegroundColor Green

    # Prepare output file path
    $outputPath = Join-Path $OutputFolder $MasterFileName

    # Open output file for writing (overwrites existing file automatically)
    try {
        $writer = [System.IO.StreamWriter]::new($outputPath, $false, [System.Text.Encoding]::UTF8)
        Write-Host "Created/overwriting master file: $outputPath" -ForegroundColor Yellow
    }
    catch {
        Write-Host "Error: Cannot create output file: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "This may be because the file is open in another application." -ForegroundColor Yellow
        return $false
    }

    # Process each CSV file
    $totalRows = 0
    $fileCount = 0
    $headerWritten = $false

    try {
        foreach ($file in $csvFiles) {
            $fileCount++
            $isFirstFile = ($fileCount -eq 1)
            
            Write-Host "`nProcessing file $fileCount of $($csvFiles.Count):" -ForegroundColor Blue
            
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
    Write-Host "Files processed: $fileCount" -ForegroundColor White
    Write-Host "Total data rows merged: $totalRows" -ForegroundColor White
    Write-Host "Master file created: $outputPath" -ForegroundColor White

    # Display master file info
    if (Test-Path $outputPath) {
        $fileSize = [math]::Round((Get-Item $outputPath).Length / 1KB, 2)
        Write-Host "Master file size: $fileSize KB" -ForegroundColor Gray
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
