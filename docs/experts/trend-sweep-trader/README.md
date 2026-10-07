# Trend Sweep Trader — EA MT5 1.00

EA คู่กับ **TrendSweepReclaim** ใช้ core และ Inputs กลยุทธ์เดียวกัน ไม่จำเป็นต้องติด Indicator เพื่อให้ EA ทำงาน

- M5 sweep/reclaim ตามเทรนด์ EMA
- SL พ้นไส้แท่งกวาด + ATR/points buffer
- เป้าหมายเริ่มต้น 2R; ขั้นต่ำสุทธิ 1.8R หลังต้นทุนที่ระบุ
- เสี่ยงเริ่มต้น **1% Equity ต่อรายการ**, ปรับได้
- สถานะ win rate: **ยังไม่ได้วัดจาก market backtest** อ่าน [strategy.md](strategy.md)

## ติดตั้ง

1. แตก `TrendSweepTrader-1.00.zip`
2. MT5 → **File → Open Data Folder**
3. คัดลอก `MQL5/Experts/TrendSweepTrader` จาก ZIP ไปใต้ `MQL5/Experts/` ใน Data Folder ให้มี `TrendSweepTrader.ex5`
4. Refresh Navigator แล้วลาก EA ไปกราฟ symbol ที่ต้องการบน **M5**
5. ค่าเริ่มต้น `InpExecuteTrades=false` แสดงสถานะสัญญาณเท่านั้น เมื่อต้องการทดสอบคำสั่งให้เปิด true ใน **Strategy Tester หรือบัญชี demo** และเปิดสิทธิ์ Algo Trading ตามแพลตฟอร์ม
6. EA รอการปิด M5 ครั้งถัดไป ไม่เปิดจากสัญญาณเก่าตอนแนบ/รีสตาร์ต

ZIP มี EX5, source, core, tests, คู่มือ และ preset `docs/experts/trend-sweep-trader/tester-demo.set` **preset นี้เปิด Execute=true** และ risk 1% สำหรับ Tester/demo ต่างจาก default ใน EX5 ที่ไม่ส่งคำสั่ง

Indicator ติดตั้งแยกเพื่อเห็นแผนบนกราฟ ตั้งค่ากลยุทธ์/ประวัติให้ตรงกัน ดู actual position SL/TP ใน MT5 Trade levels และ Experts log

## Inputs กลยุทธ์ — ตั้งให้ตรงกันทั้งสองตัว

| Input | Default | ความหมาย |
|---|---:|---|
| InpFastEMA / InpSlowEMA | 50 / 200 | Fast ≥ 2 และ < Slow ≤ 1000 |
| InpATRLength | 14 | 2–200 |
| InpSweepLookback | 8 | ช่วงหาขอบกวาด 2–100 แท่งก่อนหน้า |
| InpRoomLookback | 40 | ช่วงหาพื้นที่ TP ≥ SweepLookback และ ≤ 500 |
| InpCooldownBars | 6 | ข้ามหลังสัญญาณ 0–500 แท่ง |
| InpTradeSide | TS_BOTH | ทั้งสอง / TS_BUY_ONLY / TS_SELL_ONLY |
| InpMinSweepATR / InpMaxSweepATR | 0.05 / 0.80 | ระยะกวาดขั้นต่ำ/สูงสุดเทียบ ATR; min ≥ 0, max > min |
| InpMinBodyRatio | 0.35 | body ไปตามทิศทาง / range, 0–1 |
| InpMinCloseLocation | 0.65 | Close ใกล้ปลายด้านการกลับตัว, 0.5–1 |
| InpMaxExtensionATR | 2.0 | ระยะ Close เลย EMA fast ไปตามเทรนด์, > 0 |
| InpSLBufferATR | 0.10 | ระยะเผื่อ SL หน่วย ATR, ≥ 0 |
| InpSLBufferPoints | 0 | ระยะ points บวกเพิ่มจาก ATR buffer, ≥ 0 |
| InpMinStopATR / InpMaxStopATR | 0.5 / 2.5 | ช่วงระยะเสี่ยงที่รับ; min > 0, max ≥ min |
| InpTargetRR | 2.0 | เป้าหมายก่อน commission; 1–10 |
| InpRoomBufferATR | 0.10 | วางขอบพื้นที่ก่อนถึง high/low เดิม, ≥ 0 |
| InpHistoryBars | 3000 | ประวัติ M5: ≥ Warmup + RoomLookback + 1 และ ≤ 20000 |
| InpStartHour / InpEndHour | 0 / 0 | ช่วงเวลาปิดแท่งตาม server; 0–23, ค่าเท่ากัน = ทุกชั่วโมง |

Points ไม่ใช่ pips หรือ dollars เสมอไป: ถ้า `_Point=0.01` การตั้ง 20 points คือระยะราคา 0.20 ค่าที่สัมพันธ์กับ ATR ปรับตามความผันผวน แต่ยังต้องตรวจ digits/tick size ของ broker

## Inputs สำหรับ EA

| Input | Default | ความหมาย |
|---|---:|---|
| InpExecuteTrades | false | true จึงพิจารณาส่งคำสั่ง |
| InpRiskPercent | 1.0 | % Equity ต่อรายการ, > 0 และ ≤ MaxRiskPercent |
| InpMaxRiskPercent | 2.0 | เพดานการตั้งความเสี่ยง, > 0 ถึง 100 |
| InpMinRR | 1.8 | ขั้นต่ำหลัง spread/commission, ≥ 1 และ ≤ TargetRR |
| InpCommissionPerLot | 0 | คอมมิชชันไป–กลับสกุลบัญชีต่อ lot; 0 = ไม่รวมในการกรอง |
| InpMagicNumber | 26091902 | เลขระบุ EA, ต้องไม่เป็น 0 |
| InpDeviationPoints | 20 | requested deviation หน่วย points; ผลขึ้นกับ execution mode ของ broker |
| InpMaxSpreadPoints | 50 | cap spread หน่วย points, > 0 |
| InpMaxSpreadATR | 0.10 | cap spread อีกชั้นเทียบ ATR ก่อนสัญญาณ, > 0 |
| InpMaxEntryDriftATR | 0.20 | ระยะสัมบูรณ์ Bid ใหม่ − Close สัญญาณ / ATR สูงสุด, ≥ 0 |
| InpMaxQuoteAgeSeconds | 5 | อายุ quote 1–60 วินาที |
| InpSignalMaxDelaySeconds | 10 | ส่งได้ภายใน 1–30 วินาทีแรกหลัง M5 ปิด |
| InpFreezeGuard | true | ตรวจ freeze distance แบบ conservative ตาม Scalp Calculator |

สำหรับ symbol ที่ spread ตามปกติเกิน 50 points จะถูกข้าม ให้ตรวจจาก broker และทดสอบต้นทุนก่อนเลือกค่าของตัวเอง ไม่ได้มี preset ที่ยืนยันว่าดีที่สุดสำหรับ XAUUSD หรือคู่เงินใด

## การควบคุมคำสั่ง

- หนึ่ง market request ต่อสัญญาณ พร้อม SL/TP ไม่มี pending entry ไม่มีการ retry OrderSend
- ไม่เปิดซ้อนเมื่อ symbol มี position หรือ pending ของใครก็ตาม ทั้งบัญชี netting/hedging
- ตรวจ quote age, spread, ATR drift, room, SL distance, R:R, commission, lot/margin, broker stops/freeze, permissions และ OrderCheck
- ก่อนส่งตรวจราคาและความสดอีกครั้ง ถ้าเปลี่ยน/หมดเวลาอาจข้าม ไม่ไล่เปิดย้อนหลัง
- ใช้ lock account+symbol สำหรับ instance ของ TrendSweepTrader ภายใน terminal เดียวกัน และบันทึก attempt/pending ก่อนส่ง ไม่มี lock ร่วมกับ EA คนละระบบหรือ terminal คนละตัว
- รีสตาร์ตยังจำสัญญาณที่พยายามส่งแล้ว; Tester ใช้ marker ในหน่วยความจำแยกแต่ละ run
- หลังขาดการเชื่อมต่อข้ามแท่งจะ sync และรอแท่งใหม่ ไม่ชดเชยรายการย้อนหลัง
- ไม่มี daily loss limit หรือ news calendar อัตโนมัติ; cooldown ไม่ใช่เพดานขาดทุนรายวัน

## เมื่อผล OrderSend ไม่แน่ชัด

Timeout, PLACED หรือ partial fill จะคง pending latch และหยุดส่งครั้งถัดไป ต้องตรวจ Trade/History และ Experts log ว่าเกิด order/deal จริงอะไรบ้าง

หลังตรวจสอบและต้องการให้รับสัญญาณใหม่ เปิด **Tools → Global Variables (F3)** ลบเฉพาะ `TST.<hash>.pending` ตาม key ที่ log แจ้ง เก็บ `.B`/`.S` ของ signal attempt ไว้ ปลด latch ไม่ได้ปิด/แก้ position และ exposure guard ยังทำงาน

## การใช้งานและทดสอบ

ขั้นตอนเต็มอยู่ใน [testing.md](testing.md) และบันทึกผลใน [performance.md](performance.md) เปิด Experts/Journal อ่านเหตุผล SKIP; ถ้าไม่เทรดให้ตรวจ Execute, ประวัติ, session, spread cap และว่ามีสัญญาณจริงหรือไม่ก่อนผ่อนเงื่อนไข
