#property copyright "MT5 Trading Tools"
#property version "1.10"
#property description "MACDZonePullback EA: confirmed M5 swing TP, M1 pattern SL, broker R:R >= 1."
#property strict
#include "TradePlanCore.mqh"
#include "ScalpBroker.mqh"

input group "Execution"
input bool InpExecuteTrades=false; // Signal-only until enabled; use Strategy Tester / demo first
input double InpRiskPercent=1.0; // Percent of current Equity per trade
input double InpMaxRiskPercent=2.0;
input double InpMinRR=1.0; // Cannot be below 1.0; evaluated after spread and optional commission
input double InpSLBufferPoints=0; // Always at least one tick outside the entire M1 pattern
input double InpCommissionPerLot=0; // Estimated round-trip commission in account currency per lot
input ulong InpMagicNumber=26091801;
input ulong InpDeviationPoints=20;
input double InpMaxSpreadPoints=50;
input int InpMaxQuoteAgeSeconds=5;
input int InpSignalMaxDelaySeconds=10; // First 1..30 seconds after M1 close only
input bool InpFreezeGuard=true;
input group "MACD Histogram color - M5 and M1"
input int InpFastEMA=12;
input int InpSlowEMA=26;
input int InpSignalEMA=9;
input int InpWarmupBars=0;
input group "M5 zones"
input ENUM_RP_ZONE_MODE InpZoneMode=RP_BOTH;
input int InpHistoryM5Bars=1500;
input int InpZoneLifeBars=144;
input group "Breakout quality"
input ENUM_RP_STRENGTH InpStrength=RP_FVG_OR_DISPLACEMENT;
input int InpATRLength=14;
input int InpMaxLegBars=30;
input double InpMinLegATR=1.0;
input double InpMinFVGATR=0.10;
input double InpMinEfficiency=0.65;
input double InpMinBreakBodyRatio=0.50;
input int InpConfirmationBars=30;
input group "Signal tuning - keep identical in EA and indicator"
input ENUM_RP_SIDE InpTradeSide=RP_ALL_SIDES;
input double InpM5BreakBufferPoints=0;
input double InpM1BreakBufferPoints=0;
input ENUM_RP_TOUCH InpTouchMode=RP_TOUCH_WICK;
input ENUM_RP_INVALIDATE InpInvalidationMode=RP_INVALIDATE_CLOSE;
input double InpMaxCloseTailRatio=0.25;
input group "Take-profit buffer"
input double InpTPBufferPoints=0; // Move TP toward entry, before the nearest M5 swing; R:R must still pass

RPConfig g_config;
MSBar g_one[],g_five[];
string g_scope="",g_prefix="";
long g_seen_bar=0,g_test_buy=0,g_test_sell=0;
bool g_test_halt=false,g_tester=false,g_busy=false;

void EAStatus(const string text)
{
   if(g_prefix!="") ObjectSetString(0,g_prefix+"status",OBJPROP_TEXT,"MACD Zone Trader | "+text);
}

void EAReport(const string status,const EACandidate &candidate,const string reason)
{
   string side=candidate.signal.direction==1 ? "BUY" : "SELL";
   EAStatus(status+" | "+reason);
   Print("MACDZoneTrader ",status," ",side," | M1 ",TimeToString((datetime)candidate.signal.time)," | ",reason);
}

bool EAFresh(const EACandidate &candidate)
{
   long current=(long)iTime(_Symbol,PERIOD_M1,0);
   long now=(long)TimeCurrent();
   return current==candidate.signal.time+60 && now>=current && now-current<=InpSignalMaxDelaySeconds;
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
   // Same account+symbol scope across all MACDZoneTrader magic numbers in this terminal.
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
   if(!GlobalVariableDel(g_scope+".pending")) Print("MACDZoneTrader: pending latch could not be cleared; inspect F3: ",g_scope);
   GlobalVariablesFlush();
}

void EATradeReport(const EACandidate &candidate,const ScalpPlan &plan,const ScalpQuote &quote,
                    const MqlTradeRequest &request,const MqlTradeResult &result,const bool filled)
{
   string state=filled ? "FILLED" : (EADefiniteRejection(result.retcode) ? "REJECTED" : "PAUSED - UNCONFIRMED/PARTIAL");
   double costs=quote.lot*InpCommissionPerLot;
   double rr=(quote.broker_reward-costs)/(quote.broker_loss+costs);
   PrintFormat("MACDZoneTrader %s | M1=%s side=%s lot=%.8f entry=%.*f pattern=%.*f..%.*f strategySL=%.*f strategyTP=%.*f spread=%.*f brokerSL=%.*f brokerTP=%.*f expectedRR=%.4f risk=%.2f budget=%.2f | retcode=%u order=%I64u deal=%I64u fill=%.8f volume=%.8f %s",
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
         PrintFormat("MACDZoneTrader fill estimates: RR=%.4f stop-risk=%.2f (before swap)",fill_rr,-loss+realized_cost);
         if(fill_rr+1e-12<InpMinRR || -loss+realized_cost>quote.budget+1e-7)
            Alert("MACDZoneTrader: fill slippage changed expected R:R/risk; inspect position. SL/TP retained.");
      }
   }
   else if(!EADefiniteRejection(result.retcode))
      Alert("MACDZoneTrader paused: inspect Trade/History. Recovery key: ",g_scope,".pending");
}

// Forward declarations are useful to both MetaEditor and the C++ test adapter.
bool EADefiniteRejection(const uint code);
#include "TradeExecution.mqh"

bool EALoad(const long current)
{
   MqlRates m5[],m1[];
   ArraySetAsSeries(m5,false); ArraySetAsSeries(m1,false);
   int n5=CopyRates(_Symbol,PERIOD_M5,0,InpHistoryM5Bars+1,m5);
   if(n5<2 || !SeriesInfoInteger(_Symbol,PERIOD_M5,SERIES_SYNCHRONIZED)) return false;
   int n1=CopyRates(_Symbol,PERIOD_M1,m5[0].time,(datetime)current,m1);
   if(n1<2 || !SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED) ||
      (long)m1[n1-1].time!=current || (long)m5[n5-1].time>current || current>=(long)m5[n5-1].time+300) return false;
   if(ArrayResize(g_one,n1)!=n1 || ArrayResize(g_five,n5)!=n5) return false;
   for(int i=0;i<n1;i++)
   { g_one[i].time=(long)m1[i].time; g_one[i].open=m1[i].open; g_one[i].high=m1[i].high; g_one[i].low=m1[i].low; g_one[i].close=m1[i].close; }
   for(int i=0;i<n5;i++)
   { g_five[i].time=(long)m5[i].time; g_five[i].open=m5[i].open; g_five[i].high=m5[i].high; g_five[i].low=m5[i].low; g_five[i].close=m5[i].close; }
   return true;
}

int OnInit()
{
   if(_Period!=PERIOD_M1 && _Period!=PERIOD_M5) return INIT_PARAMETERS_INCORRECT;
   g_config.macd.fast=InpFastEMA; g_config.macd.slow=InpSlowEMA; g_config.macd.signal=InpSignalEMA;
   g_config.macd.warmup=InpWarmupBars; g_config.macd.atr_length=InpATRLength;
   g_config.macd.threshold_mode=MS_PRICE; g_config.macd.threshold=0; g_config.macd.point=_Point;
   g_config.macd.swing_mode=MS_HISTOGRAM_COLOR;
   g_config.zones=InpZoneMode; g_config.strength=InpStrength; g_config.min_leg_atr=InpMinLegATR;
   g_config.min_fvg_atr=InpMinFVGATR; g_config.min_efficiency=InpMinEfficiency;
   g_config.min_body_ratio=InpMinBreakBodyRatio; g_config.max_leg_bars=InpMaxLegBars;
   g_config.zone_life_bars=InpZoneLifeBars; g_config.confirmation_bars=InpConfirmationBars;
   g_config.side=InpTradeSide; g_config.touch_mode=InpTouchMode; g_config.invalidate_mode=InpInvalidationMode;
   g_config.m5_break_buffer_points=InpM5BreakBufferPoints; g_config.m1_break_buffer_points=InpM1BreakBufferPoints;
   g_config.max_close_tail_ratio=InpMaxCloseTailRatio;
   if(!RPConfigValid(g_config) || InpHistoryM5Bars<100 || InpHistoryM5Bars>5000 ||
      !MathIsValidNumber(InpRiskPercent) || InpRiskPercent<=0 || InpRiskPercent>InpMaxRiskPercent ||
      !MathIsValidNumber(InpMaxRiskPercent) || InpMaxRiskPercent<=0 || InpMaxRiskPercent>100 ||
      !MathIsValidNumber(InpMinRR) || InpMinRR<1 ||
      !MathIsValidNumber(InpSLBufferPoints) || InpSLBufferPoints<0 ||
      !MathIsValidNumber(InpTPBufferPoints) || InpTPBufferPoints<0 ||
      !MathIsValidNumber(InpTPBufferPoints*_Point) ||
      !MathIsValidNumber(InpCommissionPerLot) || InpCommissionPerLot<0 ||
      !MathIsValidNumber(InpMaxSpreadPoints) || InpMaxSpreadPoints<=0 ||
      InpMaxQuoteAgeSeconds<1 || InpMaxQuoteAgeSeconds>60 ||
      InpSignalMaxDelaySeconds<1 || InpSignalMaxDelaySeconds>30 || InpMagicNumber==0)
   { Print("MACDZoneTrader: invalid Inputs; see README."); return INIT_PARAMETERS_INCORRECT; }
   g_tester=(bool)MQLInfoInteger(MQL_TESTER);
   g_test_buy=0; g_test_sell=0; g_test_halt=false; g_busy=false;
   g_seen_bar=(long)iTime(_Symbol,PERIOD_M1,0); // No historical entry on attachment/restart.
   string identity=AccountInfoString(ACCOUNT_SERVER)+"|"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"|"+_Symbol;
   ulong hash=14695981039346656037;
   for(int i=0;i<StringLen(identity);i++) { hash^=(ulong)StringGetCharacter(identity,i); hash*=1099511628211; }
   g_scope=StringFormat("MZT.%I64X",hash);
   g_prefix=g_scope+"_"+(string)ChartID()+"_";
   if(!ObjectCreate(0,g_prefix+"status",OBJ_LABEL,0,0,0)) return INIT_FAILED;
   ObjectSetInteger(0,g_prefix+"status",OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,g_prefix+"status",OBJPROP_XDISTANCE,12);
   ObjectSetInteger(0,g_prefix+"status",OBJPROP_YDISTANCE,18);
   ObjectSetInteger(0,g_prefix+"status",OBJPROP_COLOR,clrSilver);
   ObjectSetInteger(0,g_prefix+"status",OBJPROP_HIDDEN,true);
   EAStatus(EAHalted() ? "PAUSED: inspect pending request" : (InpExecuteTrades ? "Ready; waiting next M1 close" : "SIGNAL ONLY"));
   Print("MACDZoneTrader initialized | risk=",InpRiskPercent,"% Equity | broker RR>=",InpMinRR,
         " | scope=",g_scope," | execute=",InpExecuteTrades);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_prefix!="") ObjectsDeleteAll(0,g_prefix);
}

void OnTick()
{
   if(g_busy) return;
   long current=(long)iTime(_Symbol,PERIOD_M1,0);
   if(current<=0 || current==g_seen_bar) return;
   // First observation / reconnect gaps are synchronization events, not entries.
   if(g_seen_bar==0 || current!=g_seen_bar+60)
   { g_seen_bar=current; EAStatus("Synchronized; waiting next M1 close"); return; }
   if((long)TimeCurrent()-current>InpSignalMaxDelaySeconds)
   { g_seen_bar=current; EAStatus("SKIP: latest signal window expired"); return; }
   g_busy=true;
   if(!EALoad(current)) { EAStatus("Loading M5/M1 history"); g_busy=false; return; }
   g_seen_bar=current;
   EACandidate candidate;
   EATarget targets[];
   string reason="";
   if(EABuildContext(g_config,g_one,ArraySize(g_one),g_five,ArraySize(g_five),current,candidate,targets,reason))
      EAExecute(candidate,targets);
   else EAStatus(reason);
   g_busy=false;
}
