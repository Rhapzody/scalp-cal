#!/usr/bin/env python3
"""Replay WickHuntSRFlow 1.03 on the fixed three-month XAUUSD window."""
from __future__ import annotations

import argparse
import calendar
import csv
import datetime as dt
import gzip
import hashlib
import json
import math
import re
import shutil
import subprocess
import sys
import tempfile
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
DEFAULT_INPUT = ROOT / "tests/reports/engulf-imbalance-xauusd-m1/xauusd_m1_bid_ask.csv.gz"
START = dt.datetime(2026, 6, 25, 21, 0, tzinfo=dt.timezone.utc)
END = dt.datetime(2026, 9, 25, 21, 0, tzinfo=dt.timezone.utc)
STUDY_START = calendar.timegm(START.utctimetuple())
STUDY_END = calendar.timegm(END.utctimetuple())
FIXED_SPREAD = 0.36
TICK_SIZE = 0.01
PRICE_DIGITS = 2
RR_VALUES = (1.0, 1.5, 2.0)
SOURCE_FORMAT = "%Y.%m.%d %H:%M:%S"


def stamp(epoch: int | float | str) -> str:
    return dt.datetime.fromtimestamp(int(float(epoch)), dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_ohlc(row: dict[str, str], prefix: str) -> tuple[float, float, float, float]:
    values = tuple(float(row[f"{prefix}_{name}"]) for name in ("open", "high", "low", "close"))
    o, h, low, close = values
    if not all(math.isfinite(value) for value in values) or low > min(o, close) or max(o, close) > h:
        raise ValueError(f"invalid {prefix} OHLC at {row['timestamp']}: {values}")
    return values


def read_source(path: Path) -> tuple[list[dict], dict]:
    rows: list[dict] = []
    gaps: Counter[int] = Counter()
    previous = None
    with gzip.open(path, "rt", newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        expected = {"timestamp", "epoch", "bid_open", "bid_high", "bid_low", "bid_close",
                    "ask_open", "ask_high", "ask_low", "ask_close", "spread_close"}
        if set(reader.fieldnames or []) != expected:
            raise ValueError(f"unexpected source columns: {reader.fieldnames}")
        for source_row in reader:
            time = int(source_row["epoch"])
            if previous is not None:
                delta = time - previous
                if delta <= 0:
                    raise ValueError(f"timestamps not strictly increasing at epoch {time}")
                if delta != 60:
                    gaps[delta] += 1
            bid = parse_ohlc(source_row, "bid")
            ask = parse_ohlc(source_row, "ask")
            spread = float(source_row["spread_close"])
            if not math.isfinite(spread) or spread < 0:
                raise ValueError(f"invalid spread at epoch {time}")
            rows.append({"time": time, "open": bid[0], "high": bid[1], "low": bid[2], "close": bid[3],
                         "source_m1_count": 1,
                         "ask_open": ask[0], "ask_high": ask[1], "ask_low": ask[2], "ask_close": ask[3],
                         "spread_close": spread})
            previous = time
    if not rows:
        raise ValueError("source dataset has no usable M1 bars")
    coverage = {
        "rows": len(rows),
        "first_bar_open_utc": stamp(rows[0]["time"]),
        "last_bar_open_utc": stamp(rows[-1]["time"]),
        "duplicate_timestamps": 0,
        "invalid_rows": 0,
        "source_gaps_seconds": {str(delta): count for delta, count in sorted(gaps.items())},
    }
    return rows, coverage


def aggregate(rows: list[dict], seconds: int) -> list[dict]:
    bars: dict[int, dict] = {}
    timestamps: dict[int, list[int]] = defaultdict(list)
    for row in rows:
        start = row["time"] // seconds * seconds
        timestamps[start].append(row["time"])
        if start not in bars:
            bars[start] = {"time": start, "open": row["open"], "high": row["high"],
                           "low": row["low"], "close": row["close"], "source_m1_count": 1}
        else:
            bar = bars[start]
            bar["high"] = max(bar["high"], row["high"])
            bar["low"] = min(bar["low"], row["low"])
            bar["close"] = row["close"]
            bar["source_m1_count"] += 1
    result = []
    for start in sorted(bars):
        times = timestamps[start]
        bar = bars[start]
        bar["complete"] = len(times) == seconds // 60 and times == [start + i * 60 for i in range(seconds // 60)]
        result.append(bar)
    return result


def write_bars(path: Path, bars: list[dict]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["timestamp_utc", "epoch", "open", "high", "low", "close", "source_m1_count"])
        for bar in bars:
            writer.writerow([stamp(bar["time"]), bar["time"], *(format(bar[k], ".12g")
                           for k in ("open", "high", "low", "close")), bar["source_m1_count"]])


def run_core(input_path: Path, output: Path, compiler: str) -> tuple[dict, list[dict]]:
    core_dir = ROOT / "MQL5/Indicators/WickHuntSRFlow"
    compiler_path = shutil.which(compiler) or compiler
    raw_events_path = output / "events_raw.csv"
    diagnostics_path = output / "replay_diagnostics.json"
    with tempfile.TemporaryDirectory(prefix="wick-hunt-m15-m1-") as tmp:
        tmp_path = Path(tmp)
        context = (core_dir / "WickHuntContextCore.mqh").read_text(encoding="utf-8")
        context = re.sub(r"const MSBar &(\w+)\[\]", r"const MSBar *\1", context)
        (tmp_path / "WickHuntContextCore.mqh").write_text(context, encoding="utf-8")
        imbalance = (core_dir / "EngulfImbalanceCore.mqh").read_text(encoding="utf-8")
        imbalance = re.sub(r"const (WHBar|int|double) &(\w+)\[\]", r"const \1 *\2", imbalance)
        (tmp_path / "EngulfImbalanceCore.mqh").write_text(imbalance, encoding="utf-8")
        executable = tmp_path / "wick-hunt-replay"
        subprocess.run([compiler_path, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
                        "-Wno-unused-parameter", "-I", str(tmp_path), "-I", str(core_dir),
                        str(HERE / "replay.cpp"), "-o", str(executable)], cwd=ROOT, check=True)
        subprocess.run([str(executable), str(input_path), str(raw_events_path), str(diagnostics_path),
                        str(STUDY_START), str(STUDY_END)], cwd=ROOT, check=True)
    with raw_events_path.open(newline="", encoding="utf-8") as handle:
        raw_events = list(csv.DictReader(handle))
    return json.loads(diagnostics_path.read_text(encoding="utf-8")), raw_events


def enrich_events(raw_events: list[dict], m1_bars: list[dict], m15_bars: list[dict]) -> tuple[list[dict], list[str]]:
    m1_by_time = {bar["time"]: bar for bar in m1_bars}
    m15_by_time = {bar["time"]: bar for bar in m15_bars}
    events = []
    for number, raw in enumerate(raw_events, 1):
        values = {key: int(float(raw[key])) for key in (
            "event_epoch", "signal_minute_epoch", "setup_epoch", "direction", "sr_type", "breakout_epoch",
            "break_close_epoch", "pivot_epoch", "confirm_epoch", "hold_bar_epoch", "hold_close_epoch",
            "retest_deadline_epoch", "retest_bar", "context_sr_type", "context_touch_epoch",
            "context_sr_pivot_epoch", "context_sr_confirm_epoch", "pattern", "anchor_epoch",
            "trend_pivot_epoch", "trend_break_epoch", "trend_origin_epoch", "trend_confirm_epoch",
            "reclaim_epoch", "swept_prior_m15_count")}
        setup = values["setup_epoch"]
        context_bar = m15_by_time.get(setup)
        signal_bar = m1_by_time.get(values["signal_minute_epoch"])
        pivot_bar = m1_by_time.get(values["pivot_epoch"])
        confirm_bar = m1_by_time.get(values["confirm_epoch"])
        break_bar = m1_by_time.get(values["breakout_epoch"])
        hold_bar = m1_by_time.get(values["hold_bar_epoch"])
        retest_bar = signal_bar
        if not context_bar or not signal_bar or not pivot_bar or not confirm_bar or not break_bar:
            raise ValueError(f"missing data reference for event {number}")
        if not hold_bar or not retest_bar:
            raise ValueError(f"missing hold/retest bar reference for event {number}")
        direction = "BUY" if values["direction"] == 1 else "SELL"
        pattern_name = {1: "Breakout", 2: "Pullback", 3: "Breakout + Pullback"}[values["pattern"]]
        signal_dt = dt.datetime.fromtimestamp(values["event_epoch"], dt.timezone.utc)
        row = {
            "event_id": f"WHM15M1-{number:06d}",
            "event_time_utc": stamp(values["event_epoch"]), "event_epoch": values["event_epoch"],
            "sample_kind": raw["signal_sample_kind"], "signal_sample_kind": raw["signal_sample_kind"],
            "signal_minute_epoch": values["signal_minute_epoch"],
            "setup_time_utc": stamp(setup), "setup_epoch": setup,
            "direction": direction, "signal_bid": raw["signal_bid"], "price": raw["signal_bid"],
            "m15_open": raw["m15_open"], "hunt_open": raw["m15_open"],
            "pattern": values["pattern"], "pattern_label": pattern_name, "scenario_config": "WS_BOTH",
            "sr_price": raw["sr_price"], "sr_type": "Swing H" if values["sr_type"] == 1 else "Swing L",
            "breakout_time_utc": stamp(values["breakout_epoch"]), "breakout_epoch": values["breakout_epoch"],
            "break_close_time_utc": stamp(values["break_close_epoch"]), "break_close_epoch": values["break_close_epoch"],
            "break_close": raw["break_close"],
            "pivot_time_utc": stamp(values["pivot_epoch"]), "pivot_epoch": values["pivot_epoch"],
            "swing_confirm_time_utc": stamp(values["confirm_epoch"]), "confirm_epoch": values["confirm_epoch"],
            "pivot_price": raw["pivot_price"], "context_sr": raw["context_sr"],
            "hold_bar_epoch": values["hold_bar_epoch"], "hold_close_epoch": values["hold_close_epoch"],
            "hold_close": raw["hold_close"], "retest_deadline_epoch": values["retest_deadline_epoch"],
            "retest_bar": values["retest_bar"], "retest_time_utc": stamp(values["event_epoch"]),
            "retest_price": raw["signal_bid"],
            "hold_bar_time_utc": stamp(values["hold_bar_epoch"]),
            "hold_close_time_utc": stamp(values["hold_close_epoch"]),
            "context_sr_type": values["context_sr_type"],
            "main_sr_type": values["context_sr_type"],
            "context_touch_epoch": values["context_touch_epoch"],
            "context_sr_pivot_epoch": values["context_sr_pivot_epoch"],
            "context_sr_confirm_epoch": values["context_sr_confirm_epoch"],
            "anchor_time_utc": stamp(values["anchor_epoch"]) if values["anchor_epoch"] else "",
            "anchor_epoch": values["anchor_epoch"],
            "trend_break_epoch": values["trend_break_epoch"],
            "trend_origin_epoch": values["trend_origin_epoch"],
            "trend_origin_price": raw["trend_origin_price"],
            "trend_pivot_epoch": values["trend_pivot_epoch"],
            "trend_pivot_price": raw["trend_pivot_price"],
            "trend_confirm_epoch": values["trend_confirm_epoch"], "trend_sr": raw["trend_sr"],
            "reclaim_time_utc": stamp(values["reclaim_epoch"]), "reclaim_epoch": values["reclaim_epoch"],
            "reclaim_sample_kind": raw["reclaim_sample_kind"], "reclaim_bid": raw["reclaim_bid"],
            "reclaim_known_high": raw["reclaim_known_high"], "reclaim_known_low": raw["reclaim_known_low"],
            "reclaim_tip": raw["reclaim_tip"], "known_high": raw["known_high"], "known_low": raw["known_low"],
            "prior_low_1": raw["prior_low_1"], "prior_high_1": raw["prior_high_1"],
            "prior_low_2": raw["prior_low_2"], "prior_high_2": raw["prior_high_2"],
            "swept_prior_m15_count": values["swept_prior_m15_count"],
            "current_m15_m1_count": context_bar["source_m1_count"],
            "current_m15_complete": int(context_bar["complete"]),
            "data_quality_eligible": int(context_bar["complete"]),
            "breakout_m1_source_count": break_bar["source_m1_count"],
            "hold_m1_source_count": hold_bar["source_m1_count"],
            "pivot_m1_source_count": pivot_bar["source_m1_count"],
            "confirmation_m1_source_count": confirm_bar["source_m1_count"],
            "month_utc": signal_dt.strftime("%Y-%m"),
            "inp_hunt_bars": 1, "inp_pullback_hunt_bars": 2, "inp_touch_bars": 5,
            "inp_sr_count": 10, "inp_sr_anchor": "MS_SR_WICK", "inp_fvg_search_bars": 0,
            "macd_fast": 12, "macd_slow": 26, "macd_signal": 9, "warmup_bars": 34,
        }
        events.append(row)
    fields = list(events[0]) if events else [
        "event_id", "event_time_utc", "event_epoch", "sample_kind", "signal_sample_kind",
        "signal_minute_epoch", "setup_time_utc", "setup_epoch",
        "direction", "signal_bid", "price", "m15_open", "hunt_open", "pattern", "pattern_label",
        "scenario_config", "sr_price", "sr_type", "breakout_time_utc", "breakout_epoch",
        "break_close_time_utc", "break_close_epoch", "break_close", "pivot_time_utc", "pivot_epoch",
        "swing_confirm_time_utc", "confirm_epoch", "pivot_price", "context_sr", "anchor_time_utc",
        "hold_bar_epoch", "hold_close_epoch", "hold_close", "retest_deadline_epoch", "retest_bar",
        "retest_time_utc", "retest_price", "hold_bar_time_utc", "hold_close_time_utc",
        "context_sr_type", "main_sr_type", "context_touch_epoch",
        "context_sr_pivot_epoch", "context_sr_confirm_epoch",
        "anchor_epoch", "trend_break_epoch", "trend_origin_epoch", "trend_origin_price",
        "trend_pivot_epoch", "trend_pivot_price", "trend_confirm_epoch", "trend_sr", "reclaim_time_utc",
        "reclaim_epoch", "reclaim_sample_kind", "reclaim_bid", "reclaim_known_high", "reclaim_known_low",
        "reclaim_tip", "known_high", "known_low", "prior_low_1", "prior_high_1", "prior_low_2",
        "prior_high_2", "swept_prior_m15_count", "current_m15_m1_count", "current_m15_complete",
        "data_quality_eligible", "breakout_m1_source_count", "pivot_m1_source_count",
        "hold_m1_source_count", "confirmation_m1_source_count", "month_utc", "inp_hunt_bars", "inp_pullback_hunt_bars",
        "inp_touch_bars", "inp_sr_count", "inp_sr_anchor", "inp_fvg_search_bars", "macd_fast",
        "macd_slow", "macd_signal", "warmup_bars"]
    return events, fields


def scalp_snap(price: float) -> float:
    """ScalpSnap/ScalpBrokerPrice: nearest symbol tick, normalized to 2 digits."""
    return round(math.floor(price / TICK_SIZE + 0.5) * TICK_SIZE, PRICE_DIGITS)


def strategy_stop(direction: str, bid_wick: float) -> float:
    """EngulfBufferedStop at zero buffer: outward tick rounding of the chart wick."""
    ticks = bid_wick / TICK_SIZE
    if direction == "BUY":
        return round(math.floor(ticks + 1e-8) * TICK_SIZE, PRICE_DIGITS)
    return round(math.ceil(ticks - 1e-8) * TICK_SIZE, PRICE_DIGITS)


def broker_levels(direction: str, entry: float, raw_stop: float, rr: float) -> dict:
    """InstantEngulf strategy TP, then ScalpBrokerPrice spread compensation."""
    sign = 1.0 if direction == "BUY" else -1.0
    strategy_sl = strategy_stop(direction, raw_stop)
    strategy_tp = scalp_snap(entry + sign * rr * abs(entry - strategy_sl))
    strategy_geometry = (strategy_sl < entry < strategy_tp) if direction == "BUY" else (strategy_tp < entry < strategy_sl)
    spread_shift = 0.0 if direction == "BUY" else FIXED_SPREAD
    broker_sl = scalp_snap(strategy_sl + spread_shift)
    broker_tp = scalp_snap(strategy_tp + spread_shift)
    broker_geometry = (broker_sl < entry < broker_tp) if direction == "BUY" else (broker_tp < entry < broker_sl)
    risk = entry - broker_sl if direction == "BUY" else broker_sl - entry
    target_reward = broker_tp - entry if direction == "BUY" else entry - broker_tp
    target_r = target_reward / risk if risk > 0 else 0.0
    valid = strategy_geometry and broker_geometry and risk > 0 and target_reward > 0
    return {"strategy_sl": strategy_sl, "strategy_tp": strategy_tp,
            "broker_sl": broker_sl, "broker_tp": broker_tp,
            "initial_risk": risk, "target_reward": target_reward,
            "target_r_multiple": target_r, "strategy_geometry": strategy_geometry,
            "broker_geometry": broker_geometry, "valid": valid}


def _close_side(direction: str, bid: float) -> float:
    return bid if direction == "BUY" else bid + FIXED_SPREAD


def evaluate_trade(event: dict, rr: float, m1_index: dict[int, int], m1_bars: list[dict]) -> dict:
    direction = event["direction"]
    signal_epoch = int(event["event_epoch"])
    signal_minute = signal_epoch // 60 * 60
    signal_index = m1_index.get(signal_minute)
    if signal_index is None:
        raise ValueError(f"signal does not map to a source M1 minute: {event['event_id']}")
    signal_bar = m1_bars[signal_index]
    sample_kind = str(event.get("sample_kind", "m1_open"))
    if sample_kind == "m1_open":
        minute_index = signal_index
        entry_kind = "same_m1_open"
    elif sample_kind == "m1_close59":
        minute_index = signal_index + 1
        entry_kind = "next_observed_m1_open_after_close59"
        expected_entry_epoch = signal_bar["time"] + 60
        no_entry_reason = ""
        if minute_index >= len(m1_bars) or m1_bars[minute_index]["time"] >= STUDY_END:
            no_entry_reason = "no_immediate_entry_open_before_study_end"
        elif m1_bars[minute_index]["time"] != expected_entry_epoch:
            no_entry_reason = "missing_expected_entry_open"
        if no_entry_reason:
            return {
                "event_id": event["event_id"], "signal_epoch": signal_epoch,
                "signal_time_utc": stamp(signal_epoch), "signal_sample_kind": sample_kind,
                "direction": direction, "rr": rr, "entry_epoch": "", "entry_time_utc": "",
                "entry_bid": "", "entry_price": "", "entry_side": "", "entry_spread": FIXED_SPREAD,
                "entry_sample_kind": "no_observed_open_before_study_end", "entry_delay_seconds": "",
                "entry_m15_boundary_cross": "", "entry_source_gap_seconds": "",
                "strategy_sl": "", "stop_price": "", "stop_side": "", "initial_risk": "",
                "strategy_tp": "", "target_price": "", "target_side": "", "target_r_multiple": "",
                "exit_epoch": "", "exit_time_utc": "", "exit_bar_open_epoch": "",
                "exit_bar_close_epoch": "", "exit_price": "", "exit_side": "",
                "exit_sample_kind": "", "outcome": "NO_ENTRY", "no_entry_reason": no_entry_reason, "r_multiple": "",
                "mark_to_market_r": "", "gap_through_stop": 0, "gap_through_target": 0,
                "source_gap_count": 0, "source_gap_exposed": 0, "bars_held": 0,
                "data_quality_eligible": int(event["data_quality_eligible"]), "month_utc": event["month_utc"],
            }
    else:
        raise ValueError(f"unknown signal sample kind {sample_kind}")
    entry_bar = m1_bars[minute_index]
    entry_bid = entry_bar["open"]
    entry = entry_bid + FIXED_SPREAD if direction == "BUY" else entry_bid
    raw_stop = float(event["known_low"]) if direction == "BUY" else float(event["known_high"])
    levels = broker_levels(direction, entry, raw_stop, rr)
    stop = levels["broker_sl"]
    target = levels["broker_tp"]
    risk = levels["initial_risk"]
    expected_gap_open = signal_bar["time"] + 60 if sample_kind == "m1_close59" else entry_bar["time"]
    entry_gap_seconds = max(0, entry_bar["time"] - expected_gap_open)
    entry_delay_seconds = entry_bar["time"] - signal_epoch
    base = {
        "event_id": event["event_id"], "signal_epoch": signal_epoch,
        "signal_time_utc": stamp(signal_epoch), "signal_sample_kind": sample_kind,
        "signal_price": float(event["signal_bid"]), "direction": direction,
        "rr": rr, "entry_epoch": entry_bar["time"], "entry_time_utc": stamp(entry_bar["time"]),
        "entry_bid": entry_bid, "entry_price": entry, "entry_side": "ASK" if direction == "BUY" else "BID",
        "entry_spread": FIXED_SPREAD, "entry_sample_kind": entry_kind,
        "entry_delay_seconds": entry_delay_seconds,
        "entry_m15_boundary_cross": int(entry_bar["time"] // 900 != int(event["setup_epoch"]) // 900),
        "entry_source_gap_seconds": entry_gap_seconds,
        "strategy_sl": levels["strategy_sl"], "stop_price": stop,
        "stop_side": "BID" if direction == "BUY" else "ASK",
        "initial_risk": risk, "strategy_tp": levels["strategy_tp"], "target_price": target,
        "target_side": "BID" if direction == "BUY" else "ASK",
        "target_r_multiple": levels["target_r_multiple"],
        "exit_epoch": "", "exit_time_utc": "", "exit_bar_open_epoch": "", "exit_bar_close_epoch": "",
        "exit_price": "", "exit_side": "BID" if direction == "BUY" else "ASK",
        "exit_sample_kind": "", "outcome": "INVALID_STOP", "no_entry_reason": "", "invalid_reason": "",
        "r_multiple": "",
        "mark_to_market_r": "", "gap_through_stop": 0, "gap_through_target": 0,
        "source_gap_count": 0, "source_gap_exposed": 0, "bars_held": 0,
        "data_quality_eligible": int(event["data_quality_eligible"]), "month_utc": event["month_utc"],
    }
    if not levels["valid"] or not math.isfinite(risk) or risk <= 0:
        base["invalid_reason"] = "broker_stop_or_target_geometry"
        return base
    previous_time = None
    gap_count = 0
    last_bid_close = entry_bar["close"]
    for index in range(minute_index, len(m1_bars)):
        bar = m1_bars[index]
        if bar["time"] >= STUDY_END:
            break
        if previous_time is not None and bar["time"] - previous_time != 60:
            gap_count += 1
        previous_time = bar["time"]
        base["bars_held"] = index - minute_index + 1
        last_bid_close = bar["close"]
        open_exec = bar["open"] if direction == "BUY" else bar["open"] + FIXED_SPREAD
        stop_open_hit = open_exec <= stop if direction == "BUY" else open_exec >= stop
        target_open_hit = open_exec >= target if direction == "BUY" else open_exec <= target
        if stop_open_hit:
            r_value = (open_exec - entry) / risk if direction == "BUY" else (entry - open_exec) / risk
            base.update({"outcome": "SL", "exit_epoch": bar["time"], "exit_time_utc": stamp(bar["time"]),
                         "exit_bar_open_epoch": bar["time"], "exit_bar_close_epoch": bar["time"] + 60,
                         "exit_price": open_exec, "exit_sample_kind": "observed_open_gap_or_touch",
                         "r_multiple": r_value,
                         "gap_through_stop": int(open_exec < stop if direction == "BUY" else open_exec > stop),
                         "source_gap_count": gap_count, "source_gap_exposed": int(gap_count > 0)})
            return base
        if target_open_hit:
            base.update({"outcome": "TP", "exit_epoch": bar["time"], "exit_time_utc": stamp(bar["time"]),
                         "exit_bar_open_epoch": bar["time"], "exit_bar_close_epoch": bar["time"] + 60,
                         "exit_price": target, "exit_sample_kind": "observed_open_limit_target",
                         "r_multiple": levels["target_r_multiple"], "gap_through_target": int(open_exec > target if direction == "BUY" else open_exec < target),
                         "source_gap_count": gap_count, "source_gap_exposed": int(gap_count > 0)})
            return base

        if direction == "BUY":
            stop_hit, target_hit = bar["low"] <= stop, bar["high"] >= target
        else:
            ask_high, ask_low = bar["high"] + FIXED_SPREAD, bar["low"] + FIXED_SPREAD
            stop_hit, target_hit = ask_high >= stop, ask_low <= target
        if stop_hit and target_hit:
            base.update({"outcome": "BOTH", "exit_epoch": bar["time"] + 59,
                         "exit_time_utc": stamp(bar["time"] + 59), "exit_bar_open_epoch": bar["time"],
                         "exit_bar_close_epoch": bar["time"] + 60, "exit_price": "",
                         "exit_sample_kind": "same_m1_both_order_unknown", "r_multiple": "",
                         "source_gap_count": gap_count, "source_gap_exposed": int(gap_count > 0)})
            return base
        if stop_hit:
            exit_price = stop
            r_value = -1.0
            base.update({"outcome": "SL", "exit_epoch": bar["time"] + 59,
                         "exit_time_utc": stamp(bar["time"] + 59), "exit_bar_open_epoch": bar["time"],
                         "exit_bar_close_epoch": bar["time"] + 60, "exit_price": exit_price,
                         "exit_sample_kind": "intraminute_stop_touch_approx", "r_multiple": r_value,
                         "source_gap_count": gap_count, "source_gap_exposed": int(gap_count > 0)})
            return base
        if target_hit:
            base.update({"outcome": "TP", "exit_epoch": bar["time"] + 59,
                         "exit_time_utc": stamp(bar["time"] + 59), "exit_bar_open_epoch": bar["time"],
                         "exit_bar_close_epoch": bar["time"] + 60, "exit_price": target,
                         "exit_sample_kind": "intraminute_limit_target_touch_approx", "r_multiple": levels["target_r_multiple"],
                         "source_gap_count": gap_count, "source_gap_exposed": int(gap_count > 0)})
            return base

    last_bar = next((bar for bar in reversed(m1_bars) if bar["time"] < STUDY_END), None)
    if last_bar is not None:
        mark = last_bar["close"] if direction == "BUY" else last_bar["close"] + FIXED_SPREAD
        base.update({"outcome": "OPEN", "exit_epoch": STUDY_END, "exit_time_utc": stamp(STUDY_END),
                     "exit_bar_open_epoch": last_bar["time"], "exit_bar_close_epoch": last_bar["time"] + 60,
                     "exit_price": mark, "exit_sample_kind": "study_end_mark_to_market",
                     "mark_to_market_r": ((mark - entry) / risk if direction == "BUY" else (entry - mark) / risk),
                     "source_gap_count": gap_count, "source_gap_exposed": int(gap_count > 0)})
    return base


def summarize_trades(trades: list[dict], only_quality: bool = False) -> dict:
    rows = [row for row in trades if not only_quality or row["data_quality_eligible"] == 1]
    counts = Counter(row["outcome"] for row in rows)
    tp, sl, both, opened, invalid = (counts[name] for name in ("TP", "SL", "BOTH", "OPEN", "INVALID_STOP"))
    resolved = tp + sl
    win_rate = tp / resolved if resolved else None
    resolved_r = [float(row["r_multiple"]) for row in rows if row["outcome"] in ("TP", "SL")]
    wins = sum(value for value in resolved_r if value > 0)
    losses = abs(sum(value for value in resolved_r if value < 0))
    all_both_sl_r = sum(float(row["r_multiple"]) for row in rows if row["outcome"] in ("TP", "SL")) - both
    all_both_tp_r = all_both_sl_r + sum(float(row["target_r_multiple"]) + 1.0
                                       for row in rows if row["outcome"] == "BOTH")
    denominator_with_both = resolved + both
    return {
        "signals": len(rows), "TP": tp, "SL": sl, "BOTH": both, "OPEN": opened,
        "NO_ENTRY": counts["NO_ENTRY"], "INVALID_STOP": invalid,
        "entered_trades": sum(counts[name] for name in ("TP", "SL", "BOTH", "OPEN")),
        "rejected_invalid_stop": invalid,
        "resolved_TP_SL": resolved,
        "win_rate_resolved": win_rate, "sum_resolved_R": sum(resolved_r),
        "gross_win_R": wins, "gross_loss_R": losses,
        "profit_factor_R": wins / losses if losses else None,
        "win_rate_if_BOTH_are_SL": tp / denominator_with_both if denominator_with_both else None,
        "win_rate_if_BOTH_are_TP": (tp + both) / denominator_with_both if denominator_with_both else None,
        "sum_R_if_BOTH_are_SL": all_both_sl_r,
        "sum_R_if_BOTH_are_TP": all_both_tp_r,
        "gap_through_stop_fills": sum(int(row["gap_through_stop"]) for row in rows),
        "trades_exposed_to_source_gaps": sum(int(row["source_gap_exposed"]) for row in rows),
        "source_gap_crossings": sum(int(row["source_gap_count"]) for row in rows),
    }


def write_trades(output: Path, events: list[dict], m1_bars: list[dict]) -> tuple[dict, dict]:
    m1_index = {bar["time"]: index for index, bar in enumerate(m1_bars)}
    summaries = {}
    month_rows = defaultdict(Counter)
    trade_fields = ["event_id", "signal_epoch", "signal_time_utc", "signal_sample_kind", "signal_price",
                    "direction", "rr", "entry_epoch", "entry_time_utc", "entry_bid", "entry_price",
                    "entry_side", "entry_spread", "entry_sample_kind", "entry_delay_seconds",
                    "entry_m15_boundary_cross", "entry_source_gap_seconds", "strategy_sl", "stop_price", "stop_side",
                    "initial_risk", "strategy_tp", "target_price", "target_side", "target_r_multiple", "exit_epoch", "exit_time_utc",
                    "invalid_reason", "no_entry_reason", "exit_bar_open_epoch", "exit_bar_close_epoch", "exit_price", "exit_side",
                    "exit_sample_kind", "outcome", "r_multiple", "mark_to_market_r", "gap_through_stop",
                    "gap_through_target", "source_gap_count", "source_gap_exposed", "bars_held",
                    "data_quality_eligible", "month_utc"]
    all_trades = []
    for rr in RR_VALUES:
        directory = output / f"rr-{rr:g}".replace(".", "_")
        directory.mkdir(parents=True, exist_ok=True)
        trades = []
        for event in events:
            trade = evaluate_trade(event, rr, m1_index, m1_bars)
            trades.append(trade)
            month = trade["month_utc"]
            month_rows[(rr, month)][trade["outcome"]] += 1
            month_rows[(rr, month)]["total"] += 1
        with (directory / "trades.csv").open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=trade_fields)
            writer.writeheader()
            writer.writerows(trades)
        summary = {
            "rr": rr,
            "all_causal_events": summarize_trades(trades, False),
            "complete_current_m15_quality_subset": summarize_trades(trades, True),
        }
        summaries[str(rr)] = summary
        with (directory / "summary.json").open("w", encoding="utf-8") as handle:
            json.dump(summary, handle, indent=2)
        for trade in trades:
            all_trades.append({**trade, "rr": rr})
    for rr in RR_VALUES:
        directory = output / f"rr-{rr:g}".replace(".", "_")
        with (directory / "monthly.csv").open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(["month_utc", "signals", "quality_eligible", "TP", "SL", "BOTH", "OPEN",
                             "NO_ENTRY", "INVALID_STOP", "win_rate_resolved", "sum_resolved_R", "profit_factor_R"])
            for month in sorted(k[1] for k in month_rows if k[0] == rr):
                rows = [t for t in all_trades if t["rr"] == rr and t["month_utc"] == month]
                all_summary = summarize_trades(rows, False)
                quality_summary = summarize_trades(rows, True)
                writer.writerow([month, all_summary["signals"], quality_summary["signals"],
                                 all_summary["TP"], all_summary["SL"], all_summary["BOTH"], all_summary["OPEN"],
                                 all_summary["NO_ENTRY"], all_summary["INVALID_STOP"], all_summary["win_rate_resolved"],
                                 all_summary["sum_resolved_R"], all_summary["profit_factor_R"]])
    return summaries, {"trade_rows_per_rr": len(events), "all_trades": all_trades}


def run_fixtures() -> dict:
    """Exercise InstantEngulf rounding/allowance, all RR models, gaps, delay and BOTH."""
    checks = 0
    outcomes = []
    assert scalp_snap(100.006) == 100.01
    assert scalp_snap(100.004) == 100.00
    assert strategy_stop("BUY", 99.001) == 99.00
    assert strategy_stop("SELL", 101.001) == 101.01
    sell_one = broker_levels("SELL", 100.0, 101.0, 1.0)
    assert sell_one["strategy_sl"] == 101.0 and sell_one["strategy_tp"] == 99.0
    assert sell_one["broker_sl"] == 101.36 and sell_one["broker_tp"] == 99.36
    assert abs(sell_one["target_r_multiple"] - (0.64 / 1.36)) < 1e-12
    buy_off_grid = broker_levels("BUY", 100.36, 99.001, 1.5)
    sell_off_grid = broker_levels("SELL", 100.0, 101.001, 1.5)
    sell_wrong_side = broker_levels("SELL", 100.0, 99.80, 1.0)
    assert (buy_off_grid["strategy_sl"], buy_off_grid["strategy_tp"],
            buy_off_grid["broker_sl"], buy_off_grid["broker_tp"]) == (99.0, 102.4, 99.0, 102.4)
    assert (sell_off_grid["strategy_sl"], sell_off_grid["strategy_tp"],
            sell_off_grid["broker_sl"], sell_off_grid["broker_tp"]) == (101.01, 98.48, 101.37, 98.84)
    assert not sell_wrong_side["strategy_geometry"] and not sell_wrong_side["valid"]
    checks += 12

    def fake_event(direction: str, raw_stop: float, name: str,
                   sample_kind: str = "m1_open", event_epoch: int = 60) -> dict:
        return {"direction": direction, "known_low": raw_stop if direction == "BUY" else 99.5,
                "known_high": raw_stop if direction == "SELL" else 100.5,
                "event_epoch": event_epoch, "setup_epoch": 0, "sample_kind": sample_kind,
                "signal_bid": 100.0, "data_quality_eligible": 1, "month_utc": "test", "event_id": name}

    for direction in ("BUY", "SELL"):
        for rr in RR_VALUES:
            fake = fake_event(direction, 99.0 if direction == "BUY" else 101.0, f"rr_{direction}_{rr}")
            entry = 100.36 if direction == "BUY" else 100.0
            levels = broker_levels(direction, entry, 99.0 if direction == "BUY" else 101.0, rr)
            if direction == "BUY":
                bar = {"time": 60, "open": 100.0, "high": levels["broker_tp"] + .1,
                       "low": max(99.5, levels["broker_sl"] + .1), "close": 100.5}
            else:
                bar = {"time": 60, "open": 100.0, "high": 100.8,
                       "low": levels["broker_tp"] - FIXED_SPREAD - .1, "close": 99.5}
            result = evaluate_trade(fake, rr, {60: 0}, [bar])
            assert result["outcome"] == "TP", (direction, rr, result)
            assert abs(float(result["r_multiple"]) - levels["target_r_multiple"]) < 1e-9
            checks += 2
            outcomes.append({"direction": direction, "rr": rr, "outcome": result["outcome"],
                             "planned_broker_target_r": levels["target_r_multiple"]})

    gap_cases = [("buy_gap_stop", "BUY", 98.5, 100.5, "SL", "gap_through_stop"),
                 ("sell_gap_stop", "SELL", 101.5, 102.0, "SL", "gap_through_stop"),
                 ("buy_gap_target", "BUY", 102.0, 102.5, "TP", "gap_through_target"),
                 ("sell_gap_target", "SELL", 98.5, 99.0, "TP", "gap_through_target")]
    for name, direction, second_open, second_extreme, expected, gap_field in gap_cases:
        fake = fake_event(direction, 99.0 if direction == "BUY" else 101.0, name)
        first = {"time": 60, "open": 100.0, "high": 100.5, "low": 99.5, "close": 100.0}
        second = {"time": 120, "open": second_open,
                  "high": max(second_open, second_extreme), "low": min(second_open, second_extreme),
                  "close": second_open}
        result = evaluate_trade(fake, 1.0, {60: 0, 120: 1}, [first, second])
        assert result["outcome"] == expected and result[gap_field] == 1, (name, result)
        checks += 2
        outcomes.append({"fixture": name, "outcome": result["outcome"], gap_field: result[gap_field]})

    for direction in ("BUY", "SELL"):
        fake = fake_event(direction, 99.0 if direction == "BUY" else 101.0, f"both_{direction.lower()}")
        bar = {"time": 60, "open": 100.0, "high": 103.0, "low": 97.0, "close": 101.0}
        result = evaluate_trade(fake, 1.0, {60: 0}, [bar])
        assert result["outcome"] == "BOTH", (direction, result)
        checks += 1
        outcomes.append({"fixture": fake["event_id"], "outcome": result["outcome"]})

    delayed = fake_event("BUY", 99.0, "close59_delay", "m1_close59", 119)
    pre_entry = {"time": 60, "open": 100.0, "high": 105.0, "low": 90.0, "close": 100.0}
    actual_entry = {"time": 120, "open": 100.0, "high": 100.7, "low": 99.8, "close": 100.4}
    delayed_result = evaluate_trade(delayed, 1.0, {60: 0, 120: 1}, [pre_entry, actual_entry])
    assert delayed_result["entry_epoch"] == 120 and delayed_result["entry_delay_seconds"] == 1
    assert delayed_result["bars_held"] == 1 and delayed_result["outcome"] == "OPEN"
    checks += 3
    outcomes.append({"fixture": "close59_next_open_entry", "outcome": delayed_result["outcome"],
                     "entry_epoch": delayed_result["entry_epoch"]})

    missed_open = {**delayed, "event_id": "close59_missing_immediate_open"}
    after_gap = {"time": 3720, "open": 101.0, "high": 101.5, "low": 100.8, "close": 101.2}
    missed_result = evaluate_trade(missed_open, 1.0, {60: 0, 3720: 1}, [pre_entry, after_gap])
    assert missed_result["outcome"] == "NO_ENTRY"
    assert missed_result["no_entry_reason"] == "missing_expected_entry_open"
    assert missed_result["entry_epoch"] == ""
    checks += 3
    outcomes.append({"fixture": "close59_missing_immediate_open", "outcome": missed_result["outcome"],
                     "no_entry_reason": missed_result["no_entry_reason"]})

    return {"checks_passed": checks, "cases": outcomes}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT, help="Dukascopy M1 bid/ask CSV.gz")
    parser.add_argument("--output", type=Path, default=HERE)
    parser.add_argument("--compiler", default=shutil.which("clang++") or shutil.which("g++") or "clang++")
    parser.add_argument("--skip-audit", action="store_true", help="Do not invoke the independent raw-data audit")
    args = parser.parse_args()
    source = args.input.expanduser().resolve()
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    if not source.is_file():
        raise SystemExit(f"missing source dataset: {source}")

    m1_bars, coverage = read_source(source)
    if m1_bars[0]["time"] > STUDY_START or m1_bars[-1]["time"] + 60 < STUDY_END:
        raise SystemExit("dataset does not cover selected 2026-06-25 through 2026-09-25 interval")
    m15_bars = aggregate(m1_bars, 900)
    write_bars(output / "m1_bars.csv", m1_bars)
    write_bars(output / "m15_bars.csv", m15_bars)
    diagnostics, raw_events = run_core(output / "m1_bars.csv", output, args.compiler)
    events, event_fields = enrich_events(raw_events, m1_bars, m15_bars)
    with (output / "events.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=event_fields)
        writer.writeheader()
        writer.writerows(events)

    study_m1 = [bar for bar in m1_bars if STUDY_START <= bar["time"] < STUDY_END]
    study_m15 = [bar for bar in m15_bars if STUDY_START <= bar["time"] < STUDY_END]
    gap_counts = Counter()
    previous = None
    for bar in study_m1:
        if previous is not None and bar["time"] - previous != 60:
            gap_counts[bar["time"] - previous] += 1
        previous = bar["time"]
    monthly_events = defaultdict(Counter)
    for event in events:
        monthly_events[event["month_utc"]][event["direction"]] += 1
        monthly_events[event["month_utc"]]["total"] += 1
        monthly_events[event["month_utc"]]["quality_eligible"] += int(event["data_quality_eligible"])
    with (output / "monthly.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["month_utc", "BUY", "SELL", "signals", "quality_eligible"])
        for month in sorted(monthly_events):
            counts = monthly_events[month]
            writer.writerow([month, counts["BUY"], counts["SELL"], counts["total"], counts["quality_eligible"]])

    trade_summaries, trades = write_trades(output, events, m1_bars)
    source_files = ["WickHuntSRFlow.mq5", "WickHuntContextCore.mqh", "WickHuntSRCore.mqh",
                    "SwingCore.mqh", "FVGCore.mqh", "EngulfImbalanceCore.mqh", "EngulfFlowCore.mqh"]
    production_hashes = {name: sha256(ROOT / "MQL5/Indicators/WickHuntSRFlow" / name) for name in source_files}
    runner_paths = [HERE / "replay.cpp", HERE / "run_study.py", HERE / "audit_study.py",
                    HERE / "verify_ea_mapping.py"]
    runner_hashes = {path.name: sha256(path) for path in runner_paths if path.exists()}
    m15_groups_study = [bar for bar in study_m15]
    pattern_counts = Counter(str(event["pattern"]) for event in events)
    direction_counts = Counter(event["direction"] for event in events)
    sample_counts = Counter(event["sample_kind"] for event in events)
    retest_age_counts = Counter(str(event["retest_bar"]) for event in events)
    reference_trades = [row for row in trades["all_trades"] if row["rr"] == 1.0]
    candidate_entry_rows = [row for row in reference_trades if row["entry_epoch"] != ""]
    entered_rows = [row for row in candidate_entry_rows if row["outcome"] not in ("NO_ENTRY", "INVALID_STOP")]
    entry_delays = Counter(str(int(row["entry_delay_seconds"])) for row in entered_rows)
    entry_diagnostics = {
        "signals": len(reference_trades),
        "entries_before_study_end": len(entered_rows),
        "potential_entry_timestamps_including_rejections": len(candidate_entry_rows),
        "no_entry_before_study_end": sum(row["outcome"] == "NO_ENTRY" for row in reference_trades),
        "no_entry_reason_counts": dict(sorted(Counter(row["no_entry_reason"] for row in reference_trades
            if row["outcome"] == "NO_ENTRY").items())),
        "rejected_invalid_stop": sum(row["outcome"] == "INVALID_STOP" for row in reference_trades),
        "entry_delay_seconds_histogram": dict(sorted(entry_delays.items(), key=lambda kv: int(kv[0]))),
        "close59_delayed_entries": sum(row["entry_sample_kind"] == "next_observed_m1_open_after_close59" for row in entered_rows),
        "entry_crossed_m15_boundary": sum(int(row["entry_m15_boundary_cross"]) for row in entered_rows),
        "entry_open_gap_seconds_histogram": dict(sorted(Counter(str(int(row["entry_source_gap_seconds"]))
            for row in entered_rows).items(), key=lambda kv: int(kv[0]))),
    }
    fixtures = run_fixtures()
    artifact_paths = [output / "m1_bars.csv", output / "m15_bars.csv", output / "events.csv",
                      output / "events_raw.csv", output / "monthly.csv", output / "replay_diagnostics.json"]
    for rr in RR_VALUES:
        folder = output / f"rr-{rr:g}".replace(".", "_")
        artifact_paths.extend(folder / name for name in ("trades.csv", "monthly.csv", "summary.json"))
    artifact_paths.extend(output / name for name in ("ea_mapping_verification.json", "gallery_manifest.json")
                          if (output / name).is_file())
    summary = {
        "indicator": "WickHuntSRFlow 1.03",
        "symbol": "XAUUSD",
        "signal_timeframe": "M1",
        "hunt_timeframe": "M15",
        "study_window_utc": {"start_inclusive": START.isoformat(), "end_exclusive": END.isoformat(),
                             "duration_days": (END - START).days, "calendar_months": 3},
        "data_coverage_utc": coverage,
        "data": {
            "source": "Dukascopy XAUUSD M1 bid/ask OHLC, UTC offset 0",
            "source_path": str(source.relative_to(ROOT)) if source.is_relative_to(ROOT) else str(source),
            "source_sha256": sha256(source),
            "study_m1_rows": len(study_m1),
            "study_source_gaps_seconds": {str(delta): count for delta, count in sorted(gap_counts.items())},
            "m15_groups_study": len(m15_groups_study),
            "m15_complete_15m1_study": sum(bar["complete"] for bar in m15_groups_study),
            "m15_incomplete_study": sum(not bar["complete"] for bar in m15_groups_study),
            "m1_export_rows_include_seed_history": len(m1_bars),
            "m15_export_rows_include_seed_history": len(m15_bars),
            "m15_incomplete_quality_filter": "Raw signals are retained; primary quality subset excludes a current M15 setup whose final source bin lacks exactly 15 contiguous M1 opens. This is an ex-post data-completeness label, not a live signal condition.",
        },
        "production_source_sha256": production_hashes,
        "instant_engulf_broker_source_sha256": {
            name: sha256(ROOT / "MQL5/Experts/InstantEngulf" / name)
            for name in ("InstantBroker.mqh", "ScalpCore.mqh", "EngulfCore.mqh")
        },
        "runner_sha256": runner_hashes,
        "artifact_sha256": {str(path.relative_to(output)): sha256(path) for path in artifact_paths},
        "settings": {
            "InpSignalTF": "PERIOD_M1 (60 seconds)", "InpHuntTF": "PERIOD_M15 (900 seconds)",
            "InpScenario": "WS_BOTH", "scenario_pattern_values": {"1": "Breakout", "2": "Pullback", "3": "both qualified at reclaim"},
            "InpHuntBars": 1, "InpPullbackHuntBars": 2, "InpTouchBars": 5,
            "InpRetestBars": 8,
            "InpFastEMA": 12, "InpSlowEMA": 26, "InpSignalEMA": 9,
            "InpWarmupBars": 0, "warmup_effective_bars": 34,
            "InpSRCount": 10, "InpSRAnchor": "MS_SR_WICK", "InpFVGSearchBars": 0,
            "InpMinFVGGapPoints": 0, "InpRequireFVGMiddleDirection": False,
            "higher_context_quality_rule": "Only full, contiguous M15 bins are processed into WHC; an incomplete observed M15 bin resets WHC history and warmup. Context starts require the first M1 open exactly at the M15 epoch and the production higher replay warmup (35 closed M15 bars plus current bar).",
            "lower_context_rule": "After reclaim, consume only completed M1 closes. The first strict close-through frozen SR must be followed by the immediate next observed M1 bar closing strictly on the same side; then a sampled bid quote must retest that frozen SR within the next eight lower bars and before the M15 setup ends. Failed hold clears that candidate; a later fresh close-cross may retry.",
            "event_order": "M15 setup rolls before consuming the boundary-crossing prior M1 close. Reclaim precedes the M1 breakout close strictly; immediate successor close confirms hold; the first eligible sampled retest occurs within the same M15. Events are sampled at M1 open or representative close:59; close:59 signals enter only at the immediate next chronological M1 open, otherwise NO_ENTRY.",
        },
        "execution_assumptions": {
            "spread_model": "Fixed provisional $0.36 per XAUUSD unit (36 points at 0.01 point size); replaces variable recorded spread for all entries/exits.",
            "buy": "Entry Ask = sampled M1 bid open + 0.36; strategy SL is the M15 cumulative Bid low known at the signal, outward-rounded to the $0.01 tick; broker SL is unchanged. Exits execute on Bid.",
            "sell": "Entry Bid = sampled M1 bid open; strategy SL is the M15 cumulative Bid high known at the signal, outward-rounded to the $0.01 tick; broker SL and TP are each shifted upward by $0.36 and nearest-tick rounded as in InstantEngulf. Exits execute on Ask = Bid + 0.36.",
            "target": "Strategy TP is derived from the executable entry price at the actual entry M1 open (which can be delayed after a close:59 signal) and the already tick-rounded strategy SL using nominal RR 1/1.5/2, then nearest-tick rounded. Broker mapping follows InstantEngulf; sell executable target-R can differ from nominal RR. Strategy and broker geometry are both checked before counting a trade as entered.",
            "entry_timing": "An M1-open signal enters at that observed open. A close:59 signal enters only if the immediate next chronological M1 open exists, at that open; otherwise it is NO_ENTRY (a later open after a data gap is not assumed to fill a stale market order). Signal-minute OHLC is excluded from post-entry outcome checks. Delays, M15-boundary crosses and entry gaps are recorded.",
            "stop_known_time": "M15 cumulative wick as known at the retest signal snapshot (M1 open uses prior closed-minute extrema plus current open; close:59 also knows that minute's completed OHLC). No final forming-M15 OHLC is fed into an earlier signal.",
            "ambiguity": "Open is tested first, then M1 high/low. A same-M1 stop and target touch is BOTH with unknown order, excluded from main resolved metrics and included in bounds.",
            "gap_policy": "No missing M1 bars are synthesized. Observed open gaps through SL fill at actual open; target gaps fill at the limit target. Gaps can hide unobserved touches before the next quote. A close:59 market signal is not assumed to fill after an absent immediate next M1 open; it is NO_ENTRY.",
            "excluded_costs": ["commission", "swap", "latency", "slippage beyond observed open-gap fill"],
            "portfolio_note": "Every signal is evaluated independently and trades may overlap; summed R is not an equity curve or account return.",
            "exit_time_resolution": "For intraminute M1 OHLC touches, the exact tick order/time is unknown; same-minute stop and target touches are BOTH. Exit timestamps at :59 are representative bucket labels, not actual tick times. Open-gap exits use observed M1 open time.",
        },
        "replay": {
            **diagnostics,
            "raw_causal_events": len(raw_events),
            "events_after_current_m15_completeness_filter": sum(event["data_quality_eligible"] for event in events),
            "events_in_finally_incomplete_current_m15": sum(not event["data_quality_eligible"] for event in events),
            "counts_by_direction": dict(sorted(direction_counts.items())),
            "counts_by_pattern": dict(sorted(pattern_counts.items())),
            "counts_by_signal_sample_kind": dict(sorted(sample_counts.items())),
            "counts_by_retest_bar": dict(sorted(retest_age_counts.items(), key=lambda item: int(item[0]))),
            "rr1_entry_diagnostics": entry_diagnostics,
            "distinct_signal_m15_setups": len({event["setup_epoch"] for event in events}),
            "m15_setups_with_both_directions": sum(1 for setup in {event["setup_epoch"] for event in events}
                if {event["direction"] for event in events if event["setup_epoch"] == setup} == {"BUY", "SELL"}),
            "monthly_counts": {month: dict(counts) for month, counts in sorted(monthly_events.items())},
            "rr_summaries": trade_summaries,
            "trade_rows_per_rr": trades["trade_rows_per_rr"],
            "fixture_audit": fixtures,
            "fixture_result_sha256": hashlib.sha256(json.dumps(fixtures, sort_keys=True).encode("utf-8")).hexdigest(),
            "commands": [
                "python3 tests/reports/wick-hunt-sr-xauusd-m15-m1-3m-v103/run_study.py",
                "python3 tests/reports/wick-hunt-sr-xauusd-m15-m1-3m-v103/audit_study.py",
                "python3 tests/reports/wick-hunt-sr-xauusd-m15-m1-3m-v103/verify_ea_mapping.py",
                "python3 tests/reports/wick-hunt-sr-xauusd-m15-m1-3m-v103/build_gallery.py",
                "python3 tests/reports/wick-hunt-sr-xauusd-m15-m1-3m-v103/build_report.py",
            ],
        },
    }
    summary_path = output / "summary.json"
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    if not args.skip_audit and output == HERE.resolve() and source == DEFAULT_INPUT.resolve():
        subprocess.run([sys.executable, str(HERE / "audit_study.py")], cwd=ROOT, check=True)
        audit_path = output / "independent-audit.json"
        audit = json.loads(audit_path.read_text(encoding="utf-8"))
        summary["replay"]["independent_audit"] = audit
        summary["artifact_sha256"]["independent-audit.json"] = sha256(audit_path)
        summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    print(f"Study: {START.isoformat()} through {END.isoformat()} (end exclusive)")
    print(f"Signals: {len(events)} raw causal; {summary['replay']['events_after_current_m15_completeness_filter']} complete-M15 subset")
    for rr in RR_VALUES:
        stats = trade_summaries[str(rr)]["all_causal_events"]
        print(f"RR {rr:g}: TP {stats['TP']}, SL {stats['SL']}, BOTH {stats['BOTH']}, OPEN {stats['OPEN']}, WR {stats['win_rate_resolved']}")
    print(f"Output: {output}")


if __name__ == "__main__":
    main()
