// Export the project's TV Style MACD on the report's complete chronological M1 series.
#include <algorithm>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
constexpr double EMPTY_VALUE=std::numeric_limits<double>::max();
bool MathIsValidNumber(double v) { return std::isfinite(v); }
double MathMax(double a,double b) { return std::max(a,b); }
double MathAbs(double v) { return std::abs(v); }
#include "MACDCore.mqh"
#include "SwingCore.mqh"

int main(int argc,char** argv)
{
    try {
        if(argc!=3) throw std::runtime_error("usage: tv-macd M1.csv MACD.csv");
        std::ifstream input(argv[1]); std::ofstream output(argv[2]);
        if(!input || !output) throw std::runtime_error("cannot open MACD input/output");
        std::string line; std::getline(input,line);
        output<<"epoch,macd,signal,histogram,color_index\n"<<std::setprecision(17);
        double fast=EMPTY_VALUE,slow=EMPTY_VALUE,signal=EMPTY_VALUE,previous_histogram=EMPTY_VALUE;
        MSEngine swing; MSReset(swing);
        MSConfig config{12,26,9,0,14,MS_PRICE,0,.001,MS_HISTOGRAM_COLOR};
        int count=0;
        while(std::getline(input,line)) {
            std::stringstream stream(line); std::vector<std::string> values; std::string value;
            while(std::getline(stream,value,',')) values.push_back(value);
            if(values.size()!=7) throw std::runtime_error("invalid M1 CSV row");
            long time=std::stol(values[1]);
            double o=std::stod(values[2]),h=std::stod(values[3]),l=std::stod(values[4]),c=std::stod(values[5]);
            double source=TVPrice(TV_CLOSE,o,h,l,c),sum=0;
            ++count;
            fast=TVMovingAverage(TV_EMA,12,count,source,fast,0,0,sum);
            slow=TVMovingAverage(TV_EMA,26,count,source,slow,0,0,sum);
            double macd=fast-slow;
            signal=TVMovingAverage(TV_EMA,9,count,macd,signal,0,0,sum);
            double histogram=macd-signal;
            int color=TVHistogramColor(histogram,previous_histogram,true);
            MSBar bar{time,o,h,l,c}; MSEvent event;
            if(!MSProcess(config,bar,count-1,swing,event) ||
               macd!=swing.fast-swing.slow || signal!=swing.signal || histogram!=swing.histogram)
                throw std::runtime_error("TV Style MACD differs from the signal's swing engine at "+values[1]);
            output<<time<<','<<macd<<','<<signal<<','<<histogram<<','<<color<<'\n';
            previous_histogram=histogram;
        }
        std::cerr<<"TV Style MACD: "<<count<<" M1 bars verified against Histogram swing engine\n";
    } catch(const std::exception& error) {
        std::cerr<<error.what()<<'\n'; return 1;
    }
}
