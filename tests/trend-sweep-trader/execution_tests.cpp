long test_now=1000;
#define SCALP_TEST_TIME_NOW test_now
#define main scalp_regression_main
#include "broker_fixture.cpp"
#undef main
#define MathMin std::min
using uint=unsigned int;
template<class T> int ArrayResize(std::vector<T>& a,int n) { a.resize(n); return n; }
template<class T> int ArraySize(const std::vector<T>& a) { return int(a.size()); }
bool IsStopped() { return false; }
#include "TradePlanCore.mqh"
enum {
    TRADE_RETCODE_DONE=10009,TRADE_RETCODE_DONE_PARTIAL=10010,TRADE_RETCODE_PLACED=10008,
    TRADE_RETCODE_REQUOTE=10004,TRADE_RETCODE_REJECT=10006,TRADE_RETCODE_CANCEL=10007,
    TRADE_RETCODE_INVALID=10013,TRADE_RETCODE_INVALID_VOLUME=10014,TRADE_RETCODE_INVALID_PRICE=10015,
    TRADE_RETCODE_INVALID_STOPS=10016,TRADE_RETCODE_TRADE_DISABLED=10017,TRADE_RETCODE_MARKET_CLOSED=10018,
    TRADE_RETCODE_NO_MONEY=10019,TRADE_RETCODE_PRICE_CHANGED=10020,TRADE_RETCODE_PRICE_OFF=10021,
    TRADE_RETCODE_INVALID_FILL=10030,TRADE_RETCODE_TIMEOUT=10012,
    ACCOUNT_EQUITY=500,PERIOD_M5=300,FILE_READ=1,FILE_WRITE=2,FILE_BIN=4,INVALID_HANDLE=-1
};
struct MqlTradeCheckResult { uint retcode=0; string comment; };
struct MqlTradeResult { uint retcode=0; ulong deal=0,order=0; double price=0,volume=0; string comment; };
bool InpExecuteTrades=true,InpFreezeGuard=true;
double InpRiskPercent=1,InpMaxRiskPercent=2,InpMinRR=1,InpSLBufferPoints=0,
       InpMaxSpreadPoints=50,InpCommissionPerLot=0,InpTargetRR=2,InpMaxSpreadATR=.3,InpMaxEntryDriftATR=.2;
TSConfig g_config;
int InpMaxQuoteAgeSeconds=5,InpSignalMaxDelaySeconds=10;
ulong InpMagicNumber=42,InpDeviationPoints=20;
string g_scope="MZT.test",last_status,last_reason;
long g_test_buy=0,g_test_sell=0,current_bar=1000;
bool g_tester=false,g_test_halt=false,locked=false,persist_fail=false,drift_on_flush=false;
bool ordercheck_ok=true,send_ok=true,drift_on_check=false;
uint send_code=TRADE_RETCODE_DONE;
double send_volume_ratio=1;
int sends=0,orderchecks=0,unlocks=0,trade_reports=0;
std::map<string,double> globals;
std::vector<string> trace;
MqlTradeRequest last_request;
long iTime(const string&,int,int) { return current_bar; }
bool GlobalVariableCheck(const string& key) { return globals.count(key)>0; }
double GlobalVariableGet(const string& key) { return globals[key]; }
datetime GlobalVariableSet(const string& key,double value) {
    if(persist_fail) return 0;
    globals[key]=value; trace.push_back("persist"); return test_now;
}
bool GlobalVariableDel(const string& key) { globals.erase(key); return true; }
void GlobalVariablesFlush() { trace.push_back("flush"); if(drift_on_flush) tick.ask+=.01; }
int FileOpen(const string&,int) { if(locked) return INVALID_HANDLE; locked=true; return 42; }
void FileClose(int) { locked=false; ++unlocks; }
template<class... T> void Print(T... args) {}
void EAReport(const string& status,const EACandidate&,const string& reason) { last_status=status; last_reason=reason; }
void EATradeReport(const EACandidate&,const ScalpPlan&,const ScalpQuote&,const MqlTradeRequest&,
                   const MqlTradeResult&,bool) { ++trade_reports; }
#include "host_under_test.hpp"
bool OrderCheck(const MqlTradeRequest&,MqlTradeCheckResult& result) {
    ++orderchecks;
    result.retcode=ordercheck_ok ? TRADE_RETCODE_DONE : TRADE_RETCODE_INVALID_STOPS;
    result.comment=ordercheck_ok ? "OK" : "Rejected";
    if(drift_on_check) tick.ask+=.01;
    return ordercheck_ok;
}
bool OrderSend(const MqlTradeRequest& request,MqlTradeResult& result) {
    ++sends; trace.push_back("send"); last_request=request;
    check(EAHalted(),"pending intent is persisted before OrderSend");
    result.retcode=send_code; result.order=123; result.deal=send_code==TRADE_RETCODE_DONE ? 456 : 0;
    result.volume=request.volume*send_volume_ratio; result.price=request.price;
    return send_ok;
}
#include "TradeExecution.mqh"

void eaReset() {
    reset(); test_now=1000; current_bar=1000; tick={1000,100,100.2};
    props[ACCOUNT_EQUITY]=10000;
    InpExecuteTrades=true; InpRiskPercent=1; InpMinRR=1; InpSLBufferPoints=0; InpCommissionPerLot=0; InpTargetRR=2; InpMaxSpreadATR=.3; InpMaxEntryDriftATR=.2;
    g_config.min_stop_atr=.5; g_config.max_stop_atr=2.5;
    sends=orderchecks=unlocks=trade_reports=0;
    globals.clear(); trace.clear(); last_status=""; last_reason="";
    g_tester=g_test_halt=locked=persist_fail=drift_on_flush=drift_on_check=false;
    g_test_buy=g_test_sell=0; ordercheck_ok=send_ok=true; send_code=TRADE_RETCODE_DONE; send_volume_ratio=1;
}
EACandidate signal(bool is_buy=true) {
    EACandidate c{}; c.signal.time=700; c.signal.price=100; c.signal.atr=1; c.signal.stop=is_buy ? 99.2 : 100.8; c.signal.direction=is_buy ? 1 : -1;
    c.pattern_low=99.21; c.pattern_high=100.79;
    return c;
}
std::vector<EATarget> levels(bool is_buy=true,double price=0) {
    return {{price>0 ? price : (is_buy ? 104.0 : 96.0)}};
}
bool prepare(const EACandidate& c,const std::vector<EATarget>& t,ScalpPlan& p,ScalpQuote& q,
             MqlTradeRequest& r,string& reason) {
    return EAPrepare(c,t,10000,InpRiskPercent,2,InpMinRR,InpTargetRR,50,5,true,
                     InpCommissionPerLot,42,20,p,q,r,reason);
}

// Exercise the actual new-bar coordinator with history / signal computation
// mocked separately from the genuine execution path tested above.
bool g_busy=false;
long g_seen_bar=0;
std::vector<TSBar> g_bars;
int loads=0,contexts=0,executions=0;
bool load_ok=true,context_ok=true;
void EAStatus(const string& reason) { last_reason=reason; }
bool EALoad(long) { ++loads; return load_ok; }
bool MockContext(const TSConfig&,const std::vector<TSBar>&,int,long,
                 EACandidate&,std::vector<EATarget>&,string&) { ++contexts; return context_ok; }
void MockExecute(const EACandidate&,const std::vector<EATarget>&) { ++executions; }
#define EABuildContext MockContext
#define EAExecute MockExecute
#include "tick_under_test.hpp"
#undef EABuildContext
#undef EAExecute

int main() {
    scalp_regression_main();
    eaReset(); ScalpPlan plan{}; ScalpQuote quote{}; MqlTradeRequest request{}; string reason;
    auto candidate=signal(); auto target=levels();
    check(prepare(candidate,target,plan,quote,request,reason),"buy plan accepted");
    check(near(request.sl,99.2) && near(request.tp,102.2) && near(request.price,100.2),"buy target is two R at executable ask");
    check(quote.broker_loss<=100+1e-7,"buy risk capped at one percent");
    candidate=signal(false); target=levels(false);
    check(prepare(candidate,target,plan,quote,request,reason),"sell plan accepted");
    check(near(request.sl,101) && near(request.tp,98) && near(request.price,100),"sell target compensates both stop and target spread");
    check(near(plan.tp,97.8) && near(quote.broker_loss,100),"sell strategy TP differs from broker TP and risk is reduced");
    target=levels(false,97.9);
    check(!prepare(candidate,target,plan,quote,request,reason),"insufficient room after spread blocks sell");
    candidate=signal(); target=levels(true,102.1);
    check(!prepare(candidate,target,plan,quote,request,reason),"room lost at actual ask blocks buy");
    target=levels(); InpMinRR=2; InpCommissionPerLot=10;
    check(!prepare(candidate,target,plan,quote,request,reason),"commission cannot masquerade as net two R");
    InpMinRR=1.8; InpCommissionPerLot=2;
    check(prepare(candidate,target,plan,quote,request,reason) && quote.broker_loss+quote.lot*2<=100+1e-7,"commission included in risk cap");
    eaReset(); InpRiskPercent=.5;
    check(prepare(candidate,target,plan,quote,request,reason) && quote.broker_loss<=50+1e-7,"configurable equity risk");
    candidate.signal.stop=99; InpRiskPercent=1;
    check(prepare(candidate,target,plan,quote,request,reason) && near(request.sl,99),"signal ATR/point SL buffer used by executor");
    check(!prepare(candidate,{},plan,quote,request,reason),"missing room boundary blocks order");
    eaReset(); InpMaxSpreadATR=.1; EAExecute(signal(),levels());
    check(sends==0,"ATR-relative spread cap");
    eaReset(); tick.bid=100.3;tick.ask=100.5;EAExecute(signal(),levels());
    check(sends==0,"entry drift cap rejects chasing");
    eaReset(); candidate=signal(); target=levels();
    eaReset(); candidate=signal(); target=levels(); EAExecute(candidate,target);
    check(sends==1 && orderchecks==1 && trade_reports==1,"one checked market request submitted");
    check(EAAttempted(candidate) && !EAHalted() && !locked,"filled attempt persisted and lock released");
    check(std::find(trace.begin(),trace.end(),"persist")<std::find(trace.begin(),trace.end(),"send"),"persist precedes send");
    EAExecute(candidate,target);
    check(sends==1,"same signal not sent twice");
    g_seen_bar=0; // Simulate local process state reset while terminal globals survive.
    EAExecute(candidate,target); check(sends==1,"restart does not erase duplicate protection");
    eaReset(); InpExecuteTrades=false; EAExecute(candidate,target);
    check(sends==0 && orderchecks==0 && last_status=="SIGNAL ONLY","disabled execution emits no request");
    eaReset(); tick.ask=100.51; EAExecute(candidate,target); check(sends==0,"spread cap blocks order");
    eaReset(); tick.time=994; EAExecute(candidate,target); check(sends==0,"stale tick blocks order");
    eaReset(); props[ACCOUNT_MARGIN_FREE]=1; EAExecute(candidate,target); check(sends==0,"insufficient margin blocks order");
    eaReset(); props[SYMBOL_TRADE_STOPS_LEVEL]=200; EAExecute(candidate,target); check(sends==0,"broker stop-level guard");
    eaReset(); props[MQL_TRADE_ALLOWED]=0; EAExecute(candidate,target); check(sends==0,"EA permission guard");
    eaReset(); positions.push_back({_Symbol,POSITION_TYPE_SELL,.1}); EAExecute(candidate,target);
    check(sends==0,"manual or other-EA symbol position blocks even in hedging");
    eaReset(); orders.push_back({_Symbol,ORDER_TYPE_BUY_LIMIT,.1}); EAExecute(candidate,target);
    check(sends==0,"existing pending symbol exposure blocks");
    eaReset(); positions.push_back({"OTHER",POSITION_TYPE_SELL,.1}); EAExecute(candidate,target);
    check(sends==1,"unrelated symbol does not block");
    eaReset(); ordercheck_ok=false; EAExecute(candidate,target);
    check(sends==0 && !EAAttempted(candidate),"OrderCheck failure never submits");
    eaReset(); persist_fail=true; EAExecute(candidate,target);
    check(sends==0,"persistence failure never submits");
    eaReset(); locked=true; EAExecute(candidate,target); check(sends==0,"concurrent instance lock blocks");
    eaReset(); test_now=1011; EAExecute(candidate,target); check(sends==0,"late signal cannot enter");
    eaReset(); current_bar=1300; EAExecute(candidate,target); check(sends==0,"old M5 signal cannot enter next bar");
    eaReset(); drift_on_check=true; EAExecute(candidate,levels(true,104));
    check(sends==0 && orderchecks==3,"bounded quote refresh before send");
    eaReset(); drift_on_flush=true; EAExecute(candidate,target);
    check(sends==0 && EAAttempted(candidate) && !EAHalted(),"quote change during persistence cancels before send");
    for(uint code:{uint(TRADE_RETCODE_TIMEOUT),uint(TRADE_RETCODE_PLACED),uint(TRADE_RETCODE_DONE_PARTIAL),0u}) {
        eaReset(); send_code=code; send_ok=code!=0; EAExecute(candidate,target);
        check(sends==1 && EAHalted(),"ambiguous or partial outcome retains persistent halt");
        candidate.signal.time=1000; current_bar=1300; test_now=1300; tick.time=1300;
        EAExecute(candidate,target);
        check(sends==1,"uncertain request also blocks later signals");
        candidate=signal();
    }
    eaReset(); send_code=TRADE_RETCODE_REJECT; send_ok=false; EAExecute(candidate,target);
    check(!EAHalted() && EAAttempted(candidate),"definite rejection releases halt but never retries signal");
    EAExecute(candidate,target); check(sends==1,"rejected request not automatically retried");
    eaReset(); send_volume_ratio=.5; EAExecute(candidate,target);
    check(EAHalted(),"DONE with incomplete volume is treated as uncertain");
    eaReset(); g_tester=true; EAExecute(candidate,target);
    check(sends==1 && globals.empty() && EAAttempted(candidate),"tester uses isolated in-memory markers");
    g_test_buy=g_test_sell=0; g_test_halt=false; EAExecute(candidate,target);
    check(sends==2,"fresh tester run is reproducible");

    eaReset(); g_seen_bar=0; g_busy=false; loads=contexts=executions=0;
    current_bar=1000; test_now=1000; OnTick();
    check(g_seen_bar==1000 && loads==0 && executions==0,"attach synchronizes without historical entry");
    current_bar=1300; test_now=1300; OnTick();
    check(loads==1 && contexts==1 && executions==1,"new M5 bar processes once");
    OnTick(); check(executions==1,"ticks in same bar cannot resubmit");
    current_bar=2200; test_now=2200; OnTick();
    check(g_seen_bar==2200 && executions==1,"reconnect gap resynchronizes without old entries");
    current_bar=2500; test_now=2511; OnTick();
    check(g_seen_bar==2500 && executions==1,"late first tick skips signal");
    current_bar=2800; test_now=2800; load_ok=false; OnTick();
    check(g_seen_bar==2500 && !g_busy,"history load failure allows bounded retry");
    load_ok=true; OnTick(); check(g_seen_bar==2800 && executions==2,"history retry within window");
    g_busy=true; current_bar=3100; test_now=3100; OnTick();
    check(executions==2,"reentrant callback blocked"); g_busy=false;
    context_ok=false; OnTick(); check(executions==2 && g_seen_bar==3100,"no signal means no execute");
    std::cout<<"Trend Sweep Trader execution + shared broker: "<<checks<<" checks passed\n";
}
