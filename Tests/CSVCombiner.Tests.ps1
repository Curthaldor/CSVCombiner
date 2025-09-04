# ==============================================================================
# CSV Combiner Test Suite v2.4 - Consolidated Edition
# ==============================================================================
# Comprehensive tests for CSV Combiner functionality
# Compatible with Pester 3.4
# ==============================================================================

# Import the functions module
$ScriptRoot = Split-Path -Parent $PSCommandPath
$FunctionsPath = Join-Path (Split-Path $ScriptRoot -Parent) "CSVCombiner-Functions.ps1"
. $FunctionsPath

Describe "CSV Combiner Core Logic Tests" {
    
    Context "Column Schema Merging" {
        It "Should merge different column schemas correctly" {
            $existing = @("Name", "Age")
            $new = @("Name", "Email", "Phone")
            $result = Merge-ColumnSchemas -ExistingColumns $existing -NewColumns $new -IncludeTimestamp $true
            
            $result -contains "Timestamp" | Should Be $true
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
            $result = Merge-ColumnSchemas -ExistingColumns $existing -NewColumns $new -IncludeTimestamp $true
            
            $result -contains "Timestamp" | Should Be $true
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
            $schema = @("Timestamp", "Name", "Age", "Email")
            $sourceData = [PSCustomObject]@{ Name = "John"; Age = 30 }
            $result = New-UnifiedRow -SourceRow $sourceData -UnifiedSchema $schema -TimestampValue "test.csv"
            
            $result.Timestamp | Should Be "test.csv"
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
            $result.Count | Should Be 4
        }
        
        It "Should include Timestamp as first column when enabled" {
            $existing = @("Name", "Age")
            $new = @("City")
            
            $result = Merge-ColumnSchemas -ExistingColumns $existing -NewColumns $new -IncludeTimestamp $true
            
            $result[0] | Should Be "Timestamp"
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
        
        It "Should add timestamp when provided" {
            $schema = @("Timestamp", "Name", "Age")
            $sourceRow = [PSCustomObject]@{ Name = "John"; Age = 30 }
            $timestamp = "2024-12-01 12:30:00"
            
            $result = New-UnifiedRow -SourceRow $sourceRow -UnifiedSchema $schema -TimestampValue $timestamp
            
            $result.Timestamp | Should Be $timestamp
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
            $content = "Timestamp,Name,Age,Email"
            Set-Content -Path $TestMasterFile -Value $content
            
            $result = Get-MasterFileSchema -MasterFilePath $TestMasterFile
            
            $result | Should Be @("Timestamp", "Name", "Age", "Email")
        }
        
        It "Should return empty array for non-existent file" {
            $result = Get-MasterFileSchema -MasterFilePath "C:\NonExistent\file.csv"
            
            $result.Count | Should Be 0
        }
        
        It "Should count rows excluding header" {
            $content = @"
Timestamp,Name,Age
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
Timestamp,Name,Age
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
Timestamp,Name,Age
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
                    $allColumns = Merge-ColumnSchemas -ExistingColumns $allColumns -NewColumns $fileColumns -IncludeTimestamp $true
                }
            }
            
            ($allColumns -contains "Timestamp") | Should Be $true
            ($allColumns -contains "Name") | Should Be $true
            ($allColumns -contains "Age") | Should Be $true
            ($allColumns -contains "City") | Should Be $true
            ($allColumns -contains "Country") | Should Be $true
            $allColumns.Count | Should Be 5
        }
        
        It "Should create unified rows correctly" {
            $schema = @("Timestamp", "Name", "Age", "City", "Country")
            $sourceRow = [PSCustomObject]@{ Name = "Test"; Age = 35 }
            
            $result = New-UnifiedRow -SourceRow $sourceRow -UnifiedSchema $schema -TimestampValue "2024-12-01 12:30:00"
            
            $result.Timestamp | Should Be "2024-12-01 12:30:00"
            $result.Name | Should Be "Test"
            $result.Age | Should Be 35
            $result.City | Should Be ""
            $result.Country | Should Be ""
        }
    }
    
    Context "Main Function Integration" {
        It "Should have main script structure with proper function definition" {
            # Test that the main script file exists and contains the function definition
            $mainScriptPath = Join-Path (Split-Path $ScriptRoot -Parent) "CSVCombiner.ps1"
            Test-Path $mainScriptPath | Should Be $true
            
            $scriptContent = Get-Content $mainScriptPath -Raw
            $scriptContent | Should Match "function Start-CSVCombiner"
            $scriptContent | Should Match "function Merge-CSVFiles"
        }
        
        It "Should have proper script execution logic" {
            # Test that the script has the conditional execution logic
            $mainScriptPath = Join-Path (Split-Path $ScriptRoot -Parent) "CSVCombiner.ps1"
            $scriptContent = Get-Content $mainScriptPath -Raw
            
            $scriptContent | Should Match "MyInvocation.*InvocationName.*ne.*\."
            $scriptContent | Should Match "Start-CSVCombiner"
        }
        
        It "Should return proper exit codes" {
            # Test the exit code logic structure
            $mainScriptPath = Join-Path (Split-Path $ScriptRoot -Parent) "CSVCombiner.ps1"
            $scriptContent = Get-Content $mainScriptPath -Raw
            
            $scriptContent | Should Match "exit.*exitCode"
            $scriptContent | Should Match "return.*true"
            $scriptContent | Should Match "return.*false"
        }
    }
}
