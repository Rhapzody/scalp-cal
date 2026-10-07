# WickHuntSRFlow 1.02 — ทอง M15/M1 · 3 เดือน

Luna Max ทดสอบ R:R 1:1, 1:1.5 และ 1:2 ด้วย spread คงที่ $0.36 และ SL ปลายหาง M15 ที่รู้ตอนสัญญาณ

| R:R | สัญญาณ | TP | SL | Win rate | ผลรวม R | PF | BOTH | ยังเปิด |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1:1 | 567 | 241 | 322 | 42.81% | -81.00R | 0.748 | 4 | 0 |
| 1:1.5 | 567 | 199 | 367 | 35.16% | -68.50R | 0.813 | 1 | 0 |
| 1:2 | 567 | 170 | 396 | 30.04% | -56.00R | 0.859 | 1 | 0 |

## สัญญาณแยกสถานการณ์

| สถานการณ์ | Buy | Sell | รวม |
|---|---:|---:|---:|
| Breakout เท่านั้น | 52 | 37 | 89 |
| Pullback เท่านั้น | 222 | 229 | 451 |
| ผ่านทั้งสองแบบ | 21 | 6 | 27 |

## ผลแยกสถานการณ์ (กลุ่มไม่ซ้ำกัน)

| R:R | สถานการณ์ | สัญญาณ | Win rate | ผลรวม R | PF |
|---|---|---:|---:|---:|---:|
| 1:1 | Breakout เท่านั้น | 89 | 40.91% | -16.00R | 0.692 |
| 1:1 | Pullback เท่านั้น | 451 | 43.08% | -62.00R | 0.757 |
| 1:1 | ผ่านทั้งสองแบบ | 27 | 44.44% | -3.00R | 0.800 |
| 1:1.5 | Breakout เท่านั้น | 89 | 33.71% | -14.00R | 0.763 |
| 1:1.5 | Pullback เท่านั้น | 451 | 35.11% | -55.00R | 0.812 |
| 1:1.5 | ผ่านทั้งสองแบบ | 27 | 40.74% | +0.50R | 1.031 |
| 1:2 | Breakout เท่านั้น | 89 | 28.09% | -14.00R | 0.781 |
| 1:2 | Pullback เท่านั้น | 451 | 30.22% | -42.00R | 0.866 |
| 1:2 | ผ่านทั้งสองแบบ | 27 | 33.33% | +0.00R | 1.000 |

## วิธีทดสอบและขอบเขต

- ใช้ WickHuntSRFlow v1.02 โหมดรับ Breakout หรือ Pullback (WS_BOTH), TF หลัก M15 / TF รอง M1, MACD Histogram 12/26/9, S/R 10 swing ต่อ TF แบบ Wick; Breakout แตะ S/R ภายใน 5 แท่งและ first-hit strong FVG, Pullback กวาดสองหางตามโครงสร้าง
- ช่วง 2026-06-25 21:00 ถึง 2026-09-25 21:00 UTC (ไทย 26 มิ.ย. 04:00 ถึง 26 ก.ย. 04:00): 3 เดือนปฏิทินล่าสุดที่ archive ครอบคลุมเต็ม ไม่ใช่ข้อมูลถึงวันที่ 4 ต.ค.
- Spread คงที่ $0.36 ซึ่งตีความคำขอ 36 points บนทองราคา 2 ทศนิยม; Ask = Bid + 0.36 ทุกจุด ไม่ใช้ spread ผันแปรจริงใน archive
- เข้า ณ M1 Open แรกหลังแท่ง M1 ปิด break ภายหลัง M15 กลับถึง Open ในแท่ง M15 เดียวกัน; Buy เข้า Ask/ออก Bid, Sell เข้า Bid/ออก Ask
- SL Buy = Bid low ของ M15 ที่รู้ ณ เวลาเข้า; SL Sell = Ask high ที่รู้ ณ เวลาเข้า (= known Bid high + 0.36); ไม่ใช้ไส้สุดท้ายของ M15 ที่กำลังวิ่ง และไม่มี buffer เพิ่ม
- TP จากราคาเข้าจริง ห่างเท่ากับระยะ entry-to-SL คูณ 1 / 1.5 / 2 ถือจนแตะ TP/SL หรือจบช่วงทดสอบ ไม่ย้าย SL/TP และไม่ปิดตามแท่ง M15
- ทดสอบ Open ก่อน High/Low: SL gap เติมที่ Open, TP limit เติมที่เป้า; ถ้า High/Low แตะทั้ง SL และ TP ภายใน M1 และ Open ยังไม่แตะ แยกเป็น BOTH ไม่เดาลำดับ
- ตัวเลขหลักไม่นับ BOTH, OPEN และ invalid stop; มีผลแบบ pessimistic/optimistic และข้อมูล gap exposure ในผลจาก Luna; ไม่รวม commission, swap หรือ latency slippage
- ใช้ข้อมูล M1 OHLC จึงประมาณลำดับ reclaim ด้วย M1 Open และ Close ที่ :59 ไม่ใช่ tick replay / MT5 Strategy Tester เวลา exit ภายในแท่งเป็นเพียง M1 bucket
- M15 ที่ปิดแต่ข้อมูลไม่ครบจะไม่ถูกใช้เป็นบริบท และ reset higher-TF engine/reference เพื่อกัน partial OHLC เปลี่ยน trend/FVG; ไม่เติมราคาที่ขาดหาย
- ทุกสัญญาณประเมินแยกกัน อาจซ้อนกันได้ ผลรวม R เป็นผลรวมผลลัพธ์สัญญาณ ไม่ใช่กำไรบัญชีหรือ equity curve
- ภาพใช้ 15 สัญญาณเดียวกันเปรียบเทียบทั้งสาม R:R รวม 45 ภาพ เลือกตามลำดับเวลาสลับกลุ่มสถานการณ์/Buy-Sell/เดือน เฉพาะเคสที่ปิดได้ครบทั้งสามแบบภายใน 480 M1 observations; ภาพเป็นตัวอย่าง ไม่แทนสัดส่วนผลลัพธ์ทั้งหมด
- ในภาพ แท่ง M15 สีคือ final OHLC ส่วนกรอบขาวคือข้อมูลที่รู้ตอนสัญญาณ แท่งหลังสัญญาณและ MACD หลังสัญญาณใช้ดูบริบทผลลัพธ์เท่านั้น

## การตรวจสอบ

ตรวจอิสระจากข้อมูลต้นฉบับครบ 567 สัญญาณและ 1,701 ผลเทรด ผ่าน 42,515 checks รวมการยืนยัน swing, trend, touch/FVG, reclaim, SL ที่รู้ขณะเข้า และ first-hit outcome

[ผลตรวจอิสระ](independent-audit.json) · [รายละเอียด replay และ source hashes](summary.json)

## รายงานและภาพตัวอย่าง

[เปิดรายงานพร้อมภาพ 45 รูป](index.html) · [ภาพสรุป](comparison.png)

- R:R 1:1: [ทุกเทรด](rr-1/trades.csv) · [ผลสรุป Luna](rr-1/summary.json) · [15 ภาพ](index.html#rr-1)
- R:R 1:1.5: [ทุกเทรด](rr-1_5/trades.csv) · [ผลสรุป Luna](rr-1_5/summary.json) · [15 ภาพ](index.html#rr-1_5)
- R:R 1:2: [ทุกเทรด](rr-2/trades.csv) · [ผลสรุป Luna](rr-2/summary.json) · [15 ภาพ](index.html#rr-2)

## ทำซ้ำ

```sh
python3 tests/reports/wick-hunt-sr-xauusd-m15-m1-3m/run_study.py
python3 tests/reports/wick-hunt-sr-xauusd-m15-m1-3m/audit_study.py
python3 tests/reports/wick-hunt-sr-xauusd-m15-m1-3m/build_gallery.py
python3 tests/reports/wick-hunt-sr-xauusd-m15-m1-3m/build_report.py
```
