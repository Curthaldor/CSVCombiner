# CSV Combiner

A PowerShell script for efficiently merging multiple CSV files into a single master file with source tracking and memory-optimized processing.

## Features

- **Memory Efficient**: Uses streaming approach to process large files without loading everything into memory
- **Source Tracking**: Automatically adds a `SourceFile` column to track which file each row originated from
- **Smart Processing**: Checks existing output file to only process new input files, avoiding duplicates
- **Filename Filtering**: Only processes files matching YYYYMMDDHHMMSS.csv naming convention
- **Data Filtering**: Automatically filters out rows where both "Error Code" and "PassFlag" columns are empty
- **Incremental Merging**: Appends only new data to existing master files instead of reprocessing everything
- **Flexible Execution**: Run once or continuously at specified intervals
- **Configuration-Based**: Uses INI file for easy configuration management
- **Error Resilient**: Continues processing in continuous mode even when temporary file conflicts occur

## Quick Start

1. **Configure Settings**: Edit `settings.ini` to specify your input and output folders
2. **Add CSV Files**: Place your CSV files in the configured input folder
3. **Run the Script**: Execute `.\csv-merger.ps1` in PowerShell

## Configuration

The script uses `settings.ini` for configuration:

```ini
[Paths]
InputFolder=.\input
OutputFolder=.\output

[Output]
MasterFileName=master.csv

[Execution]
IntervalSeconds=0  # 0 = run once, >0 = repeat every N seconds
```

## Usage Examples

### Single Execution
```powershell
# Use default settings
.\csv-merger.ps1

# Override master file name
.\csv-merger.ps1 -MasterFileName "combined_data.csv"

# Use custom settings file
.\csv-merger.ps1 -SettingsFile ".\custom-settings.ini"
```

### Continuous Execution
Set `IntervalSeconds=30` in settings.ini to run every 30 seconds, or any desired interval.

## How It Works

### Smart Processing Logic
1. **First Run**: If no output file exists, processes all input files and creates new master file
2. **Filename Validation**: Only processes CSV files matching YYYYMMDDHHMMSS.csv format (e.g., 20250523200303.csv)
3. **Subsequent Runs**: Checks the `SourceFile` column in existing output to identify already processed files
4. **Incremental Updates**: Only processes new input files that haven't been merged yet
5. **Data Filtering**: Filters out rows where both "Error Code" and "PassFlag" columns are empty
6. **Append Mode**: New data is appended to existing master file, preserving previous results

This approach ensures efficiency and prevents duplicate data even in continuous execution mode.

- PowerShell 5.1 or later
- Read access to input folder
- Write access to output folder

## Sample Data

The `sampledata` folder contains example CSV files for testing the script functionality.

## Output Format

The merged CSV will have the following structure:
- **SourceFile**: Name of the original CSV file (automatically added)
- **[Original Columns]**: All columns from the input CSV files

## Error Handling

- **Configuration Errors**: Script exits immediately for invalid paths or missing settings
- **Single Mode**: Script exits on file write conflicts or processing errors
- **Continuous Mode**: Script logs errors and continues to next interval for file conflicts

## Version

Version 1.3-b - Minor update: normalize MAC addresses (remove `:` and `;` and whitespace), simplify daily-report deduplication to use `MAC Addr` only, and small bugfixes
