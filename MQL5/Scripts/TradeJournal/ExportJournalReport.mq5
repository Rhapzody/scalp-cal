#property copyright "MT5 Trading Tools"
#property version "1.20"
#property strict
#property script_show_inputs
#property description "Build an offline HTML report from TradeJournal CSV and broker candles. Never trades."
#include "..\\..\\Experts\\TradeJournal\\JournalCore.mqh"
#include "JournalReportTemplate.mqh"

input string InpReportTimeframes="M1,M5,M15";
input int InpBarsBefore=100;
input int InpBarsAfter=30;
input int InpMaxBarsPerChart=10000;
input int InpMaxPositions=0; // 0 = all positions in the journal

struct JRPosition
{
   ulong id;
   string symbol;
   datetime first,last;
   bool open;
};
JRPosition jr_positions[];
TJState jr_deals[];
ENUM_TIMEFRAMES jr_tfs[];
string jr_tf_names[];
string jr_folder="",jr_error="";
long jr_login=0;
string jr_server="";

string JRJson(string value)
{
   StringReplace(value,"\\","\\\\"); StringReplace(value,"\"","\\\"");
   StringReplace(value,"\r","\\r"); StringReplace(value,"\n","\\n"); StringReplace(value,"\t","\\t");
   // Prevent data closing the HTML script element, including malicious broker comments.
   StringReplace(value,"<","\\u003c"); StringReplace(value,">","\\u003e"); StringReplace(value,"&","\\u0026");
   for(int i=1;i<32;i++)
   {
      string ch=ShortToString((ushort)i);
      if(i!=9 && i!=10 && i!=13) StringReplace(value,ch,StringFormat("\\u%04X",i));
   }
   return "\""+value+"\"";
}

bool JRTimeframes()
{
   ArrayResize(jr_tfs,0); ArrayResize(jr_tf_names,0);
   string parts[]; int n=StringSplit(InpReportTimeframes,',',parts);
   for(int i=0;i<n;i++)
   {
      string name=parts[i]; StringTrimLeft(name); StringTrimRight(name); StringToUpper(name);
      ENUM_TIMEFRAMES tf=PERIOD_CURRENT;
      if(name=="M1") tf=PERIOD_M1; else if(name=="M2") tf=PERIOD_M2; else if(name=="M3") tf=PERIOD_M3;
      else if(name=="M4") tf=PERIOD_M4; else if(name=="M5") tf=PERIOD_M5; else if(name=="M6") tf=PERIOD_M6;
      else if(name=="M10") tf=PERIOD_M10; else if(name=="M12") tf=PERIOD_M12; else if(name=="M15") tf=PERIOD_M15;
      else if(name=="M20") tf=PERIOD_M20; else if(name=="M30") tf=PERIOD_M30;
      else if(name=="H1") tf=PERIOD_H1; else if(name=="H2") tf=PERIOD_H2; else if(name=="H3") tf=PERIOD_H3;
      else if(name=="H4") tf=PERIOD_H4; else if(name=="H6") tf=PERIOD_H6; else if(name=="H8") tf=PERIOD_H8;
      else if(name=="H12") tf=PERIOD_H12; else if(name=="D1") tf=PERIOD_D1; else if(name=="W1") tf=PERIOD_W1;
      else if(name=="MN1") tf=PERIOD_MN1;
      if(tf==PERIOD_CURRENT) { jr_error="Unsupported timeframe: "+name; return false; }
      bool duplicate=false;
      for(int j=0;j<ArraySize(jr_tfs);j++) if(jr_tfs[j]==tf) duplicate=true;
      if(duplicate) continue;
      int at=ArraySize(jr_tfs); ArrayResize(jr_tfs,at+1); ArrayResize(jr_tf_names,at+1);
      jr_tfs[at]=tf; jr_tf_names[at]=name;
   }
   if(ArraySize(jr_tfs)==0 || ArraySize(jr_tfs)>8) { jr_error="Choose 1 to 8 timeframes."; return false; }
   return true;
}

// Read only bytes present when each file was opened; concurrent Journal appends stay untouched.
bool JRRead(const string name,const int columns,string &csv,const bool required)
{
   csv="";
   string path=jr_folder+"\\"+name;
   int file=FileOpen(path,FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE,0,CP_UTF8);
   if(file==INVALID_HANDLE)
   {
      if(required) jr_error="Cannot read "+name+". Attach TradeJournal on this account first.";
      return !required;
   }
   ulong end=FileSize(file);
   int tail=FileOpen(path,FILE_READ|FILE_BIN|FILE_SHARE_READ|FILE_SHARE_WRITE);
   bool terminated=false;
   if(tail!=INVALID_HANDLE)
   {
      if(end>=2 && FileSeek(tail,(long)end-2,SEEK_SET))
      { int cr=FileReadInteger(tail,CHAR_VALUE); int lf=FileReadInteger(tail,CHAR_VALUE); terminated=cr==13 && lf==10; }
      FileClose(tail);
   }
   if(!terminated) { FileClose(file); jr_error="CSV is incomplete or being written: "+name+". Try export again."; return false; }
   if(FileTell(file)<end)
   {
      string header=FileReadString(file); string names[];
      if(StringSplit(header,',',names)!=columns || names[0]!="schema_version" ||
         (name=="deals.csv" && (names[3]!="action" || names[4]!="revision" || names[9]!="deal_ticket" || names[11]!="position_id")) ||
         (name=="events.csv" && (names[6]!="event" || names[13]!="position_ticket" || names[14]!="position_id")) ||
         (name=="sessions.csv" && names[6]!="event"))
      { FileClose(file); jr_error="Unsupported CSV header: "+name; return false; }
      csv=header+"\n";
   }
   string fields[];
   while(FileTell(file)<end && !IsStopped())
   {
      string line=FileReadString(file);
      if(FileTell(file)>end || !TJParse(line,fields) || ArraySize(fields)!=columns || fields[0]!="1")
      { FileClose(file); jr_error="Invalid CSV snapshot: "+name; return false; }
      int account_column=name=="events.csv" ? 7 : (name=="sessions.csv" ? 4 : 6);
      if(fields[account_column]!=IntegerToString(jr_login) || TJCell(fields[account_column+1])!=TJCell(jr_server,true))
      { FileClose(file); jr_error="CSV contains a different account: "+name; return false; }
      csv+=line+"\n";
      if(name=="deals.csv")
      {
         ulong ticket=0,revision=0;
         if(!TJUnsigned(fields[9],ticket) || ticket==0 || !TJUnsigned(fields[4],revision) || revision==0 || revision>2147483647 ||
            (fields[3]!="UPSERT" && fields[3]!="DELETE") || fields[6]!=IntegerToString(jr_login) || TJCell(fields[7])!=TJCell(jr_server,true))
         { FileClose(file); jr_error="Invalid account/deal identity in deals.csv."; return false; }
         string payload=""; for(int j=6;j<30;j++) TJAdd(payload,fields[j]);
         if(TJRevision(jr_deals,ticket,payload,fields[3]=="DELETE")!=(int)revision ||
            !TJCommit(jr_deals,ticket,payload,fields[3]=="DELETE",(int)revision))
         { FileClose(file); jr_error="Invalid deal revision sequence."; return false; }
      }
   }
   FileClose(file);
   return !IsStopped();
}

int JRLower(const ulong id)
{
   int lo=0,hi=ArraySize(jr_positions);
   while(lo<hi) { int mid=lo+(hi-lo)/2; if(jr_positions[mid].id<id) lo=mid+1; else hi=mid; }
   return lo;
}
bool JRGroups()
{
   ArrayResize(jr_positions,0); string fields[];
   for(int i=0;i<ArraySize(jr_deals);i++)
   {
      if(jr_deals[i].deleted || !TJParse(jr_deals[i].payload,fields) || ArraySize(fields)!=24) continue;
      if(fields[8]!="DEAL_TYPE_BUY" && fields[8]!="DEAL_TYPE_SELL") continue;
      ulong id=0; if(!TJUnsigned(fields[5],id) || id==0) continue;
      datetime time=(datetime)(StringToInteger(fields[6])/1000);
      string symbol=fields[12];
      // Reverse only the formula guard; newline escaping is not a valid broker symbol here.
      if(StringLen(symbol)>1 && StringGetCharacter(symbol,0)=='\'')
      { int next=StringGetCharacter(symbol,1); if(next=='=' || next=='+' || next=='-' || next=='@' || next=='\t') symbol=StringSubstr(symbol,1); }
      int at=JRLower(id),n=ArraySize(jr_positions);
      if(at==n || jr_positions[at].id!=id)
      {
         if(ArrayResize(jr_positions,n+1)!=n+1) return false;
         for(int j=n;j>at;j--) jr_positions[j]=jr_positions[j-1];
         jr_positions[at].id=id; jr_positions[at].symbol=symbol;
         jr_positions[at].first=time; jr_positions[at].last=time; jr_positions[at].open=false;
      }
      else
      {
         if(jr_positions[at].symbol!=symbol) { jr_error="Position has inconsistent symbols."; return false; }
         jr_positions[at].first=(datetime)MathMin(jr_positions[at].first,time);
         jr_positions[at].last=(datetime)MathMax(jr_positions[at].last,time);
      }
   }
   // Account state is an observation at export start, not a guessed outcome from incomplete history.
   for(int i=0;i<PositionsTotal();i++)
   {
      if(PositionGetTicket(i)==0) continue;
      ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER); int at=JRLower(id);
      if(at<ArraySize(jr_positions) && jr_positions[at].id==id)
      { jr_positions[at].open=true; jr_positions[at].last=TimeTradeServer(); }
   }
   // Most recent first. Position identity remains a string in the browser (no double rounding).
   for(int i=1;i<ArraySize(jr_positions);i++)
   {
      JRPosition value=jr_positions[i]; int j=i-1;
      while(j>=0 && jr_positions[j].last<value.last) { jr_positions[j+1]=jr_positions[j]; j--; }
      jr_positions[j+1]=value;
   }
   return true;
}

string JRCandles(const JRPosition &p,const ENUM_TIMEFRAMES tf,const string name)
{
   string result="{\"positionId\":"+JRJson(TJId(p.id))+",\"timeframe\":"+JRJson(name)+",\"seconds\":"+IntegerToString(PeriodSeconds(tf));
   if(!SymbolSelect(p.symbol,true)) return result+",\"status\":\"symbol_unavailable\",\"bars\":[]}";
   int entry=-1,finish=-1,copied=-1,start=0,requested=0;
   MqlRates rates[]; ArraySetAsSeries(rates,false);
   string status="history_unavailable";
   for(int attempt=0;attempt<3 && !IsStopped();attempt++)
   {
      entry=iBarShift(p.symbol,tf,p.first,false); finish=iBarShift(p.symbol,tf,p.last,false);
      if(entry>=0 && finish>=0 && entry>=finish)
      {
         start=(int)MathMax(0,finish-InpBarsAfter);
         requested=entry+InpBarsBefore-start+1;
         if(requested>InpMaxBarsPerChart) { status="bar_limit_use_higher_tf"; break; }
         copied=CopyRates(p.symbol,tf,start,requested,rates);
         if(copied>0) { status=copied==requested ? "ready" : "partial_history"; break; }
      }
      // Separate script thread: history downloading does not occupy Journal's event handler.
      Sleep(100);
   }
   datetime current=iTime(p.symbol,tf,0);
   int after_available=finish>=0 ? (int)MathMin(InpBarsAfter,finish) : 0;
   result+=",\"status\":"+JRJson(status)+",\"afterAvailable\":"+IntegerToString(after_available)+
           ",\"collectedAt\":"+IntegerToString((long)TimeTradeServer())+",\"bars\":[";
   if(copied>0)
   {
      for(int i=0;i<copied;i++)
      {
         if(i>0) result+=",";
         result+="["+IntegerToString((long)rates[i].time)+","+TJNum(rates[i].open)+","+TJNum(rates[i].high)+","+
                 TJNum(rates[i].low)+","+TJNum(rates[i].close)+","+IntegerToString(rates[i].tick_volume)+","+
                 IntegerToString(rates[i].real_volume)+","+IntegerToString(rates[i].spread)+","+
                 (current>0 && rates[i].time<current ? "true" : "false")+"]";
      }
   }
   return result+"]}";
}

bool JRWrite(const string filename,const string text)
{
   int file=FileOpen(jr_folder+"\\"+filename,FILE_WRITE|FILE_BIN);
   if(file==INVALID_HANDLE) { jr_error="Cannot write "+filename; return false; }
   uchar bytes[]; int count=StringToCharArray(text,bytes,0,WHOLE_ARRAY,CP_UTF8)-1;
   ResetLastError(); uint written=FileWriteArray(file,bytes,0,count); FileFlush(file); int error=GetLastError(); FileClose(file);
   if(written!=(uint)count || error!=0) { jr_error="Incomplete report write. Previous report preserved."; return false; }
   return true;
}

void OnStart()
{
   jr_error=""; ArrayResize(jr_deals,0); ArrayResize(jr_positions,0);
   if(InpBarsBefore<0 || InpBarsAfter<0 || InpBarsBefore>5000 || InpBarsAfter>5000 ||
      InpMaxBarsPerChart<100 || InpMaxBarsPerChart>100000 || InpMaxPositions<0 || !JRTimeframes())
   { Alert("TradeJournal report: invalid Inputs. ",jr_error); return; }
   if(MQLInfoInteger(MQL_TESTER)) { Alert("Export from your live/demo terminal, not the Strategy Tester."); return; }
   jr_login=AccountInfoInteger(ACCOUNT_LOGIN); jr_server=AccountInfoString(ACCOUNT_SERVER);
   jr_folder="TradeJournal\\"+IntegerToString(jr_login)+"_"+TJServerKey(jr_server);
   int lock=FileOpen(jr_folder+"\\report.lock",FILE_READ|FILE_WRITE|FILE_BIN);
   if(lock==INVALID_HANDLE) { Alert("Another report export is running, or folder is not writable."); return; }
   string deals_csv="",events_csv="",sessions_csv="";
   bool ok=JRRead("deals.csv",30,deals_csv,true) && JRRead("events.csv",26,events_csv,false) && JRRead("sessions.csv",8,sessions_csv,false) && JRGroups();
   datetime exported=TimeTradeServer();
   string charts="[",states="[";
   int n=ArraySize(jr_positions),limit=InpMaxPositions==0 ? n : (int)MathMin(n,InpMaxPositions);
   for(int i=0;i<limit && ok && !IsStopped();i++)
   {
      if(AccountInfoInteger(ACCOUNT_LOGIN)!=jr_login || AccountInfoString(ACCOUNT_SERVER)!=jr_server) { jr_error="Account changed during export."; ok=false; break; }
      if(i>0) states+=",";
      states+="{\"id\":"+JRJson(TJId(jr_positions[i].id))+",\"open\":"+(jr_positions[i].open ? "true" : "false")+"}";
      for(int j=0;j<ArraySize(jr_tfs) && !IsStopped();j++)
      {
         if(i>0 || j>0) charts+=",";
         charts+=JRCandles(jr_positions[i],jr_tfs[j],jr_tf_names[j]);
      }
      Print("TradeJournal report: ",i+1," / ",limit," positions");
   }
   charts+="]"; states+="]";
   if(ok && !IsStopped())
   {
      string data="{\"version\":\"1.20\",\"generatedAt\":"+IntegerToString((long)exported)+",\"demo\":false,\"before\":"+
                  IntegerToString(InpBarsBefore)+",\"after\":"+IntegerToString(InpBarsAfter)+",\"positionsWithCharts\":"+IntegerToString(limit)+
                  ",\"dealsCsv\":"+JRJson(deals_csv)+",\"eventsCsv\":"+JRJson(events_csv)+",\"sessionsCsv\":"+JRJson(sessions_csv)+
                  ",\"positions\":"+states+",\"charts\":"+charts+"}";
      string html=JR_TEMPLATE;
      if(StringReplace(html,"__JOURNAL_DATA__",data)!=1) { jr_error="Report template is invalid."; ok=false; }
      else ok=JRWrite("journal.html.tmp",html);
      if(ok && AccountInfoInteger(ACCOUNT_LOGIN)==jr_login && AccountInfoString(ACCOUNT_SERVER)==jr_server)
      {
         // Only replace the public report after a complete export. No external assets or fetches.
         ok=FileMove(jr_folder+"\\journal.html.tmp",0,jr_folder+"\\journal.html",FILE_REWRITE);
         if(!ok) jr_error="Cannot replace journal.html. Close the file and try again; CSV is untouched.";
      }
      else if(ok) { ok=false; jr_error="Account changed before report publication."; }
   }
   FileClose(lock);
   if(IsStopped()) return;
   if(!ok) { Alert("TradeJournal report failed: ",jr_error); return; }
   Print("Report ready: ",TerminalInfoString(TERMINAL_DATA_PATH),"\\MQL5\\Files\\",jr_folder,"\\journal.html");
   Alert("Report ready: Data Folder > MQL5 > Files > ",jr_folder," > journal.html");
}
