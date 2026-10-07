#!/usr/bin/env python3
"""Independent raw-M1 and execution audit for the M15/M1 WickHunt study."""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import gzip
import hashlib
import json
import math
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SOURCE = ROOT / "tests/reports/engulf-imbalance-xauusd-m1/xauusd_m1_bid_ask.csv.gz"
START = int(dt.datetime(2026, 6, 25, 21, 0, tzinfo=dt.timezone.utc).timestamp())
END = int(dt.datetime(2026, 9, 25, 21, 0, tzinfo=dt.timezone.utc).timestamp())
SPREAD = 0.36
EPS = 1e-8
WARMUP = 34


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def near(a: float | str, b: float | str) -> bool:
    try:
        return math.isclose(float(a), float(b), rel_tol=1e-10, abs_tol=EPS)
    except (TypeError, ValueError):
        return False


def read_raw(path: Path) -> list[dict]:
    rows = []
    last = None
    with gzip.open(path, "rt", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            t = int(row["epoch"])
            if last is not None and t <= last:
                raise AssertionError(f"source timestamps not increasing at {t}")
            bid = tuple(float(row[f"bid_{key}"]) for key in ("open", "high", "low", "close"))
            ask = tuple(float(row[f"ask_{key}"]) for key in ("open", "high", "low", "close"))
            for side, values in (("bid", bid), ("ask", ask)):
                o, h, low, close = values
                if low > min(o, close) or max(o, close) > h:
                    raise AssertionError(f"invalid {side} OHLC at {t}")
            rows.append({"time": t, "open": bid[0], "high": bid[1], "low": bid[2], "close": bid[3],
                         "ask_open": ask[0], "ask_high": ask[1], "ask_low": ask[2], "ask_close": ask[3]})
            last = t
    return rows


def aggregate_m15(rows: list[dict]) -> list[dict]:
    grouped = defaultdict(list)
    for row in rows:
        grouped[row["time"] // 900 * 900].append(row)
    bars = []
    for t in sorted(grouped):
        mins = grouped[t]
        bars.append({"time": t, "open": mins[0]["open"], "high": max(x["high"] for x in mins),
                     "low": min(x["low"] for x in mins), "close": mins[-1]["close"],
                     "count": len(mins),
                     "complete": len(mins) == 15 and [x["time"] for x in mins] == [t + i * 60 for i in range(15)]})
    return bars


class SwingStream:
    """Small independent transcription of SwingCore's EMA histogram swing recurrence."""
    def __init__(self) -> None:
        self.reset()

    def reset(self) -> None:
        self.count = 0
        self.fast = self.slow = self.signal = self.hist = 0.0
        self.prev_hist = 0.0
        self.prev_close = 0.0
        self.direction = 0
        self.extreme = 0.0
        self.extreme_time = 0

    def process(self, bar: dict) -> dict | None:
        close = bar["close"]
        if self.count == 0:
            self.fast = close
            self.slow = close
            self.signal = 0.0
        else:
            fast_alpha = 2.0 / (12 + 1.0)
            slow_alpha = 2.0 / (26 + 1.0)
            signal_alpha = 2.0 / (9 + 1.0)
            self.fast = fast_alpha * close + (1.0 - fast_alpha) * self.fast
            self.slow = slow_alpha * close + (1.0 - slow_alpha) * self.slow
            macd = self.fast - self.slow
            self.signal = signal_alpha * macd + (1.0 - signal_alpha) * self.signal
        self.prev_hist = self.hist
        self.hist = self.fast - self.slow - self.signal
        self.prev_close = close
        self.count += 1
        if self.count < WARMUP:
            return None
        if self.count == 1 or self.hist == 0 and self.prev_hist == 0:
            side = 0
        else:
            side = 1 if self.hist > self.prev_hist else -1
        if self.direction == 0:
            if side == 0:
                return None
            self.direction = side
            self.extreme = bar["high"] if side == 1 else bar["low"]
            self.extreme_time = bar["time"]
            return None
        if (self.direction == 1 and bar["high"] >= self.extreme) or (
                self.direction == -1 and bar["low"] <= self.extreme):
            self.extreme = bar["high"] if self.direction == 1 else bar["low"]
            self.extreme_time = bar["time"]
        if side == 0 or side == self.direction:
            return None
        event = {"type": self.direction, "pivot_time": self.extreme_time,
                 "price": self.extreme, "confirm_time": bar["time"]}
        self.direction = side
        self.extreme = bar["high"] if side == 1 else bar["low"]
        self.extreme_time = bar["time"]
        return event


class HigherStream:
    def __init__(self) -> None:
        self.reset()

    def reset(self) -> None:
        self.swing = SwingStream()
        self.levels: list[dict] = []
        self.trend = {"direction": 0, "ready": False, "break_time": 0, "origin_time": 0,
                      "origin_price": 0.0, "pivot_time": 0, "pivot_price": 0.0,
                      "confirm_time": 0, "sr": 0.0}
        self.bars: list[dict] = []

    def _cross(self, direction: int, before: float, after: float, level: float) -> bool:
        return before <= level and after > level if direction == 1 else before >= level and after < level

    def _start_trend(self, bar: dict, direction: int) -> bool:
        origin = next((level for level in reversed(self.levels)
                       if level["type"] == -direction and level["confirm_time"] < bar["time"]), None)
        if origin is None:
            return False
        for level in reversed(self.levels):
            if level["type"] != direction or level["confirm_time"] >= bar["time"]:
                continue
            if not self._cross(direction, self.swing.prev_close, bar["close"], level["price"]):
                continue
            self.trend = {"direction": direction, "ready": False, "break_time": bar["time"],
                          "origin_time": origin["pivot_time"], "origin_price": origin["price"],
                          "pivot_time": 0, "pivot_price": 0.0, "confirm_time": 0,
                          "sr": level["price"]}
            return True
        return False

    def process(self, bar: dict) -> None:
        if self.swing.count > 0:
            if not self._start_trend(bar, 1):
                self._start_trend(bar, -1)
        event = self.swing.process(bar)
        if event is not None:
            if event["type"] == self.trend["direction"] and event["pivot_time"] >= self.trend["break_time"]:
                self.trend["ready"] = True
                self.trend["pivot_time"] = event["pivot_time"]
                self.trend["pivot_price"] = event["price"]
                self.trend["confirm_time"] = event["confirm_time"]
            self.levels.append(event)
            self.levels = self.levels[-10:]
        self.bars.append(bar)


def body_holds(bar: dict, price: float) -> bool:
    return min(bar["open"], bar["close"]) <= price <= max(bar["open"], bar["close"])


def strong_confirmation(bar: dict, direction: int) -> bool:
    span = bar["high"] - bar["low"]
    if span <= 0:
        return False
    if direction == 1:
        return bar["close"] > bar["open"] and bar["high"] - bar["close"] <= span * .30
    return bar["close"] < bar["open"] and bar["close"] - bar["low"] <= span * .30


def fvg_anchor(bars: list[dict], tip: float, direction: int) -> int:
    for i in range(len(bars) - 1, -1, -1):
        third = bars[i]
        if third["low"] > tip or third["high"] < tip:
            continue
        if i < 2:
            return 0
        first, middle = bars[i - 2], bars[i - 1]
        if direction == 1 and third["low"] > first["high"]:
            zone_lower, zone_upper = first["high"], third["low"]
        elif direction == -1 and third["high"] < first["low"]:
            zone_lower, zone_upper = third["high"], first["low"]
        else:
            return 0
        valid_gap = middle["low"] <= zone_lower and middle["high"] >= zone_upper
        if valid_gap and body_holds(third, tip) and strong_confirmation(third, direction):
            return third["time"]
        return 0
    return 0


def verify_trade(event: dict, trade: dict, rr: float, m1: list[dict], index: int) -> tuple[int, dict]:
    direction = event["direction"]
    entry_bar = m1[index]
    entry_bid = entry_bar["open"]
    entry = entry_bid + SPREAD if direction == "BUY" else entry_bid
    stop = float(event["known_low"]) if direction == "BUY" else float(event["known_high"]) + SPREAD
    risk = entry - stop if direction == "BUY" else stop - entry
    if risk <= 0:
        expected = {"outcome": "INVALID_STOP", "risk": risk}
        return 1, expected
    target = entry + rr * risk if direction == "BUY" else entry - rr * risk
    expected = {"outcome": "OPEN", "exit_epoch": END, "exit_price": None,
                "r_multiple": None, "gaps": 0, "bars_held": 0}
    prior = None
    last = None
    for k in range(index, len(m1)):
        bar = m1[k]
        if bar["time"] >= END:
            break
        if prior is not None and bar["time"] - prior != 60:
            expected["gaps"] += 1
        prior = bar["time"]
        last = bar
        expected["bars_held"] = k - index + 1
        quote_open = bar["open"] if direction == "BUY" else bar["open"] + SPREAD
        stop_gap = quote_open <= stop if direction == "BUY" else quote_open >= stop
        tp_gap = quote_open >= target if direction == "BUY" else quote_open <= target
        if stop_gap:
            expected.update({"outcome": "SL", "exit_epoch": bar["time"], "exit_price": quote_open,
                             "r_multiple": (quote_open - entry) / risk if direction == "BUY" else (entry - quote_open) / risk,
                             "gap_stop": quote_open < stop if direction == "BUY" else quote_open > stop})
            break
        if tp_gap:
            expected.update({"outcome": "TP", "exit_epoch": bar["time"], "exit_price": target,
                             "r_multiple": rr, "gap_target": quote_open > target if direction == "BUY" else quote_open < target})
            break
        if direction == "BUY":
            stop_hit, tp_hit = bar["low"] <= stop, bar["high"] >= target
        else:
            stop_hit, tp_hit = bar["high"] + SPREAD >= stop, bar["low"] + SPREAD <= target
        if stop_hit and tp_hit:
            expected.update({"outcome": "BOTH", "exit_epoch": bar["time"] + 59,
                             "exit_price": None, "r_multiple": None})
            break
        if stop_hit:
            expected.update({"outcome": "SL", "exit_epoch": bar["time"] + 59,
                             "exit_price": stop, "r_multiple": -1.0})
            break
        if tp_hit:
            expected.update({"outcome": "TP", "exit_epoch": bar["time"] + 59,
                             "exit_price": target, "r_multiple": rr})
            break
    if expected["outcome"] == "OPEN" and last is not None:
        expected["exit_price"] = last["close"] if direction == "BUY" else last["close"] + SPREAD
        expected["r_multiple"] = (expected["exit_price"] - entry) / risk if direction == "BUY" else (entry - expected["exit_price"]) / risk
    checks = 0
    def require(condition: bool, label: str) -> None:
        nonlocal checks
        if not condition:
            raise AssertionError(f"{event['event_id']} RR {rr:g}: {label}")
        checks += 1
    require(trade["event_id"] == event["event_id"], "trade/event ID mismatch")
    require(trade["outcome"] == expected["outcome"], "first-hit outcome mismatch")
    require(near(trade["entry_price"], entry), "entry side/price mismatch")
    require(near(trade["stop_price"], stop), "known-at-signal stop mismatch")
    require(near(trade["initial_risk"], risk), "initial risk mismatch")
    require(near(trade["target_price"], target), "TP RR mismatch")
    require(near(trade["entry_spread"], SPREAD), "fixed spread mismatch")
    require(int(trade["source_gap_count"]) == expected["gaps"], "source gap exposure mismatch")
    require(int(trade["bars_held"]) == expected["bars_held"], "bars-held/first-exit mismatch")
    require(int(trade["exit_epoch"]) == expected["exit_epoch"], "exit minute mismatch")
    if expected["exit_price"] is not None:
        require(near(trade["exit_price"], expected["exit_price"]), "executable exit fill mismatch")
    if expected["r_multiple"] is not None and trade["outcome"] != "OPEN":
        require(near(trade["r_multiple"], expected["r_multiple"]), "realized R mismatch")
    return checks, expected


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=SOURCE)
    parser.add_argument("--output", type=Path, default=HERE)
    args = parser.parse_args()
    source = args.input.resolve()
    output = args.output.resolve()
    summary_path = output / "summary.json"
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    if digest(source) != summary["data"]["source_sha256"]:
        raise AssertionError("source dataset SHA-256 differs from replay summary")
    raw = read_raw(source)
    m15 = aggregate_m15(raw)
    m1_by_time = {row["time"]: row for row in raw}
    m1_by_bucket = defaultdict(list)
    for row in raw:
        m1_by_bucket[row["time"] // 900 * 900].append(row)
    m15_by_time = {bar["time"]: bar for bar in m15}
    events = list(csv.DictReader((output / "events.csv").open(newline="", encoding="utf-8")))
    if not events:
        raise AssertionError("no events exported")
    checks = 1

    # Reconstruct higher MACD swings, rolling SR, and structure only from complete M15 bins.
    higher = HigherStream()
    high_history: list[dict] = []
    event_by_setup: dict[int, list[dict]] = defaultdict(list)
    for event in events:
        event_by_setup[int(event["setup_epoch"])].append(event)
    setup_epochs = sorted(event_by_setup)
    setup_models = {}
    next_setup = 0
    for bar in m15:
        while next_setup < len(setup_epochs) and setup_epochs[next_setup] <= bar["time"]:
            setup = setup_epochs[next_setup]
            setup_models[setup] = (list(higher.levels), dict(higher.trend), list(high_history))
            next_setup += 1
        if bar["complete"]:
            higher.process(bar)
            high_history.append(bar)
        else:
            higher.reset()
            high_history = []
    for setup in setup_epochs[next_setup:]:
        setup_models[setup] = (list(higher.levels), dict(higher.trend), list(high_history))

    # Replay M1 swing levels to the breakout bar and check the production WS break selection.
    lower = SwingStream()
    lower_levels: list[dict] = []
    events_by_break: dict[int, list[dict]] = defaultdict(list)
    for event in events:
        events_by_break[int(event["breakout_epoch"])].append(event)
    for bar in raw:
        for event in events_by_break.get(bar["time"], []):
            direction = 1 if event["direction"] == "BUY" else -1
            previous = lower.prev_close
            selected = None
            for level in reversed(lower_levels):
                if level["confirm_time"] >= bar["time"]:
                    continue
                crosses = previous <= level["price"] and bar["close"] > level["price"] if direction == 1 else previous >= level["price"] and bar["close"] < level["price"]
                if crosses:
                    selected = level
                    break
            assert selected is not None, f"{event['event_id']}: no causal M1 swing crossed"
            assert selected["pivot_time"] == int(event["pivot_epoch"]), f"{event['event_id']}: pivot selection differs"
            assert selected["confirm_time"] == int(event["confirm_epoch"]), f"{event['event_id']}: confirm selection differs"
            assert selected["type"] == (1 if event["sr_type"] == "Swing H" else -1), f"{event['event_id']}: SR type differs"
            assert near(selected["price"], event["sr_price"]), f"{event['event_id']}: SR price differs"
            checks += 5
        level_event = lower.process(bar)
        if level_event is not None:
            lower_levels.append(level_event)
            lower_levels = lower_levels[-10:]

    # Validate each retained raw event against reconstructed M15 state, reclaim snapshots,
    # first-collision FVG, strict M1 close order, and current M1 price data.
    for event in events:
        eid = event["event_id"]
        event_t = int(event["event_epoch"])
        setup = int(event["setup_epoch"])
        reclaim_t = int(event["reclaim_epoch"])
        break_t = int(event["breakout_epoch"])
        close_t = int(event["break_close_epoch"])
        direction = 1 if event["direction"] == "BUY" else -1
        assert setup == event_t // 900 * 900 and event_t < setup + 900
        assert reclaim_t < close_t <= event_t and break_t >= setup and close_t <= setup + 900
        assert close_t == break_t + 60
        event_bar = m1_by_time[event_t]
        assert near(event["signal_bid"], event_bar["open"])
        context_m15 = m15_by_time[setup]
        assert near(event["m15_open"], context_m15["open"])
        assert int(event["current_m15_m1_count"]) == context_m15["count"]
        assert int(event["current_m15_complete"]) == int(context_m15["complete"])
        assert context_m15["time"] == setup and context_m15["count"] >= 1
        bucket_minutes = m1_by_bucket[setup]
        assert bucket_minutes[0]["time"] == setup
        checks += 8

        higher_levels, trend, history = setup_models[setup]
        # Use the valid segment preceding this setup, excluding current/forming M15.
        history_before = [bar for bar in history if bar["time"] < setup]
        if len(history_before) < 35:
            raise AssertionError(f"{eid}: higher context shorter than production replay warmup")
        prior1, prior2 = history_before[-1], history_before[-2]
        for column, value in (("prior_low_1", prior1["low"]), ("prior_high_1", prior1["high"]),
                              ("prior_low_2", prior2["low"]), ("prior_high_2", prior2["high"])):
            assert near(event[column], value), f"{eid}: {column} reference mismatch"
            checks += 1

        # Reconstruct the cumulative current-M15 H/L and sampled quote at reclaim.
        snap_kind = event["reclaim_sample_kind"]
        snap_minute_time = reclaim_t if snap_kind == "m1_open" else reclaim_t - 59
        snap_bar = m1_by_time[snap_minute_time]
        assert snap_minute_time // 900 * 900 == setup
        earlier = [r for r in bucket_minutes if r["time"] < snap_minute_time]
        if snap_kind == "m1_open":
            sample_high = max([context_m15["open"], *(r["high"] for r in earlier), snap_bar["open"]])
            sample_low = min([context_m15["open"], *(r["low"] for r in earlier), snap_bar["open"]])
            sample_price = snap_bar["open"]
        elif snap_kind == "m1_close59":
            sample_high = max([context_m15["open"], *(r["high"] for r in earlier), snap_bar["high"]])
            sample_low = min([context_m15["open"], *(r["low"] for r in earlier), snap_bar["low"]])
            sample_price = snap_bar["close"]
            assert reclaim_t == snap_minute_time + 59
        else:
            raise AssertionError(f"{eid}: unknown reclaim sample kind")
        assert near(event["reclaim_known_high"], sample_high)
        assert near(event["reclaim_known_low"], sample_low)
        assert near(event["reclaim_bid"], sample_price)
        tip = sample_low if direction == 1 else sample_high
        assert near(event["reclaim_tip"], tip)
        event_prior = [r for r in bucket_minutes if r["time"] < event_t]
        event_known_high = max([context_m15["open"], *(r["high"] for r in event_prior), event_bar["open"]])
        event_known_low = min([context_m15["open"], *(r["low"] for r in event_prior), event_bar["open"]])
        assert near(event["known_low"], event_known_low)
        assert near(event["known_high"], event_known_high)
        assert sample_price >= context_m15["open"] if direction == 1 else sample_price <= context_m15["open"]
        assert sample_low < context_m15["open"] if direction == 1 else sample_high > context_m15["open"]
        checks += 9

        pattern = int(event["pattern"])
        assert pattern in (1, 2, 3)
        breakout_ok = False
        fvg_time = 0
        touch_price = 0.0
        if pattern & 1:
            sweep_one = sample_low < prior1["low"] if direction == 1 else sample_high > prior1["high"]
            assert sweep_one, f"{eid}: breakout hunt edge not swept"
            for touch_bar in reversed(history_before[-5:]):
                for level in reversed(higher_levels):
                    if level["confirm_time"] < touch_bar["time"] and touch_bar["low"] <= level["price"] <= touch_bar["high"]:
                        touch_price = level["price"]
                        break
                if touch_price:
                    break
            assert touch_price, f"{eid}: no eligible higher-M15 S/R touch"
            fvg_time = fvg_anchor(history_before, tip, direction)
            assert fvg_time and int(event["anchor_epoch"]) == fvg_time, f"{eid}: first-collision FVG anchor mismatch"
            breakout_ok = True
        else:
            assert int(event["anchor_epoch"]) == 0, f"{eid}: pullback-only event unexpectedly has FVG anchor"
        pullback_ok = False
        if pattern & 2:
            assert trend["ready"] and trend["direction"] == direction and trend["confirm_time"] < setup
            assert sample_low < prior1["low"] and sample_low < prior2["low"] if direction == 1 else sample_high > prior1["high"] and sample_high > prior2["high"]
            assert sample_low < trend["pivot_price"] if direction == 1 else sample_high > trend["pivot_price"]
            assert int(event["trend_break_epoch"]) == trend["break_time"]
            assert int(event["trend_origin_epoch"]) == trend["origin_time"]
            assert int(event["trend_pivot_epoch"]) == trend["pivot_time"]
            assert int(event["trend_confirm_epoch"]) == trend["confirm_time"]
            assert near(event["trend_origin_price"], trend["origin_price"])
            assert near(event["trend_pivot_price"], trend["pivot_price"])
            assert near(event["trend_sr"], trend["sr"])
            pullback_ok = True
        expected_pattern = (1 if breakout_ok else 0) + (2 if pullback_ok else 0)
        assert pattern == expected_pattern, f"{eid}: frozen pattern tag mismatch"
        expected_context_sr = touch_price if breakout_ok else trend["sr"]
        assert near(event["context_sr"], expected_context_sr)
        expected_sweeps = int(sample_low < prior1["low"] if direction == 1 else sample_high > prior1["high"]) + int(
            sample_low < prior2["low"] if direction == 1 else sample_high > prior2["high"])
        assert int(event["swept_prior_m15_count"]) == expected_sweeps
        checks += 13

    # Complete-current-M15 quality filter is auditable from the unmodified source aggregation.
    assert sum(int(event["current_m15_complete"]) for event in events) == summary["replay"]["events_after_current_m15_completeness_filter"]
    checks += 1

    # Independent executable-side, first-hit audit for all three RR output tables.
    by_event = {event["event_id"]: event for event in events}
    indices = {row["time"]: i for i, row in enumerate(raw)}
    rr_stats = {}
    trade_checks = 0
    total_trades = 0
    for rr, folder in ((1.0, "rr-1"), (1.5, "rr-1_5"), (2.0, "rr-2")):
        path = output / folder / "trades.csv"
        trades = list(csv.DictReader(path.open(newline="", encoding="utf-8")))
        if len(trades) != len(events):
            raise AssertionError(f"{folder}: trade row count differs from event count")
        outcomes = defaultdict(int)
        resolved_r = []
        for trade in trades:
            event = by_event[trade["event_id"]]
            count, expected = verify_trade(event, trade, rr, raw, indices[int(event["event_epoch"])])
            trade_checks += count
            total_trades += 1
            outcomes[trade["outcome"]] += 1
            if trade["outcome"] in ("TP", "SL"):
                resolved_r.append(float(trade["r_multiple"]))
        rr_stats[folder] = {"trades": len(trades), "outcomes": dict(sorted(outcomes.items())),
                            "resolved_r_rows": len(resolved_r)}

    result = {
        "source_sha256": digest(source), "events_audited": len(events),
        "event_invariant_checks_passed": checks, "trade_rows_audited": total_trades,
        "trade_arithmetic_and_first_hit_checks_passed": trade_checks,
        "rr_results": rr_stats,
        "audit_method": "Independent Python recomputation from Dukascopy raw M1 bid/ask OHLC; independently replays EMA histogram swings and M15 trend/touch/FVG first collision, M1 swing cross, reclaim snapshots, executable-side trade levels, gap opens, and first-hit outcomes.",
    }
    (output / "independent-audit.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
