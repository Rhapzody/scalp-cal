# Opening Range Retest — Indicator 1.00

Indicator สำหรับกราฟ **M5** ที่หา Opening Range ตามเวลา server ของ broker แล้วรอ breakout → retest → reclaim อ่าน [strategy.md](strategy.md) สำหรับหลักการและข้อจำกัด

## ติดตั้ง

1. แตก `OpeningRangeRetest-1.00.zip`
2. MT5 → **File → Open Data Folder**
3. คัดลอก `MQL5/Indicators/OpeningRangeRetest` ไปใต้ `MQL5/Indicators/`
4. Navigator → Refresh แล้วลาก `OpeningRangeRetest` ลงกราฟ M5
5. ตรวจ `InpStartHour`/`InpStartMinute` ให้เป็นเวลา server ของ broker ไม่ใช่เวลาไทยโดยอัตโนมัติ

Indicator ไม่ส่งคำสั่งและไม่ต้องเปิด Algo Trading ลูกศรเกิดจากแท่งปิดแล้วเท่านั้น

## อ่านสัญญาณ

- ช่วง Opening Range เก็บ High/Low ของแท่ง M5 ใน `InpRangeMinutes` แรก
- Breakout ต้องปิดพ้นขอบตาม `InpMinBreakATR` และไม่ไกลเกิน `InpMaxBreakATR`
- แท่ง breakout ต้องมี body และ close location ตาม Inputs
- ต้องมีแท่งต่อมาที่ retest ขอบเดิมแล้วปิดกลับไปทาง breakout
- ลูกศร Buy/Sell อยู่บนแท่ง retest ที่ปิดแล้ว
- เส้นแดงคือ planned SL และเส้นเขียวคือ planned TP จากราคาปิด signal ก่อน spread/tick rounding
- `InpVisiblePlans=0` ซ่อนเส้นแผนแต่ไม่ปิด buffers

## Inputs

| Input | Default | ความหมาย |
|---|---:|---|
| `InpStartHour` / `InpStartMinute` | 8 / 0 | เวลาเริ่ม Opening Range ตาม server, 0–23 / 0–59 |
| `InpRangeMinutes` | 30 | ความยาวกรอบ, 5–480 และต้องหารด้วย 5 ลงตัว |
| `InpATRLength` | 14 | ATR ที่ใช้กรอง breakout/stop |
| `InpMaxRetestBars` | 12 | จำนวนแท่งหลัง breakout ที่ยอมให้ retest |
| `InpTradeSide` | OR_BOTH | ทั้งสองฝั่ง, Buy only หรือ Sell only |
| `InpRetestMode` | OR_RETEST_WICK | ไส้แตะขอบ หรือ Close แตะขอบ |
| `InpMinBreakATR` / `InpMaxBreakATR` | 0.10 / 1.50 | ระยะปิดพ้นกรอบเทียบ ATR |
| `InpMinBodyRatio` | 0.45 | body/range ของแท่ง breakout |
| `InpMinCloseLocation` | 0.70 | Close ต้องอยู่ใกล้ปลาย breakout |
| `InpSLBufferATR` / `InpSLBufferPoints` | 0.10 / 0 | ระยะเผื่อหลังไส้ retest |
| `InpMinStopATR` / `InpMaxStopATR` | 0.40 / 2.50 | ขอบเขตระยะ stop ที่รับได้ |
| `InpTargetRR` | 2.0 | planned target เป็น 2R; เป็นค่าตั้ง ไม่ใช่ win rate |
| `InpHistoryBars` | 3000 | ประวัติ M5 ที่คำนวณ |

Points คือ `_Point` ของ symbol เช่น `_Point=0.01`, 20 points = ราคา 0.20

## Buffers

| Index | ค่า |
|---|---|
| 0 / 1 | Buy / Sell ราคาปิดแท่ง retest |
| 2 / 3 | planned SL / TP |
| 4 / 5 | Opening Range High / Low |
| 6 | ขอบกรอบที่ breakout |
| 7 | ATR ก่อน signal |

## ข้อจำกัด

ระบบใช้ OHLC ของแท่งปิด ไม่รู้ลำดับ intrabar ภายในแท่ง ไม่ตรวจ order book หรือ stop orders จริง และยังไม่มีข้อมูลตลาดสำหรับอ้าง win rate ดู [performance.md](performance.md)
