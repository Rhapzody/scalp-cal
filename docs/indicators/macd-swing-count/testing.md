# MACD Swing Count — การตรวจสอบ

## Automated tests

```sh
sh scripts/test.sh macd-swing-count
```

ทดสอบ production `SwingCore.mqh` และดึงฟังก์ชันจริง `ClearBuffers`, `ClearBar`, `CalculateClosedBar`, `OnCalculate` จาก `.mq5` มาใช้ใน C++ harness ปรับเฉพาะ syntax arrays/API ของ MT5 เป็น vector และ stub การวาด/รายงาน ไม่ใช่คัดลอก algorithm ไปเขียนใหม่ใน test

**ผลเวอร์ชัน 1.20: 42,454 checks ผ่าน** (core/integration 42,436 + S/R renderer 18)

MetaEditor คอมไพล์ source เวอร์ชันนี้ได้ **0 errors, 0 warnings** และสร้าง `.ex5` สำเร็จ

- MACD เทียบ oracle ที่คำนวณ EMA จากผลรวม geometric weights อย่างอิสระ ไม่ใช้ recurrence เดียวกับ production เป็นคำตอบอ้างอิง
- ทดสอบค่าเริ่มต้น, length=1, Fast > Slow และ periods ยาวกว่าประวัติ
- Threshold เท่ากับขอบ, Histogram เท่ากับศูนย์, ราคา/points/ATR
- Regression cross `+0.10 → −0.01 → −0.10` ที่เกณฑ์ 0.05 ยืนยันเมื่อถึงเกณฑ์ ไม่พลาดขาทั้งช่วง
- Pivot เทียบ oracle ที่สแกน High/Low ตลอดช่วง ณ ตอนยืนยัน แยกจากการเก็บ extreme แบบ incremental
- High/Low เท่ากันเลือกแท่งล่าสุด, รวมแท่งยืนยันในขาเก่า, HH/HL/LH/LL/EH/EL
- ข้อมูลผิด, NaN, ราคาติดลบ, warmup และการเริ่มขาแรก
- เปรียบเทียบทุก buffer ระหว่างเดินทีละแท่งกับ full rebuild
- Tick ของแท่งสดไม่เปลี่ยนค่าเก่าและไม่สั่งวาด label ซ้ำ แม้ SlowEMA ยาวกว่าประวัติ
- เติมหลายแท่งพร้อมกัน, เลื่อนขอบประวัติ, ประวัติหด, แก้ OHLC พร้อม reset และหยุด/เริ่มคำนวณใหม่
- Event อยู่บนแท่งยืนยัน, pivot อยู่บนแท่งยอด/ก้น, shift 0 ของทุก buffer ว่าง
- Histogram color: แดงเข้ม/อ่อน, เขียวเข้ม/อ่อน, กระโดดข้ามศูนย์ และต่อทิศเดิมโดยไม่สร้าง swing ซ้ำ
- สีเมื่อ Histogram เท่ากัน/ศูนย์และไม่มีแท่งก่อนหน้า; Signal length=1 ไม่มี swing เทียม
- Oracle แปลง Histogram เป็น 4 สีแล้วสแกน extreme ในช่วงราคาอย่างอิสระ เทียบกับ event buffers จริงของโหมดสี
- ทดสอบ incremental/reload/live ticks/เปลี่ยนขอบประวัติครบทั้ง Cross และ Histogram color และยืนยันว่า cross threshold/ATR length ไม่เปลี่ยน outputs โหมดสี

เพิ่ม tests body ของแท่ง pivot จริงในทั้งสองโหมด รวม equal-wick ties และ doji พร้อมดึง `RenderSRLevels` จริงมาทดสอบกับ object API จำลอง ตรวจ horizontal ray, ตำแหน่งเริ่มที่ pivot, ราคาปลายเส้นทั้งสองจุด, สี/ความหนา, จำนวนล่าสุด, เปิดปิด และการไม่ลบ object ของส่วนอื่น

การทดสอบ render เลข/report ใช้ stub และ S/R render ใช้ API จำลอง จึงไม่ได้ยืนยันหน้าตา object, popup หรือพฤติกรรม API บน terminal จริง การคอมไพล์ MetaEditor และตรวจ log/binary ทำแยกจาก tests

## ตรวจบน MT5

1. แนบ indicator ด้วยค่าปกติ ตรวจเลขล่าสุด สี และ marker ยืนยัน High/Low
2. เปิด Data Window เทียบ MACD กับ TVStyleMACD โดยใช้ EMA/EMA, Close, timeframe และประวัติเริ่มต้นเดียวกัน เฉพาะแท่งปิด; การแสดงของแท่งสดต่างกันโดยตั้งใจ
3. ใช้จุดที่ยอดเกิดก่อน cross ตรวจว่าเลขอยู่แท่งยอด แต่ลูกศรยืนยันอยู่แท่งที่ Histogram ผ่านเกณฑ์
4. ตรวจตัวกรองราคา/points/ATR และตรวจ buffer 11 ว่าเป็นหน่วยราคาที่คาดไว้
5. เปลี่ยน label mode, จำนวนจุด, สี, ระยะห่าง และเปิดเส้นเชื่อม ตรวจกรณี High/Low อยู่แท่งเดียวกัน
6. แนบสอง instance คนละ period จากนั้นถอดตัวหนึ่ง ตรวจว่าอีกตัวไม่สูญเสีย object
7. เปิด popup บนกราฟทดลอง ตรวจว่าไม่แจ้งย้อนหลังตอน attach/reload และแจ้งครั้งเดียวตอนมี event ใหม่บนแท่งปิดล่าสุด
8. เปลี่ยน timeframe, โหลดประวัติเพิ่ม และเปิดกราฟใหม่ ตรวจว่าไม่เหลือ object เก่า
9. อ่าน buffers 2–5 ด้วย EA ทดลอง ต้องประมวลผลหลังแท่งยืนยันปิดและป้องกัน event ซ้ำด้วยเวลาแท่ง ห้ามย้อนเข้าออเดอร์ที่เวลา pivot
10. เปลี่ยน `InpSwingMode` เป็น Histogram color แล้วตรวจตัวอย่างเขียวเข้ม → เขียวอ่อน → แดง: High ยืนยันเมื่อเขียวอ่อนปิด และไม่มี High ใหม่ซ้ำเมื่อกลายเป็นแดง ตรวจฝั่งกลับและชื่อโหมดเมื่อแนบสอง instance
11. ตรวจ S/R แบบ Wick และ Body บนแท่ง swing ที่มี wick ชัดเจนทั้งแท่งเขียว/แดง: High body = max(Open,Close), Low body = min(Open,Close) ต้องเป็น OHLC ของ pivot ไม่ใช่แท่งยืนยัน
12. ตั้งเลข 3 จุดและ S/R 10 จุด จากนั้นตั้งเลข 0 ตรวจว่าเส้น S/R ยังอยู่ เปลี่ยนจำนวนเส้นและเปิดปิด ตรวจไม่มีเส้นเก่าค้างและไม่ลบ object ของอีก instance

**ยังไม่ได้ดำเนินการ checklist native MT5 ข้างต้น** และยังไม่ได้เทียบ CSV จาก TradingView/EA ต้นฉบับ
