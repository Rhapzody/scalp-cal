#!/usr/bin/env python3
"""Build annotated XAUUSD setup charts from the public 5m OHLCV sample.

The visuals are deliberately labelled as replay candidates.  They use the
same broad conditions as the EAs, but they are not a broker-exact backtest:
the public file contains OHLC and tick volume only (no bid/ask or spread).
"""
import csv
import html
import math
import os
import sys
from collections import defaultdict
from datetime import datetime


CSV_PATH = "/private/tmp/xauusd_5m.csv"
DEFAULT_OUT = "/Users/peeratatmantaga/.codex/visualizations/2026/09/15/01a0a392-dd78-7ee0-958d-71275bd184ff"


def load_rows(path):
    out = []
    with open(path, newline="") as f:
        for r in csv.DictReader(f):
            out.append({
                "dt": datetime.fromisoformat(r["datetime"].replace("Z", "+00:00")),
                "o": float(r["open"]), "h": float(r["high"]),
                "l": float(r["low"]), "c": float(r["close"]),
                "v": float(r["volume"]),
            })
    return out


def ema(values, period):
    alpha = 2.0 / (period + 1.0)
    result, prev = [], None
    for value in values:
        prev = value if prev is None else prev + alpha * (value - prev)
        result.append(prev)
    return result


def atr(rows, period=14):
    tr, prev_close = [], None
    for r in rows:
        ref = r["c"] if prev_close is None else prev_close
        tr.append(max(r["h"] - r["l"], abs(r["h"] - ref), abs(r["l"] - ref)))
        prev_close = r["c"]
    return ema(tr, period)


def pivot_indices(rows, side, radius=2):
    pivots = []
    for i in range(radius, len(rows) - radius):
        if side == "high":
            value = rows[i]["h"]
            if value >= max(rows[j]["h"] for j in range(i - radius, i + radius + 1)):
                pivots.append(i)
        else:
            value = rows[i]["l"]
            if value <= min(rows[j]["l"] for j in range(i - radius, i + radius + 1)):
                pivots.append(i)
    return pivots


def nearest_confirmed_swing(rows, pivots, side, idx, entry):
    past = [p for p in pivots if p <= idx - 2]
    if side == "buy":
        levels = [rows[p]["h"] for p in past if rows[p]["h"] > entry]
        return min(levels) if levels else None
    levels = [rows[p]["l"] for p in past if rows[p]["l"] < entry]
    return max(levels) if levels else None


def outcome(rows, idx, side, entry, sl, tp, horizon=32):
    for j in range(idx + 1, min(len(rows), idx + horizon + 1)):
        if side == "buy":
            hit_sl, hit_tp = rows[j]["l"] <= sl, rows[j]["h"] >= tp
        else:
            hit_sl, hit_tp = rows[j]["h"] >= sl, rows[j]["l"] <= tp
        if hit_sl and hit_tp:
            return "both same bar"
        if hit_tp:
            return "TP first"
        if hit_sl:
            return "SL first"
    return "not reached in 32 bars"


def spaced(candidates, rows, count=3, min_gap=450):
    """Pick three candidates across the sample, preferring clean follow-through."""
    if not candidates:
        return []
    # One candidate per broad time slice makes the examples less cherry-picked.
    n = len(rows)
    buckets = [[], [], []]
    for c in candidates:
        bucket = min(2, int(3 * c["idx"] / n))
        buckets[bucket].append(c)
    chosen = []
    for bucket in buckets:
        bucket.sort(key=lambda c: (c.get("quality", 0), c.get("rr", 0)), reverse=True)
        for c in bucket:
            if all(abs(c["idx"] - p["idx"]) >= min_gap for p in chosen):
                chosen.append(c)
                break
    # Backfill if a bucket had no candidate after spacing.
    if len(chosen) < count:
        for c in sorted(candidates, key=lambda x: x.get("quality", 0), reverse=True):
            if all(abs(c["idx"] - p["idx"]) >= min_gap for p in chosen):
                chosen.append(c)
            if len(chosen) >= count:
                break
    return sorted(chosen[:count], key=lambda c: c["idx"])


def make_candidates(rows, count=3, skip=0, exclude_labels=None):
    closes = [r["c"] for r in rows]
    atrs = atr(rows)
    e50, e200 = ema(closes, 50), ema(closes, 200)
    m12, m26 = ema(closes, 12), ema(closes, 26)
    macd = [m12[i] - m26[i] for i in range(len(rows))]
    signal = ema(macd, 9)
    hist = [macd[i] - signal[i] for i in range(len(rows))]
    swing_hi, swing_lo = pivot_indices(rows, "high"), pivot_indices(rows, "low")

    trend = []
    for i in range(220, len(rows) - 40):
        a = max(atrs[i], 0.01)
        if e50[i] > e200[i]:
            prior = min(rows[q]["l"] for q in range(i - 12, i))
            if rows[i]["l"] < prior and rows[i]["c"] > prior and rows[i]["c"] > rows[i]["o"] and rows[i]["c"] - rows[i]["o"] > 0.45 * a:
                entry = rows[i]["c"]
                sl = rows[i]["l"] - 0.15 * a
                tp = entry + 2.0 * (entry - sl)
                trend.append({"idx": i, "side": "buy", "entry": entry, "sl": sl, "tp": tp,
                              "zone_lo": prior - 0.12 * a, "zone_hi": prior + 0.12 * a,
                              "kind": "trend", "quality": (rows[i]["c"] - rows[i]["o"]) / a,
                              "note": "EMA50 > EMA200 • sell-side sweep • close reclaimed prior low"})
        elif e50[i] < e200[i]:
            prior = max(rows[q]["h"] for q in range(i - 12, i))
            if rows[i]["h"] > prior and rows[i]["c"] < prior and rows[i]["c"] < rows[i]["o"] and rows[i]["o"] - rows[i]["c"] > 0.45 * a:
                entry = rows[i]["c"]
                sl = rows[i]["h"] + 0.15 * a
                tp = entry - 2.0 * (sl - entry)
                trend.append({"idx": i, "side": "sell", "entry": entry, "sl": sl, "tp": tp,
                              "zone_lo": prior - 0.12 * a, "zone_hi": prior + 0.12 * a,
                              "kind": "trend", "quality": (rows[i]["o"] - rows[i]["c"]) / a,
                              "note": "EMA50 < EMA200 • buy-side sweep • close reclaimed prior high"})

    # Opening range: six M5 bars from 08:00 UTC, then breakout and retest.
    by_day = defaultdict(list)
    for i, r in enumerate(rows):
        by_day[r["dt"].date()].append((i, r))
    opening = []
    for day, items in by_day.items():
        starts = [x[0] for x in items if x[1]["dt"].hour == 8 and x[1]["dt"].minute == 0]
        if not starts:
            continue
        start = starts[0]
        window = rows[start:start + 6]
        if len(window) < 6:
            continue
        hi, lo = max(r["h"] for r in window), min(r["l"] for r in window)
        for k in range(start + 6, min(start + 42, len(rows))):
            bar, a = rows[k], max(atrs[k], 0.01)
            side = "buy" if bar["c"] > hi and bar["o"] <= hi else "sell" if bar["c"] < lo and bar["o"] >= lo else None
            if not side:
                continue
            for q in range(k + 1, min(k + 14, len(rows))):
                ret = rows[q]
                if side == "buy" and ret["l"] <= hi and ret["c"] > hi:
                    entry = ret["c"]; sl = lo - 0.12 * a; tp = entry + 2.0 * (entry - sl)
                    opening.append({"idx": q, "side": side, "entry": entry, "sl": sl, "tp": tp,
                                    "zone_lo": hi - 0.10 * a, "zone_hi": hi + 0.10 * a,
                                    "range_lo": lo, "range_hi": hi, "break_idx": k, "kind": "opening",
                                    "quality": abs(bar["c"] - bar["o"]) / a,
                                    "note": "08:00 UTC 30-minute range • upside break • retest held"})
                    break
                if side == "sell" and ret["h"] >= lo and ret["c"] < lo:
                    entry = ret["c"]; sl = hi + 0.12 * a; tp = entry - 2.0 * (sl - entry)
                    opening.append({"idx": q, "side": side, "entry": entry, "sl": sl, "tp": tp,
                                    "zone_lo": lo - 0.10 * a, "zone_hi": lo + 0.10 * a,
                                    "range_lo": lo, "range_hi": hi, "break_idx": k, "kind": "opening",
                                    "quality": abs(bar["c"] - bar["o"]) / a,
                                    "note": "08:00 UTC 30-minute range • downside break • retest held"})
                    break
            break

    # MACD histogram swing -> displacement break -> return to the broken level.
    macd_zone = []
    for i in range(35, len(rows) - 40):
        a = max(atrs[i], 0.01)
        if hist[i - 1] < 0 <= hist[i]:
            level = max(rows[q]["h"] for q in range(i - 10, i))
            for k in range(i + 1, min(i + 12, len(rows))):
                if rows[k]["c"] > level and rows[k]["c"] - rows[k]["o"] > 0.45 * max(atrs[k], 0.01):
                    base = next((q for q in range(k - 1, max(i - 1, k - 9), -1) if rows[q]["c"] < rows[q]["o"]), k - 1)
                    zlo, zhi = rows[base]["l"], rows[base]["h"]
                    for q in range(k + 1, min(k + 22, len(rows))):
                        if rows[q]["l"] <= level * 1.001 and rows[q]["c"] > level:
                            entry = rows[q]["c"]; sl = min(zlo, rows[q]["l"]) - 0.15 * a
                            swing = nearest_confirmed_swing(rows, swing_hi, "buy", q, entry)
                            tp = swing if swing and swing > entry + (entry - sl) else entry + 1.6 * (entry - sl)
                            macd_zone.append({"idx": q, "side": "buy", "entry": entry, "sl": sl, "tp": tp,
                                              "zone_lo": zlo, "zone_hi": zhi, "break_idx": k, "kind": "macd",
                                              "quality": (rows[k]["c"] - rows[k]["o"]) / max(atrs[k], 0.01),
                                              "note": "MACD histogram flipped green • displacement broke SR • return to demand/FVG"})
                            break
                    break
        elif hist[i - 1] > 0 >= hist[i]:
            level = min(rows[q]["l"] for q in range(i - 10, i))
            for k in range(i + 1, min(i + 12, len(rows))):
                if rows[k]["c"] < level and rows[k]["o"] - rows[k]["c"] > 0.45 * max(atrs[k], 0.01):
                    base = next((q for q in range(k - 1, max(i - 1, k - 9), -1) if rows[q]["c"] > rows[q]["o"]), k - 1)
                    zlo, zhi = rows[base]["l"], rows[base]["h"]
                    for q in range(k + 1, min(k + 22, len(rows))):
                        if rows[q]["h"] >= level * 0.999 and rows[q]["c"] < level:
                            entry = rows[q]["c"]; sl = max(zhi, rows[q]["h"]) + 0.15 * a
                            swing = nearest_confirmed_swing(rows, swing_lo, "sell", q, entry)
                            tp = swing if swing and swing < entry - (sl - entry) else entry - 1.6 * (sl - entry)
                            macd_zone.append({"idx": q, "side": "sell", "entry": entry, "sl": sl, "tp": tp,
                                              "zone_lo": zlo, "zone_hi": zhi, "break_idx": k, "kind": "macd",
                                              "quality": (rows[k]["o"] - rows[k]["c"]) / max(atrs[k], 0.01),
                                              "note": "MACD histogram flipped red • displacement broke SR • return to supply/FVG"})
                            break
                    break

    # InstantEngulf: body engulfing candle plus a clear prior wick rejection.
    instant, scalp = [], []
    for i in range(2, len(rows) - 35):
        a, b, prev = rows[i - 1], rows[i], rows[i - 2]
        vol = max(atrs[i], 0.01)
        buy = b["c"] > b["o"] and a["c"] < a["o"] and b["o"] <= a["c"] and b["c"] >= a["o"]
        sell = b["c"] < b["o"] and a["c"] > a["o"] and b["o"] >= a["c"] and b["c"] <= a["o"]
        side = "buy" if buy else "sell" if sell else None
        if not side:
            continue
        entry = b["c"]
        if side == "buy":
            sl = min(a["l"], b["l"]) - 0.12 * vol; tp = entry + 1.5 * (entry - sl)
            wick = (min(a["l"], b["l"]) < prev["l"])
        else:
            sl = max(a["h"], b["h"]) + 0.12 * vol; tp = entry - 1.5 * (sl - entry)
            wick = (max(a["h"], b["h"]) > prev["h"])
        c = {"idx": i, "side": side, "entry": entry, "sl": sl, "tp": tp,
             "zone_lo": min(a["l"], b["l"]), "zone_hi": max(a["h"], b["h"]), "kind": "engulf",
             "quality": abs(b["c"] - b["o"]) / vol + (0.8 if wick else 0),
             "note": "closed-body engulfing candle • SL uses engulf wick + buffer • manual/auto trigger"}
        instant.append(c)
        if wick:
            s = dict(c); s["kind"] = "scalp"; s["note"] = "wick hunt + closed engulf • calculator risk/spread filter • manual button trigger"; scalp.append(s)

    total_needed = count + skip
    exclude_labels = exclude_labels or {}
    def pick(pool, name):
        excluded = set(exclude_labels.get(name, []))
        if excluded:
            pool = [x for x in pool if rows[x["idx"]]["dt"].strftime("%Y-%m-%d %H:%M UTC") not in excluded]
        return spaced(pool, rows, count=total_needed)[skip:skip + count]
    instant_examples = pick(instant, "InstantEngulf EA")
    # Show a different set for the calculator panel so the gallery demonstrates
    # both the standalone EA and the integrated/manual panel in varied markets.
    instant_ids = {x["idx"] for x in spaced(instant, rows, count=total_needed)}
    scalp_pool = [x for x in scalp if all(abs(x["idx"] - j) >= 180 for j in instant_ids)]
    scalp_examples = pick(scalp_pool or scalp, "ScalpCalculator EA — Instant Engulf panel")
    return {
        "MACDZoneTrader EA": pick(macd_zone, "MACDZoneTrader EA"),
        "TrendSweepTrader EA": pick(trend, "TrendSweepTrader EA"),
        "OpeningRangeTrader EA": pick(opening, "OpeningRangeTrader EA"),
        "InstantEngulf EA": instant_examples,
        "ScalpCalculator EA — Instant Engulf panel": scalp_examples,
    }, {"atr": atrs, "hist": hist, "e50": e50, "e200": e200}


def esc(value):
    return html.escape(str(value), quote=True)


def chart_svg(rows, indicators, setup, title, out_file):
    idx = setup["idx"]
    start, end = max(0, idx - 38), min(len(rows), idx + 26)
    bars = rows[start:end]
    chart_w, chart_h = 1120, 700
    left, right, top, bottom = 72, 30, 62, 125
    main_bottom = 515
    plot_w = chart_w - left - right
    step = plot_w / max(1, len(bars))
    values = [x for r in bars for x in (r["h"], r["l"])] + [setup["entry"], setup["sl"], setup["tp"], setup.get("zone_lo"), setup.get("zone_hi")]
    raw_lo, raw_hi = min(values), max(values)
    margin = max(0.08 * (raw_hi - raw_lo), 0.8)
    lo, hi = raw_lo - margin, raw_hi + margin
    if hi - lo < 1: hi, lo = lo + 1, lo

    def x_for(j): return left + (j + 0.5) * step
    def y_for(price): return top + (hi - price) / (hi - lo) * (main_bottom - top)
    def line(x1, y1, x2, y2, stroke, width=1, dash=""):
        return f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{stroke}" stroke-width="{width}"' + (f' stroke-dasharray="{dash}"' if dash else "") + '/>'

    parts = [f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {chart_w} {chart_h}" role="img" aria-label="{esc(title)}">''',
             '<rect width="100%" height="100%" fill="#0b1020"/>',
             f'<text x="{left}" y="30" fill="#f5f7fb" font-size="20" font-family="Arial" font-weight="700">{esc(title)}</text>',
             f'<text x="{left}" y="49" fill="#9aa8bd" font-size="12" font-family="Arial">XAUUSD · M5 · UTC · public OHLCV replay example · {esc(rows[idx]["dt"].strftime("%Y-%m-%d %H:%M"))}</text>']
    # Grid and y labels.
    for g in range(6):
        y = top + g * (main_bottom - top) / 5
        p = hi - g * (hi - lo) / 5
        parts.append(line(left, y, chart_w - right, y, "#25334a", 1))
        parts.append(f'<text x="{left - 9}" y="{y + 4:.1f}" text-anchor="end" fill="#8fa0b8" font-size="11" font-family="Arial">{p:.2f}</text>')
    # Zone shaded from signal through the visible continuation.
    zlo, zhi = setup.get("zone_lo"), setup.get("zone_hi")
    if zlo is not None and zhi is not None:
        x0 = x_for(max(0, idx - start - 2))
        y0, y1 = y_for(max(zlo, zhi)), y_for(min(zlo, zhi))
        parts.append(f'<rect x="{x0:.1f}" y="{y0:.1f}" width="{chart_w - right - x0:.1f}" height="{max(2, y1-y0):.1f}" fill="#eab308" fill-opacity="0.16" stroke="#eab308" stroke-opacity="0.65" stroke-dasharray="5 4"/>')
        parts.append(f'<text x="{x0 + 7:.1f}" y="{y0 - 6:.1f}" fill="#f7d46b" font-size="11" font-family="Arial">SR / zone</text>')
    # Opening range band if present.
    if setup.get("range_lo") is not None:
        y0, y1 = y_for(setup["range_hi"]), y_for(setup["range_lo"])
        x0 = x_for(max(0, setup.get("break_idx", idx) - start - 6))
        parts.append(f'<rect x="{x0:.1f}" y="{y0:.1f}" width="{max(2, x_for(min(len(bars)-1, idx-start+12))-x0):.1f}" height="{max(2,y1-y0):.1f}" fill="#4f46e5" fill-opacity="0.11" stroke="#818cf8" stroke-dasharray="4 4"/>')
        parts.append(f'<text x="{x0 + 7:.1f}" y="{y0 - 6:.1f}" fill="#a5b4fc" font-size="11" font-family="Arial">30m opening range</text>')

    # Price lines.
    colors = {"entry": "#f8fafc", "sl": "#fb7185", "tp": "#4ade80"}
    labels = {"entry": "ENTRY", "sl": "SL + buffer", "tp": "TP / next target"}
    for key in ("entry", "sl", "tp"):
        y = y_for(setup[key]); parts.append(line(left, y, chart_w-right, y, colors[key], 2, "8 5"))
        parts.append(f'<text x="{chart_w-right-6}" y="{y-5:.1f}" text-anchor="end" fill="{colors[key]}" font-size="11" font-family="Arial" font-weight="700">{labels[key]} {setup[key]:.2f}</text>')

    # Candles.
    candle_w = max(3, min(14, step * 0.62))
    for j, r in enumerate(bars):
        x, yo, yc = x_for(j), y_for(r["o"]), y_for(r["c"])
        col = "#39d98a" if r["c"] >= r["o"] else "#ff647c"
        parts.append(line(x, y_for(r["h"]), x, y_for(r["l"]), col, 1.3))
        parts.append(f'<rect x="{x-candle_w/2:.1f}" y="{min(yo,yc):.1f}" width="{candle_w:.1f}" height="{max(1.4,abs(yc-yo)):.1f}" fill="{col}" stroke="{col}"/>')
    entry_j = idx - start
    ex, ey = x_for(entry_j), y_for(setup["entry"])
    arrow = "M %0.1f %0.1f L %0.1f %0.1f L %0.1f %0.1f" % (ex-7, ey+22, ex, ey+8, ex+7, ey+22)
    parts += [f'<path d="{arrow}" fill="none" stroke="#f8fafc" stroke-width="2"/>',
              f'<circle cx="{ex:.1f}" cy="{ey:.1f}" r="4" fill="#f8fafc"/>',
              f'<text x="{ex+11:.1f}" y="{ey+28:.1f}" fill="#f8fafc" font-size="12" font-family="Arial" font-weight="700">signal / entry</text>']

    # MACD histogram subpanel makes the histogram colour change visible.
    if setup["kind"] == "macd":
        zero = 587
        parts.append(line(left, zero, chart_w-right, zero, "#53627a", 1))
        parts.append(f'<text x="{left}" y="{zero - 56}" fill="#9aa8bd" font-size="11" font-family="Arial">MACD histogram (green/red flip)</text>')
        hs = [indicators["hist"][start+j] for j in range(len(bars))]
        amp = max(max(abs(x) for x in hs), 1e-9)
        for j, hval in enumerate(hs):
            yy = zero - hval / amp * 46
            color = "#39d98a" if hval >= 0 else "#ff647c"
            parts.append(f'<rect x="{x_for(j)-candle_w/2:.1f}" y="{min(zero,yy):.1f}" width="{candle_w:.1f}" height="{max(1,abs(yy-zero)):.1f}" fill="{color}" fill-opacity="0.82"/>')
        flip_j = next((j for j in range(1, len(hs)) if (hs[j-1] < 0 <= hs[j]) or (hs[j-1] > 0 >= hs[j])), None)
        if flip_j is not None:
            parts.append(f'<line x1="{x_for(flip_j):.1f}" y1="{top}" x2="{x_for(flip_j):.1f}" y2="{zero+52}" stroke="#f7d46b" stroke-dasharray="3 4"/>')
            parts.append(f'<text x="{x_for(flip_j)+5:.1f}" y="{zero+42}" fill="#f7d46b" font-size="10" font-family="Arial">hist flip</text>')
    else:
        parts.append(f'<text x="{left}" y="{main_bottom + 45}" fill="#71839e" font-size="11" font-family="Arial">Each candle = 5 minutes · prices are XAUUSD quote units</text>')
    # Footer note and result tag.
    result = outcome(rows, idx, setup["side"], setup["entry"], setup["sl"], setup["tp"])
    tag_col = "#4ade80" if result == "TP first" else "#fb7185" if result == "SL first" else "#f7d46b"
    parts += [f'<rect x="{left}" y="{chart_h-52}" width="{chart_w-left-right}" height="28" rx="6" fill="#111a2e" stroke="#25334a"/>',
              f'<text x="{left+12}" y="{chart_h-34}" fill="#d6e0ee" font-size="12" font-family="Arial">{esc(setup["note"])}</text>',
              f'<text x="{chart_w-right-12}" y="{chart_h-34}" text-anchor="end" fill="{tag_col}" font-size="12" font-family="Arial" font-weight="700">historical first-touch: {esc(result)}</text>',
              '</svg>']
    with open(out_file, "w", encoding="utf-8") as f:
        f.write("\n".join(parts))
    return result


def build_html(out_dir, groups, source_first, source_last, image_rows, gallery_label="XAUUSD EA setup replay gallery"):
    sections = []
    for name, setups in groups.items():
        imgs = image_rows[name]
        body = [f'<section class="strategy"><h2>{esc(name)}</h2><p class="explain">Historical replay candidates using the EA\'s core filters. Labels show where the signal would be evaluated; they are not a performance claim.</p><div class="grid">']
        for n, (setup, info) in enumerate(zip(setups, imgs), 1):
            file_name, result = info
            dt = setup["dt_label"]
            body.append(f'<figure><img src="{esc(file_name)}" alt="{esc(name)} setup {n} on {esc(dt)}"><figcaption><strong>Example {n}</strong> · {esc(dt)} · {esc(setup["side"].upper())} · {esc(result)}</figcaption></figure>')
        body.append('</div></section>')
        sections.append("\n".join(body))
    html_doc = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{esc(gallery_label)}</title>
<style>
:root {{ color-scheme: dark; --bg:#080d18; --panel:#111a2e; --text:#e6edf6; --muted:#9aa8bd; --line:#25334a; }}
* {{ box-sizing:border-box; }} body {{ margin:0; background:var(--bg); color:var(--text); font:15px/1.45 system-ui,-apple-system,Segoe UI,sans-serif; }}
main {{ max-width:1500px; margin:auto; padding:32px 26px 60px; }} h1 {{ margin:0 0 8px; font-size:30px; }} h2 {{ margin:0 0 5px; font-size:22px; }} p {{ color:var(--muted); }} .lead {{ max-width:1000px; }}
.notice {{ margin:20px 0 30px; padding:14px 16px; border:1px solid #394b6a; background:#0d1526; border-radius:10px; color:#cbd5e1; }}
.strategy {{ margin:34px 0 44px; }} .explain {{ margin:0 0 15px; }} .grid {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(360px,1fr)); gap:18px; }}
figure {{ margin:0; padding:10px; background:var(--panel); border:1px solid var(--line); border-radius:10px; }} figure img {{ display:block; width:100%; height:auto; border-radius:6px; }} figcaption {{ color:#cbd5e1; padding:8px 3px 1px; font-size:13px; }}
footer {{ border-top:1px solid var(--line); padding-top:18px; color:var(--muted); font-size:13px; }} a {{ color:#8ab4ff; }}
</style></head><body><main>
<h1>{esc(gallery_label)}</h1>
<p class="lead">Real-candle examples across each EA. The charts use the public XAUUSD 5-minute OHLCV sample from <b>{esc(source_first)}</b> through <b>{esc(source_last)}</b> (UTC).</p>
<div class="notice"><b>How to read:</b> green = bullish candle, red = bearish candle, white = entry, pink = SL plus the strategy buffer, green dashed = TP/next target, yellow = SR/zone. “Historical first-touch” only describes what happened after the illustrated signal in this sample. It is not a win-rate estimate.</div>
{''.join(sections)}
<footer>Data fields are OHLC plus tick volume. There is no broker bid/ask spread, commission, slippage, or execution latency in this gallery. Re-test with your broker's MT5 export before using live settings. Source: <a href="https://github.com/getdata-finance/xauusd-5m-ohlcv-metals-historical-data">GetData XAUUSD 5m sample</a>; schema and UTC timestamp notes are in the repository README.</footer>
</main></body></html>'''
    path = os.path.join(out_dir, "xauusd-ea-setups.html")
    with open(path, "w", encoding="utf-8") as f:
        f.write(html_doc)
    return path


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OUT
    extra = os.environ.get("SETUP_EXTRA", "0") == "1"
    count, skip = (5, 0) if extra else (3, 0)
    previous = {
        "MACDZoneTrader EA": ["2026-04-29 01:40 UTC", "2026-06-08 06:00 UTC", "2026-08-02 22:20 UTC"],
        "TrendSweepTrader EA": ["2026-04-12 22:00 UTC", "2026-05-14 23:30 UTC", "2026-07-26 22:00 UTC"],
        "OpeningRangeTrader EA": ["2026-04-13 08:45 UTC", "2026-07-13 11:15 UTC", "2026-08-17 09:20 UTC"],
        "InstantEngulf EA": ["2026-04-07 22:00 UTC", "2026-06-14 22:00 UTC", "2026-09-04 12:30 UTC"],
        "ScalpCalculator EA — Instant Engulf panel": ["2026-04-30 08:00 UTC", "2026-05-24 22:00 UTC", "2026-08-07 12:30 UTC"],
    }
    os.makedirs(out_dir, exist_ok=True)
    rows = load_rows(CSV_PATH)
    groups, indicators = make_candidates(rows, count=count, skip=skip, exclude_labels=previous if extra else None)
    # Keep the script honest if a future sample has too few matches.
    for name, setups in groups.items():
        if len(setups) < 3:
            raise SystemExit(f"Only {len(setups)} candidates for {name}; refusing to invent examples")
    image_rows = {}
    for name, setups in groups.items():
        image_rows[name] = []
        slug = ''.join(ch.lower() if ch.isalnum() else '-' for ch in name).strip('-')
        for n, setup in enumerate(setups, 1):
            setup["dt_label"] = setup["_dt_label"] = rows[setup["idx"]]["dt"].strftime("%Y-%m-%d %H:%M UTC")
            file_name = f"{slug}-{n}.svg"
            result = chart_svg(rows, indicators, setup, f"{name} · example {n}", os.path.join(out_dir, file_name))
            image_rows[name].append((file_name, result))
    gallery_label = "XAUUSD EA setup replay gallery · additional 5 per EA" if extra else "XAUUSD EA setup replay gallery"
    html_path = build_html(out_dir, groups, rows[0]["dt"].strftime("%Y-%m-%d"), rows[-1]["dt"].strftime("%Y-%m-%d"), image_rows, gallery_label)
    print(f"HTML={html_path}")
    for name, setups in groups.items():
        print(name, len(setups), ", ".join(s["dt_label"] for s in setups))


if __name__ == "__main__":
    main()
