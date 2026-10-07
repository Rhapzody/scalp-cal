#property copyright "MT5 Trading Tools"
#property version "1.00"
#property description "Opening Range breakout-retest EA with ATR stops, 2R target and cost-aware risk sizing."
#property strict
#include "OpeningInputs.mqh"
#include "TradePlanCore.mqh"
#include "ScalpBroker.mqh"

input group "Execution and risk"
input bool InpExecuteTrades=false;
input double InpRiskPercent=1.0;
input double InpMaxRiskPercent=2.0;
input double InpMinRR=1.8;
input double InpCommissionPerLot=0;
input ulong InpMagicNumber=26091903;
input ulong InpDeviationPoints=20;
input double InpMaxSpreadPoints=50;
input double InpMaxSpreadATR=0.20;
input double InpMaxEntryDriftATR=0.20;
input int InpMaxQuoteAgeSeconds=5;
input int InpSignalMaxDelaySeconds=10;
input bool InpFreezeGuard=true;

ORConfig g_config; ORBar g_bars[]; string g_scope="",g_prefix="";
long g_seen_bar=0,g_last_attempt=0; bool g_busy=false,g_tester=false,g_pending=false;

void EAStatus(const string text){if(g_prefix!="")ObjectSetString(0,g_prefix+"status",OBJPROP_TEXT,"Opening Range Trader | "+text);}
bool EAFresh(const ORCandidate &c){long current=(long)iTime(_Symbol,PERIOD_M5,0);long now=(long)TimeCurrent();return current==c.signal.time+300&&now>=current&&now-current<=InpSignalMaxDelaySeconds;}
bool EAExposure(){for(int i=PositionsTotal()-1;i>=0;i--)if(PositionGetTicket(i)>0&&PositionGetString(POSITION_SYMBOL)==_Symbol)return true;for(int i=OrdersTotal()-1;i>=0;i--)if(OrderGetTicket(i)>0&&OrderGetString(ORDER_SYMBOL)==_Symbol)return true;return false;}
string EAMarker(const ORCandidate &c){return g_scope+"."+(string)InpMagicNumber+"."+(c.signal.direction==1?"B":"S");}
bool EAAttempted(const ORCandidate &c){if(g_tester)return g_last_attempt>=c.signal.time;string key=EAMarker(c);return GlobalVariableCheck(key)&&GlobalVariableGet(key)>=(double)c.signal.time;}
bool EAMark(const ORCandidate &c){if(g_tester){g_last_attempt=c.signal.time;g_pending=true;return true;}if(GlobalVariableSet(g_scope+".pending",(double)c.signal.time)==0||GlobalVariableSet(EAMarker(c),(double)c.signal.time)==0)return false;GlobalVariablesFlush();return true;}
void EAClear(){if(g_tester){g_pending=false;return;}GlobalVariableDel(g_scope+".pending");GlobalVariablesFlush();}
bool EAHalted(){if(g_tester)return g_pending;return GlobalVariableCheck(g_scope+".pending")&&GlobalVariableGet(g_scope+".pending")>0;}
int EALock(){if(g_tester)return 1;return FileOpen(g_scope+".lock",FILE_READ|FILE_WRITE|FILE_BIN);}
void EAUnlock(const int h){if(!g_tester)FileClose(h);}

bool EAPrepare(const ORCandidate &c,ScalpPlan &plan,ScalpQuote &quote,MqlTradeRequest &request,string &reason)
{
   ZeroMemory(plan);ZeroMemory(quote);ZeroMemory(request);if(c.signal.direction!=1&&c.signal.direction!=-1){reason="Invalid direction";return false;}
   ScalpSpec spec;MqlTick tick;if(!ScalpReadSpec(spec)||!SymbolInfoTick(_Symbol,tick)){reason="Quote unavailable";return false;}
   bool buy=c.signal.direction==1;double entry=buy?tick.ask:tick.bid;double spread=tick.ask-tick.bid;
   if(spread<0||spread>InpMaxSpreadATR*c.signal.atr||MathAbs(entry-c.signal.price)>InpMaxEntryDriftATR*c.signal.atr){reason="Spread/entry drift exceeds ATR limit";return false;}
   plan.buy=buy;plan.pending=false;plan.orders=1;plan.risk_percent=InpRiskPercent;plan.sl=ORStop(c,spec.tick_size,spec.digits);
   double broker_sl=ScalpBrokerPrice(buy,true,plan.sl,spread,spec.tick_size,spec.digits);double risk=buy?entry-broker_sl:broker_sl-entry;
   if(risk<g_config.min_stop_atr*c.signal.atr||risk>g_config.max_stop_atr*c.signal.atr){reason="Stop distance outside ATR bounds";return false;}
   double broker_tp=entry+(buy?1:-1)*g_config.target_rr*risk;plan.tp=ScalpSnap(broker_tp-(!buy?spread:0),spec.tick_size,spec.digits);
   if(!ScalpCalculate(plan,AccountInfoDouble(ACCOUNT_EQUITY),InpMaxRiskPercent,1,InpMaxSpreadPoints,true,InpFreezeGuard,InpMaxQuoteAgeSeconds,quote)){reason=quote.reason;return false;}
   if(!ORMinimumRR(buy,quote.entry,quote.broker_sl,quote.broker_tp,InpMinRR)){reason="R:R below minimum after spread";return false;}
   if(!MathIsValidNumber(InpCommissionPerLot)||InpCommissionPerLot<0){reason="Invalid commission";return false;}
   double loss=quote.broker_loss/quote.lot+InpCommissionPerLot,reward=quote.broker_reward/quote.lot-InpCommissionPerLot;
   if(loss<=0||reward<=0||reward/loss+1e-12<InpMinRR){reason="R:R below minimum after commission";return false;}
   double lot=ScalpFloorVolume(MathMin(quote.lot,quote.budget/loss),spec.step);if(lot+1e-12<MathMax(0.01,spec.min_lot)){reason="Risk budget below minimum lot";return false;}
   double ratio=lot/quote.lot;quote.lot=lot;quote.strategy_loss*=ratio;quote.broker_loss*=ratio;quote.broker_reward*=ratio;quote.margin*=ratio;
   if(quote.broker_loss+lot*InpCommissionPerLot>quote.budget+1e-7){reason="Risk budget exceeded";return false;}
   if(!ScalpRequest(plan,quote,InpMagicNumber,InpDeviationPoints,request,reason))return false;request.comment="OpeningRangeTrader 1.00";reason="Ready";return true;
}
bool EADefinite(const uint code){return code==TRADE_RETCODE_REQUOTE||code==TRADE_RETCODE_REJECT||code==TRADE_RETCODE_CANCEL||code==TRADE_RETCODE_INVALID||code==TRADE_RETCODE_INVALID_VOLUME||code==TRADE_RETCODE_INVALID_PRICE||code==TRADE_RETCODE_INVALID_STOPS||code==TRADE_RETCODE_TRADE_DISABLED||code==TRADE_RETCODE_MARKET_CLOSED||code==TRADE_RETCODE_NO_MONEY||code==TRADE_RETCODE_PRICE_CHANGED||code==TRADE_RETCODE_PRICE_OFF||code==TRADE_RETCODE_INVALID_FILL;}
bool EALoad(const long current)
{
   MqlRates rates[];ArraySetAsSeries(rates,false);int n=CopyRates(_Symbol,PERIOD_M5,0,InpHistoryBars+1,rates);if(n<ORWarmup(g_config)+2||!SeriesInfoInteger(_Symbol,PERIOD_M5,SERIES_SYNCHRONIZED)||(long)rates[n-1].time!=current)return false;if(ArrayResize(g_bars,n)!=n)return false;
   for(int i=0;i<n;i++){g_bars[i].time=(long)rates[i].time;g_bars[i].open=rates[i].open;g_bars[i].high=rates[i].high;g_bars[i].low=rates[i].low;g_bars[i].close=rates[i].close;}return true;
}
void EAExecute(const ORCandidate &c)
{
   string reason="";if(!InpExecuteTrades){EAStatus("SIGNAL ONLY");return;}if(!EAFresh(c)){EAStatus("SKIP | signal expired");return;}if(!ScalpPermissions(reason)){EAStatus("SKIP | "+reason);return;}int lock=EALock();if(lock==INVALID_HANDLE){EAStatus("SKIP | another instance holds lock");return;}
   if(EAHalted()||EAAttempted(c)||EAExposure()){EAStatus(EAHalted()?"PAUSED | pending recovery":(EAAttempted(c)?"SKIP | already attempted":"SKIP | symbol exposure"));EAUnlock(lock);return;}
   ScalpPlan plan;ScalpQuote quote;MqlTradeRequest request;MqlTradeCheckResult checked;MqlTradeResult result;ZeroMemory(checked);ZeroMemory(result);
   if(!EAPrepare(c,plan,quote,request,reason)){EAStatus("SKIP | "+reason);EAUnlock(lock);return;}
   if(!OrderCheck(request,checked)|| (checked.retcode!=0&&checked.retcode!=TRADE_RETCODE_DONE)){EAStatus("SKIP | OrderCheck: "+checked.comment);EAUnlock(lock);return;}
   if(!EAMark(c)){EAStatus("SKIP | cannot persist intent");EAUnlock(lock);return;}
   MqlTick final_tick;if(!SymbolInfoTick(_Symbol,final_tick)||final_tick.bid!=quote.tick.bid||final_tick.ask!=quote.tick.ask){EAClear();EAStatus("SKIP | quote changed");EAUnlock(lock);return;}
   bool sent=OrderSend(request,result);bool filled=sent&&result.retcode==TRADE_RETCODE_DONE&&result.deal>0&&result.volume>0;
   if(filled||EADefinite(result.retcode))EAClear();
   PrintFormat("OpeningRangeTrader %s | side=%s lot=%.8f entry=%.*f SL=%.*f TP=%.*f RR=%.4f retcode=%u order=%I64u deal=%I64u %s",filled?"FILLED":(EADefinite(result.retcode)?"REJECTED":"PAUSED"),plan.buy?"BUY":"SELL",request.volume,_Digits,quote.entry,_Digits,request.sl,_Digits,request.tp,quote.broker_reward/quote.broker_loss,result.retcode,result.order,result.deal,result.comment);
   EAStatus(filled?"FILLED":(EADefinite(result.retcode)?"REJECTED":"PAUSED | inspect Trade/History"));EAUnlock(lock);
}
int OnInit()
{
   ORConfigure(g_config);if(_Period!=PERIOD_M5||!ORConfigValid(g_config)||InpHistoryBars<ORWarmup(g_config)+20||InpHistoryBars>20000||!MathIsValidNumber(InpRiskPercent)||InpRiskPercent<=0||InpRiskPercent>InpMaxRiskPercent||!MathIsValidNumber(InpMaxRiskPercent)||InpMaxRiskPercent<=0||InpMaxRiskPercent>100||!MathIsValidNumber(InpMinRR)||InpMinRR<1||InpMinRR>InpTargetRR||!MathIsValidNumber(InpCommissionPerLot)||InpCommissionPerLot<0||!MathIsValidNumber(InpMaxSpreadPoints)||InpMaxSpreadPoints<=0||!MathIsValidNumber(InpMaxSpreadATR)||InpMaxSpreadATR<=0||!MathIsValidNumber(InpMaxEntryDriftATR)||InpMaxEntryDriftATR<0||InpMaxQuoteAgeSeconds<1||InpMaxQuoteAgeSeconds>60||InpSignalMaxDelaySeconds<1||InpSignalMaxDelaySeconds>30||InpMagicNumber==0)return INIT_PARAMETERS_INCORRECT;
   g_tester=(bool)MQLInfoInteger(MQL_TESTER);g_seen_bar=(long)iTime(_Symbol,PERIOD_M5,0);string identity=AccountInfoString(ACCOUNT_SERVER)+"|"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"|"+_Symbol;ulong hash=14695981039346656037;for(int i=0;i<StringLen(identity);i++){hash^=(ulong)StringGetCharacter(identity,i);hash*=1099511628211;}g_scope=StringFormat("ORR.%I64X",hash);g_prefix=g_scope+"_"+(string)ChartID()+"_";if(!ObjectCreate(0,g_prefix+"status",OBJ_LABEL,0,0,0))return INIT_FAILED;ObjectSetInteger(0,g_prefix+"status",OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(0,g_prefix+"status",OBJPROP_XDISTANCE,12);ObjectSetInteger(0,g_prefix+"status",OBJPROP_YDISTANCE,60);ObjectSetInteger(0,g_prefix+"status",OBJPROP_COLOR,clrSilver);EAStatus(InpExecuteTrades?"Waiting next M5 close":"SIGNAL ONLY");return INIT_SUCCEEDED;
}
void OnDeinit(const int reason){if(g_prefix!="")ObjectsDeleteAll(0,g_prefix);}
void OnTick()
{
   long current=(long)iTime(_Symbol,PERIOD_M5,0);if(current<=0||current==g_seen_bar)return;if(g_seen_bar==0||current!=g_seen_bar+300){g_seen_bar=current;EAStatus("Synchronized; waiting next M5 close");return;}if((long)TimeCurrent()-current>InpSignalMaxDelaySeconds){g_seen_bar=current;EAStatus("SKIP | window expired");return;}if(g_busy)return;g_busy=true;if(!EALoad(current)){EAStatus("Loading M5 history");g_busy=false;return;}g_seen_bar=current;ORCandidate c;ORTarget t[];string reason="";if(ORBuildContext(g_config,g_bars,ArraySize(g_bars),current,c,t,reason))EAExecute(c);else EAStatus(reason);g_busy=false;
}
