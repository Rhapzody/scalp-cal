# WickHuntAnchor 1.12 — build status

แก้ ReplayLowerClosed ที่เคยบังคับ first small.time == main Open และทุก small.time == previous close ให้ยอมรับ gap เฉพาะที่ไม่มี quote session ของ symbol ทับช่วงนั้น ผ่าน WickHuntQuoteSessions.mqh. รองรับ first bar หลังเปิดตลาด, intramain break, weekend, midnight/overnight sessions; quote schedule ไม่พร้อมยังใช้ guard เดิม และไม่ยอมผ่าน open-session data gaps

ตรวจ source ว่า AddEvent / RefreshEventAnchor / ReplayClosed / price cores / 28 Inputs / frozen links คงเดิม และ EA runtime/validation เป็น source ที่สกัดตรงจาก 1.12. ตัวส่ง Telegram, queue schema, image snapshots และ watermark identity ไม่เปลี่ยน

MetaEditor indicator / detector / sender **0 errors / 0 warnings**; ตรวจ source และ ZIP/hash เท่านั้น ไม่รัน tests/backtest หรือยืนยันจาก OHLC GOLD ของ VPS จริงตามคำขอเดิม ไม่อ้างว่าแท่ง 4/10 ที่แนบผ่านแน่นอนก่อนตรวจ native feed/session metadata ของ terminal นั้น

## ประวัติ build ก่อนหน้า

# WickHuntAnchor 1.11 — build status

1.11 เพิ่ม immutable `signal_tip` ลง event ณ AddEvent เท่านั้น; `tip` ยังเปลี่ยนจาก RefreshEventAnchor เหมือนเดิม เส้นใช้ anchor_time / signal_tip → time / signal_tip. Buffers และ Inputs คงลำดับ/จำนวนเดิม Tooltip แยก signal/latest tip

Source review เทียบ RefreshEventAnchor และ shared Core กับ 1.10 ว่าตรงเดิม การสร้าง/ทบทวน/ยกเลิกสัญญาณไม่เปลี่ยน เพิ่มเฉพาะ snapshot และการวาด. Generated EA runtime/validation ตรง source 1.11

MetaEditor compile 0 errors / 0 warnings; ตรวจ source/package hashes เท่านั้น ไม่รัน tests/backtest หรือยืนยันหน้ากราฟ/Telegram จริง

## ประวัติ build ก่อนหน้า

# WickHuntAnchor 1.10 — build status

รุ่น 1.10 เพิ่ม `InpMinSweptWickBodyPercent=10` ท้าย 27 Inputs เดิม และ gate เดียวใน AddEvent ซึ่งทุก observation mode ใช้ร่วมกัน วัดหางด้านถูกกวาดของแท่งก่อนหน้า/เนื้อของตัวเอง เมื่อ N=1 เท่านั้น; N≥2 หรือ threshold=0 bypass. Doji ผ่านเมื่อมีหางด้านถูกกวาด ตามคำตอบผู้ใช้ ไม่หารด้วยศูนย์

ตรวจ source ว่า Buy ใช้หางล่าง Sell ใช้หางบน เท่ากับ threshold ผ่าน ใช้เฉพาะแท่งปิดก่อน hunt และไม่เปลี่ยน anchor/FVG/Strong classifier. EA runtime/validation สกัดจาก indicator 1.10 โดยตรง และ ConfigurationKey รวม Input ใหม่

คอมไพล์ MetaEditor **0 errors / 0 warnings** และตรวจ source / SHA256 / ZIP integrity เท่านั้น ไม่รัน logic tests/backtest หรือยืนยันสัญญาณบนกราฟจริง ตามคำขอเดิม ยังไม่ตรวจแผง Inputs ใน MT5 จริง

## ประวัติ build ก่อนหน้า

# WickHuntAnchor 1.09 — build status

รุ่น 1.09 เปลี่ยนเฉพาะ display comments ของ Inputs 27 ตัวให้เป็น `ชื่อตัวแปร | ความหมายไทย` ทุก label ไม่เกิน 63 ตัวอักษรตาม MQL5 input display comment บันทึก MQ5 เป็น UTF-8 BOM เพื่อระบุ Unicode ชื่อตัวแปร/type/ลำดับ/defaults และ logic ไม่เปลี่ยน ตรวจ source หลังตัด comments/version/trailing spaces ว่าตรง v1.08

รุ่น 1.09 คอมไพล์ด้วย MetaEditor **0 errors / 0 warnings** ตรวจ hashes ของ MT5 อื่น/core/FVGCore 97 ไฟล์ว่าไม่เปลี่ยน ไม่รัน logic tests/backtest ตามคำขอเดิม ยังไม่ตรวจหน้าต่าง Inputs ใน MT5 จริง

รุ่น 1.08 เปลี่ยนค่าเริ่มต้น InpSearchBars=36 และ preset ทุกตัวเป็น 36 ใช้ช่วงค้นเดิมของ core: anchor ระยะ 1–36 ผ่าน, 37+ ไม่ผ่าน, 0 ปิดจำกัด ใช้ทั้ง Buy/Sell และทุก Rule รวม RefreshEventAnchor โดยไม่เพิ่ม/ย้าย Inputs ไม่แก้ Core/FVG/% Strong/Pine/SR/EA

รุ่น 1.08 คอมไพล์ด้วย MetaEditor **0 errors / 0 warnings** ตรวจ hashes ของ MT5 อื่น/core/FVGCore 97 ไฟล์ว่าไม่เปลี่ยน ไม่รัน logic tests/backtest ตามคำขอเดิม ยังไม่ตรวจบนกราฟจริง

รุ่น 1.07 เพิ่ม InpRequireSellAnchorRed=true ต่อท้าย Inputs ส่ง RequireAnchorColor ของ Sell เข้า core และ RefreshEventAnchor เดิมร่วมกับทุก Rule Sell ต้อง Close<Open หาก first collision เป็นเขียวหรือ Doji ไม่ผ่านและไม่ข้ามแท่ง เมื่อปลายหางเปลี่ยนไปผิดสีจะยกเลิกลูกศร/เส้น/buffers แบบ Buy % Strong ยังแยกจาก FVG Core/FVG/Pine/SR/EA ไม่เปลี่ยน

รุ่น 1.07 คอมไพล์ด้วย MetaEditor **0 errors / 0 warnings** ตรวจ hashes ของ MT5 อื่น/core/FVGCore 97 ไฟล์ว่าไม่เปลี่ยน เพิ่ม preset OR + Buy เขียว/Sell แดง (Strong 20%, ลูกศร 1/60 points) ไม่รัน logic tests/backtest ตามคำขอเดิม ยังไม่ตรวจบนกราฟจริง

รุ่น 1.06 เพิ่มการทบทวน first anchor ของฝั่งที่เปิดกรองสี เมื่อปลายหางเปลี่ยน: อัปเดต tip/metadata ถ้ายังผ่าน anchor เดิม; ลบลูกศร/เส้น/buffers และ reset sent หากไม่ผ่านหรือเปลี่ยน anchor ต้องยืนยัน reclaim ใหม่ก่อนสร้าง event ใหม่ Lower-close replay ทำตามลำดับ M5; tick ทบทวนปัจจุบันและแท่งก่อนหน้าเมื่อ rollover; main-close ใช้ปลายหางสุดท้ายเดิม Core/FVG และตัวกรอง % Strong ไม่เปลี่ยน

รุ่น 1.06 คอมไพล์ด้วย MetaEditor **0 errors / 0 warnings** ตรวจ hashes ของ MT5 อื่น/core/FVGCore 97 ไฟล์ว่าไม่เปลี่ยน ไม่รัน logic tests/backtest ตามคำขอเดิม ยังไม่ยืนยันเคสในภาพด้วย OHLC/Tooltip จริง Pine/SR/EA ไม่เปลี่ยน

รุ่น 1.05 เพิ่ม InpRequireBuyAnchorGreen=true ท้าย Inputs โดยส่ง flag กรองสีไปยัง core เดิมเฉพาะ Buy ตรวจแท่ง first collision จริง Close>Open ก่อนรับ FVG/Strong ร่วมกับทุก Rule; Sell ยังใช้ InpRequireAnchorColor เดิม % Strong และการยืนยัน FVG เดิมไม่เปลี่ยน

รุ่น 1.05 คอมไพล์ด้วย MetaEditor **0 errors / 0 warnings** ตรวจ hashes ของ MT5 อื่น/core/FVGCore 97 ไฟล์ว่าไม่เปลี่ยน เพิ่ม preset OR + Buy anchor เขียว (Strong 20%, ลูกศร 1/60 points) ไม่รัน logic tests/backtest ตามคำขอเดิม ยังไม่ตรวจบนกราฟจริง Pine/SR/EA ไม่เปลี่ยน

รุ่น 1.04 เพิ่ม anchor ที่แท่งกลางของ FVG โดยแท่งที่ 3 ต้องอยู่ใน prefix ของแท่งปิดก่อน hunt (`third_index<count`) รักษา anchor แท่งที่ 3 เดิม, first collision, rule IDs/Inputs/buffers และ % Strong ที่แยกจาก FVG เดิม โหมด Lower close/history, tick และ main-close ใช้ core เดียวกัน Pine/SR/EA ไม่เปลี่ยน

รุ่น 1.04 คอมไพล์ด้วย MetaEditor **0 errors / 0 warnings** ตรวจ hashes ของ MT5 อื่น/FVGCore 96 ไฟล์ว่าไม่เปลี่ยน พร้อม preset FVG only ตามค่าภาพผู้ใช้ ไม่รัน logic tests/backtest ตามคำขอเดิม ยังไม่ตรวจเคสในภาพบน MT5 ด้วย OHLC จริง

รุ่น 1.03 เพิ่ม WHA_FVG_ONLY=2 และ WHA_STRONG_ONLY=3 โดยคง OR=0/AND=1 และลำดับ Inputs/buffers เดิม เกณฑ์หางหัวใช้ตัดสิน Strong เท่านั้น ไม่กรอง FVG ใน OR/FVG only ค่าเริ่มต้น MT5 เปลี่ยนเป็น 30% (ยังเปรียบเทียบ < อย่างเคร่งครัด) สถานะบนกราฟแสดง Rule ที่เลือก Pine และ WickHuntSRFlow/EA ไม่เปลี่ยน

รุ่น 1.03 คอมไพล์ด้วย MetaEditor **0 errors / 0 warnings** ไม่รัน logic tests/backtest ตามคำขอเดิม ตรวจ hashes ของ MT5 อื่น/FVGCore 96 ไฟล์ว่าไม่เปลี่ยน ยังไม่ได้ยืนยันการแสดงผลหรือ rules ใหม่บนกราฟ MT5 จริง

รุ่น 1.02 เปลี่ยนเฉพาะการแสดงผล: ความหนาลูกศรเริ่มต้น 1 ระยะห่าง 200 points และ OBJPROP_BACK=true เพื่อให้ panel ด้านหน้าอยู่เหนือ markers เงื่อนไขตรวจหาและ buffers ไม่เปลี่ยน

รุ่น 1.01 เพิ่มโหมด TF ย่อยปิดพร้อมย้อนหลัง ค่าเริ่มต้น H1/M5: สะสม H/L ของ H1 จาก M5 ที่ปิดไปแล้ว, Close M5 ยืนยันกลับถึง Open H1, anchor จาก H1 ก่อนหน้า, หนึ่ง event ต่อฝั่งต่อ H1 ไม่มี MACD/SR breakout หรือ hold/retest โหมด tick และ main-close ของ v1.00 ยังเลือกได้

ไม่รัน tests/backtest ตามคำขอเดิม รุ่น 1.02 คอมไพล์ด้วย MetaEditor **0 errors / 0 warnings**; ตรวจ hashes ของ MT5 core/indicator/EA อื่น 97 ไฟล์ว่าไม่เปลี่ยน ยังไม่ตรวจลูกศรหรือการซ้อน panel บน MT5 จริง

สิ่งที่ยังไม่ทดสอบของโหมดใหม่: ตัวอย่าง hunt/reclaim ภายใน H1, First anchor ณ M5 ปิด, สะสมปลายหางโดยไม่มอง H/L อนาคต, M5 สุดท้ายตรงจบ H1, ข้อมูลย่อยที่เริ่มกลางแท่ง/มีช่องว่าง, หนึ่ง event ต่อฝั่ง, history reload/popup และความเร็ว replay

## บันทึก build v1.00

สร้างใหม่โดยไม่รัน logic tests/backtest ตามคำขอเดิม ยังไม่ได้ยืนยันลูกศรบน MT5 จริงหรือผลกำไร

สถานะคอมไพล์: MetaEditor **0 errors / 0 warnings** สร้าง EX5 และ ZIP 1.00 พร้อม source/core และสำเนา FVGCore จาก flow เดิม ไม่มี dependency กับ MACD/Swing/Breakout/Pullback หรือ TF ย่อย

ตรวจไฟล์เมื่อ build เสร็จ: FVGCore ตรงกับต้นฉบับ, ZIP hashes ตรงไฟล์ที่จัดแพ็กเกจ, และ source/binaries/ZIP ของ WickHuntSRFlow และ WickHuntTelegramEA เดิมไม่เปลี่ยน การตรวจไฟล์และ compile ไม่ใช่ผลตรวจ logic หรือการวาดบนกราฟจริง

สิ่งที่ยังไม่ได้ทดสอบ: hunt N หางและขอบ points, reclaim เท่ากับ Open, first collision ที่ผ่าน/ไม่ผ่าน/ข้อมูลผิด, หาง 10% พอดีและสี/body ที่ไม่บังคับ, FVG ทั้งสองทิศและ OR, ส่งครั้งเดียวต่อฝั่งต่อแท่ง, freeze ปลายหางที่เคยให้ event, attach/reinit/disconnect, โหมด Closed และการวาดตาม TF กราฟ
