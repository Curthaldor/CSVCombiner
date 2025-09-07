# CSV Combiner v3.0 - Advanced Automated CSV File Combination Tool with StartMinimized Feature

This tool automatically monitors a folder for CSV files and combines them into a master CSV file using additive processing, perfect for consolidating data files into a OneDrive location for remote access.

## Key Features

- **Additive Processing**: Preserves existing data when source files are deleted
- **Polling-Based Monitoring**: Reliable file change detection without admin privileges
- **Unified Schema Merging**: Handles CSV files with different column structures
- **Configurable Metadata**: Optional source file name and creation time columns
- **High-Performance Processing**: Fast streaming append without data filtering
- **Optional Filename Validation**: Enforces 14-digit timestamp format (YYYYMMDDHHMMSS.csv)
- **Advanced Backup System**: Numbered backups with configurable retention
- **File Stability Checks**: Prevents processing of incomplete files
- **Simple Retry Logic**: Waits for next iteration when files are in use
- **PID-Based Process Management**: Reliable start/stop operations
- **No Admin Required**: Runs on standard Windows 11 without special permissions

## Files Included

- `CSVCombiner.ps1` - Main PowerShell script (v3.0 with StartMinimized feature and enhanced performance)
- `CSVCombiner.ini` - Configuration file with filename validation options
- `StartCSVCombiner.bat` - Batch file for easy startup with PID management
- `StopCSVCombiner.bat` - Batch file to safely stop the running process
- `README.md` - This documentation
- `TestInput/` - Sample input folder with test CSV files
- `TestOutput/` - Sample output folder for combined results

## Quick Setup

1. **Edit Configuration**:
   - Open `CSVCombiner.ini` in a text editor
   - Set `InputFolder` to the folder containing your CSV files
   - Set `OutputFolder` to your desired OneDrive location
   - Set `OutputBaseName` for the master file naming
   - Configure filename validation and metadata settings as needed

2. **Test the Script**:
   - Double-click `StartCSVCombiner.bat` to test
   - Check the console output for any errors
   - Use `StopCSVCombiner.bat` to safely stop the process

3. **Set up Automatic Startup** (Choose one method):

### Method A: Startup Folder (Easiest)
1. Press `Win + R`, type `shell:startup`, press Enter
2. Copy `StartCSVCombiner.bat` to this folder
3. The script will run automatically when you log in

### Method B: Task Scheduler (More Control)
1. Press `Win + R`, type `taskschd.msc`, press Enter
2. Click "Create Basic Task"
3. Name: "CSV Combiner"
4. Trigger: "When I log on"
5. Action: "Start a program"
6. Program: Full path to `StartCSVCombiner.bat`
7. Finish and test

## Configuration Options

Edit `CSVCombiner.ini` to customize behavior:

### Required Settings
- `InputFolder`: Folder to monitor for CSV files
- `OutputFolder`: Directory for the combined CSV files
- `OutputBaseName`: Base name for numbered output files (e.g., "MasterData" creates "MasterData_1.csv")

### Metadata Options
- `IncludeTimestamp`: Add source filename as timestamp column (true/false)

### Filename Validation Options
- `ValidateFilenameFormat`: Enforce 14-digit timestamp format YYYYMMDDHHMMSS.csv (true/false)
  - When enabled: Only files like "20250825160159.csv" will be processed
  - When disabled: Any .csv file will be processed regardless of filename

### Backup Settings
- `MaxBackups`: Number of backup copies to keep (0 = infinite, 1 = always overwrite)

### Advanced Options
- `PollingInterval`: File check frequency in seconds (default: 3)
- `UseFileHashing`: Enable MD5 hashing for change detection (true/false) - Set to false for better performance
- `WaitForStableFile`: Wait time for file stability in milliseconds (default: 2000)
- `MaxPollingRetries`: Maximum retries for locked files (default: 3)

### Optional Settings
- `LogFile`: Path for log file (leave empty to disable console-only logging)

## PowerShell Execution Policy

If you get execution policy errors:

1. **For Current User Only** (Recommended):
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

2. **Alternative**: The batch file uses `-ExecutionPolicy Bypass` to avoid this issue

## Troubleshooting

### Script Won't Start
- Check that PowerShell execution policy allows scripts
- Verify all paths in the INI file are correct and accessible
- Make sure the input folder exists

### Files Not Combining
- Check the log output for error messages
- Verify CSV files are properly formatted (headers in first row)
- If filename validation is enabled, ensure files follow YYYYMMDDHHMMSS.csv format
- Ensure you have write permissions to the output location
- Check that polling is detecting file changes (watch console output)

### Filename Validation Issues
- Check that files follow the exact format: 14 digits + .csv (e.g., "20250825160159.csv")
- Disable validation by setting `ValidateFilenameFormat=false` if needed
- Invalid examples: "data.csv", "2025-08-25.csv", "20250825.csv" (too short)

### Data Processing Notes
- **Fast Processing**: v3.0 optimized for maximum throughput and performance with StartMinimized feature
- All rows from all input files are preserved in the output
- Data is efficiently appended with minimal processing overhead
- For specialized data filtering, use external tools or previous versions

### Performance Issues
- Adjust `PollingInterval` (lower = more responsive, higher = less CPU usage)
- Set `UseFileHashing=false` to disable MD5 calculation for large files
- Increase `WaitForStableFile` if files are being processed before fully written
- Check `MaxBackups` setting if disk space is a concern

### Process Management Issues
- Use `StopCSVCombiner.bat` instead of closing PowerShell window
- Check for `csvcombiner.pid` file if script won't start
- Use Ctrl+C in PowerShell window if batch stop doesn't work

### OneDrive Issues
- Make sure OneDrive is syncing properly
- Use the local OneDrive folder path, not the web URL
- Check that you have sufficient OneDrive storage space

## Additive Processing Explained

**What is Additive Processing?**
- When a CSV file is deleted from the input folder, its data remains in the master CSV
- Only new and modified files trigger updates to the master CSV
- Existing data is preserved, making the master CSV a growing historical record

**Column Schema Merging:**
- Files with different columns are automatically merged into a unified schema
- Missing columns are filled with empty values
- Timestamp column (containing full filename) is added first for easy identification

**Example Workflow:**
1. Day 1: `sales.csv` (Name, Amount) → Master has 100 rows
2. Day 2: Add `returns.csv` (Name, Amount, Reason) → Master has 150 rows with unified schema
3. Day 3: Delete `sales.csv` from input → Master still has all 150 rows
4. Day 4: Modify `returns.csv` → Only `returns.csv` data is updated in master

## Process Management

### Starting the Script
- **Manual**: Double-click `StartCSVCombiner.bat`. Can also be used to restart the script.
- **Command Line**: `powershell -ExecutionPolicy Bypass -File CSVCombiner.ps1`

### Stopping the Script
- **Safe Stop**: Double-click `StopCSVCombiner.bat` (recommended)
- **Manual**: Press `Ctrl+C` in the PowerShell window

### Process Detection
- Script creates a PID file (`csvcombiner.pid`) for process tracking
- Start/stop batch files check for existing processes automatically
- Prevents multiple instances from running simultaneously

## How It Works

1. **Startup**: Performs initial scan and combines any existing CSV files using additive processing
2. **Monitoring**: Polling-based system checks for file changes every few seconds
3. **Change Detection**: Compares file sizes, timestamps, and optionally MD5 hashes
4. **File Stability**: Waits for files to stabilize before processing (prevents incomplete file reads)
5. **Processing**: Uses additive approach - only processes new/modified files
6. **Schema Unification**: Merges different column structures into unified master schema
7. **Backup Management**: Creates numbered backups with configurable retention
8. **Simple Retry Logic**: Waits for next iteration when files are in use

## Example OneDrive Paths

Configure your `OutputFolder` with OneDrive paths:
```
Personal OneDrive:
C:/Users/YourName/OneDrive/Documents/

Business OneDrive:
C:/Users/YourName/OneDrive - CompanyName/Documents/

Shared OneDrive:
C:/Users/YourName/OneDrive - CompanyName/Shared Documents/
```

Then set `OutputBaseName=MasterData` to create files like:
- `MasterData_1.csv` (current)
- `MasterData_2.csv` (previous backup)
- `MasterData_3.csv` (older backup)

## Security Note

This script only uses built-in Windows PowerShell features and does not require:
- Administrative privileges
- Additional software installation
- Network connections (except to OneDrive)
- Registry modifications

## Version History

### v3.0 (Current)
- **New Feature**: StartMinimized option for background operation
- **Enhanced**: Comprehensive 97-test modular test suite (100% pass rate)
- **Improved**: Enhanced batch file launchers with configuration reading
- **Refined**: Modular architecture with improved organization
- **Added**: Production-ready deployment with trusted execution options

### v2.4
- **Refactored**: Modular architecture with improved organization
- **Enhanced**: Better maintainability and code separation
- **Improved**: Module-based design for easier testing and development

### v2.3
- **Enhanced**: Optional filename format validation (14-digit timestamp format)
- **Optimized**: High-performance streaming processing
- **Improved**: Better error messages and validation feedback
- **Simplified**: Streamlined data processing workflow

### v2.2
- **Previous Version**: Alternative processing approach
- **Features**: Different data handling methodology

### v2.0-2.1
- **Foundation**: Initial additive processing implementation
- **Core Features**: Polling-based monitoring, schema merging, backup management

## Support

For issues or questions:
1. Check the console output and log files for error messages
2. Verify your configuration file settings
3. Test with a simple setup first (local folders)
4. Ensure OneDrive is working properly
