#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <string>
#include <vector>
#define MathIsValidNumber std::isfinite
#define MathAbs std::abs
template<class A,class B> double MathMax(A a,B b) { return std::max(double(a),double(b)); }
template<class A,class B> double MathMin(A a,B b) { return std::min(double(a),double(b)); }
#include "../../MQL5/Indicators/WickHuntSRFlow/WickHuntSRCore.mqh"
#include "WickHuntContextCore.hpp"
using datetime=long;
using string=std::string;
using ENUM_TIMEFRAMES=int;
constexpr double EMPTY_VALUE=std::numeric_limits<double>::max();
constexpr int PERIOD_M5=300,PERIOD_H1=3600,SERIES_SYNCHRONIZED=1;
constexpr int TERMINAL_CONNECTED=1,SYMBOL_CHART_MODE=1,SYMBOL_CHART_MODE_LAST=2;
struct MqlRates { long time; double open,high,low,close; };
struct MqlTick { long time; double bid,last; };
template<class T> void ArraySetAsSeries(const T&,bool) {}
template<class T> int ArraySize(const std::vector<T>& v) { return int(v.size()); }
template<class T> int ArrayResize(std::vector<T>& v,int n) { v.resize(n); return n; }
template<class T> void ArrayInitialize(std::vector<T>& v,double x) { std::fill(v.begin(),v.end(),x); }
string _Symbol="TEST",g_prefix="TEST_";
int _Period=PERIOD_H1,_Digits=2;
int InpSignalTF=PERIOD_M5,InpHuntTF=PERIOD_H1,InpHuntBars=1,InpHistoryBars=1000,InpSRCount=10;
ENUM_WS_SCENARIO InpScenario=WS_LEGACY;
int InpTouchBars=5,InpPullbackHuntBars=2,InpContextHistoryBars=0,InpFVGSearchBars=0;
int InpRetestBars=0; // Preserve old-path regression fixtures; explicit v1.03 cases use 8.
int InpConfirmBars=1;
double InpCloseBufferPoints=0,InpRetestTolerancePoints=0,InpMinHuntPoints=0;
double InpFVGMaxLeadWickPercent=30;
bool InpEnableBuy=true,InpEnableSell=true;
// Existing fixtures exercise the original tick adapter only. No historical
// replay checks are claimed by this suite until that adapter is covered.
constexpr int WH_LOWER_TF_CLOSE=1;
int InpObservationMode=0;
double InpMinFVGGapPoints=0,_Point=.01;
bool InpRequireFVGMiddleDirection=false;
ENUM_MS_SR_ANCHOR InpSRAnchor=MS_SR_WICK;
bool InpPopupAlert=true;
std::vector<double> BuyBuffer,SellBuffer,EventTimeBuffer,DirectionBuffer,SRPriceBuffer,SRTypeBuffer,BreakTimeBuffer,HuntTimeBuffer;
std::vector<double> PatternBuffer,ContextSRBuffer,FVGTimeBuffer,TrendPivotBuffer;
MSConfig g_config;
WSState g_state;
WSContext g_context;
std::vector<WSSignal> g_signals;
WHCState g_higher;
std::vector<MSBar> g_higher_bars;
long g_higher_open=0;
int g_higher_available=0;
int g_small_seconds=300,g_big_seconds=3600,g_chart_total=0;
long g_lower_open=0;
long g_chart_first=0,g_chart_last=0;
bool g_force_replay=true,g_outputs_dirty=true,g_observed=false;
bool g_arrows_dirty=true;
double g_chart_high=0,g_chart_low=0;
std::vector<MqlRates> high_rates,low_rates;
std::vector<long> chart_times;
MqlTick live_tick;
bool synchronized=true,lower_synchronized=true,connected=true,copy_fail=false,stop_requested=false;
int renders=0,alerts=0,copies=0;
long chart_mode=0;
string status_text;
bool SeriesInfoInteger(const string&,int tf,int) { return synchronized && (tf!=PERIOD_M5 || lower_synchronized); }
bool TerminalInfoInteger(int) { return connected; }
bool SymbolInfoTick(const string&,MqlTick& tick) { tick=live_tick; return true; }
long SymbolInfoInteger(const string&,int) { return chart_mode; }
int CopyRates(const string&,int tf,int start,int count,std::vector<MqlRates>& out)
{
    ++copies;
    if(copy_fail) return -1;
    const auto& data=tf==PERIOD_H1 ? high_rates : low_rates;
    int n=std::min(count,int(data.size()));
    out.assign(data.end()-n,data.end());
    return n;
}
long iTime(const string&,int tf,int shift)
{
    if(tf==PERIOD_M5) return low_rates.empty() ? 0 : low_rates.at(low_rates.size()-1-shift).time;
    if(shift>=int(chart_times.size())) return 0;
    return chart_times.at(chart_times.size()-1-shift);
}
int iBarShift(const string&,int,long time,bool)
{
    for(int i=int(chart_times.size())-1;i>=0;--i)
        if(chart_times[i]<=time) return int(chart_times.size())-1-i;
    return -1;
}
int PeriodSeconds(int tf) { return tf; }
int iBars(const string&,int tf) { return tf==PERIOD_M5 ? int(low_rates.size()) : int(high_rates.size()); }
bool IsStopped() { return stop_requested; }
bool RenderSR() { ++renders; return true; }
bool RenderSignals() { ++renders; return true; }
void ChartRedraw(int) {}
string EnumToString(int x) { return std::to_string(x); }
string DoubleToString(double x,int) { return std::to_string(x); }
template<class... T> void Alert(T... args) { ++alerts; }
void Status(const string& text) { status_text=text; }
void ClearOutput()
{
    for(auto p:{&BuyBuffer,&SellBuffer,&EventTimeBuffer,&DirectionBuffer,&SRPriceBuffer,&SRTypeBuffer,&BreakTimeBuffer,&HuntTimeBuffer,&PatternBuffer,&ContextSRBuffer,&FVGTimeBuffer,&TrendPivotBuffer})
        ArrayInitialize(*p,EMPTY_VALUE);
}
void UpdateLive();
void UpdateIndicator() { UpdateLive(); } // Legacy fixture's timer dispatcher.
#include "indicator_under_test.hpp"

int checks=0;
void check(bool ok,const char* message)
{
    ++checks;
    if(!ok) { std::cerr<<"FAIL: "<<message<<'\n'; std::exit(1); }
}
MSConfig config() { return {2,4,2,3,14,MS_PRICE,0,.01,MS_HISTOGRAM_COLOR}; }
MSBar bar(long t,double o,double h,double l,double c) { return {t,o,h,l,c}; }
MSEvent level(int type,double price,long confirmed,long pivot=0,double body=0)
{
    MSEvent e{}; e.type=type; e.price=price; e.confirm_time=confirmed;
    e.pivot_time=pivot; e.body_price=body; return e;
}
WSContext context() { return {36000,39600,100,90,110,true}; }
void prime(WSState& state,int type,double price)
{
    WSReset(state,36000); state.macd.count=100; state.macd.previous_close=99;
    state.macd.fast=99; state.macd.slow=99; state.macd.signal=0; state.macd.atr=1;
    state.levels[0]=level(type,price,35400,35100,price-1); state.level_count=1;
}
void fixture()
{
    g_config=config(); WSReset(g_state,36000); g_context=context();
    g_signals.clear(); g_chart_total=1; chart_times={36000};
    high_rates={{32400,100,110,90,100},{36000,100,106,89,100}};
    low_rates={{36600,100,105,99,101}}; live_tick={36650,100,100};
    for(auto p:{&BuyBuffer,&SellBuffer,&EventTimeBuffer,&DirectionBuffer,&SRPriceBuffer,&SRTypeBuffer,&BreakTimeBuffer,&HuntTimeBuffer,&PatternBuffer,&ContextSRBuffer,&FVGTimeBuffer,&TrendPivotBuffer}) p->resize(1);
    ClearOutput(); g_lower_open=36600; g_force_replay=false;
    g_outputs_dirty=true; g_observed=true; connected=true; synchronized=true;
    copy_fail=false; stop_requested=false; alerts=0; chart_mode=0; lower_synchronized=true;
    g_state.buy_reclaimed=true; g_state.buy_reclaim_time=36250;
    WSClearBreak(g_state.buy_break);
    g_state.buy_break.valid=true; g_state.buy_break.bar_time=36300;
    g_state.buy_break.pivot_time=35100; g_state.buy_break.confirm_time=35400;
    g_state.buy_break.price=98; g_state.buy_break.close=101;
    g_state.buy_break.type=-1; g_state.buy_break.close_time=36600;
    InpRetestBars=0;
    InpScenario=WS_LEGACY; InpTouchBars=5; InpPullbackHuntBars=2;
    InpContextHistoryBars=0; InpFVGSearchBars=0; WHCReset(g_higher);
    g_higher_bars.clear(); g_higher_open=0; g_higher_available=0;
}

#include "scenario_tests.hpp"
#include "retest_tests.hpp"

int main()
{
    retest_tests();
    WSState s; WSContext c=context(); WSSignal e{};
    check(WSCross(1,100,101,100),"buy accepts previous close equality");
    check(!WSCross(1,99,100,100),"buy current close equality fails");
    check(!WSCross(1,101,102,100),"already above is not a new break");
    check(WSCross(-1,100,99,100),"sell accepts previous close equality");
    check(!WSCross(-1,101,100,100),"sell current close equality fails");
    check(!WSCross(1,99,std::numeric_limits<double>::quiet_NaN(),100),"invalid close fails");
    for(int type:{1,-1}) {
        prime(s,type,100);
        check(WSProcessClosed(s,config(),bar(36300,99,102,98,101),1,300,c,10,MS_SR_WICK),"closed bar processes");
        check(!s.buy_break.valid,"break before reclaim is not remembered for either H/L");
        check(!WSTakeSignal(s,c,36600,100,1,e),"break alone has no signal");
        WSObserve(s,c,36610,102,90,100);
        check(!s.buy_reclaimed,"equal prior low is not a hunt");
        WSObserve(s,c,36620,102,89,99.99);
        check(!s.buy_reclaimed,"below open is not a reclaim");
        WSObserve(s,c,36621,102,89,100);
        check(s.buy_reclaimed && s.buy_reclaim_time==36621,"live exact-open reclaim arms later M5 closes");
        check(!WSTakeSignal(s,c,36621,100,1,e),"reclaim does not retroactively trigger earlier closed break");
        WSProcessClosed(s,config(),bar(36600,101,102,98,99),2,300,c,10,MS_SR_WICK);
        WSProcessClosed(s,config(),bar(36900,99,102,98,101),3,300,c,10,MS_SR_WICK);
        check(s.buy_break.valid && s.buy_break.type==type,"both swing H and L allow a later buy close break");
        check(!WSTakeSignal(s,c,37199,101,1,e),"cannot emit before selected M5 actually closes");
        check(WSTakeSignal(s,c,37200,101,1,e),"close break after reclaim emits signal");
        check(e.break_time==36900 && e.time==37200 && e.sr_type==type,"event retains later breakout and observation times");
        check(!WSTakeSignal(s,c,37201,101,1,e),"no duplicate on later tick");
    }
    prime(s,-1,100); WSObserve(s,c,36200,102,89,100); s.levels[0].confirm_time=36300;
    WSProcessClosed(s,config(),bar(36300,99,102,98,101),1,300,c,10,MS_SR_WICK);
    check(!s.buy_break.valid,"same candle confirmation cannot supply its own SR");
    prime(s,-1,100); WSObserve(s,c,36200,102,89,100); s.levels[0].confirm_time=36900;
    WSProcessClosed(s,config(),bar(36300,99,102,98,101),1,300,c,10,MS_SR_WICK);
    check(!s.buy_break.valid,"future confirmed swing excluded");
    prime(s,1,100);
    WSProcessClosed(s,config(),bar(35700,99,102,98,101),1,300,c,10,MS_SR_WICK);
    check(!s.buy_break.valid,"prior H1 breakout excluded");
    prime(s,1,100);
    WSObserve(s,c,36320,102,89,100);
    check(s.buy_reclaimed,"reclaim can come first");
    WSProcessClosed(s,config(),bar(36600,99,102,98,101),1,300,c,10,MS_SR_WICK);
    check(WSTakeSignal(s,c,36900,101,1,e),"later close break triggers latched reclaim");
    prime(s,1,100); s.macd.previous_close=101;
    WSProcessClosed(s,config(),bar(36300,101,112,98,99),1,300,c,10,MS_SR_WICK);
    check(!s.sell_break.valid,"sell break before reclaim excluded");
    WSObserve(s,c,36600,110,98,100);
    check(!s.sell_reclaimed,"equal prior high is not a hunt");
    WSObserve(s,c,36601,111,98,100);
    check(!WSTakeSignal(s,c,36601,100,-1,e),"sell reclaim must wait for later close");
    WSProcessClosed(s,config(),bar(36600,99,102,98,101),2,300,c,10,MS_SR_WICK);
    WSProcessClosed(s,config(),bar(36900,101,112,98,99),3,300,c,10,MS_SR_WICK);
    check(WSTakeSignal(s,c,37200,99,-1,e),"symmetric sell reclaim then later break");
    WSBeginSetup(s,39600);
    check(!s.buy_break.valid && !s.sell_break.valid && !s.buy_reclaimed && !s.sell_sent,"new H1 clears facts and dedup");
    check(s.buy_reclaim_time==0 && s.sell_reclaim_time==0,"new H1 clears reclaim timestamps");
    prime(s,1,100); WSObserve(s,c,39600,111,89,100);
    check(!s.buy_reclaimed && !s.sell_reclaimed,"boundary quote cannot reclaim expired H1");
    prime(s,1,100); WSObserve(s,c,36200,102,89,100); s.levels[0].body_price=99;
    WSProcessClosed(s,config(),bar(36300,98,100,97,99.5),1,300,c,10,MS_SR_BODY);
    check(s.buy_break.valid && s.buy_break.price==99,"body anchor uses exact swing candle body");
    prime(s,1,100); WSObserve(s,c,36200,102,89,100); s.levels[1]=level(-1,99.5,35700,35400); s.level_count=2;
    WSProcessClosed(s,config(),bar(36300,99,102,98,101),1,300,c,10,MS_SR_WICK);
    check(s.buy_break.price==99.5,"most recently confirmed crossed level wins");
    WSProcessClosed(s,config(),bar(36600,100,99,101,100),2,300,c,10,MS_SR_WICK);
    check(s.level_count==0 && !s.buy_break.valid && s.macd.count==0,"invalid OHLC invalidates levels and pending breaks");

    for(int direction:{1,-1}) {
        prime(s,direction,100); s.macd.previous_close=direction==1 ? 99 : 101;
        WSObserve(s,c,36600,111,89,100);
        WSProcessClosed(s,config(),bar(36300,100,112,88,direction==1 ? 101 : 99),1,300,c,10,MS_SR_WICK);
        check(!(direction==1 ? s.buy_break.valid : s.sell_break.valid),"same-time close/reclaim excluded");
        s.macd.previous_close=direction==1 ? 99 : 101;
        WSProcessClosed(s,config(),bar(36600,100,112,88,direction==1 ? 101 : 99),2,300,c,10,MS_SR_WICK);
        check(WSTakeSignal(s,c,36900,100,direction,e),"M5 close strictly after reclaim eligible in both directions");
        prime(s,direction,100); s.macd.previous_close=direction==1 ? 99 : 101;
        WSObserve(s,c,36599,111,89,100);
        WSProcessClosed(s,config(),bar(36300,100,112,88,direction==1 ? 101 : 99),1,300,c,10,MS_SR_WICK);
        check(WSTakeSignal(s,c,36600,100,direction,e),"M5 opened before reclaim may qualify by later close");
        long first_reclaim=direction==1 ? s.buy_reclaim_time : s.sell_reclaim_time;
        WSObserve(s,c,36620,111,89,100);
        check((direction==1 ? s.buy_reclaim_time : s.sell_reclaim_time)==first_reclaim,"later open visits do not move initial reclaim cutoff");
    }

    // Compare copied histogram swing engine with a direct MACDSwingCount engine
    // through many rising/falling legs, including bounded recent-level retention.
    WSReset(s,c.time); MSEngine oracle; MSReset(oracle); std::vector<MSEvent> events;
    for(int i=0;i<600;i++) {
        double close=100+7*std::sin(i*.31)+2*std::sin(i*.77);
        MSBar b=bar(1000+i*300,close-.2,close+1,close-1,close);
        MSEvent expected; MSProcess(config(),b,i,oracle,expected);
        WSProcessClosed(s,config(),b,i,300,c,7,MS_SR_WICK);
        if(expected.type) { events.push_back(expected); if(events.size()>7) events.erase(events.begin()); }
        check(s.level_count==int(events.size()),"SR count matches chronological histogram events");
        check(s.macd.histogram==oracle.histogram,"histogram formula identical");
        for(int j=0;j<s.level_count;j++)
            check(s.levels[j].price==events[j].price && s.levels[j].pivot_time==events[j].pivot_time && s.levels[j].confirm_time==events[j].confirm_time,"no swing backdating in SR availability");
    }

    // Actual MT5 wrapper bodies under a quote/history/chart API fixture.
    fixture(); OnTimer();
    check(g_signals.size()==1 && g_signals[0].time==36650,"timer emits closed M5 break after an observed reclaim on H1 chart");
    check(BuyBuffer[0]==100 && EventTimeBuffer[0]==36650 && SRPriceBuffer[0]==98,"live H1 shift zero carries confirmed observed event");
    check(alerts==1,"one live popup");
    OnTimer(); check(g_signals.size()==1 && alerts==1,"timer dedup");
    fixture(); g_state.buy_reclaimed=false; g_state.buy_reclaim_time=0; OnTimer();
    check(g_signals.empty() && g_state.buy_reclaim_time==36650 && !g_state.buy_break.valid,
          "timer arms at live reclaim but discards the earlier M5 break");
    OnTimer(); check(g_signals.empty(),"repeated timer cannot turn earlier break into a signal");
    fixture(); connected=false; OnTimer(); check(g_signals.empty(),"disconnected quote cannot signal");
    fixture(); synchronized=false; OnTimer(); check(g_signals.empty(),"unsynchronized history cannot signal");
    fixture(); lower_synchronized=false; OnTimer(); check(g_signals.empty(),"cached lower-TF data must still be synchronized");
    fixture(); copy_fail=true; OnTimer(); check(g_signals.empty(),"CopyRates failure cannot signal");
    fixture(); live_tick.time=39600; OnTimer(); check(g_signals.empty(),"stale high-TF series cannot signal beyond expiry");
    fixture(); live_tick.bid=99; live_tick.last=100; chart_mode=SYMBOL_CHART_MODE_LAST; OnTimer();
    check(g_signals.size()==1 && g_signals[0].price==100,"last-price chart uses last rather than bid");
    fixture(); InpHuntBars=2; high_rates.insert(high_rates.begin(),{28800,100,108,88,100});
    g_state.buy_reclaimed=false; g_state.buy_reclaim_time=0; OnTimer();
    check(g_signals.empty() && !g_state.buy_reclaimed,"multi-candle hunt must sweep the lowest prior candle"); InpHuntBars=1;
    fixture(); g_observed=false; OnTimer(); check(g_signals.size()==1 && alerts==0,"attach observation suppresses popup");

    fixture(); g_force_replay=true; low_rates.clear();
    for(int i=0;i<140;i++) {
        double close=100+std::sin(i*.5)*5;
        low_rates.push_back({1000+i*300,close,close+1,close-1,close});
    }
    g_context={40000,43600,100,90,110,true};
    WSBeginSetup(g_state,40000); g_state.buy_reclaimed=true; g_state.buy_reclaim_time=40001; g_state.buy_sent=true;
    long now=low_rates.back().time+10;
    check(ReplayLower(now),"actual closed history replay succeeds");
    InpHistoryBars=0; g_force_replay=true;
    check(ReplayLower(now),"zero history input replays all loaded bars"); InpHistoryBars=1000;
    check(g_state.macd.count==139,"forming lower-TF bar excluded");
    check(g_state.buy_reclaimed && g_state.buy_sent,"replay preserves observed same-H1 facts and dedup");
    check(g_state.buy_reclaim_time==40001,"replay preserves original live reclaim time before rebuilding breaks");
    double histogram=g_state.macd.histogram;
    low_rates.back().close=120; low_rates.back().high=121;
    check(ReplayLower(now) && g_state.macd.histogram==histogram,"forming bar price does not change swings");
    low_rates.push_back({low_rates.back().time+300,120,121,119,120});
    check(ReplayLower(low_rates.back().time+10) && g_state.macd.count==140,"new M5 candle advances while H1 remains open");
    g_context.time=43600; g_context.end_time=47200;
    check(ReplayLower(low_rates.back().time+10) && !g_state.buy_reclaimed && !g_state.buy_sent,"replay clears live facts at H1 rollover");

    fixture(); OnTimer(); g_chart_total=2; chart_times={36000,39600};
    for(auto p:{&BuyBuffer,&SellBuffer,&EventTimeBuffer,&DirectionBuffer,&SRPriceBuffer,&SRTypeBuffer,&BreakTimeBuffer,&HuntTimeBuffer,&PatternBuffer,&ContextSRBuffer,&FVGTimeBuffer,&TrendPivotBuffer}) p->resize(2);
    g_outputs_dirty=true; MapOutput();
    check(BuyBuffer[0]==100 && BuyBuffer[1]==EMPTY_VALUE,"signal retained at its original chart bar after rollover");
    fixture(); OnTimer();
    // Same rates_total while the chart's fixed-size history window advances.
    chart_times={39600}; high_rates[1]={39600,100,106,89,100};
    low_rates[0].time=39600; live_tick.time=39650;
    g_force_replay=false; g_lower_open=39600; WSBeginSetup(g_state,39600);
    g_chart_first=36000; g_chart_last=36000;
    std::vector<long> times={39600},volumes(1); std::vector<double> prices(1,100); std::vector<int> spread(1);
    check(OnCalculate(1,1,times,prices,prices,prices,prices,volumes,volumes,spread)==1,"actual OnCalculate accepts shifted fixed-size chart");
    check(BuyBuffer[0]==EMPTY_VALUE,"old event does not remain in a new chart bar when rates_total is unchanged");
    scenario_tests();
    std::cout<<"WickHuntSRFlow: "<<checks<<" checks passed\n";
}
