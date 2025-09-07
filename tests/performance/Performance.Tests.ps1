# ==============================================================================
# Performance Tests
# ==============================================================================
# Tests for performance, memory usage, and scalability
# ==============================================================================

# Import required modules
$ScriptRoot = Split-Path -Parent $PSCommandPath
$ProjectRoot = Split-Path (Split-Path $ScriptRoot -Parent) -Parent
$ModuleRoot = Join-Path $ProjectRoot "src\modules"

$modules = @(
    "CSVCombiner-Logger.ps1",
    "CSVCombiner-Config.ps1", 
    "CSVCombiner-FileOperations.ps1",
    "CSVCombiner-DataProcessing.ps1",
    "CSVCombiner-FileProcessor.ps1"
)

foreach ($module in $modules) {
    $modulePath = Join-Path $ModuleRoot $module
    if (Test-Path $modulePath) {
        . $modulePath
    }
}

Describe "Performance and Scalability Tests" {
    
    Context "Memory Efficiency Tests" {
        It "Should handle large datasets without excessive memory usage" {
            # Create a large test dataset
            $testData = @()
            for ($i = 1; $i -le 1000; $i++) {
                $testData += [PSCustomObject]@{
                    Name = "User$i"
                    Age = Get-Random -Minimum 18 -Maximum 80
                    City = "City$($i % 10)"
                    Department = "Dept$($i % 5)"
                    Salary = Get-Random -Minimum 30000 -Maximum 100000
                }
            }
            
            $testFile = Join-Path ([System.IO.Path]::GetTempPath()) "large_test_$(Get-Random).csv"
            
            try {
                # Measure memory usage during export
                $memoryBefore = [System.GC]::GetTotalMemory($false)
                $testData | Export-Csv -Path $testFile -NoTypeInformation
                $memoryAfter = [System.GC]::GetTotalMemory($false)
                
                # Test that the file was created successfully
                Test-Path $testFile | Should Be $true
                
                # Test memory-efficient functions
                $rowCount = Get-MasterFileRowCount -MasterFilePath $testFile
                $rowCount | Should Be 1000
                
                $schema = Get-MasterFileSchema -MasterFilePath $testFile
                $schema.Count | Should BeGreaterThan 0
                $schema -contains "Name" | Should Be $true
                
                # Memory usage should be reasonable (less than 50MB growth for 1000 rows)
                $memoryGrowth = $memoryAfter - $memoryBefore
                $memoryGrowth | Should BeLessThan (50 * 1024 * 1024)  # 50MB
            }
            finally {
                if (Test-Path $testFile) {
                    Remove-Item $testFile -Force
                }
            }
        }
        
        It "Should efficiently handle duplicate detection on large datasets" {
            # Create test data with known duplicates
            $data = @()
            for ($i = 1; $i -le 500; $i++) {
                # Add each record twice to create duplicates
                $record = [PSCustomObject]@{ 
                    Name = "User$($i % 100)"  # This will create duplicates
                    Age = 30 + ($i % 20)
                    City = "City$($i % 10)"
                    Timestamp = "file$($i % 2).csv"
                }
                $data += $record
                $data += $record  # Duplicate
            }
            
            # Measure time for duplicate removal
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Remove-DuplicateRows -Data $data -ExcludeColumns @("Timestamp")
            $stopwatch.Stop()
            
            # Should complete quickly (less than 5 seconds for 1000 records)
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 5000
            
            # Should have removed duplicates effectively
            $result.Count | Should BeLessThan $data.Count
            $result.Count | Should BeGreaterThan 0
        }
        
        It "Should handle large schema merging efficiently" {
            # Create schemas with many columns
            $existing = @()
            for ($i = 1; $i -le 50; $i++) {
                $existing += "ExistingCol$i"
            }
            
            $new = @()
            for ($i = 1; $i -le 50; $i++) {
                $new += "NewCol$i"
            }
            
            # Add some overlapping columns
            $new += "ExistingCol1", "ExistingCol25", "ExistingCol50"
            
            # Measure performance
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Merge-ColumnSchemas -ExistingColumns $existing -NewColumns $new -IncludeTimestamp $true
            $stopwatch.Stop()
            
            # Should complete quickly
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 1000  # 1 second
            
            # Should have correct number of unique columns
            $result.Count | Should Be 101  # 50 + 50 + 1 (SourceFile), no duplicates
            $result -contains "SourceFile" | Should Be $true
            $result -contains "ExistingCol1" | Should Be $true
            $result -contains "NewCol50" | Should Be $true
            
            # Should not have duplicates
            ($result | Group-Object | Where-Object { $_.Count -gt 1 }).Count | Should Be 0
        }
    }
    
    Context "File Processing Performance" {
        BeforeEach {
            $script:perfTestDir = Join-Path ([System.IO.Path]::GetTempPath()) "perf_test_$(Get-Random)"
            New-Item -ItemType Directory -Path $perfTestDir -Force | Out-Null
        }
        
        AfterEach {
            if (Test-Path $perfTestDir) {
                Remove-Item $perfTestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "Should process multiple CSV files efficiently" {
            # Create multiple test files
            $fileCount = 10
            $recordsPerFile = 100
            
            for ($fileNum = 1; $fileNum -le $fileCount; $fileNum++) {
                $csvData = @()
                for ($i = 1; $i -le $recordsPerFile; $i++) {
                    $csvData += [PSCustomObject]@{
                        ID = "$fileNum-$i"
                        Name = "User$i"
                        Value = Get-Random -Minimum 1 -Maximum 1000
                        Category = "Cat$($i % 5)"
                    }
                }
                
                $fileName = "test_file_$($fileNum.ToString('00')).csv"
                $filePath = Join-Path $perfTestDir $fileName
                $csvData | Export-Csv -Path $filePath -NoTypeInformation
            }
            
            # Test file snapshot performance
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $snapshot = Get-FileSnapshot -FolderPath $perfTestDir -UseFileHashing $false -ValidateFilenameFormat $false
            $stopwatch.Stop()
            
            # Should complete quickly
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 2000  # 2 seconds
            
            # Should find all files
            $snapshot.Files.Count | Should Be $fileCount
        }
        
        It "Should handle file monitoring efficiently" {
            # Create initial file set
            $initialFiles = 5
            for ($i = 1; $i -le $initialFiles; $i++) {
                $fileName = "initial_$i.csv"
                $filePath = Join-Path $perfTestDir $fileName
                "Name,Value`nTest$i,$i" | Out-File -FilePath $filePath
            }
            
            # Take initial snapshot
            $snapshot1 = Get-FileSnapshot -FolderPath $perfTestDir -UseFileHashing $false -ValidateFilenameFormat $false
            
            # Add new files
            for ($i = 6; $i -le 10; $i++) {
                $fileName = "new_$i.csv"
                $filePath = Join-Path $perfTestDir $fileName
                "Name,Value`nTest$i,$i" | Out-File -FilePath $filePath
            }
            
            # Take second snapshot and compare
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $snapshot2 = Get-FileSnapshot -FolderPath $perfTestDir -UseFileHashing $false -ValidateFilenameFormat $false
            $changes = Compare-FileSnapshots -OldSnapshot $snapshot1 -NewSnapshot $snapshot2 -ValidateFilenameFormat $false
            $stopwatch.Stop()
            
            # Should complete quickly
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 1000  # 1 second
            
            # Should detect new files
            $changes.NewFiles.Count | Should Be 5
        }
    }
    
    Context "Scalability Tests" {
        It "Should handle increasing column counts gracefully" {
            # Test with progressively larger column counts
            $columnCounts = @(10, 50, 100, 200)
            
            foreach ($colCount in $columnCounts) {
                $columns = @()
                for ($i = 1; $i -le $colCount; $i++) {
                    $columns += "Column$i"
                }
                
                $testRow = New-Object PSObject
                foreach ($col in $columns) {
                    Add-Member -InputObject $testRow -MemberType NoteProperty -Name $col -Value "Value"
                }
                
                # Measure unified row creation performance
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $result = New-UnifiedRow -SourceRow $testRow -UnifiedSchema $columns
                $stopwatch.Stop()
                
                # Should scale reasonably (less than 100ms even for 200 columns)
                $stopwatch.ElapsedMilliseconds | Should BeLessThan 100
                
                # Should have all columns
                ($result.PSObject.Properties | Measure-Object).Count | Should Be $colCount
            }
        }
        
        It "Should maintain performance with increasing row counts" {
            # Test duplicate removal with increasing data sizes
            $rowCounts = @(100, 500, 1000, 2000)
            
            foreach ($rowCount in $rowCounts) {
                $data = @()
                for ($i = 1; $i -le $rowCount; $i++) {
                    $data += [PSCustomObject]@{
                        ID = $i % 50  # This creates duplicates even for 100 rows
                        Name = "User$($i % 25)"
                        Value = Get-Random
                        Timestamp = "file.csv"
                    }
                }
                
                # Measure duplicate removal performance
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $result = Remove-DuplicateRows -Data $data -ExcludeColumns @("Timestamp", "Value")
                $stopwatch.Stop()
                
                # Performance should scale reasonably (less than 5 seconds for 2000 rows)
                $stopwatch.ElapsedMilliseconds | Should BeLessThan 5000
                
                # Should reduce duplicates
                $result.Count | Should BeLessThan $data.Count
                $result.Count | Should BeGreaterThan 0
            }
        }
    }
    
    Context "Resource Usage Tests" {
        It "Should not create memory leaks during repeated operations" {
            # Force garbage collection to get baseline
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()
            
            $memoryBefore = [System.GC]::GetTotalMemory($false)
            
            # Perform repeated operations
            for ($i = 1; $i -le 100; $i++) {
                $testData = @()
                for ($j = 1; $j -le 10; $j++) {
                    $testData += [PSCustomObject]@{ Name = "Test$j"; Value = $j }
                }
                
                $schema = @("Name", "Value", "Extra")
                $result = New-UnifiedRow -SourceRow $testData[0] -UnifiedSchema $schema
                
                # Simulate some processing
                $merged = Merge-ColumnSchemas -ExistingColumns @("Name") -NewColumns @("Value", "Extra")
            }
            
            # Force garbage collection again
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()
            
            $memoryAfter = [System.GC]::GetTotalMemory($false)
            $memoryGrowth = $memoryAfter - $memoryBefore
            
            # Memory growth should be minimal (less than 10MB for 100 iterations)
            $memoryGrowth | Should BeLessThan (10 * 1024 * 1024)  # 10MB
        }
        
        It "Should handle file operations without excessive handles" {
            $testDir = Join-Path ([System.IO.Path]::GetTempPath()) "handle_test_$(Get-Random)"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                # Create and process many files
                for ($i = 1; $i -le 20; $i++) {
                    $fileName = "test_$i.csv"
                    $filePath = Join-Path $testDir $fileName
                    "Name,Value`nTest$i,$i" | Out-File -FilePath $filePath
                    
                    # Test memory-efficient functions
                    $rowCount = Get-MasterFileRowCount -MasterFilePath $filePath
                    $schema = Get-MasterFileSchema -MasterFilePath $filePath
                    
                    # These should not throw errors or hang
                    $rowCount | Should BeGreaterThan 0
                    $schema.Count | Should BeGreaterThan 0
                }
                
                # Test snapshot of all files
                $snapshot = Get-FileSnapshot -FolderPath $testDir -UseFileHashing $false -ValidateFilenameFormat $false
                $snapshot.Files.Count | Should Be 20
            }
            finally {
                if (Test-Path $testDir) {
                    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

Write-Host "✅ Performance tests completed" -ForegroundColor Green
