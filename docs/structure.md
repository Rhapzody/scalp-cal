# แนวทางจัดไฟล์

## การตั้งชื่อ

- Source MT5 ใช้ PascalCase ตรงกับ entry point เช่น `InstantEngulf.mq5` และ `InstantEngulf.ex5` เพื่อคงชื่อใน Navigator และการเรียก `iCustom`
- โฟลเดอร์คู่มือ, tests และ distribution ใช้ชื่อเครื่องมือแบบตัวเล็กคั่นขีด เช่น `instant-engulf`
- คู่มือแรกชื่อ `README.md`; เอกสารเสริมตั้งตามหน้าที่ เช่น `requirements.md` และ `testing.md`
- C++ tests ใช้ชื่อ `*_tests.cpp`; Pine reference อยู่ในกลุ่ม MACD
- ZIP ใช้ `<MT5Name>-<version>.zip` โดยอ่าน version จาก `#property version` ใน source

## MQL5 layout

`MQL5/Experts` และ `MQL5/Indicators` ตรงกับวิธีติดตั้งใน MT5 อยู่แล้ว จึงไม่เพิ่มชั้น `src/` หรือเปลี่ยนชื่อ entry point Source และ binary ทุกตัวคงเนื้อหาเดิม มีการปรับเฉพาะตำแหน่ง tests, include ของ tests, เอกสารและ tooling

Helpers ของ Scalp Calculator และ Instant Engulf ยังอยู่ในโฟลเดอร์เครื่องมือของตนเอง Instant Broker มีพฤติกรรมเฉพาะสำหรับ TP 1:1 จึงยังไม่รวมเป็นโมดูลกลางในงานนี้ เพื่อให้แต่ละชุดติดตั้งเป็นอิสระ

## Paths ที่เปลี่ยน

| เดิม | ใหม่ |
|---|---|
| Root README เป็นคู่มือ Scalp Calculator | Root README เป็นสารบัญ; คู่มือเดิมไป `docs/experts/scalp-calculator/README.md` |
| `docs/REQUIREMENTS.md` | `docs/experts/scalp-calculator/requirements.md` |
| `docs/TESTING.md` | `docs/experts/scalp-calculator/testing.md` |
| `docs/InstantEngulf.md` | `docs/experts/instant-engulf/README.md` |
| `docs/TVStyleMACD.md` | `docs/indicators/tv-style-macd/README.md` |
| `docs/PAReversal.md` | `docs/indicators/pa-reversal/README.md` |
| `tests/*.cpp` | `tests/<product>/*_tests.cpp` |
| `tests/macd-reference.pine` | `tests/tv-style-macd/reference.pine` |
| `dist/ScalpCalculator*` | `dist/experts/scalp-calculator/` |
| `dist/InstantEngulf/` | `dist/experts/instant-engulf/` |
| `dist/TVStyleMACD/` | `dist/indicators/tv-style-macd/` |
| `dist/PAReversal/` | `dist/indicators/pa-reversal/` |

ZIP และ manifest เดิมเก็บใน `dist/archive/legacy-layout/<product>/` โดยไม่แก้เนื้อหาภายใน ลิงก์ดาวน์โหลดจากข้อความเก่าอาจชี้ path เดิม ให้ใช้ลิงก์ปัจจุบันจาก README กลาง

## คำสั่งที่รวมแล้ว

| เดิม | ใหม่ |
|---|---|
| `sh scripts/test.sh` (เฉพาะ scalp) | `sh scripts/test.sh scalp-calculator` |
| `sh scripts/test-engulf.sh` | `sh scripts/test.sh instant-engulf` |
| `sh scripts/test-macd.sh` | `sh scripts/test.sh tv-style-macd` |
| `sh scripts/test-pa-reversal.sh` | `sh scripts/test.sh pa-reversal` |
| `sh scripts/compile-macos.sh` (เฉพาะ scalp) | `sh scripts/compile-macos.sh scalp-calculator` |
| `sh scripts/compile-pa-reversal-macos.sh` | `sh scripts/compile-macos.sh pa-reversal` |

`test.sh` และ `compile-macos.sh` ที่ไม่ระบุชื่อจะทำทุกตัวใน checkout ชุด ZIP แยกตัวมี runner/catalog เฉพาะเครื่องมือที่บรรจุมา

## เพิ่มเครื่องมือใหม่

MACD Swing Count ใช้ source `MQL5/Indicators/MACDSwingCount/`, คู่มือ `docs/indicators/macd-swing-count/`, tests `tests/macd-swing-count/` และ output `dist/indicators/macd-swing-count/` ตามโครงสร้างเดียวกัน

1. สร้าง source ใน `MQL5/Experts/<Name>` หรือ `MQL5/Indicators/<Name>`
2. เพิ่มคู่มือใน `docs/<category>/<product>/README.md` และ tests ใน `tests/<product>/`
3. เพิ่ม runner ที่ `scripts/tests/<product>.sh` และข้อมูลใน `scripts/products.json`
4. เพิ่มชื่อที่อนุญาตใน `scripts/test.sh` และแถวใน README กลาง
5. Test → Compile → Package แล้วตรวจใน MT5 ตาม checklist ของเครื่องมือนั้น

`dist/` เป็น output ที่สร้างใหม่ได้; compiler log และ manifest ช่วยตรวจว่าแพ็กมาจากไฟล์ใด `package.py` ไม่ถือว่าการแพ็กเท่ากับการทดสอบ runtime

## Trade Journal

EA บันทึกอย่างเดียวอยู่ใน `MQL5/Experts/TradeJournal/` พร้อมคู่มือ `docs/experts/trade-journal/`, tests `tests/trade-journal/` และ output `dist/experts/trade-journal/` ใช้ `trade-journal` กับ test/compile/package runners ติดบนอีกกราฟเพื่อใช้คู่กับ Calculator; CSV runtime อยู่ใน Data Folder ของ MT5 ไม่เขียนข้อมูลบัญชีลง repository

Trade Journal 1.10 เพิ่ม companion Script ใน `MQL5/Scripts/TradeJournal/`; `companions` ใน products.json ให้ compile/package ตรวจ binary และ log ทั้ง EA กับ Script ส่วน `extra_files` รวม HTML/JS sources, template builder และ demo โดยไม่รวมข้อมูลบัญชีจริง

## EngulfFlow

ใช้ source `MQL5/Indicators/EngulfFlow/`, คู่มือ `docs/indicators/engulf-flow/`, tests `tests/engulf-flow/` และ output `dist/indicators/engulf-flow/` ใช้ชื่อ `engulf-flow` กับ test/compile/package runners; core และ timer อยู่ในชุดของตัวเองเพื่อติดตั้งได้อิสระ

## ImbalanceFlow

ใช้ source `MQL5/Indicators/ImbalanceFlow/`, คู่มือ `docs/indicators/imbalance-flow/`, tests `tests/imbalance-flow/` และ output `dist/indicators/imbalance-flow/` ใช้ชื่อ `imbalance-flow` กับ test/compile/package runners; `FVGCore.mqh` แยกกติกาตรวจจับ/เติมโซนออกจากการวาดกราฟใน `ImbalanceFlow.mq5` ทดสอบ core และฟังก์ชันคำนวณจริงผ่าน C++ โดยไม่เปิด MT5

## EngulfImbalanceFlow

ใช้ source `MQL5/Indicators/EngulfImbalanceFlow/`, คู่มือ `docs/indicators/engulf-imbalance-flow/` และ output `dist/indicators/engulf-imbalance-flow/` ใช้ชื่อ `engulf-imbalance-flow` กับ compile/package runners สำเนา core ของ EngulfFlow และ ImbalanceFlow อยู่ในโฟลเดอร์นี้เพื่อติดตั้งได้อิสระ รุ่นนี้ยังไม่มีชุดทดสอบ ตามที่สร้างไว้โดยไม่รัน backtest

## MACD Zone Pullback

ใช้ source `MQL5/Indicators/MACDZonePullback/`, คู่มือ `docs/indicators/macd-zone-pullback/`, tests `tests/macd-zone-pullback/` และ output `dist/indicators/macd-zone-pullback/` ใช้ชื่อ `macd-zone-pullback` กับ test/compile/package runners

`PullbackCore.mqh` ควบคุมโซน, คุณภาพขาเบรก, M1 confirmation และ replay สอง timeframe; `SwingCore.mqh` และ `FVGCore.mqh` เป็นสำเนาตรงจาก indicator ต้นทางเพื่อให้ ZIP ติดตั้งได้อิสระ Test runner ตรวจความตรงกันเมื่อมีต้นฉบับใน checkout หากเปลี่ยน core ต้นทางต้องประเมินและทดสอบผลก่อนอัปเดตสำเนา

## MACD Zone Trader

EA อยู่ใน `MQL5/Experts/MACDZoneTrader/`, คู่มือและ test preset อยู่ใน `docs/experts/macd-zone-trader/`, tests อยู่ใน `tests/macd-zone-trader/` และชุดติดตั้งใน `dist/experts/macd-zone-trader/` ใช้ชื่อ `macd-zone-trader` กับ runners

`TradePlanCore.mqh` ใช้ replay ของ MACDZonePullback แล้วสร้างขอบ pattern M1/รายการเป้าหมาย M5 เฉพาะข้อมูลที่รู้ ณ เวลาสัญญาณ `TradeExecution.mqh` เป็นเส้นทาง OrderSend เดียวพร้อม R:R/risk guard และการป้องกันซ้ำ `ScalpCore.mqh`/`ScalpBroker.mqh` คัดลอกจาก Calculator และ signal cores คัดลอกจาก indicator โดย runner ตรวจความตรงกัน สำเนาทำให้ติดตั้ง EA ได้อิสระ

ImbalanceFlow 1.10 เพิ่ม `DisplacementCore.mqh` สำหรับแรงส่งไม่มี gap และ buffer 3–6 โดยคง FVG buffers 0–2 และ Inputs เดิม เพิ่มตัวเลือกตรวจเดี่ยว/หลายแท่ง, ATR/body/wick/median/breakout และพื้นที่โซนผ่าน Inputs

## WickHuntSRFlow

รุ่น 1.05 เพิ่ม `WickHuntHistory.mqh` เป็น adapter ของ indi เท่านั้น สำหรับ reclaim ด้วย Close TF ย่อย และ retest จากแท่งรอที่ปิดแล้ว การ replay ใน `WickHuntSRFlow.mq5` เดินสอง TF ตามเวลาโดยไม่ใช้ H/L สุดท้ายของแท่งใหญ่ในอดีตก่อนมันจบ Shared signal cores เดิมยังอยู่แยกกันและไม่เปลี่ยน; EA ยังคงเรียกการ observe/take จาก tick แบบเดิม ไม่ include adapter ประวัตินี้

Preset `docs/indicators/wick-hunt-sr-flow/m15-m1-history.set` รวมใน ZIP ของ indi และใช้ Load ในหน้า Inputs เพื่อเลือก M15/M1, โหมด Close/history และวาดได้ถึง 5000 events โดยไม่ทับ Inputs กฎอื่น

## WickHuntAnchor

Indicator ใหม่ใน `MQL5/Indicators/WickHuntAnchor/` ใช้ `WickHuntAnchorCore.mqh` และสำเนา `FVGCore.mqh` เพียงสอง headers ไม่มี dependency กับ MACD/SR หรือ signal core ของตัวเดิม ตรวจ first collision เลือก FVG only, Strong only, OR หรือ AND โดยเกณฑ์หางหัว <30% ของ range ใช้กับ Strong เท่านั้น ไม่บังคับ body รุ่น 1.09 แสดงชื่อตัวแปรพร้อมความหมายไทยครบทุก Input โดย logic/defaults เดิม รุ่น 1.08 ตั้ง InpSearchBars=36 เป็นระยะสูงสุดจาก hunt ถึง anchor บน TF หลัก ใช้ทั้งสองฝั่งและทุก Rule และ preset รุ่น 1.07 เพิ่ม Sell ต้องชน anchor แดงพร้อม Input แยกเปิดเป็นค่าเริ่มต้น และใช้การทบทวนเช่นเดียวกับ Buy รุ่น 1.06 ทบทวน anchor ที่กรองสีเมื่อปลายหางเปลี่ยน ยกเลิก event เดิมหากไม่ผ่านหรือเปลี่ยน anchor และรอ reclaim ใหม่ รุ่น 1.05 เพิ่มกรอง Buy ต้องชน anchor เขียวเป็นค่าเริ่มต้น โดย Sell คงสีเดิม และเพิ่ม Input ท้ายรายการ รุ่น 1.04 เพิ่ม FVG anchor แบบแท่งกลางที่มีแท่งที่ 3 ยืนยันปิดก่อน hunt แล้ว ยังคงรับ anchor แท่งที่ 3 เดิม ย่อลูกศรเป็นความหนา 1 เว้นระยะ 200 points และวาดในพื้นหลัง ค่าเริ่มต้น H1/M5 ตรวจทุกแท่ง M5 ปิดและสะสม H/L ของ H1 จากข้อมูลย่อยที่เกิดแล้ว ใช้ Close M5 ยืนยัน reclaim ไม่มี secondary breakout/hold/retest โหมด tick/main-close เดิมยังเลือกได้

คู่มือ/presets อยู่ใน `docs/indicators/wick-hunt-anchor/`; build/ZIP อยู่ใน `dist/indicators/wick-hunt-anchor/` ใช้ชื่อ `wick-hunt-anchor` กับ compile/package runners ไม่มี tests/backtest ในรุ่นแรก และไม่เปลี่ยน indicator/EA เดิม

พอร์ต TradingView อยู่ใน `Pine/Indicators/WickHuntAnchor.pine` ใช้ Pine Script v6 และเลขรุ่น Pine แยกจาก MT5 โหมด TF ย่อยปิด ค่าเริ่มต้น H1/M5 คู่มือ/สถานะ compiler เป็น `pine.md` / `pine-build.md` ในโฟลเดอร์คู่มือเดิม Distribution แยกใน `dist/pine/wick-hunt-anchor/` ไม่ผ่าน compile/package runners ของ MT5

`Pine/Indicators/WickHuntSRAnchor.pine` เป็น combined indicator ใหม่: SR ของ WickHuntSRFlow 1.06 และ Anchor ของ WickHuntAnchor 1.01 โหมด TF ย่อยปิด ทำงานแยก engines และรูปแบบ markers คู่มืออยู่ใน `docs/indicators/wick-hunt-sr-flow/pine.md` Distribution แยกที่ `dist/pine/wick-hunt-sr-anchor/` ไม่ทับ standalone Anchor Pine หรือ source/EX5/ZIP ของ MT5

## WickHunt Telegram EA

ตัวตรวจ `WickHuntTelegramEA` และ companion `WickHuntTelegramSender` อยู่ใน `MQL5/Experts/WickHuntTelegramEA/` ใช้ queue helper ร่วมกันและ include cores ของ `MQL5/Indicators/WickHuntSRFlow/` โดยตรง แพ็กเกจรวม headers เหล่านี้ไว้สำหรับคอมไพล์ source แต่ไม่จำเป็นต้องติดตั้ง/แนบ EX5 ของ indi บน VPS

ตัวส่งมี thread ของตนเองบนกราฟอีกหนึ่งกราฟ เพื่อไม่ให้ WebRequest บล็อกตัวตรวจ ไม่ใช้คำสั่งเทรด คิว/acknowledgement/reclaim checkpoint แยกตามบัญชี/channel/instance มีคู่มือใน `docs/experts/wick-hunt-telegram-ea/` และ build ที่ `dist/experts/wick-hunt-telegram-ea/` รุ่นแรกจัดทำโดยไม่รัน tests/backtest
