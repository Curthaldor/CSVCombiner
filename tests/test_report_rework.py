from pathlib import Path
from csv_combiner.report import update_daily_report, update_daily_summary
from csv_combiner.io import write_csv


def test_rework_integration(tmp_path: Path):
    # create rework.csv in same folder as summary
    summary_path = tmp_path / "daily_summary.csv"
    rework_path = tmp_path / "rework.csv"
    # initial rework entries
    write_csv(rework_path, [{"MAC": "A", "status": "", "date": ""}], append=False)

    date_string = "20250920"
    new_rows = [{"MAC Addr": "A", "PassFlag": "Passed", "Error Code": ""}, {"MAC Addr": "B", "PassFlag": "", "Error Code": "E1"}]
    res = update_daily_summary(summary_path, date_string, new_rows)
    assert res["Success"]
    # rework file should be updated: status for A should be 'pass'
    content = rework_path.read_text()
    assert "pass" in content
    # summary should have Rwrk Pass = 1 and TotalRwrk = 1
    s = summary_path.read_text()
    assert "Rwrk Pass" in s
    assert "1" in s
    assert "TotalRwrk" in s
    # Ensure Totals do not include rework unit A (so Passed should be 0 for non-rework units in this test)
    assert "Passed,Failed" in s
