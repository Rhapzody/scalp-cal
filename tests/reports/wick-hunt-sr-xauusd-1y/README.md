# WickHuntSRFlow — XAUUSD ครบ 365 วัน

ผล replay กฎใหม่ **WickHuntSRFlow 1.01** พบ **2,410 เหตุการณ์สัญญาณภายใต้การจำลองแบบ snapshot รายหนึ่งนาที**: Buy 1,178 และ Sell 1,232 ใช้ S/R จาก Swing H 1,182 ครั้ง และ Swing L 1,228 ครั้ง นี่เป็นการนับสัญญาณ ไม่ใช่จำนวนออเดอร์หรือผลกำไร

ต้องให้ H1 wick hunt และกลับถึง Open ก่อน แล้วจึงรับ M5 ที่ปิดข้าม S/R โดยเวลา Close ต้องหลัง reclaim อย่างเคร่งครัดภายใน H1 เดียวกัน M5 ที่เปิดก่อน reclaim แต่ปิดหลังยังใช้ได้ ไม่ใช้ breakout เก่าหรือ Close ที่เกิดเวลาเดียวกับ reclaim ผลเดิมที่รับทั้งสองลำดับมี 2,686 เหตุการณ์ เก็บไว้ใน [previous-any-order](previous-any-order/summary.json); กฎใหม่ลดลง 276 เหตุการณ์ (10.3%) และอาจเลื่อนเวลา/ระดับของสัญญาณ เพราะต้องรอการข้ามครั้งใหม่หลัง reclaim

ดูกราฟตัวอย่าง 8 ภาพใน [แกลเลอรี](gallery.html) หรือดูรายการเหตุการณ์ทั้งหมดใน [events.csv](events.csv) และผลตรวจใน [summary.json](summary.json)

ผลทดสอบ entry/SL/TP ที่ **R:R 1:1** อยู่ใน [รายงานแยก](rr-1-to-1/index.html) เปรียบเทียบ SL wick H1 ณ สัญญาณ กับ wick M5 ที่ปิด break รวม spread จาก Bid/Ask จริง และประเมินแต่ละสัญญาณแยกกัน

ภาพแสดง M5 แบบ zoom out ย้อนหลังอย่างน้อย 120 แท่งที่ปิดแล้ว ณ สัญญาณ (ประมาณ 10 ชั่วโมงซื้อขาย) และเพิ่ม **12 แท่งถัดจากแท่ง breakout** (ประมาณ 1 ชั่วโมงซื้อขาย) ขยายย้อนหลังเพิ่มเมื่อจำเป็นเพื่อให้เห็น swing pivot ช่วงตลาดปิดถูกย่อบนแกนเวลา ใต้กราฟมี **TV Style MACD** จากโค้ดในโปรเจกต์: Close, EMA 12/26/9, เส้น MACD น้ำเงิน, Signal ส้ม และ Histogram 4 สี ทั้งราคาและ MACD ใช้แท่งและแกนเวลาเดียวกัน คำนวณจากประวัติ M5 ทั้งหมดก่อนเลือกช่วงแสดง ค่าของ MACD/Signal/Histogram ตรวจเทียบกับ swing engine ทุกแท่งและตรงกัน

เส้นชมพูแบ่งช่วงแท่งหลัง breakout และเส้นขาวระบุเวลาสัญญาณ เส้นประฟ้าต่อระดับ S/R อ้างอิงเดิมเพื่อดูการเคลื่อนต่อ ข้อมูลหลังสัญญาณในราคา/MACD มีไว้แสดงบริบทเท่านั้น ไม่ใช้คำนวณสัญญาณย้อนหลัง

กราฟ H1 zoom out เป็น 24 แท่งก่อน setup และ 12 แท่งถัดไป แท่งสีใช้ OHLC สุดท้ายเพื่อให้เห็นการเคลื่อนต่อหลังสัญญาณ ส่วนกรอบ/ไส้และจุดสีขาวแสดง H1 บางส่วนที่สังเกตได้ ณ snapshot ของสัญญาณ เส้นประขาวระบุแท่ง setup และเส้นชมพูแบ่งแท่งถัดไป ข้อมูลหลังสัญญาณใช้เพื่อแสดงภาพเท่านั้น ไม่ได้ป้อนกลับเข้าการคำนวณสัญญาณ

ช่วงทดสอบคือ **2025-09-25 21:00 ถึง 2026-09-25 21:00 UTC** ครบ 365 วัน และเป็นช่วงล่าสุดที่ชุดข้อมูลรองรับ ชุดข้อมูลมีแท่ง XAUUSD M1 จาก Dukascopy ตั้งแต่ 2025-09-01 00:00 ถึง 2026-09-25 20:59 UTC; ใช้ประวัติก่อนวันเริ่มทดสอบเป็น seed ของ MACD/Swing

## วิธี replay

ตัว runner คอมไพล์และเรียก `WSProcessClosed`, `WSObserve` และ `WSTakeSignal` จาก `WickHuntSRCore.mqh` กับ `SwingCore.mqh` โดยใช้ค่าเริ่มต้น H1/M5, HuntBars 1, Histogram MACD 12/26/9, SR 10 จุด และ Wick anchor แท่ง H1/M5 สร้างจาก M1 Bid OHLC ชุดเดียวกัน เริ่มคำนวณ swings จากข้อมูล M5 ที่มีทั้งหมดตั้งแต่ 2025-09-01

M1 OHLC ไม่ใช่ tick history การ replay สังเกต M1 Open และราคา M1 Close ณ snapshot ปลายแท่งที่กำหนดเวลาเป็นวินาที `:59`; เมื่อขึ้นนาทีใหม่จึงประมวลผล M5 ที่ปิดแล้วแล้วใช้ M1 Open ใหม่เป็น quote snapshot เวลาที่บันทึกจึงเป็นเวลาตัวแทนจากแท่งหนึ่งนาที ไม่ใช่เวลาของ tick จริง และการเคลื่อนที่ระหว่าง snapshot อาจทำให้พลาด reclaim บางครั้ง การตัดสินสัญญาณใช้เฉพาะข้อมูลที่รู้ถึง snapshot ส่วนกราฟ H1 แสดง OHLC สุดท้ายประกอบกับกรอบขาวของแท่ง ณ ตอนเกิดสัญญาณ

ไม่เติมแท่งในช่วง data gap; ในช่วงทดสอบมี H1 ที่มี M1 ไม่ครบ 32 แท่งเป็น reference ของ setup และมี H1 อีก 4 ช่วงที่ M1 แรกไม่มี timestamp ตรงต้นชั่วโมง จึงระงับ setup เหล่านั้น (หนึ่งชั่วโมงเข้าเงื่อนไขทั้งสองข้อ) เหลือ H1 setups ที่ตรวจได้ 5,851 จาก 5,886 ช่วงที่มีแท่งข้อมูล M5 ที่ไม่ครบห้านาที 44 กลุ่มยังป้อน OHLC ที่สังเกตได้เข้า swing engine แต่ไม่ใช้กลุ่มนั้นตัดสิน breakout M5; มี 3 เหตุการณ์ที่ pivot หรือ confirmation ใช้กลุ่ม M5 ไม่ครบ ส่วน breakout ทั้งหมดใช้ M5 ที่มี M1 ครบห้านาที

ทั้ง 2,410 เหตุการณ์เป็น reclaim มาก่อน รวม 2,285 H1 setups ที่มีสัญญาณ โดย 125 setups มีทั้ง Buy และ Sell หากจำกัด pivot/confirmation/breakout ให้มี M1 ครบทุกแท่ง จะเหลือ 2,407 เหตุการณ์ (Buy 1,175 / Sell 1,232)

มีการตรวจซ้ำกับ M1 Bid OHLC ดิบ **2,410 เหตุการณ์ / 40,970 invariants ผ่าน** ตรวจระดับ wick ของ pivot, แท่ง breakout ปิดข้าม S/R หลังระดับยืนยันแล้ว, hunt/reclaim ภายใน H1 เดียวกัน, ราคา snapshot, Close M5 ต้องหลัง reclaim อย่างเคร่งครัด และการไม่ซ้ำต่อทิศทาง/H1 ตรวจนี้ยืนยันความสอดคล้องกับข้อมูล M1 ที่มี แต่ไม่เปลี่ยนข้อจำกัดเรื่อง tick history

## ไฟล์

- [gallery.html](gallery.html) และ [gallery/](gallery/) — 8 ตัวอย่าง Buy/Sell ครบ Swing H/L ทุกภาพเป็น reclaim ก่อน breakout เลือกสองตัวอย่างแรกตามเวลาในแต่ละกลุ่ม ไม่ได้จัดอันดับด้วยราคาหลังสัญญาณ
- [events.csv](events.csv) — ทุกเหตุการณ์พร้อมเวลา snapshot, H1 setup, breakout, pivot/confirmation และ S/R
- [monthly.csv](monthly.csv) — จำนวน Buy/Sell แยกเดือน UTC
- [summary.json](summary.json) และ [independent-audit.json](independent-audit.json) — ช่วงข้อมูล, hashes, settings, counts และผล audit
- [run_report.py](run_report.py), [replay.cpp](replay.cpp), [build_gallery.py](build_gallery.py) — เครื่องมือสร้างรายงาน/ภาพจากข้อมูลต้นฉบับ
- [h1_bars.csv](h1_bars.csv), [m5_bars.csv](m5_bars.csv) — แท่งที่สร้างจาก M1 Bid OHLC รวมประวัติ seed
- [m5_macd.csv](m5_macd.csv), [tv_macd.cpp](tv_macd.cpp) — ค่า TV Style MACD และเครื่องมือเรียก production core เพื่อสร้างแผง MACD

## ทำซ้ำ

จากโฟลเดอร์ repository ใช้ Python 3, C++17 (`clang++` หรือ `g++`) และ Pillow สำหรับภาพ:

```sh
python3 tests/reports/wick-hunt-sr-xauusd-1y/run_report.py
python3 tests/reports/wick-hunt-sr-xauusd-1y/audit_events.py
python3 tests/reports/wick-hunt-sr-xauusd-1y/build_gallery.py
```

ปรับระดับ zoom out ได้ด้วย `build_gallery.py --m5-bars 180` (รับ 40–360 แท่ง) โดยไม่เปลี่ยนผลนับสัญญาณ
ปรับจำนวน M5 หลัง breakout ด้วย `--m5-after 24` (รับ 0–72 แท่ง; 0 = แสดงถึงสัญญาณ)
ปรับ H1 ด้วย `--h1-before 36 --h1-after 24` (ก่อน setup รับ 1–72 แท่ง; หลัง setup รับ 1–48 แท่ง)

รายงานนับสัญญาณนี้ไม่ประเมิน entry/SL/TP หรือผลตอบแทน ส่วนผลจำลอง R:R 1:1 และข้อจำกัดด้านต้นทุน/การเข้าออกอยู่ใน [rr-1-to-1](rr-1-to-1/README.md)
