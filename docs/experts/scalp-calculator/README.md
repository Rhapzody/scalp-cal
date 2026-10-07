# Scalp Calculator — MT5 EA 1.05

EA สำหรับ **ลากเส้นวางแผน → คำนวณ Lot/RR แบบ realtime → กด Execute ด้วยตนเอง** บน MT5 เน้น CFD Gold แต่ใช้ specification ของ symbol บน chart จริง ไม่ผูกกับชื่อ XAUUSD หรือสัญญาของ broker ใด

สร้างตามแชท “แชทเรื่อง ea scalp calcualtor” รวมไฟล์แนบและข้อแก้ไขล่าสุด: Pending SELL ใช้ spread ตอน **Execute** และ SL ที่ลากออกจะดัน TP ออกเท่ากัน

## Manual SL buffer — ใหม่ใน 1.05

`InpSLBufferPoints=0` เพิ่มระยะ SL จากเส้น Manual หน่วย MT5 points ใช้ทั้ง Market และ Pending:

- BUY: Strategy SL = ราคาเส้น SL − buffer × Point
- SELL: Strategy SL = ราคาเส้น SL + buffer × Point จากนั้นจึงบวก spread หากเปิด Sell spread compensation
- ปัด SL ออกด้านนอกตาม tick ของ broker; 0 คงพฤติกรรมเดิม
- Lot, Strategy loss และ R:R ใช้ SL ที่รวม buffer แล้ว TP คงตามเส้นที่วางไว้
- Panel แสดง Manual SL line, Manual SL buffer, Strategy SL หลัง buffer และ Broker SL หลัง spread
- เส้นที่ลากยังเป็นราคาอ้างอิง ไม่สะสม buffer เพิ่มทุก tick และไม่ย้าย SL ของออเดอร์ที่ส่งแล้ว
- Instant Engulf ใช้ `InpEngulfSLBufferPoints` ของตัวเอง

ตัวอย่าง Point=0.01, buffer=15: BUY เส้น 3000.00 จะใช้ SL 2999.85; SELL เส้น 3000.00 จะใช้ Strategy SL 3000.15 และถ้า spread=0.30 พร้อมเปิดชดเชย จะส่ง Broker SL 3000.45

## Instant ช่วง 5 วินาทีสุดท้าย — ใหม่ใน 1.04

- เหลือ **มากกว่า 5 วินาที**: `CLOSED [1/2]` ใช้สองแท่งปิดล่าสุดตามเดิม
- เหลือ **5, 4, 3, 2, 1 วินาที**: `LIVE [0/1]` ใช้แท่งปัจจุบันเทียบแท่งปิดก่อนหน้า ราคาที่ใช้แทน Close[0] คือราคาล่าสุดใน OHLC ของแท่งที่ยังวิ่ง ไม่ใช่ราคาปิดยืนยัน
- BUY: `Close[0] > max(Open[1], Close[1])`; SELL: `Close[0] < min(Open[1], Close[1])` ในโหมด LIVE; เท่าขอบไม่ผ่าน และไม่ย้อนกลับไปใช้ PA ชุดปิดถ้า LIVE ไม่ผ่าน
- SL ใช้ min(Low)/max(High) ของ **คู่ที่เลือก** + buffer, TP strategy 1:1, Risk และ SELL spread เหมือนเดิม
- หัวข้อเหนือปุ่มบอก LIVE/CLOSED และคู่แท่ง; เวลาใต้หัว Panel ใช้นาฬิกาเดียวกับการเลือกคู่
- ที่ 0 วินาทีแต่ terminal ยังไม่สร้างแท่งใหม่ จะรอข้อมูลแท่งใหม่ก่อน ถ้าคู่แท่งหรือหน้าต่างเวลาเปลี่ยนระหว่างตรวจ/บันทึกกันซ้ำ หรือ PA/SL เปลี่ยนระหว่าง OrderCheck จะไม่ส่งและให้กดใหม่
- เมื่อส่งจากแท่ง LIVE แล้ว เวลาที่เปิดแท่งเดิมยังเป็นตัวกันซ้ำเมื่อแท่งนั้นกลายเป็น CLOSED จึงไม่ส่งซ้ำเพราะโหมดเปลี่ยน (เมื่อเปิด OneOrderPerSignal)

ใช้บน symbol และ TF ปัจจุบันเท่านั้น และยังส่งจากการกดปุ่ม ไม่มี auto-entry ตอนเข้า 5 วินาทีสุดท้าย

## สีสถานะและกฎ Instant ใน 1.03

- **Execute สีแดง — LOCKED - REARM** และ **REARM สีเหลือง — REARM REQUIRED**: ต้องตรวจผลชุดก่อนแล้วกด REARM เพื่ออนุญาตชุดใหม่ แม้ CLEAR หรือตั้งให้เคลียร์อัตโนมัติหลังสำเร็จแล้วก็ตาม ถ้าไม่มี setup ต้องสร้าง BUY/SELL ใหม่ด้วย
- **REARM สีเทา — REARM: NOT NEEDED**: ไม่มีล็อกชุดก่อน แต่เงื่อนไขอื่นยังอาจบล็อก Execute
- **Execute สีเขียว**: setup และเงื่อนไขส่งผ่านทั้งหมด; **สีเทา**: ยังส่งไม่ได้ด้วยเหตุผลอื่นที่แสดงใต้ปุ่ม
- ระหว่างส่งขึ้น SENDING / PLEASE WAIT; REARM ไม่เติมไม้ที่ขาดและไม่เปิดคำสั่งเอง
- Instant เปลี่ยนจากผ่านหางเป็นปิดผ่าน **ขอบเนื้อเทียนของแท่ง [2]** อย่างเคร่งครัด ราคาปิดเท่าขอบยังไม่ผ่าน ใช้ max/min ของ Open/Close ไม่ขึ้นกับสีแท่ง ส่วน SL ยังใช้ High/Low ของคู่แท่งที่เลือกพร้อม buffer เดิม

## Instant Engulf ใน Panel — ใหม่ใน 1.02

มี **INSTANT BUY / INSTANT SELL** อยู่ใต้ชุดควบคุม manual ใช้บน chart เดียวกับ Calculator ได้ โดยไม่ต้องแนบ EA ตัวที่สอง เปิด/ซ่อนส่วนนี้ด้วย `InpShowInstantEngulf` (default `true`); เมื่อซ่อนจะส่งผ่านปุ่ม Instant ไม่ได้

- **BUY:** `Close[1] > max(Open[2], Close[2])`; **SELL:** `Close[1] < min(Open[2], Close[2])` บน TF ปัจจุบัน เป็นกฎช่วง CLOSED; ช่วง LIVE ใช้ `[0]` เทียบ `[1]` ตามหัวข้อ 1.04 ไม่เพิ่มเงื่อนไขสีแท่ง
- กดแล้วไม่มี PA ฝั่งนั้น → Alert; ผ่าน PA และเงื่อนไข broker → ส่ง **Market 1 ไม้ทันที** ไม่ต้องกด Execute ต่อ
- BUY SL = Low ต่ำสุดของคู่แท่งที่เลือก − buffer; SELL SL = High สูงสุดของคู่แท่งที่เลือก + buffer โดยปัด SL ออกตาม tick grid
- TP strategy = 1:1 จาก quote ชุดเดียวกับ Entry/Lot; SELL broker SL/TP บวก spread เสมอในโหมด Instant แม้ `InpSellSpreadCompensation=false` สำหรับ manual
- ใช้ **`InpEngulfRiskPercent=1.0`** และ **`InpEngulfSLBufferPoints=0`** แยกจาก preset Risk, Orders, SL/TP และ MARKET/PENDING ของ manual โดยใช้ Risk Base, Initial Balance, Max Risk, spread limit, deviation, freeze guard และ quote age ร่วมกัน
- **EA ON/OFF** ควบคุมทั้งสองส่วน ปุ่ม BUY/SELL เดิมยังสร้างเส้นวางแผน ส่วน REARM SETUP ใช้กับ batch manual และไม่ปลดตัวกันส่งซ้ำของ Instant

หัวข้อ ENGULF แสดง PA และ Risk ของส่วนนี้ ในหน้ารายละเอียดท้าย ๆ มี Engulf PA, Risk, SL, TP, Lot, Broker loss, SL buffer และเวลาเปิดของแท่งสัญญาณที่เลือก; ค่าพรีวิวเป็นข้อมูลขณะนั้น เมื่อกดจะอ่าน PA และราคาใหม่อีกครั้ง ผลการกดขึ้นต้น `INSTANT` และมีรายละเอียดใน Alert/tooltip/Experts log

`InpEngulfOneOrderPerSignal=true` กันส่งซ้ำตาม account/server, symbol, TF, magic และฝั่ง ใช้ file lock และ persistent marker แบบ InstantEngulf เดิม ผล partial/timeout/ยังไม่ยืนยันคงตัวกันซ้ำไว้ ปลดเฉพาะ server ปฏิเสธชัดเจน ไม่มี auto-retry มี debounce 1.2 วินาทีแม้ปิดตัวกันซ้ำ

`InpEngulfMagicNumber=26091202` ตรงกับค่าเริ่มต้นของ EA InstantEngulf แยก จึงแชร์ตัวกันซ้ำกันได้ภายใน terminal เดียวเมื่อ account/symbol/TF/magic ตรงกัน การเปลี่ยน magic แยกขอบเขตนี้; Magic ของ manual ยังคงใช้ `InpMagicNumber`

เมื่อเปิดส่วน Instant พื้นที่ข้อมูลต่อหน้าจะลดลง ใช้ `< / >` หรือเพิ่มความสูงกราฟเพื่ออ่านรายละเอียดเพิ่มเติม สูตรและปุ่มวางแผน manual ยังคงเดิม

## ปรับ UI ใน 1.01

เพิ่มระยะห่างปุ่มและแถว แยกช่องชื่อ/ค่า และจัดตัวเลขชิดขวา เลิกย่อพิกัดตามความสูงจนตัวหนังสือทับกัน วัดข้อความตามฟอนต์และ DPI ของ MT5; บนกราฟแคบใช้ชื่อ/ค่าสองบรรทัด ส่วนกราฟเตี้ยแบ่งหน้ารายละเอียดให้ปุ่มและสถานะอยู่ในกรอบ หากพื้นที่เล็กเกินจะแสดงข้อความให้ขยายกราฟ

ใช้ Scale = 1 เป็นค่าเริ่มต้น กราฟสูงขึ้นจะแสดงรายละเอียดต่อหน้าได้มากขึ้น; สูตร Risk, SL/TP, spread และการส่งคำสั่งเหมือนเดิม

## ติดตั้ง

1. เปิด MT5 → **File → Open Data Folder**
2. คัดลอกโฟลเดอร์ `MQL5/Experts/ScalpCalculator` จาก ZIP ไปยัง `MQL5/Experts` ใน Data Folder
3. ใน Navigator → Expert Advisors → คลิกขวา **Refresh** แล้วลาก **ScalpCalculator** ลงบนกราฟ symbol ที่จะใช้
4. ตั้ง `InpInitialBalance` เป็นทุนเริ่มต้นจริงของบัญชี เช่น `100000` หรือเลือก `InpRiskBase = SCALP_CURRENT_BALANCE` เพื่อใช้ Balance ปัจจุบัน
5. กำหนด `InpMaxSpreadPoints` ให้ตรงกับ symbol: ถ้า Point = 0.01 ค่า 30 คือระยะราคา 0.30; ถ้า Point = 0.001 ค่า 30 คือระยะราคา 0.030
6. เปิด Algo Trading และ Allow Algo Trading ในคุณสมบัติ EA เมื่อต้องการใช้ปุ่ม Execute

มีไฟล์ `ScalpCalculator.ex5` ที่คอมไพล์แล้ว หากแก้ source ให้เปิด `ScalpCalculator.mq5` ใน MetaEditor แล้วกด F7 โดยเก็บ `.mqh` ทั้งห้าไฟล์ในโฟลเดอร์เดียวกัน

## ใช้งาน

- เลือก **MARKET / PENDING** และ **BUY / SELL** เพื่อสร้าง setup
- Market มีเส้น **SL, TP** และใช้ Ask สำหรับ BUY / Bid สำหรับ SELL แบบ realtime
- Pending เพิ่มเส้น **ENTRY** และตรวจ Buy Limit/Stop หรือ Sell Limit/Stop อัตโนมัติ
- ลาก SL ออก → TP ขยับออกด้วยระยะเดียวกัน; ลาก SL เข้า → TP อยู่ที่เดิม; ลาก TP → SL อยู่ที่เดิม
- เลือก preset Risk และจำนวน Orders ด้วยปุ่ม `− / +` แล้วอ่าน Lot ต่อไม้และข้อมูลบน Panel
- **EXECUTE** ส่งชุดออเดอร์เมื่อผ่านเงื่อนไขทั้งหมด ปุ่มจะถูกล็อกหลังเริ่มส่งชุดหนึ่ง ใช้ **REARM SETUP** เมื่อตรวจผลและต้องการส่งอีกชุด
- **EA OFF** ปิดเฉพาะความสามารถในการ Execute; Calculator ยังทำงาน
- **CLEAR** ลบ setup บนกราฟ; **HIDE/SHOW** ย่อ/ขยาย Panel
- ใช้ปุ่ม **< / >** ข้าง DETAILS เพื่อเปลี่ยนหน้ารายละเอียดเมื่อกราฟมีพื้นที่ไม่พอ; ปุ่ม Execute และสถานะอยู่ด้านล่างเสมอ
- ข้อความที่ยาวเกินช่องแสดง `...` สามารถวางเมาส์เพื่ออ่านข้อความเต็มผ่าน tooltip
- เปลี่ยน timeframe แล้วเส้น, side, mode, Risk, Orders และสถานะล็อก Execute ยังอยู่

การกด BUY/SELL สร้างตำแหน่งเส้นเริ่มต้นใหม่ ส่วนการสลับ Market/Pending คง SL/TP เดิมและเพิ่ม/ลบ Entry line ตามโหมด หากตำแหน่งไม่ถูกต้อง Panel จะแจ้งให้แก้

**เส้นของ EA เป็นเส้นวางแผนสำหรับคำสั่งชุดถัดไป** การลากเส้น, Clear, EA OFF หรือถอด EA ไม่แก้ไข/ยกเลิก pending และ position ที่ส่งไปแล้ว ให้จัดการรายการเหล่านั้นในแท็บ Trade ของ MT5

## นิยาม Risk ที่ใช้

```text
Risk target = Initial Balance หรือ Current Balance × Risk% / 100
LossPerLot = ผลขาดทุนจาก Entry → Strategy SL ผ่าน OrderCalcProfit
Lot/order = floor_to_step(Risk target / Orders / LossPerLot)
Strategy RR = abs(Strategy TP − Entry) / abs(Entry − Strategy SL)
```

เลือก 1% และ 2 Orders หมายถึงแบ่งงบ 1% ออกเป็นสองไม้เท่ากัน ไม่ใช่ 1% ต่อไม้ เศษ Lot ถูกปัดลงทุกไม้ ไม่กระจายเศษไปเพิ่มไม้ใด และไม่ลดจำนวน Orders ให้อัตโนมัติ

ตัวอย่างทุน 10,000, Risk 1%, SL ราคา 7.00, มูลค่าขาดทุน 700 ต่อ lot และ step 0.01: ได้ 0.07 × 2 ไม้, Strategy loss 98 หน่วยเงินบัญชี

**SELL spread compensation เปิดเป็นค่าเริ่มต้น:**

```text
spread = Ask − Bid ตอนกด Execute
Broker SL = Strategy SL + spread
Broker TP = Strategy TP + spread
```

ทั้งสองราคาปรับลงบน tick grid ที่ broker รองรับด้วยการปัดราคาที่ใกล้ที่สุด ราคา Entry ของ Pending ไม่ถูกชดเชย ทุกไม้ในชุดใช้ Broker SL/TP และ Lot ชุดเดียวกันที่จับไว้ตอน Execute; ไม่คำนวณ spread ชดเชยใหม่ตอน Pending fill และไม่ต้องให้ EA คอยเติม SL ภายหลัง

**Risk target เป็น strategy price risk ตามสเปก ไม่ใช่เพดานขาดทุนเงินจริงรวมทุกค่าใช้จ่าย** ตัวอย่าง SELL ข้างต้น spread 0.20 จะมี Strategy loss 98 แต่ Broker loss estimate 100.80 จึงแสดงทั้งสองค่าแยกกัน การประมาณนี้ยังไม่รวม commission, swap และ slippage/gap; สกุลเงินกำไรและขาดทุนอ่านจากบัญชี ไม่สมมติว่าเป็น USD

## Inputs หลัก

| Input | ค่าเริ่มต้น | ความหมาย |
|---|---:|---|
| `InpRiskBase` | Initial Balance | อีกตัวเลือกคือ Current Balance; ไม่ใช้ Equity |
| `InpInitialBalance` | 0 | ต้องกรอกเองในโหมด Initial; ค่า 0 จะบล็อก Execute |
| `InpRiskPreset1..4` | 0.5 / 1 / 1.5 / 2 | เปอร์เซ็นต์ของทั้ง setup |
| `InpDefaultRisk` | 1 | Risk ที่เลือกตอนเริ่ม |
| `InpDefaultOrders` | 1 | จำนวนไม้เริ่มต้น |
| `InpMaxRiskPercent` | 2 | เพดาน Risk ของ setup; presets ต้องไม่เกินค่านี้ |
| `InpMaxOrders` | 5 | จำนวนไม้สูงสุด |
| `InpMagicNumber` | 26091201 | Magic ของคำสั่งที่ส่ง |
| `InpSellSpreadCompensation` | true | บวก spread ให้ SELL SL/TP |
| `InpMaxSpreadPoints` | 30 | spread สูงสุด หน่วย MT5 points |
| `InpDeviationPoints` | 20 | ส่งค่า deviation ให้ broker; ผลขึ้นกับ execution mode |
| `InpFreezeGuard` | true | กันวาง Market SL/TP หรือ Pending Entry ภายใน freeze zone |
| `InpMaxQuoteAgeSeconds` | 10 | ปฏิเสธราคาที่เก่าเกินค่านี้ |
| `InpClearAfterExecute` | false | ลบ setup หลังทั้งชุดสำเร็จครบเท่านั้น |
| `InpEnableAtStart` | true | เปิดใช้ปุ่ม Execute หากเงื่อนไขอื่นผ่าน; ไม่เปิด trade อัตโนมัติ |
| `InpSLBufferPoints` | 0 | Manual: ระยะเผื่อจากเส้น SL; ใช้คำนวณ Lot/RR และ SL ก่อนชดเชย spread |
| `InpDefaultSLPoints` | 700 | ระยะ SL เริ่มต้น |
| `InpDefaultRR` | 2 | RR เริ่มต้นก่อนลากเส้น |
| `InpPendingOffsetPoints` | 200 | ระยะ Entry เริ่มต้นฝั่ง Limit |
| `InpShowInstantEngulf` | true | แสดงและเปิดใช้ส่วนปุ่ม Instant |
| `InpEngulfRiskPercent` | 1.0 | Risk ของ Instant 1 ไม้; ไม่อิง preset manual |
| `InpEngulfSLBufferPoints` | 0 | ระยะเผื่อ SL เพิ่ม หน่วย MT5 points |
| `InpEngulfMagicNumber` | 26091202 | Magic และ identity ของตัวกันส่งซ้ำ Instant |
| `InpEngulfOneOrderPerSignal` | true | กันส่งซ้ำจาก PA เดิมและคงสถานะข้าม restart |
| `InpPanelX / Y / Scale` | 16 / 20 / 1 | ตำแหน่งและขนาด Panel; ปรับตามพื้นที่กราฟและแบ่งหน้ารายละเอียด ไม่ลดฟอนต์ต่ำกว่า 8 pt |

Minimum Lot/order คือ `max(0.01, SYMBOL_VOLUME_MIN)` และต้องตรง `SYMBOL_VOLUME_STEP` เมื่อแยกไม้แล้วต่ำกว่า minimum จะบล็อกทั้งชุดและ Alert เมื่อกด Execute

## พฤติกรรมการส่งออเดอร์

ตรวจ side, stop distance, freeze guard, min/max/step lot, directional volume limit, margin รวม, Max Spread, อายุราคา, symbol order modes และสิทธิ์เทรดก่อนเปิด รวมทั้งใช้ `OrderCheck` ก่อน `OrderSend` ทุกไม้

จับชุดราคาและ Lot อีกครั้งตอน Execute แล้วตรวจราคาตลาดก่อนส่งแต่ละไม้ ถ้าตลาดเคลื่อนจนงบ strategy ที่เหลือไม่พอสำหรับ Lot เท่าเดิม จะหยุดไม้ที่เหลือ ไม่ปรับ Lot ให้ต่างกันระหว่างไม้

รายงาน filled/placed ตามผลตอบกลับ broker ถ้า partial fill, reject, timeout หรือ accepted แต่ยังไม่ยืนยัน fill จะหยุดไม้ถัดไปและให้ตรวจ Trade/History ไม่มี retry, rollback หรือ auto-close ไม้ที่สำเร็จ ดูรายละเอียดผ่าน Alert, tooltip ที่บรรทัดผล หรือ Experts log ซึ่งมี retcode, ticket, ราคาและ volume

บัญชี Hedging แยก position ได้ ส่วน Netting รวมหลายไม้เป็น position เดียว EA จึงอนุญาตเริ่ม batch บน symbol ที่ยังไม่มี position/pending เท่านั้น เพื่อไม่เปลี่ยน SL/TP หรือหักล้าง exposure เดิม การเทรด symbol เดียวกันจากแหล่งอื่นระหว่างส่งหรือก่อน pending fill ยังเปลี่ยน exposure ของบัญชี Netting ได้

Pending ใช้ GTC และมี SL/TP ไปพร้อมคำสั่ง หาก symbol ไม่รองรับจะบล็อกและบอกเหตุผล Freeze guard เป็นเกณฑ์เพิ่มเติมสำหรับการวาง setup; freeze level ของ broker ใช้กับการแก้ไข/ยกเลิกเป็นหลัก ไม่ได้หมายความว่า broker ทุกเจ้าบังคับเกณฑ์นี้กับ initial placement

Countdown ใช้เวลา server จาก MT5 เป็นจุดอ้างอิง แล้วเดินต่อด้วย monotonic timer ทุก 250 ms ไม่รอ tick; เมื่อครบแต่ยังไม่มีแท่งใหม่จะแสดง `00:00 (wait bar)` และแสดง OFFLINE เมื่อตัดการเชื่อมต่อ

## สถานะการตรวจสอบ

- MetaEditor: **0 errors, 0 warnings**, มี `.ex5`
- ทดสอบฟังก์ชัน production ใน `ScalpCore.mqh`: **80,041 checks** รวม property checks จาก 20,000 ชุดข้อมูล
- ทดสอบ `ScalpBroker.mqh` กับ MT5 API จำลอง: **59 checks**
- ทดสอบ Engulf core/broker ที่รวมใน Panel: **4,116 checks** (รวม broker 59 checks ที่รันซ้ำ) และเส้นทางกดส่งแบบจำลองเพิ่ม **152 checks**
- ทดสอบสี/ข้อความและล็อกหลัง Clear เพิ่ม **17 UI state checks**
- ตรวจ geometry จาก Render จริงด้วย font metrics จำลอง: **1,611 scenarios** ครอบคลุมขนาดกราฟ, Scale, DPI, เปลี่ยนหน้า, ย่อ/ขยาย และกรณีวัดฟอนต์ไม่สำเร็จ
- ยังไม่ได้ทดสอบ UI/การ fill กับ broker ใน MT5 จริง และไม่ได้เปิดออเดอร์ในบัญชีของผู้ใช้

รันชุดทดสอบด้วย `sh scripts/test.sh scalp-calculator` รายละเอียดและรายการตรวจบน Demo อยู่ใน [การทดสอบ](testing.md) ควรทดสอบ checklist บนบัญชี Demo ของ broker ที่จะใช้ก่อนนำไปใช้งานจริง ยังไม่อ้างว่าผ่านการรับรองหรือข้อกำหนดของ E8, FundingPips, FTMO หรือ The5ers

ดูการตีความสเปกฉบับละเอียดที่ [ข้อกำหนด](requirements.md)

## ขอบเขต V1

ไม่มี auto-entry strategy, BE, trailing, partial close, Multi TP, Close All, daily loss/trade limits, session/news filters หรือ hotkeys ตามขอบเขตที่ตกลงไว้

## เอกสาร API ที่ตรวจประกอบ

- [OrderCalcProfit — MetaQuotes](https://www.mql5.com/en/docs/trading/ordercalcprofit): คำนวณ P/L ตามบัญชีและ symbol
- [OrderSend — MetaQuotes](https://www.mql5.com/en/docs/trading/ordersend): ต้องแยกการรับคำสั่งออกจากการยืนยัน fill และตรวจ retcode
- [OrderCheck — MetaQuotes](https://www.mql5.com/en/docs/trading/ordercheck): ตรวจ request ก่อนส่ง
- [Execution and filling policies — MetaQuotes](https://www.mql5.com/en/book/automation/experts/experts_execution_filling): ใช้ RETURN สำหรับ Pending และเลือก policy สำหรับ Market ตาม symbol
- [Symbol properties — MetaQuotes](https://www.mql5.com/en/docs/constants/environment_state/marketinfoconstants): หน่วยราคา, volume, stop/freeze และ order modes
