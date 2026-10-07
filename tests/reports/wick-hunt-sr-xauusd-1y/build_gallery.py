#!/usr/bin/env python3
"""Build balanced M5/H1 snapshot charts from the reproducible WickHunt replay."""
from __future__ import annotations

import csv
import argparse
import bisect
import gzip
import hashlib
import html
import json
import math
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


HERE = Path(__file__).resolve().parent
DATA = HERE.parent / "engulf-imbalance-xauusd-m1/xauusd_m1_bid_ask.csv.gz"
OUT = HERE / "gallery"
WIDTH, HEIGHT = 2400, 2100
BG = "#0b1019"
PANEL = "#111a27"
GRID = "#293546"
TEXT = "#e7edf4"
MUTED = "#9aabbe"
UP = "#38c889"
DOWN = "#ee6675"
SR = "#60d5ff"
H1_OPEN = "#f4c95d"
PRIOR = "#bd8cff"
SIGNAL = "#ffffff"
RECLAIM = "#ff9dca"
MACD_BLUE = "#2962ff"
SIGNAL_ORANGE = "#ff6d00"
HISTOGRAM_COLORS = ("#26a69a", "#b2dfdb", "#ffcdd2", "#ff5252")


def calculate_tv_macd() -> dict[int, dict]:
    root = HERE.parents[2]
    compiler = shutil.which("clang++") or shutil.which("g++")
    if not compiler:
        raise RuntimeError("C++ compiler required for the production TV Style MACD core")
    with tempfile.TemporaryDirectory(prefix="wick-hunt-tv-macd-") as directory:
        executable = Path(directory) / "tv-macd"
        subprocess.run([compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
                        "-I", str(root / "MQL5/Indicators/TVStyleMACD"),
                        "-I", str(root / "MQL5/Indicators/WickHuntSRFlow"),
                        str(HERE / "tv_macd.cpp"), "-o", str(executable)], check=True)
        subprocess.run([str(executable), str(HERE / "m5_bars.csv"), str(HERE / "m5_macd.csv")], check=True)
    return {int(r["epoch"]): {k: float(r[k]) for k in ("macd", "signal", "histogram", "color_index")}
            for r in read_csv(HERE / "m5_macd.csv")}


def draw_macd(draw: ImageDraw.ImageDraw, bars: list[dict], xs: list[float], values: dict[int, dict],
              top: int, bottom: int, markers: list, x_by_time, histogram_width: int,
              following_x: float | None = None) -> None:
    left, right = 105, WIDTH - 120
    draw.rectangle((left, top, right, bottom), fill=PANEL)
    draw.text((left + 8, top + 8), "TV Style MACD · M5 · EMA 12 / 26 / 9 · Close", fill=TEXT, font=font(25, True))
    draw.text((left + 8, top + 41), "MACD", fill=MACD_BLUE, font=font(18, True))
    draw.text((left + 100, top + 41), "Signal", fill=SIGNAL_ORANGE, font=font(18, True))
    for i, label in enumerate(("Hist + rising", "Hist + falling", "Hist - rising", "Hist - falling")):
        draw.text((left + 210 + i * 180, top + 41), label, fill=HISTOGRAM_COLORS[i], font=font(17, True))
    series = [values[int(b["epoch"])] for b in bars]
    extrema = [0.0] + [row[k] for row in series for k in ("macd", "signal", "histogram")]
    padding = max((max(extrema) - min(extrema)) * .09, .01)
    low, high = min(extrema) - padding, max(extrema) + padding
    ytop, ybottom = top + 82, bottom - 28
    for i in range(5):
        price = high - (high - low) * i / 4
        y = price_y(price, low, high, ytop, ybottom)
        draw.line((left, y, right, y), fill=GRID)
        draw.text((right + 14, y - 10), f"{price:.4f}", fill=MUTED, font=font(17))
    zero = price_y(0, low, high, ytop, ybottom)
    draw.line((left, zero, right, zero), fill="#787b86", width=2)
    for x, row in zip(xs, series):
        y = price_y(row["histogram"], low, high, ytop, ybottom)
        color = HISTOGRAM_COLORS[int(row["color_index"])]
        draw.rectangle((x - histogram_width // 2, min(zero, y), x + histogram_width // 2, max(zero, y)), fill=color)
    for key, color in (("macd", MACD_BLUE), ("signal", SIGNAL_ORANGE)):
        points = [(x, price_y(row[key], low, high, ytop, ybottom)) for x, row in zip(xs, series)]
        if len(points) > 1:
            draw.line(points, fill=color, width=3)
    for time, label, color, width in markers:
        x = int(x_by_time(time))
        draw.line((x, ytop, x, ybottom), fill=color, width=1)
    if following_x is not None:
        draw.line((following_x, ytop, following_x, ybottom), fill=RECLAIM, width=1)
    for i in range(min(9, len(bars))):
        index = round(i * (len(bars) - 1) / max(1, min(9, len(bars)) - 1))
        label = time_label(int(bars[index]["epoch"]), date=True)
        box = draw.textbbox((0, 0), label, font=font(16))
        draw.text((xs[index] - (box[2] - box[0]) // 2, bottom - 20), label, fill=MUTED, font=font(16))


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = [
        Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf"),
        Path("/System/Library/Fonts/Supplemental/Arial.ttf"),
    ]
    for candidate in candidates:
        if candidate.is_file():
            return ImageFont.truetype(str(candidate), size=size)
    return ImageFont.load_default(size=size)


def read_csv(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def read_m1() -> dict[int, dict]:
    rows = {}
    with gzip.open(DATA, "rt", newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            t = int(row["epoch"])
            rows[t] = {
                "time": t,
                "open": float(row["bid_open"]), "high": float(row["bid_high"]),
                "low": float(row["bid_low"]), "close": float(row["bid_close"]),
            }
    return rows


def time_label(t: int, date: bool = False) -> str:
    import datetime as dt
    fmt = "%m-%d %H:%M" if date else "%H:%M"
    return dt.datetime.fromtimestamp(t, dt.timezone.utc).strftime(fmt)


def price_y(price: float, low: float, high: float, y0: int, y1: int) -> int:
    if high <= low:
        high = low + 1e-6
    return round(y1 - (price - low) / (high - low) * (y1 - y0))


def draw_candles(draw: ImageDraw.ImageDraw, bars: list[dict], x_positions: list[float],
                 price_range: tuple[float, float], top: int, bottom: int,
                 body_width: int, title: str, labels: bool = True,
                 plot_top_offset: int = 48) -> None:
    lo, hi = price_range
    left, right = 105, WIDTH - 120
    draw.rectangle((left, top, right, bottom), fill=PANEL)
    draw.text((left + 8, top + 8), title, fill=TEXT, font=font(25, True))
    ytop, ybottom = top + plot_top_offset, bottom - 28
    for fraction in range(5):
        y = int(ytop + (ybottom - ytop) * fraction / 4)
        draw.line((left, y, right, y), fill=GRID, width=1)
        val = hi - (hi - lo) * fraction / 4
        draw.text((right + 14, y - 12), f"{val:.3f}", fill=MUTED, font=font(17))
    for i, (bar, x) in enumerate(zip(bars, x_positions)):
        color = UP if float(bar["close"]) >= float(bar["open"]) else DOWN
        yo = price_y(float(bar["open"]), lo, hi, ytop, ybottom)
        yc = price_y(float(bar["close"]), lo, hi, ytop, ybottom)
        yh = price_y(float(bar["high"]), lo, hi, ytop, ybottom)
        yl = price_y(float(bar["low"]), lo, hi, ytop, ybottom)
        draw.line((x, yh, x, yl), fill=color, width=2)
        draw.rectangle((x - body_width // 2, min(yo, yc), x + body_width // 2,
                        max(yo, yc, min(yo, yc) + 2)), fill=color, outline=color)
    if labels and bars:
        axis_y = bottom - 20
        draw.line((left, axis_y, right, axis_y), fill=GRID, width=1)
        tick_count = min(7, len(bars))
        for j in range(tick_count):
            idx = round(j * (len(bars) - 1) / max(1, tick_count - 1))
            x = x_positions[idx]
            label = time_label(int(bars[idx]["epoch"]), date=True)
            draw.line((x, axis_y - 4, x, axis_y + 4), fill=MUTED, width=1)
            box = draw.textbbox((0, 0), label, font=font(16))
            draw.text((x - (box[2] - box[0]) // 2, axis_y + 5), label, fill=MUTED, font=font(16))


def partial_h1(event: dict, m1: dict[int, dict]) -> dict:
    setup = int(event["setup_epoch"])
    event_time = int(event["event_epoch"])
    minute = event_time // 60 * 60
    observed = [m1[t] for t in sorted(m1) if setup <= t <= minute and t < setup + 3600]
    if not observed:
        raise ValueError(f"no M1 observations available for {event['event_time_utc']}")
    open_price = float(event["h1_open"])
    high = open_price
    low = open_price
    close = open_price
    for b in observed[:-1]:
        high = max(high, b["high"])
        low = min(low, b["low"])
        close = b["close"]
    latest = observed[-1]
    if event["sample_kind"] == "m1_close":
        high = max(high, latest["high"])
        low = min(low, latest["low"])
        close = latest["close"]
    else:
        high = max(high, latest["open"])
        low = min(low, latest["open"])
        close = latest["open"]
    return {"epoch": setup, "open": open_price, "high": high, "low": low,
            "close": close, "source_m1_count": len(observed), "partial": True}


def plot_event(event: dict, m1: dict[int, dict], h1_all: list[dict], m5_all: list[dict],
               macd: dict[int, dict], zoom_bars: int, m5_after: int,
               h1_before: int, h1_after: int, output: Path) -> dict:
    setup = int(event["setup_epoch"])
    event_time = int(event["event_epoch"])
    pivot = int(event["pivot_epoch"])
    confirm = int(event["confirm_epoch"])
    breakout = int(event["breakout_epoch"])
    reclaim = int(event["reclaim_epoch"])
    h1_index = bisect.bisect_left([int(b["epoch"]) for b in h1_all], setup)
    if h1_index == len(h1_all) or int(h1_all[h1_index]["epoch"]) != setup:
        raise ValueError("H1 setup candle missing")
    current_partial = partial_h1(event, m1)
    h1_start = max(0, h1_index - h1_before)
    h1_view = h1_all[h1_start:h1_index + h1_after + 1]
    setup_index = h1_index - h1_start
    following_count = len(h1_view) - setup_index - 1

    all_m5_times = [int(b["epoch"]) for b in m5_all]
    known_end = bisect.bisect_right(all_m5_times, event_time - 300)
    break_index = bisect.bisect_left(all_m5_times, breakout)
    if break_index >= known_end or all_m5_times[break_index] != breakout:
        raise ValueError("breakout is not a completed M5 candle at the signal")
    # Zoom out over trading bars, extending the window when needed to include this swing.
    first_index = max(0, known_end - zoom_bars)
    pivot_index = bisect.bisect_left(all_m5_times, pivot)
    first_index = min(first_index, max(0, pivot_index - 5))
    last_index = min(len(m5_all), max(known_end, break_index + 1 + m5_after))
    m5_view = m5_all[first_index:last_index]
    m5_known_count = known_end - first_index
    m5_following_count = last_index - break_index - 1
    if not m5_view:
        raise ValueError(f"no completed M5 candles around {event['event_time_utc']}")

    image = Image.new("RGB", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(image)
    title = f"{event['direction']}  |  {event['sr_type']} break  |  {event['event_order'].replace('_', ' ')}"
    draw.text((80, 35), title, fill=TEXT, font=font(34, True))
    draw.text((82, 82),
              f"XAUUSD  |  Signal snapshot {event['event_time_utc']}  |  {event['sample_kind']}  |  SR {float(event['sr_price']):.3f}",
              fill=MUTED, font=font(21))
    reclaim_label = time_label(reclaim) + f":{reclaim % 60:02d}"
    break_close = breakout + 300
    draw.text((82, 113), f"H1 returns to Open {reclaim_label}  →  M5 breakout CLOSE {time_label(break_close)}:00 UTC",
              fill=RECLAIM, font=font(20, True))
    draw.text((82, 143), "Dukascopy M1 OHLC reconstruction; minute labels do not identify exact tick times.",
              fill=MUTED, font=font(18))
    htop, hbottom = 178, 790
    mtop, mbottom = 850, 1510
    h1_values = [float(b[k]) for b in h1_view for k in ("high", "low")]
    h1_values.extend([float(event["h1_open"]), float(event["prior_h1_low"]), float(event["prior_h1_high"])])
    h1_pad = max((max(h1_values) - min(h1_values)) * 0.09, 0.25)
    h1_range = (min(h1_values) - h1_pad, max(h1_values) + h1_pad)
    hl, hr = 105, WIDTH - 120
    h1_spacing = (hr - hl - 80) / max(1, len(h1_view) - 1)
    h1_xs = [hl + 40 + i * h1_spacing for i in range(len(h1_view))]
    h1_body = max(5, min(26, round(h1_spacing * .48)))
    draw_candles(draw, h1_view, h1_xs, h1_range, htop, hbottom, h1_body,
                 f"H1 zoom out · {setup_index} before / {following_count} after · final candles include later prices",
                 plot_top_offset=78)
    hytop, hybottom = htop + 78, hbottom - 28
    draw.text((hl + 8, htop + 42), "White outline = H1 observed at signal; colored candle = final OHLC.",
              fill=MUTED, font=font(18))
    y_open_h1 = price_y(float(event["h1_open"]), *h1_range, hytop, hybottom)
    y_sweep_h1 = price_y(float(event["prior_h1_low"] if event["direction"] == "BUY" else event["prior_h1_high"]),
                         *h1_range, hytop, hybottom)
    draw.line((hl, y_open_h1, hr, y_open_h1), fill=H1_OPEN, width=2)
    sweep_price = float(event["prior_h1_low"] if event["direction"] == "BUY" else event["prior_h1_high"])
    draw.line((hl, y_sweep_h1, hr, y_sweep_h1), fill=PRIOR, width=2)
    draw.text((hl + 6, y_sweep_h1 - 25), f"prior H1 swept {'low' if event['direction']=='BUY' else 'high'} {sweep_price:.3f}",
              fill=PRIOR, font=font(17, True))
    xcur = h1_xs[setup_index]
    for y in range(hytop, hybottom, 12):
        draw.line((xcur, y, xcur, min(y + 6, hybottom)), fill=SIGNAL, width=2)
    if following_count:
        future_left = xcur + h1_spacing / 2
        draw.line((future_left, hytop, future_left, hybottom), fill=RECLAIM, width=1)
        draw.text((future_left + 8, hytop + 8), "FOLLOWING H1 CANDLES", fill=RECLAIM, font=font(17, True))
    y_partial_close = price_y(current_partial["close"], *h1_range, hytop, hybottom)
    y_partial_high = price_y(current_partial["high"], *h1_range, hytop, hybottom)
    y_partial_low = price_y(current_partial["low"], *h1_range, hytop, hybottom)
    draw.line((xcur, y_partial_high, xcur, y_partial_low), fill=SIGNAL, width=3)
    partial_left, partial_right = xcur - h1_body // 2 - 3, xcur + h1_body // 2 + 3
    draw.rectangle((partial_left, min(y_open_h1, y_partial_close), partial_right,
                    max(y_open_h1, y_partial_close, min(y_open_h1, y_partial_close) + 3)),
                   outline=SIGNAL, width=2)
    draw.ellipse((xcur - 8, y_partial_close - 8, xcur + 8, y_partial_close + 8), fill=SIGNAL, outline=BG, width=2)
    badge_left = max(hl + 10, min(xcur - 335, hr - 345))
    draw.rounded_rectangle((badge_left, y_partial_close - 35, badge_left + 320, y_partial_close - 10),
                           radius=5, fill=BG, outline=SIGNAL, width=1)
    draw.text((badge_left + 8, y_partial_close - 33),
              f"signal {time_label(event_time)} · snapshot {current_partial['close']:.3f}", fill=SIGNAL, font=font(16, True))
    draw.text((hr - 250, y_open_h1 + 6), f"H1 open {float(event['h1_open']):.3f}",
              fill=H1_OPEN, font=font(17, True))

    marker_legend = [
        ("PIVOT BAR", pivot, "#9ac5ff"),
        ("CONFIRM BAR", confirm, "#ffad66"),
        ("BREAK CLOSE", break_close, SR),
        ("RECLAIM SAMPLE", reclaim, RECLAIM),
        ("SIGNAL SAMPLE", event_time, SIGNAL),
    ]
    lx = 105
    for label, t, color in marker_legend:
        shown = time_label(t) + (f":{t % 60:02d}" if t % 60 else "")
        draw.line((lx, 819, lx + 26, 819), fill=color, width=4)
        draw.text((lx + 36, 807), f"{label}  {shown}", fill=color, font=font(16, True))
        box = draw.textbbox((0, 0), f"{label}  {shown}", font=font(16, True))
        lx += 36 + box[2] - box[0] + 34

    lows = [float(b["low"]) for b in m5_view]
    highs = [float(b["high"]) for b in m5_view]
    local_values = lows + highs + [float(event["sr_price"]), float(event["h1_open"]), float(event["price"])]
    pad = max((max(highs) - min(lows)) * 0.1, 0.15)
    local_lo, local_hi = min(local_values) - pad, max(local_values) + pad
    m5_x_left, m5_x_right = 105, WIDTH - 120
    times = [int(b["epoch"]) for b in m5_view]
    right_index = len(times) - 1 + max(1.0, (event_time + 120 - times[-1]) / 300)
    spacing = (m5_x_right - m5_x_left) / right_index
    m5_xs = [m5_x_left + i * spacing for i in range(len(times))]
    def x_by_time(t: int) -> float:
        index = bisect.bisect_right(times, t) - 1
        if index < 0:
            return m5_x_left + (t - times[0]) / 300 * spacing
        fraction = (t - times[index]) / 300
        if index < len(times) - 1:
            fraction = min(fraction, 1.0)  # Compress market closures like a trading chart.
        return m5_x_left + (index + fraction) * spacing
    body_width = max(3, min(12, round(spacing * .55)))
    # Bars are drawn after scaling the local M5 section to a useful price range.
    draw_candles(draw, m5_view, m5_xs, (local_lo, local_hi), mtop, mbottom, body_width,
                 f"M5 zoom out · {m5_known_count} known at signal + {m5_following_count} after breakout · final OHLC",
                 plot_top_offset=78)
    following_x = None
    if m5_following_count:
        local_break_index = break_index - first_index
        following_x = (m5_xs[local_break_index] + m5_xs[local_break_index + 1]) / 2
        draw.line((following_x, mtop + 77, following_x, mbottom - 29), fill=RECLAIM, width=1)
        following_label = f"{m5_following_count} AFTER BREAK"
        following_box = draw.textbbox((0, 0), following_label, font=font(17, True))
        label_x = min(following_x + 8, m5_x_right - (following_box[2] - following_box[0]) - 8)
        draw.text((label_x, mtop + 43), following_label, fill=RECLAIM, font=font(17, True))
    py_sr = price_y(float(event["sr_price"]), local_lo, local_hi, mtop + 78, mbottom - 28)
    confirm_available = next((int(b["epoch"]) for b in m5_all
                              if int(b["epoch"]) >= confirm + 300), confirm + 300)
    x_confirm = int(x_by_time(confirm_available))
    x_signal = int(x_by_time(event_time))
    draw.line((x_confirm, py_sr, x_signal, py_sr), fill=SR, width=3)
    if m5_following_count:
        # Continue this selected historical S/R reference across the context bars.
        for x in range(x_signal, m5_x_right, 14):
            draw.line((x, py_sr, min(x + 7, m5_x_right), py_sr), fill=SR, width=2)
    sr_label = f"S/R eligible after close · {float(event['sr_price']):.3f}"
    sr_box = draw.textbbox((0, 0), sr_label, font=font(18, True))
    sr_label_x = min(x_confirm + 8, m5_x_right - (sr_box[2] - sr_box[0]) - 12)
    draw.rounded_rectangle((sr_label_x - 5, py_sr + 6, sr_label_x + sr_box[2] - sr_box[0] + 5,
                            py_sr + 31), radius=4, fill=BG)
    draw.text((sr_label_x, py_sr + 7), sr_label, fill=SR, font=font(18, True))

    # The open line remains explicit even if the H1 open sits beyond this local M5 view.
    open_price = float(event["h1_open"])
    if local_lo <= open_price <= local_hi:
        py_open = price_y(open_price, local_lo, local_hi, mtop + 78, mbottom - 28)
        draw.line((m5_x_left, py_open, m5_x_right, py_open), fill=H1_OPEN, width=2)
        draw.text((m5_x_right - 205, py_open - 25), f"H1 open {open_price:.3f}", fill=H1_OPEN, font=font(17, True))
    else:
        edge_y = mtop + 60 if open_price > local_hi else mbottom - 50
        draw.line((m5_x_right - 185, edge_y, m5_x_right, edge_y), fill=H1_OPEN, width=3)
        draw.text((m5_x_right - 410, edge_y - 24), f"H1 open {open_price:.3f} beyond local M5 price range",
                  fill=H1_OPEN, font=font(16, True))

    markers = [
        (pivot, "pivot", "#9ac5ff", 2),
        (confirm, "confirmed", "#ffad66", 2),
        (break_close, "breakout close", SR, 3),
        (reclaim, "reclaim sample", RECLAIM, 2),
        (event_time, "signal sample", SIGNAL, 3),
    ]
    for t, label, color, width in markers:
        x = int(x_by_time(t))
        draw.line((x, mtop + 77, x, mbottom - 29), fill=color, width=width)

    signal_y = price_y(float(event["price"]), local_lo, local_hi, mtop + 78, mbottom - 28)
    draw.ellipse((x_signal - 9, signal_y - 9, x_signal + 9, signal_y + 9), fill=SIGNAL, outline=SR, width=3)
    signal_label = f"signal snapshot {float(event['price']):.3f}"
    label_box = draw.textbbox((0, 0), signal_label, font=font(16, True))
    signal_label_x = max(m5_x_left + 8, min(x_signal - (label_box[2] - label_box[0]) - 14, m5_x_right - 320))
    draw.rounded_rectangle((signal_label_x, signal_y - 61, signal_label_x + label_box[2] - label_box[0] + 14,
                            signal_y - 38), radius=4, fill=BG, outline=SIGNAL, width=1)
    draw.text((signal_label_x + 7, signal_y - 59), signal_label, fill=SIGNAL, font=font(16, True))

    breakout_bar = next((b for b in m5_view if int(b["epoch"]) == breakout), None)
    if breakout_bar:
        bx = int(x_by_time(breakout))
        by_high = price_y(float(breakout_bar["high"]), local_lo, local_hi, mtop + 78, mbottom - 28)
        by_low = price_y(float(breakout_bar["low"]), local_lo, local_hi, mtop + 78, mbottom - 28)
        draw.rectangle((bx - 8, by_high - 3, bx + 8, by_low + 3), outline=SR, width=3)
        by_close = price_y(float(breakout_bar["close"]), local_lo, local_hi, mtop + 78, mbottom - 28)
        draw.ellipse((bx - 5, by_close - 5, bx + 5, by_close + 5), fill=SIGNAL, outline=SR, width=2)

    draw_macd(draw, m5_view, m5_xs, macd, 1550, 2030, markers, x_by_time, body_width, following_x)
    draw.text((82, 2060),
              "The pivot is retrospective; S/R becomes eligible after the confirmation bar closes.  |  No order or P/L model.",
              fill=MUTED, font=font(17))
    image.save(output, format="PNG", optimize=True)
    return {
        "file": output.name,
        "event_time_utc": event["event_time_utc"],
        "direction": event["direction"],
        "sr_type": event["sr_type"],
        "event_order": event["event_order"],
        "all_reference_m5_complete": int(event["all_reference_m5_complete"]),
        "h1_visible_bars": len(h1_view),
        "h1_before_bars": setup_index,
        "h1_after_bars": following_count,
        "h1_setup_bar_epoch": setup,
        "h1_last_bar_epoch": int(h1_view[-1]["epoch"]),
        "m5_visible_bars": len(m5_view),
        "m5_known_at_signal_bars": m5_known_count,
        "m5_after_break_bars": m5_following_count,
        "m5_breakout_bar_epoch": breakout,
        "m5_first_bar_epoch": times[0],
        "m5_last_bar_epoch": times[-1],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--m5-bars", type=int, default=120,
                        help="Minimum visible M5 candles; extends to include the swing pivot (default: 120)")
    parser.add_argument("--m5-after", type=int, default=12,
                        help="M5 candles following the breakout candle (default: 12)")
    parser.add_argument("--h1-before", type=int, default=24, help="H1 candles before setup (default: 24)")
    parser.add_argument("--h1-after", type=int, default=12, help="H1 candles after setup (default: 12)")
    args = parser.parse_args()
    if not 40 <= args.m5_bars <= 360:
        parser.error("--m5-bars must be between 40 and 360")
    if not 0 <= args.m5_after <= 72:
        parser.error("--m5-after must be between 0 and 72")
    if not 1 <= args.h1_before <= 72 or not 1 <= args.h1_after <= 48:
        parser.error("--h1-before must be 1–72; --h1-after must be 1–48")
    OUT.mkdir(parents=True, exist_ok=True)
    events = read_csv(HERE / "events.csv")
    h1 = read_csv(HERE / "h1_bars.csv")
    m5 = read_csv(HERE / "m5_bars.csv")
    macd = calculate_tv_macd()
    minute_rows = read_m1()
    eligible = [r for r in events if r["all_reference_m5_complete"] == "1" and r["event_order"] == "reclaim_first"]
    selected = []
    for direction in ("BUY", "SELL"):
        for sr_type in ("Swing H", "Swing L"):
            group = [r for r in eligible if r["direction"] == direction and r["sr_type"] == sr_type]
            selected.extend((r, number) for number, r in enumerate(group[:2], 1))
            # First two chronological members; never rank by later price movement.

    examples = []
    for event, number in selected:
        suffix = "" if number == 1 else f"-{number:02d}"
        filename = f"{event['direction'].lower()}-{event['sr_type'][-1].lower()}-reclaim_first{suffix}.png"
        example = plot_event(event, minute_rows, h1, m5, macd, args.m5_bars, args.m5_after,
                             args.h1_before, args.h1_after, OUT / filename)
        example["chronological_example_in_group"] = number
        examples.append(example)

    previous_manifest = HERE / "gallery_manifest.json"
    if previous_manifest.exists():
        active_files = {r["file"] for r in examples}
        for prior in json.loads(previous_manifest.read_text())["examples"]:
            name = prior["file"]
            if Path(name).name == name and name not in active_files:
                (OUT / name).unlink(missing_ok=True)

    cards = []
    for item in examples:
        cards.append(
            f"<article><h2>{html.escape(item['direction'])} · {html.escape(item['sr_type'])} · "
            f"{html.escape(item['event_order'].replace('_', ' '))}</h2>"
            f"<p>Example {item['chronological_example_in_group']} · {html.escape(item['event_time_utc'])}</p>"
            f"<a href='gallery/{html.escape(item['file'])}'><img src='gallery/{html.escape(item['file'])}'></a></article>"
        )
    page = """<!doctype html><meta charset='utf-8'><title>WickHuntSRFlow XAUUSD 1y examples</title>
<style>body{font:16px Arial,sans-serif;background:#0b1019;color:#e7edf4;margin:24px}h1{font-size:28px}p{color:#9aabbe}main{display:grid;grid-template-columns:1fr;gap:24px}article{background:#111a27;padding:18px;border-radius:10px}img{width:100%;height:auto}h2{margin:4px 0}</style>
<h1>WickHuntSRFlow — XAUUSD one-year snapshot examples</h1>
<p>v1.01: H1 hunts and returns to its Open first, then M5 must close across confirmed swing S/R strictly afterward within the same H1. Earlier breaks and same-time closes are excluded.</p>
<p>Minute OHLC reconstruction, not exact tick replay. Examples are the first two chronological signals in each direction/SR group. H1 shows final candles including later prices; the white outline and dot show the partial H1 at the signal snapshot.</p>
<p>H1 zoom out: 24 candles before and 12 after the setup. Following candles are displayed for context; signal calculations use only information known at the event.</p>
<p>M5 zoom out with at least 120 candles known at signal and 12 following the breakout candle, plus the project's TV Style MACD: Close, EMA 12/26/9, four histogram colors. Price and MACD share the same time axis; market closures are compressed. Pink separators mark the following candles; later prices are displayed for context only.</p>
<main>""" + "\n".join(cards) + "</main>"
    page = page.replace("at least 120 candles known at signal and 12 following",
                        f"at least {args.m5_bars} candles known at signal and {args.m5_after} following")
    page = page.replace("24 candles before and 12 after", f"{args.h1_before} candles before and {args.h1_after} after")
    (HERE / "gallery.html").write_text(page, encoding="utf-8")
    manifest = {"examples": examples, "selection": "first two chronological eligible reclaim-first examples per direction × SR type",
                "signal_rule": "H1 hunt/open reclaim first; M5 close strictly later within the same H1",
                "limitations": "M1 OHLC snapshot reconstruction; chart timestamps are approximate. H1 colored candles show final OHLC including later prices; the white overlay shows partial H1 at signal. M5/MACD include subsequent bars for context only; signal calculations use no future prices.",
                "view": {"width": WIDTH, "height": HEIGHT, "m5_minimum_bars": args.m5_bars,
                         "market_closures": "compressed", "m5_future_bars": args.m5_after > 0,
                         "m5_after_break_bars": args.m5_after,
                         "h1_before_bars": args.h1_before, "h1_after_bars": args.h1_after,
                         "h1_candles": "final OHLC with partial-at-signal white overlay",
                         "future_prices_used_for_signals": False,
                         "macd": {"source": "Close", "ma": "EMA", "signal_ma": "EMA", "periods": [12, 26, 9],
                                  "histogram_colors": HISTOGRAM_COLORS,
                                  "production_core_sha256": hashlib.sha256((HERE.parents[2] / "MQL5/Indicators/TVStyleMACD/MACDCore.mqh").read_bytes()).hexdigest(),
                                  "series_sha256": hashlib.sha256((HERE / "m5_macd.csv").read_bytes()).hexdigest(),
                                  "swing_engine_comparison": "all M5 MACD / Signal / Histogram values match exactly"}}}
    (HERE / "gallery_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    summary_path = HERE / "summary.json"
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    summary["gallery"] = manifest
    summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {len(examples)} example charts to {OUT}")


if __name__ == "__main__":
    main()
