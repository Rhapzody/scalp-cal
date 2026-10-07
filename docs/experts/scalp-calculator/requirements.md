# สเปกที่นำไปสร้าง V1

ที่มา: ChatGPT conversation `6aa437ca-8244-83ec-b0b6-55c3f0863cf4` ชื่อ “แชทเรื่อง ea scalp calcualtor” จำนวน 10 turns ที่อ่านได้ครบ และไฟล์แนบ “Markdown ที่วาง (1)(1).md” อ่านทั้งไฟล์

ใช้คำตอบผู้ใช้ที่แก้ไขล่าสุดเป็นหลักเมื่อข้อความเก่าขัดกัน

## ข้อแก้ไขที่มีผลเหนือข้อความเก่า

1. Market ไม่มี Entry line; BUY ใช้ Ask และ SELL ใช้ Bid ปัจจุบัน Pending เท่านั้นที่มี Entry line
2. SELL ยก **SL และ TP ขึ้นทั้งคู่** ตาม spread สูตรเก่าที่ SL ลบ spread ถูกยกเลิก
3. Pending SELL ใช้ spread ตอน **Execute** ข้อสรุปเก่าเรื่อง spread-at-fill ถูกยกเลิก ไม่มีงานปรับ SL/TP ใน fill callback
4. ลาก SL ออก → TP ออกเท่ากับระยะที่ SL เคลื่อน; SL เข้าไม่ดึง TP กลับ; TP เคลื่อนได้อิสระ
5. Initial Balance เป็นค่าเริ่มต้น; Current Balance เลือกใน Inputs และไม่ใช้ Equity
6. Lot ปัดลงเสมอ; Risk เป็นงบรวมที่หารเท่ากันตาม Orders; ต่ำกว่า 0.01 หรือ broker minimum บล็อกทั้งชุด
7. เส้นต้องคงอยู่เมื่อเปลี่ยน timeframe
8. เปิดได้ไม่ครบให้รายงานผล โดยไม่ปิดออเดอร์ที่เปิดสำเร็จไปแล้ว

## Traceability

| Requirement | Implementation |
|---|---|
| Symbol บน chart; ไม่ hardcode gold contract | `ScalpReadSpec`, `_Symbol`, `OrderCalcProfit` |
| Balance initial/current | `InpRiskBase`, `RiskBase()` |
| Initial Balance กรอกเอง | `InpInitialBalance=0`; บล็อกจนมีค่ามากกว่า 0 |
| Risk presets ปรับได้ | Inputs 4 ค่าและปุ่ม Risk |
| Max Risk/Orders | Validation ใน Init และ Calculate |
| Market BUY Ask / SELL Bid | `ScalpCalculate` |
| Pending 4 ประเภท | `ScalpPendingKind` และ `ScalpTypeName` |
| Strategy RR | `ScalpRR` ก่อน compensation |
| Lot จาก Strategy SL | `OrderCalcProfit` แล้ว `ScalpLot` |
| Floor และ equal split | `ScalpFloorVolume` ต่อไม้; คง volume ชุดเดิมตอนส่ง |
| Minimum max(0.01, broker min) | บล็อก Calculate และ Alert ตอน Execute |
| SL → TP one-way follow | `ScalpFollowTP` ทั้ง timer refresh และ drag/change event |
| Strategy/Broker แยกกัน | `ScalpPlan` เทียบ `ScalpQuote` |
| SELL SL/TP + spread | `ScalpBrokerPrice`; optional Input เปิดเป็น default |
| Spread at Execute สำหรับ Pending | Snapshot ใน `Execute`, request มี protection ตั้งแต่ต้น |
| Spread realtime + Max Spread | Calculate และ Panel |
| Stop/freeze และ broker modes | Calculate, freeze guard และ OrderCheck |
| Volume min/max/step/limit | Calculate และ existing directional exposure |
| Margin ทั้งชุด | OrderCalcMargin × จำนวนไม้ที่เหลือ และ OrderCheck ต่อไม้ |
| Magic | Request ใช้ `InpMagicNumber` |
| Execution result | retcode, filled/placed/partial/accepted; Experts log และ tooltip |
| Partial batch ไม่ rollback | หยุดไม้ที่เหลือโดยไม่มี close/remove request |
| Enable/Disable | EA ON/OFF ไม่หยุด calculator |
| Clear และ Clear After Execute | ลบเฉพาะ setup; auto-clear เมื่อสำเร็จครบ |
| Hide/Show | ย่อเหลือ header + countdown |
| Timeframe persistence | chart-local hidden state objects; retain เฉพาะ REASON_CHARTCHANGE |
| Candle countdown | server-anchored monotonic timer 250 ms; month-aware bar boundary |

## รายละเอียดที่ตัดสินใจตอน implementation

- ไม่เดาทุนและไม่ตั้งทุน 100,000 ให้เอง: เริ่ม `InpInitialBalance=0` แต่ยังวางเส้นได้
- Lot ใช้ Strategy SL ตามแชท ไม่เปลี่ยนเงียบ ๆ ไปใช้ compensated SL หรือรวม commission แต่เพิ่ม Broker loss/reward estimate ให้เห็นผลจาก spread
- Reference volume ของ `OrderCalcProfit` ใช้ broker minimum ที่ valid แล้วหารกลับเป็น loss per lot แทนสมมติว่า 1.00 lot ใช้ได้กับทุก symbol
- ปัดราคาไปยัง tick grid ที่ใกล้ที่สุด แต่ **Lot ปัดลง** เสมอ
- SL/TP, spread compensation และ Lot ถูกจับครั้งเดียวต่อ Execute batch; Market Entry เปลี่ยนตาม quote ก่อนส่งแต่ละไม้ และตรวจงบเหลือก่อนส่ง
- บล็อก batch ใหม่หากบัญชี Netting มี exposure เดิมบน symbol เพื่อไม่เปลี่ยน position เดิม ส่วน batch ที่เริ่มจากว่างอาจรวม position ตามระบบ Netting
- ใช้ GTC สำหรับ pending; ไม่มี fallback ไปอายุอื่นโดยเงียบ ๆ
- Partial fill หรือผลไม่ยืนยัน: หยุดส่งไม้ถัดไป ไม่ retry และคง latch จนผู้ใช้กด REARM
- บันทึกผล Execute และ latch ข้าม timeframe; การแก้เส้น/เลือก risk/กด BUY/SELL ไม่ปลด latch
- ค่าเริ่มต้นของ SL 700 points, RR 2, spread สูงสุด 30 points และ deviation 20 points เป็นค่า Inputs ที่ปรับได้ ไม่ใช่ข้อกำหนดของ prop firm
- ลบ state เมื่อถอด EA/ปิด chart/เปลี่ยน Inputs/เปลี่ยนบัญชี ขอบเขต persistence ที่รับประกันคือการเปลี่ยน timeframe บน chart และบัญชีเดิม

## โครงสร้าง

```text
ScalpCalculator.mq5
  OnInit / OnDeinit      Inputs + restore/save chart-local state
  OnTick / OnTimer       อ่านเส้น, realtime calculations, countdown, render
  OnChartEvent           ปุ่ม, mode, drag, rearm, resize
  Execute                snapshot, revalidate, OrderCheck, OrderSend, result
  ScalpBroker.mqh        symbol/account APIs, validation, request builder
  ScalpCore.mqh          geometry, snapping, floor lot, RR, pending kind, follow
```

V1 ไม่จัดการ position หลังส่งและไม่อ้างว่า strategy risk เป็นเพดาน loss จริง เมื่อราคา gap, spread เปลี่ยนหลัง Execute, currency conversion เปลี่ยน หรือมีค่าใช้จ่าย ผลจริงอาจต่างจากค่าประมาณ
