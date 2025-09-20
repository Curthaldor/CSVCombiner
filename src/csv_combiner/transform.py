"""Data transformation utilities"""
from typing import Iterator, Dict, List
import re

PRIORITY_COLUMNS = [
    "SourceFile", "PassFlag", "Error Code", "Miner Type", "MAC Addr",
    "PCB SN0", "PCB SN1", "PCB SN2", "ChipData0", "ChipData1", "ChipData2", "Miner SN", "Power SN",
]


def filter_rows(rows: Iterator[Dict[str, str]]) -> Iterator[Dict[str, str]]:
    """Keep rows where either 'Error Code' or 'PassFlag' has a value"""
    for r in rows:
        ec = r.get("Error Code", "").strip()
        pf = r.get("PassFlag", "").strip()
        if ec or pf:
            yield r


def normalize_mac(mac: str) -> str:
    if not mac:
        return ""
    # remove colons, semicolons, whitespace
    return re.sub(r"[:;\s]", "", mac).strip()


def parse_chip_data(all_data: str) -> List[str]:
    """Split Chip Data (All) by '_' and remove dash-digit part from the first token"""
    if not all_data:
        return ["", "", ""]
    parts = all_data.split("_")
    def clean(text):
        text = text.strip()
        # remove first dash-digit sequence (part number)
        return re.sub(r"-\d+(?=\s)|-\d+$", "", text).strip()
    out = [clean(parts[0]) if len(parts) > 0 else "",
           clean(parts[1]) if len(parts) > 1 else "",
           clean(parts[2]) if len(parts) > 2 else ""]
    return out


def apply_transformations(rows: Iterator[Dict[str, str]], source_filename: str) -> List[Dict[str, str]]:
    """Return a list of transformed rows (small memory hit per-file)."""
    out = []
    for r in rows:
        new = {k: v for k, v in r.items()}
        new["SourceFile"] = source_filename
        chip_all = new.get("Chip Data (All)", "")
        chip0, chip1, chip2 = parse_chip_data(chip_all)
        new["ChipData0"] = chip0
        new["ChipData1"] = chip1
        new["ChipData2"] = chip2
        if "MAC Addr" in new:
            new["MAC Addr"] = normalize_mac(new.get("MAC Addr", ""))
        out.append(new)
    # reorder columns: priority first
    reordered = []
    for row in out:
        nr = {}
        for c in PRIORITY_COLUMNS:
            if c in row:
                nr[c] = row[c]
        for k, v in row.items():
            if k not in nr:
                nr[k] = v
        reordered.append(nr)
    return reordered
