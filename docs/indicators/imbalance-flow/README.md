# ImbalanceFlow 1.11

Indicator สำหรับ MT5 ตรวจ FVG และแรงส่งแบบไม่มี gap (Displacement) บน symbol/timeframe ของกราฟ ใช้เฉพาะแท่งปิด วาดโซนแยกสีและติดตามการเติมโซน ค่าเริ่มต้นแสดงทั้งสองประเภท ปรับจาก Inputs ได้ทั้งหมด Displacement เป็นเกณฑ์วัดการเคลื่อนที่จาก OHLC ไม่ใช่การยืนยัน order-flow imbalance หรือรับประกันว่าโซนจะรับราคาได้

## เปลี่ยนชื่อในรุ่น 1.11

เปลี่ยนชื่อจาก FVG Finder (`FVGFinder`) เป็น **ImbalanceFlow** ให้ครอบคลุม FVG และแรงส่งไม่มี gap โดยคง logic, Inputs, ค่าเริ่มต้น และ buffer indices ของรุ่น 1.10

หลังติดตั้ง ให้ถอด FVGFinder เดิมออกจากกราฟ แล้วใส่ ImbalanceFlow พร้อมตั้ง Inputs ตามเดิม หากใช้ iCustom ให้เปลี่ยน path เป็น `ImbalanceFlow\\ImbalanceFlow` และอัปเดต template ที่อ้างชื่อเก่า

## เริ่มใช้งาน

- `InpDetectionMode = FVG_AND_DISPLACEMENT`: แสดง FVG และ Displacement (ค่าเริ่มต้น)
- `FVG_ONLY`: ใช้กติกา FVG เดิม
- `DISPLACEMENT_ONLY`: ดูแรงส่งโดยไม่ต้องเกิด FVG
- `InpDisplacementMethod`: ตรวจแท่งเดี่ยว, หลายแท่ง หรือทั้งคู่ ถ้าผ่านทั้งสองบนแท่งเดียวกัน เลือกแท่งเดี่ยวก่อน จากนั้นเลือกขาหลายแท่งที่สั้นที่สุดที่ผ่าน
- สี FVG ขึ้น/ลง = DarkGreen/Maroon; Displacement ขึ้น/ลง = Teal/DarkOrange ขอบหนา 2 ชี้กล่องเพื่อดูชนิดและเวลาเปิดแท่งสัญญาณ

## กติกา FVG

เรียงแท่ง 1 → 2 → 3 จากเก่าไปใหม่ โดยทั้งสามแท่งต้องปิดแล้ว:

- **Bullish FVG:** `Low[3] > High[1]` โซนอยู่ระหว่าง `High[1]` ถึง `Low[3]`
- **Bearish FVG:** `High[3] < Low[1]` โซนอยู่ระหว่าง `High[3]` ถึง `Low[1]`
- ไส้แท่ง 2 ต้องครอบคลุมช่องว่างทั้งหมด เพื่อแยก session gap ที่แท่งกลางไม่ได้วิ่งผ่านโซนออก
- ไส้แท่ง 1 และ 3 แตะกันพอดีไม่เป็น FVG และขนาดช่องว่างต้องไม่น้อยกว่า `InpMinGapPoints × _Point`
- ค่าเริ่มต้นไม่บังคับสีแท่งกลาง ถ้าเปิด `InpRequireMiddleDirection` แท่ง 2 ต้องเขียวสำหรับ Bullish หรือแดงสำหรับ Bearish; doji จะไม่ผ่าน
- ไม่มีตัวกรอง ATR/ขนาด body ขั้นต่ำ และไม่บังคับให้ทั้งสามแท่งมีสีเดียวกัน

ตัวอย่าง Bullish: แท่ง 1 มี High = 100, แท่ง 3 มี Low = 102 และแท่ง 2 ครอบคลุม 100–102 จะได้โซน 100–102 หลังแท่ง 3 ปิด

นิยามช่องว่างระหว่างไส้ของแท่งรอบแท่งกลางอ้างอิง [TrendSpider: Fair Value Gap Basics](https://trendspider.com/blog/fair-value-gap-basics/) ส่วนเงื่อนไขและตัวเลือกของ implementation นี้ระบุไว้ข้างต้น

## กติกา Displacement

**แท่งเดี่ยว** ต้องไปตามทิศทางและผ่านทุกข้อ:

```text
Range = High − Low
Body = abs(Close − Open)
Body / ATR_before ≥ InpMinBodyATR
Body / Range ≥ InpMinBodyRatio
BUY:  (High − Close) / Range ≤ InpMaxTailRatio
SELL: (Close − Low) / Range ≤ InpMaxTailRatio
```

ถ้าเปิด RelativeBody (`InpMinRelativeBody > 0`) ต้องมี Body / median(Body ของ N แท่งก่อนหน้า) ≥ ค่าที่ตั้ง ค่า 0 ปิดตัวกรองนี้; median เป็น 0 จะไม่ผ่านเมื่อเปิดกรอง

**หลายแท่ง** ทดสอบความยาว MinLegBars ถึง MaxLegBars:

```text
Net = Close สุดท้าย − Close ก่อนเริ่มขา
Travel = ผลรวม abs(Close[j] − Close[j−1]) ตั้งแต่แท่งแรกถึงแท่งสุดท้าย
abs(Net) / ATR_before ≥ InpMinLegATR
abs(Net) / Travel ≥ InpMinEfficiency
จำนวนแท่งเนื้อเทียนตามทิศ / จำนวนแท่งในขา ≥ InpMinDirectionRatio
ไส้ด้านปลายทางของแท่งสุดท้าย / Range แท่งสุดท้าย ≤ InpMaxLegTailRatio
```

แท่งสุดท้ายต้องมีเนื้อเทียนตามทิศ Net; doji ไม่ผ่านเป็นแท่งสุดท้าย และไม่นับเป็นแท่งตามทิศ ตัวอย่าง .66 ยอมรับ 2 ใน 3 แท่ง แต่ .67 จะไม่รับเพราะ 2/3 ≈ .6667 ตัวกรองของแท่งเดี่ยวไม่บังคับกับแต่ละแท่งของขาหลายแท่ง Efficiency ใช้ Close จึงไม่ได้วัดการสะบัดภายในแท่งทั้งหมด

ATR ของรุ่นนี้เป็น **SMA ของ True Range** ย้อนหลัง N แท่งก่อนเริ่มขา (รวม previous close ใน True Range) ไม่ใช่ Wilder/RMA; ไม่นำแท่งสัญญาณหรือขาแรงส่งไปเพิ่ม ATR ของตัวเอง ข้อมูลอ้างอิง ATR/median/breakout อ่านก่อน lookback ได้ แต่แท่ง impulse และต้นทางโซนต้องอยู่ใน lookback ข้อมูลไม่ครบ/ผิดรูปแบบ, ATR/Range เป็น 0 จะไม่ผ่าน

เมื่อ `InpRequireBreakout=true`: BUY ต้องปิดเหนือ High สูงสุดของ N แท่ง **ก่อนเริ่มขา** บวก buffer×ATR; SELL ต้องปิดต่ำกว่า Low ต่ำสุดลบ buffer×ATR เท่าระดับไม่ผ่าน เกณฑ์นี้ใช้ขอบราคาย้อนหลัง ไม่ได้ใช้ MACD swing

เมื่อ `InpRejectTimeGaps=true`: ช่วงอ้างอิงและ impulse ต้องห่างเท่ากับ PeriodSeconds ของกราฟ จึงอาจไม่ให้สัญญาณช่วงหลังหยุดตลาดจนมีประวัติต่อเนื่องครบ สำหรับกราฟ Monthly ที่จำนวนวันไม่คงที่ เงื่อนไขนี้อาจบล็อก; ปิดได้แต่จะยอมให้ช่วงข้าม session/ข้อมูลขาดมีส่วนใน ATR และแรงส่ง ไม่มีแท่งอนาคตถูกใช้ในการตรวจแรงส่ง

## พื้นที่โซน Displacement

| `InpDisplacementZone` | พื้นที่ที่วาด |
|---|---|
| `DP_BASE_WICK` | High/Low ของแท่งสวนทางหรือ doji สุดท้ายก่อนเริ่มขา ภายใน BaseSearchBars; ถ้าไม่พบใช้แท่งก่อนเริ่มขา |
| `DP_BASE_BODY` | เช่นเดียวกัน แต่ใช้ขอบเนื้อเทียน; ถ้าต้นทางเป็น doji เนื้อเทียนกว้าง 0 จะข้ามโซนนั้น |
| `DP_IMPULSE_BODY` | จาก Open ของแท่งแรกในขา ถึง Close ของแท่งสุดท้าย อาจได้โซนกว้างมาก |

โซนต้นทางต้องมีการปิดออกจากขอบในทิศแรงส่งแล้วจึงสร้าง กล่องเริ่มที่แท่งต้นทาง แต่ **สัญญาณเพิ่งทราบเมื่อแท่งแรงส่งสุดท้ายปิด** ไม่ใช่ตั้งแต่ต้นทาง แต่ละต้นทาง/ทิศทางสร้าง Displacement ครั้งเดียวใน lookback ที่สแกน เพื่อไม่ให้ขาที่ต่อเนื่องสร้างกล่องต้นทางเดิมซ้ำ การเลื่อน lookback หรือแก้ Inputs/ประวัติอาจทำให้เหตุการณ์ที่เลือกใหม่เปลี่ยนได้

FVG และ Displacement เป็นการตรวจอิสระ จึงอาจเกิดพร้อมกันและมีสองกล่องบนแท่งเดียวกัน ค่า MaxZones จำกัดจำนวนกล่องรวมสองชนิด เลือกแท่งใหม่ที่สุดก่อน ถ้าเวลาเท่ากัน FVG ได้ลำดับก่อน

## การเติมโซน

FVG เริ่มตรวจตั้งแต่แท่งถัดจากแท่ง 3; Displacement เริ่มตรวจตั้งแต่แท่งถัดจากแท่งแรงส่งสุดท้าย ใช้ `InpFillMode` และ `InpDisplacementFillMode` แยกกัน โดยใช้ **ไส้แท่งที่ปิดแล้ว** เช่นเดียวกับการตรวจจับ:

| โหมด | Bullish | Bearish |
|---|---|---|
| `FVG_FILL_FULL` (ค่าเริ่มต้น) | Low ลงถึงขอบล่าง | High ขึ้นถึงขอบบน |
| `FVG_FILL_TOUCH` | Low ลงถึงขอบบน | High ขึ้นถึงขอบล่าง |

แตะขอบพอดีนับว่าเติม; ราคา gap ข้ามขอบดังกล่าวก็นับด้วย ในโหมด FULL การเติมเพียงบางส่วนจะคงขอบเขตโซนเดิม ไม่ย่อกล่อง

ค่าเริ่มต้นซ่อนโซนที่เติมแล้ว ถ้าเปิด `InpShowFilled` จะแสดงโซนเหล่านี้เป็นสีเทาและหยุดกล่องที่ปลายแท่งแรกที่เติมสำเร็จ โซน active จะยืดถึงแท่งปัจจุบันบวก `InpExtendBars` ช่วงเวลาแท่ง การเติมระหว่างแท่งยังไม่ปิดจะรอยืนยันเมื่อมี tick แรกของแท่งใหม่

กล่องเริ่มที่แท่ง 1 เพื่อแสดงรูปแบบทั้งชุด แต่ FVG เพิ่งทราบหลังแท่ง 3 ปิด ห้ามตีความว่ามีสัญญาณตั้งแต่แท่ง 1

## Inputs

| Input | ค่าเริ่มต้น | ความหมาย |
|---|---|---|
| `InpLookbackBars` | 500 | สแกนแท่งปิดล่าสุด 3–5000 แท่ง; ทั้ง 3 แท่งต้องอยู่ในหน้าต่างนี้ |
| `InpMinGapPoints` | 0 | ขนาด FVG ขั้นต่ำเป็น points ของ symbol, ต้อง ≥ 0; ไม่ใช่ pips |
| `InpRequireMiddleDirection` | false | บังคับสีแท่งกลางให้ตรงทิศทาง |
| `InpFillMode` | FVG_FILL_FULL | เต็มโซนหรือแตะโซน |
| `InpShowFilled` | false | แสดงโซนที่เติมแล้ว |
| `InpShowBullish` / `InpShowBearish` | true | เปิด/ปิดการแสดงโซนแต่ละทิศ |
| `InpMaxZones` | 50 | แสดงโซนล่าสุดที่ผ่านตัวเลือกการแสดงผลรวมสองทิศ 1–500 โซน |
| `InpExtendBars` | 10 | ต่อกล่อง active จากเวลาเปิดแท่งปัจจุบัน 0–500 ช่วงเวลาแท่ง |
| `InpFillRectangles` | true | ระบายสีในกล่อง; false แสดงเฉพาะกรอบ |
| `InpBullishColor` | clrDarkGreen | สีโซนขาขึ้น |
| `InpBearishColor` | clrMaroon | สีโซนขาลง |
| `InpFilledColor` | clrDimGray | สีโซนที่เติมแล้ว |

จำนวนโซนที่แสดงและ lookback มีผลแยกกัน โซนที่เก่าเกิน lookback จะหายจากทั้งกราฟและ buffers แม้ยังไม่ถูกเติม เมื่อเปิด ShowFilled โซนที่เติมแล้วจะใช้โควตา MaxZones ด้วย; โซนที่ถูกซ่อนจะไม่ใช้โควตา


### Inputs เพิ่มใน 1.10

| Input | ค่าเริ่มต้น | ความหมาย / ขอบเขต |
|---|---|---|
| `InpDetectionMode` | FVG_AND_DISPLACEMENT | FVG อย่างเดียว / Displacement อย่างเดียว / ทั้งคู่ |
| `InpDisplacementMethod` | DP_SINGLE_OR_LEG | แท่งเดี่ยวหรือหลายแท่ง / DP_SINGLE_ONLY / DP_LEG_ONLY |
| `InpATRLength` | 14 | SMA True Range ก่อนเริ่มขา, 1–200 |
| `InpRejectTimeGaps` | true | ไม่รับช่วงประวัติ/impulse ที่เวลาไม่ต่อเนื่อง; ใช้เฉพาะ Displacement |
| `InpMinBodyATR` | 0.80 | เนื้อแท่งเดี่ยวขั้นต่ำเทียบ ATR, > 0 |
| `InpMinBodyRatio` | 0.70 | เนื้อ/ช่วง High–Low ขั้นต่ำ, > 0 ถึง 1 |
| `InpMaxTailRatio` | 0.15 | ไส้ด้านปลายทางของแท่งเดี่ยวสูงสุด, 0–1 |
| `InpMinRelativeBody` | 0 | Body/median body ก่อนหน้า; 0 ปิด, > 0 เปิด เช่น 1.5 |
| `InpRelativeBodyBars` | 20 | จำนวนแท่งอ้างอิง median, 1–200 |
| `InpMinLegBars` | 2 | จำนวนแท่งเริ่มทดสอบขาแรงส่ง, ≥ 2 |
| `InpMaxLegBars` | 4 | จำนวนแท่งสูงสุด, ≥ MinLegBars และ ≤ 10 |
| `InpMinLegATR` | 1.50 | ระยะ Net ขั้นต่ำเทียบ ATR ก่อนขา, > 0 |
| `InpMinEfficiency` | 0.75 | abs(Net)/Travel ขั้นต่ำ, > 0 ถึง 1 |
| `InpMinDirectionRatio` | 0.66 | สัดส่วนแท่งเนื้อเทียนตามทิศ, > 0 ถึง 1 |
| `InpMaxLegTailRatio` | 0.20 | ไส้ด้านปลายทางแท่งสุดท้ายของขา, 0–1 |
| `InpRequireBreakout` | true | ต้องปิดออกจากกรอบ High/Low ก่อนขา |
| `InpBreakoutBars` | 5 | จำนวนแท่งก่อนขาสำหรับกรอบ breakout, 1–200 |
| `InpBreakoutBufferATR` | 0.10 | ระยะต้องปิดพ้นกรอบเทียบ ATR, ≥ 0 |
| `InpDisplacementZone` | DP_BASE_WICK | ไส้ต้นทาง / เนื้อต้นทาง / เนื้อขาแรงส่ง |
| `InpBaseSearchBars` | 5 | ค้นแท่งสวนทาง/doji ก่อน impulse, 1–20 |
| `InpBullishDisplacementColor` | clrTeal | สีโซนแรงส่งขึ้น |
| `InpBearishDisplacementColor` | clrDarkOrange | สีโซนแรงส่งลง |
| `InpDisplacementFillMode` | FVG_FILL_FULL | เงื่อนไขปลดโซนแรงส่ง: เต็มโซน / แตะโซน |

Inputs ของ Displacement ไม่มีผลกับเกณฑ์ FVG เดิม และเพิ่มต่อท้าย Inputs เดิมเพื่อรักษาลำดับ arguments ของ iCustom ทุกค่าเป็นจุดเริ่มต้นทดลอง ยังไม่ได้ backtest ว่าให้ผลตอบแทนหรือ win rate ดีขึ้น

ต้องการแท่งเข้มขึ้น: เพิ่ม MinBodyATR/MinBodyRatio หรือเปิด MinRelativeBody เช่น 1.5 และลด MaxTailRatio ต้องการให้ขาหลายแท่งเข้มขึ้น: เพิ่ม MinLegATR/MinEfficiency/MinDirectionRatio ควรปรับทีละเกณฑ์และตรวจผลด้วยข้อมูลช่วงที่ไม่ได้ใช้เลือกค่า

## ติดตั้งและใช้งาน

1. แตก `ImbalanceFlow-1.11.zip`
2. คัดลอกโฟลเดอร์ `MQL5/Indicators/ImbalanceFlow` ลง Data Folder ของ MT5 ใต้ `MQL5/Indicators/`
3. Refresh ใน Navigator แล้วลาก **ImbalanceFlow** ลงกราฟ
4. เลือก timeframe และปรับ Inputs; ชี้ที่ขอบกล่องเพื่อดูทิศทาง ราคา และเวลาเปิดของแท่ง 3 ใน tooltip

แต่ละอินสแตนซ์มีชื่อ object ของตนเอง การถอด indicator จะลบเฉพาะ object ที่ตัวนั้นสร้าง สามารถติดตั้งซ้ำบนกราฟเพื่อเปรียบเทียบ Inputs ได้

## Buffers สำหรับ Data Window / iCustom

Buffers 0–2 บันทึก FVG ที่ **แท่ง 3**; 3–6 บันทึก Displacement ที่แท่งสุดท้ายของ impulse หลังปิด ไม่ลบเหตุการณ์เพราะโซนถูกเติม:

| Index | ค่า |
|---|---|
| 0 | ทิศทาง `+1` Bullish / `-1` Bearish |
| 1 | ขอบล่างของโซน |
| 2 | ขอบบนของโซน FVG |
| 3 | Displacement direction +1 / −1 |
| 4 | ขอบล่าง Displacement |
| 5 | ขอบบน Displacement |
| 6 | Displacement kind: 1 แท่งเดี่ยว / 2 หลายแท่ง |

แท่งที่ไม่พบ FVG, แท่งกำลังก่อตัว และแท่งนอก lookback ใช้ `EMPTY_VALUE` ตัวเลือกการแสดงผล เช่น MaxZones/ShowFilled/ShowBullish ไม่กรอง buffers ดังนั้น buffers **ไม่ใช่รายการโซน active** ไม่มี buffer สำหรับสถานะ fill

## พัฒนาและตรวจสอบ

```sh
sh scripts/test.sh imbalance-flow
sh scripts/compile-macos.sh imbalance-flow
python3 scripts/package.py imbalance-flow
```

Tests ตรวจ core และดึง `RebuildFVG`, `OnCalculate`, `OnDeinit` จริงมารันใน C++ โดยจำลอง chart API: bullish/bearish, ขอบราคา, minimum points, ข้อมูลผิดรูปแบบ, fill สองโหมด, การยืนยันแท่งปิด, การเติมบางส่วน, lookback, จำกัดจำนวนกล่อง, buffers, โหลด/เลื่อน/ลดประวัติ, การคำนวณใหม่ และการแยก object ตามอินสแตนซ์

ผลตรวจรุ่น 1.10: ผ่าน 5,043 checks ทดสอบ core และ OnCalculate/Rebuild จริง ครอบคลุม FVG เดิม, แรงส่งไม่มี gap, Buy/Sell สมมาตร, ATR ก่อนสัญญาณ, ไส้/เนื้อ/median, leg efficiency, breakout, ข้อมูลขาด, โซนสามแบบ, การกันซ้ำ, buffers แยก, fill และการคำนวณ incremental เทียบ full replay; ดูจำนวน checks ใน build-manifest ของแพ็กเกจ MetaEditor คอมไพล์ 0 errors / 0 warnings การทดสอบนี้ไม่ใช่ market backtest

การตรวจอัตโนมัติไม่ยืนยันภาพใน native MT5 ควรตรวจบนกราฟจริง: สี/กรอบบนพื้นกราฟ, สลับ timeframe/Inputs, เปิด ShowFilled, เปลี่ยน fill mode และติดสองอินสแตนซ์แล้วถอดทีละตัว

ระบบคำนวณใหม่เมื่อเกิดแท่งใหม่หรือ MT5 แจ้งว่าประวัติเปลี่ยน ไม่คำนวณซ้ำทุก tick ผลของแท่งที่ปิดแล้วคงเดิมตราบที่ราคาในประวัติและ Inputs ไม่เปลี่ยน; โซนอาจถูกซ่อนตาม lifecycle/lookback การหาการเติมโซนมีต้นทุนเพิ่มตาม lookback จึงจำกัดไว้ที่ 5000 แท่ง การต่อเวลาไปอนาคตใช้ `PeriodSeconds` จึงไม่ข้ามวันหยุดตลาดให้โดยอัตโนมัติ
