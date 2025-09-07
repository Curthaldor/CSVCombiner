# ==============================================================================
# Data Processing Module Tests
# ==============================================================================
# Tests for CSVCombiner-DataProcessing.ps1 functionality
# ==============================================================================

# Import required modules
$ScriptRoot = Split-Path -Parent $PSCommandPath
$ProjectRoot = Split-Path (Split-Path $ScriptRoot -Parent) -Parent
$ModuleRoot = Join-Path $ProjectRoot "src\modules"
. (Join-Path $ModuleRoot "CSVCombiner-DataProcessing.ps1")

Describe "Data Processing Core Logic Tests" {
    
    Context "Column Schema Merging" {
        It "Should merge different column schemas correctly" {
            $existing = @("Name", "Age")
            $new = @("Name", "Email", "Phone")
            $result = Merge-ColumnSchemas -ExistingColumns $existing -NewColumns $new -IncludeTimestamp $true
            
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
            $result = Merge-ColumnSchemas -ExistingColumns $existing -NewColumns $new -IncludeTimestamp $true
            
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
        
        It "Should preserve column order from first file" {
            $existing = @()
            $new = @("ZZZ", "AAA", "MMM", "BBB")  # Non-alphabetical order
            
            $result = Merge-ColumnSchemas -ExistingColumns $existing -NewColumns $new -IncludeTimestamp $true
            
            $result[0] | Should Be "SourceFile"
            $result[1] | Should Be "ZZZ"
            $result[2] | Should Be "AAA"
            $result[3] | Should Be "MMM"
            $result[4] | Should Be "BBB"
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
        
        It "Should handle missing columns gracefully" {
            $schema = @("Name", "Age", "City", "Country")
            $sourceData = [PSCustomObject]@{ Name = "John"; Age = 30 }
            $result = New-UnifiedRow -SourceRow $sourceData -UnifiedSchema $schema
            
            $result.Name | Should Be "John"
            $result.Age | Should Be 30
            $result.City | Should Be ""
            $result.Country | Should Be ""
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
    
    Context "Data Type Preservation" {
        It "Should preserve numeric data formatting" {
            $schema = @("ID", "Price", "Quantity")
            $sourceData = [PSCustomObject]@{ ID = "001"; Price = "123.45"; Quantity = "1000" }
            $result = New-UnifiedRow -SourceRow $sourceData -UnifiedSchema $schema
            
            $result.ID | Should Be "001"
            $result.Price | Should Be "123.45"
            $result.Quantity | Should Be "1000"
        }
        
        It "Should handle empty fields correctly" {
            $schema = @("Name", "Age", "City")
            $sourceData = [PSCustomObject]@{ Name = "John"; Age = ""; City = "NYC" }
            $result = New-UnifiedRow -SourceRow $sourceData -UnifiedSchema $schema
            
            $result.Name | Should Be "John"
            $result.Age | Should Be ""
            $result.City | Should Be "NYC"
        }
        
        It "Should preserve special characters" {
            $schema = @("Name", "Description")
            $sourceData = [PSCustomObject]@{ 
                Name = "O'Connor, John"
                Description = "Senior Developer (C#/.NET)"
            }
            $result = New-UnifiedRow -SourceRow $sourceData -UnifiedSchema $schema
            
            $result.Name | Should Be "O'Connor, John"
            $result.Description | Should Be "Senior Developer (C#/.NET)"
        }
    }
}

Write-Host "✅ Data Processing module tests completed" -ForegroundColor Green
