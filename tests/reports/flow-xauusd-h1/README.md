# Engulf Flow and Imbalance Flow replay: XAUUSD H1

This report replays the current indicator cores on one year of XAUUSD H1 bars and includes 30 diagnostic chart examples for each indicator. The charts and event CSVs are in this folder; open [gallery.html](gallery.html) for the image gallery and [summary.json](summary.json) for machine-readable coverage and counts.

## Data coverage

The source is Algo Special's free 100,000-row XAUUSDm M30 export: [dataset article](https://www.algospecial.com/blogs/xauusd-historical-dataset-free-download.php) and [CSV download](https://www.algospecial.com/historical-data/XAUUSDm_PERIOD_M30_OHLC.csv). The verified file used here has SHA-256 8b8a597b3e9d9ab9c7d608e2e0c8ac25f8b2a48fe2f1e26ef339994030da74fd, source labels from 2018.02.11 23:00:00 through 2026.08.05 15:30:00, 100,000 unique rows, and no invalid OHLC rows.

The user's requested dates were 2025-09-27 through 2026-09-27. The available file ends on 2026-08-05, so the last part of that request has no source data. Following the approved cutoff, the primary test is the exact 365-day interval [2025.08.05 15:00:00, 2026.08.05 15:00:00) in the file's displayed time labels. It contains 5,905 complete H1 bars; the last tested H1 bar opens at 2026.08.05 14:00:00. The overlap with the originally requested start date contains 5,028 bars and is summarized separately in summary.json.

The dataset article calls the timestamp a close label, while its embedded MT5 export example uses MqlRates.time, the bar-open time. This report therefore assumes each timestamp is an M30 open label, preserves the labels as supplied, and does not claim a timezone. That assumption matters for H1 alignment. The observed symbol is XAUUSDm; its price feed and session schedule can differ from another broker's XAUUSD.

The H1 series is derived by grouping M30 bars with the same hour label and requiring both :00 and :30 rows. H1 open is the first M30 open, high and low are the extremes of both rows, close is the second M30 close, and tick volumes are summed. Forty-eight incomplete hour bins are excluded, and no bars are invented across gaps. The final possible H1 bar at 2026.08.05 15:00:00 is excluded because the source has no retrieval timestamp proving that its last 15:30 M30 bar was closed. h1_bars.csv contains the chronological H1 bars used by the replay, including the earlier bars needed for indicator history; event rows are restricted to the one-year study interval.

The replay encodes the timezone-naive source labels on a fixed arithmetic axis solely so the displacement core can compare one-hour intervals. It does not convert the displayed labels to UTC. Imbalance Flow's default Reject time gaps setting remains enabled, so gaps in the observed hourly series can suppress displacement signals when the core's reference window crosses a gap.

## Method and results

The runner compiles and calls the same Engulf Flow and Imbalance Flow MQL5 core functions shipped in this project. It does not edit production indicator code or run a MetaTrader terminal. Engulf uses the default one-bar wick hunt and body engulf mode, with prior-movement and EMA filters off. Its 5-second live-candle preview is outside this historical closed-bar replay.

Imbalance uses the shipped defaults: a 500-closed-bar rolling window; FVG plus displacement detection; full-fill lifecycle; displacement single-or-leg with base-wick zones; ATR 14; breakout required; and time-gap rejection enabled. The replay rebuilds the rolling window on each close and resets source/direction deduplication inside that window, matching the indicator's historical calculation behavior. Its chart cap is 50 zones at a time; the event counts below are confirmed detections across the replay, not zones shown simultaneously on one live chart. Both indicators are evaluated only after each H1 candle closes.

| Indicator output | Count |
| --- | ---: |
| Engulf Flow buy signals | 401 |
| Engulf Flow sell signals | 405 |
| Engulf Flow total signal bars | 806 |
| Imbalance FVG zones | 1,152 |
| Imbalance single-candle displacement zones | 89 |
| Imbalance multi-candle displacement zones | 46 |
| Imbalance total components | 1,287 |
| Imbalance distinct signal bars | 1,248 |

The component total can exceed distinct Imbalance signal bars because an FVG and a displacement zone can confirm on the same candle. In the available portion of the originally requested date range, the replay found 677 Engulf signals and 1,094 Imbalance components across 1,065 signal bars.

The event log records only detections on the newest completed candle at each step. It does not count older-buffer changes that may arise later as the rolling lookback changes. This harness runs core detection and rolling deduplication; it does not execute the complete MT5 OnCalculate function, render the native chart, or reconstruct all visible boxes at every historical step. Fill annotations in the gallery are calculated separately for the selected events.

The gallery selects events by chronological position within each event group, without ranking by later price movement. It shows 15 buy and 15 sell Engulf examples, and five buy plus five sell examples for each Imbalance component type. Each chart has 36 prior and 24 later observed H1 bars where available. Imbalance charts annotate the first subsequent full fill through the available cutoff, or show that the zone was still unfilled; the charts keep filled zones visible for explanation even though the MT5 default hides filled zones.

These counts and chart outcomes test indicator signals and zone lifecycles. They are not trade counts or a profitability result: this report defines no entries, stops, targets, order fills, spread adjustment, commission, or slippage model. Tick volume and spread are present in the source file but are not used by these indicator cores. The images are reconstructions from OHLC, not screenshots from MT5.

## Reproduce

The downloaded source CSV is not copied into this folder. To reproduce the same run, download the file from the link above and use a Python 3 environment with Pillow for the gallery and clang++ for the source-core replay.

1. Run python3 tests/reports/flow-xauusd-h1/run_replay.py --input /path/to/XAUUSDm_PERIOD_M30_OHLC.csv --output tests/reports/flow-xauusd-h1.
2. Run python3 scripts/build_flow_gallery.py tests/reports/flow-xauusd-h1 tests/reports/flow-xauusd-h1/h1_bars.csv.

The replay writes h1_bars.csv, engulf_events.csv, imbalance_events.csv, and summary.json. The gallery builder writes 60 PNG charts, gallery.html, and gallery_manifest.json. For the data file used in this report, the core replay produced the counts above; a later refreshed CSV can have different coverage and results, so compare its SHA-256 before treating it as the same run.

The existing unit suites for these indicator cores also passed in the parent audit: 21,019 Engulf Flow checks and 5,043 Imbalance Flow checks. An independent default Engulf replay matched this report's 806 signals (401 buy, 405 sell).
