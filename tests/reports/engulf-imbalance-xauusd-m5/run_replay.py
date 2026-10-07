#!/usr/bin/env python3
"""Convert Dukascopy XAUUSD M5 and replay EngulfImbalanceFlow for one year back from 2026-09-27."""
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
SOURCE = ROOT / "MQL5/Indicators/EngulfImbalanceFlow"
REPLAY = ROOT / "tests/reports/engulf-imbalance-xauusd-h1/replay_combo.cpp"
BARS = HERE / "m5_bars.csv"
START = calendar.timegm(datetime.datetime(2025, 9, 27).timetuple())
END = calendar.timegm(datetime.datetime(2026, 9, 28).timetuple())
SPREAD_POINTS = 36


def stamp(epoch):
    return datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc).strftime("%Y.%m.%d %H:%M:%S")


def source_csv() -> Path:
    matches = sorted(Path("/tmp/xau-m5").glob("xauusd-m5-bid-*.csv"))
    if not matches:
        raise SystemExit("missing Dukascopy M5 CSV in /tmp/xau-m5")
    return matches[-1]


def convert(path: Path) -> int:
    rows = []
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            epoch = int(row["timestamp"]) // 1000
            prices = [float(row[key]) for key in ("open", "high", "low", "close")]
            if not (prices[2] <= min(prices[0], prices[3]) <= max(prices[0], prices[3]) <= prices[1]):
                raise SystemExit(f"invalid OHLC at {epoch}")
            rows.append((epoch, *prices, row["volume"]))
    rows.sort()
    if any(rows[i][0] <= rows[i - 1][0] for i in range(1, len(rows))):
        raise SystemExit("M5 timestamps are not strictly increasing")
    with BARS.open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["timestamp", "epoch", "open", "high", "low", "close", "tick_volume"])
        for epoch, open_, high, low, close, volume in rows:
            writer.writerow([stamp(epoch), epoch, open_, high, low, close, volume])
    print(f"converted {len(rows)} bars {stamp(rows[0][0])} -> {stamp(rows[-1][0])}")
    return len(rows)


def adapt(text: str) -> str:
    text = re.sub(r"const (WHBar|FVGBar|long|int|double) &(\w+)\[\]", r"const std::vector<\1> &\2", text)
    return text.replace("double bodies[];", "std::vector<double> bodies;")


def replay() -> None:
    clang = shutil.which("clang++") or "clang++"
    with tempfile.TemporaryDirectory(prefix="engulf-imbalance-m5-") as build:
        build_dir = Path(build)
        (build_dir / "ei_core_adapted.hpp").write_text(adapt((SOURCE / "EngulfImbalanceCore.mqh").read_text()), encoding="utf-8")
        (build_dir / "dp_core_adapted.hpp").write_text(adapt((SOURCE / "DisplacementCore.mqh").read_text()), encoding="utf-8")
        binary = build_dir / "replay-combo"
        subprocess.run([
            clang, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
            "-I", str(build_dir), "-I", str(SOURCE),
            str(REPLAY), "-o", str(binary),
        ], cwd=ROOT, check=True)
        subprocess.run([str(binary), str(BARS), str(START), str(END), str(HERE), "300", str(SPREAD_POINTS)], cwd=ROOT, check=True)
    subprocess.run(["python3", str(REPLAY.parent / "annotate_trades.py"), str(HERE), str(BARS)], cwd=ROOT, check=True)


def main() -> None:
    convert(source_csv())
    print(f"replaying {stamp(START)} <= t < {stamp(END)}")
    replay()


if __name__ == "__main__":
    main()
