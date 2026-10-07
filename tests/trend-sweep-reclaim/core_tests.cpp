#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>
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
#include "SweepCore.mqh"
#ifdef TEST_TRADE_PLAN
#include "TradePlanCore.mqh"
#endif
int checks=0;
void check(bool ok,const char* why) { ++checks; if(!ok) { std::cerr<<"FAIL: "<<why<<'\n'; std::exit(1); } }
bool near(double a,double b) { return std::abs(a-b)<1e-8; }
TSConfig config() {
 TSConfig c{}; c.fast=50;c.slow=200;c.atr_length=14;c.lookback=8;c.room_bars=40;c.cooldown=6;
 c.min_sweep_atr=.05;c.max_sweep_atr=.8;c.min_body=.35;c.min_close_location=.65;c.max_extension_atr=2;
 c.stop_atr=.1;c.point=.01;c.min_stop_atr=.5;c.max_stop_atr=2.5;c.target_rr=2;c.room_buffer_atr=.1;
 return c;
}
TSBar mirror(TSBar b) { return {b.time,200-b.open,200-b.low,200-b.high,200-b.close}; }
std::vector<TSBar> setup() {
 std::vector<TSBar> b;
 for(int i=0;i<40;i++) b.push_back({3000+i*300,101,101.5,100.5,101});
 b[0].high=105;
 b.push_back({15000,100.5,101.3,100.2,101.2}); return b;
}
TSState primed(int direction=1) {
 TSState s;TSReset(s);s.count=600;s.fast=101;s.slow=100;s.previous_slow=99.9;s.atr=1;s.previous_close=101;s.previous_time=14700;
 if(direction==-1) {s.fast=99;s.previous_slow=100.1;s.previous_close=99;}
 return s;
}
TSSignal run(TSConfig c,std::vector<TSBar> bars,TSState s=primed()) { TSSignal out; TSProcess(s,c,bars,40,out); return out; }
bool same(TSSignal a,TSSignal b) { return a.direction==b.direction && a.time==b.time && a.price==b.price && a.stop==b.stop && a.target==b.target && a.obstacle==b.obstacle && a.atr==b.atr && a.trigger==b.trigger; }
int main() {
 auto c=config();check(TSValid(c),"default valid");check(TSWarmup(c)==600,"EMA warmup");
 auto b=setup();
 for(int direction:{1,-1}) {
  auto path=b;if(direction==-1) for(auto& x:path)x=mirror(x);
  auto s=primed(direction);auto signal=run(c,path,s);
  check(signal.direction==direction,"symmetric trend sweep signal");
  check(near(signal.stop,direction==1?100.1:99.9),"stop beyond sweep plus ATR buffer");
  check(near(direction*(signal.target-signal.price),2*direction*(signal.price-signal.stop)),"planned two R");
  check(signal.atr==1,"ATR captured before signal candle");
  auto filtered=c;filtered.side=direction==1?TS_SELL_ONLY:TS_BUY_ONLY;
  check(run(filtered,path,s).direction==0,"opposite-side filter");
  s.last_signal=35;check(run(c,path,s).direction==0,"cooldown suppresses repeated setup");
  s=primed(direction);s.count=599;check(run(c,path,s).direction==0,"no signal before warmup");
  s=primed(direction);s.previous_time-=300;check(run(c,path,s).direction==0,"session gap blocks sweep window");
  s=primed(direction);s.previous_slow=s.slow;check(run(c,path,s).direction==0,"flat slow EMA rejected");
 }
 auto altered=b;altered[40].low=100.5;check(run(c,altered).direction==0,"equal low is not sweep");
 altered=b;altered[40].low=99.5;check(run(c,altered).direction==0,"oversized sweep rejected");
 altered=b;altered[40].close=100.5;check(run(c,altered).direction==0,"must reclaim level with close");
 altered=b;altered[40].open=101.2;check(run(c,altered).direction==0,"doji body rejected");
 altered=b;altered[40].high=104;check(run(c,altered).direction==0,"weak close location rejected");
 altered=b;altered[0].high=102;check(run(c,altered).direction==0,"insufficient prior resistance room");
 auto tuned=c;tuned.target_rr=4;check(run(tuned,b).direction==0,"higher target rejected when no room");
 tuned=c;tuned.stop_points=10;check(near(run(tuned,b).stop,100),"point SL buffer adds to ATR buffer");
 auto s=primed();s.slow=102;check(run(c,b,s).direction==0,"against trend rejected");
 tuned=c;tuned.start_hour=9;tuned.end_hour=17;
 check(!TSHourAllowed(tuned,8*3600) && TSHourAllowed(tuned,9*3600) && !TSHourAllowed(tuned,17*3600),"session boundaries");
 tuned.start_hour=22;tuned.end_hour=3;
 check(TSHourAllowed(tuned,23*3600) && TSHourAllowed(tuned,2*3600) && !TSHourAllowed(tuned,4*3600),"overnight session");
 for(double invalid:{-1.,std::numeric_limits<double>::infinity(),std::numeric_limits<double>::quiet_NaN()}) {
  tuned=c;tuned.stop_points=invalid;check(!TSValid(tuned),"invalid stop buffer");
  tuned=c;tuned.target_rr=invalid;check(!TSValid(tuned),"invalid target RR");
 }
 tuned=c;tuned.target_rr=.9;check(!TSValid(tuned),"RR below one forbidden");
 tuned=c;tuned.fast=200;check(!TSValid(tuned),"EMA ordering enforced");
 tuned=c;tuned.room_bars=2;check(!TSValid(tuned),"room window cannot be shorter than sweep");
 s=primed();TSSignal out;altered=b;altered[40].close=999;
 check(!TSProcess(s,c,altered,40,out) && s.count==0 && out.direction==0,"bad OHLC resets warmup");
 // Actual EMA/ATR replay, deterministic artificial price path (not a performance backtest).
 std::vector<TSBar> history;
 for(int cycle=0;cycle<4;cycle++) {
  for(int i=0;i<640;i++) {
   double p=i<600 ? 80+i*.035 : 101;
   history.push_back({3000+long(history.size())*300,p,p+.5,p-.5,p});
  }
  history[history.size()-40].high=105;
  history.push_back({3000+long(history.size())*300,100.5,101.3,100.2,101.2});
 }
 std::vector<TSSignal> full;
 check(TSReplay(c,history,int(history.size()),history.back().time+300,full),"real engine replay");
 check(!full.empty(),"real engine produces signals");
 TSState stream;TSReset(stream);std::vector<TSSignal> streamed;
 for(int i=0;i<int(history.size());i++) {TSProcess(stream,c,history,i,out);if(out.direction)streamed.push_back(out);}
 check(streamed.size()==full.size(),"stream count agrees");
 for(size_t i=0;i<full.size();i++) check(same(full[i],streamed[i]),"stream values agree");
 for(int n=100;n<int(history.size());n+=29) {
  long cut=history[n-1].time+300;std::vector<TSSignal> bounded,truncated,expected;
  check(TSReplay(c,history,int(history.size()),cut,bounded),"bounded replay with future data present");
  std::vector<TSBar> prefix(history.begin(),history.begin()+n);
  check(TSReplay(c,prefix,n,cut,truncated),"prefix replay");
  for(auto e:full)if(e.time+300<=cut)expected.push_back(e);
  check(bounded.size()==truncated.size() && bounded.size()==expected.size(),"no future signal leakage");
  for(size_t i=0;i<bounded.size();i++)check(same(bounded[i],truncated[i])&&same(bounded[i],expected[i]),"prior signal immutable with fixed seed");
 }
#ifdef TEST_TRADE_PLAN
 EACandidate candidate;std::vector<EATarget> targets;string reason;
 for(auto e:full) {
  check(EABuildContext(c,history,int(history.size()),e.time+300,candidate,targets,reason),"EA accepts actual indicator signal");
  check(same(e,candidate.signal) && targets.size()==1 && targets[0].price==e.obstacle,"EA indicator levels match");
  double stop=TSStop(candidate,.05,2);
  check(e.direction==1 ? stop<candidate.pattern_low && stop<=e.stop+1e-8 : stop>candidate.pattern_high && stop>=e.stop-1e-8,"tick rounding remains outside pattern");
 }
 check(!EABuildContext(c,history,int(history.size()),history[100].time+300,candidate,targets,reason),"no old entry reused");
 check(!EAMinimumRR(true,100,99,102,.5),"execution minimum RR cannot fall below one");
#endif
 std::cout<<"Trend Sweep core/plan: "<<checks<<" checks passed; "<<full.size()<<" synthetic signals (not market win rate)\n";
}
