#include <algorithm>
#include <cmath>
#include <cstring>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <string>
#include <vector>
#define MathIsValidNumber std::isfinite
#define MathAbs std::abs
#define MathMax std::max
template<class T> void ZeroMemory(T& value) { std::memset(&value,0,sizeof(value)); }
template<class T> int ArrayResize(std::vector<T>& a,int n) { a.resize(n); return n; }
bool IsStopped() { return false; }
#include "PullbackCore.mqh"
using datetime=long long;
constexpr double EMPTY_VALUE=std::numeric_limits<double>::max();
constexpr int PERIOD_M1=60;
int _Period=60;
std::string _Symbol="TEST",g_prefix="test_",status;
std::vector<double> BuyBuffer,SellBuffer,SignalTime,TriggerPrice,ZoneLower,ZoneUpper,SRPrice,Quality;
std::vector<RPEntry> g_entries;
long g_last_m1=0,g_first_chart=0,g_alert_time=0,currentTime=3600;
bool g_ready=false,InpPopupAlert=true,loadOK=true,renderOK=true;
int loads=0,renders=0,deletes=0,alerts=0,checks=0;
template<class T> void ArraySetAsSeries(const std::vector<T>&,bool) {}
template<class T> int ArraySize(const std::vector<T>& a) { return int(a.size()); }
int PeriodSeconds(int period) { return period; }
long iTime(const std::string&,int,int) { return currentTime; }
std::string TimeToString(datetime t) { return std::to_string(t); }
std::string KindText(int) { return "zone"; }
void Status(const std::string& text) { status=text; }
void ObjectsDeleteAll(int,const std::string&) { ++deletes; }
template<class... T> void Alert(T... args) { ++alerts; }
bool LoadAndReplay(long) { ++loads; return loadOK; }
bool Render(long) { ++renders; return renderOK; }
void ClearOutput() {
    for(auto p:{&BuyBuffer,&SellBuffer,&SignalTime,&TriggerPrice,&ZoneLower,&ZoneUpper,&SRPrice,&Quality})
        std::fill(p->begin(),p->end(),EMPTY_VALUE);
}
#include "indicator_under_test.hpp"
void check(bool value,const char* message) {
    ++checks;
    if(!value) { std::cerr<<"FAIL: "<<message<<'\n'; std::exit(1); }
}
int calculate(const std::vector<datetime>& time,int prev) {
    for(auto p:{&BuyBuffer,&SellBuffer,&SignalTime,&TriggerPrice,&ZoneLower,&ZoneUpper,&SRPrice,&Quality})
        p->resize(time.size(),EMPTY_VALUE);
    std::vector<double> price(time.size(),1);
    std::vector<long> volume(time.size()); std::vector<int> spread(time.size());
    return OnCalculate(int(time.size()),prev,time,price,price,price,price,volume,volume,spread);
}
RPEntry entry(long time,int side) {
    RPEntry e{}; e.time=time; e.direction=side; e.price=12; e.trigger=11.5;
    e.lower=10; e.upper=11; e.sr=11; e.kind=1; e.quality=2;
    return e;
}
int main() {
    std::vector<datetime> times{3420,3480,3540,3600};
    g_entries={entry(3540,1)};
    check(calculate(times,0)==4,"first calculation");
    check(BuyBuffer[2]==12 && SellBuffer[2]==EMPTY_VALUE && SignalTime[2]==3540,"signal mapped to actual M1 candle");
    check(BuyBuffer[3]==EMPTY_VALUE && SellBuffer[3]==EMPTY_VALUE,"forming M1 has no signal");
    check(alerts==0,"no historical popup on attach");
    check(calculate(times,4)==4 && loads==1 && renders==1,"same minute ticks reuse outputs");
    times.push_back(3660); currentTime=3660; g_entries.push_back(entry(3600,-1));
    check(calculate(times,4)==5,"new M1 calculation");
    check(SellBuffer[3]==12 && alerts==1,"new closed signal popup");
    calculate(times,5); check(alerts==1,"tick does not repeat alert");
    calculate(times,0); check(alerts==1,"history reset does not repeat alert");
    loadOK=false; currentTime=3720; times.push_back(3720);
    check(calculate(times,5)==0 && deletes==1,"history unavailable clears stale objects and requests retry");
    check(BuyBuffer[2]==EMPTY_VALUE && SellBuffer[3]==EMPTY_VALUE,"history unavailable clears stale buffers");
    loadOK=true; g_entries.push_back(entry(3660,1));
    check(calculate(times,0)==6 && alerts==2,"successful history retry publishes once");
    currentTime=3780; times.push_back(3780); g_entries.push_back(entry(3720,1)); renderOK=false;
    check(calculate(times,6)==0 && alerts==2,"drawing error does not emit alert");
    renderOK=true; check(calculate(times,0)==7 && alerts==3,"drawing retry succeeds without lost alert");
    _Period=300; times={3300,3600}; currentTime=3780;
    g_entries={entry(3600,1),entry(3720,-1)};
    check(calculate(times,0)==2,"M5 chart supported");
    check(BuyBuffer[1]==EMPTY_VALUE && SellBuffer[1]==12 && SignalTime[1]==3720,
          "M5 chart buffers retain latest M1 event, even in current M5 candle");
    int previousLoads=loads;
    currentTime=3840; g_entries.push_back(entry(3780,1));
    calculate(times,2);
    check(loads==previousLoads+1,"M5 chart updates at M1 boundary without new M5 bar");
    check(SignalTime[1]==3780,"M5 receives new M1 event");
    check(ChartBar(3299,times,2)==-1,"ignore signal before loaded chart");
    check(ChartBar(3900,times,2)==-1,"ignore signal outside chart interval");
    _Period=60;
    std::vector<datetime> gaps{3300,3420,3480};
    check(ChartBar(3360,gaps,3)==-1,"do not map into missing chart candle");
    check(ChartBar(3420,gaps,3)==1,"exact timestamp maps correctly");
    currentTime=0;
    check(calculate(gaps,0)==0,"missing M1 clock returns retry");
    check(calculate({},0)==0,"empty chart");
    std::cout<<"MACD Zone Pullback indicator: "<<checks<<" checks passed\n";
}
