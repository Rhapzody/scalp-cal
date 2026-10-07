# บันทึกผลตลาด — Trend Sweep 1.00

## สถานะ ณ ส่งมอบ

**ยังไม่มี market backtest/forward test จึงไม่มีค่า win rate ที่ยืนยันได้** ค่าเริ่มต้น TargetRR=2.0 และ MinRR=1.8 เป็นกติกาในการเตรียมคำสั่ง ไม่ใช่ realized average RR

ผ่านการตรวจโค้ดและคอมไพล์ตาม `testing.md` เท่านั้น ไม่ใช้ข้อมูลสร้างขึ้นอ้างความสามารถทำกำไร

## แบบบันทึกผลหลังรัน MT5

| รายการ | ค่าที่วัด/กำหนด |
|---|---|
| เวอร์ชัน source / build | 1.00 / แนบ build-manifest.json |
| ชื่อไฟล์ report / preset | ยังไม่มี |
| Symbol / broker server / account type | ยังไม่ระบุ |
| ช่วงวันที่ / timezone | ยังไม่มี |
| Training / validation / untouched test | ยังไม่มี |
| Model / data quality / execution delay | ยังไม่มี |
| Deposit / currency / leverage | ยังไม่มี |
| Spread / commission / swap | ยังไม่มี |
| จำนวน trade ปิด / ค้าง | ยังไม่มี |
| Win rate (trade ปิดที่กำไรสุทธิ > 0 / trade ปิดทั้งหมด) | ยังไม่มี |
| Average win / average loss สุทธิ | ยังไม่มี |
| Realized reward:risk = average win / abs(average loss) | ยังไม่มี |
| Expectancy ต่อ trade สุทธิ | ยังไม่มี |
| Profit factor สุทธิ | ยังไม่มี |
| Maximum equity drawdown % / เงิน | ยังไม่มี |
| แยก Buy/Sell และแยกเดือน | ยังไม่มี |
| ผลเมื่อเพิ่ม spread/delay/commission | ยังไม่มี |
| Forward demo ช่วงที่ไม่ปรับค่า | ยังไม่มี |

## การอ่านผล

- นับเป็น **trade/position ที่ปิดครบ** ไม่สับสนจำนวน deals กับจำนวน trade; รวม commission, swap และค่าธรรมเนียมที่เกิดจริง
- Win rate สูงพร้อม average loss ใหญ่กว่า average win มากอาจขาดทุนได้
- `expectancy = win_rate × average_win − loss_rate × average_loss_absolute` ถ้ามี trade เท่าทุนให้แยกสัดส่วนด้วย สูตรต้องใช้หน่วยเดียวกัน เช่นเงิน หรือ R ต่อ trade
- TP/SL gap และการปิดก่อนถึงเป้าทำให้ผลไม่ได้อยู่ที่ +2R/−1R เสมอ ใช้ผลสุทธิจริง
- แยกผลช่วงที่ใช้ปรับค่าออกจากช่วงที่ไม่เคยใช้ ห้ามนำผลที่ดีที่สุดจากการค้นหลายชุดไปเรียกว่า out-of-sample โดยไม่ทดสอบใหม่
- ถ้ายังไม่ผ่านข้อมูลนอกช่วงพัฒนา ให้ระบุว่า “กลยุทธ์ทดลอง ยังไม่พบหลักฐานเพียงพอ” แม้ compile/tests ผ่าน
