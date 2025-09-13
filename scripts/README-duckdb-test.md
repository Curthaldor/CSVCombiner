DuckDB test harness

This folder contains a small PowerShell harness to verify DuckDB functionality on Windows.

Files:
- `test_duckdb.ps1` - Main test script. It expects `duckdb.exe` to be installed (default path `C:\Tools\duckdb\duckdb.exe`) or pass `-DuckDbExe`.
- `sample_input.csv` - Created automatically by the script if missing.

Usage:
```powershell
# From repository root
.\scripts\test_duckdb.ps1

# If duckdb.exe is in a custom location:
.\scripts\test_duckdb.ps1 -DuckDbExe "C:\path\to\duckdb.exe"
```

What it does:
1. Creates a small DuckDB database `master.duckdb` in the repo root.
2. Imports `sample_input.csv` into a table named `master`.
3. Runs a small aggregation and writes `output_test.csv` next to the script.

Exit codes:
- `0` success
- `2` duckdb.exe not found
- `3` output CSV not created

