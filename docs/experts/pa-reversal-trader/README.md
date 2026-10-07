# PA Reversal Trader 1.00

EA ที่ต่อยอดจาก `PAReversal` โดยใช้แท่งปิดเป็นสัญญาณเท่านั้น

## Logic

1. ตรวจ PA reversal ตาม `PAReversalCore.mqh` (`InpMinBars=3` เป็นค่าเริ่มต้น)
2. Buy ต้องปิดเหนือ EMA20 และ Sell ต้องปิดต่ำกว่า EMA20
3. สำหรับ bearish setup แท่ง retrace ก่อนหน้าอย่างน้อย 3 แท่งต้องเคลื่อนอยู่ใต้ EMA20 ยกเว้นแท่งล่าสุดของ retrace ที่สามารถเลย EMA ได้; bullish setup ใช้กฎกลับด้าน
4. Signal wick ต้องเข้าใกล้ EMA20 ไม่เกิน `0.25 × ATR(14)` หรือทะลุ EMA แล้วกลับมาปิดฝั่งเดิม โดยยอมให้ wick ทะลุได้ไม่เกิน `0.50 × ATR(14)`
5. SL ใช้ไส้สุดของแท่ง pattern สองแท่งล่าสุด บวก fixed buffer `15 points` แบบ Scalp Calculator
6. ถ้า `abs(EMA20 - SL) > 1.5 × ATR(14)` ให้ยกเลิก setup (เป็น safety envelope; ไม่ใช่ตัววัด proximity หลัก)
7. TP อิง swing ถัดไป แต่ถ้า swing ให้ RR มากกว่า 1:1 จะ cap TP ไว้ที่ 1R เท่านั้น
8. ถ้า R:R ณ ราคาเปิดแท่งถัดไปยังต่ำกว่า 1:1 จะรอได้แค่แท่งถัดไปหนึ่งแท่ง
   - Buy: ถ้า Ask ย่อลงถึง midpoint ระหว่าง SL/TP ให้เข้า
   - Sell: ถ้า Bid เด้งขึ้นถึง midpoint ระหว่าง SL/TP ให้เข้า
9. ถ้าแท่ง engulf ปิดเลย swing TP หรือราคาแตะ/ผ่าน TP ก่อนเข้า สัญญาณหมดอายุทันที
