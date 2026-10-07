#!/usr/bin/env python3
"""Build a 30-chart, stratified visual sample for the fixed-spread M1 replay."""
from __future__ import annotations

import csv
import gzip
import html
import json
import math
from bisect import bisect_right
from collections import Counter
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
DATA = HERE / "xauusd_m1_bid_ask.csv.gz"
M5_DATA = HERE.parent / "engulf-imbalance-xauusd-m5" / "m5_bars.csv"
EVENTS = HERE / "events.csv"
OUT = HERE / "gallery"
POINT = 0.001
SAMPLE_PER_PATTERN = 10
WIDTH, HEIGHT = 1800, 1480
BG, INK, GRID, MUTED = "#f4f7fb", "#17273c", "#dce3ed", "#5d6d80"
BUY, SELL, BLUE = "#178a52", "#d24545", "#1684d8"
EMA_COLORS = {20: "#1565c0", 50: "#ef6c00", 200: "#6d4c41"}

FONT_PATH = Path("/System/Library/Fonts/Supplemental/Tahoma.ttf")
FONT_BOLD_PATH = Path("/System/Library/Fonts/Supplemental/Tahoma Bold.ttf")


def font(size: int, bold: bool = False):
    path = FONT_BOLD_PATH if bold else FONT_PATH
    try:
        return ImageFont.truetype(str(path), size)
    except OSError:
        return ImageFont.load_default()


FONTS = {size: font(size) for size in (15, 17, 20, 23)}
FONTS_BOLD = {size: font(size, True) for size in (19, 26, 30)}


def evenly_spaced(rows: list[dict], count: int) -> list[dict]:
    rows = sorted(rows, key=lambda row: int(row["index"]))
    if count >= len(rows):
        return rows
    if count <= 0 or not rows:
        return []
    if count == 1:
        return [rows[len(rows) // 2]]
    selected = []
    for slot in range(count):
        position = round(slot * (len(rows) - 1) / (count - 1))
        selected.append(rows[position])
    return selected


def select_sample(events: list[dict]) -> list[dict]:
    """Choose ten examples per pattern, spanning outcomes and both sides."""
    selected = []
    quotas = (("TP", 4), ("SL", 4), ("BOTH", 1), ("NO_ENTRY", 1))
    for pattern in ("A", "B", "A+B"):
        pattern_rows = [event for event in events if event["pattern"] == pattern]
        picked = []
        for result, quota in quotas:
            group = [event for event in pattern_rows if event["result"] == result]
            buy = [event for event in group if event["side"] == "BUY"]
            sell = [event for event in group if event["side"] == "SELL"]
            buy_quota = quota // 2
            sell_quota = quota // 2
            if quota % 2:
                if len(buy) > len(sell):
                    buy_quota += 1
                else:
                    sell_quota += 1
            buy_quota = min(buy_quota, len(buy))
            sell_quota = min(sell_quota, len(sell))
            remaining = quota - buy_quota - sell_quota
            if remaining:
                add_buy = min(remaining, len(buy) - buy_quota)
                buy_quota += add_buy
                sell_quota += min(remaining - add_buy, len(sell) - sell_quota)
            picked.extend(evenly_spaced(buy, buy_quota))
            picked.extend(evenly_spaced(sell, sell_quota))
        # If a small outcome bucket is short, fill from the remaining pattern
        # examples while retaining time and side coverage.
        picked_ids = {id(event) for event in picked}
        remainder = [event for event in pattern_rows if id(event) not in picked_ids]
        picked.extend(evenly_spaced(remainder, max(0, SAMPLE_PER_PATTERN - len(picked))))
        if len(picked) != SAMPLE_PER_PATTERN:
            raise RuntimeError(f"could not select {SAMPLE_PER_PATTERN} examples for {pattern}")
        selected.extend(picked)
    selected.sort(key=lambda event: int(event["index"]))
    if len(selected) != 30 or len({event["index"] for event in selected}) != 30:
        raise RuntimeError("sample must contain 30 distinct signals")
    return selected


def read_events() -> list[dict]:
    with EVENTS.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def read_bars() -> list[tuple[int, float, float, float, float]]:
    bars = []
    with gzip.open(DATA, "rt", newline="", encoding="utf-8") as stream:
        for row in csv.DictReader(stream):
            bars.append((int(row["epoch"]), float(row["bid_open"]), float(row["bid_high"]),
                         float(row["bid_low"]), float(row["bid_close"])))
    return bars


def read_m5_bars() -> list[tuple[int, float, float, float, float]]:
    bars = []
    with M5_DATA.open(newline="", encoding="utf-8") as stream:
        for row in csv.DictReader(stream):
            bars.append((int(row["epoch"]), float(row["open"]), float(row["high"]),
                         float(row["low"]), float(row["close"])))
    if not bars:
        raise RuntimeError(f"no M5 bars in {M5_DATA}")
    return bars


def compute_ema(bars: list[tuple[int, float, float, float, float]], period: int) -> list[float]:
    alpha = 2.0 / (period + 1)
    output = []
    value = None
    for bar in bars:
        close = bar[4]
        value = close if value is None else alpha * close + (1.0 - alpha) * value
        output.append(value)
    return output


def dashed_line(draw, xy1, xy2, fill, width=2, dash=9, gap=6):
    x1, y1 = xy1
    x2, y2 = xy2
    length = math.hypot(x2 - x1, y2 - y1)
    if not length:
        return
    dx, dy = (x2 - x1) / length, (y2 - y1) / length
    pos = 0.0
    while pos < length:
        end = min(length, pos + dash)
        draw.line((x1 + dx * pos, y1 + dy * pos, x1 + dx * end, y1 + dy * end),
                  fill=fill, width=width)
        pos += dash + gap


def plot_pane(draw, bars, start, end, box, pane_title, *, ema=None, signal_index=None,
              levels=None, highlights=None, gap_zones=None):
    left, top, right, bottom = box
    view = bars[start:end]
    prices = [price for bar in view for price in bar[1:5]]
    if ema:
        for values in ema.values():
            prices.extend(values[start:end])
    for _, value, _ in levels or []:
        if value is not None and value > 0:
            prices.append(value)
    low, high = min(prices), max(prices)
    pad = max((high - low) * 0.08, 0.12)
    low, high = low - pad, high + pad
    step = (right - left) / max(1, len(view))

    def x_at(bar_index):
        return left + (bar_index - start + 0.5) * step

    def y_at(price):
        return bottom - (price - low) / (high - low) * (bottom - top)

    draw.text((left, top - 39), pane_title, font=FONTS_BOLD[26], fill=INK)
    draw.rectangle((left, top, right, bottom), fill="white", outline="#ced7e3", width=2)
    for tick in range(5):
        price = low + (high - low) * tick / 4
        yy = y_at(price)
        draw.line((left, yy, right, yy), fill=GRID, width=1)
        draw.text((right + 10, yy - 10), f"{price:.3f}", font=FONTS[15], fill=MUTED)

    for zone_low, zone_high, from_index, to_index, color in gap_zones or []:
        x1 = max(left, x_at(max(start, from_index)))
        x2 = min(right, x_at(min(end - 1, to_index)))
        y1, y2 = sorted((y_at(zone_high), y_at(zone_low)))
        if x2 > x1 and y2 > y1:
            draw.rectangle((x1, y1, x2, y2), outline=color, width=2)

    for idx in range(start, end):
        _, open_, high_, low_, close_ = bars[idx]
        xx = x_at(idx)
        color = BUY if close_ >= open_ else SELL
        draw.line((xx, y_at(low_), xx, y_at(high_)), fill=color, width=2)
        y1, y2 = sorted((y_at(open_), y_at(close_)))
        if y2 - y1 < 2:
            y2 = y1 + 2
        half = max(2, step * .30)
        draw.rectangle((xx - half, y1, xx + half, y2), fill=color)

    for idx, color, _label in highlights or []:
        if not start <= idx < end:
            continue
        _, open_, _, _, close_ = bars[idx]
        body_low, body_high = sorted((open_, close_))
        if body_high == body_low:
            body_high += 0.005
        xx = x_at(idx)
        draw.rectangle((xx - step * .44, y_at(body_high), xx + step * .44, y_at(body_low)),
                       outline=color, width=3)

    if ema:
        legend_x = left + 12
        for period in (20, 50, 200):
            values = ema[period]
            points = [(x_at(idx), y_at(values[idx])) for idx in range(start, end)]
            if len(points) > 1:
                draw.line(points, fill=EMA_COLORS[period], width=3)
            draw.line((legend_x, top + 18, legend_x + 24, top + 18), fill=EMA_COLORS[period], width=4)
            draw.text((legend_x + 30, top + 7), f"EMA {period}", font=FONTS[15], fill=EMA_COLORS[period])
            legend_x += 115

    for label, value, color in levels or []:
        if value is None or value <= 0:
            continue
        yy = y_at(value)
        dashed_line(draw, (left, yy), (right, yy), color, width=2, dash=10, gap=6)
        draw.text((right - 145, yy - 20), f"{label} {value:.3f}", font=FONTS[15], fill=color)

    if signal_index is not None and start <= signal_index < end:
        xx = x_at(signal_index)
        dashed_line(draw, (xx, top), (xx, bottom), "#7d5ac7", width=3, dash=7, gap=6)

    count = end - start
    every = 1 if count <= 16 else 8 if count <= 60 else 12
    for idx in range(start, end):
        if (idx - start) % every:
            continue
        minute = (bars[idx][0] % 86400) // 60
        label = f"{minute // 60:02d}:{minute % 60:02d}"
        draw.text((x_at(idx) - 24, bottom + 8), label, font=FONTS[15], fill=MUTED)
    return x_at


def draw_chart(event: dict, bars, m5_bars, emas, m5_epochs, number: int, folder: Path) -> Path:
    index = int(event["index"])
    entry_index = int(event["entry_index"] or index + 1)
    anchor_indices = [int(event[key]) for key in ("anchor_a", "anchor_b")
                      if event[key] not in ("", "-1", "-2")]
    focus = min([index, *anchor_indices]) if anchor_indices else index
    start, end = max(0, focus - 32), min(len(bars), max(index, entry_index) + 22)
    signal_epoch = bars[index][0]
    m5_index = bisect_right(m5_epochs, signal_epoch) - 1
    if m5_index < 0 or m5_index >= len(m5_bars):
        raise RuntimeError(f"no M5 context for M1 signal at {signal_epoch}")
    m5_start, m5_end = max(0, m5_index - 30), min(len(m5_bars), m5_index + 13)
    wait = int(event["wait"])
    result = event["result"]
    result_label = {"TP": "TP", "SL": "SL", "BOTH": "TP และ SL ในแท่งเดียว", "NO_ENTRY": "เข้าไม่ได้"}.get(result, result)
    side_color = BUY if event["side"] == "BUY" else SELL
    image = Image.new("RGB", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(image)
    draw.text((48, 28), f"EngulfImbalanceFlow 1.08 · {event['pattern']} · {event['side']} · {result_label}",
              font=FONTS_BOLD[30], fill=INK)
    draw.text((50, 74), f"XAUUSD M1 · สัญญาณ {event['timestamp']} UTC · ตัวอย่าง {number}/30",
              font=FONTS[23], fill=MUTED)
    wait_label = "เข้าเมื่อแท่งถัดไป" if wait == 0 else f"รอย่อ {wait} แท่ง"
    draw.text((50, 111), f"Fixed spread 20 จุด (0.020) · {wait_label} · EMA แสดงบนกราฟ M1 เท่านั้น ไม่ได้กรองสัญญาณ",
              font=FONTS[20], fill=INK)

    levels = []
    for key, label, color in (("entry_level", "Pullback", "#b28b00"),
                              ("entry", "Entry", "#334155"), ("sl", "SL", "#b42318"),
                              ("tp", "TP 1:1", "#0f7a45")):
        try:
            value = float(event.get(key, ""))
        except (TypeError, ValueError):
            value = None
        levels.append((label, value if value and value > 0 else None, color))

    highlights = []
    gap_zones = []
    for key, label in (("anchor_a", "FVG A"), ("anchor_b", "FVG B")):
        if event[key] in ("", "-1", "-2"):
            continue
        anchor = int(event[key])
        highlights.append((anchor, BLUE, label))
        if anchor >= 2:
            old, current = bars[anchor - 2], bars[anchor]
            if event["side"] == "BUY":
                zone_low, zone_high = old[2], current[3]
            else:
                zone_low, zone_high = current[2], old[3]
            if zone_high > zone_low:
                gap_zones.append((zone_low, zone_high, anchor, index, "#92c6e8"))
    engulf_index = int(event["engulf_index"])
    highlights.extend(((engulf_index - 1, "#8c66c5", "Engulfed"),
                       (engulf_index, "#e49b18", "Engulf")))
    plot_pane(draw, bars, start, end, (100, 260, 1570, 820),
              "M1 · EMA 20 / 50 / 200", ema=emas, signal_index=index,
              levels=levels, highlights=highlights, gap_zones=gap_zones)

    context_start = m5_bars[m5_index][0]
    plot_pane(draw, m5_bars, m5_start, m5_end, (100, 1010, 1570, 1320),
              f"M5 context · signal falls inside candle opened {context_start // 3600 % 24:02d}:{context_start // 60 % 60:02d} UTC",
              signal_index=m5_index)

    spread = float(event["spread_used"])
    draw.text((50, 1380), f"กราฟ M1: กรอบน้ำเงิน = FVG · ม่วง/ส้ม = คู่แท่ง engulf · เส้นม่วง = แท่งสัญญาณ | กราฟ M5: เส้นม่วงชี้แท่งที่ครอบเวลาสัญญาณ",
              font=FONTS[17], fill=INK)
    draw.text((50, 1414), f"Spread ที่ใช้ตรวจ pullback: {spread / POINT:.0f} จุด ({spread:.3f}) · ผล: {result_label} · TP/SL เป็น gross ไม่หักต้นทุน execution",
              font=FONTS[17], fill=side_color)

    path = folder / f"{number:02d}.png"
    image.save(path, compress_level=4)
    return path


def main() -> None:
    events = read_events()
    sample = select_sample(events)
    bars = read_bars()
    m5_bars = read_m5_bars()
    emas = {period: compute_ema(bars, period) for period in (20, 50, 200)}
    m5_epochs = [bar[0] for bar in m5_bars]
    folder = OUT / "signals"
    folder.mkdir(parents=True, exist_ok=True)
    cards = []
    for number, event in enumerate(sample, 1):
        image_path = draw_chart(event, bars, m5_bars, emas, m5_epochs, number, folder)
        cards.append({"number": number, "image": f"signals/{image_path.name}",
                      "timestamp": event["timestamp"], "side": event["side"],
                      "pattern": event["pattern"], "result": event["result"],
                      "wait": event["wait"]})

    counts = Counter((card["pattern"], card["result"]) for card in cards)
    cards_json = json.dumps(cards, ensure_ascii=False)
    articles = []
    for card in cards:
        label = f"{card['number']:02d} · {card['pattern']} · {card['side']} · {card['result']} · {card['timestamp']} UTC"
        articles.append(
            f'<article data-pattern="{html.escape(card["pattern"])}" data-side="{card["side"]}" '
            f'data-result="{card["result"]}"><a href="{card["image"]}" target="_blank">'
            f'<img loading="lazy" src="{card["image"]}" alt="{html.escape(label)}"></a>'
            f'<p><strong>{html.escape(label)}</strong><br>รอเข้า {card["wait"]} แท่งหลัง engulf</p></article>')

    buttons = [("all", "ทั้งหมด 30"), ("A", "A · 10"), ("B", "B · 10"), ("A+B", "A+B · 10"),
               ("BUY", "Buy"), ("SELL", "Sell"), ("TP", "TP"), ("SL", "SL"),
               ("BOTH", "ทั้งคู่ในแท่ง"), ("NO_ENTRY", "เข้าไม่ได้")]
    nav = "".join(f'<button data-filter="{key}" class="{"active" if key == "all" else ""}">{html.escape(label)}</button>'
                   for key, label in buttons)
    page = f'''<!doctype html><html lang="th"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>EngulfImbalanceFlow XAUUSD M1 · 30 ตัวอย่าง</title>
<style>
body{{margin:0;background:#f4f7fb;color:#17273c;font:16px/1.5 system-ui,sans-serif}}
main{{max-width:1500px;margin:auto;padding:28px}}nav{{display:flex;gap:8px;flex-wrap:wrap;position:sticky;top:0;background:#f4f7fb;padding:12px 0;z-index:2}}
button{{border:1px solid #ced7e3;border-radius:8px;background:white;padding:8px 14px;cursor:pointer;font:inherit}}
button.active{{background:#17273c;color:white}}.grid{{display:grid;grid-template-columns:1fr 1fr;gap:16px}}
article{{background:white;border:1px solid #dce3ed;border-radius:12px;overflow:hidden}}img{{width:100%;display:block;background:#eef2f7}}
p{{margin:0;padding:10px 14px 14px}}article[hidden]{{display:none}}@media(max-width:900px){{.grid{{grid-template-columns:1fr}}}}
</style><main><h1>EngulfImbalanceFlow 1.08 · XAUUSD M1</h1>
<p>ตัวอย่าง 30 สัญญาณ คัดแบบละ 10 ภาพให้ครอบคลุม A, B, A+B และผล TP/SL/กรณียกเว้น แต่ละภาพแสดงกราฟ M1 พร้อม EMA 20/50/200 และกราฟ M5 ที่จัดแนวตามแท่งซึ่งครอบเวลาสัญญาณ M1. EMA เป็นเส้นประกอบภาพ ไม่ได้กรองสัญญาณ; fixed spread 20 จุดใช้เฉพาะ pullback. คลิกรูปเพื่อเปิดขนาดเต็ม</p>
<nav>{nav}</nav><div class="grid">{''.join(articles)}</div></main><script>
document.querySelectorAll('button').forEach(button => button.onclick = () => {{
  document.querySelectorAll('button').forEach(item => item.classList.toggle('active', item === button));
  const filter = button.dataset.filter;
  document.querySelectorAll('article').forEach(card => {{
    card.hidden = filter !== 'all' && card.dataset.pattern !== filter && card.dataset.side !== filter && card.dataset.result !== filter;
  }});
}});
</script></html>'''
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "index.html").write_text(page, encoding="utf-8")
    (OUT / "manifest.json").write_text(cards_json + "\n", encoding="utf-8")
    print(json.dumps({"images": len(cards), "patterns": {p: sum(1 for c in cards if c["pattern"] == p)
                                                           for p in ("A", "B", "A+B")},
                      "gallery": str(OUT / "index.html"),
                      "pattern_outcomes": {f"{p}/{r}": count for (p, r), count in sorted(counts.items())}},
                     ensure_ascii=False))


if __name__ == "__main__":
    main()
