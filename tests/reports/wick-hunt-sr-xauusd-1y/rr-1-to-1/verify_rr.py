#!/usr/bin/env python3
"""Regression checks for execution edge cases and independent raw-data trade audit."""
import argparse
import csv
import gzip
import json
import math
from collections import defaultdict
from pathlib import Path

from run_rr import DATA, EPS, HERE, bar_hit


def fixtures():
    count = 0
    def test(actual, expected):
        nonlocal count
        assert actual == expected, (actual, expected)
        count += 1
    def row(o, h, l):
        return {f"{s}_{k}": v for s in ("bid", "ask") for k, v in (("open", o), ("high", h), ("low", l))}
    test(bar_hit(1, row(100, 111, 89), 90, 110), ("BOTH", None, "intraminute_order_unknown"))
    test(bar_hit(-1, row(100, 111, 89), 110, 90), ("BOTH", None, "intraminute_order_unknown"))
    test(bar_hit(1, row(89, 115, 88), 90, 110), ("SL", 89, "open_gap_or_touch"))
    test(bar_hit(-1, row(111, 112, 85), 110, 90), ("SL", 111, "open_gap_or_touch"))
    test(bar_hit(1, row(115, 116, 88), 90, 110), ("TP", 110, "open_target_limit_fill"))
    test(bar_hit(-1, row(85, 112, 84), 110, 90), ("TP", 90, "open_target_limit_fill"))
    test(bar_hit(1, row(100, 110, 91), 90, 110), ("TP", 110, "intraminute_target_touch"))
    test(bar_hit(1, row(100, 109, 90), 90, 110), ("SL", 90, "intraminute_stop_touch"))
    test(bar_hit(-1, row(100, 109, 90), 110, 90), ("TP", 90, "intraminute_target_touch"))
    test(bar_hit(-1, row(100, 110, 91), 110, 90), ("SL", 110, "intraminute_stop_touch"))
    test(bar_hit(1, row(100, 109, 91), 90, 110), (None, None, ""))
    mixed = row(100, 109, 91)
    mixed.update(ask_open=101, ask_high=110, ask_low=92)
    test(bar_hit(1, mixed, 90, 110)[0], None)
    test(bar_hit(-1, mixed, 110, 90)[0], "SL")
    print(f"Execution fixtures: {count} checks passed")


def audit(stop_mode):
    output = HERE / f"sl-{stop_mode}"
    summary = json.loads((output / "summary.json").read_text())
    end = __import__('datetime').datetime.fromisoformat(summary['study_window_utc']['end_exclusive']).timestamp()
    with (output / "trades.csv").open() as handle:
        trades = list(csv.DictReader(handle))
    bars, index, hours, fives = [], {}, defaultdict(list), defaultdict(list)
    with gzip.open(DATA, "rt") as handle:
        for source in csv.DictReader(handle):
            t = int(source['epoch'])
            row = {k: float(source[k]) for k in source if k.startswith(('bid_', 'ask_'))}
            row['epoch'] = t
            index[t] = len(bars)
            bars.append(row)
            hours[t // 3600 * 3600].append(row)
            fives[t // 300 * 300].append(row)
    checks = 0
    def require(ok, message, trade):
        nonlocal checks
        checks += 1
        assert ok, (message, trade['number'])
    for trade in trades:
        entry_time, setup = int(trade['entry_epoch']), int(trade['setup_epoch'])
        is_buy = trade['direction'] == 'BUY'
        sign = 1 if is_buy else -1
        quote = bars[index[entry_time]]
        entry, stop, target, risk = (float(trade[k]) for k in ('entry', 'stop', 'target', 'risk_price'))
        require(abs(entry - quote['ask_open' if is_buy else 'bid_open']) < EPS, 'wrong entry side', trade)
        require(abs(float(trade['entry_spread']) - (quote['ask_open'] - quote['bid_open'])) < EPS, 'wrong spread', trade)
        if stop_mode == 'h1':
            known = [b for b in hours[setup] if b['epoch'] < entry_time]
            extreme_key = 'bid_low' if is_buy else 'ask_high'
            prices = [b[extreme_key] for b in known] + [quote['bid_open' if is_buy else 'ask_open']]
        else:
            known = fives[int(trade['breakout_epoch'])]
            require(int(trade['breakout_epoch']) + 300 <= entry_time, 'forming M5 used for SL', trade)
            prices = [b['bid_low' if is_buy else 'ask_high'] for b in known]
        actual_stop = min(prices) if is_buy else max(prices)
        require(abs(stop - actual_stop) < EPS, 'SL uses a future extreme or wrong quote', trade)
        require(abs(sign * (entry - stop) - risk) < EPS, 'risk mismatch', trade)
        require(abs(sign * (target - entry) - risk) < EPS, 'not RR 1:1', trade)
        if trade['result'] == 'INVALID_STOP':
            closing_quote = quote['bid_open' if is_buy else 'ask_open']
            require(risk <= EPS or sign * (closing_quote - stop) <= EPS, 'invalid-stop flag incorrect', trade)
            continue
        selected_result, exit_bar, fill = None, None, None
        previous_t = entry_time
        gap_count, missing_seconds, scanned = 0, 0, 0
        last_bar = quote
        for position in range(index[entry_time], len(bars)):
            bar = bars[position]
            if bar['epoch'] >= end:
                break
            last_bar = bar
            delta = bar['epoch'] - previous_t
            if delta > 60:
                gap_count += 1
                missing_seconds += delta - 60
            previous_t = bar['epoch']
            scanned += 1
            prefix = 'bid' if is_buy else 'ask'
            o, low, high = [bar[f'{prefix}_{k}'] for k in ('open', 'low', 'high')]
            open_stop, open_target = (o <= stop + EPS, o >= target - EPS) if is_buy else (o >= stop - EPS, o <= target + EPS)
            hits_stop, hits_target = (low <= stop + EPS, high >= target - EPS) if is_buy else (high >= stop - EPS, low <= target + EPS)
            if open_stop:
                selected_result, fill = 'SL', o
            elif open_target:
                selected_result, fill = 'TP', target
            elif hits_stop and hits_target:
                selected_result, fill = 'BOTH', None
            elif hits_stop:
                selected_result, fill = 'SL', stop
            elif hits_target:
                selected_result, fill = 'TP', target
            if selected_result:
                exit_bar = bar['epoch']
                break
        require(trade['result'] == (selected_result or 'OPEN'), 'earliest observed exit is incorrect', trade)
        require(int(trade['observed_minutes']) == scanned, 'incorrect holding bars', trade)
        require(int(trade['exposed_source_gaps']) == gap_count, 'incorrect gap count', trade)
        require(int(trade['missing_seconds_between_observations']) == missing_seconds, 'incorrect gap duration', trade)
        if selected_result:
            require(int(trade['exit_epoch']) == exit_bar, 'exit timestamp is wrong', trade)
        if fill is not None:
            require(abs(float(trade['exit_price']) - fill) < EPS, 'exit fill is wrong', trade)
            require(abs(float(trade['r_multiple']) - sign * (fill - entry) / risk) < EPS, 'incorrect realized R', trade)
        elif trade['result'] == 'BOTH':
            require(trade['r_multiple'] == '', 'BOTH order was guessed', trade)
        elif trade['result'] == 'OPEN':
            last_quote = last_bar['bid_close' if is_buy else 'ask_close']
            require(abs(float(trade['last_mark_r']) - sign * (last_quote - entry) / risk) < EPS,
                    'incorrect mark at study end', trade)
    result = {'audited_trades': len(trades), 'checks_passed': checks,
              'method': 'SL rebuilt from raw known Bid/Ask source; every exit rescanned independently in chronological order.'}
    (output / 'independent-audit.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stop', choices=('h1', 'm5'))
    args = parser.parse_args()
    fixtures()
    if args.stop:
        audit(args.stop)
