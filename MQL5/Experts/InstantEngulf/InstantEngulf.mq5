#property copyright "Instant Engulf"
#property version "1.02"
#property strict
#property description "Manual Instant Buy/Sell: body breakout; current candle allowed in final 5 seconds."
#property description "SL at the two-candle extreme, strategy TP 1:1; SELL SL/TP + Execute spread."
#include "InstantBroker.mqh"
#include "EngulfCore.mqh"
#include "EngulfTiming.mqh"

enum ENUM_ENGULF_RISK_BASE { ENGULF_INITIAL_BALANCE=0,ENGULF_CURRENT_BALANCE=1 };
input group "Risk - entire single order"
input ENUM_ENGULF_RISK_BASE InpRiskBase=ENGULF_INITIAL_BALANCE;
input double InpInitialBalance=0; // Enter actual initial balance; never inferred
input double InpRiskPercent=1.0;
input double InpMaxRiskPercent=2.0;
input double InpSLBufferPoints=0; // Extra distance beyond the two-candle High/Low, in MT5 points
input group "Execution"
input ulong InpMagicNumber=26091202;
input double InpMaxSpreadPoints=30;
input ulong InpDeviationPoints=20;
input int InpMaxQuoteAgeSeconds=10;
input bool InpFreezeGuard=true;
input bool InpOneOrderPerSignal=true; // Persist duplicate protection across reattach/restart
input bool InpEnableAtStart=true;
input group "Panel"
input int InpPanelX=16;
input int InpPanelY=20;
input double InpPanelScale=1.0;

const string UI="INSTANT_ENGULF.";
bool g_busy=false,g_enabled=true;
ulong g_last_click=0;
string g_result="Waiting for a button click",g_result_detail="";
MqlRates g_latest,g_older;
bool g_bars_ready=false,g_buy=false,g_sell=false;
EngulfPairContext g_preview_pair;
double g_scale=1;

double BalanceBase() { return InpRiskBase==ENGULF_INITIAL_BALANCE ? InpInitialBalance : AccountInfoDouble(ACCOUNT_BALANCE); }
string Money(const double value) { return DoubleToString(value,2)+" "+AccountInfoString(ACCOUNT_CURRENCY); }
string Price(const double value) { return DoubleToString(value,_Digits); }
int Px(const int value) { return (int)MathRound(value*g_scale); }

EngulfBar AsBar(const MqlRates &rate) { return EngulfRateBar(rate); }

bool ReadPair(MqlRates &latest,MqlRates &older,EngulfPairContext &context,string &reason)
{
   return EngulfReadSelectedPair(latest,older,context,reason);
}

string SignalKey(const bool buy)
{
   string identity=AccountInfoString(ACCOUNT_SERVER)+"|"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"|"+
                   _Symbol+"|"+IntegerToString(_Period)+"|"+IntegerToString((long)InpMagicNumber);
   ulong hash=14695981039346656037;
   for(int i=0;i<StringLen(identity);i++) { hash^=(ulong)StringGetCharacter(identity,i); hash*=1099511628211; }
   return StringFormat("IE1.%I64X.%s",hash,buy ? "B" : "S");
}

bool AlreadyAttempted(const bool buy,const datetime candle_time)
{
   if(!InpOneOrderPerSignal) return false;
   string key=SignalKey(buy);
   return GlobalVariableCheck(key) && GlobalVariableGet(key)>=(double)candle_time;
}

void Text(const string suffix,const int x,const int y,const string value,const color ink=C'226,232,240',const int size=10)
{
   string name=UI+suffix;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,InpPanelX+Px(x));
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,InpPanelY+Px(y));
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,(int)MathMax(7,Px(size)));
   ObjectSetInteger(0,name,OBJPROP_COLOR,ink);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,11);
   ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
   ObjectSetString(0,name,OBJPROP_TEXT,value);
}

void Button(const string suffix,const int x,const int y,const int width,const string value,const color bg)
{
   string name=UI+suffix;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,InpPanelX+Px(x));
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,InpPanelY+Px(y));
   ObjectSetInteger(0,name,OBJPROP_XSIZE,Px(width)); ObjectSetInteger(0,name,OBJPROP_YSIZE,Px(38));
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg); ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_COLOR,C'17,24,39');
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,(int)MathMax(7,Px(11)));
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,20);
   ObjectSetString(0,name,OBJPROP_FONT,"Consolas"); ObjectSetString(0,name,OBJPROP_TEXT,value);
}

void Refresh()
{
   if(g_busy) return;
   string reason="";
   g_bars_ready=ReadPair(g_latest,g_older,g_preview_pair,reason);
   g_buy=false; g_sell=false;
   if(g_bars_ready)
   {
      EngulfBar latest=AsBar(g_latest),older=AsBar(g_older);
      g_buy=EngulfSignal(true,latest,older); g_sell=EngulfSignal(false,latest,older);
   }
   string bg=UI+"background";
   if(ObjectFind(0,bg)<0) ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,InpPanelX); ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,InpPanelY);
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,Px(436)); ObjectSetInteger(0,bg,OBJPROP_YSIZE,Px(410));
   ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,C'17,24,39'); ObjectSetInteger(0,bg,OBJPROP_COLOR,C'30,41,59');
   ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT); ObjectSetInteger(0,bg,OBJPROP_ZORDER,10);
   ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,bg,OBJPROP_HIDDEN,true);
   string tf=EnumToString((ENUM_TIMEFRAMES)_Period); StringReplace(tf,"PERIOD_","");
   Text("title",16,14,"INSTANT ENGULF / "+_Symbol,C'251,191,36',12);
   Text("tf",16,44,tf+" | "+(g_bars_ready ? EngulfPairLabel(g_preview_pair) : "Waiting for candles"),C'148,163,184');
   Button("buy",16,77,197,"INSTANT BUY",g_enabled ? C'52,211,153' : C'148,163,184');
   Button("sell",223,77,197,"INSTANT SELL",g_enabled ? C'251,113,133' : C'148,163,184');
   Text("pattern",16,130,g_bars_ready ? (g_buy ? "PA: BUY - close above previous body" : (g_sell ? "PA: SELL - close below previous body" : "PA: No engulf on selected candle")) : reason,C'251,191,36',9);
   Text("bar",16,154,"Signal bar: "+(g_bars_ready ? TimeToString(g_latest.time,TIME_DATE|TIME_MINUTES) : "--"),C'148,163,184',9);
   Text("risk",16,178,"Risk "+DoubleToString(InpRiskPercent,2)+"% | "+Money(BalanceBase()*InpRiskPercent/100),C'226,232,240',10);
   Text("base",16,201,(InpRiskBase==ENGULF_INITIAL_BALANCE ? "Initial: " : "Balance: ")+Money(BalanceBase()),C'148,163,184',9);
   string preview="SL/TP: waiting for valid PA",riskline="Strategy RR 1:1 | SELL spread ON";
   if(g_bars_ready && (g_buy || g_sell))
   {
      EngulfBar a=AsBar(g_latest),b=AsBar(g_older);
      ScalpPlan plan={}; ScalpQuote quote;
      plan.buy=g_buy; plan.pending=false; plan.orders=1; plan.risk_percent=InpRiskPercent;
      ScalpSpec spec;
      if(!ScalpReadSpec(spec)) { Text("preview",16,226,"Waiting for symbol specification"); return; }
      plan.sl=EngulfBufferedStop(g_buy,a,b,InpSLBufferPoints,spec.point,spec.tick_size,spec.digits);
      bool valid=ScalpCalculate(plan,BalanceBase(),InpMaxRiskPercent,1,InpMaxSpreadPoints,true,InpFreezeGuard,InpMaxQuoteAgeSeconds,quote,0,true);
      preview="SL "+Price(plan.sl)+" | TP "+Price(plan.tp);
      riskline=valid ? "Lot "+DoubleToString(quote.lot,4)+" | Broker loss "+Money(quote.broker_loss) : quote.reason;
      if(AlreadyAttempted(g_buy,g_latest.time)) riskline="This signal was already submitted - review Trade";
   }
   Text("preview",16,226,preview,C'226,232,240',9);
   Text("riskline",16,250,StringSubstr(riskline,0,55),C'251,191,36',9);
   ObjectSetString(0,UI+"riskline",OBJPROP_TOOLTIP,riskline);
   Text("costs",16,274,"Risk uses strategy SL; excludes fees / slippage",C'148,163,184',9);
   Button("enabled",16,303,119,g_enabled ? "EA ON" : "EA OFF",g_enabled ? C'52,211,153' : C'148,163,184');
   Text("single",151,314,"1 click = 1 market order",C'148,163,184',9);
   Text("result",16,358,StringSubstr(g_result,0,54),C'226,232,240',9);
   Text("detail",16,382,StringSubstr(g_result_detail,0,54),C'148,163,184',9);
   ObjectSetString(0,UI+"result",OBJPROP_TOOLTIP,g_result+"\n"+g_result_detail);
   ObjectSetString(0,UI+"detail",OBJPROP_TOOLTIP,g_result_detail);
   ChartRedraw();
}

void Fail(const string reason)
{
   g_result="NOT SENT"; g_result_detail=reason;
   Print("Instant Engulf: ",reason); Alert("Instant Engulf: ",reason);
}

// Called only by a user button click. OnTick and OnTimer never submit orders.
void Execute(const bool buy)
{
   if(g_busy) return;
   ulong now_ms=GetTickCount64();
   if(g_last_click>0 && now_ms-g_last_click<1200) return;
   g_last_click=now_ms;
   g_busy=true;
   int lock=INVALID_HANDLE;
   string reason="",key=SignalKey(buy);
   MqlRates latest,older; EngulfPairContext selected;
   ScalpPlan plan={}; ScalpQuote quote;
   MqlTradeRequest request={}; MqlTradeCheckResult check={}; MqlTradeResult result={};
   do
   {
      if(!g_enabled) { Fail("EA OFF"); break; }
      if(!ReadPair(latest,older,selected,reason)) { Fail(reason); break; }
      EngulfBar a=AsBar(latest),b=AsBar(older);
      if(!EngulfSignal(buy,a,b))
      {
         Fail(EngulfPairLabel(selected)+(buy ? ": BUY ต้องผ่านขอบบนเนื้อเทียนแท่งที่เทียบ" : ": SELL ต้องผ่านขอบล่างเนื้อเทียนแท่งที่เทียบ"));
         break;
      }
      if(!ScalpPermissions(reason)) { Fail(reason); break; }
      // Exclusive terminal-local file lock serializes multiple chart instances.
      lock=FileOpen(key+".lock",FILE_READ|FILE_WRITE|FILE_BIN);
      if(lock==INVALID_HANDLE) { Fail("Another instance is processing this signal; check Trade"); break; }
      if(AlreadyAttempted(buy,latest.time)) { Fail("This PA signal was already submitted; check Trade / History"); break; }
      if(ScalpNettingExposure()) { Fail("Netting: symbol already has position or pending exposure"); break; }
      plan.buy=buy; plan.pending=false; plan.orders=1; plan.risk_percent=InpRiskPercent;
      ScalpSpec spec;
      if(!ScalpReadSpec(spec)) { Fail("Symbol specification unavailable"); break; }
      plan.sl=EngulfBufferedStop(buy,a,b,InpSLBufferPoints,spec.point,spec.tick_size,spec.digits);
      if(!ScalpCalculate(plan,BalanceBase(),InpMaxRiskPercent,1,InpMaxSpreadPoints,true,
                         InpFreezeGuard,InpMaxQuoteAgeSeconds,quote,0,true)) { Fail(quote.reason); break; }
      if(!ScalpRequest(plan,quote,InpMagicNumber,InpDeviationPoints,request,reason)) { Fail(reason); break; }
      ResetLastError();
      if(!OrderCheck(request,check) || (check.retcode!=0 && check.retcode!=TRADE_RETCODE_DONE))
      { Fail(StringFormat("OrderCheck %u: %s (error %d)",check.retcode,check.comment,GetLastError())); break; }
      if(!EngulfPairStillValid(buy,selected,latest.time,plan.sl,InpSLBufferPoints,quote.spec,reason))
      { Fail(reason); break; }
      double previous_marker=GlobalVariableCheck(key) ? GlobalVariableGet(key) : 0;
      if(InpOneOrderPerSignal)
      {
         if(GlobalVariableSet(key,(double)latest.time)==0) { Fail("Could not persist duplicate protection"); break; }
         GlobalVariablesFlush(); // Also protects against a crash after the send.
      }
      // Disk persistence can take time; check the window once more before send.
      if(!EngulfSelectionCurrent(selected,reason))
      {
         if(InpOneOrderPerSignal) { GlobalVariableSet(key,previous_marker); GlobalVariablesFlush(); }
         Fail(reason); break;
      }
      bool sent=OrderSend(request,result);
      ENUM_ENGULF_RESULT outcome=EngulfResult(sent,result.retcode,result.price,result.volume,request.volume,quote.spec.step);
      if(outcome==ENGULF_REJECTED && InpOneOrderPerSignal)
         { GlobalVariableSet(key,0); GlobalVariablesFlush(); }
      string side=buy ? "BUY" : "SELL";
      g_result=outcome==ENGULF_FILLED ? side+" FILLED" :
               (outcome==ENGULF_PARTIAL ? side+" PARTIAL FILL - CHECK TRADE" :
               (outcome==ENGULF_UNCERTAIN ? side+" UNCONFIRMED - CHECK TRADE" : side+" REJECTED"));
      g_result+=" / "+EngulfPairLabel(selected);
      g_result_detail=StringFormat("code %u | order %I64u | deal %I64u | %s",result.retcode,result.order,result.deal,result.comment);
      PrintFormat("Instant Engulf %s | PA=%s TF=%s | requested lot=%.8f entry=%.*f strategy SL=%.*f TP=%.*f | spread=%.*f broker SL=%.*f TP=%.*f | strategy risk=%.2f broker risk=%.2f | fill price=%.*f volume=%.8f | %s",
                  g_result,TimeToString(latest.time),EnumToString((ENUM_TIMEFRAMES)_Period),request.volume,_Digits,quote.entry,
                  _Digits,plan.sl,_Digits,plan.tp,_Digits,quote.spread,_Digits,request.sl,_Digits,request.tp,
                  quote.strategy_loss,quote.broker_loss,_Digits,result.price,result.volume,g_result_detail);
      if(outcome!=ENGULF_FILLED) Alert("Instant Engulf: ",g_result,"\n",g_result_detail);
      // No retry, auto-close, or post-fill adjustment of the submitted SL/TP.
   } while(false);
   if(lock!=INVALID_HANDLE) FileClose(lock);
   g_busy=false;
   Refresh();
}

int OnInit()
{
   if(InpInitialBalance<0 || InpRiskPercent<=0 || InpMaxRiskPercent<=0 || InpRiskPercent>InpMaxRiskPercent ||
      InpSLBufferPoints<0 || !MathIsValidNumber(InpSLBufferPoints) ||
      InpMaxSpreadPoints<=0 || InpMaxQuoteAgeSeconds<1 || InpPanelX<0 || InpPanelY<0 || InpPanelScale<0.5 || InpPanelScale>2)
   { Print("Instant Engulf: invalid Inputs"); return INIT_PARAMETERS_INCORRECT; }
   g_enabled=InpEnableAtStart; g_scale=InpPanelScale;
   ObjectsDeleteAll(0,UI);
   if(!EventSetMillisecondTimer(500)) return INIT_FAILED;
   Refresh(); return INIT_SUCCEEDED;
}
void OnTick() { Refresh(); }
void OnTimer() { Refresh(); }
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id!=CHARTEVENT_OBJECT_CLICK || g_busy) return;
   if(StringFind(sparam,UI)!=0) return;
   ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
   if(sparam==UI+"buy") { Execute(true); return; }
   if(sparam==UI+"sell") { Execute(false); return; }
   if(sparam==UI+"enabled") { g_enabled=!g_enabled; Refresh(); }
}
void OnDeinit(const int reason)
{
   EventKillTimer(); ObjectsDeleteAll(0,UI); ChartRedraw();
   // Persistent per-signal markers intentionally survive removal/restart.
}
