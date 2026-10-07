# ทดสอบ Opening Range Retest

ใช้ `OpeningRangeRetest` เพื่อดูสัญญาณใน Visual mode และใช้ `OpeningRangeTrader` แยกสำหรับ backtest คำสั่งจริง

```sh
sh scripts/test.sh opening-range-retest
sh scripts/compile-macos.sh opening-range-retest
python3 scripts/package.py opening-range-retest
```

การทดสอบอัตโนมัติตรวจ breakout/retest, Buy/Sell, side/retest mode, stop/target geometry, invalid Inputs และ replay แบบไม่ใช้ข้อมูลอนาคต ไม่ใช่ market backtest

เมื่อตรวจใน MT5 ให้ใช้ M5, symbol เดียวกับ EA, เวลา server เดียวกัน และ Inputs กลยุทธ์ชุดเดียวกัน ตรวจกรอบ High/Low, เวลา breakout, เวลา retest และ planned SL/TP ก่อนประเมิน win rate
