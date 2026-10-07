#include <algorithm>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>
using string=std::string;
#define MathIsValidNumber std::isfinite
#define MathMax std::max
#define MathMin std::min
#define MathAbs std::abs
#define MathRound std::round
#define MathFloor std::floor
double NormalizeDouble(double v,int d){ double p=std::pow(10.,d); return std::round(v*p)/p; }
template<class T> void ZeroMemory(T& v){ v=T{}; }
template<class T> int ArrayResize(std::vector<T>& v,int n){ v.resize(n); return n; }
template<class T> int ArraySize(const std::vector<T>& v){ return int(v.size()); }
#include "PATradeCore.mqh"

struct Bar{ long t; PABar p; };
std::vector<Bar> load(const std::string& path){
    std::ifstream in(path); if(!in) throw std::runtime_error("cannot open "+path);
    std::string line; std::getline(in,line); std::vector<Bar> out;
    while(std::getline(in,line)){
        std::stringstream ss(line); std::string c[6]; int k=0; while(k<6 && std::getline(ss,c[k],',')) k++;
        if(k<5) continue; long ms=std::stol(c[0]); out.push_back({ms/1000,{std::stod(c[1]),std::stod(c[2]),std::stod(c[3]),std::stod(c[4])}});
    } return out;
}
std::string iso(long t){ std::time_t x=t; std::tm tm{}; gmtime_r(&x,&tm); char b[32]; std::strftime(b,sizeof(b),"%Y-%m-%d %H:%M:%S",&tm); return b; }

struct Result{ std::string signal_time,entry_time,side,status,reason,result,exit_time; double entry=0,sl=0,tp=0,rr=0,r=0,spread=0,ema=0,atr=0; int bars=0; };
void writeCsv(const std::string& path,const std::vector<Result>& rs){
    std::ofstream o(path); o<<"signal_time,entry_time,side,status,reason,result,exit_time,entry,sl,tp,rr,r_multiple,spread,ema20,atr,bars_held\n"; o<<std::fixed<<std::setprecision(3);
    for(auto&r:rs) o<<r.signal_time<<','<<r.entry_time<<','<<r.side<<','<<r.status<<','<<r.reason<<','<<r.result<<','<<r.exit_time<<','<<r.entry<<','<<r.sl<<','<<r.tp<<','<<r.rr<<','<<r.r<<','<<r.spread<<','<<r.ema<<','<<r.atr<<','<<r.bars<<'\n';
}

int main(int argc,char**argv){
    if(argc<3){ std::cerr<<"usage: pa_reversal_trader_backtest M5_CSV OUTPUT_PREFIX\n"; return 2; }
    auto all=load(argv[1]); const std::string prefix=argv[2];
    std::tm stm{}; stm.tm_year=2026-1900; stm.tm_mon=5; stm.tm_mday=19; stm.tm_hour=0; const long startUtc=timegm(&stm);
    std::tm etm{}; etm.tm_year=2026-1900; etm.tm_mon=8; etm.tm_mday=19; etm.tm_hour=0; const long endUtc=timegm(&etm);
    PATradeConfig cfg{}; cfg.min_bars=3; cfg.ema_period=20; cfg.atr_length=14; cfg.max_sl_ema_atr=1.5; cfg.max_retrace_ema_atr=.25; cfg.max_ema_penetration_atr=.50; cfg.sl_buffer_points=15; cfg.min_rr=1; cfg.point=.01; cfg.tick=.01;
    const double spread=.30, maxSpread=.40; const int history=3000;
    std::vector<Result> rows; long occupiedUntil=0; int executed=0;
    for(int i=history;i+1<int(all.size());i++){
        if(all[i].t<startUtc || all[i].t>=endUtc) continue;
        int first=std::max(0,i-history+1); std::vector<PABar> bars; bars.reserve(i-first+1); for(int j=first;j<=i;j++) bars.push_back(all[j].p);
        PASetup s{}; string reason; if(!PABuildLatest(cfg,bars,int(bars.size()),int(bars.size())-1,2,s,reason)) continue;
        s.signal_time=all[i].t; if(s.signal_index!=int(bars.size())-1) continue;
        int entryIdx=i+1; if(entryIdx>=int(all.size())) continue;
        Result row; row.signal_time=iso(all[i].t); row.entry_time=iso(all[entryIdx].t); row.side=s.direction==1?"BUY":"SELL"; row.spread=spread; row.ema=s.ema20; row.atr=s.atr;
        if(all[entryIdx].t<occupiedUntil){ row.status="SKIP"; row.reason="symbol exposure open"; rows.push_back(row); continue; }
        double bidOpen=all[entryIdx].p.open, entry=s.direction==1?bidOpen+spread:bidOpen;
        double brokerSl=s.direction==1?s.sl:s.sl+spread, brokerTp=s.direction==1?s.tp:s.tp+spread;
        double cappedBrokerTp=PACapTPAtOneR(s.direction==1,entry,brokerSl,brokerTp);
        if(cappedBrokerTp<=0){ row.status="SKIP"; row.reason="invalid capped TP"; rows.push_back(row); continue; }
        brokerTp=cappedBrokerTp;
        double risk=s.direction==1?entry-brokerSl:brokerSl-entry, reward=s.direction==1?brokerTp-entry:entry-brokerTp;
        row.entry=entry; row.sl=brokerSl; row.tp=brokerTp; row.rr=risk>0?reward/risk:0;
        if(spread>maxSpread){ row.status="SKIP"; row.reason="spread above 40 points"; rows.push_back(row); continue; }
        int fillIdx=entryIdx; double fill=entry; bool follow=false;
        if(row.rr+1e-12<1){
            double threshold=(brokerSl+brokerTp)/2.0; bool hitTp=s.direction==1 ? all[entryIdx].p.high>=brokerTp : all[entryIdx].p.low+spread<=brokerTp;
            bool hitBetter=s.direction==1 ? all[entryIdx].p.low+spread<=threshold : all[entryIdx].p.high>=threshold;
            if(hitTp){ row.status="SKIP"; row.reason="TP passed before one-bar RR recovery"; rows.push_back(row); continue; }
            if(!hitBetter){ row.status="SKIP"; row.reason="RR stayed below 1 for one follow-up bar"; rows.push_back(row); continue; }
            fill=threshold; risk=s.direction==1?fill-brokerSl:brokerSl-fill; reward=s.direction==1?brokerTp-fill:fill-brokerTp; row.rr=risk>0?reward/risk:0; follow=true;
        }
        row.status="EXECUTED"; row.reason=follow?"one-bar RR recovery":"initial RR valid";
        int exit=-1; bool hitSl=false; for(int j=fillIdx;j<int(all.size());j++){
            bool sl=s.direction==1 ? all[j].p.low<=brokerSl : all[j].p.high+spread>=brokerSl;
            bool tp=s.direction==1 ? all[j].p.high>=brokerTp : all[j].p.low+spread<=brokerTp;
            if(sl||tp){ exit=j; hitSl=sl; break; }
        }
        if(exit<0){ row.result="OPEN_AT_DATA_END"; row.exit_time=iso(all.back().t); double ep=s.direction==1?all.back().p.close:all.back().p.close+spread; row.r=s.direction==1?(ep-fill)/risk:(fill-ep)/risk; row.bars=int(all.size())-fillIdx; }
        else { row.exit_time=iso(all[exit].t); row.bars=exit-fillIdx+1; row.result=hitSl?"SL":"TP"; row.r=hitSl?-1.0:reward/risk; occupiedUntil=all[exit].t+300; }
        rows.push_back(row); if(row.status=="EXECUTED") executed++;
    }
    writeCsv(prefix+"_audit.csv",rows);
    double net=0,peak=0,dd=0,winR=0,lossR=0; int wins=0,losses=0,streak=0,maxStreak=0; for(auto&r:rows) if(r.status=="EXECUTED"){ net+=r.r; peak=std::max(peak,net); dd=std::max(dd,peak-net); if(r.r>0){wins++;winR+=r.r;streak=0;}else{losses++;lossR+=r.r;streak++;maxStreak=std::max(maxStreak,streak);} }
    std::ofstream meta(prefix+"_meta.txt"); meta<<"data_start_utc="<<iso(startUtc)<<"\ndata_end_utc="<<iso(endUtc)<<"\ninput_spread="<<spread<<"\nmax_spread="<<maxSpread<<"\npoint=0.01\ndigits=2\nmin_bars=3\nema_period=20\natr_period=14\nmax_sl_from_ema_atr=1.5\nmax_retrace_from_ema_atr=0.25\nmax_ema_penetration_atr=0.50\nsl_buffer_points=15\ntp_policy=cap_at_1R\nexecuted="<<executed<<"\nsetup_rows="<<rows.size()<<"\nnet_R="<<net<<"\nwin_rate="<<(executed?100.0*wins/executed:0)<<"\nprofit_factor="<<(lossR<0?winR/-lossR:0)<<"\nmax_drawdown_R="<<dd<<"\nmax_loss_streak="<<maxStreak<<"\n";
    std::cout<<"setup_rows="<<rows.size()<<" executed="<<executed<<" wins="<<wins<<" losses="<<losses<<" netR="<<net<<" winrate="<<(executed?100.0*wins/executed:0)<<" PF="<<(lossR<0?winR/-lossR:0)<<" maxDD="<<dd<<"\n";
}
