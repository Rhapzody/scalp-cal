#include <cmath>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>
using string=std::string;
#define MathIsValidNumber std::isfinite
#define MathMax std::max
#define MathMin std::min
#define MathAbs std::abs
#define MathRound std::round
#define MathFloor std::floor
double NormalizeDouble(double v,int d) { double p=std::pow(10.,d); return std::round(v*p)/p; }
template<class T> void ZeroMemory(T& v) { v=T{}; }
template<class T> int ArrayResize(std::vector<T>& a,int n) { a.resize(n); return n; }
template<class T> int ArraySize(const std::vector<T>& a) { return int(a.size()); }
#include "PATradeCore.mqh"
int checks=0;
void check(bool ok,const char* msg) { ++checks; if(!ok) { std::cerr<<"FAIL: "<<msg<<'\n'; std::exit(1); } }

PATradeConfig cfg() { PATradeConfig c{}; c.min_bars=3; c.ema_period=20; c.atr_length=14; c.max_sl_ema_atr=1.5; c.max_retrace_ema_atr=.25; c.max_ema_penetration_atr=.50; c.sl_buffer_points=15; c.min_rr=1; c.point=.01; c.tick=.01; return c; }

int main() {
    check(PASLFromEMAValid(100,98,2,1.5),"EMA distance inside ATR envelope");
    check(!PASLFromEMAValid(100,96,2,1.5),"EMA distance outside ATR envelope");
    PABar emaBuy{100,102,99.6,101}; PABar emaPrev{100,100.2,99.8,99.9};
    check(PAEMAReversalValid(true,emaBuy,emaPrev,100,100,2,.25,.50),"buy wick near EMA and closes above");
    PABar deepBuy{100,103,97,101};
    check(!PAEMAReversalValid(true,deepBuy,emaPrev,100,100,2,.25,.50),"buy wick too far below EMA rejected");
    PABar reclaimBuy{99.5,102,99.0,101.2};
    check(PAEMAReversalValid(true,reclaimBuy,emaPrev,100,100,2,.25,.50),"buy EMA reclaim accepted");
    PABar farAfterPierce{101,104,102.5,103};
    check(!PAEMAReversalValid(true,farAfterPierce,emaPrev,100,100,2,.25,.50),"buy rebound too far from EMA rejected");
    PABar emaSell{100,100.4,98,99}; PABar emaSellPrev{100,100.2,99.8,100.1};
    check(PAEMAReversalValid(false,emaSell,emaSellPrev,100,100,2,.25,.50),"sell wick near EMA and closes below");
    check(PARRValid(true,100,98,102,1),"exact buy RR one accepted");
    check(!PARRValid(true,100,98,101.99,1),"buy RR below one rejected");
    check(PARRThreshold(true,98,102)==100,"buy midpoint threshold");
    check(PARRThreshold(false,102,98)==100,"sell midpoint threshold");
    check(PACapTPAtOneR(true,100,98,105)==102,"buy swing TP capped at one R");
    check(PACapTPAtOneR(false,100,102,95)==98,"sell swing TP capped at one R");
    std::vector<PAConfirmedSwing> swings={{1,1,101}};
    check(PANearestTarget(true,100,swings)==0,"swing target remains available before engulf close");
    check(PANearestTarget(true,101,swings)==-1,"swing target invalidated when engulf closes through it");
    std::vector<PABar> legBars={{100,102,99,101},{101,103,100,102},{102,104,100.5,101},{101,105,100,103}};
    std::vector<double> legEma={100,100,100,100};
    check(PALegEMASequenceValid(true,legBars,legEma,3,3),"bullish reversal keeps earlier retrace candles above EMA");
    check(!PALegEMASequenceValid(false,legBars,legEma,3,3),"bearish reversal rejects earlier retrace candles above EMA");
    std::vector<PABar> bars={
      {100,101,99,99.5},{99.5,100,98.5,99},{99,99.5,97.5,98},
      {98,100.5,97.8,100.2},{99.0,100.3,98.8,99.2},{99.0,100.0,98.9,99.3},
      {99.3,102.0,99.2,101.5},{99.9,100.4,98.8,99.0}
    };
    auto c=cfg(); PASetup s{}; string reason;
    bool built=PABuildLatest(c,bars,int(bars.size()),7,2,s,reason);
    check(built,"PA signal with three-bar prior leg");
    check(s.direction==-1 && s.signal_index==7,"sell reversal direction/index");
    check(s.tp<100 && s.sl>100,"next confirmed low target and pattern stop");
    check(s.rr_entry<1 && s.followup_allowed,"invalid initial RR enables one-bar recovery");
    auto no_target=std::vector<PABar>(bars.begin(),bars.begin()+4);
    check(!PABuildLatest(c,no_target,int(no_target.size()),3,2,s,reason),"first reversal has no prior profit swing");
    std::cout<<"PA Reversal Trader core: "<<checks<<" checks passed\n";
}
