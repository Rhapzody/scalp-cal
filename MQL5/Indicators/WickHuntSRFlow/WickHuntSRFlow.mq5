#property copyright "MT5 Trading Tools"
#property version "1.06"
#property description "Closed lower-TF historical hunt/reclaim replay, with optional original live tick mode."
#property indicator_chart_window
#property indicator_buffers 12
#property indicator_plots 12
#property strict
#include "WickHuntHistory.mqh"

input group "Timeframes - independent of the chart"
input ENUM_TIMEFRAMES InpSignalTF=PERIOD_M5;
input ENUM_TIMEFRAMES InpHuntTF=PERIOD_H1;
input int InpHuntBars=1; // Sweep ALL of these preceding higher-TF candles
input group "Lower-TF MACD Histogram swings"
input int InpFastEMA=12;
input int InpSlowEMA=26;
input int InpSignalEMA=9;
input int InpWarmupBars=0;
input int InpHistoryBars=0; // 0=all loaded lower-TF history, otherwise 100..100000 closed bars
input int InpSRCount=10; // Latest confirmed high AND low swings, total
input ENUM_MS_SR_ANCHOR InpSRAnchor=MS_SR_WICK;
input group "Display and notifications"
input bool InpShowSR=true;
input int InpVisibleSignals=100;
input color InpBuyColor=clrLimeGreen;
input color InpSellColor=clrTomato;
input color InpSupportColor=clrDeepSkyBlue;
input color InpResistanceColor=clrTomato;
input int InpArrowWidth=2;
input int InpArrowGapPoints=30;
input bool InpPopupAlert=false;

// Appended: original positional iCustom arguments and buffers 0..7 are retained.
input group "Higher-TF scenarios"
input ENUM_WS_SCENARIO InpScenario=WS_BOTH;
input int InpTouchBars=5; // Prior CLOSED higher-TF candles touching a known histogram SR
input int InpPullbackHuntBars=2; // One current candle sweeps ALL preceding same-side wicks
input int InpContextHistoryBars=0; // 0=all loaded higher-TF history, otherwise 100..100000
input int InpFVGSearchBars=0; // 0=all loaded context; inspect every intervening candle
input double InpMinFVGGapPoints=0;
input bool InpRequireFVGMiddleDirection=false;
input bool InpShowContextSR=true;
input group "Lower-TF entry confirmation"
input int InpRetestBars=8; // After the immediate next candle holds SR; 0=old direct-break entry
// Append new Inputs to preserve existing positional iCustom calls.
input int InpConfirmBars=1; // Consecutive CLOSED candles after the breakout; 1..1000
input double InpCloseBufferPoints=0; // Break/hold closes must exceed SR by MORE than this distance
input double InpRetestTolerancePoints=0; // Accept approach within this many points of frozen SR
input group "Higher-TF hunt and FVG thresholds"
input double InpMinHuntPoints=0; // Sweep prior wick extreme by MORE than this distance
input double InpFVGMaxLeadWickPercent=30; // Maximum leading wick / full range, 0..100
input group "Signal directions"
input bool InpEnableBuy=true;
input bool InpEnableSell=true;
input group "Indicator observation and history"
input ENUM_WH_OBSERVATION InpObservationMode=WH_LOWER_TF_CLOSE;
input ENUM_WH_CLOSED_RETEST InpClosedRetest=WH_RETEST_HIGH_LOW;

double BuyBuffer[],SellBuffer[],EventTimeBuffer[],DirectionBuffer[];
double SRPriceBuffer[],SRTypeBuffer[],BreakTimeBuffer[],HuntTimeBuffer[];
double PatternBuffer[],ContextSRBuffer[],FVGTimeBuffer[],TrendPivotBuffer[];
MSConfig g_config;
WSState g_state;
WSContext g_context;
WSSignal g_signals[];
WHCState g_higher;
MSBar g_higher_bars[];
long g_higher_open=0;
int g_higher_available=0;
int g_small_seconds=0,g_big_seconds=0,g_chart_total=0;
long g_lower_open=0;
long g_chart_first=0,g_chart_last=0;
bool g_force_replay=true,g_outputs_dirty=true,g_observed=false;
string g_prefix="";
int g_close_lower_available=-1,g_close_higher_available=-1;
long g_close_lower_open=0,g_close_higher_open=0,g_close_history_start=0;
long g_close_last_processed=0;
bool g_close_ready=false;
bool g_arrows_dirty=true;
double g_chart_high=0,g_chart_low=0;

void Status(const string text)
{
   if(g_prefix!="") ObjectSetString(0,g_prefix+"owner",OBJPROP_TEXT,"WickHuntSRFlow | "+text);
}

void ClearOutput()
{
   ArrayInitialize(BuyBuffer,EMPTY_VALUE); ArrayInitialize(SellBuffer,EMPTY_VALUE);
   ArrayInitialize(EventTimeBuffer,EMPTY_VALUE); ArrayInitialize(DirectionBuffer,EMPTY_VALUE);
   ArrayInitialize(SRPriceBuffer,EMPTY_VALUE); ArrayInitialize(SRTypeBuffer,EMPTY_VALUE);
   ArrayInitialize(BreakTimeBuffer,EMPTY_VALUE); ArrayInitialize(HuntTimeBuffer,EMPTY_VALUE);
   ArrayInitialize(PatternBuffer,EMPTY_VALUE); ArrayInitialize(ContextSRBuffer,EMPTY_VALUE);
   ArrayInitialize(FVGTimeBuffer,EMPTY_VALUE); ArrayInitialize(TrendPivotBuffer,EMPTY_VALUE);
}

int OnInit()
{
   g_small_seconds=PeriodSeconds(InpSignalTF); g_big_seconds=PeriodSeconds(InpHuntTF);
   g_config.fast=InpFastEMA; g_config.slow=InpSlowEMA; g_config.signal=InpSignalEMA;
   g_config.warmup=InpWarmupBars; g_config.atr_length=14; g_config.threshold_mode=MS_PRICE;
   g_config.threshold=0; g_config.point=_Point; g_config.swing_mode=MS_HISTOGRAM_COLOR;
   if(InpSignalTF==PERIOD_CURRENT || InpHuntTF==PERIOD_CURRENT ||
      PeriodSeconds((ENUM_TIMEFRAMES)_Period)<=0 || PeriodSeconds((ENUM_TIMEFRAMES)_Period)>86400 ||
      g_small_seconds<=0 || g_big_seconds<=g_small_seconds || g_big_seconds>86400 ||
      g_big_seconds%g_small_seconds!=0 || InpHuntBars<1 || InpHuntBars>1000 ||
      !MSConfigValid(g_config) || InpHistoryBars<0 || InpHistoryBars>100000 ||
      (InpHistoryBars>0 && (InpHistoryBars<100 || InpHistoryBars<MSWarmup(g_config)+1)) ||
      InpSRCount<1 || InpSRCount>WS_MAX_LEVELS ||
      InpSRAnchor<MS_SR_WICK || InpSRAnchor>MS_SR_BODY ||
      InpVisibleSignals<0 || InpVisibleSignals>5000 || InpArrowWidth<1 || InpArrowWidth>5 ||
      InpArrowGapPoints<0 || InpArrowGapPoints>100000 ||
      InpScenario<WS_LEGACY || InpScenario>WS_BOTH || InpTouchBars<1 || InpTouchBars>1000 ||
      InpPullbackHuntBars<2 || InpPullbackHuntBars>1000 ||
      InpContextHistoryBars<0 || InpContextHistoryBars>100000 ||
      (InpContextHistoryBars>0 && (InpContextHistoryBars<100 || InpContextHistoryBars<MSWarmup(g_config)+1 ||
       InpContextHistoryBars<InpTouchBars || InpContextHistoryBars<InpPullbackHuntBars || InpContextHistoryBars<InpHuntBars)) ||
      InpFVGSearchBars<0 || InpFVGSearchBars>100000 ||
      !MathIsValidNumber(InpMinFVGGapPoints) || InpMinFVGGapPoints<0 ||
      !MathIsValidNumber(InpMinFVGGapPoints*_Point) || InpRetestBars<0 || InpRetestBars>1000 ||
      InpConfirmBars<1 || InpConfirmBars>1000 ||
      !MathIsValidNumber(InpCloseBufferPoints) || InpCloseBufferPoints<0 ||
      !MathIsValidNumber(InpCloseBufferPoints*_Point) ||
      !MathIsValidNumber(InpRetestTolerancePoints) || InpRetestTolerancePoints<0 ||
      !MathIsValidNumber(InpRetestTolerancePoints*_Point) ||
      !MathIsValidNumber(InpMinHuntPoints) || InpMinHuntPoints<0 ||
      !MathIsValidNumber(InpMinHuntPoints*_Point) ||
      !MathIsValidNumber(InpFVGMaxLeadWickPercent) || InpFVGMaxLeadWickPercent<0 || InpFVGMaxLeadWickPercent>100 ||
      InpObservationMode<WH_TICK_LIVE || InpObservationMode>WH_LOWER_TF_CLOSE ||
      InpClosedRetest<WH_RETEST_HIGH_LOW || InpClosedRetest>WH_RETEST_CLOSE)
   { Print("WickHuntSRFlow: invalid Inputs. Use fixed lower/higher timeframes and a chart up to D1."); return INIT_PARAMETERS_INCORRECT; }
   SetIndexBuffer(0,BuyBuffer,INDICATOR_DATA); SetIndexBuffer(1,SellBuffer,INDICATOR_DATA);
   SetIndexBuffer(2,EventTimeBuffer,INDICATOR_DATA); SetIndexBuffer(3,DirectionBuffer,INDICATOR_DATA);
   SetIndexBuffer(4,SRPriceBuffer,INDICATOR_DATA); SetIndexBuffer(5,SRTypeBuffer,INDICATOR_DATA);
   SetIndexBuffer(6,BreakTimeBuffer,INDICATOR_DATA); SetIndexBuffer(7,HuntTimeBuffer,INDICATOR_DATA);
   SetIndexBuffer(8,PatternBuffer,INDICATOR_DATA); SetIndexBuffer(9,ContextSRBuffer,INDICATOR_DATA);
   SetIndexBuffer(10,FVGTimeBuffer,INDICATOR_DATA); SetIndexBuffer(11,TrendPivotBuffer,INDICATOR_DATA);
   ArraySetAsSeries(BuyBuffer,false); ArraySetAsSeries(SellBuffer,false);
   ArraySetAsSeries(EventTimeBuffer,false); ArraySetAsSeries(DirectionBuffer,false);
   ArraySetAsSeries(SRPriceBuffer,false); ArraySetAsSeries(SRTypeBuffer,false);
   ArraySetAsSeries(BreakTimeBuffer,false); ArraySetAsSeries(HuntTimeBuffer,false);
   ArraySetAsSeries(PatternBuffer,false); ArraySetAsSeries(ContextSRBuffer,false);
   ArraySetAsSeries(FVGTimeBuffer,false); ArraySetAsSeries(TrendPivotBuffer,false);
   string labels[12]={"Buy signal price","Sell signal price","Signal confirmation time","Direction +1/-1",
                     "Broken SR price","SR type H=1/L=-1","Lower-TF breakout bar open","Higher-TF bar open",
                     "Scenario 0 legacy/1 breakout/2 pullback/3 both","Higher-TF context SR",
                     "Strong FVG confirmation bar open","Trend swing pivot bar open"};
   for(int i=0;i<12;i++)
   {
      PlotIndexSetInteger(i,PLOT_DRAW_TYPE,DRAW_NONE);
      PlotIndexSetDouble(i,PLOT_EMPTY_VALUE,EMPTY_VALUE); PlotIndexSetString(i,PLOT_LABEL,labels[i]);
   }
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   IndicatorSetString(INDICATOR_SHORTNAME,"WickHuntSRFlow 1.06 "+EnumToString(InpHuntTF)+" / "+EnumToString(InpSignalTF)+
                     (InpObservationMode==WH_LOWER_TF_CLOSE ? " [Close/history]" : " [Live tick]"));
   string base="WHSR_"+(string)ChartID()+"_"+(string)GetMicrosecondCount()+"_";
   int suffix=0;
   do { g_prefix=base+IntegerToString(suffix++)+"_"; } while(ObjectFind(0,g_prefix+"owner")>=0);
   if(!ObjectCreate(0,g_prefix+"owner",OBJ_LABEL,0,0,0)) return INIT_FAILED;
   ObjectSetInteger(0,g_prefix+"owner",OBJPROP_CORNER,CORNER_LEFT_LOWER);
   ObjectSetInteger(0,g_prefix+"owner",OBJPROP_ANCHOR,ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0,g_prefix+"owner",OBJPROP_XDISTANCE,12);
   ObjectSetInteger(0,g_prefix+"owner",OBJPROP_YDISTANCE,16);
   ObjectSetInteger(0,g_prefix+"owner",OBJPROP_COLOR,clrSilver);
   ObjectSetInteger(0,g_prefix+"owner",OBJPROP_FONTSIZE,9);
   ObjectSetInteger(0,g_prefix+"owner",OBJPROP_HIDDEN,true);
   WSReset(g_state,0); g_context.valid=false; g_context.time=0;
   WHCReset(g_higher); ArrayResize(g_higher_bars,0);
   ArrayResize(g_signals,0);
   if(!EventSetTimer(1)) { ObjectsDeleteAll(0,g_prefix); g_prefix=""; return INIT_FAILED; }
   Status(InpObservationMode==WH_LOWER_TF_CLOSE ? "Loading closed-candle history" : "Loading history / live observation only");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_prefix!="") ObjectsDeleteAll(0,g_prefix);
   ChartRedraw(0);
}

bool ReplayHigher(const long now)
{
   int available=iBars(_Symbol,InpHuntTF);
   if(!g_force_replay && g_higher_open==g_context.time && g_higher_available==available) return true;
   int requested=InpContextHistoryBars==0 ? available : InpContextHistoryBars+1;
   MqlRates rates[]; ArraySetAsSeries(rates,false);
   int n=CopyRates(_Symbol,InpHuntTF,0,requested,rates);
   int required=(int)MathMax(MSWarmup(g_config)+2,MathMax(InpTouchBars+1,MathMax(InpHuntBars+1,InpPullbackHuntBars+1)));
   if(n<required || (long)rates[n-1].time!=g_context.time ||
      !SeriesInfoInteger(_Symbol,InpHuntTF,SERIES_SYNCHRONIZED)) return false;
   WHCReset(g_higher);
   if(ArrayResize(g_higher_bars,n-1)!=n-1) return false;
   for(int i=0;i<n-1;i++)
   {
      if(IsStopped() || (long)rates[i].time+g_big_seconds>g_context.time ||
         (long)rates[i].time+g_big_seconds>now ||
         (i>0 && rates[i].time<=rates[i-1].time)) return false;
      MSBar bar={(long)rates[i].time,rates[i].open,rates[i].high,rates[i].low,rates[i].close};
      g_higher_bars[i]=bar;
      WHCProcessClosed(g_higher,g_config,bar,i,InpSRCount,InpSRAnchor);
   }
   g_higher_open=g_context.time; g_higher_available=available;
   return true;
}

bool LoadContext(const long now)
{
   MqlRates high[]; ArraySetAsSeries(high,false);
   int n=CopyRates(_Symbol,InpHuntTF,0,InpHuntBars+1,high);
   g_context.valid=false;
   if(n!=InpHuntBars+1 || !SeriesInfoInteger(_Symbol,InpHuntTF,SERIES_SYNCHRONIZED)) return false;
   MqlRates current=high[n-1];
   if(now<(long)current.time || now>=(long)current.time+g_big_seconds) return false;
   g_context.time=(long)current.time; g_context.end_time=g_context.time+g_big_seconds;
   g_context.open=current.open; g_context.prior_low=high[0].low; g_context.prior_high=high[0].high;
   for(int j=0;j<n;j++)
   {
      MSBar bar={(long)high[j].time,high[j].open,high[j].high,high[j].low,high[j].close};
      if(!MSBarValid(bar)) return false;
      if(j<n-1)
      {
         if((long)high[j].time>=g_context.time) return false;
         g_context.prior_low=MathMin(g_context.prior_low,high[j].low);
         g_context.prior_high=MathMax(g_context.prior_high,high[j].high);
      }
   }
   if(InpScenario!=WS_LEGACY && !ReplayHigher(now)) return false;
   g_context.valid=true;
   return true;
}

bool RenderSR()
{
   ObjectsDeleteAll(0,g_prefix+"sr_");
   for(int j=0;InpShowSR && j<g_state.level_count;j++)
   {
      MSEvent e=g_state.levels[j]; double price=MSSRPrice(e,InpSRAnchor);
      string name=g_prefix+"sr_"+IntegerToString(j);
      if(!ObjectCreate(0,name,OBJ_TREND,0,(datetime)e.pivot_time,price,
                       (datetime)(e.pivot_time+g_small_seconds),price)) return false;
      ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,true); ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
      ObjectSetInteger(0,name,OBJPROP_COLOR,e.type==1 ? InpResistanceColor : InpSupportColor);
      ObjectSetInteger(0,name,OBJPROP_BACK,true); ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetString(0,name,OBJPROP_TOOLTIP,EnumToString(InpSignalTF)+" Histogram Swing "+(e.type==1 ? "H" : "L")+
                      " | "+DoubleToString(price,_Digits)+" | confirmed after "+TimeToString((datetime)e.confirm_time));
   }
   for(int j=0;InpShowContextSR && InpScenario!=WS_LEGACY && j<g_higher.level_count;j++)
   {
      MSEvent e=g_higher.levels[j]; double price=MSSRPrice(e,InpSRAnchor);
      string name=g_prefix+"sr_context_"+IntegerToString(j);
      if(!ObjectCreate(0,name,OBJ_TREND,0,(datetime)e.pivot_time,price,
                       (datetime)(e.pivot_time+g_big_seconds),price)) return false;
      ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,true); ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
      ObjectSetInteger(0,name,OBJPROP_COLOR,e.type==1 ? InpResistanceColor : InpSupportColor);
      ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DASH);
      ObjectSetInteger(0,name,OBJPROP_BACK,true); ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetString(0,name,OBJPROP_TOOLTIP,EnumToString(InpHuntTF)+" context Histogram Swing "+
                      (e.type==1 ? "H" : "L")+" | "+DoubleToString(price,_Digits)+
                      " | confirmed after "+TimeToString((datetime)e.confirm_time));
   }
   return true;
}

bool ReplayLower(const long now)
{
   long current=(long)iTime(_Symbol,InpSignalTF,0);
   if(current<=0 || now<current || now>=current+g_small_seconds ||
      !SeriesInfoInteger(_Symbol,InpSignalTF,SERIES_SYNCHRONIZED)) return false;
   if(!g_force_replay && current==g_lower_open && g_state.setup_time==g_context.time) return true;
   MqlRates lower[]; ArraySetAsSeries(lower,false);
   int requested=InpHistoryBars==0 ? iBars(_Symbol,InpSignalTF) : InpHistoryBars+1;
   if(requested<MSWarmup(g_config)+2) return false;
   int n=CopyRates(_Symbol,InpSignalTF,0,requested,lower);
   if(n<MSWarmup(g_config)+2 || !SeriesInfoInteger(_Symbol,InpSignalTF,SERIES_SYNCHRONIZED) ||
      (long)lower[n-1].time!=current) return false;
   // Preserve observed live facts while recalculating closed-candle swing/SR data.
   bool same_setup=g_state.setup_time==g_context.time;
   bool buy_reclaimed=same_setup && g_state.buy_reclaimed;
   bool sell_reclaimed=same_setup && g_state.sell_reclaimed;
   long buy_reclaim_time=same_setup ? g_state.buy_reclaim_time : 0;
   long sell_reclaim_time=same_setup ? g_state.sell_reclaim_time : 0;
   bool buy_sent=same_setup && g_state.buy_sent;
   bool sell_sent=same_setup && g_state.sell_sent;
   int buy_pattern=same_setup ? g_state.buy_pattern : 0;
   int sell_pattern=same_setup ? g_state.sell_pattern : 0;
   double buy_context_sr=same_setup ? g_state.buy_context_sr : 0;
   double sell_context_sr=same_setup ? g_state.sell_context_sr : 0;
   long buy_anchor_time=same_setup ? g_state.buy_anchor_time : 0;
   long sell_anchor_time=same_setup ? g_state.sell_anchor_time : 0;
   long buy_trend_pivot=same_setup ? g_state.buy_trend_pivot : 0;
   long sell_trend_pivot=same_setup ? g_state.sell_trend_pivot : 0;
   WSReset(g_state,g_context.time);
   // Restore reclaim BEFORE replay so previously closed candles cannot be
   // accepted retroactively when the current lower-TF candle advances.
   g_state.buy_reclaimed=buy_reclaimed; g_state.sell_reclaimed=sell_reclaimed;
   g_state.buy_reclaim_time=buy_reclaim_time; g_state.sell_reclaim_time=sell_reclaim_time;
   g_state.buy_pattern=buy_pattern; g_state.sell_pattern=sell_pattern;
   g_state.buy_context_sr=buy_context_sr; g_state.sell_context_sr=sell_context_sr;
   g_state.buy_anchor_time=buy_anchor_time; g_state.sell_anchor_time=sell_anchor_time;
   g_state.buy_trend_pivot=buy_trend_pivot; g_state.sell_trend_pivot=sell_trend_pivot;
   for(int i=0;i<n-1;i++)
   {
      if(IsStopped()) return false;
      MSBar bar={(long)lower[i].time,lower[i].open,lower[i].high,lower[i].low,lower[i].close};
      if(bar.time+g_small_seconds>now) return false;
      // Invalid OHLC resets the swing engine and SRs; fresh valid warmup is required.
      WSProcessClosed(g_state,g_config,bar,i,g_small_seconds,g_context,InpSRCount,InpSRAnchor,
                      InpRetestBars,InpConfirmBars,InpCloseBufferPoints*_Point);
   }
   g_state.buy_sent=buy_sent; g_state.sell_sent=sell_sent;
   if(!RenderSR()) return false;
   g_lower_open=current; g_force_replay=false;
   return true;
}

string ScenarioText(const int pattern)
{
   if(pattern==1) return "Breakout";
   if(pattern==2) return "Pullback";
   if(pattern==3) return "Breakout + Pullback";
   return "Legacy";
}

bool RenderSignals()
{
   ObjectsDeleteAll(0,g_prefix+"signal_");
   int total=ArraySize(g_signals),first=(int)MathMax(0,total-InpVisibleSignals);
   for(int i=first;i<total;i++)
   {
      WSSignal e=g_signals[i]; string name=g_prefix+"signal_"+IntegerToString(i);
      // Closed-candle events are known at the boundary, but the arrow belongs
      // to the candle that just closed, including the final retest in a window.
      long plotted=InpObservationMode==WH_LOWER_TF_CLOSE ? e.time-1 : e.time;
      ENUM_TIMEFRAMES chart_tf=(ENUM_TIMEFRAMES)_Period;
      int shift=iBarShift(_Symbol,chart_tf,(datetime)plotted,false);
      if(shift<0) continue;
      long opened=(long)iTime(_Symbol,chart_tf,shift);
      // The chart candle, not the entry price, owns the arrow. Do not attach a
      // session-gap event to an unrelated candle returned by nearest lookup.
      if(opened<=0 || plotted<opened || plotted>=opened+PeriodSeconds(chart_tf)) continue;
      double high=iHigh(_Symbol,chart_tf,shift),low=iLow(_Symbol,chart_tf,shift);
      if(!MathIsValidNumber(high) || !MathIsValidNumber(low) || low<=0 || high<low) continue;
      double marker=e.direction==1 ? low-InpArrowGapPoints*_Point : high+InpArrowGapPoints*_Point;
      if(!ObjectCreate(0,name,OBJ_ARROW,0,(datetime)opened,marker)) return false;
      ObjectSetInteger(0,name,OBJPROP_ARROWCODE,e.direction==1 ? 233 : 234);
      ObjectSetInteger(0,name,OBJPROP_ANCHOR,e.direction==1 ? ANCHOR_TOP : ANCHOR_BOTTOM);
      ObjectSetInteger(0,name,OBJPROP_COLOR,e.direction==1 ? InpBuyColor : InpSellColor);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,InpArrowWidth);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetString(0,name,OBJPROP_TOOLTIP,(e.direction==1 ? "BUY" : "SELL")+
                      " | "+ScenarioText(e.pattern)+
                      (InpObservationMode==WH_LOWER_TF_CLOSE ? " | confirmed close " : " | observed ")+
                      TimeToString((datetime)e.time,TIME_DATE|TIME_SECONDS)+
                      " | SR "+(e.sr_type==1 ? "H " : "L ")+DoubleToString(e.sr,_Digits)+
                      " | breakout bar "+TimeToString((datetime)e.break_time)+
                      " | hold close "+TimeToString((datetime)e.hold_time)+
                      " | retest bar "+IntegerToString(e.retest_bar)+
                      " | "+EnumToString(InpHuntTF)+" SR "+DoubleToString(e.context_sr,_Digits)+
                      " | FVG "+TimeToString((datetime)e.anchor_time)+
                      " | trend pivot "+TimeToString((datetime)e.trend_pivot));
   }
   g_arrows_dirty=false;
   return true;
}

void MapOutput()
{
   if(!g_outputs_dirty || g_chart_total<1 || ArraySize(BuyBuffer)!=g_chart_total) return;
   ClearOutput();
   for(int i=0;i<ArraySize(g_signals);i++)
   {
      WSSignal e=g_signals[i];
      long plotted=InpObservationMode==WH_LOWER_TF_CLOSE ? e.time-1 : e.time;
      int shift=iBarShift(_Symbol,(ENUM_TIMEFRAMES)_Period,(datetime)plotted,false);
      if(shift<0 || shift>=g_chart_total) continue;
      datetime opened=iTime(_Symbol,(ENUM_TIMEFRAMES)_Period,shift);
      // Do not map a timestamp in a session gap to the preceding chart candle.
      if(plotted<(long)opened || plotted>=(long)opened+PeriodSeconds((ENUM_TIMEFRAMES)_Period)) continue;
      int bar=g_chart_total-1-shift;
      if(e.direction==1) BuyBuffer[bar]=e.price; else SellBuffer[bar]=e.price;
      EventTimeBuffer[bar]=(double)e.time; DirectionBuffer[bar]=e.direction;
      SRPriceBuffer[bar]=e.sr; SRTypeBuffer[bar]=e.sr_type;
      BreakTimeBuffer[bar]=(double)e.break_time; HuntTimeBuffer[bar]=(double)e.setup_time;
      PatternBuffer[bar]=(double)e.pattern;
      ContextSRBuffer[bar]=e.pattern>0 ? e.context_sr : EMPTY_VALUE;
      FVGTimeBuffer[bar]=e.anchor_time>0 ? (double)e.anchor_time : EMPTY_VALUE;
      TrendPivotBuffer[bar]=e.trend_pivot>0 ? (double)e.trend_pivot : EMPTY_VALUE;
   }
   g_outputs_dirty=false;
}

void UpdateLive()
{
   if(g_prefix=="" || g_chart_total<1) return;
   MqlTick tick;
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) || !SymbolInfoTick(_Symbol,tick) || tick.time<=0)
   { Status("Disconnected / waiting for quote"); return; }
   long now=(long)tick.time;
   bool context_ready=LoadContext(now);
   if(!context_ready || !ReplayLower(now))
   { Status("History loading / waiting for synchronized timeframes"); return; }
   MqlRates live[]; ArraySetAsSeries(live,false);
   if(CopyRates(_Symbol,InpHuntTF,0,1,live)!=1 || (long)live[0].time!=g_context.time) return;
   double price=SymbolInfoInteger(_Symbol,SYMBOL_CHART_MODE)==SYMBOL_CHART_MODE_LAST ? tick.last : tick.bid;
   if(price<=0 || price<live[0].low || price>live[0].high) return;
   WSObservePatterns(g_state,g_context,g_higher,g_higher_bars,ArraySize(g_higher_bars),now,
                     live[0].high,live[0].low,price,InpScenario,InpHuntBars,InpPullbackHuntBars,
                     InpTouchBars,InpSRAnchor,InpFVGSearchBars,InpMinFVGGapPoints,_Point,InpRequireFVGMiddleDirection,
                     InpMinHuntPoints*_Point,InpFVGMaxLeadWickPercent,InpEnableBuy,InpEnableSell);
   bool changed=false;
   for(int direction=1;direction>=-1;direction-=2)
   {
      if(direction==1 ? !InpEnableBuy : !InpEnableSell) continue;
      // Reserve before taking the event, so an allocation failure cannot consume it.
      int count=ArraySize(g_signals);
      if(ArrayResize(g_signals,count+1)!=count+1) { Status("Signal allocation failed; retrying"); return; }
      WSSignal event;
      if(!WSTakeSignal(g_state,g_context,now,price,direction,event,InpRetestTolerancePoints*_Point))
      { ArrayResize(g_signals,count); continue; }
      g_signals[count]=event; changed=true;
      if(InpPopupAlert && g_observed)
         Alert(_Symbol," WickHuntSRFlow ",direction==1 ? "BUY" : "SELL",
               " | ",ScenarioText(event.pattern),
               " | ",EnumToString(InpHuntTF)," hunt/open + ",EnumToString(InpSignalTF),
               " SR ",DoubleToString(event.sr,_Digits));
   }
   g_observed=true;
   if(changed) { g_outputs_dirty=true; RenderSignals(); }
   MapOutput();
   Status("Live | "+EnumToString(InpHuntTF)+" / "+EnumToString(InpSignalTF)+
          " | "+ScenarioText((int)InpScenario)+
          " | Buy reclaim "+(g_state.buy_reclaimed ? "yes" : "no")+
          " | Sell reclaim "+(g_state.sell_reclaimed ? "yes" : "no"));
   ChartRedraw(0);
}

bool CollectClosedSignal(const MSBar &bar,const int direction)
{
   if(!g_context.valid || g_state.setup_time!=g_context.time ||
      (direction==1 ? !g_state.buy_reclaimed || g_state.buy_sent
                    : !g_state.sell_reclaimed || g_state.sell_sent)) return true;
   WSBreak candidate=direction==1 ? g_state.buy_break : g_state.sell_break;
   if(!candidate.valid || (InpRetestBars>0 && candidate.hold_close_time==0)) return true;
   int count=ArraySize(g_signals);
   if(ArrayResize(g_signals,count+1)!=count+1) return false;
   WSSignal event; bool found=false;
   if(InpRetestBars>0)
      found=WHRTakeRetest(g_state,g_context,bar,g_small_seconds,direction,
                         InpClosedRetest,InpRetestTolerancePoints*_Point,event);
   else
      found=WSTakeSignal(g_state,g_context,bar.time+g_small_seconds,bar.close,direction,event);
   if(found) g_signals[count]=event;
   else ArrayResize(g_signals,count);
   return true;
}

bool ReplayClosedHistory()
{
   long lower_open=(long)iTime(_Symbol,InpSignalTF,0);
   long higher_open=(long)iTime(_Symbol,InpHuntTF,0);
   int lower_available=iBars(_Symbol,InpSignalTF),higher_available=iBars(_Symbol,InpHuntTF);
   if(lower_open<=0 || higher_open<=0 ||
      !SeriesInfoInteger(_Symbol,InpSignalTF,SERIES_SYNCHRONIZED) ||
      !SeriesInfoInteger(_Symbol,InpHuntTF,SERIES_SYNCHRONIZED)) return false;
   if(g_close_ready && !g_force_replay && lower_open==g_close_lower_open &&
      higher_open==g_close_higher_open && lower_available==g_close_lower_available &&
      higher_available==g_close_higher_available) return true;
   MqlRates lower[],higher[];
   ArraySetAsSeries(lower,false); ArraySetAsSeries(higher,false);
   int lower_requested=InpHistoryBars==0 ? lower_available : InpHistoryBars+1;
   int higher_requested=InpContextHistoryBars==0 ? higher_available : InpContextHistoryBars+1;
   int n=CopyRates(_Symbol,InpSignalTF,0,lower_requested,lower);
   int h=CopyRates(_Symbol,InpHuntTF,0,higher_requested,higher);
   int required=(int)MathMax(MSWarmup(g_config)+1,
                            MathMax(InpTouchBars,MathMax(InpHuntBars,InpPullbackHuntBars)));
   if(n<MSWarmup(g_config)+2 || h<required+1 ||
      (long)lower[n-1].time!=lower_open || (long)higher[h-1].time!=higher_open ||
      !SeriesInfoInteger(_Symbol,InpSignalTF,SERIES_SYNCHRONIZED) ||
      !SeriesInfoInteger(_Symbol,InpHuntTF,SERIES_SYNCHRONIZED)) return false;
   if(ArrayResize(g_higher_bars,h)!=h) return false;
   for(int j=0;j<h;j++)
   {
      if(IsStopped() || (j>0 && higher[j].time<=higher[j-1].time)) return false;
      MSBar b={(long)higher[j].time,higher[j].open,higher[j].high,higher[j].low,higher[j].close};
      g_higher_bars[j]=b;
   }
   long prior_processed=g_close_last_processed;
   bool previously_ready=g_close_ready;
   g_force_replay=true;
   WSReset(g_state,0); WHCReset(g_higher);
   ArrayResize(g_signals,0);
   g_context.valid=false; g_context.time=0;
   int closed_higher=0,active_higher=-2;
   bool complete_window=false;
   double running_high=0,running_low=0;
   long previous_end=0;
   for(int i=0;i<n-1;i++)
   {
      if(IsStopped() || (i>0 && lower[i].time<=lower[i-1].time)) return false;
      MSBar bar={(long)lower[i].time,lower[i].open,lower[i].high,lower[i].low,lower[i].close};
      if(bar.time+g_small_seconds>lower_open) return false;
      // Only higher candles already closed BEFORE this lower candle opened
      // may contribute structural swings, FVGs, touches and prior wick edges.
      while(closed_higher<h && g_higher_bars[closed_higher].time+g_big_seconds<=bar.time)
      {
         WHCProcessClosed(g_higher,g_config,g_higher_bars[closed_higher],closed_higher,InpSRCount,InpSRAnchor);
         closed_higher++;
      }
      int main=-1;
      if(closed_higher<h && bar.time>=g_higher_bars[closed_higher].time &&
         bar.time<g_higher_bars[closed_higher].time+g_big_seconds) main=closed_higher;
      if(main!=active_higher)
      {
         active_higher=main;
         g_context.time=main>=0 ? g_higher_bars[main].time : 0;
         g_context.end_time=g_context.time+g_big_seconds;
         g_context.open=main>=0 ? g_higher_bars[main].open : 0;
         running_high=g_context.open; running_low=g_context.open;
         complete_window=main>=0 && bar.time==g_context.time;
      }
      else if(bar.time!=previous_end) complete_window=false;
      if(!MSBarValid(bar)) complete_window=false;
      if(MSBarValid(bar) && main>=0)
      {
         // Never read the final high/low of the currently replayed main bar.
         running_high=MathMax(running_high,bar.high);
         running_low=MathMin(running_low,bar.low);
      }
      g_context.valid=complete_window && main>=0 && MathIsValidNumber(g_context.open) &&
                      g_context.open>0 && closed_higher>=required &&
                      bar.time+g_small_seconds<=g_context.end_time;
      if(g_context.valid)
         g_context.valid=WHCPriorExtremes(g_higher_bars,closed_higher,InpHuntBars,
                                         g_context.prior_low,g_context.prior_high);
      // Retest uses only a whole waiting candle AFTER all holds had closed.
      // Consume it before advancing this candle, including the final allowed
      // candle. Break and hold candles can never reuse their own High/Low.
      if(InpRetestBars>0)
      {
         if(InpEnableBuy && !CollectClosedSignal(bar,1)) return false;
         if(InpEnableSell && !CollectClosedSignal(bar,-1)) return false;
      }
      WSProcessClosed(g_state,g_config,bar,i,g_small_seconds,g_context,InpSRCount,InpSRAnchor,
                      InpRetestBars,InpConfirmBars,InpCloseBufferPoints*_Point);
      if(InpRetestBars==0)
      {
         if(InpEnableBuy && !CollectClosedSignal(bar,1)) return false;
         if(InpEnableSell && !CollectClosedSignal(bar,-1)) return false;
      }
      // Observe reclaim LAST: this close cannot also become its own breakout.
      // Reclaimed facts/scenario are frozen by the same unchanged live core.
      if(MSBarValid(bar))
         WSObservePatterns(g_state,g_context,g_higher,g_higher_bars,closed_higher,
                           bar.time+g_small_seconds,running_high,running_low,bar.close,
                           InpScenario,InpHuntBars,InpPullbackHuntBars,InpTouchBars,InpSRAnchor,
                           InpFVGSearchBars,InpMinFVGGapPoints,_Point,InpRequireFVGMiddleDirection,
                           InpMinHuntPoints*_Point,InpFVGMaxLeadWickPercent,InpEnableBuy,InpEnableSell);
      previous_end=bar.time+g_small_seconds;
   }
   // Bring the displayed higher SRs up to the current lower candle's open.
   while(closed_higher<h && g_higher_bars[closed_higher].time+g_big_seconds<=lower_open)
   {
      WHCProcessClosed(g_higher,g_config,g_higher_bars[closed_higher],closed_higher,InpSRCount,InpSRAnchor);
      closed_higher++;
   }
   if(!RenderSR() || !RenderSignals()) return false;
   g_outputs_dirty=true;
   if(InpPopupAlert && previously_ready)
      for(int i=0;i<ArraySize(g_signals);i++)
      {
         WSSignal e=g_signals[i];
         // No attach alerts, old loaded-history alerts, or replay duplicates.
         if(e.time>prior_processed && e.time==previous_end)
            Alert(_Symbol," WickHuntSRFlow ",e.direction==1 ? "BUY" : "SELL",
                  " | confirmed ",EnumToString(InpSignalTF)," close | ",ScenarioText(e.pattern));
      }
   g_close_lower_open=lower_open; g_close_higher_open=higher_open;
   g_close_lower_available=lower_available; g_close_higher_available=higher_available;
   g_close_history_start=(long)lower[0].time; g_close_last_processed=previous_end;
   g_close_ready=true; g_force_replay=false;
   return true;
}

void UpdateIndicator()
{
   if(InpObservationMode==WH_TICK_LIVE)
   {
      UpdateLive();
      if(g_arrows_dirty && RenderSignals()) ChartRedraw(0);
      return;
   }
   if(g_prefix=="" || g_chart_total<1) return;
   if(!ReplayClosedHistory())
   { Status("History loading / waiting for synchronized timeframes"); return; }
   if(g_arrows_dirty && !RenderSignals())
   { Status("Arrow drawing failed; retrying"); return; }
   MapOutput();
   Status("Close/history | "+EnumToString(InpHuntTF)+" / "+EnumToString(InpSignalTF)+
          " | signals "+IntegerToString(ArraySize(g_signals))+
          " | loaded from "+TimeToString((datetime)g_close_history_start,TIME_DATE|TIME_MINUTES));
   ChartRedraw(0);
}

void OnTimer() { UpdateIndicator(); }

int OnCalculate(const int rates_total,const int prev_calculated,
                const datetime &time[],const double &open[],const double &high[],const double &low[],
                const double &close[],const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(rates_total<1) return 0;
   ArraySetAsSeries(time,false);
   ArraySetAsSeries(high,false); ArraySetAsSeries(low,false);
   if(prev_calculated==0) g_force_replay=true;
   if(prev_calculated==0 || g_chart_total!=rates_total ||
      g_chart_first!=(long)time[0] || g_chart_last!=(long)time[rates_total-1])
   { g_outputs_dirty=true; g_arrows_dirty=true; }
   // A live chart candle may extend after the signal. Keep the arrow outside
   // its latest wick without changing the event price/time or signal logic.
   if(g_chart_high!=high[rates_total-1] || g_chart_low!=low[rates_total-1]) g_arrows_dirty=true;
   g_chart_high=high[rates_total-1]; g_chart_low=low[rates_total-1];
   g_chart_first=(long)time[0]; g_chart_last=(long)time[rates_total-1];
   g_chart_total=rates_total;
   UpdateIndicator();
   return rates_total;
}
