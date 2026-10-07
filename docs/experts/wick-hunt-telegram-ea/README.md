# WickHuntTelegramEA 1.00

EA แจ้งเตือนตาม WickHuntSRFlow **v1.04** พร้อมลูกศร, tooltip และเส้น S/R บนกราฟ ใช้ signal cores ร่วมกับ indi โดยตรง ไม่มีคำสั่งเปิด/ปิด/แก้ไขออเดอร์ ไม่ต้องแนบ indi บน VPS ส่วนคอมที่ใช้เข้าเทรดสามารถใช้ indi เดิมคู่กับ Scalp Calculator ได้

## สอง EA ในชุดเดียว

| ชื่อใน Navigator | แนบที่ไหน | หน้าที่ |
|---|---|---|
| `WickHuntTelegramEA` | ทุกกราฟที่ต้องการตรวจ | ตรวจราคาสด, วาด, เก็บสัญญาณลง outbox; ไม่เรียก WebRequest |
| `WickHuntTelegramSender` | อีก 1 กราฟใน terminal เดียวกัน | อ่าน outbox รวมแล้วส่ง Telegram; ใช้ symbol/TF ใดก็ได้ |

สำหรับชุดที่คุยกัน เปิดตัวตรวจ 5 กราฟ และเพิ่มกราฟตัวส่ง 1 กราฟ รวม **6 กราฟ / MT5 หนึ่งตัว** ใช้บัญชีและ `InpQueueChannel` เดียวกัน ตัวตรวจไม่ต้องรอ Telegram แม้ตัวส่งรอ WebRequest อยู่

| กราฟตัวตรวจ | `InpHuntTF` | `InpSignalTF` |
|---|---|---|
| ทอง M15 | PERIOD_M15 | PERIOD_M1 |
| ทอง H1 | PERIOD_H1 | PERIOD_M5 |
| ทอง H4 | PERIOD_H4 | เลือก TF ย่อยเอง |
| EURJPY H4 | PERIOD_H4 | เลือก TF ย่อยเอง |
| BTCUSD H4 | PERIOD_H4 | เลือก TF ย่อยเอง |

TF กราฟที่แนบไม่เปลี่ยน TF ใน Inputs อัตโนมัติ ค่าเริ่มต้นยังเป็น H1/M5; TF ใหญ่ต้องมากกว่าและหารระยะ TF เล็กลงตัว และไม่เกิน D1 แต่ละ symbol ใช้ชื่อจริงจากโบรกเกอร์ รวม suffix เช่น `XAUUSDm`

## Logic และวิธีคำนวณ

ใช้ `WickHuntSRCore.mqh`, `WickHuntContextCore.mqh` และ MACD/FVG cores ตัวเดียวกับ indi ไม่ตัดประวัติเพื่อประหยัด VPS ค่าเริ่มต้น `InpHistoryBars=0`, `InpContextHistoryBars=0` ใช้ประวัติที่ terminal โหลดไว้ทั้งหมด การ replay ของสอง TF ใช้วิธีเดิม: TF ใหญ่เมื่อข้อมูลเปลี่ยน/เริ่มแท่งใหม่ และ TF เล็กเมื่อเริ่มแท่งใหม่ ไม่ replay ทุก tick

ตรวจราคาสดผ่าน `OnTick` และมี timer 1 วินาทีเป็น fallback เมื่อ quote/history พร้อม ทุกสถานการณ์ต้อง hunt → กลับถึง Open → TF เล็กปิดข้าม S/R หลัง reclaim → ยืนยันตามจำนวน → retest ในแท่ง TF ใหญ่เดียวกัน กฎ TF ใหญ่/ทิศทาง/FVG/สองหางเหมือน [คู่มือ WickHuntSRFlow](../../indicators/wick-hunt-sr-flow/README.md)

- Breakout: H/L ของแท่งก่อนหน้าแตะ directional SR ภายใน `InpTouchBars` โดยไม่ต้องปิดทะลุ; Buy กวาดล่าง, Sell กวาดบน; first collision จากปลายหางต้องเป็นแท่งยืนยัน FVG แข็งแรงทิศเดียวกัน และ tip อยู่ใน body
- Pullback: structural break แล้วมี swing ปลายทางยืนยันก่อนแท่ง hunt; กวาดหางด้านเดียวครบ `InpPullbackHuntBars` ตามเทรน
- ค่าเริ่มต้นรอยืนยัน 1 แท่งแล้วรอ retest 8 แท่ง; `InpRetestBars=0` ให้สัญญาณจากแท่งแรกที่ปิดข้ามหลัง reclaim โดยข้าม hold/retest
- Signal inputs ของ indi รวม MACD, SR, จำนวนหางแยกสองสถานการณ์, buffer/tolerance, ความแรง FVG และ Buy/Sell มีให้ครบในตัวตรวจ

Symbol, TF, Inputs และต้นประวัติต้องตรงกันจึงเทียบระดับกับ indi ได้ เครื่องคนละเครื่องหรือคนละโบรกเกอร์อาจโหลดข้อมูลไม่เท่ากัน รุ่นนี้ยังไม่มีผลทดสอบ parity บน terminal จริง

## Inputs เพิ่มของตัวตรวจ

| Input | ค่าเริ่มต้น | ความหมาย |
|---|---|---|
| `InpQueueChannel` | default | ชื่อห้องคิวภายใน terminal ใช้ตรงกันทุกตัวตรวจและตัวส่ง; a-z/A-Z/0-9/_/- ยาว 1–48 |
| `InpInstanceTag` | ว่าง | label และ namespace เพิ่ม; tag ต่างกันใช้แยกกรณีตั้ง symbol/TF/กฎเหมือนกันโดยตั้งใจ |
| `InpDrawSignals` | true | วาดลูกศรพร้อม tooltip |
| `InpShowStatus` | true | สถานะโหลดข้อมูล, คิวรอส่ง, ส่งสำเร็จ หรือ disk error |

`InpShowSR`, `InpShowContextSR`, `InpVisibleSignals`, สี/ความหนาลูกศร และ `InpPopupAlert` ใช้แบบ indi เดิม จำกัดจำนวนลูกศรในหน่วยความจำได้โดยไม่ลบ outbox/หลักฐานการส่ง

ตัวตรวจที่ symbol/TF/กฎ/tag เหมือนกันใน channel เดียวกันจะใช้ identity เดียวกัน จึงไม่อนุญาตให้เปิดซ้อนพร้อมกัน สถานะของทอง M15/H1/H4 จะแยกกัน เมื่อปรับ signal Inputs จะได้ identity ใหม่; เปลี่ยนเฉพาะสี/การแสดงผลไม่เปลี่ยน identity

## Inputs ของตัวส่ง

| Input | ค่าเริ่มต้น | ความหมาย |
|---|---|---|
| `InpBotToken` | ว่าง | token ของ bot ตั้งเฉพาะตัวส่ง; ไม่เก็บลง outbox และไม่พิมพ์ลง log |
| `InpChatID` | ว่าง | chat ID ของคุณ/กลุ่ม หรือ @channel ที่ bot มีสิทธิ์ส่ง |
| `InpQueueChannel` | default | ใช้ชื่อเดียวกับตัวตรวจ |
| `InpTimeoutMs` | 5000 | รอ HTTP 1000–30000 ms; ไม่กระทบ thread ของตัวตรวจ |
| `InpSendIntervalSeconds` | 2 | เว้นอย่างน้อย 1–60 วินาทีระหว่างคำขอ |
| `InpRetryBaseSeconds` | 5 | ระยะเริ่ม retry แบบเพิ่มสองเท่า |
| `InpRetryMaxSeconds` | 300 | เพดานระยะ retry; HTTP 429 ใช้ retry_after ที่ยาวกว่าได้ |
| `InpLateAfterSeconds` | 60 | คิวค้างเกินเวลานี้ติดข้อความ DELAYED ALERT; 0 ปิด label |
| `InpShowStatus` | true | สถานะตัวส่งและจำนวนส่ง/ผิดพลาดใน session นี้ |

เปิดตัวส่งเพียงหนึ่งตัวต่อบัญชี/channel มี lock ป้องกันเปิดซ้อน คิวอยู่ใน terminal เดียวกัน ไม่ใช่คิวข้าม VPS หรือข้าม MT5 คนละ installation

## ติดตั้ง

1. แตก `WickHuntTelegramEA-1.00.zip` แล้วคัดลอกโครงสร้าง `MQL5` ไปยัง Data Folder ของ MT5 (`File → Open Data Folder`) ชุดนี้มี EX5 ทั้งตัวตรวจและตัวส่ง รวม headers สำหรับแก้ไข/คอมไพล์ source
2. Refresh Navigator แล้วแนบ `WickHuntTelegramEA` ทีละกราฟ เลือก TF หลัก/ย่อยของแต่ละกราฟตามตาราง อย่าแนบ Scalp Calculator บนกราฟตัวตรวจเดียวกัน เพราะ MT5 ใช้ EA ได้หนึ่งตัวต่อกราฟ
3. ตั้ง `InpQueueChannel=default` เหมือนกันทุกตัว ไม่ต้องติดตั้ง EX5 ของ indi หรือนำ indi มาแนบซ้อน
4. สร้าง bot ของตัวเองผ่าน [BotFather](https://t.me/BotFather), ส่ง `/start` หา bot หรือเพิ่ม bot เข้ากลุ่มให้มีสิทธิ์ส่ง และนำ ChatID จาก [getUpdates ของ Bot API](https://core.telegram.org/bots/api#getupdates) ของ bot ตัวเอง
5. ไปที่ `Tools → Options → Expert Advisors` เปิด `Allow WebRequest for listed URL` แล้วเพิ่ม **`https://api.telegram.org`**
6. เปิดอีก 1 กราฟ แนบ `WickHuntTelegramSender` ตั้ง `InpBotToken`, `InpChatID` และ channel เดียวกัน ไม่มีข้อความทดสอบอัตโนมัติ; ตัวส่งเริ่มส่งเมื่อมีสัญญาณจริงในคิว
7. เปิด MT5 ค้างไว้และเชื่อมต่อบัญชี ตรวจสถานะบนแต่ละกราฟและ Experts log เก็บ token ไว้ใน VPS/Inputs ของตัวส่ง; ถ้า export `.set` ของตัวส่งจะมี token อยู่ในไฟล์ด้วย

ตัวตรวจเป็น EA แจ้งเตือน ไม่เปิดออเดอร์ แม้ปิด Algo Trading ก็ยังรับ OnTick ได้ตามพฤติกรรม MT5 แต่ MT5 ต้องเปิดและต่อ quote อยู่

Hostinger KVM2 ประเมินว่าเหมาะกับ MT5 หนึ่งตัวกับชุดนี้ แต่ยังไม่มีผลวัด CPU/RAM บน VPS จริง ใช้ MetaTrader template/desktop ของ Hostinger และคง session ที่ MT5 ทำงานอยู่ การปิด MT5, logout desktop หรือหยุด VPS จะหยุดการตรวจด้วย

## คิว การรีสตาร์ต และข้อจำกัด

คิวอยู่ที่ **`MQL5/Files/WickHuntTelegram/<account-hash>/<channel>/`** แยกตาม server+account ใช้ event ID จาก instance+แท่ง TF ใหญ่+ฝั่ง จึงมีหนึ่ง event ต่อฝั่งต่อแท่งใหญ่ และเปลี่ยนบัญชีต้องถอด/แนบใหม่ก่อนตรวจหรือส่งต่อ

- `.pending`: สัญญาณที่เขียนและ flush ครบแล้ว รอส่ง
- `.sent`: Telegram ตอบ HTTP 200 พร้อม top-level `ok=true` และเก็บ acknowledgement สำเร็จ
- `.retry`: จำนวนครั้ง/เวลารอครั้งถัดไป คงไว้หลังรีสตาร์ต
- `.failed`: record ที่อ่านไม่ได้ เก็บไว้ตรวจสอบ ไม่ถือว่าส่งสำเร็จ
- `.state`: เวลา reclaim/บริบทที่เคยสังเกตในแท่งใหญ่ปัจจุบัน เพื่อคืนสถานะและ replay แท่งปิดเมื่อ restart
- `.lock` / `.tmp`: lock ขณะทำงานและไฟล์ที่ยังไม่ publish; ตัวส่งไม่อ่าน `.tmp`

เวลาและราคาในข้อความเป็น ณ ตรวจพบจริง; เวลาแสดงเป็น clock ของโบรกเกอร์ ไม่แปลงเป็นไทย คิวส่งช้าจะระบุ DELAYED ALERT ไม่ใช่สัญญาณสดสำหรับเข้าออเดอร์ ลูกศรเดิมคืนได้จาก record ที่เก็บไว้ โดยไม่สร้างสัญญาณย้อนหลังของช่วงที่ terminal ไม่ได้เปิด

Network/5xx/429 จะ retry พร้อม backoff ไม่ลบสัญญาณ 400/401/403/404 จะพักตัวส่งและเก็บคิวรอแก้ Inputs/สิทธิ์ bot ถ้าส่งสำเร็จแล้วเขียน acknowledgement ไม่ได้ จะพักเพื่อให้ตรวจไฟล์ก่อนเริ่มใหม่

**ไม่รับประกันว่าไม่พลาด 100% หรือส่งได้ exactly-once**: MT5 อาจรวม/ข้าม tick ขณะโปรแกรมกำลังทำงาน; ช่วงหลุด quote/ปิด MT5 ไม่สามารถอนุมานจังหวะราคาแตะ Open/SR จาก OHLC ได้ การตอบ HTTP ขาดหายหลัง Telegram รับข้อความแล้ว หรือ crash ก่อนเก็บ `.sent` อาจทำให้ส่งซ้ำหลัง retry โดย Event ID เดิมช่วยระบุซ้ำได้ Disk error อาจเหลือสัญญาณใน memory เท่านั้นจนเขียนสำเร็จ; shutdown ตอนนั้นเสี่ยงสูญหายและจะแจ้งใน log

ไม่ลบ record ที่ส่งแล้วอัตโนมัติ เพราะใช้คืนลูกศรและป้องกันซ้ำ ควรสำรองโฟลเดอร์คิวก่อนจัดเก็บ/ย้ายประวัติเก่าเมื่อ terminal หยุดทำงาน; การลบ event ของแท่งใหญ่ปัจจุบันอาจเปิดโอกาสให้แจ้งซ้ำ

## Build

```sh
sh scripts/compile-macos.sh wick-hunt-telegram-ea
python3 scripts/package.py wick-hunt-telegram-ea
```

การคอมไพล์สร้าง EX5 ทั้งสองตัว ไม่มีการรัน backtest หรือส่งข้อความ Telegram จริง ผล build และข้อที่ยังไม่ยืนยันอยู่ใน [testing.md](testing.md)
