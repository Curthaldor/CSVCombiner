# ==============================================================================
# CSV Combiner Tests - Pester Test Suite for v2.3.1
# ==============================================================================
# Basic integration tests for CSV Combiner functionality
# Run with: Invoke-Pester -Script CSVCombiner.Tests.ps1
# ==============================================================================

# Test the main script by running it in different scenarios

Describe "CSV Combiner Core Logic Tests" {
    
    Context "Column Schema Merging" {
        It "Should merge different column schemas correctly" {
            $existing = @("Name", "Age")
            $new = @("Name", "Email", "Phone")
            $result = Merge-ColumnSchemas -ExistingColumns $existing -NewColumns $new -IncludeTimestamp $true
            
            $result | Should -Be @("Timestamp", "Name", "Age", "Email", "Phone")
        }
        
        It "Should handle empty existing columns" {
            $existing = @()
            $new = @("Name", "Age")
            $result = Merge-ColumnSchemas -ExistingColumns $existing -NewColumns $new -IncludeTimestamp $false
            
            $result | Should -Be @("Name", "Age")
        }
        
        It "Should exclude system properties" {
            $existing = @("PSObject", "PSTypeNames", "NullData", "Name")
            $new = @("Age", "PSObject")
            $result = Merge-ColumnSchemas -ExistingColumns $existing -NewColumns $new -IncludeTimestamp $true
            
            $result | Should -Be @("Timestamp", "Name", "Age")
        }
        
        It "Should not duplicate columns" {
            $existing = @("Name", "Age")
            $new = @("Name", "Age", "Email")
            $result = Merge-ColumnSchemas -ExistingColumns $existing -NewColumns $new -IncludeTimestamp $false
            
            $result | Should -Be @("Name", "Age", "Email")
        }
    }
    
    Context "Unified Row Building" {
        It "Should create properly initialized row" {
            $schema = @("Timestamp", "Name", "Age", "Email")
            $sourceData = [PSCustomObject]@{ Name = "John"; Age = 30 }
            $result = New-UnifiedRow -SourceRow $sourceData -UnifiedSchema $schema -TimestampValue "test.csv"
            
            $result.Timestamp | Should -Be "test.csv"
            $result.Name | Should -Be "John"
            $result.Age | Should -Be 30
            $result.Email | Should -Be ""
        }
        
        It "Should handle null source row" {
            $schema = @("Name", "Age")
            $result = New-UnifiedRow -SourceRow $null -UnifiedSchema $schema
            
            $result.Name | Should -Be ""
            $result.Age | Should -Be ""
        }
        
        It "Should exclude system properties from source" {
            $schema = @("Name", "Age")
            $sourceData = [PSCustomObject]@{ 
                Name = "John"
                Age = 30
                PSObject = "system"
                PSTypeNames = "system"
            }
            $result = New-UnifiedRow -SourceRow $sourceData -UnifiedSchema $schema
            
            $result.Name | Should -Be "John"
            $result.Age | Should -Be 30
            $result.PSObject.Properties.Name | Should -Not -Contain "PSObject"
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
            
            $result.Count | Should -Be 2
            $result[0].Name | Should -Be "John"
            $result[1].Name | Should -Be "Jane"
        }
        
        It "Should handle empty data array" {
            $result = Remove-DuplicateRows -Data @()
            $result | Should -Be @()
        }
        
        It "Should handle null data" {
            $result = Remove-DuplicateRows -Data $null
            $result | Should -Be @()
        }
        
        It "Should preserve first occurrence of duplicates" {
            $data = @(
                [PSCustomObject]@{ Name = "John"; Age = 30; Timestamp = "file1.csv" },
                [PSCustomObject]@{ Name = "John"; Age = 30; Timestamp = "file2.csv" }
            )
            
            $result = Remove-DuplicateRows -Data $data -ExcludeColumns @("Timestamp")
            
            $result.Count | Should -Be 1
            $result[0].Timestamp | Should -Be "file1.csv"
        }
    }
    
    Context "Duplicate Column Name Repair" {
        It "Should fix duplicate column names" {
            $columns = @("Name", "Age", "Name", "Name", "Email")
            $result = Repair-DuplicateColumnNames -ColumnNames $columns
            
            $result | Should -Be @("Name", "Age", "Name_2", "Name_3", "Email")
        }
        
        It "Should handle empty column array" {
            $result = Repair-DuplicateColumnNames -ColumnNames @()
            $result | Should -Be @()
        }
        
        It "Should trim whitespace in column names" {
            $columns = @(" Name ", "Age", " Name ")
            $result = Repair-DuplicateColumnNames -ColumnNames $columns
            
            $result | Should -Be @("Name", "Age", "Name_2")
        }
    }
    
    Context "Data Filtering by Timestamp" {
        It "Should remove rows with specified timestamps" {
            $data = @(
                [PSCustomObject]@{ Name = "John"; Timestamp = "file1.csv" },
                [PSCustomObject]@{ Name = "Jane"; Timestamp = "file2.csv" },
                [PSCustomObject]@{ Name = "Bob"; Timestamp = "file3.csv" }
            )
            
            $result = Remove-DataByTimestamp -Data $data -TimestampsToRemove @("file1.csv", "file3.csv")
            
            $result.Count | Should -Be 1
            $result[0].Name | Should -Be "Jane"
        }
        
        It "Should handle empty data" {
            $result = Remove-DataByTimestamp -Data @() -TimestampsToRemove @("file1.csv")
            $result | Should -Be @()
        }
        
        It "Should keep rows without timestamp column" {
            $data = @(
                [PSCustomObject]@{ Name = "John" },
                [PSCustomObject]@{ Name = "Jane"; Timestamp = "file1.csv" }
            )
            
            $result = Remove-DataByTimestamp -Data $data -TimestampsToRemove @("file1.csv")
            
            $result.Count | Should -Be 1
            $result[0].Name | Should -Be "John"
        }
    }
}

Describe "Configuration Management Tests" {
    
    Context "CSVCombinerConfig Class" {
        It "Should create config from hashtable" {
            $configData = @{
                General = @{
                    InputFolder = "C:\Input"
                    OutputFolder = "C:\Output"
                    OutputBaseName = "Master"
                    MaxBackups = "10"
                    IncludeTimestamp = "true"
                    RemoveDuplicates = "false"
                    LogFile = "test.log"
                }
                Advanced = @{
                    PollingInterval = "5"
                    UseFileHashing = "true"
                    WaitForStableFile = "3000"
                    MaxPollingRetries = "5"
                }
            }
            
            $config = [CSVCombinerConfig]::FromHashtable($configData)
            
            $config.InputFolder | Should -Be "C:\Input"
            $config.OutputFolder | Should -Be "C:\Output"
            $config.OutputBaseName | Should -Be "Master"
            $config.MaxBackups | Should -Be 10
            $config.IncludeTimestamp | Should -Be $true
            $config.RemoveDuplicates | Should -Be $false
            $config.LogFile | Should -Be "test.log"
            $config.PollingInterval | Should -Be 5
            $config.UseFileHashing | Should -Be $true
            $config.WaitForStableFile | Should -Be 3000
            $config.MaxPollingRetries | Should -Be 5
        }
        
        It "Should use default values for missing settings" {
            $configData = @{
                General = @{
                    InputFolder = "C:\Input"
                    OutputFolder = "C:\Output"
                    OutputBaseName = "Master"
                }
            }
            
            $config = [CSVCombinerConfig]::FromHashtable($configData)
            
            $config.MaxBackups | Should -Be 5
            $config.PollingInterval | Should -Be 3
            $config.WaitForStableFile | Should -Be 2000
            $config.MaxPollingRetries | Should -Be 3
        }
        
        It "Should validate required fields" {
            $validConfig = [CSVCombinerConfig]::new()
            $validConfig.InputFolder = "C:\Input"
            $validConfig.OutputFolder = "C:\Output"
            $validConfig.OutputBaseName = "Master"
            
            $validConfig.IsValid() | Should -Be $true
        }
        
        It "Should fail validation for missing required fields" {
            $invalidConfig = [CSVCombinerConfig]::new()
            $invalidConfig.InputFolder = "C:\Input"
            # Missing OutputFolder and OutputBaseName
            
            $invalidConfig.IsValid() | Should -Be $false
            
            $errors = $invalidConfig.GetValidationErrors()
            $errors | Should -Contain "OutputFolder is required"
            $errors | Should -Contain "OutputBaseName is required"
        }
    }
}

Describe "File System Operations Tests" {
    
    Context "FileSystemOperations Class" {
        BeforeAll {
            # Create test directory structure
            $script:TestDrive = "TestDrive:\"
            $script:TestInput = Join-Path $TestDrive "Input"
            $script:TestOutput = Join-Path $TestDrive "Output"
            
            New-Item -Path $TestInput -ItemType Directory -Force
            New-Item -Path $TestOutput -ItemType Directory -Force
            
            # Create test CSV files
            @"
Name,Age
John,30
Jane,25
"@ | Out-File -FilePath (Join-Path $TestInput "test1.csv") -Encoding UTF8
            
            @"
Name,Email
John,john@example.com
Bob,bob@example.com
"@ | Out-File -FilePath (Join-Path $TestInput "test2.csv") -Encoding UTF8
        }
        
        It "Should find CSV files in directory" {
            $fs = [FileSystemOperations]::new()
            $files = $fs.GetCsvFiles($TestInput)
            
            $files.Count | Should -Be 2
            $files[0].Extension | Should -Be ".csv"
        }
        
        It "Should check if path exists" {
            $fs = [FileSystemOperations]::new()
            
            $fs.PathExists($TestInput) | Should -Be $true
            $fs.PathExists("C:\NonExistentPath") | Should -Be $false
        }
        
        It "Should read and write files" {
            $fs = [FileSystemOperations]::new()
            $testFile = Join-Path $TestDrive "writetest.txt"
            $content = @("Line 1", "Line 2", "Line 3")
            
            $fs.WriteFile($testFile, $content)
            $fs.PathExists($testFile) | Should -Be $true
            
            $readContent = $fs.ReadFileLines($testFile)
            $readContent | Should -Be $content
        }
        
        It "Should import CSV data correctly" {
            $fs = [FileSystemOperations]::new()
            $csvFile = Join-Path $TestInput "test1.csv"
            
            $data = $fs.ImportCsv($csvFile)
            
            $data.Count | Should -Be 2
            $data[0].Name | Should -Be "John"
            $data[0].Age | Should -Be "30"
        }
    }
}

Describe "Logger Tests" {
    
    Context "Logger Class" {
        It "Should log to console and file when file logging enabled" {
            $logFile = Join-Path "TestDrive:\" "test.log"
            $logger = [Logger]::new($logFile)
            
            $logger.WriteInfo("Test message")
            
            $logger.EnableFileLogging | Should -Be $true
            Test-Path $logFile | Should -Be $true
            
            $logContent = Get-Content $logFile
            $logContent | Should -Match "Test message"
            $logContent | Should -Match "\[INFO\]"
        }
        
        It "Should only log to console when file logging disabled" {
            $logger = [Logger]::new("")
            
            $logger.EnableFileLogging | Should -Be $false
            
            # This should not throw an error
            { $logger.WriteWarning("Test warning") } | Should -Not -Throw
        }
        
        It "Should format log messages correctly" {
            $logFile = Join-Path "TestDrive:\" "format-test.log"
            $logger = [Logger]::new($logFile)
            
            $logger.WriteError("Error message")
            
            $logContent = Get-Content $logFile
            $logContent | Should -Match "\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[ERROR\] Error message"
        }
    }
}

Describe "Integration Tests" {
    
    Context "End-to-End CSV Processing" {
        BeforeAll {
            $script:TestDrive = "TestDrive:\"
            $script:TestInput = Join-Path $TestDrive "Integration\Input"
            $script:TestOutput = Join-Path $TestDrive "Integration\Output"
            
            New-Item -Path $TestInput -ItemType Directory -Force
            New-Item -Path $TestOutput -ItemType Directory -Force
            
            # Create test files with different schemas
            @"
Name,Age,City
John,30,Seattle
Jane,25,Portland
"@ | Out-File -FilePath (Join-Path $TestInput "employees.csv") -Encoding UTF8
            
            @"
Name,Department,Salary
John,IT,50000
Bob,HR,45000
"@ | Out-File -FilePath (Join-Path $TestInput "payroll.csv") -Encoding UTF8
        }
        
        It "Should merge schemas and combine data correctly" {
            # Test the complete workflow with different schemas
            $fs = [FileSystemOperations]::new()
            $files = $fs.GetCsvFiles($TestInput)
            
            # Get all columns from all files
            $allColumns = @()
            foreach ($file in $files) {
                $data = $fs.ImportCsv($file.FullName)
                if ($data.Count -gt 0) {
                    $allColumns += $data[0].PSObject.Properties.Name
                }
            }
            
            $unifiedSchema = Merge-ColumnSchemas -NewColumns $allColumns -IncludeTimestamp $true
            
            # Verify schema contains all expected columns
            $unifiedSchema | Should -Contain "Timestamp"
            $unifiedSchema | Should -Contain "Name"
            $unifiedSchema | Should -Contain "Age"
            $unifiedSchema | Should -Contain "City"
            $unifiedSchema | Should -Contain "Department"
            $unifiedSchema | Should -Contain "Salary"
            
            # Build unified data
            $combinedData = @()
            foreach ($file in $files) {
                $fileData = $fs.ImportCsv($file.FullName)
                foreach ($row in $fileData) {
                    $unifiedRow = New-UnifiedRow -SourceRow $row -UnifiedSchema $unifiedSchema -TimestampValue $file.Name
                    $combinedData += $unifiedRow
                }
            }
            
            $combinedData.Count | Should -Be 4
            $combinedData[0].Timestamp | Should -Be "employees.csv"
            $combinedData[2].Timestamp | Should -Be "payroll.csv"
            
            # Verify empty fields are properly initialized
            $combinedData[0].Department | Should -Be ""
            $combinedData[2].City | Should -Be ""
        }
    }
}
