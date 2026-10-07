# WickHunt SR + Anchor — Pine Script v6, 1.02

[Source: WickHuntSRAnchor.pine](../../../Pine/Indicators/WickHuntSRAnchor.pine)

TradingView indicator ตัวเดียวรวม **WickHuntSRFlow 1.06 โหมด TF ย่อยปิด** กับ **WickHuntAnchor 1.01 โหมด TF ย่อยปิด** ค่าเริ่มต้น H1 / M5 ทั้งสองชุดใช้ TF จาก Inputs ร่วมกัน และทำงานแยกกัน ไม่ต้องติดตั้ง Pine Anchor ซ้อนอีกตัว

## ลูกศรสองชุด

| ชุด | Buy | Sell | แสดงเมื่อ |
|---|---|---|---|
| SR | ลูกศรขึ้นสีเขียว ป้าย `SR` ใต้แท่ง | ลูกศรลงสีแดง ป้าย `SR` เหนือแท่ง | ผ่านบริบทหลัก → reclaim → TF ย่อย break → hold → retest |
| Anchor | สามเหลี่ยมขึ้นสีฟ้า ป้าย `A` ใต้แท่ง | สามเหลี่ยมลงสีส้ม ป้าย `A` เหนือแท่ง | Wick hunt กลับถึง Open และ first anchor ผ่าน FVG OR Strong |

ตำแหน่งอิง High/Low ของ **แท่งบน TF กราฟที่เปิดดู** SR เริ่มห่าง 30 points, Anchor 80 points ปรับระยะแยกกันได้ เพื่อแสดงทั้งสองชุดในแท่งเดียวกัน หากแท่งสดขยายหางจะขยับตำแหน่งตามขอบแท่ง แต่ไม่เปลี่ยนราคา/เวลา/เงื่อนไขสัญญาณที่จำไว้

Anchor ไม่ใช่ตัวกรองเพิ่มเติมของ SR: มี `A` แล้วอาจไม่มี `SR` หรือมี `SR` โดยไม่มี `A` ก็ได้ แต่ละชุดจำสถานะแยกกัน หนึ่งสัญญาณต่อฝั่งต่อแท่งหลักของแต่ละชุด ถ้าผ่านทั้งสองในเวลาเดียวกันจะแสดงสอง markers และสามารถแจ้งเตือนทั้งคู่

เลือก `Enable SR signals` / `Enable Anchor signals` เพื่อใช้ชุดเดียวหรือทั้งคู่ การปิดการวาดเส้น S/R ไม่ปิดการตรวจ SR

## ติดตั้ง

1. เปิดกราฟ TradingView → Pine Editor → สร้าง Indicator ใหม่
2. คัดลอก **ไฟล์ source ทั้งหมด** รวม `//@version=6` วางแทนโค้ดเดิม
3. Save แล้ว Add to chart
4. Main / hunt timeframe = 1 hour, Check timeframe = 5 minutes เป็นค่าเริ่มต้น เปลี่ยนเป็น 15 minutes / 1 minute ได้

### ถ้าพบ `Script could not be translated from: ... string mainTF`

`string mainTF = input.timeframe(...)` เป็น syntax ที่ถูกต้องของ Pine v6 ข้อความนี้เป็นเบาะแสว่าตัวแปลอาจกำลังใช้รุ่นเก่า เช่นไม่ได้คัดลอก compiler annotation มาด้วย ไม่ใช่หลักฐานว่าตัวแปร `string` ผิด

ให้สร้าง Indicator ใหม่ กด Select All (`⌘A` บน Mac) ในพื้นที่โค้ด ลบโค้ดเดิมแล้ววาง **ไฟล์ทั้งชุด** ตรวจว่าบรรทัดแรกเป็นข้อความตรงนี้ ไม่มี code fence หรือช่องว่างนำหน้า:

```pine
//@version=6
```

บรรทัดต่อไปต้องเป็น `indicator("WickHunt SR + Anchor 1.02", ...)` ตาม source อย่าวางเฉพาะส่วนที่เริ่มจาก `string mainTF` และอย่าแปะเพิ่มท้าย indicator/template เดิม ถ้าไม่มี annotation TradingView จะถือว่าเป็น Pine v1 ตาม [เอกสาร Script structure](https://www.tradingview.com/pine-script-docs/language/script-structure/)

มีสำเนา plain text ที่ `dist/pine/wick-hunt-sr-anchor/WickHuntSRAnchor-Pine-1.02.txt` สำหรับเปิดและคัดลอกทั้งหมดโดยตรง หากยังมี error แม้สองบรรทัดแรกครบ ต้องอ่านข้อความ compiler ถัดไปเพื่อวินิจฉัยต่อ ไม่ถือว่าคำแนะนำนี้ยืนยัน compilation ของทั้ง script

รองรับกราฟแท่งเวลาปกติ เช่น M1, M5, M15, H1, H4 เมื่อ TF กราฟกับ TF ตรวจหารกันลงตัว Main TF ต้องใหญ่กว่า Check TF, หารกันลงตัว และไม่เกิน D1 ไม่ใช้แท่ง Heikin Ashi / Renko

กราฟสูงกว่า TF ตรวจอ่าน **ทุก intrabar** ผ่าน `request.security_lower_tf()` ไม่ข้ามไปดูแค่แท่งสุดท้าย กราฟเท่ากับ TF ตรวจใช้แท่งที่ปิดแล้ว กราฟเล็กกว่าจะรับผล TF ตรวจที่ปิดแล้วเมื่อเริ่มรอบถัดไป แล้วผูกลูกศรกับแท่งเล็กที่เพิ่งปิด

## SR: กฎจากรุ่น MT5

MACD ใช้ EMA 12 / 26 / 9 แบบ seed จาก Close แรกและ Signal seed 0 ตาม `SwingCore.mqh` โหมด Histogram color: Histogram เพิ่มจากค่าก่อนหน้าเป็นขาขึ้น; ไม่เพิ่มเป็นขาลง (flat zero ไม่เริ่มขา) ไม่ใช้จุดตัด MACD/Signal หรือ `ta.pivothigh/low` แท่งที่ยืนยัน swing อัปเดต extreme ของขาเก่าก่อน แล้วเริ่มขาใหม่ จึงเป็นส่วนของสองขาที่ติดกันเหมือนต้นฉบับ

Swing H/L ของ TF หลักและ TF ย่อยคำนวณแยกกัน S/R ใช้ wick หรือ body ของแท่ง pivot ตาม Input ใช้เฉพาะ swing ที่ยืนยันก่อนแท่งที่ทดสอบเปิดแล้ว

**Breakout** ค่าเริ่มต้น hunt หางก่อนหน้า 1 แท่ง: Buy hunt หางล่าง, Sell hunt หางบน ใน 5 แท่งหลักก่อนหน้าต้องมี H/L แตะ S/R ที่รู้ก่อนแท่งแตะเปิดแล้ว Buy ใช้ Swing H / Sell ใช้ Swing L **ไม่จำเป็นต้องปิดทะลุ S/R หลัก** หน้าต่าง 5 แท่งใช้หา base ไม่บังคับ base ยาว 5 แท่ง

ปลายหางต้องลากไปชนแท่งแรกทางซ้ายที่เป็นแท่งที่ 3 ยืนยัน **FVG ทิศเดียวกัน** และอยู่ใน body ของแท่งนั้น Buy anchor ต้องเขียวและหางบน ≤30% ของ High−Low; Sell ต้องแดงและหางล่าง ≤30% แท่งกลางต้องครอบคลุม gap หากแท่งแรกไม่ผ่านจะไม่ข้ามไปแท่งถัดไป

**Pullback** ค่าเริ่มต้น hunt 2 หางฝั่งเดียวกันในแท่งหลักเดียว: Buy มี Swing L → Close TF หลักข้าม Swing H ที่ยืนยันไว้ → ยืนยัน Swing H ใหม่ที่ pivot อยู่บน/หลังแท่ง breakout → retrace แล้ว hunt หางล่างพร้อมกลับ Open; Sell กลับด้าน เมื่อ Close TF หลัก break โครงสร้างทิศตรงข้าม จะเริ่มบริบทใหม่และรอ swing ปลายทางใหม่ Pullback ไม่ใช้ตัวกรอง touch/FVG ของ Breakout

เลือก Breakout, Pullback, Breakout + Pullback หรือ Legacy ได้ ถ้าผ่านทั้งสองบริบทตอน reclaim ใช้ tag Both และให้ SR หนึ่ง event ต่อฝั่ง ไม่ให้ซ้ำสองบริบท

**ยืนยัน TF ย่อยตามลำดับ**:

1. Close TF ย่อยกลับถึง Open หลัก แล้วจำ reclaim/บริบท ณ ตอนนั้น ไม่รับ breakout ของแท่ง reclaim เอง
2. แท่งหลังจากนั้นปิดข้าม S/R ที่ยืนยันก่อนแท่งเปิด: Buy Close ก่อนหน้า ≤SR และ Close ใหม่ >SR; Sell กลับด้าน ใช้ทั้ง Swing H และ L ของ TF ย่อยได้ เมื่อข้ามหลายเส้นเลือก swing ที่ยืนยันล่าสุด
3. แท่งถัดไปทันทีต้องปิดยืนฝั่งเดิม จำนวน hold เริ่มต้น 1; หากไม่ผ่านหรือขาดแท่ง ทิ้ง candidate และต้องรอการข้ามใหม่ในแท่งหลังจากนั้น
4. หลัง hold ครบ รอ **8 แท่งถัดไป** ย้อนแตะ S/R เดิมด้วย High/Low เมื่อแท่งรอปิดจึงแสดง SR ไม่ใช้หางแท่ง break/hold เป็น retest รับแท่งที่ 8 แต่ไม่รับแท่งที่ 9

ตรึงเส้นเดิมตลอด candidate แม้เกิด swing ใหม่ Setup หมดอายุเมื่อแท่งหลักจบ ไม่ยกไปแท่งถัดไป Retest ของแท่งรอสุดท้ายที่ปิดตรงจบแท่งหลักรับได้ แต่ reclaim/direct break ที่ปิดตรงจบแท่งหลักไม่เริ่ม event ใหม่

ตั้ง `Retest candles AFTER holds = 0` เพื่อให้แท่งเดียวปิด break แล้วแสดง SR เลย โหมดนี้ข้ามทั้ง hold และ retest ไม่ได้รอจำนวน Confirm bars ที่ตั้งไว้ ยังคงต้องผ่านบริบท/reclaim ก่อน และ break ภายในแท่งหลักเดิม

รายละเอียดต้นฉบับ: [คู่มือ WickHuntSRFlow](README.md)

## Anchor: กฎแยกจาก SR

Buy กวาด Low ของ N แท่งหลักก่อนหน้า แล้ว Close TF ย่อย ≥Open หลัก; Sell กวาด High แล้ว Close ≤Open หลัก จากนั้นตรวจแท่งแรกที่ปลายหางไปชนทางซ้าย:

- ผ่าน **FVG หรือ Strong** อย่างใดอย่างหนึ่ง ไม่จำเป็นต้องผ่านทั้งคู่
- Strong ใช้หางบนของ anchor สำหรับ Buy / หางล่างสำหรับ Sell **สั้นกว่า 10%** ของ High−Low; เท่ากับ 10% ไม่ผ่าน
- ค่าเริ่มต้นไม่บังคับสี ไม่บังคับแตะ body รับ FVG ทั้งสองทิศ และไม่ใช้ MACD/SR หรือ break/hold/retest
- หยุดที่ first collision แม้แท่งนั้นไม่ผ่าน ไม่ข้ามไปหาแท่งแข็งแรงที่ไกลกว่า
- ให้ A ทันทีในรอบ TF ย่อยปิดที่ผ่าน จำปลายหาง/anchor ตอนนั้น ไม่ลบเพราะหางหลักขยายภายหลัง รับผล TF ย่อยสุดท้ายที่ปิดตรงจบแท่งหลักได้

รายละเอียด: [WickHuntAnchor Pine](../wick-hunt-anchor/pine.md) Inputs ของ Anchor แยกจาก SR ทั้งจำนวนหาง, min hunt, min FVG, search, leading-wick threshold, สี/body และ OR/AND เปลี่ยนกฎ Anchor ไม่เปลี่ยนตัวกรอง FVG ของ SR

## Inputs สำคัญ

| กลุ่ม | ค่าเริ่มต้น / การปรับ |
|---|---|
| Timeframes | หลัก H1 / ตรวจ M5 ร่วมกันทั้งสองชุด |
| Signals | เปิด–ปิด SR / Anchor แยกกัน; เปิด Buy/Sell ร่วมกัน |
| MACD Histogram swings | EMA 12/26/9, warmup 0 = อัตโนมัติ, เก็บ 10 swings ล่าสุดต่อ TF, wick/body |
| SR: main context | Both, Breakout hunt 1, Pullback hunt 2, touch 5, FVG leading wick ≤30% |
| SR: lower confirmation | Hold 1, retest 8, High/Low retest; ปรับ Close buffer/tolerance เป็น points ได้ |
| Anchor: independent rules | Hunt 1, OR, leading wick <10%, สี/body/direction ปิด |
| History | เก็บแท่งหลักสำหรับค้น anchor 1000 (สูงสุด 5000), ขอแท่งตรวจ 100000 ตามสิทธิ์แผน |
| Display | แสดง 100 signals รวมสองชุด (สูงสุด 450); SR gap 30 / A gap 80 points; สี/ขนาดปรับได้ |
| Display SR | TF ย่อยเส้นจุด; TF หลักเส้นขีด; เปิด–ปิดแยกกันและจำกัดจำนวนเส้นที่วาดได้ |
| Alerts | ปิดเริ่มต้น; เลือกส่ง SR / Anchor แยกกันได้ |

`Point size = 0` ใช้ `syminfo.mintick` หากต้องการเทียบระยะกับ MT5 ใส่ `_Point` ของ broker เช่น 0.01 เอง Price feed, session และการแบ่งแท่งของ TradingView อาจต่างจาก MT5 จึงไม่รับรองว่าจำนวน/เวลาสัญญาณตรงกันทุกจุด

`Recent signals to draw = 0` ซ่อนลูกศรและเส้นประกอบ event โดยยังตรวจและแจ้งเตือนได้ จำนวนนี้รวมสองชุดและสองฝั่งตามเวลา ไม่แยกโควตาแต่ละชุด

## Alerts

เปิด `Enable new live alerts` และเลือก `Alert SR signals` / `Alert Anchor signals` แล้วสร้าง TradingView Alert → **Any alert() function call** จะได้ข้อความแยก SR/Anchor พร้อม Buy/Sell, เวลา, TF, pattern และ S/R/anchor ที่เกี่ยวข้อง แม้เปิดกราฟ H1/H4 อยู่ ไม่ส่งประวัติเก่าตอนโหลดและไม่ส่งซ้ำ event เดิมระหว่างแท่งกราฟสด

มี conditions `SR BUY`, `SR SELL`, `Anchor BUY`, `Anchor SELL` ให้เลือกแยก ใช้ Once Per Bar หากใช้เงื่อนไขชื่อฝั่ง ซึ่งจำกัดหนึ่ง alert ต่อแท่งกราฟ หากต้องการรับทุก event บนกราฟ H4 ให้ใช้ Any alert() function call ไม่เลือก Once Per Bar Close เพราะจะรอแท่งกราฟปิด เมื่อเปลี่ยน Inputs ต้องสร้าง alert ใหม่ตาม [snapshot ของ TradingView](https://www.tradingview.com/pine-script-docs/concepts/alerts/)

ตัวนี้ไม่ส่ง Telegram หรือเปิดออเดอร์โดยตรง

## ข้อจำกัดและสถานะ

ทั้งสดและย้อนหลังใช้แท่ง TF ย่อยที่ปิดแล้ว ไม่มีโหมด tick ของ EA การกลับ Open/retest ที่เกิดระหว่าง M5 แล้วปิดไม่ตรงเงื่อนไขอาจต่างจากโหมด tick

หากประวัติ TF ย่อยเริ่มกลางแท่งหลัก หรือขาดแท่งในรอบนั้น จะไม่สร้างสัญญาณใหม่จนเริ่มแท่งหลักรอบที่ข้อมูลครบ Main anchor cache สะสมจากช่วง TF ย่อยที่เข้าถึงได้ เมื่อขาดทั้งช่วง TF หลักจะเริ่ม cache ใหม่ ป้องกันค้นทะลุแท่งที่ไม่ได้เห็น ช่วงต้นข้อมูลอาจยังมี anchor history ไม่เต็มตาม Input

เส้น S/R บนกราฟแสดง swing ที่ได้รับระหว่างประมวลผล TF ย่อย เริ่มเส้นที่เวลายืนยันจริง จึงไม่ลากเส้นกลับไปดูเหมือนรู้ระดับก่อนยืนยัน ในช่วงเริ่มข้อมูลหรือขาดทั้งช่วง TF หลัก เส้นแสดงอาจยังไม่ครบชุดที่ context หลักคำนวณจากประวัติหลักได้ เส้นนี้ใช้เพื่อแสดงผลเท่านั้น บริบท touch/trend คำนวณใน TF หลักจาก swing ของมันเอง

TradingView จำกัด intrabars ตามแผนและ labels/lines สูงสุด 500 ตัว Script จำกัด markers 450 เพื่อเหลือโควตาเส้น S/R สูงสุด 50 เส้น ข้อมูล feed ที่ถูกแก้ไขย้อนหลังอาจเปลี่ยนผลเมื่อ reload ตาม [พฤติกรรม request ข้าม TF](https://www.tradingview.com/pine-script-docs/concepts/other-timeframes-and-data/)

**ตรวจ source แล้ว แต่ยังไม่ได้ยืนยันคอมไพล์/runtime บน TradingView** ไม่มี tests/backtest หรือ alert จริงตามคำขอเดิม ดู [pine-build.md](pine-build.md)

## การวาด Anchor ใน 1.01

เส้นของ family Anchor ใช้ timestamp ที่ event เกิด (`closedAt`) แทนเวลาเปิดแท่งหลัก และระดับปลายหางที่ event บันทึก ณ ตอนนั้น ระดับนี้เป็น snapshot อยู่แล้วและไม่ได้เลื่อนตามหางภายหลัง กฎ engine ของ SR และ Anchor ตัวรวมคงเดิม ไม่ใช่การพอร์ต filters/revalidation ใหม่ทั้งหมดของ standalone Anchor เข้ามาในรุ่นนี้

## Session continuity ใน 1.02

Engine ที่ใช้ร่วมกัน SR/Anchor ตรวจ source bar_index แทน timestamp ต่อกัน ยอมรับแท่งที่ต่อกันจริงใน canonical feed ผ่านช่วงไม่มีการซื้อขาย รับ first available bar ของ main window ใหม่เมื่อประมวลผล previous source bar แล้ว และรับ closed lower bar ที่สั้นกว่าปกติแต่ไม่เกิน main End. window แรกที่โหลดกลาง main window / invalid OHLC / index ขาด / close ไม่ถูกต้อง ยังไม่ผ่าน ไม่อ่าน final main H/L ล่วงหน้า

Pine ไม่มีตาราง quote sessions ของ broker MT5 จึงไม่ได้แยก provider omissions จากไม่มีการซื้อขายด้วย calendar แบบ MT5. กฎ SR breakout/pullback/hold/retest, Anchor filters และ frozen Anchor link คงเดิม แต่ eligibility ผ่านเวลาปิดตลาดที่ source bars ยังเรียงต่อกันได้ ยังไม่ port filters ใหม่ทั้งหมดของ standalone Anchor มาที่ combined engine
