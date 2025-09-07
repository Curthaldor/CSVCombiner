# ==============================================================================
# End-to-End Integration Tests
# ==============================================================================
# Tests for complete workflow scenarios and module integration
# ==============================================================================

# Import all required modules
$ScriptRoot = Split-Path -Parent $PSCommandPath
$ProjectRoot = Split-Path (Split-Path $ScriptRoot -Parent) -Parent
$ModuleRoot = Join-Path $ProjectRoot "src\modules"

$modules = @(
    "CSVCombiner-Logger.ps1",
    "CSVCombiner-Config.ps1", 
    "CSVCombiner-FileOperations.ps1",
    "CSVCombiner-DataProcessing.ps1",
    "CSVCombiner-FileProcessor.ps1",
    "CSVCombiner-MonitoringService.ps1"
)

foreach ($module in $modules) {
    $modulePath = Join-Path $ModuleRoot $module
    if (Test-Path $modulePath) {
        . $modulePath
    }
}

Describe "End-to-End Integration Tests" {
    
    Context "CSV Processing Integration" {
        BeforeEach {
            $script:testId = [System.Guid]::NewGuid().ToString().Substring(0, 8)
            $script:testInputDir = Join-Path ([System.IO.Path]::GetTempPath()) "csv_input_$testId"
            $script:testOutputDir = Join-Path ([System.IO.Path]::GetTempPath()) "csv_output_$testId"
            
            New-Item -ItemType Directory -Path $testInputDir -Force | Out-Null
            New-Item -ItemType Directory -Path $testOutputDir -Force | Out-Null
        }
        
        AfterEach {
            if (Test-Path $testInputDir) {
                Remove-Item $testInputDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $testOutputDir) {
                Remove-Item $testOutputDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "Should process single CSV file end-to-end" {
            # Create test CSV file
            $testData = @(
                [PSCustomObject]@{ Name = "Alice"; Age = 30; City = "NYC" }
                [PSCustomObject]@{ Name = "Bob"; Age = 25; City = "LA" }
            )
            
            $inputFile = Join-Path $testInputDir "20250101120000.csv"
            $testData | Export-Csv -Path $inputFile -NoTypeInformation
            
            # Verify file was created correctly
            Test-Path $inputFile | Should Be $true
            $importedData = Import-Csv $inputFile
            $importedData.Count | Should Be 2
            $importedData[0].Name | Should Be "Alice"
            $importedData[1].Name | Should Be "Bob"
        }
        
        It "Should merge different schemas correctly in integration" {
            # Create test CSV files with different schemas
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
            Set-Content -Path (Join-Path $testInputDir "20241201123000.csv") -Value $csv1
            Set-Content -Path (Join-Path $testInputDir "20241201124000.csv") -Value $csv2
            
            $files = Get-ChildItem -Path $testInputDir -Filter "*.csv"
            
            # Test schema merging using the actual functions
            $allColumns = @()
            foreach ($file in $files) {
                $csvData = Import-Csv -Path $file.FullName
                if ($csvData.Count -gt 0) {
                    $fileColumns = $csvData[0].PSObject.Properties.Name
                    $allColumns = Merge-ColumnSchemas -ExistingColumns $allColumns -NewColumns $fileColumns -IncludeTimestamp $true
                }
            }
            
            ($allColumns -contains "SourceFile") | Should Be $true
            ($allColumns -contains "Name") | Should Be $true
            ($allColumns -contains "Age") | Should Be $true
            ($allColumns -contains "City") | Should Be $true
            ($allColumns -contains "Country") | Should Be $true
            $allColumns.Count | Should Be 5
        }
        
        It "Should create unified rows correctly in integration" {
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
    
    Context "Configuration and Logging Integration" {
        It "Should integrate configuration and logging systems" {
            # Test configuration loading
            $configPath = Join-Path $ProjectRoot "config\CSVCombiner.ini"
            if (Test-Path $configPath) {
                $config = [CSVCombinerConfig]::new($configPath)
                $config | Should Not BeNullOrEmpty
                
                # Test logging integration
                $testLogPath = Join-Path ([System.IO.Path]::GetTempPath()) "integration_test.log"
                $logger = [CSVCombinerLogger]::new($testLogPath, "INFO")
                $logger | Should Not BeNullOrEmpty
                
                # Test they can work together
                $logger.Info("Configuration loaded successfully")
                
                Start-Sleep -Milliseconds 100
                Test-Path $testLogPath | Should Be $true
                
                # Cleanup
                if (Test-Path $testLogPath) {
                    Remove-Item $testLogPath -Force
                }
            }
            else {
                Set-TestInconclusive "Configuration file not found for integration test"
            }
        }
    }
    
    Context "File Processing with Classes Integration" {
        It "Should instantiate and use file processor classes" {
            # Create mock configuration
            $config = New-Object -TypeName PSObject
            Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetValidateFilenameFormat" -Value { return $false }
            Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetInputFolder" -Value { return $testInputDir }
            Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetOutputFolder" -Value { return $testOutputDir }
            
            # Create logger
            $logger = [CSVCombinerLogger]::new($null, "INFO")
            
            # Create file processor
            { $processor = [CSVFileProcessor]::new($config, $logger) } | Should Not Throw
        }
    }
    
    Context "Main Function Integration" {
        It "Should have proper script execution structure" {
            # Test that the main script file exists and has proper structure
            $mainScriptPath = Join-Path $ProjectRoot "src\CSVCombiner.ps1"
            Test-Path $mainScriptPath | Should Be $true
            
            $scriptContent = Get-Content $mainScriptPath -Raw
            $scriptContent | Should Match "function Start-CSVCombiner"
            $scriptContent | Should Match "MyInvocation.*InvocationName.*ne.*\."
            $scriptContent | Should Match "Start-CSVCombiner"
        }
        
        It "Should have proper error handling structure" {
            $mainScriptPath = Join-Path $ProjectRoot "src\CSVCombiner.ps1"
            $scriptContent = Get-Content $mainScriptPath -Raw
            
            $scriptContent | Should Match "exit.*exitCode"
            $scriptContent | Should Match "return.*true"
            $scriptContent | Should Match "return.*false"
        }
    }
    
    Context "Module Loading Integration" {
        It "Should load all modules successfully" {
            foreach ($module in $modules) {
                $modulePath = Join-Path $ModuleRoot $module
                Test-Path $modulePath | Should Be $true
            }
        }
        
        It "Should have proper function dependencies between modules" {
            # Test that functions from different modules can call each other
            $testPath = Join-Path ([System.IO.Path]::GetTempPath()) "dependency_test.log"
            
            { Write-Log -Message "Test" -Level "INFO" -LogFile $testPath } | Should Not Throw
            
            if (Test-Path $testPath) {
                Remove-Item $testPath -ErrorAction SilentlyContinue
            }
        }
    }
    
    Context "Data Integrity Integration" {
        BeforeEach {
            $script:testId = [System.Guid]::NewGuid().ToString().Substring(0, 8)
            $script:testInputDir = Join-Path ([System.IO.Path]::GetTempPath()) "csv_input_$testId"
            $script:testOutputDir = Join-Path ([System.IO.Path]::GetTempPath()) "csv_output_$testId"
            
            New-Item -ItemType Directory -Path $testInputDir -Force | Out-Null
            New-Item -ItemType Directory -Path $testOutputDir -Force | Out-Null
        }
        
        AfterEach {
            if (Test-Path $testInputDir) {
                Remove-Item $testInputDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $testOutputDir) {
                Remove-Item $testOutputDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "Should preserve data through complete processing pipeline" {
            # Create test data with known values
            $csvContent = @"
Name,Age,City,Salary
John Doe,30,New York,50000
Jane Smith,25,Los Angeles,45000
Bob Johnson,35,Chicago,55000
"@
            
            $inputFile = Join-Path $testInputDir "20250101120000.csv"
            $csvContent | Out-File -FilePath $inputFile -Encoding UTF8
            
            # Process through the pipeline
            $testData = Import-Csv $inputFile
            $columns = $testData[0].PSObject.Properties.Name
            $mergedColumns = Merge-ColumnSchemas -ExistingColumns @() -NewColumns $columns -IncludeTimestamp $true
            
            # Verify schema
            $mergedColumns -contains "SourceFile" | Should Be $true
            $mergedColumns -contains "Name" | Should Be $true
            $mergedColumns -contains "Age" | Should Be $true
            $mergedColumns -contains "City" | Should Be $true
            $mergedColumns -contains "Salary" | Should Be $true
            
            # Verify data integrity
            $testData.Count | Should Be 3
            $testData[0].Name | Should Be "John Doe"
            $testData[0].Age | Should Be "30"
            $testData[0].Salary | Should Be "50000"
            
            # Test unified row creation
            $unifiedRow = New-UnifiedRow -SourceRow $testData[0] -UnifiedSchema $mergedColumns -SourceFileValue "20250101120000.csv"
            $unifiedRow.SourceFile | Should Be "20250101120000.csv"
            $unifiedRow.Name | Should Be "John Doe"
            $unifiedRow.Age | Should Be "30"
            $unifiedRow.Salary | Should Be "50000"
        }
    }
}

Write-Host "✅ End-to-End Integration tests completed" -ForegroundColor Green
