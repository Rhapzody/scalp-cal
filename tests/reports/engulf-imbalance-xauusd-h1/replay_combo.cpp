#include <algorithm>
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
#include "../../../MQL5/Indicators/EngulfImbalanceFlow/FVGCore.mqh"

template<class T> int ArrayResize(std::vector<T>& values,int size) {
    values.resize(static_cast<size_t>(size));
    return size;
}
void ArraySort(std::vector<double>& values) {
    std::sort(values.begin(),values.end());
}

#include "dp_core_adapted.hpp"

struct Bar {
    std::string stamp;
    long time;
    double open,high,low,close;
};

static std::vector<std::string> split_csv(const std::string& line) {
    std::vector<std::string> fields;
    std::stringstream stream(line);
    std::string field;
    while(std::getline(stream,field,',')) fields.push_back(field);
    return fields;
}

static std::vector<Bar> read_bars(const std::string& path) {
    std::ifstream input(path);
    if(!input) throw std::runtime_error("cannot open "+path);
    std::string line;
    if(!std::getline(input,line)) throw std::runtime_error("empty H1 file");
    std::vector<Bar> rows;
    while(std::getline(input,line)) {
        if(line.empty()) continue;
        auto fields=split_csv(line);
        if(fields.size()<6) throw std::runtime_error("short H1 row "+line);
        Bar bar;
        bar.stamp=fields[0];
        bar.time=std::stol(fields[1]);
        bar.open=std::stod(fields[2]);
        bar.high=std::stod(fields[3]);
        bar.low=std::stod(fields[4]);
        bar.close=std::stod(fields[5]);
        rows.push_back(bar);
    }
    return rows;
}

static std::string kinds_for(int mask,int direction) {
    std::string text;
    auto add=[&](int bit,const char* name) {
        if((mask&bit)==0) return;
        if(!text.empty()) text+='+';
        text+=name;
    };
    if(direction==1) {
        add(1,"FVG"); add(4,"DP_SINGLE"); add(16,"DP_LEG");
    } else {
        add(2,"FVG"); add(8,"DP_SINGLE"); add(32,"DP_LEG");
    }
    return text.empty() ? "-" : text;
}

static const char* pattern_name(int pattern) {
    if(pattern==1) return "A";
    if(pattern==2) return "B";
    if(pattern==3) return "A+B";
    return "";
}

int main(int argc,char** argv) {
    if(argc<5 || argc>7) {
        std::cerr<<"usage: replay-combo BARS.csv start_epoch end_epoch output_dir [bar_seconds] [fixed_spread_points]\n";
        return 2;
    }
    try {
        auto rows=read_bars(argv[1]);
        const long start=std::stol(argv[2]);
        const long finish=std::stol(argv[3]);
        const std::string output=argv[4];
        const long seconds=argc>=6 ? std::stol(argv[5]) : 3600;
        const double fixed_spread_points=argc==7 ? std::stod(argv[6]) : 0.0;
        const int count=static_cast<int>(rows.size());
        if(count<4 || finish<=start || seconds<=0) throw std::runtime_error("not enough closed bars");
        std::vector<WHBar> bars(count);
        std::vector<FVGBar> zones(count);
        std::vector<long> times(count);
        std::vector<int> imbalance(count,0),components(count,0);
        for(int i=0;i<count;++i) {
            bars[i].open=zones[i].open=rows[i].open;
            bars[i].high=zones[i].high=rows[i].high;
            bars[i].low=zones[i].low=rows[i].low;
            bars[i].close=zones[i].close=rows[i].close;
            times[i]=rows[i].time;
        }
        const double point=0.001;
        for(int i=0;i<count;++i) {
            if(i<2) continue;
            FVGZone zone;
            if(FVGDetect(zones[i-2],zones[i-1],zones[i],0,point,false,zone)) {
                imbalance[i]|=EIDirectionBit(zone.direction);
                components[i]|=zone.direction==1 ? 1 : 2;
            }
        }
        std::vector<double> spread(static_cast<size_t>(count),fixed_spread_points*point);
        std::ofstream events(output+"/combo_events.csv");
        if(!events) throw std::runtime_error("cannot write combo events");
        events<<"index,timestamp,side,pattern,anchor_a,anchor_a_time,anchor_a_kinds,gap_a,"
              <<"anchor_b,anchor_b_time,anchor_b_kinds,gap_b,wick_tip,open,high,low,close,"
              <<"engulf_index,wait,entry_level\n";
        events<<std::setprecision(12);
        int signals=0,buys=0,sells=0,a=0,b=0,both=0;
        for(int i=2;i<count;++i) {
            if(rows[i].time<start || rows[i].time>=finish) continue;
            EIResult result;
            if(!EIFindEntry(i,bars,imbalance,spread,count,0,5,result)) continue;
            auto anchor_fields=[&](int anchor) {
                if(anchor<0) { events<<"-,-,-,-,"; return; }
                events<<anchor<<','<<rows[anchor].stamp<<','
                      <<kinds_for(components[anchor],result.direction)<<','
                      <<(result.engulfIndex-anchor-1)<<',';
            };
            ++signals;
            if(result.direction==1) ++buys; else ++sells;
            if(result.pattern==1) ++a;
            else if(result.pattern==2) ++b;
            else ++both;
            events<<i<<','<<rows[i].stamp<<','<<(result.direction==1 ? "BUY" : "SELL")<<','
                  <<pattern_name(result.pattern)<<',';
            anchor_fields(result.anchorA);
            anchor_fields(result.anchorB);
            if(result.anchorB>=0) events<<result.wickTip;
            events<<','<<rows[i].open<<','<<rows[i].high<<','<<rows[i].low<<','<<rows[i].close<<','
                  <<result.engulfIndex<<','<<(i-result.engulfIndex)<<','<<result.entryLevel<<'\n';
        }
        std::cout<<"signals "<<signals<<" buy "<<buys<<" sell "<<sells
                 <<" A "<<a<<" B "<<b<<" AB "<<both<<'\n';
        return 0;
    } catch(const std::exception& error) {
        std::cerr<<"combo replay failed: "<<error.what()<<'\n';
        return 1;
    }
}
