# Opening Range Retest — หลักการกลยุทธ์

กลยุทธ์นี้ตั้งสมมติฐานว่า หลังช่วงเปิดตลาดสร้างกรอบแรก ราคาอาจขยายต่อเมื่อทะลุกรอบ และการ retest ขอบเดิมที่ reclaim กลับไปทาง breakout อาจให้จุดเข้าและ stop ที่วัดได้

Buy:

1. เก็บ High/Low ของ Opening Range ตามเวลา server
2. หลังกรอบจบ แท่ง M5 ปิดเหนือ High อย่างน้อย `MinBreakATR` แต่ไม่เกิน `MaxBreakATR`
3. แท่ง breakout ต้องมี body และ close location ตาม Inputs
4. ภายใน `MaxRetestBars` แท่งถัดมา ราคาแตะ High เดิม แล้วปิดกลับเหนือ High พร้อมแท่งขึ้น
5. SL อยู่ใต้ Low ของแท่ง retest บวก ATR/points buffer และต้องอยู่ในช่วง MinStopATR–MaxStopATR
6. TP = `TargetRR × risk` ค่าเริ่มต้น 2R

Sell กลับด้านทั้งหมด ใช้ Low ของ Opening Range เป็นขอบ breakout และ High ของแท่ง retest เป็นฐาน SL

แท่ง breakout ใช้เป็น retest ไม่ได้ เพราะต้องรอแท่งถัดไปโดยตั้งใจลดความกำกวมของ OHLC ระบบยกเลิก breakout ถ้าราคาปิดทะลุกรอบฝั่งตรงข้ามหรือหมดเวลารอ

ค่าตั้ง 2R ทำให้จุดคุ้มทุนทางคณิตศาสตร์ของผลลัพธ์คงที่อยู่ที่ 33.33% ก่อนต้นทุน แต่ตลาดจริงมี spread, slippage, commission, stop ที่ถูกชนก่อน target และการออกกลางทาง จึงสรุป win rate จากสูตรนี้ไม่ได้

ไม่มี market backtest ใน checkout นี้ ตัวเลข win rate, expectancy และ drawdown จึงยังเป็น “ไม่มีข้อมูล” ไม่ใช่ศูนย์และไม่ใช่ค่าที่คาดเดา ดู [testing.md](testing.md) สำหรับวิธีสร้างหลักฐานด้วยข้อมูล broker
