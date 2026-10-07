#!/usr/bin/env python3
"""Replay current EngulfImbalanceFlow 1.08 on one year of XAUUSD M1 bid/ask bars."""
from __future__ import annotations

import csv
import datetime as dt
import gzip
import hashlib
import json
import math
import re
import shutil
import subprocess
import tempfile
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SOURCE = ROOT / "MQL5/Indicators/EngulfImbalanceFlow"
DATA = HERE / "xauusd_m1_bid_ask.csv.gz"
BID_SOURCE = Path("/private/tmp/xau-m1/xauusd-m1-bid-2025-09-01-2026-09-27.csv")
ASK_SOURCE = Path("/private/tmp/xau-m1/xauusd-m1-ask-2025-09-01-2026-09-27.csv")
EVENTS = HERE / "events.csv"
MONTHLY = HERE / "monthly.csv"
SUMMARY = HERE / "summary.json"
README = HERE / "README.md"
START = dt.datetime(2025, 9, 27, tzinfo=dt.timezone.utc)
END = dt.datetime(2026, 9, 28, tzinfo=dt.timezone.utc)
POINT = 0.001
STOP_BUFFER_POINTS = 15
SPREAD_POINTS = 20
MAX_GAP = 5
PATTERNS = ("A", "B", "A+B")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def stamp(epoch: int) -> str:
    return dt.datetime.fromtimestamp(epoch, dt.timezone.utc).strftime("%Y.%m.%d %H:%M:%S")


def validate_ohlc(values: tuple[float, float, float, float], label: str) -> None:
    open_, high, low, close = values
    if not (math.isfinite(open_) and math.isfinite(high) and math.isfinite(low) and
            math.isfinite(close) and low <= min(open_, close) <= max(open_, close) <= high):
        raise ValueError(f"invalid {label} OHLC: {values}")


def prepare_data() -> dict:
    if DATA.exists():
        return {"prepared_from_bid_ask_csv": False}
    if not BID_SOURCE.is_file() or not ASK_SOURCE.is_file():
        raise FileNotFoundError(f"Need {DATA}, or source files {BID_SOURCE} and {ASK_SOURCE}")
    start = int(dt.datetime(2025, 9, 1, tzinfo=dt.timezone.utc).timestamp())
    end = int(END.timestamp())
    rows = 0
    unmatched_bid = 0
    unmatched_ask = 0
    max_spread = 0.0
    with BID_SOURCE.open(newline="", encoding="utf-8") as bid_file, \
         ASK_SOURCE.open(newline="", encoding="utf-8") as ask_file, \
         gzip.open(DATA, "wt", newline="", encoding="utf-8", compresslevel=6) as output:
        bid_reader, ask_reader = csv.DictReader(bid_file), csv.DictReader(ask_file)
        writer = csv.writer(output)
        writer.writerow(["timestamp", "epoch", "bid_open", "bid_high", "bid_low", "bid_close",
                         "ask_open", "ask_high", "ask_low", "ask_close", "spread_close"])
        bid_iter, ask_iter = iter(bid_reader), iter(ask_reader)
        bid = next(bid_iter, None)
        ask = next(ask_iter, None)
        while bid is not None and ask is not None:
            if bid["timestamp"] < ask["timestamp"]:
                unmatched_bid += 1
                bid = next(bid_iter, None)
                continue
            if ask["timestamp"] < bid["timestamp"]:
                unmatched_ask += 1
                ask = next(ask_iter, None)
                continue
            epoch = int(bid["timestamp"]) // 1000
            if start <= epoch < end:
                b = tuple(float(bid[k]) for k in ("open", "high", "low", "close"))
                a = tuple(float(ask[k]) for k in ("open", "high", "low", "close"))
                validate_ohlc(b, "bid")
                validate_ohlc(a, "ask")
                spread = a[3] - b[3]
                if spread < 0 or not math.isfinite(spread):
                    raise ValueError(f"invalid close spread at {epoch}: {spread}")
                max_spread = max(max_spread, spread)
                writer.writerow([stamp(epoch), epoch, *b, *a, f"{spread:.12g}"])
                rows += 1
            bid = next(bid_iter, None)
            ask = next(ask_iter, None)
        while bid is not None:
            unmatched_bid += 1
            bid = next(bid_iter, None)
        while ask is not None:
            unmatched_ask += 1
            ask = next(ask_iter, None)
    if rows == 0:
        raise ValueError("no synchronized M1 bid/ask data")
    return {"prepared_from_bid_ask_csv": True, "rows": rows,
            "unmatched_bid_timestamps": unmatched_bid,
            "unmatched_ask_timestamps": unmatched_ask,
            "max_close_spread": max_spread}


def compile_and_replay(plain_bars: Path) -> str:
    compiler = shutil.which("clang++") or shutil.which("g++")
    if not compiler:
        raise RuntimeError("clang++ or g++ is required")
    core = (SOURCE / "EngulfImbalanceCore.mqh").read_text(encoding="utf-8")
    adapted = re.sub(r"const (WHBar|int|double) &(\w+)\[\]",
                     r"const std::vector<\1> &\2", core)
    if adapted == core:
        raise RuntimeError("MQL dynamic array signatures were not adapted")
    with tempfile.TemporaryDirectory(prefix="ei-m1-replay-") as tmp:
        build = Path(tmp)
        (build / "ei_core_adapted.hpp").write_text(
            "#include <algorithm>\n#include <vector>\n" + adapted, encoding="utf-8")
        binary = build / "replay-m1"
        subprocess.run([compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
                        "-I", str(build), "-I", str(SOURCE), str(HERE / "replay_m1.cpp"),
                        "-o", str(binary)], cwd=ROOT, check=True)
        result = subprocess.run([str(binary), str(plain_bars), str(int(START.timestamp())),
                                 str(int(END.timestamp())), str(EVENTS), str(SPREAD_POINTS)], cwd=ROOT, check=True,
                                capture_output=True, text=True)
        return result.stdout.strip()


def wilson(wins: int, n: int) -> tuple[float | None, float | None]:
    if not n:
        return None, None
    z = 1.959963984540054
    p = wins / n
    denominator = 1 + z * z / n
    center = (p + z * z / (2 * n)) / denominator
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denominator
    return center - half, center + half


def read_bars() -> list[dict]:
    bars = []
    with gzip.open(DATA, "rt", newline="", encoding="utf-8") as stream:
        for row in csv.DictReader(stream):
            bars.append({"timestamp": row["timestamp"], "epoch": int(row["epoch"]),
                         **{k: float(row[k]) for k in
                            ("bid_open", "bid_high", "bid_low", "bid_close", "ask_open",
                             "ask_high", "ask_low", "ask_close", "spread_close")}})
    if not bars:
        raise ValueError("prepared dataset is empty")
    if any(bars[i]["epoch"] <= bars[i - 1]["epoch"] for i in range(1, len(bars))):
        raise ValueError("timestamps are not strictly increasing")
    return bars


def replay(bars: list[dict]) -> dict:
    with tempfile.NamedTemporaryFile("w", newline="", encoding="utf-8", suffix=".csv") as plain:
        with gzip.open(DATA, "rt", newline="", encoding="utf-8") as packed:
            shutil.copyfileobj(packed, plain)
        plain.flush()
        compiler_output = compile_and_replay(Path(plain.name))

    with EVENTS.open(newline="", encoding="utf-8") as stream:
        events = list(csv.DictReader(stream))
    outcomes = []
    for event in events:
        i = int(event["index"])
        engulf_i = int(event["engulf_index"])
        direction = 1 if event["side"] == "BUY" else -1
        pattern = event["pattern"]
        entry_i = i + 1
        outcome = {**event, "entry_index": entry_i, "entry": None, "sl": None, "tp": None,
                   "result": "NO_ENTRY", "bars_to_hit": None}
        if entry_i >= len(bars):
            outcomes.append(outcome)
            continue
        engulf = bars[engulf_i]
        engulfed = bars[engulf_i - 1]
        entry = bars[entry_i]["bid_open"]  # Preserve the prior M5/M15 gross-BID convention.
        buffer = STOP_BUFFER_POINTS * POINT
        if direction == 1:
            stop = min(engulf["bid_low"], engulfed["bid_low"]) - buffer
            if entry <= stop:
                outcomes.append({**outcome, "entry": entry, "sl": stop, "tp": None,
                                 "result": "NO_ENTRY"})
                continue
            target = entry + (entry - stop)
        else:
            stop = max(engulf["bid_high"], engulfed["bid_high"]) + buffer
            if entry >= stop:
                outcomes.append({**outcome, "entry": entry, "sl": stop, "tp": None,
                                 "result": "NO_ENTRY"})
                continue
            target = entry - (stop - entry)
        result, bars_to_hit = "UNRESOLVED", None
        for j in range(entry_i, len(bars)):
            bar = bars[j]
            if direction == 1:
                hit_sl, hit_tp = bar["bid_low"] <= stop, bar["bid_high"] >= target
            else:
                hit_sl, hit_tp = bar["bid_high"] >= stop, bar["bid_low"] <= target
            if hit_sl or hit_tp:
                bars_to_hit = j - entry_i + 1
                result = "BOTH" if hit_sl and hit_tp else ("SL" if hit_sl else "TP")
                break
        outcomes.append({**outcome, "entry": entry, "sl": stop, "tp": target,
                         "result": result, "bars_to_hit": bars_to_hit})

    fields = list(outcomes[0].keys()) if outcomes else []
    with EVENTS.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(outcomes)
    return {"compiler_output": compiler_output, "events": outcomes}


def metrics(events: list[dict]) -> dict:
    counts = Counter(event["result"] for event in events)
    tp, sl = counts["TP"], counts["SL"]
    resolved = tp + sl
    wr = tp / resolved if resolved else None
    low, high = wilson(tp, resolved)
    equity = peak = max_dd = 0
    streak = max_streak = 0
    for event in events:
        if event["result"] == "TP":
            equity += 1
            streak = 0
        elif event["result"] == "SL":
            equity -= 1
            streak += 1
            max_streak = max(max_streak, streak)
        else:
            continue
        peak = max(peak, equity)
        max_dd = max(max_dd, peak - equity)
    return {"signals": len(events), "TP": tp, "SL": sl, "BOTH": counts["BOTH"],
            "NO_ENTRY": counts["NO_ENTRY"], "UNRESOLVED": counts["UNRESOLVED"],
            "resolved": resolved, "win_rate": wr, "wilson95_low": low,
            "wilson95_high": high, "gross_profit_factor": tp / sl if sl else None,
            "gross_expectancy_R": (tp - sl) / resolved if resolved else None,
            "sequential_max_drawdown_R": max_dd, "max_loss_streak": max_streak,
            "immediate": sum(int(e["wait"]) == 0 for e in events),
            "R1": sum(int(e["wait"]) == 1 for e in events),
            "R2": sum(int(e["wait"]) == 2 for e in events)}


def make_reports(bars: list[dict], events: list[dict], prep: dict, replay_log: str) -> dict:
    groups = {"ALL": events}
    groups.update({pattern: [e for e in events if e["pattern"] == pattern] for pattern in PATTERNS})
    groups.update({side: [e for e in events if e["side"] == side] for side in ("BUY", "SELL")})
    grouped_metrics = {name: metrics(subset) for name, subset in groups.items()}

    by_month: dict[str, list[dict]] = defaultdict(list)
    for event in events:
        by_month[event["timestamp"][:7].replace(".", "-")].append(event)
    with MONTHLY.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(["month", "signals", "immediate", "R1", "R2", "TP", "SL", "BOTH",
                         "NO_ENTRY", "UNRESOLVED", "win_rate", "PF", "expectancy_R"])
        for month, subset in sorted(by_month.items()):
            m = metrics(subset)
            writer.writerow([month, m["signals"], m["immediate"], m["R1"], m["R2"], m["TP"],
                             m["SL"], m["BOTH"], m["NO_ENTRY"], m["UNRESOLVED"], m["win_rate"],
                             m["gross_profit_factor"], m["gross_expectancy_R"]])

    sources = {name: sha256(SOURCE / name) for name in
               ("EngulfImbalanceFlow.mq5", "EngulfImbalanceCore.mqh", "EngulfFlowCore.mqh", "FVGCore.mqh")}
    summary = {
        "indicator": "EngulfImbalanceFlow 1.08",
        "symbol": "XAUUSD",
        "timeframe": "M1",
        "study_window_utc": {"start_inclusive": START.isoformat(), "end_exclusive": END.isoformat()},
        "data_coverage_utc": {"first_bar_open": stamp(bars[0]["epoch"]),
                              "last_bar_open": stamp(bars[-1]["epoch"]), "bars": len(bars)},
        "data": {"source": "Dukascopy XAUUSD M1 bid and ask CSV, UTC offset 0",
                 "prepared_path": DATA.name, "prepared_sha256": sha256(DATA), **prep,
                 "bid_source_sha256": sha256(BID_SOURCE) if BID_SOURCE.exists() else None,
                 "ask_source_sha256": sha256(ASK_SOURCE) if ASK_SOURCE.exists() else None},
        "production_source_sha256": sources,
        "settings": {"mode": "FVG only", "FVG_min_gap_points": 0,
                     "FVG_require_middle_direction": False, "max_gap_bars": MAX_GAP,
                     "engulf_head_wick_max_of_body": 0.10,
                     "pullback_trigger": "Close extension beyond engulfed candle wick > 30% of engulf body",
                     "pullback_wait_bars": 2,
                     "fixed_spread_points": SPREAD_POINTS,
                     "fixed_spread_price": SPREAD_POINTS * POINT,
                     "pullback_allowance": "fixed spread for timeframe, used only as pullback allowance",
                     "entry": "next M1 bar bid open; same gross-BID convention as prior M5/M15 summary",
                     "stop": f"extreme of engulfed + engulf candles, buffer {STOP_BUFFER_POINTS} × {POINT}",
                     "target": "1:1 risk/reward from next-bar entry",
                     "outcome_scan": "bid OHLC from entry bar; first TP/SL touch; same-bar both is ambiguous",
                     "costs": "spread is used for pullback eligibility only; entry/exit gross results exclude spread cost, commission and slippage",
                     "overlap": "signals are evaluated independently; positions may overlap"},
        "replay_log": replay_log,
        "metrics": grouped_metrics,
        "monthly_csv": MONTHLY.name,
        "events_csv": EVENTS.name,
        "sample_gallery": "gallery/index.html",
        "caveats": ["BOTH cases are excluded from win rate/PF/expectancy.",
                    "NO_ENTRY means the next open was already through the planned stop or the data ended before an entry bar.",
                    "UNRESOLVED means neither level was touched before the dataset ended.",
                    "Sequential drawdown is an event-sequence statistic, not a portfolio simulation.",
                    "This is a Dukascopy bid/ask replay, not broker-specific MT5 execution or Strategy Tester output."]
    }
    SUMMARY.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    def fmt_pct(value):
        return "—" if value is None else f"{value * 100:.1f}%"
    def fmt_float(value, digits=3):
        return "—" if value is None else f"{value:.{digits}f}"
    lines = [
        "# EngulfImbalanceFlow 1.08 บน XAUUSD M1", "",
        f"ทดสอบ source ปัจจุบันด้วย FVG-only, ไส้ฝั่งพุ่งของแท่ง engulf ≤10% ของเนื้อ, และกฎปิดเลยปลายไส้เกิน 30% ให้รอย่อภายใน 2 แท่ง ใช้ fixed spread {SPREAD_POINTS} จุด ({SPREAD_POINTS * POINT:.3f}) เฉพาะตัดสินการย่อกลับ",
        "",
        f"ช่วงสัญญาณ UTC: {START:%Y-%m-%d} ถึงก่อน {END:%Y-%m-%d}. ข้อมูลมี {len(bars):,} แท่ง ตั้งแต่ {stamp(bars[0]['epoch'])} ถึง {stamp(bars[-1]['epoch'])}.",
        "",
        f"ผล TP/SL ใช้ entry ที่ bid open ของแท่งถัดไป, stop ใช้ extreme ของคู่แท่ง P/E เผื่อ 15×0.001, TP 1:1 และผล gross ใช้ bid OHLC. Fixed spread {SPREAD_POINTS} จุดถูกใช้เฉพาะกฎแตะกลับ ไม่ได้หักต้นทุน execution.",
        "",
        "| แบบ | สัญญาณ | เข้าทันที | R1 | R2 | TP | SL | ทั้งคู่ในแท่ง | เข้าไม่ได้ | ชนเป้า* |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|"
    ]
    for name, label in (("A", "A"), ("B", "B"), ("A+B", "A+B"), ("ALL", "**รวม**")):
        m = grouped_metrics[name]
        lines.append(f"| {label} | {m['signals']} | {m['immediate']} | {m['R1']} | {m['R2']} | {m['TP']} | {m['SL']} | {m['BOTH']} | {m['NO_ENTRY']} | {fmt_pct(m['win_rate'])} |")
    m = grouped_metrics["ALL"]
    lines += ["", f"*คำนวณ TP ÷ (TP+SL) เฉพาะ {m['resolved']} รายที่ตัดสินได้ ไม่รวมทั้งคู่, เข้าไม่ได้ และยังไม่ชนระดับ. Wilson 95%: {fmt_pct(m['wilson95_low'])}–{fmt_pct(m['wilson95_high'])}; gross PF {fmt_float(m['gross_profit_factor'])}; expectancy {fmt_float(m['gross_expectancy_R'], 4)}R ต่อรายการที่ตัดสินได้.",
              "", "ผลแยก BUY/SELL และรายเดือนอยู่ใน CSV.",
              "", "ข้อจำกัด: ผล TP/SL เป็น gross และไม่นับ spread, commission หรือ slippage ตอนเข้าออก. Bid/Ask M1 OHLC ไม่บอกลำดับ tick ภายในแท่ง; ถ้าแตะ TP และ SL ในแท่งเดียวจึงนับเป็น BOTH. สัญญาณประเมินแยกกันและอาจซ้อนกัน จึงไม่ใช่ผลพอร์ต.",
              "", "ดูภาพตัวอย่าง 30 สัญญาณได้ที่ [แกลเลอรี M1](gallery/index.html): แต่ละภาพมี EMA 20/50/200 บน M1 และกราฟ M5 ที่จัดแนวกับเวลาเกิดสัญญาณ. EMA เป็นเส้นประกอบภาพ ไม่ได้กรองสัญญาณ. ไฟล์ `events.csv` เก็บทุกสัญญาณและผล, `monthly.csv` สรุปรายเดือน, `summary.json` เก็บ source/data hashes และ settings. รันซ้ำด้วย:",
              "", "```sh", "python3 tests/reports/engulf-imbalance-xauusd-m1/run_m1_analysis.py", "```", ""]
    README.write_text("\n".join(lines), encoding="utf-8")
    return summary


def main() -> None:
    prep = prepare_data()
    bars = read_bars()
    replay_result = replay(bars)
    summary = make_reports(bars, replay_result["events"], prep, replay_result["compiler_output"])
    print(replay_result["compiler_output"])
    print(json.dumps(summary["metrics"]["ALL"], ensure_ascii=False))
    print(f"data bars={len(bars)} sha256={sha256(DATA)}")
    print(f"outputs={HERE}")


if __name__ == "__main__":
    main()
