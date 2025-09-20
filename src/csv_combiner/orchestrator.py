"""High-level orchestration: runs one processing cycle"""
from pathlib import Path
import logging
from .io import unique_first_column, read_csv_objects, write_csv
from .transform import filter_rows, apply_transformations
from .report import update_daily_report, update_daily_summary
from pathlib import Path

log = logging.getLogger(__name__)


def run_once(cfg: dict):
    input_folder = Path(cfg["Paths.InputFolder"])
    output_folder = Path(cfg["Paths.OutputFolder"])
    master_name = cfg["Output.MasterFileName"]
    master_path = output_folder / master_name

    # First gate: ensure master file is accessible if it exists. If it exists but is not readable,
    # halt the run (fail-fast) so we don't accidentally process files without knowing prior state.
    if master_path.exists():
        try:
            # Attempt a small read to ensure readability
            _ = unique_first_column(master_path)
        except Exception as e:
            log.error(f"Master file '{master_path}' exists but is not readable: {e}")
            return
        processed = set(_)
    else:
        processed = set()
    log.info(f"Found {len(processed)} processed files in master")

    # list input csv files
    files = [p.name for p in input_folder.glob("*.csv") if p.is_file()]
    if not files:
        log.info("No CSV files found in input folder")
        return
    new_files = [f for f in files if f not in processed]
    if not new_files:
        log.info("No new files to process")
        return

    # Second gate: before making any changes ensure that the files we will need to write are accessible
    # (either writable if they exist, or their parent directories are writable so they can be created).
    # Determine the set of output targets we will touch for the discovered new files.
    targets = set()
    # master file will be appended
    targets.add(master_path)
    # daily report and summary/rework per file
    daily_folder = Path(cfg.get("Paths.DailyReportFolder", cfg.get("Paths.OutputFolder")))
    summary_path = Path(cfg.get("Paths.SummaryOutputFolder", cfg.get("Paths.OutputFolder"))) / cfg.get("Output.SummaryFileName", "daily_summary.csv")
    rework_path = summary_path.parent / "rework.csv"

    for fname in new_files:
        date_string = fname[:8]
        daily_file_name = f"{date_string}-report.csv"
        targets.add(daily_folder / daily_file_name)
    targets.add(summary_path)
    targets.add(rework_path)

    # Check accessibility: for each target, if it exists ensure it's writable; if it does not exist ensure parent dir is writable
    for t in targets:
        try:
            if t.exists():
                # Try opening for append to check write permission without modifying content
                with t.open("a", encoding="utf-8"):
                    pass
            else:
                # Ensure parent directory is writable (can create files)
                parent = t.parent
                parent.mkdir(parents=True, exist_ok=True)
                test_path = parent / (".writetest_" + t.name)
                try:
                    with test_path.open("w", encoding="utf-8") as fh:
                        fh.write("test")
                    test_path.unlink()
                except Exception as e:
                    raise
        except Exception as e:
            log.error(f"Preflight check failed for target '{t}': {e}")
            log.error("Aborting run to avoid partial updates")
            return

    all_new_rows = []
    for fname in new_files:
        input_path = input_folder / fname
        log.info(f"Processing {fname}")
        raw_rows = read_csv_objects(input_path)
        filtered = list(filter_rows(raw_rows))
        if not filtered:
            log.info("File had no valid rows after filtering; will append placeholder")
            placeholder = {"SourceFile": fname, "ProcessedAt": "", "Status": "NoValidData", "IP": ""}
            write_csv(master_path, [placeholder], append=True)
            continue
        processed_rows = apply_transformations(iter(filtered), fname)
        write_csv(master_path, processed_rows, append=True)
        all_new_rows.extend(processed_rows)
        # Update daily report and summary
        try:
            # derive date string from filename (first 8 chars YYYYMMDD)
            date_string = fname[:8]
            daily_file_name = f"{date_string}-report.csv"
            daily_folder = Path(cfg.get("Paths.DailyReportFolder", cfg.get("Paths.OutputFolder")))
            summary_path = Path(cfg.get("Paths.SummaryOutputFolder", cfg.get("Paths.OutputFolder"))) / cfg.get("Output.SummaryFileName", "daily_summary.csv")

            update_daily_report(daily_folder, daily_file_name, processed_rows)
            update_daily_summary(summary_path, date_string, processed_rows)
        except Exception as e:
            log.warning(f"Failed to update daily report/summary for {fname}: {e}")

    log.info(f"Processed {len(all_new_rows)} rows from {len(new_files)} new files")
    return all_new_rows
