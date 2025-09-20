"""Deduplication utilities"""
from typing import List, Dict


def remove_duplicates(csv_data: List[Dict[str, str]], key_columns: List[str]) -> List[Dict[str, str]]:
    """Remove duplicates keeping last occurrence. Works in-memory for given list."""
    if not csv_data:
        return []
    # Validate columns exist not enforced here
    seen = set()
    result = []
    # iterate reverse and keep first seen
    for row in reversed(csv_data):
        key_parts = []
        for k in key_columns:
            v = row.get(k, "")
            if v == "":
                key_parts.append("NULL")
            else:
                key_parts.append(v)
        composite = "|".join(key_parts)
        if composite not in seen:
            seen.add(composite)
            result.append(row)
    # reverse back to original order
    result.reverse()
    return result
