#property copyright "MT5 Trading Tools"
#property version "1.00"
#property description "PA Reversal Trader: EMA20 pullback/reclaim, PA reversal, ATR stop filter and one-bar RR recovery."
#property strict

#include "PATradeCore.mqh"
#include "../ScalpCalculator/ScalpBroker.mqh"

input group "Execution and risk"
input bool InpExecuteTrades=false; // Signal-only until enabled
input double InpRiskPercent=1.0;
input double InpMaxRiskPercent=2.0;
input double InpMinRR=1.0; // Cannot be below 1:1
input double InpCommissionPerLot=0;
input ulong InpMagicNumber=26091904;
input ulong InpDeviationPoints=20;
input double InpMaxSpreadPoints=40; // Backtest profile: spread 30, accept up to 40
input double InpFallbackSpreadPoints=30; // Used only by external/replay adapters with no Ask feed
input int InpMaxQuoteAgeSeconds=5;
input int InpSignalMaxDelaySeconds=10;
input bool InpFreezeGuard=true;

input group "PA reversal"
input int InpMinBars=3; // Same minimum leg length as PAReversal indicator
input int InpHistoryBars=3000;
input ENUM_TIMEFRAMES InpSignalTimeframe=PERIOD_M5;

input group "EMA20 / ATR filter"
input int InpEMAPeriod=20;
input int InpATRLength=14;
input double InpMaxSLFromEMAATR=1.5; // Safety envelope for the pattern SL
input double InpMaxRetraceFromEMAATR=0.25; // Signal wick must reach this close to EMA20
input double InpMaxEMAPenetrationATR=0.50; // Maximum wick penetration before reclaim
const double FixedSLBufferPoints=15.0; // Deliberately fixed beyond the pattern wick

input group "One-bar RR recovery"
input int InpFollowupBars=1; // Intentionally one bar; later bars invalidate the signal
input double InpTPBufferPoints=0;

PATradeConfig g_config;
PASetup g_pending_setup;
bool g_pending=false,g_busy=false,g_tester=false;
long g_seen_bar=0,g_pending_bar=0,g_last_signal=0;
string g_scope="",g_prefix="";

void EAStatus(const string text)
{
   if(g_prefix!="") ObjectSetString(0,g_prefix+"status",OBJPROP_TEXT,"PA Reversal Trader | "+text);
}

bool EAHasExposure()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
      if(PositionGetTicket(i)>0 && PositionGetString(POSITION_SYMBOL)==_Symbol) return true;
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderGetTicket(i)>0 && OrderGetString(ORDER_SYMBOL)==_Symbol) return true;
   return false;
}

string SignalKey(const PASetup &setup)
{
   return g_scope+"."+(string)InpMagicNumber+"."+(string)setup.signal_time+"."+(setup.direction==1 ? "B" : "S");
}

bool AlreadyAttempted(const PASetup &setup)
{
   if(g_tester) return g_last_signal>=setup.signal_time;
   string key=SignalKey(setup);
   return GlobalVariableCheck(key) && GlobalVariableGet(key)>=(double)setup.signal_time;
}

bool MarkAttempt(const PASetup &setup)
{
   g_last_signal=setup.signal_time;
   if(g_tester) return true;
   string key=SignalKey(setup);
   if(GlobalVariableSet(key,(double)setup.signal_time)==0) return false;
   GlobalVariablesFlush(); return true;
}

bool EAFresh(const PASetup &setup)
{
   long current=(long)iTime(_Symbol,(ENUM_TIMEFRAMES)_Period,0);
   long now=(long)TimeCurrent();
   return current==setup.signal_time+PeriodSeconds((ENUM_TIMEFRAMES)_Period) &&
          now>=current && now-current<=InpSignalMaxDelaySeconds;
}

bool LoadBars(PABar &bars[],long &current,long &closed_time)
{
   MqlRates rates[]; ArraySetAsSeries(rates,false);
   int n=CopyRates(_Symbol,InpSignalTimeframe,0,InpHistoryBars+1,rates);
   if(n<InpMinBars+3 || !SeriesInfoInteger(_Symbol,InpSignalTimeframe,SERIES_SYNCHRONIZED)) return false;
   current=(long)rates[n-1].time;
   closed_time=(long)rates[n-2].time;
   if(ArrayResize(bars,n)!=n) return false;
   for(int i=0;i<n;i++)
   {
      bars[i].open=rates[i].open; bars[i].high=rates[i].high;
      bars[i].low=rates[i].low; bars[i].close=rates[i].close;
   }
   return true;
}

bool BuildLatest(PASetup &setup,string &reason)
{
   PABar bars[]; long current=0,closed_time=0;
   if(!LoadBars(bars,current,closed_time)) { reason="Loading PA history"; return false; }
   int n=ArraySize(bars); int signal_index=n-2; // latest CLOSED candle
   g_config.point=_Point; g_config.tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(g_config.tick<=0) g_config.tick=_Point;
   bool ready=PABuildLatest(g_config,bars,n,signal_index,_Digits,setup,reason);
   if(ready) setup.signal_time=closed_time;
   return ready;
}

bool Prepare(const PASetup &setup,ScalpPlan &plan,ScalpQuote &quote,MqlTradeRequest &request,string &reason)
{
   ZeroMemory(plan); ZeroMemory(quote); ZeroMemory(request);
   plan.buy=setup.direction==1; plan.pending=false; plan.orders=1; plan.risk_percent=InpRiskPercent;
   plan.sl=setup.sl; plan.tp=PATargetPrice(plan.buy,setup.tp,InpTPBufferPoints,_Point,
                                            quote.spec.tick_size>0 ? quote.spec.tick_size : _Point,_Digits);
   if(plan.tp<=0) plan.tp=setup.tp;
   // Quote once using the structural swing. If it offers more than 1R, cap
   // the broker target at exactly one risk unit and recalculate the final lot.
   ScalpQuote swing_quote;
   if(!ScalpCalculate(plan,AccountInfoDouble(ACCOUNT_EQUITY),InpMaxRiskPercent,1,InpMaxSpreadPoints,
                      true,InpFreezeGuard,InpMaxQuoteAgeSeconds,swing_quote,0)) { reason=swing_quote.reason; return false; }
   double capped_broker_tp=PACapTPAtOneR(plan.buy,swing_quote.entry,swing_quote.broker_sl,swing_quote.broker_tp);
   if(capped_broker_tp<=0) { reason="Cannot derive one-to-one TP"; return false; }
   if((plan.buy && capped_broker_tp<swing_quote.broker_tp- swing_quote.spec.tick_size*0.5) ||
      (!plan.buy && capped_broker_tp>swing_quote.broker_tp+ swing_quote.spec.tick_size*0.5))
   {
      double capped_strategy_tp=plan.buy ? capped_broker_tp : capped_broker_tp-swing_quote.spread;
      plan.tp=ScalpSnap(capped_strategy_tp,swing_quote.spec.tick_size,swing_quote.spec.digits);
   }
   if(!ScalpCalculate(plan,AccountInfoDouble(ACCOUNT_EQUITY),InpMaxRiskPercent,1,InpMaxSpreadPoints,
                      true,InpFreezeGuard,InpMaxQuoteAgeSeconds,quote,0)) { reason=quote.reason; return false; }
   if(!PARRValid(plan.buy,quote.entry,quote.broker_sl,quote.broker_tp,InpMinRR))
   { reason="R:R below minimum after spread compensation"; return false; }
   if(!MathIsValidNumber(InpCommissionPerLot) || InpCommissionPerLot<0) { reason="Invalid commission"; return false; }
   double loss_per_lot=quote.broker_loss/quote.lot+InpCommissionPerLot;
   double reward_per_lot=quote.broker_reward/quote.lot-InpCommissionPerLot;
   if(loss_per_lot<=0 || reward_per_lot<=0 || reward_per_lot/loss_per_lot+1e-12<InpMinRR)
   { reason="R:R below minimum after commission"; return false; }
   double lot=ScalpFloorVolume(MathMin(quote.lot,quote.budget/loss_per_lot),quote.spec.step);
   if(lot+1e-12<MathMax(0.01,quote.spec.min_lot)) { reason="Risk budget below broker minimum lot"; return false; }
   double ratio=lot/quote.lot; quote.lot=lot; quote.strategy_loss*=ratio; quote.broker_loss*=ratio;
   quote.broker_reward*=ratio; quote.margin*=ratio;
   if(quote.broker_loss+lot*InpCommissionPerLot>quote.budget+1e-7) { reason="Broker risk exceeds budget"; return false; }
   if(!ScalpRequest(plan,quote,InpMagicNumber,InpDeviationPoints,request,reason)) return false;
   request.comment="PAReversalTrader 1.00"; return true;
}

bool ExecuteSetup(const PASetup &setup,const string trigger)
{
   string reason="";
   if(!InpExecuteTrades) { EAStatus("SIGNAL ONLY | "+trigger); Print("PAReversalTrader SIGNAL ONLY ",trigger); return true; }
   if(!ScalpPermissions(reason)) { EAStatus("SKIP | "+reason); return false; }
   if(EAHasExposure()) { EAStatus("SKIP | Symbol exposure already open"); return false; }
   if(AlreadyAttempted(setup)) { EAStatus("SKIP | Signal already attempted"); return false; }
   ScalpPlan plan; ScalpQuote quote; MqlTradeRequest request;
   if(!Prepare(setup,plan,quote,request,reason)) { EAStatus("SKIP | "+reason); return false; }
   MqlTradeCheckResult check; MqlTradeResult result; ZeroMemory(check); ZeroMemory(result);
   if(!OrderCheck(request,check) || (check.retcode!=0 && check.retcode!=TRADE_RETCODE_DONE))
   { EAStatus("SKIP | OrderCheck: "+check.comment); return false; }
   if(!MarkAttempt(setup)) { EAStatus("SKIP | Cannot persist signal marker"); return false; }
   bool sent=OrderSend(request,result);
   bool filled=sent && result.retcode==TRADE_RETCODE_DONE && result.deal>0 && result.volume>0;
   string side=setup.direction==1 ? "BUY" : "SELL";
   string state=filled ? "FILLED" : (result.retcode==TRADE_RETCODE_REJECT ? "REJECTED" : "CHECK TRADE");
   PrintFormat("PAReversalTrader %s | %s | signal=%s trigger=%s entry=%.*f SL=%.*f TP=%.*f spread=%.*f RR=%.3f lot=%.4f risk=%.2f result=%u %s",
               state,side,TimeToString((datetime)setup.signal_time),trigger,_Digits,quote.entry,_Digits,request.sl,
               _Digits,request.tp,_Digits,quote.spread,ScalpRR(quote.entry,quote.broker_sl,quote.broker_tp),quote.lot,
               quote.broker_loss,result.retcode,result.comment);
   EAStatus(state+" | "+side+" | "+trigger); return filled;
}

bool PendingTick()
{
   if(!g_pending) return false;
   long current=(long)iTime(_Symbol,InpSignalTimeframe,0);
   if(current!=g_pending_bar)
   {
      if(current>g_pending_bar) { g_pending=false; EAStatus("EXPIRED | follow-up RR not reached in one bar"); }
      return false;
   }
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return false;
   bool buy=g_pending_setup.direction==1;
   // TP crossed before the better RR entry invalidates the setup. If both are
   // touched in one tick, the TP check wins and the signal is cancelled.
   if((buy && tick.bid>=g_pending_setup.tp) || (!buy && tick.ask<=g_pending_setup.tp))
   { g_pending=false; EAStatus("EXPIRED | price passed TP before RR recovery"); return false; }
   double threshold=g_pending_setup.rr_threshold;
   if((buy && tick.ask<=threshold) || (!buy && tick.bid>=threshold))
   {
      PASetup ready=g_pending_setup; g_pending=false;
      return ExecuteSetup(ready,"one-bar RR recovery");
   }
   return false;
}

void ProcessNewBar(const long current)
{
   if(g_pending && current>g_pending_bar) { g_pending=false; EAStatus("EXPIRED | follow-up bar closed"); }
   PASetup setup; string reason="";
   if(!BuildLatest(setup,reason)) { EAStatus(reason); return; }
   if(setup.signal_time==g_last_signal || AlreadyAttempted(setup)) return;
   // Signal is known at the opening of the next bar; calculate market RR now.
   if(ExecuteSetup(setup,"initial PA reversal")) return;
   if(!setup.followup_allowed || InpFollowupBars!=1) { EAStatus("EXPIRED | initial RR invalid"); return; }
   g_pending_setup=setup; g_pending=true; g_pending_bar=current;
   EAStatus("WAITING | one-bar RR recovery");
}

int OnInit()
{
   g_config.min_bars=InpMinBars; g_config.ema_period=InpEMAPeriod; g_config.atr_length=InpATRLength;
   g_config.max_sl_ema_atr=InpMaxSLFromEMAATR; g_config.max_retrace_ema_atr=InpMaxRetraceFromEMAATR;
   g_config.max_ema_penetration_atr=InpMaxEMAPenetrationATR; g_config.sl_buffer_points=FixedSLBufferPoints;
   g_config.min_rr=InpMinRR; g_config.point=_Point; g_config.tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(g_config.tick<=0) g_config.tick=_Point;
   if(InpSignalTimeframe!=PERIOD_M1 && InpSignalTimeframe!=PERIOD_M5) return INIT_PARAMETERS_INCORRECT;
   if(_Period!=InpSignalTimeframe || !PATradeConfigValid(g_config) || InpHistoryBars<100 || InpHistoryBars>10000 ||
      InpFollowupBars!=1 || InpRiskPercent<=0 || InpMaxRiskPercent<=0 || InpRiskPercent>InpMaxRiskPercent ||
      InpMaxSpreadPoints<=0 || InpFallbackSpreadPoints<=0 || InpMaxQuoteAgeSeconds<1 || InpSignalMaxDelaySeconds<1 ||
      InpSignalMaxDelaySeconds>30 || InpMagicNumber==0) return INIT_PARAMETERS_INCORRECT;
   g_tester=(bool)MQLInfoInteger(MQL_TESTER); g_seen_bar=(long)iTime(_Symbol,InpSignalTimeframe,0);
   string identity=AccountInfoString(ACCOUNT_SERVER)+"|"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"|"+_Symbol+"|PA";
   ulong hash=14695981039346656037; for(int i=0;i<StringLen(identity);i++) { hash^=(ulong)StringGetCharacter(identity,i); hash*=1099511628211; }
   g_scope=StringFormat("PAT.%I64X",hash); g_prefix=g_scope+"_"+(string)ChartID()+"_";
   if(!ObjectCreate(0,g_prefix+"status",OBJ_LABEL,0,0,0)) return INIT_FAILED;
   ObjectSetInteger(0,g_prefix+"status",OBJPROP_CORNER,CORNER_LEFT_UPPER); ObjectSetInteger(0,g_prefix+"status",OBJPROP_XDISTANCE,12);
   ObjectSetInteger(0,g_prefix+"status",OBJPROP_YDISTANCE,18); ObjectSetInteger(0,g_prefix+"status",OBJPROP_COLOR,clrSilver);
   EAStatus(InpExecuteTrades ? "Ready; waiting next bar" : "SIGNAL ONLY"); return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { if(g_prefix!="") ObjectsDeleteAll(0,g_prefix); }

void OnTick()
{
   if(g_busy) return; g_busy=true;
   PendingTick();
   long current=(long)iTime(_Symbol,InpSignalTimeframe,0);
   if(current>0 && current!=g_seen_bar)
   {
      if(g_seen_bar==0 || current!=g_seen_bar+PeriodSeconds(InpSignalTimeframe)) g_seen_bar=current;
      else if((long)TimeCurrent()-current<=InpSignalMaxDelaySeconds) { g_seen_bar=current; ProcessNewBar(current); }
      else { g_seen_bar=current; EAStatus("SKIP | signal window expired"); }
   }
   g_busy=false;
}
