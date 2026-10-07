#!/usr/bin/env python3
"""Render 30 PAReversalTrader backtest trades as annotated M5/EMA20 charts.

The script deliberately uses only the Python standard library.  It reads the
same audit CSV and Dukascopy M5 bid data used by the replay backtest, writes
one SVG/PNG per selected trade, and builds three 10-chart contact sheets.
"""

from __future__ import annotations

import argparse
import bisect
import csv
import html
import math
import os
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DATA_PATH = Path("/private/tmp/duka_xauusd_m5/xauusd-m5-bid-2025-09-19-2026-09-19.csv")
AUDIT_PATH = ROOT / "docs/experts/pa-reversal-trader/backtest-3m-audit.csv"
OUT_DIR = ROOT / "docs/experts/pa-reversal-trader/charts-30"


def esc(value: object) -> str:
    return html.escape(str(value), quote=True)


def num(value: str) -> float:
    return float(value)


def parse_time(value: str) -> datetime:
    return datetime.strptime(value, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)


def read_market() -> list[dict]:
    market: list[dict] = []
    with DATA_PATH.open(newline="") as handle:
        for row in csv.DictReader(handle):
            ts_ms = int(row["timestamp"])
            market.append(
                {
                    "ts": ts_ms,
                    "dt": datetime.fromtimestamp(ts_ms / 1000, tz=timezone.utc),
                    "open": num(row["open"]),
                    "high": num(row["high"]),
                    "low": num(row["low"]),
                    "close": num(row["close"]),
                }
            )
    return market


def read_trades() -> list[dict]:
    with AUDIT_PATH.open(newline="") as handle:
        rows = [row for row in csv.DictReader(handle) if row["status"] == "EXECUTED"]
    return rows


def ema20(market: list[dict]) -> list[float]:
    alpha = 2.0 / 21.0
    values: list[float] = []
    previous = 0.0
    for i, bar in enumerate(market):
        previous = bar["close"] if i == 0 else previous + alpha * (bar["close"] - previous)
        values.append(previous)
    return values


def nearest_index(timestamps: list[int], dt: datetime) -> int:
    target = int(dt.timestamp() * 1000)
    pos = bisect.bisect_left(timestamps, target)
    if pos <= 0:
        return 0
    if pos >= len(timestamps):
        return len(timestamps) - 1
    before = pos - 1
    return before if target - timestamps[before] <= timestamps[pos] - target else pos


def choose_trades(trades: list[dict], count: int = 30) -> list[tuple[int, dict]]:
    if len(trades) <= count:
        return [(i + 1, trade) for i, trade in enumerate(trades)]
    # Evenly spaced chronological sample, including the first and last trade.
    selected: list[tuple[int, dict]] = []
    for sample in range(count):
        source_index = round(sample * (len(trades) - 1) / (count - 1))
        selected.append((source_index + 1, trades[source_index]))
    return selected


def fmt_dt(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%d %H:%M")


def svg_chart(
    sample_no: int,
    source_no: int,
    trade: dict,
    market: list[dict],
    ema: list[float],
    timestamps: list[int],
) -> str:
    signal_dt = parse_time(trade["signal_time"])
    entry_dt = parse_time(trade["entry_time"])
    exit_dt = parse_time(trade["exit_time"])
    signal_idx = nearest_index(timestamps, signal_dt)
    entry_idx = nearest_index(timestamps, entry_dt)
    exit_idx = nearest_index(timestamps, exit_dt)

    left = max(0, signal_idx - 36)
    right = min(len(market), max(entry_idx, exit_idx) + 30)
    if right - left < 84:
        right = min(len(market), left + 84)
    if right - left > 180:
        left = max(0, entry_idx - 55)
        right = min(len(market), exit_idx + 25)

    bars = market[left:right]
    ema_values = ema[left:right]
    sl = num(trade["sl"])
    tp = num(trade["tp"])
    entry = num(trade["entry"])
    levels = [sl, tp, entry] + ema_values
    pmin = min([bar["low"] for bar in bars] + levels)
    pmax = max([bar["high"] for bar in bars] + levels)
    spread = max((pmax - pmin) * 0.08, 0.5)
    pmin -= spread
    pmax += spread

    width, height = 1500, 900
    plot_left, plot_top = 82, 116
    plot_right, plot_bottom = 1260, 800
    plot_width = plot_right - plot_left
    plot_height = plot_bottom - plot_top
    slot = plot_width / max(1, len(bars))
    candle_width = max(3.0, slot * 0.62)

    def x_for(index: int) -> float:
        return plot_left + (index - left + 0.5) * slot

    def y_for(price: float) -> float:
        return plot_top + (pmax - price) / (pmax - pmin) * plot_height

    side = trade["side"]
    result = trade["result"]
    result_color = "#39d353" if result == "TP" else "#ff6672"
    title = f"PA Reversal Trader  |  sample {sample_no:02d}  |  trade #{source_no}  |  {side}  |  {result}"
    signal_ema = num(trade["ema20"])
    plotted_signal_ema = ema[signal_idx]

    out: list[str] = []
    out.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">')
    out.append('<rect width="100%" height="100%" fill="#0f1724"/>')
    out.append(f'<text x="38" y="38" fill="#f8fafc" font-family="Arial, sans-serif" font-size="25" font-weight="700">{esc(title)}</text>')
    out.append(f'<text x="38" y="68" fill="#aab7c8" font-family="Arial, sans-serif" font-size="16">M5 bid OHLC  |  UTC  |  fixed spread 0.30  |  EMA20 shown in gold</text>')

    # Plot frame and horizontal grid.
    out.append(f'<rect x="{plot_left}" y="{plot_top}" width="{plot_width}" height="{plot_height}" fill="#121c2b" stroke="#35445a"/>')
    for grid in range(6):
        ratio = grid / 5.0
        y = plot_top + ratio * plot_height
        price = pmax - ratio * (pmax - pmin)
        out.append(f'<line x1="{plot_left}" y1="{y:.1f}" x2="{plot_right}" y2="{y:.1f}" stroke="#28374b" stroke-width="1"/>')
        out.append(f'<text x="{plot_right + 16}" y="{y + 5:.1f}" fill="#aab7c8" font-family="Arial, sans-serif" font-size="14">{price:.2f}</text>')

    # Signal, entry, and exit markers.
    for idx, label, color in (
        (signal_idx, "SIGNAL", "#f0a34b"),
        (entry_idx, "ENTRY", "#60a5fa"),
        (exit_idx, "EXIT", result_color),
    ):
        if left <= idx < right:
            x = x_for(idx)
            out.append(f'<line x1="{x:.1f}" y1="{plot_top}" x2="{x:.1f}" y2="{plot_bottom}" stroke="{color}" stroke-width="1.5" stroke-dasharray="7,6" opacity="0.85"/>')
            out.append(f'<text x="{x + 5:.1f}" y="{plot_top + 20}" fill="{color}" font-family="Arial, sans-serif" font-size="12" transform="rotate(90 {x + 5:.1f},{plot_top + 20})">{label}</text>')

    # Candles.
    for idx, bar in enumerate(bars):
        absolute = left + idx
        x = x_for(absolute)
        bullish = bar["close"] >= bar["open"]
        color = "#22c55e" if bullish else "#ef5350"
        out.append(f'<line x1="{x:.1f}" y1="{y_for(bar["high"]):.1f}" x2="{x:.1f}" y2="{y_for(bar["low"]):.1f}" stroke="{color}" stroke-width="1.5"/>')
        top = y_for(max(bar["open"], bar["close"]))
        bottom = y_for(min(bar["open"], bar["close"]))
        body_height = max(1.5, bottom - top)
        out.append(f'<rect x="{x - candle_width / 2:.1f}" y="{top:.1f}" width="{candle_width:.1f}" height="{body_height:.1f}" fill="{color}" opacity="0.95"/>')

    # EMA20 path.
    path = " ".join(("M" if i == 0 else "L") + f" {x_for(left + i):.1f} {y_for(value):.1f}" for i, value in enumerate(ema_values))
    out.append(f'<path d="{path}" fill="none" stroke="#f4c95d" stroke-width="3"/>')

    # Entry marker.
    if left <= entry_idx < right:
        x = x_for(entry_idx)
        y = y_for(entry)
        if side == "BUY":
            points = f"{x:.1f},{y + 15:.1f} {x - 9:.1f},{y + 30:.1f} {x + 9:.1f},{y + 30:.1f}"
        else:
            points = f"{x:.1f},{y - 15:.1f} {x - 9:.1f},{y - 30:.1f} {x + 9:.1f},{y - 30:.1f}"
        out.append(f'<polygon points="{points}" fill="#60a5fa" stroke="#e2e8f0" stroke-width="1"/>')

    # Trading levels.
    for price, label, color, dash in (
        (sl, "SL", "#ff6672", "8,5"),
        (entry, "ENTRY", "#60a5fa", "3,4"),
        (tp, "TP", "#39d9ff", "8,5"),
    ):
        y = y_for(price)
        out.append(f'<line x1="{plot_left}" y1="{y:.1f}" x2="{plot_right}" y2="{y:.1f}" stroke="{color}" stroke-width="1.7" stroke-dasharray="{dash}" opacity="0.9"/>')
        out.append(f'<text x="{plot_right + 16}" y="{y + 5:.1f}" fill="{color}" font-family="Arial, sans-serif" font-size="14" font-weight="700">{label} {price:.2f}</text>')

    # X-axis labels.
    x_ticks = [0, len(bars) // 2, len(bars) - 1]
    for idx in x_ticks:
        bar = bars[idx]
        x = x_for(left + idx)
        out.append(f'<line x1="{x:.1f}" y1="{plot_bottom}" x2="{x:.1f}" y2="{plot_bottom + 7}" stroke="#9aa8bb"/>')
        out.append(f'<text x="{x:.1f}" y="{plot_bottom + 28}" text-anchor="middle" fill="#aab7c8" font-family="Arial, sans-serif" font-size="13">{bar["dt"].strftime("%d %b %H:%M")}</text>')

    # Analysis panel.
    panel_x, panel_y = 38, 835
    info = (
        f"Signal {fmt_dt(signal_dt)}  |  Entry {fmt_dt(entry_dt)}  |  Exit {fmt_dt(exit_dt)}   "
        f"Entry {entry:.3f}  SL {sl:.3f}  TP {tp:.3f}  RR {num(trade['rr']):.2f}  R {num(trade['r_multiple']):+.2f}"
    )
    out.append(f'<text x="{panel_x}" y="{panel_y}" fill="#e2e8f0" font-family="Arial, sans-serif" font-size="15">{esc(info)}</text>')
    note = f"Audit EMA20 {signal_ema:.3f}  |  plotted EMA20 {plotted_signal_ema:.3f}  |  ATR {num(trade['atr']):.3f}  |  held {trade['bars_held']} M5 bars"
    out.append(f'<text x="{panel_x}" y="{panel_y + 27}" fill="#f4c95d" font-family="Arial, sans-serif" font-size="15">{esc(note)}</text>')
    out.append('</svg>')
    return "\n".join(out)


def convert_svg(svg_path: Path, png_path: Path) -> None:
    converter = shutil.which("rsvg-convert")
    if not converter:
        return
    subprocess.run([converter, "-o", str(png_path), str(svg_path)], check=True)


def make_contact_sheet(pngs: list[Path], output: Path) -> None:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg or not pngs:
        return
    # ffmpeg's concat demuxer preserves the explicit chronological sample order.
    list_file = output.with_suffix(".concat.txt")
    with list_file.open("w") as handle:
        for png in pngs:
            handle.write(f"file '{png.as_posix()}'\n")
    subprocess.run(
        [
            ffmpeg,
            "-y",
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
            str(list_file),
            "-frames:v",
            "1",
            "-vf",
            "tile=5x2:padding=10:margin=10",
            "-q:v",
            "2",
            str(output),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    list_file.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="Render PA Reversal Trader backtest trade charts")
    parser.add_argument("--count", type=int, default=30, help="number of executed trades to render")
    parser.add_argument("--out-dir", type=Path, default=OUT_DIR, help="output directory")
    args = parser.parse_args()
    if args.count < 1:
        raise SystemExit("--count must be positive")
    output_dir = args.out_dir if args.out_dir.is_absolute() else ROOT / args.out_dir
    if not DATA_PATH.exists():
        raise SystemExit(f"Missing market data: {DATA_PATH}")
    if not AUDIT_PATH.exists():
        raise SystemExit(f"Missing audit file: {AUDIT_PATH}")
    output_dir.mkdir(parents=True, exist_ok=True)
    for old in output_dir.glob("trade-*.svg"):
        old.unlink()
    for old in output_dir.glob("trade-*.png"):
        old.unlink()
    for old in output_dir.glob("contact-sheet-*.png"):
        old.unlink()

    market = read_market()
    trades = read_trades()
    timestamps = [bar["ts"] for bar in market]
    ema = ema20(market)
    selected = choose_trades(trades, args.count)
    pngs: list[Path] = []
    index_rows: list[dict] = []

    for sample_no, (source_no, trade) in enumerate(selected, start=1):
        svg_path = output_dir / f"trade-{sample_no:02d}.svg"
        png_path = output_dir / f"trade-{sample_no:02d}.png"
        svg_path.write_text(svg_chart(sample_no, source_no, trade, market, ema, timestamps), encoding="utf-8")
        convert_svg(svg_path, png_path)
        pngs.append(png_path)
        index_rows.append(
            {
                "sample": sample_no,
                "source_trade": source_no,
                "signal_time_utc": trade["signal_time"],
                "entry_time_utc": trade["entry_time"],
                "exit_time_utc": trade["exit_time"],
                "side": trade["side"],
                "result": trade["result"],
                "entry": trade["entry"],
                "sl": trade["sl"],
                "tp": trade["tp"],
                "rr": trade["rr"],
                "r_multiple": trade["r_multiple"],
                "ema20": trade["ema20"],
                "atr": trade["atr"],
                "image": png_path.name,
            }
        )

    with (output_dir / "index.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(index_rows[0]))
        writer.writeheader()
        writer.writerows(index_rows)

    for start in range(0, len(pngs), 10):
        group = pngs[start : start + 10]
        make_contact_sheet(group, output_dir / f"contact-sheet-{start // 10 + 1:02d}.png")

    readme = output_dir / "README.md"
    readme.write_text(
        f"# PA Reversal Trader: {len(selected)} backtest trade charts\n\n"
        f"ภาพเลือกแบบ chronological evenly spaced จาก {len(trades)} executed trades ใน replay 3 เดือน "
        "แต่ละภาพเป็น XAUUSD M5 bid OHLC จริง พร้อม EMA20 (เส้นสีทอง), signal, entry, SL, TP และ exit\n\n"
        f"- `contact-sheet-01.png` ถึง `contact-sheet-{(len(selected) + 9) // 10:02d}.png`: ภาพรวม 10 trades ต่อแผ่น\n"
        f"- `trade-01.png` ถึง `trade-{len(selected):02d}.png`: ภาพแยกราย trade\n"
        "- `index.csv`: mapping ของ sample กับข้อมูลผลลัพธ์\n",
        encoding="utf-8",
    )
    print(f"Rendered {len(pngs)} trades into {output_dir}")


if __name__ == "__main__":
    main()
