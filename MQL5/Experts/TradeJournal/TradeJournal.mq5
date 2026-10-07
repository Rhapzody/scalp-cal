#property copyright "MT5 Trading Tools"
#property version "1.20"
#property strict
#property description "Passive account-wide CSV journal. Records manual and EA trades; never trades."
#include "JournalCore.mqh"

input group "Recording"
input int InpHistoryDays=0; // 0 = all history available from broker, on each startup
input int InpReconcileSeconds=30; // History safety scan, in addition to transaction events
input bool InpShowStatus=true;

const string DEAL_HEADER="schema_version,recorded_server_time,session_id,action,revision,origin,account_login,account_server,currency,deal_ticket,order_ticket,position_id,deal_time_msc,deal_time,deal_type,entry,reason,magic,symbol,volume,price,sl,tp,profit,commission,swap,fee,net,comment,external_id";
const string EVENT_HEADER="schema_version,observed_server_time,observed_local_time,session_id,sequence,origin,event,account_login,account_server,currency,symbol,order_ticket,deal_ticket,position_ticket,position_id,position_by_ticket,order_type,order_state,deal_or_position_type,volume,price,sl,tp,magic,reason,comment";
const string SESSION_HEADER="schema_version,server_time,local_time,session_id,account_login,account_server,event,detail";
int g_deals=INVALID_HANDLE,g_events=INVALID_HANDLE,g_sessions=INVALID_HANDLE,g_lock=INVALID_HANDLE;
long g_login=0;
string g_server="",g_currency="",g_folder="",g_session="",g_error="";
bool g_failed=false,g_started=false,g_connected=false,g_backfill=false,g_snapshot_baseline=true;
ulong g_sequence=0,g_written=0,g_last_heartbeat=0;
datetime g_scan_until=0,g_last_scan=0;
TJState g_known[],g_positions[],g_orders[];
ulong g_scan_tickets[];
int g_scan_at=0,g_retry_at=0;

struct TJQueued
{
   MqlTradeTransaction tx;
   datetime server_time,local_time;
};
TJQueued g_queue[];
int g_queue_count=0;
const int QUEUE_LIMIT=8192;
ulong g_retry[];

string TJTime(const datetime value) { return TimeToString(value,TIME_DATE|TIME_SECONDS); }
datetime TJNow() { datetime value=TimeTradeServer(); return value>0 ? value : TimeCurrent(); }
bool TJAccount() { return AccountInfoInteger(ACCOUNT_LOGIN)==g_login && AccountInfoString(ACCOUNT_SERVER)==g_server; }
void TJFail(const string reason)
{
   if(!g_failed) { Print("TradeJournal STOPPED: ",reason); Alert("TradeJournal stopped recording: ",reason); }
   g_failed=true; g_error=reason;
}
bool TJAppend(const int handle,const string row)
{
   if(g_failed || handle==INVALID_HANDLE) return false;
   ResetLastError();
   string line=row+"\r\n";
   // ANSI handle uses UTF-8; compare the byte count, not UTF-16 character length.
   uchar bytes[];
   int expected=StringToCharArray(line,bytes,0,WHOLE_ARRAY,CP_UTF8)-1;
   uint written=FileWriteString(handle,line);
   int error=GetLastError();
   if(expected<0 || written!=(uint)expected || error!=0)
   { TJFail("CSV write failed ("+IntegerToString(error)+"). Check disk/permissions; keep files for recovery."); return false; }
   ResetLastError();
   FileFlush(handle);
   if(GetLastError()!=0) { TJFail("CSV flush failed. Recording halted."); return false; }
   return true;
}
bool TJSession(const string event,const string detail)
{
   string row="";
   TJAdd(row,"1"); TJAdd(row,TJTime(TJNow())); TJAdd(row,TJTime(TimeLocal())); TJAdd(row,g_session);
   TJAdd(row,IntegerToString(g_login)); TJAdd(row,g_server,true); TJAdd(row,event); TJAdd(row,detail,true);
   return TJAppend(g_sessions,row);
}

int TJOpen(const string name,const string header)
{
   ResetLastError();
   if(g_failed) return INVALID_HANDLE;
   int handle=FileOpen(g_folder+"\\"+name,FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ,0,CP_UTF8);
   if(handle==INVALID_HANDLE) { TJFail("Cannot open "+name+" ("+IntegerToString(GetLastError())+")."); return INVALID_HANDLE; }
   if(FileSize(handle)==0)
   {
      if(!TJAppend(handle,header)) { FileClose(handle); return INVALID_HANDLE; }
   }
   else
   {
      // Refuse a complete-looking final row without its terminating newline.
      int tail=FileOpen(g_folder+"\\"+name,FILE_READ|FILE_BIN|FILE_SHARE_READ|FILE_SHARE_WRITE);
      bool terminated=false;
      if(tail!=INVALID_HANDLE)
      {
         if(FileSize(tail)>=2 && FileSeek(tail,-2,SEEK_END))
         { int cr=FileReadInteger(tail,CHAR_VALUE); int lf=FileReadInteger(tail,CHAR_VALUE); terminated=(cr==13 && lf==10); }
         FileClose(tail);
      }
      if(!terminated) { FileClose(handle); TJFail("Incomplete CSV ending: "+name+". Back up and repair before restarting."); return INVALID_HANDLE; }
      string first=FileReadString(handle);
      if(first!=header) { FileClose(handle); TJFail("Unexpected CSV schema: "+name); return INVALID_HANDLE; }
   }
   return handle; // Immediately after header, for validation / recovery.
}

bool TJLoadDeals()
{
   string fields[];
   while(!FileIsEnding(g_deals))
   {
      string line=FileReadString(g_deals);
      if(!TJParse(line,fields) || ArraySize(fields)!=30 || fields[0]!="1")
      { TJFail("Invalid/torn deals.csv row. Back up files and repair before restarting."); return false; }
      ulong ticket=0,revision=0;
      if(!TJUnsigned(fields[9],ticket) || ticket==0 || !TJUnsigned(fields[4],revision) || revision==0 || revision>2147483647 ||
         (fields[3]!="UPSERT" && fields[3]!="DELETE") || fields[6]!=IntegerToString(g_login) || TJCell(fields[7])!=TJCell(g_server,true))
      { TJFail("Invalid deal identity or revision in deals.csv."); return false; }
      string payload="";
      for(int i=6;i<30;i++) TJAdd(payload,fields[i]);
      bool deleted=fields[3]=="DELETE";
      int expected=TJRevision(g_known,ticket,payload,deleted);
      if(expected!=(int)revision) { TJFail("Nonsequential deal revision in deals.csv."); return false; }
      if(!TJCommit(g_known,ticket,payload,deleted,(int)revision)) { TJFail("Cannot allocate deal index."); return false; }
   }
   return true;
}
bool TJValidateTail(const int handle,const int columns)
{
   string fields[];
   while(!FileIsEnding(handle))
   {
      string line=FileReadString(handle);
      if(!TJParse(line,fields) || ArraySize(fields)!=columns || fields[0]!="1")
      { TJFail("Invalid/torn event or session CSV. Back up and repair before restarting."); return false; }
   }
   return true;
}

string TJDealPayload(const ulong ticket)
{
   string row="";
   TJAdd(row,IntegerToString(g_login)); TJAdd(row,g_server,true); TJAdd(row,g_currency,true);
   TJAdd(row,TJId(ticket)); TJAdd(row,TJId((ulong)HistoryDealGetInteger(ticket,DEAL_ORDER)));
   TJAdd(row,TJId((ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID)));
   long time_msc=HistoryDealGetInteger(ticket,DEAL_TIME_MSC);
   TJAdd(row,IntegerToString(time_msc)); TJAdd(row,TJTime((datetime)(time_msc/1000)));
   TJAdd(row,EnumToString((ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket,DEAL_TYPE)));
   TJAdd(row,EnumToString((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket,DEAL_ENTRY)));
   TJAdd(row,EnumToString((ENUM_DEAL_REASON)HistoryDealGetInteger(ticket,DEAL_REASON)));
   TJAdd(row,TJId((ulong)HistoryDealGetInteger(ticket,DEAL_MAGIC)));
   TJAdd(row,HistoryDealGetString(ticket,DEAL_SYMBOL),true);
   TJAdd(row,TJNum(HistoryDealGetDouble(ticket,DEAL_VOLUME)));
   TJAdd(row,TJNum(HistoryDealGetDouble(ticket,DEAL_PRICE)));
   TJAdd(row,TJNum(HistoryDealGetDouble(ticket,DEAL_SL)));
   TJAdd(row,TJNum(HistoryDealGetDouble(ticket,DEAL_TP)));
   double profit=HistoryDealGetDouble(ticket,DEAL_PROFIT),commission=HistoryDealGetDouble(ticket,DEAL_COMMISSION);
   double swap=HistoryDealGetDouble(ticket,DEAL_SWAP),fee=HistoryDealGetDouble(ticket,DEAL_FEE);
   TJAdd(row,TJNum(profit)); TJAdd(row,TJNum(commission)); TJAdd(row,TJNum(swap)); TJAdd(row,TJNum(fee));
   TJAdd(row,TJNum(profit+commission+swap+fee));
   TJAdd(row,HistoryDealGetString(ticket,DEAL_COMMENT),true); TJAdd(row,HistoryDealGetString(ticket,DEAL_EXTERNAL_ID),true);
   return row;
}
bool TJStoreDeal(const ulong ticket,const string payload,const bool deleted,const string origin)
{
   int revision=TJRevision(g_known,ticket,payload,deleted);
   if(revision==0) return true;
   string row="";
   TJAdd(row,"1"); TJAdd(row,TJTime(TJNow())); TJAdd(row,g_session);
   TJAdd(row,deleted ? "DELETE" : "UPSERT"); TJAdd(row,IntegerToString(revision)); TJAdd(row,origin);
   row+=","+payload;
   if(!TJAppend(g_deals,row)) return false;
   if(!TJCommit(g_known,ticket,payload,deleted,revision)) { TJFail("Cannot allocate deal index after append."); return false; }
   g_written++;
   return true;
}
bool TJRefreshDeal(const ulong ticket,const string origin)
{
   if(ticket==0) return false;
   if(!HistoryDealSelect(ticket))
   {
      int at=TJLower(g_known,ticket);
      return at<ArraySize(g_known) && g_known[at].ticket==ticket && g_known[at].deleted;
   }
   ResetLastError();
   string payload=TJDealPayload(ticket);
   if(GetLastError()!=0) return false; // Never persist a partially read deal as zeros.
   return TJStoreDeal(ticket,payload,false,origin);
}
void TJRetry(const ulong ticket)
{
   if(ticket==0) return;
   for(int i=0;i<ArraySize(g_retry);i++) if(g_retry[i]==ticket) return;
   int n=ArraySize(g_retry);
   if(ArrayResize(g_retry,n+1,256)!=n+1) { TJFail("Cannot queue history retry."); return; }
   g_retry[n]=ticket;
}
void TJDeleteDeal(const ulong ticket)
{
   if(ticket==0) return;
   int at=TJLower(g_known,ticket);
   if(at<ArraySize(g_known) && g_known[at].ticket==ticket)
      TJStoreDeal(ticket,g_known[at].payload,true,"LIVE_DELETE");
   else
   {
      string payload="";
      TJAdd(payload,IntegerToString(g_login)); TJAdd(payload,g_server,true); TJAdd(payload,g_currency,true); TJAdd(payload,TJId(ticket));
      for(int i=0;i<20;i++) TJAdd(payload,"");
      TJStoreDeal(ticket,payload,true,"LIVE_DELETE");
   }
   // Raw DEAL_DELETE remains in events.csv even if its old deal was never observed.
}

string TJEventPrefix(const datetime server_time,const datetime local_time,const string origin,const string event)
{
   string row="";
   TJAdd(row,"1"); TJAdd(row,TJTime(server_time)); TJAdd(row,TJTime(local_time)); TJAdd(row,g_session);
   TJAdd(row,TJId(++g_sequence)); TJAdd(row,origin); TJAdd(row,event);
   TJAdd(row,IntegerToString(g_login)); TJAdd(row,g_server,true); TJAdd(row,g_currency,true);
   return row;
}
string TJTransactionRow(const TJQueued &item)
{
   MqlTradeTransaction t=item.tx;
   bool order=t.type==TRADE_TRANSACTION_ORDER_ADD || t.type==TRADE_TRANSACTION_ORDER_UPDATE ||
              t.type==TRADE_TRANSACTION_ORDER_DELETE || t.type==TRADE_TRANSACTION_HISTORY_ADD ||
              t.type==TRADE_TRANSACTION_HISTORY_UPDATE || t.type==TRADE_TRANSACTION_HISTORY_DELETE;
   bool deal=t.type==TRADE_TRANSACTION_DEAL_ADD || t.type==TRADE_TRANSACTION_DEAL_UPDATE || t.type==TRADE_TRANSACTION_DEAL_DELETE;
   string row=TJEventPrefix(item.server_time,item.local_time,"LIVE_TRANSACTION",EnumToString(t.type));
   TJAdd(row,t.symbol,true); TJAdd(row,order || deal ? TJId(t.order) : ""); TJAdd(row,deal ? TJId(t.deal) : "");
   TJAdd(row,TJId(t.position)); TJAdd(row,""); // Position ticket is NOT stable position identifier.
   TJAdd(row,order || deal ? TJId(t.position_by) : "");
   TJAdd(row,order ? EnumToString(t.order_type) : ""); TJAdd(row,order ? EnumToString(t.order_state) : "");
   TJAdd(row,order ? "" : EnumToString(t.deal_type));
   TJAdd(row,TJNum(t.volume)); TJAdd(row,TJNum(t.price)); TJAdd(row,TJNum(t.price_sl)); TJAdd(row,TJNum(t.price_tp));
   // Request-only metadata is not available here. Enrich from separate history/snapshot rows, never guess.
   TJAdd(row,""); TJAdd(row,""); TJAdd(row,"");
   return row;
}
void TJDrain()
{
   for(int i=0;i<g_queue_count && !g_failed;i++)
   {
      if(!TJAppend(g_events,TJTransactionRow(g_queue[i]))) break;
      MqlTradeTransaction t=g_queue[i].tx;
      if(t.type==TRADE_TRANSACTION_DEAL_DELETE) TJDeleteDeal(t.deal);
      else if(t.type==TRADE_TRANSACTION_DEAL_ADD || t.type==TRADE_TRANSACTION_DEAL_UPDATE) TJRetry(t.deal);
   }
   g_queue_count=0;
}

bool TJBeginScan(const bool full)
{
   datetime until=TJNow();
   datetime from=full ? (InpHistoryDays==0 ? 0 : (datetime)MathMax(0,(long)until-(long)InpHistoryDays*86400)) :
                       (datetime)MathMax(0,(long)g_last_scan-120);
   if(!HistorySelect(from,until)) return false;
   int n=HistoryDealsTotal();
   if(ArrayResize(g_scan_tickets,n)!=n) { TJFail("Cannot allocate history scan."); return false; }
   // Snapshot IDs before HistoryDealSelect replaces the terminal's selected history list.
   for(int i=0;i<n;i++)
   {
      g_scan_tickets[i]=HistoryDealGetTicket(i);
      if(g_scan_tickets[i]==0) { ArrayResize(g_scan_tickets,0); return false; }
   }
   g_scan_at=0; g_scan_until=until; g_backfill=full;
   return true;
}
void TJScanBatch()
{
   int stop=(int)MathMin(ArraySize(g_scan_tickets),g_scan_at+200);
   while(g_scan_at<stop && !g_failed)
   {
      ulong ticket=g_scan_tickets[g_scan_at++];
      if(!TJRefreshDeal(ticket,g_backfill ? "HISTORY_BACKFILL" : "HISTORY_RECONCILE")) TJRetry(ticket);
   }
   if(g_scan_at==ArraySize(g_scan_tickets))
   {
      g_last_scan=g_scan_until;
      ArrayResize(g_scan_tickets,0); g_scan_at=0;
      if(g_backfill) { TJSession("BACKFILL_SCANNED","Available deal history scanned; unresolved tickets="+IntegerToString(ArraySize(g_retry))+". Historical SL/TP edit paths are unavailable."); g_backfill=false; }
   }
}

// Snapshot payload columns 10..25. Raw transaction rows preserve intermediate SL/TP edits.
string TJPositionPayload(const ulong ticket)
{
   string row="";
   TJAdd(row,PositionGetString(POSITION_SYMBOL),true); TJAdd(row,""); TJAdd(row,""); TJAdd(row,TJId(ticket));
   TJAdd(row,TJId((ulong)PositionGetInteger(POSITION_IDENTIFIER))); TJAdd(row,""); TJAdd(row,""); TJAdd(row,"");
   TJAdd(row,EnumToString((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)));
   TJAdd(row,TJNum(PositionGetDouble(POSITION_VOLUME))); TJAdd(row,TJNum(PositionGetDouble(POSITION_PRICE_OPEN)));
   TJAdd(row,TJNum(PositionGetDouble(POSITION_SL))); TJAdd(row,TJNum(PositionGetDouble(POSITION_TP)));
   TJAdd(row,TJId((ulong)PositionGetInteger(POSITION_MAGIC)));
   TJAdd(row,EnumToString((ENUM_POSITION_REASON)PositionGetInteger(POSITION_REASON)));
   TJAdd(row,PositionGetString(POSITION_COMMENT),true);
   return row;
}
string TJOrderPayload(const ulong ticket)
{
   string row="";
   TJAdd(row,OrderGetString(ORDER_SYMBOL),true); TJAdd(row,TJId(ticket)); TJAdd(row,""); TJAdd(row,"");
   TJAdd(row,TJId((ulong)OrderGetInteger(ORDER_POSITION_ID))); TJAdd(row,"");
   TJAdd(row,EnumToString((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE)));
   TJAdd(row,EnumToString((ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE))); TJAdd(row,"");
   TJAdd(row,TJNum(OrderGetDouble(ORDER_VOLUME_CURRENT))); TJAdd(row,TJNum(OrderGetDouble(ORDER_PRICE_OPEN)));
   TJAdd(row,TJNum(OrderGetDouble(ORDER_SL))); TJAdd(row,TJNum(OrderGetDouble(ORDER_TP)));
   TJAdd(row,TJId((ulong)OrderGetInteger(ORDER_MAGIC)));
   TJAdd(row,EnumToString((ENUM_ORDER_REASON)OrderGetInteger(ORDER_REASON)));
   TJAdd(row,OrderGetString(ORDER_COMMENT),true);
   return row;
}
bool TJSnapshotSave(TJState &states[],const ulong ticket,const string payload,const string kind)
{
   int revision=TJRevision(states,ticket,payload,false);
   if(revision==0) return true;
   string event=g_snapshot_baseline ? kind+"_BASELINE" : (revision==1 ? kind+"_FIRST_OBSERVED" : kind+"_CHANGED");
   string row=TJEventPrefix(TJNow(),TimeLocal(),"OBSERVED_SNAPSHOT",event)+","+payload;
   if(!TJAppend(g_events,row)) return false;
   if(!TJCommit(states,ticket,payload,false,revision)) { TJFail("Cannot allocate snapshot index."); return false; }
   return true;
}
void TJMissing(TJState &states[],const bool positions)
{
   for(int i=ArraySize(states)-1;i>=0 && !g_failed;i--)
   {
      bool exists=positions ? PositionSelectByTicket(states[i].ticket) : OrderSelect(states[i].ticket);
      if(exists) continue;
      // NOT a fabricated exit price/volume. Payload explicitly represents last observed state.
      string row=TJEventPrefix(TJNow(),TimeLocal(),"LAST_OBSERVED_SNAPSHOT",positions ? "POSITION_NO_LONGER_OPEN" : "ORDER_NO_LONGER_ACTIVE")+","+states[i].payload;
      if(!TJAppend(g_events,row)) return;
      for(int j=i;j<ArraySize(states)-1;j++) states[j]=states[j+1];
      ArrayResize(states,ArraySize(states)-1);
   }
}
void TJSnapshots()
{
   for(int i=0;i<PositionsTotal() && !g_failed;i++)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      ResetLastError(); string payload=TJPositionPayload(ticket);
      if(GetLastError()==0) TJSnapshotSave(g_positions,ticket,payload,"POSITION");
   }
   for(int i=0;i<OrdersTotal() && !g_failed;i++)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      ResetLastError(); string payload=TJOrderPayload(ticket);
      if(GetLastError()==0) TJSnapshotSave(g_orders,ticket,payload,"ORDER");
   }
   TJMissing(g_positions,true); TJMissing(g_orders,false);
   g_snapshot_baseline=false;
}
void TJStatus()
{
   if(!InpShowStatus) return;
   string status=g_failed ? "STOPPED: "+g_error : (!g_connected ? "DISCONNECTED - waiting" :
                 (g_last_scan==0 || g_backfill ? "RECORDING / history loading" : "RECORDING"));
   Comment("Trade Journal 1.20 | ",status,"\nAccount: ",g_login," / ",g_server,
           "\nAll symbols | Manual + Calculator + other EAs | No trading",
           "\nKnown deals: ",ArraySize(g_known)," | Rows this session: ",g_written," | History retries: ",ArraySize(g_retry),
           "\nData Folder > MQL5 > Files > ",g_folder,
           "\nKeep this terminal running to capture SL/TP changes.");
}

// A chart/input change can call OnInit again without resetting MQL global variables.
void TJResetRuntime()
{
   g_deals=g_events=g_sessions=g_lock=INVALID_HANDLE;
   g_login=0; g_server=""; g_currency=""; g_folder=""; g_session=""; g_error="";
   g_failed=false; g_started=false; g_connected=false; g_backfill=false; g_snapshot_baseline=true;
   g_sequence=0; g_written=0; g_last_heartbeat=0; g_scan_until=0; g_last_scan=0;
   g_scan_at=0; g_retry_at=0; g_queue_count=0;
   ArrayResize(g_known,0); ArrayResize(g_positions,0); ArrayResize(g_orders,0);
   ArrayResize(g_scan_tickets,0); ArrayResize(g_queue,0); ArrayResize(g_retry,0);
}
int OnInit()
{
   TJResetRuntime();
   if(InpHistoryDays<0 || InpHistoryDays>36500 || InpReconcileSeconds<5 || InpReconcileSeconds>3600) return INIT_PARAMETERS_INCORRECT;
   if(MQLInfoInteger(MQL_TESTER)) { Print("TradeJournal records live/demo terminals, not Strategy Tester simulations."); return INIT_FAILED; }
   g_login=AccountInfoInteger(ACCOUNT_LOGIN); g_server=AccountInfoString(ACCOUNT_SERVER); g_currency=AccountInfoString(ACCOUNT_CURRENCY);
   if(g_login<=0 || g_server=="") { Print("Sign into an account, then attach TradeJournal."); return INIT_FAILED; }
   g_folder="TradeJournal\\"+IntegerToString(g_login)+"_"+TJServerKey(g_server);
   g_session=IntegerToString((long)TimeLocal())+"_"+TJId(GetMicrosecondCount());
   // No sharing flags: one writer per account in this terminal. OS releases the handle after a crash.
   g_lock=FileOpen(g_folder+"\\writer.lock",FILE_READ|FILE_WRITE|FILE_BIN);
   if(g_lock==INVALID_HANDLE) { TJFail("Account journal is already open on another chart, or its folder is not writable."); return INIT_FAILED; }
   g_deals=TJOpen("deals.csv",DEAL_HEADER);
   g_events=TJOpen("events.csv",EVENT_HEADER);
   g_sessions=TJOpen("sessions.csv",SESSION_HEADER);
   if(g_failed || !TJLoadDeals() || !TJValidateTail(g_events,26) || !TJValidateTail(g_sessions,8)) return INIT_FAILED;
   if(!FileSeek(g_deals,0,SEEK_END) || !FileSeek(g_events,0,SEEK_END) || !FileSeek(g_sessions,0,SEEK_END))
   { TJFail("Cannot seek journal files."); return INIT_FAILED; }
   if(ArrayResize(g_queue,QUEUE_LIMIT)!=QUEUE_LIMIT) { TJFail("Cannot allocate transaction queue."); return INIT_FAILED; }
   if(!TJSession("START","Version 1.20; history_days="+IntegerToString(InpHistoryDays)+"; account_mode="+
      EnumToString((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE))+"; server times are broker time; no recording while terminal is stopped.")) return INIT_FAILED;
   g_started=true;
   if(!EventSetTimer(1)) { TJFail("Cannot start recording timer."); return INIT_FAILED; }
   Print("TradeJournal files: ",TerminalInfoString(TERMINAL_DATA_PATH),"\\MQL5\\Files\\",g_folder);
   TJStatus();
   return INIT_SUCCEEDED;
}

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(!g_started || g_failed) return;
   if(!TJAccount()) { TJFail("Account changed. Reattach Journal to select the correct account folder."); return; }
   // A request result is not an executed deal and its other transaction fields are undefined.
   if(trans.type==TRADE_TRANSACTION_REQUEST) return;
   if(g_queue_count>=QUEUE_LIMIT) { TJFail("Transaction queue overflow: coverage gap. Restart and reconcile history."); return; }
   g_queue[g_queue_count].tx=trans;
   g_queue[g_queue_count].server_time=TJNow();
   g_queue[g_queue_count].local_time=TimeLocal();
   g_queue_count++;
}
void OnTimer()
{
   if(g_failed) { TJStatus(); return; }
   if(!TJAccount()) { TJFail("Account changed. Reattach Journal."); TJStatus(); return; }
   TJDrain();
   bool connected=(bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   if(connected!=g_connected)
   {
      TJSession(connected ? "CONNECTED" : "DISCONNECTED",connected ? "History will reconcile; snapshot gaps cannot be reconstructed." : "Live event coverage may be incomplete until reconnect.");
      g_connected=connected;
      if(connected) { g_snapshot_baseline=true; g_last_scan=0; }
   }
   if(connected && !g_failed)
   {
      TJSnapshots();
      // Bounded retry work. Failed older tickets stay visible, including broker deletions.
      int attempts=(int)MathMin(200,ArraySize(g_retry));
      for(int i=0;i<attempts && ArraySize(g_retry)>0 && !g_failed;i++)
      {
         g_retry_at%=ArraySize(g_retry);
         if(TJRefreshDeal(g_retry[g_retry_at],"TRANSACTION_OR_RETRY"))
         {
            for(int j=g_retry_at;j<ArraySize(g_retry)-1;j++) g_retry[j]=g_retry[j+1];
            ArrayResize(g_retry,ArraySize(g_retry)-1);
         }
         else g_retry_at++; // Round-robin: unavailable tickets cannot starve older retries.
      }
      if(ArraySize(g_scan_tickets)>0) TJScanBatch();
      else if(g_last_scan==0 || TJNow()-g_last_scan>=InpReconcileSeconds)
      {
         if(TJBeginScan(g_last_scan==0)) TJScanBatch();
      }
   }
   ulong now=GetTickCount64();
   if(now-g_last_heartbeat>=60000 && !g_failed)
   {
      TJSession("HEARTBEAT","connected="+IntegerToString((int)connected)+"; pending_history="+IntegerToString(ArraySize(g_retry)));
      g_last_heartbeat=now;
   }
   TJStatus();
}
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_started && !g_failed && TJAccount())
   {
      TJDrain();
      TJSession("STOP","reason="+IntegerToString(reason)+"; events after this point are not observed until next START.");
   }
   if(g_deals!=INVALID_HANDLE) FileClose(g_deals);
   if(g_events!=INVALID_HANDLE) FileClose(g_events);
   if(g_sessions!=INVALID_HANDLE) FileClose(g_sessions);
   if(g_lock!=INVALID_HANDLE) FileClose(g_lock);
   if(InpShowStatus && g_started) Comment("");
   g_deals=g_events=g_sessions=g_lock=INVALID_HANDLE;
   g_started=false;
}
