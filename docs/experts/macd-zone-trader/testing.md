# การติดตั้งทดสอบ MACD Zone Trader 1.10

## ผลตรวจอัตโนมัติ

| ส่วน | ขอบเขต | ผล |
|---|---|---|
| Trade plan | เทียบสัญญาณกับ indicator จริง, ช่วง pattern SL, TP ใกล้สุด, ห้ามใช้อนาคต | 3,673 checks ผ่าน |
| Execution + shared broker | Spread, lot/risk, R:R, OrderCheck/Send mocks, duplicate, restart, uncertainty, OnTick | 133 checks ผ่าน รวม broker regression เดิม 59 checks |
| รวม EA | ไม่เปิด terminal และไม่ส่ง order จริงระหว่าง unit/integration tests | **3,806 checks ผ่าน** |
| Regression ทั้งโปรเจค | `sh scripts/test.sh` ของเครื่องมือเดิมและตัวใหม่ทั้งหมด | ผ่าน |
| MetaEditor | คอมไพล์ MACDZoneTrader 1.10 เป็น EX5 | **0 errors / 0 warnings** |

Compiler result จะอยู่ใน `dist/experts/macd-zone-trader/compile.txt` และ compiler log ใน ZIP ชุดติดตั้ง

การผ่าน tests หมายถึงโปรแกรมทำตามกติกาที่ทดสอบ ไม่ใช่ผล backtest ราคาตลาด

ทดสอบเพิ่มใน 1.10: ค่าเริ่มต้นยังให้ 27 สัญญาณใน fixture เดิม, การกรองทิศทาง, break buffer สอง timeframe, wick/close touch และ invalidation, tail filter, TP buffer ก่อน spread, risk/SL Inputs และความตรงกันของ EA/Indicator เมื่อเปลี่ยนค่าร่วมกัน

## คำสั่งนักพัฒนา

เรียกจาก root ของ checkout หรือ root ภายใน ZIP:

```sh
sh scripts/test.sh macd-zone-trader
sh scripts/compile-macos.sh macd-zone-trader
python3 scripts/package.py macd-zone-trader
```

Test runner ใช้ Python 3 กับ clang++ และแปลงเฉพาะ syntax array ของ MQL เป็น C++ เพื่อรัน core จริง รวมถึงดึง `OnTick` และฟังก์ชัน persistence จาก EA จริง การเรียก API broker ถูกจำลอง ไม่มีการส่งเงินหรือออเดอร์จริง

มีการตรวจว่า PullbackCore/SwingCore/FVGCore ตรงกับ indicator และ ScalpCore/ScalpBroker ตรงกับ Calculator ใน checkout ชุดเต็ม เพื่อป้องกันความต่างของกติกาโดยไม่ตั้งใจ

## ทดสอบใน MT5 Strategy Tester

1. ติดตั้ง EX5 ตาม README แล้วเปิด **View → Strategy Tester** หรือกด **Ctrl+R**
2. เลือก Expert: **MACDZoneTrader\MACDZoneTrader.ex5**
3. เลือก symbol ของ broker ที่ต้องการตรวจ ใช้ **M1** เป็น timeframe ของ Tester
4. เลือก model **Every tick based on real ticks** เพื่อทดสอบผลของราคา Bid/Ask และ spread ระหว่างแท่งด้วยข้อมูลละเอียด เลือกช่วงวันที่ที่ broker มีประวัติ M1/M5 และ ticks ครอบคลุม
5. กำหนด deposit, สกุลบัญชีและ leverage ให้ตรงกับกรณีที่จะประเมิน
6. ใน Inputs โหลด `docs/experts/macd-zone-trader/tester-demo.set` จาก ZIP หรือกำหนด `InpExecuteTrades=true`, `InpRiskPercent=1.0`, `InpMinRR=1.0` ด้วยตนเอง
7. กรอก `InpCommissionPerLot` เป็นประมาณการค่าไป–กลับต่อ lot ของบัญชีที่ทดสอบ ถ้าคง 0 การกรองก่อนส่งจะยังไม่รวมคอมมิชชัน
8. ตรวจ `InpMaxSpreadPoints`, `InpSLBufferPoints` และ `InpTPBufferPoints` ตาม point/tick size ของ symbol ไม่ใช้ค่าของโบรกเกอร์คนละ digits โดยไม่แปลงหน่วย
9. เปิด **Visual mode** ในการตรวจลำดับสัญญาณรอบแรก แล้ว Start
10. อ่าน **Journal / Deals / Orders / Results** ตรวจเวลาและราคาแต่ละรายการ เทียบกับ MACDZonePullback ด้วย Inputs และประวัติชุดเดียวกัน
11. บันทึก report พร้อม symbol, broker, ช่วงวันที่, model, deposit, leverage, Inputs, commission และ execution delay ทุกครั้ง

MetaTrader อธิบายว่า real ticks ใกล้เงื่อนไขจริงกว่า และ Tester ตั้ง execution delay ได้ ดู [Strategy Testing](https://www.metatrader5.com/en/terminal/help/algotrading/testing) ทั้งนี้ [Real and Generated Ticks](https://www.metatrader5.com/en/terminal/help/algotrading/tick_generation) ระบุว่าหากมีแท่ง M1 แต่ไม่มี ticks บางช่วง ระบบอาจสร้าง ticks แทน จึงต้องอ่านคุณภาพข้อมูลของ report ด้วย

## รายการที่ควรตรวจใน Visual test

| กรณี | ผลที่ควรเกิด |
|---|---|
| แนบ/เริ่ม EA ตอนมีลูกศรเก่า | ไม่เปิดจากลูกศรเก่าทันที รอแท่ง M1 ถัดไป |
| Buy ครบเงื่อนไข | SL ต่ำกว่าไส้ต่ำสุดใน pattern; TP เป็น High M5 ที่ยืนยันแล้วใกล้สุดเหนือ Ask |
| Sell ครบเงื่อนไข | strategy SL สูงกว่า pattern; broker SL/TP เพิ่ม spread ทั้งคู่ |
| R:R หลังเผื่อ spread = 1 และ commission = 0 | ผ่านตัวกรอง R:R หากเงื่อนไข broker อื่นผ่าน |
| R:R หลังเผื่อ spread < 1 | ไม่มี order และ log แจ้งเหตุผล |
| swing ใกล้สุดให้ R:R ไม่พอ แต่ swing ถัดออกไปให้พอ | ยังข้าม ไม่ขยาย TP เพื่อฝืนให้ผ่าน |
| ไม่มี swing ที่ยืนยันแล้วด้านกำไร | ข้าม ไม่มี TP สมมติจากอนาคต |
| SL อยู่ใกล้กว่าระยะ Stops/Freeze | ข้าม ไม่ขยาย SL เองจนผิด pattern |
| งบ 1% ไม่พอ minimum lot | ข้าม ไม่ปัด lot ขึ้น |
| spread สูงกว่าเพดาน | ข้าม |
| มี position/pending บน symbol | ไม่เปิดซ้อน |
| แตะโซนและเบรก LH/HL ในแท่งเดียวกัน | ไม่เป็น entry ตามกติกา indicator |
| LH/HL ถูกเบรกก่อนเข้าโซนแล้ว | ไม่เอาการเบรกเก่ามาเปิด |
| quote เปลี่ยนระหว่าง check/persistence | เตรียมใหม่ก่อนส่งได้ไม่เกิน 3 ครั้ง หรือข้าม |
| หลาย tick ใน M1 เดียวกัน | พิจารณา/ส่งจากสัญญาณนั้นครั้งเดียว |
| เปิด TP buffer | TP เข้าหาจุดเข้า; ยังใช้ swing เดิม และข้ามหาก R:R ไม่ถึงเกณฑ์ |
| ปรับ M1/M5 break buffer | ต้องปิดพ้นระดับรวม buffer; เท่าระดับยังไม่ผ่าน |
| เปลี่ยน Touch เป็น Close | ไส้แตะอย่างเดียวยังไม่เริ่มรอยืนยัน |
| เปลี่ยน Invalidation เป็น Wick | ไส้เลยขอบไกลยกเลิก แม้ปิดกลับเข้าโซน |
| เลือก Buy only / Sell only | แสดงและเทรดเฉพาะด้านที่เลือก เมื่อ Inputs ทั้งสองตัวตรงกัน |
| กำหนด commission มากขึ้น | RR สุทธิลดลงและ lot อาจลดลง หรือถูกข้าม |
| เปลี่ยน execution delay/slippage | ตรวจ RR และ risk ที่ fill จริงจาก log ไม่ถือว่าตรงกับ quote เสมอ |

## ทดสอบสถานการณ์ผิดปกติ

Automated tests ครอบคลุม OrderCheck rejection, permission/margin failure, persistence failure, timeout, partial fill, PLACED, signal ซ้ำหลัง restart, quote drift และ history retry โดยใช้ API จำลอง

เมื่อทดสอบบน demo ให้ตรวจผลไม่แน่ชัดตามขั้นตอน recovery ใน README ห้ามตีความ `OrderSend=true` ว่า fill สำเร็จเสมอ เพราะ [เอกสาร OrderSend](https://www.mql5.com/en/docs/trading/ordersend) กำหนดให้ตรวจ retcode และสถานะการทำรายการด้วย

## ประเมินผลกลยุทธ์

หลังยืนยันว่า EA ทำงานตรงกติกาแล้วจึงแยกประเมินผลตลาด: จำนวนรายการ, win rate, expectancy, drawdown, spread/commission และความต่างระหว่าง RR ก่อนส่งกับหลัง fill ควรแยกช่วงที่ใช้ปรับ Inputs ออกจากช่วงที่ใช้ตรวจผล ไม่ใช้ผล unit tests เป็นหลักฐานว่ากลยุทธ์ทำกำไร

**สิ่งที่ยังไม่ได้ทำในการส่งมอบครั้งนี้:** native Strategy Tester กับประวัติ tick ของ broker, ตรวจภาพ native MT5 และ forward test บัญชี demo ไม่มีการติด EA บนบัญชีหรือส่งคำสั่งจริงระหว่างพัฒนา
