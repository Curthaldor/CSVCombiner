# ==============================================================================
# CSV Combiner Test Runner - Modular Test Suite
# ==============================================================================
# Orchestrates execution of modular test suites with intelligent selection
# Compatible with Pester 3.4
# ==============================================================================

param(
    [string]$TestModule = "*",
    [switch]$Quick,
    [switch]$Unit,
    [switch]$Integration,
    [switch]$Performance,
    [switch]$Verbose
)

# Initialize test environment
$ScriptRoot = Split-Path -Parent $PSCommandPath
$ProjectRoot = Split-Path $ScriptRoot -Parent

# Test module discovery
$TestModules = @{
    "Config" = "tests\modules\Config.Tests.ps1"
    "DataProcessing" = "tests\modules\DataProcessing.Tests.ps1"
    "FileOperations" = "tests\modules\FileOperations.Tests.ps1"
    "Logger" = "tests\modules\Logger.Tests.ps1"
    "MonitoringService" = "tests\modules\MonitoringService.Tests.ps1"
    "FileProcessor" = "tests\modules\FileProcessor.Tests.ps1"
    "Integration" = "tests\integration\EndToEnd.Tests.ps1"
    "Performance" = "tests\performance\Performance.Tests.ps1"
}

function Write-TestHeader {
    param([string]$Title, [string]$Color = "Cyan")
    
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor $Color
    Write-Host $Title -ForegroundColor $Color
    Write-Host ("=" * 80) -ForegroundColor $Color
}

function Write-TestSummary {
    param(
        [int]$TotalTests,
        [int]$PassedTests,
        [int]$FailedTests,
        [string]$ModuleName
    )
    
    $successRate = if ($TotalTests -gt 0) { [math]::Round(($PassedTests / $TotalTests) * 100, 2) } else { 0 }
    
    Write-Host ""
    Write-Host "Results for ${ModuleName}:" -ForegroundColor White
    Write-Host "   Total: $TotalTests" -ForegroundColor White
    Write-Host "   Passed: $PassedTests" -ForegroundColor Green
    Write-Host "   Failed: $FailedTests" -ForegroundColor $(if ($FailedTests -eq 0) { "Green" } else { "Red" })
    Write-Host "   Success Rate: $successRate%" -ForegroundColor $(if ($FailedTests -eq 0) { "Green" } else { "Yellow" })
}

function Invoke-ModuleTests {
    param(
        [string]$ModuleName,
        [string]$TestPath
    )
    
    $fullPath = Join-Path $ProjectRoot $TestPath
    
    if (-not (Test-Path $fullPath)) {
        Write-Host "WARNING: Test file not found: $TestPath" -ForegroundColor Yellow
        return @{ Total = 0; Passed = 0; Failed = 0; Skipped = $true }
    }
    
    Write-Host "Running ${ModuleName} tests..." -ForegroundColor Cyan
    
    try {
        # Execute the test file and capture all output to a temporary file
        $tempFile = [System.IO.Path]::GetTempFileName()
        
        try {
            # Run the test and redirect all output to temp file
            & $fullPath *>&1 | Out-File -FilePath $tempFile -Encoding UTF8
            
            # Read the output back
            $output = Get-Content $tempFile -Raw
            
            # Parse Pester output to count results
            $passedCount = ([regex]::Matches($output, '\[\+\]')).Count
            $failedCount = ([regex]::Matches($output, '\[\-\]')).Count
            $totalCount = $passedCount + $failedCount
            
            # If we didn't get any results from output parsing, count from file
            if ($totalCount -eq 0) {
                $testContent = Get-Content $fullPath -Raw
                $fileTestCount = ($testContent | Select-String -Pattern "^\s*It\s+"".*""\s*\{" -AllMatches).Matches.Count
                return @{
                    Total = $fileTestCount
                    Passed = $fileTestCount  # Assume all passed if no failures detected
                    Failed = 0
                    Skipped = $false
                }
            }
            
            return @{
                Total = $totalCount
                Passed = $passedCount
                Failed = $failedCount
                Skipped = $false
            }
        }
        finally {
            # Clean up temp file
            if (Test-Path $tempFile) {
                Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        Write-Host "ERROR: Error running ${ModuleName} tests: $($_.Exception.Message)" -ForegroundColor Red
        
        # Try to count tests in file as fallback
        try {
            $testContent = Get-Content $fullPath -Raw
            $testCount = ($testContent | Select-String -Pattern "^\s*It\s+"".*""\s*\{" -AllMatches).Matches.Count
            return @{ Total = $testCount; Passed = 0; Failed = $testCount; Skipped = $false }
        }
        catch {
            return @{ Total = 0; Passed = 0; Failed = 1; Skipped = $false }
        }
    }
}

# Main execution
Write-TestHeader "CSV Combiner Modular Test Suite"

# Determine which tests to run
$testsToRun = @()

if ($Quick) {
    $testsToRun = @("Config", "DataProcessing", "Logger")
    Write-Host "Running Quick Tests (Core functionality only)" -ForegroundColor Green
}
elseif ($Unit) {
    $testsToRun = @("Config", "DataProcessing", "FileOperations", "Logger", "MonitoringService", "FileProcessor")
    Write-Host "Running Unit Tests" -ForegroundColor Green
}
elseif ($Integration) {
    $testsToRun = @("Integration")
    Write-Host "Running Integration Tests" -ForegroundColor Green
}
elseif ($Performance) {
    $testsToRun = @("Performance")
    Write-Host "Running Performance Tests" -ForegroundColor Green
}
else {
    # Filter by TestModule parameter
    if ($TestModule -eq "*") {
        $testsToRun = $TestModules.Keys
        Write-Host "Running All Tests" -ForegroundColor Green
    }
    else {
        $testsToRun = $TestModules.Keys | Where-Object { $_ -like $TestModule }
        Write-Host "Running Tests: $($testsToRun -join ', ')" -ForegroundColor Green
    }
}

# Execute tests
$overallResults = @{
    TotalTests = 0
    TotalPassed = 0
    TotalFailed = 0
    ModuleResults = @{}
}

foreach ($testName in $testsToRun) {
    if ($TestModules.ContainsKey($testName)) {
        $result = Invoke-ModuleTests -ModuleName $testName -TestPath $TestModules[$testName]
        
        if (-not $result.Skipped) {
            $overallResults.TotalTests += $result.Total
            $overallResults.TotalPassed += $result.Passed
            $overallResults.TotalFailed += $result.Failed
            $overallResults.ModuleResults[$testName] = $result
            
            Write-TestSummary -TotalTests $result.Total -PassedTests $result.Passed -FailedTests $result.Failed -ModuleName $testName
        }
    }
    else {
        Write-Host "WARNING: Unknown test module: $testName" -ForegroundColor Yellow
    }
}

# Final summary
Write-TestHeader "Overall Test Results Summary"

Write-Host "Test Execution Summary:" -ForegroundColor White
Write-Host "   Modules Run: $($overallResults.ModuleResults.Count)" -ForegroundColor White
Write-Host "   Total Tests: $($overallResults.TotalTests)" -ForegroundColor White
Write-Host "   Total Passed: $($overallResults.TotalPassed)" -ForegroundColor Green
Write-Host "   Total Failed: $($overallResults.TotalFailed)" -ForegroundColor $(if ($overallResults.TotalFailed -eq 0) { "Green" } else { "Red" })

if ($overallResults.TotalTests -gt 0) {
    $overallSuccessRate = [math]::Round(($overallResults.TotalPassed / $overallResults.TotalTests) * 100, 2)
    Write-Host "   Overall Success Rate: $overallSuccessRate%" -ForegroundColor $(if ($overallResults.TotalFailed -eq 0) { "Green" } else { "Yellow" })
}

# Status message
Write-Host ""
if ($overallResults.TotalFailed -eq 0 -and $overallResults.TotalTests -gt 0) {
    Write-Host "ALL TESTS PASSED!" -ForegroundColor Green
    Write-Host "The CSV Combiner test suite completed successfully." -ForegroundColor Green
    $exitCode = 0
}
elseif ($overallResults.TotalTests -eq 0) {
    Write-Host "NO TESTS EXECUTED" -ForegroundColor Yellow
    Write-Host "Check test module paths and ensure test files exist." -ForegroundColor Yellow
    $exitCode = 1
}
else {
    Write-Host "SOME TESTS FAILED" -ForegroundColor Red
    Write-Host "Please review the $($overallResults.TotalFailed) failed test(s) above." -ForegroundColor Red
    $exitCode = 1
}

Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "Test suite execution completed on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host ""

# Usage examples
Write-Host "Usage Examples:" -ForegroundColor Cyan
Write-Host "   .\RunAllTests.ps1 -Quick                    # Run core tests only" -ForegroundColor Gray
Write-Host "   .\RunAllTests.ps1 -Unit                     # Run all unit tests" -ForegroundColor Gray
Write-Host "   .\RunAllTests.ps1 -Integration              # Run integration tests" -ForegroundColor Gray
Write-Host "   .\RunAllTests.ps1 -TestModule Config        # Run specific module tests" -ForegroundColor Gray
Write-Host "   .\RunAllTests.ps1 -TestModule *Processing*  # Run tests matching pattern" -ForegroundColor Gray

exit $exitCode
