from pathlib import Path
from csv_combiner.report import update_daily_report, update_daily_summary


def test_update_daily_report(tmp_path: Path):
    daily_folder = tmp_path
    filename = "20250920-report.csv"
    new_rows = [{"MAC Addr": "A", "PassFlag": "Passed"}, {"MAC Addr": "B", "PassFlag": ""}]
    res = update_daily_report(daily_folder, filename, new_rows)
    assert res["Success"]
    # file exists
    p = daily_folder / filename
    assert p.exists()


def test_update_daily_summary(tmp_path: Path):
    summary_path = tmp_path / "daily_summary.csv"
    date_string = "20250920"
    new_rows = [{"MAC Addr": "A", "PassFlag": "Passed"}, {"MAC Addr": "B", "PassFlag": ""}]
    res = update_daily_summary(summary_path, date_string, new_rows)
    assert res["Success"]
    assert summary_path.exists()
    # read file to confirm values
    content = summary_path.read_text()
    assert "2025-09-20" in content
    assert "Passed" in content or "1" in content
