# MACD Zone Trader 1.10

EA สำหรับ MT5 ที่ใช้สัญญาณเดียวกับ **MACDZonePullback** และเปิด market order เมื่อผ่านเงื่อนไขทั้งหมด:

1. M5/M1 หา swing ด้วย **MACD Histogram เปลี่ยนสี**
2. M5 เบรก swing ด้วย FVG หรือแรงส่งที่ผ่านเกณฑ์ แล้วกลับเข้าโซน swing flip / impulse origin
3. M1 ปิดเหนือ Lower High สำหรับ Buy หรือปิดต่ำกว่า Higher Low สำหรับ Sell หลังแตะโซน
4. **TP = swing M5 ที่ยืนยันแล้วและใกล้ที่สุดในทิศทางกำไร**
5. **SL = ไส้สุดของ pattern M1 ตั้งแต่ LH/HL ที่ถูกเบรกจนถึงแท่งสัญญาณ** พร้อมระยะเผื่อ
6. **R:R ≥ 1:1 หลังเผื่อ spread** และหลังค่าคอมมิชชันที่กรอก (ถ้ามี)

ค่าเริ่มต้นเสี่ยง **1% ของ Equity ต่อรายการ** คำนวณ lot ให้ความเสี่ยงประมาณการที่ broker SL รวม commission ที่ระบุไม่เกินงบ ก่อนส่งคำสั่ง

EA ใช้ core ที่คัดลอกตรงจาก indicator และ Scalp Calculator เพื่อให้ชุดติดตั้งเป็นอิสระ ไม่ต้องมี indicator ทำงานอยู่จึงจะส่งสัญญาณได้

## นิยาม TP / SL

### TP: swing ถัดไปของ M5

- Buy เลือก **Swing High ที่ยืนยันแล้ว ซึ่งสูงกว่าราคาเข้า Ask และใกล้ที่สุดตามระดับราคา**
- Sell เลือก **Swing Low ที่ยืนยันแล้ว ซึ่งต่ำกว่าราคาเข้า Bid และใกล้ที่สุดตามระดับราคา**
- ใช้ปลายไส้ของ swing ไม่ใช้ body
- ค้นในหน้าต่างประวัติที่โหลด และใช้เฉพาะ swing ที่ยืนยันไม่เกินเวลาปิดแท่งสัญญาณ M1
- ไม่รอสร้าง swing ในอนาคต ไม่มีการนำจุดที่เพิ่งทราบภายหลังมาย้อนเป็น TP
- หากไม่มีเป้าหมายด้านกำไร จะข้ามสัญญาณ
- หากเป้าหมายใกล้ที่สุดทำให้ R:R ต่ำกว่าเกณฑ์ จะข้ามสัญญาณ **ไม่เลือก swing ที่ไกลกว่ามาทำให้ R:R ผ่าน**
- ไม่กรองว่า swing เคยถูกแตะหรือเบรกมาแล้วหรือไม่; นิยามในรุ่นนี้คือ swing ที่ยืนยันแล้วและอยู่ถัดไปตามราคา
- `InpTPBufferPoints` ค่าเริ่มต้น 0; ค่าบวกเลื่อน TP เข้าหาจุดเข้า ก่อนถึง swing: Buy ลบระยะ buffer, Sell บวกระยะ buffer แล้วปัดเข้าหาจุดเข้าตาม tick size
- เลือก swing ใกล้สุดก่อนหัก buffer แล้วจึงเผื่อ spread ตามสูตรด้านล่าง หากระยะที่เหลือทำให้ R:R ไม่ผ่านหรือ TP ผิดด้าน จะข้ามรายการ ไม่เลือก swing ใหม่
- TP คงที่หลังส่ง order ไม่เลื่อนตาม swing ใหม่

### SL: ครอบคลุม pattern กลับตัว M1

Buy ใช้ Low ต่ำสุดของทุกแท่งตั้งแต่ **แท่ง pivot ของ LH ที่ถูกปิดทะลุ** จนถึงแท่งสัญญาณ M1 รวมทั้งสองปลาย แล้ววาง SL ต่ำลงอีก

Sell ใช้ High สูงสุดตั้งแต่ **แท่ง pivot ของ HL ที่ถูกปิดทะลุ** จนถึงแท่งสัญญาณ M1 แล้ววาง SL สูงขึ้นอีก

`InpSLBufferPoints=0` ยังเผื่อออกไปอย่างน้อย **1 tick** เพื่อให้ SL อยู่พ้นไส้จริง หากกำหนด buffer จะใช้ค่าที่มากกว่าระหว่าง buffer กับ 1 tick แล้วปัดราคาออกนอก pattern ตาม tick size หากข้อมูล M1 ในช่วง pattern ขาดหาย จะไม่ส่ง order

## การเผื่อ spread: ตรงกับ Scalp Calculator

ใช้ `ScalpBrokerPrice` และ `ScalpCalculate` จาก Scalp Calculator โดยไม่แก้สูตร:

| รายการ | Buy | Sell |
|---|---|---|
| ราคาเข้า market | Ask | Bid |
| SL ส่งให้ broker | strategy SL | strategy SL + spread |
| TP ส่งให้ broker | strategy TP | strategy TP + spread |

`spread = Ask − Bid` จาก quote ที่ใช้เตรียมคำสั่ง ราคาทั้งหมดถูกปรับเข้ากับ tick size ของ broker

**จุดต่างเรื่อง lot:** Scalp Calculator เดิมคำนวณ lot จาก strategy SL ก่อน EA นี้ลด lot เพิ่มหาก spread ฝั่ง Sell หรือ commission ทำให้ความเสี่ยงที่ broker SL เกินงบ 1% โดยไม่เพิ่ม lot จากค่าคำนวณเดิม

### ตัวอย่าง Sell

```text
Bid 100.00, Ask 100.20 → spread 0.20
SL จาก pattern รวม buffer = 100.80
TP จาก swing M5 = 98.80

broker SL = 101.00
broker TP = 99.00
Risk = 1.00, Reward = 1.00 → R:R 1:1 ผ่าน (เมื่อ commission = 0)
```

ถ้า swing M5 ที่ใกล้ที่สุดอยู่ที่ 99.20 จะได้ broker TP = 99.40, Reward = 0.60 เทียบ Risk = 1.00 จึง **ไม่ Execute** แม้การวัดก่อนชดเชย spread จะดูดีกว่า

## R:R และขนาดออเดอร์

- ตรวจทั้งระยะราคาและผลขาดทุน/กำไรในสกุลบัญชีจาก `OrderCalcProfit`
- `InpMinRR` เริ่มที่ 1.0 และตั้งต่ำกว่า 1.0 ไม่ได้
- งบความเสี่ยง = Equity ปัจจุบัน × `InpRiskPercent / 100`
- ปัด lot ลงตาม volume step และตรวจ minimum/maximum, margin และ volume limit ของ symbol
- ใช้ minimum ของระบบ Scalp เดิม: ไม่น้อยกว่า `max(0.01, broker minimum lot)` หากงบไม่รองรับ lot ขั้นต่ำจะข้าม ไม่เพิ่มความเสี่ยงเพื่อให้เปิดได้
- `InpCommissionPerLot` คือ commission ไป–กลับโดยประมาณ หน่วยสกุลบัญชีต่อ 1 lot ค่าเริ่มต้น 0 หมายถึงยังไม่รวม commission; swap ไม่รวมในประมาณการ
- ตรวจ quote ใหม่หลัง OrderCheck และหลังบันทึกป้องกันคำสั่งซ้ำ หากราคาหรือ spread เปลี่ยนระหว่างขั้นตอนสุดท้ายจะข้าม

**เกณฑ์ R:R และงบความเสี่ยงเป็นการตรวจ ณ ก่อนส่งคำสั่ง** การ fill จริงอาจมี slippage โดยเฉพาะ market execution จึงไม่รับประกันว่า R:R/risk หลัง fill จะเท่ากับก่อนส่ง EA บันทึกค่าจากราคา fill ให้ตรวจสอบและแจ้งเมื่อผิดเกณฑ์ ไม่ขยับ SL/TP หรือปิดออเดอร์เองเพื่อแก้ตัวเลขภายหลัง

## ติดตั้ง

1. แตก `MACDZoneTrader-1.10.zip`
2. MT5 → **File → Open Data Folder**
3. คัดลอกโฟลเดอร์ `MQL5/Experts/MACDZoneTrader` จาก ZIP ไปไว้ใต้ `MQL5/Experts/` ของ Data Folder
4. ใน Navigator → Expert Advisors คลิกขวา **Refresh** จะพบ **MACDZoneTrader**
5. เปิดกราฟ symbol ที่ต้องการเป็น **M1** (รองรับ M5 ด้วย แต่คำนวณสัญญาณ M1/M5 เหมือนกัน)
6. ลาก EA ลงกราฟ ค่าเริ่มต้น `InpExecuteTrades=false` จะคำนวณและรายงานสัญญาณอย่างเดียว
7. เมื่อต้องการให้ส่งคำสั่งใน Strategy Tester หรือบัญชี demo ให้ตั้ง `InpExecuteTrades=true`, อนุญาต Algo Trading ใน properties ของ EA และเปิดปุ่ม **Algo Trading** ของ MT5
8. ตรวจสถานะบนกราฟและแท็บ **Experts / Journal** ว่าเหตุใดจึงส่งหรือข้ามสัญญาณ

ไม่ต้องติดตั้ง indicator เดิมเพื่อให้ EA ทำงาน หากต้องการเห็นโซนและลูกศรประกอบ ให้ติด **MACDZonePullback** บนกราฟเดียวกันและใช้ค่ากลุ่ม MACD/Zone/Quality/History/Signal tuning เท่ากัน EA เองแสดงข้อความสถานะ ส่วนระดับ SL/TP ของ position ดูจาก Trade levels ของ MT5

EA ไม่เข้าเทรดจากสัญญาณเก่าทันทีที่แนบหรือรีสตาร์ต จะเริ่มพิจารณาหลังแท่ง M1 ถัดไปปิด

## Inputs สำคัญ

| Input | ค่าเริ่มต้น | ความหมาย |
|---|---:|---|
| `InpExecuteTrades` | false | true จึงส่ง order; false รายงานสัญญาณเท่านั้น |
| `InpRiskPercent` | **1.0** | ความเสี่ยง % Equity ต่อรายการ |
| `InpMaxRiskPercent` | 2.0 | เพดาน Inputs สำหรับ risk; สูงสุด 100 |
| `InpMinRR` | **1.0** | ขั้นต่ำหลัง spread/commission; ต้อง ≥ 1 |
| `InpSLBufferPoints` | 0 | เผื่อจากไส้ pattern; อย่างน้อย 1 tick เสมอ |
| `InpTPBufferPoints` | 0 | TP ก่อนถึง swing ใกล้สุด หน่วย points; ≥ 0 |
| `InpCommissionPerLot` | 0 | คอมมิชชันไป–กลับ หน่วยสกุลบัญชี/lot |
| `InpMagicNumber` | 26091801 | ใช้แยกออเดอร์และบันทึกป้องกันซ้ำ |
| `InpDeviationPoints` | 20 | ส่งให้ broker เป็น requested deviation; ขึ้นกับ execution mode |
| `InpMaxSpreadPoints` | 50 | เพดาน spread หน่วย points ของ symbol |
| `InpMaxQuoteAgeSeconds` | 5 | อายุ quote สูงสุด 1–60 วินาที |
| `InpSignalMaxDelaySeconds` | 10 | เข้าเฉพาะ 1–30 วินาทีแรกหลังแท่ง M1 ปิด |
| `InpFreezeGuard` | true | ตรวจ freeze distance แบบ conservative ตาม Scalp Calculator |
| `InpFastEMA / InpSlowEMA / InpSignalEMA` | 12 / 26 / 9 | Histogram color บนทั้ง M5 และ M1 |
| `InpWarmupBars` | 0 | อัตโนมัติ `max(Fast,Slow)+Signal−1` |
| `InpZoneMode` | RP_BOTH | ทั้งสอง / swing flip / impulse origin |
| `InpHistoryM5Bars` | 1500 | 100–5000 แท่ง M5 รวม warmup |
| `InpZoneLifeBars` | 144 | อายุโซน 1–1000 แท่ง M5 |
| `InpStrength` | RP_FVG_OR_DISPLACEMENT | รับ FVG หรือแรงส่ง / FVG เท่านั้น |
| `InpATRLength` | 14 | ATR M5 ใช้วัดแรงส่ง |
| `InpMaxLegBars` | 30 | ขาเบรกยาวไม่เกิน 3–300 แท่ง |
| `InpMinLegATR` | 1.0 | การเคลื่อนที่สุทธิของขา/ATR ขั้นต่ำ |
| `InpMinFVGATR` | 0.10 | ขนาด FVG/ATR ขั้นต่ำ |
| `InpMinEfficiency` | 0.65 | ทิศทางสุทธิ/ผลรวมการเปลี่ยน close สำหรับขาที่ไม่มี FVG |
| `InpMinBreakBodyRatio` | 0.50 | body/range ของแท่งเบรกสำหรับขาที่ไม่มี FVG |
| `InpConfirmationBars` | 30 | รอยืนยันหลังเข้าโซนไม่เกิน 1–300 แท่ง M1 |
| `InpTradeSide` | RP_ALL_SIDES | ทั้ง Buy/Sell, RP_BUY_ONLY หรือ RP_SELL_ONLY |
| `InpM5BreakBufferPoints` | 0 | ระยะเพิ่มจาก swing M5 ที่ราคาปิดต้องทะลุ, ≥ 0 points |
| `InpM1BreakBufferPoints` | 0 | ระยะเพิ่มจาก LH/HL M1 ที่ราคาปิดต้องทะลุ, ≥ 0 points |
| `InpTouchMode` | RP_TOUCH_WICK | ไส้แตะโซน หรือ RP_TOUCH_CLOSE ให้ราคาปิดอยู่ในโซน |
| `InpInvalidationMode` | RP_INVALIDATE_CLOSE | ปิดเลยขอบไกลจึงยกเลิก หรือ RP_INVALIDATE_WICK ให้ไส้เลยก็ยกเลิก |
| `InpMaxCloseTailRatio` | 0.25 | ระยะ Close ถึงปลายแท่งด้านการเบรก / range สำหรับ displacement; 0–1 |

### การปรับค่าร่วมกันระหว่าง Indicator กับ EA

ค่ากลุ่ม MACD, ประวัติ, โซน, แรงส่ง, ระยะรอยืนยัน และ Signal tuning ต้องตรงกันเมื่อใช้เทียบสัญญาณ รวมทั้งใช้ symbol และประวัติช่วงเดียวกัน ค่าเริ่มต้นของรุ่น 1.10 คงกติกาสัญญาณของ 1.00 ไว้

- Buffer ใช้ **points ของ symbol**: ระยะราคา = จำนวน points × `_Point` เช่น `_Point=0.01` และ 20 points คือราคา 0.20
- Buy ต้องปิด **สูงกว่า** ราคา swing + buffer; Sell ต้องปิด **ต่ำกว่า** ราคา swing − buffer การปิดเท่าระดับยังไม่ผ่าน ทั้ง M5 และ M1
- ถ้าผ่านราคา swing เดิมแต่ยังไม่ผ่าน buffer จะยังไม่ใช้สิทธิ์เบรกนั้น เงื่อนไขห้ามใช้การเบรกก่อน touch และห้าม touch/เบรกในแท่งเดียวกันนับจากระดับที่รวม buffer แล้ว
- Touch ตรวจจากแท่ง M1 ที่ปิดแล้วเสมอ: โหมดไส้ยอมรับช่วง High–Low ตัดโซน; โหมด Close ต้องปิดอยู่ในโซน รวมกรณีเท่าขอบ
- Invalidation ตรวจขอบไกลก่อน touch/entry: โหมด Wick จะยกเลิกเมื่อไส้เลยขอบ แม้ปิดกลับเข้ามา; เท่าขอบยังไม่ยกเลิก
- `InpMaxCloseTailRatio` ใช้เฉพาะขาที่ผ่านด้วย displacement ค่าเล็กบังคับ Close ใกล้ปลายแท่งมากขึ้น; 0 ต้องปิดตรงปลาย และ 1 ไม่จำกัดตำแหน่ง Close แต่ยังตรวจ body/efficiency ไม่เปลี่ยนกติกา FVG

ค่าความเสี่ยงและ SL/TP buffer อยู่ใน EA ส่วน Indicator แสดงโซนและสัญญาณ ไม่คำนวณ lot หรือส่ง order เปลี่ยน Inputs แล้วระบบคำนวณประวัติใหม่ จึงควรบันทึกชุดค่าที่ใช้ทุกครั้งที่เปรียบเทียบผล

## กติกาสัญญาณที่สืบทอดจาก indicator

โซนใช้ Low–High เต็มแท่งของ swing ที่ถูกเบรก หรือแท่งสวนทาง/doji ล่าสุดก่อน impulse เบรก (ถ้าไม่มี ใช้แท่ง origin swing) ขาเบรกต้องมีระยะสุทธิขั้นต่ำเทียบ ATR ก่อนแท่งเบรก และมี FVG หรือผ่าน efficiency/body/close-location filters

ค่าเริ่มต้นตรวจ touch ด้วยแท่งปิด M1 ที่มีช่วงราคาแตะโซน M5 แล้วรอแท่งต่อมาปิดทะลุ LH/HL ที่ยืนยันมาก่อน ห้ามใช้การเบรกเก่าที่เกิดก่อน touch และไม่รับกรณี touch กับ break เกิดในแท่งเดียวกัน โซนหมดอายุตาม Inputs หรือถูกยกเลิกเมื่อ M1 ปิดเลยขอบไกล หนึ่ง M5 breakout มีหนึ่งโอกาสสัญญาณร่วมกันระหว่างสองโซน

สัญญาณที่เกิดแล้วแต่ EA ข้ามเพราะ R:R, spread, exposure หรือข้อกำหนด broker จะไม่รอจังหวะใหม่จากสัญญาณเดิม

## พฤติกรรมการส่งคำสั่ง

- หนึ่ง market order ต่อสัญญาณ พร้อม SL/TP ใน request เดียว
- ไม่เปิดซ้อนเมื่อ symbol มี position หรือ pending order อยู่ ไม่ว่าจะมาจาก EA นี้ ตัวอื่น หรือ manual ใช้กติกานี้ทั้ง netting และ hedging
- ตรวจ permissions, spread, quote age, stops/freeze, margin, volume และ `OrderCheck`
- เตรียม quote ใหม่ได้ไม่เกินสามรอบก่อนส่ง หากราคายังเปลี่ยนตลอดจะข้าม; **ไม่ retry OrderSend**
- หลัง re-connect ที่ข้ามหลายแท่งจะ sync แล้วรอแท่งใหม่ ไม่ไล่เปิดรายการที่พลาดไป
- ถ้าประวัติยังโหลดไม่สำเร็จจะลองอ่านใหม่ภายในหน้าต่างเวลา entry เท่านั้น
- บันทึก signal attempt และ pending latch ก่อนส่งคำสั่ง ใช้ lock ระดับ account+symbol ระหว่าง instance ของ EA ใน terminal เดียวกัน
- ปฏิเสธชัดเจน: ไม่ส่งซ้ำสัญญาณนั้น แต่รับสัญญาณใหม่ได้
- ผลไม่แน่ชัด เช่น timeout, PLACED, partial fill: หยุดส่งรายการถัดไปจนตรวจสอบและปลด pending latch
- ไม่มี trailing, break-even, แบ่งปิด, เพิ่มไม้ หรือการย้าย TP ตาม swing ใหม่

ใน Strategy Tester ใช้ marker ในหน่วยความจำต่อ run จึงไม่ให้ผลการรันทดสอบก่อนหน้าบล็อก run ใหม่

## กู้สถานะหลังผลส่งคำสั่งไม่แน่ชัด

1. ดู Experts/Journal เพื่อหา retcode, order, deal และชื่อ recovery key เช่น `MZT.<hash>.pending`
2. ตรวจ **Trade และ History** ให้ทราบว่ามี position/order/deal จริงหรือไม่ รวมถึง SL/TP ที่ broker รับ
3. หลังตรวจแล้ว หากต้องการให้ EA รับสัญญาณใหม่ เปิด **Tools → Global Variables (F3)** และลบเฉพาะ key `.pending` ที่ log ระบุ
4. เก็บ key `.B`/`.S` ของ signal attempt ไว้เพื่อป้องกันส่งสัญญาณเก่าซ้ำ EA จะรอสัญญาณใหม่

การปลด latch ไม่ปิด/แก้ไข position ที่มีอยู่ และ exposure guard ยังทำงานตามปกติ

## การทดสอบและข้อจำกัด

ดูขั้นตอน Strategy Tester, test cases และผลตรวจใน [testing.md](testing.md) มีไฟล์ `tester-demo.set` สำหรับโหลดใน Tester โดยเปิด Execute และตั้ง risk 1%

ประวัติ M1/M5 และ EMA seed มีผลต่อ swing: การเติมข้อมูล, เลื่อนหน้าต่าง HistoryM5Bars หรือเปลี่ยน Inputs อาจทำให้ผลย้อนหลังเปลี่ยนได้ TP/SL ที่ส่งแล้วไม่เปลี่ยนตามการคำนวณประวัติใหม่

รุ่นนี้ตรวจด้วย tests ของโค้ดจริงและคอมไพล์ MetaEditor ยังไม่มีผล Strategy Tester บน tick ของ broker หรือผล forward test จึงยังไม่อ้าง win rate/กำไร
