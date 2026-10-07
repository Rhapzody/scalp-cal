#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <random>
#include <string>
#include <vector>
#define MathIsValidNumber std::isfinite
#define MathAbs std::abs
template<class A,class B> double MathMax(A a,B b) { return std::max(double(a),double(b)); }
#include "../../MQL5/Indicators/MACDSwingCount/SwingCore.mqh"
using datetime=long long;
using string=std::string;
constexpr double EMPTY_VALUE=std::numeric_limits<double>::max();
template<class T> void ArrayInitialize(std::vector<T>& a,double v) { std::fill(a.begin(),a.end(),v); }
template<class T> int ArrayResize(std::vector<T>& a,int n) { a.resize(n); return n; }
template<class T> int ArraySize(const std::vector<T>& a) { return int(a.size()); }
template<class T> void ArraySetAsSeries(const std::vector<T>&,bool) {}
bool stop_requested=false;
bool IsStopped() { return stop_requested; }
int renders=0,reports=0;
bool last_report_reset=false;
void RenderSwings() { renders++; }
void ReportLatest(bool reset,int) { reports++; last_report_reset=reset; }
#include "indicator_under_test.hpp"

int checks=0;
void check(bool condition,const char* reason)
{
    ++checks;
    if(!condition) { std::cerr<<"FAIL: "<<reason<<'\n'; std::exit(1); }
}
bool near(double a,double b)
{
    if(a==EMPTY_VALUE || b==EMPTY_VALUE) return a==b;
    return std::abs(a-b)<=1e-10*(1+std::abs(b));
}
MSConfig config() { return {12,26,9,0,14,MS_PRICE,0,0.01,MS_MACD_CROSS}; }
MSBar bar(int i,double h,double l,double c) { return {1000+i*60,c,h,l,c}; }
MSEvent detect(MSEngine& s,int i,double histogram,double h=110,double l=90)
{
    s.histogram=histogram;
    MSEvent e{};
    MSDetectSwing(bar(i,h,l,100),i,s,e);
    return e;
}
std::vector<int> colorEvents(const std::vector<double>& histogram)
{
    MSEngine s; MSReset(s);
    std::vector<int> events;
    for(size_t i=0;i<histogram.size();i++) {
        s.has_previous_histogram=i>0;
        s.previous_histogram=i>0 ? histogram[i-1] : 0;
        s.histogram=histogram[i];
        s.threshold=1000; // Cross-distance filters must not suppress color turns.
        MSEvent event{};
        MSDetectSwing(bar(int(i),110+i,90-i,100),int(i),s,event,MS_HISTOGRAM_COLOR);
        events.push_back(event.type);
    }
    return events;
}
std::vector<std::vector<double>*> buffers()
{
    return {&SwingHigh,&SwingLow,&EventType,&EventPrice,&EventSwingTime,&EventClass,
            &HighConfirmation,&LowConfirmation,&MACDValues,&SignalValues,&HistogramValues,&ThresholdValues};
}
using Snapshot=std::vector<std::vector<double>>;
Snapshot snapshot()
{
    Snapshot out;
    for(auto p:buffers()) out.push_back(*p);
    return out;
}
Snapshot calculate(const std::vector<MSBar>& bars,int prev)
{
    std::vector<datetime> times;
    std::vector<double> open,high,low,close;
    for(auto b:bars) { times.push_back(b.time); open.push_back(b.open); high.push_back(b.high); low.push_back(b.low); close.push_back(b.close); }
    int n=int(bars.size());
    for(auto p:buffers()) p->resize(n);
    std::vector<long> volume(n);
    std::vector<int> spread(n);
    check(OnCalculate(n,prev,times,open,high,low,close,volume,volume,spread)==(stop_requested ? 0 : n),"OnCalculate return");
    return snapshot();
}
void same(const Snapshot& a,const Snapshot& b)
{
    check(a==b,"incremental/tick/reload buffers identical");
}

// Independent explicit geometric-weight EMA oracle, with a first-source seed.
double ema(const std::vector<double>& values,int last,int length)
{
    long double alpha=2.L/(length+1),beta=1-alpha;
    long double result=values[0]*std::pow(beta,last);
    for(int j=1;j<=last;j++) result+=alpha*values[j]*std::pow(beta,last-j);
    return double(result);
}

int main()
{
    MSConfig c=config();
    check(MSConfigValid(c) && MSWarmup(c)==34,"automatic warmup depends on periods");
    c.fast=0; check(!MSConfigValid(c),"reject zero length"); c=config();
    c.threshold=-1; check(!MSConfigValid(c),"reject negative threshold"); c=config();
    c.threshold=std::numeric_limits<double>::quiet_NaN(); check(!MSConfigValid(c),"reject NaN threshold"); c=config();
    c.signal=1; check(MSWarmup(c)==26,"signal one warmup"); c=config();
    c.threshold_mode=MS_ATR; c.atr_length=100; check(MSWarmup(c)==100,"ATR auto warmup");
    c.warmup=3; check(MSWarmup(c)==3,"explicit warmup override");
    check(MSQualifiedSide(0,0)==0,"zero does not flip");
    check(MSQualifiedSide(-.05,.05)==-1 && MSQualifiedSide(.05,.05)==1,"threshold equality qualifies");

    MSEngine s; MSReset(s); s.threshold=.05;
    check(detect(s,0,.1).type==0 && s.direction==1,"initial leg produces no invented pivot");
    check(detect(s,1,-.01,120).type==0 && s.direction==1,"small crossover remains pending");
    auto e=detect(s,2,-.10,115);
    check(e.type==1 && e.pivot_index==1 && e.price==120 && e.confirm_index==2,"delayed threshold confirms earlier peak");
    check(e.classification==MS_FIRST_HIGH,"first high classification");
    check(detect(s,3,-.2).type==0,"no duplicate swing in same direction");
    e=detect(s,4,.1,110,80);
    check(e.type==-1 && e.price==80 && e.pivot_index==4,"confirmation bar included in old leg");
    check(e.classification==MS_FIRST_LOW,"first low classification");
    detect(s,5,.1,130); detect(s,6,.1,130);
    e=detect(s,7,-.1,125);
    check(e.pivot_index==6 && e.price==130 && e.classification==MS_HH,"equal high selects latest; higher high classification");
    e=detect(s,8,.1,110,85);
    check(e.classification==MS_HL,"higher low classification");
    e=detect(s,9,-.1,115);
    check(e.classification==MS_LH,"lower high classification");
    e=detect(s,10,.1,110,70);
    check(e.classification==MS_LL,"lower low classification");
    e=detect(s,11,-.1,115);
    check(e.classification==MS_EH,"equal high classification");
    e=detect(s,12,.1,110,70);
    check(e.classification==MS_EL,"equal low classification");
    MSReset(s); s.threshold=0;
    detect(s,0,.1); detect(s,1,-.001);
    check(s.direction==-1,"zero threshold accepts first strict negative");
    detect(s,2,0); check(s.direction==-1,"zero histogram holds prior leg");

    check(colorEvents({-.1,-.2,-.1,-.2})==std::vector<int>({0,0,-1,1}),"dark red -> light red up; light red -> dark red down");
    check(colorEvents({.1,.2,.1,.2})==std::vector<int>({0,0,1,-1}),"dark green -> light green down; light green -> dark green up");
    check(colorEvents({.1,.2,.3,-.1})==std::vector<int>({0,0,0,1}),"dark green -> dark green -> red confirms high");
    check(colorEvents({.1,.2,.1,-.1})==std::vector<int>({0,0,1,0}),"dark green -> light green -> red continues down without duplicate high");
    check(colorEvents({-.1,-.2,-.3,.1})==std::vector<int>({0,0,0,-1}),"dark red -> dark red -> green confirms low");
    check(colorEvents({-.1,-.2,-.1,.1})==std::vector<int>({0,0,-1,0}),"dark red -> light red -> green continues up without duplicate low");
    check(colorEvents({.1,.2,.2,.2,.3})==std::vector<int>({0,0,1,0,-1}),"equal positive histogram follows non-rising light-green color");
    check(colorEvents({-.3,-.2,-.2,-.2,-.1})==std::vector<int>({0,0,1,0,-1}),"equal negative histogram follows non-rising dark-red color");
    check(colorEvents({.1,.2,0,0,-.1})==std::vector<int>({0,0,1,0,0}),"zero plateau does not create duplicate swings");
    check(colorEvents({0,0,0,0})==std::vector<int>({0,0,0,0}),"flat zero histogram has no color swings");
    check(MSHistogramColorSide(.1,0,false)==0,"no color from missing previous bar");
    check(MSHistogramColorSide(.1,std::numeric_limits<double>::quiet_NaN(),true)==0,"invalid previous histogram ignored");
    c=config(); c.swing_mode=MS_HISTOGRAM_COLOR; c.threshold_mode=MS_ATR; c.atr_length=1000;
    check(MSWarmup(c)==34,"color mode does not wait for unused ATR length");

    std::mt19937 rng(781);
    std::vector<MSBar> history;
    double price=100;
    for(int i=0;i<320;i++) {
        double open=price; price+=(int(rng()%17)-8)*.2;
        history.push_back({1000+i*60,open,std::max(open,price)+(rng()%10)*.1,
                           std::min(open,price)-(rng()%10)*.1,price});
    }
    // Numerics and swing events versus a separate, finite segment reference.
    for(auto lengths:std::vector<std::vector<int>>{{12,26,9},{1,2,3},{30,7,4},{3,4,1},{200,300,250}}) {
        c=config(); c.fast=lengths[0]; c.slow=lengths[1]; c.signal=lengths[2];
        MSReset(s);
        std::vector<double> closes,mains;
        double ref_atr=0;
        for(size_t i=0;i<history.size();i++) {
            closes.push_back(history[i].close);
            double fast=ema(closes,int(i),c.fast),slow=ema(closes,int(i),c.slow);
            mains.push_back(fast-slow);
            check(MSProcess(c,history[i],int(i),s,e),"valid bar processes");
            check(near(s.fast,fast) && near(s.slow,slow) && near(s.signal,ema(mains,int(i),c.signal)),"MACD equals explicit weighted oracle");
            double tr=history[i].high-history[i].low;
            if(i>0) tr=std::max({tr,std::abs(history[i].high-history[i-1].close),std::abs(history[i].low-history[i-1].close)});
            ref_atr=i==0 ? tr : (ref_atr*(c.atr_length-1)+tr)/c.atr_length;
            check(near(s.atr,ref_atr),"ATR Wilder recurrence");
            if(i+1<size_t(MSWarmup(c))) check(s.direction==0 && e.type==0,"warmup does not create swings");
        }
    }
    for(auto mode:{MS_PRICE,MS_POINTS,MS_ATR}) {
        c=config(); c.threshold_mode=mode; c.threshold=.5; MSReset(s);
        for(int i=0;i<20;i++) {
            MSProcess(c,history[i],i,s,e);
            double ref=c.threshold*(mode==MS_PRICE ? 1 : (mode==MS_POINTS ? c.point : s.atr));
            check(near(s.threshold,ref),"threshold unit conversion");
        }
    }
    c=config(); MSReset(s);
    auto bad=history[0]; bad.close=std::numeric_limits<double>::quiet_NaN();
    check(!MSProcess(c,bad,0,s,e) && s.count==0,"invalid OHLC resets warmup");
    check(MSProcess(c,bar(0,-90,-110,-100),0,s,e),"negative prices supported");

    // Exact reference swing segmentation on random histogram data. It scans the
    // entire leg for its pivot at confirmation, independently of stored extrema.
    MSReset(s); s.threshold=.25;
    int direction=0,start=-1,last_type=0;
    std::vector<double> hs,ls;
    for(int i=0;i<1000;i++) {
        double h=101+(rng()%100)*.1,l=99-(rng()%100)*.1;
        hs.push_back(h); ls.push_back(l);
        double hist=(int(rng()%101)-50)*.01;
        int qualified=std::abs(hist)>=.25 ? (hist>0 ? 1 : -1) : 0;
        e=detect(s,i,hist,h,l);
        if(direction==0) { if(qualified!=0) { direction=qualified; start=i; } check(e.type==0,"reference initial leg"); }
        else if(qualified!=0 && qualified!=direction) {
            int pivot=start;
            for(int j=start+1;j<=i;j++) if(direction==1 ? hs[j]>=hs[pivot] : ls[j]<=ls[pivot]) pivot=j;
            check(e.type==direction && e.pivot_index==pivot && e.price==(direction==1 ? hs[pivot] : ls[pivot]),"pivot matches independent full segment scan");
            check(e.type!=last_type,"confirmed highs/lows alternate"); last_type=e.type;
            direction=qualified; start=i;
        } else check(e.type==0,"reference no event inside leg");
    }

    // Actual OnCalculate buffers: all-at-once, ticks, skipped ticks, resets and history caps.
    for(auto swing_mode:{MS_MACD_CROSS,MS_HISTOGRAM_COLOR})
    for(auto mode:{MS_PRICE,MS_POINTS,MS_ATR}) {
        g_config=config(); g_config.threshold_mode=mode; g_config.threshold=.05; g_config.swing_mode=swing_mode;
        int prev=0;
        for(size_t n=1;n<=history.size();n++) {
            std::vector<MSBar> prefix(history.begin(),history.begin()+n);
            auto incremental=calculate(prefix,prev);
            int before_renders=renders;
            auto live_changed=prefix; live_changed.back().close=live_changed.back().high+100;
            same(incremental,calculate(live_changed,int(n)));
            check(renders==before_renders,"same-bar tick does not redraw labels");
            same(incremental,calculate(prefix,0));
            for(auto p:buffers()) check(p->back()==EMPTY_VALUE,"live candle buffers empty");
            prev=int(n);
        }
        check(g_event_count>0,"random history produced integration swings");
        for(int j=0;j<g_event_count;j++) {
            auto event=g_events[j];
            check(EventType[event.confirm_index]==event.type && EventPrice[event.confirm_index]==event.price &&
                  EventSwingTime[event.confirm_index]==event.pivot_time,"event buffer is at confirmation candle");
            check((event.type==1 ? SwingHigh : SwingLow)[event.pivot_index]==event.price,"pivot buffer is at extreme candle");
            auto pivot=history[event.pivot_index];
            double body=event.type==1 ? std::max(pivot.open,pivot.close) : std::min(pivot.open,pivot.close);
            check(event.body_price==body,"body level uses exact historical pivot candle in either swing mode");
        }
        calculate(std::vector<MSBar>(history.begin(),history.begin()+60),0);
        auto caught_up=calculate(history,60); same(caught_up,calculate(history,0));
        auto shifted=std::vector<MSBar>(history.begin()+1,history.end());
        auto last=shifted.back(); last.time+=60; shifted.push_back(last);
        auto capped=calculate(shifted,int(history.size())); same(capped,calculate(shifted,0));
        auto shorter=std::vector<MSBar>(history.begin(),history.begin()+100);
        auto shrunk=calculate(shorter,int(history.size())); same(shrunk,calculate(shorter,0));
        calculate(history,0);
        auto changed=history; changed[30].high+=50;
        auto corrected=calculate(changed,0); same(corrected,calculate(changed,0));
        check(last_report_reset,"history rebuild suppresses live report flag");
    }
    // End-to-end color oracle based on the exported MACD histogram. Scan the
    // price segment independently and verify confirmation timing + pivot values.
    g_config=config(); g_config.swing_mode=MS_HISTOGRAM_COLOR;
    auto colors=calculate(history,0);
    int color_direction=0,color_start=-1,color_count=0;
    for(size_t i=0;i+1<history.size();i++) {
        if(i+1<size_t(MSWarmup(g_config)) || i==0) {
            check(EventType[i]==EMPTY_VALUE,"no color events before warmup"); continue;
        }
        double current=HistogramValues[i],previous=HistogramValues[i-1];
        // Palette: 0 dark green, 1 light green, 2 light red, 3 dark red.
        int palette=current>=0 ? (current>previous ? 0 : 1) : (current>previous ? 2 : 3);
        int side=current==0 && previous==0 ? 0 : (palette==0 || palette==2 ? 1 : -1);
        if(color_direction==0) {
            if(side!=0) { color_direction=side; color_start=int(i); }
            check(EventType[i]==EMPTY_VALUE,"first color leg has no pivot event");
        } else if(side!=0 && side!=color_direction) {
            int extreme=color_start;
            for(int j=color_start+1;j<=int(i);j++)
                if(color_direction==1 ? history[j].high>=history[extreme].high : history[j].low<=history[extreme].low) extreme=j;
            double expected=color_direction==1 ? history[extreme].high : history[extreme].low;
            check(EventType[i]==color_direction && EventPrice[i]==expected && EventSwingTime[i]==history[extreme].time,
                  "color mode actual buffers match independent palette and full price scan");
            color_count++; color_direction=side; color_start=int(i);
        } else check(EventType[i]==EMPTY_VALUE,"no duplicate event for unchanged color direction");
    }
    check(color_count>0 && color_count==g_event_count,"all color-mode events accounted for");
    g_config.threshold_mode=MS_ATR; g_config.threshold=100000; g_config.atr_length=1000;
    same(colors,calculate(history,0)); // Includes threshold buffer=0 and same warmup.
    g_config=config(); g_config.swing_mode=MS_HISTOGRAM_COLOR; g_config.signal=1;
    calculate(history,0); check(g_event_count==0,"signal length one gives no false color swings");
    g_config=config(); g_config.slow=200; g_config.warmup=1;
    auto short_history=std::vector<MSBar>(history.begin(),history.begin()+60);
    auto before=calculate(short_history,0);
    short_history.back().close+=1000; short_history.back().high+=1000;
    same(before,calculate(short_history,0)); // Even full rebuild never reads the live candle.
    g_config=config();
    calculate({},0);
    calculate(history,0);
    stop_requested=true; calculate(history,0); stop_requested=false;
    auto recovered=calculate(history,0); same(recovered,calculate(history,0));
    // Body endpoints track the exact extreme candle, including equal-wick ties.
    MSReset(s); s.histogram=.1;
    MSBar seed={1000,100,120,90,105};
    MSDetectSwing(seed,0,s,e);
    MSBar top={1060,110,130,90,100};
    MSDetectSwing(top,1,s,e);
    MSBar tied_top={1120,105,130,95,115};
    MSDetectSwing(tied_top,2,s,e);
    s.histogram=-.1;
    MSBar confirm_high={1180,105,120,80,90};
    MSDetectSwing(confirm_high,3,s,e);
    check(e.type==1 && e.pivot_index==2 && e.price==130 && e.body_price==115,"equal wick picks latest candle AND its body");
    check(MSSRPrice(e,MS_SR_WICK)==130 && MSSRPrice(e,MS_SR_BODY)==115,"wick/body anchor selection");
    MSBar bottom={1240,95,100,70,85};
    MSDetectSwing(bottom,4,s,e);
    s.histogram=.1;
    MSBar confirm_low={1300,90,110,80,100};
    MSDetectSwing(confirm_low,5,s,e);
    check(e.type==-1 && e.pivot_index==4 && e.price==70 && e.body_price==85,"low uses lower body edge of pivot, not confirmation candle");
    MSBar doji={1360,100,120,80,100};
    check(MSBodyEdge(doji,1)==100 && MSBodyEdge(doji,-1)==100,"doji body is open/close for both types");
    std::cout<<"MACD Swing Count: "<<checks<<" checks passed\n";
}
