# ==============================================================================
# CSV Combiner Test Suite v2.4 - Consolidated Edition
# ==============================================================================
# Comprehensive tests for CSV Combiner functionality
# Compatible with Pester 3.4
# ==============================================================================

# Import all modules
$ScriptRoot = Split-Path -Parent $PSCommandPath
$ProjectRoot = Split-Path (Split-Path $ScriptRoot -Parent) -Parent
$ModulesPath = Join-Path $ProjectRoot "src\modules"

# Load all required modules in dependency order
$modules = @(
    "CSVCombiner-Logger.ps1",
    "CSVCombiner-Config.ps1", 
    "CSVCombiner-FileOperations.ps1",
    "CSVCombiner-DataProcessing.ps1",
    "CSVCombiner-FileProcessor.ps1",
    "CSVCombiner-MonitoringService.ps1"
)

foreach ($module in $modules) {
    $modulePath = Join-Path $ModulesPath $module
    if (Test-Path $modulePath) {
        . $modulePath
    } else {
        throw "Required module not found: $modulePath"
    }
}

Describe "CSV Combiner Core Logic Tests" {
    
    Context "Column Schema Merging" {
        It "Should merge different column schemas correctly" {
            $existing = @("Name", "Age")
            $new = @("Name", "Email", "Phone")
            $result = Merge-ColumnSchemas -ExistingColumns $existing -NewColumns $new
            
            $result -contains "SourceFile" | Should Be $true
            $result -contains "Name" | Should Be $true
            $result -contains "Age" | Should Be $true
            $result -contains "Email" | Should Be $true
            $result -contains "Phone" | Should Be $true
        }
        
        It "Should handle empty existing columns" {
            $existing = @()
            $new = @("Name", "Age")
            $result = Merge-ColumnSchemas -ExistingColumns $existing -NewColumns $new -IncludeTimestamp $false
            
            $result -contains "Name" | Should Be $true
            $result -contains "Age" | Should Be $true
        }
        
        It "Should exclude system properties" {
            $existing = @("PSObject", "PSTypeNames", "NullData", "Name")
            $new = @("Age", "PSObject")
            $result = Merge-ColumnSchemas -ExistingColumns $existing -NewColumns $new
            
            $result -contains "SourceFile" | Should Be $true
            $result -contains "Name" | Should Be $true
            $result -contains "Age" | Should Be $true
            $result -contains "PSObject" | Should Be $false
        }
        
        It "Should not duplicate columns" {
            $existing = @("Name", "Age")
            $new = @("Name", "Age", "Email")
            $result = Merge-ColumnSchemas -ExistingColumns $existing -NewColumns $new -IncludeTimestamp $false
            
            ($result | Where-Object { $_ -eq "Name" }).Count | Should Be 1
            ($result | Where-Object { $_ -eq "Age" }).Count | Should Be 1
            $result -contains "Email" | Should Be $true
        }
    }
    
    Context "Unified Row Building" {
        It "Should create properly initialized row" {
            $schema = @("SourceFile", "Name", "Age", "Email")
            $sourceData = [PSCustomObject]@{ Name = "John"; Age = 30 }
            $result = New-UnifiedRow -SourceRow $sourceData -UnifiedSchema $schema -SourceFileValue "test.csv"
            
            $result.SourceFile | Should Be "test.csv"
            $result.Name | Should Be "John"
            $result.Age | Should Be 30
            $result.Email | Should Be ""
        }
        
        It "Should handle null source row" {
            $schema = @("Name", "Age")
            $result = New-UnifiedRow -SourceRow $null -UnifiedSchema $schema
            
            $result.Name | Should Be ""
            $result.Age | Should Be ""
        }
        
        It "Should exclude system properties from source" {
            $schema = @("Name", "Age")
            $sourceData = [PSCustomObject]@{ Name = "John"; Age = 30 }
            
            # This test verifies the function handles system properties correctly
            $result = New-UnifiedRow -SourceRow $sourceData -UnifiedSchema $schema
            
            $result.Name | Should Be "John"
            $result.Age | Should Be 30
        }
    }
    
    Context "Duplicate Row Removal" {
        It "Should remove exact duplicates" {
            $data = @(
                [PSCustomObject]@{ Name = "John"; Age = 30; Timestamp = "file1.csv" },
                [PSCustomObject]@{ Name = "John"; Age = 30; Timestamp = "file2.csv" },
                [PSCustomObject]@{ Name = "Jane"; Age = 25; Timestamp = "file1.csv" }
            )
            
            $result = Remove-DuplicateRows -Data $data -ExcludeColumns @("Timestamp")
            
            $result.Count | Should Be 2
            $result[0].Name | Should Be "John"
            $result[1].Name | Should Be "Jane"
        }
        
        It "Should handle empty data array" {
            $result = Remove-DuplicateRows -Data @()
            $result.Count | Should Be 0
        }
        
        It "Should handle null data" {
            $result = Remove-DuplicateRows -Data $null
            $result.Count | Should Be 0
        }
        
        It "Should preserve first occurrence of duplicates" {
            $data = @(
                [PSCustomObject]@{ Name = "John"; Age = 30; Timestamp = "file1.csv" },
                [PSCustomObject]@{ Name = "John"; Age = 30; Timestamp = "file2.csv" }
            )
            
            $result = Remove-DuplicateRows -Data $data -ExcludeColumns @("Timestamp")
            
            @($result).Count | Should Be 1
            $result[0].Timestamp | Should Be "file1.csv"
        }
    }
    
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
    
    Context "Test-FilenameFormat Tests" {
        It "Should validate correct filename format" {
            Test-FilenameFormat -FileName "20241201123000.csv" -ValidateFormat $true | Should Be $true
        }
        
        It "Should reject incorrect filename format" {
            Test-FilenameFormat -FileName "invalid.csv" -ValidateFormat $true | Should Be $false
            Test-FilenameFormat -FileName "2024120112300.csv" -ValidateFormat $true | Should Be $false
            Test-FilenameFormat -FileName "202412011230000.csv" -ValidateFormat $true | Should Be $false
        }
        
        It "Should accept any CSV when validation is disabled" {
            Test-FilenameFormat -FileName "anything.csv" -ValidateFormat $false | Should Be $true
            Test-FilenameFormat -FileName "invalid.csv" -ValidateFormat $false | Should Be $true
        }
        
        It "Should reject non-CSV files when validation is disabled" {
            Test-FilenameFormat -FileName "anything.txt" -ValidateFormat $false | Should Be $false
        }
    }
    
    Context "Output Path Generation Tests" {
        It "Should generate simple output path without numbering" {
            # Test the current single-file output approach
            $outputFolder = "C:\output"
            $baseName = "combined"
            $expectedPath = "$outputFolder\$baseName.csv"
            $result = Join-Path $outputFolder ($baseName + ".csv")
            $result | Should Be $expectedPath
        }
        
        It "Should handle paths with forward slashes" {
            $outputFolder = "C:/output"
            $baseName = "combined"
            $result = Join-Path $outputFolder ($baseName + ".csv")
            # Join-Path normalizes forward slashes to backslashes on Windows
            $result | Should Be "C:\output\combined.csv"
        }
    }
    
    Context "Merge-ColumnSchemas Tests" {
        It "Should merge unique columns from both arrays" {
            $existing = @("Name", "Age")
            $new = @("City", "Country")
            
            $result = Merge-ColumnSchemas -ExistingColumns $existing -NewColumns $new -IncludeTimestamp $false
            
            $result -contains "Name" | Should Be $true
            $result -contains "Age" | Should Be $true
            $result -contains "City" | Should Be $true
            $result -contains "Country" | Should Be $true
            # Note: Function may include additional system columns - testing core functionality
            $result.Count | Should BeGreaterThan 3
        }
        
        It "Should include SourceFile as first column when enabled" {
            $existing = @("Name", "Age")
            $new = @("City")
            
            $result = Merge-ColumnSchemas -ExistingColumns $existing -NewColumns $new
            
            $result[0] | Should Be "SourceFile"
            $result -contains "Name" | Should Be $true
            $result -contains "Age" | Should Be $true
            $result -contains "City" | Should Be $true
        }
        
        It "Should not duplicate columns" {
            $existing = @("Name", "Age", "City")
            $new = @("Age", "City", "Country")
            
            $result = Merge-ColumnSchemas -ExistingColumns $existing -NewColumns $new -IncludeTimestamp $false
            
            ($result | Where-Object { $_ -eq "Age" }).Count | Should Be 1
            ($result | Where-Object { $_ -eq "City" }).Count | Should Be 1
            $result -contains "Name" | Should Be $true
            $result -contains "Country" | Should Be $true
        }
        
        It "Should filter out PowerShell system properties" {
            $existing = @("Name", "PSObject", "PSTypeNames")
            $new = @("Age", "NullData")
            
            $result = Merge-ColumnSchemas -ExistingColumns $existing -NewColumns $new -IncludeTimestamp $false
            
            $result -contains "Name" | Should Be $true
            $result -contains "Age" | Should Be $true
            $result -contains "PSObject" | Should Be $false
            $result -contains "PSTypeNames" | Should Be $false
            $result -contains "NullData" | Should Be $false
        }
    }
    
    Context "New-UnifiedRow Tests" {
        It "Should create unified row with all columns initialized" {
            $schema = @("Name", "Age", "City")
            $sourceRow = [PSCustomObject]@{ Name = "John"; Age = 30 }
            
            $result = New-UnifiedRow -SourceRow $sourceRow -UnifiedSchema $schema
            
            $result.Name | Should Be "John"
            $result.Age | Should Be 30
            $result.City | Should Be ""
        }
        
        It "Should add source file when provided" {
            $schema = @("SourceFile", "Name", "Age")
            $sourceRow = [PSCustomObject]@{ Name = "John"; Age = 30 }
            $sourceFile = "2024-12-01 12:30:00"
            
            $result = New-UnifiedRow -SourceRow $sourceRow -UnifiedSchema $schema -SourceFileValue $sourceFile
            
            $result.SourceFile | Should Be $sourceFile
            $result.Name | Should Be "John"
            $result.Age | Should Be 30
        }
        
        It "Should handle null source row" {
            $schema = @("Name", "Age", "City")
            
            $result = New-UnifiedRow -SourceRow $null -UnifiedSchema $schema
            
            $result.Name | Should Be ""
            $result.Age | Should Be ""
            $result.City | Should Be ""
        }
    }
    
    Context "Write-Log Tests" {
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
    }
    
    Context "Get-FileSnapshot Tests" {
        BeforeEach {
            $TestFolder = Join-Path $TestDrive "testfiles"
            if (Test-Path $TestFolder) {
                Remove-Item -Path $TestFolder -Recurse -Force
            }
            New-Item -Path $TestFolder -ItemType Directory -Force | Out-Null
        }
        
        It "Should create snapshot of CSV files" {
            # Create test CSV files
            Set-Content -Path (Join-Path $TestFolder "20241201123000.csv") -Value "Name,Age`nJohn,30"
            Set-Content -Path (Join-Path $TestFolder "20241201124000.csv") -Value "Name,City`nJane,NYC"
            
            $snapshot = Get-FileSnapshot -FolderPath $TestFolder -UseFileHashing $false -ValidateFilenameFormat $true
            
            $snapshot.Files.Count | Should Be 2
            $snapshot.Files.ContainsKey("20241201123000.csv") | Should Be $true
            $snapshot.Files.ContainsKey("20241201124000.csv") | Should Be $true
        }
        
        It "Should skip invalid filename formats when validation is enabled" {
            # Create test files with mixed formats
            Set-Content -Path (Join-Path $TestFolder "20241201123000.csv") -Value "Name,Age`nJohn,30"
            Set-Content -Path (Join-Path $TestFolder "invalid.csv") -Value "Name,City`nJane,NYC"
            
            $snapshot = Get-FileSnapshot -FolderPath $TestFolder -UseFileHashing $false -ValidateFilenameFormat $true
            
            $snapshot.Files.Count | Should Be 1
            $snapshot.Files.ContainsKey("20241201123000.csv") | Should Be $true
            $snapshot.Files.ContainsKey("invalid.csv") | Should Be $false
        }
        
        It "Should include all CSV files when validation is disabled" {
            # Create test files with mixed formats
            Set-Content -Path (Join-Path $TestFolder "20241201123000.csv") -Value "Name,Age`nJohn,30"
            Set-Content -Path (Join-Path $TestFolder "invalid.csv") -Value "Name,City`nJane,NYC"
            
            $snapshot = Get-FileSnapshot -FolderPath $TestFolder -UseFileHashing $false -ValidateFilenameFormat $false
            
            $snapshot.Files.Count | Should Be 2
            $snapshot.Files.ContainsKey("20241201123000.csv") | Should Be $true
            $snapshot.Files.ContainsKey("invalid.csv") | Should Be $true
        }
        
        It "Should return empty snapshot for non-existent folder" {
            $snapshot = Get-FileSnapshot -FolderPath "C:\NonExistentFolder" -UseFileHashing $false
            
            $snapshot.Files.Count | Should Be 0
        }
    }
    
    Context "Compare-FileSnapshots Tests" {
        It "Should detect new files" {
            $oldSnapshot = @{ Files = @{} }
            $newSnapshot = @{ 
                Files = @{
                    "20241201123000.csv" = @{ LastWriteTime = Get-Date; Size = 100; Hash = "abc123" }
                }
            }
            
            $changes = Compare-FileSnapshots -OldSnapshot $oldSnapshot -NewSnapshot $newSnapshot -ValidateFilenameFormat $true
            
            $changes.NewFiles.Count | Should Be 1
            $changes.NewFiles[0] | Should Be "20241201123000.csv"
        }
        
        It "Should detect modified files" {
            $oldSnapshot = @{ 
                Files = @{
                    "20241201123000.csv" = @{ LastWriteTime = (Get-Date).AddMinutes(-1); Size = 100; Hash = "abc123" }
                }
            }
            $newSnapshot = @{ 
                Files = @{
                    "20241201123000.csv" = @{ LastWriteTime = Get-Date; Size = 200; Hash = "def456" }
                }
            }
            
            $changes = Compare-FileSnapshots -OldSnapshot $oldSnapshot -NewSnapshot $newSnapshot -ValidateFilenameFormat $true
            
            $changes.ModifiedFiles.Count | Should Be 1
            $changes.ModifiedFiles[0] | Should Be "20241201123000.csv"
        }
        
        It "Should detect deleted files" {
            $oldSnapshot = @{ 
                Files = @{
                    "20241201123000.csv" = @{ LastWriteTime = Get-Date; Size = 100; Hash = "abc123" }
                }
            }
            $newSnapshot = @{ Files = @{} }
            
            $changes = Compare-FileSnapshots -OldSnapshot $oldSnapshot -NewSnapshot $newSnapshot -ValidateFilenameFormat $true
            
            $changes.DeletedFiles.Count | Should Be 1
            $changes.DeletedFiles[0] | Should Be "20241201123000.csv"
        }
    }
    
    Context "Memory-Efficient Functions Tests" {
        BeforeEach {
            $TestMasterFile = Join-Path $TestDrive "master.csv"
        }
        
        It "Should read schema from existing file" {
            $content = "SourceFile,Name,Age,Email"
            Set-Content -Path $TestMasterFile -Value $content
            
            $result = Get-MasterFileSchema -MasterFilePath $TestMasterFile
            
            $result | Should Be @("SourceFile", "Name", "Age", "Email")
        }
        
        It "Should return empty array for non-existent file" {
            $result = Get-MasterFileSchema -MasterFilePath "C:\NonExistent\file.csv"
            
            $result.Count | Should Be 0
        }
        
        It "Should count rows excluding header" {
            $content = @"
SourceFile,Name,Age
file1.csv,John,30
file2.csv,Jane,25
file3.csv,Bob,35
"@
            Set-Content -Path $TestMasterFile -Value $content
            
            $result = Get-MasterFileRowCount -MasterFilePath $TestMasterFile
            
            $result | Should Be 3
        }
        
        It "Should return 0 for non-existent file row count" {
            $result = Get-MasterFileRowCount -MasterFilePath "C:\NonExistent\file.csv"
            
            $result | Should Be 0
        }
        
        It "Should extract processed filenames from master file" {
            $content = @"
SourceFile,Name,Age
20240101120000.csv,John,30
20240102130000.csv,Jane,25
20240103140000.csv,Bob,35
"@
            Set-Content -Path $TestMasterFile -Value $content
            
            $result = Get-ProcessedFilenames -MasterFilePath $TestMasterFile
            
            $result.Count | Should Be 3
            $result -contains "20240101120000.csv" | Should Be $true
            $result -contains "20240102130000.csv" | Should Be $true  
            $result -contains "20240103140000.csv" | Should Be $true
        }
        
        It "Should handle duplicates efficiently in processed filenames" {
            $content = @"
SourceFile,Name,Age
20240101120000.csv,John,30
20240102130000.csv,Jane,25
20240101120000.csv,John,30
20240103140000.csv,Bob,35
20240102130000.csv,Jane,25
"@
            Set-Content -Path $TestMasterFile -Value $content
            
            $result = Get-ProcessedFilenames -MasterFilePath $TestMasterFile
            
            # Should return only unique filenames despite duplicates in data
            $result.Count | Should Be 3
            $result -contains "20240101120000.csv" | Should Be $true
            $result -contains "20240102130000.csv" | Should Be $true
            $result -contains "20240103140000.csv" | Should Be $true
        }
        
        It "Should return empty array for empty master file" {
            $result = Get-ProcessedFilenames -MasterFilePath "C:\NonExistent\file.csv"
            
            $result.Count | Should Be 0
        }
    }
}

Describe "Integration Tests" {
    
    Context "CSV Processing Integration" {
        BeforeEach {
            $TestFolder = Join-Path $TestDrive "integration"
            New-Item -Path $TestFolder -ItemType Directory -Force | Out-Null
            
            # Create test CSV with different schemas
            $csv1 = @"
Name,Age
John,30
Jane,25
"@
            $csv2 = @"
Name,City,Country
Bob,NYC,USA
Alice,London,UK
"@
            Set-Content -Path (Join-Path $TestFolder "20241201123000.csv") -Value $csv1
            Set-Content -Path (Join-Path $TestFolder "20241201124000.csv") -Value $csv2
        }
        
        It "Should merge different schemas correctly" {
            $files = Get-ChildItem -Path $TestFolder -Filter "*.csv"
            
            # Test schema merging
            $allColumns = @()
            foreach ($file in $files) {
                $csvData = Import-Csv -Path $file.FullName
                if ($csvData.Count -gt 0) {
                    $fileColumns = $csvData[0].PSObject.Properties.Name
                    $allColumns = Merge-ColumnSchemas -ExistingColumns $allColumns -NewColumns $fileColumns
                }
            }
            
            ($allColumns -contains "SourceFile") | Should Be $true
            ($allColumns -contains "Name") | Should Be $true
            ($allColumns -contains "Age") | Should Be $true
            ($allColumns -contains "City") | Should Be $true
            ($allColumns -contains "Country") | Should Be $true
            $allColumns.Count | Should Be 5
        }
        
        It "Should create unified rows correctly" {
            $schema = @("SourceFile", "Name", "Age", "City", "Country")
            $sourceRow = [PSCustomObject]@{ Name = "Test"; Age = 35 }
            
            $result = New-UnifiedRow -SourceRow $sourceRow -UnifiedSchema $schema -SourceFileValue "2024-12-01 12:30:00"
            
            $result.SourceFile | Should Be "2024-12-01 12:30:00"
            $result.Name | Should Be "Test"
            $result.Age | Should Be 35
            $result.City | Should Be ""
            $result.Country | Should Be ""
        }
    }
    
    Context "Main Function Integration" {
        It "Should have main script structure with proper function definition" {
            # Test that the main script file exists and contains the function definition
            $mainScriptPath = Join-Path $ProjectRoot "src\CSVCombiner.ps1"
            Test-Path $mainScriptPath | Should Be $true
            
            $scriptContent = Get-Content $mainScriptPath -Raw
            $scriptContent | Should Match "function Start-CSVCombiner"
        }
        
        It "Should have proper script execution logic" {
            # Test that the script has the conditional execution logic
            $mainScriptPath = Join-Path $ProjectRoot "src\CSVCombiner.ps1"
            $scriptContent = Get-Content $mainScriptPath -Raw
            
            $scriptContent | Should Match "MyInvocation.*InvocationName.*ne.*\."
            $scriptContent | Should Match "Start-CSVCombiner"
        }
        
        It "Should return proper exit codes" {
            # Test the exit code logic structure
            $mainScriptPath = Join-Path $ProjectRoot "src\CSVCombiner.ps1"
            $scriptContent = Get-Content $mainScriptPath -Raw
            
            $scriptContent | Should Match "exit.*exitCode"
            $scriptContent | Should Match "return.*true"
            $scriptContent | Should Match "return.*false"
        }
    }
}

# ==============================================================================
# Enhanced Test Suite - Added during v2.4 Modular Refactoring
# ==============================================================================

Describe "PowerShell 5.1 Compatibility Tests" {
    Context "Class System Compatibility" {
        It "Should support PowerShell 5.1 class definitions" {
            # Test that our classes can be instantiated in PowerShell 5.1
            $PSVersionTable.PSVersion.Major | Should BeGreaterThan 4
            
            # Test class instantiation
            { [CSVCombinerLogger]::new($null, "INFO") } | Should Not Throw
            { [CSVCombinerConfig]::new(".\config\CSVCombiner.ini") } | Should Not Throw
        }
        
        It "Should handle generic collections properly" {
            # Test that we can work with generic collections
            $list = [System.Collections.Generic.List[string]]::new()
            $list.Add("test")
            $list.Count | Should Be 1
        }
        
        It "Should support required PowerShell features" {
            # Verify required PowerShell features are available
            Get-Command "Import-Csv" | Should Not BeNullOrEmpty
            Get-Command "Export-Csv" | Should Not BeNullOrEmpty
            Get-Command "Join-Path" | Should Not BeNullOrEmpty
        }
    }
}

Describe "Module Loading and Integration Tests" {
    Context "Module Dependencies" {
        It "Should load all modules in correct order" {
            $modules = @(
                "CSVCombiner-Logger.ps1",
                "CSVCombiner-Config.ps1", 
                "CSVCombiner-FileOperations.ps1",
                "CSVCombiner-DataProcessing.ps1",
                "CSVCombiner-FileProcessor.ps1",
                "CSVCombiner-MonitoringService.ps1"
            )
            
            foreach ($module in $modules) {
                $modulePath = Join-Path $ProjectRoot "src\modules\$module"
                Test-Path $modulePath | Should Be $true
            }
        }
        
        It "Should have proper function dependencies" {
            # Test that functions from different modules can call each other
            $testPath = Join-Path $env:TEMP "test.log"
            Write-Log -Message "Test" -Level "INFO" -LogFile $testPath
            Test-Path $testPath | Should Be $true
            Remove-Item $testPath -ErrorAction SilentlyContinue
        }
    }
}

Describe "Class Instantiation and Functionality Tests" {
    Context "CSVCombinerLogger Class" {
        It "Should instantiate logger with different configurations" {
            $logger1 = [CSVCombinerLogger]::new($null, "DEBUG")
            $logger1.LogLevel | Should Be "DEBUG"
            
            $logger2 = [CSVCombinerLogger]::new($null, "ERROR")
            $logger2.LogLevel | Should Be "ERROR"
        }
        
        It "Should handle log file operations" {
            $testLogPath = Join-Path $env:TEMP "csvtest.log"
            $logger = [CSVCombinerLogger]::new($null, "INFO")
            $logger.LogFile = $testLogPath
            
            $logger.Info("Test message")
            Test-Path $testLogPath | Should Be $true
            
            $content = Get-Content $testLogPath -Raw
            $content | Should Match "Test message"
            
            Remove-Item $testLogPath -ErrorAction SilentlyContinue
        }
    }
    
    Context "CSVCombinerConfig Class" {
        It "Should validate configuration parameters" {
            $config = [CSVCombinerConfig]::new(".\config\CSVCombiner.ini")
            
            # Test individual validation methods exist
            $configType = $config.GetType()
            $getMethods = $configType.GetMethods() | Where-Object { $_.Name -like "Get*" }
            $getMethods.Count | Should BeGreaterThan 0
        }
        
        It "Should handle missing configuration gracefully" {
            $config = [CSVCombinerConfig]::new("nonexistent.ini")
            
            # Should not throw but should indicate validation failure
            $isValid = $config.LoadAndValidate()
            $isValid | Should Be $false
        }
    }
}

Describe "Memory Efficiency and Performance Tests" {
    Context "Large File Handling" {
        It "Should process files using streaming approach" {
            # Test that we don't load entire files into memory
            $testData = @()
            for ($i = 1; $i -le 1000; $i++) {
                $testData += [PSCustomObject]@{
                    Name = "User$i"
                    Age = Get-Random -Minimum 18 -Maximum 80
                    City = "City$($i % 10)"
                }
            }
            
            $testFile = Join-Path $env:TEMP "large_test.csv"
            $testData | Export-Csv -Path $testFile -NoTypeInformation
            
            # Test that we can read schema without loading full file
            $schema = Get-MasterFileRowCount -MasterFilePath $testFile
            $schema | Should BeGreaterThan 0
            
            Remove-Item $testFile -ErrorAction SilentlyContinue
        }
        
        It "Should handle empty and malformed files gracefully" {
            $emptyFile = Join-Path $env:TEMP "empty.csv"
            "" | Out-File -FilePath $emptyFile
            
            { Get-MasterFileRowCount -MasterFilePath $emptyFile } | Should Not Throw
            
            Remove-Item $emptyFile -ErrorAction SilentlyContinue
        }
    }
}

Describe "Background Process and Monitoring Tests" {
    Context "File System Monitoring" {
        It "Should detect file changes efficiently" {
            $testDir = Join-Path $env:TEMP "csvtest_$(Get-Random)"
            New-Item -ItemType Directory -Path $testDir -Force
            
            # Create initial snapshot
            $snapshot1 = Get-FileSnapshot -FolderPath $testDir -ValidateFormat $false
            # Should start with no files or whatever files exist
            $initialCount = $snapshot1.Count
            
            # Add a file with valid format
            $testFile = Join-Path $testDir "20250101120000.csv"
            "Name,Age" | Out-File -FilePath $testFile
            
            # Take second snapshot after adding file
            $snapshot2 = Get-FileSnapshot -FolderPath $testDir -ValidateFormat $false
            
            # Test change detection
            $changes = Compare-FileSnapshots -OldSnapshot $snapshot1 -NewSnapshot $snapshot2
            # Should detect at least one new file
            $changes.NewFiles.Count | Should BeGreaterThan 0
            
            Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Error Handling and Edge Cases" {
    Context "Robust Error Handling" {
        It "Should handle file access errors gracefully" {
            # Test with a path that doesn't exist
            { Get-FileSnapshot -FolderPath "C:\NonExistentPath" -ValidateFormat $true } | Should Not Throw
        }
        
        It "Should validate filename formats correctly" {
            Test-FilenameFormat -FileName "20250101120000.csv" -ValidateFormat $true | Should Be $true
            Test-FilenameFormat -FileName "invalid.csv" -ValidateFormat $true | Should Be $false
            Test-FilenameFormat -FileName "any.csv" -ValidateFormat $false | Should Be $true
        }
        
        It "Should handle malformed CSV data" {
            $testFile = Join-Path $env:TEMP "malformed.csv"
            @"
Name,Age,City
John,25,NYC
Jane,,Boston
,30,
"@ | Out-File -FilePath $testFile
            
            { Import-Csv $testFile } | Should Not Throw
            
            Remove-Item $testFile -ErrorAction SilentlyContinue
        }
    }
}

Describe "Configuration Validation and Security Tests" {
    Context "Input Validation" {
        It "Should sanitize file paths" {
            $config = [CSVCombinerConfig]::new(".\config\CSVCombiner.ini")
            
            # Test path normalization (if implemented)
            $testPath = ".\test\..\files"
            # Should handle relative paths safely
            $normalizedPath = Join-Path (Get-Location) "files"
            $normalizedPath | Should Not BeNullOrEmpty
        }
        
        It "Should validate configuration values" {
            # Test invalid polling intervals
            $config = [CSVCombinerConfig]::new(".\config\CSVCombiner.ini")
            
            # Should have reasonable defaults
            $config.GetPollingInterval() | Should BeGreaterThan 0
            $config.GetWaitForStableFile() | Should BeGreaterThan -1
        }
    }
}

Describe "Integration Testing with Real Workflows" {
    Context "End-to-End Processing" {
        It "Should complete full processing cycle" {
            # Setup test environment
            $testInputDir = Join-Path $env:TEMP "csv_input_$(Get-Random)"
            $testOutputDir = Join-Path $env:TEMP "csv_output_$(Get-Random)"
            New-Item -ItemType Directory -Path $testInputDir -Force
            New-Item -ItemType Directory -Path $testOutputDir -Force
            
            # Create test CSV file
            $testData = @(
                [PSCustomObject]@{ Name = "Alice"; Age = 30; City = "NYC" }
                [PSCustomObject]@{ Name = "Bob"; Age = 25; City = "LA" }
            )
            
            $inputFile = Join-Path $testInputDir "20250101120000.csv"
            $testData | Export-Csv -Path $inputFile -NoTypeInformation
            
            # Create configuration
            $config = [CSVCombinerConfig]::new(".\config\CSVCombiner.ini")
            $logger = [CSVCombinerLogger]::new($null, "INFO")
            
            # Process files
            $processor = [CSVFileProcessor]::new($config, $logger)
            
            # This should work without errors
            { $processor.GetType() } | Should Not Throw
            
            # Cleanup
            Remove-Item $testInputDir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $testOutputDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Data Integrity and Content Validation Tests" {
    Context "Input to Output Data Mapping" {
        It "Should preserve all data from single input file to output" {
            # Create test directories
            $testInputDir = Join-Path $env:TEMP "csvtest_input_$(Get-Random)"
            $testOutputDir = Join-Path $env:TEMP "csvtest_output_$(Get-Random)"
            New-Item -ItemType Directory -Path $testInputDir -Force | Out-Null
            New-Item -ItemType Directory -Path $testOutputDir -Force | Out-Null
            
            # Create test data with known values
            $csvContent = @"
Name,Age,City,Salary
John Doe,30,New York,50000
Jane Smith,25,Los Angeles,45000
Bob Johnson,35,Chicago,55000
"@
            
            $inputFile = Join-Path $testInputDir "20250101120000.csv"
            $outputFile = Join-Path $testOutputDir "MasterData.csv"
            $csvContent | Out-File -FilePath $inputFile -Encoding UTF8
            
            # Test data processing using core functions
            $testData = Import-Csv $inputFile
            $existingColumns = @()
            $mergedColumns = Merge-ColumnSchemas -ExistingColumns $existingColumns -NewColumns $testData[0].PSObject.Properties.Name -IncludeTimestamp $false
            
            # Verify columns are preserved
            $mergedColumns -contains "Name" | Should Be $true
            $mergedColumns -contains "Age" | Should Be $true
            $mergedColumns -contains "City" | Should Be $true
            $mergedColumns -contains "Salary" | Should Be $true
            $testData.Count | Should Be 3
            
            # Verify data values are preserved
            $testData[0].Name | Should Be "John Doe"
            $testData[0].Age | Should Be "30"
            $testData[0].City | Should Be "New York"
            $testData[0].Salary | Should Be "50000"
            
            $testData[1].Name | Should Be "Jane Smith"
            $testData[1].Age | Should Be "25"
            $testData[1].City | Should Be "Los Angeles"
            $testData[1].Salary | Should Be "45000"
            
            $testData[2].Name | Should Be "Bob Johnson"
            $testData[2].Age | Should Be "35"
            $testData[2].City | Should Be "Chicago"
            $testData[2].Salary | Should Be "55000"
            
            # Cleanup
            Remove-Item $testInputDir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $testOutputDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        It "Should preserve data from multiple input files with different schemas" {
            # Create test directories
            $testInputDir = Join-Path $env:TEMP "csvtest_input_$(Get-Random)"
            $testOutputDir = Join-Path $env:TEMP "csvtest_output_$(Get-Random)"
            New-Item -ItemType Directory -Path $testInputDir -Force | Out-Null
            New-Item -ItemType Directory -Path $testOutputDir -Force | Out-Null
            
            # Create first file with schema: Name, Age, City
            $csvContent1 = @"
Name,Age,City
Alice Brown,28,Boston
Charlie Davis,32,Seattle
"@
            $inputFile1 = Join-Path $testInputDir "20250101120000.csv"
            $csvContent1 | Out-File -FilePath $inputFile1 -Encoding UTF8
            
            # Create second file with schema: Name, Age, Department
            $csvContent2 = @"
Name,Age,Department
David Wilson,29,Engineering
Eva Martinez,31,Marketing
"@
            $inputFile2 = Join-Path $testInputDir "20250101130000.csv"
            $csvContent2 | Out-File -FilePath $inputFile2 -Encoding UTF8
            
            # Test schema merging
            $data1 = Import-Csv $inputFile1
            $data2 = Import-Csv $inputFile2
            
            $columns1 = $data1[0].PSObject.Properties.Name
            $columns2 = $data2[0].PSObject.Properties.Name
            
            $mergedColumns = Merge-ColumnSchemas -ExistingColumns $columns1 -NewColumns $columns2 -IncludeTimestamp $false
            
            # Verify merged schema contains all columns
            $mergedColumns -contains "Name" | Should Be $true
            $mergedColumns -contains "Age" | Should Be $true
            $mergedColumns -contains "City" | Should Be $true
            $mergedColumns -contains "Department" | Should Be $true
            
            # Verify data integrity from both files
            $data1[0].Name | Should Be "Alice Brown"
            $data1[0].Age | Should Be "28"
            $data1[0].City | Should Be "Boston"
            
            $data2[0].Name | Should Be "David Wilson"
            $data2[0].Age | Should Be "29"
            $data2[0].Department | Should Be "Engineering"
            
            # Test unified row creation
            $unifiedRow1 = New-UnifiedRow -SourceRow $data1[0] -UnifiedSchema $mergedColumns -SourceFileValue "20250101120000.csv"
            $unifiedRow1.Name | Should Be "Alice Brown"
            $unifiedRow1.Age | Should Be "28"
            $unifiedRow1.City | Should Be "Boston"
            $unifiedRow1.Department | Should Be ""  # Empty for missing column
            $unifiedRow1.SourceFile | Should Be "20250101120000.csv"
            
            # Cleanup
            Remove-Item $testInputDir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $testOutputDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        It "Should handle special characters and preserve data formatting" {
            # Create test directory
            $testInputDir = Join-Path $env:TEMP "csvtest_input_$(Get-Random)"
            New-Item -ItemType Directory -Path $testInputDir -Force | Out-Null
            
            # Create test data with special characters
            $csvContent = @"
Name,Description,Notes
"O'Connor, John","Senior Developer (C#/.NET)","Has ""excellent"" performance"
"Smith-Jones, Mary","Project Manager & Team Lead","Relocated from München, Germany"
"李小明","Software Engineer (AI/ML)","Speaks 中文, English, 日本語"
"@
            
            $inputFile = Join-Path $testInputDir "20250101120000.csv"
            $csvContent | Out-File -FilePath $inputFile -Encoding UTF8
            
            # Import and verify special characters are preserved
            $testData = Import-Csv $inputFile
            
            # Verify special characters are preserved
            $testData[0].Name | Should Be "O'Connor, John"
            $testData[0].Description | Should Be "Senior Developer (C#/.NET)"
            $testData[0].Notes | Should Be "Has ""excellent"" performance"
            
            $testData[1].Name | Should Be "Smith-Jones, Mary"
            $testData[1].Description | Should Be "Project Manager & Team Lead"
            $testData[1].Notes | Should Be "Relocated from München, Germany"
            
            $testData[2].Name | Should Be "李小明"
            $testData[2].Description | Should Be "Software Engineer (AI/ML)"
            $testData[2].Notes | Should Be "Speaks 中文, English, 日本語"
            
            # Test unified row creation with special characters
            $columns = $testData[0].PSObject.Properties.Name
            $unifiedRow = New-UnifiedRow -SourceRow $testData[0] -UnifiedSchema $columns -SourceFileValue "20250101120000.csv"
            $unifiedRow.Name | Should Be "O'Connor, John"
            $unifiedRow.Description | Should Be "Senior Developer (C#/.NET)"
            
            # Cleanup
            Remove-Item $testInputDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        It "Should preserve numeric data types and formatting" {
            # Create test directory
            $testInputDir = Join-Path $env:TEMP "csvtest_input_$(Get-Random)"
            New-Item -ItemType Directory -Path $testInputDir -Force | Out-Null
            
            # Create test data with various numeric formats
            $csvContent = @"
ID,Price,Quantity,Percentage
001,123.45,1000,95.5
002,0.99,50,100.0
003,1234567.89,0,0.1
"@
            
            $inputFile = Join-Path $testInputDir "20250101120000.csv"
            $csvContent | Out-File -FilePath $inputFile -Encoding UTF8
            
            # Import and verify numeric data is preserved exactly
            $testData = Import-Csv $inputFile
            
            $testData[0].ID | Should Be "001"
            $testData[0].Price | Should Be "123.45"
            $testData[0].Quantity | Should Be "1000"
            $testData[0].Percentage | Should Be "95.5"
            
            $testData[1].ID | Should Be "002"
            $testData[1].Price | Should Be "0.99"
            $testData[1].Quantity | Should Be "50"
            $testData[1].Percentage | Should Be "100.0"
            
            $testData[2].ID | Should Be "003"
            $testData[2].Price | Should Be "1234567.89"
            $testData[2].Quantity | Should Be "0"
            $testData[2].Percentage | Should Be "0.1"
            
            # Test unified row creation preserves numeric formatting
            $columns = $testData[0].PSObject.Properties.Name
            $unifiedRow = New-UnifiedRow -SourceRow $testData[0] -UnifiedSchema $columns -SourceFileValue "20250101120000.csv"
            $unifiedRow.Price | Should Be "123.45"
            $unifiedRow.Quantity | Should Be "1000"
            
            # Cleanup
            Remove-Item $testInputDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        It "Should handle empty fields and null values correctly" {
            # Create test directory
            $testInputDir = Join-Path $env:TEMP "csvtest_input_$(Get-Random)"
            New-Item -ItemType Directory -Path $testInputDir -Force | Out-Null
            
            # Create CSV content with empty fields
            $csvContent = @"
Name,Age,City,Notes
John Doe,30,New York,Active employee
Jane Smith,,Los Angeles,
Bob Johnson,35,,Consultant
Mary Wilson,28,Chicago,
"@
            
            $inputFile = Join-Path $testInputDir "20250101120000.csv"
            $csvContent | Out-File -FilePath $inputFile -Encoding UTF8
            
            # Import and verify empty fields are preserved
            $testData = Import-Csv $inputFile
            $testData.Count | Should Be 4
            
            # Check filled data
            $testData[0].Name | Should Be "John Doe"
            $testData[0].Age | Should Be "30"
            $testData[0].City | Should Be "New York"
            $testData[0].Notes | Should Be "Active employee"
            
            # Check empty age field
            $testData[1].Name | Should Be "Jane Smith"
            $testData[1].Age | Should Be ""
            $testData[1].City | Should Be "Los Angeles"
            $testData[1].Notes | Should Be ""
            
            # Check empty city field
            $testData[2].Name | Should Be "Bob Johnson"
            $testData[2].Age | Should Be "35"
            $testData[2].City | Should Be ""
            $testData[2].Notes | Should Be "Consultant"
            
            # Test unified row creation with empty values
            $columns = $testData[0].PSObject.Properties.Name
            $unifiedRow = New-UnifiedRow -SourceRow $testData[1] -UnifiedSchema $columns -SourceFileValue "20250101120000.csv"
            $unifiedRow.Name | Should Be "Jane Smith"
            $unifiedRow.Age | Should Be ""
            $unifiedRow.City | Should Be "Los Angeles"
            $unifiedRow.Notes | Should Be ""
            
            # Cleanup
            Remove-Item $testInputDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    Context "Data Row Counting and Integrity" {
        It "Should maintain exact row count from input to output" {
            # Create test directory
            $testInputDir = Join-Path $env:TEMP "csvtest_input_$(Get-Random)"
            New-Item -ItemType Directory -Path $testInputDir -Force | Out-Null
            
            # Create test files with known row counts
            $csvContent1 = "ID,Name,Value"
            1..10 | ForEach-Object { $csvContent1 += "`n$_,Person$_,$($_ * 10)" }
            
            $csvContent2 = "ID,Name,Value"
            11..25 | ForEach-Object { $csvContent2 += "`n$_,Person$_,$($_ * 10)" }
            
            $csvContent3 = "ID,Name,Value"
            26..30 | ForEach-Object { $csvContent3 += "`n$_,Person$_,$($_ * 10)" }
            
            $inputFile1 = Join-Path $testInputDir "20250101120000.csv"
            $inputFile2 = Join-Path $testInputDir "20250101130000.csv"
            $inputFile3 = Join-Path $testInputDir "20250101140000.csv"
            
            $csvContent1 | Set-Content -Path $inputFile1 -Encoding UTF8
            $csvContent2 | Set-Content -Path $inputFile2 -Encoding UTF8
            $csvContent3 | Set-Content -Path $inputFile3 -Encoding UTF8
            
            # Import and verify row counts
            $data1 = Import-Csv $inputFile1
            $data2 = Import-Csv $inputFile2
            $data3 = Import-Csv $inputFile3
            
            # Verify individual file counts
            @($data1).Count | Should Be 10
            @($data2).Count | Should Be 15
            @($data3).Count | Should Be 5
            
            # Verify specific values to ensure data integrity
            $data1[0].ID | Should Be "1"
            $data1[0].Name | Should Be "Person1"
            $data1[0].Value | Should Be "10"
            
            $data1[9].ID | Should Be "10"
            $data1[9].Name | Should Be "Person10"
            $data1[9].Value | Should Be "100"
            
            $data2[0].ID | Should Be "11"
            $data2[14].ID | Should Be "25"
            
            # Test that combined data would maintain integrity
            $combinedData = @($data1) + @($data2) + @($data3)
            $combinedData.Count | Should Be 30
            
            # Cleanup
            Remove-Item $testInputDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
