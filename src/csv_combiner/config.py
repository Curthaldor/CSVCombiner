"""Configuration loader and validator for csv_combiner"""
from configparser import ConfigParser
from pathlib import Path
import sys


REQUIRED_SETTINGS = ["Paths.InputFolder", "Paths.OutputFolder", "Output.MasterFileName"]


def load_config(path: Path) -> dict:
    """Load INI into a simple dict of Section.Key -> value"""
    if not path.exists():
        raise FileNotFoundError(f"Config file not found: {path}")
    cp = ConfigParser()
    # preserve option name case (INI keys are case-sensitive for our config keys)
    cp.optionxform = str
    cp.read(path)
    out = {}
    for section in cp.sections():
        for k, v in cp[section].items():
            out[f"{section}.{k}"] = v
    # Also include top-level items if any
    for k, v in cp.defaults().items():
        out[k] = v
    validate_config(out)
    return out


def validate_config(cfg: dict) -> None:
    # Check required
    for r in REQUIRED_SETTINGS:
        if r not in cfg or not cfg[r]:
            print(f"Required setting missing: {r}", file=sys.stderr)
            raise ValueError(f"Required setting missing: {r}")

    # Validate paths: require input folder to exist; create output folders if missing
    input_key = "Paths.InputFolder"
    if input_key in cfg and cfg[input_key]:
        p_in = Path(cfg[input_key])
        if not p_in.exists():
            raise ValueError(f"Input folder does not exist: {p_in} (setting: {input_key})")

    # Ensure output folders exist (create if needed)
    for k in ("Paths.OutputFolder", "Paths.SummaryOutputFolder", "Paths.DailyReportFolder"):
        if k in cfg and cfg[k]:
            p = Path(cfg[k])
            try:
                p.mkdir(parents=True, exist_ok=True)
            except Exception:
                raise ValueError(f"Unable to create or access path: {p} (setting: {k})")

    # Validate interval
    if "Execution.IntervalSeconds" in cfg and cfg["Execution.IntervalSeconds"]:
        try:
            iv = int(cfg["Execution.IntervalSeconds"])
        except Exception:
            raise ValueError("Execution.IntervalSeconds must be an integer")
        if iv < 0:
            raise ValueError("Execution.IntervalSeconds must be non-negative")
    # Basic filename character validation omitted for brevity
