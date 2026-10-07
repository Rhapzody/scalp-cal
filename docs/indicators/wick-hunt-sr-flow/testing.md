# WickHuntSRFlow 1.06 — build status

รุ่น 1.06 เปลี่ยนการวาดลูกศรของ indi เท่านั้น: หาแท่งที่ครอบคลุมเวลาสัญญาณบน TF กราฟ, Buy ใต้ Low/Sell เหนือ High พร้อมระยะ points, วางตรงเวลาเปิดแท่ง และปรับตามหางของแท่งสดที่ขยาย เงื่อนไข/ราคา/เวลาสัญญาณและ shared cores รวมทั้ง EA ไม่เปลี่ยน

คอมไพล์ด้วย MetaEditor **0 errors / 0 warnings**; จัดแพ็กเกจ `WickHuntSRFlow-1.06.zip` และตรวจ hash ของ EA/shared signal headers เทียบก่อนแก้ ไม่รัน logic tests/backtest และยังไม่ยืนยันตำแหน่งลูกศรบน MT5 จริง Fixture ของชุดเดิมเพิ่ม globals สำหรับสถานะ redraw ของกราฟเท่านั้น

## บันทึก build ของ v1.05

รุ่น 1.05 เพิ่มโหมด Close/history เฉพาะ indi: reclaim จาก Close TF ย่อย, replay จากแท่งปิดตามลำดับโดยสะสม H/L ของแท่งใหญ่, breakout หลังแท่ง reclaim, และ retest จาก H/L หรือ Close ของแท่งรอที่ปิดแล้ว โหมด Tick เดิมยังเลือกได้ Shared signal cores และ WickHuntTelegramEA/Sender ทั้ง source/EX5/ZIP ไม่ได้เปลี่ยน

สถานะคอมไพล์ v1.05: MetaEditor **0 errors / 0 warnings**; จัดแพ็กเกจ `WickHuntSRFlow-1.05.zip` พร้อม preset M15/M1 และตรวจ hash เทียบไฟล์ EA/shared cores เดิม ไม่รัน logic tests/backtest ตามคำขอผู้ใช้ และยังไม่ได้ตรวจลูกศรบน MT5 จริง

ผล checks ที่บันทึกด้านล่างเป็น v1.03 เท่านั้น ไม่ยืนยันโหมด Close/history ใหม่ Fixture C++ เดิมยังชี้ไปที่ dispatch โหมด Tick เพื่อรักษาชุด regression เดิม ไม่มีการรันชุดนั้นในรุ่นนี้

สิ่งที่ยังต้องตรวจเมื่ออนุญาตให้ทดสอบ: Buy/Sell reclaim ที่ปิดเท่ากับ Open, ห้าม reclaim/break ในแท่งเดียว, ห้ามใช้หาง hold เป็น retest, แท่ง retest ที่ 8/9 และขอบแท่งใหญ่, ช่วงข้อมูลย่อยขาดหาย, ลำดับ swing/FVG ที่ยังไม่ทราบ ณ ตอนนั้น, การ attach/reinitialize/popup และความเร็วเมื่อโหลดประวัติจำนวนมาก

## บันทึก build ของ v1.04

รุ่น 1.04 เพิ่ม Inputs จำนวนแท่งยืนยัน, close buffer, retest tolerance, ระยะ hunt, เกณฑ์หางนำ FVG และเปิด/ปิด Buy/Sell ค่าเริ่มต้นตั้งตามกฎ v1.03

**ไม่รัน logic tests หรือ backtest ของ v1.04 ตามคำขอผู้ใช้** จำนวน checks และผล replay ด้านล่างเป็นหลักฐานของ v1.03 เท่านั้น ไม่ใช่ผลทดสอบ Inputs ใหม่

สถานะคอมไพล์ v1.04: MetaEditor **0 errors / 0 warnings**; สร้าง EX5 แล้ว และจัดแพ็กเกจ `WickHuntSRFlow-1.04.zip` โดยไม่ได้รัน tests/backtest

## ผลทดสอบที่บันทึกไว้ของ v1.03

ชุดทดสอบ C++ ใช้ core จริง และดึง body ของ `ReplayHigher`, `LoadContext`, `ReplayLower`, `ScenarioText`, `MapOutput`, `UpdateLive`, `OnTimer`, `OnCalculate` จาก source จริง โดยปรับเพียง syntax ของ MQL arrays เป็น vectors และจำลอง API ของ MT5 ตรวจ byte-for-byte ของ SwingCore และ FVG/EngulfImbalance/EngulfFlow cores ที่คัดลอกมาจาก flow เดิมด้วย

ผลตรวจอัตโนมัติ: **5,538 checks ผ่าน** (5,487 regression checks + direction/hold/retest 51 checks) และชุด MACDSwingCount เดิม **42,454 checks ผ่าน** คอมไพล์ด้วย MetaEditor **0 errors / 0 warnings**

ครอบคลุม:

- Breakout ใช้ Swing H ต้านสำหรับ Bull + hunt ล่าง / Swing L รับสำหรับ Bear + hunt บน; แตะอย่างเดียวผ่านได้โดยไม่ต้องมี closed structural break หรือ trend ready
- Breakout ทั้ง Buy/Sell: H/L แตะ S/R พอดีได้, แท่งที่ห้าย้อนหลังได้, นอกช่วงไม่ได้, ห้ามระดับที่ยังไม่ยืนยัน ณ แท่งที่แตะ; รองรับ Wick/Body anchor
- FVG first collision: ทิศเดียวกับสัญญาณ, tip อยู่ใน body, หางนำ 30% พอดีผ่าน/เกินไม่ผ่าน, แท่งอื่นบังไม่ข้าม, ขอบหน้าต่างค้น, minimum gap และปฏิเสธ session gap ที่แท่งกลางไม่ครอบคลุม
- Pullback ทั้งสองทิศ: origin swing → H1 ปิด break ระดับที่รู้ก่อนเปิด → ยืนยัน swing ปลายทางจึงพร้อม; opposite structural break เปลี่ยนเทรน; invalid OHLC ล้างบริบท
- กวาดหางสอง H1 ด้านเดียวในแท่งปัจจุบัน; กวาดได้หางเดียว/แตะหางที่สองพอดี/สวนเทรน/swing ยังไม่ยืนยัน/ไม่ย่อจากปลายทางต้องไม่ผ่าน
- แยก Breakout/Pullback/Both; ผ่าน FVG ไม่เป็นเงื่อนไขบังคับของ Pullback; Both ให้ event เดียวพร้อม metadata สองแบบ; ต้องมี M5 break ภายหลังทุกแบบ
- Replay H1 ใช้แท่งปิดเท่านั้น, forming H1 ไม่เปลี่ยน histogram; H1 ใหม่เดิน engine ต่อ; timer/buffers ส่ง tag Pullback หลัง M5 ปิดจริง
- จำ scenario/SR/FVG/trend pivot ณ reclaim และคงไว้ขณะ M5 replay; เมื่อ event ล่าสุดในแท่งกราฟไม่มี FVG ต้องล้าง metadata FVG ของ event เก่า
- Buy/Sell crossing: เท่าระดับที่ Close ก่อนหน้าผ่าน, เท่าที่ Close ล่าสุดไม่ผ่าน, อยู่ฝั่งเดิมไม่ถือว่า cross
- ทั้ง swing High และ Low เป็นระดับ Buy ได้, Sell กลับด้าน; เลือก swing ที่ยืนยันล่าสุดเมื่อข้ามหลายระดับ
- ห้าม swing ที่ยืนยันบนแท่ง breakout เองหรือในอนาคต; anchor body มาจากแท่ง swing จริง
- Hunt ต้องทะลุจริง, reclaim เท่ากับ Open ผ่าน, ราคาไม่ถึง Open ไม่ผ่าน, hunt หลายแท่งต้องกวาดครบ
- ต้อง reclaim ก่อน breakout: ปฏิเสธ Close ก่อนหรือเวลาเดียวกับ reclaim; M5 ที่เปิดก่อน reclaim แต่ปิดหลังผ่านได้ ทั้ง Buy/Sell และ Swing H/L; หนึ่ง event ต่อฝั่งต่อ H1 และ setup หมดอายุเมื่อเปลี่ยน H1
- Histogram และการเก็บระดับตรงกับ replay ของ MACDSwingCount ผ่านหลายขาราคา พร้อมตรวจ byte-for-byte ของ SwingCore
- Break/hold/retest ทั้ง Buy/Sell: แท่งถัดไปทันทีต้องปิดฝั่งเดิมอย่างเคร่งครัด; equality/ผิดฝั่ง/แท่งหายทิ้ง; ราคาจริง retest ในแท่งแรกและแท่งที่ 8 ผ่าน, เปิดแท่งที่ 9 ไม่ผ่าน; swing ใหม่ไม่เปลี่ยน SR ที่ตรึงไว้; invalid OHLC/main rollover ล้างชุด; หลังทิ้งรอ fresh cross ใหม่
- Timer ไม่อนุมาน retest จาก Low/High ของแท่งสดซึ่งอาจแตะก่อน hold close; รับ quote แตะจริงและส่งเพียงครั้งเดียว
- Timer ตรวจภายใน M5 ขณะที่ chart เป็น H1, metadata/ราคาใน buffer shift 0 และ popup ไม่ซ้ำ
- Connection/series/CopyRates failure, quote นอกช่วง H1, Last-price chart และ popup ตอน attach
- ประมวลผลเฉพาะแท่ง TF เล็กที่ปิด, tick ของแท่งสดไม่เปลี่ยน swing, แท่ง M5 ใหม่ประมวลผลได้ระหว่าง H1 เดิม
- Replay คืนเวลา reclaim ก่อนคำนวณแท่งปิดใหม่ เพื่อกัน breakout เก่าถูกยกกลับมาใช้; คงสถานะ sent ของ H1 เดิม; H1 ใหม่ล้างเวลา reclaim และสถานะ และลูกศรเดิมยัง map ไปแท่งเดิม
- โหมดประวัติทั้งหมดและโหมดจำกัดประวัติ

## ตรวจบน MT5 จริง — ยังไม่ดำเนินการ

1. แนบ H1 ใช้ H1/M5 ค่าเริ่มต้น เปิด MACDSwingCount ทั้ง H1/M5 โหมด Histogram, periods/warmup/anchor และต้นประวัติเดียวกัน เทียบ H1 เส้นประและ M5 เส้นทึบ
2. Buy: H1 ลงต่ำกว่า Low ก่อนหน้าแล้วกลับถึง Open ระหว่าง M5; เมื่อ M5 ปิดข้าม S/R ต้องรอแท่งถัดไปปิดยืนเหนือเส้น แล้วราคาสดย้อนแตะใน 8 แท่งและใน H1 เดียวกันจึงได้ลูกศร ตรวจ Sell กลับด้าน
3. ลอง breakout ก่อน/ตรงเวลา reclaim ต้องไม่ผ่าน; หลัง reclaim ผ่านได้; wick M5 ทะลุแต่ Close ไม่ทะลุต้องไม่เป็น breakout
4. ทดสอบสัญญาณจาก reclaim Swing L และจากทะลุ Swing H ขึ้น โดยไม่ต้องมี pattern detector
5. ตรวจไม่มีสัญญาณซ้ำต่อฝั่งใน H1 เดิม และไม่มี carry setup ไป H1 ถัดไป
6. ตรวจ Inputs สอง TF, Scenario, HuntBars/PullbackHuntBars, TouchBars, FVGSearchBars, RetestBars, SRCount และ Body/Wick รวมถึงการแนบสอง instance/ถอดทีละตัว
7. ตรวจ Tooltip เวลาตรวจพบจริงและเวลาแท่ง breakout, popup, อ่าน buffers ระหว่าง H1 สด และตำแหน่งหลัง H1 เปลี่ยนแท่ง
8. ทดสอบ reconnect/โหลดประวัติเพิ่ม, symbol ที่ใช้ Last และการทำงานบนพื้นกราฟหลายสี
9. ตรวจว่าการ reinitialize ล้าง events ตามข้อจำกัดรุ่น 1.03 และไม่แสดงลูกศรย้อนหลังด้วย OHLC ของ H1 ที่จบแล้ว
10. ตรวจ Breakout first collision กับ FVG confirmation จริง และ Pullback ที่กวาดสองหางในครั้งเดียว; tooltip/tag buffers 8–11 ต้องตรงกับบริบทที่ reclaim

ผล replay ทอง 1 ปีเดิมเป็น **v1.01**, M15/M1 3 เดือนเดิมเป็น **v1.02**; [รายงาน 3 เดือน v1.03](../../../tests/reports/wick-hunt-sr-xauusd-m15-m1-3m-v103/README.md) แยกไฟล์และใช้ M1 Open/Close snapshots เพื่อประมาณเหตุการณ์ระหว่างแท่ง ไม่ใช่ native tick Strategy Tester
