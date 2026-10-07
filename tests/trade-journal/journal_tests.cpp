#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <cmath>
#include <cstdio>
#include <iomanip>
#include <iostream>
#include <map>
#include <sstream>
#include <string>
#include <vector>
using string=std::string;
using datetime=long;
using ulong=unsigned long;
using uchar=unsigned char;
using ushort=unsigned short;
const int INVALID_HANDLE=-1, FILE_READ=1,FILE_WRITE=2,FILE_TXT=4,FILE_ANSI=8,FILE_SHARE_READ=16,FILE_BIN=32,FILE_SHARE_WRITE=64,FILE_REWRITE=128;
const int CP_UTF8=65001,WHOLE_ARRAY=-1,CHAR_VALUE=1,TIME_DATE=1,TIME_SECONDS=2;
const int INIT_SUCCEEDED=0,INIT_FAILED=1,INIT_PARAMETERS_INCORRECT=2;
#include "enums.hpp"
template<class T> int ArraySize(const std::vector<T>& v) { return int(v.size()); }
template<class T> int ArrayResize(std::vector<T>& v,int n,int reserve=0) { v.resize(n); return n; }
int StringLen(const string& s) { return int(s.size()); }
int StringGetCharacter(const string& s,int p) { return (unsigned char)s.at(p); }
string StringSubstr(const string& s,int p,int n=-1) { return s.substr(p,n<0?string::npos:size_t(n)); }
int StringReplace(string& s,const string& from,const string& to) { size_t p=0;int count=0;while((p=s.find(from,p))!=string::npos){s.replace(p,from.size(),to);p+=to.size();count++;}return count; }
string StringFormat(const string& f,ulong n) { if(f=="%I64u")return std::to_string(n); char b[80]; std::snprintf(b,sizeof b,"%04X",unsigned(n)); return (f=="\\u%04X"?"\\u":"")+string(b); }
string DoubleToString(double d,int digits) {std::ostringstream out;out<<std::fixed<<std::setprecision(digits)<<d;return out.str();}
string IntegerToString(long n) {return std::to_string(n);}
int StringToCharArray(const string& s,std::vector<uchar>& b,int start,int length,int cp) {b.assign(s.begin(),s.end());b.push_back(0);return b.size();}
template<class A,class B> auto MathMax(A a,B b){return std::max<double>(a,b);}
template<class A,class B> auto MathMin(A a,B b){return std::min<double>(a,b);}
long now_server=1000000,now_local=1001000,login=123456;
string server="Broker-Demo",currency="USD";
bool connected=true,tester=false;
int last_error=0;
void ResetLastError(){last_error=0;} int GetLastError(){return last_error;}
datetime TimeTradeServer(){return now_server;} datetime TimeCurrent(){return now_server;} datetime TimeLocal(){return now_local;}
string TimeToString(datetime n,int flags){return std::to_string(n);}
ulong GetTickCount64(){return now_local*1000;} ulong GetMicrosecondCount(){return now_local*1000000;}
long AccountInfoInteger(int p){return p==ACCOUNT_LOGIN?login:ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;}
string AccountInfoString(int p){return p==ACCOUNT_SERVER?server:currency;}
long TerminalInfoInteger(int p){return connected;} string TerminalInfoString(int p){return "fake-terminal";}
long MQLInfoInteger(int p){return tester;}
bool EventSetTimer(int n){return true;} void EventKillTimer(){}
template<class... T> void Print(const T&... values){} template<class... T> void Alert(const T&... values){}
template<class... T> void Comment(const T&... values){}
struct MqlTradeTransaction {ulong deal=0,order=0;string symbol="";ENUM_TRADE_TRANSACTION_TYPE type=TRADE_TRANSACTION_ORDER_ADD;ENUM_ORDER_TYPE order_type=ORDER_TYPE_BUY;ENUM_ORDER_STATE order_state=ORDER_STATE_STARTED;ENUM_DEAL_TYPE deal_type=DEAL_TYPE_BUY;int time_type=0;datetime time_expiration=0;double price=0,price_trigger=0,price_sl=0,price_tp=0,volume=0;ulong position=0,position_by=0;};
struct MqlTradeRequest{};struct MqlTradeResult{};
struct FakeHandle {string name;size_t at;int flags;};
std::map<string,string> disk; std::map<int,FakeHandle> handles; int next_handle=1;
bool fail_write=false,fail_flush=false,short_write=false;
int FileOpen(const string& name,int flags,int delimiter=0,int cp=0){
  for(const auto& it:handles){const auto& h=it.second;if(h.name!=name)continue;
    if(((flags&FILE_READ)&&!(h.flags&FILE_SHARE_READ))||((flags&FILE_WRITE)&&!(h.flags&FILE_SHARE_WRITE))||((h.flags&FILE_READ)&&!(flags&FILE_SHARE_READ))||((h.flags&FILE_WRITE)&&!(flags&FILE_SHARE_WRITE))){last_error=5004;return INVALID_HANDLE;}}
  if(!(flags&FILE_WRITE)&&!disk.count(name)){last_error=5004;return INVALID_HANDLE;}
  if(!disk.count(name)||((flags&FILE_WRITE)&&!(flags&FILE_READ)))disk[name]="";
  handles[next_handle]={name,0,flags};return next_handle++;
}
void FileClose(int h){handles.erase(h);} ulong FileSize(int h){return disk[handles.at(h).name].size();}
bool FileSeek(int h,long offset,int origin){auto& f=handles.at(h);long p=(origin==SEEK_END?long(disk[f.name].size()):0)+offset;if(p<0)return false;f.at=p;return true;}
int FileReadInteger(int h,int size){auto& f=handles.at(h);return (unsigned char)disk[f.name].at(f.at++);}
string FileReadString(int h){auto& f=handles.at(h);const auto& s=disk[f.name];auto end=s.find("\n",f.at);if(end==string::npos)end=s.size();string row=s.substr(f.at,end-f.at);if(!row.empty()&&row.back()=='\r')row.pop_back();f.at=end<s.size()?end+1:end;return row;}
bool FileIsEnding(int h){return handles.at(h).at>=FileSize(h);}
uint FileWriteString(int h,const string& s){if(fail_write){last_error=5010;return 0;}auto& f=handles.at(h);auto& bytes=disk[f.name];size_t n=short_write?s.size()/2:s.size();bytes.replace(f.at,n,s.substr(0,n));f.at+=n;return n;}
void FileFlush(int h){if(fail_flush)last_error=5011;}
struct Record{std::map<int,long> integers;std::map<int,double> doubles;std::map<int,string> strings;};
std::map<ulong,Record> deals,positions,orders; std::vector<ulong> selected_deals;
ulong selected_position=0,selected_order=0;
bool history_fail=false;
bool HistorySelect(datetime from,datetime to){if(history_fail)return false;selected_deals.clear();for(auto& [id,r]:deals)if(r.integers[DEAL_TIME_MSC]/1000>=from&&r.integers[DEAL_TIME_MSC]/1000<=to)selected_deals.push_back(id);return true;}
int HistoryDealsTotal(){return selected_deals.size();} ulong HistoryDealGetTicket(int i){return selected_deals.at(i);}
bool HistoryDealSelect(ulong id){if(!deals.count(id))return false;selected_deals={id};return true;}
long HistoryDealGetInteger(ulong id,int p){if(!deals.count(id)){last_error=4401;return 0;}return deals[id].integers[p];}
double HistoryDealGetDouble(ulong id,int p){return deals[id].doubles[p];} string HistoryDealGetString(ulong id,int p){return deals[id].strings[p];}
int PositionsTotal(){return positions.size();}int OrdersTotal(){return orders.size();}
ulong PositionGetTicket(int i){auto it=positions.begin();std::advance(it,i);selected_position=it->first;return it->first;}
ulong OrderGetTicket(int i){auto it=orders.begin();std::advance(it,i);selected_order=it->first;return it->first;}
bool PositionSelectByTicket(ulong id){if(!positions.count(id))return false;selected_position=id;return true;}
bool OrderSelect(ulong id){if(!orders.count(id))return false;selected_order=id;return true;}
long PositionGetInteger(int p){return positions[selected_position].integers[p];}double PositionGetDouble(int p){return positions[selected_position].doubles[p];}string PositionGetString(int p){return positions[selected_position].strings[p];}
long OrderGetInteger(int p){return orders[selected_order].integers[p];}double OrderGetDouble(int p){return orders[selected_order].doubles[p];}string OrderGetString(int p){return orders[selected_order].strings[p];}
long StringToInteger(const string& s){try{return std::stol(s);}catch(...){return 0;}}
string ShortToString(ushort c){return string(1,char(c));}
void StringTrimLeft(string& s){s.erase(0,s.find_first_not_of(" \t"));}void StringTrimRight(string& s){auto at=s.find_last_not_of(" \t");if(at==string::npos)s="";else s.erase(at+1);}
void StringToUpper(string& s){for(char& c:s)c=std::toupper(c);}
int StringSplit(const string& s,char delimiter,std::vector<string>& parts){parts.clear();std::istringstream in(s);string item;while(std::getline(in,item,delimiter))parts.push_back(item);return parts.size();}
ulong FileTell(int h){return handles.at(h).at;}
uint FileWriteArray(int h,const std::vector<uchar>& bytes,int start,int count){return FileWriteString(h,string(bytes.begin()+start,bytes.begin()+start+count));}
bool move_fail=false;
bool FileMove(const string& from,int origin,const string& to,int flags){if(move_fail||!disk.count(from))return false;disk[to]=disk[from];disk.erase(from);return true;}
bool IsStopped(){return false;}void Sleep(int ms){}
struct MqlRates{datetime time=0;double open=0,high=0,low=0,close=0;long tick_volume=0,real_volume=0;int spread=0;};
std::map<int,std::vector<MqlRates>> market;bool symbol_available=true;
bool SymbolSelect(const string& symbol,bool selected){return symbol_available;}
int PeriodSeconds(ENUM_TIMEFRAMES tf){if(tf==PERIOD_M1)return 60;if(tf==PERIOD_M5)return 300;if(tf==PERIOD_M15)return 900;return 3600;}
template<class T> bool ArraySetAsSeries(std::vector<T>& v,bool series){return true;}
int iBarShift(const string& symbol,ENUM_TIMEFRAMES tf,datetime t,bool exact){auto& b=market[tf];for(int i=int(b.size())-1;i>=0;i--)if(b[i].time<=t)return b.size()-1-i;return -1;}
datetime iTime(const string& symbol,ENUM_TIMEFRAMES tf,int shift){auto& b=market[tf];return shift<int(b.size())?b[b.size()-1-shift].time:0;}
int CopyRates(const string& symbol,ENUM_TIMEFRAMES tf,int start,int count,std::vector<MqlRates>& out){auto& b=market[tf];int end=int(b.size())-start;if(end<=0)return -1;int first=std::max(0,end-count);out.assign(b.begin()+first,b.begin()+end);return out.size();}
#include "production.hpp"
int checks=0;
void check(bool ok,const string& reason){checks++;if(!ok){std::cerr<<"FAIL: "<<reason<<"\n";std::exit(1);}}
std::vector<std::vector<string>> rows(const string& suffix){std::vector<std::vector<string>> result;string all=disk[g_folder+"\\"+suffix];std::istringstream in(all);string row;std::getline(in,row);while(std::getline(in,row)){if(!row.empty()&&row.back()=='\r')row.pop_back();std::vector<string> f;check(TJParse(row,f),"CSV row parse "+suffix);result.push_back(f);}return result;}
void runtime_reset(){
 g_deals=g_events=g_sessions=g_lock=INVALID_HANDLE;g_login=0;g_server=g_currency=g_folder=g_session=g_error="";
 g_failed=g_started=g_connected=g_backfill=false;g_snapshot_baseline=true;g_sequence=g_written=g_last_heartbeat=0;
 g_scan_until=g_last_scan=0;g_known.clear();g_positions.clear();g_orders.clear();g_scan_tickets.clear();g_scan_at=g_retry_at=0;g_queue.clear();g_queue_count=0;g_retry.clear();
 InpHistoryDays=0;InpReconcileSeconds=30;InpShowStatus=false;fail_write=fail_flush=short_write=history_fail=tester=false;
 now_local++;handles.clear();
}
Record deal(ulong position,ulong order,int entry,int type,double volume,double profit,long magic=0){Record r;r.integers={{DEAL_POSITION_ID,long(position)},{DEAL_ORDER,long(order)},{DEAL_TIME_MSC,now_server*1000},{DEAL_TYPE,type},{DEAL_ENTRY,entry},{DEAL_REASON,magic?DEAL_REASON_EXPERT:DEAL_REASON_CLIENT},{DEAL_MAGIC,magic}};r.doubles={{DEAL_VOLUME,volume},{DEAL_PRICE,3650.25},{DEAL_SL,3640},{DEAL_TP,3660},{DEAL_PROFIT,profit},{DEAL_COMMISSION,-.5},{DEAL_SWAP,-.1},{DEAL_FEE,-.2}};r.strings={{DEAL_SYMBOL,"XAUUSD"},{DEAL_COMMENT,"manual, \"test\"\nline"},{DEAL_EXTERNAL_ID,"=not-a-formula"}};return r;}
void tx(ENUM_TRADE_TRANSACTION_TYPE kind,ulong id=0,double sl=0,double tp=0){MqlTradeTransaction t;t.type=kind;t.deal=id;t.order=800;t.position=900;t.symbol="XAUUSD";t.price_sl=sl;t.price_tp=tp;t.price=3650;t.volume=.1;OnTradeTransaction(t,MqlTradeRequest{},MqlTradeResult{});}
int main(){
 // CSV escapes, exact 64-bit ticket roundtrip, injection-safe free text only.
 string r="";TJAdd(r,"a,b");TJAdd(r,"a\"b");TJAdd(r,"ไทย\nline",true);TJAdd(r,"=1+1",true);TJAdd(r,"-12.5");
 std::vector<string> f;check(TJParse(r,f)&&f.size()==5,"CSV columns");check(f[0]=="a,b"&&f[1]=="a\"b"&&f[2]=="ไทย\\nline","text escaping");check(f[3]=="'=1+1"&&f[4]=="-12.5","protect text without damaging numbers");
 for(const string& invalid:{"", "\"unfinished", "\"a\",", "unquoted", "\"a\"garbage", "\"a\",b"})check(!TJParse(invalid,f),"reject malformed CSV");
 ulong u=0;check(TJUnsigned("18446744073709551615",u)&&TJId(u)=="18446744073709551615","max uint64");check(!TJUnsigned("18446744073709551616",u)&&!TJUnsigned("-1",u)&&!TJUnsigned("1.0",u),"invalid IDs");
 check(TJServerKey("A/B")!=TJServerKey("A:B"),"account server paths cannot sanitize to same name");
 std::vector<TJState> index;
 for(ulong id:{900ul,1ul,300ul})check(TJCommit(index,id,"p",false,1),"index insert");
 check(index[0].ticket==1&&index[1].ticket==300&&index[2].ticket==900,"sorted index");check(TJRevision(index,300,"p",false)==0&&TJRevision(index,300,"changed",false)==2,"dedup and corrections");
 check(TJRevision(index,300,"p",true)==2,"delete has separate revision");
 // Full initialization, pending baseline and hedged positions. Real historical deals.
 deals[100]=deal(900,800,DEAL_ENTRY_IN,DEAL_TYPE_BUY,.2,0,26091201);
 deals[101]=deal(900,801,DEAL_ENTRY_OUT,DEAL_TYPE_SELL,.1,10);
 deals[102]=deal(900,802,DEAL_ENTRY_OUT,DEAL_TYPE_SELL,.1,-5);
 positions[900].integers={{POSITION_IDENTIFIER,900},{POSITION_TYPE,POSITION_TYPE_BUY},{POSITION_MAGIC,26091201},{POSITION_REASON,POSITION_REASON_EXPERT}};
 positions[900].doubles={{POSITION_VOLUME,.2},{POSITION_PRICE_OPEN,3650},{POSITION_SL,3640},{POSITION_TP,3660}};positions[900].strings[POSITION_SYMBOL]="XAUUSD";
 positions[901]=positions[900];positions[901].integers[POSITION_IDENTIFIER]=901;positions[901].integers[POSITION_TYPE]=POSITION_TYPE_SELL;
 orders[810].integers={{ORDER_POSITION_ID,0},{ORDER_TYPE,ORDER_TYPE_BUY_LIMIT},{ORDER_STATE,ORDER_STATE_PLACED},{ORDER_REASON,ORDER_REASON_CLIENT}};
 orders[810].doubles={{ORDER_VOLUME_CURRENT,.3},{ORDER_PRICE_OPEN,3630},{ORDER_SL,3620},{ORDER_TP,3640}};orders[810].strings[ORDER_SYMBOL]="XAUUSD";
 check(OnInit()==INIT_SUCCEEDED,"initialize");check(g_lock!=INVALID_HANDLE,"exclusive lock held");
 int second=FileOpen(g_folder+"\\writer.lock",FILE_READ|FILE_WRITE|FILE_BIN);check(second==INVALID_HANDLE,"second writer blocked");
 OnTimer();check(!g_failed&&g_known.size()==3,"history scan snapshots IDs before per-deal select");
 auto d=rows("deals.csv");check(d.size()==3&&d[0].size()==30,"one row per execution");check(d[0][17]=="26091201"&&d[0][16]=="DEAL_REASON_EXPERT","calculator orders included");check(d[1][15]=="DEAL_ENTRY_OUT"&&d[1][11]=="900"&&d[2][11]=="900","partial closes link stable position");check(d[1][27]=="9.2000000000","net includes profit commission swap fee");
 auto e=rows("events.csv");check(e.size()==3&&e[0].size()==26,"two hedged positions and pending baseline");check(e[0][6]=="POSITION_BASELINE"&&e[2][6]=="ORDER_BASELINE","first observed levels not claimed as historical initial");
 auto original_deals=disk[g_folder+"\\deals.csv"];OnTimer();check(disk[g_folder+"\\deals.csv"]==original_deals,"repeated timer doesn't duplicate deals");
 // Multiple SL edits in one second retained from event payload, not latest polling state.
 size_t before=disk[g_folder+"\\events.csv"].size();tx(TRADE_TRANSACTION_POSITION,0,3641,3661);tx(TRADE_TRANSACTION_POSITION,0,3642,3662);check(disk[g_folder+"\\events.csv"].size()==before&&g_queue_count==2,"handler queues without IO");
 positions[900].doubles[POSITION_SL]=3642;OnTimer();e=rows("events.csv");check(e[3][21]==TJNum(3641)&&e[4][21]==TJNum(3642),"intermediate SL retained");check(e[3][14].empty()&&e[3][23].empty(),"unknown transaction identifier and magic left blank");check(e.back()[6]=="POSITION_CHANGED","snapshot corroborates current level");
 tx(TRADE_TRANSACTION_REQUEST);check(g_queue_count==0,"request acceptance is not a deal");
 // Late availability, correction, deletion and reinsertion.
 tx(TRADE_TRANSACTION_DEAL_ADD,103);OnTimer();check(g_retry.size()==1,"deal history not ready retained for retry");
 deals[103]=deal(901,803,DEAL_ENTRY_INOUT,DEAL_TYPE_SELL,.5,4,26091202);OnTimer();check(g_retry.empty()&&g_known.size()==4,"late deal recovered");
 d=rows("deals.csv");check(d.back()[15]=="DEAL_ENTRY_INOUT"&&d.back()[17]=="26091202","netting reversal and instant magic preserved");
 deals[103].doubles[DEAL_COMMISSION]=-1.5;tx(TRADE_TRANSACTION_DEAL_UPDATE,103);OnTimer();d=rows("deals.csv");check(d.back()[4]=="2"&&d.back()[27]=="2.2000000000","broker correction versioned");
 deals.erase(103);tx(TRADE_TRANSACTION_DEAL_DELETE,103);OnTimer();d=rows("deals.csv");check(d.back()[3]=="DELETE"&&d.back()[4]=="3","deletion is tombstone");check(TJRefreshDeal(103,"TEST"),"deleted deal not stuck retrying");
 tx(TRADE_TRANSACTION_DEAL_DELETE,104);OnTimer();d=rows("deals.csv");check(d.back()[9]=="104"&&d.back()[3]=="DELETE","unknown deleted deal still gets tombstone");
 deals[103]=deal(901,803,DEAL_ENTRY_OUT_BY,DEAL_TYPE_BUY,.1,3);tx(TRADE_TRANSACTION_DEAL_ADD,103);OnTimer();d=rows("deals.csv");check(d.back()[4]=="4"&&d.back()[15]=="DEAL_ENTRY_OUT_BY","close-by or restored deal retained");
 positions.erase(901);orders.erase(810);OnTimer();e=rows("events.csv");check(e[e.size()-2][6]=="POSITION_NO_LONGER_OPEN"&&e.back()[6]=="ORDER_NO_LONGER_ACTIVE","removed states labeled observations");check(e[e.size()-2][5]=="LAST_OBSERVED_SNAPSHOT","last snapshot not fabricated fill");
 // Reattach: no duplicated deal or correction, late fees appear as independent broker rows.
 OnDeinit(0);check(OnInit()==INIT_SUCCEEDED,"chart/input reinit restores ledger without global reset");auto count=rows("deals.csv").size();OnTimer();check(rows("deals.csv").size()==count,"restart history dedup");
 deals[105]=deal(0,0,DEAL_ENTRY_IN,DEAL_TYPE_COMMISSION,0,-2);deals[105].doubles[DEAL_COMMISSION]=deals[105].doubles[DEAL_SWAP]=deals[105].doubles[DEAL_FEE]=0;deals[105].strings[DEAL_SYMBOL]="";
 now_server+=31;OnTimer();d=rows("deals.csv");check(d.back()[14]=="DEAL_TYPE_COMMISSION"&&d.back()[11]=="0","unallocated broker fees retained without invented trade linkage");
 // Disconnect does not turn missing cached positions into real close events.
 connected=false;before=disk[g_folder+"\\events.csv"].size();positions.clear();OnTimer();check(disk[g_folder+"\\events.csv"].size()==before,"no snapshots while disconnected");connected=true;OnTimer();check(!g_failed,"reconnect reconciles");
 OnDeinit(0);runtime_reset();check(OnInit()==INIT_SUCCEEDED,"second restart");OnTimer();
 // Stop on cross-account access before touching the old files.
 before=disk[g_folder+"\\deals.csv"].size();login++;tx(TRADE_TRANSACTION_DEAL_ADD,106);check(g_failed&&disk[g_folder+"\\deals.csv"].size()==before,"account isolation");OnDeinit(0);login--;
 // Durable state only advances after successful write and flush.
 runtime_reset();check(OnInit()==INIT_SUCCEEDED,"restart before failure test");size_t known=g_known.size();fail_write=true;check(!TJStoreDeal(999,TJDealPayload(100),false,"TEST")&&g_failed&&g_known.size()==known,"write failure never commits dedup state");OnDeinit(0);
 runtime_reset();check(OnInit()==INIT_SUCCEEDED,"write failure left intact ledger");deals[100].doubles[DEAL_COMMISSION]=-3;fail_flush=true;check(!TJStoreDeal(100,TJDealPayload(100),false,"TEST")&&g_failed,"flush failure stops recorder");OnDeinit(0);
 runtime_reset();check(OnInit()==INIT_SUCCEEDED,"fully written row after uncertain flush recovered");count=rows("deals.csv").size();OnTimer();check(rows("deals.csv").size()==count,"uncertain flush recovery does not duplicate");OnDeinit(0);
 // New empty disk for corruption tests, preserve artifact evidence instead of silently truncating it.
 disk.clear();runtime_reset();check(OnInit()==INIT_SUCCEEDED,"fresh files");string path=g_folder+"\\deals.csv";OnDeinit(0);disk[path]+="\"1\",\"torn";runtime_reset();check(OnInit()==INIT_FAILED&&g_failed,"torn ledger rejected");OnDeinit(0);
 disk.clear();runtime_reset();check(OnInit()==INIT_SUCCEEDED,"fresh complete tail test");path=g_folder+"\\sessions.csv";OnDeinit(0);disk[path].resize(disk[path].size()-2);runtime_reset();check(OnInit()==INIT_FAILED&&g_failed,"missing final CRLF rejected even if row otherwise valid");OnDeinit(0);
 disk.clear();runtime_reset();tester=true;check(OnInit()==INIT_FAILED&&handles.empty(),"tester cannot mix simulated and actual journals");
 disk.clear();runtime_reset();check(OnInit()==INIT_SUCCEEDED,"queue overflow setup");g_queue_count=QUEUE_LIMIT;tx(TRADE_TRANSACTION_POSITION);check(g_failed,"queue overflow prominently stops recording");OnDeinit(0);
 // History batching is not disrupted by a live per-ticket select between batches.
 disk.clear();runtime_reset();deals.clear();positions.clear();orders.clear();
 for(ulong id=1000;id<1450;id++)deals[id]=deal(id, id,DEAL_ENTRY_IN,DEAL_TYPE_BUY,.01,0);
 check(OnInit()==INIT_SUCCEEDED,"large history init");OnTimer();check(g_known.size()==200&&g_backfill,"history work bounded to 200 per pass");
 deals[1500]=deal(1500,1500,DEAL_ENTRY_IN,DEAL_TYPE_SELL,.02,0);tx(TRADE_TRANSACTION_DEAL_ADD,1500);OnTimer();check(g_known.size()==401,"live deal and second history batch coexist");OnTimer();check(g_known.size()==451&&!g_backfill,"all history IDs survive selected-list resets");
 for(ulong id=4000;id<4250;id++)TJRetry(id);
 TJRetry(1500);OnTimer();OnTimer();check(g_retry.size()==250,"unavailable tickets cannot starve a ready retry");OnDeinit(0);
 // File short-write halts before advancing the durable index; next attach rejects torn bytes.
 disk.clear();runtime_reset();deals.clear();check(OnInit()==INIT_SUCCEEDED,"short-write setup");deals[1]=deal(1,1,DEAL_ENTRY_IN,DEAL_TYPE_BUY,.1,0);short_write=true;
 check(!TJRefreshDeal(1,"TEST")&&g_failed&&g_known.empty(),"short write cannot commit state");OnDeinit(0);short_write=false;
 check(OnInit()==INIT_FAILED,"short write detected on reinit");OnDeinit(0);
 // Account/server identity survives spreadsheet-safe escaping and changing accounts.
 disk.clear();runtime_reset();server="=Broker,Test";check(OnInit()==INIT_SUCCEEDED,"unusual server name");OnTimer();count=g_known.size();OnDeinit(0);check(OnInit()==INIT_SUCCEEDED&&g_known.size()==count,"escaped server identity reload");OnDeinit(0);
 string old_folder=g_folder;login++;check(OnInit()==INIT_SUCCEEDED&&g_folder!=old_folder,"reinit on different account uses another folder");OnDeinit(0);login--;server="Broker-Demo";
 // Actual exporter reads the same active journal without modifying its ledgers.
 disk.clear();runtime_reset();deals.clear();positions.clear();orders.clear();
 deals[11]=deal(90,80,DEAL_ENTRY_IN,DEAL_TYPE_BUY,.2,0);deals[11].integers[DEAL_TIME_MSC]=(now_server-100*60)*1000;deals[11].strings[DEAL_COMMENT]="</script><script>bad()</script>";
 deals[12]=deal(90,81,DEAL_ENTRY_OUT,DEAL_TYPE_SELL,.2,5);deals[12].integers[DEAL_TIME_MSC]=(now_server-80*60)*1000;
 check(OnInit()==INIT_SUCCEEDED,"report source recorder init");OnTimer();
 for(auto tf:{PERIOD_M1,PERIOD_M5,PERIOD_M15})for(int i=0;i<=300;i++){MqlRates b;b.time=now_server-(300-i)*PeriodSeconds(tf);b.open=100+i;b.high=b.open+2;b.low=b.open-2;b.close=b.open+1;b.tick_volume=100;b.spread=20;market[tf].push_back(b);}
 InpReportTimeframes="M1, M5,M15,M1";check(JRTimeframes()&&jr_tfs.size()==3,"report TF parsing and dedup");InpReportTimeframes="M7";check(!JRTimeframes(),"unsupported TF rejected");InpReportTimeframes="M1,M5,M15";
 InpBarsBefore=10;InpBarsAfter=5;InpMaxBarsPerChart=10000;InpMaxPositions=0;
 auto ledger=disk[g_folder+"\\deals.csv"];OnStart();check(jr_error.empty(),"reporter reads active CSV snapshot");check(disk[g_folder+"\\deals.csv"]==ledger,"exporter leaves original ledger untouched");
 auto report=disk[g_folder+"\\journal.html"];check(report.find("\"status\":\"ready\"")!=string::npos,"candles included");check(report.find("\\u003c/script")!=string::npos&&report.find("</script><script>bad")==string::npos,"embedded data escapes HTML breakout");check(jr_positions.size()==1&&jr_positions[0].first==now_server-100*60,"group entry and partial exit times");
 string chart=JRCandles(jr_positions[0],PERIOD_M1,"M1");check(chart.find("\"afterAvailable\":5")!=string::npos,"context includes requested after bars");
 InpMaxBarsPerChart=5;chart=JRCandles(jr_positions[0],PERIOD_M1,"M1");check(chart.find("bar_limit_use_higher_tf")!=string::npos&&chart.find("\"bars\":[]")!=string::npos,"long hold does not silently truncate candles");InpMaxBarsPerChart=10000;
 JRPosition open_report=jr_positions[0];open_report.last=now_server;open_report.open=true;chart=JRCandles(open_report,PERIOD_M1,"M1");check(chart.find("\"afterAvailable\":0")!=string::npos&&chart.find(",false]")!=string::npos,"future context unavailable and current candle explicitly unclosed");
 InpBarsBefore=400;chart=JRCandles(jr_positions[0],PERIOD_M1,"M1");check(chart.find("partial_history")!=string::npos,"limited broker candles explicitly partial");InpBarsBefore=10;
 symbol_available=false;check(JRCandles(jr_positions[0],PERIOD_M1,"M1").find("symbol_unavailable")!=string::npos,"missing symbol explicit");symbol_available=true;
 market[PERIOD_M1].clear();check(JRCandles(jr_positions[0],PERIOD_M1,"M1").find("history_unavailable")!=string::npos,"missing history explicit");
 move_fail=true;OnStart();check(!jr_error.empty()&&disk[g_folder+"\\journal.html"]==report,"failed publication preserves previous complete report");move_fail=false;
 OnDeinit(0);
 std::cout<<"TradeJournal: "<<checks<<" checks passed (production core, persistence, handlers, history, snapshots; mocked MT5 APIs).\n";
}
