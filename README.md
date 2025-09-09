# CSV Combiner

A PowerShell script for efficiently merging multiple CSV files into a single master file with source tracking and memory-optimized processing.

## Features

- **Memory Efficient**: Uses streaming approach to process large files without loading everything into memory
- **Source Tracking**: Automatically adds a `SourceFile` column to track which file each row originated from
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

## Requirements

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

Version 2.0 - Complete rewrite with streaming architecture and enhanced error handling
