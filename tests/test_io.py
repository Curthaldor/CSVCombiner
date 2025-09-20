import tempfile
from pathlib import Path
from csv_combiner.io import read_csv_objects, write_csv, unique_first_column


def test_read_write_roundtrip(tmp_path: Path):
    p = tmp_path / "input.csv"
    p.write_text("col1,col2\nA,1\nB,2\n")

    rows = list(read_csv_objects(p))
    assert len(rows) == 2
    assert rows[0]["col1"] == "A"

    out = tmp_path / "out.csv"
    res = write_csv(out, rows)
    assert res["Success"]

    u = unique_first_column(out)
    # unique_first_column skips header -> first column values
    assert set(u) == {"A", "B"}
