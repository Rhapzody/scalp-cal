# WickHuntSRFlow 1.03 — ทอง M15/M1 · 3 เดือน

Luna Max ทดสอบ R:R 1:1, 1:1.5 และ 1:2 ด้วย spread คงที่ $0.36, SL ปลายหาง M15 ที่รู้ตอนสัญญาณ และ allowance/tick rounding แบบ Instant Engulf

| Nominal R:R | สัญญาณ | TP | SL | Win rate | ผลรวม R | PF | BOTH | ยังเปิด | เข้าไม่ได้ |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1:1 | 227 | 92 | 117 | 44.02% | -37.65R | 0.680 | 10 | 0 | 8 |
| 1:1.5 | 227 | 73 | 141 | 34.11% | -44.80R | 0.684 | 6 | 0 | 7 |
| 1:2 | 227 | 67 | 152 | 30.59% | -33.81R | 0.779 | 2 | 0 | 6 |

เข้าไม่ได้ในตารางรวม geometry SL/TP ไม่ผ่าน กับ NO_ENTRY ที่ไม่มีข้อมูลราคาเปิด M1 ถัดไป; แยกจำนวนไว้ในภาพสรุปและผล CSV/JSON

## สัญญาณแยกสถานการณ์

| สถานการณ์ | Buy | Sell | รวม |
|---|---:|---:|---:|
| Breakout เท่านั้น | 14 | 12 | 26 |
| Pullback เท่านั้น | 98 | 90 | 188 |
| ผ่านทั้งสองแบบ | 12 | 1 | 13 |

## ผลแยกสถานการณ์ (กลุ่มไม่ซ้ำกัน)

| R:R | สถานการณ์ | สัญญาณ | Win rate | ผลรวม R | PF |
|---|---|---:|---:|---:|---:|
| 1:1 | Breakout เท่านั้น | 26 | 50.00% | -2.16R | 0.820 |
| 1:1 | Pullback เท่านั้น | 188 | 42.44% | -36.32R | 0.636 |
| 1:1 | ผ่านทั้งสองแบบ | 13 | 53.85% | +0.82R | 1.137 |
| 1:1.5 | Breakout เท่านั้น | 26 | 33.33% | -6.14R | 0.616 |
| 1:1.5 | Pullback เท่านั้น | 188 | 34.46% | -35.66R | 0.694 |
| 1:1.5 | ผ่านทั้งสองแบบ | 13 | 30.77% | -3.00R | 0.667 |
| 1:2 | Breakout เท่านั้น | 26 | 32.00% | -3.55R | 0.791 |
| 1:2 | Pullback เท่านั้น | 188 | 30.39% | -29.26R | 0.769 |
| 1:2 | ผ่านทั้งสองแบบ | 13 | 30.77% | -1.00R | 0.888 |

## วิธีทดสอบและขอบเขต

- ใช้ WickHuntSRFlow v1.03 โหมดรับ Breakout หรือ Pullback (WS_BOTH), TF หลัก M15 / TF รอง M1, MACD Histogram 12/26/9, S/R 10 swing ต่อ TF แบบ Wick; Breakout ใช้ Swing H ต้านสำหรับ Buy/hunt ล่าง หรือ Swing L รับสำหรับ Sell/hunt บน, High/Low แตะ S/R ภายใน 5 แท่งโดยไม่ต้องปิดทะลุ และ first-hit strong FVG, Pullback กวาดสองหางตามโครงสร้าง
- ช่วง 2026-06-25 21:00 ถึง 2026-09-25 21:00 UTC (ไทย 26 มิ.ย. 04:00 ถึง 26 ก.ย. 04:00): 3 เดือนปฏิทินล่าสุดที่ archive ครอบคลุมเต็ม ไม่ใช่ข้อมูลถึงวันที่ 4 ต.ค.
- Spread คงที่ $0.36 ซึ่งตีความคำขอ 36 points บนทองราคา 2 ทศนิยม; Ask = Bid + 0.36 ทุกจุด ไม่ใช้ spread ผันแปรจริงใน archive
- หลัง M15 reclaim รอ M1 ปิด cross → แท่งถัดไปทันทีปิดฝั่งเดิมอย่างเคร่งครัด → retest เส้นเดิมภายใน 8 แท่งถัดจากแท่งยืนยัน และก่อน setup M15 สิ้นสุด; S/R ตรึงไว้แม้มี swing ใหม่ ถ้าชุดล้มเหลวรอ fresh cross ใหม่
- SL strategy คือ Bid low/high ของ M15 ที่รู้ ณ signal, buffer 0 ตามค่าเริ่มต้น Instant Engulf และปัดออกนอกตลาดบน tick $0.01; Buy broker SL ใช้ค่าเดิม, Sell broker SL เพิ่ม spread $0.36 แล้วปัดใกล้สุด ไม่ใช้ไส้สุดท้ายของ M15
- TP strategy = ราคาเข้าจริง ± ระยะ entry-to-strategy-SL × nominal RR 1/1.5/2 ปัดใกล้สุด tick $0.01; broker TP ของ Sell เพิ่ม spread $0.36 เหมือน Instant Engulf ส่วน Buy ไม่เพิ่ม ถือจน TP/SL หรือจบช่วง ไม่ย้ายระดับ
- ทดสอบ Open ก่อน High/Low: SL gap เติมที่ Open, TP limit เติมที่เป้า; ถ้า High/Low แตะทั้ง SL และ TP ภายใน M1 และ Open ยังไม่แตะ แยกเป็น BOTH ไม่เดาลำดับ
- ตัวเลขหลักไม่นับ BOTH, OPEN, NO_ENTRY และ invalid stop/TP; มีผลแบบ pessimistic/optimistic และข้อมูล gap exposure ในผลจาก Luna; ไม่รวม commission, swap หรือ latency slippage
- ใช้ M1 Open และ representative Close ที่ :59 เพื่อประมาณ reclaim/retest ไม่ใช่ tick replay; ถ้า signal ที่ Open เข้า Open นั้น ถ้า signal ที่ Close:59 เข้า Open ของ M1 ถัดไปทันทีที่ signal-minute +60 วินาทีเท่านั้น ถ้าข้อมูลแท่งนั้นขาดจัดเป็น NO_ENTRY ไม่สมมติ fill หลังช่องว่าง; เริ่มตรวจ exit จากแท่งเข้าจริงเพื่อไม่นำ High/Low ก่อนเข้าไปตัดสิน exit; มี metadata signal/entry delay และการข้าม setup boundary เวลา exit เป็น M1 bucket
- M15 ที่ปิดแต่ข้อมูลไม่ครบจะไม่ถูกใช้เป็นบริบท และ reset higher-TF engine/reference เพื่อกัน partial OHLC เปลี่ยน trend/FVG; ไม่เติมราคาที่ขาดหาย
- Buy เข้า Ask/ออก Bid; Sell เข้า Bid/ออก Ask. R ของผลเทรดหารด้วยระยะ entry-to-broker-SL จริง ดังนั้น realized RR ของ Sell หลัง allowance ต่างจาก nominal RR โดยเฉพาะเมื่อ stop แคบ
- ทุกสัญญาณประเมินแยกกัน อาจซ้อนกันได้ ผลรวม R เป็นผลรวมผลลัพธ์สัญญาณ ไม่ใช่กำไรบัญชีหรือ equity curve
- ภาพใช้ 15 สัญญาณเดียวกันเปรียบเทียบทั้งสาม R:R รวม 45 ภาพ เลือกตามลำดับเวลาสลับกลุ่มสถานการณ์/Buy-Sell/เดือน เฉพาะเคสที่ปิดได้ครบทั้งสามแบบภายใน 480 M1 observations; ภาพเป็นตัวอย่าง ไม่แทนสัดส่วนผลลัพธ์ทั้งหมด
- ในภาพ แท่ง M15 สีคือ final OHLC ส่วนกรอบขาวคือข้อมูลที่รู้ตอนสัญญาณ แท่งหลังสัญญาณและ MACD หลังสัญญาณใช้ดูบริบทผลลัพธ์เท่านั้น

## การตรวจสอบ

ตรวจอิสระจากข้อมูลต้นฉบับครบ 227 สัญญาณและ 681 ผลเทรด ผ่าน 28,577 checks รวม swing, trend, touch/FVG, reclaim, break/hold/retest, SL ที่รู้ขณะ signal และ first-hit outcome; เทียบราคาและ geometry กับ pure helpers จริงของ Instant Engulf เพิ่ม 4,746 checks

[ผลตรวจอิสระ](independent-audit.json) · [เทียบสูตร EA จริง](ea_mapping_verification.json) · [รายละเอียด replay และ source hashes](summary.json)

## รายงานและภาพตัวอย่าง

[เปิดรายงานพร้อมภาพ 45 รูป](index.html) · [ภาพสรุป](comparison.png)

- R:R 1:1: [ทุกเทรด](rr-1/trades.csv) · [ผลสรุป Luna](rr-1/summary.json) · [15 ภาพ](index.html#rr-1)
- R:R 1:1.5: [ทุกเทรด](rr-1_5/trades.csv) · [ผลสรุป Luna](rr-1_5/summary.json) · [15 ภาพ](index.html#rr-1_5)
- R:R 1:2: [ทุกเทรด](rr-2/trades.csv) · [ผลสรุป Luna](rr-2/summary.json) · [15 ภาพ](index.html#rr-2)

## ทำซ้ำ

```sh
python3 tests/reports/wick-hunt-sr-xauusd-m15-m1-3m-v103/run_study.py
python3 tests/reports/wick-hunt-sr-xauusd-m15-m1-3m-v103/audit_study.py
python3 tests/reports/wick-hunt-sr-xauusd-m15-m1-3m-v103/verify_ea_mapping.py
python3 tests/reports/wick-hunt-sr-xauusd-m15-m1-3m-v103/build_gallery.py
python3 tests/reports/wick-hunt-sr-xauusd-m15-m1-3m-v103/build_report.py
```
