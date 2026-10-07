#!/usr/bin/env python3
"""Evaluate each current WickHunt signal separately at executable-price RR 1:1."""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import gzip
import hashlib
import json
import math
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPORT = HERE.parent
ROOT = REPORT.parents[2]
DATA = ROOT / "tests/reports/engulf-imbalance-xauusd-m1/xauusd_m1_bid_ask.csv.gz"
EPS = 1e-9


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def stamp(epoch: int) -> str:
    return dt.datetime.fromtimestamp(epoch, dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")


def read_data() -> tuple[list[dict], dict[int, int], dict[int, dict]]:
    rows, indices, extremes = [], {}, {}
    active_hour = None
    running = {}
    with gzip.open(DATA, "rt", newline="") as handle:
        for source in csv.DictReader(handle):
            t = int(source["epoch"])
            row = {"epoch": t, **{k: float(source[k]) for k in
                   ("bid_open", "bid_high", "bid_low", "bid_close", "ask_open", "ask_high", "ask_low", "ask_close")}}
            if rows and t <= rows[-1]["epoch"]:
                raise ValueError("source timestamps must increase strictly")
            for side in ("bid", "ask"):
                o, h, l, c = [row[f"{side}_{k}"] for k in ("open", "high", "low", "close")]
                if not all(math.isfinite(v) for v in (o, h, l, c)) or l > min(o, c) or h < max(o, c):
                    raise ValueError("invalid OHLC")
            if row["ask_open"] < row["bid_open"]:
                raise ValueError("negative entry spread")
            hour = t // 3600 * 3600
            if hour != active_hour:
                active_hour = hour
                running = {f"{side}_{k}": row[f"{side}_open"] for side in ("bid", "ask") for k in ("low", "high")}
            # At an M1 Open only prior completed minutes and the current Open are known.
            for side in ("bid", "ask"):
                running[f"{side}_low"] = min(running[f"{side}_low"], row[f"{side}_open"])
                running[f"{side}_high"] = max(running[f"{side}_high"], row[f"{side}_open"])
            extremes[t] = dict(running)
            indices[t] = len(rows)
            rows.append(row)
            for side in ("bid", "ask"):
                running[f"{side}_low"] = min(running[f"{side}_low"], row[f"{side}_low"])
                running[f"{side}_high"] = max(running[f"{side}_high"], row[f"{side}_high"])
    return rows, indices, extremes


def bar_hit(direction: int, bar: dict, stop: float, target: float) -> tuple[str | None, float | None, str]:
    """Open is observed first. High/Low have no assumed order."""
    side = "bid" if direction == 1 else "ask"
    o, high, low = [bar[f"{side}_{k}"] for k in ("open", "high", "low")]
    if (o <= stop + EPS) if direction == 1 else (o >= stop - EPS):
        return "SL", o, "open_gap_or_touch"
    if (o >= target - EPS) if direction == 1 else (o <= target + EPS):
        return "TP", target, "open_target_limit_fill"
    hit_stop = low <= stop + EPS if direction == 1 else high >= stop - EPS
    hit_target = high >= target - EPS if direction == 1 else low <= target + EPS
    if hit_stop and hit_target:
        return "BOTH", None, "intraminute_order_unknown"
    if hit_stop:
        return "SL", stop, "intraminute_stop_touch"
    if hit_target:
        return "TP", target, "intraminute_target_touch"
    return None, None, ""


def evaluate(event: dict, number: int, bars: list[dict], indices: dict[int, int],
             extremes: dict[int, dict], m5: dict[int, dict], stop_mode: str, end: int) -> dict:
    now = int(event["event_epoch"])
    if event["sample_kind"] != "m1_open" or now not in indices:
        raise ValueError("this evaluator requires an observed M1 Open signal")
    direction = 1 if event["direction"] == "BUY" else -1
    index = indices[now]
    current = bars[index]
    entry = current["ask_open" if direction == 1 else "bid_open"]
    anchor_bid = extremes[now]["bid_low" if direction == 1 else "bid_high"]
    if stop_mode == "h1":
        stop = extremes[now]["bid_low" if direction == 1 else "ask_high"]
    else:
        lower = m5[int(event["breakout_epoch"])]
        anchor_bid = lower["bid_low" if direction == 1 else "bid_high"]
        stop = lower["bid_low" if direction == 1 else "ask_high"]
    risk = direction * (entry - stop)
    target = entry + direction * risk
    row = {"number": number, "signal_time_utc": event["event_time_utc"], "entry_epoch": now,
           "direction": event["direction"], "sr_type": event["sr_type"], "sr_price": float(event["sr_price"]),
           "setup_epoch": int(event["setup_epoch"]), "reclaim_epoch": int(event["reclaim_epoch"]),
           "breakout_epoch": int(event["breakout_epoch"]), "stop_mode": stop_mode,
           "entry": entry, "entry_spread": current["ask_open"] - current["bid_open"],
           "stop_bid_wick": anchor_bid, "stop": stop, "target": target, "risk_price": risk,
           "result": "OPEN", "exit_epoch": "", "exit_time_utc": "", "exit_price": "",
           "exit_phase": "", "r_multiple": "", "last_mark_r": "", "observed_minutes": 0,
           "exposed_source_gaps": 0, "missing_seconds_between_observations": 0}
    close_quote = current["bid_open" if direction == 1 else "ask_open"]
    if risk <= EPS or direction * (close_quote - stop) <= EPS:
        row["result"] = "INVALID_STOP"
        return row
    previous_time = now
    last_bar = current
    for j in range(index, len(bars)):
        bar = bars[j]
        if bar["epoch"] >= end:
            break
        delta = bar["epoch"] - previous_time
        if delta > 60:
            row["exposed_source_gaps"] += 1
            row["missing_seconds_between_observations"] += delta - 60
        previous_time = bar["epoch"]
        last_bar = bar
        row["observed_minutes"] += 1
        result, fill, phase = bar_hit(direction, bar, stop, target)
        if result is None:
            continue
        row.update(result=result, exit_epoch=bar["epoch"], exit_time_utc=stamp(bar["epoch"]),
                   exit_price="" if fill is None else fill, exit_phase=phase,
                   r_multiple="" if fill is None else direction * (fill - entry) / risk)
        return row
    last_quote = last_bar["bid_close" if direction == 1 else "ask_close"]
    row["last_mark_r"] = direction * (last_quote - entry) / risk
    return row


def metrics(trades: list[dict]) -> dict:
    counts = Counter(t["result"] for t in trades)
    closed = [t for t in trades if t["result"] in ("TP", "SL")]
    wins = [float(t["r_multiple"]) for t in closed if t["result"] == "TP"]
    losses = [float(t["r_multiple"]) for t in closed if t["result"] == "SL"]
    total_r = sum(wins + losses)
    ambiguous = counts["BOTH"]
    resolved = len(closed)
    return {"signals": len(trades), **{k: counts[k] for k in ("TP", "SL", "BOTH", "OPEN", "INVALID_STOP")},
            "resolved": resolved, "win_rate_resolved": len(wins) / resolved if resolved else None,
            "sum_resolved_R": total_r, "mean_resolved_R": total_r / resolved if resolved else None,
            "profit_factor_in_R": sum(wins) / -sum(losses) if sum(losses) < 0 else None,
            "win_rate_if_all_BOTH_SL": len(wins) / (resolved + ambiguous) if resolved + ambiguous else None,
            "win_rate_if_all_BOTH_TP": (len(wins) + ambiguous) / (resolved + ambiguous) if resolved + ambiguous else None,
            "sum_R_if_all_BOTH_SL": total_r - ambiguous,
            "sum_R_if_all_BOTH_TP": total_r + ambiguous,
            "stop_gap_fills": sum(t["exit_phase"] == "open_gap_or_touch" and float(t["r_multiple"]) < -1-EPS for t in closed),
            "trades_exposed_to_source_gaps": sum(t["exposed_source_gaps"] > 0 for t in trades),
            "median_observed_minutes_to_exit": sorted(t["observed_minutes"] for t in closed)[resolved//2] if resolved else None}


def write_csv(path: Path, rows: list[dict]) -> None:
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stop", choices=("h1", "m5"), required=True)
    args = parser.parse_args()
    source_summary = json.loads((REPORT / "summary.json").read_text())
    if sha(DATA) != source_summary["data"]["prepared_sha256"]:
        raise ValueError("source dataset changed")
    for name, expected in source_summary["artifacts"].items():
        if sha(REPORT / name) != expected:
            raise ValueError(f"source report changed: {name}")
    for name, expected in source_summary["production_source_sha256"].items():
        if sha(ROOT / "MQL5/Indicators/WickHuntSRFlow" / name) != expected:
            raise ValueError(f"indicator source changed: {name}")
    with (REPORT / "events.csv").open() as handle:
        events = list(csv.DictReader(handle))
    bars, indices, extremes = read_data()
    m5 = {}
    for bar in bars:
        bucket = bar["epoch"] // 300 * 300
        if bucket not in m5:
            m5[bucket] = {k: bar[k] for k in ("bid_low", "bid_high", "ask_high")}
        else:
            m5[bucket]["bid_low"] = min(m5[bucket]["bid_low"], bar["bid_low"])
            for key in ("bid_high", "ask_high"):
                m5[bucket][key] = max(m5[bucket][key], bar[key])
    end = int(dt.datetime.fromisoformat(source_summary["study_window_utc"]["end_exclusive"]).timestamp())
    trades = [evaluate(e, i, bars, indices, extremes, m5, args.stop, end) for i, e in enumerate(events, 1)]
    output = HERE / f"sl-{args.stop}"
    output.mkdir(exist_ok=True)
    write_csv(output / "trades.csv", trades)
    monthly = [{"month_utc": month, **metrics([r for r in trades if r["signal_time_utc"].startswith(month)])}
               for month in sorted({r["signal_time_utc"][:7] for r in trades})]
    write_csv(output / "monthly.csv", monthly)
    summary = {"indicator": source_summary["indicator"], "symbol": "XAUUSD", "rr": 1,
               "study_window_utc": source_summary["study_window_utc"],
               "settings": {"stop_mode": args.stop,
                            "entry": "first observed M1 Open at signal after closed M5 breakout; zero latency",
                            "buy": "enter Ask; SL at observed Bid low; exit on Bid",
                            "sell": "enter Bid; SL at observed Ask high; exit on Ask",
                            "stop_known_time": "H1 extremes strictly known at signal Open, or closed breakout M5 extremes",
                            "tp": "one executable entry-to-SL distance; no additional buffer",
                            "overlap": "all signals assessed independently, including opposite sides in the same H1",
                            "holding": "until first observed TP/SL touch or study end; no H1 close exit",
                            "same_m1_both": "BOTH, unknown order; excluded from primary win rate and sum R; bounds also reported",
                            "gaps": "SL beyond at next observed Open fills at Open; TP limit fills at target; no bars filled across source gaps",
                            "costs": "actual Bid/Ask spread included; commission, swap and latency slippage excluded",
                            "portfolio": "signal-level outcomes only; no balance, compounding or equity drawdown model"},
               "overall": metrics(trades),
               "by_direction": {side: metrics([r for r in trades if r["direction"] == side]) for side in ("BUY", "SELL")},
               "by_sr_type": {side: metrics([r for r in trades if r["sr_type"] == side]) for side in ("Swing H", "Swing L")},
               "all_reference_m5_complete": metrics([r for r, e in zip(trades, events) if e["all_reference_m5_complete"] == "1"]),
               "without_exposed_source_gaps": metrics([r for r in trades if r["exposed_source_gaps"] == 0]),
               "monthly": monthly,
               "limitations": ["Signal timing is the existing M1 snapshot approximation, not tick replay or MT5 Strategy Tester.",
                               "Intraminute exit timestamps identify the M1 bucket, not an exact tick.",
                               "Historical outcomes across source gaps cannot establish unobserved paths; gap-free subset is reported.",
                               "Results are not a portfolio return because signal trades can overlap."],
               "inputs_sha256": {"source": sha(DATA), "events": sha(REPORT / "events.csv"), "runner": sha(Path(__file__))},
               "artifacts_sha256": {name: sha(output / name) for name in ("trades.csv", "monthly.csv")}}
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps({"output": str(output), "overall": summary["overall"], "by_direction": summary["by_direction"]}, indent=2))


if __name__ == "__main__":
    main()
