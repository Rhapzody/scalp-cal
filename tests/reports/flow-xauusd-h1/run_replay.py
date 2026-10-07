#!/usr/bin/env python3
"""Resample the public XAUUSDm M30 export and replay the shipped C++ cores."""
from __future__ import annotations

import argparse
import calendar
import csv
import hashlib
import json
import math
import re
import os
import shutil
import subprocess
import tempfile
from collections import defaultdict
from datetime import datetime
from pathlib import Path


HERE = Path(__file__).resolve().parent
DEFAULT_INPUT = Path("/private/tmp/flow-xauusd-algospecial-m30.csv")
PERIOD_START = datetime(2025, 8, 5, 15, 0, 0)
PERIOD_END = datetime(2026, 8, 5, 15, 0, 0)
REQUESTED_START = datetime(2025, 9, 27, 0, 0, 0)
REQUESTED_END = datetime(2026, 9, 28, 0, 0, 0)
SOURCE_FORMAT = "%Y.%m.%d %H:%M:%S"


def parse_source_time(text: str) -> datetime:
    return datetime.strptime(text, SOURCE_FORMAT)


def epoch_for_spacing_only(value: datetime) -> int:
    """Encode naive source labels on a fixed UTC arithmetic axis, without converting labels."""
    return calendar.timegm(value.timetuple())


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_and_resample(path: Path, h1_path: Path) -> dict:
    rows = []
    invalid_rows = 0
    duplicate_times = 0
    seen = set()
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        expected = {"Timestamp", "Open", "High", "Low", "Close", "TickVolume", "Spread"}
        if set(reader.fieldnames or []) != expected:
            raise ValueError(f"unexpected source headers: {reader.fieldnames}")
        for row in reader:
            stamp = parse_source_time(row["Timestamp"])
            if stamp in seen:
                duplicate_times += 1
                continue
            seen.add(stamp)
            try:
                o, h, low, close = (float(row[key]) for key in ("Open", "High", "Low", "Close"))
                volume = float(row["TickVolume"])
                spread = float(row["Spread"])
                valid = all(math.isfinite(v) for v in (o, h, low, close, volume, spread))
                valid = valid and low <= min(o, close) <= max(o, close) <= h
            except (ValueError, TypeError):
                valid = False
            if not valid or stamp.minute not in (0, 30) or stamp.second != 0:
                invalid_rows += 1
                continue
            rows.append({
                "time": stamp,
                "o": o,
                "h": h,
                "l": low,
                "c": close,
                "volume": volume,
                "spread": spread,
            })

    if not rows:
        raise ValueError("source CSV contains no valid M30 candles")
    rows.sort(key=lambda r: r["time"])
    by_hour: dict[datetime, dict[int, dict]] = defaultdict(dict)
    for row in rows:
        hour = row["time"].replace(minute=0, second=0, microsecond=0)
        by_hour[hour][row["time"].minute] = row

    complete = []
    incomplete_hours = 0
    for hour, parts in sorted(by_hour.items()):
        if set(parts) != {0, 30}:
            incomplete_hours += 1
            continue
        first, second = parts[0], parts[30]
        complete.append({
            "time": hour,
            "o": first["o"],
            "h": max(first["h"], second["h"]),
            "l": min(first["l"], second["l"]),
            "c": second["c"],
            "volume": first["volume"] + second["volume"],
            "spread": max(first["spread"], second["spread"]),
        })
    if not complete:
        raise ValueError("no complete H1 candles could be formed from paired M30 rows")

    # Keep the replay file causal through the final verified bar. The raw
    # export ends at an M30 15:30 label, but has no retrieval timestamp to
    # prove that the 15:00 H1 aggregate was closed; exclude that final hour.
    replay_bars = [bar for bar in complete if bar["time"] < PERIOD_END]
    with h1_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["timestamp", "epoch", "open", "high", "low", "close", "tick_volume"])
        for bar in replay_bars:
            writer.writerow([
                bar["time"].strftime(SOURCE_FORMAT),
                epoch_for_spacing_only(bar["time"]),
                format(bar["o"], ".10g"),
                format(bar["h"], ".10g"),
                format(bar["l"], ".10g"),
                format(bar["c"], ".10g"),
                format(bar["volume"], ".10g"),
            ])

    full_year = [
        bar for bar in complete
        if PERIOD_START <= bar["time"] < PERIOD_END
    ]
    requested_subset = [
        bar for bar in complete
        if REQUESTED_START <= bar["time"] < PERIOD_END
    ]
    return {
        "source_rows": len(seen),
        "invalid_rows": invalid_rows,
        "duplicate_timestamps": duplicate_times,
        "source_first": rows[0]["time"],
        "source_last": rows[-1]["time"],
        "hour_bins": len(by_hour),
        "complete_h1_bars": len(complete),
        "incomplete_h1_bins": incomplete_hours,
        "complete_first": complete[0]["time"],
        "complete_last": complete[-1]["time"],
        "replay_h1_bars": len(replay_bars),
        "replay_last": replay_bars[-1]["time"] if replay_bars else None,
        "full_year_bars": len(full_year),
        "full_year_first": full_year[0]["time"] if full_year else None,
        "full_year_last": full_year[-1]["time"] if full_year else None,
        "requested_subset_bars": len(requested_subset),
        "requested_subset_first": requested_subset[0]["time"] if requested_subset else None,
        "requested_subset_last": requested_subset[-1]["time"] if requested_subset else None,
        "complete": complete,
    }


def count_rows(path: Path) -> dict:
    counts = defaultdict(int)
    with path.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            if "side" in row:
                counts[row["side"]] += 1
            if "component" in row:
                counts[row["component"]] += 1
    return dict(counts)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT, help="M30 source CSV from Algo Special")
    parser.add_argument("--output", type=Path, default=HERE, help="directory for replay outputs")
    parser.add_argument("--clang", default=shutil.which("clang++") or "clang++", help="C++17 compiler")
    args = parser.parse_args()
    source = args.input.expanduser().resolve()
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    if not source.is_file():
        raise SystemExit(
            f"missing source CSV: {source}\n"
            "Download it from https://www.algospecial.com/historical-data/XAUUSDm_PERIOD_M30_OHLC.csv"
        )

    h1_path = output / "h1_bars.csv"
    data = load_and_resample(source, h1_path)
    year_bars = [b for b in data["complete"] if PERIOD_START <= b["time"] < PERIOD_END]
    if not year_bars:
        raise SystemExit("source does not overlap the agreed one-year fallback interval")

    with tempfile.TemporaryDirectory(prefix="flow-xauusd-h1-") as build_dir:
        executable = Path(build_dir) / "flow-replay"
        repo_root = HERE.parents[2]
        displacement = repo_root / "MQL5/Indicators/ImbalanceFlow/DisplacementCore.mqh"
        adapted = displacement.read_text(encoding="utf-8")
        adapted = re.sub(
            r"const (FVGBar|long) &(\w+)\[\]",
            r"const std::vector<\1> &\2",
            adapted,
        ).replace("double bodies[];", "std::vector<double> bodies;")
        (Path(build_dir) / "dp_core_adapted.hpp").write_text(adapted, encoding="utf-8")
        subprocess.run([
            args.clang, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
            "-I", str(build_dir),
            "-I", str(repo_root / "MQL5/Indicators/ImbalanceFlow"),
            str(HERE / "replay_cores.cpp"), "-o", str(executable),
        ], cwd=repo_root, check=True)
        start = epoch_for_spacing_only(PERIOD_START)
        end = epoch_for_spacing_only(PERIOD_END)
        subprocess.run([
            str(executable), str(h1_path), str(start), str(end), str(output),
        ], cwd=repo_root, check=True)

    engulf_path = output / "engulf_events.csv"
    imbalance_path = output / "imbalance_events.csv"
    with engulf_path.open(newline="", encoding="utf-8") as handle:
        engulf_rows = list(csv.DictReader(handle))
    with imbalance_path.open(newline="", encoding="utf-8") as handle:
        imbalance_rows = list(csv.DictReader(handle))
    engulf_counts = defaultdict(int)
    for row in engulf_rows:
        engulf_counts[row["side"]] += 1
    imbalance_counts = defaultdict(int)
    imbalance_by_side = defaultdict(int)
    for row in imbalance_rows:
        imbalance_counts[row["component"]] += 1
        imbalance_by_side[row["side"]] += 1
    unique_imbalance_bars = len({row["timestamp"] for row in imbalance_rows})
    subset_start_epoch = epoch_for_spacing_only(REQUESTED_START)
    subset_rows = [
        row for row in engulf_rows
        if subset_start_epoch <= epoch_for_spacing_only(parse_source_time(row["timestamp"]))
        < epoch_for_spacing_only(PERIOD_END)
    ]
    subset_imbalance = [
        row for row in imbalance_rows
        if subset_start_epoch <= epoch_for_spacing_only(parse_source_time(row["timestamp"]))
        < epoch_for_spacing_only(PERIOD_END)
    ]
    summary = {
        "source": {
            "download_url": "https://www.algospecial.com/historical-data/XAUUSDm_PERIOD_M30_OHLC.csv",
            "description_url": "https://www.algospecial.com/blogs/xauusd-historical-dataset-free-download.php",
            "sha256": sha256(source),
            "source_file": source.name,
            "timezone": "unspecified broker server time; original labels retained",
            "source_rows": data["source_rows"],
            "source_first": data["source_first"].strftime(SOURCE_FORMAT),
            "source_last": data["source_last"].strftime(SOURCE_FORMAT),
            "invalid_rows": data["invalid_rows"],
            "duplicate_timestamps": data["duplicate_timestamps"],
        },
        "aggregation": {
            "source_timeframe": "M30",
            "target_timeframe": "H1",
            "rule": "require bars at :00 and :30; H1 open=first open, high=max, low=min, close=second close; volumes summed",
            "complete_h1_bars": data["complete_h1_bars"],
            "incomplete_h1_bins_excluded": data["incomplete_h1_bins"],
            "complete_first": data["complete_first"].strftime(SOURCE_FORMAT),
            "complete_last": data["complete_last"].strftime(SOURCE_FORMAT),
            "h1_replay_bars_excluding_unverified_final_hour": data["replay_h1_bars"],
            "replay_last": data["replay_last"].strftime(SOURCE_FORMAT),
            "unverified_final_hour_excluded": True,
            "numeric_time_axis": "naive source labels encoded on a fixed UTC arithmetic axis only for 3600-second continuity checks; no timezone conversion",
        },
        "study_period": {
            "start_inclusive": PERIOD_START.strftime(SOURCE_FORMAT),
            "end_exclusive": PERIOD_END.strftime(SOURCE_FORMAT),
            "bars": len(year_bars),
            "first_bar": data["full_year_first"].strftime(SOURCE_FORMAT),
            "last_bar": data["full_year_last"].strftime(SOURCE_FORMAT),
            "source_cutoff_gap": "requested through 2026-09-27; no available source bars after 2026-08-05",
        },
        "original_requested_period_available_subset": {
            "start_inclusive": REQUESTED_START.strftime(SOURCE_FORMAT),
            "end_through_latest_available": data["requested_subset_last"].strftime(SOURCE_FORMAT) if data["requested_subset_last"] else None,
            "bars": data["requested_subset_bars"],
            "engulf_signals": len(subset_rows),
            "imbalance_components": len(subset_imbalance),
            "imbalance_signal_bars": len({row["timestamp"] for row in subset_imbalance}),
        },
        "defaults": {
            "EngulfFlow": {
                "hunt_bars": 1,
                "engulf_mode": "body",
                "prior_move_filter": False,
                "ema_filter": False,
                "confirmation": "closed H1 bar only",
            },
            "ImbalanceFlow": {
                "lookback_bars": 500,
                "detection_mode": "FVG_AND_DISPLACEMENT",
                "fvg_min_gap_points": 0,
                "fvg_middle_direction_required": False,
                "fvg_fill_mode": "FULL",
                "show_filled": False,
                "displacement_method": "SINGLE_OR_LEG",
                "atr_length": 14,
                "reject_time_gaps": True,
                "single_body_atr": 0.8,
                "single_body_ratio": 0.7,
                "single_max_directional_tail_ratio": 0.15,
                "min_relative_body": 0,
                "leg_bars": "2..4",
                "min_leg_atr": 1.5,
                "min_efficiency": 0.75,
                "min_direction_ratio": 0.66,
                "max_leg_tail_ratio": 0.2,
                "require_breakout": True,
                "breakout_bars": 5,
                "breakout_buffer_atr": 0.1,
                "zone": "BASE_WICK",
                "confirmed_closed_bars_only": True,
                "deduplicate_source_direction_each_rolling_window": True,
            },
        },
        "results": {
            "engulf_signal_bars": len(engulf_rows),
            "engulf_buy": engulf_counts["BUY"],
            "engulf_sell": engulf_counts["SELL"],
            "imbalance_components": dict(imbalance_counts),
            "imbalance_by_side": dict(imbalance_by_side),
            "imbalance_distinct_signal_bars": unique_imbalance_bars,
        },
        "interpretation": "indicator signal replay only; no entry/exit strategy, costs, slippage, or profitability claim",
    }
    (output / "summary.json").write_text(json.dumps(summary, indent=2, default=str) + "\n", encoding="utf-8")
    print(json.dumps({
        "source_sha256": summary["source"]["sha256"],
        "source_rows": data["source_rows"],
        "complete_h1_bars": data["complete_h1_bars"],
        "study_bars": len(year_bars),
        "study_first": summary["study_period"]["first_bar"],
        "study_last": summary["study_period"]["last_bar"],
        "engulf": dict(engulf_counts),
        "imbalance_components": dict(imbalance_counts),
        "imbalance_signal_bars": unique_imbalance_bars,
        "outputs": [str(h1_path), str(engulf_path), str(imbalance_path), str(output / "summary.json")],
    }, indent=2))


if __name__ == "__main__":
    main()
