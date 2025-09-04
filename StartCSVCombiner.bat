@echo off
setlocal enabledelayedexpansion
REM CSV Combiner Startup Script
REM This batch file starts the PowerShell CSV combiner script
REM If the script is already running, it will be stopped and restarted

echo CSV Combiner Management Script
echo ===============================

REM Change to the script directory
cd /d "%~dp0"

REM Check if PowerShell execution policy allows scripts (informational only)
echo Checking PowerShell execution policy...
powershell -Command "Write-Host 'Current execution policy:' (Get-ExecutionPolicy); if ((Get-ExecutionPolicy) -eq 'Restricted') { Write-Host 'Note: Execution policy is Restricted, but we will use -ExecutionPolicy Bypass to run the script safely.' }"

REM Check if CSV Combiner is already running using PID file
echo Checking for existing CSV Combiner processes...
if exist "csvcombiner.pid" (
    set /p existingPID=<csvcombiner.pid
    echo Found PID file with PID: !existingPID!
    
    REM Check if the process is actually running
    tasklist /FI "PID eq !existingPID!" 2>nul | find "!existingPID!" >nul
    if !errorlevel! equ 0 (
        echo CSV Combiner is already running with PID !existingPID!. Stopping it first...
        taskkill /PID !existingPID! /F >nul 2>&1
        timeout /t 3 >nul
        echo Stopped existing CSV Combiner process.
    ) else (
        echo PID file exists but process is not running. Cleaning up stale PID file...
        del "csvcombiner.pid" >nul 2>&1
    )
) else (
    echo No PID file found - no existing CSV Combiner processes detected.
)

REM Start the PowerShell script with proper signal handling
echo Starting CSV Combiner...
echo Use Ctrl+C to stop the CSV Combiner when needed.
echo.

REM Launch PowerShell in background without waiting for user input
start "CSV Combiner" powershell -WindowStyle Normal -ExecutionPolicy Bypass -Command "& '.\CSVCombiner.ps1' -ConfigPath 'CSVCombiner.ini' -Monitor"

echo CSV Combiner started in background with continuous monitoring.
echo Use StopCSVCombiner.bat to stop it safely.
echo.
timeout /t 3 >nul
