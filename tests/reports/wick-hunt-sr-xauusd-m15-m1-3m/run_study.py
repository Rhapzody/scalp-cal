#!/usr/bin/env python3
"""Replay WickHuntSRFlow 1.02 on the latest complete three-month XAUUSD window."""
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


def enrich_events(raw_events: list[dict], m1_bars: list[dict], m15_bars: list[dict]) -> list[dict]:
    m1_by_time = {bar["time"]: bar for bar in m1_bars}
    m15_by_time = {bar["time"]: bar for bar in m15_bars}
    events = []
    for number, raw in enumerate(raw_events, 1):
        values = {key: int(float(raw[key])) for key in (
            "event_epoch", "setup_epoch", "direction", "sr_type", "breakout_epoch",
            "break_close_epoch", "pivot_epoch", "confirm_epoch", "pattern", "anchor_epoch",
            "trend_pivot_epoch", "trend_break_epoch", "trend_origin_epoch", "trend_confirm_epoch",
            "reclaim_epoch", "swept_prior_m15_count")}
        setup = values["setup_epoch"]
        context_bar = m15_by_time.get(setup)
        signal_bar = m1_by_time.get(values["event_epoch"])
        pivot_bar = m1_by_time.get(values["pivot_epoch"])
        confirm_bar = m1_by_time.get(values["confirm_epoch"])
        break_bar = m1_by_time.get(values["breakout_epoch"])
        if not context_bar or not signal_bar or not pivot_bar or not confirm_bar or not break_bar:
            raise ValueError(f"missing data reference for event {number}")
        direction = "BUY" if values["direction"] == 1 else "SELL"
        pattern_name = {1: "Breakout", 2: "Pullback", 3: "Breakout + Pullback"}[values["pattern"]]
        signal_dt = dt.datetime.fromtimestamp(values["event_epoch"], dt.timezone.utc)
        row = {
            "event_id": f"WHM15M1-{number:06d}",
            "event_time_utc": stamp(values["event_epoch"]), "event_epoch": values["event_epoch"],
            "sample_kind": raw["sample_kind"], "setup_time_utc": stamp(setup), "setup_epoch": setup,
            "direction": direction, "signal_bid": raw["signal_bid"], "price": raw["signal_bid"],
            "m15_open": raw["m15_open"], "hunt_open": raw["m15_open"],
            "pattern": values["pattern"], "pattern_label": pattern_name, "scenario_config": "WS_BOTH",
            "sr_price": raw["sr_price"], "sr_type": "Swing H" if values["sr_type"] == 1 else "Swing L",
            "breakout_time_utc": stamp(values["breakout_epoch"]), "breakout_epoch": values["breakout_epoch"],
            "break_close_time_utc": stamp(values["break_close_epoch"]), "break_close_epoch": values["break_close_epoch"],
            "pivot_time_utc": stamp(values["pivot_epoch"]), "pivot_epoch": values["pivot_epoch"],
            "swing_confirm_time_utc": stamp(values["confirm_epoch"]), "confirm_epoch": values["confirm_epoch"],
            "pivot_price": raw["pivot_price"], "context_sr": raw["context_sr"],
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
            "pivot_m1_source_count": pivot_bar["source_m1_count"],
            "confirmation_m1_source_count": confirm_bar["source_m1_count"],
            "month_utc": signal_dt.strftime("%Y-%m"),
            "inp_hunt_bars": 1, "inp_pullback_hunt_bars": 2, "inp_touch_bars": 5,
            "inp_sr_count": 10, "inp_sr_anchor": "MS_SR_WICK", "inp_fvg_search_bars": 0,
            "macd_fast": 12, "macd_slow": 26, "macd_signal": 9, "warmup_bars": 34,
        }
        events.append(row)
    fields = list(events[0]) if events else [
        "event_id", "event_time_utc", "event_epoch", "sample_kind", "setup_time_utc", "setup_epoch",
        "direction", "signal_bid", "price", "m15_open", "hunt_open", "pattern", "pattern_label",
        "scenario_config", "sr_price", "sr_type", "breakout_time_utc", "breakout_epoch",
        "break_close_time_utc", "break_close_epoch", "pivot_time_utc", "pivot_epoch",
        "swing_confirm_time_utc", "confirm_epoch", "pivot_price", "context_sr", "anchor_time_utc",
        "anchor_epoch", "trend_break_epoch", "trend_origin_epoch", "trend_origin_price",
        "trend_pivot_epoch", "trend_pivot_price", "trend_confirm_epoch", "trend_sr", "reclaim_time_utc",
        "reclaim_epoch", "reclaim_sample_kind", "reclaim_bid", "reclaim_known_high", "reclaim_known_low",
        "reclaim_tip", "known_high", "known_low", "prior_low_1", "prior_high_1", "prior_low_2",
        "prior_high_2", "swept_prior_m15_count", "current_m15_m1_count", "current_m15_complete",
        "data_quality_eligible", "breakout_m1_source_count", "pivot_m1_source_count",
        "confirmation_m1_source_count", "month_utc", "inp_hunt_bars", "inp_pullback_hunt_bars",
        "inp_touch_bars", "inp_sr_count", "inp_sr_anchor", "inp_fvg_search_bars", "macd_fast",
        "macd_slow", "macd_signal", "warmup_bars"]
    return events, fields


def _close_side(direction: str, bid: float) -> float:
    return bid if direction == "BUY" else bid + FIXED_SPREAD


def evaluate_trade(event: dict, rr: float, minute_index: int, m1_bars: list[dict]) -> dict:
    direction = event["direction"]
    entry_bar = m1_bars[minute_index]
    entry_bid = entry_bar["open"]
    entry = entry_bid + FIXED_SPREAD if direction == "BUY" else entry_bid
    stop = float(event["known_low"]) if direction == "BUY" else float(event["known_high"]) + FIXED_SPREAD
    risk = entry - stop if direction == "BUY" else stop - entry
    base = {
        "event_id": event["event_id"], "signal_epoch": event["event_epoch"], "direction": direction,
        "rr": rr, "entry_epoch": entry_bar["time"], "entry_time_utc": stamp(entry_bar["time"]),
        "entry_bid": entry_bid, "entry_price": entry, "entry_side": "ASK" if direction == "BUY" else "BID",
        "entry_spread": FIXED_SPREAD, "stop_price": stop, "stop_side": "BID" if direction == "BUY" else "ASK",
        "initial_risk": risk, "target_price": "", "target_side": "BID" if direction == "BUY" else "ASK",
        "exit_epoch": "", "exit_time_utc": "", "exit_bar_open_epoch": "", "exit_bar_close_epoch": "",
        "exit_price": "", "exit_side": "BID" if direction == "BUY" else "ASK",
        "exit_sample_kind": "", "outcome": "INVALID_STOP", "r_multiple": "",
        "mark_to_market_r": "", "gap_through_stop": 0, "gap_through_target": 0,
        "source_gap_count": 0, "source_gap_exposed": 0, "bars_held": 0,
        "data_quality_eligible": int(event["data_quality_eligible"]), "month_utc": event["month_utc"],
    }
    if not math.isfinite(risk) or risk <= 0:
        return base
    target = entry + rr * risk if direction == "BUY" else entry - rr * risk
    base["target_price"] = target
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
            base.update({"outcome": "SL", "exit_epoch": bar["time"], "exit_time_utc": stamp(bar["time"]),
                         "exit_bar_open_epoch": bar["time"], "exit_bar_close_epoch": bar["time"] + 60,
                         "exit_price": open_exec, "exit_sample_kind": "observed_open_gap_or_touch",
                         "r_multiple": ((open_exec - entry) / risk if direction == "BUY" else (entry - open_exec) / risk),
                         "gap_through_stop": int(open_exec < stop if direction == "BUY" else open_exec > stop),
                         "source_gap_count": gap_count, "source_gap_exposed": int(gap_count > 0)})
            return base
        if target_open_hit:
            base.update({"outcome": "TP", "exit_epoch": bar["time"], "exit_time_utc": stamp(bar["time"]),
                         "exit_bar_open_epoch": bar["time"], "exit_bar_close_epoch": bar["time"] + 60,
                         "exit_price": target, "exit_sample_kind": "observed_open_limit_target",
                         "r_multiple": rr, "gap_through_target": int(open_exec > target if direction == "BUY" else open_exec < target),
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
                         "exit_sample_kind": "intraminute_limit_target_touch_approx", "r_multiple": rr,
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
    all_both_tp_r = all_both_sl_r + both * (1.0 + float(rows[0]["rr"] if rows else 0))
    denominator_with_both = resolved + both
    return {
        "signals": len(rows), "TP": tp, "SL": sl, "BOTH": both, "OPEN": opened,
        "INVALID_STOP": invalid, "resolved_TP_SL": resolved,
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
    trade_fields = ["event_id", "signal_epoch", "direction", "rr", "entry_epoch", "entry_time_utc",
                    "entry_bid", "entry_price", "entry_side", "entry_spread", "stop_price", "stop_side",
                    "initial_risk", "target_price", "target_side", "exit_epoch", "exit_time_utc",
                    "exit_bar_open_epoch", "exit_bar_close_epoch", "exit_price", "exit_side",
                    "exit_sample_kind", "outcome", "r_multiple", "mark_to_market_r", "gap_through_stop",
                    "gap_through_target", "source_gap_count", "source_gap_exposed", "bars_held",
                    "data_quality_eligible", "month_utc"]
    all_trades = []
    for rr in RR_VALUES:
        directory = output / f"rr-{rr:g}".replace(".", "_")
        directory.mkdir(parents=True, exist_ok=True)
        trades = []
        for event in events:
            index = m1_index.get(event["event_epoch"])
            if index is None:
                raise ValueError(f"event entry is not an observed M1 open: {event['event_id']}")
            trade = evaluate_trade(event, rr, index, m1_bars)
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
                             "INVALID_STOP", "win_rate_resolved", "sum_resolved_R", "profit_factor_R"])
            for month in sorted(k[1] for k in month_rows if k[0] == rr):
                rows = [t for t in all_trades if t["rr"] == rr and t["month_utc"] == month]
                all_summary = summarize_trades(rows, False)
                quality_summary = summarize_trades(rows, True)
                writer.writerow([month, all_summary["signals"], quality_summary["signals"],
                                 all_summary["TP"], all_summary["SL"], all_summary["BOTH"], all_summary["OPEN"],
                                 all_summary["INVALID_STOP"], all_summary["win_rate_resolved"],
                                 all_summary["sum_resolved_R"], all_summary["profit_factor_R"]])
    return summaries, {"trade_rows_per_rr": len(events), "all_trades": all_trades}


def run_fixtures() -> dict:
    """Exercise executable sides, all RR targets, gap fills and BOTH classification."""
    checks = 0
    outcomes = []
    for direction in ("BUY", "SELL"):
        for rr in RR_VALUES:
            if direction == "BUY":
                entry = 100.36
                stop = 99.00
                risk = entry - stop
                target = entry + rr * risk
                bars = [{"time": 60, "open": 100.0, "high": target + .1, "low": 99.5, "close": 101.0}]
                fake = {"direction": direction, "known_low": stop, "known_high": 100.5,
                        "event_epoch": 60, "data_quality_eligible": 1, "month_utc": "test", "event_id": "fixture"}
            else:
                entry = 100.0
                stop = 101.36
                risk = stop - entry
                target = entry - rr * risk
                bid_high = 100.5
                bars = [{"time": 60, "open": 100.0, "high": bid_high, "low": target - FIXED_SPREAD - .1,
                         "close": 99.0}]
                fake = {"direction": direction, "known_low": 99.5, "known_high": 101.0,
                        "event_epoch": 60, "data_quality_eligible": 1, "month_utc": "test", "event_id": "fixture"}
            result = evaluate_trade(fake, rr, 0, bars)
            assert result["outcome"] == "TP", (direction, rr, result)
            assert abs(float(result["r_multiple"]) - rr) < 1e-9
            checks += 2
            outcomes.append({"direction": direction, "rr": rr, "target": result["outcome"]})
    fixtures = [
        ("buy_gap_stop", "BUY", 99.0, 98.5, 99.0, 99.2, "SL", True),
        ("sell_gap_stop", "SELL", 101.0, 102.0, 101.0, 102.2, "SL", True),
    ]
    for name, direction, known_price, open_price, high, low, expected, gap in fixtures:
        fake = {"direction": direction, "known_low": 99.0 if direction == "BUY" else 99.5,
                "known_high": 100.5 if direction == "BUY" else 101.0,
                "event_epoch": 60, "data_quality_eligible": 1, "month_utc": "test", "event_id": name}
        first_bar = {"time": 60, "open": 100.0, "high": 100.5, "low": 99.5, "close": 100.0}
        if direction == "SELL":
            fake["known_high"] = known_price
            second_low = min(open_price, high, low)
            second_high = max(open_price, high, low)
        else:
            fake["known_low"] = known_price
            second_low = min(open_price, high, low)
            second_high = max(open_price, high, low)
        result = evaluate_trade(fake, 1.0, 0, [first_bar, {"time": 120, "open": open_price,
                                                           "high": second_high, "low": second_low,
                                                           "close": open_price}])
        assert result["outcome"] == expected and result["gap_through_stop"] == int(gap), (name, result)
        checks += 2
        outcomes.append({"fixture": name, "outcome": result["outcome"], "gap_stop": result["gap_through_stop"]})
    target_gap_fixtures = [
        ("buy_gap_target", "BUY", 100.0, 102.0, 101.8, 102.5),
        ("sell_gap_target", "SELL", 100.0, 97.5, 97.0, 97.8),
    ]
    for name, direction, entry_bid, open_bid, low_bid, high_bid in target_gap_fixtures:
        fake = {"direction": direction, "known_low": 99.0, "known_high": 101.0,
                "event_epoch": 60, "data_quality_eligible": 1, "month_utc": "test", "event_id": name}
        first = {"time": 60, "open": 100.0, "high": 100.5, "low": 99.5, "close": 100.0}
        second = {"time": 120, "open": open_bid, "high": high_bid, "low": low_bid, "close": open_bid}
        result = evaluate_trade(fake, 1.0, 0, [first, second])
        assert result["outcome"] == "TP" and result["gap_through_target"] == 1, (name, result)
        checks += 2
        outcomes.append({"fixture": name, "outcome": result["outcome"], "gap_target": result["gap_through_target"]})
    for direction in ("BUY", "SELL"):
        fake = {"direction": direction, "known_low": 99.0, "known_high": 101.0,
                "event_epoch": 60, "data_quality_eligible": 1, "month_utc": "test", "event_id": f"both_{direction.lower()}"}
        bar = {"time": 60, "open": 100.0, "high": 103.0, "low": 97.0, "close": 101.0}
        result = evaluate_trade(fake, 1.0, 0, [bar])
        assert result["outcome"] == "BOTH", (direction, result)
        checks += 1
        outcomes.append({"fixture": fake["event_id"], "outcome": result["outcome"]})
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
    runner_paths = [HERE / "replay.cpp", HERE / "run_study.py", HERE / "audit_study.py"]
    runner_hashes = {path.name: sha256(path) for path in runner_paths if path.exists()}
    m15_groups_study = [bar for bar in study_m15]
    pattern_counts = Counter(str(event["pattern"]) for event in events)
    direction_counts = Counter(event["direction"] for event in events)
    fixtures = run_fixtures()
    artifact_paths = [output / "m1_bars.csv", output / "m15_bars.csv", output / "events.csv",
                      output / "events_raw.csv", output / "monthly.csv", output / "replay_diagnostics.json"]
    for rr in RR_VALUES:
        folder = output / f"rr-{rr:g}".replace(".", "_")
        artifact_paths.extend(folder / name for name in ("trades.csv", "monthly.csv", "summary.json"))
    summary = {
        "indicator": "WickHuntSRFlow 1.02",
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
        "runner_sha256": runner_hashes,
        "artifact_sha256": {str(path.relative_to(output)): sha256(path) for path in artifact_paths},
        "settings": {
            "InpSignalTF": "PERIOD_M1 (60 seconds)", "InpHuntTF": "PERIOD_M15 (900 seconds)",
            "InpScenario": "WS_BOTH", "scenario_pattern_values": {"1": "Breakout", "2": "Pullback", "3": "both qualified at reclaim"},
            "InpHuntBars": 1, "InpPullbackHuntBars": 2, "InpTouchBars": 5,
            "InpFastEMA": 12, "InpSlowEMA": 26, "InpSignalEMA": 9,
            "InpWarmupBars": 0, "warmup_effective_bars": 34,
            "InpSRCount": 10, "InpSRAnchor": "MS_SR_WICK", "InpFVGSearchBars": 0,
            "InpMinFVGGapPoints": 0, "InpRequireFVGMiddleDirection": False,
            "higher_context_quality_rule": "Only full, contiguous M15 bins are processed into WHC; an incomplete observed M15 bin resets WHC history and warmup. Context starts require the first M1 open exactly at the M15 epoch and the production higher replay warmup (35 closed M15 bars plus current bar).",
            "lower_context_rule": "Consume only completed M1 bars at the next observed M1 open; sampled close:59 is only a representative reclaim snapshot, never an entry or a closed-bar event.",
            "event_order": "M15 hunt/reclaim first; M1 close must be strictly after reclaim in same M15; event/entry at next observed M1 open.",
        },
        "execution_assumptions": {
            "spread_model": "Fixed provisional $0.36 per XAUUSD unit (36 points at 0.01 point size); replaces variable recorded spread for all entries/exits.",
            "buy": "Entry Ask = M1 bid open + 0.36; SL is known cumulative M15 Bid low at event; exits execute on Bid.",
            "sell": "Entry Bid = M1 bid open; SL is known cumulative M15 Bid high + 0.36 Ask; exits execute on Ask = Bid + 0.36.",
            "target": "TP distance from actual executable entry equals RR times initial executable entry-to-stop risk; no tick-grid rounding.",
            "entry_timing": "Zero-latency fill at the first observed M1 open where the closed M1 break is consumed and signaled.",
            "stop_known_time": "M15 cumulative wick as known at the M1 entry-open snapshot; no final forming-M15 OHLC used.",
            "ambiguity": "Open is tested first, then M1 high/low. A same-M1 stop and target touch is BOTH with unknown order, excluded from main resolved metrics and included in bounds.",
            "gap_policy": "No missing M1 bars are synthesized. Observed open gaps through SL fill at actual open; target gaps fill at the limit target. Gaps can hide unobserved touches before the next quote.",
            "excluded_costs": ["commission", "swap", "latency", "slippage beyond observed open-gap fill"],
            "portfolio_note": "Every signal is evaluated independently and trades may overlap; summed R is not an equity curve or account return.",
            "exit_time_resolution": "For intraminute OHLC touches, the actual tick time is unknown; exit_epoch labels the M1 minute-end snapshot at :59 for visualization. Open-gap exits use observed M1 open time.",
        },
        "replay": {
            **diagnostics,
            "raw_causal_events": len(raw_events),
            "events_after_current_m15_completeness_filter": sum(event["data_quality_eligible"] for event in events),
            "events_in_finally_incomplete_current_m15": sum(not event["data_quality_eligible"] for event in events),
            "counts_by_direction": dict(sorted(direction_counts.items())),
            "counts_by_pattern": dict(sorted(pattern_counts.items())),
            "distinct_signal_m15_setups": len({event["setup_epoch"] for event in events}),
            "m15_setups_with_both_directions": sum(1 for setup in {event["setup_epoch"] for event in events}
                if {event["direction"] for event in events if event["setup_epoch"] == setup} == {"BUY", "SELL"}),
            "monthly_counts": {month: dict(counts) for month, counts in sorted(monthly_events.items())},
            "rr_summaries": trade_summaries,
            "trade_rows_per_rr": trades["trade_rows_per_rr"],
            "fixture_audit": fixtures,
            "fixture_result_sha256": hashlib.sha256(json.dumps(fixtures, sort_keys=True).encode("utf-8")).hexdigest(),
            "commands": [
                "python3 tests/reports/wick-hunt-sr-xauusd-m15-m1-3m/run_study.py",
                "python3 tests/reports/wick-hunt-sr-xauusd-m15-m1-3m/audit_study.py",
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
