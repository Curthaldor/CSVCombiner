# ==============================================================================
# CSV Combiner Configuration Module v2.4
# ==============================================================================
# Purpose: Configuration management and validation
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

# Configuration validation and loading functions
class CSVCombinerConfig {
    [hashtable]$Config
    [string]$ConfigPath
    
    CSVCombinerConfig([string]$configPath) {
        $this.ConfigPath = $configPath
        $this.Config = @{}
    }
    
    [bool]LoadAndValidate() {
        try {
            Write-Log "Loading configuration from: $($this.ConfigPath)" "INFO"
            
            # Read the configuration file
            $newConfig = Read-IniFile -FilePath $this.ConfigPath
            
            # Validate required sections and settings
            if (!$this.ValidateRequiredSettings($newConfig)) {
                return $false
            }
            
            # Validate paths and permissions
            if (!$this.ValidatePathsAndPermissions($newConfig)) {
                return $false
            }
            
            # All validation passed
            $this.Config = $newConfig
            Write-Log "Configuration loaded and validated successfully" "INFO"
            return $true
        }
        catch {
            Write-Log "Error reading configuration file: $($_.Exception.Message)" "ERROR"
            return $false
        }
    }
    
    [bool]ValidateRequiredSettings([hashtable]$config) {
        $requiredSettings = @(
            @{Section="General"; Key="InputFolder"; Description="Input folder path"},
            @{Section="General"; Key="OutputFolder"; Description="Output folder path"},
            @{Section="General"; Key="OutputBaseName"; Description="Output file base name"}
        )
        
        foreach ($setting in $requiredSettings) {
            if (!$config[$setting.Section]) {
                Write-Log "Missing [$($setting.Section)] section in configuration" "ERROR"
                return $false
            }
            
            if (!$config[$setting.Section][$setting.Key]) {
                Write-Log "Missing or empty $($setting.Description) in configuration" "ERROR"
                return $false
            }
        }
        
        return $true
    }
    
    [bool]ValidatePathsAndPermissions([hashtable]$config) {
        # Validate input folder exists
        if (!(Test-Path $config.General.InputFolder)) {
            Write-Log "Input folder does not exist: $($config.General.InputFolder)" "ERROR"
            return $false
        }
        
        # Check output directory but don't auto-create it
        $outputDir = $config.General.OutputFolder
        if ($outputDir -and !(Test-Path $outputDir)) {
            Write-Log "Output directory does not exist: $outputDir (will queue data until directory is created)" "WARNING"
        } elseif ($outputDir -and (Test-Path $outputDir)) {
            Write-Log "Output directory validated: $outputDir" "INFO"
        }
        
        return $true
    }
    
    [string]GetInputFolder() {
        return $this.Config.General.InputFolder
    }
    
    [string]GetOutputFolder() {
        return $this.Config.General.OutputFolder
    }
    
    [string]GetOutputBaseName() {
        return $this.Config.General.OutputBaseName
    }
    
    [bool]GetValidateFilenameFormat() {
        return ($this.Config.General.ValidateFilenameFormat -eq "true")
    }
    
    [bool]GetUseFileHashing() {
        return ($this.Config.Advanced.UseFileHashing -eq "true")
    }
    
    [int]GetPollingInterval() {
        $interval = [int]$this.Config.Advanced.PollingInterval
        if ($interval -gt 0) { return $interval } else { return 10 }
    }
    
    [int]GetWaitForStableFile() {
        return [int]$this.Config.Advanced.WaitForStableFile
    }
    
    [int]GetMaxPollingRetries() {
        return [int]$this.Config.Advanced.MaxPollingRetries
    }
    
    [string]GetLogFile() {
        return $this.Config.General.LogFile
    }
    
    [bool]GetStartMinimized() {
        $value = $this.Config.General.StartMinimized
        if ($value -eq $null -or $value -eq "") {
            return $false
        }
        return $value.ToLower() -eq "true"
    }
}
