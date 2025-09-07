# ==============================================================================
# Logger Module Tests
# ==============================================================================
# Tests for CSVCombiner-Logger.ps1 functionality
# ==============================================================================

# Import required modules
$ScriptRoot = Split-Path -Parent $PSCommandPath
$ProjectRoot = Split-Path (Split-Path $ScriptRoot -Parent) -Parent
$ModuleRoot = Join-Path $ProjectRoot "src\modules"
. (Join-Path $ModuleRoot "CSVCombiner-Logger.ps1")

Describe "Logger Module Tests" {
    
    Context "Write-Log Function Tests" {
        BeforeEach {
            $TestLogPath = Join-Path $TestDrive "test.log"
            if (Test-Path $TestLogPath) {
                Remove-Item $TestLogPath -Force
            }
        }
        
        AfterEach {
            if (Test-Path $TestLogPath) {
                Remove-Item $TestLogPath -Force
            }
        }
        
        It "Should write log message to file when LogFile is specified" {
            Write-Log -Message "Test message" -Level "INFO" -LogFile $TestLogPath
            
            Start-Sleep -Milliseconds 100  # Give time for file write
            $content = Get-Content -Path $TestLogPath -Raw
            $content | Should Match "\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[INFO\] Test message"
        }
        
        It "Should include timestamp in log message" {
            Write-Log -Message "Test message" -Level "DEBUG" -LogFile $TestLogPath
            
            Start-Sleep -Milliseconds 100  # Give time for file write
            $content = Get-Content -Path $TestLogPath -Raw
            $content | Should Match "\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[DEBUG\] Test message"
        }
        
        It "Should default to INFO level" {
            Write-Log -Message "Test message" -LogFile $TestLogPath
            
            Start-Sleep -Milliseconds 100  # Give time for file write
            $content = Get-Content -Path $TestLogPath -Raw
            $content | Should Match "\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[INFO\] Test message"
        }
        
        It "Should handle different log levels" {
            @("DEBUG", "INFO", "WARN", "ERROR") | ForEach-Object {
                $level = $_
                $message = "Test $level message"
                Write-Log -Message $message -Level $level -LogFile $TestLogPath
            }
            
            Start-Sleep -Milliseconds 200  # Give time for file writes
            $content = Get-Content -Path $TestLogPath -Raw
            
            $content | Should Match "\[DEBUG\] Test DEBUG message"
            $content | Should Match "\[INFO\] Test INFO message"
            $content | Should Match "\[WARN\] Test WARN message"
            $content | Should Match "\[ERROR\] Test ERROR message"
        }
    }
    
    Context "CSVCombinerLogger Class Tests" {
        It "Should instantiate logger with different log levels" {
            $logger1 = [CSVCombinerLogger]::new($null, "DEBUG")
            $logger1.LogLevel | Should Be "DEBUG"
            
            $logger2 = [CSVCombinerLogger]::new($null, "ERROR")
            $logger2.LogLevel | Should Be "ERROR"
        }
        
        It "Should handle log file operations through class" {
            $testLogPath = Join-Path $TestDrive "csvtest_class.log"
            $logger = [CSVCombinerLogger]::new($null, "INFO")
            $logger.LogFile = $testLogPath
            
            $logger.Info("Test info message")
            
            Start-Sleep -Milliseconds 100  # Give time for file write
            Test-Path $testLogPath | Should Be $true
            
            $content = Get-Content $testLogPath -Raw
            $content | Should Match "Test info message"
            
            # Cleanup
            if (Test-Path $testLogPath) {
                Remove-Item $testLogPath -Force
            }
        }
        
        It "Should support different logging methods" {
            $testLogPath = Join-Path $TestDrive "csvtest_methods.log"
            $logger = [CSVCombinerLogger]::new($testLogPath, "DEBUG")
            
            # Test that the logger has the expected methods
            $logger.GetType().GetMethods() | Where-Object { $_.Name -eq "Debug" } | Should Not BeNullOrEmpty
            $logger.GetType().GetMethods() | Where-Object { $_.Name -eq "Info" } | Should Not BeNullOrEmpty
            $logger.GetType().GetMethods() | Where-Object { $_.Name -eq "Warning" } | Should Not BeNullOrEmpty
            $logger.GetType().GetMethods() | Where-Object { $_.Name -eq "Error" } | Should Not BeNullOrEmpty
            
            # Cleanup
            if (Test-Path $testLogPath) {
                Remove-Item $testLogPath -Force
            }
        }
        
        It "Should filter log messages by level" {
            $testLogPath = Join-Path $TestDrive "csvtest_filter.log"
            $logger = [CSVCombinerLogger]::new($testLogPath, "WARNING")
            
            # These should be written (WARNING and above)
            $logger.Warning("Warning message")
            $logger.Error("Error message")
            
            # These should be filtered out (below WARNING level)
            $logger.Debug("Debug message")
            $logger.Info("Info message")
            
            Start-Sleep -Milliseconds 100  # Give time for file write
            
            if (Test-Path $testLogPath) {
                $content = Get-Content $testLogPath -Raw
                $content | Should Match "Warning message"
                $content | Should Match "Error message"
                $content | Should Not Match "Debug message"
                $content | Should Not Match "Info message"
                
                Remove-Item $testLogPath -Force
            }
        }
    }
    
    Context "Log File Management" {
        It "Should create log directory if it doesn't exist" {
            $testDir = Join-Path $TestDrive "newlogdir"
            $testLogPath = Join-Path $testDir "test.log"
            
            # Directory shouldn't exist initially
            Test-Path $testDir | Should Be $false
            
            Write-Log -Message "Test message" -Level "INFO" -LogFile $testLogPath
            
            Start-Sleep -Milliseconds 100
            
            # Directory and file should be created
            Test-Path $testDir | Should Be $true
            Test-Path $testLogPath | Should Be $true
            
            # Cleanup
            Remove-Item $testDir -Recurse -Force
        }
        
        It "Should append to existing log file" {
            $testLogPath = Join-Path $TestDrive "append_test.log"
            
            # Write first message
            Write-Log -Message "First message" -Level "INFO" -LogFile $testLogPath
            Start-Sleep -Milliseconds 50
            
            # Write second message
            Write-Log -Message "Second message" -Level "INFO" -LogFile $testLogPath
            Start-Sleep -Milliseconds 50
            
            $content = Get-Content $testLogPath -Raw
            $content | Should Match "First message"
            $content | Should Match "Second message"
            
            # Should have both messages (not overwritten)
            ($content -split "`n" | Where-Object { $_ -match "INFO" }).Count | Should BeGreaterThan 1
            
            # Cleanup
            Remove-Item $testLogPath -Force
        }
    }
    
    Context "Error Handling" {
        It "Should handle invalid log file paths gracefully" {
            # Try to write to an invalid path
            { Write-Log -Message "Test" -Level "INFO" -LogFile "Z:\InvalidPath\test.log" } | Should Not Throw
        }
        
        It "Should handle null or empty messages" {
            $testLogPath = Join-Path $TestDrive "null_test.log"
            
            { Write-Log -Message $null -Level "INFO" -LogFile $testLogPath } | Should Not Throw
            { Write-Log -Message "" -Level "INFO" -LogFile $testLogPath } | Should Not Throw
            
            if (Test-Path $testLogPath) {
                Remove-Item $testLogPath -Force
            }
        }
        
        It "Should handle invalid log levels gracefully" {
            $testLogPath = Join-Path $TestDrive "invalid_level.log"
            
            { Write-Log -Message "Test" -Level "INVALID" -LogFile $testLogPath } | Should Not Throw
            
            if (Test-Path $testLogPath) {
                Remove-Item $testLogPath -Force
            }
        }
    }
}

Write-Host "✅ Logger module tests completed" -ForegroundColor Green
