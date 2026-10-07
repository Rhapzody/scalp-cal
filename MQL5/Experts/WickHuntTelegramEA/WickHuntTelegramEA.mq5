#property copyright "MT5 Trading Tools"
#property version "1.00"
#property strict
#property description "WickHuntSRFlow v1.04 live rules, chart arrows and durable Telegram outbox. Never trades."
#include "TelegramQueue.mqh"

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

input group "Telegram outbox and chart"
input string InpQueueChannel="default"; // Same channel on all detectors and the sender
input string InpInstanceTag=""; // Optional label; use different tags for intentional duplicates
input bool InpDrawSignals=true;
input bool InpShowStatus=true;

MSConfig g_config;
WSState g_state;
WSContext g_context;
WSSignal g_signals[],g_unpublished[];
WHCState g_higher;
MSBar g_higher_bars[];
long g_higher_open=0;
int g_higher_available=0;
int g_small_seconds=0,g_big_seconds=0;
long g_lower_open=0;
bool g_force_replay=true,g_outputs_dirty=true,g_observed=false;
string g_prefix="",g_folder="",g_instance="",g_account="",g_last_id="";
int g_lock=INVALID_HANDLE;
bool g_restore=true,g_storage_error=false,g_checkpoint_dirty=false;
bool g_draw_dirty=false;
long g_checkpoint_setup=0;
ulong g_last_disk_try=0;

void Status(const string text)
{
   if(InpShowStatus && g_prefix!="") ObjectSetString(0,g_prefix+"owner",OBJPROP_TEXT,"WickHuntTelegramEA | "+text);
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
   if(!InpDrawSignals) { ObjectsDeleteAll(0,g_prefix+"signal_"); return true; }
   ObjectsDeleteAll(0,g_prefix+"signal_");
   int total=ArraySize(g_signals),first=(int)MathMax(0,total-InpVisibleSignals);
   for(int i=first;i<total;i++)
   {
      WSSignal e=g_signals[i]; string name=g_prefix+"signal_"+IntegerToString(i);
      double marker=e.price-e.direction*InpArrowGapPoints*_Point;
      if(!ObjectCreate(0,name,OBJ_ARROW,0,(datetime)e.time,marker)) return false;
      ObjectSetInteger(0,name,OBJPROP_ARROWCODE,e.direction==1 ? 233 : 234);
      ObjectSetInteger(0,name,OBJPROP_COLOR,e.direction==1 ? InpBuyColor : InpSellColor);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,InpArrowWidth);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetString(0,name,OBJPROP_TOOLTIP,(e.direction==1 ? "BUY" : "SELL")+
                      " | "+ScenarioText(e.pattern)+" | observed "+TimeToString((datetime)e.time,TIME_DATE|TIME_SECONDS)+
                      " | SR "+(e.sr_type==1 ? "H " : "L ")+DoubleToString(e.sr,_Digits)+
                      " | breakout bar "+TimeToString((datetime)e.break_time)+
                      " | hold close "+TimeToString((datetime)e.hold_time)+
                      " | retest bar "+IntegerToString(e.retest_bar)+
                      " | "+EnumToString(InpHuntTF)+" SR "+DoubleToString(e.context_sr,_Digits)+
                      " | FVG "+TimeToString((datetime)e.anchor_time)+
                      " | trend pivot "+TimeToString((datetime)e.trend_pivot));
   }
   return true;
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
      !MathIsValidNumber(InpFVGMaxLeadWickPercent) || InpFVGMaxLeadWickPercent<0 || InpFVGMaxLeadWickPercent>100)
   { Print("WickHuntSRFlow: invalid Inputs. Use fixed lower/higher timeframes and a chart up to D1."); return INIT_PARAMETERS_INCORRECT; }
   if(!WHTSafeName(InpQueueChannel) || (InpInstanceTag!="" && !WHTSafeName(InpInstanceTag)))
   { Print("WickHuntTelegramEA: channel/tag must use letters, digits, underscore or hyphen (1..48)."); return INIT_PARAMETERS_INCORRECT; }
   g_account=WHTAccountKey(); g_folder=WHTFolder(InpQueueChannel);
   string identity="WickHuntSRFlow-1.04|"+_Symbol+"|"+InpInstanceTag;
   identity+="|"+IntegerToString((int)InpHuntTF)+"|"+IntegerToString((int)InpSignalTF);
   identity+="|"+IntegerToString(InpHuntBars)+"|"+IntegerToString(InpFastEMA)+"|"+IntegerToString(InpSlowEMA);
   identity+="|"+IntegerToString(InpSignalEMA)+"|"+IntegerToString(InpWarmupBars)+"|"+IntegerToString(InpHistoryBars);
   identity+="|"+IntegerToString(InpSRCount)+"|"+IntegerToString((int)InpSRAnchor)+"|"+IntegerToString((int)InpScenario);
   identity+="|"+IntegerToString(InpTouchBars)+"|"+IntegerToString(InpPullbackHuntBars)+"|"+IntegerToString(InpContextHistoryBars);
   identity+="|"+IntegerToString(InpFVGSearchBars)+"|"+DoubleToString(InpMinFVGGapPoints,16)+"|"+(string)InpRequireFVGMiddleDirection;
   identity+="|"+IntegerToString(InpRetestBars)+"|"+IntegerToString(InpConfirmBars);
   identity+="|"+DoubleToString(InpCloseBufferPoints,16)+"|"+DoubleToString(InpRetestTolerancePoints,16);
   identity+="|"+DoubleToString(InpMinHuntPoints,16)+"|"+DoubleToString(InpFVGMaxLeadWickPercent,16);
   identity+="|"+(string)InpEnableBuy+"|"+(string)InpEnableSell;
   g_instance=WHTHash(identity);
   if(g_folder=="" || g_instance=="") return INIT_FAILED;
   g_lock=FileOpen(g_folder+"\\"+g_instance+".lock",FILE_READ|FILE_WRITE|FILE_BIN);
   if(g_lock==INVALID_HANDLE)
   { Print("WickHuntTelegramEA: identical detector already running, or queue folder is not writable. Use a distinct InstanceTag for intentional duplicates."); return INIT_FAILED; }
   g_prefix="WHT_"+(string)ChartID()+"_"+g_instance+"_";
   if(InpShowStatus)
   {
      if(!ObjectCreate(0,g_prefix+"owner",OBJ_LABEL,0,0,0)) return INIT_FAILED;
      ObjectSetInteger(0,g_prefix+"owner",OBJPROP_CORNER,CORNER_LEFT_LOWER);
      ObjectSetInteger(0,g_prefix+"owner",OBJPROP_ANCHOR,ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0,g_prefix+"owner",OBJPROP_XDISTANCE,12);
      ObjectSetInteger(0,g_prefix+"owner",OBJPROP_YDISTANCE,16);
      ObjectSetInteger(0,g_prefix+"owner",OBJPROP_COLOR,clrSilver);
      ObjectSetInteger(0,g_prefix+"owner",OBJPROP_FONTSIZE,9);
      ObjectSetInteger(0,g_prefix+"owner",OBJPROP_HIDDEN,true);
   }
   WSReset(g_state,0); WHCReset(g_higher); g_context.valid=false;
   RestoreArrows();
   if(!RenderSignals()) return INIT_FAILED;
   if(!EventSetTimer(1)) return INIT_FAILED;
   Status("Loading history | sender channel "+InpQueueChannel);
   return INIT_SUCCEEDED;
}

bool SaveCheckpoint()
{
   string target=g_folder+"\\"+g_instance+".state", temp=target+".tmp";
   int f=FileOpen(temp,FILE_WRITE|FILE_BIN);
   if(f==INVALID_HANDLE) return false;
   ResetLastError();
   FileWriteInteger(f,0x57485331); FileWriteInteger(f,1);
   FileWriteLong(f,g_state.setup_time);
   FileWriteLong(f,g_state.buy_reclaim_time); FileWriteLong(f,g_state.sell_reclaim_time);
   FileWriteInteger(f,g_state.buy_pattern); FileWriteInteger(f,g_state.sell_pattern);
   FileWriteDouble(f,g_state.buy_context_sr); FileWriteDouble(f,g_state.sell_context_sr);
   FileWriteLong(f,g_state.buy_anchor_time); FileWriteLong(f,g_state.sell_anchor_time);
   FileWriteLong(f,g_state.buy_trend_pivot); FileWriteLong(f,g_state.sell_trend_pivot);
   bool ok=FileTell(f)==88 && GetLastError()==0;
   FileFlush(f); ok=ok && GetLastError()==0;
   FileClose(f);
   return ok && FileMove(temp,0,target,FILE_REWRITE);
}
void RestoreCheckpoint(const long now)
{
   g_restore=false;
   int f=FileOpen(g_folder+"\\"+g_instance+".state",FILE_READ|FILE_BIN);
   if(f==INVALID_HANDLE) return;
   ResetLastError();
   int magic=FileReadInteger(f),schema=FileReadInteger(f);
   long setup=FileReadLong(f),buy=FileReadLong(f),sell=FileReadLong(f);
   int bp=FileReadInteger(f),sp=FileReadInteger(f);
   double bs=FileReadDouble(f),ss=FileReadDouble(f);
   long ba=FileReadLong(f),sa=FileReadLong(f),bt=FileReadLong(f),st=FileReadLong(f);
   bool ok=FileSize(f)==88 && magic==0x57485331 && schema==1 && GetLastError()==0 &&
      setup==g_context.time && (buy==0 || (buy>=setup && buy<=now && buy<g_context.end_time)) &&
      (sell==0 || (sell>=setup && sell<=now && sell<g_context.end_time)) &&
      bp>=0 && bp<=3 && sp>=0 && sp<=3 && MathIsValidNumber(bs) && MathIsValidNumber(ss);
   FileClose(f);
   if(!ok) return;
   WSBeginSetup(g_state,setup);
   g_state.buy_reclaimed=buy>0; g_state.sell_reclaimed=sell>0;
   g_state.buy_reclaim_time=buy; g_state.sell_reclaim_time=sell;
   g_state.buy_pattern=bp; g_state.sell_pattern=sp;
   g_state.buy_context_sr=bs; g_state.sell_context_sr=ss;
   g_state.buy_anchor_time=ba; g_state.sell_anchor_time=sa;
   g_state.buy_trend_pivot=bt; g_state.sell_trend_pivot=st;
   g_state.buy_sent=WHTExists(g_folder,WHTEventID(g_instance,setup,1));
   g_state.sell_sent=WHTExists(g_folder,WHTEventID(g_instance,setup,-1));
}
// Bound chart memory independently of the durable outbox / acknowledgement files.
void RememberSignal(const WSSignal &e)
{
   if(InpVisibleSignals==0) return;
   int n=ArraySize(g_signals);
   for(int i=0;i<n;i++)
      if(g_signals[i].setup_time==e.setup_time && g_signals[i].direction==e.direction) return;
   if(n>=InpVisibleSignals)
   {
      if(e.time<g_signals[0].time) return;
      for(int i=1;i<n;i++) g_signals[i-1]=g_signals[i];
      n--;
   }
   if(ArrayResize(g_signals,n+1)!=n+1) return;
   int at=n;
   while(at>0 && g_signals[at-1].time>e.time) { g_signals[at]=g_signals[at-1]; at--; }
   g_signals[at]=e;
}
void RestoreArrows()
{
   if(!InpDrawSignals || InpVisibleSignals==0) return;
   string extensions[3]={".pending",".sent",".failed"};
   for(int i=0;i<3;i++)
   {
      string name;
      long search=FileFindFirst(g_folder+"\\"+g_instance+"_*"+extensions[i],name);
      if(search==INVALID_HANDLE) continue;
      do
      {
         WSSignal e; string message; long queued;
         if(WHTRead(g_folder+"\\"+name,e,message,queued)) RememberSignal(e);
      } while(FileFindNext(search,name));
      FileFindClose(search);
   }
}
string SignalMessage(const WSSignal &e,const string id)
{
   string text="WickHunt | "+_Symbol+" | "+(e.direction==1 ? "BUY" : "SELL")+" | "+ScenarioText(e.pattern);
   text+="\nMain "+EnumToString(InpHuntTF)+" / Lower "+EnumToString(InpSignalTF);
   if(InpInstanceTag!="") text+=" | "+InpInstanceTag;
   text+="\nBroker time: "+TimeToString((datetime)e.time,TIME_DATE|TIME_SECONDS);
   text+="\nSignal price: "+DoubleToString(e.price,_Digits)+" | Lower SR: "+DoubleToString(e.sr,_Digits);
   if(e.pattern!=0) text+="\nMain SR: "+DoubleToString(e.context_sr,_Digits);
   text+="\nBreak bar: "+TimeToString((datetime)e.break_time,TIME_DATE|TIME_MINUTES);
   if(e.hold_time>0)
      text+="\nConfirm close: "+TimeToString((datetime)e.hold_time,TIME_MINUTES)+" | Retest bar "+IntegerToString(e.retest_bar)+"/"+IntegerToString(InpRetestBars);
   else text+="\nDirect break-close signal";
   text+="\nEvent: "+id+"\nAlert for chart review; no order placed.";
   return text;
}
void FlushOutbox()
{
   if(ArraySize(g_unpublished)==0 && !g_checkpoint_dirty) return;
   ulong now=GetTickCount64();
   if(g_storage_error && now-g_last_disk_try<5000) return;
   g_last_disk_try=now;
   bool error=false;
   for(int i=ArraySize(g_unpublished)-1;i>=0;i--)
   {
      WSSignal e=g_unpublished[i];
      string id=WHTEventID(g_instance,e.setup_time,e.direction);
      if(!WHTPublish(g_folder,id,e,SignalMessage(e,id))) { error=true; continue; }
      g_last_id=id;
      int n=ArraySize(g_unpublished);
      for(int j=i+1;j<n;j++) g_unpublished[j-1]=g_unpublished[j];
      ArrayResize(g_unpublished,n-1);
   }
   if(g_checkpoint_dirty)
   {
      if(SaveCheckpoint()) g_checkpoint_dirty=false;
      else error=true;
   }
   if(error && !g_storage_error) Print("WickHuntTelegramEA: cannot persist alert/checkpoint; check disk and permissions. Pending alerts remain in memory.");
   g_storage_error=error;
}
void UpdateLive()
{
   if(g_account!=WHTAccountKey()) { Status("Account changed: remove and reattach EA"); return; }
   FlushOutbox();
   MqlTick tick;
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) || !SymbolInfoTick(_Symbol,tick) || tick.time<=0)
   { Status("Disconnected / waiting for quote"); return; }
   long now=(long)tick.time;
   if(!LoadContext(now)) { Status("History loading / waiting for synchronized timeframes"); return; }
   if(g_restore) RestoreCheckpoint(now);
   if(!ReplayLower(now)) { Status("History loading / waiting for synchronized timeframes"); return; }
   MqlRates live[]; ArraySetAsSeries(live,false);
   if(CopyRates(_Symbol,InpHuntTF,0,1,live)!=1 || (long)live[0].time!=g_context.time) return;
   double price=SymbolInfoInteger(_Symbol,SYMBOL_CHART_MODE)==SYMBOL_CHART_MODE_LAST ? tick.last : tick.bid;
   if(price<=0 || price<live[0].low || price>live[0].high) return;
   long buy_before=g_state.buy_reclaim_time,sell_before=g_state.sell_reclaim_time;
   WSObservePatterns(g_state,g_context,g_higher,g_higher_bars,ArraySize(g_higher_bars),now,
                     live[0].high,live[0].low,price,InpScenario,InpHuntBars,InpPullbackHuntBars,
                     InpTouchBars,InpSRAnchor,InpFVGSearchBars,InpMinFVGGapPoints,_Point,InpRequireFVGMiddleDirection,
                     InpMinHuntPoints*_Point,InpFVGMaxLeadWickPercent,InpEnableBuy,InpEnableSell);
   if(g_checkpoint_setup!=g_state.setup_time || buy_before!=g_state.buy_reclaim_time || sell_before!=g_state.sell_reclaim_time)
   { g_checkpoint_setup=g_state.setup_time; g_checkpoint_dirty=true; }
   bool changed=false;
   for(int direction=1;direction>=-1;direction-=2)
   {
      if(direction==1 ? !InpEnableBuy : !InpEnableSell) continue;
      string id=WHTEventID(g_instance,g_context.time,direction);
      if(WHTExists(g_folder,id))
      { if(direction==1) g_state.buy_sent=true; else g_state.sell_sent=true; continue; }
      int count=ArraySize(g_unpublished);
      if(ArrayResize(g_unpublished,count+1)!=count+1)
      { Status("Outbox allocation failed; retrying"); return; }
      WSSignal event;
      if(!WSTakeSignal(g_state,g_context,now,price,direction,event,InpRetestTolerancePoints*_Point))
      { ArrayResize(g_unpublished,count); continue; }
      g_unpublished[count]=event;
      RememberSignal(event); changed=true;
      if(InpPopupAlert && g_observed)
         Alert(_Symbol," WickHuntTelegramEA ",direction==1 ? "BUY" : "SELL"," | ",ScenarioText(event.pattern));
   }
   g_observed=true;
   FlushOutbox();
   if(changed) g_draw_dirty=true;
   if(g_draw_dirty && RenderSignals()) g_draw_dirty=false;
   string delivery=g_last_id=="" ? "no new alert" :
      (FileIsExist(g_folder+"\\"+g_last_id+".sent") ? "last alert sent" :
       (FileIsExist(g_folder+"\\"+g_last_id+".failed") ? "last alert FAILED: check sender" : "alert queued / waiting for sender"));
   Status(g_storage_error ? "DISK ERROR: alerts not yet durable" :
          (g_draw_dirty ? "Chart drawing failed; retrying" :
          "Live | "+EnumToString(InpHuntTF)+" / "+EnumToString(InpSignalTF)+" | "+ScenarioText((int)InpScenario)+" | "+delivery));
}
void OnTick() { UpdateLive(); }
void OnTimer() { UpdateLive(); }
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_account==WHTAccountKey()) FlushOutbox();
   if(ArraySize(g_unpublished)>0 || g_checkpoint_dirty)
      Print("WickHuntTelegramEA: unsaved alert/checkpoint at shutdown; disk error requires attention.");
   if(g_lock!=INVALID_HANDLE) FileClose(g_lock);
   if(g_prefix!="") ObjectsDeleteAll(0,g_prefix);
   ChartRedraw(0);
}
