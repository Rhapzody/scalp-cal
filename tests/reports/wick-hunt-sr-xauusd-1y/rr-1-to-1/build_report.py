#!/usr/bin/env python3
"""Render the two audited RR 1:1 models and the case discussed in the conversation."""
import csv
import hashlib
import html
import importlib.util
import json
from pathlib import Path

from PIL import Image, ImageDraw
from run_rr import HERE, REPORT, sha, stamp

spec = importlib.util.spec_from_file_location('wick_charts', REPORT / 'build_gallery.py')
charts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(charts)
font = charts.font
BG, PANEL, TEXT, MUTED = charts.BG, charts.PANEL, charts.TEXT, charts.MUTED
WIN, LOSS = '#38c889', '#ee6675'


def read(path):
    with path.open() as handle:
        return list(csv.DictReader(handle))


def overview(models):
    image = Image.new('RGB', (1600, 880), BG)
    d = ImageDraw.Draw(image)
    d.text((65, 40), 'XAUUSD · WickHuntSRFlow 1.01 · R:R 1:1', fill=TEXT, font=font(36, True))
    d.text((65, 94), '365 days · 2025-09-25 21:00 — 2026-09-25 21:00 UTC · 2,410 signals', fill=MUTED, font=font(23))
    d.text((65, 132), 'Bid/Ask spread included · each signal assessed independently · no commission / swap', fill=MUTED, font=font(21))
    for i, (mode, summary) in enumerate(models.items()):
        m = summary['overall']
        y = 205 + i * 265
        d.rounded_rectangle((55, y, 1545, y + 235), radius=14, fill=PANEL)
        label = 'SL = observed H1 wick at signal' if mode == 'h1' else 'SL = closed breakout M5 wick'
        d.text((80, y + 20), label, fill=TEXT, font=font(29, True))
        d.text((80, y + 70), f"Win rate {m['win_rate_resolved'] * 100:.2f}%", fill=WIN, font=font(29, True))
        d.text((550, y + 70), f"PF {m['profit_factor_in_R']:.3f}", fill=TEXT, font=font(29, True))
        d.text((920, y + 70), f"Sum closed outcomes {m['sum_resolved_R']:+.2f}R", fill=LOSS, font=font(29, True))
        left, right, by = 80, 1520, y + 129
        split = left + (right-left) * m['TP'] / m['resolved']
        d.rectangle((left, by, split, by + 38), fill=WIN)
        d.rectangle((split, by, right, by + 38), fill=LOSS)
        d.text((left + 12, by + 6), f"TP {m['TP']:,}", fill=BG, font=font(23, True))
        d.text((split + 12, by + 6), f"SL {m['SL']:,}", fill=BG, font=font(23, True))
        d.text((80, y + 188), f"Both touched / unknown: {m['BOTH']}  |  Still open at study end: {m['OPEN']}  |  Median exit: {m['median_observed_minutes_to_exit']} observed M1 bars", fill=MUTED, font=font(21))
    d.text((65, 770), 'Win rate and Sum R exclude BOTH and still-open trades. Gap stop fills may lose more than 1R.', fill=MUTED, font=font(21))
    d.text((65, 812), 'M1 snapshot approximation · overlapping signal outcomes are not portfolio returns.', fill=MUTED, font=font(21))
    image.save(HERE / 'comparison.png', optimize=True)


def case_chart(mode, trade, bars, macd):
    # The requested example: the first Buy/Swing H at 05:40 UTC.
    charts.WIDTH = 1800
    entry_t = int(trade['entry_epoch'])
    breakout = int(trade['breakout_epoch'])
    break_index = next(i for i, b in enumerate(bars) if int(b['epoch']) == breakout)
    view = bars[max(0, break_index - 23):break_index + 13]
    entry, stop, target = (float(trade[k]) for k in ('entry', 'stop', 'target'))
    vals = [float(b[k]) for b in view for k in ('low', 'high')] + [entry, stop, target]
    padding = max((max(vals)-min(vals))*.1, .25)
    lo, hi = min(vals)-padding, max(vals)+padding
    img = Image.new('RGB', (1800, 1200), BG)
    d = ImageDraw.Draw(img)
    d.text((70, 30), f"Discussed BUY case · RR 1:1 · SL {mode.upper()} · {trade['result']} {float(trade['r_multiple']):+.0f}R", fill=TEXT, font=font(32, True))
    d.text((70, 77), f"Entry Ask {entry:.3f} at 05:40 UTC · SL {stop:.3f} · TP {target:.3f} · spread {float(trade['entry_spread']):.3f}", fill=MUTED, font=font(21))
    d.text((70, 110), f"Exit observed in M1 {trade['exit_time_utc']} · M5 price candles use Bid · exits use Bid for this Buy", fill=MUTED, font=font(18))
    left, right = 105, 1680
    spacing = (right-left-50)/max(1,len(view)-1)
    xs = [left+25+i*spacing for i in range(len(view))]
    times = [int(b['epoch']) for b in view]
    def x(t):
        import bisect
        i = max(0, bisect.bisect_right(times, t)-1)
        return xs[i]+min((t-times[i])/300, 1)*spacing
    top, bottom = 160, 780
    charts.draw_candles(d, view, xs, (lo,hi), top, bottom, 20, 'M5 · 24 bars through breakout + 12 following bars', plot_top_offset=72)
    def y(v): return charts.price_y(v,lo,hi,top+72,bottom-28)
    for name, value, color in (('ENTRY ASK',entry,TEXT),('SL',stop,LOSS),('TP',target,WIN)):
        py = y(value)
        d.line((x(entry_t),py,right,py),fill=color,width=2)
        label = f'{name} {value:.3f}'
        width = d.textbbox((0,0),label,font=font(18,True))[2]
        d.text((right-width-10,py-25),label,fill=color,font=font(18,True))
    exit_t = int(trade['exit_epoch'])
    markers = [(entry_t,'entry',TEXT,2),(exit_t,'exit M1 bucket',LOSS,2)]
    for t,label,color,width in markers:
        px = x(t)
        d.line((px,top+72,px,bottom-28),fill=color,width=width)
        d.text((px+6,top+42),label,fill=color,font=font(17,True))
    d.ellipse((x(entry_t)-7,y(entry)-7,x(entry_t)+7,y(entry)+7),fill=TEXT,outline=BG,width=2)
    d.ellipse((x(exit_t)-7,y(stop)-7,x(exit_t)+7,y(stop)+7),fill=LOSS,outline=BG,width=2)
    charts.draw_macd(d, view, xs, macd, 820, 1140, markers, x, 20)
    d.text((70,1160), 'SL uses the wick already known at signal, not the final H1 low. Exit minute is an OHLC bucket, not exact tick time.', fill=MUTED,font=font(17))
    img.save(HERE / f'case-sl-{mode}.png', optimize=True)


def main():
    models = {}
    discussed = {}
    for mode in ('h1','m5'):
        directory = HERE / f'sl-{mode}'
        summary = json.loads((directory/'summary.json').read_text())
        audit = json.loads((directory/'independent-audit.json').read_text())
        assert audit['audited_trades'] == summary['overall']['signals']
        for name, digest in summary['artifacts_sha256'].items():
            assert sha(directory/name) == digest
        summary['independent_audit'] = audit
        summary['artifacts_sha256']['independent-audit.json'] = sha(directory/'independent-audit.json')
        (directory/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
        models[mode] = summary
        discussed[mode] = next(t for t in read(directory/'trades.csv') if t['signal_time_utc']=='2025-09-26 05:40:00 UTC' and t['direction']=='BUY')
    overview(models)
    macd = {int(r['epoch']): {k:float(r[k]) for k in ('macd','signal','histogram','color_index')} for r in read(REPORT/'m5_macd.csv')}
    expected = json.loads((REPORT/'gallery_manifest.json').read_text())['view']['macd']['series_sha256']
    assert sha(REPORT/'m5_macd.csv') == expected
    bars = read(REPORT/'m5_bars.csv')
    for mode in models:
        case_chart(mode,discussed[mode],bars,macd)
    markdown = ['# WickHuntSRFlow 1.01 — XAUUSD R:R 1:1', '',
                'ทดสอบ 365 วัน: 2025-09-25 21:00 ถึง 2026-09-25 21:00 UTC ใช้สัญญาณ 2,410 เหตุการณ์เดิม ทุกสัญญาณประเมินแยกกัน รวมกรณี Buy/Sell ใน H1 เดียวกัน จึงไม่ใช่ผลตอบแทนพอร์ต', '',
                '| SL | TP | SL | Win rate | ผลรวม R ที่ปิดแล้ว | PF ในหน่วย R | BOTH | ยังเปิด |',
                '|---|---:|---:|---:|---:|---:|---:|---:|']
    html_rows = []
    for mode, s in models.items():
        m = s['overall']
        label = 'wick H1 ณ สัญญาณ' if mode=='h1' else 'wick M5 ที่ปิด break'
        fields = [label,f"{m['TP']:,}",f"{m['SL']:,}",f"{m['win_rate_resolved']*100:.2f}%",f"{m['sum_resolved_R']:+.2f}R",f"{m['profit_factor_in_R']:.3f}",str(m['BOTH']),str(m['OPEN'])]
        markdown.append('| '+' | '.join(fields)+' |')
        html_rows.append('<tr>'+''.join(f'<td>{html.escape(x)}</td>' for x in fields)+'</tr>')
    methodology = [
        'เข้า ณ M1 Open แรกที่ตรวจพบสัญญาณหลัง M5 ปิด break สมมติ latency เป็นศูนย์ Buy เข้า Ask / ออก Bid; Sell เข้า Bid / ออก Ask รวม spread จริงจากชุดข้อมูล',
        'SL Buy ใช้ Low ของ Bid ส่วน SL Sell ใช้ High ของ Ask ซึ่งเป็นราคาปิดสถานะ Sell ไม่เติม buffer จุดอื่น รุ่น H1 ใช้เฉพาะไส้ที่รู้ ณ สัญญาณ ไม่ใช้ High/Low สุดท้ายของ H1; รุ่น M5 ใช้แท่ง breakout ที่ปิดแล้ว',
        'TP ห่างจากราคาเข้าจริงเท่ากับระยะ SL อัตรา 1:1 ถือจนแตะ TP/SL หรือสิ้นช่วงทดสอบ ไม่ปิดตาม H1 และไม่ย้าย SL/TP',
        'กรณี Open กระโดดเลย SL เติมที่ราคา Open ทำให้บางครั้งขาดทุนเกิน -1R; TP limit เติมที่เป้า กรณี M1 แตะทั้งสองระดับแต่ Open ยังไม่แตะจะแยกเป็น BOTH ไม่เดาลำดับ',
        'Win rate/PF/ผลรวม R หลักไม่นับ BOTH และสถานะที่ยังเปิด ไม่รวม commission, swap และ slippage จาก latency; รายงาน sensitivity กรณี BOTH เป็น SL/TP และ subset ที่ไม่ผ่านช่องว่างข้อมูลไว้ใน summary.json',
        'สัญญาณเป็น M1 snapshot approximation ไม่ใช่ tick replay หรือ MT5 Strategy Tester; เวลา exit ในแท่งคือ label M1 และข้อมูลที่ขาดหายไม่ถูกเติมราคา',
        'ประเมินแต่ละสัญญาณแยกกัน สามารถซ้อนกันได้ ผลรวม R เป็นผลรวมผลลัพธ์สัญญาณ ไม่ใช่ equity curve หรือ % ผลตอบแทนบัญชี'
    ]
    markdown += ['', '## วิธีทดสอบ', '', *['- '+x for x in methodology], '', '## เคส Buy ที่คุยกัน เวลา 05:40 UTC วันที่ 2025-09-26', '']
    for mode, t in discussed.items():
        markdown.append(f"- SL {mode.upper()}: เข้า Ask {float(t['entry']):.3f}, SL {float(t['stop']):.3f}, TP {float(t['target']):.3f}; ผล SL -1R ใน M1 {t['exit_time_utc']}")
    markdown += ['', '## ผลตรวจและไฟล์', '']
    for mode,s in models.items():
        audit=s['independent_audit']
        markdown.append(f"- SL {mode.upper()}: {audit['audited_trades']:,} trades / {audit['checks_passed']:,} raw-data audit checks ผ่าน; [trades.csv](sl-{mode}/trades.csv), [summary.json](sl-{mode}/summary.json), [monthly.csv](sl-{mode}/monthly.csv)")
    markdown += ['', '[รายงานพร้อมภาพ](index.html) · [ภาพเปรียบเทียบ](comparison.png)', '', '## ทำซ้ำ', '', '```sh']
    for mode in ('h1','m5'):
        markdown += [f'python3 tests/reports/wick-hunt-sr-xauusd-1y/rr-1-to-1/run_rr.py --stop {mode}',f'python3 tests/reports/wick-hunt-sr-xauusd-1y/rr-1-to-1/verify_rr.py --stop {mode}']
    markdown += ['python3 tests/reports/wick-hunt-sr-xauusd-1y/rr-1-to-1/build_report.py','```','']
    (HERE/'README.md').write_text('\n'.join(markdown))
    page = '''<!doctype html><html lang="th"><meta charset="utf-8"><title>WickHuntSRFlow RR 1:1</title>
<style>body{background:#0b1019;color:#e7edf4;font:17px Arial,sans-serif;margin:32px auto;max-width:1600px;padding:0 24px;line-height:1.6}a{color:#60d5ff}img{max-width:100%;height:auto}table{border-collapse:collapse;width:100%}th,td{padding:12px;border-bottom:1px solid #293546;text-align:left}li,p{color:#aab9ca}figure{margin:32px 0}</style>
<h1>WickHuntSRFlow 1.01 — ทอง 365 วัน · R:R 1:1</h1>
<p>2025-09-25 21:00 ถึง 2026-09-25 21:00 UTC · 2,410 สัญญาณจากกฎปัจจุบัน · เปรียบเทียบ SL สองแบบ</p>
<img src="comparison.png" alt="Comparison of audited RR models">
<table><tr><th>SL</th><th>TP</th><th>SL</th><th>Win rate</th><th>ผลรวม R</th><th>PF (R)</th><th>BOTH</th><th>ยังเปิด</th></tr>'''+''.join(html_rows)+'</table><h2>วิธีทดสอบ</h2><ul>'+''.join('<li>'+html.escape(x)+'</li>' for x in methodology)+'</ul>'
    page += '<h2>เคส Buy 05:40 UTC วันที่ 2025-09-26</h2>'
    for mode in models:
        page += f'<figure><a href="case-sl-{mode}.png"><img src="case-sl-{mode}.png" alt="Discussed case with SL {mode}"></a><figcaption>SL {mode.upper()} · แท่งหลังสัญญาณใช้เพื่อดูผลลัพธ์</figcaption></figure>'
        page += f'<p>SL {mode.upper()}: <a href="sl-{mode}/trades.csv">ทุกเทรด CSV</a> · <a href="sl-{mode}/summary.json">ผลสรุปและ audit</a> · <a href="sl-{mode}/monthly.csv">แยกเดือน</a></p>'
    page += '<p><a href="README.md">วิธีทำซ้ำและข้อจำกัด</a></p></html>'
    (HERE/'index.html').write_text(page)
    print('Wrote report, comparison.png and two discussed-case charts.')


if __name__=='__main__':
    main()
