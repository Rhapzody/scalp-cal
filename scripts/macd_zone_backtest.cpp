// Deterministic MACDZoneTrader replay adapter.
// It includes the production PullbackCore/TradePlanCore code and supplies
// simple CSV/quote adapters so the historical run is reproducible outside MT5.
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

using string = std::string;
using datetime = long;
using ulong = unsigned long long;
#define MathIsValidNumber std::isfinite
#define MathMax std::max
#define MathMin std::min
#define MathAbs std::abs
#define MathRound std::round
#define MathFloor std::floor
double NormalizeDouble(double v, int d) { double p = std::pow(10.0, d); return std::round(v * p) / p; }
template <class T> void ZeroMemory(T &v) { v = T{}; }
template <class T> int ArrayResize(std::vector<T> &v, int n) { v.resize(n); return n; }
template <class T> int ArraySize(const std::vector<T> &v) { return static_cast<int>(v.size()); }
bool IsStopped() { return false; }

#include "TradePlanCore.mqh" // generated C++-compatible copy of production headers

struct QuoteBar { long time; double open, high, low, close, volume; };

static std::vector<std::string> split(const std::string &line) {
    std::vector<std::string> out; std::stringstream ss(line); std::string cell;
    while (std::getline(ss, cell, ',')) out.push_back(cell);
    return out;
}

static std::vector<MSBar> loadBars(const std::string &path) {
    std::ifstream in(path); if (!in) throw std::runtime_error("cannot open " + path);
    std::string line; std::getline(in, line); std::vector<MSBar> out;
    while (std::getline(in, line)) {
        auto c = split(line); if (c.size() < 5) continue;
        long ms = std::stol(c[0]);
        out.push_back({ms / 1000, std::stod(c[1]), std::stod(c[2]), std::stod(c[3]), std::stod(c[4])});
    }
    return out;
}

static std::vector<QuoteBar> loadQuotes(const std::string &path) {
    std::ifstream in(path); if (!in) throw std::runtime_error("cannot open " + path);
    std::string line; std::getline(in, line); std::vector<QuoteBar> out;
    while (std::getline(in, line)) {
        auto c = split(line); if (c.size() < 6) continue;
        long ms = std::stol(c[0]);
        out.push_back({ms / 1000, std::stod(c[1]), std::stod(c[2]), std::stod(c[3]), std::stod(c[4]), std::stod(c[5])});
    }
    return out;
}

static RPConfig defaultConfig() {
    RPConfig c{};
    c.macd = {12, 26, 9, 0, 14, MS_PRICE, 0, 0.001, MS_HISTOGRAM_COLOR};
    c.zones = RP_BOTH; c.strength = RP_FVG_OR_DISPLACEMENT;
    c.min_leg_atr = 1.0; c.min_fvg_atr = 0.10; c.min_efficiency = 0.65; c.min_body_ratio = 0.50;
    c.max_leg_bars = 30; c.zone_life_bars = 144; c.confirmation_bars = 30;
    c.side = RP_ALL_SIDES; c.touch_mode = RP_TOUCH_WICK; c.invalidate_mode = RP_INVALIDATE_CLOSE;
    c.m5_break_buffer_points = 0; c.m1_break_buffer_points = 0; c.max_close_tail_ratio = 0.25;
    return c;
}

static std::string iso(long t) {
    std::time_t tt = static_cast<std::time_t>(t); std::tm tm{};
    gmtime_r(&tt, &tm); char buf[32]; std::strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", &tm);
    return buf;
}

static int indexAt(const std::vector<MSBar> &bars, long time) {
    auto it = std::lower_bound(bars.begin(), bars.end(), time, [](const MSBar &b, long t) { return b.time < t; });
    return it != bars.end() && it->time == time ? static_cast<int>(it - bars.begin()) : -1;
}

static double g_tick = 0.01; static int g_digits = 2;
static double snap(double price) { return NormalizeDouble(std::round(price / g_tick) * g_tick, g_digits); }

struct Audit {
    string signal_time, entry_time, side, status, reason, result, exit_time;
    double signal_price=0, trigger=0, zone_low=0, zone_high=0, entry=0, spread=0,
           pattern_low=0, pattern_high=0, sl=0, tp=0, broker_sl=0, broker_tp=0,
           rr=0, exit_price=0, r_multiple=0, target=0;
    int quality=0, bars_held=0;
};

static void writeAudit(const std::string &path, const std::vector<Audit> &rows) {
    std::ofstream out(path);
    out << "signal_time,entry_time,side,status,reason,result,exit_time,signal_price,trigger,zone_low,zone_high,pattern_low,pattern_high,entry,spread,sl,tp,broker_sl,broker_tp,target,rr,exit_price,r_multiple,bars_held,quality\n";
    out << std::fixed << std::setprecision(3);
    for (const auto &r : rows) {
        out << r.signal_time << ',' << r.entry_time << ',' << r.side << ',' << r.status << ',' << r.reason << ',' << r.result << ',' << r.exit_time << ','
            << r.signal_price << ',' << r.trigger << ',' << r.zone_low << ',' << r.zone_high << ',' << r.pattern_low << ',' << r.pattern_high << ','
            << r.entry << ',' << r.spread << ',' << r.sl << ',' << r.tp << ',' << r.broker_sl << ',' << r.broker_tp << ',' << r.target << ','
            << r.rr << ',' << r.exit_price << ',' << r.r_multiple << ',' << r.bars_held << ',' << r.quality << '\n';
    }
}

int main(int argc, char **argv) {
    if (argc < 5) {
        std::cerr << "usage: macd_zone_backtest BID_M1 ASK_M1 BID_M5 OUTPUT_PREFIX [digits] [max_spread_points] [fallback_spread]\n";
        return 2;
    }
    auto m1 = loadBars(argv[1]); auto ask = loadQuotes(argv[2]); auto m5 = loadBars(argv[3]);
    const std::string prefix = argv[4];
    if (m1.empty() || m5.empty()) throw std::runtime_error("empty data");
    const int digits = argc > 5 ? std::stoi(argv[5]) : 2;
    const double point = argc > 6 ? std::stod(argv[6]) : std::pow(10.0, -digits);
    const double maxSpreadPoints = argc > 7 ? std::stod(argv[7]) : 50.0;
    const double fallbackSpread = argc > 8 ? std::stod(argv[8]) : 0.67;
    g_tick = point; g_digits = digits;
    std::unordered_map<long, QuoteBar> askByTime;
    for (const auto &q : ask) askByTime[q.time] = q;
    RPConfig cfg = defaultConfig();
    const long horizon = m1.back().time + 60;

    RPState replay; std::vector<RPEntry> rawEntries;
    if (!RPReplay(replay, cfg, m1, static_cast<int>(m1.size()), m5, static_cast<int>(m5.size()), horizon, rawEntries))
        throw std::runtime_error("RPReplay failed");

    std::vector<Audit> audit;
    std::vector<long> seenBuy, seenSell;
    long occupiedUntil = 0; size_t trades = 0;
    const int historyM5 = 1500;
    const double tick = point;
    size_t fallbackQuotes = 0;

    // Candidate entries come from the production replay. Re-run each candidate
    // with the EA's rolling 1500-bar M5 history for exact context/targets.
    for (const auto &raw : rawEntries) {
        const int sigIdx = indexAt(m1, raw.time); if (sigIdx < 1) continue;
        const long entryTime = raw.time + 60; const int quoteIdx = indexAt(m1, entryTime);
        if (quoteIdx < 0) continue;
        if ((raw.direction == 1 && std::find(seenBuy.begin(), seenBuy.end(), raw.time) != seenBuy.end()) ||
            (raw.direction == -1 && std::find(seenSell.begin(), seenSell.end(), raw.time) != seenSell.end())) continue;
        (raw.direction == 1 ? seenBuy : seenSell).push_back(raw.time);

        int m5idx = static_cast<int>(std::upper_bound(m5.begin(), m5.end(), entryTime,
            [](long t, const MSBar &b) { return t < b.time; }) - m5.begin()) - 1;
        if (m5idx < 0) continue;
        int m5start = std::max(0, m5idx - historyM5);
        long firstM5 = m5[m5start].time;
        int m1start = static_cast<int>(std::lower_bound(m1.begin(), m1.end(), firstM5,
            [](const MSBar &b, long t) { return b.time < t; }) - m1.begin());
        int m1end = quoteIdx;
        if (m1start < 0 || m1end < m1start) continue;
        std::vector<MSBar> one(m1.begin() + m1start, m1.begin() + m1end + 1);
        std::vector<MSBar> five(m5.begin() + m5start, m5.begin() + m5idx + 1);
        EACandidate candidate{}; std::vector<EATarget> targets; string reason;
        if (!EABuildContext(cfg, one, static_cast<int>(one.size()), five, static_cast<int>(five.size()), entryTime, candidate, targets, reason)) continue;
        if (candidate.signal.time != raw.time || candidate.signal.direction != raw.direction) continue;

        Audit row; row.signal_time = iso(raw.time); row.entry_time = iso(entryTime);
        row.side = raw.direction == 1 ? "BUY" : "SELL"; row.signal_price = candidate.signal.price;
        row.trigger = candidate.signal.trigger; row.zone_low = candidate.signal.lower; row.zone_high = candidate.signal.upper;
        row.quality = candidate.signal.quality; row.pattern_low = candidate.pattern_low; row.pattern_high = candidate.pattern_high;
        auto qit = askByTime.find(entryTime);
        QuoteBar qbar;
        if (qit != askByTime.end()) qbar = qit->second;
        else { qbar = {entryTime, m1[quoteIdx].open + fallbackSpread, m1[quoteIdx].high + fallbackSpread,
                       m1[quoteIdx].low + fallbackSpread, m1[quoteIdx].close + fallbackSpread, 0}; fallbackQuotes++; }
        const double bidEntry = m1[quoteIdx].open, askEntry = qbar.open;
        row.entry = raw.direction == 1 ? askEntry : bidEntry; row.spread = askEntry - bidEntry;
        if (row.spread <= 0 || row.spread / point > maxSpreadPoints + 1e-7) { row.status="SKIP"; row.reason="spread above configured maximum"; audit.push_back(row); continue; }

        int tix = EANextTarget(raw.direction == 1, row.entry, entryTime, targets);
        if (tix < 0) { row.status="SKIP"; row.reason="no confirmed M5 swing ahead"; audit.push_back(row); continue; }
        row.target = targets[tix].price;
        row.sl = EAPatternStop(candidate, 0, point, tick, digits);
        row.tp = EATargetPrice(raw.direction == 1, row.target, 0, point, tick, digits);
        row.broker_sl = raw.direction == 1 ? row.sl : snap(row.sl + row.spread);
        row.broker_tp = raw.direction == 1 ? row.tp : snap(row.tp + row.spread);
        double risk = raw.direction == 1 ? row.entry - row.broker_sl : row.broker_sl - row.entry;
        double reward = raw.direction == 1 ? row.broker_tp - row.entry : row.entry - row.broker_tp;
        row.rr = risk > 0 ? reward / risk : 0;
        if (row.rr + 1e-12 < 1.0) { row.status="SKIP"; row.reason="R:R below 1 after spread"; audit.push_back(row); continue; }
        if (entryTime < occupiedUntil) { row.status="SKIP"; row.reason="symbol exposure already open"; audit.push_back(row); continue; }

        row.status="EXECUTED"; row.reason="all EA filters passed";
        int exitIdx = -1; bool stopFirst = false, targetFirst = false;
        for (int j = quoteIdx; j < static_cast<int>(m1.size()); ++j) {
            bool hitStop, hitTarget;
            auto aqit = askByTime.find(m1[j].time);
            QuoteBar aq;
            if (aqit != askByTime.end()) aq = aqit->second;
            else { aq = {m1[j].time, m1[j].open + fallbackSpread, m1[j].high + fallbackSpread,
                         m1[j].low + fallbackSpread, m1[j].close + fallbackSpread, 0}; fallbackQuotes++; }
            if (raw.direction == 1) {
                hitStop = m1[j].low <= row.broker_sl + 1e-9;
                hitTarget = m1[j].high >= row.broker_tp - 1e-9;
            } else {
                hitStop = aq.high >= row.broker_sl - 1e-9;
                hitTarget = aq.low <= row.broker_tp + 1e-9;
            }
            if (hitStop || hitTarget) { exitIdx = j; stopFirst = hitStop; targetFirst = hitTarget; break; }
        }
        if (exitIdx < 0) {
            auto aqit = askByTime.find(m1.back().time);
            double endAsk = aqit != askByTime.end() ? aqit->second.close : m1.back().close + fallbackSpread;
            row.result="OPEN_AT_DATA_END"; row.exit_time=iso(m1.back().time); row.exit_price=raw.direction==1 ? m1.back().close : endAsk;
            row.r_multiple = raw.direction==1 ? (row.exit_price-row.entry)/risk : (row.entry-row.exit_price)/risk;
            row.bars_held = static_cast<int>(m1.size()) - quoteIdx;
        } else {
            row.exit_time=iso(m1[exitIdx].time); row.bars_held=exitIdx-quoteIdx+1;
            if (stopFirst) { row.result = targetFirst ? "SL_AND_TP_SAME_BAR_SL_FIRST" : "SL"; row.exit_price=row.broker_sl; row.r_multiple=-1.0; }
            else { row.result="TP"; row.exit_price=row.broker_tp; row.r_multiple=reward/risk; }
            occupiedUntil = m1[exitIdx].time + 60;
        }
        audit.push_back(row); trades++;
    }
    writeAudit(prefix + "_audit.csv", audit);
    std::ofstream meta(prefix + "_meta.txt");
    meta << "data_start_utc=" << iso(m1.front().time) << "\n";
    meta << "data_end_utc=" << iso(m1.back().time) << "\n";
    meta << "m1_rows=" << m1.size() << "\n" << "m5_rows=" << m5.size() << "\n";
    meta << "raw_replay_entries=" << rawEntries.size() << "\n" << "audit_rows=" << audit.size() << "\n";
    meta << "executed_trades=" << trades << "\n";
    meta << "digits=" << digits << "\npoint=" << point << "\nmax_spread_points=" << maxSpreadPoints << "\nfallback_spread=" << fallbackSpread << "\n";
    meta << "actual_ask_rows=" << askByTime.size() << "\nfallback_quote_uses=" << fallbackQuotes << "\n";
    std::cerr << "raw_entries=" << rawEntries.size() << " audit_rows=" << audit.size() << " executed=" << trades << "\n";
    return 0;
}
