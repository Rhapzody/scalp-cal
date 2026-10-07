#include <cmath>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#define MathIsValidNumber std::isfinite
#define MathMin std::min
#define MathMax std::max
#define MathAbs std::abs

#include "ei_core_adapted.hpp"
#include "FVGCore.mqh"

struct Bar {
    std::string stamp;
    long time;
    double bid_open, bid_high, bid_low, bid_close;
    double ask_open, ask_high, ask_low, ask_close;
    double spread_close;
};

static std::vector<std::string> split_csv(const std::string& line) {
    std::vector<std::string> fields;
    std::stringstream stream(line);
    std::string field;
    while (std::getline(stream, field, ',')) fields.push_back(field);
    return fields;
}

static std::vector<Bar> read_bars(const std::string& path) {
    std::ifstream input(path);
    if (!input) throw std::runtime_error("cannot open " + path);
    std::string line;
    if (!std::getline(input, line)) throw std::runtime_error("empty M1 file");
    std::vector<Bar> rows;
    while (std::getline(input, line)) {
        if (line.empty()) continue;
        const auto f = split_csv(line);
        if (f.size() != 11) throw std::runtime_error("expected 11 columns: " + line);
        rows.push_back({f[0], std::stol(f[1]),
            std::stod(f[2]), std::stod(f[3]), std::stod(f[4]), std::stod(f[5]),
            std::stod(f[6]), std::stod(f[7]), std::stod(f[8]), std::stod(f[9]),
            std::stod(f[10])});
    }
    return rows;
}

static const char* pattern_name(const int pattern) {
    if (pattern == 1) return "A";
    if (pattern == 2) return "B";
    if (pattern == 3) return "A+B";
    return "";
}

int main(int argc, char** argv) {
    if (argc != 6) {
        std::cerr << "usage: replay-m1 BARS.csv start_epoch end_epoch output.csv fixed_spread_points\n";
        return 2;
    }
    try {
        const auto rows = read_bars(argv[1]);
        const long start = std::stol(argv[2]);
        const long finish = std::stol(argv[3]);
        const double fixed_spread_points = std::stod(argv[5]);
        const int count = static_cast<int>(rows.size());
        if (count < 4 || finish <= start || !std::isfinite(fixed_spread_points) || fixed_spread_points < 0)
            throw std::runtime_error("invalid interval, spread or too few bars");

        std::vector<WHBar> bars(static_cast<size_t>(count));
        std::vector<FVGBar> zones(static_cast<size_t>(count));
        std::vector<int> imbalance(static_cast<size_t>(count), 0);
        constexpr double point = 0.001;
        const double fixed_spread = fixed_spread_points * point;
        std::vector<double> spread(static_cast<size_t>(count), fixed_spread);
        for (int i = 0; i < count; ++i) {
            const auto& row = rows[static_cast<size_t>(i)];
            bars[static_cast<size_t>(i)] = {row.bid_open, row.bid_high, row.bid_low, row.bid_close};
            zones[static_cast<size_t>(i)] = {row.bid_open, row.bid_high, row.bid_low, row.bid_close};
            if (i > 0 && row.time <= rows[static_cast<size_t>(i - 1)].time)
                throw std::runtime_error("timestamps are not strictly increasing");
        }

        for (int i = 2; i < count; ++i) {
            FVGZone zone;
            if (FVGDetect(zones[static_cast<size_t>(i - 2)], zones[static_cast<size_t>(i - 1)],
                          zones[static_cast<size_t>(i)], 0.0, point, false, zone))
                imbalance[static_cast<size_t>(i)] |= EIDirectionBit(zone.direction);
        }

        std::ofstream output(argv[4]);
        if (!output) throw std::runtime_error("cannot write event CSV");
        output << "index,timestamp,side,pattern,anchor_a,anchor_b,wick_tip,engulf_index,wait,entry_level,"
                  "signal_open,signal_high,signal_low,signal_close,spread_used,"
                  "engulf_open,engulf_high,engulf_low,engulf_close,"
                  "engulfed_open,engulfed_high,engulfed_low,engulfed_close\n";
        output << std::setprecision(15);
        int emitted = 0;
        for (int i = 2; i < count; ++i) {
            const auto& row = rows[static_cast<size_t>(i)];
            if (row.time < start || row.time >= finish) continue;
            EIResult result;
            if (!EIFindEntry(i, bars, imbalance, spread, count, 0, 5, result)) continue;
            const auto& engulf = rows[static_cast<size_t>(result.engulfIndex)];
            const auto& engulfed = rows[static_cast<size_t>(result.engulfIndex - 1)];
            output << i << ',' << row.stamp << ','
                   << (result.direction == 1 ? "BUY" : "SELL") << ','
                   << pattern_name(result.pattern) << ',' << result.anchorA << ',' << result.anchorB << ','
                   << result.wickTip << ',' << result.engulfIndex << ',' << (i - result.engulfIndex) << ','
                   << result.entryLevel << ',' << row.bid_open << ',' << row.bid_high << ','
                   << row.bid_low << ',' << row.bid_close << ',' << fixed_spread << ','
                   << engulf.bid_open << ',' << engulf.bid_high << ',' << engulf.bid_low << ','
                   << engulf.bid_close << ',' << engulfed.bid_open << ',' << engulfed.bid_high << ','
                   << engulfed.bid_low << ',' << engulfed.bid_close << '\n';
            ++emitted;
        }
        std::cout << "bars=" << count << " FVG-only entry signals=" << emitted << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "M1 replay failed: " << error.what() << '\n';
        return 1;
    }
}
