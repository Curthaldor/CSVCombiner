# ==============================================================================
# File Operations Module Tests
# ==============================================================================
# Tests for CSVCombiner-FileOperations.ps1 functionality
# ==============================================================================

# Import required modules
$ScriptRoot = Split-Path -Parent $PSCommandPath
$ProjectRoot = Split-Path (Split-Path $ScriptRoot -Parent) -Parent
$ModuleRoot = Join-Path $ProjectRoot "src\modules"
. (Join-Path $ModuleRoot "CSVCombiner-FileOperations.ps1")

Describe "File Operations Tests" {
    
    Context "Filename Format Validation" {
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
    
    Context "File Snapshot Operations" {
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
    
    Context "File Snapshot Comparison" {
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
    
    Context "Memory-Efficient File Functions" {
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
        
        It "Should extract processed filenames efficiently" {
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
    }
    
    Context "Path Operations" {
        It "Should generate simple output path" {
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
}

Write-Host "✅ File Operations module tests completed" -ForegroundColor Green
