# Opening Range Trader — หลักการและความเสี่ยง

Opening Range Retest เป็นระบบ continuation ที่ใช้กรอบราคาแรกของ session เป็นจุดอ้างอิง ไม่ใช่การทายทิศจาก indicator เพียงตัวเดียว

EA จะส่ง market order หลังแท่ง retest ปิด และ target/SL ที่ส่งจริงอาจต่างจาก planned line ของ Indicator เพราะราคาเข้า, spread, tick size และ commission เปลี่ยนตาม quote ขณะส่ง

ผลที่ควรรายงานจาก Tester ต้องรวมต้นทุนและ slippage ไม่ใช่รายงานแค่จำนวนลูกศรหรือเปอร์เซ็นต์แท่งที่ทะลุกรอบ ถ้าผลดีเฉพาะ session hour หรือค่าพารามิเตอร์จุดเดียว ให้ถือว่าเสี่ยง overfit จนกว่าจะผ่านช่วง out-of-sample และ forward demo
