#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <random>
#include <vector>
#define MathIsValidNumber std::isfinite
#include "../../MQL5/Indicators/PAReversal/PAReversalCore.mqh"
using datetime=long long;
constexpr double EMPTY_VALUE=std::numeric_limits<double>::max();
int InpMinBars=3;
std::vector<double> BuyBuffer,SellBuffer,DirectionBuffer,CountBuffer;
datetime g_first_bar=0,g_current_bar=0;
template<class T> void ArraySetAsSeries(const std::vector<T>&,bool) {}
template<class T,class V> void ArrayInitialize(std::vector<T>& a,V v) { std::fill(a.begin(),a.end(),v); }
int MathMax(int a,int b) { return std::max(a,b); }
bool IsStopped() { return false; }
#include "pa_indicator_under_test.hpp"
int checks=0;
void check(bool ok,const char* label)
{
    ++checks;
    if(!ok) { std::cerr<<"FAIL: "<<label<<'\n'; std::exit(1); }
}
std::vector<int> signals(const std::vector<PABar>& bars,int minimum=3)
{
    PAState state{};
    std::vector<int> result;
    for(size_t i=0;i<bars.size();++i) {
        PAState next{};
        int signal=0;
        if(i==0) PASeed(bars[i],next);
        else signal=PAStep(bars[i],bars[i-1],state,minimum,next);
        result.push_back(signal);
        state=next;
    }
    return result;
}
struct Snapshot { std::vector<double> buy,sell,direction,count; };
Snapshot calculate(const std::vector<PABar>& bars,int prev,datetime base=1000)
{
    size_t n=bars.size();
    BuyBuffer.resize(n); SellBuffer.resize(n); DirectionBuffer.resize(n); CountBuffer.resize(n);
    std::vector<double> o,h,l,c;
    std::vector<datetime> t;
    for(size_t i=0;i<n;++i) {
        o.push_back(bars[i].open); h.push_back(bars[i].high);
        l.push_back(bars[i].low); c.push_back(bars[i].close); t.push_back(base+i*60);
    }
    std::vector<long> ticks(n),vol(n);
    std::vector<int> spreads(n);
    check(OnCalculate(int(n),prev,t,o,h,l,c,ticks,vol,spreads)==int(n),"OnCalculate return count");
    return {BuyBuffer,SellBuffer,DirectionBuffer,CountBuffer};
}
void equal(const Snapshot& a,const Snapshot& b)
{
    check(a.buy==b.buy && a.sell==b.sell && a.direction==b.direction && a.count==b.count,
          "incremental calculation equals full history");
}
int main()
{
    const PABar a{10,12,9,11},b{11,13,10,12},c{12,14,11,13},sell{13,13.5,9,10};
    auto seq=signals({a,b,c,sell});
    check(seq==std::vector<int>({0,0,0,-1}),"three up candles then sell on fourth");
    check(signals({b,c,sell}).back()==0,"two candles are insufficient despite wick break");
    check(signals({a,b,c,sell},4).back()==0,"custom minimum four");
    check(signals({a,sell},1).back()==0,"equal low is not below low");
    check(signals({c,sell},1).back()==-1,"minimum one");
    check(signals({a,b,c,{13,15,8,12}}).back()==0,"wick-only penetration ignored");
    check(signals({a,b,c,{13,15,8,11}}).back()==0,"close exactly at low ignored");
    check(signals({a,{11,12,10,10.5},{10.5,11.5,10,10.5},{10.5,11,9,9.5}}).back()==-1,
          "opposite color, inside bar and doji continue up leg");
    check(signals({a,b,c,{8,10.8,7,10.5}}).back()==-1,"gap bullish candle can sell by close");
    check(signals({{10,11,9,10},{10,11,9,10},{10,11,9,10}})==std::vector<int>({0,0,0}),
          "initial dojis do not invent a direction");
    const PABar down2{10,11,8,9},down3{9,10,7,8},buy{8,12,7,11};
    check(signals({a,b,c,sell,down2,down3,buy})==std::vector<int>({0,0,0,-1,0,0,1}),
          "reversal bar is first candle of next leg");
    check(signals({a,{10,11,7,8},{8,13,7,12}},2).back()==0,"premature reversal resets count");
    check(signals({a,b,c,sell,down2}).back()==0,"no repeated sell while leg continues down");
    // Reflect all prices: buy and sell must behave symmetrically, even below zero.
    std::vector<PABar> original{a,b,c,sell,down2,down3,buy},mirror;
    for(auto v:original) mirror.push_back({-v.open,-v.low,-v.high,-v.close});
    auto normal=signals(original),reflected=signals(mirror);
    for(size_t i=0;i<normal.size();++i) check(normal[i]==-reflected[i],"buy/sell mirror symmetry");
    auto invalid=c; invalid.close=std::numeric_limits<double>::quiet_NaN();
    check(signals({a,b,invalid,sell}).back()==0,"invalid data resets leg");

    // Exercise actual production OnCalculate, not a duplicate scheduler.
    auto live=calculate({a,b,c,sell},0);
    check(live.sell.back()==EMPTY_VALUE,"forming reversal candle is hidden");
    auto confirmed=calculate({a,b,c,sell,down2},4);
    check(confirmed.sell[3]==sell.high && confirmed.buy[3]==EMPTY_VALUE,"sell on signal high after close");
    auto tick=calculate({a,b,c,sell,buy},5);
    equal(confirmed,tick);
    auto both=calculate({a,b,c,sell,down2,down3,buy,a},0);
    check(both.buy[6]==buy.low,"buy anchored below signal low");
    check(both.sell[7]==EMPTY_VALUE && both.buy[7]==EMPTY_VALUE,"live buffers empty");
    calculate({},0);
    calculate({a},0);

    std::mt19937 random(42);
    std::vector<PABar> bars;
    double last=100;
    for(int i=0;i<500;++i) {
        double o=last+(int(random()%9)-4)*0.25;
        double close=o+(int(random()%17)-8)*0.25;
        bars.push_back({o,std::max(o,close)+(random()%5)*0.25,
                         std::min(o,close)-(random()%5)*0.25,close});
        last=close;
    }
    for(int minimum:{1,2,3,7,1000}) {
        InpMinBars=minimum;
        int prev=0;
        for(size_t n=1;n<=bars.size();++n) {
            std::vector<PABar> prefix(bars.begin(),bars.begin()+n);
            auto incremental=calculate(prefix,prev);
            auto full=calculate(prefix,0);
            equal(incremental,full);
            check(full.buy.back()==EMPTY_VALUE && full.sell.back()==EMPTY_VALUE,"live bar always empty");
            prev=int(n);
        }
        calculate(std::vector<PABar>(bars.begin(),bars.begin()+20),0);
        auto catchup=calculate(bars,20);
        equal(catchup,calculate(bars,0));
        // Chart history cap drops oldest candles while total count stays fixed.
        auto shifted=bars; shifted.erase(shifted.begin()); shifted.push_back(a);
        auto rolling=calculate(shifted,int(bars.size()),1060);
        equal(rolling,calculate(shifted,0,1060));
        auto shrink=std::vector<PABar>(bars.begin(),bars.begin()+30);
        auto smaller=calculate(shrink,int(bars.size()));
        equal(smaller,calculate(shrink,0));
    }
    std::cout<<"PA Reversal: "<<checks<<" checks passed\n";
}
