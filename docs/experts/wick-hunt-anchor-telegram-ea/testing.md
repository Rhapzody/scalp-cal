# Verification status — 1.07

วันที่ 2026-10-07 ผู้ใช้ยืนยันว่า 1.06 ส่งข้อความ/รูปจาก MT5 มาถึง Telegram แล้ว และเลือกรูปแบบ “รายละเอียดครบ” จากตัวอย่าง. 1.07 เปลี่ยนเฉพาะข้อความ/ภาพ: HTML bold/code, ภาษาไทยแยกหัวข้อ, ID แสดง 8 ตัว, caption สั้น และ Canvas พื้นเข้มพร้อมตัวอักษรใหญ่และ label ที่วัดความกว้าง. ชื่อ symbol/legacy plaintext escape ก่อนใช้ parse_mode=HTML. Legacy record ไม่ถูก rewrite; schema 1 เดิม

Source/hash review ยืนยัน runtime, validation, Anchor/FVG/quote-session cores, queue/checkpoint schema, ConfigurationKey, presets, indicator และ Pine ไม่เปลี่ยน. SignalRecord จัดรูปแบบใหม่แต่เวลา/ราคา/frozen signal_tip/ID เต็มเดิม. Text-first, retry, receipt และ cancellation conditions คงเดิม. ส่ง % Strong เฉพาะ pattern ที่มี Strong ไม่ใช้ % ไปกรอง FVG

MetaEditor Detector/Sender ผ่าน **0 errors / 0 warnings** ทั้งคู่. ตรวจ compiler/source/ZIP manifest เท่านั้น ไม่มี tests/backtest, ไม่ติดตั้ง EA และไม่ส่ง Telegram จริงเพิ่ม. Inline preview ตรวจสองแบบ/แสงมืด/สว่าง/ความกว้างมือถือแล้ว แต่เป็นกราฟจำลอง ไม่ใช่ผล Canvas บน VPS. ยังไม่ได้ยืนยันฟอนต์/DPI ของ Wine บน VPS หรือการแสดง HTML/caption จากสัญญาณจริงของรุ่น 1.07

อัปเดต EX5 ทั้ง detector และ sender เป็น 1.07 ใช้ Input/Channel/InstanceID เดิมและเก็บคิว/receipt/checkpoint เดิมไว้. ดูข้อความใหม่เป็นหัวข้อหนาและ caption ไม่ซ้ำทั้งข้อความ; กราฟต้องแสดง MAIN TF/CHECK TF กับ ID สั้นเดียวกัน. ค่า signal conditions คงเดิม

## ประวัติ build ก่อนหน้า

# Verification status — 1.06

วันที่ 2026-10-07. ผู้ใช้ส่ง native VPS log ของ 1.05: record-write/flush error=4009 ที่ active.tmp ซ้ำ. 4009 = ERR_NOTINITIALIZED_STRING ตามเอกสาร MQL5; source เดิม StringToCharArray บน optional empty/deinitialized fields สอดคล้องกับอาการ. แก้ writer ให้ NULL/empty เขียน 4-byte length=0 ก่อนแปลง UTF-8; ตรวจ length-prefix byte count และระบุ optional signal fields เป็น empty ก่อนใช้งาน.

Source review ยืนยัน decoder/schema 1 เดิมอ่าน zero length ได้; ไม่กลบ error ไม่เปลี่ยน ConfigurationKey/runtime/validation/pictures/signal conditions/replay/session helpers/rendering/text-first. Sender source เปลี่ยนเฉพาะ property version 1.06; Sender 1.05 ใช้ต่อได้. ค่าของ preset คงเดิม.

MetaEditor Detector/Sender **0 errors / 0 warnings**; source comparison/protected hashes/ZIP integrity/manifest เท่านั้น. ไม่รัน tests/backtest ไม่ติดตั้ง EA และไม่ส่ง Telegram เพิ่ม. Native VPS/MT5 ของผู้ใช้ยังไม่ได้ยืนยันหลังลง 1.06; ผล compile ไม่ใช่ผล end-to-end delivery.

## ประวัติ build ก่อนหน้า

# Verification status — 1.05

วันที่ 2026-10-07. จากรายงาน screenshot: detector แสดง Outbox/checkpoint write failed และลูกศรไม่อัปเดต. ยืนยันจาก source ว่า ProcessSignals false ทำให้ RunDetector return ก่อน RenderEvents. รุ่น 1.05 วาดจาก replay ที่สำเร็จก่อน ProcessSignals และไม่ให้ drawing failure ขวาง outbox. การตรวจราคาหรือ replay ที่ยังไม่สำเร็จยังไม่วาด/publish partial events.

แก้ watermark ให้ commit checkpoint สำเร็จก่อน advance in-memory cursor. เพิ่ม error diagnostics ใน write/open/flush/move ของ record/checkpoint/textack/retry/completion และ active delete; logs มี operation/code/path/data directory และ throttle 30s ต่อ error เดิม. ไม่เปลี่ยน ConfigurationKey, queue schema, signal price rules, generated runtime, anchor/FVG/session cores, frozen links, text-first scheduling หรือค่าของ preset.

MetaEditor detector/sender **0 errors / 0 warnings**; ตรวจ source/protected hashes/ZIP integrity/manifest เท่านั้น. ไม่รัน tests/backtest, ไม่ติดตั้ง EA และไม่ส่งข้อความเพิ่ม. การทดสอบ Telegram โดยผู้ใช้อนุญาตก่อนหน้านี้ส่งจาก Codex สำเร็จ แต่ไม่ได้เป็นหลักฐานของ VPS/MT5 queue delivery.

**ยังไม่ได้ reproduce native I/O บน VPS และยังระบุ root cause ของการเขียนไม่ได้จาก screenshot generic เดิม.** รุ่นนี้แก้การวาดที่ถูกขวางและเพิ่มหลักฐานสำหรับแยก operation/error; ไม่รับรองว่าปัญหาสิทธิ์/file lock/disk ของ VPS ถูกแก้แล้ว.

## ประวัติ build ก่อนหน้า

# Verification status — 1.04

Detector สกัด runtime/validation จาก indicator 1.12 รวม helper quote sessions ตัวเดียวกัน ตรวจ source ว่า price conditions / first anchor / revalidation / frozen signal-tip / Telegram processing / queue/image protocol / checkpoint identity คงเดิม เพิ่มเฉพาะการยอมรับเวลาไม่มี quote session และข้อความสถานะ

MetaEditor detector / sender 0 errors / 0 warnings; ZIP manifest มี helper shared ใหม่และตรวจ hashes. ไม่รัน tests/backtest ไม่ติดตั้ง EA ไม่ส่งข้อความ/รูป และยังไม่ได้ยืนยัน OHLC/session ของ GOLD บน Ava-Demo ใน VPS ของผู้ใช้จริง ตามคำขอเดิม

## ประวัติ build ก่อนหน้า

# Verification status — 1.03

ไม่มีการรัน backtest, เปิด EA ลงกราฟจริง, ส่ง Telegram, หรือเปิดออเดอร์ในขั้นสร้างรุ่นนี้ ตามคำขอก่อนหน้าที่ไม่ต้องเทสเพิ่ม

ตรวจ source ว่า detector runtime และ validation สกัดจาก indicator 1.10 โดยตรงและใช้ Anchor/FVG core เดียวกัน; ตัวส่งไม่มีเงื่อนไขหา signal และ detector ไม่มี WebRequest. ทั้งสองโปรแกรมไม่มีคำสั่ง trade

MetaEditor compile ต้องเป็น `0 errors, 0 warnings` ทั้ง detector และ sender ก่อนสร้าง ZIP. Manifest เก็บ SHA256 ทุกไฟล์ และ package ตรวจ ZIP integrity.

ยังไม่ได้ยืนยัน native Canvas/font/การรับอัลบั้มจริงกับ Telegram หรือวัด performance บน KVM2. ผล compile ไม่ใช่หลักฐาน end-to-end delivery.

เมื่อใช้งาน: ใส่ credential ที่ Sender, allow WebRequest, ดูสถานะ Ready/Waiting, รอสัญญาณใหม่ตามเวลา broker. ข้อความแรกต้องส่งก่อนเริ่มสร้างภาพ อัลบั้มตามมีภาพ main/lower และ ID เดียวกัน; ถ้าหางยืดทำให้สัญญาณถูกลบควรมี CANCELLED ID เดิมตามหลัง. HTTP auth errors จะ pause และเก็บ outbox; network/429/5xx จะ retry ตาม checkpoint.


Source review ของ transport ตั้งแต่รุ่น 1.01: Sender ไม่รอ .photos ก่อน text; เขียน .textack หลัง HTTP200/ok=true เท่านั้น; detector ต้องอ่าน receipt สำเร็จก่อน WAPRender; scheduler เลือก text/cancellation ก่อน albums; retry แยก text/pictures; .textack กันการส่งข้อความซ้ำหลัง restart. ภาพและคิวแยก channel. รุ่น 1.02 เพิ่มตัวกรองหางเดิมใน detector ตาม indicator 1.10; ส่วน transport ไม่เปลี่ยน logic.

ตัวอย่างการแยก chat และ presets m15_m1 / h1_m5 อยู่ใน README และ ZIP. ยังไม่ได้ยืนยัน delivery/restart/retry กับ Telegram จริงหรือวัดเวลาบน KVM2.

รุ่น 1.02: Source review ตรวจ threshold 10%, Buy/Sell wick/body แยกจาก anchor Strong, N≥2 และ 0 bypass, Doji with swept-side wick passes; generated runtime/validation ตรง indicator 1.10 และ ConfigurationKey รวม threshold ใหม่. MetaEditor detector/sender 0 errors / 0 warnings; package/source checks เท่านั้น ไม่ติดตั้ง EA หรือส่ง Telegram จริง

1.03: generated runtime/validation จาก indicator 1.11; graph link signal_tip/time และ SignalRecord.tip = e.signal_tip; Canvas line endpoint ใช้ event time ภายใน TF ไม่ใช้ main Open. ProcessSignals / cancellation / sender transport / queue schema เดิมคงเดิม. MetaEditor detector/sender 0 errors / 0 warnings; source/package review เท่านั้น ไม่ติดตั้ง EA/ส่งจริง
