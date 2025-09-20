"""CSV streaming read/write utilities"""
from typing import Iterator, Tuple, List, Dict
from pathlib import Path
import csv


def _unique_headers(headers: List[str]) -> List[str]:
    seen = {}
    out = []
    for h in headers:
        h_clean = h.strip()
        if h_clean in seen:
            seen[h_clean] += 1
            out.append(f"{h_clean}{seen[h_clean]}")
        else:
            seen[h_clean] = 0
            out.append(h_clean)
    return out


def read_csv_objects(path: Path, encoding: str = "utf-8") -> Iterator[Dict[str, str]]:
    """Yield dict rows from CSV. First non-empty line is header. Handles duplicate headers."""
    if not path.exists():
        return
        yield  # keep as generator
    with path.open("r", encoding=encoding, newline="") as fh:
        reader = csv.reader(fh)
        headers = None
        for row in reader:
            # Skip empty lines
            if not any(cell.strip() for cell in row):
                continue
            if headers is None:
                headers = _unique_headers([c for c in row])
                continue
            # Pad shorter rows
            if len(row) < len(headers):
                row = row + [""] * (len(headers) - len(row))
            yield {headers[i]: row[i].strip() for i in range(len(headers))}


def unique_first_column(path: Path, encoding: str = "utf-8") -> List[str]:
    """Return unique values from first column (skip header)

    This loads unique values into a set (memory cost = number of unique items)
    """
    if not path.exists():
        return []
    seen = set()
    with path.open("r", encoding=encoding, newline="") as fh:
        reader = csv.reader(fh)
        headers_seen = False
        for row in reader:
            if not any(cell.strip() for cell in row):
                continue
            if not headers_seen:
                headers_seen = True
                continue
            first = row[0].strip() if row else ""
            if first:
                seen.add(first)
    return list(seen)


def write_csv(path: Path, rows: List[Dict[str, str]], append: bool = False, encoding: str = "utf-8") -> dict:
    """Write rows (list of dicts) to CSV. If append and file exists, merges columns.

    Returns dict with Success and Message keys.
    """
    if not rows:
        return {"Success": False, "Message": "No data provided to write"}

    out_dir = path.parent
    out_dir.mkdir(parents=True, exist_ok=True)

    file_exists = path.exists()
    write_headers = not (append and file_exists)

    # Determine full column set if appending
    if append and file_exists:
        # Read existing headers
        with path.open("r", encoding=encoding, newline="") as fh:
            r = csv.reader(fh)
            existing_headers = None
            for row in r:
                if not any(cell.strip() for cell in row):
                    continue
                existing_headers = [c for c in row]
                break
        # union
        first_row = rows[0]
        all_headers = existing_headers.copy()
        for k in first_row.keys():
            if k not in all_headers:
                all_headers.append(k)
    else:
        all_headers = list(rows[0].keys())

    mode = "a" if append else "w"
    try:
        with path.open(mode, encoding=encoding, newline="") as fh:
            writer = csv.writer(fh)
            if write_headers:
                writer.writerow(all_headers)
            for rdict in rows:
                row = [rdict.get(h, "") for h in all_headers]
                writer.writerow(row)
        return {"Success": True, "Message": f"CSV file written successfully: {path}"}
    except Exception as e:
        return {"Success": False, "Message": f"Error writing CSV file '{path}': {e}"}
