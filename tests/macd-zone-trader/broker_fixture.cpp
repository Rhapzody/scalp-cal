// Execute the production broker/calculator module with a deterministic MT5
// adapter. Prices, account currency profit, symbol limits and permissions are
// controlled here; no network, terminal, or order submission is involved.
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <string>
#include <map>
#include <vector>
using string=std::string;
using datetime=long;
using ulong=unsigned long;
#define MathIsValidNumber std::isfinite
#define MathRound std::round
#define MathFloor std::floor
#define MathMax std::max
#define MathAbs std::abs
double NormalizeDouble(double v,int d) { double p=std::pow(10.,d); return std::round(v*p)/p; }
template<class T> void ZeroMemory(T &v) { v=T{}; }
enum ENUM_ORDER_TYPE { ORDER_TYPE_BUY,ORDER_TYPE_SELL,ORDER_TYPE_BUY_LIMIT,ORDER_TYPE_SELL_LIMIT,
    ORDER_TYPE_BUY_STOP,ORDER_TYPE_SELL_STOP,ORDER_TYPE_BUY_STOP_LIMIT,ORDER_TYPE_SELL_STOP_LIMIT };
enum ENUM_POSITION_TYPE { POSITION_TYPE_BUY,POSITION_TYPE_SELL };
enum ENUM_SYMBOL_TRADE_MODE { SYMBOL_TRADE_MODE_DISABLED,SYMBOL_TRADE_MODE_LONGONLY,
    SYMBOL_TRADE_MODE_SHORTONLY,SYMBOL_TRADE_MODE_CLOSEONLY,SYMBOL_TRADE_MODE_FULL };
enum ENUM_SYMBOL_TRADE_EXECUTION { SYMBOL_TRADE_EXECUTION_REQUEST,SYMBOL_TRADE_EXECUTION_INSTANT,
    SYMBOL_TRADE_EXECUTION_MARKET,SYMBOL_TRADE_EXECUTION_EXCHANGE };
enum { SYMBOL_POINT=100,SYMBOL_TRADE_TICK_SIZE,SYMBOL_DIGITS,SYMBOL_VOLUME_MIN,SYMBOL_VOLUME_MAX,
    SYMBOL_VOLUME_STEP,SYMBOL_VOLUME_LIMIT,SYMBOL_TRADE_STOPS_LEVEL,SYMBOL_TRADE_FREEZE_LEVEL,
    SYMBOL_TRADE_MODE,SYMBOL_ORDER_MODE,SYMBOL_EXPIRATION_MODE,SYMBOL_FILLING_MODE,SYMBOL_TRADE_EXEMODE,
    ACCOUNT_MARGIN_MODE,ACCOUNT_MARGIN_FREE,ACCOUNT_TRADE_ALLOWED,ACCOUNT_TRADE_EXPERT,
    TERMINAL_CONNECTED,TERMINAL_TRADE_ALLOWED,MQL_TRADE_ALLOWED,POSITION_SYMBOL,POSITION_TYPE,
    POSITION_VOLUME,ORDER_SYMBOL,ORDER_TYPE,ORDER_VOLUME_CURRENT,
    ACCOUNT_MARGIN_MODE_RETAIL_HEDGING,ACCOUNT_MARGIN_MODE_RETAIL_NETTING,
    TRADE_ACTION_PENDING,TRADE_ACTION_DEAL,ORDER_TIME_GTC,ORDER_FILLING_RETURN,ORDER_FILLING_FOK,ORDER_FILLING_IOC };
constexpr long SYMBOL_ORDER_MARKET=1,SYMBOL_ORDER_LIMIT=2,SYMBOL_ORDER_STOP=4,SYMBOL_ORDER_SL=16,SYMBOL_ORDER_TP=32;
constexpr long SYMBOL_EXPIRATION_GTC=1,SYMBOL_FILLING_FOK=1,SYMBOL_FILLING_IOC=2;
const string _Symbol="GOLD.test";
struct MqlTick { datetime time; double bid,ask; };
struct MqlTradeRequest {
    int action=0; string symbol; ulong magic=0; double volume=0; ENUM_ORDER_TYPE type=ORDER_TYPE_BUY;
    double price=0,sl=0,tp=0; ulong deviation=0; int type_time=0,type_filling=0; string comment;
};
std::map<int,double> props;
MqlTick tick;
bool calc_ok=true,tick_ok=true,margin_ok=true;
int tick_reads=0;
double profit_factor=100,margin_per_lot=1000;
struct Exposure { string symbol; int type; double volume; };
std::vector<Exposure> positions,orders;
int selected_pos=0,selected_order=0;
double SymbolInfoDouble(const string&,int key) { return props[key]; }
long SymbolInfoInteger(const string&,int key) { return static_cast<long>(props[key]); }
double AccountInfoDouble(int key) { return props[key]; }
long AccountInfoInteger(int key) { return static_cast<long>(props[key]); }
long TerminalInfoInteger(int key) { return static_cast<long>(props[key]); }
long MQLInfoInteger(int key) { return static_cast<long>(props[key]); }
bool SymbolInfoTick(const string&,MqlTick &out) { ++tick_reads; out=tick; return tick_ok; }
#ifndef SCALP_TEST_TIME_NOW
#define SCALP_TEST_TIME_NOW 1000
#endif
datetime TimeTradeServer() { return SCALP_TEST_TIME_NOW; }
datetime TimeCurrent() { return SCALP_TEST_TIME_NOW; }
int PositionsTotal() { return static_cast<int>(positions.size()); }
int OrdersTotal() { return static_cast<int>(orders.size()); }
ulong PositionGetTicket(int i) { selected_pos=i; return static_cast<ulong>(i+1); }
ulong OrderGetTicket(int i) { selected_order=i; return static_cast<ulong>(i+1); }
string PositionGetString(int) { return positions.at(selected_pos).symbol; }
string OrderGetString(int) { return orders.at(selected_order).symbol; }
long PositionGetInteger(int) { return positions.at(selected_pos).type; }
long OrderGetInteger(int) { return orders.at(selected_order).type; }
double PositionGetDouble(int) { return positions.at(selected_pos).volume; }
double OrderGetDouble(int) { return orders.at(selected_order).volume; }
bool PositionSelect(const string &symbol) {
    for(size_t i=0;i<positions.size();++i) if(positions[i].symbol==symbol) { selected_pos=static_cast<int>(i); return true; }
    return false;
}
bool OrderCalcProfit(ENUM_ORDER_TYPE side,const string&,double volume,double entry,double close,double &pnl) {
    pnl=(close-entry)*(side==ORDER_TYPE_BUY ? 1 : -1)*volume*profit_factor; return calc_ok;
}
bool OrderCalcMargin(ENUM_ORDER_TYPE,const string&,double volume,double,double &margin) {
    margin=volume*margin_per_lot; return margin_ok;
}
#ifndef SCALP_BROKER_HEADER
#define SCALP_BROKER_HEADER "../../MQL5/Experts/ScalpCalculator/ScalpBroker.mqh"
#endif
#include SCALP_BROKER_HEADER
int checks=0;
void check(bool b,const char *text) { ++checks; if(!b) { std::cerr<<"FAIL: "<<text<<'\n'; std::exit(1); } }
bool near(double a,double b) { return std::abs(a-b)<1e-8; }
void reset() {
    props={{SYMBOL_POINT,.01},{SYMBOL_TRADE_TICK_SIZE,.01},{SYMBOL_DIGITS,2},{SYMBOL_VOLUME_MIN,.01},
      {SYMBOL_VOLUME_MAX,100},{SYMBOL_VOLUME_STEP,.01},{SYMBOL_VOLUME_LIMIT,0},
      {SYMBOL_TRADE_STOPS_LEVEL,10},{SYMBOL_TRADE_FREEZE_LEVEL,0},{SYMBOL_TRADE_MODE,SYMBOL_TRADE_MODE_FULL},
      {SYMBOL_ORDER_MODE,55},{SYMBOL_EXPIRATION_MODE,SYMBOL_EXPIRATION_GTC},{SYMBOL_FILLING_MODE,SYMBOL_FILLING_FOK},
      {SYMBOL_TRADE_EXEMODE,SYMBOL_TRADE_EXECUTION_MARKET},{ACCOUNT_MARGIN_FREE,100000},
      {ACCOUNT_MARGIN_MODE,ACCOUNT_MARGIN_MODE_RETAIL_HEDGING},{ACCOUNT_TRADE_ALLOWED,1},{ACCOUNT_TRADE_EXPERT,1},
      {TERMINAL_CONNECTED,1},{TERMINAL_TRADE_ALLOWED,1},{MQL_TRADE_ALLOWED,1}};
    tick={1000,3650,3650.2}; tick_reads=0; calc_ok=tick_ok=margin_ok=true; profit_factor=100; margin_per_lot=1000;
    positions.clear(); orders.clear();
}
ScalpPlan buy() { return {true,false,0,3643.2,3664.2,1,2}; }
ScalpPlan sell() { return {false,false,0,3657,3636,1,2}; }
bool calculate(ScalpPlan p,ScalpQuote &q,int remaining=0) {
    return ScalpCalculate(p,10000,2,5,30,true,true,10,q,remaining);
}
int main() {
    reset(); ScalpQuote q{}; auto p=buy();
    check(calculate(p,q),"buy calculation valid");
    check(near(q.entry,3650.2),"market BUY uses Ask");
    check(near(q.lot,.07) && near(q.strategy_loss,98),"equal lots and rounded total risk");
    check(near(q.broker_loss,98) && near(q.broker_reward,196),"BUY broker estimates");
    p=sell(); check(calculate(p,q),"sell calculation valid");
    check(near(q.entry,3650),"market SELL uses Bid");
    check(near(q.broker_sl,3657.2) && near(q.broker_tp,3636.2),"both SELL levels compensated up");
    check(near(q.broker_loss,100.8) && near(q.strategy_loss,98),"broker risk separate from strategy target");
    check(near(q.broker_reward,193.2),"SELL broker reward includes compensated TP");
    p.pending=true; p.entry=3655; p.sl=3662; p.tp=3641;
    check(calculate(p,q) && q.type==ORDER_TYPE_SELL_LIMIT,"SELL LIMIT detected");
    MqlTradeRequest request; string error;
    check(ScalpRequest(p,q,42,20,request,error),"pending request built");
    check(request.type_filling==ORDER_FILLING_RETURN,"pending requires RETURN even with market execution");
    check(near(request.price,3655) && near(request.sl,3662.2) && near(request.tp,3641.2),"pending carries SL/TP from Execute");
    check(request.magic==42 && request.volume==.07,"magic and equal volume passed through");
    tick.ask=3650.29;
    check(near(request.sl,3662.2) && near(request.tp,3641.2),"built request frozen as spread changes");
    reset(); p=buy(); p.pending=true; p.entry=3649; p.sl=3642; p.tp=3663;
    check(calculate(p,q) && q.type==ORDER_TYPE_BUY_LIMIT,"BUY LIMIT detected");
    p.entry=3651; p.sl=3644; p.tp=3665;
    check(calculate(p,q) && q.type==ORDER_TYPE_BUY_STOP,"BUY STOP detected");
    p=sell(); p.pending=true; p.entry=3649; p.sl=3656; p.tp=3635;
    check(calculate(p,q) && q.type==ORDER_TYPE_SELL_STOP,"SELL STOP detected");
    p.entry=3650; check(!calculate(p,q),"pending exactly at current Bid rejected");
    reset(); p=buy(); props[SYMBOL_VOLUME_MIN]=.1;
    check(!calculate(p,q) && q.reason.find("minimum")!=string::npos,"broker min .1 blocks .07");
    reset(); props[SYMBOL_VOLUME_MIN]=.001; props[SYMBOL_VOLUME_STEP]=.001; p.risk_percent=.01;
    check(!calculate(p,q),"user minimum .01 remains even with broker .001");
    reset(); p=buy(); props[SYMBOL_VOLUME_MAX]=.05;
    check(!calculate(p,q),"per-order max rejects oversized lot");
    reset(); props[SYMBOL_VOLUME_LIMIT]=.2; positions.push_back({_Symbol,POSITION_TYPE_BUY,.1});
    check(!calculate(p,q),"directional limit includes existing positions");
    reset(); props[SYMBOL_VOLUME_LIMIT]=.2; orders.push_back({_Symbol,ORDER_TYPE_BUY_STOP,.1});
    check(!calculate(p,q),"directional limit includes pending orders");
    reset(); props[SYMBOL_VOLUME_LIMIT]=.2; positions.push_back({_Symbol,POSITION_TYPE_SELL,.1});
    check(calculate(p,q),"opposite-side exposure excluded from directional limit");
    reset(); props[ACCOUNT_MARGIN_FREE]=100;
    check(!calculate(p,q),"whole batch margin checked before sending");
    check(calculate(p,q,1),"remaining batch margin does not charge already placed tickets twice");
    reset(); tick.ask=3650.31;
    check(!calculate(p,q) && q.reason.find("Spread")!=string::npos,"spread above 30 points blocks");
    reset(); tick.ask=3650.3;
    check(calculate(p,q),"exact maximum spread accepted");
    reset(); tick.time=989;
    check(!calculate(p,q) && q.reason.find("Stale")!=string::npos,"stale quote blocked");
    reset(); p.sl=3649.95;
    check(!calculate(p,q),"BUY market SL checked from Bid, not entry Ask");
    reset(); p=sell(); p.tp=3649.9;
    check(!calculate(p,q),"SELL TP crossing entry after compensation blocked");
    reset(); p=buy(); props[SYMBOL_TRADE_FREEZE_LEVEL]=800;
    check(!calculate(p,q),"conservative market freeze guard");
    reset(); p.risk_percent=3;
    check(!calculate(p,q),"max risk enforced");
    p=buy(); p.orders=6; check(!calculate(p,q),"max orders enforced");
    reset(); p=buy(); check(!ScalpCalculate(p,0,2,5,30,true,true,10,q),"initial balance never inferred");
    check(ScalpCalculate(p,96500,2,5,30,true,true,10,q) && near(q.budget,965),"caller-supplied current balance");
    reset(); props[SYMBOL_TRADE_MODE]=SYMBOL_TRADE_MODE_SHORTONLY;
    check(!calculate(p,q),"long side restricted");
    reset(); props[SYMBOL_ORDER_MODE]=SYMBOL_ORDER_MARKET;
    check(!calculate(p,q),"no stopless fallback when SL/TP unsupported");
    reset(); props[SYMBOL_EXPIRATION_MODE]=2; p.pending=true; p.entry=3649;
    check(!calculate(p,q),"unsupported GTC expiration rejected");
    reset(); p=buy(); calc_ok=false;
    check(!calculate(p,q),"profit API failure blocks trading");
    reset(); margin_ok=false; check(!calculate(p,q),"margin API failure blocks trading");
    reset(); tick_ok=false; check(!calculate(p,q),"tick API failure blocks trading");
    reset(); props[SYMBOL_TRADE_TICK_SIZE]=0; check(!calculate(p,q),"invalid spec blocks trading");
    reset(); profit_factor=10;
    check(calculate(p,q) && near(q.lot,.71),"contract value is supplied by broker, not hardcoded gold");
    reset(); props[SYMBOL_POINT]=.001; props[SYMBOL_TRADE_TICK_SIZE]=.005; props[SYMBOL_DIGITS]=3; tick.ask=3650.02;
    p.sl=3643.02; p.tp=3664.02;
    check(calculate(p,q) && near(q.spread/q.spec.point,20),"different broker digits/point/tick work without recompilation");
    reset(); p=buy(); calculate(p,q);
    check(ScalpRequest(p,q,42,20,request,error) && request.type_filling==ORDER_FILLING_FOK,"prefer FOK when supported");
    props[SYMBOL_FILLING_MODE]=SYMBOL_FILLING_IOC;
    check(ScalpRequest(p,q,42,20,request,error) && request.type_filling==ORDER_FILLING_IOC,"IOC fallback");
    props[SYMBOL_FILLING_MODE]=0;
    check(!ScalpRequest(p,q,42,20,request,error),"market execution never falls back to RETURN");
    props[SYMBOL_TRADE_EXEMODE]=SYMBOL_TRADE_EXECUTION_EXCHANGE;
    check(ScalpRequest(p,q,42,20,request,error) && request.type_filling==ORDER_FILLING_RETURN,"exchange RETURN fallback");
    props[SYMBOL_TRADE_EXEMODE]=SYMBOL_TRADE_EXECUTION_INSTANT;
    check(ScalpRequest(p,q,42,20,request,error) && request.type_filling==ORDER_FILLING_FOK,"instant execution permits FOK");
    reset(); check(ScalpPermissions(error),"permissions available");
    props[TERMINAL_CONNECTED]=0; check(!ScalpPermissions(error),"offline blocked");
    reset(); props[MQL_TRADE_ALLOWED]=0; check(!ScalpPermissions(error),"EA trading permission blocked");
    reset(); props[ACCOUNT_TRADE_EXPERT]=0; check(!ScalpPermissions(error),"account EA permission blocked");
    reset(); positions.push_back({_Symbol,POSITION_TYPE_BUY,.1});
    check(!ScalpNettingExposure(),"hedging supports independent exposure");
    props[ACCOUNT_MARGIN_MODE]=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
    check(ScalpNettingExposure(),"netting existing position guarded");
    positions.clear(); orders.push_back({_Symbol,ORDER_TYPE_SELL_LIMIT,.1});
    check(ScalpNettingExposure(),"netting existing pending guarded");
    orders.clear(); check(!ScalpNettingExposure(),"empty netting symbol may start a batch");
    std::cout<<"PASS: "<<checks<<" broker checks (production ScalpBroker.mqh with mocked MT5 APIs)\n";
    return 0;
}
