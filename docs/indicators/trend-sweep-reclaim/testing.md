# ทดสอบ Trend Sweep Reclaim 1.00

## ผลตรวจในการส่งมอบ

| ส่วน | ผล | สิ่งที่ยืนยัน |
|---|---|---|
| Indicator core | 435 checks ผ่าน | EMA/ATR จริง, Buy/Sell, sweep/reclaim, room, buffer, cooldown, session, no-future replay |
| Indicator OnCalculate | 15 checks ผ่าน | buffers ตรงแท่ง, forming bar ว่าง, popup ไม่ซ้ำ, history retry, ซ่อนแผน |
| EA core/plan | 449 checks ผ่าน | core เดียวกัน, ระดับตรง Indicator, fresh signal, tick snapping |
| EA execution/broker | 127 checks ผ่าน รวม broker regression 59 | R:R/lot/spread/commission/room, exposure, duplicate, persistence, quote drift, timeout/partial, OnTick |
| MetaEditor | ทั้งสอง EX5: 0 errors / 0 warnings | คอมไพล์ source จริง |
| Market performance | **ยังไม่ได้ทดสอบ** | ไม่มีตัวเลข win rate, profit factor หรือ drawdown ที่รับรอง |

ข้อมูลราคาสร้างขึ้นใช้ตรวจเงื่อนไขของโปรแกรมเท่านั้น จำนวนสัญญาณใน fixture ไม่ใช่จำนวน trade ในตลาด ไม่มีการติด EA กับบัญชีหรือส่งคำสั่งจริงระหว่างพัฒนา

## ทดสอบใน MT5 Strategy Tester

ขั้นตอนประเมินตลาดด้านล่างใช้ **EA TrendSweepTrader ซึ่งติดตั้งจาก ZIP แยกต่างหาก** ส่วน Indicator ZIP มี source/EX5/tests ของ Indicator เท่านั้น

1. ติดตั้งตาม README แล้วเปิด **View → Strategy Tester / Ctrl+R**
2. เลือก `TrendSweepTrader\TrendSweepTrader.ex5`, symbol ที่จะใช้จริง, timeframe **M5**
3. เลือก **Every tick based on real ticks** และช่วงที่ broker มีประวัติครอบคลุม ใช้ deposit, สกุลบัญชีและ leverage ตามกรณีที่ต้องการประเมิน
4. โหลด `docs/experts/trend-sweep-trader/tester-demo.set` หรือใส่ `InpExecuteTrades=true` ด้วยตนเอง ค่า risk ใน preset คือ 1%
5. กรอกคอมมิชชันไป–กลับต่อ lot ใน `InpCommissionPerLot` ตรวจ spread จริง, `_Point` และ tick size ก่อนเลือก cap และ SLBufferPoints
6. ทดสอบรอบแรกด้วย **Visual mode** เทียบลูกศรจาก Indicator กับเวลาคำสั่งจริง โดยตั้ง Inputs กลยุทธ์และ History ให้ตรงกัน
7. ตรวจทั้ง Journal/Experts, Orders, Deals และผลทดสอบ EA ไม่จำเป็นต้องเปิดทุกลูกศร เพราะมีตัวกรอง execution
8. ทดสอบ execution delay ด้วย และอ่านคุณภาพข้อมูลใน report ไม่ถือว่าเลือก real ticks แล้วข้อมูลทุกช่วงสมบูรณ์อัตโนมัติ
9. เก็บ report, `.set`, symbol เต็มรวม suffix, broker server, ช่วงเวลา, digits/tick size, spread, commission, swap และ delay ทุกครั้ง

ดู [คู่มือ Strategy Testing](https://www.metatrader5.com/en/terminal/help/algotrading/testing) สำหรับตัวเลือกของ Tester

## รายการตรวจใน Visual mode

| กรณี | ผลที่ควรได้ |
|---|---|
| แท่ง M5 ยังไม่ปิด | ไม่มีสัญญาณใหม่จากแท่งนั้น |
| Buy sweep/reclaim ผ่านทุกเกณฑ์ | ลูกศรหลังปิด; SL พ้น Low + buffer; planned TP 2R จาก Close |
| Sell sweep/reclaim | กลับด้าน Buy; broker SL/TP มี spread compensation |
| ราคาปิดเท่าระดับที่กวาด | ไม่ผ่าน reclaim |
| EMA slow แบน/ผิดทิศ | ไม่มีสัญญาณ |
| TP 2R เลยขอบช่วงเดิม | ไม่ผ่าน room filter |
| Indicator ผ่าน แต่ actual Ask/spread ทำให้ TP เลย room | EA ข้ามพร้อมเหตุผล |
| Spread ผ่าน points แต่เกิน ATR cap | ข้าม |
| Bid ใหม่ห่าง Close เกิน EntryDriftATR | ข้าม |
| R:R สุทธิหลัง commission ต่ำกว่า MinRR | ข้าม แม้เป้าหมาย nominal เป็น 2R |
| งบไม่พอ minimum lot | ข้าม ไม่ปัดขึ้น |
| มี position หรือ pending บน symbol | ข้าม ไม่เปิดซ้อน |
| แนบ/รีสตาร์ตตอนมีลูกศรเก่า | ไม่เปิดจากลูกศรเก่า |
| ขาดการเชื่อมต่อข้ามแท่ง | Sync แล้วรอแท่ง M5 ใหม่ |
| ช่วง server time ข้ามเที่ยงคืน | ผ่านเฉพาะช่วงที่ตั้งตามเวลาปิดแท่ง |
| เปลี่ยน TargetRR / SLBuffer | เกิดแผนและจำนวนสัญญาณใหม่; ไม่แก้ position ที่เปิดแล้ว |
| Timeout/partial fill | ตรวจสถานะและ recovery ตาม README ก่อนปลด pending latch |

## ประเมินว่ามี edge จริงหรือไม่

1. ล็อกเวอร์ชันและค่าเริ่มต้นก่อนทดสอบ อย่าเริ่มด้วยการค้นหา win rate สูงสุดจากหลายพันชุด
2. แบ่งช่วงข้อมูลตามเวลา: ช่วงพัฒนา → ช่วง validation → ช่วงท้ายที่ไม่เคยใช้เลือกค่า (out of sample) ถ้าดูช่วงท้ายแล้วกลับไปแก้กติกา ช่วงนั้นไม่ใช่ข้อมูลที่ไม่เคยเห็นอีกต่อไป
3. ทดสอบทั้งตลาดขึ้น ลง แกว่ง ข่าวแรง และหลายระดับ spread โดยใช้ต้นทุนของ broker ที่จะประเมิน
4. รายงาน win rate พร้อมจำนวน trade, average win/loss สุทธิ, expectancy, profit factor, drawdown และผลแยกช่วงเวลา ไม่เลือกเฉพาะช่วงที่สวย
5. ตรวจความไวเมื่อปรับค่าทีละเล็กน้อย เช่น Lookback, RR, SL buffer และต้นทุน ถ้าผลดีเฉพาะจุดเดียวถือว่ายังไม่มั่นคง
6. หลังผ่านขั้นต้นจึงเก็บ forward demo แยกจาก backtest ด้วย Inputs ที่ล็อกไว้ เทียบ fill/slippage และเหตุผลที่ข้ามสัญญาณ

จำนวน trade น้อยทำให้ win rate ไม่นิ่ง ไม่มีจำนวนขั้นต่ำเดียวที่รับประกันความน่าเชื่อถือ ถ้าตัวกรองเข้มจนแทบไม่มีรายการ ให้รายงานว่า evidence ไม่พอ ไม่สรุปจากเปอร์เซ็นต์ชนะสูงของไม่กี่รายการ

ดู [Forward optimization ของ MT5](https://www.metatrader5.com/en/terminal/help/algotrading/strategy_optimization) และบันทึกผลใน `performance.md`

## คำสั่งนักพัฒนา

จาก root checkout หรือ root ภายใน ZIP ของแต่ละตัว:

```sh
sh scripts/test.sh trend-sweep-reclaim
sh scripts/compile-macos.sh trend-sweep-reclaim
python3 scripts/package.py trend-sweep-reclaim
```

ชุด Indicator ใช้ชื่อ `trend-sweep-reclaim` แทน ชุดทดสอบใช้ Python 3 และ clang++ แปลง syntax array ของ MQL เป็น C++ แล้วรัน core จริง รวมถึงดึงฟังก์ชัน OnCalculate/OnTick และ persistence จาก source จริง API terminal/broker จำลอง จึงไม่ใช่ native visual/tick test
