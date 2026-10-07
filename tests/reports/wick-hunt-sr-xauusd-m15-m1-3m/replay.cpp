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

bool MathIsValidNumber(double value) { return std::isfinite(value); }
double MathMax(double left, double right) { return std::max(left, right); }
double MathMin(double left, double right) { return std::min(left, right); }
double MathAbs(double value) { return std::abs(value); }

#include "WickHuntContextCore.mqh"

struct Minute {
  long time;
  double open, high, low, close;
};

struct HigherBar {
  long time;
  double open, high, low, close;
  int minute_count;
  long first_minute_time, last_minute_time;
};

struct ReclaimFacts {
  bool valid = false;
  long time = 0;
  std::string sample_kind;
  double price = 0, high = 0, low = 0;
  int pattern = 0;
  long trend_break_epoch = 0, trend_origin_epoch = 0;
  long trend_pivot_epoch = 0, trend_confirm_epoch = 0;
  double trend_origin_price = 0, trend_pivot_price = 0, trend_sr = 0;
};

struct EventRow {
  long event_epoch = 0, setup_epoch = 0, reclaim_epoch = 0;
  long breakout_epoch = 0, break_close_epoch = 0, pivot_epoch = 0, confirm_epoch = 0;
  long anchor_epoch = 0, trend_pivot_epoch = 0;
  long trend_break_epoch = 0, trend_origin_epoch = 0, trend_confirm_epoch = 0;
  int direction = 0, pattern = 0, sr_type = 0, swept_count = 0;
  std::string reclaim_sample_kind;
  double signal_bid = 0, m15_open = 0, sr_price = 0, pivot_price = 0, context_sr = 0;
  double trend_origin_price = 0, trend_pivot_price = 0, trend_sr = 0;
  double reclaim_bid = 0, reclaim_known_high = 0, reclaim_known_low = 0, reclaim_tip = 0;
  double known_high = 0, known_low = 0;
  double prior_low_1 = 0, prior_high_1 = 0, prior_low_2 = 0, prior_high_2 = 0;
};

static std::vector<std::string> Split(const std::string &line) {
  std::vector<std::string> fields;
  std::stringstream stream(line);
  std::string field;
  while (std::getline(stream, field, ',')) fields.push_back(field);
  return fields;
}

static std::vector<Minute> ReadMinutes(const std::string &path) {
  std::ifstream input(path);
  if (!input) throw std::runtime_error("cannot open M1 source: " + path);
  std::string line;
  std::getline(input, line);
  std::vector<Minute> result;
  long previous = -1;
  while (std::getline(input, line)) {
    const auto fields = Split(line);
    if (fields.size() < 6) throw std::runtime_error("invalid M1 CSV row");
    Minute minute{std::stol(fields[1]), std::stod(fields[2]), std::stod(fields[3]),
                  std::stod(fields[4]), std::stod(fields[5])};
    if (minute.time <= previous) throw std::runtime_error("M1 timestamps not strictly increasing");
    if (!MSBarValid(MSBar{minute.time, minute.open, minute.high, minute.low, minute.close}))
      throw std::runtime_error("invalid M1 bid OHLC at epoch " + fields[1]);
    result.push_back(minute);
    previous = minute.time;
  }
  if (result.empty()) throw std::runtime_error("M1 source is empty");
  return result;
}

static void WriteEventHeader(std::ofstream &out) {
  out << "event_epoch,sample_kind,setup_epoch,direction,signal_bid,m15_open,sr_price,sr_type,"
         "breakout_epoch,break_close_epoch,pivot_epoch,confirm_epoch,pivot_price,pattern,"
         "context_sr,anchor_epoch,trend_pivot_epoch,trend_break_epoch,trend_origin_epoch,"
         "trend_origin_price,trend_pivot_price,trend_confirm_epoch,trend_sr,reclaim_epoch,reclaim_sample_kind,"
         "reclaim_bid,reclaim_known_high,reclaim_known_low,reclaim_tip,known_high,known_low,"
         "prior_low_1,prior_high_1,prior_low_2,prior_high_2,swept_prior_m15_count\n";
}

int main(int argc, char **argv) {
  try {
    if (argc != 6) {
      std::cerr << "usage: replay M1.csv events_raw.csv diagnostics.json start_epoch end_epoch\n";
      return 2;
    }
    const std::string input_path = argv[1], event_path = argv[2], diagnostics_path = argv[3];
    const long study_start = std::stol(argv[4]), study_end = std::stol(argv[5]);
    const std::vector<Minute> minutes = ReadMinutes(input_path);

    MSConfig config{};
    config.fast = 12; config.slow = 26; config.signal = 9; config.warmup = 0;
    config.atr_length = 14; config.threshold_mode = MS_PRICE; config.threshold = 0;
    config.point = 0.01; config.swing_mode = MS_HISTOGRAM_COLOR;

    WHCState higher{};
    WHCReset(higher);
    std::vector<MSBar> higher_closed;
    int higher_index = 0;
    WSState lower{};
    WSReset(lower, 0);
    WSContext context{};
    context.valid = false;
    int lower_index = 0;

    long active_setup = -1;
    long active_bucket = -1;
    HigherBar forming{};
    bool forming_initialized = false;
    int bucket_source_count = 0;
    long bucket_first_time = -1, bucket_last_time = -1;
    double running_high = 0, running_low = 0;
    bool bucket_saw_gap = false;
    Minute previous_minute{};
    bool has_previous_minute = false;
    ReclaimFacts buy_reclaim, sell_reclaim;
    std::vector<EventRow> all_events;

    long complete_m15 = 0, incomplete_m15 = 0, higher_resets = 0;
    long study_setups = 0, eligible_setups = 0;
    long late_open_setups = 0, insufficient_higher_history_setups = 0;
    long source_gap_context_invalidations = 0;
    long m1_open_samples = 0, m1_close59_samples = 0;
    long raw_signal_count = 0;
    long prior_minute_gaps = 0;

    auto clear_reclaims = [&]() {
      buy_reclaim = ReclaimFacts{};
      sell_reclaim = ReclaimFacts{};
    };

    auto finish_higher = [&]() {
      if (!forming_initialized) return;
      const bool complete = forming.minute_count == 15 &&
          forming.first_minute_time == forming.time &&
          forming.last_minute_time == forming.time + 14 * 60 && !bucket_saw_gap;
      if (complete) {
        MSBar bar{forming.time, forming.open, forming.high, forming.low, forming.close};
        if (!WHCProcessClosed(higher, config, bar, higher_index++, 10, MS_SR_WICK))
          throw std::runtime_error("higher core rejected a valid M15 bar");
        higher_closed.push_back(bar);
        ++complete_m15;
      } else {
        ++incomplete_m15;
        ++higher_resets;
        WHCReset(higher);
        higher_closed.clear();
        higher_index = 0;
      }
    };

    auto record_transition = [&](bool was_reclaimed, int direction, long now,
                                 const std::string &kind, double price,
                                 double high, double low) {
      const bool is_reclaimed = direction == 1 ? lower.buy_reclaimed : lower.sell_reclaimed;
      if (was_reclaimed || !is_reclaimed) return;
      ReclaimFacts &fact = direction == 1 ? buy_reclaim : sell_reclaim;
      fact.valid = true; fact.time = now; fact.sample_kind = kind;
      fact.price = price; fact.high = high; fact.low = low;
      fact.pattern = direction == 1 ? lower.buy_pattern : lower.sell_pattern;
      if ((fact.pattern & 2) != 0) {
        fact.trend_break_epoch = higher.trend.break_time;
        fact.trend_origin_epoch = higher.trend.origin_time;
        fact.trend_origin_price = higher.trend.origin_price;
        fact.trend_pivot_epoch = higher.trend.pivot_time;
        fact.trend_pivot_price = higher.trend.pivot_price;
        fact.trend_confirm_epoch = higher.trend.confirm_time;
        fact.trend_sr = higher.trend.sr;
      }
    };

    auto capture_signal = [&](long now, double price, double high, double low) {
      if (now < study_start || now >= study_end || !context.valid) return;
      for (int direction : {1, -1}) {
        WSSignal signal{};
        if (!WSTakeSignal(lower, context, now, price, direction, signal)) continue;
        const WSBreak &br = direction == 1 ? lower.buy_break : lower.sell_break;
        const ReclaimFacts &reclaim = direction == 1 ? buy_reclaim : sell_reclaim;
        if (!reclaim.valid) throw std::runtime_error("signal has no recorded reclaim");
        // Wick anchor means the remembered WSBreak price is also the pivot wick.
        // The level can be evicted from the rolling SR buffer after this break is latched.
        const double pivot_price = br.price;
        if (higher_closed.size() < 2) throw std::runtime_error("valid context has fewer than two prior M15 bars");
        const MSBar &prior1 = higher_closed[higher_closed.size() - 1];
        const MSBar &prior2 = higher_closed[higher_closed.size() - 2];
        const double reclaim_tip = direction == 1 ? reclaim.low : reclaim.high;
        const int swept = static_cast<int>(direction == 1 ? reclaim.low < prior1.low : reclaim.high > prior1.high) +
                          static_cast<int>(direction == 1 ? reclaim.low < prior2.low : reclaim.high > prior2.high);
        EventRow row{};
        row.event_epoch = now; row.setup_epoch = signal.setup_time;
        row.direction = direction; row.signal_bid = price; row.m15_open = context.open;
        row.sr_price = signal.sr; row.sr_type = signal.sr_type;
        row.breakout_epoch = signal.break_time; row.break_close_epoch = br.close_time;
        row.pivot_epoch = signal.pivot_time; row.confirm_epoch = br.confirm_time;
        row.pivot_price = pivot_price; row.pattern = signal.pattern;
        row.context_sr = signal.context_sr; row.anchor_epoch = signal.anchor_time;
        row.trend_pivot_epoch = reclaim.trend_pivot_epoch;
        row.trend_break_epoch = reclaim.trend_break_epoch;
        row.trend_origin_epoch = reclaim.trend_origin_epoch;
        row.trend_confirm_epoch = reclaim.trend_confirm_epoch;
        row.trend_origin_price = reclaim.trend_origin_price;
        row.trend_pivot_price = reclaim.trend_pivot_price;
        row.trend_sr = reclaim.trend_sr;
        row.reclaim_epoch = reclaim.time; row.reclaim_sample_kind = reclaim.sample_kind;
        row.reclaim_bid = reclaim.price; row.reclaim_known_high = reclaim.high;
        row.reclaim_known_low = reclaim.low; row.reclaim_tip = reclaim_tip;
        row.known_high = high; row.known_low = low;
        row.prior_low_1 = prior1.low; row.prior_high_1 = prior1.high;
        row.prior_low_2 = prior2.low; row.prior_high_2 = prior2.high;
        row.swept_count = swept;
        all_events.push_back(row);
        ++raw_signal_count;
      }
    };

    for (size_t i = 0; i < minutes.size(); ++i) {
      const Minute &minute = minutes[i];
      const long bucket = (minute.time / 900) * 900;
      if (has_previous_minute && minute.time - previous_minute.time != 60) ++prior_minute_gaps;

      if (bucket != active_bucket) {
        finish_higher();
        active_bucket = bucket;
        forming = HigherBar{bucket, minute.open, minute.open, minute.open, minute.open, 0,
                            minute.time, minute.time};
        forming_initialized = true;
        bucket_source_count = 0;
        bucket_first_time = minute.time;
        bucket_last_time = minute.time;
        bucket_saw_gap = false;
        running_high = minute.open;
        running_low = minute.open;

        context.time = bucket;
        context.end_time = bucket + 900;
        context.open = minute.open;
        context.prior_low = 0;
        context.prior_high = 0;
        context.valid = false;
        if (higher_closed.size() >= 1) {
          context.prior_low = higher_closed.back().low;
          context.prior_high = higher_closed.back().high;
        }
        const bool starts_on_boundary = minute.time == bucket;
        const int required_closed_higher = std::max(MSWarmup(config) + 1,
                                                    std::max(6, std::max(3, 2)));
        const bool enough_higher = static_cast<int>(higher_closed.size()) >= required_closed_higher;
        const bool has_full_prior = !higher_closed.empty() &&
            higher_closed.back().time + 900 <= bucket;
        context.valid = starts_on_boundary && enough_higher && has_full_prior;
        if (bucket >= study_start && bucket < study_end) {
          ++study_setups;
          if (!starts_on_boundary) ++late_open_setups;
          if (!enough_higher) ++insufficient_higher_history_setups;
          if (context.valid) ++eligible_setups;
        }

        // Roll the M15 setup before consuming the M1 bar that just closed at this boundary.
        if (context.time != active_setup) {
          active_setup = context.time;
          WSBeginSetup(lower, context.time);
          clear_reclaims();
        }
      } else if (has_previous_minute && minute.time - previous_minute.time != 60) {
        bucket_saw_gap = true;
        if (context.valid) {
          context.valid = false;
          WSBeginSetup(lower, context.time);
          clear_reclaims();
          ++source_gap_context_invalidations;
        }
      }

      // A closed M1 is consumed only at the next observed M1 open. At an M15
      // boundary the fresh setup above is already active, so the old close expires.
      if (has_previous_minute) {
        MSBar closed{previous_minute.time, previous_minute.open, previous_minute.high,
                     previous_minute.low, previous_minute.close};
        WSProcessClosed(lower, config, closed, lower_index++, 60, context, 10, MS_SR_WICK);
      }

      // The M1 open is the entry snapshot. Reclaim sees only the prior closed
      // M1 extrema plus this new open; no current-minute high/low is used here.
      running_high = std::max(running_high, minute.open);
      running_low = std::min(running_low, minute.open);
      if (context.valid) {
        const bool had_buy = lower.buy_reclaimed;
        const bool had_sell = lower.sell_reclaimed;
        WSObservePatterns(lower, context, higher, higher_closed.data(),
                          static_cast<int>(higher_closed.size()), minute.time,
                          running_high, running_low, minute.open, WS_BOTH,
                          1, 2, 5, MS_SR_WICK, 0, 0, config.point, false);
        record_transition(had_buy, 1, minute.time, "m1_open", minute.open,
                          running_high, running_low);
        record_transition(had_sell, -1, minute.time, "m1_open", minute.open,
                          running_high, running_low);
        capture_signal(minute.time, minute.open, running_high, running_low);
      }
      ++m1_open_samples;

      // Fold the minute into the higher candle once its OHLC is available.
      if (bucket_source_count == 0) {
        forming.open = minute.open;
        forming.high = minute.high;
        forming.low = minute.low;
      } else {
        forming.high = std::max(forming.high, minute.high);
        forming.low = std::min(forming.low, minute.low);
      }
      forming.close = minute.close;
      forming.minute_count = ++bucket_source_count;
      forming.first_minute_time = bucket_first_time;
      forming.last_minute_time = bucket_last_time = minute.time;

      // M1 close:59 snapshot is representative and approximate. Its completed
      // minute OHLC supplies cumulative current-M15 extremes, but never an M1
      // breakout until the bar is consumed at the next open.
      running_high = std::max(running_high, minute.high);
      running_low = std::min(running_low, minute.low);
      if (context.valid) {
        const long close_sample_time = minute.time + 59;
        const bool had_buy = lower.buy_reclaimed;
        const bool had_sell = lower.sell_reclaimed;
        WSObservePatterns(lower, context, higher, higher_closed.data(),
                          static_cast<int>(higher_closed.size()), close_sample_time,
                          running_high, running_low, minute.close, WS_BOTH,
                          1, 2, 5, MS_SR_WICK, 0, 0, config.point, false);
        record_transition(had_buy, 1, close_sample_time, "m1_close59", minute.close,
                          running_high, running_low);
        record_transition(had_sell, -1, close_sample_time, "m1_close59", minute.close,
                          running_high, running_low);
      }
      ++m1_close59_samples;
      previous_minute = minute;
      has_previous_minute = true;
    }
    finish_higher();

    std::ofstream events(event_path);
    if (!events) throw std::runtime_error("cannot create event output");
    WriteEventHeader(events);
    events << std::setprecision(15);
    for (const EventRow &row : all_events) {
      events << row.event_epoch << ",m1_open," << row.setup_epoch << "," << row.direction << ","
             << row.signal_bid << "," << row.m15_open << "," << row.sr_price << "," << row.sr_type << ","
             << row.breakout_epoch << "," << row.break_close_epoch << "," << row.pivot_epoch << ","
             << row.confirm_epoch << "," << row.pivot_price << "," << row.pattern << ","
             << row.context_sr << "," << row.anchor_epoch << "," << row.trend_pivot_epoch << ","
             << row.trend_break_epoch << "," << row.trend_origin_epoch << "," << row.trend_origin_price << ","
             << row.trend_pivot_price << "," << row.trend_confirm_epoch << "," << row.trend_sr << ","
             << row.reclaim_epoch << "," << row.reclaim_sample_kind << "," << row.reclaim_bid << ","
             << row.reclaim_known_high << "," << row.reclaim_known_low << "," << row.reclaim_tip << ","
             << row.known_high << "," << row.known_low << "," << row.prior_low_1 << ","
             << row.prior_high_1 << "," << row.prior_low_2 << "," << row.prior_high_2 << ","
             << row.swept_count << "\n";
    }

    std::ofstream diagnostics(diagnostics_path);
    if (!diagnostics) throw std::runtime_error("cannot create diagnostics output");
    diagnostics << "{\n"
      << "  \"m1_rows\": " << minutes.size() << ",\n"
      << "  \"complete_m15_processed\": " << complete_m15 << ",\n"
      << "  \"incomplete_m15_rejected\": " << incomplete_m15 << ",\n"
      << "  \"higher_core_resets\": " << higher_resets << ",\n"
      << "  \"study_m15_setups\": " << study_setups << ",\n"
      << "  \"eligible_m15_setups\": " << eligible_setups << ",\n"
      << "  \"late_current_m15_open_setups\": " << late_open_setups << ",\n"
      << "  \"insufficient_higher_history_setups\": " << insufficient_higher_history_setups << ",\n"
      << "  \"source_gap_context_invalidations\": " << source_gap_context_invalidations << ",\n"
      << "  \"m1_gaps\": " << prior_minute_gaps << ",\n"
      << "  \"m1_open_snapshots\": " << m1_open_samples << ",\n"
      << "  \"m1_close59_snapshots\": " << m1_close59_samples << ",\n"
      << "  \"events\": " << raw_signal_count << "\n}\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "replay error: " << error.what() << "\n";
    return 1;
  }
}
