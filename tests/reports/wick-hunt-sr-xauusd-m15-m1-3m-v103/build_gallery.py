#!/usr/bin/env python3
"""Render the same 15 audited XAUUSD signals at three risk/reward targets."""
from __future__ import annotations

import bisect
import csv
import datetime as dt
import hashlib
import html
import importlib.util
import json
import math
import shutil
import subprocess
import tempfile
from collections import Counter, defaultdict
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
spec = importlib.util.spec_from_file_location("chart_helpers", HERE.parent / "wick-hunt-sr-xauusd-1y/build_gallery.py")
charts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(charts)
WIDTH, HEIGHT = 2400, 2200
charts.WIDTH = WIDTH
BG, PANEL, TEXT, MUTED = charts.BG, charts.PANEL, charts.TEXT, charts.MUTED
GREEN, RED, CYAN, PINK, GOLD = charts.UP, charts.DOWN, charts.SR, charts.RECLAIM, charts.H1_OPEN
HOLD = '#bb9aff'
LEFT, RIGHT = 105, WIDTH - 120
MODELS = (("rr-1", 1.0), ("rr-1_5", 1.5), ("rr-2", 2.0))
font = charts.font


def read_csv(path):
    with Path(path).open(newline="") as handle:
        return list(csv.DictReader(handle))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def val(row, *keys, default=None):
    for key in keys:
        if row.get(key) not in (None, ""):
            return row[key]
    if default is not None:
        return default
    raise KeyError(f"Missing {keys} in {list(row)}")


def num(row, *keys, default=None):
    return float(val(row, *keys, default=default))


def integer(row, *keys, default=None):
    value = val(row, *keys, default=default)
    if 'event_id' in keys and str(value).startswith('WHM15M1-'):
        return int(str(value).rpartition('-')[2])
    return int(float(value))


def normalize_trade(row):
    result = dict(row)
    for target, source in (('result','outcome'),('entry','entry_price'),('stop','stop_price'),
                           ('target','target_price'),('observed_minutes','bars_held'),
                           ('exposed_source_gaps','source_gap_count')):
        if target not in result:
            result[target] = result[source]
    return result


def side(row):
    return "BUY" if str(val(row, "direction")).upper() in ("BUY", "1") else "SELL"


def label_time(t, full=False):
    return dt.datetime.fromtimestamp(int(t), dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S" if full else "%m-%d %H:%M")


def bars_from_csv(path):
    return [{"epoch": integer(b, "epoch", "time"), **{k: num(b, k) for k in ("open", "high", "low", "close")},
             "source_m1_count": integer(b, "source_m1_count", "minute_count", default=1)} for b in read_csv(path)]


def export_macd(bars):
    verification = HERE / "macd_verification.json"
    paths = {"dataset": HERE.parent / "engulf-imbalance-xauusd-m1/xauusd_m1_bid_ask.csv.gz",
             "exporter": HERE / "tv_macd.cpp", "tv_core": ROOT / "MQL5/Indicators/TVStyleMACD/MACDCore.mqh",
             "swing_core": ROOT / "MQL5/Indicators/WickHuntSRFlow/SwingCore.mqh", "series": HERE / "m1_macd.csv"}
    if verification.exists() and paths['series'].exists():
        metadata = json.loads(verification.read_text())
        if all(sha(path) == metadata['sha256'][key] for key, path in paths.items()):
            values = {integer(r, "epoch"): {k: num(r, k) for k in ("macd", "signal", "histogram", "color_index")}
                      for r in read_csv(paths['series'])}
            if len(values) == metadata['verified_bars'] and all(b['epoch'] in values for b in bars):
                print(f"Reusing {len(values):,} verified M1 MACD observations; provenance unchanged", flush=True)
                return values
    compiler = shutil.which("clang++") or shutil.which("g++")
    if not compiler:
        raise RuntimeError("C++ compiler required to verify actual TV Style MACD")
    with tempfile.TemporaryDirectory(prefix="wick-m15-m1-macd-") as tmp:
        tmp = Path(tmp)
        normalized = tmp / "bars.csv"
        with normalized.open("w", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(["timestamp_utc", "epoch", "open", "high", "low", "close", "source_m1_count"])
            for b in bars:
                writer.writerow([label_time(b["epoch"], True), b["epoch"], *(b[k] for k in ("open", "high", "low", "close")), b["source_m1_count"]])
        executable = tmp / "tv-macd"
        subprocess.run([compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
                        "-I", str(ROOT / "MQL5/Indicators/TVStyleMACD"),
                        "-I", str(ROOT / "MQL5/Indicators/WickHuntSRFlow"),
                        str(HERE / "tv_macd.cpp"), "-o", str(executable)], check=True)
        subprocess.run([str(executable), str(normalized), str(HERE / "m1_macd.csv")], check=True)
    verification.write_text(json.dumps({"verified_bars": len(bars),
        "method": "actual TVStyleMACD EMA12/26/9 exact equality against Histogram SwingCore each M1",
        "sha256": {key: sha(path) for key, path in paths.items()}}, indent=2) + '\n')
    return {integer(r, "epoch"): {k: num(r, k) for k in ("macd", "signal", "histogram", "color_index")}
            for r in read_csv(HERE / "m1_macd.csv")}


def draw_macd(draw, bars, xs, macd, xmap, entry, reclaim, exit_t, hold=0, retest=0):
    top, bottom = 1660, 2130
    draw.rectangle((LEFT, top, RIGHT, bottom), fill=PANEL)
    draw.text((LEFT + 8, top + 8), "TV Style MACD · M1 · EMA 12 / 26 / 9 · Close", fill=TEXT, font=font(25, True))
    for i, (text, color) in enumerate((("MACD", charts.MACD_BLUE), ("Signal", charts.SIGNAL_ORANGE),
                                       ("Hist + rising", "#26a69a"), ("Hist + falling", "#b2dfdb"),
                                       ("Hist - rising", "#ffcdd2"), ("Hist - falling", "#ff5252"))):
        draw.text((LEFT + 8 + i * 210, top + 43), text, fill=color, font=font(18, True))
    values = [macd[b["epoch"]] for b in bars]
    levels = [0] + [r[k] for r in values for k in ("macd", "signal", "histogram")]
    padding = max((max(levels) - min(levels)) * .09, .01)
    lo, hi = min(levels) - padding, max(levels) + padding
    y = lambda price: charts.price_y(price, lo, hi, top + 85, bottom - 28)
    for i in range(5):
        v = hi - (hi - lo) * i / 4
        draw.line((LEFT, y(v), RIGHT, y(v)), fill=charts.GRID)
        draw.text((RIGHT + 12, y(v) - 10), f"{v:.3f}", fill=MUTED, font=font(16))
    draw.line((LEFT, y(0), RIGHT, y(0)), fill="#787b86", width=2)
    width = max(1, min(10, round((xs[1] - xs[0]) * .6))) if len(xs) > 1 else 4
    for x, row in zip(xs, values):
        draw.rectangle((x - width / 2, min(y(0), y(row["histogram"])), x + width / 2, max(y(0), y(row["histogram"]))),
                       fill=charts.HISTOGRAM_COLORS[int(row["color_index"])])
    for key, color in (("macd", charts.MACD_BLUE), ("signal", charts.SIGNAL_ORANGE)):
        draw.line([(x, y(r[key])) for x, r in zip(xs, values)], fill=color, width=3)
    for t, color in ((reclaim, PINK), (hold,HOLD), (retest,CYAN), (entry, TEXT), (exit_t, GOLD)):
        if t and bars[0]["epoch"] <= t <= bars[-1]["epoch"] + 60:
            draw.line((xmap(t), top + 85, xmap(t), bottom - 28), fill=color, width=1)
    for i in range(min(8, len(bars))):
        j = round(i * (len(bars) - 1) / max(1, min(8, len(bars)) - 1))
        text = label_time(bars[j]["epoch"])
        tw = draw.textbbox((0, 0), text, font=font(16))[2]
        draw.text((xs[j] - tw / 2, bottom - 20), text, fill=MUTED, font=font(16))


def scenario_text(pattern):
    return {1: "Breakout / strong FVG", 2: "Trend pullback / two wicks", 3: "Breakout + Pullback"}[pattern]


def select_examples(events, models):
    # Deterministic chronology within strata, shared across all RR models.
    # Gallery is illustrative; full results always use every signal.
    common = set.intersection(*(set(rows) for rows in models.values()))
    groups = defaultdict(list)
    for e in events:
        identity = integer(e, "event_id", "number")
        if identity not in common:
            continue
        rows = [model[identity] for model in models.values()]
        if any(r["result"] not in ("TP", "SL") for r in rows):
            continue
        if max(integer(r, "observed_minutes", default=0) for r in rows) > 480:
            continue
        month = label_time(integer(e, "event_epoch"), True)[:7]
        groups[(integer(e, "pattern", "scenario"), side(e), month)].append(e)
    for rows in groups.values():
        rows.sort(key=lambda e: (integer(e, "event_epoch"), integer(e, "event_id", "number")))
    selected, keys, cursor = [], sorted(groups), 0
    while len(selected) < 15 and keys:
        key = keys[cursor % len(keys)]
        selected.append(groups[key].pop(0))
        if not groups[key]:
            keys.remove(key)
        else:
            cursor += 1
    if len(selected) < 15:
        raise ValueError(f"Only {len(selected)} eligible gallery examples; do not fabricate the requested 15")
    return sorted(selected, key=lambda e: (integer(e, "event_epoch"), integer(e, "event_id", "number")))


def plot_case(event, trade, rr, m15, m1, macd, output, number):
    now, setup = integer(event, "event_epoch"), integer(event, "setup_epoch")
    reclaim, breakout = integer(event, "reclaim_epoch"), integer(event, "breakout_epoch")
    hold = integer(event, 'hold_close_epoch')
    entry_time = integer(trade,'entry_epoch')
    retest_bar = integer(event,'retest_bar')
    pivot, confirm = integer(event, "pivot_epoch"), integer(event, "confirm_epoch")
    anchor = integer(event, "anchor_epoch", "anchor_time", default=0)
    trend_pivot = integer(event, "trend_pivot_epoch", "trend_pivot", default=0)
    pattern, direction = integer(event, "pattern", "scenario"), side(event)
    entry, stop, target = (num(trade, k) for k in ("entry", "stop", "target"))
    exit_t = integer(trade, "exit_bar_open_epoch", default=integer(trade, "exit_epoch") // 60 * 60)
    result_r = num(trade, "r_multiple")
    m15_times, m1_times = [b["epoch"] for b in m15], [b["epoch"] for b in m1]
    hi = bisect.bisect_left(m15_times, setup)
    if hi >= len(m15) or m15[hi]["epoch"] != setup:
        raise ValueError("M15 setup missing")
    first_hi = max(0, hi - 24)
    for context_t in (anchor, trend_pivot):
        if context_t:
            first_hi = min(first_hi, max(hi - 96, bisect.bisect_left(m15_times, context_t) - 2))
    hview = m15[max(0, first_hi):hi + 13]
    setup_index = hi - max(0, first_hi)
    known_end = bisect.bisect_right(m1_times, now - 60)
    pi = bisect.bisect_left(m1_times, pivot)
    first_mi = max(0, min(known_end - 120, max(known_end - 300, pi - 5)))
    last_mi = min(len(m1), max(known_end + 60, bisect.bisect_right(m1_times, exit_t) + 20))
    view = m1[first_mi:last_mi]
    image = Image.new("RGB", (WIDTH, HEIGHT), BG)
    d = ImageDraw.Draw(image)
    d.text((80, 28), f"#{number:02d}  XAUUSD · {direction} · nominal RR 1:{rr:g} · {trade['result']} {result_r:+.2f}R", fill=TEXT, font=font(36, True))
    d.text((82, 80), f"{scenario_text(pattern)}  |  Signal {label_time(now, True)} UTC  |  fixed spread $0.36", fill=MUTED, font=font(22))
    d.text((82, 114), f"Reclaim {label_time(reclaim)} → break close {label_time(breakout+60)} → hold close {label_time(hold)} → retest bar {retest_bar}/8", fill=PINK, font=font(21, True))
    d.text((82, 145), f"Entry {label_time(entry_time)} UTC @ {entry:.3f}   SL {stop:.3f}   TP {target:.3f}   |   exit M1 {label_time(exit_t)}", fill=MUTED, font=font(20))
    d.text((82, 175), "M1 Open / :59 Close samples; exact intraminute reclaim/exit order is unavailable. Future candles are context only.", fill=MUTED, font=font(18))

    htop, hbottom = 215, 840
    hopen = num(event, "hunt_open", "m15_open")
    known_high, known_low = num(event, "known_high"), num(event, "known_low")
    context_sr = num(event, "context_sr")
    hvalues = [b[k] for b in hview for k in ("high", "low")] + [hopen, context_sr, known_high, known_low]
    hpad = max((max(hvalues) - min(hvalues)) * .09, .2)
    hlo, hhi = min(hvalues) - hpad, max(hvalues) + hpad
    hspacing = (RIGHT - LEFT - 80) / max(1, len(hview) - 1)
    hxs = [LEFT + 40 + i * hspacing for i in range(len(hview))]
    hx = {b["epoch"]: x for b, x in zip(hview, hxs)}
    hbody = max(3, min(25, round(hspacing * .5)))
    charts.draw_candles(d, hview, hxs, (hlo, hhi), htop, hbottom, hbody,
                        f"M15 zoom out · {setup_index} preceding / {len(hview)-setup_index-1} following · colored candles = FINAL OHLC", plot_top_offset=80)
    d.text((LEFT + 8, htop + 43), "White outline = M15 values already known at the signal; final candles include later prices.", fill=MUTED, font=font(18))
    hy = lambda v: charts.price_y(v, hlo, hhi, htop + 80, hbottom - 28)
    curx = hx[setup]
    d.line((LEFT, hy(hopen), RIGHT, hy(hopen)), fill=GOLD, width=2)
    d.text((RIGHT - 245, hy(hopen) + 5), f"M15 OPEN {hopen:.3f}", fill=GOLD, font=font(17, True))
    d.line((LEFT, hy(context_sr), curx, hy(context_sr)), fill=CYAN, width=2)
    d.text((LEFT + 8, hy(context_sr) - 24), f"M15 context SR {context_sr:.3f}", fill=CYAN, font=font(17, True))
    touch=integer(event,'context_touch_epoch',default=0)
    if pattern & 1 and touch in hx:
        tb=m15[bisect.bisect_left(m15_times,touch)]; tx=hx[touch]
        d.rectangle((tx-hbody/2-5,hy(tb['high'])-4,tx+hbody/2+5,hy(tb['low'])+4),outline=CYAN,width=3)
        bars_ago=(setup-touch)//900
        d.text((RIGHT-480,htop+62),f"SR TOUCH {bars_ago}/5 bars ago (cyan outline)",fill=CYAN,font=font(16,True))
    for offset in range(1, 3 if pattern & 2 else 2):
        prior = m15[hi - offset]
        level = prior["low" if direction == "BUY" else "high"]
        start_x = hx.get(prior["epoch"], LEFT)
        charts_y = hy(level)
        d.line((start_x, charts_y, min(RIGHT, curx + hspacing), charts_y), fill=charts.PRIOR, width=2)
        d.text((LEFT+8+(offset-1)*260,htop+62),f"Swept wick {offset}: {level:.3f}",fill=charts.PRIOR,font=font(16,True))
    d.line((curx, hy(known_high), curx, hy(known_low)), fill=TEXT, width=3)
    signal_bid = num(event, "price", "bid_price", "signal_bid")
    d.rectangle((curx-hbody/2-3, min(hy(hopen),hy(signal_bid)), curx+hbody/2+3,
                 max(hy(hopen),hy(signal_bid), min(hy(hopen),hy(signal_bid))+3)), outline=TEXT, width=2)
    d.ellipse((curx-7, hy(signal_bid)-7, curx+7, hy(signal_bid)+7), fill=TEXT, outline=BG, width=2)
    for y in range(htop + 80, hbottom - 28, 14):
        d.line((curx, y, curx, min(y + 7, hbottom - 28)), fill=TEXT, width=1)
    if anchor and anchor in hx:
        anchor_bar = m15[bisect.bisect_left(m15_times, anchor)]
        ax = hx[anchor]
        tip = num(event, "reclaim_tip", default=known_low if direction == "BUY" else known_high)
        d.rectangle((ax-hbody/2-3, min(hy(anchor_bar['open']),hy(anchor_bar['close'])),
                     ax+hbody/2+3, max(hy(anchor_bar['open']),hy(anchor_bar['close']))), outline=GOLD, width=3)
        d.line((ax, hy(tip), curx, hy(tip)), fill=GOLD, width=3)
        d.text((LEFT+560,htop+62),"STRONG FVG BODY = gold outline / tip line",fill=GOLD,font=font(16,True))
    if trend_pivot and trend_pivot in hx:
        tb = m15[bisect.bisect_left(m15_times, trend_pivot)]
        tx = hx[trend_pivot]
        ty = hy(tb["high" if direction == "BUY" else "low"])
        d.ellipse((tx-7, ty-7, tx+7, ty+7), fill=PINK)
        d.text((max(LEFT+8, min(tx-95, RIGHT-240)), ty-28 if direction=="BUY" else ty+8), "CONFIRMED TREND PIVOT", fill=PINK, font=font(16, True))

    mtop, mbottom = 900, 1610
    shift = .36 if direction == "SELL" else 0
    plotted_sl, plotted_tp = stop - shift, target - shift
    mvalues = [b[k] for b in view for k in ("high", "low")] + [entry, plotted_sl, plotted_tp, num(event,"sr_price")]
    mpad = max((max(mvalues) - min(mvalues)) * .1, .15)
    lo, hi_price = min(mvalues)-mpad, max(mvalues)+mpad
    spacing = (RIGHT-LEFT-50) / max(1, len(view))
    xs = [LEFT + 25 + i * spacing for i in range(len(view))]
    times = [b["epoch"] for b in view]
    def xmap(t):
        i = bisect.bisect_right(times, t)-1
        if i < 0: return xs[0] + (t-times[0])/60 * spacing
        return xs[min(i,len(xs)-1)] + min((t-times[min(i,len(times)-1)])/60,1) * spacing
    width = max(2,min(10,round(spacing*.6)))
    charts.draw_candles(d, view, xs, (lo,hi_price), mtop, mbottom, width,
                        f"M1 zoom out · {known_end-first_mi} closed at signal + {last_mi-known_end} following · Bid candles", plot_top_offset=80)
    d.text((LEFT+8,mtop+43), "SELL SL/TP lines are converted to Bid (Ask order level − spread)." if direction=="SELL" else "BUY enters Ask; SL/TP and exits use Bid.", fill=MUTED,font=font(18))
    my = lambda price: charts.price_y(price,lo,hi_price,mtop+80,mbottom-28)
    sx = xmap(entry_time)
    for label_index,(label,value,order_value,color) in enumerate((("ENTRY",entry,entry,TEXT),("SL",plotted_sl,stop,RED),("TP",plotted_tp,target,GREEN))):
        y = my(value)
        d.line((sx,y,RIGHT,y), fill=color, width=2)
        text=f"{label} order {order_value:.3f}"
        tw=d.textbbox((0,0),text,font=font(18,True))[2]
        label_y=mtop+88+label_index*30
        d.rounded_rectangle((RIGHT-tw-24,label_y-2,RIGHT-4,label_y+25),radius=4,fill=BG)
        d.text((RIGHT-tw-14,label_y),text,fill=color,font=font(18,True))
    sr=num(event,"sr_price")
    confirm_x=max(LEFT,xmap(confirm+60))
    d.line((confirm_x,my(sr),sx,my(sr)),fill=CYAN,width=3)
    sr_type = str(val(event,'sr_type'))
    sr_type = {'1':'Swing H','-1':'Swing L'}.get(sr_type,sr_type)
    d.text((max(LEFT+8,min(confirm_x+8,RIGHT-350)),my(sr)+6),f"M1 {sr_type} SR {sr:.3f}",fill=CYAN,font=font(17,True))
    for t,color in ((reclaim,PINK),(hold,HOLD),(now,CYAN),(entry_time,TEXT),(exit_t,GOLD)):
        d.line((xmap(t),mtop+80,xmap(t),mbottom-28),fill=color,width=2)
    d.text((LEFT+8,865), f"BREAK cyan outline  |  HOLD violet outline  |  RETEST {now%60:02d}s cyan line (bar {retest_bar}/8)  |  ENTRY white  |  EXIT gold",fill=MUTED,font=font(19,True))
    bx=xmap(breakout)
    bb=m1[bisect.bisect_left(m1_times,breakout)]
    d.rectangle((bx-6,my(bb['high'])-3,bx+6,my(bb['low'])+3),outline=CYAN,width=2)
    hb=m1[bisect.bisect_left(m1_times,hold-60)]; hold_x=xmap(hold-60)
    d.rectangle((hold_x-6,my(hb['high'])-3,hold_x+6,my(hb['low'])+3),outline=HOLD,width=3)
    d.ellipse((xmap(now)-6,my(signal_bid)-6,xmap(now)+6,my(signal_bid)+6),fill=CYAN,outline=BG,width=2)
    exit_bid=num(trade,"exit_price")-shift
    d.ellipse((xmap(exit_t)-8,my(exit_bid)-8,xmap(exit_t)+8,my(exit_bid)+8),fill=GREEN if trade['result']=='TP' else RED,outline=TEXT,width=2)
    d.ellipse((sx-7,my(entry)-7,sx+7,my(entry)+7),fill=TEXT,outline=BG,width=2)
    draw_macd(d,view,xs,macd,xmap,entry_time,reclaim,exit_t,hold,now)
    d.text((82,2160), "v1.03 · SL = known M15 wick; Instant Engulf tick rounding + SELL spread on SL/TP. R normalized to executable risk; nominal RR differs.",fill=MUTED,font=font(18))
    image.save(output,optimize=True)
    return {"number":number,"event_id":integer(event,"event_id","number"),"rr":rr,"file":str(output.relative_to(HERE)),
            "event_epoch":now,"entry_epoch":entry_time,"hold_close_epoch":hold,"retest_bar":retest_bar,"pattern":pattern,"direction":direction,"result":trade['result'],"r_multiple":result_r,
            "m15_before":setup_index,"m15_after":len(hview)-setup_index-1,"m1_before":known_end-first_mi,
            "m1_after":last_mi-known_end,"exit_visible":view[0]['epoch']<=exit_t<=view[-1]['epoch'],"sha256":sha(output)}


def main():
    events=read_csv(HERE/'events.csv')
    models={name:{integer(t,'event_id','number'):normalize_trade(t) for t in read_csv(HERE/name/'trades.csv')} for name,_ in MODELS}
    selected=select_examples(events,models)
    m15=bars_from_csv(HERE/'m15_bars.csv'); m1=bars_from_csv(HERE/'m1_bars.csv')
    macd=export_macd(m1)
    examples=[]
    for name,rr in MODELS:
        output=HERE/name/'gallery'; output.mkdir(parents=True,exist_ok=True)
        for i,event in enumerate(selected,1):
            identity=integer(event,'event_id','number')
            trade=models[name][identity]
            examples.append(plot_case(event,trade,rr,m15,m1,macd,output/f'{i:02d}-{side(event).lower()}-event-{identity}.png',i))
        print(f'{name}: 15 charts rendered',flush=True)
    manifest={"examples_per_rr":15,"total_images":45,"selected_event_ids":[integer(e,'event_id','number') for e in selected],
              "selection":"same 15 resolved <=480-observed-minute signals across RR; chronological round-robin by scenario/direction/month; illustrative, not representative trade frequency",
              "macd":"actual TVStyleMACD EMA12/26/9 Close, exact equality checked against actual HistogramSwingCore on every M1",
              "macd_series_sha256":sha(HERE/'m1_macd.csv'),"builder_sha256":sha(Path(__file__)),"examples":examples}
    (HERE/'gallery_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')


if __name__=='__main__':
    main()
