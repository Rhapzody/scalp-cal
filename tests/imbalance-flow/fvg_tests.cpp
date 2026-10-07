#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <random>
#include <string>
#include <vector>
#define MathIsValidNumber std::isfinite
#include "../../MQL5/Indicators/ImbalanceFlow/FVGCore.mqh"

#define MathAbs std::abs
template<class T> int ArrayResize(std::vector<T>& a,int n) { a.resize(n); return n; }
void ArraySort(std::vector<double>& a) { std::sort(a.begin(),a.end()); }
#include "dp_core_under_test.hpp"
DPConfig defaults() {
    DPConfig c{}; c.method=DP_SINGLE_OR_LEG; c.zone_mode=DP_BASE_WICK;
    c.atr_length=14;c.relative_bars=20;c.min_leg_bars=2;c.max_leg_bars=4;
    c.breakout_bars=5;c.base_search_bars=5;c.min_body_atr=.8;c.min_body_ratio=.7;
    c.max_tail_ratio=.15;c.min_leg_atr=1.5;c.min_efficiency=.75;c.min_direction_ratio=.66;
    c.max_leg_tail_ratio=.2;c.require_breakout=true;c.breakout_atr=.1;c.reject_time_gaps=true;
    return c;
}
DPConfig g_dp=defaults();
ENUM_FVG_DETECTION InpDetectionMode=FVG_ONLY;
ENUM_FVG_FILL InpDisplacementFillMode=FVG_FILL_FULL;
std::vector<double> DPDirectionBuffer,DPLowerBuffer,DPUpperBuffer,DPKindBuffer;
using datetime=long long;
constexpr double EMPTY_VALUE=std::numeric_limits<double>::max();
int InpLookbackBars=500,InpMaxZones=50,InpExtendBars=10;
double InpMinGapPoints=0,_Point=0.01;
bool InpRequireMiddleDirection=false,InpShowBullish=true,InpShowBearish=true,InpShowFilled=false;
ENUM_FVG_FILL InpFillMode=FVG_FILL_FULL;
int _Period=60;
std::vector<double> DirectionBuffer,LowerBuffer,UpperBuffer;
std::string g_prefix="test_";
datetime g_first_bar=0,g_current_bar=0;
bool stopped=false,draw_failure=false;
int redraws=0,checks=0;
struct Rectangle {
    std::string name;
    FVGZone zone;
    datetime start,confirmed,end;
    bool filled;
    int kind=0;
    bool operator==(const Rectangle& b) const {
        return name==b.name && zone.direction==b.zone.direction && zone.lower==b.zone.lower &&
               zone.upper==b.zone.upper && start==b.start && confirmed==b.confirmed &&
               end==b.end && filled==b.filled && kind==b.kind;
    }
};
std::vector<Rectangle> objects;
template<class T> void ArraySetAsSeries(const std::vector<T>&,bool) {}
template<class T,class V> void ArrayInitialize(std::vector<T>& a,V v) { std::fill(a.begin(),a.end(),v); }
int MathMax(int a,int b) { return std::max(a,b); }
int PeriodSeconds(int period) { return period; }
bool IsStopped() { return stopped; }
void ChartRedraw(int) { ++redraws; }
void ObjectsDeleteAll(int,const std::string& prefix) {
    objects.erase(std::remove_if(objects.begin(),objects.end(),[&](const Rectangle& r) {
        return r.name.find(prefix)==0;
    }),objects.end());
}
bool DrawFVGZone(const FVGZone& z,datetime start,datetime confirmed,datetime end,bool filled,int kind=0) {
    if(draw_failure) return false;
    objects.push_back({g_prefix+"zone_"+std::to_string(confirmed),z,start,confirmed,end,filled,kind});
    return true;
}
#include "fvg_indicator_under_test.hpp"

void check(bool ok,const char* label) {
    ++checks;
    if(!ok) { std::cerr<<"FAIL: "<<label<<'\n'; std::exit(1); }
}
struct Snapshot {
    std::vector<double> direction,lower,upper,dpdir,dplow,dpup,dpkind;
    std::vector<Rectangle> rectangles;
    bool operator==(const Snapshot& b) const {
        return direction==b.direction && lower==b.lower && upper==b.upper && dpdir==b.dpdir && dplow==b.dplow && dpup==b.dpup && dpkind==b.dpkind && rectangles==b.rectangles;
    }
};
Snapshot calculate(const std::vector<FVGBar>& bars,int prev,datetime base=1000,int expected=-1) {
    int n=int(bars.size());
    DPDirectionBuffer.resize(n);DPLowerBuffer.resize(n);DPUpperBuffer.resize(n);DPKindBuffer.resize(n);
    DirectionBuffer.resize(n); LowerBuffer.resize(n); UpperBuffer.resize(n);
    std::vector<double> o,h,l,c;
    std::vector<datetime> t;
    for(int i=0;i<n;++i) {
        o.push_back(bars[i].open); h.push_back(bars[i].high);
        l.push_back(bars[i].low); c.push_back(bars[i].close); t.push_back(base+i*60);
    }
    std::vector<long> ticks(n),vol(n);
    std::vector<int> spreads(n);
    check(OnCalculate(n,prev,t,o,h,l,c,ticks,vol,spreads)==(expected<0 ? n : expected),"OnCalculate result");
    return {DirectionBuffer,LowerBuffer,UpperBuffer,DPDirectionBuffer,DPLowerBuffer,DPUpperBuffer,DPKindBuffer,objects};
}
FVGBar mirror(const FVGBar& b) { return {-b.open,-b.low,-b.high,-b.close}; }

int main() {
    const FVGBar a{10,12,9,11},b{11,16,10,15},c{15,17,14,16};
    const FVGBar far{16,18,15,17},partial{15,16,13,14},touch{15,16,14,15},full{14,15,12,13};
    FVGZone z{};
    check(FVGDetect(a,b,c,0,0.01,false,z),"bullish FVG");
    check(z.direction==1 && z.lower==12 && z.upper==14,"bullish wick boundaries");
    check(!FVGIsFilled(z,far,FVG_FILL_TOUCH),"price outside zone");
    check(FVGIsFilled(z,touch,FVG_FILL_TOUCH),"near edge equality fills touch mode");
    check(!FVGIsFilled(z,touch,FVG_FILL_FULL),"near edge is not full fill");
    check(!FVGIsFilled(z,partial,FVG_FILL_FULL),"partial fill keeps full-fill zone");
    check(FVGIsFilled(z,partial,FVG_FILL_TOUCH),"partial fill retires touch zone");
    check(FVGIsFilled(z,full,FVG_FILL_FULL),"far edge equality fills zone");
    check(FVGIsFilled(z,{8,10,7,9},FVG_FILL_FULL),"gap through zone retires it");
    check(!FVGIsFilled(z,full,static_cast<ENUM_FVG_FILL>(9)),"invalid fill mode");
    check(FVGDetect(a,b,c,200,0.01,false,z),"minimum gap equality");
    check(!FVGDetect(a,b,c,201,0.01,false,z),"gap below minimum excluded");
    check(z.direction==0 && z.lower==0 && z.upper==0,"rejected detection clears output");
    check(!FVGDetect(a,b,{13,15,12,14},0,0.01,false,z),"equal outer wicks are no gap");
    check(!FVGDetect(a,b,{12,15,11,14},0,0.01,false,z),"overlapping wicks are no gap");
    check(!FVGDetect(a,{15,17,14,16},c,0,0.01,false,z),"unbridged session gap excluded");
    check(FVGDetect(a,{15,16,10,11},c,0,0.01,false,z),"opposite middle allowed by default");
    check(!FVGDetect(a,{15,16,10,11},c,0,0.01,true,z),"optional middle direction filter");
    check(!FVGDetect(a,{13,16,10,13},c,0,0.01,true,z),"middle doji fails direction filter");
    check(FVGDetect(a,b,c,0,0.01,true,z),"bullish middle passes filter");
    check(FVGDetect(mirror(a),mirror(b),mirror(c),0,0.01,true,z),"bearish FVG mirror");
    check(z.direction==-1 && z.lower==-14 && z.upper==-12,"bearish wick boundaries");
    check(FVGIsFilled(z,mirror(touch),FVG_FILL_TOUCH),"bearish touch equality");
    check(!FVGIsFilled(z,mirror(partial),FVG_FILL_FULL),"bearish partial fill");
    check(FVGIsFilled(z,mirror(full),FVG_FILL_FULL),"bearish full fill equality");
    for(double bad:{-1.0,std::numeric_limits<double>::quiet_NaN(),std::numeric_limits<double>::infinity()}) {
        check(!FVGDetect(a,b,c,bad,0.01,false,z),"invalid threshold rejected");
        check(!FVGDetect(a,b,c,0,bad,false,z),"invalid point rejected");
    }
    check(!FVGDetect(a,b,c,0,0,false,z),"zero point rejected");
    check(!FVGDetect(a,b,c,1e308,1e308,false,z),"threshold multiplication overflow rejected");
    FVGBar invalid=b; invalid.high=invalid.low-1;
    check(!FVGDetect(a,invalid,c,0,0.01,false,z),"invalid OHLC rejected");
    invalid=b; invalid.open=std::numeric_limits<double>::quiet_NaN();
    check(!FVGDetect(a,invalid,c,0,0.01,false,z),"NaN candle rejected");
    check(FVGDetect({1.0,1.1,0.9,1.05},{1.05,1.3,1.0,1.25},{1.25,1.4,1.2,1.3},
                    10,0.01,false,z),"decimal point minimum survives subtraction rounding");

    calculate({},0);
    calculate({a},0);
    auto live=calculate({a,b,c},0);
    check(live.rectangles.empty(),"third forming candle creates no FVG");
    auto confirmed=calculate({a,b,c,far},3);
    check(confirmed.direction[2]==1 && confirmed.lower[2]==12 && confirmed.upper[2]==14,
          "signal recorded on third closed candle");
    check(confirmed.rectangles.size()==1,"one visible confirmed zone");
    check(confirmed.rectangles[0].start==1000 && confirmed.rectangles[0].confirmed==1120 &&
          confirmed.rectangles[0].end==1780 && !confirmed.rectangles[0].filled,"rectangle anchors and extension");
    int before=redraws;
    check(calculate({a,b,c,full},4)==confirmed,"forming fill does not change confirmed results");
    check(redraws==before,"no repeated rendering on ticks");
    auto filled=calculate({a,b,c,full,far},4);
    check(filled.rectangles.empty(),"filled zone hidden on next bar");
    check(filled.direction[2]==1,"detection buffer preserved after fill");
    InpShowFilled=true;
    filled=calculate({a,b,c,full,far,full,far},0);
    auto old=std::find_if(filled.rectangles.begin(),filled.rectangles.end(),[](const Rectangle& r) { return r.confirmed==1120; });
    check(old!=filled.rectangles.end() && old->filled && old->end==1240,"filled zone ends at first fill candle close");
    InpShowFilled=false;
    InpFillMode=FVG_FILL_TOUCH;
    check(calculate({a,b,c,far},0).rectangles.size()==1,"third candle never fills its own zone");
    check(calculate({a,b,c,touch,far},0).rectangles.empty(),"touch mode hides at first near edge touch");
    InpFillMode=FVG_FILL_FULL;
    check(calculate({a,b,c,partial,far},0).rectangles.size()==1,"full mode retains partially filled rectangle");
    InpShowBullish=false;
    auto hidden=calculate({a,b,c,far},0);
    check(hidden.rectangles.empty() && hidden.direction[2]==1,"direction display filter does not filter buffers");
    InpShowBullish=true;
    InpExtendBars=0;
    check(calculate({a,b,c,far},0).rectangles[0].end==1180,"zero extension ends at current bar");
    InpExtendBars=10;
    InpLookbackBars=3;
    auto expired=calculate({a,b,c,touch,far},0);
    check(expired.direction[2]==EMPTY_VALUE && expired.rectangles.empty(),"lookback requires all three candles in window");
    InpLookbackBars=500;

    std::mt19937 random(71);
    std::vector<FVGBar> bars;
    double last=100;
    for(int i=0;i<150;++i) {
        double o=last,close=o+(int(random()%33)-16)*0.25;
        bars.push_back({o,std::max(o,close)+0.25,std::min(o,close)-0.25,close});
        last=close;
    }
    for(auto mode:{FVG_FILL_FULL,FVG_FILL_TOUCH}) for(bool keep:{false,true}) {
        InpFillMode=mode; InpShowFilled=keep; InpLookbackBars=35; InpMaxZones=3;
        int prev=0;
        for(size_t n=1;n<=bars.size();++n) {
            std::vector<FVGBar> prefix(bars.begin(),bars.begin()+n);
            auto incremental=calculate(prefix,prev);
            check(incremental==calculate(prefix,0),"new-bar rebuild equals full history");
            check(incremental.direction.back()==EMPTY_VALUE && incremental.lower.back()==EMPTY_VALUE &&
                  incremental.upper.back()==EMPTY_VALUE,"forming buffers empty");
            check(incremental.rectangles.size()<=3,"visible limit enforced");
            for(size_t j=1;j<incremental.rectangles.size();++j)
                check(incremental.rectangles[j-1].confirmed>incremental.rectangles[j].confirmed,"newest zones selected first");
            prev=int(n);
        }
        calculate(std::vector<FVGBar>(bars.begin(),bars.begin()+20),0);
        auto catchup=calculate(bars,20);
        check(catchup==calculate(bars,0),"multiple missed bars catch up");
        auto shifted=bars; shifted.erase(shifted.begin()); shifted.push_back(a);
        auto rolling=calculate(shifted,int(bars.size()),1060);
        check(rolling==calculate(shifted,0,1060),"capped history rebuild");
        auto shorter=std::vector<FVGBar>(bars.begin(),bars.begin()+30);
        auto shrink=calculate(shorter,int(bars.size()));
        check(shrink==calculate(shorter,0),"shrinking history rebuild");
        auto loaded=calculate(bars,30,-1000);
        check(loaded==calculate(bars,0,-1000),"history reload rebuild");
    }

    InpShowFilled=false; InpFillMode=FVG_FILL_FULL;
    objects.push_back({"other_instance_zone",{1,12,14},1,2,3,false});
    auto isolated=calculate({a,b,c,far},0);
    check(isolated.rectangles.size()==2 && isolated.rectangles.front().name=="other_instance_zone",
          "rebuild preserves other instance objects");
    OnDeinit(0);
    check(objects.size()==1 && objects.front().name=="other_instance_zone","deinit only deletes owned objects");
    g_prefix=""; OnDeinit(0);
    check(objects.size()==1,"failed initialization cannot delete all chart objects");
    g_prefix="test_"; objects.clear();
    stopped=true;
    calculate({a,b,c,far},0,1000,0);
    stopped=false;
    check(calculate({a,b,c,far},0).rectangles.size()==1,"interrupted calculation retries");
    draw_failure=true;
    calculate({a,b,c,far},0,1000,0);
    draw_failure=false;
    check(calculate({a,b,c,far},0).rectangles.size()==1,"failed drawing retries");

    // Gapless impulses: exercise the production detector and actual rebuild/OnCalculate.
    std::vector<FVGBar> dpbars(30,{100,101,99,100});
    dpbars.push_back({100,104.1,99.9,104});
    dpbars.push_back({104,104.5,103.5,104.2}); // forming bar
    std::vector<long> times; for(size_t i=0;i<dpbars.size();i++) times.push_back(1000+i*60);
    int source,kind;
    auto cfg=defaults(); cfg.method=DP_SINGLE_ONLY;
    check(DPConfigValid(cfg),"default displacement config valid");
    check(DPDetect(cfg,dpbars,times,dpbars.size(),0,30,60,z,source,kind),"gapless single candle displacement");
    check(z.direction==1&&z.lower==99&&z.upper==101&&source==29&&kind==1,"base wick zone before impulse");
    check(!FVGDetect(dpbars[28],dpbars[29],dpbars[30],0,.01,false,z),"displacement fixture really has no FVG");
    auto neg=dpbars;for(auto& bar:neg)bar=mirror(bar);
    check(DPDetect(cfg,neg,times,neg.size(),0,30,60,z,source,kind)&&z.direction==-1&&z.lower==-101&&z.upper==-99,"bearish symmetry");
    auto variant=dpbars;variant[30].high=108;
    check(!DPDetect(cfg,variant,times,variant.size(),0,30,60,z,source,kind),"long directional wick rejected");
    variant=dpbars;variant[30].low=90;
    check(!DPDetect(cfg,variant,times,variant.size(),0,30,60,z,source,kind),"small body ratio rejected");
    cfg.min_body_atr=2.01;
    check(!DPDetect(cfg,dpbars,times,dpbars.size(),0,30,60,z,source,kind),"body relative to prior ATR filter");
    cfg.min_body_atr=2;
    check(DPDetect(cfg,dpbars,times,dpbars.size(),0,30,60,z,source,kind),"ATR excludes signal candle and accepts equality");
    cfg=defaults();cfg.method=DP_SINGLE_ONLY;cfg.breakout_atr=2;
    check(!DPDetect(cfg,dpbars,times,dpbars.size(),0,30,60,z,source,kind),"breakout buffer rejects insufficient distance");
    cfg.require_breakout=false;
    check(DPDetect(cfg,dpbars,times,dpbars.size(),0,30,60,z,source,kind),"breakout filter can be disabled");
    cfg=defaults();cfg.method=DP_SINGLE_ONLY;cfg.min_relative_body=1.5;
    check(!DPDetect(cfg,dpbars,times,dpbars.size(),0,30,60,z,source,kind),"zero median body is rejected without division by zero");
    variant=dpbars;for(int i=0;i<30;i++)variant[i]={100,101,99,100.5};
    check(DPDetect(cfg,variant,times,variant.size(),0,30,60,z,source,kind),"relative body uses previous candles only");
    cfg.min_relative_body=9;
    check(!DPDetect(cfg,variant,times,variant.size(),0,30,60,z,source,kind),"relative body threshold adjustable");
    cfg=defaults();cfg.method=DP_SINGLE_ONLY;cfg.zone_mode=DP_BASE_BODY;
    check(!DPDetect(cfg,dpbars,times,dpbars.size(),0,30,60,z,source,kind),"zero-width doji body zone excluded");
    variant=dpbars;variant[29]={100.5,101,99,100};
    check(DPDetect(cfg,variant,times,variant.size(),0,30,60,z,source,kind)&&z.lower==100&&z.upper==100.5,"base body zone boundaries");
    cfg.zone_mode=DP_IMPULSE_BODY;
    check(DPDetect(cfg,dpbars,times,dpbars.size(),0,30,60,z,source,kind)&&source==30&&z.lower==100&&z.upper==104,"impulse body alternative zone");
    cfg=defaults();cfg.method=DP_SINGLE_ONLY;
    auto gaps=times;gaps[30]+=60;gaps[31]+=60;
    check(!DPDetect(cfg,dpbars,gaps,dpbars.size(),0,30,60,z,source,kind),"time gap cannot manufacture displacement");
    cfg.reject_time_gaps=false;
    check(DPDetect(cfg,dpbars,gaps,dpbars.size(),0,30,60,z,source,kind),"time gap filter switch");
    cfg=defaults();cfg.method=DP_SINGLE_ONLY;
    check(!DPDetect(cfg,dpbars,times,dpbars.size(),0,5,60,z,source,kind),"insufficient ATR history rejected");
    check(!DPDetect(cfg,dpbars,times,dpbars.size(),30,30,60,z,source,kind),"base cannot precede lookback");
    variant=dpbars;variant[31]={0,0,0,0};
    check(DPDetect(cfg,variant,times,variant.size(),0,30,60,z,source,kind),"future candle cannot affect signal");
    variant=dpbars;variant[25].close=INFINITY;
    check(!DPDetect(cfg,variant,times,variant.size(),0,30,60,z,source,kind),"invalid historical OHLC rejected");
    auto bad=cfg;bad.min_body_atr=NAN;check(!DPConfigValid(bad),"NaN config rejected");
    bad=cfg;bad.min_direction_ratio=1.01;check(!DPConfigValid(bad),"ratio above one rejected");
    bad=cfg;bad.min_leg_bars=5;check(!DPConfigValid(bad),"inverted leg window rejected");
    bad=cfg;bad.breakout_bars=0;check(!DPConfigValid(bad),"empty breakout window rejected");
    bad=cfg;bad.zone_mode=static_cast<ENUM_DP_ZONE>(9);check(!DPConfigValid(bad),"invalid zone mode rejected");

    auto leg=std::vector<FVGBar>(dpbars.begin(),dpbars.begin()+30);
    leg.push_back({100,102.1,99.9,102});leg.push_back({102,102.1,101.4,101.5});
    leg.push_back({101.5,104.1,101.4,104});leg.push_back({104,104.5,103.5,104.2});
    times.clear();for(size_t i=0;i<leg.size();i++)times.push_back(1000+i*60);
    cfg=defaults();cfg.method=DP_LEG_ONLY;cfg.min_leg_bars=3;cfg.max_leg_bars=3;
    check(DPDetect(cfg,leg,times,leg.size(),0,32,60,z,source,kind)&&kind==2&&source==29,"three-bar impulse with one counter candle");
    cfg.min_direction_ratio=.67;
    check(!DPDetect(cfg,leg,times,leg.size(),0,32,60,z,source,kind),"2/3 passes .66 but not .67");
    cfg.min_direction_ratio=.66;cfg.min_efficiency=.81;
    check(!DPDetect(cfg,leg,times,leg.size(),0,32,60,z,source,kind),"efficiency includes every close change from pre-leg close");
    cfg.min_efficiency=.8;
    check(DPDetect(cfg,leg,times,leg.size(),0,32,60,z,source,kind),"efficiency equality accepted");
    cfg.min_leg_atr=2.01;
    check(!DPDetect(cfg,leg,times,leg.size(),0,32,60,z,source,kind),"leg ATR threshold adjustable");
    cfg.min_leg_atr=1.5;neg=leg;for(auto& bar:neg)bar=mirror(bar);
    check(DPDetect(cfg,neg,times,neg.size(),0,32,60,z,source,kind)&&z.direction==-1,"multi-bar sell symmetry");

    InpLookbackBars=500;InpMaxZones=50;InpShowFilled=false;InpShowBullish=true;InpShowBearish=true;
    InpDetectionMode=FVG_AND_DISPLACEMENT;g_dp=defaults();g_dp.method=DP_SINGLE_ONLY;
    auto both=calculate(dpbars,0);
    check(both.direction[30]==EMPTY_VALUE&&both.dpdir[30]==1&&both.dpkind[30]==1,"separate buffers for gapless displacement");
    check(both.rectangles.size()==1&&both.rectangles[0].kind==1,"displacement drawn without FVG");
    auto dp_live=calculate(std::vector<FVGBar>(dpbars.begin(),dpbars.end()-1),0);
    check(dp_live.dpdir.back()==EMPTY_VALUE&&dp_live.rectangles.empty(),"forming impulse never signals");
    variant=dpbars;variant[31]={104,108.1,103.9,108};variant.push_back({108,108.5,107.5,108.2});
    auto dedup=calculate(variant,0);
    check(dedup.dpdir[30]==1&&dedup.dpdir[31]==EMPTY_VALUE,"same source and direction cannot produce duplicate displacement");
    variant=dpbars;variant[29]={100,102,99,101.5};variant[30]={101.5,106.1,101.1,106};
    variant[31]={106,106.5,105.5,106.2};
    auto coexist=calculate(variant,0);
    check(coexist.direction[30]==1&&coexist.dpdir[30]==1&&coexist.rectangles.size()==2,"FVG and displacement coexist on the same candle");
    InpMaxZones=1;
    auto capped=calculate(variant,0);
    check(capped.rectangles.size()==1&&capped.rectangles[0].kind==0&&capped.dpdir[30]==1,"FVG priority at shared display cap preserves both buffers");
    InpMaxZones=50;
    InpDetectionMode=FVG_ONLY;
    check(calculate(dpbars,0).dpdir[30]==EMPTY_VALUE,"FVG-only mode disables new detector");
    InpDetectionMode=DISPLACEMENT_ONLY;
    check(calculate({a,b,c,far},0).direction[2]==EMPTY_VALUE,"displacement-only disables FVG buffers");
    InpShowBullish=false;
    auto dp_hidden=calculate(dpbars,0);
    check(dp_hidden.dpdir[30]==1&&dp_hidden.rectangles.empty(),"display filter leaves displacement buffers intact");
    InpShowBullish=true;
    variant=dpbars;variant[31]={104,104.2,100.5,102};variant.push_back({102,103,101.5,102.5});
    InpDisplacementFillMode=FVG_FILL_FULL;
    check(calculate(variant,0).rectangles.size()==1,"displacement partial fill remains active");
    InpDisplacementFillMode=FVG_FILL_TOUCH;
    check(calculate(variant,0).rectangles.empty(),"displacement touch mode retires zone");
    InpShowFilled=true;
    auto dp_filled=calculate(variant,0);
    check(dp_filled.rectangles.size()==1&&dp_filled.rectangles[0].filled&&dp_filled.rectangles[0].end==1000+32*60,"filled displacement ends after first touch candle");
    InpShowFilled=false;InpDisplacementFillMode=FVG_FILL_FULL;
    InpDetectionMode=FVG_AND_DISPLACEMENT;g_dp=defaults();g_dp.atr_length=3;g_dp.require_breakout=false;g_dp.min_body_atr=.4;
    InpLookbackBars=35;InpMaxZones=3;
    int dp_prev=0;
    for(size_t n=1;n<=bars.size();n++) {
        auto prefix=std::vector<FVGBar>(bars.begin(),bars.begin()+n);
        auto incremental=calculate(prefix,dp_prev);
        check(incremental==calculate(prefix,0),"combined incremental equals full rebuild");
        check(incremental.dpdir.back()==EMPTY_VALUE,"combined forming buffer remains empty");
        check(incremental.rectangles.size()<=3,"both types share visible zone budget");
        dp_prev=n;
    }
    std::cout<<"ImbalanceFlow: "<<checks<<" checks passed\n";
}
