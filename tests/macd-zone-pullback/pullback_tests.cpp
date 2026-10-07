#include <algorithm>
#include <cmath>
#include <cstring>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <random>
#include <vector>
#define MathIsValidNumber std::isfinite
#define MathAbs std::abs
#define MathMax std::max
template<class T> void ZeroMemory(T& value) { std::memset(&value,0,sizeof(value)); }
template<class T> int ArrayResize(std::vector<T>& a,int n) { a.resize(n); return n; }
bool IsStopped() { return false; }
#include "PullbackCore.mqh"

int checks=0;
void check(bool value,const char* message) {
    ++checks;
    if(!value) { std::cerr<<"FAIL: "<<message<<'\n'; std::exit(1); }
}
RPConfig config() {
    RPConfig c{};
    c.macd={12,26,9,0,14,MS_PRICE,0,0.01,MS_HISTOGRAM_COLOR};
    c.zones=RP_BOTH; c.strength=RP_FVG_OR_DISPLACEMENT;
    c.min_leg_atr=1; c.min_fvg_atr=.1; c.min_efficiency=.65; c.min_body_ratio=.5;
    c.max_leg_bars=30; c.zone_life_bars=144; c.confirmation_bars=30; c.max_close_tail_ratio=.25;
    return c;
}
MSBar mirror(MSBar b) { return {b.time,-b.open,-b.low,-b.high,-b.close}; }
MSEvent pivot(int type,int classification,int index,long time,double price) {
    MSEvent e{}; e.type=type; e.classification=classification; e.pivot_index=index;
    e.confirm_index=index+1; e.pivot_time=time; e.confirm_time=time+60; e.price=price;
    return e;
}
void primeM1(RPState& s,double previous=13) {
    s.m1.count=1; s.m1.fast=previous; s.m1.slow=previous;
    s.m1.previous_close=previous; s.m1.atr=1;
    s.has_high1=true; s.high1=pivot(1,MS_LH,0,1000,12.5);
    s.has_low1=true; s.low1=pivot(-1,MS_LL,1,1060,10);
}
RPState waiting(const RPConfig& c,int direction=1) {
    RPState s; RPReset(s);
    RPAddZone(s,c,{3000,10,12,9.5,11},RP_SWING_ZONE,1,2,12,3,4200,14.5);
    if(direction==-1) {
        s.zones[0].direction=-1; s.zones[0].lower=-12; s.zones[0].upper=-9.5; s.zones[0].sr=-12;
    }
    primeM1(s);
    if(direction==-1) {
        s.m1.fast=-13; s.m1.slow=-13; s.m1.previous_close=-13;
        s.high1=pivot(1,MS_HH,1,1060,-10);
        s.low1=pivot(-1,MS_HL,0,1000,-12.5);
    }
    return s;
}
bool same(const RPEntry& a,const RPEntry& b) {
    return a.direction==b.direction && a.kind==b.kind && a.quality==b.quality &&
           a.zone_serial==b.zone_serial && a.time==b.time && a.price==b.price &&
           a.trigger==b.trigger && a.lower==b.lower && a.upper==b.upper && a.sr==b.sr;
}
void sameEntries(const std::vector<RPEntry>& a,const std::vector<RPEntry>& b) {
    check(a.size()==b.size(),"event count matches");
    for(size_t i=0;i<a.size();++i) check(same(a[i],b[i]),"event values match");
}

int main() {
    auto c=config();
    check(RPConfigValid(c),"default config valid");
    auto bad=c; bad.macd.swing_mode=MS_MACD_CROSS;
    check(!RPConfigValid(bad),"cross mode prohibited");
    bad=c; bad.min_efficiency=1.01; check(!RPConfigValid(bad),"efficiency bounded");
    bad=c; bad.min_leg_atr=std::numeric_limits<double>::quiet_NaN();
    check(!RPConfigValid(bad),"NaN rejected");
    std::vector<MSBar> bars{{3000,10,12,9.5,11},{3300,10.5,11,9,10},
                            {3600,10,12.5,9.8,12},{3900,12,15,11.5,14.5}};
    check(RPQuality(c,bars,1,3,1,1)==2,"qualifying FVG leg");
    auto reflected=bars; for(auto& b:reflected) b=mirror(b);
    check(RPQuality(c,reflected,1,3,-1,1)==2,"bearish FVG leg");
    check(RPQuality(c,bars,1,3,-1,1)==0,"opposing impulse rejected");
    check(RPQuality(c,bars,1,3,1,10)==0,"weak net movement rejected even with FVG");
    check(RPQuality(c,bars,1,3,1,0)==0,"zero ATR rejected");
    auto missing=bars; missing[2].time+=60;
    check(RPQuality(c,missing,1,3,1,1)==0,"session gap cannot fabricate impulse");
    auto soft=bars; soft[3].low=10.9; // No gap vs origin high 11.
    check(RPQuality(c,soft,1,3,1,1)==1,"strong displacement without FVG");
    auto strict=c; strict.strength=RP_FVG_ONLY;
    check(RPQuality(strict,soft,1,3,1,1)==0,"FVG-only filter");
    auto wick=soft; wick[3].high=20;
    check(RPQuality(c,wick,1,3,1,1)==0,"long rejection wick fails displacement");
    auto doji=soft; doji[3].open=14.5;
    check(RPQuality(c,doji,1,3,1,1)==0,"doji breakout fails displacement");
    auto choppy=std::vector<MSBar>{{3000,10,11,9,10},{3300,10,15,9,14},
                                 {3600,14,15,9,10},{3900,10,15,9,14.5}};
    check(RPQuality(c,choppy,0,3,1,1)==0,"low directional efficiency rejected");
    strict=c; strict.max_leg_bars=3;
    check(RPQuality(strict,choppy,0,3,1,1)==0,"overlong leg rejected");

    // Isolate the setup/lifecycle rules from the separately exercised real MACD engine.
    c.macd.warmup=100000;
    RPState s; RPReset(s);
    s.has_high5=true; s.high5=pivot(1,MS_HH,0,3000,12);
    s.has_low5=true; s.low5=pivot(-1,MS_HL,1,3300,9);
    s.m5.atr=1;
    RPProcessM5(s,c,bars,3);
    check(s.serial==2,"both zone types created");
    check(s.zones[0].lower==9.5 && s.zones[0].upper==12 && s.zones[0].sr==12,"swing zone uses whole wick range");
    check(s.zones[1].lower==9 && s.zones[1].upper==11 && s.zones[1].kind==RP_ORIGIN_ZONE,
          "origin zone uses last opposing launch candle");
    check(s.zones[0].born_time==4200,"zone known at M5 breakout close");
    RPProcessM5(s,c,bars,3);
    check(s.serial==2,"same target does not create repeated setups");
    auto only=c; only.zones=RP_ORIGIN_ZONE;
    RPReset(s); RPCreateSetup(s,only,bars,3,1,pivot(1,MS_HH,0,3000,12),pivot(-1,MS_HL,1,3300,9),true,1);
    check(s.serial==1 && s.zones[0].kind==RP_ORIGIN_ZONE,"origin-only mode");
    only.zones=RP_SWING_ZONE;
    RPReset(s); RPCreateSetup(s,only,bars,3,1,pivot(1,MS_HH,0,3000,12),pivot(-1,MS_HL,1,3300,9),true,1);
    check(s.serial==1 && s.zones[0].kind==RP_SWING_ZONE,"swing-only mode");
    RPReset(s); RPCreateSetup(s,c,bars,3,1,pivot(1,MS_HH,0,3000,12),pivot(-1,MS_HL,1,3300,9),false,1);
    check(s.serial==0,"no invented impulse origin");
    RPReset(s); RPCreateSetup(s,c,reflected,3,-1,pivot(-1,MS_LL,0,3000,-12),pivot(1,MS_LH,1,3300,-9),true,1);
    check(s.serial==2 && s.zones[0].direction==-1,"bearish setup symmetry");
    RPEntry buy{},sell{};
    MSBar touch{4200,12.2,12.3,11.6,11.8},breakout{4260,11.8,13,11.7,12.7};
    for(int direction:{1,-1}) {
        s=waiting(c,direction);
        auto t=direction==1 ? touch : mirror(touch);
        auto b=direction==1 ? breakout : mirror(breakout);
        RPProcessM1(s,c,t,5,buy,sell);
        check(s.zones[0].status==RP_TOUCHED && buy.direction==0 && sell.direction==0,"touch arms without entry");
        RPProcessM1(s,c,b,6,buy,sell);
        auto entry=direction==1 ? buy : sell;
        check(entry.direction==direction && entry.trigger==direction*12.5 && entry.time==4260,
              "later close through LH or HL produces entry");
        check(s.zones[0].status==RP_SIGNALED,"zone consumed after entry");
        b.time+=60;
        RPProcessM1(s,c,b,7,buy,sell);
        check(buy.direction==0 && sell.direction==0,"one entry per setup");
    }
    s=waiting(c);
    auto early=touch; early.time=4140;
    RPProcessM1(s,c,early,4,buy,sell);
    check(s.zones[0].status==RP_WAITING,"M1 inside M5 breakout cannot retest its zone");
    s=waiting(c); RPProcessM1(s,c,touch,5,buy,sell);
    auto wickOnly=breakout; wickOnly.close=12.5;
    RPProcessM1(s,c,wickOnly,6,buy,sell);
    check(buy.direction==0,"wick break and equal close insufficient");
    breakout.time=4320; RPProcessM1(s,c,breakout,7,buy,sell);
    check(buy.direction==1,"strict close above LH triggers");
    breakout.time=4260;
    s=waiting(c); s.m1.previous_close=12;
    auto sameBar=touch; sameBar.high=13; sameBar.close=12.7;
    RPProcessM1(s,c,sameBar,5,buy,sell);
    check(s.zones[0].status==RP_TOUCHED && buy.direction==0,"same candle touch and break not tradable");
    RPProcessM1(s,c,breakout,6,buy,sell);
    check(buy.direction==0,"same-bar break cannot be reused later");
    s=waiting(c); s.m1.previous_close=12;
    auto beforeTouch=breakout; beforeTouch.time=4140; beforeTouch.low=12.1;
    RPProcessM1(s,c,beforeTouch,4,buy,sell);
    RPProcessM1(s,c,touch,5,buy,sell);
    RPProcessM1(s,c,breakout,6,buy,sell);
    check(buy.direction==0,"break before proximity cannot be recycled");
    s=waiting(c); s.high1.classification=MS_HH;
    RPProcessM1(s,c,touch,5,buy,sell); RPProcessM1(s,c,breakout,6,buy,sell);
    check(buy.direction==0,"must break a Lower High, not arbitrary high");
    s=waiting(c);
    RPProcessM1(s,c,{4200,10,11,8,9},5,buy,sell);
    check(s.zones[0].status==RP_INVALID && buy.direction==0,"M1 close beyond distal invalidates");
    s=waiting(c);
    RPProcessM1(s,c,{4200,10,11,8,10},5,buy,sell);
    check(s.zones[0].status==RP_TOUCHED,"wick outside zone does not invalidate by itself");
    s=waiting(c); RPProcessM1(s,c,touch,5,buy,sell);
    RPProcessM1(s,c,breakout,36,buy,sell);
    check(s.zones[0].status==RP_EXPIRED && buy.direction==0,"confirmation timeout");
    s=waiting(c); auto shortLife=c; shortLife.zone_life_bars=1;
    auto extended=bars; extended.push_back({4200,14.5,15,14,14.8});
    RPProcessM5(s,shortLife,extended,4);
    check(s.zones[0].status==RP_EXPIRED,"M5 zone lifetime");
    s=waiting(c);
    RPAddZone(s,c,{3300,10,12,9,11},RP_ORIGIN_ZONE,1,2,12,3,4200,14.5);
    RPProcessM1(s,c,touch,5,buy,sell); RPProcessM1(s,c,breakout,6,buy,sell);
    check(buy.direction==1 && s.zones[0].status==RP_SIGNALED && s.zones[1].status==RP_SIGNALED,
          "sibling zones share one entry opportunity");

    // Configurable filters, checked in both directions against the same candles.
    for(int direction:{1,-1}) {
        auto tuned=c; tuned.m1_break_buffer_points=30;
        s=waiting(c,direction);
        auto t=direction==1 ? touch : mirror(touch);
        auto b=direction==1 ? breakout : mirror(breakout);
        RPProcessM1(s,tuned,t,5,buy,sell);
        RPProcessM1(s,tuned,b,6,buy,sell);
        check(!buy.direction && !sell.direction,"raw break below buffer does not signal");
        check(direction==1 ? !s.broken_high1 : !s.broken_low1,"sub-buffer break preserves swing opportunity");
        b.time+=60; b.close=direction*12.8;
        RPProcessM1(s,tuned,b,7,buy,sell);
        check(!buy.direction && !sell.direction,"close equal to buffered level is insufficient");
        b.time+=60; b.close=direction*12.9;
        RPProcessM1(s,tuned,b,8,buy,sell);
        auto e=direction==1 ? buy : sell;
        check(e.direction==direction && e.trigger==direction*12.5,"buffered entry retains raw pattern pivot");

        tuned=c; tuned.touch_mode=RP_TOUCH_CLOSE;
        auto skim=touch; skim.close=12.1;
        if(direction==-1) skim=mirror(skim);
        s=waiting(c,direction); RPProcessM1(s,tuned,skim,5,buy,sell);
        check(s.zones[0].status==RP_WAITING,"close-touch excludes wick-only overlap");
        RPProcessM1(s,tuned,t,6,buy,sell);
        check(s.zones[0].status==RP_TOUCHED,"close inside zone arms close-touch mode");
        s=waiting(c,direction); RPProcessM1(s,c,skim,5,buy,sell);
        check(s.zones[0].status==RP_TOUCHED,"default wick-touch includes overlap");
        tuned=c; tuned.invalidate_mode=RP_INVALIDATE_WICK;
        auto sweep=MSBar{4200,10,11,8,10};
        if(direction==-1) sweep=mirror(sweep);
        s=waiting(c,direction); RPProcessM1(s,tuned,sweep,5,buy,sell);
        check(s.zones[0].status==RP_INVALID,"wick invalidation rejects distal sweep");
        s=waiting(c,direction); RPProcessM1(s,c,sweep,5,buy,sell);
        check(s.zones[0].status==RP_TOUCHED,"default close invalidation permits distal sweep");

        tuned=c; tuned.side=direction==1 ? RP_SELL_ONLY : RP_BUY_ONLY;
        RPReset(s);
        auto base=direction==1 ? bars[0] : reflected[0];
        check(!RPAddZone(s,tuned,base,RP_SWING_ZONE,direction,2,direction*12,3,4200,direction*14.5),
              "opposite-side zone creation blocked");
        s=waiting(c,direction); RPProcessM1(s,tuned,t,5,buy,sell);
        b=direction==1 ? breakout : mirror(breakout);
        RPProcessM1(s,tuned,b,6,buy,sell);
        check(!buy.direction && !sell.direction,"opposite-side entries blocked");

        tuned=c; tuned.m5_break_buffer_points=250;
        RPReset(s); s.m5.atr=1;
        if(direction==1) {
            s.has_high5=s.has_low5=true; s.high5=pivot(1,MS_HH,0,3000,12); s.low5=pivot(-1,MS_HL,1,3300,9);
        } else {
            s.has_high5=s.has_low5=true; s.low5=pivot(-1,MS_LL,0,3000,-12); s.high5=pivot(1,MS_LH,1,3300,-9);
        }
        auto path=direction==1 ? bars : reflected;
        RPProcessM5(s,tuned,path,3);
        check(s.serial==0 && (direction==1 ? !s.broken_high5 : !s.broken_low5),"M5 equal buffered close preserves target");
        auto next=MSBar{4200,14.5,15,14,14.6};
        path.push_back(direction==1 ? next : mirror(next));
        RPProcessM5(s,tuned,path,4);
        check(s.serial==2,"later M5 close beyond buffer creates setup");
    }
    auto tuned=c; tuned.max_close_tail_ratio=.1;
    check(RPQuality(tuned,soft,1,3,1,1)==0,"stricter tail filter rejects displacement");
    tuned.max_close_tail_ratio=.2;
    check(RPQuality(tuned,soft,1,3,1,1)==1,"relaxed tail filter accepts displacement");
    tuned.max_close_tail_ratio=0;
    check(RPQuality(tuned,bars,1,3,1,1)==2,"tail filter does not replace FVG qualification");
    bad=c; bad.m5_break_buffer_points=-1; check(!RPConfigValid(bad),"negative M5 buffer rejected");
    bad=c; bad.m1_break_buffer_points=std::numeric_limits<double>::infinity(); check(!RPConfigValid(bad),"infinite M1 buffer rejected");
    bad=c; bad.max_close_tail_ratio=1.01; check(!RPConfigValid(bad),"tail ratio bounded");
    bad=c; bad.side=static_cast<ENUM_RP_SIDE>(3); check(!RPConfigValid(bad),"unknown side rejected");
    bad=c; bad.touch_mode=static_cast<ENUM_RP_TOUCH>(2); check(!RPConfigValid(bad),"unknown touch mode rejected");
    bad=c; bad.invalidate_mode=static_cast<ENUM_RP_INVALIDATE>(2); check(!RPConfigValid(bad),"unknown invalidation rejected");

    // Real MACD, both frames, aggregated from the same deterministic M1 path.
    std::mt19937 random(452);
    std::vector<MSBar> one,five;
    double price=100;
    for(int i=0;i<3000;++i) {
        double drift=((i/25)%2==0 ? .22 : -.19);
        double close=price+drift+(int(random()%41)-20)*.04;
        one.push_back({3000+i*60,price,std::max(price,close)+.07,std::min(price,close)-.07,close});
        price=close;
        if(i%5==4) {
            MSBar aggregate=one[i-4]; aggregate.close=one[i].close;
            for(int j=i-3;j<=i;++j) { aggregate.high=std::max(aggregate.high,one[j].high); aggregate.low=std::min(aggregate.low,one[j].low); }
            five.push_back(aggregate);
        }
    }
    c=config(); c.macd.fast=3; c.macd.slow=7; c.macd.signal=3;
    c.min_leg_atr=.5; c.min_efficiency=.4; c.min_body_ratio=.2;
    std::vector<RPEntry> full;
    const long horizon=one.back().time+60;
    check(RPReplay(s,c,one,int(one.size()),five,int(five.size()),horizon,full),"full replay succeeds");
    check(s.serial>0,"real MACD creates qualified setups");
    check(!full.empty(),"real M5 to M1 path produces entries");
    for(const auto& e:full) {
        check(e.time+60<=horizon,"signal within known horizon");
        check(e.direction==1 ? e.price>e.trigger : e.price<e.trigger,"all entries close past trigger");
    }
    // Leave ALL future data in arrays. Horizon must still reproduce truncated replay.
    for(int n=200;n<=3000;n+=37) {
        long cut=one[n-1].time+60;
        std::vector<RPEntry> bounded,truncated,expected;
        check(RPReplay(s,c,one,int(one.size()),five,int(five.size()),cut,bounded),"bounded replay");
        std::vector<MSBar> o(one.begin(),one.begin()+n),f(five.begin(),five.begin()+n/5);
        check(RPReplay(s,c,o,int(o.size()),f,int(f.size()),cut,truncated),"truncated replay");
        sameEntries(bounded,truncated);
        for(const auto& e:full) if(e.time+60<=cut) expected.push_back(e);
        sameEntries(bounded,expected);
    }
    // Scheduler equivalence against individual chronological production steps.
    RPState streamed; RPReset(streamed);
    std::vector<RPEntry> stream;
    int next5=0;
    for(int i=0;i<int(one.size());++i) {
        RPProcessM1(streamed,c,one[i],i,buy,sell);
        if(buy.direction) stream.push_back(buy);
        if(sell.direction) stream.push_back(sell);
        if(next5<int(five.size()) && five[next5].time+300<=one[i].time+60)
            RPProcessM5(streamed,c,five,next5++);
    }
    sameEntries(full,stream);
    c=config();
    check(RPReplay(s,c,one,int(one.size()),five,int(five.size()),horizon,full),"default MACD replay");
    check(s.serial>0,"default settings find setups");
    check(full.size()==27,"default signal count remains unchanged from 1.00");
    for(auto side:{RP_BUY_ONLY,RP_SELL_ONLY}) {
        auto filtered=c; filtered.side=side;
        std::vector<RPEntry> actual,expected;
        check(RPReplay(s,filtered,one,int(one.size()),five,int(five.size()),horizon,actual),"side-filtered replay");
        for(const auto& e:full) if(e.direction==(side==RP_BUY_ONLY ? 1 : -1)) expected.push_back(e);
        check(actual.size()==expected.size(),"side filter retains all matching default entries");
        for(size_t i=0;i<actual.size();i++) check(actual[i].time==expected[i].time && actual[i].direction==expected[i].direction,
                                               "side filter preserves matching entry timing");
    }
    std::cout<<"MACD Zone Pullback core: "<<checks<<" checks passed; "<<full.size()<<" default-fixture entries\n";
}
