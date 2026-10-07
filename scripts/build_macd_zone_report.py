#!/usr/bin/env python3
"""Render the MACDZoneTrader replay audit as a Thai-friendly HTML gallery."""
import csv
import html
import os
import shutil
import sys
from datetime import datetime, timezone


def esc(x):
    return html.escape(str(x), quote=True)


def read_bars(path):
    out = []
    with open(path, newline="") as f:
        for r in csv.DictReader(f):
            t = int(r["timestamp"]) // 1000
            out.append({"t": t, "o": float(r["open"]), "h": float(r["high"]), "l": float(r["low"]), "c": float(r["close"])})
    return out


def read_audit(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def dt(t):
    return datetime.fromtimestamp(int(t), timezone.utc).strftime("%Y-%m-%d %H:%M")


def chart_svg(m1, m5, trade, number, out_path):
    signal_t = int(datetime.strptime(trade["signal_time"], "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc).timestamp())
    entry_t = int(datetime.strptime(trade["entry_time"], "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc).timestamp())
    exit_t = int(datetime.strptime(trade["exit_time"], "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc).timestamp())
    m5_times = [b["t"] for b in m5]
    m1_times = [b["t"] for b in m1]
    m5i = max(0, next((i for i, t in enumerate(m5_times) if t >= signal_t), len(m5)-1))
    m1i = max(0, next((i for i, t in enumerate(m1_times) if t >= signal_t), len(m1)-1))
    m5_start, m5_end = max(0, m5i - 28), min(len(m5), m5i + 38)
    m1_end_time = max(exit_t, entry_t + 30 * 60)
    m1_start, m1_end = max(0, m1i - 30), min(len(m1), next((i for i, t in enumerate(m1_times) if t > m1_end_time), len(m1)))
    m5v, m1v = m5[m5_start:m5_end], m1[m1_start:m1_end]
    vals = [v for b in m5v for v in (b["h"], b["l"])] + [float(trade[k]) for k in ("entry", "broker_sl", "broker_tp", "zone_low", "zone_high")]
    lo, hi = min(vals), max(vals); margin = max(0.10 * (hi-lo), 0.5); lo -= margin; hi += margin
    W, H = 1200, 820; L, R = 82, 28; top, main_bottom = 60, 515; m1_top, m1_bottom = 575, 735
    plot_w = W-L-R; step5 = plot_w/max(1,len(m5v)); step1 = plot_w/max(1,len(m1v))
    def y(p): return top+(hi-p)/(hi-lo)*(main_bottom-top)
    def x5(j): return L+(j+.5)*step5
    def x1(j): return L+(j+.5)*step1
    def line(x1_,y1,x2,y2,color,w=1,dash=""):
        return f'<line x1="{x1_:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{color}" stroke-width="{w}"' + (f' stroke-dasharray="{dash}"' if dash else '') + '/>'
    parts=[f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" role="img" aria-label="MACDZoneTrader trade {number}">', '<rect width="100%" height="100%" fill="#0b1020"/>',
           f'<text x="{L}" y="28" fill="#f5f7fb" font-size="20" font-family="Arial" font-weight="700">MACDZoneTrader · trade {number} · {esc(trade["side"])}</text>',
           f'<text x="{L}" y="47" fill="#9aa8bd" font-size="12" font-family="Arial">XAUUSD · M5 zone + M1 confirmation · signal {esc(trade["signal_time"])} UTC</text>']
    for g in range(6):
        yy=top+g*(main_bottom-top)/5; pp=hi-g*(hi-lo)/5
        parts.append(line(L,yy,W-R,yy,"#25334a")); parts.append(f'<text x="{L-8}" y="{yy+4:.1f}" text-anchor="end" fill="#8fa0b8" font-size="11" font-family="Arial">{pp:.2f}</text>')
    zlo,zhi=float(trade["zone_low"]),float(trade["zone_high"]); zx=x5(max(0,m5i-m5_start-2))
    parts.append(f'<rect x="{zx:.1f}" y="{y(zhi):.1f}" width="{W-R-zx:.1f}" height="{max(2,y(zlo)-y(zhi)):.1f}" fill="#eab308" fill-opacity="0.16" stroke="#eab308" stroke-dasharray="5 4"/>')
    parts.append(f'<text x="{zx+7:.1f}" y="{y(zhi)-6:.1f}" fill="#f7d46b" font-size="11" font-family="Arial">M5 SR / zone</text>')
    colors={"entry":"#f8fafc","broker_sl":"#fb7185","broker_tp":"#4ade80"}; labels={"entry":"ENTRY","broker_sl":"SL + spread buffer","broker_tp":"TP / confirmed swing"}
    for key in ("entry","broker_sl","broker_tp"):
        yy=y(float(trade[key])); parts.append(line(L,yy,W-R,yy,colors[key],2,"8 5")); parts.append(f'<text x="{W-R-7}" y="{yy-5:.1f}" text-anchor="end" fill="{colors[key]}" font-size="11" font-family="Arial" font-weight="700">{labels[key]} {float(trade[key]):.2f}</text>')
    cw=max(3,min(13,step5*.65))
    for j,b in enumerate(m5v):
        col="#39d98a" if b["c"]>=b["o"] else "#ff647c"; xx=x5(j)
        parts.append(line(xx,y(b["h"]),xx,y(b["l"]),col,1.3)); parts.append(f'<rect x="{xx-cw/2:.1f}" y="{min(y(b["o"]),y(b["c"])):.1f}" width="{cw:.1f}" height="{max(1.3,abs(y(b["c"])-y(b["o"]))):.1f}" fill="{col}"/>')
    # M1 panel is intentionally compact; it shows the reversal pattern that set SL.
    parts.append(f'<line x1="{L}" y1="{m1_top-18}" x2="{W-R}" y2="{m1_top-18}" stroke="#394b6a"/>')
    parts.append(f'<text x="{L}" y="{m1_top-28}" fill="#9aa8bd" font-size="11" font-family="Arial">M1 closed candles · pattern range {float(trade["pattern_low"]):.2f}–{float(trade["pattern_high"]):.2f}</text>')
    m1vals=[v for b in m1v for v in (b["h"],b["l"])] + [float(trade["entry"]),float(trade["broker_sl"]),float(trade["broker_tp"]),float(trade["pattern_low"]),float(trade["pattern_high"])]
    mlo,mhi=min(m1vals),max(m1vals); mm=max(.12*(mhi-mlo),.25); mlo-=mm; mhi+=mm
    def ym(p): return m1_top+(mhi-p)/(mhi-mlo)*(m1_bottom-m1_top)
    px=max(0,next((i for i,b in enumerate(m1v) if b["t"]>=entry_t),len(m1v)-1)); sx=max(0,next((i for i,b in enumerate(m1v) if b["t"]>=signal_t),len(m1v)-1)); ex=max(0,next((i for i,b in enumerate(m1v) if b["t"]>=exit_t),len(m1v)-1))
    pat0=max(0,sx-2); pat1=min(len(m1v)-1,px+1)
    parts.append(f'<rect x="{x1(pat0):.1f}" y="{ym(float(trade["pattern_high"])):.1f}" width="{max(2,x1(pat1)-x1(pat0)):.1f}" height="{max(2,ym(float(trade["pattern_low"]))-ym(float(trade["pattern_high"]))):.1f}" fill="#a855f7" fill-opacity="0.16" stroke="#c084fc" stroke-dasharray="4 3"/>')
    cw1=max(2,min(7,step1*.7))
    for j,b in enumerate(m1v):
        col="#39d98a" if b["c"]>=b["o"] else "#ff647c"; xx=x1(j)
        parts.append(f'<line x1="{xx:.1f}" y1="{ym(b["h"]):.1f}" x2="{xx:.1f}" y2="{ym(b["l"]):.1f}" stroke="{col}" stroke-width="1"/>')
        parts.append(f'<rect x="{xx-cw1/2:.1f}" y="{min(ym(b["o"]),ym(b["c"])):.1f}" width="{cw1:.1f}" height="{max(1,abs(ym(b["c"])-ym(b["o"]))):.1f}" fill="{col}"/>')
    for xx,label,col,ly in ((x1(sx),"M1 signal","#f7d46b",m1_top+10),(x1(px),"entry","#f8fafc",m1_top+24),(x1(ex),"exit","#38bdf8",m1_top+10)):
        parts.append(f'<line x1="{xx:.1f}" y1="{m1_top-5}" x2="{xx:.1f}" y2="{m1_bottom+4}" stroke="{col}" stroke-dasharray="3 3"/>')
        parts.append(f'<text x="{xx+4:.1f}" y="{ly}" fill="{col}" font-size="10" font-family="Arial">{label}</text>')
    result=trade["result"]; col="#4ade80" if result=="TP" else "#fb7185" if result.startswith("SL") else "#f7d46b"
    parts += [f'<rect x="{L}" y="{H-54}" width="{W-L-R}" height="30" rx="6" fill="#111a2e" stroke="#25334a"/>',
              f'<text x="{L+12}" y="{H-35}" fill="#d6e0ee" font-size="12" font-family="Arial">{esc(result)} · exit {esc(trade["exit_time"])} UTC · R = {float(trade["r_multiple"]):.2f}</text>',
              f'<text x="{W-R-12}" y="{H-35}" text-anchor="end" fill="{col}" font-size="12" font-family="Arial" font-weight="700">RR at entry {float(trade["rr"]):.2f}</text>', '</svg>']
    with open(out_path,"w",encoding="utf-8") as f: f.write("\n".join(parts))


def main():
    if len(sys.argv) < 5:
        raise SystemExit("usage: build_macd_zone_report.py AUDIT BID_M1 BID_M5 OUT_DIR [META]")
    audit_path, m1_path, m5_path, out_dir = sys.argv[1:5]
    meta_path = sys.argv[5] if len(sys.argv)>5 else ""
    os.makedirs(out_dir, exist_ok=True)
    rows=read_audit(audit_path); m1=read_bars(m1_path); m5=read_bars(m5_path)
    trades=[r for r in rows if r["status"]=="EXECUTED"]
    image_files=[]
    for n,t in enumerate(trades,1):
        fn=f"trade-{n:03d}.svg"; chart_svg(m1,m5,t,n,os.path.join(out_dir,fn)); image_files.append(fn)
    shutil.copy2(audit_path, os.path.join(out_dir,"macd-zone-audit.csv"))
    if meta_path and os.path.exists(meta_path): shutil.copy2(meta_path, os.path.join(out_dir,"backtest-meta.txt"))
    rs=[float(r["r_multiple"]) for r in trades]; wins=[x for x in rs if x>0]; losses=[x for x in rs if x<0]
    eq=peak=dd=0; streak=max_streak=0
    for x in rs:
        eq+=x; peak=max(peak,eq); dd=max(dd,peak-eq); streak=streak+1 if x<0 else 0; max_streak=max(max_streak,streak)
    pf=sum(wins)/(-sum(losses)) if losses else 0; wr=100*len(wins)/len(rs) if rs else 0
    body=[]
    for n,(t,fn) in enumerate(zip(trades,image_files),1):
        cls = "win" if t["result"] == "TP" else "loss"
        body.append(f'<figure><img src="{esc(fn)}" alt="MACDZoneTrader trade {n}"><figcaption><b>#{n}</b> {esc(t["entry_time"])} UTC · {esc(t["side"])} · <span class="{cls}">{esc(t["result"])} {float(t["r_multiple"]):.2f}R</span></figcaption></figure>')
    config_rows=[
        ("EA", "MACDZoneTrader 1.10", "production headers: PullbackCore + TradePlanCore"),
        ("Execution", "InpExecuteTrades=true; InpRiskPercent=1.0; InpMinRR=1.0", "one symbol exposure at a time"),
        ("Spread", "InpMaxSpreadPoints=50; point/tick=0.01; digits=2", "Dukascopy bid/ask spread; ask tail fallback noted below"),
        ("MACD", "Fast 12 / Slow 26 / Signal 9; Warmup 0", "M5 and M1; MS_HISTOGRAM_COLOR"),
        ("M5 zones", "RP_BOTH; FVG_OR_DISPLACEMENT; ATR 14", "min leg ATR 1.0; FVG ATR 0.10; efficiency 0.65; body 0.50"),
        ("Timing", "max leg 30; zone life 144; confirmation 30", "M1 touch wick; invalidation close; break buffers 0"),
        ("Stops/target", "SL buffer 0; TP buffer 0", "M1 pattern extreme; nearest confirmed M5 swing; spread compensation"),
    ]
    cfg_html=''.join(f'<tr><th>{esc(a)}</th><td>{esc(b)}</td><td>{esc(c)}</td></tr>' for a,b,c in config_rows)
    table=[]
    for n,t in enumerate(trades,1):
        cls='win' if t["result"]=="TP" else 'loss'
        table.append(f'<tr><td>{n}</td><td>{esc(t["entry_time"])} UTC</td><td>{esc(t["side"])}</td><td>{float(t["entry"]):.2f}</td><td>{float(t["broker_sl"]):.2f}</td><td>{float(t["broker_tp"]):.2f}</td><td>{float(t["rr"]):.2f}</td><td class="{cls}">{esc(t["result"])} {float(t["r_multiple"]):.2f}R</td><td>{esc(t["exit_time"])} UTC</td></tr>')
    html_doc=f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>MACDZoneTrader 12-month backtest</title><style>
:root{{--bg:#080d18;--panel:#111a2e;--text:#e6edf6;--muted:#9aa8bd;--line:#25334a}}*{{box-sizing:border-box}}body{{margin:0;background:var(--bg);color:var(--text);font:14px/1.45 system-ui,-apple-system,Segoe UI,sans-serif}}main{{max-width:1500px;margin:auto;padding:32px 26px 60px}}h1{{margin:0 0 8px;font-size:30px}}h2{{margin:34px 0 8px;font-size:22px}}p,.muted{{color:var(--muted)}}.notice{{padding:14px 16px;border:1px solid #394b6a;background:#0d1526;border-radius:10px;margin:20px 0}}.metrics{{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:10px;margin:18px 0}}.metric{{background:var(--panel);border:1px solid var(--line);border-radius:9px;padding:12px}}.metric b{{display:block;font-size:23px}}table{{width:100%;border-collapse:collapse;background:var(--panel);border:1px solid var(--line);font-size:12px}}th,td{{padding:8px 9px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top}}th{{color:#cbd5e1;background:#0e1729}}.config th{{width:150px}}.win{{color:#4ade80;font-weight:700}}.loss{{color:#fb7185;font-weight:700}}.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(440px,1fr));gap:16px}}figure{{margin:0;padding:9px;background:var(--panel);border:1px solid var(--line);border-radius:9px}}figure img{{display:block;width:100%;height:auto;border-radius:5px}}figcaption{{padding:8px 2px 1px;color:#cbd5e1;font-size:13px}}footer{{border-top:1px solid var(--line);margin-top:36px;padding-top:16px;color:var(--muted);font-size:13px}}a{{color:#8ab4ff}}
</style></head><body><main><h1>MACDZoneTrader 1.10 · 12-month replay</h1><p>Period: <b>2025-09-19 00:00 UTC → 2026-09-18 20:59 UTC</b> · XAUUSD bid M1/M5 with Dukascopy ask where available.</p><div class="notice"><b>อ่านผล:</b> รายงานนี้รัน production logic ของ <code>PullbackCore.mqh</code> และ <code>TradePlanCore.mqh</code> แบบ chronological replay. 1R คือระยะจาก entry ถึง broker SL หลัง spread compensation. การแตะ SL และ TP ในแท่งเดียวกันใช้ SL ก่อนเพื่อความ conservative. ข้อมูล Ask ช่วงท้ายที่ดาวน์โหลดไม่ได้ใช้ fallback spread 0.67 USD เฉพาะ execution model; OHLC signal ทั้งหมดยังเป็นข้อมูลจริง.</div><div class="metrics"><div class="metric"><span class="muted">executed</span><b>{len(trades)}</b></div><div class="metric"><span class="muted">win rate</span><b>{wr:.1f}%</b></div><div class="metric"><span class="muted">net R</span><b>{sum(rs):.2f}R</b></div><div class="metric"><span class="muted">expectancy</span><b>{(sum(rs)/len(rs) if rs else 0):.2f}R</b></div><div class="metric"><span class="muted">profit factor</span><b>{pf:.2f}</b></div><div class="metric"><span class="muted">max drawdown</span><b>{dd:.2f}R</b></div><div class="metric"><span class="muted">max loss streak</span><b>{max_streak}</b></div></div><h2>Config ที่ใช้</h2><table class="config"><tr><th>กลุ่ม</th><th>ค่า</th><th>ความหมาย</th></tr>{cfg_html}</table><h2>ผลลัพธ์ทุกเทรด</h2><table><tr><th>#</th><th>Entry</th><th>Side</th><th>Entry px</th><th>Broker SL</th><th>Broker TP</th><th>RR</th><th>ผล</th><th>Exit</th></tr>{''.join(table)}</table><h2>ภาพ setup และผลลัพธ์</h2><div class="grid">{''.join(body)}</div><footer>Backtest sensitivity: with the same rules and <b>InpMaxSpreadPoints=100</b>, the same data produced 104 executed trades, 35 TP / 69 SL, net -9.90R, win rate 33.7%, PF 0.86. With 3-digit point/tick 0.001 and max spread 50, no trade passed the spread filter. Broker symbol specification therefore materially changes this EA. Re-test in MT5 with the user's broker export for final numbers.</footer></main></body></html>'''
    with open(os.path.join(out_dir,"index.html"),"w",encoding="utf-8") as f: f.write(html_doc)
    print(os.path.join(out_dir,"index.html"), "trades", len(trades), "netR", round(sum(rs),3))


if __name__ == "__main__": main()
