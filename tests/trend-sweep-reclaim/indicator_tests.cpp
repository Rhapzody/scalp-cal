#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <string>
#include <vector>
using string=std::string; using datetime=long;
#define MathIsValidNumber std::isfinite
#define MathAbs std::abs
#define MathMax std::max
#define MathMin std::min
template<class T> void ZeroMemory(T& v) { v=T{}; }
template<class T> int ArrayResize(std::vector<T>& a,int n) { a.resize(n);return n; }
template<class T> int ArraySize(const std::vector<T>& a) { return int(a.size()); }
template<class T> void ArraySetAsSeries(const std::vector<T>&,bool) {}
template<class T> void ArrayInitialize(std::vector<T>& a,T v) { std::fill(a.begin(),a.end(),v); }
bool IsStopped() { return false; }
#include "SweepCore.mqh"
using MqlRates=TSBar;
constexpr int PERIOD_M5=300,SERIES_SYNCHRONIZED=1,OBJPROP_TEXT=2,clrIndianRed=3,clrSeaGreen=4;
constexpr double EMPTY_VALUE=std::numeric_limits<double>::max();
string _Symbol="TEST",g_prefix="TEST_",status;
int InpHistoryBars=3000,InpVisiblePlans=20;
bool InpPopupAlert=true,g_ready=false,synchronized=true,replayOK=true;
long g_last=0,g_first=0,g_alert=0;
TSConfig g_config;
std::vector<TSBar> g_bars,feed;
std::vector<TSSignal> g_signals,next;
std::vector<double> Buy,Sell,Stop,Target,Level,Obstacle,SignalATR;
int reads=0,alerts=0,lines=0,deletes=0,checks=0;
int CopyRates(const string&,int,int,int,std::vector<MqlRates>& out) {++reads;out=feed;return int(out.size());}
bool SeriesInfoInteger(const string&,int,int) {return synchronized;}
void ObjectsDeleteAll(int,const string&) {++deletes;lines=0;}
void ObjectSetString(int,const string&,int,const string& text) {status=text;}
void TSLine(const string&,long,double,int) {++lines;}
template<class... T> void Alert(T... args) {++alerts;}
bool MockReplay(const TSConfig&,const std::vector<TSBar>&,int,long,std::vector<TSSignal>& out) {out=next;return replayOK;}
#define TSReplay MockReplay
#include "indicator_under_test.hpp"
#undef TSReplay
void check(bool ok,const char* why) {++checks;if(!ok){std::cerr<<"FAIL: "<<why<<'\n';std::exit(1);}}
TSSignal entry(long t,int direction) {TSSignal s{};s.time=t;s.direction=direction;s.price=100;s.stop=99;s.target=102;s.trigger=99.5;s.obstacle=105;s.atr=1;return s;}
int calculate(const std::vector<datetime>& time,int prev) {
 for(auto p:{&Buy,&Sell,&Stop,&Target,&Level,&Obstacle,&SignalATR})p->resize(time.size(),EMPTY_VALUE);
 std::vector<double> price(time.size());std::vector<long> volume(time.size());std::vector<int> spread(time.size());
 return OnCalculate(int(time.size()),prev,time,price,price,price,price,volume,volume,spread);
}
void add(std::vector<datetime>& times,long t) {times.push_back(t);feed.push_back({t,100,101,99,100});}
int main() {
 g_config.slow=1;g_config.room_bars=2;g_config.atr_length=2;
 std::vector<datetime> times;for(int i=0;i<8;i++)add(times,3000+i*300);
 next={entry(4800,1)};
 check(calculate(times,0)==8,"initial publish");
 check(Buy[6]==100 && Sell[6]==EMPTY_VALUE && Stop[6]==99 && Target[6]==102,"signal and plan mapped to actual closed M5");
 check(Buy[7]==EMPTY_VALUE && Sell[7]==EMPTY_VALUE,"forming bar blank");
 check(alerts==0 && lines==2,"attach displays plans without historical alert");
 check(calculate(times,8)==8 && reads==1,"same-bar ticks reuse outputs");
 add(times,5400);next.push_back(entry(5100,-1));
 check(calculate(times,8)==9 && alerts==1 && Sell[7]==100,"new closed signal alerts once");
 calculate(times,0);check(alerts==1,"history reset does not duplicate popup");
 InpVisiblePlans=0;calculate(times,0);check(lines==0 && Buy[6]==100,"hiding plans preserves buffers");
 add(times,5700);synchronized=false;
 check(calculate(times,9)==0 && Buy[6]==EMPTY_VALUE && lines==0,"unavailable history clears stale output");
 synchronized=true;next.push_back(entry(5400,1));
 check(calculate(times,0)==10 && alerts==2,"history retry publishes fresh signal");
 add(times,6300);next.push_back(entry(5700,-1));
 calculate(times,10);check(alerts==2,"reconnect does not alert old missed bars");
 check(TSChartIndex(times,int(times.size()),6000)==-1,"missing candle not mapped to neighbour");
 check(TSChartIndex(times,int(times.size()),5400)==8,"exact timestamp lookup");
 replayOK=false;check(calculate(times,0)==0 && Stop[6]==EMPTY_VALUE,"failed replay does not show old plan");
 check(calculate({},0)==0,"empty chart safe");
 std::cout<<"Trend Sweep indicator: "<<checks<<" checks passed\n";
}
