# WickHuntSRFlow 1.01 — XAUUSD R:R 1:1

ทดสอบ 365 วัน: 2025-09-25 21:00 ถึง 2026-09-25 21:00 UTC ใช้สัญญาณ 2,410 เหตุการณ์เดิม ทุกสัญญาณประเมินแยกกัน รวมกรณี Buy/Sell ใน H1 เดียวกัน จึงไม่ใช่ผลตอบแทนพอร์ต

| SL | TP | SL | Win rate | ผลรวม R ที่ปิดแล้ว | PF ในหน่วย R | BOTH | ยังเปิด |
|---|---:|---:|---:|---:|---:|---:|---:|
| wick H1 ณ สัญญาณ | 1,127 | 1,280 | 46.82% | -175.03R | 0.866 | 1 | 2 |
| wick M5 ที่ปิด break | 1,043 | 1,364 | 43.33% | -338.53R | 0.755 | 3 | 0 |

## วิธีทดสอบ

- เข้า ณ M1 Open แรกที่ตรวจพบสัญญาณหลัง M5 ปิด break สมมติ latency เป็นศูนย์ Buy เข้า Ask / ออก Bid; Sell เข้า Bid / ออก Ask รวม spread จริงจากชุดข้อมูล
- SL Buy ใช้ Low ของ Bid ส่วน SL Sell ใช้ High ของ Ask ซึ่งเป็นราคาปิดสถานะ Sell ไม่เติม buffer จุดอื่น รุ่น H1 ใช้เฉพาะไส้ที่รู้ ณ สัญญาณ ไม่ใช้ High/Low สุดท้ายของ H1; รุ่น M5 ใช้แท่ง breakout ที่ปิดแล้ว
- TP ห่างจากราคาเข้าจริงเท่ากับระยะ SL อัตรา 1:1 ถือจนแตะ TP/SL หรือสิ้นช่วงทดสอบ ไม่ปิดตาม H1 และไม่ย้าย SL/TP
- กรณี Open กระโดดเลย SL เติมที่ราคา Open ทำให้บางครั้งขาดทุนเกิน -1R; TP limit เติมที่เป้า กรณี M1 แตะทั้งสองระดับแต่ Open ยังไม่แตะจะแยกเป็น BOTH ไม่เดาลำดับ
- Win rate/PF/ผลรวม R หลักไม่นับ BOTH และสถานะที่ยังเปิด ไม่รวม commission, swap และ slippage จาก latency; รายงาน sensitivity กรณี BOTH เป็น SL/TP และ subset ที่ไม่ผ่านช่องว่างข้อมูลไว้ใน summary.json
- สัญญาณเป็น M1 snapshot approximation ไม่ใช่ tick replay หรือ MT5 Strategy Tester; เวลา exit ในแท่งคือ label M1 และข้อมูลที่ขาดหายไม่ถูกเติมราคา
- ประเมินแต่ละสัญญาณแยกกัน สามารถซ้อนกันได้ ผลรวม R เป็นผลรวมผลลัพธ์สัญญาณ ไม่ใช่ equity curve หรือ % ผลตอบแทนบัญชี

## เคส Buy ที่คุยกัน เวลา 05:40 UTC วันที่ 2025-09-26

- SL H1: เข้า Ask 3749.895, SL 3744.355, TP 3755.435; ผล SL -1R ใน M1 2025-09-26 05:52:00 UTC
- SL M5: เข้า Ask 3749.895, SL 3745.765, TP 3754.025; ผล SL -1R ใน M1 2025-09-26 05:51:00 UTC

## ผลตรวจและไฟล์

- SL H1: 2,410 trades / 28,915 raw-data audit checks ผ่าน; [trades.csv](sl-h1/trades.csv), [summary.json](sl-h1/summary.json), [monthly.csv](sl-h1/monthly.csv)
- SL M5: 2,410 trades / 31,327 raw-data audit checks ผ่าน; [trades.csv](sl-m5/trades.csv), [summary.json](sl-m5/summary.json), [monthly.csv](sl-m5/monthly.csv)

[รายงานพร้อมภาพ](index.html) · [ภาพเปรียบเทียบ](comparison.png)

## ทำซ้ำ

```sh
python3 tests/reports/wick-hunt-sr-xauusd-1y/rr-1-to-1/run_rr.py --stop h1
python3 tests/reports/wick-hunt-sr-xauusd-1y/rr-1-to-1/verify_rr.py --stop h1
python3 tests/reports/wick-hunt-sr-xauusd-1y/rr-1-to-1/run_rr.py --stop m5
python3 tests/reports/wick-hunt-sr-xauusd-1y/rr-1-to-1/verify_rr.py --stop m5
python3 tests/reports/wick-hunt-sr-xauusd-1y/rr-1-to-1/build_report.py
```
