# ==============================================================================
# CSV Combiner Logging Module v2.4
# ==============================================================================
# Purpose: Centralized logging with consistent formatting and levels
# ==============================================================================

# Standalone logging function for backwards compatibility and utility use
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

class CSVCombinerLogger {
    [string]$LogFile
    [string]$LogLevel
    
    static [hashtable]$LogLevels = @{
        "DEBUG" = 0
        "INFO" = 1
        "WARNING" = 2
        "ERROR" = 3
    }
    
    CSVCombinerLogger([string]$logFile = $null, [string]$logLevel = "INFO") {
        $this.LogFile = $logFile
        $this.LogLevel = $logLevel.ToUpper()
    }
    
    [void]Log([string]$message, [string]$level = "INFO") {
        $upperLevel = $level.ToUpper()
        
        # Check if this message should be logged based on current log level
        if ([CSVCombinerLogger]::LogLevels[$upperLevel] -lt [CSVCombinerLogger]::LogLevels[$this.LogLevel]) {
            return
        }
        
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$timestamp] [$upperLevel] $message"
        
        # Always write to console
        switch ($upperLevel) {
            "ERROR" { Write-Host $logMessage -ForegroundColor Red }
            "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
            "DEBUG" { Write-Host $logMessage -ForegroundColor Gray }
            default { Write-Host $logMessage }
        }
        
        # Write to file if configured
        if ($this.LogFile) {
            try {
                Add-Content -Path $this.LogFile -Value $logMessage -ErrorAction SilentlyContinue
            }
            catch {
                Write-Host "Failed to write to log file: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    
    [void]Debug([string]$message) {
        $this.Log($message, "DEBUG")
    }
    
    [void]Info([string]$message) {
        $this.Log($message, "INFO")
    }
    
    [void]Warning([string]$message) {
        $this.Log($message, "WARNING")
    }
    
    [void]Error([string]$message) {
        $this.Log($message, "ERROR")
    }
    
    [void]LogSectionHeader([string]$title) {
        $separator = "=" * $title.Length
        $this.Info($separator)
        $this.Info($title)
        $this.Info($separator)
    }
    
    [void]LogSubsectionHeader([string]$title) {
        $separator = "-" * $title.Length
        $this.Info($separator)
        $this.Info($title)
        $this.Info($separator)
    }
}
