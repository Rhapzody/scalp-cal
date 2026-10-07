# Verification

## Completed

Build: installed MetaEditor under MetaTrader 5 Wine on macOS, **0 errors / 0 warnings**, X64 Regular output. The original compiler output is included as `compile.log`; a UTF-8 copy is `compile.txt` in the distribution directory.

Host tests: `sh scripts/test.sh scalp-calculator` compiles the actual production `.mqh` modules as C++17 with minimal MQL adapters, using clang++ with `-Wall -Wextra -Werror`.

- **80,041 core assertions**, including 20,000 seeded randomized combinations with four invariants each: total strategy risk stays within budget, step alignment, nonnegative volume, largest admissible floor.
- **59 broker assertions** against deterministic fake MT5 APIs: Ask/Bid selection, all pending types, spread compensation and snapshot request values, currency/contract conversion, min/max/step/volume limits, whole-batch and remaining margin, stale quotes, spread boundary, stop/freeze validation, order support, fill policy, permissions and netting exposure.
- Fake profit/margin functions only provide test-controlled broker responses. Tests exercise production calculation and validation; they do not prove that an actual broker will accept or fill a request.

## Not yet performed

Native MT5 panel visual/interaction verification, actual demo fills, broker-specific rejection/partial-fill tests, and acceptance tests on the named prop accounts. No user trade has been submitted during development. Compilation and mock API tests are not substitutes for these runtime checks.

## Demo acceptance checklist

Use a demo chart with the correct symbol specification. Start with Algo Trading OFF for items 1–10. Record the terminal build, symbol point/tick/volume specifications, account currency, hedging/netting mode, EA Inputs, and screenshots/results.

| # | Action | Expected result |
|---|---|---|
| 1 | Attach with Initial Balance 0 | Calculator appears; Execute blocked with explanation |
| 2 | Set Initial Balance to real starting capital | Risk target uses input capital; Current Balance mode uses balance instead |
| 3 | BUY MARKET; then SELL MARKET | Exactly SL/TP strategy lines; Entry shows Ask/Bid respectively |
| 4 | Drag SL outward by 2.00, then inward | TP moves outward by 2.00, then remains unchanged |
| 5 | Drag TP both ways | SL unchanged; RR and Lot refresh |
| 6 | Switch Pending and move Entry across market | Correct Limit/Stop detection with Entry line present |
| 7 | Switch M1 → M5 → M15 → M1 | All setup prices, side, mode, Risk, Orders and latch retained |
| 8 | Observe candle rollover and quiet tick periods | Countdown continues via timer and resets when a new bar arrives; never goes negative |
| 9 | Hide/Show and resize chart | Panel redraws correctly; no stale buttons or changed setup |
| 10 | Delete a setup line; move SL wrong side; choose tiny risk | Execute blocked with cause; below-minimum alert on click |
| 11 | Enable Algo Trading on demo and Execute one BUY | Request has expected Lot, SL/TP, magic; display/log matches Trade and History |
| 12 | Execute SELL and compare snapshot Bid/Ask | Broker SL and TP both equal strategy level + spread, tick-normalized |
| 13 | Place SELL pending; observe a later spread change/fill | Protection remains the Execute snapshot; no later EA SL/TP modification |
| 14 | Request 2/3 orders | Equal lots, total strategy risk <= target under snapshot conditions |
| 15 | Double-click Execute; change timeframe after batch | No second batch until explicit REARM |
| 16 | Simulate rejection after first successful order | Accurate partial-batch status, remaining sends stopped, first trade left open |
| 17 | Simulate IOC partial fill or accepted/unconfirmed response | Remaining batch stopped; no automatic retry; user directed to Trade/History |
| 18 | Disconnect, disable trading, widen spread or use stale prices | New execution blocked; setup retained |
| 19 | Enable Clear After Execute; run successful batch | Only setup objects cleared; orders untouched; unsuccessful batch retains setup |
| 20 | Test Netting with existing exposure | New batch blocked; empty symbol permits a batch whose fills may merge |
| 21 | Compare actual fills to expected loss and costs | Slippage/fees and compensated SELL differences documented; no assumption of exact risk cap |

Order submission tests require a market session with valid ticks. Broker-side partial fills, gaps, and server failures may require a controlled test server; do not label those cases passed merely because normal market execution succeeds.

## Rebuild

Open `MQL5/Experts/ScalpCalculator/ScalpCalculator.mq5` in MetaEditor and compile with F7. All five included `.mqh` files must remain beside it. A Windows command-line example is:

```bat
metaeditor64.exe /compile:"C:\path\ScalpCalculator\ScalpCalculator.mq5" /log:"C:\path\compile.log"
```

Inspect the compiler log, rather than inferring success from process exit alone. The macOS build script requires the locally installed MetaTrader Wine bundle and does not start the trading terminal.

## UI 1.03

`python3 tests/scalp-calculator/ui_layout_tests.py` ดึง MeasureLayout, Label, Button, Row และ Render จาก EA จริงมารันผ่าน object adapter โดยตรวจขอบเขตและการทับกันของวัตถุ 1,611 scenarios: กราฟกว้าง 240/314/480/900, สูง 240/362/500/720/1080, Scale 0.5/1/2, DPI 96/144/192, เปิด/ซ่อนส่วน Instant, ทุกหน้ารายละเอียด, ย่อ/ขยาย และ font measurement fallback ใช้ font metrics จำลอง ยังไม่ใช่ผล render จาก MT5 จริง

ตรวจบน MT5 เพิ่มเติม: ขยาย/ย่อ chart แล้วดูว่า DETAILS เปลี่ยนจำนวนหน้า, กด < / > ถึงหน้าสุดท้ายและกลับหน้าแรก, วางเมาส์เหนือข้อความ ... เพื่ออ่านเต็ม, กด HIDE/SHOW และเปลี่ยน timeframe โดยไม่มีวัตถุเก่าค้าง ข้อความ Set Initial Balance in Inputs เมื่อทุนเป็น 0 เป็นสถานะที่ถูกต้องของ calculator

## Integrated Instant Engulf 1.02

`python3 tests/scalp-calculator/run_engulf_panel_tests.py` รัน Engulf suite เดิม 4,116 checks กับ ScalpBroker/EngulfCore ที่อยู่ใน Calculator และเพิ่ม 152 checks ของ ScalpEngulf production executor ผ่าน mock candles, file locks, Global Variables, OrderCheck และ OrderSend; ครอบคลุม PA ผิดฝั่ง/ปิดเท่าเนื้อเทียน/ปิดพ้นเนื้อแต่ยังอยู่ในหาง, preview ไม่ส่ง, BUY/SELL ส่ง 1 ไม้, Risk input แยก, buffer/spread, EA OFF, busy, ซ่อนส่วน Instant, history ไม่พร้อม, permission, netting exposure, lock/storage failure, PA เปลี่ยนระหว่าง preflight, rejection/timeout/partial, กันซ้ำข้าม reattach และ debounce

ไม่มีการเรียก terminal หรือส่ง trade จริงระหว่าง tests การแปลงเพื่อ C++ มีเฉพาะ dynamic MqlRates array เป็น fixed array สองสมาชิกใน adapter และ compiler warning ของ unsigned hash literal

Native demo checklist เพิ่ม: ตรวจปุ่ม Instant กับปุ่มวางแผนเดิม, shared EA OFF, เปลี่ยน Risk preset/Orders/manual Pending แล้ว Instant ยังใช้ Risk input และ Market 1 ไม้, SELL compensation ยังเปิดแม้ปิดของ manual, guard หลัง restart/ข้าม chart รวม standalone ที่ magic ตรงกัน และตรวจผลจริงใน Trade/History

## Rearm states 1.03

17 assertions ตรวจข้อความและสี Execute/REARM ในสถานะมี setup/ไม่มี setup และ latched/unlatched รวมส่งกำลังทำงาน โดยเรียก ApplyRearmStatus และ Render จาก source จริง กรณี latched + ไม่มี setup จำลองสถานะหลัง Clear/automatic Clear ต้องยังเป็น LOCKED - REARM และ REARM REQUIRED; native MT5 ยังต้องตรวจสีและการกดจริง

## Final-five-second selection 1.04

The integrated executor suite now has 152 checks beyond the 4,116 core/broker suite. Production EngulfTiming.mqh is exercised with mocked server time and monotonic ticks. Cases include 6/5/4/3/2/1 seconds, no fallback from failed LIVE to old CLOSED PA, selected-pair SL extremes for BUY/SELL, expired bar with no next-bar tick, closed-to-live transition during OrderCheck, expiry during persistent-marker flush (restoring the prior marker), live PA/SL changing during preflight, live-to-closed duplicate protection, timer-only progression, current TF selection, leap February and December rollover.

Native checklist: observe the main countdown and LIVE [0/1] / CLOSED [1/2] label together, click outside/inside the last five seconds on demo, record selected pair/SL/TP/request result, and verify the same signal cannot be resubmitted after closing. No live orders or native terminal interactions have been tested by this suite.

Clock design uses last server quote time from [TimeCurrent](https://www.mql5.com/en/docs/dateandtime/timecurrent) plus elapsed GetTickCount64 time, shared by selection and the Panel countdown. Broker quote-age/permission checks remain in effect.

## Manual SL buffer (1.05)

Automated checks cover BUY/SELL, zero and positive buffers, MT5 point units, outward tick rounding, invalid buffers, Market/Pending, repeat calculation without accumulation, unchanged entry/TP, lot sizing against buffered strategy SL, and broker requests with SELL spread added once. 96 integration checks execute the production ManualPlan function and shared broker code.

Run `sh scripts/test.sh scalp-calculator`. Latest run: 80,051 core checks, 59 broker checks, 96 manual buffer integration checks, 4,268 combined Engulf checks; 1,670 UI layout scenarios and 17 rearm state checks. Native MT5 UI and real order execution are not covered by these mocks.

Manual terminal check: set buffer 15, compare Manual SL line / Strategy SL / Broker SL, drag the SL, switch Market/Pending, and confirm TP stays at its line while Lot and R:R update. Verify buffer 0 preserves previous behavior and Instant Engulf still uses its independent buffer.
