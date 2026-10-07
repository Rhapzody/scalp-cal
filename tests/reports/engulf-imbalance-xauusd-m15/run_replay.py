#!/usr/bin/env python3
"""Convert Dukascopy XAUUSD M15 and replay EngulfImbalanceFlow for one year back from 2026-09-27."""
from __future__ import annotations

import calendar
import csv
import datetime
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SOURCE_CSV = Path("/tmp/xau-m15/xauusd-m15-bid-2025-09-01-2026-09-27T10-57.csv")
BARS = HERE / "m15_bars.csv"
SOURCE = ROOT / "MQL5/Indicators/EngulfImbalanceFlow"
REPLAY = ROOT / "tests/reports/engulf-imbalance-xauusd-h1/replay_combo.cpp"
START = calendar.timegm(datetime.datetime(2025, 9, 27).timetuple())
END = calendar.timegm(datetime.datetime(2026, 9, 28).timetuple())
SPREAD_POINTS = 36


def stamp(epoch):
    return datetime.datetime.utcfromtimestamp(epoch).strftime("%Y.%m.%d %H:%M:%S")


def convert() -> int:
    rows = []
    with SOURCE_CSV.open(newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            epoch = int(row["timestamp"]) // 1000
            prices = [float(row[key]) for key in ("open", "high", "low", "close")]
            if not (prices[2] <= min(prices[0], prices[3]) <= max(prices[0], prices[3]) <= prices[1]):
                raise SystemExit(f"invalid OHLC at {epoch}")
            rows.append((epoch, *prices, row["volume"]))
    rows.sort()
    if any(rows[i][0] <= rows[i - 1][0] for i in range(1, len(rows))):
        raise SystemExit("M15 timestamps are not strictly increasing")
    with BARS.open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["timestamp", "epoch", "open", "high", "low", "close", "tick_volume"])
        for epoch, open_, high, low, close, volume in rows:
            writer.writerow([stamp(epoch), epoch, open_, high, low, close, volume])
    return len(rows)


def adapt(text: str) -> str:
    text = re.sub(r"const (WHBar|FVGBar|long|int|double) &(\w+)\[\]", r"const std::vector<\1> &\2", text)
    return text.replace("double bodies[];", "std::vector<double> bodies;")


def replay() -> None:
    clang = shutil.which("clang++") or "clang++"
    with tempfile.TemporaryDirectory(prefix="engulf-imbalance-m15-") as build:
        build_dir = Path(build)
        (build_dir / "ei_core_adapted.hpp").write_text(adapt((SOURCE / "EngulfImbalanceCore.mqh").read_text()), encoding="utf-8")
        (build_dir / "dp_core_adapted.hpp").write_text(adapt((SOURCE / "DisplacementCore.mqh").read_text()), encoding="utf-8")
        binary = build_dir / "replay-combo"
        subprocess.run([
            clang, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
            "-I", str(build_dir), "-I", str(SOURCE),
            str(REPLAY), "-o", str(binary),
        ], cwd=ROOT, check=True)
        subprocess.run([str(binary), str(BARS), str(START), str(END), str(HERE), "900", str(SPREAD_POINTS)], cwd=ROOT, check=True)
    subprocess.run(["python3", str(REPLAY.parent / "annotate_trades.py"), str(HERE), str(BARS)], cwd=ROOT, check=True)


def main() -> None:
    if not SOURCE_CSV.is_file():
        raise SystemExit(f"missing Dukascopy CSV: {SOURCE_CSV}")
    count = convert()
    print(f"bars {count} first-last written; replaying {stamp(START)} <= t < {stamp(END)}")
    replay()


if __name__ == "__main__":
    main()
