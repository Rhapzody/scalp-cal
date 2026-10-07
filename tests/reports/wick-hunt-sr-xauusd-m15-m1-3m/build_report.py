#!/usr/bin/env python3
"""Publish the audited three-month M15/M1 study and its 45 comparison charts."""
from __future__ import annotations

import csv
import hashlib
import html
import json
from collections import Counter
from pathlib import Path

from PIL import Image, ImageDraw

from build_gallery import HERE, MODELS, BG, PANEL, TEXT, MUTED, GREEN, RED, font, read_csv, integer, num, label_time, sha, normalize_trade


def metrics(trades):
    counts=Counter(t['result'] for t in trades)
    closed=[t for t in trades if t['result'] in ('TP','SL')]
    results=[num(t,'r_multiple') for t in closed]
    gains=sum(r for r in results if r>0); losses=-sum(r for r in results if r<0)
    return {"signals":len(trades),**{k:counts[k] for k in ('TP','SL','BOTH','OPEN','INVALID_STOP')},
            "resolved":len(closed),"win_rate_resolved":counts['TP']/len(closed) if closed else None,
            "sum_resolved_R":sum(results),"mean_resolved_R":sum(results)/len(closed) if closed else None,
            "profit_factor_in_R":gains/losses if losses else None,
            "source_gap_exposed":sum(integer(t,'exposed_source_gaps',default=0)>0 for t in trades)}


def nice(v,decimals=2):
    return '—' if v is None else f'{v:,.{decimals}f}'


def table_row(rr,m):
    return [f'1:{rr:g}',f"{m['signals']:,}",f"{m['TP']:,}",f"{m['SL']:,}",
            '—' if m['win_rate_resolved'] is None else f"{m['win_rate_resolved']*100:.2f}%",
            f"{m['sum_resolved_R']:+.2f}R",nice(m['profit_factor_in_R'],3),str(m['BOTH']),str(m['OPEN'])]


def overview(summaries):
    image=Image.new('RGB',(1800,1150),BG); d=ImageDraw.Draw(image)
    d.text((70,35),'XAUUSD · WickHuntSRFlow 1.02 · M15 / M1',fill=TEXT,font=font(38,True))
    d.text((70,93),'2026-06-25 21:00 — 2026-09-25 21:00 UTC · three calendar months',fill=MUTED,font=font(25))
    d.text((70,136),'Fixed spread $0.36 · SL = known M15 wick · same signals at three targets',fill=MUTED,font=font(25))
    for i,(name,rr) in enumerate(MODELS):
        m=summaries[name]; y=215+i*255
        d.rounded_rectangle((60,y,1740,y+225),radius=15,fill=PANEL)
        d.text((88,y+22),f'RR 1:{rr:g}',fill=TEXT,font=font(34,True))
        d.text((390,y+24),f"Win rate {nice(None if m['win_rate_resolved'] is None else m['win_rate_resolved']*100)}%",fill=GREEN,font=font(30,True))
        d.text((950,y+24),f"PF {nice(m['profit_factor_in_R'],3)}",fill=TEXT,font=font(30,True))
        d.text((1300,y+24),f"{m['sum_resolved_R']:+.2f}R",fill=GREEN if m['sum_resolved_R']>=0 else RED,font=font(30,True))
        split=90+1610*m['TP']/max(1,m['resolved'])
        d.rectangle((90,y+91,split,y+135),fill=GREEN)
        d.rectangle((split,y+91,1700,y+135),fill=RED)
        d.text((100,y+97),f"TP {m['TP']:,}",fill=BG,font=font(24,True))
        d.text((max(split+12,1040),y+97),f"SL {m['SL']:,}",fill=BG,font=font(24,True))
        d.text((88,y+165),f"Signals {m['signals']:,}  |  BOTH / unknown {m['BOTH']}  |  still open {m['OPEN']}  |  invalid stop {m['INVALID_STOP']}",fill=MUTED,font=font(23))
    d.text((70,1014),'Win rate / PF / Sum R exclude BOTH, OPEN and invalid stops. Gap fills may lose more than −1R.',fill=MUTED,font=font(22))
    d.text((70,1053),'M1 snapshot approximation; independent overlapping signals, not a portfolio return.',fill=MUTED,font=font(22))
    d.text((70,1092),'No commission, swap or latency slippage. Complete results use every signal; galleries show illustrative cases.',fill=MUTED,font=font(21))
    image.save(HERE/'comparison.png',optimize=True)


def main():
    gallery=json.loads((HERE/'gallery_manifest.json').read_text())
    assert gallery['total_images']==45 and gallery['examples_per_rr']==15
    events=read_csv(HERE/'events.csv')
    audit=json.loads((HERE/'independent-audit.json').read_text())
    assert audit['events_audited']==len(events)
    assert audit['trade_rows_audited']==len(events)*len(MODELS)
    by_id={integer(e,'event_id','number'):e for e in events}
    trades={name:[normalize_trade(t) for t in read_csv(HERE/name/'trades.csv')] for name,_ in MODELS}
    for name,rows in trades.items():
        assert len(rows)==len(events)
        assert {integer(t,'event_id','number') for t in rows}==set(by_id)
    summaries={name:metrics(rows) for name,rows in trades.items()}
    for name,m in summaries.items():
        audited=audit['rr_results'][name]
        assert audited['trades']==m['signals']
        assert all(audited['outcomes'].get(k,0)==m[k] for k in ('TP','SL','BOTH','OPEN','INVALID_STOP'))
    audit_note=f"ตรวจอิสระจากข้อมูลต้นฉบับครบ {audit['events_audited']:,} สัญญาณและ {audit['trade_rows_audited']:,} ผลเทรด ผ่าน {audit['event_invariant_checks_passed']+audit['trade_arithmetic_and_first_hit_checks_passed']:,} checks รวมการยืนยัน swing, trend, touch/FVG, reclaim, SL ที่รู้ขณะเข้า และ first-hit outcome"
    scenario_labels={1:'Breakout เท่านั้น',2:'Pullback เท่านั้น',3:'ผ่านทั้งสองแบบ'}
    scenario_metrics={name:{str(p):metrics([t for t in rows if integer(by_id[integer(t,'event_id','number')],'pattern','scenario')==p])
                           for p in (1,2,3)} for name,rows in trades.items()}
    overview(summaries)
    headers=['R:R','สัญญาณ','TP','SL','Win rate','ผลรวม R','PF','BOTH','ยังเปิด']
    table=[table_row(rr,summaries[name]) for name,rr in MODELS]
    methodology=[
        'ใช้ WickHuntSRFlow v1.02 โหมดรับ Breakout หรือ Pullback (WS_BOTH), TF หลัก M15 / TF รอง M1, MACD Histogram 12/26/9, S/R 10 swing ต่อ TF แบบ Wick; Breakout แตะ S/R ภายใน 5 แท่งและ first-hit strong FVG, Pullback กวาดสองหางตามโครงสร้าง',
        'ช่วง 2026-06-25 21:00 ถึง 2026-09-25 21:00 UTC (ไทย 26 มิ.ย. 04:00 ถึง 26 ก.ย. 04:00): 3 เดือนปฏิทินล่าสุดที่ archive ครอบคลุมเต็ม ไม่ใช่ข้อมูลถึงวันที่ 4 ต.ค.',
        'Spread คงที่ $0.36 ซึ่งตีความคำขอ 36 points บนทองราคา 2 ทศนิยม; Ask = Bid + 0.36 ทุกจุด ไม่ใช้ spread ผันแปรจริงใน archive',
        'เข้า ณ M1 Open แรกหลังแท่ง M1 ปิด break ภายหลัง M15 กลับถึง Open ในแท่ง M15 เดียวกัน; Buy เข้า Ask/ออก Bid, Sell เข้า Bid/ออก Ask',
        'SL Buy = Bid low ของ M15 ที่รู้ ณ เวลาเข้า; SL Sell = Ask high ที่รู้ ณ เวลาเข้า (= known Bid high + 0.36); ไม่ใช้ไส้สุดท้ายของ M15 ที่กำลังวิ่ง และไม่มี buffer เพิ่ม',
        'TP จากราคาเข้าจริง ห่างเท่ากับระยะ entry-to-SL คูณ 1 / 1.5 / 2 ถือจนแตะ TP/SL หรือจบช่วงทดสอบ ไม่ย้าย SL/TP และไม่ปิดตามแท่ง M15',
        'ทดสอบ Open ก่อน High/Low: SL gap เติมที่ Open, TP limit เติมที่เป้า; ถ้า High/Low แตะทั้ง SL และ TP ภายใน M1 และ Open ยังไม่แตะ แยกเป็น BOTH ไม่เดาลำดับ',
        'ตัวเลขหลักไม่นับ BOTH, OPEN และ invalid stop; มีผลแบบ pessimistic/optimistic และข้อมูล gap exposure ในผลจาก Luna; ไม่รวม commission, swap หรือ latency slippage',
        'ใช้ข้อมูล M1 OHLC จึงประมาณลำดับ reclaim ด้วย M1 Open และ Close ที่ :59 ไม่ใช่ tick replay / MT5 Strategy Tester เวลา exit ภายในแท่งเป็นเพียง M1 bucket',
        'M15 ที่ปิดแต่ข้อมูลไม่ครบจะไม่ถูกใช้เป็นบริบท และ reset higher-TF engine/reference เพื่อกัน partial OHLC เปลี่ยน trend/FVG; ไม่เติมราคาที่ขาดหาย',
        'ทุกสัญญาณประเมินแยกกัน อาจซ้อนกันได้ ผลรวม R เป็นผลรวมผลลัพธ์สัญญาณ ไม่ใช่กำไรบัญชีหรือ equity curve',
        'ภาพใช้ 15 สัญญาณเดียวกันเปรียบเทียบทั้งสาม R:R รวม 45 ภาพ เลือกตามลำดับเวลาสลับกลุ่มสถานการณ์/Buy-Sell/เดือน เฉพาะเคสที่ปิดได้ครบทั้งสามแบบภายใน 480 M1 observations; ภาพเป็นตัวอย่าง ไม่แทนสัดส่วนผลลัพธ์ทั้งหมด',
        'ในภาพ แท่ง M15 สีคือ final OHLC ส่วนกรอบขาวคือข้อมูลที่รู้ตอนสัญญาณ แท่งหลังสัญญาณและ MACD หลังสัญญาณใช้ดูบริบทผลลัพธ์เท่านั้น'
    ]
    md=['# WickHuntSRFlow 1.02 — ทอง M15/M1 · 3 เดือน','',
        'Luna Max ทดสอบ R:R 1:1, 1:1.5 และ 1:2 ด้วย spread คงที่ $0.36 และ SL ปลายหาง M15 ที่รู้ตอนสัญญาณ','',
        '| '+' | '.join(headers)+' |','|'+'|'.join(['---']+['---:']*(len(headers)-1))+'|']
    md.extend('| '+' | '.join(row)+' |' for row in table)
    md += ['', '## สัญญาณแยกสถานการณ์', '', '| สถานการณ์ | Buy | Sell | รวม |','|---|---:|---:|---:|']
    for p,label in ((1,'Breakout เท่านั้น'),(2,'Pullback เท่านั้น'),(3,'ผ่านทั้งสองแบบ')):
        rows=[e for e in events if integer(e,'pattern','scenario')==p]
        buy=sum(str(e['direction']).upper() in ('BUY','1') for e in rows)
        md.append(f'| {label} | {buy:,} | {len(rows)-buy:,} | {len(rows):,} |')
    md += ['', '## ผลแยกสถานการณ์ (กลุ่มไม่ซ้ำกัน)', '',
           '| R:R | สถานการณ์ | สัญญาณ | Win rate | ผลรวม R | PF |', '|---|---|---:|---:|---:|---:|']
    scenario_table=[]
    for name,rr in MODELS:
        for p,label in scenario_labels.items():
            m=scenario_metrics[name][str(p)]
            row=[f'1:{rr:g}',label,str(m['signals']),f"{m['win_rate_resolved']*100:.2f}%" if m['win_rate_resolved'] is not None else '—',
                 f"{m['sum_resolved_R']:+.2f}R",nice(m['profit_factor_in_R'],3)]
            scenario_table.append(row); md.append('| '+' | '.join(row)+' |')
    md += ['', '## วิธีทดสอบและขอบเขต', '', *['- '+text for text in methodology], '',
           '## การตรวจสอบ', '', audit_note, '', '[ผลตรวจอิสระ](independent-audit.json) · [รายละเอียด replay และ source hashes](summary.json)', '',
           '## รายงานและภาพตัวอย่าง', '', '[เปิดรายงานพร้อมภาพ 45 รูป](index.html) · [ภาพสรุป](comparison.png)', '']
    for name,rr in MODELS:
        md.append(f'- R:R 1:{rr:g}: [ทุกเทรด]({name}/trades.csv) · [ผลสรุป Luna]({name}/summary.json) · [15 ภาพ](index.html#{name})')
    md += ['', '## ทำซ้ำ', '', '```sh',
           f'python3 tests/reports/{HERE.name}/run_study.py',
           f'python3 tests/reports/{HERE.name}/audit_study.py',
           f'python3 tests/reports/{HERE.name}/build_gallery.py',
           f'python3 tests/reports/{HERE.name}/build_report.py', '```', '']
    (HERE/'README.md').write_text('\n'.join(md))
    css='body{background:#0b1019;color:#e7edf4;font:17px Arial,sans-serif;max-width:1600px;margin:30px auto;padding:0 24px;line-height:1.65}a{color:#60d5ff}table{border-collapse:collapse;width:100%}td,th{padding:10px;border-bottom:1px solid #293546;text-align:left}img{width:100%;height:auto}button{background:#182538;color:#e7edf4;border:1px solid #60d5ff;border-radius:8px;padding:12px 24px;margin:8px;cursor:pointer}button.active{background:#265b7e}figure{margin:30px 0 60px}figcaption,li,p{color:#aab9ca}.tabs{position:sticky;top:0;background:#0b1019;z-index:2;padding:8px}details{margin:24px 0}'
    page=['<!doctype html><html lang="th"><meta charset="utf-8"><title>ทอง M15/M1 — สาม R:R</title><style>'+css+'</style>',
          '<h1>ทอง M15/M1 · WickHuntSRFlow v1.02 · Luna Max</h1>',
          '<p>25 มิ.ย.–25 ก.ย. 2026 เวลา 21:00 UTC · spread $0.36 · SL ไส้ M15 ที่รู้ตอนสัญญาณ</p>',
          '<img src="comparison.png" alt="ผลสรุปสาม R:R">',
          '<table><tr>'+''.join('<th>'+html.escape(h)+'</th>' for h in headers)+'</tr>']
    page.extend('<tr>'+''.join('<td>'+html.escape(x)+'</td>' for x in row)+'</tr>' for row in table)
    page += ['</table><details><summary>ผลแยก Breakout / Pullback / ผ่านทั้งคู่ (กลุ่มไม่ซ้ำกัน)</summary><table><tr>'+''.join('<th>'+h+'</th>' for h in ['R:R','สถานการณ์','สัญญาณ','Win rate','ผลรวม R','PF'])+'</tr>'+''.join('<tr>'+''.join('<td>'+html.escape(x)+'</td>' for x in row)+'</tr>' for row in scenario_table)+'</table></details>',
             '<details><summary>วิธีทดสอบและข้อจำกัด</summary><ul>'+''.join('<li>'+html.escape(x)+'</li>' for x in methodology)+'</ul></details>',
             '<p>'+html.escape(audit_note)+' · <a href="independent-audit.json">ผลตรวจอิสระ</a> · <a href="summary.json">Replay และ source hashes</a></p>',
             '<h2>15 เคสเดียวกัน เทียบเป้าสามแบบ</h2><p>รูปละ M15 zoom out + M1 หลัง break + TV MACD; กดภาพเพื่อเปิดขนาดเต็ม</p>', '<div class="tabs">']
    for name,rr in MODELS:
        page.append(f'<button data-model="{name}" onclick="showModel(\'{name}\')">R:R 1:{rr:g}</button>')
    page.append('</div>')
    for name,rr in MODELS:
        examples=[e for e in gallery['examples'] if e['rr']==rr]
        assert len(examples)==15 and all(e['exit_visible'] for e in examples)
        page.append(f'<section id="{name}" class="model"><h2>R:R 1:{rr:g} — 15 รูป</h2><p><a href="{name}/trades.csv">ทุกเทรด CSV</a> · <a href="{name}/summary.json">ผลสรุป Luna</a></p>')
        for e in examples:
            caption=f"#{e['number']:02d} · Event {e['event_id']} · {e['direction']} · {e['result']} {e['r_multiple']:+.2f}R · {label_time(e['event_epoch'],True)} UTC"
            file=html.escape(e['file'])
            page.append(f'<figure><a href="{file}"><img loading="lazy" src="{file}" alt="{html.escape(caption)}"></a><figcaption>{html.escape(caption)}</figcaption></figure>')
        page.append('</section>')
    page.append('<p><a href="README.md">รายละเอียดและวิธีทำซ้ำ</a> · <a href="gallery_manifest.json">รายการภาพและ hashes</a></p>')
    page.append("<script>function showModel(id){document.querySelectorAll('.model').forEach(s=>s.hidden=s.id!==id);document.querySelectorAll('button[data-model]').forEach(b=>b.classList.toggle('active',b.dataset.model===id));history.replaceState(null,'','#'+id)}showModel(['rr-1','rr-1_5','rr-2'].includes(location.hash.slice(1))?location.hash.slice(1):'rr-1')</script></html>")
    (HERE/'index.html').write_text('\n'.join(page))
    summary={"indicator":"WickHuntSRFlow 1.02","symbol":"XAUUSD","higher_tf":"M15","lower_tf":"M1",
             "fixed_spread_price":.36,"stop":"known executable-side M15 wick at signal","models":summaries,"by_scenario":scenario_metrics,
             "gallery_count":45,"gallery_signals":15,"methodology":methodology,
             "independent_audit":audit,"independent_audit_sha256":sha(HERE/'independent-audit.json'),
             "report_sha256":{p.name:sha(p) for p in (HERE/'events.csv',HERE/'gallery_manifest.json',HERE/'comparison.png',HERE/'index.html',HERE/'README.md')}}
    (HERE/'report_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(summaries,indent=2))


if __name__=='__main__':
    main()
