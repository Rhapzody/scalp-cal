# Instant Engulf — EA ปุ่ม Instant Buy / Instant Sell สำหรับ MT5 — 1.02

กดปุ่มเพื่อตรวจ PA บน symbol และ timeframe ของกราฟปัจจุบัน ถ้าผ่านเงื่อนไขจะส่ง **Market order 1 ไม้ทันที** ถ้าไม่ผ่านจะแจ้ง Alert และไม่ส่งคำสั่ง ไม่มีการเข้าออเดอร์อัตโนมัติเมื่อเกิด PA โดยที่ไม่ได้กดปุ่ม

## นิยาม PA ที่ใช้ตามข้อสรุป

- `[0]` = แท่งกำลังก่อตัว ใช้ราคาปัจจุบันในช่วง 5 วินาทีสุดท้ายก่อนปิด
- `[1]` = แท่งที่ปิดล่าสุด
- `[2]` = แท่งก่อนหน้า `[1]`
- **CLOSED (เหลือ > 5 วินาที):** BUY `Close[1] > max(Open[2], Close[2])`; SELL `Close[1] < min(Open[2], Close[2])`
- **LIVE (เหลือ 5–1 วินาที):** BUY `Close[0] > max(Open[1], Close[1])`; SELL `Close[0] < min(Open[1], Close[1])`

ตั้งแต่ 1.01 ใช้ราคาปิดผ่านขอบเนื้อเทียนเดิมก็พอ ไม่จำเป็นต้องพ้นหาง ถ้าแค่หางทะลุแต่ปิดไม่ผ่านเนื้อ หรือปิดเท่ากับขอบเนื้อเดิม ไม่ผ่าน ไม่ค้นย้อนหลังไปหา PA เก่ากว่าแท่งสองแท่งนี้

ใช้เงื่อนไขราคาปิดตามที่ผู้ใช้กำหนดโดยตรง ไม่เพิ่มเงื่อนไขสีแท่งก่อนหน้า หรือบังคับราคาเปิดของแท่งใหม่ให้ครอบทั้ง body ของแท่งเก่า กรณี gap ก็ใช้กฎ Close เทียบ max/min(Open, Close) เดียวกัน; SL ยังใช้ High/Low ทั้งสองแท่งตามเดิม

Panel แสดง `LIVE [0/1]` หรือ `CLOSED [1/2]` เพื่อบอกคู่แท่ง ราคาของแท่ง LIVE ยังเปลี่ยนได้ก่อนปิด ถ้า PA LIVE ไม่ผ่านจะ Alert โดยไม่ไปเลือก PA ปิดเก่ามาแทน ที่ 0 วินาทีแต่ยังไม่มีแท่งใหม่จะรอข้อมูลก่อน หากคู่/เวลาเปลี่ยนระหว่างตรวจคำสั่ง หรือ PA/SL เปลี่ยนระหว่าง OrderCheck จะให้กดใหม่ ไม่ส่งคำสั่งค้างจากคู่เดิม

การส่งจาก LIVE และการตรวจ CLOSED ของแท่งเดียวกันใช้เวลาเปิดแท่งเป็น marker เดียวกัน จึงยังกันส่งซ้ำเมื่อ OneOrderPerSignal เปิด

## SL buffer, TP และ spread

Input ใหม่ **`InpSLBufferPoints` เริ่มต้น `0`** หน่วยเป็น MT5 points ของ symbol จริง

```text
buffer = InpSLBufferPoints × SYMBOL_POINT

shift = 0 ในโหมด LIVE / 1 ในโหมด CLOSED
BUY Strategy SL  = min(Low[shift], Low[shift+1]) − buffer
SELL Strategy SL = max(High[shift], High[shift+1]) + buffer

Entry ตอนกด = Ask สำหรับ BUY / Bid สำหรับ SELL
Strategy TP = 2 × Entry − Strategy SL
```

SL ปัดออกด้านนอกตาม tick grid ของ broker เพื่อไม่ให้การปัดราคาลดระยะเผื่อที่ขอ TP ปัดไปยัง tick ที่ใกล้ที่สุด ระยะ strategy จึงเป็น 1:1 ภายในความละเอียด tick ที่ broker รองรับ

เมื่อเปลี่ยน buffer → SL เปลี่ยน → TP เปลี่ยนตามระยะ 1:1 → Lot คำนวณใหม่ตาม Risk เปอร์เซ็นต์เดิม

**Spread ชดเชยแบบเดียวกับ Scalp Calculator:**

```text
BUY Broker SL/TP = Strategy SL/TP

SELL Broker SL = Strategy SL + (Ask − Bid)
SELL Broker TP = Strategy TP + (Ask − Bid)
```

ใช้ quote ชุดเดียวตอนสร้างคำสั่งเพื่อคำนวณ Entry, TP, Lot และ spread ส่ง SL/TP ไปกับคำสั่ง Market ตั้งแต่แรก ไม่มีคำสั่งเปล่าที่ค่อยเพิ่ม SL ภายหลัง

ตัวอย่าง SELL:

```text
High สูงสุดของสองแท่ง = 3654.00
Point = 0.01
SL buffer = 20 points = 0.20
Bid = 3642.00, Ask = 3642.20

Strategy SL = 3654.20
Entry = 3642.00
Strategy TP = 3629.80  (ระยะ 12.20 ทั้งสองฝั่ง)

Broker SL = 3654.40
Broker TP = 3630.00
```

RR 1:1 หมายถึง **strategy ก่อนชดเชย spread** และอิง quote ขณะส่ง หากเกิด slippage ราคา fill จริงอาจต่างออกไป EA ไม่แก้ SL/TP หลัง fill เพื่อบังคับ RR ใหม่

## Risk และ Lot

```text
Risk budget = Risk Base × InpRiskPercent / 100
Loss per lot = OrderCalcProfit จาก Entry → Strategy SL
Lot = floor_to_step(Risk budget / Loss per lot)
```

Risk Base เริ่มต้นเป็น Initial Balance ที่กรอกเอง มี Current Balance ให้เลือก ไม่ใช้ Equity ไม่ hardcode contract ของทอง และไม่เพิ่ม Lot เมื่อปัดเศษ

เหมือน EA ก่อนหน้า: Risk เป็นงบตาม **Strategy SL** ไม่รวม spread compensation เพิ่มใน SELL, commission, swap หรือ slippage ดังนั้น Broker loss estimate อาจสูงกว่า Strategy risk; Panel แสดงประมาณการ broker loss เพื่อให้เห็นความต่าง

## ติดตั้ง

1. MT5 → **File → Open Data Folder**
2. คัดลอกโฟลเดอร์ `MQL5/Experts/InstantEngulf` จาก ZIP ไปไว้ใน `MQL5/Experts`
3. Navigator → Expert Advisors → Refresh แล้วลาก **InstantEngulf** ลงบนกราฟ
4. ใน Inputs ตั้ง `InpInitialBalance` เป็นทุนเริ่มต้นจริง หรือเลือก `ENGULF_CURRENT_BALANCE`
5. ตั้ง `InpRiskPercent`, `InpSLBufferPoints`, `InpMaxSpreadPoints` ตามที่ต้องการ
6. เปิด Algo Trading และ Allow Algo Trading เมื่อต้องการใช้ปุ่มส่งออเดอร์

Scalp Calculator ตั้งแต่รุ่น 1.02 รวมปุ่ม Instant Engulf ใน Panel แล้ว จึงใช้ความสามารถทั้งสองบน chart เดียวได้ หากเลือกใช้ InstantEngulf EA แยกตัวนี้ร่วมกับ Scalp Calculator ให้ใช้คนละ chart เพราะ MT5 แนบ EA ได้หนึ่งตัวต่อ chart ส่วน Indicator MACD สามารถแนบกับกราฟของ EA ได้ตามปกติ

ค่า `InpInitialBalance=0` มีไว้เพื่อไม่เดาทุนให้ผู้ใช้ ระบบจะบล็อกการเทรดในโหมด Initial จนตั้งค่ามากกว่า 0

## Inputs

| Input | Default | ความหมาย |
|---|---:|---|
| `InpRiskBase` | Initial Balance | หรือเลือก Current Balance |
| `InpInitialBalance` | 0 | ทุนเริ่มต้นในสกุลเงินบัญชี ต้องกรอกเอง |
| `InpRiskPercent` | 1.0 | เปอร์เซ็นต์ risk ของคำสั่ง 1 ไม้ |
| `InpMaxRiskPercent` | 2.0 | เพดานเปอร์เซ็นต์ที่อนุญาต |
| **`InpSLBufferPoints`** | **0** | ระยะเผื่อเพิ่มจาก H/L ของสองแท่ง; ค่าติดลบใช้ไม่ได้ |
| `InpMagicNumber` | 26091202 | Magic ของ EA นี้ แยกจาก Scalp Calculator |
| `InpMaxSpreadPoints` | 30 | spread สูงสุด หน่วย MT5 points |
| `InpDeviationPoints` | 20 | ค่า deviation ใน request; ผลขึ้นกับ broker execution mode |
| `InpMaxQuoteAgeSeconds` | 10 | อายุ quote สูงสุดก่อนบล็อก |
| `InpFreezeGuard` | true | ไม่วาง SL/TP ภายใน freeze zone |
| `InpOneOrderPerSignal` | true | กันส่งซ้ำจาก PA เดิม |
| `InpEnableAtStart` | true | เปิดใช้ปุ่มเมื่อเงื่อนไขอื่นผ่าน; ไม่เข้า trade เอง |
| `InpPanelX / Y / Scale` | 16 / 20 / 1 | ตำแหน่งและขนาด Panel |

หน่วยตัวอย่าง: broker Point=0.01 → 20 points = ราคา 0.20; broker Point=0.001 → 20 points = ราคา 0.020

ไม่มี Input เปลี่ยน RR เพราะสเปกนี้กำหนด 1:1 และ SELL spread compensation เปิดใช้เสมอตาม requirement

## การตรวจและผลหลังคลิก

- หากไม่มี PA ฝั่งที่กด: Alert อธิบาย Close เทียบขอบเนื้อเทียน และไม่ส่งคำสั่ง
- หาก broker constraints ไม่ผ่าน: บล็อกและแจ้งเหตุผล เช่น min/max/step lot, spread, margin, stop/freeze distance, สิทธิ์เทรด หรือราคาเก่า
- ใช้ `OrderCheck` ก่อน `OrderSend` และตรวจว่าระหว่างนั้นไม่เกิดแท่งใหม่จน PA ที่อ่านไว้เก่าไป
- ผลสำเร็จ, partial fill, rejection และ accepted/timeout ที่ยังไม่ยืนยัน แยกกันใน Panel/Alert/Experts log พร้อม ticket, retcode, ราคาและ volume
- ไม่มี auto-retry, auto-close หรือ rollback และไม่แก้ position หลังส่ง
- บัญชี Netting ที่มี position/pending เดิมบน symbol จะถูกบล็อก เพื่อไม่รวม/หักล้าง exposure เดิม ส่วน Hedging เปิดแยกได้ตามข้อจำกัด broker

กด **EA OFF** เพื่อปิดปุ่มส่งคำสั่ง โดยยังดูสถานะ PA ได้ การถอด EA หรือปิด EA ไม่ปิดออเดอร์ที่ส่งไปแล้ว

## กันกดซ้ำ

เมื่อ `InpOneOrderPerSignal=true` บันทึก PA ที่เคยส่งแยกตาม account/server, symbol, timeframe, magic และ side สถานะยังอยู่เมื่อถอด/ใส่ EA ใหม่หรือรีสตาร์ต terminal และใช้ file lock กัน EA หลาย chart ที่ใช้ identity เดียวกันส่งพร้อมกัน

ผล filled, partial หรือยังไม่ยืนยันจะคงตัวกันซ้ำไว้ หาก server ปฏิเสธอย่างชัดเจนจึงปลดให้กดใหม่ได้ ไม่มี retry ให้เอง เมื่อแท่งใหม่ปิดจะตรวจ PA ชุดใหม่ตามปกติ

การตั้ง `InpOneOrderPerSignal=false` อนุญาตให้กดส่งซ้ำจาก PA เดิมได้ ยังมี debounce 1.2 วินาทีป้องกัน double-click; การเปลี่ยน magic เปลี่ยนขอบเขตตัวกันซ้ำด้วย

## การตรวจสอบที่ทำแล้ว

- MetaEditor: **0 errors / 0 warnings**, ได้ `InstantEngulf.ex5`
- **4,116 assertions** ใน production signal, SL buffer, result classification และ broker calculation โดยใช้ MT5 APIs จำลอง ครอบคลุม 59 shared broker regression checks และ 1,000 ชุด buffer/risk
- ตรวจผ่านเนื้อแต่ยังไม่พ้นหางได้, wick-only ไม่ผ่าน, equality ไม่ผ่าน, extreme ของทั้งสองแท่ง, buffer=0/เพิ่ม/ต่าง point/tick, TP 1:1 จาก quote ชุดเดียว, lot floor, SELL compensation, reject/timeout/partial
- EngulfTiming ใช้ source เดียวกับ Panel 1.04 ซึ่งมีชุดจำลองเส้นทางรวม 152 checks เพิ่มจาก core/broker; ไม่ใช่การทดสอบปุ่ม standalone ใน terminal จริง
- ยังไม่ได้ทดสอบปุ่ม/การส่งออเดอร์/การคงสถานะกันซ้ำใน terminal จริง และไม่ได้เปิด trade ในบัญชีของผู้ใช้

รัน test ด้วย `sh scripts/test.sh instant-engulf` ทดสอบบน Demo ก่อนใช้งานจริง โดยตรวจ Signal bar time, Close[1] เทียบ max/min(Open[2], Close[2]), SL ทั้งกรณี buffer 0 และเพิ่ม, volume, broker SL/TP, การกดปุ่มผิดฝั่ง, การกดซ้ำ และ log ผลส่ง

## ไฟล์

- `InstantEngulf.mq5` — Panel, อ่านแท่งปิด, click-to-trade, duplicate guard
- `EngulfTiming.mqh` — เลือกคู่ตามช่วง 5 วินาที และตรวจเวลา/PA/SL ก่อนส่ง
- `EngulfCore.mqh` — กฎ PA, buffered SL, แยกประเภทผลส่ง
- `InstantBroker.mqh` — logic broker จาก EA เดิม เพิ่มการสร้าง TP 1:1 จาก quote เดียว
- `ScalpCore.mqh` — price grid, lot floor และ helpers เดิม
- `InstantEngulf.ex5` — ไฟล์คอมไพล์พร้อมติดตั้ง

เอกสาร API: [CopyRates](https://www.mql5.com/en/docs/series/copyrates), [OrderSend](https://www.mql5.com/en/docs/trading/ordersend), [OrderCheck](https://www.mql5.com/en/docs/trading/ordercheck)
