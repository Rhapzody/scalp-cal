# Pine 1.05 — สถานะตรวจสอบ

วันที่ 2026-10-06

พอร์ตจาก MT5 WickHuntAnchor **1.12 เฉพาะ lower-TF-close mode** โดยปรับ source Pine 1.04 เดิม:

- 1.05 ตรวจ continuity ด้วย source bar_index, รับ first available bar ของ main window ใหม่เมื่อมี previous source bar และยอมรับ session-shortened closed bar; window แรกที่โหลดกลางแท่งหลักยังไม่ผ่าน ไม่ได้อ่าน MT5 quote metadata จาก Pine
- 1.04 เก็บ buy/sellSignalTip เฉพาะ birth/reset/cancellation แยกจาก latest tips; เส้นใช้ event timestamp และ signal tip และ f_refresh ไม่ย้ายระดับเส้น; revalidation/alerts เดิมคงเดิม
- 1.03 เพิ่ม hidden global plot ทันทีหลัง indicator() เพื่อตรวจ output ได้จากต้นไฟล์ ตามรายงาน CE10213 ของผู้ใช้; ไฟล์ 1.02 ฉบับเต็มมี global event plots ที่ท้ายไฟล์อยู่แล้ว จึงยังไม่ยืนยัน root cause หรือ native compiler result
- เพิ่ม minSweptWickBodyPercent=10 เฉพาะ huntBars=1: previous-main lower wick (Buy)/upper wick (Sell) เทียบ body; threshold=0 หรือ N≥2 bypass; Doji ผ่านเมื่อมีหางด้านนั้น
- กฎ OR / AND / FVG only / Strong only, default Strong 30%, search 36, สี Buy/Sell true
- First collision, strict sweep / leading-wick threshold และ % ของ Strong แยกจาก FVG
- FVG anchor รับแท่งกลางที่มี third confirmation ปิดแล้วก่อน hunt รวมกับ third anchor เดิม
- เก็บ birth time / anchor / tip ต่อฝั่ง ทบทวนเมื่อ tip ยืดตาม color-filter behavior ของ MT5 1.12
- ส่ง cancellation delta และ active snapshot ทุกแท่งย่อยเพื่อถอดลูกศร/อัปเดตเส้นแม้สัญญาณอยู่ในแท่งกราฟก่อนหน้า
- ใช้ main payload offset `[1]` + lookahead_on และสร้าง main H/L จากแท่งย่อยตามลำดับ ไม่มี import final main H/L ก่อนเวลา
- เพิ่ม snapshot ของแท่งย่อยที่ปิดล่าสุดก่อนรอยต่อกราฟใหญ่ผ่าน timeframe.main_period และจำ lastAppliedCheck แบบ var ป้องกันการข้าม/วาดซ้ำ; ยังต้องยืนยัน native realtime ของ TradingView
- Inputs มีชื่อตัวแปรคู่กับความหมาย UTF-8 และบรรทัดแรก `//@version=6` ไม่มี BOM

อ่านอ้างอิง Pine v6 ทางการเรื่อง objects, nested requests, request.security_lower_tf และ realtime rollback. ตรวจ source/ไฟล์แจกจ่าย ไม่รัน tests/backtest หรือส่ง alert จริง ตามคำขอเดิม

**ยังไม่ได้ยืนยัน compiler/runtime ของ Pine 1.05 บน TradingView.** รุ่นก่อนพยายาม Pine Editor แล้วพบ Sign in ก่อนผล compiler; ไม่ถือเป็นผล compile ของรุ่นนี้ ไม่ใช้ MetaEditor compile MQL5 เป็นหลักฐานสำหรับ Pine

ต้องนำไฟล์ไป Save / Add to chart ใน Pine Editor ของ TradingView เพื่อให้ได้ผล compiler และตรวจข้อมูล native ของ symbol ที่ใช้
