#!/usr/bin/env python3
"""Independent raw-data invariants for Luna's minute-snapshot signal replay."""
import csv
import gzip
import json
from bisect import bisect_right
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
DATA = ROOT / 'tests/reports/engulf-imbalance-xauusd-m1/xauusd_m1_bid_ask.csv.gz'


def main():
    minutes = {}
    by_hour = defaultdict(list)
    by_five = defaultdict(list)
    with gzip.open(DATA, 'rt') as handle:
        for row in csv.DictReader(handle):
            epoch = int(row['epoch'])
            assert epoch not in minutes, 'duplicate source timestamp'
            values = {field: float(row['bid_' + field]) for field in ('open', 'high', 'low', 'close')}
            minutes[epoch] = values
            by_hour[epoch // 3600 * 3600].append(epoch)
            by_five[epoch // 300 * 300].append(epoch)
    hours, fives = sorted(by_hour), sorted(by_five)

    def aggregate(indices):
        return dict(open=minutes[indices[0]]['open'], high=max(minutes[t]['high'] for t in indices),
                    low=min(minutes[t]['low'] for t in indices), close=minutes[indices[-1]]['close'])

    five_ohlc = {t: aggregate(indices) for t, indices in by_five.items()}
    hour_ohlc = {t: aggregate(indices) for t, indices in by_hour.items()}

    def quote_and_extremes(snapshot, setup):
        minute = snapshot // 60 * 60
        row = minutes[minute]
        phase = snapshot % 60
        assert phase in (0, 59), 'unexpected sample time'
        past = [t for t in by_hour[setup] if t < minute or (phase == 59 and t == minute)]
        price = row['open'] if phase == 0 else row['close']
        high = max([price] + [minutes[t]['high'] for t in past])
        low = min([price] + [minutes[t]['low'] for t in past])
        return price, high, low

    with (HERE / 'events.csv').open() as handle:
        events = list(csv.DictReader(handle))
    aliases = {'event_time': 'event_epoch', 'setup_time': 'setup_epoch', 'break_time': 'breakout_epoch',
               'pivot_time': 'pivot_epoch', 'confirm_time': 'confirm_epoch',
               'reclaim_observed_time': 'reclaim_epoch', 'breakout_observed_time': 'breakout_observed_epoch',
               'sr': 'sr_price', 'hunt_open': 'h1_open'}
    for event in events:
        if 'event_epoch' in event:
            event.update({name: event[column] for name, column in aliases.items()})
            event['direction'] = '1' if event['direction'] == 'BUY' else '-1'
            event['sr_type'] = '1' if event['sr_type'] == 'Swing H' else '-1'
    seen = set()
    checks = 0

    def require(condition, reason, event):
        nonlocal checks
        checks += 1
        if not condition:
            raise AssertionError(f'{reason}: {event}')

    for event in events:
        now, setup, direction = (int(event[x]) for x in ('event_time', 'setup_time', 'direction'))
        level, price = float(event['sr']), float(event['price'])
        breakout, pivot, confirmed = (int(event[x]) for x in ('break_time', 'pivot_time', 'confirm_time'))
        reclaim = int(event['reclaim_observed_time'])
        known_break = int(event['breakout_observed_time'])
        key = (setup, direction)
        require(key not in seen, 'duplicate signal for same direction/H1', event)
        seen.add(key)
        require(setup <= now < setup + 3600, 'event outside setup H1', event)
        require(setup <= breakout and breakout + 300 <= now, 'break not closed in same H1 before signal', event)
        require(pivot <= confirmed < breakout, 'SR unknown when breakout opened', event)
        require(breakout + 300 <= known_break <= now, 'selected break observation precedes actual close', event)
        require(setup <= reclaim <= now, 'reclaim outside setup or after event', event)
        require(reclaim < breakout + 300, 'M5 close not strictly after H1 reclaim', event)
        require(reclaim < known_break and event['event_order'] == 'reclaim_first',
                'signal violates reclaim-first order', event)
        require(len(by_five[breakout]) == 5, 'incomplete M5 breakout', event)
        prior_five = fives[bisect_right(fives, breakout) - 2]
        before, after = five_ohlc[prior_five]['close'], five_ohlc[breakout]['close']
        require((before <= level < after) if direction == 1 else (after < level <= before),
                'raw Close prices do not cross SR', event)
        sr_type = int(event['sr_type'])
        pivot_price = five_ohlc[pivot]['high' if sr_type == 1 else 'low']
        require(abs(level - pivot_price) < 1e-8, 'SR not actual pivot wick', event)
        preceding_hour = hours[bisect_right(hours, setup) - 2]
        require(len(by_hour[preceding_hour]) == 60, 'incomplete immediate prior H1', event)
        require(by_hour[setup][0] == setup, 'current H1 Open unobserved', event)
        open_price = hour_ohlc[setup]['open']
        require(abs(float(event['hunt_open']) - open_price) < 1e-8, 'wrong H1 Open', event)
        reclaim_price, high, low = quote_and_extremes(reclaim, setup)
        prior = hour_ohlc[preceding_hour]
        hunted = (low < prior['low'] and low < open_price and reclaim_price >= open_price) if direction == 1 else (
                  high > prior['high'] and high > open_price and reclaim_price <= open_price)
        require(hunted, 'raw data does not prove hunt/reclaim at recorded snapshot', event)
        observed_price, _, _ = quote_and_extremes(now, setup)
        require(abs(price - observed_price) < 1e-8, 'signal price not recorded snapshot quote', event)
        order = 'reclaim_first' if reclaim < known_break else 'breakout_first' if reclaim > known_break else 'same_snapshot'
        require(event['event_order'] == order, 'event order metadata inconsistent', event)
    result = {'events_audited': len(events), 'invariant_checks_passed': checks,
              'method': 'Independent validation against raw M1 bid OHLC, not a tick replay certification.'}
    (HERE / 'independent-audit.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
