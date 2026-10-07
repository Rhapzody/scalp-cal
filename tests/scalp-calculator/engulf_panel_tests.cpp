// Runs the integrated broker/core suite, then the production click executor
// against simulated candles, storage, permissions, OrderCheck and OrderSend.
long mock_server_time=1000;
#define SCALP_TEST_TIME_NOW mock_server_time
#define SCALP_BROKER_HEADER "../../MQL5/Experts/ScalpCalculator/ScalpBroker.mqh"
#define ENGULF_CORE_HEADER "../../MQL5/Experts/ScalpCalculator/EngulfCore.mqh"
#define ENGULF_EXPECTED_REQUEST_COMMENT "ScalpCalculator V1"
#define ENGULF_TEST_MAIN PreviousEngulfTests
#include "../instant-engulf/engulf_tests.cpp"
#include <sstream>
#include <iomanip>
#include <ctime>
using ENUM_TIMEFRAMES=int;
int _Period=1;
const int _Digits=2;
const int PERIOD_MN1=43200;
struct MqlDateTime {int year=0,mon=0,day=0,hour=0,min=0,sec=0;};
bool TimeToStruct(datetime t,MqlDateTime&d){auto tm=*gmtime(&t);d={tm.tm_year+1900,tm.tm_mon+1,tm.tm_mday,tm.tm_hour,tm.tm_min,tm.tm_sec};return true;}
datetime StructToTime(const MqlDateTime&d){std::tm tm={};tm.tm_year=d.year-1900;tm.tm_mon=d.mon-1;tm.tm_mday=d.day;tm.tm_hour=d.hour;tm.tm_min=d.min;tm.tm_sec=d.sec;return timegm(&tm);}
int PeriodSeconds(int period){return period*60;}
enum {ACCOUNT_SERVER=2000,ACCOUNT_LOGIN,SERIES_SYNCHRONIZED,FILE_READ=1,FILE_WRITE=2,FILE_BIN=4,TIME_DATE=1,TIME_MINUTES=2};
const int INVALID_HANDLE=-1;
struct MqlRates {datetime time=0;double open=0,high=0,low=0,close=0;};
struct MqlTradeCheckResult {uint retcode=0;string comment;};
struct MqlTradeResult {uint retcode=0;ulong order=0,deal=0;string comment;double price=0,volume=0;};
bool g_busy=false,g_enabled=true,InpShowInstantEngulf=true,InpEngulfOneOrderPerSignal=true;
double InpEngulfRiskPercent=1,InpEngulfSLBufferPoints=0,InpMaxRiskPercent=2,InpMaxSpreadPoints=30;
int InpMaxQuoteAgeSeconds=10;
bool InpFreezeGuard=true;
ulong InpEngulfMagicNumber=26091202,InpDeviationPoints=20,g_engulf_last_click=0;
string g_result,g_detail,g_engulf_pa,g_engulf_bar_time,g_engulf_pair;
bool g_engulf_has_signal=false,g_engulf_valid=false;
ScalpPlan g_engulf_plan;
ScalpQuote g_engulf_quote;
MqlRates latest,older,current_bar;
datetime chart_bar_time=960;
int last_shift=-1,advance_seconds=0,flush_advance_seconds=0;
bool change_pa=false,change_sl=false;
std::map<string,double> markers;
ulong clock_ms=2000;
bool bars_ok=true,synced=true,lock_ok=true,persist_ok=true,check_ok=true,roll_bar=false,send_ok=true;
uint send_code=TRADE_RETCODE_DONE;
int sends=0,alerts=0,closed_locks=0,checks_sent=0;
MqlTradeRequest submitted;
MqlTradeResult send_result;
ulong GetTickCount64(){return clock_ms;}
int StringLen(const string&s){return int(s.size());}
int StringGetCharacter(const string&s,int n){return s.at(n);}
string IntegerToString(long v){return std::to_string(v);}
string AccountInfoString(int){return "TestServer";}
template<class... A> string StringFormat(const string &format,A...){return format;}
string StringFormat(const char *format,ulong hash,const char *side){return string(format)+std::to_string(hash)+side;}
string TimeToString(datetime t,int=0){return std::to_string(t);}
string EnumToString(int v){return std::to_string(v);}
void ArraySetAsSeries(MqlRates (&)[2],bool){}
int CopyRates(const string&,int,int shift,int count,MqlRates (&p)[2]){check((shift==0||shift==1)&&count==2,"only selected adjacent candle pair read");last_shift=shift;p[0]=shift==0?current_bar:latest;p[1]=shift==0?latest:older;return bars_ok?2:0;}
bool SeriesInfoInteger(const string&,int,int){return synced;}
datetime iTime(const string&,int,int shift){return shift==0?chart_bar_time+(roll_bar&&checks_sent?60:0):(roll_bar&&checks_sent?chart_bar_time:latest.time);}
bool GlobalVariableCheck(const string&k){return markers.count(k);}
double GlobalVariableGet(const string&k){return markers[k];}
datetime GlobalVariableSet(const string&k,double v){if(!persist_ok)return 0;markers[k]=v;return 1;}
void GlobalVariablesFlush(){mock_server_time+=flush_advance_seconds;}
int FileOpen(const string&,int){return lock_ok?1:INVALID_HANDLE;}
void FileClose(int){closed_locks++;}
template<class... A> void Print(A...){}
template<class... A> void PrintFormat(A...){}
template<class... A> void Alert(A...){alerts++;}
void ResetLastError(){}
int GetLastError(){return 0;}
double RiskBase(){return 10000;}
void SaveState(){}
void Refresh(){}
bool OrderCheck(const MqlTradeRequest&,MqlTradeCheckResult&r){checks_sent++;mock_server_time+=advance_seconds;if(change_pa)current_bar.close=3651;if(change_sl)current_bar.low=3640;r.retcode=check_ok?TRADE_RETCODE_DONE:TRADE_RETCODE_NO_MONEY;return check_ok;}
bool OrderSend(const MqlTradeRequest&r,MqlTradeResult&out){sends++;submitted=r;out=send_result;out.retcode=send_code;if(send_code==TRADE_RETCODE_DONE){out.price=r.price;out.volume=r.volume;}return send_ok;}
#include SCALP_ENGULF_TIMING_HEADER
#include SCALP_ENGULF_ENGINE_HEADER
void reset_panel(bool buy=true){
 mock_server_time=1000;reset();markers.clear();g_busy=false;g_enabled=true;InpShowInstantEngulf=true;InpEngulfOneOrderPerSignal=true;
 InpEngulfRiskPercent=1;InpEngulfSLBufferPoints=0;g_engulf_last_click=0;clock_ms=2000;_Period=1;
 bars_ok=synced=lock_ok=persist_ok=check_ok=send_ok=true;roll_bar=false;sends=alerts=closed_locks=checks_sent=0;
 send_code=TRADE_RETCODE_DONE;send_result={};g_result=g_detail="";
 chart_bar_time=960;last_shift=-1;advance_seconds=0;flush_advance_seconds=0;change_pa=change_sl=false;g_engulf_server_anchor=0;g_engulf_clock_anchor=0;
 older={840,3648,3650,3643,3645};latest=buy?MqlRates{900,3645,3653,3644,3652}:MqlRates{900,3648,3654,3640,3642};
 current_bar=buy?MqlRates{960,3650,3654,3649,3653}:MqlRates{960,3641,3656,3639,3640};
 tick=buy?MqlTick{1000,3652,3652.2}:MqlTick{1000,3642,3642.2};
}
int main(){
 PreviousEngulfTests();int before=checks;
 reset_panel();RefreshEngulfPreview();check(sends==0&&g_engulf_valid,"preview never submits");
 ExecuteEngulf(true);check(sends==1&&submitted.type==ORDER_TYPE_BUY,"BUY click sends one market order");
 check(near(submitted.tp-submitted.price,submitted.price-submitted.sl),"BUY click TP 1:1");
 check(submitted.magic==InpEngulfMagicNumber&&submitted.comment=="Scalp InstantEngulf","integrated request identity");
 check(!g_busy&&closed_locks==1,"executor releases busy and file lock");
 clock_ms+=2000;ExecuteEngulf(true);check(sends==1,"repeated signal blocked");
 g_engulf_last_click=0;ExecuteEngulf(true);check(sends==1,"reattach keeps persistent duplicate marker");
 _Period=5;clock_ms+=2000;ExecuteEngulf(true);check(sends==2,"different timeframe has separate signal identity");
 reset_panel(false);InpEngulfSLBufferPoints=20;ExecuteEngulf(false);
 check(sends==1&&submitted.type==ORDER_TYPE_SELL,"SELL click sends one market order");
 check(near(submitted.sl,3654.4)&&near(submitted.tp,3630),"SELL buffer and spread applied to 1:1 strategy");
 reset_panel();ExecuteEngulf(false);check(sends==0&&alerts>0,"wrong side alerts without submission");
 reset_panel();latest.close=3648;ExecuteEngulf(true);check(sends==0,"equal body top is not engulf");
 reset_panel();latest.close=3649;ExecuteEngulf(true);check(sends==1,"BUY body breakout inside older wick sends");
 reset_panel(false);latest.close=3644;ExecuteEngulf(false);check(sends==1,"SELL body breakout inside older wick sends");
 reset_panel();g_enabled=false;ExecuteEngulf(true);check(sends==0,"shared EA OFF blocks instant execution");
 reset_panel();InpShowInstantEngulf=false;ExecuteEngulf(true);check(sends==0,"hidden section rejects synthetic click");
 reset_panel();g_busy=true;ExecuteEngulf(true);check(sends==0,"shared busy state blocks another order path");
 reset_panel();bars_ok=false;ExecuteEngulf(true);check(sends==0,"unavailable candles block");
 reset_panel();synced=false;ExecuteEngulf(true);check(sends==0,"unsynchronized history blocks");
 reset_panel();props[TERMINAL_TRADE_ALLOWED]=0;ExecuteEngulf(true);check(sends==0,"terminal trade permission blocks");
 reset_panel();lock_ok=false;ExecuteEngulf(true);check(sends==0,"other chart holding file lock blocks");
 reset_panel();persist_ok=false;ExecuteEngulf(true);check(sends==0,"storage failure blocks before OrderSend");
 reset_panel();check_ok=false;ExecuteEngulf(true);check(sends==0,"OrderCheck rejection blocks");
 reset_panel();roll_bar=true;ExecuteEngulf(true);check(sends==0,"candle turnover after preflight blocks stale PA");
 reset_panel();props[ACCOUNT_MARGIN_MODE]=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;positions.push_back({_Symbol,POSITION_TYPE_BUY,.1});ExecuteEngulf(true);check(sends==0,"netting exposure blocked");
 reset_panel();send_code=TRADE_RETCODE_INVALID_STOPS;send_ok=false;ExecuteEngulf(true);clock_ms+=2000;ExecuteEngulf(true);check(sends==2,"definite rejection unlocks deliberate retry");
 reset_panel();send_code=TRADE_RETCODE_TIMEOUT;send_ok=false;ExecuteEngulf(true);clock_ms+=2000;ExecuteEngulf(true);check(sends==1,"uncertain response retains duplicate guard");
 reset_panel();send_code=TRADE_RETCODE_DONE_PARTIAL;ExecuteEngulf(true);clock_ms+=2000;ExecuteEngulf(true);check(sends==1,"partial fill retains duplicate guard");
 reset_panel();InpEngulfOneOrderPerSignal=false;ExecuteEngulf(true);clock_ms+=100;ExecuteEngulf(true);check(sends==1,"double-click debounce when per-signal guard off");clock_ms+=1300;ExecuteEngulf(true);check(sends==2,"guard-off permits later deliberate click");
 reset_panel();InpEngulfRiskPercent=.5;ExecuteEngulf(true);check(submitted.volume<=.05,"dedicated input risk controls instant lot");
 // Selection boundaries: >5 seconds uses closed bars; 5..1 uses bar zero.
 for(int remaining:{6,5,4,3,2,1}){
  reset_panel();mock_server_time=1020-remaining;tick.time=mock_server_time;
  RefreshEngulfPreview();check(last_shift==(remaining<=5?0:1),"5-second pair boundary");
  check(g_engulf_pair==(remaining<=5?"LIVE [0/1]":"CLOSED [1/2]"),"preview identifies selected bars");
  ExecuteEngulf(true);check(sends==1,"selected BUY pair can send");
  check(near(submitted.sl,remaining<=5?3644:3643),"SL uses extremes of the selected pair");
 }
 reset_panel(false);mock_server_time=1015;tick.time=1015;ExecuteEngulf(false);
 check(sends==1&&near(submitted.sl,3656.2),"live SELL uses current High plus spread");
 reset_panel();mock_server_time=1015;tick.time=1015;current_bar.close=3651;ExecuteEngulf(true);
 check(sends==0,"no fallback to valid closed PA when live PA fails");
 reset_panel();mock_server_time=1020;tick.time=1020;ExecuteEngulf(true);check(sends==0,"zero seconds waits for new chart bar");
 reset_panel();mock_server_time=1021;tick.time=1021;ExecuteEngulf(true);check(sends==0,"expired unchanged bar is blocked");
 reset_panel();mock_server_time=1019;tick.time=1019;advance_seconds=1;ExecuteEngulf(true);check(sends==0,"live deadline during OrderCheck blocks send");
 reset_panel();mock_server_time=1014;tick.time=1014;advance_seconds=1;ExecuteEngulf(true);check(sends==0,"closed-to-live transition during preflight blocks send");
 reset_panel();mock_server_time=1015;tick.time=1015;change_pa=true;ExecuteEngulf(true);check(sends==0,"live PA invalidated during OrderCheck blocks send");
 reset_panel();mock_server_time=1015;tick.time=1015;change_sl=true;ExecuteEngulf(true);check(sends==0,"expanded live candle SL during OrderCheck requires new click");
 reset_panel();mock_server_time=1015;tick.time=1015;ExecuteEngulf(true);check(sends==1,"live signal submitted once");
 // The same candle becomes bar one: its opening-time marker remains identical.
 older=latest;latest=current_bar;chart_bar_time=1020;mock_server_time=1021;tick.time=1021;clock_ms+=2000;
 current_bar={1020,3653,3655,3652,3654};ExecuteEngulf(true);check(sends==1,"live-to-closed duplicate remains blocked");
 reset_panel();mock_server_time=1014;tick.time=1014;RefreshEngulfPreview();clock_ms+=1000;RefreshEngulfPreview();
 check(last_shift==0,"timer reaches live window without waiting for a new tick");
 for(int period:{5,60,240,1440}){reset_panel();_Period=period;mock_server_time=chart_bar_time+period*60-5;tick.time=mock_server_time;RefreshEngulfPreview();check(last_shift==0,"final five seconds honors current timeframe");}
 reset_panel();mock_server_time=1019;tick.time=1019;flush_advance_seconds=1;
 markers[PanelEngulfSignalKey(true)]=840;ExecuteEngulf(true);
 check(sends==0,"window expiration while persisting marker blocks actual send");
 check(markers[PanelEngulfSignalKey(true)]==840,"unsent expired attempt restores previous marker");
 reset_panel();_Period=PERIOD_MN1;
 check(EngulfBarClose(StructToTime({2028,2,1,0,0,0}))==StructToTime({2028,3,1,0,0,0}),"monthly close respects leap February");
 check(EngulfBarClose(StructToTime({2027,12,1,0,0,0}))==StructToTime({2028,1,1,0,0,0}),"monthly close respects year turnover");
 std::cout<<"PASS: "<<checks-before<<" integrated executor checks; "<<checks<<" combined engulf checks\n";
}
