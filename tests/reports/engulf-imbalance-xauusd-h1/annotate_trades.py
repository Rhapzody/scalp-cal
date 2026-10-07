#!/usr/bin/env python3
"""Add Instant Engulf 1:1 prices and a 15-point stop buffer to combo events."""
from __future__ import annotations

import csv
import math
import sys
from pathlib import Path

POINT = 0.001
BUFFER_POINTS = 15
BALANCE = 10000.0
RISK_PERCENT = 1.0
OUNCES_PER_LOT = 100.0
LOT_STEP = 0.01


def plan(bars, index, side, engulf_index=None):
    if index + 1 >= len(bars):
        return None
    origin = index if engulf_index is None else engulf_index
    if origin < 1 or origin >= len(bars):
        return None
    signal, previous, nxt = bars[origin], bars[origin - 1], bars[index + 1]
    entry = nxt["open"]
    if side == "BUY":
        stop = min(signal["low"], previous["low"]) - BUFFER_POINTS * POINT
        if not stop < entry:
            return {"entry": entry, "sl": stop, "tp": entry, "lot": 0.0, "result": "NO_TRADE", "bars": 0}
        target = 2.0 * entry - stop
    else:
        stop = max(signal["high"], previous["high"]) + BUFFER_POINTS * POINT
        if not stop > entry:
            return {"entry": entry, "sl": stop, "tp": entry, "lot": 0.0, "result": "NO_TRADE", "bars": 0}
        target = 2.0 * entry - stop
    risk_money = BALANCE * RISK_PERCENT / 100.0
    loss_per_lot = abs(entry - stop) * OUNCES_PER_LOT
    lot = math.floor(risk_money / loss_per_lot / LOT_STEP + 1e-9) * LOT_STEP
    result, bars_to_hit = "OPEN", 0
    for offset, bar in enumerate(bars[index + 1:], start=1):
        if side == "BUY":
            hit_sl, hit_tp = bar["low"] <= stop, bar["high"] >= target
        else:
            hit_sl, hit_tp = bar["high"] >= stop, bar["low"] <= target
        if hit_sl or hit_tp:
            result = "BOTH" if hit_sl and hit_tp else ("SL" if hit_sl else "TP")
            bars_to_hit = offset
            break
    return {"entry": entry, "sl": stop, "tp": target, "lot": lot, "result": result, "bars": bars_to_hit}


def main():
    out = Path(sys.argv[1])
    bars_path = Path(sys.argv[2])
    bars = list(csv.DictReader(bars_path.open()))
    for bar in bars:
        for key in ("open", "high", "low", "close"):
            bar[key] = float(bar[key])
    events = list(csv.DictReader((out / "combo_events.csv").open()))
    fields = list(events[0].keys())
    for name in ("entry", "sl", "tp", "lot", "result", "bars_to_hit"):
        if name not in fields:
            fields.append(name)
    counts = {}
    for event in events:
        origin = event.get("engulf_index")
        trade = plan(bars, int(event["index"]), event["side"],
                     None if origin in (None, "", "-") else int(origin))
        if trade is None:
            event.update({"entry": "", "sl": "", "tp": "", "lot": "", "result": "OPEN", "bars_to_hit": ""})
        else:
            event["entry"] = f"{trade['entry']:.5f}"
            event["sl"] = f"{trade['sl']:.5f}"
            event["tp"] = f"{trade['tp']:.5f}"
            event["lot"] = f"{trade['lot']:.2f}"
            event["result"] = trade["result"]
            event["bars_to_hit"] = str(trade["bars"])
        counts[event["result"]] = counts.get(event["result"], 0) + 1
    with (out / "combo_events.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(events)
    print(counts)


if __name__ == "__main__":
    main()
