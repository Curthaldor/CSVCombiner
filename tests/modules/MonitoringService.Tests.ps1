# ==============================================================================
# MonitoringService Module Tests
# ==============================================================================
# Tests for CSVCombiner-MonitoringService.ps1 functionality
# ==============================================================================

# Import required modules
$ScriptRoot = Split-Path -Parent $PSCommandPath
$ProjectRoot = Split-Path (Split-Path $ScriptRoot -Parent) -Parent
$ModuleRoot = Join-Path $ProjectRoot "src\modules"
. (Join-Path $ModuleRoot "CSVCombiner-Logger.ps1")
. (Join-Path $ModuleRoot "CSVCombiner-Config.ps1")
. (Join-Path $ModuleRoot "CSVCombiner-FileOperations.ps1")
. (Join-Path $ModuleRoot "CSVCombiner-MonitoringService.ps1")

Describe "MonitoringService Module Tests" {
    
    Context "CSVMonitoringService Class Tests" {
        It "Should instantiate CSVMonitoringService successfully" {
            # Create mock configuration
            $config = New-Object -TypeName PSObject
            Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetInputFolder" -Value { return ".\input" }
            Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetPollingInterval" -Value { return 5 }
            Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetValidateFilenameFormat" -Value { return $true }
            Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetUseFileHashing" -Value { return $false }
            
            # Create logger
            $logger = [CSVCombinerLogger]::new($null, "INFO")
            
            # Create mock file processor
            $fileProcessor = New-Object -TypeName PSObject
            Add-Member -InputObject $fileProcessor -MemberType ScriptMethod -Name "GetOutputPath" -Value { return ".\output\MasterData.csv" }
            Add-Member -InputObject $fileProcessor -MemberType ScriptMethod -Name "ProcessFiles" -Value { param($folder, $changes) return ".\output\MasterData.csv" }
            
            # Test instantiation
            { $monitor = [CSVMonitoringService]::new($config, $logger, $fileProcessor) } | Should Not Throw
        }
        
        It "Should have required properties for monitoring" {
            $config = New-Object -TypeName PSObject
            Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetInputFolder" -Value { return ".\input" }
            Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetPollingInterval" -Value { return 5 }
            Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetValidateFilenameFormat" -Value { return $true }
            Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetUseFileHashing" -Value { return $false }
            
            $logger = [CSVCombinerLogger]::new($null, "INFO")
            
            # Create mock file processor
            $fileProcessor = New-Object -TypeName PSObject
            Add-Member -InputObject $fileProcessor -MemberType ScriptMethod -Name "GetOutputPath" -Value { return ".\output\MasterData.csv" }
            Add-Member -InputObject $fileProcessor -MemberType ScriptMethod -Name "ProcessFiles" -Value { param($folder, $changes) return ".\output\MasterData.csv" }
            
            $monitor = [CSVMonitoringService]::new($config, $logger, $fileProcessor)
            
            # Check that required properties exist
            $monitor.InputFolder | Should Not BeNullOrEmpty
            $monitor.Config.GetPollingInterval() | Should BeGreaterThan 0
        }
        
        It "Should initialize with current file snapshot" {
            $testDir = Join-Path ([System.IO.Path]::GetTempPath()) "monitor_test_$(Get-Random)"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                # Create test files
                "Name,Age`nJohn,30" | Out-File -FilePath (Join-Path $testDir "20250101120000.csv") -Encoding UTF8
                "Name,City`nJane,NYC" | Out-File -FilePath (Join-Path $testDir "20250101130000.csv") -Encoding UTF8
                
                $config = New-Object -TypeName PSObject
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetInputFolder" -Value { return $testDir }
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetPollingInterval" -Value { return 5 }
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetValidateFilenameFormat" -Value { return $true }
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetUseFileHashing" -Value { return $false }
                
                $logger = [CSVCombinerLogger]::new($null, "INFO")
                
                # Create mock file processor
                $fileProcessor = New-Object -TypeName PSObject
                Add-Member -InputObject $fileProcessor -MemberType ScriptMethod -Name "GetOutputPath" -Value { return ".\output\MasterData.csv" }
                Add-Member -InputObject $fileProcessor -MemberType ScriptMethod -Name "ProcessFiles" -Value { param($folder, $changes) return ".\output\MasterData.csv" }
                
                $monitor = [CSVMonitoringService]::new($config, $logger, $fileProcessor)
                
                # Initialize monitoring to take initial snapshot
                $monitor.TakeInitialSnapshot()
                
                # Should initialize with current files
                $monitor.LastSnapshot | Should Not BeNullOrEmpty
                $monitor.LastSnapshot.Files.Count | Should Be 2
            }
            finally {
                if (Test-Path $testDir) {
                    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        
        It "Should detect file changes during monitoring check" {
            $testDir = Join-Path ([System.IO.Path]::GetTempPath()) "monitor_changes_test_$(Get-Random)"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                # Create initial file
                "Name,Age`nJohn,30" | Out-File -FilePath (Join-Path $testDir "20250101120000.csv") -Encoding UTF8
                
                $config = New-Object -TypeName PSObject
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetInputFolder" -Value { return $testDir }
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetPollingInterval" -Value { return 5 }
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetValidateFilenameFormat" -Value { return $true }
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetUseFileHashing" -Value { return $false }
                
                $logger = [CSVCombinerLogger]::new($null, "INFO")
                
                # Create mock file processor
                $fileProcessor = New-Object -TypeName PSObject
                Add-Member -InputObject $fileProcessor -MemberType ScriptMethod -Name "GetOutputPath" -Value { return ".\output\MasterData.csv" }
                Add-Member -InputObject $fileProcessor -MemberType ScriptMethod -Name "ProcessFiles" -Value { param($folder, $changes) return ".\output\MasterData.csv" }
                
                $monitor = [CSVMonitoringService]::new($config, $logger, $fileProcessor)
                
                # Take initial snapshot of existing files
                $monitor.TakeInitialSnapshot()
                
                # Add new file
                Start-Sleep -Milliseconds 100  # Ensure timestamp difference
                "Name,City`nJane,NYC" | Out-File -FilePath (Join-Path $testDir "20250101130000.csv") -Encoding UTF8
                
                # Check for changes
                $changes = $monitor.CheckForChanges()
                
                # Should detect new file
                $changes | Should Not BeNullOrEmpty
                $changes.NewFiles.Count | Should Be 1
                $changes.NewFiles[0] | Should Be "20250101130000.csv"
            }
            finally {
                if (Test-Path $testDir) {
                    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        
        It "Should handle empty directories" {
            $testDir = Join-Path ([System.IO.Path]::GetTempPath()) "monitor_empty_test_$(Get-Random)"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                $config = New-Object -TypeName PSObject
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetInputFolder" -Value { return $testDir }.GetNewClosure()
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetPollingInterval" -Value { return 5 }
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetValidateFilenameFormat" -Value { return $true }
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetUseFileHashing" -Value { return $false }
                
                $logger = [CSVCombinerLogger]::new($null, "INFO")
                
                # Create mock file processor
                $fileProcessor = New-Object -TypeName PSObject
                Add-Member -InputObject $fileProcessor -MemberType ScriptMethod -Name "GetOutputPath" -Value { return ".\output\MasterData.csv" }
                Add-Member -InputObject $fileProcessor -MemberType ScriptMethod -Name "ProcessFiles" -Value { param($folder, $changes) return ".\output\MasterData.csv" }
                
                # Should handle empty directory without error
                { $monitor = [CSVMonitoringService]::new($config, $logger, $fileProcessor) } | Should Not Throw
                
                # Initialize monitoring to take initial snapshot
                $monitor.TakeInitialSnapshot()
                
                # LastSnapshot should exist and have empty Files collection
                $monitor.LastSnapshot | Should Not Be $null
                $monitor.LastSnapshot.Files | Should Not Be $null
                $monitor.LastSnapshot.Files.Count | Should Be 0
                
                # Should handle checking for changes in empty directory
                { $changes = $monitor.CheckForChanges() } | Should Not Throw
            }
            finally {
                if (Test-Path $testDir) {
                    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    
    Context "File Monitoring Logic" {
        It "Should respect filename format validation setting" {
            $testDir = Join-Path ([System.IO.Path]::GetTempPath()) "monitor_validation_test_$(Get-Random)"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                # Create valid and invalid format files
                "Name,Age`nJohn,30" | Out-File -FilePath (Join-Path $testDir "20250101120000.csv") -Encoding UTF8
                "Name,City`nJane,NYC" | Out-File -FilePath (Join-Path $testDir "invalid_name.csv") -Encoding UTF8
                
                # Test with validation enabled
                $configValidate = New-Object -TypeName PSObject
                Add-Member -InputObject $configValidate -MemberType ScriptMethod -Name "GetInputFolder" -Value { return $testDir }
                Add-Member -InputObject $configValidate -MemberType ScriptMethod -Name "GetPollingInterval" -Value { return 5 }
                Add-Member -InputObject $configValidate -MemberType ScriptMethod -Name "GetValidateFilenameFormat" -Value { return $true }
                Add-Member -InputObject $configValidate -MemberType ScriptMethod -Name "GetUseFileHashing" -Value { return $false }
                
                $logger = [CSVCombinerLogger]::new($null, "INFO")
                
                # Create mock file processor
                $fileProcessor = New-Object -TypeName PSObject
                Add-Member -InputObject $fileProcessor -MemberType ScriptMethod -Name "GetOutputPath" -Value { return ".\output\MasterData.csv" }
                Add-Member -InputObject $fileProcessor -MemberType ScriptMethod -Name "ProcessFiles" -Value { param($folder, $changes) return ".\output\MasterData.csv" }
                
                $monitorValidate = [CSVMonitoringService]::new($configValidate, $logger, $fileProcessor)
                
                # Initialize monitoring to take initial snapshot
                $monitorValidate.TakeInitialSnapshot()
                
                # Should only detect valid format file
                $monitorValidate.LastSnapshot.Files.Count | Should Be 1
                $monitorValidate.LastSnapshot.Files.ContainsKey("20250101120000.csv") | Should Be $true
                $monitorValidate.LastSnapshot.Files.ContainsKey("invalid_name.csv") | Should Be $false
                
                # Test with validation disabled
                $configNoValidate = New-Object -TypeName PSObject
                Add-Member -InputObject $configNoValidate -MemberType ScriptMethod -Name "GetInputFolder" -Value { return $testDir }
                Add-Member -InputObject $configNoValidate -MemberType ScriptMethod -Name "GetPollingInterval" -Value { return 5 }
                Add-Member -InputObject $configNoValidate -MemberType ScriptMethod -Name "GetValidateFilenameFormat" -Value { return $false }
                Add-Member -InputObject $configNoValidate -MemberType ScriptMethod -Name "GetUseFileHashing" -Value { return $false }
                
                # Create mock file processor
                $fileProcessor2 = New-Object -TypeName PSObject
                Add-Member -InputObject $fileProcessor2 -MemberType ScriptMethod -Name "GetOutputPath" -Value { return ".\output\MasterData.csv" }
                Add-Member -InputObject $fileProcessor2 -MemberType ScriptMethod -Name "ProcessFiles" -Value { param($folder, $changes) return ".\output\MasterData.csv" }
                
                $monitorNoValidate = [CSVMonitoringService]::new($configNoValidate, $logger, $fileProcessor2)
                
                # Initialize monitoring to take initial snapshot
                $monitorNoValidate.TakeInitialSnapshot()
                
                # Should detect both files
                $monitorNoValidate.LastSnapshot.Files.Count | Should Be 2
                $monitorNoValidate.LastSnapshot.Files.ContainsKey("20250101120000.csv") | Should Be $true
                $monitorNoValidate.LastSnapshot.Files.ContainsKey("invalid_name.csv") | Should Be $true
            }
            finally {
                if (Test-Path $testDir) {
                    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        
        It "Should detect file modifications" {
            $testDir = Join-Path ([System.IO.Path]::GetTempPath()) "monitor_modify_test_$(Get-Random)"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                $testFile = Join-Path $testDir "20250101120000.csv"
                "Name,Age`nJohn,30" | Out-File -FilePath $testFile -Encoding UTF8
                
                $config = New-Object -TypeName PSObject
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetInputFolder" -Value { return $testDir }
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetPollingInterval" -Value { return 5 }
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetValidateFilenameFormat" -Value { return $true }
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetUseFileHashing" -Value { return $false }
                
                $logger = [CSVCombinerLogger]::new($null, "INFO")
                $fileProcessor = New-Object -TypeName PSObject; Add-Member -InputObject $fileProcessor -MemberType ScriptMethod -Name "GetOutputPath" -Value { return ".\output\MasterData.csv" }; Add-Member -InputObject $fileProcessor -MemberType ScriptMethod -Name "ProcessFiles" -Value { param($folder, $changes) return ".\output\MasterData.csv" }; $monitor = [CSVMonitoringService]::new($config, $logger, $fileProcessor)
                
                # Take initial snapshot first
                $monitor.TakeInitialSnapshot()
                
                # Modify the file
                Start-Sleep -Milliseconds 100  # Ensure timestamp difference
                "Name,Age,City`nJohn,30,NYC`nJane,25,LA" | Out-File -FilePath $testFile -Encoding UTF8
                
                # Check for changes
                $changes = $monitor.CheckForChanges()
                
                # Should detect modification
                $changes.ModifiedFiles.Count | Should Be 1
                $changes.ModifiedFiles[0] | Should Be "20250101120000.csv"
            }
            finally {
                if (Test-Path $testDir) {
                    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        
        It "Should detect file deletions" {
            $testDir = Join-Path ([System.IO.Path]::GetTempPath()) "monitor_delete_test_$(Get-Random)"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                $testFile = Join-Path $testDir "20250101120000.csv"
                "Name,Age`nJohn,30" | Out-File -FilePath $testFile -Encoding UTF8
                
                $config = New-Object -TypeName PSObject
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetInputFolder" -Value { return $testDir }
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetPollingInterval" -Value { return 5 }
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetValidateFilenameFormat" -Value { return $true }
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetUseFileHashing" -Value { return $false }
                
                $logger = [CSVCombinerLogger]::new($null, "INFO")
                $fileProcessor = New-Object -TypeName PSObject; Add-Member -InputObject $fileProcessor -MemberType ScriptMethod -Name "GetOutputPath" -Value { return ".\output\MasterData.csv" }; Add-Member -InputObject $fileProcessor -MemberType ScriptMethod -Name "ProcessFiles" -Value { param($folder, $changes) return ".\output\MasterData.csv" }; $monitor = [CSVMonitoringService]::new($config, $logger, $fileProcessor)
                
                # Take initial snapshot first
                $monitor.TakeInitialSnapshot()
                
                # Delete the file
                Remove-Item $testFile -Force
                
                # Check for changes
                $changes = $monitor.CheckForChanges()
                
                # Should detect deletion
                $changes.DeletedFiles.Count | Should Be 1
                $changes.DeletedFiles[0] | Should Be "20250101120000.csv"
            }
            finally {
                if (Test-Path $testDir) {
                    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    
    Context "Error Handling in Monitoring" {
        It "Should handle non-existent input directory" {
            $config = New-Object -TypeName PSObject
            Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetInputFolder" -Value { return "C:\NonExistentPath" }
            Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetPollingInterval" -Value { return 5 }
            Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetValidateFilenameFormat" -Value { return $true }
            Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetUseFileHashing" -Value { return $false }
            
            $logger = [CSVCombinerLogger]::new($null, "INFO")
            
            # Should handle non-existent directory gracefully
            { $fileProcessor = New-Object -TypeName PSObject; Add-Member -InputObject $fileProcessor -MemberType ScriptMethod -Name "GetOutputPath" -Value { return ".\output\MasterData.csv" }; Add-Member -InputObject $fileProcessor -MemberType ScriptMethod -Name "ProcessFiles" -Value { param($folder, $changes) return ".\output\MasterData.csv" }; $monitor = [CSVMonitoringService]::new($config, $logger, $fileProcessor) } | Should Not Throw
        }
        
        It "Should handle permission errors gracefully" {
            # This test may not work in all environments due to permission restrictions
            # but it tests the error handling structure
            $config = New-Object -TypeName PSObject
            Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetInputFolder" -Value { return "C:\System32" }
            Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetPollingInterval" -Value { return 5 }
            Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetValidateFilenameFormat" -Value { return $true }
            Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetUseFileHashing" -Value { return $false }
            
            $logger = [CSVCombinerLogger]::new($null, "INFO")
            
            # Should not throw exception even if permission issues occur
            { $fileProcessor = New-Object -TypeName PSObject; Add-Member -InputObject $fileProcessor -MemberType ScriptMethod -Name "GetOutputPath" -Value { return ".\output\MasterData.csv" }; Add-Member -InputObject $fileProcessor -MemberType ScriptMethod -Name "ProcessFiles" -Value { param($folder, $changes) return ".\output\MasterData.csv" }; $monitor = [CSVMonitoringService]::new($config, $logger, $fileProcessor) } | Should Not Throw
        }
        
        It "Should continue monitoring after errors" {
            $testDir = Join-Path ([System.IO.Path]::GetTempPath()) "monitor_error_test_$(Get-Random)"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                $config = New-Object -TypeName PSObject
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetInputFolder" -Value { return $testDir }
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetPollingInterval" -Value { return 5 }
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetValidateFilenameFormat" -Value { return $true }
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetUseFileHashing" -Value { return $false }
                
                $logger = [CSVCombinerLogger]::new($null, "INFO")
                $fileProcessor = New-Object -TypeName PSObject; Add-Member -InputObject $fileProcessor -MemberType ScriptMethod -Name "GetOutputPath" -Value { return ".\output\MasterData.csv" }; Add-Member -InputObject $fileProcessor -MemberType ScriptMethod -Name "ProcessFiles" -Value { param($folder, $changes) return ".\output\MasterData.csv" }; $monitor = [CSVMonitoringService]::new($config, $logger, $fileProcessor)
                
                # Simulate normal operation after initialization
                { $changes = $monitor.CheckForChanges() } | Should Not Throw
                
                # Should be able to check multiple times
                { $changes = $monitor.CheckForChanges() } | Should Not Throw
                { $changes = $monitor.CheckForChanges() } | Should Not Throw
            }
            finally {
                if (Test-Path $testDir) {
                    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

Write-Host "✅ MonitoringService module tests completed" -ForegroundColor Green

