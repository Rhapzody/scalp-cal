# ติดตั้งและทดสอบ Opening Range Trader

ผลตรวจโค้ดอัตโนมัติ:

- Opening Range core: 16 checks
- EA plan: 5 checks
- MetaEditor: Indicator และ EA 0 errors / 0 warnings
- ยังไม่มี market win rate หรือผลกำไรที่รับรอง

ทดสอบใน Strategy Tester:

1. เลือก `OpeningRangeTrader.ex5`, symbol และ M5
2. ใช้ **Every tick based on real ticks** เมื่อ broker มีข้อมูล และโหลด `tester-demo.set`
3. ตรวจ StartHour/Minute เป็นเวลา server และกรอก CommissionPerLot ตามบัญชี
4. เริ่ม Visual mode ตรวจ Opening Range, breakout, retest, SL/TP และเหตุผลที่ EA ข้าม
5. แบ่งช่วงพัฒนา, validation และ out-of-sample ห้ามเลือกค่าจากช่วงท้ายแล้วเรียกช่วงเดิมว่า forward
6. บันทึก win rate พร้อมจำนวน trade, average win/loss, realized RR, expectancy, profit factor, drawdown, spread และ commission

ค่า preset เปิด Execute=true และ risk 1% สำหรับ Tester/demo ค่า EX5 ปกติเป็น signal-only
