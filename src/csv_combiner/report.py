"""Daily report and summary utilities"""
from pathlib import Path
from typing import List, Dict
from .io import read_csv_objects, write_csv
from .dedupe import remove_duplicates
from datetime import datetime
from pathlib import Path
import json


def update_daily_report(daily_folder: Path, filename: str, new_rows: List[Dict[str, str]]) -> dict:
    """Combine existing daily report and new_rows, dedupe by 'MAC Addr', and overwrite daily file.

    filename: name like 'YYYYMMDD-report.csv' or date string used to build filename
    """
    daily_path = daily_folder / filename
    existing = list(read_csv_objects(daily_path)) if daily_path.exists() else []
    combined = existing + new_rows
    deduped = remove_duplicates(combined, ["MAC Addr"]) if combined else []
    return write_csv(daily_path, deduped)


def update_daily_summary(summary_path: Path, date_string: str, daily_rows: List[Dict[str, str]]) -> dict:
    """Update a summary CSV with counts for date_string (YYYYMMDD or YYYY-MM-DD).

    Summary columns: Date, TotalDevices, Passed, Failed, PassRate
    """
    # Normalize date
    try:
        if len(date_string) == 8:
            parsed = datetime.strptime(date_string, "%Y%m%d").date()
        else:
            parsed = datetime.strptime(date_string, "%Y-%m-%d").date()
    except Exception:
        parsed = datetime.now().date()
    date_str = parsed.isoformat()

    existing = list(read_csv_objects(summary_path)) if summary_path.exists() else []

    # Try to locate rework.csv in the same folder as the summary (or next to it)
    rework_path = summary_path.parent / "rework.csv"
    rework_map = {}
    if rework_path.exists():
        for r in read_csv_objects(rework_path):
            mac = r.get("MAC") or r.get("MAC Addr") or r.get("MACAddr")
            if mac:
                rework_map[mac] = r
    rework_updated = False

    pass_count = 0
    fail_count = 0
    rwrk_pass = 0
    rwrk_fail = 0
    total_rwrk = 0
    for r in daily_rows:
        pf = r.get("PassFlag", "").strip()
        # If this unit is in rework list, update rework status/date and count
        mac = r.get("MAC Addr") or r.get("MAC")
        if mac and mac in rework_map:
            # It's a rework unit: increment rework counters, update rework file, but do NOT include in main totals
            total_rwrk += 1
            if pf == "Passed":
                rework_map[mac]["status"] = "pass"
                rwrk_pass += 1
            else:
                # Use Error Code if present, otherwise generic fail
                err = r.get("Error Code", r.get("ErrorCode", "Failed"))
                rework_map[mac]["status"] = err or "Failed"
                rwrk_fail += 1
            # Update date to now (ISO format)
            rework_map[mac]["date"] = datetime.now().isoformat(sep=" ", timespec="seconds")
        else:
            # Not a rework unit: count toward main totals
            if pf == "Passed":
                pass_count += 1
            else:
                fail_count += 1
            rework_updated = True
    total = pass_count + fail_count
    pass_rate = round((pass_count / total) * 100, 2) if total > 0 else 0

    # Update or append
    updated = False
    for row in existing:
        if row.get("Date") == date_str:
            row["TotalDevices"] = str(total)
            row["Passed"] = str(pass_count)
            row["Failed"] = str(fail_count)
            row["PassRate"] = str(pass_rate)
            # Add rework counts
            row["Rwrk Pass"] = str(rwrk_pass)
            row["Rwrk Fail"] = str(rwrk_fail)
            row["TotalRwrk"] = str(total_rwrk)
            updated = True
            break
    if not updated:
        new = {"Date": date_str, "TotalDevices": str(total), "Passed": str(pass_count), "Failed": str(fail_count), "PassRate": str(pass_rate)}
        new["Rwrk Pass"] = str(rwrk_pass)
        new["Rwrk Fail"] = str(rwrk_fail)
        new["TotalRwrk"] = str(total_rwrk)
        existing.append(new)

    # Sort by date descending
    existing.sort(key=lambda r: r.get("Date", ""), reverse=True)
    res = write_csv(summary_path, existing)
    # If rework entries were modified, write them back to rework.csv with standard headers
    if rework_updated and rework_map:
        rows = []
        for mac, entry in rework_map.items():
            rows.append({
                "MAC": mac,
                "status": str(entry.get("status", "")),
                "date": str(entry.get("date", "")),
            })
        write_csv(rework_path, rows, append=False)
    return res
