"""Command-line entrypoint for csv_combiner"""
import argparse
import logging
from pathlib import Path

from .orchestrator import run_once
from .config import load_config


def build_parser():
    p = argparse.ArgumentParser(prog="csv-combiner", description="CSV Combiner (Python port)")
    p.add_argument("--config", "-c", help="Path to settings.ini", default="settings.ini")
    p.add_argument("--input-folder", help="Override input folder path")
    p.add_argument("--output-folder", help="Override output folder path")
    p.add_argument("--master-file", help="Override master file name")
    p.add_argument("--interval", type=int, help="Interval seconds (0 = run once)")
    p.add_argument("--verbose", "-v", action="store_true", help="Verbose logging")
    return p


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO)

    config_path = Path(args.config)
    cfg = load_config(config_path)

    # Apply overrides
    overrides = {}
    if args.input_folder:
        overrides["Paths.InputFolder"] = args.input_folder
    if args.output_folder:
        overrides["Paths.OutputFolder"] = args.output_folder
    if args.master_file:
        overrides["Output.MasterFileName"] = args.master_file
    if args.interval is not None:
        overrides["Execution.IntervalSeconds"] = str(args.interval)

    cfg.update(overrides)

    # Determine interval: CLI override or config
    interval = 0
    if "Execution.IntervalSeconds" in cfg and cfg["Execution.IntervalSeconds"]:
        try:
            interval = int(cfg["Execution.IntervalSeconds"])
        except Exception:
            interval = 0

    # Run once or continuously based on interval
    try:
        if interval <= 0:
            run_once(cfg)
        else:
            logging.info(f"Running continuously every {interval} seconds. Press Ctrl+C to stop.")
            import time
            while True:
                run_once(cfg)
                time.sleep(interval)
    except KeyboardInterrupt:
        logging.info("Interrupted by user. Exiting.")


if __name__ == "__main__":
    main()
