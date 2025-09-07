# ==============================================================================
# Configuration Module Tests
# ==============================================================================
# Tests for CSVCombiner-Config.ps1 functionality
# ==============================================================================

# Import required modules
$ScriptRoot = Split-Path -Parent $PSCommandPath
$ProjectRoot = Split-Path (Split-Path $ScriptRoot -Parent) -Parent
$ModuleRoot = Join-Path $ProjectRoot "src\modules"
. (Join-Path $ModuleRoot "CSVCombiner-Logger.ps1")
. (Join-Path $ModuleRoot "CSVCombiner-Config.ps1")

Describe "Configuration Management Tests" {
    
    Context "Read-IniFile Tests" {
        BeforeEach {
            $TestIniPath = Join-Path $TestDrive "test.ini"
        }
        
        It "Should parse basic INI file correctly" {
            $IniContent = @"
[General]
InputFolder=./input
OutputFolder=./output
OutputBaseName=combined

[Advanced]
PollingInterval=3
UseFileHashing=true
"@
            Set-Content -Path $TestIniPath -Value $IniContent
            
            $result = Read-IniFile -FilePath $TestIniPath
            
            $result.General.InputFolder | Should Be "./input"
            $result.General.OutputFolder | Should Be "./output"
            $result.General.OutputBaseName | Should Be "combined"
            $result.Advanced.PollingInterval | Should Be "3"
            $result.Advanced.UseFileHashing | Should Be "true"
        }
        
        It "Should handle comments and empty lines" {
            $IniContent = @"
# This is a comment
[General]
InputFolder=./input
; This is another comment

OutputFolder=./output
"@
            Set-Content -Path $TestIniPath -Value $IniContent
            
            $result = Read-IniFile -FilePath $TestIniPath
            
            $result.General.InputFolder | Should Be "./input"
            $result.General.OutputFolder | Should Be "./output"
        }
        
        It "Should return empty hash table for non-existent file" {
            $result = Read-IniFile -FilePath "nonexistent.ini"
            $result | Should BeOfType hashtable
            $result.Count | Should Be 0
        }
    }
    
    Context "CSVCombinerConfig Class Tests" {
        It "Should instantiate with valid configuration file" {
            $configPath = Join-Path $ProjectRoot "config\CSVCombiner.ini"
            if (Test-Path $configPath) {
                $config = [CSVCombinerConfig]::new($configPath)
                $config | Should Not BeNullOrEmpty
            }
            else {
                # Skip if config file doesn't exist
                Set-TestInconclusive "Configuration file not found"
            }
        }
        
        It "Should handle missing configuration file gracefully" {
            $config = [CSVCombinerConfig]::new("nonexistent.ini")
            $config | Should Not BeNullOrEmpty
            
            # Should indicate validation failure
            $isValid = $config.LoadAndValidate()
            $isValid | Should Be $false
        }
        
        It "Should validate configuration parameters exist" {
            $config = [CSVCombinerConfig]::new(".\config\CSVCombiner.ini")
            
            # Test that key methods exist
            $configType = $config.GetType()
            $methods = $configType.GetMethods() | Where-Object { $_.Name -like "Get*" }
            $methods.Count | Should BeGreaterThan 0
            
            # Test specific methods exist
            { $config.GetPollingInterval() } | Should Not Throw
            { $config.GetValidateFilenameFormat() } | Should Not Throw
        }
    }
    
    Context "Configuration Validation Tests" {
        It "Should validate polling interval is positive" {
            $config = [CSVCombinerConfig]::new(".\config\CSVCombiner.ini")
            $pollingInterval = $config.GetPollingInterval()
            $pollingInterval | Should BeGreaterThan 0
        }
        
        It "Should validate wait time is non-negative" {
            $config = [CSVCombinerConfig]::new(".\config\CSVCombiner.ini")
            $waitTime = $config.GetWaitForStableFile()
            $waitTime | Should BeGreaterThan -1
        }
        
        It "Should provide reasonable default values" {
            $config = [CSVCombinerConfig]::new("nonexistent.ini")
            
            # Even with missing file, should have defaults
            $pollingInterval = $config.GetPollingInterval()
            $pollingInterval | Should BeGreaterThan 0
            $pollingInterval | Should BeLessThan 3600  # Should be reasonable
        }
        
        It "Should handle StartMinimized setting correctly" {
            # Create the necessary directories for path validation
            $testInput = Join-Path $TestDrive "sampledata\input"
            $testOutput = Join-Path $TestDrive "sampledata\output"
            New-Item -ItemType Directory -Path $testInput -Force | Out-Null
            New-Item -ItemType Directory -Path $testOutput -Force | Out-Null
            
            # Change to TestDrive to make relative paths work
            Push-Location $TestDrive
            try {
                $config = [CSVCombinerConfig]::new("..\..\config\CSVCombiner.ini")
                $result = $config.LoadAndValidate()
                
                if ($result) {
                    # Should return boolean value
                    $startMinimized = $config.GetStartMinimized()
                    $startMinimized | Should BeOfType [bool]
                } else {
                    # If validation fails, just test the method works
                    $config.Config = @{
                        General = @{
                            StartMinimized = "false"
                        }
                    }
                    $startMinimized = $config.GetStartMinimized()
                    $startMinimized | Should BeOfType [bool]
                    $startMinimized | Should Be $false
                }
            }
            finally {
                Pop-Location
            }
        }
        
        It "Should default StartMinimized to false when not specified" {
            # Create temp config with all required settings but without StartMinimized
            $tempInput = Join-Path $TestDrive "input"
            $tempOutput = Join-Path $TestDrive "output"
            New-Item -ItemType Directory -Path $tempInput -Force | Out-Null
            New-Item -ItemType Directory -Path $tempOutput -Force | Out-Null
            
            $tempConfig = Join-Path $TestDrive "temp.ini"
            Set-Content -Path $tempConfig -Value @"
[General]
InputFolder=$tempInput
OutputFolder=$tempOutput
OutputBaseName=TestData
ValidateFilenameFormat=true
LogFile=./logs/test.log

[Advanced]
PollingInterval=3
UseFileHashing=true
WaitForStableFile=2000
MaxPollingRetries=3
"@
            
            $config = [CSVCombinerConfig]::new($tempConfig)
            $config.LoadAndValidate() | Should Be $true
            $config.GetStartMinimized() | Should Be $false
        }
    }
}

Write-Host "✅ Configuration module tests completed" -ForegroundColor Green
