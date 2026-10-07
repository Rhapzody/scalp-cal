# WickHunt SR + Anchor Pine 1.02 — สถานะตรวจสอบ

วันที่ 2026-10-05

- Source ใหม่ `Pine/Indicators/WickHuntSRAnchor.pine` รวม engines สองชุดเป็นอิสระ ใช้รูปทรง/สี/ป้าย/ระยะ markers ต่างกัน และแยก Inputs/Alerts
- อ่านและเทียบลำดับกับ `SwingCore.mqh`, `WickHuntContextCore.mqh`, `WickHuntSRCore.mqh`, `WickHuntHistory.mqh`, `ReplayClosedHistory()` ของ WickHuntSRFlow 1.06 รวมถึง core/FVG ของ WickHuntAnchor 1.01
- ใช้ EMA seed จาก Close แรก/Signal 0, warmup และ histogram rising/non-rising ของ SwingCore ไม่แทนด้วย pivot detector แบบอื่น
- ตรวจ SR state order: retest ก่อน advance; ระดับก่อนเพิ่ม swing ของแท่งปัจจุบัน; reclaim หลัง advance จึงไม่ให้แท่ง reclaim เป็น break; failure ของ hold ไม่เริ่ม candidate ใหม่ในแท่งเดียวกัน; รับ retest แท่งที่ 8 แต่ไม่รับที่ 9; direct break ไม่รับที่จบแท่งหลัก
- แยก FVG/strength: SR Breakout บังคับ FVG ทิศ/color/body และ leading wick ≤30%; Anchor OR/AND ตาม Input เริ่มต้น OR และ leading wick <10% ไม่บังคับสี/body
- คำขอ TF หลักคืน object ที่ offset `[1]` ร่วมกับ `lookahead_on`; Trend/touch คำนวณใน context TF หลัก ส่วน H/L ของแท่ง hunt ปัจจุบันสะสมใน context TF ย่อย
- Source review เท่านั้น **ยังไม่ได้คอมไพล์หรือยืนยัน runtime ของไฟล์ใหม่นี้ใน TradingView** ในงาน Pine ก่อนหน้า Add to chart ติดหน้า Sign in และไม่มี Pine compiler ในเครื่อง
- ไม่มีการรัน tests/backtest, synthetic replay, ตรวจผลกราฟจริง หรือสร้าง/ส่ง alert จริง ตามคำขอเดิม

ไฟล์ MT5 และ standalone WickHuntAnchor Pine เดิมไม่ถูกแก้เพื่อทำ combined version นี้ การตรวจ hash/ZIP เป็นการตรวจความครบของ artifact ไม่ใช่การรับรอง logic หรือผล compile

## Translation error ที่ผู้ใช้รายงาน

ภาพวันที่ 2026-10-05 แสดง `Script could not be translated from: |B|string mainTF = input.timeframe("60", ...` ตรวจ source และ distribution แล้ว บรรทัดแรกเป็น `//@version=6` ไม่มี UTF-8 BOM และเป็น source ชุดเดียวกัน การประกาศ `string` ใช้ได้ใน v6 จึงสงสัยว่าการวางใน editor อาจทำให้ compiler annotation หาย/ไม่ได้รับการอ่าน ยังไม่ได้เห็นโค้ดทั้งหมดใน editor จึงไม่ได้ยืนยันสาเหตุแน่นอน

เพิ่มสำเนา `.txt` ที่เหมือน source ทุก byte และวิธีวางแทนโค้ดทั้งหมดในคู่มือ ไม่แก้การประกาศตัวแปรหรือกฎสัญญาณ ยังไม่ถือว่าคอมไพล์ผ่าน

## 1.01 — 2026-10-06

แก้เฉพาะเวลา endpoint ของเส้น family Anchor จาก mainOpened เป็น closedAt; e.tip เป็น snapshot ณ event อยู่แล้ว ไม่มีการแก้ signal engines, SR line/levels หรือ filters. Source/hash/package review เท่านั้น ยังไม่ยืนยัน compiler/runtime TradingView

## 1.02 — 2026-10-06

แก้ shared engine completeness ด้วย source indices และ closed lower-bar duration ภายใน main End รองรับ gaps ใน canonical feed; first partial loaded window ยังไม่ผ่าน. Signal conditions SR/Anchor อื่นคงเดิม ไม่ใช้ MT5 session API ใน Pine และยังไม่ยืนยัน TradingView compiler/runtime. Source/package review เท่านั้น ไม่รัน tests/backtest
