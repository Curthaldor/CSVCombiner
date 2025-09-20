# Run script for CSV Combiner (Windows PowerShell)
# Ensures a repository-level virtual environment (.venv) exists and that the package is installed.
param(
    [string[]]$ScriptArgs
)

$venvDir = Join-Path $PSScriptRoot '.venv'
$venvPython = Join-Path -Path $PSScriptRoot -ChildPath ".venv\Scripts\python.exe"

# Create .venv if missing
if (-not (Test-Path $venvPython)) {
    Write-Host "Creating virtual environment (.venv)..."
    # Use system python to create the venv
    & python -m venv $venvDir
    if (-not (Test-Path $venvPython)) {
        Write-Error "Failed to create virtual environment at $venvDir. Aborting."
        exit 1
    }
}

# Use venv python for all subsequent actions
$python = $venvPython

# Ensure package is importable in the venv; if not, install it in editable mode
$importCheck = & $python -c "import sys
try:
    import csv_combiner
    sys.stdout.write('OK')
except Exception:
    sys.stdout.write('MISSING')
"

if ($importCheck -match 'MISSING') {
    Write-Host "Installing package into .venv (editable)..."
    & $python -m pip install --upgrade pip
    & $python -m pip install -e .
}

# Build python CLI args and run (filter out internal flags like --setup)
$pyArgs = @('-m','csv_combiner.cli')
if ($ScriptArgs) {
    $filtered = @()
    foreach ($a in $ScriptArgs) { if ($a -ne '--setup') { $filtered += $a } }
    if ($filtered) { $pyArgs += $filtered }
}

& $python @pyArgs
