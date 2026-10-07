# Opening Range Trader — EA 1.00

EA สำหรับกลยุทธ์ Opening Range breakout → retest → reclaim บน M5 ใช้ core เดียวกับ Indicator

## ติดตั้งและใช้งาน

1. แตก `OpeningRangeTrader-1.00.zip`
2. MT5 → **File → Open Data Folder**
3. คัดลอก `MQL5/Experts/OpeningRangeTrader` และ `MQL5/Experts/ScalpCalculator` ไปตามโครงสร้างใน Data Folder
4. Refresh Navigator แล้วลาก EA ลงกราฟ M5
5. ค่า EX5 เริ่มต้น `InpExecuteTrades=false` เพื่อแสดงสถานะเท่านั้น ใช้ preset ใน Strategy Tester หรือ demo ก่อนเปิดการส่งคำสั่ง
6. EA รอแท่ง M5 ถัดไปหลังแนบ ไม่เปิดจากสัญญาณเก่า

## Inputs เพิ่มเติมของ EA

| Input | Default | ความหมาย |
|---|---:|---|
| `InpExecuteTrades` | false | เปิดการส่ง market order |
| `InpRiskPercent` | 1.0 | % Equity ต่อรายการ |
| `InpMaxRiskPercent` | 2.0 | เพดาน risk |
| `InpMinRR` | 1.8 | R:R ขั้นต่ำหลัง spread และ commission; ห้ามต่ำกว่า 1 |
| `InpCommissionPerLot` | 0 | round-trip commission ต่อ lot ในสกุลบัญชี |
| `InpMaxSpreadPoints` | 50 | spread cap เป็น points |
| `InpMaxSpreadATR` | 0.20 | spread cap เทียบ ATR |
| `InpMaxEntryDriftATR` | 0.20 | ระยะจากราคา signal ถึง quote ใหม่สูงสุด |
| `InpMaxQuoteAgeSeconds` | 5 | อายุ quote สูงสุด |
| `InpSignalMaxDelaySeconds` | 10 | ส่งในช่วงต้นแท่ง M5 ถัดไป |
| `InpFreezeGuard` | true | ตรวจ stop/freeze ตาม broker |

Inputs กลยุทธ์ Opening Range เหมือน Indicator ต้องตั้งตรงกันเมื่อเทียบสัญญาณ โดยเฉพาะ StartHour/Minute และเวลา server

## การคำนวณ order

EA ใช้ Ask สำหรับ Buy และ Bid สำหรับ Sell วาง SL พ้น retest pattern และคำนวณ target ใหม่จากราคาเข้าและ `TargetRR` เพื่อให้ R คงที่ จากนั้นชดเชย spread ฝั่ง Sell ตามกติกา Scalp Calculator ตรวจ R:R หลังต้นทุน และลด lot ลงตาม Equity risk หากจำเป็น

ถ้า spread, ราคาไหล, stop distance, margin, broker limits, R:R หรือ commission ไม่ผ่าน ระบบข้ามสัญญาณ ไม่เลื่อน stop/target เพื่อฝืนให้ผ่าน ไม่มี martingale, grid, trailing หรือเพิ่มไม้

## ข้อจำกัดด้านผลลัพธ์

ยังไม่มี market backtest จึงไม่มี win rate ที่อ้างได้ ค่า 2R/1.8R เป็นเงื่อนไขของระบบ ดู [strategy.md](strategy.md), [testing.md](testing.md) และ [performance.md](performance.md)
