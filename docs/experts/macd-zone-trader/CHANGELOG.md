# MACDZoneTrader — 1.10

- เพิ่ม Inputs เลือกทิศทาง Buy/Sell, break buffer M5/M1, touch แบบ wick/close, invalidation แบบ close/wick และตำแหน่ง close สำหรับ displacement
- ค่าเริ่มต้นคงกติกาสัญญาณรุ่น 1.00 และ histogram color บนทั้งสอง timeframe
- เพิ่ม TP buffer ก่อนถึง swing M5 ใกล้สุด แล้วตรวจ R:R หลัง spread/commission ตามเดิม
- คง risk เริ่มต้น 1% Equity ปรับได้, SL buffer ปรับได้ และ R:R ขั้นต่ำ 1:1
- อัปเดต preset กับคู่มือติดตั้ง/ทดสอบ; การปรับ buffer ไม่ย้าย SL/TP ของ position ที่เปิดแล้ว
