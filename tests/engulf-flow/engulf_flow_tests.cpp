#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <ctime>
#include <iostream>
#include <limits>
#include <random>
#include <vector>
#define MathIsValidNumber std::isfinite
#define MathMin std::min
#define MathMax std::max
using datetime=long;
using ulong=unsigned long;
#include "../../MQL5/Indicators/EngulfFlow/EngulfFlowCore.mqh"
constexpr double EMPTY_VALUE=std::numeric_limits<double>::max();
std::vector<double> BuyBuffer,SellBuffer,LegDirectionBuffer,LegCountBuffer;
std::vector<double> EMA20Buffer,EMA54Buffer,EMAValidCountBuffer;
datetime g_first_bar=0,g_current_bar=0,g_close_time=0,g_server_anchor=0;
ulong g_clock_anchor=0;
int g_live_index=-1;
int InpHuntBars=1,g_live_signal=0;
ENUM_WH_ENGULF_MODE InpEngulfMode=WH_ENGULF_BODY;
bool InpUsePriorMove=false;
bool InpUseEMAFilter=false;
int InpPriorMoveBars=3;
WHBar g_live;
datetime fake_server=0;
ulong fake_clock=100;
bool connected=true,synchronized=true,stopped=false;
int redraws=0;
std::vector<datetime> times;
template<class T> void ArraySetAsSeries(const std::vector<T>&,bool) {}
template<class T> int ArraySize(const std::vector<T>& a) { return int(a.size()); }
template<class T> void ArrayInitialize(std::vector<T>& a,T value) { std::fill(a.begin(),a.end(),value); }
bool IsStopped() { return stopped; }
datetime TimeCurrent() { return fake_server; }
ulong GetTickCount64() { return fake_clock; }
constexpr int TERMINAL_CONNECTED=1,SERIES_SYNCHRONIZED=1;
enum ENUM_TIMEFRAMES { PERIOD_M1=60,PERIOD_MN1=999 };
ENUM_TIMEFRAMES _Period=PERIOD_M1;
const char* _Symbol="TEST";
long TerminalInfoInteger(int) { return connected; }
long SeriesInfoInteger(const char*,ENUM_TIMEFRAMES,int) { return synchronized; }
datetime iTime(const char*,ENUM_TIMEFRAMES,int shift) {
    return shift>=0 && shift<int(times.size()) ? times[times.size()-1-shift] : 0;
}
void ChartRedraw() { ++redraws; }
int PeriodSeconds(ENUM_TIMEFRAMES period) { return int(period); }
struct MqlDateTime { int year,mon,day,hour,min,sec; };
bool TimeToStruct(datetime time,MqlDateTime& d) {
    auto t=gmtime(&time); if(!t) return false;
    d={t->tm_year+1900,t->tm_mon+1,t->tm_mday,t->tm_hour,t->tm_min,t->tm_sec}; return true;
}
datetime StructToTime(const MqlDateTime& d) {
    std::tm t{}; t.tm_year=d.year-1900; t.tm_mon=d.mon-1; t.tm_mday=d.day;
    t.tm_hour=d.hour; t.tm_min=d.min; t.tm_sec=d.sec; return timegm(&t);
}
#include "wh_indicator_under_test.hpp"
int checks=0;
void check(bool ok,const char* label) {
    ++checks; if(!ok) { std::cerr<<"FAIL: "<<label<<'\n'; std::exit(1); }
}
struct Snapshot { std::vector<double> buy,sell,direction,count,ema20,ema54,emaCount; };
Snapshot calculate(const std::vector<WHBar>& bars,int prev,datetime now,datetime base=1200) {
    const int n=int(bars.size()); times.clear();
    std::vector<double> o,h,l,c;
    for(int i=0;i<n;++i) {
        times.push_back(base+i*60); o.push_back(bars[i].open); h.push_back(bars[i].high);
        l.push_back(bars[i].low); c.push_back(bars[i].close);
    }
    BuyBuffer.resize(n); SellBuffer.resize(n); fake_server=now;
    LegDirectionBuffer.resize(n); LegCountBuffer.resize(n);
    EMA20Buffer.resize(n); EMA54Buffer.resize(n); EMAValidCountBuffer.resize(n);
    std::vector<long> ticks(n),vol(n); std::vector<int> spread(n);
    check(OnCalculate(n,prev,times,o,h,l,c,ticks,vol,spread)==n,"calculation count");
    return {BuyBuffer,SellBuffer,LegDirectionBuffer,LegCountBuffer,EMA20Buffer,EMA54Buffer,EMAValidCountBuffer};
}
int main() {
    WHBar previous{10,13,7,12},buy{11,14,6,13},sell{11,14,6,9};
    check(WHSignal(buy,previous)==1,"buy sweeps low and closes above body");
    check(WHSignal(sell,previous)==-1,"sell sweeps high and closes below body");
    check(WHSignal({11,12,6,12},previous)==0,"equal body top fails");
    check(WHSignal({11,14,8,10},previous)==0,"equal body bottom fails");
    check(WHSignal({11,14,7,13},previous)==0,"equal low fails");
    check(WHSignal({11,13,8,9},previous)==0,"equal high fails");
    check(WHSignal({11,15,8,13},previous)==0,"buy wrong side sweep fails");
    check(WHSignal({11,12,6,9},previous)==0,"sell wrong side sweep fails");
    check(WHSignal({11,14,6,11},previous)==0,"sweeps both but inside body fails");
    check(WHSignal({6,14,6,13},previous)==0,"gap with no lower wick fails");
    check(WHSignal({14,14,6,9},previous)==0,"gap with no upper wick fails");
    check(WHSignal(buy,{12,13,7,10})==1,"previous color is unrestricted");
    check(WHSignal(buy,{10,13,7,10})==1,"previous doji permitted");
    check(WHSignal({13.5,14,6,13},previous)==1,"close rule does not add color filter");
    check(WHSignal({11,14,6,13},{10,12,10,12})==1,"previous wick need not exist");
    for(double bad:{std::numeric_limits<double>::quiet_NaN(),std::numeric_limits<double>::infinity()}) {
        WHBar invalid=buy; invalid.close=bad;
        check(WHSignal(invalid,previous)==0,"nonfinite signal bar rejected");
        check(WHSignal(buy,invalid)==0,"nonfinite previous bar rejected");
    }
    check(WHSignal({11,12,6,13},previous)==0,"malformed OHLC rejected");
    check(!WHPreviewWindow(1314,1260,1320),"6 seconds is too early");
    check(WHPreviewWindow(1315,1260,1320),"5 seconds starts preview");
    check(WHPreviewWindow(1319,1260,1320),"1 second stays live");
    check(WHPreviewWindow(1320,1260,1320),"boundary retains last known OHLC pending rollover");
    check(!WHPreviewWindow(1259,1260,1320),"future bar rejected");
    check(!WHPreviewWindow(10,0,60),"unknown opening time rejected");
    check(!WHPreviewWindow(1320,1260,0),"unknown closing time rejected");
    check(WHBarClose(1200)==1260,"M1 close");
    _Period=PERIOD_MN1;
    for(auto d:std::vector<MqlDateTime>{{2024,2,1,0,0,0},{2025,2,1,0,0,0},{2025,12,1,0,0,0}}) {
        auto expected=d; if(++expected.mon==13) { expected.mon=1; ++expected.year; }
        check(WHBarClose(StructToTime(d))==StructToTime(expected),"calendar month boundary");
    }
    _Period=PERIOD_M1;
    auto s=calculate({previous,buy},0,1314);
    check(s.buy[0]==EMPTY_VALUE && s.buy[1]==EMPTY_VALUE,"no early or first-candle signal");
    // Exercise the real OnTimer with no new quote: the monotonic clock alone advances.
    fake_clock+=1000; OnTimer();
    check(BuyBuffer[1]==6 && SellBuffer[1]==EMPTY_VALUE,"timer shows 5-second preview without tick");
    connected=false; OnTimer(); check(BuyBuffer[1]==EMPTY_VALUE,"disconnect clears preview");
    connected=true; OnTimer(); check(BuyBuffer[1]==6,"reconnect restores eligible preview");
    synchronized=false; OnTimer(); check(BuyBuffer[1]==EMPTY_VALUE,"unsynchronized history hides preview");
    synchronized=true; OnTimer();
    auto noEngulf=buy; noEngulf.close=12;
    s=calculate({previous,noEngulf},2,1316);
    check(s.buy[1]==EMPTY_VALUE,"live loss of engulf removes arrow");
    s=calculate({previous,buy},2,1317); check(s.buy[1]==6,"live condition returns");
    s=calculate({previous,noEngulf,{12,12,12,12}},2,1320);
    check(s.buy[1]==EMPTY_VALUE,"failed final close removes prior preview");
    calculate({previous,buy},0,1319);
    s=calculate({previous,buy,{13,13,13,13}},2,1320);
    check(s.buy[1]==6 && s.buy[2]==EMPTY_VALUE,"successful close retained on engulfing bar");
    s=calculate({previous,buy,{13,13,13,13}},3,1340);
    check(s.buy[1]==6,"confirmed arrow persists on later ticks");
    calculate({previous,noEngulf},0,1319);
    s=calculate({previous,buy,{13,13,13,13}},2,1320);
    check(s.buy[1]==6,"final tick qualifies even without preview");
    calculate({previous,sell},0,1315);
    check(SellBuffer[1]==14 && BuyBuffer[1]==EMPTY_VALUE,"sell preview placement");
    calculate({previous,noEngulf},2,1316);
    check(SellBuffer[1]==EMPTY_VALUE,"sell preview removed on lost condition");
    calculate({previous,sell},2,1319);
    s=calculate({previous,sell,{9,9,9,9}},2,1320);
    check(s.sell[1]==14,"sell confirmed");
    // Timer must not touch shifted buffers while waiting for OnCalculate.
    calculate({previous,buy},0,1315); BuyBuffer[1]=123;
    times.back()+=60; OnTimer(); check(BuyBuffer[1]==123,"timer guards new bar race");
    times.back()-=60; times.front()-=60; OnTimer(); check(BuyBuffer[1]==123,"timer guards shifted history");
    times.front()+=60; BuyBuffer.push_back(456); OnTimer();
    check(BuyBuffer[1]==123 && BuyBuffer.back()==456,"timer guards resized buffers");
    s=calculate({previous},0,1259); OnTimer();
    check(s.buy[0]==EMPTY_VALUE && s.sell[0]==EMPTY_VALUE,"one-bar history remains empty");
    calculate({},0,1260); OnTimer(); check(g_live_index==-1,"empty history disables timer writes");
    // Compare streaming updates with full recalculation over varied OHLC, including
    // both sweeps, gaps, dojis and late invalidation. Also verify price reflection.
    std::mt19937 rng(713); std::uniform_int_distribution<int> price(-20,20);
    std::vector<WHBar> bars{previous};
    calculate(bars,0,1259);
    for(int i=1;i<=500;++i) {
        double o=price(rng),c=price(rng);
        WHBar bar{o,std::max(o,c)+std::abs(price(rng)),std::min(o,c)-std::abs(price(rng)),c};
        WHBar mirror{-bar.open,-bar.low,-bar.high,-bar.close};
        auto p=bars.back(); WHBar pm{-p.open,-p.low,-p.high,-p.close};
        check(WHSignal(bar,p)==-WHSignal(mirror,pm),"buy/sell reflection symmetry");
        bars.push_back(bar);
        auto stream=calculate(bars,i,1200+i*60+55);
        auto full=calculate(bars,0,1200+i*60+55);
        check(stream.buy==full.buy && stream.sell==full.sell,"stream equals full history");
        bars.back().close=bars.back().open;
        stream=calculate(bars,i+1,1200+i*60+59);
        full=calculate(bars,0,1200+i*60+59);
        check(stream.buy==full.buy && stream.sell==full.sell,"live revision equals full history");
    }
    auto shifted=calculate(bars,int(bars.size()),1200+int(bars.size())*60,1260);
    auto fresh=calculate(bars,0,1200+int(bars.size())*60,1260);
    check(shifted.buy==fresh.buy && shifted.sell==fresh.sell,"rolling fixed-size history resets");
    bars.resize(5);
    shifted=calculate(bars,501,1559); fresh=calculate(bars,0,1559);
    check(shifted.buy==fresh.buy && shifted.sell==fresh.sell,"shrinking history resets");

    // Lookback count applies to wick sweeps only, excludes the signal candle,
    // and requires all N immediately preceding candles to be available.
    InpHuntBars=3;
    WHBar far{20,22,5,21},middle{10,15,6,12};
    WHBar huntBuy{11,14,4,13},huntSell{11,23,8,9};
    s=calculate({far,middle,previous,buy},0,1435);
    check(s.buy[3]==EMPTY_VALUE,"sweeping only nearest candle is insufficient for N=3");
    s=calculate({far,middle,previous,huntBuy},0,1434);
    check(s.buy[3]==EMPTY_VALUE,"N=3 still waits for five-second window");
    fake_clock+=1000; OnTimer();
    check(BuyBuffer[3]==4,"timer uses all three wick levels without new quote");
    check(BuyBuffer[0]==EMPTY_VALUE && BuyBuffer[1]==EMPTY_VALUE && BuyBuffer[2]==EMPTY_VALUE,
          "first N candles cannot signal");
    s=calculate({far,middle,previous,huntBuy,{13,13,13,13}},4,1440);
    check(s.buy[3]==4,"N=3 close confirmed; older body above close does not block");
    auto failed=huntBuy; failed.close=12;
    calculate({far,middle,previous,huntBuy},0,1439);
    s=calculate({far,middle,previous,failed,{12,12,12,12}},4,1440);
    check(s.buy[3]==EMPTY_VALUE,"N=3 final body failure removes preview");
    auto equalLow=huntBuy; equalLow.low=5;
    s=calculate({far,middle,previous,equalLow},0,1435);
    check(s.buy[3]==EMPTY_VALUE,"equal oldest low fails");
    s=calculate({middle,far,previous,equalLow},0,1435);
    check(s.buy[3]==EMPTY_VALUE,"interior candle also must be swept");
    s=calculate({far,middle,previous,huntSell},0,1435);
    check(s.sell[3]==23,"sell sweeps all three highs");
    auto equalHigh=huntSell; equalHigh.high=22;
    s=calculate({far,middle,previous,equalHigh},4,1436);
    check(s.sell[3]==EMPTY_VALUE,"equal oldest high removes sell preview");
    s=calculate({far,middle,previous,huntSell,{9,9,9,9}},4,1440);
    check(s.sell[3]==23,"N=3 sell confirmed");
    s=calculate({middle,previous,huntBuy},0,1375); OnTimer();
    check(BuyBuffer[2]==EMPTY_VALUE,"insufficient history blocks preview and timer");
    auto invalid=far; invalid.low=std::numeric_limits<double>::quiet_NaN();
    s=calculate({invalid,middle,previous,huntBuy},0,1435);
    check(s.buy[3]==EMPTY_VALUE,"invalid older wick data rejected");
    InpHuntBars=2;
    s=calculate({far,middle,previous,huntBuy},0,1435);
    check(s.buy[3]==4,"changing input and reinitializing recomputes signals");
    s=calculate({{30,40,0,35},middle,previous,buy},0,1435);
    check(s.buy[3]==EMPTY_VALUE,"equal low in N=2 fails");
    s=calculate({{30,40,0,35},middle,previous,huntBuy},0,1435);
    check(s.buy[3]==4,"extreme outside N=2 window is excluded");
    InpHuntBars=std::numeric_limits<int>::max();
    s=calculate({previous,buy},0,1315); OnTimer();
    check(BuyBuffer[1]==EMPTY_VALUE,"huge lookback safely waits for history");

    // Independent min/max reference for multiple lookback lengths; also check
    // streaming and history shifts for each setting, including warm-up bars.
    for(int count:{1,2,3,10,50}) {
        InpHuntBars=count;
        bars={previous}; calculate(bars,0,1259);
        for(int i=1;i<=120;++i) {
            double o=price(rng),c=price(rng);
            bars.push_back({o,std::max(o,c)+std::abs(price(rng)),std::min(o,c)-std::abs(price(rng)),c});
            auto stream=calculate(bars,i,1200+i*60+55);
            auto full=calculate(bars,0,1200+i*60+55);
            check(stream.buy==full.buy && stream.sell==full.sell,"multi-lookback stream equals full");
            int expected=0;
            if(i>=count) {
                double lowest=bars[i-1].low,highest=bars[i-1].high;
                for(int j=i-count;j<i;++j) {
                    lowest=std::min(lowest,bars[j].low); highest=std::max(highest,bars[j].high);
                }
                auto b=bars[i],p=bars[i-1];
                if(b.close>std::max(p.open,p.close) && b.low<lowest && b.low<std::min(b.open,b.close)) expected=1;
                if(b.close<std::min(p.open,p.close) && b.high>highest && b.high>std::max(b.open,b.close)) expected=-1;
            }
            check(full.buy.back()==(expected==1 ? bars.back().low : EMPTY_VALUE) &&
                  full.sell.back()==(expected==-1 ? bars.back().high : EMPTY_VALUE),"min/max reference agrees");
        }
        shifted=calculate(bars,int(bars.size()),1200+int(bars.size())*60,1260);
        fresh=calculate(bars,0,1200+int(bars.size())*60,1260);
        check(shifted.buy==fresh.buy && shifted.sell==fresh.sell,"multi-lookback shifted history resets");
    }
    // Hunt=0 removes the entire sweep requirement, including own-wick presence.
    InpHuntBars=0;
    WHBar noHuntBuy{12,14,12,13},noHuntSell{10,10,8,9};
    s=calculate({previous,noHuntBuy},0,1315);
    check(s.buy[1]==12,"hunt zero allows buy without lower wick or sweep");
    s=calculate({previous,noHuntSell},0,1315);
    check(s.sell[1]==10,"hunt zero allows sell without upper wick or sweep");
    check(WHSignal(noHuntBuy,previous,true)==0,"enabling hunt blocks no-sweep buy");
    check(WHSignal(noHuntSell,previous,true)==0,"enabling hunt blocks no-sweep sell");
    check(WHSignal({12,13,12,12},previous,false)==0,"hunt zero keeps strict body boundary");
    check(WHSignal({12,13,12,13},previous,false,WH_ENGULF_WICK)==0,"equal previous high is not wick engulf");
    check(WHSignal({10,10,7,7},previous,false,WH_ENGULF_WICK)==0,"equal previous low is not wick engulf");
    check(WHSignal({12,14,12,14},previous,false,WH_ENGULF_WICK)==1,"wick mode closes above previous high");
    check(WHSignal({10,10,6,6},previous,false,WH_ENGULF_WICK)==-1,"wick mode closes below previous low");
    InpEngulfMode=WH_ENGULF_WICK;
    s=calculate({previous,noHuntBuy},0,1315);
    check(s.buy[1]==EMPTY_VALUE,"wick mode filters a body-only engulf");
    s=calculate({previous,{12,14,12,14}},2,1316);
    check(s.buy[1]==12,"wick engulf preview appears");
    s=calculate({previous,noHuntBuy,{13,13,13,13}},2,1320);
    check(s.buy[1]==EMPTY_VALUE,"wick engulf invalidation on close removes preview");
    InpHuntBars=1;
    s=calculate({previous,{12,14,12,14}},0,1315);
    check(s.buy[1]==EMPTY_VALUE,"wick mode still requires hunt when enabled");
    s=calculate({previous,{12,14,6,14}},0,1315);
    check(s.buy[1]==6,"wick mode combines with hunt");

    // Initial bearish candle seeds a down leg. An inside green candle extends
    // that leg; equality at a body boundary does not reset it.
    WHBar d1{15,16,9,10},d2{11,14,10,12},d3{12,13,8,9};
    WHBar bodyBuy{9,14,8.5,12.5},wickBuy{9,15,7,14};
    WHLeg state{},next{};
    WHSeedLeg(d1,state);
    check(state.direction==-1 && state.count==1,"bearish seed starts down leg");
    WHStepLeg(d2,d1,state,3,next); state=next;
    check(state.direction==-1 && state.count==2,"green inside candle continues down leg");
    WHStepLeg(d3,d2,state,3,next); state=next;
    check(state.direction==-1 && state.count==3,"down leg reaches three candles");
    check(WHPriorMoveAllows(1,state,3) && !WHPriorMoveAllows(-1,state,3),"only opposing signal allowed");
    WHStepLeg(bodyBuy,d3,state,3,next);
    check(next.direction==1 && next.count==1,"body reversal starts new leg at one without wick engulf");
    WHBar equalBody{11,14,8,12};
    WHStepLeg(equalBody,d3,state,3,next);
    check(next.direction==-1 && next.count==3,"equal top does not reset and count saturates");
    WHBar doji{10,11,9,10};
    WHSeedLeg(doji,state); check(state.direction==0 && state.count==0,"initial doji has no direction");
    WHStepLeg(doji,doji,state,3,next);
    check(next.direction==0 && next.count==0,"flat dojis alone do not invent prior movement");
    auto invalidMove=d1; invalidMove.close=std::numeric_limits<double>::quiet_NaN();
    WHSeedLeg(d1,state); WHStepLeg(invalidMove,d1,state,3,next);
    check(next.direction==0 && next.count==0,"invalid candle interrupts prior movement");

    InpHuntBars=0; InpEngulfMode=WH_ENGULF_BODY; InpUsePriorMove=true; InpPriorMoveBars=3;
    s=calculate({d1,d2,d3,bodyBuy},0,1434);
    check(s.buy[3]==EMPTY_VALUE && s.direction[2]==-1 && s.count[2]==3,"prior movement ready before preview");
    fake_clock+=1000; OnTimer();
    check(BuyBuffer[3]==8.5,"timer respects confirmed three-candle prior movement");
    check(LegDirectionBuffer[3]==0 && LegCountBuffer[3]==0,"preview does not alter confirmed leg");
    s=calculate({d1,d2,d3,bodyBuy,{12.5,12.5,12.5,12.5}},4,1440);
    check(s.buy[3]==8.5 && s.direction[3]==1 && s.count[3]==1,"confirmed reversal uses old leg then starts new one");
    InpPriorMoveBars=4;
    s=calculate({d1,d2,d3,bodyBuy},0,1435);
    check(s.buy[3]==EMPTY_VALUE,"signal candle excluded from required count");
    InpPriorMoveBars=3;
    s=calculate({d1,d2,bodyBuy},0,1375);
    check(s.buy[2]==EMPTY_VALUE,"two prior candles are insufficient");
    InpUsePriorMove=false;
    s=calculate({d1,d2,bodyBuy},0,1375);
    check(s.buy[2]==8.5,"filter off bypasses insufficient movement");
    InpUsePriorMove=true; InpEngulfMode=WH_ENGULF_WICK;
    s=calculate({d1,d2,d3,bodyBuy},0,1435);
    check(s.buy[3]==EMPTY_VALUE,"prior movement does not bypass wick engulf mode");
    s=calculate({d1,d2,d3,wickBuy},4,1436);
    check(s.buy[3]==7,"wick engulf and prior movement combine");
    // bodyBuy resets down leg even when the selected wick signal doesn't fire.
    WHBar downAgain{12.5,13,8,8.5};
    s=calculate({d1,d2,d3,bodyBuy,downAgain,wickBuy},0,1555);
    check(s.direction[3]==1 && s.count[3]==1 && s.direction[4]==-1 && s.count[4]==1 &&
          s.buy[5]==EMPTY_VALUE,"body-only reversal resets movement under wick signal mode");
    InpHuntBars=3;
    s=calculate({d1,d2,d3,wickBuy},0,1435);
    check(s.buy[3]==7,"all three options allow eligible buy");
    auto noSweep=wickBuy; noSweep.low=8;
    s=calculate({d1,d2,d3,noSweep},4,1436);
    check(s.buy[3]==EMPTY_VALUE,"all options reject equal hunt level");
    auto noBody=wickBuy; noBody.close=12;
    calculate({d1,d2,d3,wickBuy},0,1439);
    s=calculate({d1,d2,d3,noBody,{12,12,12,12}},4,1440);
    check(s.buy[3]==EMPTY_VALUE && s.direction[3]==-1,"final engulf loss removes preview without resetting old leg");
    // Mirror fixtures validate the entire sell path, including the timer and final close.
    std::vector<WHBar> mirrored;
    for(auto b:std::vector<WHBar>{d1,d2,d3,wickBuy}) mirrored.push_back({-b.open,-b.low,-b.high,-b.close});
    s=calculate(mirrored,0,1434); fake_clock+=1000; OnTimer();
    check(SellBuffer[3]==-7 && LegDirectionBuffer[2]==1 && LegCountBuffer[2]==3,"sell preview after three up candles");
    mirrored.push_back({-14,-14,-14,-14});
    s=calculate(mirrored,4,1440);
    check(s.sell[3]==-7 && s.direction[3]==-1 && s.count[3]==1,"sell confirms and starts down leg");

    // Every option combination: incremental state, restart state and mirrored
    // prices must agree. Recalculate after intra-bar changes and window shifts.
    for(int hunt:{0,1,3}) for(auto mode:{WH_ENGULF_BODY,WH_ENGULF_WICK})
    for(bool filter:{false,true}) for(int minimum:{1,3,7}) {
        InpHuntBars=hunt; InpEngulfMode=mode; InpUsePriorMove=filter; InpPriorMoveBars=minimum;
        bars={d1}; calculate(bars,0,1259);
        for(int i=1;i<=40;++i) {
            double o=price(rng),c=price(rng);
            bars.push_back({o,std::max(o,c)+std::abs(price(rng)),std::min(o,c)-std::abs(price(rng)),c});
            auto stream=calculate(bars,i,1200+i*60+55);
            auto full=calculate(bars,0,1200+i*60+55);
            check(stream.buy==full.buy && stream.sell==full.sell && stream.direction==full.direction &&
                  stream.count==full.count,"all option combinations stream equals restart");
            bars.back().close=bars.back().open;
            stream=calculate(bars,i+1,1200+i*60+59);
            full=calculate(bars,0,1200+i*60+59);
            check(stream.buy==full.buy && stream.sell==full.sell && stream.direction==full.direction &&
                  stream.count==full.count,"live edits do not contaminate movement history");
        }
        mirrored.clear();
        for(auto b:bars) mirrored.push_back({-b.open,-b.low,-b.high,-b.close});
        auto normal=calculate(bars,0,3655),mirror=calculate(mirrored,0,3655);
        for(size_t i=0;i<bars.size();++i) {
            check((normal.buy[i]==EMPTY_VALUE ? mirror.sell[i]==EMPTY_VALUE : normal.buy[i]==-mirror.sell[i]) &&
                  (normal.sell[i]==EMPTY_VALUE ? mirror.buy[i]==EMPTY_VALUE : normal.sell[i]==-mirror.buy[i]) &&
                  normal.direction[i]==-mirror.direction[i] && normal.count[i]==mirror.count[i],"full history buy/sell symmetry");
        }
        calculate(bars,0,3655);
        shifted=calculate(bars,int(bars.size()),3715,1260);
        fresh=calculate(bars,0,3715,1260);
        check(shifted.buy==fresh.buy && shifted.sell==fresh.sell && shifted.direction==fresh.direction &&
              shifted.count==fresh.count,"all options reset rolling history correctly");
    }
    InpHuntBars=0; InpUsePriorMove=false; InpEngulfMode=WH_ENGULF_BODY; InpUseEMAFilter=true;
    bars.clear();
    for(int i=0;i<60;++i) { double c=100+i; bars.push_back({c-.2,c+1,c-1,c}); }
    bars.push_back({159,162,158,161});
    s=calculate(bars,0,4854);
    check(s.ema20.back()>s.ema54.back() && s.buy.back()==EMPTY_VALUE,"uptrend still waits for preview window");
    fake_clock+=1000; OnTimer();
    check(BuyBuffer.back()==158,"EMA uptrend allows buy through timer");
    bars.back()={159,160,156,157};
    s=calculate(bars,61,4856);
    check(s.ema20.back()>s.ema54.back() && s.sell.back()==EMPTY_VALUE,"EMA uptrend blocks otherwise valid sell");
    InpUseEMAFilter=false;
    s=calculate(bars,0,4856);
    check(s.sell.back()==160,"EMA filter off restores countertrend sell");
    InpUseEMAFilter=true;
    mirrored.clear(); for(auto b:bars) mirrored.push_back({-b.open,-b.low,-b.high,-b.close});
    s=calculate(mirrored,0,4856);
    check(s.ema20.back()<s.ema54.back() && s.buy.back()==EMPTY_VALUE,"EMA downtrend blocks buy");
    mirrored.back()={-159,-158,-162,-161};
    s=calculate(mirrored,61,4857);
    check(s.sell.back()==-158,"EMA downtrend allows sell");
    mirrored.push_back({-161,-161,-161,-161});
    s=calculate(mirrored,61,4860);
    check(s.sell[60]==-158,"EMA-filtered sell persists after close");

    // Compare actual EMA buffers with a direct weighted sum, rather than a
    // duplicate recursive implementation, on the entire historical sequence.
    s=calculate(bars,0,4855);
    for(int period:{20,54}) for(size_t i=0;i<bars.size();++i) {
        long double alpha=2.0L/(period+1),beta=1-alpha;
        long double expected=std::pow(beta,i)*bars[0].close;
        for(size_t j=1;j<=i;++j) expected+=alpha*std::pow(beta,i-j)*bars[j].close;
        double actual=period==20 ? s.ema20[i] : s.ema54[i];
        check(std::abs(actual-double(expected))<1e-10,"EMA matches independent weighted sum");
    }
    bars.resize(53);
    s=calculate(bars,0,4375);
    check(s.emaCount.back()==53 && s.buy.back()==EMPTY_VALUE,"53 closes are insufficient for EMA filter");
    InpUseEMAFilter=false;
    s=calculate(bars,0,4375); check(s.buy.back()!=EMPTY_VALUE,"filter off does not impose EMA warmup");
    InpUseEMAFilter=true;
    bars.push_back({153,155,152,154});
    s=calculate(bars,53,4435);
    check(s.emaCount.back()==54 && s.buy.back()==152,"54th close enables EMA filter");
    // Explicit equality and unavailable-value guards on a valid candidate.
    std::vector<double> eo{100,100},eh{101,103},el{99,99},ec{100,102};
    calculate({{100,101,99,100},{100,103,99,102}},0,1315);
    EMAValidCountBuffer[1]=54; EMA20Buffer[1]=100; EMA54Buffer[1]=100;
    check(WHSignalAt(1,eo,eh,el,ec)==0,"equal EMAs suppress buy");
    ec[1]=98; el[1]=97;
    check(WHSignalAt(1,eo,eh,el,ec)==0,"equal EMAs suppress sell");
    EMA20Buffer[1]=EMPTY_VALUE;
    check(WHSignalAt(1,eo,eh,el,ec)==0,"missing EMA fails closed");

    // Both live closes engulf the previous body; ONLY the EMA ordering changes.
    bars.assign(60,{100,101,99,100});
    bars.push_back({81,82,79,80});
    bars.push_back({80,140,79,130});
    s=calculate(bars,0,4915);
    check(s.buy.back()==79 && s.ema20.back()>s.ema54.back(),"live EMA crossover permits engulf buy");
    auto closedFast=s.ema20[60],closedSlow=s.ema54[60];
    auto liveFast=s.ema20.back(),liveSlow=s.ema54.back();
    s=calculate(bars,62,4915);
    check(s.ema20.back()==liveFast && s.ema54.back()==liveSlow,"identical repeated tick does not compound EMA");
    bars.back().close=101;
    s=calculate(bars,62,4916); OnTimer();
    check(s.ema20.back()<s.ema54.back() && BuyBuffer.back()==EMPTY_VALUE,"EMA crossover alone removes preview");
    check(s.ema20[60]==closedFast && s.ema54[60]==closedSlow,"live ticks preserve previous closed EMA");
    bars.back().close=130;
    s=calculate(bars,62,4919); check(s.buy.back()==79,"EMA reversal restores preview");
    bars.back().close=101; bars.push_back({101,101,101,101});
    s=calculate(bars,62,4920);
    check(s.buy[61]==EMPTY_VALUE,"failed final EMA trend removes formerly valid preview");
    bars.resize(62); bars.back().close=101; calculate(bars,0,4919);
    bars.back().close=130; bars.push_back({130,130,130,130});
    s=calculate(bars,62,4920);
    check(s.buy[61]==79,"final tick EMA crossover confirms buy even without preview");

    // Invalid price interrupts EMA history; 54 valid closes are required again.
    auto invalidEma=bars;
    invalidEma[10].close=std::numeric_limits<double>::quiet_NaN();
    s=calculate(invalidEma,0,4975);
    check(s.ema20[10]==EMPTY_VALUE && s.emaCount[10]==0 && s.emaCount[11]==1 &&
          s.emaCount.back()==52 && s.buy.back()==EMPTY_VALUE,"invalid close resets EMA warmup");

    // EMA combines with all existing filters. Compare streaming and full
    // recalculation, plus filtered output against the unfiltered candidates.
    for(int hunt:{0,1,3}) for(auto mode:{WH_ENGULF_BODY,WH_ENGULF_WICK}) for(bool move:{false,true}) {
        InpHuntBars=hunt; InpEngulfMode=mode; InpUsePriorMove=move; InpPriorMoveBars=3;
        InpUseEMAFilter=true; bars={{100,101,99,100}}; calculate(bars,0,1259);
        for(int i=1;i<90;++i) {
            double o=100+price(rng),c=100+price(rng);
            bars.push_back({o,std::max(o,c)+3,std::min(o,c)-3,c});
            auto stream=calculate(bars,i,1200+i*60+55),full=calculate(bars,0,1200+i*60+55);
            check(stream.buy==full.buy && stream.sell==full.sell && stream.ema20==full.ema20 &&
                  stream.ema54==full.ema54 && stream.emaCount==full.emaCount,"EMA stream matches full recomputation");
        }
        auto filtered=calculate(bars,0,6595);
        InpUseEMAFilter=false; auto candidates=calculate(bars,0,6595); InpUseEMAFilter=true;
        for(size_t i=0;i<bars.size();++i) {
            bool ready=filtered.emaCount[i]>=54;
            check(filtered.buy[i]==(ready && filtered.ema20[i]>filtered.ema54[i] ? candidates.buy[i] : EMPTY_VALUE) &&
                  filtered.sell[i]==(ready && filtered.ema20[i]<filtered.ema54[i] ? candidates.sell[i] : EMPTY_VALUE),
                  "EMA is an additional directional filter on existing candidates");
        }
        calculate(bars,0,6595);
        auto shiftedEMA=calculate(bars,90,6655,1260),freshEMA=calculate(bars,0,6655,1260);
        check(shiftedEMA.buy==freshEMA.buy && shiftedEMA.sell==freshEMA.sell && shiftedEMA.ema20==freshEMA.ema20 &&
              shiftedEMA.ema54==freshEMA.ema54,"rolling history resets EMA seed and signals");
        bars.resize(25);
        auto shrunk=calculate(bars,90,2695),rebuilt=calculate(bars,0,2695);
        check(shrunk.ema20==rebuilt.ema20 && shrunk.ema54==rebuilt.ema54 && shrunk.buy==rebuilt.buy &&
              shrunk.sell==rebuilt.sell,"shrunk history resets EMA and hides immature signals");
    }
    std::cout<<"EngulfFlow: "<<checks<<" checks passed\n";
}
