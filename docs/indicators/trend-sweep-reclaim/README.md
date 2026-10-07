# Trend Sweep Reclaim — Indicator MT5 1.00

แสดงสัญญาณ **M5 trend + sweep/reclaim + พื้นที่ถึงเป้า** พร้อมระดับ SL/TP ตาม Close ของแท่งสัญญาณ อ่าน [หลักการเต็ม](strategy.md) ก่อนใช้เทียบผล

## ติดตั้ง

1. แตก `TrendSweepReclaim-1.00.zip`
2. ใน MT5 เลือก **File → Open Data Folder**
3. คัดลอกโฟลเดอร์ `MQL5/Indicators/TrendSweepReclaim` จาก ZIP ไปใต้ `MQL5/Indicators/` ของ Data Folder ให้มี `TrendSweepReclaim.ex5` อยู่ข้างใน
4. คลิกขวา Navigator → Refresh แล้วลาก **TrendSweepReclaim** ลงกราฟ **M5**
5. รอโหลดประวัติอย่างน้อย warmup 600 แท่ง ค่าเริ่มต้นขอประวัติ 3,000 แท่ง ถ้าไม่มีสัญญาณไม่ได้แปลว่าเสีย ให้ดูช่วงตลาดและ Inputs

ไม่ต้องเปิด Algo Trading เพื่อดู Indicator และไม่ต้องติด EA ตัวอื่นก่อน ถ้าจะแก้ source เปิด `.mq5` ใน MetaEditor แล้ว Compile โดยเก็บ `.mqh` ในโฟลเดอร์เดียวกัน

## อ่านกราฟ

- ลูกศรเขียว Buy / แดง Sell ที่ราคา Close ของแท่ง M5 ที่ยืนยันแล้ว ไม่มีลูกศรบนแท่งกำลังก่อตัว
- เส้นจุดแดง = planned SL; เส้นจุดเขียว = planned TP เส้นเริ่มที่เวลาที่ทราบสัญญาณ คือเวลาปิดแท่ง และยาวตาม Display Input
- ระดับที่วาดเป็นแผนจาก Close **ก่อน spread, commission และ tick rounding ของคำสั่งจริง** ไม่ใช่ประวัติ position ของ EA
- แสดงแผนล่าสุด 20 สัญญาณตาม default ปิดแผนด้วย VisiblePlans=0 ได้โดยยังมี buffers/ลูกศร
- Popup ปิดไว้ เมื่อเปิดจะแจ้งสัญญาณใหม่หลังปิดแท่ง ไม่ไล่แจ้งประวัติเมื่อแนบ
- แนบ Indicator กับ EA บน M5 โดยใช้ symbol, Inputs กลยุทธ์ และประวัติชุดเดียวกันเพื่อเทียบผล ตัวกรอง execution อาจทำให้ EA ไม่เทรดบางลูกศร

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

## Inputs แสดงผล

| Input | Default | ความหมาย |
|---|---:|---|
| InpVisiblePlans | 20 | แผน SL/TP ย้อนหลัง 0–100 สัญญาณ |
| InpPlanLengthBars | 6 | ความยาวเส้น 1–100 แท่ง M5; ไม่ใช่เวลาออกจาก trade |
| InpBuyColor / InpSellColor | LimeGreen / Tomato | สีลูกศร |
| InpPopupAlert | false | แจ้งเตือนใหม่หลังแท่งปิด |

## Buffers สำหรับ iCustom / Data Window

| Index | ข้อมูลที่แท่งสัญญาณ |
|---|---|
| 0 / 1 | Buy Close / Sell Close |
| 2 / 3 | planned SL / TP |
| 4 | ระดับ Low/High ที่ถูกกวาด |
| 5 | Room limit หลังเผื่อ RoomBufferATR |
| 6 | ATR ก่อนแท่งสัญญาณ |

ไม่มีสัญญาณใช้ EMPTY_VALUE; buffers 2–6 เป็น DRAW_NONE เก็บค่าให้ตรวจใน Data Window ไม่ลากเส้นต่อทุกแท่ง

## ทดสอบ

ดู [testing.md](testing.md) ตัว Indicator ไม่คำนวณ win rate จากลูกศร เพราะราคาเข้า spread และลำดับชน SL/TP ภายในแท่งต้องตรวจจากข้อมูล execution/ticks
