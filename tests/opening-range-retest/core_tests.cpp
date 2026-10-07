#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <vector>
#define MathIsValidNumber std::isfinite
#define MathAbs std::abs
#define MathMax std::max
#define MathMin std::min
template<class T> void ZeroMemory(T& v){v=T{};}
template<class T> int ArrayResize(std::vector<T>& a,int n){a.resize(n);return n;}
template<class T> int ArraySize(const std::vector<T>& a){return int(a.size());}
bool IsStopped(){return false;}
#include "OpeningCore.mqh"
int checks=0;
void check(bool ok,const char* why){++checks;if(!ok){std::cerr<<"FAIL: "<<why<<'\n';std::exit(1);}}
ORConfig config(){
 ORConfig c{}; c.start_hour=8;c.start_minute=0;c.range_minutes=30;c.atr_length=2;c.max_retest_bars=12;
 c.min_range_points=0;c.side=OR_BOTH;c.retest_mode=OR_RETEST_WICK;c.min_break_atr=.05;c.max_break_atr=1.5;
 c.min_body_ratio=.2;c.min_close_location=.6;c.stop_buffer_atr=.1;c.point=.01;c.min_stop_atr=.1;c.max_stop_atr=3;c.target_rr=2;return c;
}
std::vector<ORBar> day(bool sell=false){
 std::vector<ORBar>b;long t=8*3600;for(int i=0;i<6;i++)b.push_back({t+i*300,100,100.4,99.6,100});
 if(!sell)b.push_back({t+1800,100.1,101.2,99.9,101});else b.push_back({t+1800,99.9,100.1,98.8,99});
 if(!sell)b.push_back({t+2100,101,101.3,100.4,101.1});else b.push_back({t+2100,99,99.6,98.7,98.9});return b;
}
int main(){
 auto c=config();check(ORConfigValid(c),"default config valid");check(ORWarmup(c)==8,"warmup");
 for(int d:{1,-1}){
  auto b=day(d==-1);ORState s;ORReset(s);ORSignal out;
  for(int i=0;i<int(b.size());i++)ORProcess(s,c,b,i,out);
  check(out.direction==d,"breakout then later retest signal");check(out.retest_time==b.back().time,"signal uses retest close");check(out.breakout_time==b[6].time,"breakout recorded");
  auto f=c;f.side=d==1?OR_SELL_ONLY:OR_BUY_ONLY;ORState fs;ORReset(fs);ORSignal x;
  for(int i=0;i<int(b.size());i++)ORProcess(fs,f,b,i,x);check(x.direction==0,"side filter");
 }
 auto b=day();ORState s;ORReset(s);ORSignal x;for(int i=0;i<int(b.size());i++)ORProcess(s,c,b,i,x);check(x.direction==1,"baseline signal");
 auto invalid=c;invalid.target_rr=.9;check(!ORConfigValid(invalid),"RR below one rejected");invalid=c;invalid.range_minutes=31;check(!ORConfigValid(invalid),"range aligns to M5");invalid=c;invalid.stop_buffer_points=-1;check(!ORConfigValid(invalid),"negative buffer rejected");
 std::vector<ORBar> history;for(int d=0;d<4;d++){auto one=day();for(auto& q:one)q.time+=d*86400;history.insert(history.end(),one.begin(),one.end());}
 std::vector<ORSignal> full;check(ORReplay(c,history,int(history.size()),history.back().time+300,full),"replay");check(full.size()==4,"four independent sessions");
 std::cout<<"Opening Range Retest core: "<<checks<<" checks passed\n";
}
