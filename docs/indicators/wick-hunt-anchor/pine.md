# WickHuntAnchor — Pine Script v6, version 1.05

Source: [WickHuntAnchor.pine](../../../Pine/Indicators/WickHuntAnchor.pine)

พอร์ตเงื่อนไข **WickHuntAnchor MT5 1.12 เฉพาะโหมด TF ย่อยปิด** ค่าเริ่มต้น TF หลัก H1 / TF ตรวจ M5 ตรวจเมื่อ M5 ปิดโดยไม่รอ H1 ปิด ทั้งสอง TF ปรับใน Inputs ได้ ใช้กับกราฟแท่งเวลาปกติ เช่น M1, M5, M15, H1 หรือ H4 โดย TF กราฟกับ TF ตรวจต้องหารกันลงตัว

## Error CE10213 / output

Pine 1.03 เพิ่ม `plot(close, title = "Hidden output", display = display.none, editable = false)` ใน global scope ทันทีหลัง `indicator()` ให้มี output ที่ไม่ขึ้นกับส่วนวาดสัญญาณ ไม่แสดงเส้นหรือเปลี่ยน scale ตาม [เอกสาร Plots](https://www.tradingview.com/pine-script-docs/visuals/plots/) ส่วน plot ของ event, labels, lines, alerts และ logic เดิมยังอยู่

ไฟล์ 1.02 ฉบับเต็มมี global plot ของ Buy/Sell อยู่แล้วที่ท้ายไฟล์ จึงยังไม่ยืนยันสาเหตุของ CE10213 ที่ผู้ใช้พบ และการเพิ่ม hidden output ไม่ถือเป็นหลักฐานว่า TradingView compile ผ่าน ให้แทนที่ source ทั้งหมดด้วยไฟล์ฉบับเต็มที่มี `//@version=6` บรรทัดแรก หากยังพบ error ต้องดู editor และ source ที่กำลังตรวจจริง

## ติดตั้ง TradingView

1. เปิดกราฟ → Pine Editor → สร้าง Indicator ใหม่
2. คัดลอกไฟล์ `.pine` ทั้งหมดวางแทนโค้ดเดิม ต้องมี `//@version=6` เป็นบรรทัดแรก ไม่คัดลอกเครื่องหมาย ``` ของ Markdown
3. Save แล้ว Add to chart
4. Inputs เริ่มต้น `mainTF=60`, `checkTF=5`, OR, `searchBars=36`, Buy green / Sell red = true

ใช้ M15/M1 ให้ตั้ง `mainTF=15`, `checkTF=1`; H4/M5 ตั้ง `mainTF=240`, `checkTF=5`. ชื่อสคริปต์ H1/M5 บอกค่าเริ่มต้น ตารางสถานะบอก TF ที่ใช้งานจริง

ลูกศร Buy ใต้ Low และ Sell เหนือ High ของแท่งบน TF กราฟที่ครอบคลุมเวลาสัญญาณ เมื่อกราฟเล็กกว่า TF ตรวจ เช่น M1/M5 รับผล M5 ที่ปิดแล้วเมื่อเริ่มรอบใหม่ วางลูกศรที่แท่ง M1 ก่อนหน้า

## ตัวกรองหางเดิม — ใหม่ใน Pine 1.02

`minSweptWickBodyPercent=10` มีผลเฉพาะ `huntBars=1`: วัดหางของแท่งหลักก่อนหน้าที่ถูกกวาด เทียบกับ `abs(Close−Open)` ของแท่งนั้นเอง Buy ใช้หางล่าง Sell ใช้หางบน ต่ำกว่าเกณฑ์ไม่ผ่าน เท่ากันผ่าน

Doji ผ่านเมื่อมีหางด้านที่ถูกกวาด; ไม่มีหางด้านนั้นไม่ผ่าน ตั้ง 0 ปิดกรองได้ และตั้งมากกว่า 100 ได้ เมื่อ `huntBars≥2` จะไม่ใช้ตัวกรองนี้ ค่า `maxHeadPercent` ของ Strong anchor ยังแยกต่างหาก ไม่เปลี่ยนกฎ FVG

## Logic ล่าสุด

- Buy: หางล่าง TF หลักกวาดต่ำกว่าขอบ Low ต่ำสุดของ N แท่งหลักก่อนหน้า และ Close TF ย่อยกลับถึง/เหนือ Open TF หลัก; Sell กลับด้านด้วยหางบนและ Close กลับถึง/ใต้ Open
- สะสม High/Low แท่งหลักจากแท่งย่อยตามเวลา ไม่ใช้ High/Low สุดท้ายของแท่งหลักจากอนาคต
- ลากระดับปลายหางไปทางซ้ายบนแท่งหลักที่ปิดก่อนแท่ง hunt เปิด หยุดแท่งแรกที่ Low ≤ tip ≤ High ถ้าไม่ผ่านไม่ข้ามไปแท่งถัดไป
- ระยะ anchor เริ่มต้น 36 แท่ง: แท่งก่อน hunt เป็น 1, รวม 1–36; 0 ค้นทั้งหมดที่ Pine เก็บไว้
- ค่าเริ่มต้น Buy ชนเขียว Close > Open และ Sell ชนแดง Close < Open; doji ไม่ผ่าน ปิดแยกฝั่งได้ `requireColor` เดิมถ้าเปิดจะบังคับสีทั้งคู่แม้ปิดตัวเลือกแยกฝั่ง
- เลือก FVG OR Strong / FVG AND Strong / FVG only / Strong only
- Strong วัดหางบนของ anchor สำหรับ Buy, หางล่างสำหรับ Sell เป็น % ของ High–Low ทั้งแท่ง ต้อง **น้อยกว่า** threshold; เท่ากันไม่ผ่าน ค่า % มีผลกับ Strong เท่านั้น ไม่เอาไปกรอง FVG ใน OR/FVG only
- FVG ใช้ Bull Low3 > High1 หรือ Bear High3 < Low1 และแท่งกลางครอบคลุม gap รับแท่งกลางผู้สร้าง FVG เมื่อแท่งสามปิดก่อน hunt แล้ว หรือแท่งสามยืนยัน ไม่รับแท่งแรกเพียงเพราะอยู่ในชุด FVG
- เมื่อหางยืดและเปิดกรองสีฝั่งนั้น ทบทวนแท่งแรกที่ชนใหม่: ถ้ายังเป็น anchor เดิมที่ผ่านให้ปรับ metadata/Tooltip (เส้นตรึงอยู่ที่ signal tip เดิม); ถ้าเปลี่ยนหรือไม่ผ่านลบสัญญาณเดิม สัญญาณใหม่ต้องผ่านการกลับ Open ณ Close ของแท่งย่อยที่กำลังตรวจอีกครั้ง
- เมื่อปิดกรองสีฝั่งนั้นทั้งตัวเลือกเดิมและแยกฝั่ง จะไม่ทบทวน event เดิมเมื่อหางยืด ตามพฤติกรรม MT5 1.12
- ในแท่งหลักเดียวกันมีหนึ่ง event ที่ยัง valid ต่อฝั่ง; ยกเลิกแล้วเกิดใหม่ได้ แค่ราคากลับผิดฝั่ง Open โดย tip ไม่เปลี่ยนไม่ลบ event เดิม
- ข้อมูลย่อยเริ่มกลางแท่งหลักหรือขาดแท่ง จะไม่สร้าง/ทบทวนสัญญาณใน window ที่ข้อมูลไม่ครบ

ไม่มี SR/MACD, breakout/pullback, engulf หรือ break TF ย่อย ตัวนี้ตรวจ lower close เท่านั้น ไม่มีโหมด tick หรือ main-close ของ MT5/EA และไม่มี spread/SL/TP

## เส้น Anchor ตรึง ณ สัญญาณ — ใหม่ใน Pine 1.04

เก็บ `buySignalTip` / `sellSignalTip` แยกจาก buyTip/sellTip ที่ใช้ทบทวนปลายหางล่าสุด เส้นเริ่มที่ timestamp ของสัญญาณ ณ Close TF ย่อย และราคา signal tip แล้วลากกลับไป anchor ไม่เริ่มที่ main Open และไม่เลื่อนระดับเมื่อหางยืด

Tooltip แสดง Wick at signal / Latest wick แยกกัน เมื่อ event ถูกยกเลิกยังลบเส้นและลูกศรตามเดิม และ event ใหม่ตรึงเส้นที่ snapshot ใหม่ การสะสม H/L, FVG/Strong, colors, minSweptWickBodyPercent และ alerts ใช้กฎเดิม ไม่ใช้การตรึงเส้นไปตรึงสัญญาณ

## ช่วงปิดตลาด / เวลาไม่มีแท่ง — ใหม่ใน Pine 1.05

ใช้ `bar_index` ใน context TF ตรวจย่อยแทนการบังคับ timestamp ต่อกันทุก 5/15 นาที แท่งที่มีจริงติดกันใน feed จึงผ่านช่วงไม่มีแท่ง เช่น weekend/daily break หรือไม่มีการซื้อขายตามข้อมูล TradingView เมื่อเปลี่ยน main window หลัง engine ประมวลผล source bar ก่อนหน้าแล้ว จะรับ first available bar แม้ timestamp ช้ากว่า main Open

window แรกที่โหลดเริ่มกลางแท่งหลักยังไม่ผ่านจนถึง main window ถัดไป; invalid OHLC, source index ที่ไม่ต่อกัน, close ไม่ถูกต้อง หรือ close เกิน main End ยังไม่ผ่าน ยอมรับแท่งย่อยสุดท้ายที่ duration สั้นกว่าปกติตาม session แต่ต้องปิดจริงและไม่เกิน main End ไม่ใช้ final main High/Low ล่วงหน้า

Pine อ่าน quote-session metadata ของ broker MT5 ไม่ได้ ใช้ canonical bars ของ TradingView เป็นหลัก ไม่สามารถแยกช่องว่างที่ผู้ให้ข้อมูลไม่มีแท่งออกจากเวลาปิดตลาดด้วยตารางโบรกเกอร์แบบ MT5 ได้ จึงไม่รับรองการตัด open-session data gaps เหมือน MT5 ในทุก feed. เงื่อนไขราคา/anchor/alerts/frozen links เดิมคงเดิม

## Inputs

ทุกช่องแสดง `ชื่อตัวแปร | ความหมาย` ใน Inputs

| ตัวแปร | ค่าเริ่มต้น | ความหมาย |
|---|---|---|
| mainTF / checkTF | 60 / 5 | TF หลัก / TF ตรวจย่อย |
| huntBars | 1 | จำนวนหางก่อนหน้าที่กวาดพร้อมกัน (1–1000) |
| minSweptWickBodyPercent | 10 | หางด้านที่ถูกกวาด/เนื้อขั้นต่ำ % เฉพาะ huntBars=1; 0 ปิด; Doji ผ่านเมื่อมีหางด้านนั้น |
| minHuntPoints | 0 | ระยะทะลุขอบขั้นต่ำ แบบ strict greater |
| enableBuy / enableSell | true / true | เปิดตรวจแยกฝั่ง |
| anchorRule | FVG OR Strong | กฎแท่งแรกที่ปลายหางชน |
| maxHeadPercent | 30 | threshold Strong; ไม่ใช้กรอง FVG ใน OR/FVG only |
| requireBuyGreen / requireSellRed | true / true | บังคับสี anchor ตามฝั่ง |
| requireColor | false | ตัวเลือกเดิมเปิดบังคับสีทั้งสองฝั่ง |
| requireBody | false | tip ต้องอยู่ใน body ของ anchor |
| minFVGPoints | 0 | ช่องว่าง FVG ขั้นต่ำ |
| requireMiddleColor | false | สีแท่งกลางต้องตรงทิศ FVG |
| requireFVGDirection | false | ทิศ FVG ต้องตรง Buy/Sell |
| searchBars | 36 | จำกัดระยะ anchor; 0 = ทั้งหมดที่เก็บ |
| mainHistory | 1000 | จำนวนแท่งหลักเก็บใน cache (3–5000) |
| checkHistory | 100000 | แท่งย่อยที่ขอ ขึ้นกับแผน TradingView |
| pointOverride | 0 | 0 ใช้ syminfo.mintick; ใส่ broker _Point เองเมื่อต้องการเทียบ MT5 |
| visibleSignals | 100 | ลูกศร/เส้นล่าสุดสูงสุด 0–500; 0 ซ่อนภาพแต่ยังตรวจ/alert |
| arrowGapPoints | 200 | ระยะลูกศรจากแท่งกราฟ |
| arrowSize | Tiny | ขนาดลูกศร |
| showLinks / showStatus | true / true | เปิดเส้น anchor และตารางแยกกัน |
| buyColor / sellColor / linkColor | lime / tomato / silver | สีลูกศรและเส้น |
| enableAlerts | false | เปิดใช้ alert ของสัญญาณใหม่ |
| cancellationAlerts | true | เมื่อเปิด alerts ให้แจ้งการยกเลิกด้วย |

หากต้องการเทียบ preset OR ที่คุณใช้ใน MT5 ก่อนหน้า ตั้ง `maxHeadPercent=20`, `arrowGapPoints=60`, สีทั้งสองฝั่ง true และ `searchBars=36`

## Alerts

เปิด `enableAlerts` แล้วสร้าง Alert เลือก **Any alert() function call** ให้รับสัญญาณย่อยทุกจังหวะแม้เปิดกราฟ H1/H4 อยู่ ไม่ต้องรอ TF กราฟปิด เปิด `cancellationAlerts` เพื่อรับ CANCELLED อ้างอิงเวลา event เดิม หากยืนยันใหม่ใน M5 เดียวกัน อาจได้รับยกเลิกและสัญญาณใหม่ตามลำดับ

แยก alert conditions BUY / SELL / BUY CANCELLED / SELL CANCELLED ได้ แต่ความถี่ Once Per Bar จำกัดตามแท่งกราฟที่เปิด ถ้าต้องการทุก event ให้ใช้ Any alert() function call

การแจ้งยกเลิกไม่ได้ลบ alert ที่ได้รับแล้ว เมื่อเปลี่ยน Inputs ต้องสร้าง alert ใหม่เพื่อใช้ค่าปัจจุบันตาม [TradingView alerts](https://www.tradingview.com/pine-script-docs/concepts/alerts/) ไม่ส่ง Telegram โดยตรงและไม่ส่งรูปแบบ EA

## ประวัติและข้อจำกัด

ใช้ [request.security_lower_tf()](https://www.tradingview.com/pine-script-docs/concepts/other-timeframes-and-data/) รับผลทุกแท่งย่อยในแท่งกราฟใหญ่ เรียงตามเวลา ส่วนกราฟที่เล็กกว่า TF ตรวจใช้ผลก่อนหน้าที่ปิดแล้วด้วย offset `[1]` คำขอข้อมูล anchor และขอบ sweep TF หลักทุก field มี offset `[1]` เพื่อใช้เฉพาะแท่งที่ยืนยันแล้ว

ที่รอยต่อแท่งกราฟใหญ่ ใช้ผล TF ย่อยที่ปิดล่าสุดก่อนรอบกราฟใหม่เป็น boundary snapshot เพิ่มด้วย และจำเวลา check ที่ใช้แล้วแบบ rollback ปกติ เพื่อไม่ละทิ้งแท่งย่อยสุดท้ายและไม่วาดซ้ำ

ลูกศรยังเปลี่ยน/หายได้ก่อนแท่งหลักปิดตามกฎทบทวน anchor และ Pine มี [realtime rollback](https://www.tradingview.com/pine-script-docs/language/execution-model/) จึง replay intrabars ของแท่งกราฟปัจจุบันเมื่ออัปเดต ใช้ varip เฉพาะกัน alert ซ้ำ ไม่ใช้เก็บ logic ที่ย้อนตรวจไม่ได้

History TF ย่อยขึ้นกับแผนและข้อมูล TradingView ช่วงเก่าที่ไม่มี intrabars จะไม่มีสัญญาณ Cache แท่งหลักค่อย ๆ สะสมตั้งแต่ประวัติย่อยที่เข้าถึงได้ และล้างเมื่อขาดทั้งช่วงหลักเพื่อไม่ค้นทะลุแท่งที่ไม่เห็น Labels/lines สูงสุด 500; แสดงไม่เกินจำนวนล่าสุดที่ตั้ง ลูกศรที่ถูกตัดออกจาก cache การวาดไปแล้วจะไม่สร้างคืนเมื่อ event ใหม่กว่าถูกยกเลิก

ข้อมูลราคา/session/เวลาเปิดแท่งและ minimum tick อาจต่างจาก broker MT5 จึงไม่รับรอง event ตรงกันทุกจุด กลไก boundary ใช้ [timeframe.main_period](https://www.tradingview.com/pine-script-docs/concepts/chart-information/) เพื่อรักษา TF กราฟใน request context. Source review ไม่ใช่ compilation/runtime verification สถานะใน [pine-build.md](pine-build.md)
