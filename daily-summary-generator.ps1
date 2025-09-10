# Daily Summary Generator for CSV Combiner
# Reads the main output file and generates daily summary statistics
# Author: GitHub Copilot
# Version: 1.0

param(
    [string]$ConfigFile = "settings.ini",
    [string]$OutputFile = "",
    [string]$SummaryFile = "",
    [string]$SummaryOutputFolder = "",
    [switch]$Silent
)

# Function to read configuration from INI file
function Read-IniFile {
    param([string]$FilePath)
    
    $config = @{}
    $currentSection = ""
    
    if (-not (Test-Path $FilePath)) {
        Write-ConditionalHost "Configuration file '$FilePath' not found. Using default settings." -ForegroundColor "Yellow" -IsWarning
        return $config
    }
    
    Get-Content $FilePath | ForEach-Object {
        $line = $_.Trim()
        if ($line -match '^\[(.+)\]$') {
            $currentSection = $matches[1]
            $config[$currentSection] = @{}
        }
        elseif ($line -match '^(.+?)=(.*)$' -and $currentSection) {
            $config[$currentSection][$matches[1]] = $matches[2]
        }
    }
    
    return $config
}

# Function to conditionally write to console (respects Silent parameter)
function Write-ConditionalHost {
    param(
        [string]$Message,
        [string]$ForegroundColor = "White",
        [switch]$IsWarning,
        [switch]$IsError
    )
    
    if (-not $Silent) {
        if ($IsError) {
            Write-Host $Message -ForegroundColor "Red"
        } elseif ($IsWarning) {
            Write-Host $Message -ForegroundColor "Yellow"
        } else {
            Write-Host $Message -ForegroundColor $ForegroundColor
        }
    }
}

# Function to extract date from filename (YYYYMMDDHHMMSS.csv -> YYYY-MM-DD)
function Extract-DateFromFileName {
    param([string]$FileName)
    
    # Extract the base filename without path and extension
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    
    # Check if it matches the expected 14-digit pattern
    if ($baseName -match '^(\d{4})(\d{2})(\d{2})\d{6}$') {
        return "$($matches[1])-$($matches[2])-$($matches[3])"
    }
    
    # If it doesn't match, return null to indicate invalid format
    return $null
}

# Function to determine pass/fail status from a row
function Get-PassFailStatus {
    param([string]$PassFlag)
    
    # Normalize the PassFlag value
    $passFlag = $PassFlag.Trim()
    
    if ($passFlag -eq "Passed") {
        return "Pass"
    }
    elseif ([string]::IsNullOrEmpty($passFlag)) {
        return "Fail"
    }
    else {
        return "Fail"  # Any non-"Passed" value is considered a failure
    }
}

# Function to process the output file and generate daily summaries
function Generate-DailySummary {
    param(
        [string]$OutputFilePath,
        [string]$SummaryFilePath
    )
    
    Write-ConditionalHost "Reading output file: $OutputFilePath" -ForegroundColor "Blue"
    
    if (-not (Test-Path $OutputFilePath)) {
        Write-ConditionalHost "Output file '$OutputFilePath' not found." -IsError
        return
    }
    
    # Dictionary to store daily statistics
    # Structure: @{"2025-01-15" = @{Files=@(); Passes=0; Failures=0; TotalRows=0}}
    $dailyStats = @{}
    
    try {
        # Read the CSV file
        $reader = [System.IO.StreamReader]::new($OutputFilePath)
        $headerLine = $reader.ReadLine()
        
        if ([string]::IsNullOrEmpty($headerLine)) {
            Write-ConditionalHost "Output file is empty or has no header." -IsWarning
            $reader.Close()
            return
        }
        
        # Parse header to find column indices
        $headers = $headerLine.Split(',')
        $sourceFileIndex = -1
        $passFlagIndex = -1
        
        for ($i = 0; $i -lt $headers.Length; $i++) {
            if ($headers[$i].Trim() -eq "SourceFile") {
                $sourceFileIndex = $i
            }
            elseif ($headers[$i].Trim() -eq "PassFlag") {
                $passFlagIndex = $i
            }
        }
        
        if ($sourceFileIndex -eq -1) {
            Write-ConditionalHost "SourceFile column not found in output file." -IsError
            $reader.Close()
            return
        }
        
        if ($passFlagIndex -eq -1) {
            Write-ConditionalHost "PassFlag column not found in output file." -IsError
            $reader.Close()
            return
        }
        
        Write-ConditionalHost "Found SourceFile column at index $sourceFileIndex" -ForegroundColor "Green"
        Write-ConditionalHost "Found PassFlag column at index $passFlagIndex" -ForegroundColor "Green"
        
        $rowCount = 0
        
        # Process each data row
        while ($null -ne ($line = $reader.ReadLine())) {
            $rowCount++
            
            # Parse CSV row (simple split - assumes no commas in data)
            $columns = $line.Split(',')
            
            if ($columns.Length -le [Math]::Max($sourceFileIndex, $passFlagIndex)) {
                Write-ConditionalHost "Row $rowCount has insufficient columns, skipping." -IsWarning
                continue
            }
            
            $sourceFile = $columns[$sourceFileIndex].Trim()
            $passFlag = $columns[$passFlagIndex].Trim()
            
            # Extract date from source filename
            $date = Extract-DateFromFileName -FileName $sourceFile
            
            if ($null -eq $date) {
                Write-ConditionalHost "Row ${rowCount}: Could not extract date from filename '$sourceFile', skipping." -IsWarning
                continue
            }
            
            # Initialize daily stats if not exists
            if (-not $dailyStats.ContainsKey($date)) {
                $dailyStats[$date] = @{
                    Files = @{}
                    Passes = 0
                    Failures = 0
                    TotalRows = 0
                }
            }
            
            # Track unique files for this date
            if (-not $dailyStats[$date].Files.ContainsKey($sourceFile)) {
                $dailyStats[$date].Files[$sourceFile] = $true
            }
            
            # Count passes and failures
            $status = Get-PassFailStatus -PassFlag $passFlag
            if ($status -eq "Pass") {
                $dailyStats[$date].Passes++
            } else {
                $dailyStats[$date].Failures++
            }
            
            $dailyStats[$date].TotalRows++
            
            # Progress indicator for large files
            if ($rowCount % 1000 -eq 0) {
                Write-ConditionalHost "Processed $rowCount rows..." -ForegroundColor "Yellow"
            }
        }
        
        $reader.Close()
        Write-ConditionalHost "Processed $rowCount total rows" -ForegroundColor "Green"
        
    }
    catch {
        Write-ConditionalHost "Error reading output file: $($_.Exception.Message)" -IsError
        if ($reader) { $reader.Close() }
        return
    }
    
    # Generate summary CSV
    Write-ConditionalHost "`nGenerating daily summary: $SummaryFilePath" -ForegroundColor "Blue"
    
    try {
        $writer = [System.IO.StreamWriter]::new($SummaryFilePath)
        
        # Write header
        $writer.WriteLine("Date,FilesProcessed,TotalRows,Passes,Failures,PassRate")
        
        # Sort dates and write summary rows
        $sortedDates = $dailyStats.Keys | Sort-Object
        
        foreach ($date in $sortedDates) {
            $stats = $dailyStats[$date]
            $filesProcessed = $stats.Files.Count
            $totalRows = $stats.TotalRows
            $passes = $stats.Passes
            $failures = $stats.Failures
            
            # Calculate pass rate
            if ($totalRows -gt 0) {
                $passRate = [Math]::Round(($passes / $totalRows) * 100, 1)
            } else {
                $passRate = 0.0
            }
            
            # Write summary row
            $summaryRow = "$date,$filesProcessed,$totalRows,$passes,$failures,$passRate%"
            $writer.WriteLine($summaryRow)
            
            Write-ConditionalHost "  ${date}: $filesProcessed files, $totalRows rows, $passes passes, $failures failures ($passRate%)" -ForegroundColor "Cyan"
        }
        
        $writer.Close()
        Write-ConditionalHost "`nDaily summary generated successfully!" -ForegroundColor "Green"
        
    }
    catch {
        Write-ConditionalHost "Error writing summary file: $($_.Exception.Message)" -IsError
        if ($writer) { $writer.Close() }
        return
    }
}

# Main execution
Write-ConditionalHost "Daily Summary Generator v1.0" -ForegroundColor "Magenta"
Write-ConditionalHost "================================" -ForegroundColor "Magenta"

# Read configuration
$config = Read-IniFile -FilePath $ConfigFile

# Determine output file path
if ([string]::IsNullOrEmpty($OutputFile)) {
    if ($config.ContainsKey("General") -and $config["General"].ContainsKey("OutputFile")) {
        $OutputFile = $config["General"]["OutputFile"]
    } elseif ($config.ContainsKey("Output") -and $config["Output"].ContainsKey("MasterFileName") -and $config.ContainsKey("Paths") -and $config["Paths"].ContainsKey("OutputFolder")) {
        # Construct output file path from OutputFolder and MasterFileName
        $outputFolder = $config["Paths"]["OutputFolder"]
        $masterFileName = $config["Output"]["MasterFileName"]
        $OutputFile = Join-Path $outputFolder $masterFileName
    } else {
        $OutputFile = "combined_output.csv"
    }
}

# Determine summary output folder
if ([string]::IsNullOrEmpty($SummaryOutputFolder)) {
    if ($config.ContainsKey("Paths") -and $config["Paths"].ContainsKey("SummaryOutputFolder")) {
        $SummaryOutputFolder = $config["Paths"]["SummaryOutputFolder"]
    } else {
        $SummaryOutputFolder = ".\output"  # Default to output folder
    }
}

# Determine summary file name
if ([string]::IsNullOrEmpty($SummaryFile)) {
    if ($config.ContainsKey("Output") -and $config["Output"].ContainsKey("SummaryFileName")) {
        $SummaryFile = $config["Output"]["SummaryFileName"]
    } else {
        $SummaryFile = "daily_summary.csv"  # Default filename
    }
}

# Construct full summary file path
$SummaryFilePath = Join-Path $SummaryOutputFolder $SummaryFile

Write-ConditionalHost "Configuration:" -ForegroundColor "Yellow"
Write-ConditionalHost "  Config File: $ConfigFile" -ForegroundColor "White"
Write-ConditionalHost "  Output File: $OutputFile" -ForegroundColor "White"
Write-ConditionalHost "  Summary Output Folder: $SummaryOutputFolder" -ForegroundColor "White"
Write-ConditionalHost "  Summary File: $SummaryFile" -ForegroundColor "White"
Write-ConditionalHost "  Full Summary Path: $SummaryFilePath" -ForegroundColor "White"

# Generate the daily summary
Generate-DailySummary -OutputFilePath $OutputFile -SummaryFilePath $SummaryFilePath

Write-ConditionalHost "`nDaily summary generation complete!" -ForegroundColor "Green"
