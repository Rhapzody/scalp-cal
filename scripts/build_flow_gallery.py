#!/usr/bin/env python3
"""Render diagnostic charts from Luna's source-core replay event CSVs (Pillow).

Usage: python3 scripts/build_flow_gallery.py REPORT_DIR H1_CSV
Charts preserve historical events after fill for explanation; they are not MT5 screenshots.
"""
import csv
import html
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(sys.argv[1]).resolve()
H1 = Path(sys.argv[2]).resolve()
ROOT.mkdir(parents=True, exist_ok=True)
FONT_DIR = Path('/System/Library/Fonts/Supplemental')


def font(size, bold=False):
    path = FONT_DIR / ('Arial Bold.ttf' if bold else 'Arial.ttf')
    if path.exists():
        return ImageFont.truetype(str(path), size)
    return ImageFont.truetype('DejaVuSans.ttf', size)


with H1.open() as f:
    bars = list(csv.DictReader(f))
for bar in bars:
    for k in ('open', 'high', 'low', 'close'):
        bar[k] = float(bar[k])
    bar['timestamp'] = bar.get('timestamp', bar.get('datetime', bar.get('stamp')))
    if not bar['timestamp']:
        raise ValueError('H1 CSV needs timestamp/datetime/stamp column')
bars = [b for b in bars if b['timestamp'] < '2026.08.05 15:00:00']


def load_events(name):
    with (ROOT / name).open() as f:
        rows = list(csv.DictReader(f))
    for row in rows:
        row['index'] = int(row['index'])
        if 'source_index' in row:
            row['source_index'] = int(row['source_index'])
            row['zone_lower'] = float(row['zone_lower'])
            row['zone_upper'] = float(row['zone_upper'])
    return rows


engulf = load_events('engulf_events.csv')
imbalance = load_events('imbalance_events.csv')


def even(rows, count):
    if len(rows) < count:
        raise ValueError(f'Need {count} events; only {len(rows)} available')
    if count == 1:
        return [rows[len(rows) // 2]]
    return [rows[round(j * (len(rows) - 1) / (count - 1))] for j in range(count)]


selected = []
for side in ('BUY', 'SELL'):
    pool = [e for e in engulf if e['side'] == side and e['index'] >= 36 and e['index'] + 24 < len(bars)]
    selected += [dict(e, indicator='Engulf Flow', component='ENGULF') for e in even(pool, 15)]
components = sorted(set(e['component'] for e in imbalance))
if len(components) != 3:
    raise ValueError(f'Expected FVG and two displacement types, got {components}')
for component in components:
    for side in ('BUY', 'SELL'):
        pool = [e for e in imbalance if e['component'] == component and e['side'] == side
                and e['index'] >= 36 and e['index'] + 24 < len(bars)]
        selected += [dict(e, indicator='Imbalance Flow') for e in even(pool, 5)]
selected.sort(key=lambda e: (e['indicator'], e['index'], e['component']))

BG = '#f5f7fb'
INK = '#17273c'
MUTED = '#607084'
BUY = '#168c65'
SELL = '#cc4a55'


def render(event, number):
    i = event['index']
    lo, hi = max(0, i - 36), min(len(bars), i + 25)
    segment = bars[lo:hi]
    img = Image.new('RGB', (1600, 980), BG)
    d = ImageDraw.Draw(img)
    color = BUY if event['side'] == 'BUY' else SELL
    title = f"{event['indicator']}  /  {event['component'].replace('_', ' ')}  /  {event['side']}"
    d.text((56, 34), title, font=font(31, True), fill=INK)
    d.text((56, 80), f"XAUUSDm  |  H1  |  Signal candle opens {event['timestamp']}  |  Example {number:02d}/30",
           font=font(21), fill=MUTED)
    d.text((56, 116), 'Source broker time; timezone unspecified. Signal known only after this candle closes.',
           font=font(19), fill=MUTED)
    left, top, right, bottom = 75, 192, 1480, 738
    ymax = max(b['high'] for b in segment)
    ymin = min(b['low'] for b in segment)
    pad = (ymax - ymin) * 0.12
    ymin -= pad
    ymax += pad
    step = (right - left) / len(segment)

    def x(index):
        return left + (index - lo + 0.5) * step

    def y(price):
        return bottom - (price - ymin) / (ymax - ymin) * (bottom - top)

    d.rectangle((left, top, right, bottom), fill='white')
    boundary = x(i) + step * 0.5
    d.rectangle((boundary, top, right, bottom), fill='#edf1f7')
    for j in range(7):
        price = ymin + (ymax - ymin) * j / 6
        yy = y(price)
        d.line((left, yy, right, yy), fill='#dce3ed', width=1)
        d.text((right + 8, yy - 8), f'{price:.2f}', font=font(16), fill=MUTED)
    fill_index = None
    if event['indicator'] == 'Imbalance Flow':
        lower, upper = event['zone_lower'], event['zone_upper']
        for j in range(i + 1, len(bars)):
            if (event['side'] == 'BUY' and bars[j]['low'] <= lower) or (event['side'] == 'SELL' and bars[j]['high'] >= upper):
                fill_index = j
                break
        source = event['source_index']
        zone_right = min(right, x(fill_index) + step / 2) if fill_index is not None else right
        zone_left = max(left, x(source) - step / 2)
        zone_color = ('#008080' if event['side'] == 'BUY' else '#ff8c00') if 'FVG' not in event['component'] else ('#006400' if event['side'] == 'BUY' else '#800000')
        overlay = Image.new('RGBA', img.size)
        od = ImageDraw.Draw(overlay)
        od.rectangle((zone_left, y(upper), zone_right, y(lower)), fill=zone_color + '32', outline=zone_color, width=3)
        img = Image.alpha_composite(img.convert('RGBA'), overlay).convert('RGB')
        d = ImageDraw.Draw(img)
    for j in range(lo, hi):
        b = bars[j]
        xx = x(j)
        cc = BUY if b['close'] >= b['open'] else SELL
        d.line((xx, y(b['low']), xx, y(b['high'])), fill=cc, width=2)
        y1, y2 = sorted((y(b['open']), y(b['close'])))
        if y2 - y1 < 2:
            y2 = y1 + 2
        d.rectangle((xx - step * .28, y1, xx + step * .28, y2), fill=cc)
    for yy in range(top, bottom, 12):
        d.line((boundary, yy, boundary, min(yy + 6, bottom)), fill='#7d5ac7', width=2)
    d.text((left + 12, top + 12), 'BEFORE SIGNAL', font=font(16, True), fill=MUTED)
    d.text((boundary + 12, top + 12), 'AFTER SIGNAL  /  24 OBSERVED BARS', font=font(16, True), fill=MUTED)
    b = bars[i]
    if event['side'] == 'BUY':
        yy = y(b['low']) + 13
        d.polygon(((x(i), yy), (x(i) - 8, yy + 14), (x(i) + 8, yy + 14)), fill=color)
        d.line((x(i), yy + 13, x(i), yy + 30), fill=color, width=4)
    else:
        yy = y(b['high']) - 13
        d.polygon(((x(i), yy), (x(i) - 8, yy - 14), (x(i) + 8, yy - 14)), fill=color)
        d.line((x(i), yy - 13, x(i), yy - 30), fill=color, width=4)
    for j in range(lo, hi, 10):
        stamp = bars[j]['timestamp']
        d.text((x(j) - 44, bottom + 14), stamp[5:16], font=font(15), fill=MUTED)
    d.text((56, 794), 'WHY THIS EVENT QUALIFIES' if event['indicator'] == 'Engulf Flow' else 'ZONE AND LIFECYCLE', font=font(16, True), fill=MUTED)
    if event['indicator'] == 'Engulf Flow':
        previous = bars[i - 1]
        if event['side'] == 'BUY':
            rule = f"Close {b['close']:.3f} > previous body top {max(previous['open'],previous['close']):.3f}; low {b['low']:.3f} < previous low {previous['low']:.3f}."
        else:
            rule = f"Close {b['close']:.3f} < previous body bottom {min(previous['open'],previous['close']):.3f}; high {b['high']:.3f} > previous high {previous['high']:.3f}."
        subtitle = 'Default BODY + hunt 1; prior-move and EMA filters OFF. Arrow is confirmed, not a 5-second preview.'
    else:
        rule = f"Zone {event['zone_lower']:.3f} - {event['zone_upper']:.3f}; source candle {bars[event['source_index']]['timestamp']}."
        status = f"First full fill: {bars[fill_index]['timestamp']}" if fill_index is not None else 'No full fill observed before dataset end'
        subtitle = status + '. Filled zones are retained here for explanation; MT5 defaults hide them.'
    d.text((56, 824), rule, font=font(20), fill=INK)
    d.text((56, 858), subtitle, font=font(18), fill=MUTED)
    d.text((56, 907), 'Diagnostic reconstruction from MQL5 core replay; not a native MT5 screenshot or an executed trade.',
           font=font(18), fill=MUTED)
    d.text((56, 937), 'Rows use observed bars: weekends / missing hours are not invented. Examples selected without looking at outcomes.',
           font=font(17), fill=MUTED)
    folder = ROOT / ('engulf' if event['indicator'] == 'Engulf Flow' else 'imbalance')
    folder.mkdir(exist_ok=True)
    path = folder / f'{number:02d}.png'
    img.save(path)
    return dict(event, image=str(path.relative_to(ROOT)), first_fill_index=fill_index)


counters = {'Engulf Flow': 0, 'Imbalance Flow': 0}
cards = []
for event in selected:
    counters[event['indicator']] += 1
    cards.append(render(event, counters[event['indicator']]))
(ROOT / 'gallery_manifest.json').write_text(json.dumps(cards, indent=2), encoding='utf-8')
article = []
for e in cards:
    tag = 'engulf' if e['indicator'] == 'Engulf Flow' else 'imbalance'
    article.append(f'''<article data-group="{tag}" data-component="{html.escape(e['component'])}"><a href="{e['image']}" target="_blank"><img loading="lazy" src="{e['image']}" alt="{html.escape(e['indicator']+' '+e['timestamp']+' '+e['side'])}"></a><p><strong>{html.escape(e['indicator'])} · {html.escape(e['component'])} · {e['side']}</strong><br>{e['timestamp']} — คลิกรูปเพื่อดูขนาดเต็ม</p></article>''')
page = '''<!doctype html><html lang="th"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Flow indicators — XAUUSD H1 gallery</title><style>
body{margin:0;background:#f1f4f9;color:#17273c;font:17px/1.65 system-ui,sans-serif}main{max-width:1500px;margin:auto;padding:32px}h1{font-size:32px;line-height:1.2}.intro{max-width:1100px}nav{display:flex;gap:10px;flex-wrap:wrap;margin:24px 0;position:sticky;top:0;background:#f1f4f9;padding:14px 0;z-index:2}button{border:1px solid #ced7e3;border-radius:8px;background:white;color:#17273c;padding:10px 16px;cursor:pointer;font:inherit}button.active{background:#17273c;color:white}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:22px}article{background:white;border:1px solid #dce3ed;border-radius:12px;overflow:hidden}article img{width:100%;display:block}article p{padding:0 18px 10px;font-size:15px}a{color:#166d8d}article[hidden]{display:none}@media(max-width:850px){.grid{grid-template-columns:1fr}main{padding:18px}}
</style><main><h1>Engulf Flow + Imbalance Flow · XAUUSD H1</h1><div class="intro"><p>รูปตัวอย่าง 60 รูป: Engulf 30 และ Imbalance 30 จากการทดสอบค่าเริ่มต้นด้วย source ของโปรเจค โดย Luna max เป็นผู้ทำตัวรันทดสอบ ส่วนกราฟนี้จัดทำจากผล replay</p><p><strong>ช่วงทดสอบ:</strong> 5 ส.ค. 2025 เวลา 15:00 ถึงก่อน 5 ส.ค. 2026 เวลา 15:00 ตามเวลาของไฟล์โบรกเกอร์ (ไม่ทราบ timezone) ใช้ XAUUSDm M30 รวมเป็น H1 เฉพาะชั่วโมงที่ข้อมูลครบ ตัดชั่วโมงสุดท้ายที่ยังยืนยันการปิดไม่ได้ ตามช่วงข้อมูลที่ผู้ใช้อนุมัติ</p><p><strong>วิธีเลือกรูป:</strong> Engulf Buy/Sell อย่างละ 15; Imbalance FVG / แรงส่งแท่งเดี่ยว / แรงส่งหลายแท่ง อย่างละ 10 แบ่ง Buy/Sell อย่างละ 5 เลือกตำแหน่งกระจายตามลำดับเวลาในแต่ละกลุ่มโดยไม่ดูผลลัพธ์ และต้องมีข้อมูลหลังสัญญาณครบ 24 แท่ง สัดส่วนรูปมีไว้เทียบรูปแบบ ไม่ใช่สัดส่วนการเกิดจริง</p><p><strong>วิธีอ่าน:</strong> เส้นม่วงคือหลังแท่งสัญญาณปิด พื้นด้านขวาคือราคาที่เกิดภายหลัง รูป Imbalance คงโซนที่เติมแล้วไว้เพื่ออธิบายเหตุการณ์ แม้ค่าเริ่มต้น MT5 จะซ่อนโซนเหล่านั้น รูปนี้เป็นการวาดจากข้อมูล ไม่ใช่ภาพจับหน้าจอ MT5; ลูกศรบน Imbalance เป็น annotation ของรายงาน</p><p><a href="https://www.algospecial.com/blogs/xauusd-historical-dataset-free-download.php">แหล่งข้อมูล AlgoSpecial</a> · <a href="gallery_manifest.json">รายการรูปและเหตุการณ์</a> · <a href="summary.json">ผลสรุปการทดสอบ</a></p></div><nav><button class="active" data-filter="all">ทั้งหมด 60</button><button data-filter="engulf">Engulf 30</button><button data-filter="imbalance">Imbalance 30</button></nav><div class="grid">''' + '\n'.join(article) + '''</div></main><script>document.querySelectorAll('button').forEach(b=>b.onclick=()=>{document.querySelectorAll('button').forEach(x=>x.classList.toggle('active',x===b));document.querySelectorAll('article').forEach(x=>x.hidden=b.dataset.filter!=='all'&&x.dataset.group!==b.dataset.filter)});</script></html>'''
summary = json.loads((ROOT / 'summary.json').read_text())
results = summary['results']
counts = results['imbalance_components']
stats = f'''<section style="padding:18px 24px;background:white;border:1px solid #dce3ed;border-radius:12px;margin:20px 0"><strong>ผลทดสอบจาก {summary['study_period']['bars']:,} แท่ง H1</strong><ul><li>Engulf: {results['engulf_signal_bars']:,} สัญญาณ — Buy {results['engulf_buy']:,} / Sell {results['engulf_sell']:,}</li><li>Imbalance: FVG {counts['FVG']:,} โซน / แรงส่งแท่งเดี่ยว {counts['DP_SINGLE']:,} / แรงส่งหลายแท่ง {counts['DP_LEG']:,}</li><li>Imbalance เกิดใน {results['imbalance_distinct_signal_bars']:,} แท่ง — บางแท่งมีทั้ง FVG และ Displacement</li></ul><p>ผลนี้นับการตรวจพบจากแท่งปิด ไม่ใช่ผลกำไรหรือ win rate ของกลยุทธ์ และไม่ทดสอบ preview 5 วินาทีของ Engulf ด้วยข้อมูล H1</p></section>'''
page = page.replace('</div><nav>', '</div>' + stats + '<nav>')
(ROOT / 'gallery.html').write_text(page, encoding='utf-8')
print(json.dumps({'gallery': str(ROOT / 'gallery.html'), 'images': counters}))
