# MT5 Trading Tools

รวม EA และ Indicator สำหรับ MT5 ในโปรเจกต์เดียว แต่ละตัวมี source, คู่มือ, tests และชุดติดตั้งแยกกัน

| ประเภท | เครื่องมือ | ใช้ทำอะไร | คู่มือ | ชุดติดตั้ง |
|---|---|---|---|---|
| EA | Scalp Calculator | ลาก SL/TP คำนวณ Lot/RR แล้ว Execute + ปุ่ม Instant Engulf | [คู่มือ](docs/experts/scalp-calculator/README.md) | [ZIP](dist/experts/scalp-calculator/ScalpCalculator-1.05.zip) |
| EA | Instant Engulf | กด Buy/Sell ตรวจ PA, SL + buffer, TP 1:1 | [คู่มือ](docs/experts/instant-engulf/README.md) | [ZIP](dist/experts/instant-engulf/InstantEngulf-1.02.zip) |
| EA | Trade Journal | บันทึกการเทรด/SL/TP ลง CSV และส่งออก HTML พร้อมกราฟ M1/M5/M15 | [คู่มือ](docs/experts/trade-journal/README.md) | [ZIP](dist/experts/trade-journal/TradeJournal-1.20.zip) |
| EA | Trend Sweep Trader | M5 sweep/reclaim ตามเทรนด์ EMA, เป้า 2R, ตรวจ room/spread/risk | [คู่มือ](docs/experts/trend-sweep-trader/README.md) | [ZIP](dist/experts/trend-sweep-trader/TrendSweepTrader-1.00.zip) |
| Indicator | Trend Sweep Reclaim | สัญญาณ M5 กวาดขอบช่วงแล้วปิดกลับ พร้อม planned SL/TP | [คู่มือ](docs/indicators/trend-sweep-reclaim/README.md) | [ZIP](dist/indicators/trend-sweep-reclaim/TrendSweepReclaim-1.00.zip) |
| EA | Opening Range Trader | Opening Range breakout/retest/reclaim M5, ATR stop และเป้า 2R | [คู่มือ](docs/experts/opening-range-trader/README.md) | [ZIP](dist/experts/opening-range-trader/OpeningRangeTrader-1.00.zip) |
| Indicator | Opening Range Retest | กรอบช่วงเปิดตลาด พร้อม breakout/retest signal และ planned levels | [คู่มือ](docs/indicators/opening-range-retest/README.md) | [ZIP](dist/indicators/opening-range-retest/OpeningRangeRetest-1.00.zip) |
| EA | MACD Zone Trader | สัญญาณ MACDZonePullback → TP swing M5, SL pattern M1, เผื่อ spread แบบ Scalp และ R:R ≥ 1 | [คู่มือ](docs/experts/macd-zone-trader/README.md) | [ZIP](dist/experts/macd-zone-trader/MACDZoneTrader-1.10.zip) |
| EA | PA Reversal Trader | PA reversal + EMA20, SL ห่าง EMA ไม่เกิน 1.5 ATR, TP swing ถัดไป และรอแก้ R:R ได้ 1 แท่ง | [คู่มือ](docs/experts/pa-reversal-trader/README.md) | — |
| Indicator | TV Style MACD | MACD/Signal และ Histogram 4 สี | [คู่มือ](docs/indicators/tv-style-macd/README.md) | [ZIP](dist/indicators/tv-style-macd/TVStyleMACD-1.00.zip) |
| Indicator | PA Reversal | ลูกศรกลับทิศตามกติกา PA | [คู่มือ](docs/indicators/pa-reversal/README.md) | [ZIP](dist/indicators/pa-reversal/PAReversal-1.00.zip) |
| Indicator | MACD Swing Count | Swing จาก MACD cross / Histogram เปลี่ยนสี, HH/HL/LH/LL และเส้น S/R แบบ wick/body | [คู่มือ](docs/indicators/macd-swing-count/README.md) | [ZIP](dist/indicators/macd-swing-count/MACDSwingCount-1.20.zip) |
| EA | WickHunt Telegram | Logic ของ WickHuntSRFlow, ลูกศร/SR และ outbox สำหรับตัวส่ง Telegram กลาง | [คู่มือ](docs/experts/wick-hunt-telegram-ea/README.md) | [ZIP](dist/experts/wick-hunt-telegram-ea/WickHuntTelegramEA-1.00.zip) |
| Indicator | WickHuntSRFlow | Wick hunt → Close TF ย่อย reclaim → break/hold/retest พร้อมลูกศรย้อนหลังและโหมด tick เดิม | [คู่มือ](docs/indicators/wick-hunt-sr-flow/README.md) | [ZIP](dist/indicators/wick-hunt-sr-flow/WickHuntSRFlow-1.06.zip) |
| Indicator | WickHuntAnchor | H1 hunt กลับ Open ตรวจทุก M5 ปิด; first anchor เลือก FVG/Strong/OR/AND; Strong หางหัว <30% ไม่ใช้ MACD/SR | [คู่มือ](docs/indicators/wick-hunt-anchor/README.md) | [ZIP](dist/indicators/wick-hunt-anchor/WickHuntAnchor-1.09.zip) |
| Pine Indicator | WickHuntAnchor | เวอร์ชัน TradingView: H1/M5, first anchor FVG OR Strong, ลูกศรและ Alerts | [คู่มือ](docs/indicators/wick-hunt-anchor/pine.md) | [Pine v6](Pine/Indicators/WickHuntAnchor.pine) |
| Pine Indicator | WickHunt SR + Anchor | TradingView: SR breakout/pullback → break/hold/retest และ Anchor แยก engines/ลูกศร/Alerts | [คู่มือ](docs/indicators/wick-hunt-sr-flow/pine.md) | [Pine v6](Pine/Indicators/WickHuntSRAnchor.pine) |
| Indicator | EngulfFlow | Engulf เนื้อ/ไส้, เปิดปิด hunt, กรองช่วงก่อนหน้าและ EMA 20/54 พร้อมลูกศรล่วงหน้า 5 วินาที | [คู่มือ](docs/indicators/engulf-flow/README.md) | [ZIP](dist/indicators/engulf-flow/EngulfFlow-1.05.zip) |
| Indicator | ImbalanceFlow | FVG + แรงส่งไม่มี gap แบบแท่งเดี่ยว/หลายแท่ง ปรับเกณฑ์และโซนผ่าน Inputs | [คู่มือ](docs/indicators/imbalance-flow/README.md) | [ZIP](dist/indicators/imbalance-flow/ImbalanceFlow-1.11.zip) |
| Indicator | EngulfImbalanceFlow | FVG-only, ไม่กรองเทรนด์, ไส้หัว engulf ≤10%; ถ้าปิดเลยไส้เดิมเกิน 30% ของเนื้อต้องย่อกลับภายใน 2 แท่งจึงเข้า | [คู่มือ](docs/indicators/engulf-imbalance-flow/README.md) | [ZIP](dist/indicators/engulf-imbalance-flow/EngulfImbalanceFlow-1.08.zip) |
| Indicator | MACD Zone Pullback | M5 Histogram swing + แรงส่ง/FVG → Demand/Supply retest → M1 ปิดทะลุ LH/HL | [คู่มือ](docs/indicators/macd-zone-pullback/README.md) | [ZIP](dist/indicators/macd-zone-pullback/MACDZonePullback-1.10.zip) |

## โครงสร้าง

```text
MQL5/
  Experts/                   EA — ชื่อเดิมที่ใช้ใน MT5
    ScalpCalculator/
    InstantEngulf/
    TradeJournal/
    WickHuntTelegramEA/
    MACDZoneTrader/
    TrendSweepTrader/
  Scripts/
    TradeJournal/            ส่งออก HTML ด้วย ExportJournalReport
  Indicators/                Indicator — ชื่อเดิมที่ใช้ใน MT5
    TVStyleMACD/
    PAReversal/
    MACDSwingCount/
    WickHuntSRFlow/
    WickHuntAnchor/
    EngulfFlow/
    ImbalanceFlow/
    EngulfImbalanceFlow/
    MACDZonePullback/
    TrendSweepReclaim/
Pine/
  Indicators/                Indicator สำหรับ TradingView (Pine Script v6)
docs/
  experts/<product>/         คู่มือและสเปกของแต่ละ EA
  indicators/<product>/      คู่มือของแต่ละ Indicator
  structure.md               วิธีจัดไฟล์และรายการเปลี่ยน path
tests/<product>/             ชุดทดสอบแยกตามเครื่องมือ
scripts/
  products.json              รายการเครื่องมือและตำแหน่งไฟล์
  test.sh                    ทดสอบทั้งหมดหรือเฉพาะตัว
  compile-macos.sh           คอมไพล์ด้วย MetaEditor บน Mac
  package.py                 สร้าง ZIP จาก build ที่คอมไพล์แล้ว
  tests/<product>.sh         test runner ของแต่ละเครื่องมือ
dist/
  experts/<product>/         EX5, ZIP, compiler log, manifest
  indicators/<product>/      EX5, ZIP, compiler log, manifest
  archive/legacy-layout/     ชุดติดตั้งเดิมก่อนจัดโครงสร้าง
```

`<product>` ใช้ชื่อ `scalp-calculator`, `instant-engulf`, `trade-journal`, `tv-style-macd`, `pa-reversal`, `macd-swing-count`, `engulf-flow`, `imbalance-flow`, `engulf-imbalance-flow`, `macd-zone-pullback`, `macd-zone-trader` อย่างสม่ำเสมอ ส่วนชื่อ `.mq5/.ex5` คงเดิมตามที่ MT5 ใช้

## คำสั่งสำหรับพัฒนา

เรียกจาก root ของโปรเจกต์:

```sh
# ทดสอบทุกตัว หรือเลือกตัวเดียว
sh scripts/test.sh
sh scripts/test.sh instant-engulf

# คอมไพล์ทุกตัว หรือเลือกตัวเดียว (ต้องมี MetaEditor/Wine)
sh scripts/compile-macos.sh
sh scripts/compile-macos.sh tv-style-macd

# แพ็ก build ที่คอมไพล์แล้ว เป็น ZIP พร้อมคู่มือและ tests
python3 scripts/package.py
python3 scripts/package.py pa-reversal
```

Test ใช้ Python 3 และ clang++ (Trade Journal ใช้ Node.js เพิ่มสำหรับ HTML model tests) โดยไม่เปิด MT5 หรือส่งออเดอร์ คำสั่ง compile เรียกเฉพาะ MetaEditor; คำสั่ง package ตรวจอายุ EX5 และ compiler log ก่อนแพ็ก โดยไม่ได้รันทดสอบให้เอง

## ติดตั้ง

ดาวน์โหลด ZIP ของตัวที่ต้องการ แล้วคัดลอกโฟลเดอร์ใต้ `MQL5/Experts` หรือ `MQL5/Indicators` ไปยัง Data Folder ของ MT5 จากนั้น Refresh ใน Navigator ดู Inputs และข้อจำกัดของแต่ละตัวในคู่มือก่อนใช้งาน

ไฟล์ `.ex5` ที่อยู่ข้าง source เป็นผลลัพธ์ปกติของ MetaEditor และไม่เข้า Git เช่นเดียวกับ `dist/` คู่มือแต่ละตัวระบุขอบเขตการตรวจสอบไว้ การผ่าน unit tests/compile ไม่ได้ยืนยันการแสดงผลหรือการส่งออเดอร์กับ broker จริง

ข้อมูลตลาด รูปกราฟ และรายงานที่สร้างจาก backtest ใต้ `tests/reports/` ไม่เข้า Git ส่วนสคริปต์ replay และบันทึก Markdown ยังคงอยู่ใน repository หากต้องการรัน backtest ซ้ำ ให้เตรียมข้อมูลตลาดไว้ในเครื่องตามคู่มือของแต่ละชุด

รายละเอียดการจัดชื่อและย้ายไฟล์อยู่ใน [แนวทางโครงสร้างโปรเจกต์](docs/structure.md)
