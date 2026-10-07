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
    double open, high, low, close;
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
    if (!std::getline(input, line)) throw std::runtime_error("empty M5 file");
    std::vector<Bar> rows;
    while (std::getline(input, line)) {
        if (line.empty()) continue;
        const auto fields = split_csv(line);
        if (fields.size() < 6) throw std::runtime_error("short M5 row: " + line);
        rows.push_back({fields[0], std::stol(fields[1]), std::stod(fields[2]),
                        std::stod(fields[3]), std::stod(fields[4]), std::stod(fields[5])});
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
    if (argc != 5) {
        std::cerr << "usage: replay-fvg BARS.csv start_epoch end_epoch output.csv\n";
        return 2;
    }
    try {
        const auto rows = read_bars(argv[1]);
        const long start = std::stol(argv[2]);
        const long finish = std::stol(argv[3]);
        const int count = static_cast<int>(rows.size());
        if (count < 4 || finish <= start) throw std::runtime_error("invalid interval or too few bars");

        std::vector<WHBar> bars(count);
        std::vector<FVGBar> zones(count);
        std::vector<int> imbalance(count, 0);
        for (int i = 0; i < count; ++i) {
            bars[i] = {rows[i].open, rows[i].high, rows[i].low, rows[i].close};
            zones[i] = {rows[i].open, rows[i].high, rows[i].low, rows[i].close};
        }
        constexpr double point = 0.001;
        for (int i = 2; i < count; ++i) {
            FVGZone zone;
            if (FVGDetect(zones[i - 2], zones[i - 1], zones[i], 0, point, false, zone))
                imbalance[i] |= EIDirectionBit(zone.direction);
        }

        std::ofstream output(argv[4]);
        if (!output) throw std::runtime_error("cannot write event CSV");
        output << "index,timestamp,side,pattern,anchor_a,anchor_b,wick_tip,open,high,low,close\n";
        output << std::setprecision(15);
        int emitted = 0;
        for (int i = 2; i < count; ++i) {
            if (rows[i].time < start || rows[i].time >= finish) continue;
            EIResult result;
            if (!EIFind(i, bars, imbalance, count, 0, 5, result)) continue;
            output << i << ',' << rows[i].stamp << ','
                   << (result.direction == 1 ? "BUY" : "SELL") << ','
                   << pattern_name(result.pattern) << ','
                   << result.anchorA << ',' << result.anchorB << ','
                   << result.wickTip << ',' << rows[i].open << ',' << rows[i].high << ','
                   << rows[i].low << ',' << rows[i].close << '\n';
            ++emitted;
        }
        std::cout << "bars=" << count << " FVG-only signals=" << emitted << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FVG replay failed: " << error.what() << '\n';
        return 1;
    }
}
