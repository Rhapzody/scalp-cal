#property copyright "MT5 Trading Tools"
#property version "1.00"
#property description "Trend Sweep Reclaim M5 EA: ATR stop, cost-aware R:R, prior-range room and risk sizing."
#property strict
#include "SweepInputs.mqh"
#include "TradePlanCore.mqh"
#include "ScalpBroker.mqh"
input group "Execution and risk"
input bool InpExecuteTrades=false;
input double InpRiskPercent=1.0;
input double InpMaxRiskPercent=2.0;
input double InpMinRR=1.8; // Net minimum; cannot be below 1 or above TargetRR
input double InpCommissionPerLot=0;
input ulong InpMagicNumber=26091902;
input ulong InpDeviationPoints=20;
input double InpMaxSpreadPoints=50;
input double InpMaxSpreadATR=0.10;
input double InpMaxEntryDriftATR=0.20;
input int InpMaxQuoteAgeSeconds=5;
input int InpSignalMaxDelaySeconds=10;
input bool InpFreezeGuard=true;
TSConfig g_config;
TSBar g_bars[];
string g_scope="",g_prefix="";
long g_seen_bar=0,g_test_buy=0,g_test_sell=0;
bool g_tester=false,g_test_halt=false,g_busy=false;
void EAStatus(const string text)
{
   if(g_prefix!="") ObjectSetString(0,g_prefix+"status",OBJPROP_TEXT,"Trend Sweep Trader | "+text);
}

void EAReport(const string status,const EACandidate &candidate,const string reason)
{
   string side=candidate.signal.direction==1 ? "BUY" : "SELL";
   EAStatus(status+" | "+reason);
   Print("TrendSweepTrader ",status," ",side," | M5 ",TimeToString((datetime)candidate.signal.time)," | ",reason);
}

bool EAFresh(const EACandidate &candidate)
{
   long current=(long)iTime(_Symbol,PERIOD_M5,0);
   long now=(long)TimeCurrent();
   return current==candidate.signal.time+300 && now>=current && now-current<=InpSignalMaxDelaySeconds;
}

bool EAHasExposure()
{
   // Also guard hedging accounts: no overlapping symbol exposure from this or another EA/manual trade.
   for(int i=PositionsTotal()-1;i>=0;i--)
      if(PositionGetTicket(i)>0 && PositionGetString(POSITION_SYMBOL)==_Symbol) return true;
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderGetTicket(i)>0 && OrderGetString(ORDER_SYMBOL)==_Symbol) return true;
   return false;
}

string EAMarker(const EACandidate &candidate)
{
   return g_scope+"."+(string)InpMagicNumber+(candidate.signal.direction==1 ? ".B" : ".S");
}

int EALock()
{
   if(g_tester) return 1;
   // Same account+symbol scope across all TrendSweepTrader magic numbers in this terminal.
   return FileOpen(g_scope+".lock",FILE_READ|FILE_WRITE|FILE_BIN);
}

void EAUnlock(const int handle) { if(!g_tester) FileClose(handle); }

bool EAHalted()
{
   if(g_tester) return g_test_halt;
   return GlobalVariableCheck(g_scope+".pending") && GlobalVariableGet(g_scope+".pending")>0;
}

bool EAAttempted(const EACandidate &candidate)
{
   if(g_tester) return (candidate.signal.direction==1 ? g_test_buy : g_test_sell)>=candidate.signal.time;
   string key=EAMarker(candidate);
   return GlobalVariableCheck(key) && GlobalVariableGet(key)>=(double)candidate.signal.time;
}

bool EAMarkAttempt(const EACandidate &candidate)
{
   if(g_tester)
   {
      if(candidate.signal.direction==1) g_test_buy=candidate.signal.time;
      else g_test_sell=candidate.signal.time;
      g_test_halt=true;
      return true;
   }
   if(GlobalVariableSet(g_scope+".pending",(double)candidate.signal.time)==0 ||
      GlobalVariableSet(EAMarker(candidate),(double)candidate.signal.time)==0) return false;
   GlobalVariablesFlush();
   return true;
}

void EAClearHalt()
{
   if(g_tester) { g_test_halt=false; return; }
   if(!GlobalVariableDel(g_scope+".pending")) Print("TrendSweepTrader: pending latch could not be cleared; inspect F3: ",g_scope);
   GlobalVariablesFlush();
}

void EATradeReport(const EACandidate &candidate,const ScalpPlan &plan,const ScalpQuote &quote,
                    const MqlTradeRequest &request,const MqlTradeResult &result,const bool filled)
{
   string state=filled ? "FILLED" : (EADefiniteRejection(result.retcode) ? "REJECTED" : "PAUSED - UNCONFIRMED/PARTIAL");
   double costs=quote.lot*InpCommissionPerLot;
   double rr=(quote.broker_reward-costs)/(quote.broker_loss+costs);
   PrintFormat("TrendSweepTrader %s | M5=%s side=%s lot=%.8f entry=%.*f pattern=%.*f..%.*f strategySL=%.*f strategyTP=%.*f spread=%.*f brokerSL=%.*f brokerTP=%.*f expectedRR=%.4f risk=%.2f budget=%.2f | retcode=%u order=%I64u deal=%I64u fill=%.8f volume=%.8f %s",
               state,TimeToString((datetime)candidate.signal.time),plan.buy ? "BUY" : "SELL",request.volume,
               _Digits,quote.entry,_Digits,candidate.pattern_low,_Digits,candidate.pattern_high,
               _Digits,plan.sl,_Digits,plan.tp,_Digits,quote.spread,_Digits,request.sl,_Digits,request.tp,
               rr,quote.broker_loss+costs,quote.budget,result.retcode,result.order,result.deal,result.price,result.volume,result.comment);
   EAStatus(state+" | "+result.comment);
   if(filled)
   {
      double loss=0,reward=0;
      if(OrderCalcProfit(request.type,_Symbol,result.volume,result.price,request.sl,loss) &&
         OrderCalcProfit(request.type,_Symbol,result.volume,result.price,request.tp,reward) && loss<0)
      {
         double realized_cost=result.volume*InpCommissionPerLot;
         double fill_rr=(reward-realized_cost)/(-loss+realized_cost);
         PrintFormat("TrendSweepTrader fill estimates: RR=%.4f stop-risk=%.2f (before swap)",fill_rr,-loss+realized_cost);
         if(fill_rr+1e-12<InpMinRR || -loss+realized_cost>quote.budget+1e-7)
            Alert("TrendSweepTrader: fill slippage changed expected R:R/risk; inspect position. SL/TP retained.");
      }
   }
   else if(!EADefiniteRejection(result.retcode))
      Alert("TrendSweepTrader paused: inspect Trade/History. Recovery key: ",g_scope,".pending");
}

// Forward declarations are useful to both MetaEditor and the C++ test adapter.
bool EADefiniteRejection(const uint code);
#include "TradeExecution.mqh"

bool EALoad(const long current)
{
   MqlRates rates[]; ArraySetAsSeries(rates,false);
   int n=CopyRates(_Symbol,PERIOD_M5,0,InpHistoryBars+1,rates);
   if(n<TSWarmup(g_config)+2 || !SeriesInfoInteger(_Symbol,PERIOD_M5,SERIES_SYNCHRONIZED) || (long)rates[n-1].time!=current) return false;
   if(ArrayResize(g_bars,n)!=n) return false;
   for(int i=0;i<n;i++)
   { g_bars[i].time=(long)rates[i].time; g_bars[i].open=rates[i].open; g_bars[i].high=rates[i].high; g_bars[i].low=rates[i].low; g_bars[i].close=rates[i].close; }
   return true;
}
int OnInit()
{
   TSConfigure(g_config);
   if(_Period!=PERIOD_M5 || !TSValid(g_config) || InpHistoryBars<TSWarmup(g_config)+g_config.room_bars+1 || InpHistoryBars>20000 ||
      !MathIsValidNumber(InpRiskPercent) || InpRiskPercent<=0 || InpRiskPercent>InpMaxRiskPercent ||
      !MathIsValidNumber(InpMaxRiskPercent) || InpMaxRiskPercent<=0 || InpMaxRiskPercent>100 ||
      !MathIsValidNumber(InpMinRR) || InpMinRR<1 || InpMinRR>InpTargetRR ||
      !MathIsValidNumber(InpCommissionPerLot) || InpCommissionPerLot<0 ||
      !MathIsValidNumber(InpMaxSpreadPoints) || InpMaxSpreadPoints<=0 ||
      !MathIsValidNumber(InpMaxSpreadATR) || InpMaxSpreadATR<=0 ||
      !MathIsValidNumber(InpMaxEntryDriftATR) || InpMaxEntryDriftATR<0 ||
      InpMaxQuoteAgeSeconds<1 || InpMaxQuoteAgeSeconds>60 || InpSignalMaxDelaySeconds<1 || InpSignalMaxDelaySeconds>30 || InpMagicNumber==0)
   { Print("TrendSweepTrader: use M5 and valid Inputs; see README."); return INIT_PARAMETERS_INCORRECT; }
   g_tester=(bool)MQLInfoInteger(MQL_TESTER);
   g_test_buy=g_test_sell=0; g_test_halt=false; g_busy=false;
   g_seen_bar=(long)iTime(_Symbol,PERIOD_M5,0);
   string identity=AccountInfoString(ACCOUNT_SERVER)+"|"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"|"+_Symbol;
   ulong hash=14695981039346656037;
   for(int i=0;i<StringLen(identity);i++) { hash^=(ulong)StringGetCharacter(identity,i); hash*=1099511628211; }
   g_scope=StringFormat("TST.%I64X",hash); g_prefix=g_scope+"_"+(string)ChartID()+"_";
   if(!ObjectCreate(0,g_prefix+"status",OBJ_LABEL,0,0,0)) return INIT_FAILED;
   ObjectSetInteger(0,g_prefix+"status",OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,g_prefix+"status",OBJPROP_XDISTANCE,12); ObjectSetInteger(0,g_prefix+"status",OBJPROP_YDISTANCE,40);
   ObjectSetInteger(0,g_prefix+"status",OBJPROP_COLOR,clrSilver);
   EAStatus(EAHalted() ? "PAUSED: inspect pending request" : (InpExecuteTrades ? "Waiting next M5 close" : "SIGNAL ONLY"));
   Print("TrendSweepTrader initialized | risk=",InpRiskPercent,"% Equity | target RR=",InpTargetRR," net minimum=",InpMinRR,
         " | execute=",InpExecuteTrades," | scope=",g_scope);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) { if(g_prefix!="") ObjectsDeleteAll(0,g_prefix); }
void OnTick()
{
   if(g_busy) return;
   long current=(long)iTime(_Symbol,PERIOD_M5,0);
   if(current<=0 || current==g_seen_bar) return;
   // First observation / reconnect gaps are synchronization events, not entries.
   if(g_seen_bar==0 || current!=g_seen_bar+300)
   { g_seen_bar=current; EAStatus("Synchronized; waiting next M5 close"); return; }
   if((long)TimeCurrent()-current>InpSignalMaxDelaySeconds)
   { g_seen_bar=current; EAStatus("SKIP: latest signal window expired"); return; }
   g_busy=true;
   if(!EALoad(current)) { EAStatus("Loading M5 history"); g_busy=false; return; }
   g_seen_bar=current;
   EACandidate candidate;
   EATarget targets[];
   string reason="";
   if(EABuildContext(g_config,g_bars,ArraySize(g_bars),current,candidate,targets,reason))
      EAExecute(candidate,targets);
   else EAStatus(reason);
   g_busy=false;
}
