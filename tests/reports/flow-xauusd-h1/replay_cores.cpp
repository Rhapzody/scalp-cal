#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <map>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

#define MathIsValidNumber std::isfinite
#define MathMin std::min
#define MathMax std::max
#define MathAbs std::abs

#include "../../../MQL5/Indicators/EngulfFlow/EngulfFlowCore.mqh"
#include "../../../MQL5/Indicators/ImbalanceFlow/FVGCore.mqh"

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
    FVGBar price;
    double volume;
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
    if(!input) throw std::runtime_error("cannot open H1 input CSV: "+path);
    std::string line;
    std::getline(input,line);
    std::vector<Bar> result;
    size_t row=1;
    while(std::getline(input,line)) {
        ++row;
        if(line.empty()) continue;
        auto f=split_csv(line);
        if(f.size()!=7) throw std::runtime_error("expected 7 fields at H1 CSV row "+std::to_string(row));
        Bar b;
        b.stamp=f[0];
        b.time=std::stol(f[1]);
        b.price.open=std::stod(f[2]);
        b.price.high=std::stod(f[3]);
        b.price.low=std::stod(f[4]);
        b.price.close=std::stod(f[5]);
        b.volume=std::stod(f[6]);
        if(!FVGValidBar(b.price)) throw std::runtime_error("invalid OHLC at H1 CSV row "+std::to_string(row));
        result.push_back(b);
    }
    if(result.size()<3) throw std::runtime_error("fewer than 3 H1 candles");
    for(size_t i=1;i<result.size();++i)
        if(result[i].time<=result[i-1].time)
            throw std::runtime_error("H1 timestamps must be strictly increasing");
    return result;
}

static DPConfig default_dp_config() {
    DPConfig c{};
    c.method=DP_SINGLE_OR_LEG;
    c.zone_mode=DP_BASE_WICK;
    c.atr_length=14;
    c.relative_bars=20;
    c.min_leg_bars=2;
    c.max_leg_bars=4;
    c.breakout_bars=5;
    c.base_search_bars=5;
    c.min_body_atr=0.80;
    c.min_body_ratio=0.70;
    c.max_tail_ratio=0.15;
    c.min_relative_body=0;
    c.min_leg_atr=1.50;
    c.min_efficiency=0.75;
    c.min_direction_ratio=0.66;
    c.max_leg_tail_ratio=0.20;
    c.require_breakout=true;
    c.reject_time_gaps=true;
    c.breakout_atr=0.10;
    return c;
}

static bool in_period(long time,long start,long end) {
    return time>=start && time<end;
}

static std::string side_name(int side) { return side>0 ? "BUY" : "SELL"; }

static void write_engulf(std::ofstream& out,size_t index,int side,const Bar& b) {
    out<<std::setprecision(15);
    out<<index<<','<<b.stamp<<','<<side_name(side)<<','
       <<b.price.open<<','<<b.price.high<<','<<b.price.low<<','<<b.price.close<<'\n';
}

static void write_imbalance(std::ofstream& out,size_t index,const Bar& b,const std::string& kind,
                            int side,int source,double lower,double upper) {
    out<<std::setprecision(15);
    out<<index<<','<<b.stamp<<','<<kind<<','<<side_name(side)<<','<<source<<','
       <<lower<<','<<upper<<'\n';
}

int main(int argc,char** argv) {
    if(argc!=5) {
        std::cerr<<"usage: flow-replay H1.csv start_epoch end_epoch output_dir\n";
        return 2;
    }
    try {
        const std::string input_path=argv[1];
        const long start=std::stol(argv[2]);
        const long end=std::stol(argv[3]);
        const std::string output_dir=argv[4];
        if(end<=start) throw std::runtime_error("end epoch must be after start");
        auto bars=read_bars(input_path);
        std::vector<long> times;
        std::vector<FVGBar> core_bars;
        times.reserve(bars.size());
        core_bars.reserve(bars.size());
        for(const auto& b:bars) {
            times.push_back(b.time);
            core_bars.push_back(b.price);
        }

        std::ofstream engulf(output_dir+"/engulf_events.csv");
        std::ofstream imbalance(output_dir+"/imbalance_events.csv");
        if(!engulf || !imbalance) throw std::runtime_error("cannot create event CSVs in "+output_dir);
        engulf<<"index,timestamp,side,open,high,low,close\n";
        imbalance<<"index,timestamp,component,side,source_index,zone_lower,zone_upper\n";

        const DPConfig config=default_dp_config();
        if(!DPConfigValid(config)) throw std::runtime_error("invalid default displacement config");
        const long seconds=3600;
        size_t begin=bars.size(),finish=bars.size();
        for(size_t i=0;i<bars.size();++i) {
            if(begin==bars.size() && bars[i].time>=start) begin=i;
            if(finish==bars.size() && bars[i].time>=end) finish=i;
        }
        if(begin==bars.size()) begin=bars.size()-1;
        if(finish==bars.size()) finish=bars.size();

        for(size_t i=std::max<size_t>(1,begin);i<finish;++i) {
            if(!in_period(bars[i].time,start,end)) continue;

            WHBar current{bars[i].price.open,bars[i].price.high,bars[i].price.low,bars[i].price.close};
            WHBar previous{bars[i-1].price.open,bars[i-1].price.high,bars[i-1].price.low,bars[i-1].price.close};
            const int engulf_side=WHSignal(current,previous,true,WH_ENGULF_BODY);
            if(engulf_side!=0) write_engulf(engulf,i,engulf_side,bars[i]);

            const int first=std::max(0,static_cast<int>(i)-500+1);
            if(static_cast<int>(i)>=first+2) {
                FVGZone fvg{};
                if(FVGDetect(core_bars[i-2],core_bars[i-1],core_bars[i],0.0,0.01,false,fvg))
                    write_imbalance(imbalance,i,bars[i],"FVG",fvg.direction,i-2,fvg.lower,fvg.upper);
            }

            // Rebuild the indicator's rolling detection window at each closed
            // candle. This mirrors its source/direction deduplication state.
            std::unordered_map<int,int> used;
            used.reserve(64);
            for(int j=first;j<=static_cast<int>(i);++j) {
                FVGZone zone{};
                int source=-1,kind=0;
                if(!DPDetect(config,core_bars,times,static_cast<int>(core_bars.size()),
                             first,j,seconds,zone,source,kind)) continue;
                const int bit=zone.direction==1 ? 1 : 2;
                int& mask=used[source];
                if((mask&bit)!=0) continue;
                mask|=bit;
                if(j==static_cast<int>(i))
                    write_imbalance(imbalance,i,bars[i],kind==1 ? "DP_SINGLE" : "DP_LEG",
                                    zone.direction,source,zone.lower,zone.upper);
            }
        }
        return 0;
    }
    catch(const std::exception& error) {
        std::cerr<<"flow replay failed: "<<error.what()<<'\n';
        return 1;
    }
}
