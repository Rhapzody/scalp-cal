#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <random>
#include <string>
#include <vector>
using string=std::string;
#define MathIsValidNumber std::isfinite
#define MathAbs std::abs
#define MathMax std::max
#define MathMin std::min
#define MathRound std::round
#define MathFloor std::floor
double NormalizeDouble(double v,int d) { double p=std::pow(10.,d); return std::round(v*p)/p; }
template<class T> void ZeroMemory(T& v) { v=T{}; }
template<class T> int ArrayResize(std::vector<T>& a,int n) { a.resize(n); return n; }
template<class T> int ArraySize(const std::vector<T>& a) { return int(a.size()); }
bool IsStopped() { return false; }
#include "TradePlanCore.mqh"
int checks=0;
void check(bool ok,const char* message) { ++checks; if(!ok) { std::cerr<<"FAIL: "<<message<<'\n'; std::exit(1); } }
bool near(double a,double b) { return std::abs(a-b)<1e-8; }
RPConfig config() {
    RPConfig c{}; c.macd={12,26,9,0,14,MS_PRICE,0,.01,MS_HISTOGRAM_COLOR};
    c.zones=RP_BOTH; c.strength=RP_FVG_OR_DISPLACEMENT;
    c.min_leg_atr=1; c.min_fvg_atr=.1; c.min_efficiency=.65; c.min_body_ratio=.5;
    c.max_leg_bars=30; c.zone_life_bars=144; c.confirmation_bars=30; c.max_close_tail_ratio=.25;
    return c;
}
int main() {
    EACandidate candidate{}; candidate.signal.direction=1; candidate.pattern_low=99; candidate.pattern_high=101;
    check(near(EAPatternStop(candidate,0,.01,.01,2),98.99),"buy stop strictly below pattern even zero buffer");
    check(near(EAPatternStop(candidate,20,.01,.01,2),98.8),"buy point buffer");
    candidate.signal.direction=-1;
    check(near(EAPatternStop(candidate,0,.01,.01,2),101.01),"sell stop above pattern");
    candidate.pattern_high=101.003;
    check(near(EAPatternStop(candidate,0,.001,.005,3),101.01),"sell rounds outward to tick grid");
    candidate.signal.direction=1; candidate.pattern_low=99.003;
    check(near(EAPatternStop(candidate,0,.001,.005,3),98.995),"buy rounds outward to tick grid");
    check(EAPatternStop(candidate,-1,.01,.01,2)==0,"negative buffer rejected");
    std::vector<EATarget> targets{{1,100,200,105},{1,120,220,102},{-1,130,230,98},
                                {1,140,2000,101},{-1,150,250,95},{1,160,260,102}};
    check(EANextTarget(true,100,1000,targets)==5,"nearest high, newest pivot breaks price tie");
    check(EANextTarget(false,100,1000,targets)==2,"nearest low");
    check(EANextTarget(true,105,1000,targets)==-1,"no TP in price discovery; equal target not ahead");
    check(EANextTarget(false,94,1000,targets)==-1,"no downside target");
    check(EANextTarget(true,100,210,targets)==0,"future confirmed levels excluded");
    check(EAMinimumRR(true,100,99,101,1),"exact one-to-one accepted");
    check(!EAMinimumRR(true,100,99,100.99,1),"below one-to-one rejected");
    check(!EAMinimumRR(true,100,99,101,.9),"minimum cannot be disabled below one");
    check(!EAMinimumRR(false,100,99,101,1),"wrong stop geometry rejected");

    check(near(EATargetPrice(true,102,0,.01,.01,2),102),"zero TP buffer preserves target");
    check(near(EATargetPrice(true,102,20,.01,.01,2),101.8),"buy TP buffer moves toward entry");
    check(near(EATargetPrice(false,98,20,.01,.01,2),98.2),"sell TP buffer moves toward entry");
    check(near(EATargetPrice(true,102,1,.001,.005,3),101.995),"buy TP rounds toward entry");
    check(near(EATargetPrice(false,98,1,.001,.005,3),98.005),"sell TP rounds toward entry");
    check(EATargetPrice(true,102,-1,.01,.01,2)==0,"negative TP buffer rejected");
    check(EATargetPrice(true,102,1e308,100,.01,2)==0,"overflow TP buffer rejected");

    std::mt19937 random(452);
    std::vector<MSBar> one,five;
    double price=100;
    for(int i=0;i<3000;i++) {
        double drift=(i/25)%2==0 ? .22 : -.19;
        double close=price+drift+(int(random()%41)-20)*.04;
        one.push_back({3000+i*60,price,std::max(price,close)+.07,std::min(price,close)-.07,close});
        price=close;
        if(i%5==4) {
            MSBar b=one[i-4]; b.close=one[i].close;
            for(int j=i-3;j<=i;j++) { b.high=std::max(b.high,one[j].high); b.low=std::min(b.low,one[j].low); }
            five.push_back(b);
        }
    }
    auto c=config(); RPState state; std::vector<RPEntry> entries;
    check(RPReplay(state,c,one,int(one.size()),five,int(five.size()),one.back().time+60,entries),"indicator replay");
    check(!entries.empty(),"fixture has actual indicator signals");
    string reason;
    for(const auto& entry:entries) {
        long horizon=entry.time+60;
        check(EABuildContext(c,one,int(one.size()),five,int(five.size()),horizon,candidate,targets,reason),
              "build tradable context for every indicator signal");
        check(candidate.signal.time==entry.time && candidate.signal.direction==entry.direction &&
              candidate.signal.trigger==entry.trigger,"EA signals match indicator exactly");
        double low=1e10,high=-1e10;
        for(const auto& bar:one) if(bar.time>=candidate.pattern_start && bar.time<=entry.time) {
            low=std::min(low,bar.low); high=std::max(high,bar.high);
        }
        check(candidate.pattern_low==low && candidate.pattern_high==high,"stop uses entire reversal pattern incl signal candle");
        for(const auto& t:targets) check(t.known_time<=horizon,"no future M5 target");
        auto fullCandidate=candidate; auto fullTargets=targets;
        std::vector<MSBar> o,f;
        for(const auto& b:one) if(b.time+60<=horizon) o.push_back(b);
        for(const auto& b:five) if(b.time+300<=horizon) f.push_back(b);
        check(EABuildContext(c,o,int(o.size()),f,int(f.size()),horizon,candidate,targets,reason),"truncated context");
        check(candidate.pattern_low==fullCandidate.pattern_low && candidate.pattern_high==fullCandidate.pattern_high &&
              candidate.pattern_start==fullCandidate.pattern_start,"SL immune to future candles");
        check(targets.size()==fullTargets.size(),"TP catalog immune to future candles");
        for(size_t k=0;k<targets.size();k++) check(targets[k].price==fullTargets[k].price &&
              targets[k].known_time==fullTargets[k].known_time,"same confirmed target prices");
    }
    long emptyHorizon=one[100].time+60;
    bool actual=false; for(const auto& e:entries) if(e.time+60==emptyHorizon) actual=true;
    if(!actual) check(!EABuildContext(c,one,int(one.size()),five,int(five.size()),emptyHorizon,candidate,targets,reason),
                      "historical signals never used as current entries");
    c.m1_break_buffer_points=2; c.m5_break_buffer_points=3;
    c.touch_mode=RP_TOUCH_CLOSE; c.max_close_tail_ratio=.3;
    check(RPReplay(state,c,one,int(one.size()),five,int(five.size()),one.back().time+60,entries),"tuned indicator replay");
    check(!entries.empty(),"tuned fixture has signals");
    for(const auto& entry:entries) {
        check(EABuildContext(c,one,int(one.size()),five,int(five.size()),entry.time+60,candidate,targets,reason),
              "tuned EA reconstructs every indicator pattern");
        check(candidate.signal.trigger==entry.trigger && candidate.signal.time==entry.time && candidate.signal.direction==entry.direction,
              "tuned EA and indicator agree");
        double low=1e10,high=-1e10;
        for(const auto& bar:one) if(bar.time>=candidate.pattern_start && bar.time<=entry.time) {
            low=std::min(low,bar.low); high=std::max(high,bar.high);
        }
        check(candidate.pattern_low==low && candidate.pattern_high==high,"buffer does not alter pattern extrema");
    }
    std::cout<<"MACD Zone Trader plan: "<<checks<<" checks passed\n";
}
