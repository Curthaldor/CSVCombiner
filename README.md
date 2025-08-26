# CSV Combiner v2.0 - Advanced Automated CSV File Combination Tool

This tool automatically monitors a folder for CSV files and combines them into a master CSV file using additive processing, perfect for consolidating data files into a OneDrive location for remote access.

## Key Features

- **Additive Processing**: Preserves existing data when source files are deleted
- **Polling-Based Monitoring**: Reliable file change detection without admin privileges
- **Unified Schema Merging**: Handles CSV files with different column structures
- **Configurable Metadata**: Optional source file name and creation time columns
- **Duplicate Removal**: Optional deduplication based on data content
- **Advanced Backup System**: Numbered backups with configurable retention
- **File Stability Checks**: Prevents processing of incomplete files
- **Persistent Popup Handling**: Handles file-in-use scenarios gracefully
- **PID-Based Process Management**: Reliable start/stop operations
- **Static Configuration**: Settings loaded once at startup for predictable behavior
- **No Admin Required**: Runs on standard Windows 11 without special permissions

## Files Included

- `CSVCombiner.ps1` - Main PowerShell script (v2.0 with additive processing)
- `CSVCombiner.ini` - Configuration file with advanced options
- `StartCSVCombiner.bat` - Batch file for easy startup with PID management
- `StopCSVCombiner.bat` - Batch file to safely stop the running process
- `ForceStopCSVCombiner.bat` - Emergency stop batch file
- `README.md` - This documentation

## Quick Setup

1. **Edit Configuration**:
   - Open `CSVCombiner.ini` in a text editor
   - Set `InputFolder` to the folder containing your CSV files
   - Set `OutputFolder` to your desired OneDrive location
   - Set `OutputBaseName` for the master file naming
   - Adjust metadata and duplicate removal settings as needed

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
- `IncludeSourceFile`: Add source filename column (true/false)
- `IncludeFileCreationTime`: Add file creation timestamp column (true/false)
- `RemoveDuplicates`: Remove duplicate rows based on data content (true/false)

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
- Ensure you have write permissions to the output location
- Check that polling is detecting file changes (watch console output)

### Duplicate Data Issues
- Enable `RemoveDuplicates=true` in configuration (requires metadata columns)
- Verify that `IncludeSourceFile=true` and `IncludeFileCreationTime=true`
- Check that data columns are consistent across CSV files

### Performance Issues
- Adjust `PollingInterval` (lower = more responsive, higher = less CPU usage)
- Set `UseFileHashing=false` to disable MD5 calculation for large files
- Increase `WaitForStableFile` if files are being processed before fully written
- Check `MaxBackups` setting if disk space is a concern

### Configuration Changes
- **Static Configuration**: Settings are loaded once at startup
- **To Change Settings**: Stop the script, edit `CSVCombiner.ini`, then restart
- **No Dynamic Reloading**: Ensures predictable behavior and simplified operation

### Process Management Issues
- Use `StopCSVCombiner.bat` instead of closing PowerShell window
- Check for `csvcombiner.pid` file if script won't start
- Use `ForceStopCSVCombiner.bat` if normal stop doesn't work

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
- Metadata columns (SourceFile, FileCreationTime) are added first for easy identification

**Example Workflow:**
1. Day 1: `sales.csv` (Name, Amount) → Master has 100 rows
2. Day 2: Add `returns.csv` (Name, Amount, Reason) → Master has 150 rows with unified schema
3. Day 3: Delete `sales.csv` from input → Master still has all 150 rows
4. Day 4: Modify `returns.csv` → Only `returns.csv` data is updated in master

## Process Management

### Starting the Script
- **Manual**: Double-click `StartCSVCombiner.bat` (launches in background and auto-closes)
- **Command Line**: `powershell -ExecutionPolicy Bypass -File CSVCombiner.ps1`

### Stopping the Script
- **Safe Stop**: Double-click `StopCSVCombiner.bat` (auto-closes after completion)
- **Emergency Stop**: Double-click `ForceStopCSVCombiner.bat` (force kills process)
- **Manual**: Press `Ctrl+C` in the PowerShell window

### Process Detection
- Script creates a PID file (`csvcombiner.pid`) for process tracking
- Start/stop batch files check for existing processes automatically
- Prevents multiple instances from running simultaneously
- All batch files close automatically without requiring user input

## How It Works

1. **Startup**: Loads configuration once and performs initial scan of existing CSV files
2. **Monitoring**: Polling-based system checks for file changes at configured intervals
3. **Change Detection**: Compares file sizes, timestamps, and optionally MD5 hashes
4. **File Stability**: Waits for files to stabilize before processing (prevents incomplete file reads)
5. **Processing**: Uses additive approach - only processes new/modified files
6. **Schema Unification**: Merges different column structures into unified master schema
7. **Backup Management**: Creates numbered backups with configurable retention
8. **Static Configuration**: Settings remain constant throughout the session for predictable behavior

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

## Testing and Development

The project includes test files for development and validation:

### Test Setup
- `TestInput/` folder contains sample CSV files for testing
- `TestOutput/` folder will contain the generated master CSV files
- Configure `InputFolder=./TestInput` and `OutputFolder=./TestOutput` for testing

### Sample Test Data
- Test files contain employee data with consistent schema
- Demonstrates additive processing and schema merging
- Shows metadata column functionality (SourceFile, FileCreationTime)

### Debugging
- Script includes comprehensive logging for troubleshooting
- Console output shows detailed processing information
- Optional log file creation for persistent logging

## Security Note

This script only uses built-in Windows PowerShell features and does not require:
- Administrative privileges
- Additional software installation
- Network connections (except to OneDrive)
- Registry modifications

## Support

For issues or questions:
1. Check the console output and log files for error messages
2. Verify your configuration file settings
3. Test with a simple setup first (local folders)
4. Ensure OneDrive is working properly
