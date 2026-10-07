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


def scalp_snap(price: float) -> float:
    # ScalpSnap: MathRound(price / tick) followed by NormalizeDouble. Positive
    # XAU prices use floor(x + .5); retaining IEEE arithmetic mirrors the EA.
    return round(math.floor(price / .01 + .5) * .01, 2)


def outward_stop(direction: str, wick: float) -> float:
    ticks = wick / .01
    rounded = math.floor(ticks + 1e-8) if direction == "BUY" else math.ceil(ticks - 1e-8)
    return round(rounded * .01, 2)


def broker_levels(direction: str, entry: float, wick: float, rr: float) -> dict:
    sign = 1.0 if direction == "BUY" else -1.0
    strategy_sl = outward_stop(direction, wick)
    strategy_tp = scalp_snap(entry + sign * rr * abs(entry - strategy_sl))
    strategy_geometry = (strategy_sl < entry < strategy_tp) if direction == "BUY" else (strategy_tp < entry < strategy_sl)
    shift = 0.0 if direction == "BUY" else SPREAD
    broker_sl = scalp_snap(strategy_sl + shift)
    broker_tp = scalp_snap(strategy_tp + shift)
    broker_geometry = (broker_sl < entry < broker_tp) if direction == "BUY" else (broker_tp < entry < broker_sl)
    risk = entry - broker_sl if direction == "BUY" else broker_sl - entry
    reward = broker_tp - entry if direction == "BUY" else entry - broker_tp
    return {"strategy_sl": strategy_sl, "strategy_tp": strategy_tp, "broker_sl": broker_sl,
            "broker_tp": broker_tp, "risk": risk, "reward": reward,
            "target_r": reward / risk if risk > 0 else 0.0,
            "strategy_geometry": strategy_geometry, "broker_geometry": broker_geometry,
            "valid": strategy_geometry and broker_geometry and risk > 0 and reward > 0}


def verify_trade_v103(event: dict, trade: dict, rr: float, m1: list[dict], indices: dict[int, int]) -> tuple[int, dict]:
    direction = event["direction"]
    kind = event["signal_sample_kind"]
    minute = int(event["signal_minute_epoch"])
    event_time = int(event["event_epoch"])
    if kind == "m1_open":
        assert event_time == minute
        entry_index = indices[minute]
        no_entry_reason = ""
    elif kind == "m1_close59":
        assert event_time == minute + 59
        next_index = indices[minute] + 1
        if next_index >= len(m1) or m1[next_index]["time"] >= END:
            entry_index = None
            no_entry_reason = "no_immediate_entry_open_before_study_end"
        elif m1[next_index]["time"] != minute + 60:
            entry_index = None
            no_entry_reason = "missing_expected_entry_open"
        else:
            entry_index = next_index
            no_entry_reason = ""
    else:
        raise AssertionError(f"{event['event_id']}: unknown sample kind {kind}")
    checks = 0
    def require(condition: bool, label: str) -> None:
        nonlocal checks
        if not condition:
            raise AssertionError(f"{event['event_id']} RR {rr:g}: {label}")
        checks += 1
    require(trade["event_id"] == event["event_id"], "trade/event ID mismatch")
    require(trade["signal_sample_kind"] == kind, "signal sample kind mismatch")
    if entry_index is None:
        require(trade["outcome"] == "NO_ENTRY", "missing next open before study end must be NO_ENTRY")
        require(not trade["entry_epoch"], "NO_ENTRY has entry timestamp")
        require(trade["no_entry_reason"] == no_entry_reason, "NO_ENTRY reason differs from immediate-open rule")
        require(int(trade["bars_held"]) == 0, "NO_ENTRY has held bars")
        return checks, {"outcome": "NO_ENTRY", "entry_index": None}

    entry_bar = m1[entry_index]
    entry_bid = entry_bar["open"]
    entry = entry_bid + SPREAD if direction == "BUY" else entry_bid
    wick = float(event["known_low"]) if direction == "BUY" else float(event["known_high"])
    levels = broker_levels(direction, entry, wick, rr)
    entry_kind = "same_m1_open" if kind == "m1_open" else "next_observed_m1_open_after_close59"
    expected_delay = entry_bar["time"] - event_time
    expected_gap = max(0, entry_bar["time"] - (minute if kind == "m1_open" else minute + 60))
    require(int(trade["entry_epoch"]) == entry_bar["time"], "entry did not use expected observed M1 open")
    require(near(trade["entry_bid"], entry_bid), "entry bid mismatch")
    require(near(trade["entry_price"], entry), "executable entry-side mapping mismatch")
    require(trade["entry_sample_kind"] == entry_kind, "entry timing type mismatch")
    require(int(trade["entry_delay_seconds"]) == expected_delay, "entry delay mismatch")
    require(int(trade["entry_source_gap_seconds"]) == expected_gap, "entry source-gap delay mismatch")
    require(int(trade["entry_m15_boundary_cross"]) == int(entry_bar["time"] // 900 != int(event["setup_epoch"]) // 900), "M15-boundary entry flag mismatch")
    require(near(trade["entry_spread"], SPREAD), "fixed spread mismatch")
    require(not trade["no_entry_reason"], "entry/rejection row unexpectedly has NO_ENTRY reason")
    require(near(trade["strategy_sl"], levels["strategy_sl"]), "outward-rounded strategy stop mismatch")
    require(near(trade["strategy_tp"], levels["strategy_tp"]), "strategy TP from strategy SL mismatch")
    require(near(trade["stop_price"], levels["broker_sl"]), "broker SL compensation mismatch")
    require(near(trade["target_price"], levels["broker_tp"]), "broker TP compensation mismatch")
    require(near(trade["initial_risk"], levels["risk"]), "executable entry-to-stop risk mismatch")
    require(near(trade["target_r_multiple"], levels["target_r"]), "planned broker TP R mismatch")

    if not levels["valid"]:
        require(trade["outcome"] == "INVALID_STOP", "invalid strategy/broker geometry must be rejected")
        require(bool(trade["invalid_reason"]), "invalid geometry reason missing")
        require(int(trade["bars_held"]) == 0, "invalid trade has held bars")
        return checks, {"outcome": "INVALID_STOP", "entry_index": entry_index, "levels": levels}

    expected = {"outcome": "OPEN", "exit_epoch": END, "exit_price": None,
                "r_multiple": None, "mark_r": None, "gaps": 0, "bars_held": 0,
                "gap_stop": False, "gap_target": False}
    previous = None
    last = None
    for i in range(entry_index, len(m1)):
        bar = m1[i]
        if bar["time"] >= END:
            break
        if previous is not None and bar["time"] - previous != 60:
            expected["gaps"] += 1
        previous = bar["time"]
        last = bar
        expected["bars_held"] = i - entry_index + 1
        qopen = bar["open"] if direction == "BUY" else bar["open"] + SPREAD
        stop_at_open = qopen <= levels["broker_sl"] if direction == "BUY" else qopen >= levels["broker_sl"]
        tp_at_open = qopen >= levels["broker_tp"] if direction == "BUY" else qopen <= levels["broker_tp"]
        if stop_at_open:
            r = ((qopen - entry) / levels["risk"] if direction == "BUY"
                 else (entry - qopen) / levels["risk"])
            expected.update({"outcome": "SL", "exit_epoch": bar["time"], "exit_price": qopen,
                             "r_multiple": r,
                             "gap_stop": qopen < levels["broker_sl"] if direction == "BUY" else qopen > levels["broker_sl"]})
            break
        if tp_at_open:
            expected.update({"outcome": "TP", "exit_epoch": bar["time"],
                             "exit_price": levels["broker_tp"], "r_multiple": levels["target_r"],
                             "gap_target": qopen > levels["broker_tp"] if direction == "BUY" else qopen < levels["broker_tp"]})
            break
        if direction == "BUY":
            stop_hit = bar["low"] <= levels["broker_sl"]
            tp_hit = bar["high"] >= levels["broker_tp"]
        else:
            stop_hit = bar["high"] + SPREAD >= levels["broker_sl"]
            tp_hit = bar["low"] + SPREAD <= levels["broker_tp"]
        if stop_hit and tp_hit:
            expected.update({"outcome": "BOTH", "exit_epoch": bar["time"] + 59})
            break
        if stop_hit:
            expected.update({"outcome": "SL", "exit_epoch": bar["time"] + 59,
                             "exit_price": levels["broker_sl"], "r_multiple": -1.0})
            break
        if tp_hit:
            expected.update({"outcome": "TP", "exit_epoch": bar["time"] + 59,
                             "exit_price": levels["broker_tp"], "r_multiple": levels["target_r"]})
            break
    if expected["outcome"] == "OPEN" and last is not None:
        close = last["close"] if direction == "BUY" else last["close"] + SPREAD
        expected["exit_price"] = close
        expected["mark_r"] = ((close - entry) / levels["risk"] if direction == "BUY"
                               else (entry - close) / levels["risk"])
    require(trade["outcome"] == expected["outcome"], "first-hit outcome mismatch")
    require(int(trade["source_gap_count"]) == expected["gaps"], "source gap exposure mismatch")
    require(int(trade["bars_held"]) == expected["bars_held"], "bars held mismatch")
    require(int(trade["exit_epoch"]) == expected["exit_epoch"], "exit time mismatch")
    require(int(trade["gap_through_stop"]) == int(expected["gap_stop"]), "SL gap fill mismatch")
    require(int(trade["gap_through_target"]) == int(expected["gap_target"]), "TP gap fill mismatch")
    if expected["exit_price"] is not None:
        require(near(trade["exit_price"], expected["exit_price"]), "exit fill mismatch")
    if expected["r_multiple"] is not None:
        require(near(trade["r_multiple"], expected["r_multiple"]), "realized R mismatch")
    if expected["mark_r"] is not None:
        require(near(trade["mark_to_market_r"], expected["mark_r"]), "open trade mark R mismatch")
    return checks, {**expected, "entry_index": entry_index, "levels": levels}


def ea_adapter_fixtures() -> dict:
    """Independent edge fixtures for strategy rounding and broker spread shifts."""
    checks = 0
    buy = broker_levels("BUY", 100.36, 99.001, 1.5)
    assert (buy["strategy_sl"], buy["strategy_tp"], buy["broker_sl"], buy["broker_tp"]) == (99.0, 102.4, 99.0, 102.4)
    checks += 4
    sell = broker_levels("SELL", 100.0, 101.001, 1.5)
    # Binary floating arithmetic is intentional: actual ScalpCore MathRound
    # resolves the computed 98.484999999999985 to 98.48 (confirmed by C++ shim).
    assert (sell["strategy_sl"], sell["strategy_tp"], sell["broker_sl"], sell["broker_tp"]) == (101.01, 98.48, 101.37, 98.84)
    checks += 4
    wrong_side = broker_levels("SELL", 100.0, 99.80, 1.0)
    assert not wrong_side["strategy_geometry"] and not wrong_side["valid"]
    assert wrong_side["broker_sl"] > 100.0
    checks += 3
    return {"checks_passed": checks, "buy_off_grid": buy, "sell_off_grid": sell,
            "sell_wrong_side_rejected": {k: wrong_side[k] for k in ("strategy_sl", "strategy_tp", "broker_sl", "broker_tp", "strategy_geometry", "broker_geometry", "valid")}}


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
    raw_index_by_time = {row["time"]: i for i, row in enumerate(raw)}
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
            assert near(bar["close"], event["break_close"]), f"{event['event_id']}: breakout close differs from raw M1"
            hold_t = int(event["hold_bar_epoch"])
            hold_close_t = int(event["hold_close_epoch"])
            assert hold_t == bar["time"] + 60, f"{event['event_id']}: hold is not exactly the successor bar"
            assert hold_close_t == hold_t + 60, f"{event['event_id']}: hold close time mismatch"
            hold = m1_by_time.get(hold_t)
            assert hold is not None, f"{event['event_id']}: missing immediate successor hold bar"
            assert near(hold["close"], event["hold_close"]), f"{event['event_id']}: hold close value mismatch"
            assert (hold["close"] > selected["price"] if direction == 1 else hold["close"] < selected["price"]), \
                f"{event['event_id']}: immediate successor did not strictly hold the frozen SR side"
            reclaim_t = int(event["reclaim_epoch"])
            break_close_t = int(event["break_close_epoch"])
            assert break_close_t > reclaim_t, f"{event['event_id']}: breakout close is not strictly after reclaim"
            assert int(event["retest_deadline_epoch"]) == hold_close_t + 8 * 60
            sample_time = int(event["event_epoch"])
            assert hold_close_t <= sample_time < int(event["retest_deadline_epoch"]), \
                f"{event['event_id']}: retest is outside the 8-bar window"
            retest_age = 1 + (sample_time - hold_close_t) // 60
            assert int(event["retest_bar"]) == retest_age and 1 <= retest_age <= 8, \
                f"{event['event_id']}: retest bar age mismatch"
            sample_minute_t = int(event["signal_minute_epoch"])
            sample_minute = m1_by_time[sample_minute_t]
            sample_price = sample_minute["open"] if event["signal_sample_kind"] == "m1_open" else sample_minute["close"]
            assert (sample_price <= selected["price"] if direction == 1 else sample_price >= selected["price"]), \
                f"{event['event_id']}: sampled retest quote does not touch the frozen SR"
            # Every earlier eligible open/close:59 quote after the hold close
            # must have stayed away; otherwise production would already latch.
            first_index = raw_index_by_time.get(hold_close_t)
            last_index = raw_index_by_time[sample_minute_t]
            assert first_index is not None and last_index >= first_index, \
                f"{event['event_id']}: retest observation window is missing its first lower bar"
            for candidate in raw[first_index:last_index + 1]:
                if candidate["time"] // 900 != int(event["setup_epoch"]) // 900:
                    continue
                open_time = candidate["time"]
                close_time = candidate["time"] + 59
                for candidate_time, quote in ((open_time, candidate["open"]), (close_time, candidate["close"])):
                    if candidate_time < hold_close_t or candidate_time >= sample_time:
                        continue
                    if candidate_time // 900 != int(event["setup_epoch"]) // 900:
                        continue
                    assert not (quote <= selected["price"] if direction == 1 else quote >= selected["price"]), \
                        f"{event['event_id']}: an earlier sampled quote had already retested SR"
                    checks += 1
            checks += 14
        level_event = lower.process(bar)
        if level_event is not None:
            lower_levels.append(level_event)
            lower_levels = lower_levels[-10:]

    # Validate each retained raw event against reconstructed M15 state, reclaim snapshots,
    # first-collision FVG, strict M1 close order, and current M1 price data.
    for event in events:
        eid = event["event_id"]
        event_t = int(event["event_epoch"])
        sample_minute_t = int(event["signal_minute_epoch"])
        sample_kind = event["signal_sample_kind"]
        setup = int(event["setup_epoch"])
        reclaim_t = int(event["reclaim_epoch"])
        break_t = int(event["breakout_epoch"])
        close_t = int(event["break_close_epoch"])
        direction = 1 if event["direction"] == "BUY" else -1
        assert setup == event_t // 900 * 900 and event_t < setup + 900
        assert reclaim_t < close_t <= event_t and break_t >= setup and close_t <= setup + 900
        assert close_t == break_t + 60
        event_bar = m1_by_time[sample_minute_t]
        if sample_kind == "m1_open":
            assert event_t == sample_minute_t
            signal_price = event_bar["open"]
        elif sample_kind == "m1_close59":
            assert event_t == sample_minute_t + 59
            signal_price = event_bar["close"]
        else:
            raise AssertionError(f"{eid}: unknown signal sample kind {sample_kind}")
        assert near(event["signal_bid"], signal_price)
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
        event_prior = [r for r in bucket_minutes if r["time"] < sample_minute_t]
        if sample_kind == "m1_open":
            event_known_high = max([context_m15["open"], *(r["high"] for r in event_prior), event_bar["open"]])
            event_known_low = min([context_m15["open"], *(r["low"] for r in event_prior), event_bar["open"]])
        else:
            event_known_high = max([context_m15["open"], *(r["high"] for r in event_prior), event_bar["high"]])
            event_known_low = min([context_m15["open"], *(r["low"] for r in event_prior), event_bar["low"]])
        assert near(event["known_low"], event_known_low)
        assert near(event["known_high"], event_known_high)
        assert sample_price >= context_m15["open"] if direction == 1 else sample_price <= context_m15["open"]
        assert sample_low < context_m15["open"] if direction == 1 else sample_high > context_m15["open"]
        checks += 9

        pattern = int(event["pattern"])
        assert pattern in (1, 2, 3)
        base_ok = sample_low < prior1["low"] if direction == 1 else sample_high > prior1["high"]
        touch_price = 0.0
        touch_time = touch_pivot = touch_confirm = 0
        if len(history_before) >= 5:
            for touch_bar in reversed(history_before[-5:]):
                for level in reversed(higher_levels):
                    if (level["type"] == direction and level["confirm_time"] < touch_bar["time"] and
                            touch_bar["low"] <= level["price"] <= touch_bar["high"]):
                        touch_price = level["price"]
                        touch_time = touch_bar["time"]
                        touch_pivot = level["pivot_time"]
                        touch_confirm = level["confirm_time"]
                        break
                if touch_price:
                    break
        fvg_time = fvg_anchor(history_before, tip, direction) if base_ok and touch_price else 0
        breakout_ok = bool(base_ok and touch_price and fvg_time)
        assert bool(pattern & 1) == breakout_ok, f"{eid}: breakout bit does not match independent candidate tests"
        if breakout_ok:
            assert int(event["anchor_epoch"]) == fvg_time, f"{eid}: first-collision FVG anchor mismatch"
        else:
            assert int(event["anchor_epoch"]) == 0, f"{eid}: pullback-only event unexpectedly has FVG anchor"
        trend_eligible = (trend["ready"] and trend["direction"] == direction and trend["confirm_time"] < setup)
        pullback_extreme_ok = (sample_low < prior1["low"] and sample_low < prior2["low"] and
                               sample_low < trend["pivot_price"] if direction == 1 else
                               sample_high > prior1["high"] and sample_high > prior2["high"] and
                               sample_high > trend["pivot_price"])
        pullback_ok = bool(trend_eligible and pullback_extreme_ok)
        assert bool(pattern & 2) == pullback_ok, f"{eid}: pullback bit does not match independent trend/extreme tests"
        if pullback_ok:
            assert int(event["trend_break_epoch"]) == trend["break_time"]
            assert int(event["trend_origin_epoch"]) == trend["origin_time"]
            assert int(event["trend_pivot_epoch"]) == trend["pivot_time"]
            assert int(event["trend_confirm_epoch"]) == trend["confirm_time"]
            assert near(event["trend_origin_price"], trend["origin_price"])
            assert near(event["trend_pivot_price"], trend["pivot_price"])
            assert near(event["trend_sr"], trend["sr"])
        else:
            assert int(event["trend_break_epoch"]) == 0
            assert int(event["trend_origin_epoch"]) == 0
            assert int(event["trend_pivot_epoch"]) == 0
            assert int(event["trend_confirm_epoch"]) == 0
        expected_pattern = (1 if breakout_ok else 0) + (2 if pullback_ok else 0)
        assert pattern == expected_pattern, f"{eid}: frozen pattern tag mismatch"
        expected_context_sr = touch_price if breakout_ok else trend["sr"]
        assert near(event["context_sr"], expected_context_sr)
        if breakout_ok:
            assert int(event["context_sr_type"]) == direction
            assert int(event["context_touch_epoch"]) == touch_time
            assert int(event["context_sr_pivot_epoch"]) == touch_pivot
            assert int(event["context_sr_confirm_epoch"]) == touch_confirm
        else:
            assert int(event["context_sr_type"]) == 0
            assert int(event["context_touch_epoch"]) == 0
            assert int(event["context_sr_pivot_epoch"]) == 0
            assert int(event["context_sr_confirm_epoch"]) == 0
        expected_sweeps = int(sample_low < prior1["low"] if direction == 1 else sample_high > prior1["high"]) + int(
            sample_low < prior2["low"] if direction == 1 else sample_high > prior2["high"])
        assert int(event["swept_prior_m15_count"]) == expected_sweeps
        checks += 13

    # Complete-current-M15 quality filter is auditable from the unmodified source aggregation.
    assert sum(int(event["current_m15_complete"]) for event in events) == summary["replay"]["events_after_current_m15_completeness_filter"]
    checks += 1

    # Independent executable-side, first-hit audit for all three RR output tables.
    by_event = {event["event_id"]: event for event in events}
    indices = raw_index_by_time
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
            count, expected = verify_trade_v103(event, trade, rr, raw, indices)
            trade_checks += count
            total_trades += 1
            outcomes[trade["outcome"]] += 1
            if trade["outcome"] in ("TP", "SL"):
                resolved_r.append(float(trade["r_multiple"]))
        rr_stats[folder] = {"trades": len(trades), "outcomes": dict(sorted(outcomes.items())),
                            "resolved_r_rows": len(resolved_r)}

    adapter_fixtures = ea_adapter_fixtures()
    result = {
        "source_sha256": digest(source), "events_audited": len(events),
        "event_invariant_checks_passed": checks, "trade_rows_audited": total_trades,
        "trade_arithmetic_and_first_hit_checks_passed": trade_checks,
        "ea_adapter_fixtures": adapter_fixtures,
        "rr_results": rr_stats,
        "audit_method": "Independent Python replay from raw Dukascopy M1 bid/ask OHLC. Rebuilds M15 histogram swings, directional Swing-H/Swing-L touches, trend/FVG anchoring and reclaim snapshots; independently validates M1 swing cross, exact successor hold, strict close-after-reclaim ordering, first sampled SR retest within the exclusive eight-bar deadline, and same-M15 containment. Recalculates InstantEngulf outward wick rounding, strategy TP from rounded strategy SL, ScalpCore nearest-tick SELL spread compensation, geometry rejection, entry delay, executable-side stop/target levels, open-gap fills and first-hit outcomes. M1 OHLC is not treated as tick order.",
    }
    (output / "independent-audit.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
