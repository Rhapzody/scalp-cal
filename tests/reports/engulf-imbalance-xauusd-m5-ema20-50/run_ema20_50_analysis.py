#!/usr/bin/env python3
"""Rebuild FVG-only events and compare causal EMA50/EMA20-50 regime filters."""
from __future__ import annotations

import csv
import datetime as dt
import hashlib
import json
import math
import re
import shutil
import subprocess
import tempfile
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
INPUT = ROOT / "tests/reports/engulf-imbalance-xauusd-m5/m5_bars.csv"
SOURCE = ROOT / "MQL5/Indicators/EngulfImbalanceFlow"
START = dt.datetime(2025, 9, 27, tzinfo=dt.timezone.utc)
END = dt.datetime(2026, 9, 28, tzinfo=dt.timezone.utc)
POINT = 0.001
STOP_BUFFER_POINTS = 15
EMA_FAST_PERIOD = 20
EMA_SLOW_PERIOD = 50
ALPHA20 = 2.0 / (EMA_FAST_PERIOD + 1)
ALPHA50 = 2.0 / (EMA_SLOW_PERIOD + 1)
FILTERS = ("baseline", "ema50_price_side", "ema20_50_regime", "ema20_50_prior_bar")
PATTERNS = ("ALL", "A", "B", "A+B")
SIDES = ("ALL", "BUY", "SELL")
EXPECTED_BARS = 75505
EXPECTED_DATA_SHA256 = "16323f99e604f4df40895db0b6a4d6c4e61d809f3e1b41fc9028f84a8d448215"
EXPECTED_EVENT_SHA256 = "71fdcc2595881920d2b4a1da63021b9ddc08720b6cf35d0d0782485e2c2c36ab"
EXPECTED_SOURCE_HASHES = {
    "EngulfImbalanceFlow.mq5": "70b7a9a8911ec851f8774814fb477353d41697e7381f01ec6bc7890db5edf900",
    "EngulfImbalanceCore.mqh": "cf3e1d8a0cd6ce955ac54807770f0e07ee25543781aaae67d79ccb9db82b8472",
    "EngulfFlowCore.mqh": "f13bd146d05896a072dd2e1713a6f4684730eddfd43429cfb9ab91dd9a9de83d",
    "FVGCore.mqh": "713befe4121d14aad2316a54411eeb7b0c14dafbf4115a10bc14542a096fb61c",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_bars() -> list[dict]:
    if sha256(INPUT) != EXPECTED_DATA_SHA256:
        raise ValueError("M5 input SHA-256 differs from the prior analysis")
    with INPUT.open(newline="", encoding="utf-8") as stream:
        bars = list(csv.DictReader(stream))
    if len(bars) != EXPECTED_BARS:
        raise ValueError(f"expected {EXPECTED_BARS} M5 bars; got {len(bars)}")
    for i, bar in enumerate(bars):
        bar["index"] = i
        bar["epoch"] = int(bar["epoch"])
        for key in ("open", "high", "low", "close"):
            bar[key] = float(bar[key])
        if i and bar["epoch"] <= bars[i - 1]["epoch"]:
            raise ValueError("input timestamps are not strictly increasing")
        if not (bar["low"] <= min(bar["open"], bar["close"]) <=
                max(bar["open"], bar["close"]) <= bar["high"]):
            raise ValueError(f"invalid OHLC at input row {i}")
    return bars


def compile_and_replay(events_path: Path) -> str:
    compiler = shutil.which("clang++") or shutil.which("g++")
    if not compiler:
        raise RuntimeError("clang++ or g++ is required to replay the shipped C++ core")
    core_text = (SOURCE / "EngulfImbalanceCore.mqh").read_text(encoding="utf-8")
    adapted = re.sub(
        r"const (WHBar|FVGBar|long|int) &(\w+)\[\]",
        r"const std::vector<\1> &\2",
        core_text,
    )
    if adapted == core_text:
        raise RuntimeError("expected MQL array parameters were not adapted")
    start = int(START.timestamp())
    end = int(END.timestamp())
    with tempfile.TemporaryDirectory(prefix="ei-fvg-ema20-50-") as tmp:
        build = Path(tmp)
        (build / "ei_core_adapted.hpp").write_text(
            "#include <algorithm>\n#include <vector>\n" + adapted, encoding="utf-8"
        )
        binary = build / "replay-fvg"
        subprocess.run(
            [
                compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
                "-I", str(build), "-I", str(SOURCE), str(HERE / "replay_fvg.cpp"),
                "-o", str(binary),
            ],
            cwd=ROOT,
            check=True,
        )
        result = subprocess.run(
            [str(binary), str(INPUT), str(start), str(end), str(events_path)],
            cwd=ROOT,
            check=True,
            text=True,
            capture_output=True,
        )
        return result.stdout.strip()


def wilson95(wins: int, n: int) -> tuple[float | None, float | None]:
    if not n:
        return None, None
    z = 1.959963984540054
    p = wins / n
    denom = 1 + z * z / n
    center = (p + z * z / (2 * n)) / denom
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom
    return center - half, center + half


def annotate_events(bars: list[dict], raw_events: list[dict]) -> list[dict]:
    closes = [bar["close"] for bar in bars]
    ema20 = [0.0] * len(bars)
    ema50 = [0.0] * len(bars)
    ema20[0] = ema50[0] = closes[0]
    for i in range(1, len(bars)):
        ema20[i] = ALPHA20 * closes[i] + (1 - ALPHA20) * ema20[i - 1]
        ema50[i] = ALPHA50 * closes[i] + (1 - ALPHA50) * ema50[i - 1]

    out = []
    for raw in raw_events:
        i = int(raw["index"])
        side = raw["side"]
        bar = bars[i]
        for key in ("open", "high", "low", "close"):
            if abs(float(raw[key]) - bar[key]) > 1e-9:
                raise ValueError(f"core event OHLC does not match source at index {i}")
        if i + 1 >= len(bars):
            raise ValueError(f"no next bar for signal at index {i}")
        direction = 1 if side == "BUY" else -1
        ema50_price_pass = (bar["close"] > ema50[i]) if direction == 1 else (bar["close"] < ema50[i])
        regime_pass = (ema20[i] > ema50[i]) if direction == 1 else (ema20[i] < ema50[i])
        prior_regime_pass = (ema20[i - 1] > ema50[i - 1]) if direction == 1 else (ema20[i - 1] < ema50[i - 1])

        pair_high = max(bars[i - 1]["high"], bar["high"])
        pair_low = min(bars[i - 1]["low"], bar["low"])
        stop = pair_low - STOP_BUFFER_POINTS * POINT if direction == 1 else pair_high + STOP_BUFFER_POINTS * POINT
        entry = bars[i + 1]["open"]
        risk = entry - stop if direction == 1 else stop - entry
        if risk <= 0:
            raise ValueError(f"nonpositive signal risk at index {i}")
        target = entry + risk if direction == 1 else entry - risk

        result, bars_to_hit = "UNRESOLVED", ""
        for j in range(i + 1, len(bars)):
            lo, hi = bars[j]["low"], bars[j]["high"]
            hit_stop = lo <= stop if direction == 1 else hi >= stop
            hit_target = hi >= target if direction == 1 else lo <= target
            if hit_stop and hit_target:
                result, bars_to_hit = "BOTH", j - i
                break
            if hit_target:
                result, bars_to_hit = "TP", j - i
                break
            if hit_stop:
                result, bars_to_hit = "SL", j - i
                break

        event = dict(raw)
        event.update({
            "ema20": ema20[i],
            "ema50": ema50[i],
            "ema20_prev": ema20[i - 1],
            "ema50_prev": ema50[i - 1],
            "ema50_price_side_pass": int(ema50_price_pass),
            "ema20_50_regime_pass": int(regime_pass),
            "ema20_50_prior_bar_pass": int(prior_regime_pass),
            "entry_next_open": entry,
            "sl_pair_extreme_15pt": stop,
            "tp_1r": target,
            "result": result,
            "bars_to_hit": bars_to_hit,
            "month": bar["timestamp"][:7],
        })
        out.append(event)

    if len({row["index"] for row in out}) != len(out):
        raise ValueError("duplicate signal bars found")
    return out


def chosen(filter_name: str, event: dict) -> bool:
    if filter_name == "baseline":
        return True
    if filter_name == "ema50_price_side":
        return bool(int(event["ema50_price_side_pass"]))
    if filter_name == "ema20_50_regime":
        return bool(int(event["ema20_50_regime_pass"]))
    if filter_name == "ema20_50_prior_bar":
        return bool(int(event["ema20_50_prior_bar_pass"]))
    raise ValueError(filter_name)


def metrics(events: list[dict]) -> dict:
    counts = defaultdict(int)
    for event in events:
        counts[event["result"]] += 1
    wins, losses = counts["TP"], counts["SL"]
    resolved = wins + losses
    lo, hi = wilson95(wins, resolved)
    curve = peak = max_dd = 0
    loss_streak = current_streak = 0
    for event in sorted(events, key=lambda row: int(row["index"])):
        if event["result"] not in ("TP", "SL"):
            continue
        if event["result"] == "TP":
            curve += 1
            current_streak = 0
        else:
            curve -= 1
            current_streak += 1
            loss_streak = max(loss_streak, current_streak)
        peak = max(peak, curve)
        max_dd = max(max_dd, peak - curve)
    return {
        "signals": len(events),
        "TP": wins,
        "SL": losses,
        "BOTH": counts["BOTH"],
        "UNRESOLVED": counts["UNRESOLVED"],
        "resolved_TP_or_SL": resolved,
        "win_rate_excluding_BOTH_unresolved": wins / resolved if resolved else None,
        "win_rate_wilson95_low": lo,
        "win_rate_wilson95_high": hi,
        "gross_profit_factor_TP_div_SL": wins / losses if losses else None,
        "gross_expectancy_R_per_resolved_signal": (wins - losses) / resolved if resolved else None,
        "sequential_max_drawdown_R_resolved_only": max_dd,
        "max_consecutive_SL_resolved_only": loss_streak,
    }


def filters_for_report(events: list[dict]) -> list[dict]:
    all_rows = []
    for name in FILTERS:
        picked = [event for event in events if chosen(name, event)]
        for pattern in PATTERNS:
            for side in SIDES:
                group = [
                    event for event in picked
                    if (pattern == "ALL" or event["pattern"] == pattern)
                    and (side == "ALL" or event["side"] == side)
                ]
                row = {"filter": name, "pattern": pattern, "side": side}
                row.update(metrics(group))
                all_rows.append(row)
    return all_rows


def monthly_for_report(events: list[dict]) -> list[dict]:
    rows = []
    months = sorted({event["month"] for event in events})
    for month in months:
        month_events = [event for event in events if event["month"] == month]
        for name in FILTERS:
            picked = [event for event in month_events if chosen(name, event)]
            for pattern in PATTERNS:
                for side in SIDES:
                    group = [
                        event for event in picked
                        if (pattern == "ALL" or event["pattern"] == pattern)
                        and (side == "ALL" or event["side"] == side)
                    ]
                    row = {"month": month, "filter": name, "pattern": pattern, "side": side}
                    row.update(metrics(group))
                    rows.append(row)
    return rows


def write_csv(path: Path, rows: list[dict]) -> None:
    if not rows:
        raise ValueError(f"refusing to write empty CSV: {path}")
    fields = list(rows[0])
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    bars = read_bars()
    raw_path = HERE / "core_fvg_events.csv"
    print(compile_and_replay(raw_path))
    if sha256(raw_path) != EXPECTED_EVENT_SHA256:
        raise ValueError("fresh core event CSV hash differs from the prior direct replay")
    with raw_path.open(newline="", encoding="utf-8") as stream:
        raw_events = list(csv.DictReader(stream))
    if len(raw_events) != 554:
        raise ValueError(f"expected 554 current-core FVG-only events; got {len(raw_events)}")
    events = annotate_events(bars, raw_events)

    comparison = filters_for_report(events)
    monthly = monthly_for_report(events)
    write_csv(HERE / "comparison.csv", comparison)
    write_csv(HERE / "monthly.csv", monthly)
    write_csv(HERE / "filtered_events.csv", events)

    source_files = [
        SOURCE / "EngulfImbalanceFlow.mq5",
        SOURCE / "EngulfImbalanceCore.mqh",
        SOURCE / "EngulfFlowCore.mqh",
        SOURCE / "FVGCore.mqh",
    ]
    source_hashes = {path.name: sha256(path) for path in source_files}
    if source_hashes != EXPECTED_SOURCE_HASHES:
        raise ValueError("indicator source hashes differ from the prior analysis")
    actual_start = dt.datetime.fromtimestamp(bars[0]["epoch"], dt.timezone.utc)
    actual_end = dt.datetime.fromtimestamp(bars[-1]["epoch"], dt.timezone.utc)
    signal_events_sorted = sorted(events, key=lambda row: int(row["index"]))
    resolved_by_filter = {}
    for name in FILTERS:
        resolved_by_filter[name] = metrics([e for e in events if chosen(name, e)])
    current_regime_set = {
        e["index"] for e in events if chosen("ema20_50_regime", e)
    }
    prior_regime_set = {
        e["index"] for e in events if chosen("ema20_50_prior_bar", e)
    }
    base_metrics = resolved_by_filter["baseline"]
    if (base_metrics["signals"], base_metrics["TP"], base_metrics["SL"], base_metrics["BOTH"]) != (554, 278, 274, 2):
        raise ValueError("baseline outcome counts differ from the validated prior run")
    summary = {
        "analysis": "Current EngulfImbalanceFlow 1.05 core, FVG-only imbalance, max gap 5",
        "symbol": "XAUUSD",
        "timeframe": "M5",
        "test_window_utc": {"start_inclusive": START.isoformat(), "end_exclusive": END.isoformat()},
        "observed_data_coverage_utc": {
            "first_bar_open": actual_start.isoformat(),
            "last_bar_open": actual_end.isoformat(),
            "signal_window_first_event": signal_events_sorted[0]["timestamp"] if events else None,
            "signal_window_last_event": signal_events_sorted[-1]["timestamp"] if events else None,
            "warmup_bars_before_window": sum(bar["epoch"] < int(START.timestamp()) for bar in bars),
            "unavailable_requested_tail": "No bars after 2026-09-25 20:55 UTC in the supplied data; the requested interval is therefore not complete to 2026-09-27.",
            "warmup": "EMA20 and EMA50 are each seeded with the first available close (2025-09-01 00:00 UTC) and advanced through every available close before each tested signal.",
        },
        "input_data": {
            "path_relative_to_repo": str(INPUT.relative_to(ROOT)),
            "bars": len(bars),
            "sha256": sha256(INPUT),
            "timezone": "UTC, inherited from the Dukascopy M5 report",
        },
        "indicator_source": {str(path.relative_to(ROOT)): sha256(path) for path in source_files},
        "legacy_metadata_mismatch": "The existing report summary.json labels itself 1.02 and combined FVG+displacement, inconsistent with this test request and current .mq5 source (1.05). This analysis independently replays current EngulfImbalanceCore/FVGCore with FVG-only flags and maxGap=5; no old trade outcomes are reused.",
        "replay_validation": {
            "fresh_direct_core_events": len(raw_events),
            "fresh_core_event_csv_sha256": sha256(raw_path),
            "prior_core_event_csv_sha256": EXPECTED_EVENT_SHA256,
            "raw_events_match_prior_replay_exactly": sha256(raw_path) == EXPECTED_EVENT_SHA256,
            "data_hash_matches_prior": sha256(INPUT) == EXPECTED_DATA_SHA256,
            "source_hashes_match_prior": source_hashes == EXPECTED_SOURCE_HASHES,
        },
        "signal_logic": {
            "confirmation": "Current EIFind from EngulfImbalanceCore.mqh, all loaded bars as lookback, maxGap=5; pattern A, B, and A+B recorded separately.",
            "imbalance": "FVGDetect only on each third candle; default minimum gap 0, point 0.001, middle-direction requirement false; displacement flags excluded.",
            "ema": {
                "EMA20": {"period": EMA_FAST_PERIOD, "alpha": ALPHA20},
                "EMA50": {"period": EMA_SLOW_PERIOD, "alpha": ALPHA50},
                "seed": "first available close for both",
                "filters": {
                    "ema50_price_side": "At the signal close: BUY only when Close[i]>EMA50[i], SELL only when Close[i]<EMA50[i]; equality rejects.",
                    "ema20_50_regime": "At the signal close: BUY only when EMA20[i]>EMA50[i], SELL only when EMA20[i]<EMA50[i]; equality rejects.",
                    "ema20_50_prior_bar": "Robustness check: use EMA20[i-1]>EMA50[i-1] for BUY, EMA20[i-1]<EMA50[i-1] for SELL; equality rejects.",
                },
                "all_values_causal": True,
            },
        },
        "regime_robustness": {
            "current_regime_signals": len(current_regime_set),
            "prior_bar_regime_signals": len(prior_regime_set),
            "same_selected_signal_indices": len(current_regime_set & prior_regime_set),
            "current_only_indices": len(current_regime_set - prior_regime_set),
            "prior_only_indices": len(prior_regime_set - current_regime_set),
        },
        "outcome_rules": {
            "entry": "next M5 bar open",
            "stop": f"BUY=min(low of signal candle and immediately previous candle)-{STOP_BUFFER_POINTS}*{POINT}; SELL=max(high of pair)+{STOP_BUFFER_POINTS}*{POINT}",
            "target": "1:1 risk/reward from next-bar entry",
            "scan": "From the next bar onward, use bar high/low touches until first target/stop touch or end of input.",
            "same_bar_both": "If both target and stop fall within the same bar range, record BOTH (ambiguous) and exclude from win rate/PF/expectancy/drawdown.",
            "unresolved": "If no level is touched before available data ends, record UNRESOLVED and exclude from win rate/PF/expectancy/drawdown.",
            "costs": "Spread, commission, financing, slippage, and gaps in execution are not modeled.",
            "overlap": "Signals are evaluated independently, so positions may overlap; the event-sequence drawdown is not a portfolio backtest.",
            "drawdown": "Chronological resolved TP=+1R / SL=-1R sequence; BOTH and UNRESOLVED are omitted.",
        },
        "filter_metrics": resolved_by_filter,
        "replay_command": "python3 tests/reports/engulf-imbalance-xauusd-m5-ema20-50/run_ema20_50_analysis.py",
        "outputs": ["core_fvg_events.csv", "filtered_events.csv", "comparison.csv", "monthly.csv"],
    }
    (HERE / "summary.json").write_text(
        json.dumps(summary, indent=2, allow_nan=False) + "\n", encoding="utf-8"
    )
    print(json.dumps({
        "events": len(events),
        "filter_totals": resolved_by_filter,
        "regime_robustness": summary["regime_robustness"],
        "outputs": str(HERE),
    }, indent=2))


if __name__ == "__main__":
    main()
