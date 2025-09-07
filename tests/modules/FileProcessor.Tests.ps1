# ==============================================================================
# FileProcessor Module Tests  
# ==============================================================================
# Tests for CSVCombiner-FileProcessor.ps1 functionality
# ==============================================================================

# Import required modules
$ScriptRoot = Split-Path -Parent $PSCommandPath
$ProjectRoot = Split-Path (Split-Path $ScriptRoot -Parent) -Parent
$ModuleRoot = Join-Path $ProjectRoot "src\modules"
. (Join-Path $ModuleRoot "CSVCombiner-Logger.ps1")
. (Join-Path $ModuleRoot "CSVCombiner-Config.ps1")
. (Join-Path $ModuleRoot "CSVCombiner-DataProcessing.ps1")
. (Join-Path $ModuleRoot "CSVCombiner-FileOperations.ps1")
. (Join-Path $ModuleRoot "CSVCombiner-FileProcessor.ps1")

Describe "FileProcessor Module Tests" {
    
    Context "CSVFileProcessor Class Tests" {
        It "Should instantiate CSVFileProcessor successfully" {
            # Create mock configuration
            $config = New-Object -TypeName PSObject
            Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetValidateFilenameFormat" -Value { return $false }
            
            # Create logger
            $logger = [CSVCombinerLogger]::new($null, "INFO")
            
            # Test instantiation
            { $processor = [CSVFileProcessor]::new($config, $logger) } | Should Not Throw
        }
        
        It "Should have required methods for file processing" {
            $config = New-Object -TypeName PSObject
            Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetValidateFilenameFormat" -Value { return $false }
            
            $logger = [CSVCombinerLogger]::new($null, "INFO")
            $processor = [CSVFileProcessor]::new($config, $logger)
            
            # Check that required methods exist
            $processorType = $processor.GetType()
            $methods = $processorType.GetMethods() | Where-Object { $_.DeclaringType -eq $processorType }
            
            # Should have processing methods
            $methods | Where-Object { $_.Name -like "*Process*" } | Should Not BeNullOrEmpty
        }
        
        It "Should handle CSV import with unique headers" {
            # Create test CSV file
            $testDir = Join-Path ([System.IO.Path]::GetTempPath()) "processor_test_$(Get-Random)"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                $csvContent = @"
Name,Age,City
John,30,NYC
Jane,25,LA
"@
                $testFile = Join-Path $testDir "test.csv"
                $csvContent | Out-File -FilePath $testFile -Encoding UTF8
                
                # Create processor
                $config = New-Object -TypeName PSObject
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetValidateFilenameFormat" -Value { return $false }
                
                $logger = [CSVCombinerLogger]::new($null, "INFO")
                $processor = [CSVFileProcessor]::new($config, $logger)
                
                # Test CSV import
                $result = $processor.ImportCSVWithUniqueHeaders($testFile)
                
                $result | Should Not BeNullOrEmpty
                $result.Data.Count | Should Be 2
                $result.ColumnOrder.Count | Should Be 3
                $result.ColumnOrder[0] | Should Be "Name"
                $result.ColumnOrder[1] | Should Be "Age"
                $result.ColumnOrder[2] | Should Be "City"
            }
            finally {
                if (Test-Path $testDir) {
                    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        
        It "Should preserve column order during processing" {
            $testDir = Join-Path ([System.IO.Path]::GetTempPath()) "processor_order_test_$(Get-Random)"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                # Create CSV with specific column order
                $csvContent = @"
ZZZ_Last,AAA_First,MMM_Middle,Status
value1,value2,value3,Active
value4,value5,value6,Inactive
"@
                $testFile = Join-Path $testDir "20250101120000.csv"
                $csvContent | Out-File -FilePath $testFile -Encoding UTF8
                
                $config = New-Object -TypeName PSObject
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetValidateFilenameFormat" -Value { return $false }
                
                $logger = [CSVCombinerLogger]::new($null, "INFO")
                $processor = [CSVFileProcessor]::new($config, $logger)
                
                # Import and verify order preservation
                $result = $processor.ImportCSVWithUniqueHeaders($testFile)
                
                $result.ColumnOrder[0] | Should Be "ZZZ_Last"
                $result.ColumnOrder[1] | Should Be "AAA_First"
                $result.ColumnOrder[2] | Should Be "MMM_Middle"
                $result.ColumnOrder[3] | Should Be "Status"
            }
            finally {
                if (Test-Path $testDir) {
                    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        
        It "Should process multiple input files correctly" {
            $testDir = Join-Path ([System.IO.Path]::GetTempPath()) "processor_multi_test_$(Get-Random)"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                # Create multiple test files
                $csv1 = @"
Name,Age
John,30
Jane,25
"@
                $csv2 = @"
Name,City
Bob,NYC
Alice,LA
"@
                
                $file1 = Join-Path $testDir "20250101120000.csv"
                $file2 = Join-Path $testDir "20250101130000.csv"
                
                $csv1 | Out-File -FilePath $file1 -Encoding UTF8
                $csv2 | Out-File -FilePath $file2 -Encoding UTF8
                
                # Setup processor
                $config = New-Object -TypeName PSObject
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetValidateFilenameFormat" -Value { return $false }
                
                $logger = [CSVCombinerLogger]::new($null, "INFO")
                $processor = [CSVFileProcessor]::new($config, $logger)
                
                # Create file list
                $files = Get-ChildItem -Path $testDir -Filter "*.csv"
                $filesToProcess = [System.Collections.ArrayList]::new()
                foreach ($file in $files) {
                    [void]$filesToProcess.Add($file)
                }
                
                # Process files
                $result = $processor.ProcessInputFiles($filesToProcess)
                
                # Verify results
                $result | Should Not BeNullOrEmpty
                $result.ContainsKey('Columns') | Should Be $true
                $result.ContainsKey('Rows') | Should Be $true
                
                # Should have merged schema
                $result.Columns -contains "Name" | Should Be $true
                $result.Columns -contains "Age" | Should Be $true
                $result.Columns -contains "City" | Should Be $true
                
                # Should have rows from both files
                $result.Rows.Count | Should BeGreaterThan 0
            }
            finally {
                if (Test-Path $testDir) {
                    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    
    Context "Error Handling in FileProcessor" {
        It "Should handle missing files gracefully" {
            $config = New-Object -TypeName PSObject
            Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetValidateFilenameFormat" -Value { return $false }
            
            $logger = [CSVCombinerLogger]::new($null, "INFO")
            $processor = [CSVFileProcessor]::new($config, $logger)
            
            # Test with non-existent file
            { $processor.ImportCSVWithUniqueHeaders("C:\NonExistent\file.csv") } | Should Not Throw
        }
        
        It "Should handle malformed CSV files" {
            $testDir = Join-Path ([System.IO.Path]::GetTempPath()) "processor_error_test_$(Get-Random)"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                # Create malformed CSV
                $malformedCsv = @"
Name,Age,City
John,25
Jane,30,NYC,Extra
Bob,35,LA
"@
                $testFile = Join-Path $testDir "malformed.csv"
                $malformedCsv | Out-File -FilePath $testFile -Encoding UTF8
                
                $config = New-Object -TypeName PSObject
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetValidateFilenameFormat" -Value { return $false }
                
                $logger = [CSVCombinerLogger]::new($null, "INFO")
                $processor = [CSVFileProcessor]::new($config, $logger)
                
                # Should handle malformed CSV without throwing
                { $processor.ImportCSVWithUniqueHeaders($testFile) } | Should Not Throw
            }
            finally {
                if (Test-Path $testDir) {
                    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        
        It "Should handle empty CSV files" {
            $testDir = Join-Path ([System.IO.Path]::GetTempPath()) "processor_empty_test_$(Get-Random)"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                # Create empty CSV
                $testFile = Join-Path $testDir "empty.csv"
                "" | Out-File -FilePath $testFile -Encoding UTF8
                
                $config = New-Object -TypeName PSObject
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetValidateFilenameFormat" -Value { return $false }
                
                $logger = [CSVCombinerLogger]::new($null, "INFO")
                $processor = [CSVFileProcessor]::new($config, $logger)
                
                # Should handle empty CSV without throwing
                { $processor.ImportCSVWithUniqueHeaders($testFile) } | Should Not Throw
            }
            finally {
                if (Test-Path $testDir) {
                    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    
    Context "Data Integrity in FileProcessor" {
        It "Should preserve special characters during processing" {
            $testDir = Join-Path ([System.IO.Path]::GetTempPath()) "processor_special_test_$(Get-Random)"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                # Create CSV with special characters
                $csvContent = @"
Name,Description,Notes
"O'Connor, John","Senior Developer (C#/.NET)","Has ""excellent"" performance"
"李小明","Software Engineer","Speaks 中文"
"@
                $testFile = Join-Path $testDir "special.csv"
                $csvContent | Out-File -FilePath $testFile -Encoding UTF8
                
                $config = New-Object -TypeName PSObject
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetValidateFilenameFormat" -Value { return $false }
                
                $logger = [CSVCombinerLogger]::new($null, "INFO")
                $processor = [CSVFileProcessor]::new($config, $logger)
                
                $result = $processor.ImportCSVWithUniqueHeaders($testFile)
                
                # Verify special characters are preserved
                $result.Data[0].Name | Should Be "O'Connor, John"
                $result.Data[0].Description | Should Be "Senior Developer (C#/.NET)"
                $result.Data[0].Notes | Should Be "Has ""excellent"" performance"
                $result.Data[1].Name | Should Be "李小明"
                $result.Data[1].Description | Should Be "Software Engineer"
            }
            finally {
                if (Test-Path $testDir) {
                    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        
        It "Should maintain data types during processing" {
            $testDir = Join-Path ([System.IO.Path]::GetTempPath()) "processor_types_test_$(Get-Random)"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                # Create CSV with various data types
                $csvContent = @"
ID,Price,Quantity,Active,Date
001,123.45,1000,true,2025-01-01
002,0.99,0,false,2025-01-02
003,999999.99,,,2025-01-03
"@
                $testFile = Join-Path $testDir "types.csv"
                $csvContent | Out-File -FilePath $testFile -Encoding UTF8
                
                $config = New-Object -TypeName PSObject
                Add-Member -InputObject $config -MemberType ScriptMethod -Name "GetValidateFilenameFormat" -Value { return $false }
                
                $logger = [CSVCombinerLogger]::new($null, "INFO")
                $processor = [CSVFileProcessor]::new($config, $logger)
                
                $result = $processor.ImportCSVWithUniqueHeaders($testFile)
                
                # Verify data preservation (PowerShell Import-Csv treats everything as strings)
                $result.Data[0].ID | Should Be "001"
                $result.Data[0].Price | Should Be "123.45"
                $result.Data[0].Quantity | Should Be "1000"
                $result.Data[0].Active | Should Be "true"
                
                # Empty fields should be empty strings
                $result.Data[2].Quantity | Should Be ""
                $result.Data[2].Active | Should Be ""
            }
            finally {
                if (Test-Path $testDir) {
                    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

Write-Host "✅ FileProcessor module tests completed" -ForegroundColor Green
