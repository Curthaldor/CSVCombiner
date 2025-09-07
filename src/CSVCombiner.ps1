# ==============================================================================
# CSV Combiner Script v3.0 - Production Ready with StartMinimized Feature
# ==============================================================================
# Author: Curt Haldorson, GitHub Copilot Assistant
# Created: August 2025
# Updated: September 2025 - Added StartMinimized feature and comprehensive test suite
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
# - Modular architecture with specialized classes for better maintainability
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
# - CSVCombiner-*.ps1 modules (Functions, Config, Logger, FileProcessor, MonitoringService)
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

# ===========================
# MODULE IMPORTS
# ===========================

# Load modules at script scope level to ensure classes are available
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$modulesDir = Join-Path $scriptDir "modules"
Write-Host "DEBUG: Loading modules from directory: $modulesDir"

$modules = @(
    "CSVCombiner-Logger.ps1",           # Load logger first - provides Write-Log function
    "CSVCombiner-Config.ps1",           # Load config second - depends on Read-IniFile and Write-Log  
    "CSVCombiner-FileOperations.ps1",   # Load file operations third - depends on Write-Log
    "CSVCombiner-DataProcessing.ps1",   # Load data processing fourth - depends on Write-Log
    "CSVCombiner-FileProcessor.ps1",    # Load processor fifth - depends on all data processing functions
    "CSVCombiner-MonitoringService.ps1" # Load monitoring last - depends on file operations and processor
)

foreach ($module in $modules) {
    $modulePath = Join-Path $modulesDir $module
    Write-Host "DEBUG: Attempting to load: $modulePath"
    if (Test-Path $modulePath) {
        try {
            . $modulePath
            Write-Host "DEBUG: Successfully loaded module: $module"
        }
        catch {
            Write-Host "ERROR: Failed to load module $module`: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Error "Required module not found: $modulePath"
        exit 1
    }
}
Write-Host "DEBUG: All modules loaded successfully"

# ===========================
# PROCESS MANAGEMENT
# ===========================

class ProcessManager {
    [string]$PidFile
    [object]$Logger
    
    ProcessManager([object]$logger, [string]$scriptPath) {
        $this.Logger = $logger
        # Place PID file in root directory (parent of src)
        $srcDir = Split-Path $scriptPath -Parent
        $rootDir = Split-Path $srcDir -Parent
        $this.PidFile = Join-Path $rootDir "csvcombiner.pid"
    }
    
    [void]CreatePidFile() {
        $currentPID = $global:PID
        $currentPID | Out-File -FilePath $this.PidFile -Encoding ASCII
        $this.Logger.Info("PID file created: $($this.PidFile) (PID: $currentPID)")
        
        # Set up cleanup on exit
        $null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
            $pidFile = $using:This.PidFile
            if (Test-Path $pidFile) {
                Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    [void]RemovePidFile() {
        if (Test-Path $this.PidFile) {
            Remove-Item $this.PidFile -Force -ErrorAction SilentlyContinue
            $this.Logger.Info("PID file removed: $($this.PidFile)")
        }
    }
}

# ===========================
# MAIN FUNCTION
# ===========================

# Main function that orchestrates the entire CSV Combiner execution
function Start-CSVCombiner {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConfigPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$Monitor
    )
    
    # Initialize components
    $logger = [CSVCombinerLogger]::new($null, "INFO")
    $processManager = [ProcessManager]::new($logger, $PSCommandPath)
    
    try {
        $logger.LogSectionHeader("CSV Combiner Started")
        $logger.Info("Config file: $ConfigPath")
        $logger.Info("Mode: $(if ($Monitor) { 'Continuous Monitoring' } else { 'Single Run' })")

        # Create PID file for process management
        $processManager.CreatePidFile()

        # Load and validate configuration
        $config = [CSVCombinerConfig]::new($ConfigPath)
        if (!$config.LoadAndValidate()) {
            $logger.Error("Configuration validation failed. Please check: $ConfigPath")
            return $false
        }
        
        # Update logger with config settings
        $logger.LogFile = $config.GetLogFile()

        # Initialize file processor
        $fileProcessor = [CSVFileProcessor]::new($config, $logger)

        # Perform initial file processing
        $logger.LogSubsectionHeader("Initial File Processing")
        $outputPath = $fileProcessor.ProcessFiles($config.GetInputFolder(), $null)

        if ($outputPath) {
            $logger.Info("Initial processing complete: $outputPath")
        } else {
            $logger.Info("No CSV files found during initial scan")
        }

        # Check if we should run once and exit (default behavior)
        if (-not $Monitor) {
            $logger.Info("Single-run mode: Exiting after initial processing")
            return $outputPath
        }

        # Set up and start continuous monitoring
        $monitoringService = [CSVMonitoringService]::new($config, $logger, $fileProcessor)
        $monitoringService.InitializeMonitoring()
        $monitoringService.StartMonitoring()

        return $true
    }
    catch {
        $logger.Error("FATAL: Unexpected error in main execution: $($_.Exception.Message)")
        $logger.Debug("Stack trace: $($_.ScriptStackTrace)")
        return $false
    }
    finally {
        $logger.LogSectionHeader("CSV Combiner Stopped")
        $processManager.RemovePidFile()
    }
}

# ===========================
# SCRIPT EXECUTION
# ===========================

# Execute main function when script is run directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    $exitCode = if (Start-CSVCombiner -ConfigPath $ConfigPath -Monitor:$Monitor) { 0 } else { 1 }
    exit $exitCode
}
