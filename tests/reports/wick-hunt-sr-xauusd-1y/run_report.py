#!/usr/bin/env python3
"""Replay WickHuntSRFlow's shipped C++ core on one year of XAUUSD M1 bid data."""
from __future__ import annotations

import argparse
import calendar
import csv
import datetime as dt
import gzip
import hashlib
import json
import math
import shutil
import subprocess
import sys
import tempfile
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
DEFAULT_INPUT = ROOT / "tests/reports/engulf-imbalance-xauusd-m1/xauusd_m1_bid_ask.csv.gz"
START = dt.datetime(2025, 9, 25, 21, 0, tzinfo=dt.timezone.utc)
END = dt.datetime(2026, 9, 25, 21, 0, tzinfo=dt.timezone.utc)
SOURCE_FORMAT = "%Y.%m.%d %H:%M:%S"


def epoch(value: dt.datetime) -> int:
    return calendar.timegm(value.utctimetuple())


def stamp(value: int) -> str:
    return dt.datetime.fromtimestamp(value, dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def validate_ohlc(row: dict[str, str], prefix: str = "bid") -> tuple[float, float, float, float]:
    o, h, low, close = (float(row[f"{prefix}_{key}"]) for key in ("open", "high", "low", "close"))
    if not all(math.isfinite(v) for v in (o, h, low, close)) or low > min(o, close) or max(o, close) > h:
        raise ValueError(f"invalid {prefix} OHLC at {row['timestamp']}: {(o, h, low, close)}")
    return o, h, low, close


def read_source(path: Path) -> tuple[list[dict], dict]:
    rows: list[dict] = []
    duplicate_times = 0
    invalid_rows = 0
    gaps: Counter[int] = Counter()
    previous = None
    with gzip.open(path, "rt", newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        required = {"timestamp", "epoch", "bid_open", "bid_high", "bid_low", "bid_close",
                    "ask_open", "ask_high", "ask_low", "ask_close", "spread_close"}
        if set(reader.fieldnames or []) != required:
            raise ValueError(f"unexpected input columns: {reader.fieldnames}")
        for row in reader:
            t = int(row["epoch"])
            if previous is not None:
                delta = t - previous
                if delta <= 0:
                    duplicate_times += int(delta == 0)
                    invalid_rows += int(delta < 0)
                    continue
                if delta != 60:
                    gaps[delta] += 1
            validate_ohlc(row, "bid")
            validate_ohlc(row, "ask")
            rows.append({
                "time": t,
                "open": float(row["bid_open"]),
                "high": float(row["bid_high"]),
                "low": float(row["bid_low"]),
                "close": float(row["bid_close"]),
            })
            previous = t
    if not rows:
        raise ValueError("input has no usable M1 bars")
    stats = {
        "rows": len(rows),
        "duplicate_timestamps": duplicate_times,
        "invalid_rows": invalid_rows,
        "first_bar_open_utc": stamp(rows[0]["time"]),
        "last_bar_open_utc": stamp(rows[-1]["time"]),
        "source_gaps_seconds": {str(k): v for k, v in sorted(gaps.items())},
    }
    return rows, stats


def aggregate(rows: list[dict], seconds: int) -> list[dict]:
    bars: dict[int, dict] = {}
    for row in rows:
        start = row["time"] // seconds * seconds
        if start not in bars:
            bars[start] = {
                "time": start,
                "first_minute_time": row["time"],
                "open": row["open"], "high": row["high"],
                "low": row["low"], "close": row["close"], "minute_count": 1,
            }
        else:
            bar = bars[start]
            bar["high"] = max(bar["high"], row["high"])
            bar["low"] = min(bar["low"], row["low"])
            bar["close"] = row["close"]
            bar["minute_count"] += 1
    return [bars[t] for t in sorted(bars)]


def write_bars(path: Path, bars: list[dict]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["timestamp_utc", "epoch", "open", "high", "low", "close", "source_m1_count"])
        for b in bars:
            writer.writerow([stamp(b["time"]), b["time"], *(format(b[k], ".10g") for k in ("open", "high", "low", "close")), b["minute_count"]])


def compile_and_replay(input_path: Path, output_dir: Path, start: int, end: int, compiler: str) -> tuple[dict, list[dict]]:
    core_dir = ROOT / "MQL5/Indicators/WickHuntSRFlow"
    with tempfile.TemporaryDirectory(prefix="wick-hunt-sr-xauusd-") as tmp:
        tmp_path = Path(tmp)
        plain_m1 = tmp_path / "m1_bid.csv"
        with gzip.open(input_path, "rb") as source, plain_m1.open("wb") as target:
            shutil.copyfileobj(source, target)
        executable = tmp_path / "wick-hunt-replay"
        subprocess.run([
            compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
            "-I", str(core_dir), str(HERE / "replay.cpp"), "-o", str(executable),
        ], cwd=ROOT, check=True)
        raw_events = tmp_path / "events_raw.csv"
        diagnostics_path = output_dir / "replay_diagnostics.json"
        subprocess.run([
            str(executable), str(plain_m1), str(raw_events), str(diagnostics_path), str(start), str(end),
        ], cwd=ROOT, check=True)
        diagnostics = json.loads(diagnostics_path.read_text(encoding="utf-8"))
        with raw_events.open(newline="", encoding="utf-8") as handle:
            raw_rows = list(csv.DictReader(handle))
    return diagnostics, raw_rows


def enrich_events(raw_rows: list[dict], m5_bars: list[dict], output_path: Path) -> list[dict]:
    m5_by_time = {bar["time"]: bar for bar in m5_bars}
    rows = []
    columns = [
        "event_time_utc", "sample_kind", "setup_time_utc", "direction", "price", "sr_price",
        "sr_type", "breakout_m5_open_utc", "pivot_m5_open_utc", "swing_confirm_m5_open_utc",
        "h1_open", "prior_h1_low", "prior_h1_high", "reclaim_observed_snapshot_utc",
        "breakout_observed_snapshot_utc", "event_order", "breakout_m5_complete",
        "pivot_m5_complete", "confirmation_m5_complete", "all_reference_m5_complete",
        "event_epoch", "setup_epoch", "breakout_epoch", "pivot_epoch", "confirm_epoch",
        "reclaim_epoch", "breakout_observed_epoch", "month_utc",
    ]
    for raw in raw_rows:
        event = {k: int(raw[k]) for k in ("event_time", "setup_time", "break_time", "pivot_time", "confirm_time",
                                          "reclaim_observed_time", "breakout_observed_time")}
        break_time = event["break_time"]
        pivot_time = event["pivot_time"]
        confirm_time = event["confirm_time"]
        pivot_bar = m5_by_time.get(pivot_time)
        confirm_bar = m5_by_time.get(confirm_time)
        break_bar = m5_by_time.get(break_time)
        evdt = dt.datetime.fromtimestamp(event["event_time"], dt.timezone.utc)
        row = {
            "event_time_utc": stamp(event["event_time"]),
            "sample_kind": raw["sample_kind"],
            "setup_time_utc": stamp(event["setup_time"]),
            "direction": "BUY" if int(raw["direction"]) == 1 else "SELL",
            "price": raw["price"],
            "sr_price": raw["sr"],
            "sr_type": "Swing H" if int(raw["sr_type"]) == 1 else "Swing L",
            "breakout_m5_open_utc": stamp(break_time),
            "pivot_m5_open_utc": stamp(pivot_time),
            "swing_confirm_m5_open_utc": stamp(confirm_time),
            "h1_open": raw["hunt_open"],
            "prior_h1_low": raw["prior_low"],
            "prior_h1_high": raw["prior_high"],
            "reclaim_observed_snapshot_utc": stamp(event["reclaim_observed_time"]),
            "breakout_observed_snapshot_utc": stamp(event["breakout_observed_time"]),
            "event_order": raw["event_order"],
            "breakout_m5_complete": int(raw["breakout_m5_complete"]),
            "pivot_m5_complete": int(bool(pivot_bar and pivot_bar["minute_count"] == 5)),
            "confirmation_m5_complete": int(bool(confirm_bar and confirm_bar["minute_count"] == 5)),
            "all_reference_m5_complete": int(bool(break_bar and pivot_bar and confirm_bar and
                break_bar["minute_count"] == 5 and pivot_bar["minute_count"] == 5 and
                confirm_bar["minute_count"] == 5)),
            "event_epoch": event["event_time"],
            "setup_epoch": event["setup_time"],
            "breakout_epoch": break_time,
            "pivot_epoch": pivot_time,
            "confirm_epoch": confirm_time,
            "reclaim_epoch": event["reclaim_observed_time"],
            "breakout_observed_epoch": event["breakout_observed_time"],
            "month_utc": evdt.strftime("%Y-%m"),
        }
        rows.append(row)
    with output_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns)
        writer.writeheader()
        writer.writerows(rows)
    return rows


def grouped_counts(rows: list[dict], key: str) -> dict:
    counts = Counter(r[key] for r in rows)
    return dict(sorted(counts.items()))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT, help="Dukascopy M1 bid/ask CSV.gz")
    parser.add_argument("--output", type=Path, default=HERE)
    parser.add_argument("--compiler", default=shutil.which("clang++") or shutil.which("g++") or "clang++")
    args = parser.parse_args()
    source = args.input.expanduser().resolve()
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    if not source.is_file():
        raise SystemExit(f"missing source dataset: {source}")

    data, data_stats = read_source(source)
    start, end = epoch(START), epoch(END)
    if data[0]["time"] > start or data[-1]["time"] + 60 < end:
        raise SystemExit("dataset does not cover the selected 365-day study interval")
    rows_in_window = [r for r in data if start <= r["time"] < end]
    study_gaps = Counter()
    prev = None
    for row in data:
        if prev is not None and start < row["time"] < end and row["time"] - prev != 60:
            study_gaps[row["time"] - prev] += 1
        prev = row["time"]

    h1_bars = aggregate(data, 3600)
    m5_bars = aggregate(data, 300)
    write_bars(output / "h1_bars.csv", h1_bars)
    write_bars(output / "m5_bars.csv", m5_bars)
    compiler = shutil.which(args.compiler) or args.compiler
    diagnostics, raw_events = compile_and_replay(source, output, start, end, compiler)
    events = enrich_events(raw_events, m5_bars, output / "events.csv")
    audit_target_is_canonical = output == HERE.resolve() and source == DEFAULT_INPUT.resolve()
    independent_audit = None
    if audit_target_is_canonical:
        subprocess.run([sys.executable, str(HERE / "audit_events.py")], cwd=ROOT, check=True)
        independent_audit = json.loads((output / "independent-audit.json").read_text(encoding="utf-8"))

    monthly = defaultdict(Counter)
    signals_by_setup = defaultdict(set)
    for row in events:
        monthly[row["month_utc"]][row["direction"]] += 1
        monthly[row["month_utc"]]["total"] += 1
        signals_by_setup[row["setup_epoch"]].add(row["direction"])
    with (output / "monthly.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["month_utc", "buy", "sell", "total"])
        for month in sorted(monthly):
            writer.writerow([month, monthly[month]["BUY"], monthly[month]["SELL"], monthly[month]["total"]])

    h1_window = [b for b in h1_bars if start <= b["time"] < end]
    m5_window = [b for b in m5_bars if start <= b["time"] < end]
    source_lines = {
        name: sha256(ROOT / "MQL5/Indicators/WickHuntSRFlow" / name)
        for name in ("WickHuntSRFlow.mq5", "WickHuntSRCore.mqh", "SwingCore.mqh")
    }
    summary = {
        "indicator": "WickHuntSRFlow 1.01",
        "symbol": "XAUUSD",
        "signal_timeframe": "M5",
        "hunt_timeframe": "H1",
        "study_window_utc": {"start_inclusive": START.isoformat(), "end_exclusive": END.isoformat(),
                             "duration_days": (END - START).days},
        "data_coverage_utc": data_stats,
        "data": {
            "source": "Dukascopy XAUUSD M1 bid/ask OHLC, UTC offset 0",
            "prepared_path": str(source.relative_to(ROOT)) if source.is_relative_to(ROOT) else str(source),
            "prepared_sha256": sha256(source),
            "study_m1_rows": len(rows_in_window),
            "study_source_gaps_seconds": {str(k): v for k, v in sorted(study_gaps.items())},
            "h1_groups_in_study": len(h1_window),
            "h1_complete_60m1_in_study": sum(b["minute_count"] == 60 for b in h1_window),
            "h1_partial_in_study": sum(b["minute_count"] != 60 for b in h1_window),
            "m5_groups_in_study": len(m5_window),
            "m5_complete_5m1_in_study": sum(b["minute_count"] == 5 for b in m5_window),
            "m5_partial_in_study": sum(b["minute_count"] != 5 for b in m5_window),
        },
        "production_source_sha256": source_lines,
        "settings": {
            "InpHuntTF": "PERIOD_H1", "InpSignalTF": "PERIOD_M5", "InpHuntBars": 1,
            "MACD": "EMA 12/26/9 on M5 Close", "swing_mode": "Histogram color",
            "warmup": "automatic 34 M5 bars; seed from available 2025-09-01 history",
            "InpSRCount": 10, "InpSRAnchor": "MS_SR_WICK", "InpHistoryBars": 0,
            "price_side": "Bid for OHLC charts; minute open/close used as sampled quotes",
            "event_order": "H1 hunt/open reclaim first; M5 close strictly later in the same H1",
            "m5_open_before_reclaim": "allowed only when the close occurs strictly after reclaim",
        },
        "replay": {
            **diagnostics,
            "counts_by_direction": grouped_counts(events, "direction"),
            "counts_by_sr_type": grouped_counts(events, "sr_type"),
            "counts_by_event_order": grouped_counts(events, "event_order"),
            "distinct_signal_h1_setups": len(signals_by_setup),
            "h1_setups_with_both_directions": sum(len(sides) == 2 for sides in signals_by_setup.values()),
            "fully_complete_pivot_confirmation_break_events": sum(r["all_reference_m5_complete"] for r in events),
            "fully_complete_events_by_direction": {
                side: sum(r["all_reference_m5_complete"] and r["direction"] == side for r in events)
                for side in ("BUY", "SELL")
            },
            "events_using_partial_m5_pivot_or_confirmation": sum(not r["all_reference_m5_complete"] for r in events),
            "monthly_counts": {month: dict(counts) for month, counts in sorted(monthly.items())},
            "commands": [
                "python3 tests/reports/wick-hunt-sr-xauusd-1y/run_report.py",
                "python3 tests/reports/wick-hunt-sr-xauusd-1y/audit_events.py",
                "python3 tests/reports/wick-hunt-sr-xauusd-1y/build_gallery.py",
            ],
            "independent_audit": independent_audit or {
                "status": "not_run",
                "reason": "audit_events.py is bound to the bundled dataset and default report directory; run it manually only for that canonical output.",
            },
        },
        "interpretation": [
            "This is a causal one-minute snapshot reconstruction using the shipped C++ core, not MT5 Strategy Tester or tick replay.",
            "Only M1 open and representative minute-end close snapshots are observed; quotes between them can be missed.",
            "Minute timestamps are bucket labels; minute-end snapshot times are assigned at :59 and are not exact tick timestamps.",
            "H1/M5 bars are reconstructed from this same Dukascopy M1 feed; no source bars are filled across gaps.",
            "Incomplete prior H1 references and current H1 bars whose first M1 label is not the hour boundary suppress setups.",
            "Incomplete M5 bars are excluded from breakout checks but still update the MACD swing engine from their available OHLC.",
            "The dataset ends 2026-09-25 21:00 UTC, before the current date; this is the latest exact 365-day window supported by it.",
            "Counts measure signal observations only; they are not entries, win rate, or profitability.",
        ],
        "artifacts": {name: sha256(output / name) for name in
                      ("events.csv", "monthly.csv", "h1_bars.csv", "m5_bars.csv")},
    }
    if independent_audit is not None:
        summary["artifacts"]["independent-audit.json"] = sha256(output / "independent-audit.json")
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"window": summary["study_window_utc"], "signals": len(events),
                      "by_direction": summary["replay"]["counts_by_direction"],
                      "by_sr_type": summary["replay"]["counts_by_sr_type"],
                      "diagnostics": diagnostics}, indent=2))


if __name__ == "__main__":
    main()
