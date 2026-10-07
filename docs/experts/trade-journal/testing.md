# Trade Journal 1.20 — การตรวจสอบ

## Automated tests

รัน `sh scripts/test.sh trade-journal`

**190 checks ผ่าน** โดยนำ production `JournalCore.mqh`, `TradeJournal.mq5` และ `ExportJournalReport.mq5` ทั้งตัวมาทดสอบใน C++ harness เปลี่ยนเฉพาะ input/property declarations, array syntax และจำลอง MT5 APIs ไม่มีการคัดลอก algorithm ไปเขียนใหม่ ไม่มีการเปิด MT5 หรือส่ง trade ระหว่าง automated tests

ตรวจครอบคลุม:

- CSV ที่มี comma, quotes, ภาษาไทย, newline และข้อความคล้ายสูตร; ตัวเลขติดลบไม่ถูกเปลี่ยนเป็นข้อความสูตร
- 64-bit ticket ไม่ผ่าน floating point, uint64 overflow และรูปแบบ ID ผิด
- การแยก account/server รวมชื่อที่ต้อง escape; account switch และการ reinitialize หลังเปลี่ยนกราฟ/Inputs โดยไม่สมมติว่า globals ถูก reset
- Header/schema, column counts, torn rows, บรรทัดท้ายที่ดูครบแต่ไม่มี CRLF
- Exclusive writer lock และการเปิดใหม่หลังปิด handles
- History scan แบบแบ่ง 200 tickets ต่อรอบ; snapshot ticket list ก่อน `HistoryDealSelect` เปลี่ยน selected list ของ terminal; live deal ที่เข้าระหว่างสอง batches
- Manual + Calculator magic + Instant magic, partial closes ที่มี position ID เดียวกัน, Hedging สอง positions, INOUT และ OUT_BY ตาม broker
- ผลสุทธิรวม profit/commission/swap/fee, ค่าธรรมเนียมที่ broker บันทึกเป็น deal แยกโดยไม่มี position ID
- การรอ history ที่มาช้า, round-robin retries, broker correction revisions, DELETE tombstone แม้ไม่เคยเห็น deal เดิม และรายการกลับมาหลังลบ
- เริ่มใหม่ไม่เพิ่ม deal/revision ซ้ำ และโหลด record ที่เขียนครบแต่ flush เคยแจ้งล้มเหลวได้
- รับ SL หลายค่าก่อนรอบ timer โดยเก็บค่าจาก transaction จริง ไม่ใช้ snapshot ล่าสุดแทนทุกเหตุการณ์
- Snapshots แรก/เปลี่ยน/ไม่เปิดอีกต่อไปสำหรับ positions และ pending orders; ค่าสุดท้ายไม่ถูกอ้างเป็นราคา fill
- ไม่ใช้ field ที่ไม่ทราบใน transaction เป็น position ID หรือ magic
- ไม่ถือ request acceptance เป็น execution, ไม่สร้าง snapshot ปิดไม้ขณะ disconnected
- File write, short write, flush failure และ queue overflow หยุด recorder; ไม่ advance index ก่อนยืนยันการเขียน
- ปฏิเสธ Strategy Tester เพื่อไม่ให้ข้อมูลจำลองปนกับ journal ของ terminal
- ตรวจ source ไม่มี API ส่ง/ตรวจออเดอร์, WebRequest, DLL launcher หรือ screenshot

จำนวน checks รวม assertions ของสถานการณ์และการ parse CSV ที่ผลิตจริงจาก harness ไม่ใช่จำนวนสถานการณ์อิสระ

## Native compiler

ใช้ `sh scripts/compile-macos.sh trade-journal` กับ MetaEditor/Wine สร้าง `TradeJournal.ex5` พร้อม compiler log ใน `dist/experts/trade-journal/` ตรวจ `compile.txt` สำหรับผลของ build ที่แพ็ก

## Native terminal checklist — ยังไม่ได้ดำเนินการ

ชุดจำลองไม่ได้ยืนยันการทำงานของ FileOpen/UTF-8/file sharing, การรับ event จริง, timer, Comment/Alert หรือ broker บน terminal จริง และยังไม่ได้แนบ EA หรือเปิดออเดอร์ในบัญชีผู้ใช้

ก่อนใช้งานกับข้อมูลที่ต้องการเก็บจริง ควรตรวจใน Demo:

1. แนบ Journal บนกราฟใหม่คู่กับ Calculator; ตรวจ CSV สามไฟล์และสถานะ RECORDING ตรวจว่า Calculator ยังทำงานบนกราฟเดิม
2. กดเข้า Buy/Sell ผ่าน Calculator และหน้าจอ MT5; ตรวจ ticket, position ID, magic และ reason ให้ตรงกับ History
3. ขยับ SL/TP หลายครั้ง รวมถอด SL เป็น 0; ตรวจ transaction rows และ snapshots
4. เพิ่มไม้/ปิดบางส่วน/ปิดทั้งหมด; ทดสอบ Hedging และ Netting แยกบัญชี ตรวจ INOUT/OUT_BY ตาม broker ที่รองรับ
5. วาง แก้ และยกเลิก pending; ตรวจ ORDER events และการ fill ที่สัมพันธ์กับ deal
6. ปิดด้วย SL/TP ตรวจ reason และตรวจ profit/commission/swap/fee กับ statement; เปิด CSV แบบ UTF-8 พร้อม ticket columns เป็น Text
7. เปลี่ยน TF/Inputs, ถอดใส่ EA และรีสตาร์ต terminal; deals เดิมต้องไม่ซ้ำ มี START/STOP และ BASELINE ใหม่
8. เปิด Journal ตัวที่สองใน terminal เดียวกัน ต้องถูกปฏิเสธโดยไม่กระทบตัวแรก
9. ขาดการเชื่อมต่อแล้วเชื่อมใหม่; ตรวจ sessions และ backfill; อย่าคาดหวังประวัติ SL/TP ระหว่าง offline
10. สลับบัญชี/server ตรวจว่าใช้คนละโฟลเดอร์ ไม่ปนข้อมูลเดิม
11. ตรวจบนเครื่องที่ใช้งานจริงว่ากดผ่านมือถือแล้ว Journal ซึ่งเปิดอยู่รับเหตุการณ์ได้ และสิทธิ์ Algo Trading ของ Calculator ไม่ถูกเปลี่ยน

ไม่ทำรายการทดสอบส่งออเดอร์จริงในขั้นพัฒนานี้ ชุด ZIP ไม่ถือว่า checklist native terminal ผ่านแล้ว

## HTML exporter และ browser

เพิ่มใน native mock tests: อ่าน snapshot ขณะ EA เปิด writer อยู่, ไม่แก้ CSV, parse TF/deduplicate/ปฏิเสธ TF ผิด, position time grouping, CopyRates context, แท่งปัจจุบันไม่ปิด/after bars ยังไม่มี, history บางส่วน, เพดานแท่งไม่ตัดข้อมูลเงียบ ๆ, symbol/history ไม่พร้อม, JSON escaping ของ `</script>`, การ publish ล้มเหลวรักษา HTML เดิม

**21 JavaScript model checks ผ่าน** ด้วย Node.js: CSV escaping, ID ยาวเกินความแม่น double, latest revision/DELETE, partial closes, netting INOUT, ค่าธรรมเนียมที่ผูก/ไม่ผูก position, event linkage ที่ไม่สมมติ ticket เท่ากับ ID, เส้นระดับตามเวลาที่สังเกต, timezone และ OHLC validity

ตรวจ template ที่ฝังใน MQL ว่าตรงกับ HTML/JS sources ทุกครั้งก่อนแพ็ก ไม่มี remote scripts/CDN/third-party runtime

รุ่น 1.10 เคยตรวจ browser ด้วย **ข้อมูลสาธิต** แล้ว: หน้ารายงานและกราฟ, เลือก position, M1/M5/M15, ปุ่มซูม, ดาวน์โหลด HTML แยก position และเปิดไฟล์ที่ดาวน์โหลดกลับมาผ่าน local preview ตรวจ embedded data ว่าเหลือ executions และสาม TF ของ position ที่เลือกจริง ตัวอย่างอยู่ `journal-demo.html`

ยังไม่ได้รัน ExportJournalReport ใน terminal จริงเพื่อดึง history ของ broker/อ่าน native CSV โปรดตรวจบน Demo เพิ่ม:

1. ติดตั้งทั้ง Experts/TradeJournal และ Scripts/TradeJournal, บันทึกไม้แล้วรัน ExportJournalReport
2. เปิด journal.html ตรงจาก filesystem ใน browser ที่ใช้จริงโดยปิดอินเทอร์เน็ต ตรวจไม่มี external asset requests
3. เทียบ OHLC และเวลา broker ของ M1/M5/M15 กับ MT5, เทียบจุด partial fills และ SL/TP edits กับ CSV
4. ส่งออกก่อนมีแท่งหลังออกครบ แล้วส่งออกใหม่ภายหลัง ตรวจสถานะ afterAvailable และแท่งปัจจุบัน
5. ลด history/เพดานแท่ง ตรวจคำอธิบายข้อมูลไม่ครบ; ทดสอบ Netting reversal และหลาย positions บน symbol เดียวกัน
6. ตรวจ Journal ยังบันทึกต่อระหว่าง export และ CSV เดิมไม่ถูกแทนที่

การดาวน์โหลดผ่าน browser preview ทดสอบจาก HTML สาธิต ไม่ใช่ไฟล์ที่สร้างโดย MQL บน broker จริง

## บันทึกส่วนตัวรุ่น 1.20

**44 checks ของ NotesModel และ 32 checks ของ Notebook DOM units ผ่าน** รวมกับเดิมเป็น **287 checks**:

- คงข้อความไทย newline และข้อความคล้าย HTML เป็นข้อความข้อมูล, ID ยาวและการแยกบัญชี/server/demo/position
- โหลดกลับหลังสร้าง store ใหม่, โน้ตฝังใน HTML และ JSON round-trip
- เพิ่ม/ลบ/ติ๊กเช็กลิสต์ สลับ position แล้วกลับมา และสถานะรีวิว/ค้นหา/กรองหน้า list
- นำเข้ามีขั้นตรวจจำนวนก่อนใช้, เก็บโน้ตเดิมเป็นค่าเริ่มต้น, แทนที่เมื่อผู้ใช้เลือก, ข้ามอีกบัญชี, ปฏิเสธ schema/fields/IDs ผิดและรายการซ้ำก่อนแก้ข้อมูล
- Storage เต็ม/ไม่อนุญาต/เสียหายไม่อ้างว่าเซฟแล้ว, draft ยังส่งออกได้, เตือนก่อนปิดเมื่อมี draft
- อีกหน้าต่างแก้โน้ตหลังโหลด: ไม่เขียนทับค่าที่เปลี่ยนไป เก็บ draft อีกฉบับให้สำรอง
- เลือกฉบับที่มีเวลาแก้ไขล่าสุดระหว่าง embedded snapshot กับ browser; backup จำกัดตาม positions ที่ส่งออก

Notebook DOM unit harness รัน production ReportNotebook.js กับ mock elements ตรวจชื่อ id/fields กับ Report.html จริง แต่ไม่ได้จำลอง rendering, native download, file picker, file:// storage หรือ canvas ของ browser

**ยังไม่ได้ตรวจ browser จริงของ UI รุ่น 1.20**: เครื่องมือ browser เริ่ม kernel ไม่สำเร็จ (`sandbox-exec: unbound variable: TIOCSTI`) จึงไม่ถือว่าการตรวจ UI/ดาวน์โหลดในรุ่น 1.10 ครอบคลุมฟีเจอร์ใหม่ทั้งหมด ให้ลองด้วย `journal-demo.html` ก่อน:

1. เปิดจาก filesystem ใน browser ที่ใช้จริง เขียนเหตุผล/อารมณ์/เช็กลิสต์ สลับไม้และกลับมา แล้ว Reload ตรวจข้อความอยู่ครบ
2. กรองสถานะและค้นหา Setup/Tags จากหน้า list ตรวจแต่ละไม้ไม่ปนกัน
3. ดาวน์โหลด JSON และ HTML ทั้งหมด/แยกไม้ ตรวจไฟล์ใน Downloads เปิด HTML ที่ดาวน์โหลดด้วย browser profile ใหม่ ตรวจโน้ตและสาม TF
4. ส่งออกรายงาน MT5 ใหม่ นำเข้า JSON ตรวจจำนวนรายการและค่าเริ่มต้นไม่ทับโน้ตเดิม แล้วทดสอบแทนที่ด้วยข้อมูลสาธิต
5. เปิดสองหน้าต่างแก้ไม้เดียวกัน ตรวจข้อความเตือนและสำรอง draft ได้; ทดสอบ private mode/storage ที่ไม่อนุญาต

ไม่มีการแนบ EA, เปลี่ยน settings หรือส่งออเดอร์ในบัญชีผู้ใช้ระหว่างพัฒนาฟีเจอร์นี้
