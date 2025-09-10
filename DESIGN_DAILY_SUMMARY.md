# Design Document: Real-Time Daily Summary Feature

## Overview

This document outlines the design for implementing a real-time daily summary feature in the CSV Combiner tool. The feature will track pass/fail statistics per day based on the "PassFlag" column, updating incrementally as new data is processed without requiring full file rescans.

## Requirements

### Functional Requirements
1. **Real-Time Updates**: Daily summary must update immediately as new rows are processed
2. **Performance**: No full output file rescans - only process new files or current day's data
3. **Persistence**: Summary data must survive script restarts
4. **Date-Based Grouping**: Statistics grouped by date extracted from filename (YYYYMMDDHHMMSS.csv format)
5. **Pass/Fail Tracking**: Count rows where PassFlag is "Passed" vs empty/other values
6. **Non-Disruptive**: Existing CSV merger functionality must remain unchanged
7. **Configurable**: Feature can be enabled/disabled via settings
8. **Spreadsheet-Friendly**: Output format convenient for viewing/sharing in Excel or similar tools
9. **Remote Access**: Support for OneDrive synchronization scenarios

### Non-Functional Requirements
1. **Performance**: Only process new files, avoiding full output file scans
2. **Reliability**: Summary state resilient to network storage scenarios (OneDrive)
3. **Maintainability**: Clear separation from core merge logic
4. **Extensibility**: Design allows for future statistical enhancements
5. **Scalability**: Handle thousands of output rows without performance degradation

## Architecture

### High-Level Design

The daily summary feature integrates into the existing CSV processing pipeline through incremental state tracking and smart file processing:

```
Input Files → Filename Validation → Row Processing → Summary Update → Daily CSV Update
                     ↓                      ↓              ↓              ↓
              Extract Date           Determine Pass/Fail   Track State    Update/Append Row
```

**Key Design Principles:**
- **Incremental Processing**: Only analyze new files, never rescan entire output
- **CSV-Based Output**: Spreadsheet-friendly daily summary format
- **State Tracking**: Lightweight tracking of processed files
- **OneDrive Compatible**: Network storage friendly operations

### Component Structure

```
CSV Merger Core (Existing)
├── Settings Management
├── File Processing Pipeline
└── Output Generation

Daily Summary Feature (New)
├── Summary State Management (Lightweight)
├── Daily CSV Management
├── Date Extraction Utilities
├── Pass/Fail Analysis
└── Spreadsheet-Compatible Reporting
```

## Detailed Design

### 1. Data Structures

#### Daily Summary CSV (`daily_summary.csv`)
```csv
Date,FilesProcessed,TotalRows,Passes,Failures,PassRate,LastUpdate
2025-05-23,3,150,142,8,94.7%,2025-05-23T20:30:00Z
2025-05-24,2,75,71,4,94.7%,2025-05-24T16:22:31Z
2025-05-25,1,50,48,2,96.0%,2025-05-25T14:15:22Z
```

**Key Characteristics:**
- **One row per date**: Easy spreadsheet viewing and analysis
- **Cumulative daily totals**: All files for that date aggregated
- **Pass rate calculation**: Automatic percentage for quick assessment
- **Timestamp tracking**: When the day's data was last updated

#### State Tracking File (`summary_state.txt`)
```
# Processed files for daily summary tracking
20250523200303.csv
20250523201143.csv
20250524162231.csv
20250524141936.csv
```

**Purpose:**
- Track which files have been included in daily summary
- Prevent double-counting during reprocessing
- Lightweight text format for simple read/write operations
- Network storage friendly (small, append-only)

#### Configuration Extension
```ini
[Summary]
# Enable daily summary feature
EnableDailySummary=true

# Daily summary CSV file location
DailySummaryFile=daily_summary.csv

# State tracking file location
SummaryStateFile=summary_state.txt

# Display summary at end of processing
DisplaySummaryAtEnd=true
```

### 2. Core Functions

#### Summary State Management
```powershell
function Load-ProcessedFilesList {
    param([string]$StateFilePath)
    # Load list of previously processed files from text file
    # Return array of filenames
    # Handle missing file scenario (return empty array)
}

function Save-ProcessedFilesList {
    param([array]$ProcessedFiles, [string]$StateFilePath)
    # Append new processed files to state file
    # Use simple text format for network storage compatibility
}

function Test-FileAlreadySummarized {
    param([string]$FileName, [array]$ProcessedFiles)
    # Check if file has already been included in daily summary
    # Prevent double-counting in reprocessing scenarios
}
```

#### Daily CSV Management
```powershell
function Load-DailySummaryCSV {
    param([string]$SummaryFilePath)
    # Load existing daily summary CSV into hashtable
    # Return structure: @{"2025-05-23" = @{Passes=15; Failures=2; ...}}
    # Handle missing file (return empty hashtable)
}

function Update-DailySummaryCSV {
    param([hashtable]$DailyData, [string]$SummaryFilePath)
    # Write complete daily summary back to CSV file
    # Sort by date for consistent output
    # Include calculated pass rates
}

function Add-DayStatistics {
    param([hashtable]$DailyData, [string]$Date, [int]$Passes, [int]$Failures, [string]$FileName)
    # Add statistics for processed file to daily totals
    # Update counters for specified date
    # Track file count and last update timestamp
}
```

#### Date and Status Utilities
```powershell
function Extract-DateFromFileName {
    param([string]$FileName)
    # Convert "20250523200303.csv" to "2025-05-23"
    # Validate 14-digit format already ensured by existing filename filter
}

function Get-PassFailStatus {
    param([string]$Line, [array]$HeaderColumns)
    # Parse PassFlag column from CSV row
    # Return "pass", "fail", or "unknown"
    # Reuse existing column index logic from filtering function
}

function Test-FileAlreadyProcessed {
    param([string]$FileName, [array]$ProcessedFiles)
    # Check if file has already been summarized
    # Prevent double-counting in reprocessing scenarios
}
```

#### Display and Reporting
```powershell
function Display-DailySummary {
    param([hashtable]$DailyData)
    # Console output of current daily statistics
    # Show recent days and totals
    # Calculate overall pass rates and trends
}

function Get-FileStatistics {
    param([string]$FilePath, [array]$HeaderColumns)
    # Process single file and return pass/fail counts
    # Used only for new files that haven't been summarized
    # Returns: @{Passes=15; Failures=2; Total=17}
}
```

### 3. Integration Points

#### Smart File Processing Enhancement
```powershell
# Modify file collection logic to identify new files for summary
$processedFiles = Load-ProcessedFilesList -StateFilePath $SummaryStateFilePath
$newFilesForSummary = @()

foreach ($file in $newFiles) {
    if (-not (Test-FileAlreadySummarized -FileName $file.Name -ProcessedFiles $processedFiles)) {
        $newFilesForSummary += $file
    }
}
```

#### Per-File Summary Tracking
```powershell
# After processing each file in Merge-CsvFile, collect statistics
if ($EnableDailySummary -and ($fileName -notin $ProcessedFiles)) {
    $fileDate = Extract-DateFromFileName -FileName $fileName
    
    # Count passes/failures for this file during processing
    # (tracked as rows are processed, not via separate scan)
    
    Add-DayStatistics -DailyData $DailySummaryData -Date $fileDate -Passes $filePasses -Failures $fileFailures -FileName $fileName
    
    # Mark file as processed for summary
    $ProcessedFiles += $fileName
}
```

#### Main Script Flow Enhancement
```powershell
# Load summary state at script start
if ($EnableDailySummary) {
    $ProcessedFiles = Load-ProcessedFilesList -StateFilePath $SummaryStateFilePath
    $DailySummaryData = Load-DailySummaryCSV -SummaryFilePath $DailySummaryFilePath
}

# Process files with summary tracking
foreach ($file in $newFiles) {
    $fileCount++
    $isFirstFile = $writeHeader -and ($fileCount -eq 1)
    $needsSummary = $EnableDailySummary -and ($file.Name -notin $ProcessedFiles)
    
    Write-Host "`nProcessing file $fileCount of $($newFiles.Count):" -ForegroundColor Blue
    
    $rowsAdded = Merge-CsvFile -FilePath $file.FullName -Writer $writer -IsFirstFile $isFirstFile -TrackSummary $needsSummary
    
    # Update summary for new files only
    if ($needsSummary) {
        $fileDate = Extract-DateFromFileName -FileName $file.Name
        $fileStats = Get-FileStatistics -FilePath $file.FullName -HeaderColumns $headerColumns
        Add-DayStatistics -DailyData $DailySummaryData -Date $fileDate -Passes $fileStats.Passes -Failures $fileStats.Failures -FileName $file.Name
        $ProcessedFiles += $file.Name
    }
}

# Save summary state after processing
if ($EnableDailySummary) {
    Save-ProcessedFilesList -ProcessedFiles $ProcessedFiles -StateFilePath $SummaryStateFilePath
    Update-DailySummaryCSV -DailyData $DailySummaryData -SummaryFilePath $DailySummaryFilePath
    
    if ($DisplaySummaryAtEnd) {
        Display-DailySummary -DailyData $DailySummaryData
    }
}
```

## Implementation Strategy

### Phase 1: Core Infrastructure
1. Add summary configuration to settings.ini
2. Implement date extraction and pass/fail utilities
3. Create lightweight state file management (text-based)
4. Create daily CSV management functions
5. Add unit tests for utility functions

### Phase 2: Integration
1. Modify file processing logic to identify files needing summary
2. Implement per-file statistics collection during processing
3. Update main script flow to load/save summary state
4. Implement daily CSV update functionality
5. Test with existing data files

### Phase 3: Enhancement
1. Add console display functionality for daily summaries
2. Implement validation and error handling
3. Add recovery mechanisms for corrupted state
4. Performance optimization for network storage scenarios
5. Handle edge cases (date parsing, malformed data)

### Phase 4: Documentation and Testing
1. Update README with summary feature documentation
2. Create comprehensive test scenarios
3. Performance testing with large datasets and network storage
4. User acceptance testing for spreadsheet integration
5. OneDrive synchronization testing

## Risk Analysis

### Technical Risks
1. **State File Corruption**: Text state file corruption could lose tracking data
   - **Mitigation**: Simple append-only format, easy manual recovery, backup from CSV timestamps
2. **CSV File Locking**: Network storage file locking during updates
   - **Mitigation**: Atomic write operations, retry logic, OneDrive handles most conflicts
3. **Performance Impact**: Additional processing per new file
   - **Mitigation**: Only process files not yet summarized, lightweight operations
4. **Network Storage Latency**: OneDrive sync delays affecting file operations
   - **Mitigation**: Local file operations, let OneDrive handle sync in background

### Functional Risks
1. **Date Parsing Errors**: Invalid filename formats
   - **Mitigation**: Existing filename validation prevents this
2. **Double Counting**: File reprocessing scenarios
   - **Mitigation**: Track processed files in state file, check before summarizing
3. **Column Index Changes**: CSV structure modifications
   - **Mitigation**: Dynamic column detection (existing pattern)
4. **Spreadsheet Compatibility**: CSV format issues with Excel/other tools
   - **Mitigation**: Standard CSV format, proper escaping, percentage formatting

## Testing Strategy

### Unit Tests
- Date extraction from various filename formats
- Pass/fail status detection from CSV rows
- Summary state serialization/deserialization
- Edge cases: empty files, malformed data

### Integration Tests
- End-to-end processing with summary enabled
- Multiple file processing scenarios over multiple days
- Continuous mode with summary updates
- Recovery from corrupted summary state
- OneDrive synchronization scenarios
- Spreadsheet import/export validation

### Performance Tests
- Large file processing with summary enabled (thousands of rows)
- Network storage performance with OneDrive
- Summary state file size growth over time
- Concurrent access scenarios (if applicable)

## Future Enhancements

### Additional Statistics
- Processing time per day and per file
- Error rate tracking by specific error codes
- File size and row count summaries per day
- Trend analysis and historical reporting

### Spreadsheet Integration
- Excel-compatible formatting and formulas
- Conditional formatting for pass rate thresholds
- Chart-ready data export options
- Pivot table friendly structure

### Advanced Features
- Summary data retention policies
- Historical data archiving
- Multi-metric tracking framework
- Alert thresholds for failure rates
- Email/notification integration for daily reports

## Conclusion

This updated design provides a robust, spreadsheet-friendly solution for real-time daily summary tracking that integrates seamlessly with the existing CSV Combiner architecture. The CSV-based approach with lightweight state tracking ensures excellent performance while providing the convenience and accessibility required for sharing and analysis.

The incremental processing approach ensures scalability even with thousands of output rows, while the simple file formats provide reliability across network storage scenarios like OneDrive. The daily summary CSV format enables immediate use in spreadsheet applications without additional processing or conversion steps.
