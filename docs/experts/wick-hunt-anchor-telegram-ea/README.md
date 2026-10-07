# WickHuntAnchorTelegramEA 1.06

**รุ่น 1.06 แก้ error 4009 ตอนเขียนช่องข้อความว่างลงคิว; ใช้กฎตรวจ indicator 1.12 และส่งข้อความก่อนรูปเหมือนเดิม**

EA แจ้งเตือน WickHuntAnchor ตาม indicator MT5 **1.12** วาดลูกศรและเส้น anchor เอง ไม่ต้องติด indicator ซ้อนบนกราฟ EA ตัวนี้ ไม่มีการเปิด/ปิด/แก้ไขออเดอร์ และไม่มีการเผื่อ spread/SL/TP

ใช้สองโปรแกรม:

- **WickHuntAnchorTelegramEA** ติดแต่ละกราฟที่ต้องการตรวจ ตั้ง TF หลักและ TF ย่อยแยกกันใน Inputs
- **WickHuntAnchorTelegramSender** ติดกราฟว่างอีกหนึ่งกราฟต่อบัญชี/ช่องคิว รับข้อมูลจากทุก detector แล้วส่ง Telegram จึงไม่เอา HTTP มารอในตัวตรวจ

แยกโปรแกรมและคิวจาก WickHuntTelegramEA 1.00 รุ่น S/R เดิม: Sender ของ S/R ใช้กับคิว Anchor ไม่ได้

## เงื่อนไขสัญญาณ

ค่าเริ่มต้น H1/M5 และ `InpObservationMode=2`: ตรวจทุกครั้งที่ M5 ปิด ใช้ High/Low สะสมของ H1 ตั้งแต่เริ่มแท่งถึง M5 ที่เพิ่งปิด และใช้ Close M5 ยืนยันการกลับถึง Open H1 ไม่ต้องรอ H1 ปิด

1. Buy: หางล่างกวาด Low ของ N แท่งหลักก่อนหน้า และ Close TF ย่อยกลับถึง/เหนือ Open แท่งหลัก; Sell กลับด้านด้วยหางบนและกลับถึง/ใต้ Open
2. ลากระดับปลายหางไปทางซ้าย หยุดที่แท่งหลักก่อนหน้าที่ High/Low แตะระดับเป็นแท่งแรก หากแท่งนั้นไม่ผ่านกฎจะไม่ข้ามไปหาแท่งอื่น
3. จำกัดระยะ anchor ด้วย `InpSearchBars=36` นับแท่งก่อน hunt เป็น 1 จนถึง 36; 0 = ไม่จำกัด
4. Buy ต้องชน anchor เขียว และ Sell ต้องชน anchor แดง ตามค่าตัวกรองแต่ละฝั่งที่เริ่มต้นเป็น true; doji ไม่ผ่าน
5. เลือก OR / AND / FVG only / Strong only ได้ FVG ยอมรับแท่งกลางที่สร้าง gap เมื่อแท่งสามยืนยันปิดแล้ว และแท่งสามยืนยันตามกฎ indicator
6. Strong: หางหัวของ anchor ต้องสั้นกว่า % ของ High–Low ทั้งแท่งแบบ strict `<` ฝั่ง Buy วัดหางบน ฝั่ง Sell วัดหางล่าง ค่า % ไม่ไปกรอง FVG ในโหมด OR หรือ FVG only
7. เมื่อหาง main ที่ยังไม่ปิดยืดจน anchor เปลี่ยนหรือไม่ผ่าน สัญญาณเดิมถูกลบตาม indicator ต้องมีการกลับ Open ที่ผ่านกฎอีกครั้งจึงสร้างใหม่ได้ `InpNotifyCancellation=true` ส่งข้อความ CANCELLED อ้างอิง ID เดิมด้วย ภาพ/ข้อความที่ส่งไปแล้วจะไม่ถูกลบจาก Telegram

ไม่มี MACD/SR, breakout/pullback, engulf หรือเงื่อนไข break TF ย่อยใน EA Anchor ตัวนี้

Inputs ตรวจหา/วาดทั้ง 28 ตัวตรงกับ indicator 1.12 ชื่อและความหมายปรากฏคู่กันบนแผง Inputs ดูรายละเอียดใน `docs/indicators/wick-hunt-anchor/README.md` ของโครงการ

`InpObservationMode=0` ใช้ราคาวิ่งตรวจทันทีและไม่มี replay ย้อนหลัง; `=1` รอแท่งหลักปิด; `=2` ตรวจเมื่อแท่งย่อยปิด หากต้องการเทียบกับ indi ที่ใช้ตอนนี้ให้ใช้ `=2` ทั้งคู่

## ภาพสอง TF

`InpSendPictures=true` ทำงานตามลำดับนี้:

1. Detector บันทึกสัญญาณลงคิวทันที ไม่มีการวาดรูปก่อน
2. Sender ส่ง **ข้อความสัญญาณ** โดยไม่รอภาพ เมื่อ Telegram ตอบ HTTP 200 / ok=true จึงบันทึก text receipt ลงดิสก์
3. Detector เห็น receipt แล้วเริ่มสร้างภาพ TF หลักและ TF ย่อย ทีละรูปต่อรอบ timer
4. Sender ส่งสองภาพเป็นอัลบั้มตามหลัง caption ระบุว่ารูปของสัญญาณที่ส่งแล้ว และใช้ ID เดียวกับข้อความแรก

ข้อความ/การยกเลิกที่พร้อมส่งมีลำดับสูงกว่าอัลบั้มที่รอในช่องคิวเดียวกัน ถ้า Sender กำลังทำ HTTP request อยู่จะรอ request นั้นจบก่อนเลือกรายการถัดไป ไม่มีการรับประกันเวลารับข้อความเป็นวินาทีตายตัว

ภาพแต่ละ TF ประกอบด้วย:

- TF หลัก: แท่งเทียน, ลูกศรสัญญาณ, เส้นระดับปลายหาง และกรอบทองรอบ anchor
- TF ย่อย: แท่งเทียน, ลูกศรและเส้นทองที่แท่งยืนยัน พร้อมระดับปลายหางของ TF หลัก

ภาพสร้างจาก OHLC ของ MT5 ด้วย Canvas เป็น PNG ไม่ใช่ screenshot หน้าจอ TradingView และไม่มี indicator อื่น/MACD/panel บัญชี ไม่มีการเปิด ChartOpen หรือใช้ default.tpl จึงไม่เปิด EA ที่อยู่ใน template ตามมา และไม่เปลี่ยน TF กราฟที่ผู้ใช้กำลังดู

เก็บข้อมูลหลังข้อความแรกส่งสำเร็จ (หนึ่งรูปต่อรอบ timer) แต่สองรูปไม่ใช่ snapshot tick เดียวกัน รูปแสดงทั้งเวลาเกิดสัญญาณและเวลาเก็บข้อมูลตามเวลา broker แท่งปัจจุบันอาจยังไม่ปิด และในกรณีคิวช้าหรือเพิ่งเปิดเครื่อง รูปอาจมีแท่งหลังสัญญาณเพิ่มแล้ว ไม่รอแท่งอนาคตก่อนแจ้ง

ตั้งจำนวนแท่งในภาพด้วย `InpMainPictureBars=72` และ `InpLowerPictureBars=120` เพิ่มเพื่อ zoom out; ความละเอียดเริ่มต้น 1280×720 ถ้าข้อมูลไม่พร้อม/บันทึกภาพไม่สำเร็จภายในเวลารอ จะมีข้อความตามว่า `[Pictures unavailable]` พร้อม ID เดิม ข้อความสัญญาณแรกส่งไปแล้วและไม่ถูกถอน ไม่มีการส่งภาพบางส่วนปะปนกัน

PNG เป็น lossless DEFLATE แบบไม่บีบอัดเพื่อไม่ต้องใช้ DLL/ไลบรารีนอก MT5 ภาพเริ่มต้นประมาณ 2.8 MB ต่อภาพ ตั้ง `InpDeleteSentPictures=true` เพื่อลบภาพที่ส่งแล้วและประหยัดดิสก์

## ติดตั้ง Mac / Windows VPS

1. ใน MT5 เลือก **File → Open Data Folder**
2. คัดลอก `MQL5/Experts/WickHuntAnchorTelegramEA/` จาก ZIP ไปใน `MQL5/Experts/` โดยมี EX5 ทั้งสองตัว (รัน EX5 ได้เลยไม่ต้อง compile บน VPS)
3. ถ้าจะ compile เอง ให้วาง `MQL5/Indicators/WickHuntAnchor/WickHuntAnchorCore.mqh` และ `FVGCore.mqh` รวม `WickHuntQuoteSessions.mqh` ตามตำแหน่งใน ZIP ด้วย ไม่ต้องติด indicator ลงกราฟ
4. Navigator → Expert Advisors → Refresh แล้วติด **WickHuntAnchorTelegramEA** แต่ละกราฟ ใช้ preset ที่ตรง TF และตั้ง `InpQueueChannel=anchor`
5. อีกหนึ่งกราฟต่อช่องคิวติด **WickHuntAnchorTelegramSender** ใส่ `InpBotToken`, `InpChatID` ส่วนตัวใน MT5 และ `InpQueueChannel=anchor`
6. **Tools → Options → Expert Advisors → Allow WebRequest for listed URL** เพิ่ม `https://api.telegram.org` บอทต้องได้รับ `/start` จากแชทส่วนตัวหรือมีสิทธิ์ในกลุ่ม/ช่องปลายทาง
7. Detector กับ Sender ไม่ต้องอนุญาตเปิดออเดอร์ ปล่อย MT5 และการเชื่อมต่อ broker/อินเทอร์เน็ตทำงานต่อเนื่อง

EX5 รันบน MT5 Windows รวมถึง MT5 ผ่าน Wine บน Mac ส่วน Hostinger KVM ต้องมีระบบที่รัน MT5 Windows ได้และทำงานต่อเนื่อง การเลือกขนาด KVM อย่างเดียวไม่ได้ติดตั้ง MT5 ให้

ตัวอย่างชุดที่คุยกัน: XAUUSD M15, H1, H4 + EURJPY H4 + BTCUSD H4 ใช้ 5 detector และ 1 Sender รวม 6 กราฟที่เปิดค้าง ภาพสอง TF ไม่เพิ่มจำนวนกราฟที่เปิดค้าง

บน Mac ให้ติด EA แจ้งเตือนบนกราฟแยกจากกราฟ Scalp Calculator เพราะ MT5 ติด EA ได้หนึ่งตัวต่อกราฟ ส่วนกราฟ Scalp Calculator ใช้ indi เดิมได้ตามปกติ

## Presets

- `h1-m5-or-colors.set`: H1/M5, OR, Strong 20%, Buy เขียว/Sell แดง, ระยะ 36, ลูกศร 1/60 points
- `m15-m1-or-colors.set`: M15/M1 เงื่อนไขอื่นเหมือนกัน
- `h4-m5-or-colors.set`: H4/M5 เงื่อนไขอื่นเหมือนกัน
- `sender.set`: ช่อง anchor, timeout 15 วินาที, รอรูป 45 วินาที **หลังข้อความส่งสำเร็จ** ใส่ token/chat เอง

ค่าใน source สืบทอด indicator: Strong 30%, arrow gap 200 points; preset ใช้ Strong 20% และ gap 60 ตาม preset OR ที่จัดไว้ก่อนหน้านี้

## Inputs เพิ่มจาก indicator

| ตัวแปร | ค่าเริ่มต้น | ความหมาย |
|---|---|---|
| InpTelegramEnabled | true | เปิดบันทึกสัญญาณลงคิว Telegram |
| InpQueueChannel | anchor | ต้องตรงกับ Sender ทุก detector ที่ใช้ Sender เดียวกัน |
| InpInstanceID | ว่าง | ชื่อแยกชุดตรวจได้; hash รวมชื่อและค่าตรวจหาแยกแต่ละ symbol/TF/config |
| InpNotifyCancellation | true | แจ้งเมื่อสัญญาณที่เคยประกาศถูกยกเลิก |
| InpSendPictures | true | ส่งอัลบั้ม TF หลัก + TF ย่อย |
| InpPictureWidth / Height | 1280 / 720 | ขนาดภาพ; จำกัดไม่เกิน 2 ล้าน pixels |
| InpMainPictureBars / LowerPictureBars | 72 / 120 | จำนวนแท่งที่เห็นในภาพ (10–300) |
| InpPictureWaitSeconds | 30 | รอข้อมูลภาพต่อ job ก่อนข้าม |

| Sender input | ค่าเริ่มต้น | ความหมาย |
|---|---|---|
| InpBotToken / InpChatID | ว่าง | ตั้งส่วนตัวบน Sender ไม่ต้องตั้งบน detector |
| InpQueueChannel | anchor | ช่องคิวเดียวกับ detector |
| InpTimeoutMs | 15000 | HTTP timeout 1–30 วินาที (หน่วย milliseconds) |
| InpSendIntervalSeconds | 2 | เว้นการส่งแต่ละ request |
| InpRetryBaseSeconds / MaxSeconds | 5 / 300 | หน่วงส่งซ้ำเพิ่มแบบ exponential |
| InpLateAfterSeconds | 60 | คิวรอเกินเวลานี้ระบุ DELAYED |
| InpPhotoWaitSeconds | 45 | เวลารอรูปนับหลังข้อความแรกส่งสำเร็จ; เกินแล้วส่ง notice ตาม ไม่หน่วงข้อความแรก |
| InpDeleteSentPictures | true | ลบไฟล์ PNG หลังส่งสำเร็จ |
| InpShowStatus | true | สถานะบนกราฟ Sender |

## แยก Telegram สองแชท: M15/M1 กับ H1/M5

ใช้ **สองช่องคิวและ Sender สอง instance บนสองกราฟ** โดยแต่ละ Sender มี Chat ID ของแชทตัวเอง ช่องคิวใช้ตัวอักษรอังกฤษ ตัวเลข `_` หรือ `-` ยาว 1–48 ตัว ห้ามเว้นวรรค

| ชุด | Detector TF หลัก / ย่อย | InpQueueChannel ทั้ง detector และ sender | Sender Chat ID |
|---|---|---|---|
| แชทแรก | M15 / M1 | `m15_m1` | Chat ID แชทแรก |
| แชทสอง | H1 / M5 | `h1_m5` | Chat ID แชทที่สอง |

ทำตามขั้นตอน:

1. บนกราฟทองสำหรับ M15/M1 ติด Detector และโหลด **m15-m1-chat.set**: `InpHuntTF=PERIOD_M15`, `InpCheckTF=PERIOD_M1`, `InpQueueChannel=m15_m1`
2. บนกราฟทองสำหรับ H1/M5 ติด Detector และโหลด **h1-m5-chat.set**: `InpHuntTF=PERIOD_H1`, `InpCheckTF=PERIOD_M5`, `InpQueueChannel=h1_m5`
3. เปิดกราฟว่างหนึ่งกราฟ ติด Sender โหลด **sender-m15-m1.set** ใส่ Bot Token และ Chat ID แชทแรก; ช่องคิว `m15_m1`
4. เปิดกราฟว่างอีกกราฟ ติด Sender โหลด **sender-h1-m5.set** ใส่ Bot Token และ Chat ID แชทที่สอง; ช่องคิว `h1_m5`
5. เปิด WebRequest `https://api.telegram.org` ตามขั้นตอนติดตั้ง บอทต้องเข้าถึงทั้งสองแชทได้

**ใช้บอทเดียว**: ใส่ Bot Token เดียวกันทั้งสอง Sender แต่ Chat ID ต่างกัน เช่น บอทอยู่ในกลุ่มชื่อ “M15 signals” กับ “H1 signals”. แชทส่วนตัวหนึ่งแชทกับบอทหนึ่งตัวมี Chat ID เดียว การเปลี่ยนชื่อคิวอย่างเดียวไม่ได้สร้างแชทส่วนตัวใหม่ ถ้าต้องการหน้าต่างแชทส่วนตัวสองอัน ใช้บอทสองตัว หรือจัดสองกลุ่ม/แชทปลายทางต่างกัน

**ใช้คนละบอท**: ใส่ Bot Token ของบอทแรกใน Sender `m15_m1` และของบอทที่สองใน Sender `h1_m5` และใส่ Chat ID ปลายทางตามแต่ละบอท พิมพ์ `/start` ให้แต่ละบอทในแชทส่วนตัวก่อน หากเป็นผู้ใช้คนเดียวคุยกับสองบอท ค่า Chat ID อาจเป็นตัวเลขเดียวกันได้ แต่ Bot Token ต่างกันจะส่งเข้าหน้าต่างแชทของคนละบอท

คิวเป็นตัวเลือกว่า detector ส่งให้ Sender ไหน; **Chat ID** เป็นตัวเลือกว่า Telegram ส่งเข้าแชทไหน ต้องกำหนดทั้งคู่ อย่าใช้ชื่อคิวเดียวกันกับ Sender สองแชทเพราะระบบล็อกอนุญาต Sender เดียวต่อบัญชี/คิว

ตัวอย่างนี้รวม **2 detector + 2 sender = 4 กราฟ**. ถ้ามี detector 5 กราฟเหมือนชุดเดิมแต่แบ่งสองช่อง จะรวม 7 กราฟ. รูปไม่เพิ่มจำนวนกราฟที่เปิดค้าง

หลาย symbol/TF ส่งแชทเดียวกันได้: ตั้งชื่อคิวเดียวกันและใช้ Sender ของคิวนั้นเพียงตัวเดียว ไม่ต้องสร้าง Sender ต่อ detector. กราฟของ Sender เป็น symbol/TF ใดก็ได้ใน terminal/account เดียวกัน

ข้อความและภาพจะไปยัง Chat ID ที่ตั้งใน Sender ของแต่ละคิว และภาพแยกชื่อไฟล์ตามช่องคิวเพื่อไม่ให้การลบภาพในแชทหนึ่งกระทบอีกแชทหนึ่ง

หากเปลี่ยนแชทปลายทางระหว่างมีคิวค้าง รูปที่ยังไม่ได้ส่งจะไปยัง Chat ID ที่ตั้งใหม่ ควรรอให้คิวเดิมส่งเสร็จก่อน หรือใช้ชื่อช่องคิวใหม่สำหรับปลายทางใหม่

## การส่งซ้ำและการเปิดเครื่องใหม่

คิวอยู่ `MQL5/Files/WHAtelegram/<account hash>/<channel>/` ภาพอยู่ `MQL5/Files/WHAshots/` ไม่ใช้ FILE_COMMON และไม่เก็บ bot token ลงคิว

ล็อกป้องกัน detector ที่ symbol/TF/ค่าตรวจเหมือนกันซ้ำ และป้องกัน Sender ซ้ำต่อบัญชี/channel การเผยแพร่คิวเขียน temp และ flush ก่อนเปลี่ยนชื่อ `.pending` ข้อความแรกสำเร็จบันทึก `.textack` แบบ flush/temp/rename; ยังเก็บ `.pending` รอภาพ เมื่ออัลบั้มหรือ notice สำเร็จจึงเปลี่ยนเป็น `.sent` เก็บ receipt/metadata กันซ้ำไว้. ข้อความที่ปิดภาพหรือ CANCELLED จบหลัง text สำเร็จเลย

network/5xx/429 ส่งซ้ำอัตโนมัติและบันทึกเวลารอแยก text กับ pictures. รูปส่งไม่สำเร็จจะไม่ทำให้ข้อความสัญญาณเดิมถูกส่งใหม่. HTTP 400 จากอัลบั้มส่ง notice ตามแทน; auth/destination errors 400 ของข้อความ /401/403/404 พัก Sender และเก็บคิวให้แก้ token/chat/สิทธิ์ รีสตาร์ท Sender หลังแก้ Inputs

ติด detector ใหม่ครั้งแรกไม่ส่งสัญญาณย้อนหลังทั้งหมด ลูกศรย้อนหลังแสดงได้แต่แจ้งเฉพาะหลังเริ่มติดตั้ง ครั้งต่อมามี checkpoint อ่านเฉพาะเหตุการณ์ที่ยังอยู่ใน history และใหม่กว่า checkpoint พร้อมระบุ delayed ถ้าเวลา broker เก่าเกินหนึ่งนาที โหมด tick ไม่สามารถสร้าง tick ที่เกิดตอน MT5 ปิดย้อนหลังได้

เมื่อเปิด terminal ใหม่ Detector กู้ pending photo jobs ของ instance ตัวเองและไม่เริ่มสร้างก่อน `.textack`. Sender อ่าน `.textack` แล้วทำต่อเฉพาะภาพ ไม่ส่งข้อความแรกซ้ำ. ถ้าหางยืดจนมี CANCELLED จะยกเลิกภาพที่ยังไม่ได้ส่ง และส่ง cancellation ตามหลังข้อความเดิมโดยไม่รออัลบั้ม. รูปที่ส่งไปแล้วไม่ถูกลบจาก Telegram

หากคำตอบ HTTP สูญหายหลัง Telegram รับข้อความแล้ว อาจส่งซ้ำในการ retry ไม่มีการรับประกัน exactly-once; ID ในข้อความช่วยแยกสัญญาณเดิม หากยืนยันกับ Telegram สำเร็จแต่บันทึก `.sent` ไม่ได้ Sender จะหยุดเพื่อป้องกันส่งซ้ำไม่สิ้นสุด

EA ยังต้องมีข้อมูล main/lower ครอบคลุมช่วงที่มีราคาเสนอจริงตาม quote sessions ของ symbol; ช่วงปิดตลาดตามตารางยอมรับได้ใน 1.04 ส่วนข้อมูลขาดขณะควรมีราคายังไม่ผ่าน replay ตาม indicator ไม่มีการอ้างว่าสามารถกู้ทุกสัญญาณที่เกิดและยกเลิกไปแล้วระหว่างปิด MT5 ได้

## ตัวกรองหางเดิม — ใหม่ใน 1.02

`InpMinSweptWickBodyPercent=10` ตรงกับ indicator 1.12: เฉพาะ `InpHuntBars=1` วัดหางของแท่งหลักก่อนหน้าที่ถูกกวาด / เนื้อแท่งนั้นเอง Buy หางล่าง Sell หางบน ต่ำกว่าเกณฑ์ไม่ผ่าน เท่ากันผ่าน Doji ผ่านหากมีหางด้านนั้น ตั้ง 0 ปิดได้; N≥2 ไม่ใช้เกณฑ์นี้ และไม่ได้เปลี่ยน % Strong ของ anchor

เพิ่ม Input นี้ใน configuration identity ของ detector ด้วย เมื่ออัปเกรดหรือเปลี่ยน threshold จะใช้ checkpoint/identity ใหม่ คิวที่ส่งรอจาก configuration เดิมยังอยู่และ Sender ยังส่งต่อได้ตาม channel เดิม จึงอาจได้รับรายการที่สร้างก่อนเปลี่ยนเกณฑ์พร้อม ID เดิม

Sender 1.02 เปลี่ยนเลขรุ่นเพื่อจับคู่ชุดแจกจ่าย พฤติกรรมส่งข้อความก่อนภาพและแยก chat/channel คงเดิม ไม่ได้ติดตั้ง EA ลง terminal ในขั้นสร้างรุ่นนี้

## เส้นและภาพตรึง ณ สัญญาณ — ใหม่ใน 1.03

บนกราฟใช้ signal_tip/time ของ event ณ เกิดสัญญาณ ไม่เลื่อนเส้นตาม tip ล่าสุด ส่วน tip ล่าสุดยังใช้ค้น anchor/ยกเลิกเหมือนเดิม ส่ง CANCELLED เมื่อเงื่อนไขเสียตามเดิม

`SignalRecord` บันทึก `e.signal_tip` ในช่อง tip เดิมของ record ข้อความและภาพทั้งสอง TF จึงใช้ระดับเดียวกัน แม้ภาพสร้างหลังส่งข้อความหรือกู้จาก replay ตอนหางยืดแล้ว จุดปลายเส้นในภาพเป็นเวลาเกิดสัญญาณจริง โดย interpolate ตำแหน่งภายในแท่งหลัก ไม่ใช้ main Open; caption ระบุ Wick tip at signal แท่งในภาพยังเป็นข้อมูลเวลาจับภาพ อาจเห็นหางยาวผ่านเส้นที่ตรึงไว้

Binary record/schema และ configuration identity คงเดิม Sender 1.03 เปลี่ยนเฉพาะ version เพื่อจับคู่ชุดแจกจ่าย รายการเดิมที่ค้างคิวใช้ snapshot ที่บันทึกไว้ก่อนอัปเกรด ไม่แก้ย้อนหลัง ไม่ได้ติดตั้ง EA หรือส่ง Telegram จริงในขั้นสร้างรุ่นนี้

## รองรับเวลาปิดตลาด — ใหม่ใน 1.04

Detector ใช้ WickHuntQuoteSessions.mqh และ ReplayLowerClosed ของ indicator 1.12 โดยตรง ไม่กำหนดเวลาของทองตายตัว อ่านทุก quote session จาก symbol/broker ที่ใช้งานผ่าน [SymbolInfoSessionQuote](https://www.mql5.com/en/docs/marketinformation/symbolinfosessionquote) สถานะ H4/M15 หรือ TF ที่เลือกจะแสดง `sessions OK` เมื่ออ่านตารางสำเร็จ

หาก M15 แรกเกิดหลัง H4 Open จะยอมรับเมื่อเวลาตั้งแต่ Open ถึง M15 แรกอยู่นอก quote sessions ทั้งหมด เช่น Sunday start; หากมีพักตลาดกลาง H4 จะสะสม H/L จากแท่งปิดที่มีจริงต่อไปและรอ Close M15 reclaim ตามเดิม ข้อมูลที่หายทับช่วงมีราคาเสนอยัง skip ไม่เดา H/L และหากไม่มีตาราง session จะใช้ continuity guard เดิม

อัปเกรดไม่ reset ConfigurationKey/checkpoint เดิม จึงไม่ส่งสัญญาณย้อนหลังที่เพิ่งค้นเจอก่อน watermark ทั้งหมดออก Telegram ลูกศรย้อนหลังอาจเพิ่มได้ ถ้าจะดูสองเคสก่อนหน้าให้เพิ่ม `InpVisibleSignals` จาก 5 เป็น 100 เพื่อให้ไม่ถูกจำกัดการวาด

Sender 1.04 เปลี่ยนเฉพาะ version เพื่อจับคู่ชุด; ไม่เปลี่ยน text-first/pictures/chat routing. ตาราง quote เป็นรายสัปดาห์ปัจจุบัน อาจไม่ตรง session พิเศษหรือ DST เก่าทุกวันย้อนหลัง ไม่ได้ติดตั้ง EA ลง Mac/VPS และไม่ได้ส่ง Telegram จริงในการสร้างรุ่นนี้

## Build และสถานะตรวจสอบ

- `python3 scripts/sync-wick-hunt-anchor-runtime.py` สร้าง runtime/validation จาก indicator 1.12 โดยตรง
- `sh scripts/compile-macos.sh wick-hunt-anchor-telegram-ea`
- `python3 scripts/package.py wick-hunt-anchor-telegram-ea`

`AnchorRuntime.mqh` ระบุ SHA256 ของ source indicator ที่ใช้ เงื่อนไข/การ replay/การยกเลิก/การวาดลูกศรสกัดจาก source เดิม EA ใช้กฎ indicator 1.12 รวม Input ใหม่โดยตรง; ไม่เปลี่ยน EA S/R เดิม

เมื่ออัปเกรดจากรุ่นก่อน ให้เปลี่ยน **EX5 ทั้ง Detector และ Sender เป็น 1.06** แล้วแนบใหม่ ทั้งคู่ยังใช้ Inputs เดิมได้. ไม่แก้รูปแบบ binary ของ record สัญญาณเดิม; เพิ่ม receipt แยกระหว่างส่งข้อความกับภาพ

คอมไพล์และตรวจ source/package เท่านั้น ไม่ได้ backtest หรือส่ง Telegram จริง ยังต้องตั้ง credential และยืนยันการรับอัลบั้มจากสัญญาณจริงใน terminal ที่ใช้งาน ดู `testing.md`

อ้างอิง: [Telegram sendMediaGroup](https://core.telegram.org/bots/api#sendmediagroup), [MQL5 Canvas](https://www.mql5.com/en/docs/standardlibrary/canvasgraphics/ccanvas), [WebRequest](https://www.mql5.com/en/docs/network/webrequest)


## รุ่น 1.05 — ลูกศรและรายละเอียดปัญหาการเขียนคิว

แก้กรณีสถานะ `Outbox/checkpoint write failed; retrying` ทำให้ EA ออกจากรอบก่อน RenderEvents: วาดลูกศรจากผล detector ที่ replay สำเร็จก่อนประมวลผล outbox และยังให้ประมวลผล outbox ได้เมื่อการวาดล้มเหลว. เมื่อเขียนไม่สำเร็จจะยังเก็บสถานะ dirty เพื่อ retry และแสดง `arrows updated` หรือ `arrows pending` ตามผลการวาด ไม่ใช่ผลส่ง Telegram.

Checkpoint ใช้ candidate watermark; เปลี่ยน g_watermark หลังไฟล์ checkpoint เขียน/flush/move สำเร็จเท่านั้น ไม่ข้าม cursor ในหน่วยความจำเมื่อ checkpoint commit ล้มเหลว. Stable IDs, known records, queue schema และ ConfigurationKey เดิมคงเดิม. ไม่เปลี่ยน price conditions, session checks หรือ PNG/text-first flow และไม่มี Input ใหม่.

ไฟล์ I/O ที่ล้มเหลวแสดง operation/error บนกราฟ และพิมพ์ `WickHuntAnchor I/O | operation=... | error=... | file=... | data=...` ใน Toolbox → Experts. เก็บ GetLastError ก่อน FileClose/คำสั่งอื่นเปลี่ยนค่า; log ปัญหาเดิมไม่เกินหนึ่งครั้งต่อ 30 วินาที. ครอบคลุม record-open/write/flush/move, checkpoint-open/write/flush/move, active-delete และ textack/retry/completed receipt บางขั้นตอนใน Sender. ชื่อไฟล์และ Data Folder ช่วยระบุไฟล์จริงบน Ubuntu/Wine; ไม่บันทึก BotToken/ChatID ลง log.

ข้อความ generic ของรุ่นก่อนระบุได้ว่า ProcessSignals ล้มเหลว แต่ยังไม่ระบุว่าสาเหตุจริงเป็นสิทธิ์เขียน, move/rename, file lock, ข้อมูลไฟล์ หรือพื้นที่ดิสก์. รุ่นนี้ยังไม่ได้ยืนยันสาเหตุ native I/O บน VPS ของผู้ใช้และไม่อ้างว่าทำให้ Telegram ส่งได้แล้ว.

เมื่อพบปัญหา:

1. เปลี่ยน EX5 Detector และ Sender เป็น 1.05 จาก ZIP แล้วแนบใหม่ด้วย Inputs/QueueChannel/InstanceID เดิม. ชุดนี้ไม่ได้ติดตั้ง EA ให้ผู้ใช้.
2. ดูสถานะบนกราฟและ Toolbox → Experts แล้วคัดลอกบรรทัด `WickHuntAnchor I/O` ที่เกิดหลังแนบ. รหัส error + operation + path เป็นหลักฐานสำหรับแก้ filesystem/queue ต่อ.
3. เปิด File → Open Data Folder; log ระบุโฟลเดอร์คิวภายใต้ `MQL5/Files/WHAtelegram/<account-key>/<channel>`. ให้ detector และ Sender ใช้ terminal/account/channel เดียวกัน.
4. รักษาไฟล์ checkpoint, pending, textack และ sent ไว้ขณะตรวจเพื่อให้กู้คิวและ deduplicate ต่อได้. การล้างคิว/เปลี่ยน InstanceID จะทำให้เปลี่ยนประวัติการส่งและไม่ใช่การแก้สาเหตุ I/O.

MetaEditor compile และ package/source checks เท่านั้น; ไม่รัน tests/backtest ไม่ติดตั้ง EA และไม่ส่งข้อความเพิ่มในการสร้างรุ่นนี้. ดู [testing.md](testing.md).


## รุ่น 1.06 — แก้ record-write/flush error 4009

Log จากผู้ใช้บน VPS ระบุ `operation=record-write/flush | error=4009` ซ้ำที่ไฟล์ `.active.tmp`. [MQL5 Runtime Errors](https://www.mql5.com/en/docs/constants/errorswarnings/errorcodes) กำหนด 4009 เป็น `ERR_NOTINITIALIZED_STRING`; [NULL](https://www.mql5.com/en/docs/constants/namedconstants/otherconstants) สามารถ deinitialize string ได้. Source ของรุ่นก่อนแปลงทุก field ผ่าน StringToCharArray รวม optional parent ของสัญญาณปกติ และ main_photo/lower_photo เมื่อปิดภาพหรือส่ง CANCELLED. การแปลง string ที่ว่าง/deinitialized นี้สอดคล้องกับ log และทำให้ record ไม่ถูก commit เป็น active/pending.

แก้ WATWriteString ให้ NULL/empty เขียน integer length=0 จำนวน 4 bytes โดยตรงก่อน StringToCharArray. ตรวจ byte count ของ length prefix สำหรับ nonempty ด้วย; SignalRecord ระบุ optional parent/main_photo/lower_photo ว่างอย่างชัดเจนก่อนเติมข้อมูล. ไม่กลบ/reset error เพื่อถือว่าบันทึกสำเร็จ ไม่แก้ข้อมูลข้อความจริง/UTF-8 และไม่เปลี่ยน wire schema 1. WATReadString เดิมอ่าน length=0 ได้อยู่แล้ว.

อัปเดต **Signal/Detector เป็น 1.06 ทุกกราฟที่ใช้**. Sender 1.05 ใช้ต่อได้กับแก้นี้ เพราะ decoder/schema และ transport เหมือนเดิม; Sender 1.06 ใน ZIP เปลี่ยนเลขรุ่นและใช้ header ที่แก้เดียวกันสำหรับชุดแจกจ่าย. คง Inputs/QueueChannel/InstanceID และไฟล์คิว/checkpoint/receipt เดิมไว้. ไม่ต้องติดตั้ง indicator หรือปรับ Token/ChatID เพื่อแก้ 4009.

ไฟล์ `.active.tmp` ที่เขียนไม่ครบยังไม่ใช่ pending ที่ส่งได้; retry รุ่นใหม่จะเขียน temporary record ใหม่ก่อน commit ตามเดิม. การกู้สัญญาณย้อนหลังใช้ checkpoint ที่มีอยู่และช่วงประวัติที่โหลดตามกฎเดิม ไม่อ้างว่าจะกู้ทุกสัญญาณหากไม่มี checkpoint. Signal eligibility, frozen links, quote sessions, text-first/picture scheduling และ configuration identity คงเดิม.

MetaEditor compile และ source/package checks เท่านั้น ยังไม่ได้ยืนยัน native queue/send จาก VPS หลังอัปเดต ไม่รัน tests/backtest ไม่ติดตั้ง EA และไม่ส่งข้อความเพิ่มในการแก้รุ่นนี้. หากยังมี error ให้ส่ง `WickHuntAnchor I/O` operation/code ที่ใหม่หลังอัปเดต.
