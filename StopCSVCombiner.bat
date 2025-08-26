@echo off
REM CSV Combiner Stop Script
REM This batch file stops any running CSV combiner PowerShell scripts

echo CSV Combiner Stop Script
echo =========================

REM Change to the script directory
cd /d "%~dp0"

@echo off
setlocal enabledelayedexpansion
REM CSV Combiner Stop Script
REM This batch file stops any running CSV combiner PowerShell scripts

echo CSV Combiner Stop Script
echo =========================

REM Change to the script directory
cd /d "%~dp0"

echo Searching for CSV Combiner processes...

REM Method 1: Check PID file first (most reliable)
if exist "csvcombiner.pid" (
    set /p csvPID=<csvcombiner.pid
    echo Found PID file with PID: !csvPID!
    
    REM Check if the process is actually running
    tasklist /FI "PID eq !csvPID!" 2>nul | find "!csvPID!" >nul
    if !errorlevel! equ 0 (
        echo Stopping CSV Combiner process with PID !csvPID!...
        taskkill /PID !csvPID! /F >nul 2>&1
        if !errorlevel! equ 0 (
            echo Successfully stopped CSV Combiner process !csvPID!
            timeout /t 2 >nul
            
            REM Clean up PID file
            del "csvcombiner.pid" >nul 2>&1
            echo PID file cleaned up.
        ) else (
            echo Failed to stop process !csvPID!
        )
    ) else (
        echo PID file exists but process !csvPID! is not running.
        echo Cleaning up stale PID file...
        del "csvcombiner.pid" >nul 2>&1
    )
) else (
    echo No PID file found.
)

REM Method 2: Fallback - search for PowerShell processes with CSVCombiner in command line
echo Checking for any remaining CSV Combiner processes...
for /f "tokens=2 delims=," %%i in ('wmic process where "CommandLine like '%%CSVCombiner.ps1%%'" get ProcessId /format:csv 2^>nul ^| findstr /r "[0-9]"') do (
    echo Found additional CSV Combiner process with PID: %%i
    taskkill /PID %%i /F >nul 2>&1
    if !errorlevel! equ 0 (
        echo Successfully terminated process %%i
    )
)

echo.
echo =========================
echo CSV Combiner stop completed.
echo =========================
