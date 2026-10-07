#!/usr/bin/env python3
"""Replay EngulfImbalanceFlow defaults on the prepared XAUUSDm H1 series."""
from __future__ import annotations

import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
H1 = ROOT / "tests/reports/flow-xauusd-h1/h1_bars.csv"
SOURCE = ROOT / "MQL5/Indicators/EngulfImbalanceFlow"
# 2025-08-05 15:00:00 and 2026-08-05 15:00:00 on the same naive label axis as h1_bars.csv.
START_EPOCH = 1754406000  # 2025.08.05 15:00:00
END_EPOCH = 1785974400    # 2026.08.05 15:00:00, exclusive


def adapt(name: str, text: str) -> str:
    text = re.sub(r"const (WHBar|FVGBar|long|int) &(\w+)\[\]", r"const std::vector<\1> &\2", text)
    return text.replace("double bodies[];", "std::vector<double> bodies;")


def main() -> None:
    if not H1.is_file():
        raise SystemExit(f"missing H1 bars: {H1}")
    clang = shutil.which("clang++") or "clang++"
    with tempfile.TemporaryDirectory(prefix="engulf-imbalance-replay-") as build:
        build_dir = Path(build)
        (build_dir / "ei_core_adapted.hpp").write_text(
            adapt("ei", (SOURCE / "EngulfImbalanceCore.mqh").read_text()), encoding="utf-8")
        (build_dir / "dp_core_adapted.hpp").write_text(
            adapt("dp", (SOURCE / "DisplacementCore.mqh").read_text()), encoding="utf-8")
        binary = build_dir / "replay-combo"
        subprocess.run([
            clang, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
            "-I", str(build_dir), "-I", str(SOURCE),
            str(HERE / "replay_combo.cpp"), "-o", str(binary),
        ], cwd=ROOT, check=True)
        subprocess.run([
            str(binary), str(H1), str(START_EPOCH), str(END_EPOCH), str(HERE),
        ], cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
