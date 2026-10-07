# TV Style MACD — Indicator สำหรับ MT5

MACD ในหน้าต่างแยกที่ใช้รูปแบบ TradingView: **MACD สีน้ำเงิน, Signal สีส้ม, Histogram 4 สี และเส้นศูนย์** ปรับค่าและเปิด–ปิดแต่ละส่วนได้ ใช้งานร่วมกับ Scalp Calculator EA บนกราฟเดียวกันได้

## ติดตั้ง

1. MT5 → **File → Open Data Folder**
2. คัดลอกโฟลเดอร์ `MQL5/Indicators/TVStyleMACD` จาก ZIP ไปยัง `MQL5/Indicators`
3. Navigator → Indicators → คลิกขวา **Refresh**
4. ลาก **TVStyleMACD** ลงบนกราฟ ตั้งค่าในแท็บ **Inputs**

ใช้ไฟล์ `.ex5` ที่คอมไพล์แล้วได้เลย หากแก้โค้ดให้เปิด `.mq5` ใน MetaEditor และกด F7 โดยเก็บ `MACDCore.mqh` ไว้ข้างกัน ไม่ต้องเปิด Algo Trading เพื่อใช้ Indicator นี้ และไม่มีคำสั่งเปิด/ปิดออเดอร์

## สูตรและค่าเริ่มต้น

```text
Fast = EMA(Source, 12)
Slow = EMA(Source, 26)
MACD = Fast − Slow
Signal = EMA(MACD, 9)
Histogram = MACD − Signal
```

Source เริ่มที่ Close สามารถเลือก **Close, Open, High, Low, HL2, HLC3, OHLC4, HLCC4** และเลือก **EMA หรือ SMA** สำหรับ Oscillator กับ Signal แยกกันได้ ไม่ใช้ Signal SMA ของ MACD มาตรฐาน MT5 มาแทน EMA โดยไม่แจ้ง

EMA ใช้ `alpha = 2 / (length + 1)` และเริ่มจาก source ตัวแรกที่ใช้ได้ SMA รอครบจำนวนข้อมูลของแต่ละหน้าต่างก่อนแสดงผล เมื่อเป็น SMA/SMA จึงต้องรอถึง `max(fast, slow) + signal − 1` แท่งจึงมี Histogram ค่าแรก

## เปิด–ปิดส่วนต่าง ๆ

| Input | ผล |
|---|---|
| `InpShowMACD` | เส้น MACD |
| `InpShowSignal` | เส้น Signal |
| `InpShowHistogram` | แท่ง Histogram |
| `InpShowZeroLine` | เส้นศูนย์ |
| `InpShowDataWindow` | ค่าใน Data Window |
| `InpShowToggleButtons` | ปุ่ม MACD / SIGNAL / HIST / ZERO บนหน้าต่าง Indicator; เริ่มต้นปิดเพื่อคงหน้าตาสะอาด |

เปลี่ยน Inputs ผ่าน **Ctrl+I → TVStyleMACD → Properties** การปิดเส้นไม่หยุดการคำนวณส่วนที่เหลือ เช่น ปิด MACD/Signal แล้วยังคำนวณ Histogram ได้ตามเดิม ส่วนที่ซ่อนจะไม่ถูกนำไปกำหนดสเกลแกนตั้ง

ปุ่มบนหน้าต่างเปลี่ยนการแสดงผลของ instance นั้นทันที ค่าเปิด–ปิดจากปุ่มจะกลับตาม Inputs เมื่อโหลด Indicator ใหม่หรือเปลี่ยน timeframe

## สี Histogram

| เงื่อนไข | สีเริ่มต้น | Input |
|---|---|---|
| Histogram ≥ 0 และสูงกว่าแท่งก่อน | เขียวเข้ม `#26A69A` | `InpPositiveRising` |
| Histogram ≥ 0 และไม่สูงกว่าแท่งก่อน | เขียวอ่อน `#B2DFDB` | `InpPositiveFalling` |
| Histogram < 0 และสูงกว่าแท่งก่อน (ติดลบน้อยลง) | แดงอ่อน `#FFCDD2` | `InpNegativeRising` |
| Histogram < 0 และไม่สูงกว่าแท่งก่อน (ติดลบเท่าเดิม/มากขึ้น) | แดงเข้ม `#FF5252` | `InpNegativeFalling` |

ตั้ง `InpFourColorHistogram=false` เพื่อใช้เพียงเขียวเข้มเมื่อ ≥ 0 และแดงเข้มเมื่อ < 0 สีทุกช่องปรับได้ เส้น MACD เริ่มที่ `#2962FF`, Signal `#FF6D00`, เส้นศูนย์ `#787B86`

`InpMACDWidth`, `InpSignalWidth`, `InpHistogramWidth`, `InpZeroWidth` ปรับความหนา 1–5; เส้นเลือก Solid/Dash/Dot ฯลฯ ได้จาก Inputs ของแต่ละเส้น บางรูปแบบเส้นประของ MT5 แสดงได้ตามคาดเฉพาะความหนา 1

## Timeframe

- `InpTimeframe=PERIOD_CURRENT`: ใช้ timeframe ของกราฟและอัปเดตแท่งปัจจุบันทุก tick
- เลือก timeframe อื่นเพื่อคำนวณ MACD จากแท่งของ timeframe นั้นโดยตรง ไม่ใช่คำนวณจากการทำซ้ำค่าราคา timeframe ใหญ่บนแท่งเล็ก
- `InpWaitForTimeframeClose=true`: แสดงค่าเมื่อแท่งต้นทางปิดในช่วงของแท่งกราฟนั้น จึงมีช่องว่าง Histogram ระหว่างจุดยืนยัน; เส้นเชื่อมจุดที่ยืนยันแล้ว
- `false`: ค่าอดีตใช้แท่งต้นทางล่าสุดที่ปิดแล้ว ส่วนแท่งกราฟล่าสุดใช้ค่าของแท่งต้นทางที่กำลังก่อตัวได้ การแสดงสดจึงอาจเปลี่ยนหลัง reload ตามพฤติกรรมของข้อมูลที่ยังไม่ปิด
- กรณี timeframe ต้นทางเล็กกว่ากราฟ ใช้ค่าต้นทางล่าสุดในช่วงแท่งกราฟ; เมื่อรอปิดจะใช้เฉพาะแท่งต้นทางที่ปิดแล้ว

โหมด MTF โหลดประวัติที่ MT5 มีของ timeframe ต้นทางและ map ตามเวลา ไม่มีการนำค่าปิดสุดท้ายของแท่งใหญ่ไปใส่ย้อนหลังในแท่งเล็กก่อนเวลาปิด ค่า `Wait` ไม่ปิดการอัปเดตแท่งปัจจุบันเมื่อใช้ timeframe เดียวกับกราฟ

หากประวัติ timeframe ต้นทางยังโหลดไม่พร้อม Indicator จะรอการคำนวณรอบถัดไป ประวัติที่ยาวมากในโหมด MTF ใช้ทรัพยากรมากกว่าโหมด Current เพราะต้องตรวจและ map series ตามเวลา

## Alerts (เริ่มต้นปิด)

- `InpAlertPositiveCross`: Histogram จาก ≤ 0 ขึ้นไป > 0
- `InpAlertNegativeCross`: Histogram จาก ≥ 0 ลงไป < 0
- เลือก Popup และ/หรือเสียงผ่าน `InpPopupAlert`, `InpSoundAlert`, `InpSoundFile`

แจ้งเฉพาะแท่งต้นทางที่ปิดแล้ว ครั้งเดียวต่อแท่ง ไม่แจ้งย้อนหลังตอนเพิ่ง attach และไม่แจ้งเพียงเพราะแท่งปัจจุบันแกว่งผ่านศูนย์ ไม่มีการส่งข้อความภายนอกบัญชี

## ความเหมือนกับ TradingView และขอบเขตที่ตรวจแล้ว

ใช้สูตร, ค่าเริ่มต้น, ตัวเลือก EMA/SMA และการแบ่งสีแบบ TradingView MACD มาตรฐาน ไม่ใช่การแปลง custom MACD ของผู้เขียนรายอื่น

**ยังไม่อ้างว่าตรง TradingView ทุก pixel หรือผ่านการเปรียบเทียบ feed เดียวกันแล้ว** ตัวเลขขึ้นกับราคา OHLC, เขตเวลา/ขอบแท่ง, ประวัติที่โหลดและจุดเริ่ม EMA ถ้า TradingView ใช้ symbol จากคนละ provider กับ MT5 ค่าอาจต่างกัน แม้สูตรเดียวกัน Native rendering ของ MT5 ยังต่างเรื่องช่องไฟ/ความกว้าง Histogram ตาม zoom, transparency, ฟอนต์ และเส้นแกน; ความกว้าง native Histogram จำกัด 1–5 pixel

ตรวจแล้ว:

- MetaEditor คอมไพล์ **0 errors, 0 warnings** ได้ `.ex5`
- **70,688 checks** จาก production `MACDCore.mqh` และฟังก์ชัน `CalculateBar` จริง เทียบกับ oracle ที่คำนวณ SMA จากหน้าต่างโดยตรงและ EMA จากผลรวม geometric weights
- ครอบคลุม EMA/EMA, EMA/SMA, SMA/EMA, SMA/SMA, lengths=1, fast>slow, history สั้น, warmup, source ทั้ง 8 แบบ, สีทั้งสี่, การคำนวณ tick ซ้ำ, เพิ่มแท่ง, cross และตัวเลือก mapping MTF
- ยังไม่ได้ตรวจหน้าจอ MT5 จริงหรือเปรียบเทียบ CSV จาก TradingView และยังไม่ได้ตรวจ integration ของการ map เวลา MTF กับ terminal จริง

รัน test ด้วย `sh scripts/test.sh tv-style-macd` มี Pine script ช่วยเปรียบเทียบที่ `tests/tv-style-macd/reference.pine` ใช้ข้อมูลสังเคราะห์เดียวกันได้โดยไม่ต้องหา broker feed ให้ตรงกัน แต่ไม่ได้รันใน TradingView ระหว่างการสร้างครั้งนี้

ก่อนใช้งาน ให้เช็กค่าใน Data Window เทียบ TradingView ด้วย symbol/provider, timeframe, source, MA type และช่วงข้อมูลเดียวกัน ตรวจทั้งแท่งที่ปิดแล้วและ live bar ทดลองปิดแต่ละส่วน, เปลี่ยน timeframe และทดสอบ MTF แบบ Wait ON/OFF

## สำหรับอ่านผ่าน iCustom

| Buffer | ค่า |
|---:|---|
| 0 | Histogram |
| 1 | Color index 0..3 |
| 2 | MACD |
| 3 | Signal |

Plots ที่ปิดจะเป็น `EMPTY_VALUE` ให้เปิดทั้งสามส่วนเมื่อต้องการอ่านค่าด้วย `CopyBuffer` อย่างต่อเนื่อง

## แหล่งอ้างอิง

- [MACD — TradingView Help Center](https://www.tradingview.com/support/solutions/43000502344-moving-average-convergence-divergence-macd-indicator/) — สูตรและตัวเลือกหลัก
- [PineJS utility functions — TradingView](https://tradingview.com/charting-library-docs/latest/custom_studies/PineJS-Utility-Functions/) — สูตร EMA
- [Other timeframes and data — TradingView](https://www.tradingview.com/pine-script-docs/concepts/other-timeframes-and-data/) — gaps และข้อมูล timeframe อื่น
- [DRAW_COLOR_HISTOGRAM — MetaQuotes](https://www.mql5.com/en/docs/customind/indicators_examples/draw_color_histogram) — การวาด histogram ด้วย value/color buffers

เป็น implementation อิสระสำหรับ MT5 ไม่ใช่ผลิตภัณฑ์หรือโค้ดที่ TradingView รับรอง
