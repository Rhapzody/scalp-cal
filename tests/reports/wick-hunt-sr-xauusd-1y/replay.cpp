#include <algorithm>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

bool MathIsValidNumber(double v) { return std::isfinite(v); }
double MathMax(double a, double b) { return std::max(a, b); }
double MathMin(double a, double b) { return std::min(a, b); }
double MathAbs(double v) { return std::abs(v); }

#include "WickHuntSRCore.mqh"

struct Bar {
  long time;
  long first_minute_time;
  double open, high, low, close;
  int minute_count;
};

struct Minute {
  long time;
  double open, high, low, close;
};

static std::vector<std::string> Split(const std::string &line) {
  std::vector<std::string> out;
  std::stringstream stream(line);
  std::string field;
  while (std::getline(stream, field, ',')) out.push_back(field);
  return out;
}

static std::vector<Minute> ReadMinutes(const std::string &path) {
  std::ifstream file(path);
  if (!file) throw std::runtime_error("cannot open input minutes: " + path);
  std::string line;
  std::getline(file, line); // Header
  std::vector<Minute> rows;
  while (std::getline(file, line)) {
    const auto f = Split(line);
    if (f.size() < 6) continue;
    Minute m{std::stol(f[1]), std::stod(f[2]), std::stod(f[3]),
             std::stod(f[4]), std::stod(f[5])};
    if (m.low > std::min(m.open, m.close) || m.high < std::max(m.open, m.close))
      throw std::runtime_error("invalid M1 bid OHLC at epoch " + f[1]);
    rows.push_back(m);
  }
  return rows;
}

static std::map<long, Bar> Aggregate(const std::vector<Minute> &minutes, long seconds) {
  std::map<long, Bar> bars;
  for (const Minute &m : minutes) {
    const long start = (m.time / seconds) * seconds;
    auto it = bars.find(start);
    if (it == bars.end()) {
      bars.emplace(start, Bar{start, m.time, m.open, m.high, m.low, m.close, 1});
    } else {
      it->second.high = std::max(it->second.high, m.high);
      it->second.low = std::min(it->second.low, m.low);
      it->second.close = m.close;
      it->second.minute_count++;
    }
  }
  return bars;
}

static void WriteHeader(std::ofstream &out) {
  out << "event_time,sample_kind,setup_time,direction,price,sr,sr_type,break_time,pivot_time,"
         "confirm_time,hunt_open,prior_low,prior_high,reclaim_observed_time,"
         "breakout_observed_time,event_order,breakout_m5_complete\n";
}

int main(int argc, char **argv) {
  try {
    if (argc != 6) {
      std::cerr << "usage: wick-hunt-replay M1.csv events.csv diagnostics.json start_epoch end_epoch\n";
      return 2;
    }
    const std::string input = argv[1], output = argv[2];
    const long study_start = std::stol(argv[4]), study_end = std::stol(argv[5]);
    const std::vector<Minute> minutes = ReadMinutes(input);
    const auto m5_map = Aggregate(minutes, 300);
    const auto h1_map = Aggregate(minutes, 3600);
    std::vector<Bar> m5;
    for (const auto &item : m5_map) m5.push_back(item.second);
    std::vector<Bar> h1;
    for (const auto &item : h1_map) h1.push_back(item.second);

    std::ofstream events(output);
    if (!events) throw std::runtime_error("cannot create event output: " + output);
    WriteHeader(events);

    MSConfig config{};
    config.fast = 12; config.slow = 26; config.signal = 9; config.warmup = 0;
    config.atr_length = 14; config.threshold_mode = MS_PRICE; config.threshold = 0;
    config.point = 0.001; config.swing_mode = MS_HISTOGRAM_COLOR;
    WSState state{};
    WSReset(state, 0);
    WSContext context{};
    context.valid = false;
    size_t next_m5 = 0;
    int m5_index = 0;
    long current_setup = -1;
    long open_snapshot_count = 0, close_snapshot_count = 0;
    long signals = 0;
    long buy_reclaim_time = -1, sell_reclaim_time = -1;
    long buy_break_observed_time = -1, sell_break_observed_time = -1;
  long study_setups = 0, eligible_setups = 0, no_prior_setups = 0;
  long partial_prior_setups = 0, late_current_open_setups = 0;

    auto take = [&](long now, double price, const char *sample_kind, bool breakout_complete) {
      if (now < study_start || now >= study_end || !context.valid) return;
      for (int direction = 1; direction >= -1; direction -= 2) {
        WSSignal signal{};
        if (!WSTakeSignal(state, context, now, price, direction, signal)) continue;
        WSBreak b = direction == 1 ? state.buy_break : state.sell_break;
        const long reclaim_time = direction == 1 ? buy_reclaim_time : sell_reclaim_time;
        const long break_seen_time = direction == 1 ? buy_break_observed_time : sell_break_observed_time;
        const char *order = reclaim_time < 0 || break_seen_time < 0 ? "unknown" :
                            (reclaim_time < break_seen_time ? "reclaim_first" :
                             (reclaim_time > break_seen_time ? "breakout_first" : "same_snapshot"));
        events << signal.time << ',' << sample_kind << ',' << signal.setup_time << ',' << signal.direction << ','
               << std::setprecision(12) << signal.price << ',' << signal.sr << ','
               << signal.sr_type << ',' << signal.break_time << ',' << signal.pivot_time << ','
               << b.confirm_time << ',' << context.open << ',' << context.prior_low << ','
               << context.prior_high << ',' << reclaim_time << ',' << break_seen_time << ','
               << order << ',' << (breakout_complete ? 1 : 0) << '\n';
        ++signals;
      }
    };

    auto set_context = [&](const Minute &m) {
      const long bucket = (m.time / 3600) * 3600;
      size_t hi = 0;
      while (hi < h1.size() && h1[hi].time != bucket) ++hi;
      context.time = bucket;
      context.end_time = bucket + 3600;
      context.valid = false;
      context.open = 0;
      context.prior_low = 0;
      context.prior_high = 0;
      if (hi >= h1.size()) return;
      context.open = h1[hi].open;
      const bool current_open_observed_at_hour = h1[hi].first_minute_time == bucket;
      if (hi == 0) return;
      const Bar &prior = h1[hi - 1];
      context.prior_low = prior.low;
      context.prior_high = prior.high;
      // HuntBars=1 needs the immediately preceding observed H1 candle. Require
      // all 60 source M1 bars in that candle; never skip back over a bad hour.
      // The current H1 must have its first M1 timestamp at the hour boundary
      // so its open cannot come from a later, incomplete source hour.
      context.valid = prior.minute_count == 60 && current_open_observed_at_hour;
    };

    long active_hour = -1;
    double running_high = 0, running_low = 0;
    for (size_t i = 0; i < minutes.size(); ++i) {
      const Minute &m = minutes[i];
      const long hour = (m.time / 3600) * 3600;
      if (hour != active_hour) {
        active_hour = hour;
        running_high = m.open;
        running_low = m.open;
        set_context(m);
        if (context.time != current_setup) {
          current_setup = context.time;
          if (context.time >= study_start && context.time < study_end) {
            ++study_setups;
            const auto current_it = std::find_if(h1.begin(), h1.end(),
              [&](const Bar &b) { return b.time == context.time; });
            const size_t current_index = (size_t)std::distance(h1.begin(), current_it);
            const bool current_open_observed_at_hour = current_it != h1.end() &&
              current_it->first_minute_time == context.time;
            if (current_index == 0) ++no_prior_setups;
            else if (h1[current_index - 1].minute_count != 60) ++partial_prior_setups;
            if (!current_open_observed_at_hour) ++late_current_open_setups;
            if (context.valid) ++eligible_setups;
          }
          buy_reclaim_time = sell_reclaim_time = -1;
          buy_break_observed_time = sell_break_observed_time = -1;
          WSBeginSetup(state, context.time); // Roll H1 before processing the prior M5 close.
        }
      } else {
        running_high = std::max(running_high, m.open);
        running_low = std::min(running_low, m.open);
      }

      // At a new observed M1 open, MT5 has already rolled and closed any M5
      // candle whose end time has passed. This is also where a boundary uses
      // the new H1 context, so the preceding H1's final M5 cannot emit there.
      while (next_m5 < m5.size() && m5[next_m5].time + 300 <= m.time) {
        const Bar &bar = m5[next_m5];
        WSContext process_context = context;
        const bool complete = bar.minute_count == 5;
        if (!complete) process_context.valid = false; // Reject breakout on an incomplete reconstructed M5.
        MSBar lower{bar.time, bar.open, bar.high, bar.low, bar.close};
        const WSBreak old_buy_break = state.buy_break;
        const WSBreak old_sell_break = state.sell_break;
        WSProcessClosed(state, config, lower, m5_index++, 300, process_context, 10, MS_SR_WICK);
        if (state.buy_break.valid && (!old_buy_break.valid ||
            state.buy_break.bar_time != old_buy_break.bar_time ||
            state.buy_break.pivot_time != old_buy_break.pivot_time)) {
          buy_break_observed_time = m.time;
        }
        if (state.sell_break.valid && (!old_sell_break.valid ||
            state.sell_break.bar_time != old_sell_break.bar_time ||
            state.sell_break.pivot_time != old_sell_break.pivot_time)) {
          sell_break_observed_time = m.time;
        }
        ++next_m5;
      }
      if (context.valid) {
        const bool buy_had_reclaim = state.buy_reclaimed;
        const bool sell_had_reclaim = state.sell_reclaimed;
        WSObserve(state, context, m.time, running_high, running_low, m.open);
        if (!buy_had_reclaim && state.buy_reclaimed) buy_reclaim_time = m.time;
        if (!sell_had_reclaim && state.sell_reclaimed) sell_reclaim_time = m.time;
        take(m.time, m.open, "m1_open", true);
      }
      ++open_snapshot_count;

      // The M1 OHLC becomes available at its close. Use its closing bid as an
      // observed sample only after adding this completed minute's extremes.
      running_high = std::max(running_high, m.high);
      running_low = std::min(running_low, m.low);
      const long close_sample_time = m.time + 59;
      if (context.valid) {
        const bool buy_had_reclaim = state.buy_reclaimed;
        const bool sell_had_reclaim = state.sell_reclaimed;
        WSObserve(state, context, close_sample_time, running_high, running_low, m.close);
        if (!buy_had_reclaim && state.buy_reclaimed) buy_reclaim_time = close_sample_time;
        if (!sell_had_reclaim && state.sell_reclaimed) sell_reclaim_time = close_sample_time;
        take(close_sample_time, m.close, "m1_close", true);
      }
      ++close_snapshot_count;
    }

    std::ofstream diagnostics(argv[3]);
    if (!diagnostics) throw std::runtime_error("cannot create diagnostics output: " + std::string(argv[3]));
    diagnostics << "{\n"
      << "  \"m1_rows\": " << minutes.size() << ",\n"
      << "  \"h1_groups\": " << h1.size() << ",\n"
      << "  \"m5_groups\": " << m5.size() << ",\n"
      << "  \"m5_partial_groups\": " << std::count_if(m5.begin(), m5.end(), [](const Bar &b) { return b.minute_count != 5; }) << ",\n"
      << "  \"signals\": " << signals << ",\n"
      << "  \"study_h1_setups\": " << study_setups << ",\n"
      << "  \"eligible_h1_setups\": " << eligible_setups << ",\n"
      << "  \"no_prior_h1_setups\": " << no_prior_setups << ",\n"
      << "  \"partial_prior_h1_setups\": " << partial_prior_setups << ",\n"
      << "  \"late_current_h1_open_setups\": " << late_current_open_setups << ",\n"
      << "  \"m1_open_snapshots\": " << open_snapshot_count << ",\n"
      << "  \"m1_close_snapshots\": " << close_snapshot_count << "\n}\n";
    return 0;
  } catch (const std::exception &e) {
    std::cerr << "replay error: " << e.what() << '\n';
    return 1;
  }
}
