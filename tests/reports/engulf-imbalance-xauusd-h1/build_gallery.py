#!/usr/bin/env python3
"""Draw one chart for every EngulfImbalanceFlow signal in combo_events.csv."""
from __future__ import annotations

import csv
import html
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else HERE
BARS_PATH = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else (ROOT / "tests/reports/flow-xauusd-h1/h1_bars.csv")
TIMEFRAME = sys.argv[3] if len(sys.argv) > 3 else "H1"
FONT_DIR = Path("/System/Library/Fonts/Supplemental")
W, H = 2100, 1040
BG = "#f4f7fb"
INK = "#17273c"
MUTED = "#5d6d80"
BUY = "#178a52"
SELL = "#d24545"
BODY = "#1e90ff"
GOLD = "#c8960c"
GRID = "#dce3ed"
EMA20 = "#1565c0"
EMA50 = "#ef6c00"
EMA200 = "#6d4c41"


def font(size, bold=False):
    name = "Tahoma Bold.ttf" if bold else "Tahoma.ttf"
    return ImageFont.truetype(str(FONT_DIR / name), size)


F = {(size, bold): font(size, bold) for size, bold in ((34, True), (20, False), (18, False), (16, True), (15, False))}


def load_bars():
    bars = list(csv.DictReader(BARS_PATH.open()))
    for bar in bars:
        for key in ("open", "high", "low", "close"):
            bar[key] = float(bar[key])
    for period, key in ((20, "ema20"), (50, "ema50"), (200, "ema200")):
        alpha = 2.0 / (period + 1)
        value = None
        for bar in bars:
            close = bar["close"]
            value = close if value is None else alpha * close + (1.0 - alpha) * value
            bar[key] = value
    return bars


def optional_int(value):
    return None if value in ("", "-") else int(value)


def optional_float(value):
    return None if value in ("", "-") else float(value)


def draw_text(d, xy, text, size, fill, bold=False):
    d.text(xy, text, font=F[(size, bold)], fill=fill)


def paint_pane(base, bars, lo, hi, box, bodies, line, arrow, levels=None):
    d = ImageDraw.Draw(base)
    left, top, right, bottom = box
    segment = bars[lo:hi]
    ymax = max(bar["high"] for bar in segment)
    ymin = min(bar["low"] for bar in segment)
    for bar in segment:
        for key in ("ema20", "ema50", "ema200"):
            ymax = max(ymax, bar[key])
            ymin = min(ymin, bar[key])
    for price in (levels or {}).values():
        if price is not None:
            ymax = max(ymax, price)
            ymin = min(ymin, price)
    if line is not None:
        ymax = max(ymax, line)
        ymin = min(ymin, line)
    for index, _ in bodies:
        if lo <= index < hi:
            bar = bars[index]
            low, high = sorted((bar["open"], bar["close"]))
            if high <= low:
                low -= 0.01
                high += 0.01
            ymax = max(ymax, high)
            ymin = min(ymin, low)
    pad = max((ymax - ymin) * 0.14, 0.8)
    ymin -= pad
    ymax += pad
    d.rectangle(box, fill="white")
    step = (right - left) / max(1, hi - lo)

    def x_of(index):
        return left + (index - lo + 0.5) * step

    def y_of(price):
        return bottom - (price - ymin) / (ymax - ymin) * (bottom - top)

    for step_i in range(5):
        price = ymin + (ymax - ymin) * step_i / 4
        yy = y_of(price)
        d.line((left, yy, right, yy), fill=GRID)
        d.text((right + 8, yy - 8), f"{price:.2f}", font=F[(15, False)], fill=MUTED)
    for index, _label in bodies:
        if not lo <= index < hi:
            continue
        bar = bars[index]
        low, high = sorted((bar["open"], bar["close"]))
        if high <= low:
            low -= 0.01
            high += 0.01
        d.rectangle((x_of(index) - step * 0.42, y_of(high), x_of(index) + step * 0.42, y_of(low)), outline=BODY, width=3)
    for index in range(lo, hi):
        bar = bars[index]
        xx = x_of(index)
        color = BUY if bar["close"] >= bar["open"] else SELL
        d.line((xx, y_of(bar["low"]), xx, y_of(bar["high"])), fill=color, width=2)
        y1, y2 = sorted((y_of(bar["open"]), y_of(bar["close"])))
        if y2 - y1 < 2:
            y2 = y1 + 2
        d.rectangle((xx - max(1.2, step * 0.28), y1, xx + max(1.2, step * 0.28), y2), fill=color)
    for key, color in (("ema200", EMA200), ("ema50", EMA50), ("ema20", EMA20)):
        points = [(x_of(index), y_of(bars[index][key])) for index in range(lo, hi)]
        if len(points) >= 2:
            d.line(points, fill=color, width=2)
    d.text((left + 12, top + 8), "EMA 20", font=F[(15, False)], fill=EMA20)
    d.text((left + 86, top + 8), "EMA 50", font=F[(15, False)], fill=EMA50)
    d.text((left + 168, top + 8), "EMA 200", font=F[(15, False)], fill=EMA200)
    for name, price, color in (("SL", (levels or {}).get("sl"), "#b42318"),
                               ("TP 1:1", (levels or {}).get("tp"), "#0f7a45"),
                               ("Entry", (levels or {}).get("entry"), "#334155")):
        if price is None:
            continue
        yy = y_of(price)
        d.line((left, yy, right, yy), fill=color, width=2)
        d.text((right - 92, yy - 16), f"{name} {price:.2f}", font=F[(15, False)], fill=color)
    if lo <= arrow[0] < hi:
        index, side = arrow
        color = "#32cd32" if side == "BUY" else SELL
        xx = x_of(index)
        if side == "BUY":
            yy = y_of(bars[index]["low"]) + 14
            d.polygon(((xx, yy), (xx - 8, yy + 14), (xx + 8, yy + 14)), fill=color)
        else:
            yy = y_of(bars[index]["high"]) - 14
            d.polygon(((xx, yy), (xx - 8, yy - 14), (xx + 8, yy - 14)), fill=color)
    visible_anchors = [index for index, _label in bodies if lo <= index < hi]
    if line is not None and (visible_anchors or lo <= arrow[0] < hi):
        points = [x_of(index) for index in visible_anchors]
        if lo <= arrow[0] < hi:
            points.append(x_of(arrow[0]))
        if len(points) < 2:
            start, end = left + 8, right - 8
        else:
            start, end = min(points), max(points)
        d.line((start, y_of(line), end, y_of(line)), fill=GOLD, width=3)
    if lo <= arrow[0] < hi:
        boundary = x_of(arrow[0]) + step * 0.5
        for yy in range(top, bottom, 10):
            d.line((boundary, yy, boundary, min(yy + 5, bottom)), fill="#7d5ac7", width=2)
    count = hi - lo
    label_every = 1 if count <= 16 else 8 if count <= 60 else 16 if count <= 120 else 24
    for index in range(lo, hi):
        if (index - lo) % label_every:
            continue
        d.text((x_of(index) - 36, bottom + 8), bars[index]["timestamp"][5:13], font=F[(15, False)], fill=MUTED)
    return d


def lead_wick(bar, side):
    span = bar["high"] - bar["low"]
    wick = (bar["high"] - bar["close"]) if side == "BUY" else (bar["close"] - bar["low"])
    return 100.0 * wick / span


def render(bars, event, number, total, folder):
    image = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(image)
    side = event["side"]
    pattern = event["pattern"]
    index = int(event["index"])
    anchor_a = optional_int(event["anchor_a"])
    anchor_b = optional_int(event["anchor_b"])
    tip = optional_float(event["wick_tip"])
    wait = event.get("wait", "0")
    shown = pattern if wait in ("", "0", "-") else f"{pattern} R{wait}"
    d.text((48, 28), f"EngulfImbalanceFlow   {shown}   {side}", font=F[(34, True)], fill=INK)
    d.text((48, 74), f"XAUUSD {TIMEFRAME}  |  แท่งสัญญาณเปิด {event['timestamp']}  |  {number}/{total}", font=F[(20, False)], fill=MUTED)
    clock = "เวลา UTC จาก Dukascopy" if TIMEFRAME in ("M15", "M5") else "เวลาตามไฟล์โบรกเกอร์ ไม่ทราบ timezone"
    d.text((48, 106), f"{clock}  เส้นม่วงคือหลังแท่งนี้ปิด", font=F[(18, False)], fill=MUTED)
    bodies = []
    if anchor_a is not None:
        bodies.append((anchor_a, "A"))
    if anchor_b is not None and anchor_b != anchor_a:
        bodies.append((anchor_b, "B"))
    oldest = min([item[0] for item in bodies], default=index)
    split = index - oldest > 144
    arrow = (index, side)
    line = tip if anchor_b is not None else None
    levels = {
        "entry": optional_float(event.get("entry", "")),
        "sl": optional_float(event.get("sl", "")),
        "tp": optional_float(event.get("tp", "")),
    }
    if split:
        paint_pane(image, bars, max(0, oldest - 24), min(len(bars), oldest + 48), (48, 188, 980, 800), bodies, line, arrow, levels)
        paint_pane(image, bars, max(0, index - 72), min(len(bars), index + 51), (1040, 188, 1980, 800), bodies, line, arrow, levels)
        d = ImageDraw.Draw(image)
        d.text((48, 158), "แท่งยืนยันที่อยู่ไกล", font=F[(16, True)], fill=BODY)
        d.text((1040, 158), "แท่ง engulf", font=F[(16, True)], fill=INK)
    else:
        paint_pane(image, bars, max(0, min(oldest, index - 60) - 18), min(len(bars), index + 51), (48, 168, 1980, 800), bodies, line, arrow, levels)
        d = ImageDraw.Draw(image)
    bits = []
    if anchor_a is not None:
        bits.append(f"A: ยืนยัน {event['anchor_a_time']} ({event['anchor_a_kinds']}) เว้น {event['gap_a']} แท่ง หางนำ {lead_wick(bars[anchor_a], side):.0f}%")
    if anchor_b is not None:
        bits.append(f"B: ยืนยัน {event['anchor_b_time']} ({event['anchor_b_kinds']}) เว้น {event['gap_b']} แท่ง ปลายไส้ {tip:.3f} หางนำ {lead_wick(bars[anchor_b], side):.0f}%")
    names = {"TP": "ชน TP", "SL": "ชน SL", "BOTH": "SL และ TP ในแท่งเดียวกัน", "OPEN": "ยังไม่ชน", "NO_TRADE": "เข้าไม่ได้"}
    trade = names.get(event.get("result", ""), "")
    if trade:
        bits.append(f"{trade} ใน {event.get('bars_to_hit', '')} แท่ง  Lot {event.get('lot', '')}")
    d.text((48, 820), "   ".join(bits[:2]), font=F[(18, False)], fill=INK)
    d.text((48, 850), bits[2] if len(bits) > 2 else "", font=F[(18, False)], fill=INK)
    d.text((48, 884), "Entry = Open แท่งถัดไป  SL = ปลายสองแท่ง ± 15 จุด  TP = 1:1  Lot จากทุน 10,000 ความเสี่ยง 1% สัญญา 100 ออนซ์", font=F[(15, False)], fill=MUTED)
    d.text((48, 916), "EMA ไม่ได้กรองสัญญาณ  รูปนี้เป็นการ replay ไม่ใช่ภาพหน้าจอ MT5 และไม่รวม spread", font=F[(16, True)], fill=MUTED)
    path = folder / f"{number:04d}.png"
    image.save(path, compress_level=3)
    return path


def main():
    bars = load_bars()
    events = list(csv.DictReader((OUT / "combo_events.csv").open()))
    folder = OUT / "signals"
    folder.mkdir(exist_ok=True)
    cards = []
    total = len(events)
    for number, event in enumerate(events, start=1):
        path = render(bars, event, number, total, folder)
        cards.append({
            "number": number,
            "image": str(path.relative_to(OUT)),
            "timestamp": event["timestamp"],
            "side": event["side"],
            "pattern": event["pattern"],
            "anchor_a_time": event["anchor_a_time"],
            "anchor_b_time": event["anchor_b_time"],
            "gap_b": event["gap_b"],
        })
        if number % 200 == 0:
            print(f"rendered {number}/{total}", flush=True)
    (OUT / "gallery_manifest.json").write_text(json.dumps(cards, indent=2), encoding="utf-8")
    counts = {
        "signals": total,
        "buy": sum(card["side"] == "BUY" for card in cards),
        "sell": sum(card["side"] == "SELL" for card in cards),
        "A": sum(card["pattern"] == "A" for card in cards),
        "B": sum(card["pattern"] == "B" for card in cards),
        "AB": sum(card["pattern"] == "A+B" for card in cards),
    }
    if TIMEFRAME in ("M15", "M5"):
        period = "2025.09.27 00:00:00 <= open < 2026.09.28 00:00:00 UTC"
        symbol = "XAUUSD"
        note = "Dukascopy bid bars in UTC. 27 Sep 2026 is a Sunday, so the gold session ends on Friday 25 Sep 2026."
        blurb = f"สัญญาณ {total} จุดบน XAUUSD {TIMEFRAME} ตั้งแต่ 27 ก.ย. 2025 ถึงแท่งวันศุกร์ 25 ก.ย. 2026 Entry คือ Open แท่งถัดไป SL เผื่อ 15 จุด TP 1:1"
    else:
        period = "2025.08.05 15:00:00 <= open < 2026.08.05 15:00:00"
        symbol = "XAUUSDm"
        note = "AlgoSpecial file ends 2026.08.05, so this is the available one-year window rather than through 2026.09.27."
        blurb = "สัญญาณ A+B ครบ {total} จุด จาก 5 ส.ค. 2025 เวลา 15:00 ถึงก่อน 5 ส.ค. 2026 เวลา 15:00 ข้อมูลที่มีสิ้นสุด 5 ส.ค. 2026 จึงยังไม่ถึง 27 ก.ย. 2026 ระหว่างแท่งยืนยันกับ engulf มีแท่งคั่นสีสวนแท่งเดียว และเส้นปลายไส้ต้องถึงเนื้อโดยไม่มีแท่งอื่นคร่อม คลิกรูปเพื่อดูขนาดเต็ม".format(total=total)
    (OUT / "summary.json").write_text(json.dumps({
        "indicator": "EngulfImbalanceFlow 1.02",
        "symbol": symbol,
        "timeframe": TIMEFRAME,
        "period": period,
        "data_note": note,
        "defaults": {"lookback_bars": 0, "max_gap_bars": 0, "engulf": "body", "ema_on_chart_only": [20, 50, 200], "point": 0.001,
                     "lead_wick_max": 0.30, "pattern_a_gap": 1, "engulfed_candle": "opposite color",
                     "signal": "A and B together",
                     "pattern_b_path": "first high-low crossing the wick tip must be the confirmation body"},
        "results": counts,
        "images": "signals/0001.png through every signal, chronological",
    }, indent=2) + "\n", encoding="utf-8")
    articles = []
    for card in cards:
        label = f"{card['pattern']} · {card['side']} · {card['timestamp']}"
        articles.append(
            f'<article data-pattern="{html.escape(card["pattern"])}" data-side="{card["side"]}">'
            f'<a href="{card["image"]}" target="_blank"><img loading="lazy" src="{card["image"]}" alt="{html.escape(label)}"></a>'
            f'<p><strong>{html.escape(label)}</strong></p></article>'
        )
    buttons = [("all", f"ทั้งหมด {total}")]
    for key, label in (("A", f"A {counts['A']}"), ("B", f"B {counts['B']}"), ("A+B", f"A+B {counts['AB']}"),
                       ("BUY", f"Buy {counts['buy']}"), ("SELL", f"Sell {counts['sell']}")):
        if not label.endswith(" 0"):
            buttons.append((key, label))
    nav = "".join(f'<button data-filter="{key}" class="{"active" if key=="all" else ""}">{html.escape(label)}</button>' for key, label in buttons)
    page = f'''<!doctype html><html lang="th"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>EngulfImbalanceFlow XAUUSD {TIMEFRAME}</title>
<style>
body{{margin:0;background:#f4f7fb;color:#17273c;font:16px/1.5 system-ui,sans-serif}}
main{{max-width:1500px;margin:auto;padding:28px}}
nav{{display:flex;gap:8px;flex-wrap:wrap;position:sticky;top:0;background:#f4f7fb;padding:12px 0;z-index:2}}
button{{border:1px solid #ced7e3;border-radius:8px;background:white;padding:8px 14px;cursor:pointer;font:inherit}}
button.active{{background:#17273c;color:white}}
.grid{{display:grid;grid-template-columns:1fr 1fr;gap:16px}}
article{{background:white;border:1px solid #dce3ed;border-radius:12px;overflow:hidden}}
img{{width:100%;display:block;background:#eef2f7}}
p{{margin:0;padding:10px 14px 14px}}
article[hidden]{{display:none}}
@media(max-width:900px){{.grid{{grid-template-columns:1fr}}}}
</style><main>
<h1>EngulfImbalanceFlow · {symbol} {TIMEFRAME}</h1>
<p>{blurb}</p>
<nav>{nav}</nav>
<div class="grid">{''.join(articles)}</div>
</main><script>
document.querySelectorAll('button').forEach(button => button.onclick = () => {{
  document.querySelectorAll('button').forEach(item => item.classList.toggle('active', item === button));
  const filter = button.dataset.filter;
  document.querySelectorAll('article').forEach(card => {{
    card.hidden = filter !== 'all' && card.dataset.pattern !== filter && card.dataset.side !== filter;
  }});
}});
</script></html>'''
    (OUT / "gallery.html").write_text(page, encoding="utf-8")
    print(json.dumps({"images": total, "gallery": str(OUT / "gallery.html"), **counts}))


if __name__ == "__main__":
    main()
